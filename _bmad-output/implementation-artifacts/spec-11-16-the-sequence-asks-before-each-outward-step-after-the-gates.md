---
title: 'Story 11.16: The sequence asks before each outward step after the gates'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-5-one-scripted-sequence-cuts-a-release.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-14-the-release-sequence-runs-every-gate-on-the-pushed-candidate.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-15-the-hands-on-gate-stops-the-sequence-and-its-resume-command.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Stories 11.14 and 11.15, `release/release.sh` ends once every gate has passed, with `no step after the gates has run (not a release)`. Nothing opens the release pull request, merges it into `main` only on green required checks, tags the release, merges `main` back into the integration branch, or calls the online demo's update. Nothing reads `main`'s branch protection either, so DW-27's fork gap stays open for the sequence's own merge.

**Approach:** Add five steps after `hands-on` in 11.5's `STEPS`: `pr merge tag mergeback demo`. Each one prints 11.5's `ASK` before it acts, and goes through the same stop routine, record and hands-on clock.
- `merge` reads `main`'s protection and compares it with the job names of `ci.yml` and `lane-a.yml`, with the `iris` matrix expanded. It also checks every job of both workflows' runs on the pull request's head.
- `demo` calls Story 11.18's update hook through a call contract defined here. Until that hook exists, the step says so and records that the online demo was not updated.

This story takes epics.md Story 11.16's criterion, verbatim there, and the story-closable part of DW-27.

## Boundaries & Constraints

