# Epic 11 Context: Release 1 ships: the demo path end to end, upgrade in place and a scripted release

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 11 makes a release one scripted, gated sequence. Part 1 is done: the demo path passes end to end, an upgrade and a restart keep every record, the rehearsal, checklist and draft-notes tools exist, and `release/release.sh` cuts and pushes a candidate. Releases 1.0.0 to 1.0.4 have been cut with it. The sequence stops after `notes` without running any gate ("no gate has run (not a release)"), so the Contest Planner has run the gates and every later step by hand. Part 2 finishes the sequence so that a release can't skip a gate or take an outward step without the author's word. It runs every gate on the pushed candidate, stops at the hands-on gate until a pass or carry-over is recorded, asks before the release pull request, the merge, the tag, the merge-back and the demo update, and proves the whole run on a rehearsal candidate against a stand-in demo host.

## Stories

- Story 11.14: The release sequence runs every gate on the pushed candidate
- Story 11.15: The hands-on gate stops the sequence, and its resume command waits for a pass or a carry-over
- Story 11.16: The sequence asks before each outward step after the gates
- Story 11.18: The update hook updates the online demo, and a rehearsal candidate proves the sequence
- (Done: 11.0 to 11.13, 11.17 and 11.19 to 11.28, which are part 1 and the fix-forwards)

## Requirements & Constraints

- **Gates (11.14).** The gates are: the full CI run, the release-candidate evaluation with the demo incident gate, the upgrade harness, the clean-machine rehearsal, the release checklist and the REL-7 hands-on pass.
  - Every gate must pass. Each result goes into the candidate's record, and the sequence stops naming the gate that failed.
  - The only override is REL-5's: the author's override of a blocked evaluation, with the reason shown in the notes.
  - The sequence refuses a candidate with an enabled production item that still answers "not implemented" (`Parameter STUB = 1`).
  - Never report a false pass. A gate that didn't run, or a CI run that wasn't found, is not a pass.
- **Hands-on gate (11.15).** The sequence stops and names the candidate to install. The Contest Planner records the pass in the record. The resume command refuses to continue until the record holds a pass or a carry-over for this candidate.
  - Time spent on the pass doesn't count toward the author's 15 minutes.
  - After 1.0.0, a feature's fresh pass runs on the first daily candidate that ships it. Other releases record a carry-over.
  - A re-cut from the passed candidate plus cherry-picked fixes, with no other changes, carries the pass over with the Planner's note. A re-cut from the integration head needs a fresh pass.
  - A rehearsal record never carries a pass over to a real candidate.
- **Outward steps (11.16).** The sequence asks separately before each of: the release pull request, the merge into `main`, the `v<version>` tag, the merge of `main` back into the integration branch, and the demo update. It never publishes the notes, the registry package or the listing.
  - The merge requires every required check to be green.
  - The repository has been public since 2026-10-31, and `main`'s branch protection was set on 2026-11-01. Its 12 required checks are `checks`, `web`, `install-macos`, the `iris` jobs, `standalone-bridge` and `evaluation`. The criterion's HTTP 403 private-repo fallback is no longer the live path.
  - DW-27: a fork pull request must not be able to merge without a demo-path run.
- **Update hook (11.18).**
  - It copies a `git bundle` of `v<version>` to the demo host over SSH, then calls `ocutalon-demo update <version>`.
  - That call answers `updated` (access restricted) or `scheduled` with the next reset time, which goes into the draft notes. A non-zero exit gives a one-line reason, which the sequence shows and records.
  - The hook then checks `ocutalon-demo status` (the JSON fields are fixed by AD-25).
  - With no demo host configured, it says so, and the notes say the demo wasn't updated.
  - It is tested only against a throwaway compose stand-in.
- **Rehearsal candidate (11.18).** It is named `rehearsal/<v>-rc<n>`, never `release/*`, and rehearsal mode refuses a `release/*` name (a test pins this). The branch goes only to a local bare remote, never to origin.
  - The header says that a rehearsal branch pushed to origin by accident is deleted when the rehearsal ends.
  - The run uses a fixture pass record. The author declines the PR, merge, tag and merge-back: a declined step is skipped and the run goes on. The hook bundles the rehearsal commit, because a rehearsal has no tag.
