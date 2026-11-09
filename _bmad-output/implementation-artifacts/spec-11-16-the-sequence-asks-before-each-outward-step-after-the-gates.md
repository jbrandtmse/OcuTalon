---
title: 'Story 11.16: The sequence asks before each outward step after the gates'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Once 11.15's hands-on gate passes, `release/release.sh` ends with "no step after the gates has run (not a release)". The Contest Planner has opened, merged and tagged 1.0.0 to 1.0.4 by hand, and merged `main` back into the integration branch by hand, untracking the built web bundle each time (U-216, DW-532). Nothing reads `main`'s branch protection or the release pull request's checks, and nothing calls the online demo's update.

**Approach:** Add five steps after `hands-on`: `pr merge tag mergeback demo`. Each one checks what it can first, then asks the author before it acts.
- `yes` acts. Any other answer skips the step (`SKIP`, exit 0), and the sequence goes on. End of input stops, as 11.5's ask does.
- `merge` asks only when `main`'s protection requires every job of the candidate's `ci.yml` and `lane-a.yml`, and every required check of the same-repository pull request has passed on the cut commit.
- `tag` and `mergeback` do what the Planner did by hand for 1.0.0 to 1.0.4.
- `demo` calls Story 11.18's hook if it exists.

## Boundaries & Constraints

**Always:**
- **The conventions of 11.5, 11.14 and 11.15 stay:**
  - Bash 3.2, ASCII, mode 100755, `umask 077` and the main guard;
  - `PASS|FAIL|WAIT|SKIP <step> <detail>` lines;
  - the stop routine (record, an explicit-pathspec commit, the `record` question);
  - exit codes 0, 1, 2, 4 and 5 keep their meaning, and WAIT (exit 5) records nothing and asks nothing;
  - answers come only from stdin through `ask`;
  - no value of the environment is printed;
  - every detail goes through `step_fail`/`detail_clean`.
- **The author's word comes before anything goes out.** Each step does its reads and local checks first, then prints its ASK (Public text). Only after `yes` does it call `gh pr create`, `gh pr merge` or `git push`, or create the tag or the merge-back commit.
- **A step whose earlier step did not happen is skipped with no ASK**, and its SKIP line says why:
  - `merge` needs an open pull request;
  - `tag` and `mergeback` need the merge;
  - `demo` needs the tag.
- **Work already on the remote is recorded and not asked again.** This covers:
  - an open or merged pull request from `release/<v>-rc<n>` whose head is the cut sha;
  - `v<v>` already on the remote at the merge commit;
  - the remote integration branch already containing the merge commit.
- **Every `gh` call names `--repo <r>`**, taken from 11.14's `gh_repo`. The allowed forms are:
  - reads: `run list` (11.14), `pr list`, `pr view`, `pr checks --required` and `api repos/<r>/branches/main/protection` (a GET, with no `-X`, `--method`, `-f` or `-F`);
  - writes, each only after `yes`: `pr create` and `pr merge <n> --merge --subject ... --body ... --match-head-commit <cut sha>`.
