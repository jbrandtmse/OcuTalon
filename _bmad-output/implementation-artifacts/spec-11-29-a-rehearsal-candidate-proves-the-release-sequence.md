---
title: 'Story 11.29: A rehearsal candidate proves the release sequence'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-15-the-hands-on-gate-stops-the-sequence-and-its-resume-command.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-16-the-sequence-asks-before-each-outward-step-after-the-gates.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-18-the-update-hook-updates-the-online-demo-and-a-rehearsal-cand.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing has run the whole release sequence end to end: 11.14's gates, 11.15's hands-on gate, 11.16's outward steps and 11.18's update hook have each been tested alone. `release.sh` has no rehearsal mode, so the only way to try the sequence is a real `release/*` candidate, which would reach the public origin and trip the step epics' rc1 merge gate (U-203).

**Approach:** `release.sh start --version <v> --rehearsal` cuts `rehearsal/<v>-rc<n>` and works only against local bare repositories. Its record is `release/records/<v>/rehearsal-rc<n>.md` with `Mode: rehearsal`. Nothing outward ever acts in it: each of `pr`, `merge`, `tag` and `mergeback` asks, a `no` skips it, and a `yes` fails with nothing sent. `demo` passes the cut commit to 11.18's hook, which accepts it only for a stand-in. The proof is a run from the cut to `demo` with 11.14's fixture gates and a fixture pass record: hermetic, with the fake host, and live, against 11.18's throwaway stand-in.

## Boundaries & Constraints

**Always:**
- **The conventions of 11.5 and 11.14 to 11.18 hold:**
  - Bash 3.2 and ASCII (Rule 14); `umask 077`; the main guard;
  - `PASS|FAIL|WAIT|SKIP|NOTE|STOPPED|REFUSED` lines; exit codes 0, 1, 2, 4 and 5 keep their meaning;
  - answers come only from stdin through `ask`; every detail goes through `step_fail`/`detail_clean`;
  - no environment value is printed (no `env`, `printenv`, `set -x` or `declare -p`);
  - never `docker push|login|save|export|pull`, and never a registry sign-in.
- **The kind is stored once.** `start --rehearsal` writes `mode=rehearsal` into the state with `sset`. A state with no `mode` key is a release state, so states written before this story load unchanged. From then on, in a rehearsal:
  - the branch is `rehearsal/<v>-rc<n>`, the record `release/records/<v>/rehearsal-rc<n>.md`, the draft notes `release/records/<v>/rehearsal-rc<n>-notes.md`, the state folder `<state root>/<v>-rehearsal-rc<n>` and the IPM artifact under that folder;
  - `next_rc` counts only `rehearsal/<v>-rc*` branches, local and on the remote;
  - the record's `## Release sequence` reads `Mode: rehearsal`;
  - `next`, `resume` and `status` take `--rehearsal`. Without it they see only release states; with it, only rehearsal states.
- **Every candidate name comes from `$branch`.** Every name that `release.sh` prints, records, compares or passes to a gate script, `gh` or the hook comes from the state's branch, never from a literal `release/` followed by `$`. Where 11.15's or 11.16's landed code builds one from a literal, this story changes that expression to `$branch`; that is the only edit to their lines. The one exception is the release-mode `--from` pattern (`release.sh:1823-1824`), which must stay `release/` (AC5). `notes` passes `--notes` with the kind's draft path, so a rehearsal draft never takes a real draft's name.
- **The rehearsal's guards** each print one `REFUSED` line, exit 2, and write or push nothing:
  - **At `start`:**
    - any remote of the checkout whose fetch or push URL (`git remote get-url --all` and `--push --all`, which apply `insteadOf`) is not an absolute local path, or `file://` plus one, to a bare repository (`git --git-dir=<path> rev-parse --is-bare-repository` prints `true`). The line names the remote by its name, never its URL;
    - `--from` (a rehearsal is cut from the integration branch) and `--record`.
  - **At `push`:** a state branch that is not `rehearsal/<v>-rc<n>`, which covers any `release/*` name (the pinned U-203 refusal), or a remote that is no longer a local bare repository.
- **Nothing goes out in a rehearsal.**
  - `pr`, `merge`, `tag` and `mergeback` each begin with one new line that hands a rehearsal to `rehearsal_outward <step>`. That function makes no `gh` call (read or write) and no `git push`, tag or merge. It prints its ASK. A `no` gives 11.16's `SKIP <step> declined by the author` with the row `declined`, and the sequence goes on. A `yes` gives the rehearsal FAIL (exit 1), and the next `next` asks the same question again. End of input gives 11.16's STOPPED (exit 4).
  - `demo` in a rehearsal needs no tag. When the hook is missing, it gives 11.16's SKIP. Otherwise it asks the stand-in question, and on `yes` calls the hook through 11.16's contract with `--ref <the cut sha>`, the rehearsal record and the rehearsal draft. The row follows 11.16's exit mapping unchanged.
  - The only pushes in a rehearsal are 11.5's two: the candidate branch and the record commit, both to the local bare remote.