- **Release-wide rules.**
  - Nothing goes out without the author's word. No image push or registry sign-in.
  - Never print an environment value, and no key in IRIS, a log, a commit or the record.
  - Every call fits in 10 minutes: split long gates into one phase per call.
  - Tests use the CI mock and never a real key. The real-model evaluation is the author's.
  - The 1.0.0-specific wording in the criteria (the first-version refusal, the kit, Stories 38.1 and 38.3 on `release/1.0.0-rc1`) records the first cut. The sequence must now serve daily releases: minor for a feature, patch for fixes only.

## Technical Decisions

- **`release.sh` contract (as delivered).**
  - Commands are `start --version`, then `next`/`resume` (one step per call) and `status`.
  - `STEPS` is currently `cut image overview ipm ipmcheck push notes`. Part 2 inserts its steps into `STEPS`.
  - Exit codes: 0 step done or end of steps, 1 failed, 2 refused (nothing written), 4 stopped for the author's word, 5 the lane lock is busy.
  - An outward step prints `ASK <id> <question> [yes/no]` and reads one line. Only `yes` continues. End of input means exit 4, and no option or variable can answer for the author.
  - Hands-on time is the sum of the ASK windows. A WARN is printed above 900 s.
  - The state folder sits outside the repository.
  - `release.sh` is the only writer of the record's `## Release sequence` section. Other sections are written through `record_write` in `lib-release.sh`.
  - So far it makes exactly two pushes: the candidate branch and the integration-branch record commit. It never force-pushes, never pushes `main` and never pushes a tag.
  - It stages the record by explicit pathspec, `release/records/<v>/rc<n>.md` only, never the folder (DW-560). The draft notes stay uncommitted.
  - `umask 077`.
- **Gate tools (call them, don't reimplement them).**
  - **Rehearsal (DW-548):** `rehearse.sh run` needs `OCUTALON_RUN_TAG`. It runs one phase per call (install, then one timed run per call, then report and down) and exits 4 until the last phase. The options must match on every call. Exit codes: 0 is a real pass, 1 fail or not run, 2 refused, 3 dry run, 75 lock busy. Only exit 0 with `Result: pass` passes. Real mode needs at least 20 runs and a local driver, and a dry run is never a pass.
  - **Upgrade harness:** phases `build settings seed upgrade restart storage report down`, each run under `OCUTALON_RUN_TAG` within 540 s, then `RESULT pass|fail|not run`. Exit codes: 0, 1, 2, 75.
  - **Checklist:** only exit 0 with `Result: pass` passes. The author's confirmations come from the record's `## Author confirmations`.
  - **Evaluation:** `eval/run.sh --release-candidate` writes `eval/release-candidate.json` (`ocutalon.evalResult/1`, with the candidate's sha). Exit codes: 0 pass, 3 blocked, 4 key-like text found. `--override "<reason>"` is REL-5's override, and `--on-mock` runs the same sequence with no key.
  - **Notes:** `notes.sh` checks the evaluation result, the rehearsal section and the upgrade section for the candidate's full sha. This is why `notes` fails on 1.0.3 and 1.0.4 today: no gate ran.
- **Records.** A record is `release/records/<v>/rc<n>.md` on the integration branch: the commit SHA, each gate's result, the hands-on pass with its findings, fixes and deferrals, and the hands-on time. A candidate branch is never changed after its cut. A failed gate means a fix and a new `rc<n+1>`.
- **Demo host (AD-25).** The demo host is reached only over SSH, with its address and key in the author's configuration outside the repository. The host builds the image from the bundle, with no registry and no repository access, and refreshes the golden copy at a reset boundary. The update's restore is exempt from the version refusal. The demo host's deployment stays out of this repository.
- **Lanes (AD-29).** `release/` and its records belong to Lane A. Epic 11 may change either lane's files.

## Cross-Story Dependencies

- All four stories add steps to `release.sh`. 11.15 follows 11.14's gates, 11.16 follows 11.15, and 11.18 needs 11.14 to 11.16. The gates must run before `notes`, which reads their sections.
- 11.16 builds the web bundle into a separate folder and copies it in only at the cut (DW-532). Until 11.16 lands, the Planner untracks `src/ocutalon/csp/` by hand at each merge-back. It is untracked and gitignored on the integration branch today.
- Story 15.3 reads 11.17's IPM artifact record, which is unchanged. Epic 38 ran 1.0.0's gates by hand following this gate list.
- Prior work on 11.14 conflicted with today's `release.sh` and `docker/tests/test-release-sequence.sh`, and the story is being re-planned from the current code.