- **The tag goes on the merge commit.** It is the annotated `v<v>` on `main`'s merge commit, made only when that commit's second parent is the cut sha and its tree is the cut's tree. Only `refs/tags/v<v>` is pushed.
- **The merge back runs in the author's checkout, under `umask 022`.** The script's 077 would write files the containers cannot read (11.20's lesson).
  - It needs the checkout on the integration branch, with no change to a tracked file, and HEAD equal to the remote's integration head. A HEAD that is already this merge-back counts too, for a push that failed.
  - It needs `src/ocutalon/csp/` to be ignored.
  - In one merge commit it brings in `main` with `--no-ff` and untracks `src/ocutalon/csp` (`git rm -r --cached`), which also resolves the bundle's modify/delete conflicts (U-216, DW-532).
  - Any other conflict aborts the merge.
  - The push is a fast-forward of the integration branch.
- **The new code goes in new functions,** in a new section `# --- the outward steps (Story 11.16) ---` after `step_hands_on`. Only these existing lines change: the header, `STEPS`, and the `end` text in `stop_routine`.
- **Tests run only in the self-test's throwaway repositories:** a local bare remote, the existing shims, and the `gh` shim extended to answer from fixture files. The shim's `pr merge` makes the merge commit in the bare remote with plumbing.

**Never:**
- Act outward in any form, here or in any test:
  - no real pull request, merge or comment;
  - no push to origin;
  - no real tag;
  - no publish of the notes, a GitHub release, the registry or the listing;
  - no contact with the demo host or its hook endpoint;
  - no run of the real release sequence;
  - no real model key or Telegram bot;
  - no public IPM install.
- Pass `gh pr merge` the options `--admin`, `--auto`, `--squash`, `--rebase` or `--delete-branch`. Call `gh release`, `gh repo edit` or any `gh api` write. Push `main`, `--force`, `--tags`, `--all`, `--mirror` or `--delete`.
- Put any line of the draft notes into the pull request, the merge commit or the tag.
- Merge when a required check is pending, failed, cancelled, skipped or missing, or when the pull request comes from another repository (DW-27).
- Record or skip the hands-on pass (REL-7 belongs to the Planner and the owner).
- Change any of these:
  - `step_image` or the header's "Needs bash" line, or the header's "Output"/"reports no pass" line next to it (Epic 0's Story 0.15);
  - `release/upgrade-harness.sh`, `ci/warm.sh`, `ci/units.sh`, `ci/iris.sh`, `docker/tests/lib-live.sh`, `.gitignore`, `web/` or `.github/workflows/*`;
  - the self-test's Epic 0 lines: the shim's Dockerfile message, mkseed's archive list, t_image's failed-build line and t_static's `pip_pins` line.
- Build 11.18's hook or rehearsal mode. Write the real tree's `release/records/`.
- Add a `read` command: `t_word` pins the script's one `read`. Parse with `node -e`, `awk` or `sed`, as `ci_runs` does.

## I/O & Edge-Case Matrix

Texts are under Design Notes, Public text. `<c>` is the cut sha and `<m>` is the merge commit.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Open the PR | The hands-on row reads `pass` or `carried over`; the remote holds `release/<v>-rc<n>` at `<c>`; no PR from it; `yes` | `gh pr create --repo <r> --base main --head release/<v>-rc<n> --title "Release <v>" --body-file <state>/pr-body.md`; PASS; row `opened`; state `pr=<n>` | Another hands-on row, or the branch not at `<c>`: FAIL with no ASK |
| PR already there | An open or merged PR from the branch with head `<c>`, not cross-repository | PASS (already open); no ASK, no create | `pr list` fails: WAIT, exit 5 |
| No GitHub | A local-path remote and no seam, or no `gh` | The ASK still comes, so a `no` skips. A `yes` FAILs with nothing sent | -- |
| Merge, all green | The PR is open, base `main`, head ref the branch, head `<c>`, `isCrossRepository` false; `main` is an ancestor of `<c>`; the protection's contexts include every job of `ci.yml` and `lane-a.yml` at `<c>` (`iris` matrix expanded) and nothing else; every required check's `bucket` is `pass`; `yes` | ASK, then `gh pr merge <n> --repo <r> --merge --subject "Release <v>" --body "<body>" --match-head-commit <c>`, then `pr view` reads it MERGED; row `merged`; state `merge_sha=<m>` | -- |
| Protection wrong (DW-27, REL-2) | 404; 403 or another status; a job that is not required (today `ipm-install`, `ipm-install-p`); a required name that no job runs; a workflow that cannot be read | FAIL naming the status or the names; no ASK, no merge call | -- |
| PR wrong (DW-27) | Cross-repository; another head sha, head ref or base; not open | FAIL naming the field; no ASK, no merge call | -- |
| Checks not green | A required check `pending`, or not reported | WAIT, exit 5, nothing recorded, no ASK, no hands-on time | `gh` cannot read: WAIT |
| Checks red | A required check `fail`, `cancel` or `skipping` | FAIL naming the check; no ASK, no merge call | -- |
| Main moved | `main` holds a commit that is not in `<c>` | FAIL before the ASK | -- |
| Tag | Merged; `yes` | `git tag -a v<v> -m "OcuTalon <v>" <m>`; only `refs/tags/v<v>` pushed; row `pushed` | `v<v>` already at another commit (locally or on the remote); `<m>`'s tree is not `<c>`'s, or its second parent is not `<c>`: FAIL with no ASK |
| Merge back (DW-532) | Merged; checkout clean and level with the remote; `yes` | One merge commit (parents: the integration head and `<m>`). `src/module.xml` and `module.xml` read `<v>`. `git ls-files src/ocutalon/csp` is empty. Pushed fast-forward; row `pushed`. Afterwards a file written into `src/ocutalon/csp/` leaves `git status --porcelain` empty | Not level, a dirty tracked file, or `csp` not ignored: FAIL with no ASK and nothing changed |
| Second merge back | An earlier merge-back has untracked the bundle, and the new `main` changes it (modify/delete) | The untrack resolves it; same result as above | A conflict outside `src/ocutalon/csp`: `git merge --abort`, FAIL naming the paths, the remote unchanged, no `MERGE_HEAD` |
| Declines | `no` at any ASK | `SKIP <step> declined by the author`, row `declined`, exit 0, `NEXT <next>`. Later steps without their earlier step SKIP with no ASK | End of input: `STOPPED <step>`, exit 4, the record stop; the same ASK on the next call |
| Demo hook | `release/demo-update.sh` missing in the author's checkout; or a hook that exits 0 (`RESULT updated` or `RESULT scheduled <at>`), 3, or another code | Missing: SKIP, no ASK, row `not updated`. Present: ASK, then the contract call (Design Notes). The row follows the exit | Another exit: FAIL with its last line |
| End | `next` after `demo` | Merged and tagged: the released `Result:`. Otherwise: the not-a-release `Result:`. Then the `record` question | -- |

</intent-contract>

## Code Map

**`release/release.sh`** (1909 lines at this plan; 11.15 adds about 90 before this story; anchors by function):
- Header `:4` (steps), `:5-7` (exit lines; `cli_usage` prints lines 2-7). `:40` is the gates paragraph (11.15 edits its last sentence). `:47-48` is "Pushes: exactly two ...". `:49-52` are Output and Needs bash: leave them alone (Epic 0 edits `:51`).
- `STEPS` `:59`. `refuse` `:70`. `sget`/`sset` `:79-80`. `row_set` `:83`. `next_step` `:94`. `clock` `:109`.
- `ask` `:138`: returns 0 for yes, 1 for any other line, 2 at end of input. `stopped` `:153`.
- `record_abs` `:200`. `record_render` `:208` renders a row for every id in `kit $STEPS record`, so the new steps' rows need no change.
- `record_only` `:308`, `record_push` `:324`. `stop_routine` `:340`: kind `end` `:343-346` holds the end text this story replaces.
- `step_fail` `:450`. `step_cut` `:467-560` builds the bundle in `<state>/clone` and `git add -f`s it only in the cut commit (`:524-540`): DW-532's "separate folder", already met.
- `step_push` `:1027-1066`: the ASK pattern and the remote check. Its "no stops" stays.
- `short_sha` `:1110`. `step_ci` `:1208`: the gh_repo and `gh` checks, the WAIT on a read failure, the node parse.
- `step_hands_on` `:1610` (11.15 makes it pass, row `pass` or `carried over`). `cli_usage` `:1621`.
- `cmd_next` `:1696-1745`: case 0 records the row and moves on (a SKIP is a 0 return); case 4 is the stop; case 5 is WAIT. No change.
- `release_main` `:1867`: unknown options are refused (already met for `--yes` and the like).

**`release/lib-release.sh`:**
- `gh_repo` `:628`. `ci_runs` `:646-664`: the `gh ... --json | node -e` pattern that the new readers extend.
- `record_write`/`record_section`/`record_field` `:409-454`. `candidate_branch` `:363`.

**Workflows (read only):**
- `ci.yml`: jobs `checks`, `install-macos`, `web` and `iris` (the fork guard `:103`; matrix `group: [ ...10 groups ]` `:112`).
- `lane-a.yml`: `standalone-bridge`, `evaluation`, `ipm-install` and `ipm-install-p` (each with the fork guard).
- No job has a `name:` key, so the expected check names are the 17 job keys, with `iris (<group>)` for each group. `test-ci-config.sh` pins this layout.

**`main`'s protection** (measured 2026-11-09 with a read-only `gh api` GET):
- 15 contexts, all from app 15368: `checks`, `web`, `install-macos`, `iris (install-fresh|install-upgrade|production|browser|shards|shards-2|image|shards-3|shards-4|shards-5)`, `standalone-bridge` and `evaluation`.
- Not required: `ipm-install` and `ipm-install-p`.
- `strict` false, `enforce_admins` false, no reviews.

**The Planner's practice (git history):**
- `main` first-parent: `Release 1.0.0` to `Release 1.0.4` are merge commits made by GitHub (committer `GitHub`), with parents (previous `main`, the candidate).
- Their trees equal the candidates' (checked for 1.0.0 `8b3cac3c`/`9a476db3` and 1.0.4 `176c642a`/`c7d8fa75`).
- `v1.0.0`..`v1.0.4` are annotated `OcuTalon <v>` on those merge commits.
- The merge-backs `Merge main (v1.0.x) back into the feature branch` (`8345cfca`, `9683c1f0`, `bed23f1d`, `18b9d973`) change only `module.xml` and `src/module.xml` against the feature parent. They drop the 19 bundle files that `main` tracks.
- The records 1.0.0-1.0.4 hold no PR, merge or tag row; `1.0.0/rc4.md` "## Release result" holds them as prose.

**`release/checklist.sh` `outward_hits` `:373`:** the `no-outward` patterns (`gh release ...`, `gh repo edit`, `--visibility`, public sites). `gh pr` is not among them, and none may be written.

**Self-test `docker/tests/test-release-sequence.sh`** (4312 lines; 11.15 adds `t_carryover` and changes `t_handson`):
- The gh shim is in `mkshims` `:404-409`; any form but `run list` marks the network.
- Helpers: `newcase` `:792` (`R` bare, `W` checkout, `OCUTALON_RELEASE_GH_REPO=owner/repo`), `rs` `:820`, `Y`/`N`, `snap` `:835`, `set_fixture` `:898`, `to_step` `:937`, `run_steps` `:920`, `sect`, `row_of` `:3262`, `remote_refs` `:3263`.
- `t_gate` `:1802` jumps to `next done` and pins the end text. `forbidden_scan` `:1839`: its `git ... tag` clause flags `tag -a`. `t_secret` `:1858`, `t_word` `:1912` and `t_pushes` `:1977` (two pushes up to the hands-on stop) stay valid.
- `t_static` `:3173`:
  - the STEPS pin `:3194`;
  - the "gate steps make no ASK" pin `:3195` (from the gates marker to `# --- commands ---`);
  - the gh pins `:3198-3199` (`gh run list` only, once);
  - "no outward form" `:3254`.
- Rule list `:44-77`. Rule calls `:4271-4305`. State jumps use `env_set` in a subshell that sources `lib-release.sh` (`t_gate`).

## Tasks & Acceptance

**Execution:**
- **Task 0 (implement; figures into `## Verification`):**
  - In a scratch throwaway repo (no remote), confirm that `git merge --no-ff --no-commit` then `git rm -r --cached` resolves a modify/delete on ignored-path files, and that it overwrites ignored untracked files at those paths silently.
  - Time `to_outward` (below).
- `release/lib-release.sh` -- add these functions after `ci_runs`, each with a contract comment, extending its `gh ... --json | node -e` pattern:
  - `workflow_checks`: reads a workflow on stdin and prints its check names, one per line, with `<job> (<group>)` for a one-line `group: [...]` matrix. It prints nothing for an unreadable layout.
  - `gh_pr_list <repo> <branch>`: `number<TAB>state<TAB>headRefOid<TAB>isCrossRepository`.
  - `gh_pr_view <repo> <n>`: `state baseRefName headRefName headRefOid isCrossRepository mergeCommit.oid`, tab-separated.
  - `gh_protection <repo>`: the required contexts, one per line. It returns 4 on HTTP 404 and 3 on any other HTTP status read from the stdout JSON's `status`.
  - `gh_pr_checks <repo> <n>`: `name<TAB>bucket` from `pr checks --required --json name,bucket`. Exit 0, 1 and 8 with JSON that parses are answers; anything else is a read failure.
- `release/release.sh`:
  - the header lines 4, 7 and 47-48, plus a new "The outward steps" paragraph after the gates paragraph (Public text);
  - `STEPS` gains `pr merge tag mergeback demo`;
  - the `end` result in `stop_routine` becomes the two Public-text texts, chosen from the `merge` and `tag` rows;
  - the new section after `step_hands_on`: `outward_word <id> <question>` (wraps `ask`: SKIP and row `declined` on 1; STOPPED, row `stopped` and return 4 on 2), `step_pr`, `step_merge`, `step_tag`, `step_mergeback` and `step_demo`, as the Matrix and Boundaries say.
  - The PR body file is written into the state folder from the Public text.
  - The demo hook runs from `$rel_root`, with stdin closed and its output in `<state>/demo.log`.
- `docker/tests/test-release-sequence.sh` (no new `CHECK_SCRIPTS` entry):
  - **gh shim:** it keeps `run list`. It answers `pr list|view|checks` and `api .../protection` from `$SHIMSTATE` fixture files (an exit-code file for each). `pr create` writes the PR state, takes `headRefOid` from the bare remote and prints the URL `https://github.com/owner/repo/pull/7`. `pr merge` checks `--match-head-commit`, makes `main` in `$R` a merge commit (`commit-tree <c>^{tree} -p main -p <c>`, then `update-ref`), and sets MERGED. Every call is logged; any other form marks the network.
  - **Helper `to_outward`:**
    - `set_fixture` the real `ci.yml` and `lane-a.yml`;
    - `refs/heads/main` in `$R` at the seed commit;
    - the steps from start to `push` answered yes;
    - `env_set next pr` and a `hands-on` row `pass`;
    - green fixtures: the protection from `workflow_checks` of the two files, every check `pass`.
  - **New rules:**
    - `outward`: AC2, AC4-AC6, AC8, AC9, and DW-532's second merge-back in a second release of the same case;
    - `declines`: AC1;
    - `merge`: AC3 and DW-27, every fixture in one case;
    - `demo`: AC7.
  - **Update:**
    - the `t_static` pins: STEPS; the gate-steps-no-ASK pin ends at the new section marker; gh forms and counts as Boundaries lists them; a scan for the five forbidden merge options;
    - `forbidden_scan`: accept the one form `tag -a "v$version" -m "OcuTalon $version"`, and keep `git tag v1.0.0` flagged;
    - `t_gate`'s end text;
    - 11.15's `t_handson`/`t_carryover`: a fresh pass or a carry-over now prints `NEXT pr` and exits 0 with no stop. IA1's record push is reached through the declines to the end;
    - the header rule list (Public text).

**Acceptance Criteria:**
- **AC1 (the author's word; REL-11).** Given a candidate past `hands-on`, when each of the five steps is reached, then:
  - its ASK comes before anything goes out;
  - `no` gives SKIP, exit 0 and the next step;
  - end of input gives STOPPED, exit 4, the record stop, and the same ASK on the next call;
  - every later step whose earlier step was declined SKIPs with no ASK;
  - the bare remote's refs and the shim's write calls change only after a `yes`.
- **AC2 (the pull request from the passed candidate; REL-1).** Given `yes`, when `pr` runs, then:
  - the shim saw exactly the create call of the Matrix, with the Public-text title and body;
  - a line planted in the draft notes is in no gh argv and not in the body;
  - an existing PR is adopted with no ASK;
  - a `hands-on` row of `waiting`, or a moved remote branch, FAILs before the ASK.
- **AC3 (merge only on every required check green; DW-27).** Given each protection, PR, checks and ancestry fixture of the Matrix, when `merge` runs, then its row holds. Every FAIL and WAIT has no ASK and no `pr merge` in `gh.log`. A WAIT leaves `snap` and the hands-on seconds unchanged.
- **AC4 (the merge call).** Given all green, when `merge` is answered `yes`, then:
  - the merge argv is exactly the Matrix's;
  - `main` on the remote is a merge commit with parents (old `main`, `<c>`), subject `Release 1.0.0`;
  - the row names `<m>` and the count of required checks.
- **AC5 (the tag).** Given the merge, when `tag` is answered `yes`, then the remote gains only `refs/tags/v1.0.0`, an annotated tag `OcuTalon 1.0.0` on `<m>`. Each FAIL fixture of the Matrix FAILs before the ASK.
- **AC6 (the merge back; AD-29, DW-532).** Given the merge, when `mergeback` is answered `yes`, then:
  - the remote's integration head is a merge of `<m>` that reads `1.0.0` and tracks no `src/ocutalon/csp` path;
  - the push was a fast-forward;
  - a file written into `$W/src/ocutalon/csp/` leaves `git status --porcelain` empty;
  - the next record push is a fast-forward;
  - a second release's merge-back (modify/delete on the bundle) succeeds the same way;
  - a planted conflict outside the bundle FAILs with the remote unchanged, no `MERGE_HEAD`, and HEAD as before.
- **AC7 (the demo seam; REL-10, AD-25).** Given no hook, when `demo` runs, then it SKIPs with no ASK and the row reads `not updated`. Given a stub hook that logs its argv and cwd, then:
  - on `yes` it was called exactly per the contract, from the checkout;
  - exit 0 with `RESULT updated` or `RESULT scheduled 2026-11-10T04:00:00Z` gives that row;
  - exit 3 gives `not updated`;
  - exit 1 FAILs with its last line;
  - with the tag declined it SKIPs with no ASK.
- **AC8 (nothing else goes out; REL-8, CON-1).** Given a candidate past `hands-on`, when every ASK is answered `yes` to the end, then:
  - the git shim's pushes are, in order: the candidate, the record(s) the run pushed, `refs/tags/v1.0.0`, and the integration branch's merge-back, then the final record. Never `main`, never a force;
  - the gh write calls are one `pr create` and one `pr merge`;
  - the draft is in no commit;
  - the planted secret is nowhere;
  - `t_static`'s outward-form and merge-option scans pass.
- **AC9 (the end and the time; REL-3; AD-28's principle).**
  - Given every ASK answered `yes`, when the steps end, then the record's `Result:` is the released text.
  - Given `pr`, `merge` or `tag` declined, when the steps end, then it is the not-a-release text.
  - Given the seam clock, when the steps end, then `Hands-on time:` is the sum of every ASK window, these five included.
- **IA1 (consumes 11.15's real gate).** Given 11.15's fresh-pass section, when `resume` passes `hands-on`, then it prints `NEXT pr`, and the next `next` prints the `pr` ASK. Given no pass, `pr` is never reached.
- **IA2 (consumes the real workflows).** Given the tree's `ci.yml` and `lane-a.yml`, when `workflow_checks` reads them, then it lists every `jobs:` key once, with `iris` expanded to one name per matrix group (17 today, derived in the test and not written as a literal).
- **Standing.** Given a fresh environment, when the tests added or changed run in either order, then every one passes.

## Spec Change Log

- **planner-2026-11-09-11.16** (the Contest Planner's rulings, relayed by the orchestrator, 2026-11-09):
  - The 11.14 hunks and this story's `### Public text` are reviewed after 1.0.5 is merged and on the demo, later on 2026-11-09. **Do not implement this story before that text is approved.** The merges stay held.
  1. **AD-29: amended.** The Rule now reads "so the version bump is on it, with the built web bundle untracked there (U-216, DW-532)", marked `[AMENDED 2026-11-09, Story 11.16, Contest Planner ruling]`; the epics.md merge-back clause of this story's criterion is amended to match (same marker). Written by the lead; spine lint at baseline (10 low placeholder findings, unchanged). On the owner's architecture-Update list. This resolves the plan's Clarification 1 and the Design Notes' conflict note: the `mergeback` step's untrack is the AD's rule now.
  2. **Dropping the private-repository HTTP 403 fallback: confirmed** (Decided 3). A 403 FAILs the merge.
  3. **`ipm-install` and `ipm-install-p` as required checks:** the owner is asked to add them. Until then the `merge` step refuses, which is correct. The sequence and its tests never touch repository settings.
  4. **DW-27:** report only (the residual stays a PLANNER REPORT item).
  - **CI:** the `release-sequence` self-test moves out of the hosted `checks` job into its own hosted job before this story lands, in its own CI-only commit, with its first clean timings reported.
- **planner-2026-11-09-11.16-text** (the Contest Planner [3dd56e], relayed by the orchestrator, 2026-11-09): the `### Public text` is APPROVED as written (ASK/PASS/SKIP/WAIT/FAIL lines, PR title and body, merge commit, tag message, merge-back commit, end Result texts, header contract, self-test rule list).
- **parked: owner re-plan 2026-11-09** (the owner, via the Contest Planner and the orchestrator): parked until after voting week. Do not implement; the approved text stays on file here.

## Review Triage Log

## Design Notes

**Already met (not rebuilt):**
- **ASK, only `yes`, end of input stops, no option or variable answers:** `ask` `:138`, header `:42-43`, `release_main` refusals, `t_word`.
- **Hands-on time is the sum of the ASK windows:** `:44-45`, `hands_add`.
- **"It never publishes the notes":**
  - the draft is never committed (DW-560, `record_commit`'s pathspec, `t_pushes`);
  - no `gh release` or `gh repo edit` (`t_static` "no outward form"; checklist row `no-outward`).
- **DW-532, "build into a separate folder and copy it in only at the cut":** `step_cut` builds the bundle in `<state>/clone` and force-adds it only in the cut commit (`:467-560`). The author's tree is never built into.
- **Branch protection exists:** DW-529, set 2026-11-01, measured again 2026-11-09 (Code Map).
- **1.0.0's own steps:** done by hand (`release/records/1.0.0/rc4.md`, "## Release result"; `v1.0.0` on `8b3cac3c`).

**Built here.** The steps the Planner does by hand today: open the PR, check the required checks, merge, tag, merge back with the bundle untracked, and the demo update's call.

**Governing ADs (Rule 6):**
- **AD-29:** the release PR from the integration branch, the merge back, and the lanes (`release/` is Lane A's; the workflows are only read).
- **AD-25:** the hook interface. The demo step only calls 11.18's hook.
- **AD-22:** CI and the demo path on every PR; tests in throwaways; no registry.
- **AD-23:** the version and the bundle come from the cut.
- **AD-19:** no environment value is printed.
- **AD-28's principle:** no false all-clear. The released text only when merged and tagged.
- **Conflict note:** AD-29's Rule (and the AC) say the merge back puts "the built web bundle" on the integration branch. U-216 (the owner via the Planner, kept 2026-11-02) and DW-532 untrack it there, as the Planner has done four times. This plan follows U-216. See Clarification Needed 1.

**Decided in-stage (small, reversible, within intent):**
1. **A `no` skips the step and goes on, and end of input stops.** 11.18's rehearsal needs "a declined step is skipped". `push` keeps its "a no stops".
2. **A step whose earlier step did not happen is skipped with no ASK.** It asks no question that cannot be acted on, and nothing goes out either way. 11.18's rehearsal then declines `pr`, and the later steps SKIP.
3. **The HTTP 403 private-repository fallback is dropped as moot.**
   - The repository has been public since 2026-10-31, and the protection read works (measured 2026-11-09).
   - A 403 now FAILs `merge` ("could not be read"). This refuses more, never less, and needs no dead branch kept under test (product default 6).
4. **"Every required check green":**
   - The protection must require every job of the candidate's own `ci.yml` and `lane-a.yml`, and nothing else.
   - Each required check's `gh pr checks --required` buckets must all be `pass`.
   - `skipping`, `cancel` and `fail` FAIL. `pending` or not reported WAITs, with no window: never a false pass.
5. **The merge is a GitHub merge commit,** as for 1.0.0 to 1.0.4: `--merge --subject "Release <v>" --match-head-commit <c>`, never `--admin`.
6. **The tag goes on `main`'s merge commit (practice),** only when its tree is the cut's tree and its second parent is the cut. So the tag names exactly what the gates ran on. A pre-merge guard (`main` is an ancestor of `<c>`) makes that hold.
7. **The merge back runs in the author's checkout under `umask 022`, level with the remote,** with the bundle untracked in the merge commit (U-216). A FAIL for "not level" goes through the stop routine, whose record question pushes a pending record commit, so the next call proceeds.
8. **The demo hook is looked up in the author's checkout,** like `notes.sh`. If it is absent, `demo` says so.
9. **Work already done is adopted.** This makes a re-run after a partial failure, or a step the Planner did by hand, safe.
10. **The header's line 50, "This script reports no pass for a release", stays.** It sits next to Epic 0's line, and it stays true: no PASS line is printed for the release, and the record states facts.

**Demo hook contract (Story 11.18 provides `release/demo-update.sh`):**
- **The call:** `bash release/demo-update.sh --version <v> --rc <n> --ref v<v> --record <abs record> --notes <abs draft>`, from the checkout, with stdin closed.
- **Exit codes:** 0 means updated or scheduled, with a last line `RESULT updated` or `RESULT scheduled <at>`. 3 means not updated (no demo host configured). Anything else fails, and the last line is the reason.
- **What the hook writes:** its own record section and the notes' demo lines. `release.sh` writes only the `demo` row.
- 11.18's rehearsal mode may pass another `--ref`.

**Extend, don't copy (Rule 2):**
- `outward_word` wraps `ask` and `stopped`, and follows `step_push`'s stop branch.
- The gh readers extend `ci_runs`' `gh --json | node -e` pattern, and every call takes its repository from `gh_repo`.
- The record push after the merge back is `record_push`/`record_only`, unchanged.
- The end text stays in `stop_routine`.
- The shim extends 11.14's gh shim, and `to_outward` extends `to_step` and 11.15's state jump.

**Rules 1 and 2:**
- **Consumes:**
  - 11.15: the passing `hands-on` (IA1);
  - 11.14: `gh_repo`, `ci_runs`' pattern, the gate rows;
  - 11.5: `ask`, `stop_routine`, `record_push`;
  - the real workflows (IA2);
  - Story 11.18's hook. It is not built yet, so `demo` SKIPs. 11.18 provides it and adds its own Integration AC against this contract.
- **Consumed-by:**
  - 11.18: its rehearsal drives `pr`..`demo` with declines, and `demo` calls its hook;
  - the Contest Planner's 1.0.6 release.

**Ledger (Rule 17):**
- **DW-27:** addressed for the sequence's own merge (Matrix "PR wrong", "Protection wrong" and "Checks red"; AC3). The release PR must come from the same repository with head `<c>`, so the fork guard runs `iris (browser)`. A `skipping` check is never green, and the `ci` gate already proved the push runs on `<c>`. The residual is owner-only (PLANNER REPORT). At adjudication: resolved-by this story, with that residual.
- **DW-532:** addressed by `mergeback` (AC6, Matrix "Merge back" and "Second merge back"). The "separate folder" half is already met (above).

**release/** files changed (for the Planner's review):**
- `release/release.sh`: header lines 4, 7, 47-48 and the new paragraph; `STEPS`; the `end` text in `stop_routine`; the new section.
- `release/lib-release.sh`: five new functions after `ci_runs`.

**Header contract change (Public text):**
- Pushes go from "exactly two" to: the candidate branch, the integration branch (the record commit, or the merge back) and `refs/tags/v<v>`, each behind its own ASK.
- `main` changes only through `gh pr merge` behind the `merge` ASK.

**Shared files and where (contended):**
- `release/release.sh` stays off `:51` and `step_image`.
- In the self-test: the shim block, new helpers and rules, `t_static`'s gh, STEPS and ASK pins, `forbidden_scan`, `t_gate`, and 11.15's two rules. The Epic 0 lines are untouched.
- `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` on 2026-11-09:
  - Epic 0 changes `release/release.sh` (`:51`, `:575`), the self-test (its four lines), `release/upgrade-harness.sh`, `ci/units.sh`, `ci/warm.sh` and `docker/tests/lib-live.sh`;
  - Epics 41, 17 and 32 change none of these paths.
- `footprint_extensions:` none.

**CI budget (REL-4):** no unit or group changes. The hosted `checks` job's `release-sequence` grows by about 60-90 s (inference: about 7 cases at about 13 s each, measured from `push`'s 13 s). Each case jumps to `pr` with no gate drive.

**PLANNER REPORT:**
1. `main`'s protection does not require `ipm-install` and `ipm-install-p` (measured 2026-11-09). `merge` will refuse until the owner adds them (owner-only repository setting). The other choice is for the owner to rule that those jobs are not required, which would change this story's expected set.
2. DW-27's residual: a fork PR merged by hand in GitHub still sees the fork-guarded checks as passed (a job skipped by `if:` reports success; inference from GitHub's documentation, DW-529's note). Closing it is an owner-only setting.
3. Not provable without acting outward:
   - the real `gh pr create`, `pr checks --required` (bucket mapping and duplicate push and pull_request entries), `pr merge --subject/--body/--match-head-commit`;
   - the 404 body of `gh api` (measured on 2026-11-01 by the set-aside plan: exit 1, the JSON on stdout);
   - a real tag push and merge-back.
   The Planner proves them at 1.0.6.
4. The Planner's release playbook (under `.claude/`, owner-only) should learn the five steps.

**Size and split proposal.** One implement pass: `release.sh` about +260 lines, `lib-release.sh` about +90, the self-test about +450 (inference, against 11.14's +436/+190/+1300 in one pass). If the lead wants a split: 11.16a `pr`+`merge` (DW-27), and 11.16b `tag`+`mergeback`+`demo` (DW-532).

### Public text

Every line is printed by `release/release.sh` on the author's console. Rows and `Result:` lines go into `release/records/<v>/rc<n>.md`. `<short>` is 7 characters, `<sha>` is 40, `<m>` is the merge commit and `<int>` is the integration branch.

- **Header line 4:** `# Steps, in order: cut, stubs, image, overview, ipm, ipmcheck, push, ci, eval, upgrade, rehearsal, notes, checklist, hands-on, pr, merge, tag, mergeback, demo`
- **Header line 7:** `#       (nothing recorded; the next call runs the step again); merge also waits (5) until the release pull request's required checks pass`
- **Header lines 47-48:** `# Pushes, each on the author's word: the candidate branch; the integration branch, fast-forward, with the record commit or the merge back` / `# of main; and the tag v<v> alone. Never a force, main or another ref: main changes only through gh pr merge. No value of the environment is ever printed.`
- **Header paragraph (new, after the gates paragraph):** `# The outward steps (Story 11.16; REL-1, REL-8, REL-11, AD-29). After hands-on passes, pr, merge, tag, mergeback and demo each ask for the author's word before they act; a no skips the step and the sequence goes on, and a step whose earlier step did not happen is skipped without a question. pr opens the release pull request from the candidate branch into main. merge reads main's branch protection, refuses unless every job of the candidate's ci.yml and lane-a.yml is a required check, and asks only when every required check of the pull request has passed on the cut commit; GitHub then merges it. tag puts the annotated tag v<v> on that merge commit and pushes the tag alone. mergeback merges main into the integration branch with the built web bundle kept untracked and pushes it fast-forward. demo runs release/demo-update.sh (Story 11.18) when it exists. Work already done on the remote is recorded and not asked again. The release notes are the author's to publish.`
- **ASK:**
  - `ASK pr Open the release pull request from release/<v>-rc<n> (<short>) into main? [yes/no]`
  - `ASK merge Merge pull request #<n> into main? Its <k> required checks passed on <short>. [yes/no]`
  - `ASK tag Tag the merge commit <m short> on main as v<v> and push the tag to <remote>? [yes/no]`
  - `ASK mergeback Merge main (<m short>) back into <int>, keeping the built web bundle untracked, and push it to <remote>? [yes/no]`
  - `ASK demo Update the online demo to <v>? [yes/no]`
- **PASS (row value; the detail is the text after `PASS <step> `):**
  - `PASS pr pull request #<n> from release/<v>-rc<n> into main opened on the author's word` (`opened`)
  - `PASS pr pull request #<n> from release/<v>-rc<n> into main is already open` (or `already merged`) (`opened`)
  - `PASS merge pull request #<n> merged into main at <m short> on the author's word; its <k> required checks, every job of ci.yml and lane-a.yml, passed on <short>` (`merged`)
  - `PASS merge pull request #<n> is already merged into main at <m short>` (`merged`)
  - `PASS tag v<v> on the merge commit <m short> (the tree of <short>) pushed to <remote> on the author's word` (`pushed`)
  - `PASS tag v<v> is already on <remote> at <m short>` (`pushed`)
  - `PASS mergeback main merged into <int> at <short> and pushed to <remote> on the author's word; src/module.xml reads <v> and the built web bundle stays untracked` (`pushed`)
  - `PASS mergeback main is already merged into <int> on <remote>` (`pushed`)
  - `PASS demo <the hook's RESULT text after RESULT >` (`updated` or `scheduled`)
  - `PASS demo not updated: <the hook's last line>` (`not updated`)
- **SKIP:**
  - `SKIP <step> declined by the author` (row `declined`, detail `the author declined; nothing went out`)
  - `SKIP merge no release pull request is open` (`skipped`)
  - `SKIP tag the release pull request is not merged` (`skipped`)
  - `SKIP mergeback the release pull request is not merged` (`skipped`)
  - `SKIP demo the release is not tagged, so the online demo was not updated` (`not updated`)
  - `SKIP demo the update hook release/demo-update.sh (Story 11.18) is not built, so the online demo was not updated` (`not updated`)
- **STOPPED (11.5's, unchanged):** `STOPPED <step> waiting for the author's word` (row `stopped`)
- **WAIT:**
  - `WAIT pr gh could not read the pull requests (exit <n>); the next call reads them again`
  - `WAIT merge gh could not read <pull request #<n>|main's branch protection|the checks of pull request #<n>> (exit <n>); the next call reads it again`
  - `WAIT merge required check <name> is pending on <short>`
  - `WAIT merge required check <name> has not reported on <short>`
- **FAIL (row `fail`):**
  - `FAIL pr the hands-on gate has not passed`
  - `FAIL pr release/<v>-rc<n> is not on <remote> at the cut commit`
  - `FAIL <pr|merge> gh is not installed`
  - `FAIL pr the remote <name> is not a GitHub repository, so no pull request can be opened`
  - `FAIL pr gh pr create failed: <its last line>`
  - `FAIL merge pull request #<n> <state|baseRefName|headRefName|headRefOid|isCrossRepository> is <value>, not <expected>`
  - `FAIL merge main is not on <remote>`
  - `FAIL merge main on <remote> holds commits that are not in the candidate, so the merge would not be the tree the gates ran on`
  - `FAIL merge branch protection on main is not set (HTTP 404); the owner sets it with every job of ci.yml and lane-a.yml required`
  - `FAIL merge main's branch protection could not be read (HTTP <status>); the merge needs it`
  - `FAIL merge main's branch protection does not require: <names>; the owner adds them`
  - `FAIL merge main's branch protection requires <names>, which no job of ci.yml or lane-a.yml runs`
  - `FAIL merge the jobs of .github/workflows/<file> at <short> could not be read`
  - `FAIL merge required check <name> is <fail|cancel|skipping> on <short>`
  - `FAIL merge gh pr merge failed: <its last line>`
  - `FAIL merge pull request #<n> is not merged after gh pr merge`
  - `FAIL tag v<v> is on <short>, not on the merge commit <m short>`
  - `FAIL tag the merge commit <m short> does not hold the tree of the candidate <short>`
  - `FAIL tag git push of v<v> to <remote> failed`
  - `FAIL mergeback the checkout is not on <int>`
  - `FAIL mergeback the checkout has uncommitted changes to tracked files`
  - `FAIL mergeback the checkout's <int> is not <remote>'s (<short> against <short>); push the record or bring the checkout up to date, then run release.sh resume`
  - `FAIL mergeback src/ocutalon/csp/ is not ignored on <int>, so the built web bundle cannot stay untracked`
  - `FAIL mergeback main does not merge cleanly into <int>: <paths>`
  - `FAIL mergeback after the merge, <file> reads <x>, not <v>`
  - `FAIL mergeback git push of <int> to <remote> failed`
  - `FAIL demo release/demo-update.sh exited <n>: <its last line>`
- **The pull request:**
  - Title: `Release <v>`
  - Body:
    ```
    Release <v>, from the candidate release/<v>-rc<n> at <sha>.

    Every gate of the release sequence passed on this commit, and the author's hands-on pass (REL-7) is recorded or carried over. The record is release/records/<v>/rc<n>.md on <int>.

    The release notes are published separately by the author.
    ```
- **Merge commit:** subject `Release <v>`, body `From release/<v>-rc<n> at <sha>; its record is release/records/<v>/rc<n>.md on <int>.`
- **Tag message:** `OcuTalon <v>`
- **Merge-back commit:** `Merge main (v<v>) back into <int>`, a blank line, then `The built web bundle under src/ocutalon/csp stays untracked on <int> (.gitignore).`
- **Record `Result:` at the end (replaces 11.14's end text):**
  - `merged into main at <m short> and tagged v<v>; merge back: <the mergeback row>; online demo: <the demo row>; the release notes are the author's to publish`
  - `stopped after demo: not merged and tagged (not a release)`
- **Self-test header rule list:**
  - `outward   (Story 11.16, AC2, AC4 to AC6, AC8, AC9) an all-yes run: the pull request, the merge on green required checks, the tag on the merge commit, the merge back with the bundle untracked (DW-532), the pushes, the end`
  - `declines  (Story 11.16, AC1) a no skips each outward step and the sequence goes on; the end of input stops; a step whose earlier step did not happen is skipped without a question`
  - `merge     (Story 11.16, AC3, DW-27) the merge refuses or waits on main's branch protection, the pull request's fields and every required check, with no question and no merge call`
  - `demo      (Story 11.16, AC7) the demo step and the update hook's call contract (Story 11.18)`
- No README or docs line changes.

## Clarification Needed (non-blocking: veto window; the plan follows the recommended answer)

1. **AD-29's Rule and the AC say the merge back puts "the built web bundle" on the integration branch.** U-216 (kept by the Planner under the owner's delegation, 2026-11-02) and DW-532 keep it untracked there, and the Planner has done so at every merge-back (1.0.1 to 1.0.4). The 1.0.1 to 1.0.4 pull requests merged with no conflict. Recommended: keep U-216. The lead amends AD-29's Rule text to "so the version bump is on it, with the built web bundle untracked there (U-216, DW-532)" (Rule 20; amending an AD is a veto item).
2. Rule the new public text (veto window 5).
3. Decided 3 (the 403 fallback dropped) is listed here for visibility. It narrows a clause whose condition no longer holds.

## Verification

Run each command in its own foreground call with `timeout: 600000`, from the worktree root, with `TMPDIR` in the stage's scratch folder and `ANTHROPIC_API_KEY` unset. Each must finish in about 150 s.

Measured earlier, one rule per run:
- 11.14: `push` 13 s;
- 11.14's code review: `hands resume notes` 86 s; `gate secret first word pushes` 54 s; `rehearsal handson static` 53 s;
- 11.15: `handson` 12 s, `recut` 16 s.

The new rules are estimated (inference): `outward` about 45 s, `declines` about 40 s, `merge` about 30 s, `demo` about 20 s. If a batch nears 120 s, split it and record the new batches here.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh outward declines` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh merge demo` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh handson carryover static gate` -- expected: `PASS all rules`.
- `(once)` the other rules that reach `push` or later, or scan the script, one batch per call: `secret word pushes`, `push record`, `hands resume notes`, `gates`, `ci eval` -- expected: `PASS all rules` each.
- `(once)` `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-release-checklist.sh` (its `no-outward` row scans `release/`) -- expected: exit 0 each.

**Mutations to apply (Rule 19; one per AC; record each as `mutation: ... → ...`):**
- AC1: a `no` stops (return 4) like `push`. Expect red in `declines`.
- AC2: `--head` dropped from the create call. Expect red in `outward`.
- AC3: a `skipping` bucket counted as green. Expect red in `merge`.
- AC3: the cross-repository test skipped. Expect red in `merge` (DW-27).
- AC4: `--match-head-commit` dropped. Expect red in `outward`.
- AC5: the tag put on `<c>` instead of `<m>`. Expect red in `outward`.
- AC6: the `git rm --cached` skipped. Expect red in `outward` ("no csp path tracked", "status clean after a build").
- AC7: exit 3 mapped to FAIL. Expect red in `demo`.
- AC8: the tag pushed with the integration push in one call. Expect red in `outward` (the push list).
- AC9: the released text whenever `merge` is `merged`. Expect red in `declines` (tag declined).
- IA1: `next_step hands-on` is `done`. Expect red in `handson`.
- IA2: the matrix expansion dropped. Expect red in `static`.

**Shared surfaces:**
- `STEPS` (the `t_static` pin; 11.18);
- the end `Result:` texts (`t_gate`, 11.15's rules);
- the step rows and their values;
- the gh shim's answer set and its network marker (`t_secret`);
- `forbidden_scan`;
- the header's push contract and `cli_usage`'s lines 2-7;
- the gate-steps-no-ASK pin's markers;
- the `lib-release.sh` function list;
- the `## Hands-on pass` fixture (11.15).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned fresh against the delivered 11.14 code and 11.15's validated spec. Halted after planning, as the dispatch asked. Nothing was implemented, committed or pushed.