- **The proof uses only fixtures.** 11.14's fixture gate scripts are used; a real gate cannot pass on a throwaway. The test writes a fixture `## Hands-on pass` in 11.15's form, with `Candidate: <v> rc<n>, rehearsal/<v>-rc<n> at <sha>`; the script never writes one. 11.18's fake host is used hermetically, and its stand-in live, both through `docker/tests/demo-standin/ssh-local.sh` (seam `OCUTALON_REHEARSAL_SSH`), with `DEMO_STANDIN=yes` in a temporary `release.conf` and `HOME`.
- **Extend, don't copy (Rule 2):**
  - `candidate_branch`, `record_path`, `notes_path`, `next_rc`, `release_state_dir` and `ipm_artifact_path` (`lib-release.sh`), and `earlier_hands` (`release.sh`), each take an optional last argument (`rehearsal`), and with no argument their output stays byte-identical;
  - 11.14's `newcase`, `rs`, `to_step`, `run_steps` and `gh_runs`; 11.15's `hands_put`; 11.16's `outward_word`, `step_demo` and `to_outward`; 11.18's `make-repo.sh`, `ssh-local.sh`, `fake-ocutalon-demo.sh`, `ocutalon-demo.sh` and lib-live's lock and name helpers are all reused.
- **Tests run in throwaways only:** throwaway repositories with local bare remotes, the self-test's shims and its `gh` shim, a temporary `release.conf`, `HOME` and state root. Live parts use lane D's lock folder and port, one throwaway at a time.

**Never:**
- **Never act outward, in the plan, the code or any test.**
  - No pull request, no push to origin (a rehearsal branch never goes to origin: U-203), no tag pushed outside a throwaway, and no publishing.
  - Never touch the real online demo host, its SSH address or key, or its update endpoint, and open no SSH connection. Never read the author's real `release.conf` or `~/.ssh`. Never run the real release sequence.
  - No real model key, Telegram bot, public IPM install, image push or registry sign-in.
- Let any option, variable or configuration key answer an ASK, skip a gate, write a hands-on pass, or let a rehearsal record carry a pass over to a real candidate (REL-7).
- Have the script delete or touch a branch on origin, or contact origin in a rehearsal.
- **Edit Epic 0's contended lines (Story 0.15):**
  - `release/release.sh`'s `Needs bash` header line (~48 before 11.15 and 11.16) and `step_image` (~575);
  - `docker/tests/test-release-sequence.sh` lines ~200, ~511, ~1032 and ~2908;
  - `release/upgrade-harness.sh`, `ci/warm.sh`, `ci/iris.sh`, `docker/tests/lib-live.sh` (read-only) and `docker/tests/test-ci-changes.sh`.
- Edit Epic 29's files, `.github/workflows/*`, the rc1 merge gate (`git ls-remote --heads origin release/1.0.0-rc1`) or any dependency statement. Add `rehearsal/*` to any workflow trigger.
- Reformat existing lines; the Contest Planner reviews every `release/**` hunk before merge. Add anything to the hosted `checks` job (CHECK_SCRIPTS, or a default rule of `test-release-sequence.sh`). Commit draft notes. Write a host, address, `host:port` or a URL with a literal host into a new line.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Rehearsal start | `start --version <v> --rehearsal`; every remote is a local bare repository | `START <v> rc1 ...`; state `<v>-rehearsal-rc1` with `mode=rehearsal`; later the cut makes `rehearsal/<v>-rc1` and the record `rehearsal-rc1.md` with `Mode: rehearsal` | -- |
| Start guards | a remote whose URL or push URL is a network URL (configured, never contacted); a non-bare local path; `--from <any>`; `--record <f>` | REFUSED with its line, exit 2 | no state, branch or record is written |
| Push guard | a rehearsal state whose `branch` resolves to `release/<v>-rc1` (planted), or whose remote was re-pointed to a network URL | REFUSED with the U-203 or the remote line at `push`, exit 2 | the bare remote is unchanged; no ASK |
| Full rehearsal | fixture gates; fixture pass written by the test after the stop; host = fake (hermetic) or live stand-in | push ASK `yes` pushes the branch; every gate writes its row; `hands-on` stops (4); `resume` refused (2) until the pass exists; then P1; `pr`, `merge`, `tag`, `mergeback` each ASK and are declined (SKIP, `declined`); `demo` ASKs the stand-in question, the hook gets `--ref <cut sha>`, the row is `not updated` with the stand-in line; end text 11.16's not-a-release text | -- |
| `yes` at an outward step | rehearsal at `pr`, `merge`, `tag` or `mergeback`; answer `yes` | the rehearsal FAIL, exit 1, record `failed at <step>: ...`; no `gh` call of any kind and no ref change on the remote; the next `next` asks the same step again | -- |
| Hook refuses | a rehearsal with no `DEMO_STANDIN=yes` in `release.conf` | 11.16's `FAIL demo release/demo-update.sh exited 2: refused: a rehearsal updates only a stand-in demo host (DEMO_STANDIN=yes)` | no host contacted |
| No carry-over | after a full rehearsal with its pass: a real `start --version <v>` in the same repository; `--from rehearsal/<v>-rc1` | the real candidate is `release/<v>-rc1` with `rc1.md`; at `hands-on`, `resume` gives 11.15's R1 (the rehearsal's pass is not seen); `--from rehearsal/...` is refused by `release.sh:1823-1824` | nothing written by a refusal |
| Separate sums | `rehearsal-rc1.md` and `rc1.md` of one version, each with a `Hands-on time:` | the real record's earlier-candidates sum excludes the rehearsal's seconds; the rehearsal rc2's sum covers only `rehearsal-rc*.md` | -- |

</intent-contract>

## Code Map