**Always:**
- **11.5's, 11.14's and 11.15's conventions still hold:**
  - Bash 3.2 and ASCII; mode 100755; `umask 077`; the main guard;
  - output lines `PASS|FAIL|WAIT <step> <detail>`, then `RECORD` and `RESULT`;
  - the stop routine (record, commit with an explicit pathspec, ASK `record`);
  - no value printed;
  - exit codes 0 (a step done), 1 (failed), 2 (refused), 4 (stopped for the author's word) and 5 (`WAIT`).
- **The author's word (11.5's ASK; the epics' 11.18 criterion: "a declined step is skipped and the sequence goes on").** Each of the five steps prints `ASK <step> <question> [yes/no]` and reads one line from stdin:
  - `yes` runs the step;
  - any other line declines it: `SKIP <step> declined by the author`, row `declined`, nothing goes out, exit 0, and the next `next` runs the next step;
  - end of input prints `STOPPED <step> waiting for the author's word`, exits 4 (11.5's stop), and the step is asked again later;
  - no option, variable or configuration key answers in advance. `--yes`, `--merge`, `--admin` and any unknown option exit 2.
- **Each step asks even when an earlier one was declined** (the epics' 11.18 criterion has the author decline all four in turn). After `yes`, a step whose prerequisite did not happen fails (`FAIL`, exit 1) and goes out nowhere. The next `next` asks again. The prerequisites are:
  - `merge` needs an open pull request;
  - `tag` needs the merge;
  - `mergeback` needs the merge and the tag;
  - `demo` in `Mode: release` needs the tag.
- **Work that is already done is adopted, not asked again.** Each step first reads the remote. In each of these cases it writes its row and asks nothing, because nothing new goes out:
  - an open pull request from the candidate branch into `main` whose head is the cut SHA;
  - that pull request already merged;
  - `v<v>` already on the remote at the cut SHA;
  - `<remote>/main` already an ancestor of `<remote>/<integration>`.
  - A `v<v>` tag at any other commit fails the `tag` step.
- **The merge rule (DW-27, the orchestrator's 2026-11-01 ruling).**
  - When no pull request is open (`pr` was declined), the step reads nothing on GitHub. It asks the no-PR ASK, and a `yes` fails with the prerequisite line.
  - When one is open, everything below is checked before the merge `ASK`, and any failure gives `FAIL merge <what>` with no `ASK` and no merge call:
  - **The pull request:** it is open, its base is `main`, its head ref is `release/<v>-rc<n>`, its `headRefOid` is the cut SHA and `isCrossRepository` is false.
  - **Branch protection:** read with `gh api repos/<repo>/branches/main/protection`.
    - Its `required_status_checks.checks[].context` set must equal the expected set, which is every job of `ci.yml` and `lane-a.yml` at the cut SHA, with a matrix job expanded to `<job> (<value>)`.
    - Each check's `app_id` is 15368 (GitHub Actions).
    - A required check that names no job, or a job that is not required, fails the step and is named.
    - HTTP 404 ("Branch not protected") fails the step: the protection is the owner's to set.
    - HTTP 403 takes the jobs-only path (below), and the row says so.
    - Any other error fails the step.
  - **The jobs, on both paths:** for each workflow and each event (`push` and `pull_request`), the latest run on the head SHA lists exactly the expected jobs for that workflow.
    - Every job concluded `success`, or is skipped by its own condition (Design Notes).
    - A run in progress, or a `pull_request` run that has not appeared within 15 min of the pull request's opening (clock seam), gives `WAIT merge`, exit 5, no `ASK` and no record commit.
    - After 15 min with no run, the step fails.
  - The merge is `gh pr merge <n> --repo <repo> --merge --match-head-commit <cut sha>`, and nothing else.
- **Tag:** an annotated `v<v>` on the cut SHA, the commit every gate ran on, pushed alone as `git push <remote> refs/tags/v<v>`.
- **Merge back:**
  - In a temporary clone in the state folder, `<remote>/main` is merged with `--no-ff` into `<remote>/<integration>`.
  - The result must hold `src/module.xml` at `<v>` and a tracked `src/ocutalon/csp/index.html`. Then it is pushed fast-forward as `git push <remote> <integration>`.
  - Afterwards the author's checkout is brought up to date with `git merge --ff-only <remote>/<integration>`, so the next record push stays fast-forward.
  - If the merge conflicts, the step fails, nothing is pushed and the clone is removed.
- **The demo hook call contract** (Design Notes). The hook is `release/demo-update.sh` in `<state>/candidate`. If it is missing or not executable, the step prints `SKIP demo the update hook (Story 11.18) is not built; the online demo was not updated` with no `ASK`, and the row reads `not updated`.
- **Every `gh` call names `--repo <repo>`,** from 11.14's `gh_repo`. The reads allowed are `api .../branches/main/protection` (GET), `pr list`, `pr view`, `run list` and `run view`. The writes allowed are `pr create` and `pr merge`, each only after `yes`.
- **Extend, don't copy (Rule 2):**
  - 11.5's ASK, stop routine, state, clone and `release_tags`;
  - 11.14's `gh_repo`, `candidate_clone`, `record_field` and its push-run reader, which is lifted into `lib-release.sh` as `ci_runs` and used by both steps;
  - 11.15's hands-on row;
  - 11.3's `record_write`;
  - `manifest_version`.
- **Tests:** only throwaway repositories, local bare remotes and the `gh` shim (fixture JSON). The real GitHub API is only ever read, in `--live-protection` only, and that mode is skipped when `gh` is not signed in.

**Never:**
- Run `release/release.sh` in this worktree, in a real checkout, or against GitHub or any network remote.
- In this build or its tests: open a real pull request, merge into `main`, push a tag or anything else to `origin`, publish notes, or change repository settings.
- Push `main`, push with `--force`, `--tags`, `--all` or `--mirror`, or delete or move any `release/*` branch.
- Pass `gh pr merge` the options `--admin`, `--auto`, `--squash`, `--rebase` or `--delete-branch`. Call `gh api` with `-X`, `--method`, `-f` or `-F`.
- Publish, attach or commit the draft notes. Put any notes text in the pull request.
- Write the literal words of 11.4's `no-outward` patterns in any scanned file. That includes `release/release.sh`, `lib-release.sh` and `docker/tests/test-release-sequence.sh`: a test that needs the pattern builds it from parts.
- Rename a CI job or change the `iris` matrix (the standing rule: that goes to the orchestrator first), or edit `.github/workflows/*`, `ci/units.sh`, `src/module.xml`, `README.md`, `docker/tests/lib-live.sh` or `.gitignore`.
- Build 11.17's IPM step, 11.18's hook or its rehearsal mode.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Open the PR | Every gate row passes, with hands-on `pass` or `carried over`; the remote's `release/<v>-rc<n>` is at the cut SHA; `yes` | `gh pr create --repo <r> --base main --head release/<v>-rc<n> --title "Release <v>" --body-file <state file>`; `PASS pr pull request #<n> opened`; row `opened` | A gate row not passing, or a moved remote branch, gives `FAIL pr` and no create |
| Protected, all green | The protection fixture equals the real one of 2026-11-01 (12 contexts, app 15368); the push and pull_request runs of `ci` and `lane-a` are all `success`; `yes` | The merge call above; `<remote>/main` contains the cut SHA; row `merged`, naming the merge commit and `12 required checks` | -- |
| Protection mismatch | A fixture missing `evaluation`; with an extra `deploy`; with `app_id` 1; or HTTP 404 | `FAIL merge` naming the missing check, the extra check, the app, or `branch protection on main is not set` | No ASK, no merge call |
| Protection 403 | `{"message": ..., "status": "403"}` on stdout and exit 1, with every job green | Merged; the row says the jobs were checked by the sequence because branch protection was unavailable (HTTP 403) | -- |
| Jobs not green | One job `failure`; a run in progress; no pull_request run (under 15 min, then over 15 min); a job missing from a run | `FAIL merge job <name> of <wf> <event> run <id> concluded failure`; `WAIT merge`, exit 5; `FAIL merge no <wf> pull_request run on <sha>`; `FAIL merge <wf> <event> run <id> has no job <name>` | WAIT writes no record and asks nothing |
| Skipped jobs | `evaluation` skipped (no steps run) in the pull_request run, `success` in the push run; `checks` (no `if:`) skipped; a guarded job skipped in both runs | The first merges; the other two give `FAIL merge job <name> ... skipped` | -- |
| Bad PR | The head SHA differs, `isCrossRepository` is true, the base is not `main`, or the PR is not open | `FAIL merge pull request #<n> ...` naming the field | No merge call |
| Decline / no answer | `no` at any of the five ASKs; end of input | `SKIP <step> declined by the author`, exit 0, then the next step; or `STOPPED <step>`, exit 4 | Nothing goes out |
| Yes after a decline | `pr` declined, then `yes` to `merge`, `tag` and `mergeback` | Each gives `FAIL <step>` with its prerequisite line (Design Notes, FAIL details) | Nothing goes out; asked again |
| Tag | `yes` after the merge | `v<v>` (annotated, `OcuTalon <v>`) on the cut SHA; only `refs/tags/v<v>` pushed | `v<v>` at another SHA gives `FAIL tag` |
| Merge back | `yes` after the merge and the tag | `<remote>/<integration>` is a merge of `main` holding `<v>` and the tracked bundle; the author's checkout is fast-forwarded; the end-of-steps record commit pushes fast-forward | A conflict gives `FAIL mergeback` naming the paths; nothing pushed |
| Demo hook | Absent; or a stub that exits 0 / 3 / 1 | Absent: `SKIP demo` with no ASK, row `not updated`. Present: ASK, then the contract call; the row carries the hook's `RESULT` | Exit 1 or 2 gives `FAIL demo <its line>` |

</intent-contract>

## Code Map

**Prerequisites.** Stories 11.3, 11.4, 11.11, 11.13, 11.5, 11.14 and 11.15 must be merged into this branch. Today `release/` holds only `lib-release.sh`, `rehearse.sh`, `upgrade-harness.sh` and Epic 29's files, and 11.5, 11.14 and 11.15 are `ready-for-dev`. If `release.sh`, 11.14's gate steps or 11.15's hands-on gate are missing, implement HALTs `blocked` with `missing prerequisite story`, naming them.

**Files:**
- `release/release.sh` (11.5; extended by 11.14 and 11.15) -- extend it:
  - append `pr merge tag mergeback demo` to `STEPS`, with their `step_<name>` functions;
  - replace 11.15's end-of-steps `Result:` text with this story's (Design Notes);
  - the header comment gains the steps and the hook contract (Rule 14: contract only).
  - 11.5's stop routine, ASK reader and `env_get` / `env_set` state (`lib-release.sh:40-48`) are reused. New state keys: `pr_number`, `pr_opened_at`, `merge_commit`, `tag_sha`, `mergeback_sha`, and each step's outcome.
- `release/lib-release.sh` -- add these helpers:
  - `ci_runs <repo> <sha> <event>`: 11.14's push-run reader, lifted here with an event argument;
  - `workflow_jobs <file>`: lines `<check name><TAB><if: yes|no><TAB><needs: yes|no>`;
  - `protection_judge <protection json> <expected names>`: lines naming the missing, extra and wrong-app checks; empty means equal.
  - Keep `record_path`, `record_write`, `detail_clean`, `notes_path`, `candidate_branch`, `next_rc`, `release_tags`, `record_field`, `candidate_clone` and `gh_repo`.
- `docker/tests/test-release-sequence.sh` (11.5; extended by 11.14 and 11.15) -- extend it (no new `CHECK_SCRIPTS` entry):
  - Reuse 11.14's fixture driver, which takes a candidate through every gate green, and 11.15's fresh-pass fixture.
  - Reuse the clock seam and the `gh` shim, extended as follows:
    - `api .../protection` answers from a fixture file, with its status and exit;
    - `pr list|view|create|merge` work on a PR state file. `pr merge` simulates GitHub with plumbing in the bare remote (`commit-tree` with the cut tree and two parents, then `update-ref refs/heads/main`), so the merge is not a push;
    - `run list --event pull_request` and `run view --json jobs` answer from fixtures.
  - The bare remote gets a `pre-receive` hook that logs every ref that release.sh pushes.
  - If 11.15 added `--cases`, add `--cases outward`.
- `.github/workflows/ci.yml` (read only) -- the jobs `checks`, `install-macos` and `web` have no `if:`. `iris` has the fork guard `if:` (`:102`), no `needs:` and `matrix.group: [install-fresh, install-upgrade, production, browser, shards, shards-2, image]` (`:111`). No job has a `name:` key.
- `.github/workflows/lane-a.yml` (read only) -- `standalone-bridge` (`:23-24`) and `evaluation` (`:44-45`), each with the fork guard `if:` and no `needs:`.
- `docker/tests/test-ci-config.sh:1-20,154` -- it pins the workflows' fixed layout: two-space indent, one key per line, a flow-list matrix. `workflow_jobs` relies on that layout and fails on any other shape: a block or multi-key matrix, `include`, `exclude`, a job `name:` or `uses:`.
- `docker/tests/lib-live.sh:587` `manifest_version` (source only).
- Spec 11.4 `:58` (the `no-outward` row: `release/`, `ci/`, `eval/`, `docker/` and `install.sh` are scanned) -- IA2 runs the real checklist against it.
- AD-25's hook interface (spine, AD-25 "The release hook's interface") -- the contract below matches it: a bundle of the tag, `update`, then `status`.

**Measured at plan (2026-11-01, read-only `gh`, signed in as the owner):**
- `branches/main/protection`:
  - `required_status_checks.contexts` and `.checks[]` hold the 12 names, each with `app_id` 15368;
  - `strict` is false, `enforce_admins` is false, and no reviews are required.
- `branches/feature%2FOCT_OcuTalon_MVP/protection` gives exit 1, stderr `gh: Branch not protected (HTTP 404)`, and on stdout `{"message":"Branch not protected",...,"status":"404"}`. So the status is read from the stdout JSON's `status`. The 403 body is a fixture (inference from GitHub's documentation: the repository is public, so 403 cannot be measured).
- The repository allows merge commits (`allow_merge_commit` true), and `delete_branch_on_merge` is false.
- `gh run view <id> --json jobs` gives `name` (`iris (shards-2)`, `standalone-bridge`, ...), `status`, `conclusion` and `steps[]`. Story 32.2's skipped steps conclude the job `success` (run 41306887162: 9 steps, 2 skipped).
- gh 2.98.0 has `pr merge --match-head-commit`.
- `origin/main` is an ancestor of the integration branch, and no tag exists, so 1.0.0's merge commit has the candidate's tree.

## Tasks & Acceptance

**Execution:**
- **Task 0** (measure, figures into `## Verification`):
  - In a scratch throwaway repository, check that `git merge --ff-only` over ignored files in `src/ocutalon/csp/` replaces them silently, and that `git tag -a` and `git push <bare> refs/tags/v1.0.0` push only the tag.
  - Read `gh pr create --help` and `gh pr view --help` (help only) to pin the flags and the JSON fields: `number`, `state`, `baseRefName`, `headRefName`, `headRefOid`, `isCrossRepository`, `mergeCommit` and `url`.
  - Time the self-test as built by 11.15. If it would exceed about 6 minutes with this story's cases, use `--cases`.
- `release/lib-release.sh`: add the three helpers, and move 11.14's reader into `ci_runs`.
- `release/release.sh`: the five steps, the merge rule, the texts and the end text, as in Boundaries, the Matrix and Design Notes.
- `docker/tests/test-release-sequence.sh`:
  - update the pins of 11.5 (AC5's refs), 11.14 and 11.15 (the end text) for the new steps;
  - add every Matrix row, AC1 to AC10 and IA1 to IA3;
  - add `--live-protection` (`(once)`, never in CI).

**Acceptance Criteria:**
- **AC1 (the author's word; REL-11):** **Given** a candidate past `hands-on`, **when** each of the five steps is reached, **then**:
  - it prints its ASK before anything goes out;
  - `yes` acts;
  - `no` gives `SKIP`, exit 0, and the next step;
  - end of input gives `STOPPED`, exit 4, and the same ASK on the next `next`;
  - `--yes` exits 2.
  - The bare remote's refs and the shim's write log change only after a `yes`.
- **AC2 (the pull request from the passed candidate; REL-1):** **Given** `yes` at `pr`, **when** it runs, **then**:
  - the shim saw exactly the create call in the Matrix, with the title and body texts of Design Notes and no line of the draft notes;
  - a planted non-passing gate row, or a moved `release/<v>-rc<n>`, gives `FAIL pr` and no create;
  - an already-open PR whose head is the cut SHA is adopted without an ASK.
- **AC3 (protection; DW-27):** **Given** each protection fixture in the Matrix, **when** `merge` runs, **then** the result matches its row. In every failing case there is no merge call and no ASK, and the `FAIL` line names the check or the HTTP status.
- **AC4 (every job green):** **Given** each job fixture in the Matrix, **when** `merge` runs, **then**:
  - it gives `PASS`, `FAIL` or `WAIT` as in the row;
  - `WAIT` makes no record commit and adds no hands-on time;
  - the expected names come from the workflow files at the cut SHA, not from the protection.
- **AC5 (the 403 path):** **Given** the 403 fixture, **when** `merge` runs, **then** it merges only on all-green jobs, and the record row carries the 403 sentence of Design Notes.
- **AC6 (the merge call):** **Given** a green merge, **when** it runs, **then**:
  - the shim's argv is exactly `pr merge <n> --repo <r> --merge --match-head-commit <sha>`;
  - a scan of `release/release.sh` finds no `--admin`, `--auto`, `--squash`, `--rebase` or `--delete-branch`;
  - `<remote>/main` contains the cut SHA, and the row names the merge commit.
- **AC7 (the tag; REL-1):** **Given** `yes` at `tag` after the merge, **when** it runs, **then**:
  - the bare remote gains only `refs/tags/v<v>`: an annotated tag on the cut SHA (pre-receive log);
  - `v<v>` at another SHA, or a `yes` with no merge, gives `FAIL tag`.
- **AC8 (the merge back; AD-29, AD-23):** **Given** `yes` at `mergeback`, **when** it runs, **then**:
  - `<remote>/<integration>` has `<remote>/main` as an ancestor;
  - its `src/module.xml` reads `<v>`, and `git ls-files` holds `src/ocutalon/csp/index.html`;
  - the push was fast-forward;
  - the author's checkout was fast-forwarded;
  - the final record commit pushes fast-forward.
  - A planted conflict on the integration branch gives `FAIL mergeback`, with the remote unchanged and no clone left.
- **AC9 (the demo call contract; REL-10, AD-25):**
  - **Given** no hook, **when** `demo` runs, **then** there is no ASK, the `SKIP` line and row are as in the Matrix, and the end text says the online demo was not updated.
  - **Given** a stub hook that logs its argv and cwd, **when** `yes` is answered, **then**:
    - it was called exactly as the contract says, in `<state>/candidate`, with `--ref v<v>`;
    - its `RESULT` is the row: `updated`, `scheduled` with the time, or `not updated` for exit 3;
    - exit 1 gives `FAIL demo <its FAIL line>`.
  - With the tag declined in `Mode: release`, `yes` gives `FAIL demo the release is not tagged`.
- **AC10 (nothing else goes out; REL-8, REL-11, CON-1):** **Given** a run that answers `yes` to every ASK, **when** it ends, **then**:
  - the pre-receive log holds only `release/<v>-rc<n>`, `<integration>` (the record commits and the merge back) and `refs/tags/v<v>`, never `main` and never a forced update;
  - the shim's write calls are one `pr create` and one `pr merge`;
  - the draft notes are untracked and in no commit;
  - the planted secret of 11.5's AC6 appears nowhere.
- **AC11 (the end and the time; REL-3, no false all-clear):**
  - **Given** all `yes`, **when** the steps end, **then** `Result:` is the merged-and-tagged text.
  - **Given** any of `pr`, `merge` or `tag` declined, **when** the steps end, **then** it is the not-a-release text.
  - `Hands-on time:` equals the sum of every ASK window, these five included.
- **IA1 (Rule 1/2; consumes 11.15's real gate):** **Given** the real hands-on gate with 11.15's fresh-pass fixture, **when** `resume` passes it, **then** `pr` is the next ASK. **Given** no pass, **when** `next` runs, **then** `pr` is never reached.
- **IA2 (consumes 11.4's real `checklist.sh` no-outward row):** **Given** the tree with this story's files, **when** the real row runs, **then** it passes. A copy with a planted line built from the `no-outward` pattern fails with `file:line`.
- **IA3 (`(once)`, real read-only API):** **Given** a signed-in `gh`, **when** `--live-protection` runs, **then** `workflow_jobs` of HEAD's two workflows and `protection_judge` on the real `main` protection give no line, and the self-test prints `PASS live-protection 12 required checks`. Signed out, it prints `SKIP` and exits 0.
- **Pin (shared surface):** **Given** HEAD's `ci.yml` and `lane-a.yml`, **when** the self-test runs `workflow_jobs` on them, **then** the names equal the 12 contexts of the protection fixture (the real protection of 2026-11-01). A renamed job or a changed matrix fails the self-test, which is how that change reaches the orchestrator first.
- **Standing:** **Given** a fresh environment, **when** the tests added or changed run in either order, **then** every one passes.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- **AD-29:** the release PR to `main` is cut from the integration branch, and once it is merged and tagged, `main` is merged back on the author's word so the version bump and the built bundle are on the integration branch. `release/` is Lane A's; `ci.yml` (Lane B) and `lane-a.yml` are only read.
- **AD-25:** the update hook's interface (a `git bundle` of the release tag over SSH, `ocutalon-demo update` and then `status`). With no host, the sequence says so.
- **AD-22:** the demo path runs on every pull request; throwaways only; no registry.
- **AD-23:** the version and the bundle come from the cut.
- No criterion contradicts an AD. AD-29's text still attributes the merge back and the stub refusal to "Story 11.5". That is a story pointer, not a Rule; the lead may update it to 11.16 and 11.14 (apply-and-report).

**"Skipped by its own condition" (the orchestrator's question).** A job whose conclusion is `skipped` is accepted only when all three of these hold:
1. Its definition at the cut SHA has an `if:` and no `needs:`. So nothing but its own condition can skip it: not a failed or skipped dependency, and not a cancellation.
2. It ran no step (`steps` is empty).
3. The same check name concluded `success` in the other event's run on the same SHA.

Why this is safe for the release PR:
- The release PR is checked to be from this repository (`isCrossRepository` false, head `release/<v>-rc<n>`, head SHA the cut). So the fork guard `github.event_name == 'push' || github.event.pull_request.head.repo.full_name == github.repository` is true, and the guard can never skip `iris`, `standalone-bridge` or `evaluation` there.
- The push runs on the same SHA (11.14's `ci` gate) run every job.
- So the demo path (`iris (browser)`) has run green on the merged commit, whatever GitHub's required-check status says. GitHub's documentation reports a job skipped by `if:` as a successful check (inference). A whole matrix job skipped by `if:` appears as one job named `iris` (inference), which rule 3 cannot match, so it fails.

**DW-27 (ledger inbox, Rule 17).**
- **Story-closable part, delivered here:** the sequence's merge refuses unless `main`'s protection requires exactly the jobs of `ci.yml` and `lane-a.yml`, and it merges only a same-repository PR whose every job ran green or was skipped as above (AC3 to AC6).
- **Recommended at adjudication:** `resolved-by:11-16-...`, citing those tests.
- **The owner's residual:** a fork PR merged by hand in GitHub, outside the sequence, still sees the fork-guarded checks as passed, because GitHub reports a job skipped by `if:` as successful. Keeping fork PRs out of `main` by hand is the owner's practice and setting (owner-only; DW-529 closed with the protection set).

**The demo hook call contract (for Story 11.18).** `release.sh` runs, in `<state>/candidate`:
```
release/demo-update.sh --version <v> --rc <n> --ref <ref> --record <abs record> --notes <abs draft notes>
```
- `<ref>` is `v<v>` in `Mode: release`. 11.18's rehearsal mode passes the cut SHA ("because there is no tag").
- **Output:** any lines, then `RESULT updated|scheduled|not updated|fail` last. `scheduled` is followed by a `SCHEDULED <nextReset>` line, and a failure by one `FAIL demo-update <reason>` line.
- **Exit codes:** 0 updated or scheduled; 3 not updated (no demo host configured); 1 failed; 2 refused.
- **The hook writes:**
  - its own record section through `record_write`;
  - the draft notes' online-demo lines (AD-25).
  - `release.sh` writes only its `demo` row.
- If 11.18 needs polling (a long update), it adds exit 5 with 11.14's meaning (`WAIT`, the step stays current).

**Steps and order:** `... checklist hands-on pr merge tag mergeback demo`. If 11.17 puts its IPM step among these, it says so in its own plan.

**Fixed texts (new public-facing text for the lead to rule, veto window; product default 3).** Records are committed to the public repository, and the PR is public. None of these names a rival entry or entrant, says "IRIS Couch", or names OpenClaw.

ASK lines:
- `ASK pr Open the release pull request from release/<v>-rc<n> (<short sha>) into main? [yes/no]`
- `ASK merge Merge pull request #<n> into main? Every required check is green on <short sha>. [yes/no]`
  - With no PR open: `ASK merge Merge the release pull request into main? No pull request is open. [yes/no]`
- `ASK tag Tag <short sha> as v<v> and push the tag to <remote>? [yes/no]`
- `ASK mergeback Merge main back into <integration> and push it to <remote>? [yes/no]`
- `ASK demo Update the online demo to <v>? [yes/no]`

The pull request:
- Title: `Release <v>`
- Body:
  ```
  Release <v>, from the candidate release/<v>-rc<n> at <sha>.
  Every release gate passed on this commit. Its record is release/records/<v>/rc<n>.md on <integration>.
  The release notes are published separately by the author.
  ```

The tag message, and the merge-back commit message:
- `OcuTalon <v>`
- `Merge main into <integration> after <v>`

Rows:
- `pr | opened | pull request #<n> from release/<v>-rc<n> into main, on the author's word` (adopted: `... was already open`)
- `merge | merged | pull request #<n> merged into main at <short> on the author's word; <k> required checks match ci.yml and lane-a.yml, and every job of their runs on <short sha> passed`
- `merge | merged | ... ; branch protection was unavailable (HTTP 403), so the sequence checked every job of the ci and lane-a runs on <short sha> itself`
- `tag | pushed | v<v> on <short sha>, pushed to <remote> on the author's word`
- `mergeback | pushed | main merged into <integration> at <short> and pushed on the author's word; src/module.xml reads <v> and the built web bundle is tracked`
- `<step> | declined | the author declined; nothing went out`
- `demo | updated | the online demo runs <v>`
- `demo | scheduled | the online demo updates to <v> at <at>`
- `demo | not updated | <reason>`
- `<step> | fail | <detail>`

FAIL details:
- `branch protection on main is not set (HTTP 404); the owner sets it with the ci.yml and lane-a.yml checks required`
- `main's branch protection does not require: <names>`
- `main's branch protection requires checks no job runs: <names>`
- `required check <name> is not from GitHub Actions`
- `could not read main's branch protection: <status>`
- `job <name> of <wf> <event> run <id> concluded <conclusion>`
- `no <wf> pull_request run on <short sha>`
- `<wf> <event> run <id> has no job <name>`
- `pull request #<n> <field> is <value>, not <expected>`
- `the release pull request was not opened`, `... was not merged into main`, `the release is not tagged`
- `v<v> is on <short>, not the candidate <short>`
- `main does not merge cleanly into <integration>: <paths>`
- `cannot read the jobs of <file>: <what>`

Other lines:
- WAIT: `WAIT merge <wf> <event> run <id> is <status>`, and `WAIT merge waiting for the <wf> pull_request run on <short sha>`.
- SKIP: `declined by the author`, and the unbuilt-hook line in Boundaries.

End `Result:` texts (they replace 11.15's):
- Merged and tagged: `Result: merged and tagged: <v> is on main at <short> as v<v>; main merged back into <integration>: <yes|declined>; online demo: <updated|scheduled for <at>|not updated>; the author publishes the release notes`
- Otherwise: `Result: stopped after the gates: not merged and tagged (not a release); pr <outcome>, merge <outcome>, tag <outcome>, mergeback <outcome>, demo <outcome>`

**Decided in-stage (unattended block: small, reversible, in intent):**
1. **A decline skips the step and goes on, and end of input stops** (the epics' 11.18 criterion, and 11.5's ASK). 11.5's own `push` keeps "a no stops", because nothing after it can run without the push.
2. **Dependent steps are still asked,** so the author can decline each one in turn (11.18's criterion). A `yes` without the prerequisite fails and sends nothing.
3. **The merge is checked before its ASK.** The author is asked only when everything is green, and the checks are re-read on every `next`. A `WAIT` never asks, so polling adds no hands-on time.
4. **`app_id` 15368 is required for every check,** so a status from another app cannot satisfy a required name. This is stricter than the criterion, never looser.
5. **The jobs are checked on both paths, and for both events,** and a skip counts only under the three conditions above.
6. **The merge is a merge commit with `--match-head-commit`.** It is never `--admin`, even though admins are not enforced, so the sequence never bypasses a requirement.
7. **The tag is on the cut SHA,** the commit every gate ran on. For 1.0.0, `main` is an ancestor of the integration branch, so the merge commit has the same tree.
8. **The merge back is made in a temporary clone,** so a conflict leaves nothing behind. The author's checkout is then fast-forwarded (an amendment of 11.5's "only the record commit"), so the next record push stays fast-forward.
9. **Work already on the remote is adopted without an ASK,** because nothing new goes out. This keeps a crash between an action and its state write from opening a second PR or failing on an existing tag.
10. **An unbuilt hook is reported in the record only.** The draft notes' online-demo lines are the hook's to write (AD-25), and the notes are the author's.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Consumes:**
  - 11.5's step list, ASK, stop routine, state, clone helper and `release_tags`;
  - 11.14's gate rows, `ci_runs` (lifted), `gh_repo` and `candidate_clone`;
  - 11.15's hands-on gate (IA1, real);
  - 11.4's `checklist.sh` no-outward row (IA2, real);
  - 11.3's `record_write`;
  - GitHub's protection and runs (IA3, real and read-only; otherwise the shim).
- **Consumed-by:**
  - **11.18:** the `demo` step's call contract above, and 11.18 builds the hook. 11.18's rehearsal declines `pr`, `merge`, `tag` and `mergeback` through these ASKs, and passes the cut SHA as `--ref` in `Mode: rehearsal`. Its stand-in host proves the contract end to end.
  - **11.17:** it inserts its step and keeps "asks before anything goes out".
  - **Epic 38 (38.1 to 38.3):** the real 1.0.0 merge, tag, merge back and demo update.

**Smaller is better.** 11.5's line has used 5 of its 6 split children. This story is five steps in one script, sharing one merge rule and one test, so it is not split.

**Previous story continuity.** 11.10 (done) touched web e2e only. There is nothing shared.

**Contended paths (U14):** none. The files are `release/release.sh`, `release/lib-release.sh` and `docker/tests/test-release-sequence.sh`, all Epic 11's. No footprint extension.

**CI budget (inference):** the hosted `checks` job's self-test grows by about 20 to 60 s. No IRIS group runs (`release/` and `docker/tests/test-*.sh` are not IRIS inputs).

## Clarification Needed (non-blocking: this plan does not depend on the answers)

1. **The tracked bundle after the merge back (for the orchestrator).** The criterion and AD-29 put the built bundle on the integration branch, and `.gitignore` does not untrack a tracked file. So after 1.0.0's merge back, every local `ci/iris.sh build` or `npm run build` rewrites tracked files in `src/ocutalon/csp/` (Angular cleans its output folder and changes the hashed names). That leaves dirty trees. It affects 11.5's `start`, which refuses tracked changes, and `bmad-build-auto`'s clean-tree checks in every epic worktree (Rule 16). This story does not change it. A remedy (for example, 11.5's `start` treating `src/ocutalon/csp/` as the cut's own, or a fixed recipe after the merge back) changes another story's or the pipeline's behaviour, so it is not decided here.
2. **The public texts above** are listed for the lead's veto ruling.

## Verification

Run each command in its own foreground call, with `timeout: 600000`, from the worktree root. No IRIS stack and no lane lock are used. `release/release.sh` runs only inside the self-test's throwaway.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh` (or its `--cases` parts, one per call) -- expected: exit 0; the throwaway is removed.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(once)` `bash docker/tests/test-release-sequence.sh --live-protection` -- expected: `PASS live-protection 12 required checks` (or `SKIP` when signed out). It reads the real API and writes nothing.
- `(once)` If `lib-release.sh` changed: `test-upgrade-harness.sh`, `test-rehearsal.sh`, `test-release-checklist.sh` and `test-release-notes.sh`, one per call -- expected: exit 0.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash ci/changes.sh ci.yml` -- expected: exit 0, and no IRIS group for these paths.
- `(once)` `bash ci/checks.sh` in its parts, one per call -- expected: no `FAILED`.

**Mutations (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**
- AC1: treat `no` as `yes`.
- AC2: drop the gate-row check.
- AC3: compare only that the expected set is contained in the protection (so the extra `deploy` passes).
- AC4: accept `in_progress`.
- AC5: skip the jobs check on the 403 path.
- AC6: add `--admin`.
- AC7: push `--tags`.
- AC8: push before the version check.
- AC9: call the hook with no ASK.
- AC10: push `main` with the merge back.
- AC11: print the merged text when the merge was declined.
- IA1: start `pr` without the hands-on row.
- IA2: plant the pattern as a literal in the test.
- Pin: rename a job in the fixture.

**Shared surfaces:**
- The `STEPS` list, the rows and the `Result:` texts that 11.5's, 11.14's and 11.15's self-test pins. This story updates the end text and 11.5's refs pin.
- `lib-release.sh`'s function list.
- The record's `## ` sections.
- The workflows' job names and matrix: the pin above, read by this self-test only.
- Every test added or changed passes on a fresh environment, in either order. The self-test builds and removes its own repositories, bare remotes, hooks, shims, state and records.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