**Preconditions (the implement stage HALTs `blocked`, `missing prerequisite story`, naming what is missing):**
- **Stories 11.15, 11.16 and 11.18 (part A) are merged into OCT-epic11.** This means:
  - `STEPS` ends `... hands-on pr merge tag mergeback demo`;
  - `step_hands_on` reads `## Hands-on pass`;
  - `outward_word`, `step_pr`, `step_merge`, `step_tag`, `step_mergeback` and `step_demo` exist, and the self-test has `hands_put` and `to_outward`;
  - `release/demo-update.sh` accepts `Mode: rehearsal` with a commit ref, and `docker/tests/demo-standin/` exists.
- **Epic 0's Story 0.15 is integrated forward first.** 11.18's stand-in builds the root `Dockerfile`.
- Every `release.sh` line number below is as of `9ec1a96323642703713469fd82772e68951cfdae`. Re-anchor them by function name after the merges.

**`release/lib-release.sh`** (new lines and tiny extensions only):
- `:102` `release_state_dir`, `:111` `ipm_artifact_path`, `:359` `record_path`, `:361` `notes_path`, `:363` `candidate_branch` and `:379-391` `next_rc` each gain an optional last argument, `rehearsal`. With it, they give:
  - `<v>-rehearsal-rc<n>` for the state folder;
  - `rehearsal-rc<n>.md` and `rehearsal-rc<n>-notes.md` for the record and the notes;
  - `rehearsal/<v>-rc<n>` for the branch;
  - the `rehearsal/<v>-rc*` refs for `next_rc`.
- The header lines `:48-50` and the helpers' doc lines gain the argument.
- Consumers that pass nothing (`checklist.sh:584-585`, `notes.sh:548-550`, `rehearse.sh:883`, Story 15.3's reader) are unchanged. `t_libs` (`test-release-sequence.sh:3039-3041`) keeps its pins and gains the rehearsal forms in the new rule.

**`release/release.sh`** (the Planner reviews every hunk):
- **Header and usage:**
  - `:2` gains `[--rehearsal]` and `:3` gains `[--rehearsal]`.
  - The new header line 8 is the U-203 line (Public text).
  - `cli_usage` (`:1621-1623`) prints lines 2 to 8.
- **Mode and records:**
  - `:167` `earlier_hands <dir> <rc> [<prefix>]`: the glob and the strip use `rc` by default and `rehearsal-rc` in a rehearsal. Its callers (`record_render` `:232`, `cmd_status` `:1685`) pass the state's prefix.
  - `:227` `echo "Mode: release"` prints the state's mode.
- **`:1027` `step_push`:** the rehearsal push guard comes first, before any ASK.
- **`:1068-1071` `step_notes`:** passes `--notes "$notes"` (already computed at `:1070`), so the draft lands at the kind's path. `:1070` and `:1564` (`step_checklist`) call `notes_path` with the kind.
- **`:898`, `:972` and `:1689`:** the `ipm_artifact_path` calls (ipm, ipmcheck, status) pass the kind, so a rehearsal's artifact stays in its own state folder.
- **`:631-642` `load_state`:** it reads `mode` and calls the kind-aware helpers. `:644-677` `find_state` filters `*/state.env` by `mode` against `--rehearsal` (a missing key means release).
- **`:1747-1866` `cmd_start`:**
  - parses `--rehearsal`;
  - runs the remote guard, then the `--from` and `--record` refusals, before anything is written;
  - `sset mode`;
  - passes the kind to `next_rc` (`:1806`), the state-folder loop (`:1807`), `candidate_branch` (`:1817`), `record_path` (`:1832`) and `release_state_dir` (`:1839`).
  - The release-mode `--from` lines `:1821-1828` are unchanged.
- **`:1867-1906` `release_main`:** `--rehearsal` for `next|resume|status`.
- **New section `# --- rehearsal mode (Story 11.29) ---`** after 11.16's outward section:
  - `rehearsal_remote_ok <remote>`: the bare-repository check, used by `start` and `push`;
  - `rehearsal_outward <step>`: the ASK, the decline and the FAIL. It wraps 11.16's `outward_word` for the decline and the stop branches;
  - `rehearsal_demo`: the stand-in ASK, then 11.16's hook call with the cut sha as `--ref`.
- **In 11.16's steps:** one new first line in each of `step_pr`, `step_merge`, `step_tag` and `step_mergeback`, and one in `step_demo` before its tag check. Plus the `$branch` fixes from Boundaries, if any.
- **Already take `$branch`, not changed:** the gates at `:1071`, `:1232` (`ci_runs ... "$branch"`), `:1507` and `:1575`, and `step_hands_on` `:1615`.

**`docker/tests/test-release-sequence.sh`** (shared with 11.5 and 11.14 to 11.17; Epic 0's lines untouched):
- **The runner rule mechanism:**
  - New `runner_rule <name> <fn>` beside `rule` (`:150`). It runs only when named, so the default run, which `checks` runs, does not grow.
  - The header gains the runner-rule line and the three rule lines (Public text).
- **Full-tree seed:**
  - New `mkseed_full`, used only when `OCUTALON_TEST_DEMO_STANDIN` is set. It writes `$tmp/seed-full` from the full `git archive HEAD`, with `release/records` removed, overlaid with `$tmp/seed`'s files (`.git` excluded) and committed the way `mkseed` commits.
  - `newcase` `:792` then clones `${SEED:-$tmp/seed}`, which is a one-token change.
  - It is needed because the hermetic seed (`:727-729`) has no `src/` or root `Dockerfile`. The cut commits the shim's bundle (`release.sh:534-539`), so a full-tree cut commit builds.
- **New helpers:**
  - `to_step_rehearsal <step>`: `to_step` with `--rehearsal` on `start`, and `NEXT_ARGS` carrying `--rehearsal`;
  - `to_outward_rehearsal`: 11.16's `to_outward` with the same.
  - `rcand` resolves `rehearsal/1.0.0-rc<n>`, like `cand`.
- **New runner rules** (registered after `rule static`; they reuse `newcase`, `rs`, `gh_runs`/`gh_green`, `hands_put`, `snap`, `remote_refs` and `row_of`):
  - `rehearsalmode`: AC1, AC2, AC5, AC6 and the header/usage pin;
  - `rehearsalrun`: AC3, AC4, IA2 and IA3, hermetic with the fake host;
  - `demostep`: IA1.
- The rehearsal cases use `to_step`'s version, 1.0.0, so 11.14's fixtures fit. `rehearsal/1.0.0-rc1` is not the rc1 gate's `release/1.0.0-rc1`, and AC1 pins that the bare remote never holds a `release/*` ref.

**`docker/tests/test-demo-update.sh`** (11.18's unit `live:demo-update`):
- New `--part sequence` (hermetic, no Docker) runs `bash docker/tests/test-release-sequence.sh rehearsalmode`, then `rehearsalrun`, then `demostep` as one call, and passes only if all three pass.
- New `--part rehearsal` (live) runs:
  1. claim lane D's lock (lib-live), as 11.18's live parts do;
  2. `make-repo.sh` for 0.9.9, then the stand-in `init 0.9.9`;
  3. then, with `OCUTALON_TEST_DEMO_STANDIN=<login dir>`, the self-test's live rehearsal case: a full-tree case, `to_outward_rehearsal`, the four declines, and `demo` `yes` through the real hook, `ssh-local.sh` and the stand-in;
  4. then the stand-in's `status` (running and golden `1.0.0`) and its bundle (exactly `refs/heads/rehearsal/1.0.0-rc1` at the cut sha);
  5. then `down` and the lock release, also on failure.
- The header line changes (Public text).

**`ci/units.sh`** (Epic 11's own lines; 11.18's `live:demo-update)` arm of `group_input_pattern`):
- The arm also claims `release/release\.sh$` and `docker/tests/test-release-sequence\.sh$`, because the runner rules test them.
- CI runs `--part sequence` after 11.18's parts, the same way 11.18 runs its own parts. `--part rehearsal` joins only under the CI rule in Design Notes.
- `docker/tests/test-ci-config.sh` changes only if 11.18's pin lists the arm's paths.

**Read only:** `release/demo-update.sh` and `docker/tests/demo-standin/*` (11.18); `release/notes.sh:538-550`, `release/rehearse.sh:834`, `release/checklist.sh:584` (all take `--candidate`/`--record`/`--notes`); `docker/tests/lib-live.sh`; `ci/iris.sh` (`cmd_live` passes `--part` through; teardown by tag).

## Tasks & Acceptance

**Execution:**
- **Task 0** (measure before code, with lane D's values and tag `e11s29i`; the figures go into `## Verification`):
  1. Time `bash docker/tests/test-release-sequence.sh gates` and `handson` on the merged tree, to size `rehearsalrun`.
  2. With a full-tree seed, time `mkseed_full` plus a cut and push, and confirm that the cut commit's tree builds the root `Dockerfile` with `--pull=false`.
  3. Time 11.18's `--part hook` on the merged tree, to size `--part rehearsal`.
- `release/lib-release.sh` -- the kind argument on six helpers and their header lines -- the rehearsal names sit beside the real ones.
- `release/release.sh` -- the header and usage, `mode`, the guards, the kind-aware state, names and sums, `--notes`, the rehearsal section and the five one-line hand-offs -- rehearsal mode (U-203).
- `docker/tests/test-release-sequence.sh` -- `runner_rule`, `mkseed_full` and the `SEED` token, the helpers and the three runner rules; update every existing pin that the usage line 8 or a kind argument touches -- the proof.
- `docker/tests/test-demo-update.sh` -- `--part sequence` and `--part rehearsal`, and its header -- the unit.
- `ci/units.sh` -- the two claimed paths, and the CI order per Design Notes -- CI.

**Acceptance Criteria:**
- **AC1 (U-203 names; REL-1).** Given `start --version 1.0.0 --rehearsal` in a case whose remotes are local bare repositories, when the sequence cuts and pushes, then:
  - the branch is `rehearsal/1.0.0-rc1`, the record is `release/records/1.0.0/rehearsal-rc1.md`, and its `## Release sequence` reads `Mode: rehearsal`;
  - the state folder is `1.0.0-rehearsal-rc1`;
  - after every step of a full rehearsal, the bare remote holds no `refs/heads/release/*` and no `refs/tags/*` ref;
  - `next` without `--rehearsal` reports no sequence with steps left.
- **AC2 (U-203 refusals).** Given each row of the Matrix's "Start guards" and "Push guard" (a planted `release/1.0.0-rc1` branch in the state among them), when `start` or `push` runs, then each prints its REFUSED line and exits 2. No state, branch, record or remote ref changes (`snap` before and after), and no ASK is printed.
- **AC3 (the rehearsal proves the sequence; REL-1, REL-3, REL-7).** Given a rehearsal candidate, 11.14's fixture gates, the fake host through `ssh-local.sh` with `DEMO_STANDIN=yes`, and the seam clock, when the author runs the sequence with `next`/`resume --rehearsal`, then:
  - `push` asks and pushes `rehearsal/1.0.0-rc1` on `yes`;
  - every gate step writes its row from its real step;
  - `hands-on` stops (exit 4), and `resume` is refused (exit 2) until the test writes the fixture pass; then P1;
  - `pr`, `merge`, `tag` and `mergeback` each print their rehearsal ASK, and a `no` gives `SKIP <step> declined by the author` with the row `declined`;
  - `demo` asks the stand-in question; the hook's logged argv has `--ref <cut sha>`, the rehearsal record and the rehearsal draft; the copied bundle lists exactly `refs/heads/rehearsal/1.0.0-rc1` at the cut sha;
  - the `demo` row is `not updated` with `a stand-in demo host now runs 1.0.0; the online demo wasn't updated`;
  - the record holds the cut sha, every gate's row, the hook's `## Online demo update` section with `Mode: rehearsal`, the end text `stopped after demo: not merged and tagged (not a release)`, and `Hands-on time:` equal to the sum of every ASK window;
  - the `gh` shim log holds no `pr` or `api` call.

  Given the live stand-in (`--part rehearsal`), when the same run is driven from `to_outward_rehearsal`, then the stand-in builds from the copied bundle, and its `status` reads running and golden `1.0.0`.
- **AC4 (nothing goes out; REL-11).** Given a rehearsal at each of `pr`, `merge`, `tag` and `mergeback`, when the author answers `yes`, then:
  - the rehearsal FAIL line appears, with exit 1 and the record `Result: failed at <step>: ...`;
  - the `gh` shim log gains no line, and the bare remote's refs are unchanged;
  - the next `next` prints the same ASK.

  Given a rehearsal with no `DEMO_STANDIN=yes`, when `demo` gets `yes`, then the row is 11.16's FAIL with the hook's exit-2 line, and the transport log is empty.
- **AC5 (no carry-over; REL-7).** Given a full rehearsal with its fixture pass, when a real candidate is started in the same repository, then:
  - `start --version 1.0.0` cuts `release/1.0.0-rc1` with `rc1.md` (rehearsal branches do not count);
  - at `hands-on`, `resume` gives 11.15's R1 for `release/1.0.0-rc1`;
  - `start --version 1.0.0 --from rehearsal/1.0.0-rc1` is refused, with nothing written.
- **AC6 (separate hands-on sums).** Given `rehearsal-rc1.md` and `rc1.md` of one version, each with a known `Hands-on time:`, when `rc2` of each kind renders its record, then each earlier-candidates sum counts only its own kind's records.
- **IA1 (consumer: 11.16's real `demo` step with 11.18's real hook).** Given the real `release.sh` at `demo` (`to_outward`, release mode, `v1.0.0` tagged on the merge commit by 11.16's shim run) and the fake host, when `yes` is answered, then:
  - `updated` gives the row `updated`, and `scheduled` gives `scheduled` with `<at>`;
  - no `release.conf`, or a stand-in, gives `not updated` with the hook's last line;
  - a refused `update` gives `FAIL demo release/demo-update.sh exited 1: the demo host did not update: <line>`.

  In the rehearsal, the same step gives AC3's row.
- **IA2 (consumes 11.15's real gate).** Given AC3's run, then the stop, the refusal and the pass are 11.15's STOPPED, NOTE, R1 and P1 lines, each naming `rehearsal/1.0.0-rc1`.
- **IA3 (consumes 11.14's real gate steps).** Given AC3's run, then each gate row comes from 11.14's real step with the fixture scripts. The `ci` gate's logged `gh run list` names `--branch rehearsal/1.0.0-rc1`, and no logged argument of any gate script or `gh` call holds `release/1.0.0`.
- **AC7 (static, inside `rehearsalmode`).** Given the tree, when the rule's scans run, then:
  - `release.sh` holds no `release/` directly followed by `$` outside comments and the `--from` lines;
  - header line 8 and `cli_usage`'s output hold the U-203 line;
  - `.github/workflows/*.yml` hold no `rehearsal/`;
  - the new lines are ASCII.
- **Standing (Rule 19).** Given a fresh environment, when the tests added or changed run in either order, then every one passes.

## Spec Change Log

- **planner-2026-11-09-11.29-text** (the Contest Planner [3dd56e], relayed by the orchestrator, 2026-11-09): the `### Public text` is APPROVED as written; its non-blocking clarifications follow the plan's recommended answers.
- **parked: owner re-plan 2026-11-09** (the owner, via the Contest Planner and the orchestrator): parked until after voting week. Do not implement; the approved text stays on file here.

## Review Triage Log

## Design Notes

**Consumes (Rule 2; every Integration AC runs the real consumer, never a mock of it):**
- 11.14: the gate steps, `ci_runs`/`gh_repo`, `to_step` and the fixture gates (IA3);
- 11.15: `step_hands_on`, the record form and `hands_put` (IA2, AC5);
- 11.16: `outward_word`, `step_demo` and the hook contract, `to_outward` and the gh shim (IA1, AC3, AC4);
- 11.18 part A: `release/demo-update.sh` with `Mode: rehearsal`, the fake host, `ssh-local.sh`, the stand-in and `make-repo.sh` (AC3, IA1);
- 11.5: the cut, the push, `ask`, the state and `stop_routine`; lib-live's lock helpers.

**Consumed-by:** the Contest Planner's daily releases, through the proved sequence. 11.18's Consumed-by already names this story.

**Integration ACs (Rule 1):** IA1 to IA3.

**Extend, don't copy (Rule 2):** as Boundaries lists. The new functions `rehearsal_outward`, `rehearsal_demo` and `rehearsal_remote_ok` wrap 11.16's `outward_word` and hook call, and 11.5's remote reads. `to_step_rehearsal` and `to_outward_rehearsal` wrap 11.14's and 11.16's helpers. `mkseed_full` overlays `mkseed`'s output instead of repeating its stub lines. No copy is planned.

**Governing ADs (Rule 6):**
- **AD-29:** `release/` is Lane A's, and Epic 11 may change either lane's files. The step epics' merge gate keys on `release/1.0.0-rc1`, which a rehearsal never creates (AC1).
- **AD-25:** the update hook interface. A rehearsal reaches only a stand-in.
- **AD-22:** throwaways only, no registry, and the CI unit.
- **AD-19:** configuration outside the repository; no value printed.
- **AD-23:** the stand-in's image comes from the bundle's tree through the root `Dockerfile`.
- No AC contradicts an AD.

**Already met (re-checked against the current specs and code; not rebuilt, pinned):**
- A release-mode `--from` accepts only `release/<v>-rc<m>` (`release.sh:1821-1824`; AC5).
- `--integration` refuses `rehearsal/*` (`:1783`).
- The real hands-on sums skip rehearsal records: `earlier_hands` globs `rc*.md` (`:169`).
- No workflow runs on a `rehearsal/*` push (AC7).
- The gates take the candidate from `$branch` (`:1071`, `:1232`, `:1507`, `:1575`, `:1615`).
- 11.18's hook already accepts `Mode: rehearsal` with a commit ref and `DEMO_STANDIN=yes`, and refuses a rehearsal record whose branch is `release/*`.
- 11.15's R8 already requires the source record's `Mode: release` (its own `carryover` rule pins it). With separate record names, a rehearsal record cannot be a `--from` source at all.

**Re-checked against the two-half plan (`set-aside/...-parts-A-B.reference.md`, part B):**
- **Changed: outward steps.** Each of `pr`, `merge`, `tag` and `mergeback` asks in a rehearsal, with no `gh` call. The reference declined `pr` and let 11.16's "earlier step did not happen" rule SKIP the other three. See Decided 2.
- **Changed: `notes` and the IPM artifact** take the kind. The reference missed both: `step_notes` relied on `notes_path`'s default (`:1070-1071`), and `ipm_artifact_path` would have written into the real state folder.
- **Changed: the live part.** It starts from `to_outward_rehearsal` in a full-tree case. The hermetic seed cannot build the root `Dockerfile` (no `src/`), and the gates are proved hermetically by `rehearsalrun`.
- **Changed: where the rules run.** The runner rules run in 11.18's unit through a new `--part sequence`, because 11.18's `--part fake` is its own.
- **Unchanged:** the names, the guards, the U-203 line, the "rehearsal FAIL on `yes`", and the hands-on prefix.

**Decided in-stage (small, reversible, within intent):**
1. **"Before the real 1.0.0 cut" means "before the first daily release cut through the scripted sequence".** 1.0.0 to 1.0.4 were cut by hand (`release/records/1.0.0/rc4.md`), so the criterion's timing and its "Epic 38 runs the real 1.0.0 cut through it" are history. What it promises is unchanged: a proved sequence before any real cut through it. No test can observe the timing. The lead may record the wording as a Rule 5 apply-and-report amendment.
2. **All four outward steps ask in a rehearsal**, and the author declines each. This is the criterion's literal text ("declines the release pull request, the merge, the tag and the merge back"), where 11.16's Decided 2 had expected only `pr` to be asked. It also means a rehearsal makes no `gh` call after the gates, so no read reaches a real repository through the `gh` seam.
3. **`yes` at an outward step in a rehearsal FAILs, and nothing goes out.** That is stricter than a decline, never looser, and the step is asked again.
4. **The rehearsal's names sit beside the real ones** (`rehearsal-rc<n>.md`, `<v>-rehearsal-rc<n>`), so no real path, sum, rc number, state pick or IPM artifact sees them.
5. **Every remote must be a local bare repository at `start`,** not just the chosen one. A rehearsal therefore runs in a scratch clone, never in the author's own checkout with its public origin.
6. **The end text stays 11.16's** not-a-release text. `Mode: rehearsal` marks the record.
7. **Tests use version 1.0.0**, as 11.14's `to_step` and fixtures do. `rehearsal/1.0.0-rc1` never matches the rc1 gate's `release/1.0.0-rc1`, and AC1 pins it.
8. **Naming.** The clean-machine gate is also called `rehearsal` (`step_rehearsal`, its `Mode: rehearsal` in `## Clean-machine rehearsal`). The new code uses `rehearsal_outward`, `rehearsal_demo` and `rehearsal_remote_ok`, which collide with nothing (`rehearsal_end` exists). The sequence's mode is read only from `## Release sequence`.

**CI (REL-4; owner-fixed 35 minutes a group):**
- Nothing joins `checks`. The new rules are runner-only, and `release-sequence`'s default run is unchanged.
- `--part sequence` joins `live:demo-update` in `production`. The estimate is 2-4 min on the runner (inference: the three rules about 60-120 s locally, times the 2.4-3.9 runner factor in Rule 21).
- `--part rehearsal` joins CI only if `production`'s projected time stays at or under 33 min. The projection is the first measured `production` group time after 11.18 lands, plus `sequence` and `rehearsal`'s local seconds times 3.9. Otherwise it stays out of CI, the stage runs it locally, and the Auto Run Result and a PLANNER REPORT line say so. A projection over 35 min for `sequence` alone goes to the Planner, and the unit is never moved silently.
- Claiming `release/release.sh` means a change to it now runs `production` (inference: about 30 min of runner time per such push).

**Ledger (Rule 17):** the inbox is empty, and no entry is owned.

**Contended paths and footprint:**
- Epic 0's lines are listed in Never. This story's hunks in `release.sh` are elsewhere, at the header lines 2, 3 and 8 and in functions, and the `test-release-sequence.sh` hunks are new functions, the `newcase` token and the rule list.
- **`footprint_extensions`:** none beyond 11.18's (`docker/tests/test-demo-update.sh` and `ci/units.sh` are already extended by it).

**PLANNER REPORT (cannot be proved without acting outward; nothing is built around it):**
- A rehearsal against the author's real checkout and real `gh`: the remote guard refuses it by design. The author's own rehearsal runs in a scratch clone whose remotes are local bare repositories.
- The real gates (CI on GitHub, the real-model evaluation, the clean-machine rehearsal on a fresh droplet) cannot pass on a rehearsal branch that never reaches origin. The rehearsal proves the sequence's control flow with fixture gates. The first daily release cut through the scripted sequence is the real end-to-end run, by the Contest Planner, with the author's word.
- The real demo host's leg: 11.18's PLANNER REPORT.

**The implement stage runs only after 11.15, 11.16 and 11.18 part A have landed** (Code Map preconditions). The spec is planned against their specs' contracts: 11.15 approved, 11.16 text under review, 11.18 part A just planned. If a landed contract differs from those specs, the implement stage HALTs as an intent gap, and does not adapt silently.

### Public text

New or changed, for the lead's veto ruling (product default 3). None names a host, address or rival entrant.

**`release/release.sh`:**
- Usage line 2: `# release/release.sh start --version <x.y.z> [--from release/<v>-rc<m> --pick <sha>...] [--integration <branch>] [--remote <name>] [--record <file>] [--rc <n>] [--rehearsal]`
- Usage line 3: `# release/release.sh next|resume|status [--version <v> --rc <n>] [--rehearsal]   (required when more than one state has steps left)`
- Header and usage line 8 (U-203): `# --rehearsal cuts rehearsal/<v>-rc<n>, never a release/* branch, and works only against local bare repositories; it never goes to origin (U-203). A rehearsal branch accidentally pushed to origin is deleted when the rehearsal ends, by the author or the Contest Planner; this script never contacts origin in a rehearsal.`
- **REFUSED:**
  - `REFUSED a rehearsal never uses a release/* branch: <name>; rehearsal candidates are rehearsal/<v>-rc<n> (U-203)`
  - `REFUSED a rehearsal works only against local bare repositories; remote <name> is not one`
  - `REFUSED a rehearsal candidate is cut from the integration branch; --from is not taken`
  - `REFUSED a rehearsal's record is release/records/<v>/rehearsal-rc<n>.md; --record is not taken`
- **ASK:**
  - `ASK <step> Rehearsal of rehearsal/<v>-rc<n> (<short>): <action>? A rehearsal never acts outward, so a yes fails and nothing goes out [yes/no]`
  - The `<action>` is:
    - `pr`: `open the release pull request into main`
    - `merge`: `merge the release pull request into main`
    - `tag`: `tag v<v> and push the tag`
    - `mergeback`: `merge main back into <int> and push it`
  - `ASK demo Update the stand-in demo host to <v> from rehearsal/<v>-rc<n> (<short>)? [yes/no]`
- **FAIL** (row `fail`): `FAIL <step> a rehearsal never opens the release pull request, merges, tags or merges back; nothing went out`
- **Reused unchanged:** 11.16's `SKIP <step> declined by the author`, STOPPED, its demo PASS/SKIP/FAIL lines and end texts; 11.15's lines (with `$branch`).
- **Record:**
  - `## Release sequence` `Mode: rehearsal`;
  - `Result:` reads 11.16's `stopped after demo: not merged and tagged (not a release)`, or `failed at <step>: a rehearsal never opens the release pull request, merges, tags or merges back; nothing went out`, or the existing stop texts.

**`docker/tests/test-release-sequence.sh` header:**
- `runner rules run only when named; live:demo-update (docker/tests/test-demo-update.sh --part sequence) runs them on the IRIS runner`
- `rehearsalmode (Story 11.29, AC1, AC2, AC5 to AC7) rehearsal names, the U-203 refusals, no carry-over to a real candidate, separate hands-on sums, the header's U-203 line`
- `rehearsalrun  (Story 11.29, AC3, AC4, IA2, IA3) a rehearsal from the cut to demo: fixture gates, the hands-on stop and a fixture pass, each outward step declined, the hook with the cut commit; a yes sends nothing`
- `demostep      (Story 11.29, IA1) the real demo step with the real update hook and the fake host`

**`docker/tests/test-demo-update.sh` header** (replaces 11.18's line): `# live:demo-update (Stories 11.18 and 11.29): the update hook release/demo-update.sh against a fake host (--part fake), a throwaway stand-in demo host (--part hook, --part schedule), the release sequence's rehearsal rules (--part sequence) and a rehearsal candidate's demo step against the stand-in (--part rehearsal); never a real host or SSH connection`

No README or docs line changes.

## Clarification Needed (non-blocking: the plan follows the recommended answer; for the lead's veto window)

1. **Public text (veto: public-facing text not already specified):** the lines above, in particular the U-203 header line. Deleting a branch on origin is owner-only, so the text says who deletes it, and that the script never does.
2. **Decided 2 differs from 11.16's Decided 2** (only `pr` asked). It follows the epics criterion's text. If the lead prefers 11.16's reading, the alternative is `pr` declined with `merge`, `tag` and `mergeback` SKIPping with no question. AC3's fourth bullet then changes, and nothing else does.
3. **Decided 1** (the 1.0.0 wording) may be recorded as a Rule 5 apply-and-report amendment of the criterion.

## Verification

**How to run:**
- Run each command in its own foreground call with `timeout: 600000`, from the worktree root, with `TMPDIR` in the stage's scratch folder and `ANTHROPIC_API_KEY` unset.
- **Each call must finish in about 150 s.** If a rule or part nears 120 s in Task 0 or later, split it:
  - `rehearsalrun` at the hands-on boundary into `rehearsalrun` (cut to P1) and `rehearsalend` (`to_outward_rehearsal` to `demo`), each self-contained;
  - otherwise by case, never by sharing state across calls.

  Record the new parts here.
- **Lane D values for every live call:**
  - `OCUTALON_LOCK_DIR=<coordination>/locks/lane-d`
  - `OCUTALON_TEST_WEB_PORT=52804`
  - `OCUTALON_LOCK_OWNER='epic=11 stage=<stage>'`
  - `OCUTALON_RUN_TAG` `e11s29i` (implement), `e11s29q` (QA) or `e11s29r` (review)
- At most one throwaway at a time. Never a slot, `ocutalon-aihub-test`, any `ocupilot*` container, `iris-community-edition` or another lane.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh rehearsalmode` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh rehearsalrun` -- expected: `PASS all rules`.
- `(loop)` `bash docker/tests/test-release-sequence.sh demostep` -- expected: `PASS all rules`.
- `(once)` `bash docker/tests/test-demo-update.sh --part sequence` -- expected: `PASS all`. If it nears 150 s, CI still runs it as one part (no 10-minute cap there), and the stage runs the three rules above instead.
- `(once)` `ci/iris.sh live demo-update --part rehearsal`, with the lane D values -- expected: AC3's live lines pass; no `ocutalon-demostandin-*` container, volume or image remains; the lock is released.
- `(once)` `ci/iris.sh teardown`, with the same tag -- expected: nothing left. Also run it after any failure.
- `(once)` The default batches that 11.16 records, one per call: `outward declines`, `merge demo`, `handson carryover static gate`, `secret word pushes`, `push record`, `hands resume notes`, `gates`, `ci eval`, `libs refusals cut` -- expected: `PASS all rules`, and the default run names no runner rule.
- `(once)` `bash docker/tests/test-release-notes.sh`, `test-release-checklist.sh` and `test-upgrade-harness.sh`, one per call -- expected: exit 0 (they source `lib-release.sh`).
- `(once)` `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh` and `bash ci/changes.sh ci.yml`, one per call -- expected: exit 0.
- `(once)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(once)` `git diff --stat` against the story base -- expected: no `.github/workflows/*`, no `release/records/`, no Epic 0 or Epic 29 file from Never, and no change to `_bmad/custom/epic-dependencies.yaml`.

**Mutations (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**

| AC | Mutation |
| --- | --- |
| AC1 | `candidate_branch` ignores the kind -> `rehearsalmode` |
| AC2 | drop the push guard's branch check -> `rehearsalmode` (the planted `release/1.0.0-rc1` is pushed) |
| AC3 | `rehearsal_demo` passes `v<v>` as `--ref` -> `rehearsalrun` |
| AC4 | `rehearsal_outward` calls 11.16's `step_pr` body on `yes` -> `rehearsalrun` (a `gh pr create` in the shim log) |
| AC5 | `next_rc` counts `rehearsal/*` in release mode -> `rehearsalmode` (the real candidate is not rc1) |
| AC6 | `earlier_hands` globs `*rc*.md` -> `rehearsalmode` |
| AC7 | put `release/$version-rc$rc` into `step_hands_on`'s STOPPED line -> `rehearsalmode` |
| IA1 | map exit 3 to the row `updated` -> `demostep` |
| IA2 | P1 compares against `release/$version-rc$rc` -> `rehearsalrun` |
| IA3 | `step_ci` passes `release/$version-rc$rc` to `ci_runs` -> `rehearsalrun` |

**Shared surfaces:**
- `lib-release.sh`'s six helper signatures (sourced by the harness, `rehearse.sh`, `checklist.sh`, `notes.sh`, Story 15.3 and their self-tests);
- `release.sh`'s usage lines 2, 3 and 8 and `cli_usage`'s range;
- the state folder names and the `mode` key;
- `find_state`'s pick;
- the `## Release sequence` `Mode:` line;
- the outward steps' first lines;
- `newcase`'s seed;
- `ci/units.sh`'s `live:demo-update` claims, read by `test-ci-config.sh` and `test-ci-changes.sh`.

Every test added or changed passes on a fresh environment, in either order. Each case builds and removes its own repositories, bare remotes, configuration, transport, stand-in project, volumes and images.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
