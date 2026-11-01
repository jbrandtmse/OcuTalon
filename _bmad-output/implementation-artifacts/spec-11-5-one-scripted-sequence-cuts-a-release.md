---
title: 'Story 11.5: One scripted sequence cuts a release (the cut, the author''s word, the candidate''s push, the draft notes and the record; the gates, the hands-on gate, the later outward steps, the IPM artifact and the update hook are the proposed Stories 11.14 to 11.18)'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-3-the-clean-machine-rehearsal-installs-and-times-the-demo-path.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-13-the-release-gets-draft-notes.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing takes the integration branch to a release candidate. No script refuses a wrong first version, sets the version, commits the built web bundle on a `release/<v>-rc<n>` branch that never changes, checks the version inside the built image, asks the author before the push, or keeps the candidate's record on the integration branch. Every gate (11.2, 11.3 with 11.11 and 11.12, 11.4, 11.13) already defaults to `release/<v>-rc<n>` and `release/records/<v>/rc<n>.md` and waits on this cut.

**Approach:** Add `release/release.sh`, a resumable sequence of short steps: one step per call, with state kept outside the repository. One prompt mechanism takes the author's word, and the same mechanism clocks hands-on time. This story ships the steps from the start to the candidate's push, plus the draft-notes step and the record. The gates, the hands-on gate, the later outward steps, the IPM artifact and the update hook join the same step list in the proposed Stories 11.14 to 11.18 (see Design Notes, Proposed split).

This story takes four of epics.md Story 11.5's criteria, verbatim there:
- the first (the cut, with its two **And** clauses);
- the second (the first outward step);
- the seventh (no image push and no environment value);
- the eighth (hands-on time and the draft-notes step).

## Boundaries & Constraints

**Always:**
- **11.3's conventions:**
  - Bash 3.2 and ASCII only (Rule 14).
  - Mode 100755 and `umask 077`.
  - The main runs only when the script is executed (`[ "${BASH_SOURCE[0]}" != "$0" ] && return 0`), so the self-test can source it.
  - Output lines are `PASS|FAIL <step> <detail>`, then `RECORD <file>` and `RESULT <result>`.
- **Extend, don't copy (Rule 2).** Use these and don't redefine them:
  - from `release/lib-release.sh` (11.3, 11.4, 11.13): `record_path`, `record_write`, `notes_path` and `release_previous_tag`;
  - from `docker/tests/lib-upgrade.sh`: `stamp_version`;
  - from `docker/tests/lib-live.sh` (source only): `manifest_version` and `ensure_web_bundle`.
  - New shared helpers go into `lib-release.sh`.
- **The author's word.** Each outward step, and the 1.0.0 kit confirmation, prints `ASK <id> <question> [yes/no]` and reads one line from standard input.
  - Only `yes` proceeds. Any other line declines.
  - End of input means no answer: the script prints `STOPPED <id> waiting for the author's word` and exits 4.
  - No option, variable or configuration key answers a question in advance.
- **Hands-on time** is the sum of the ASK windows, each measured from printing the question to reading the answer, on one clock (`date -u +%s`).
  - The sum is kept in the state and written into the record at every stop.
  - Nothing else counts: no step's run time, no CI and no hands-on pass.
- **The cut never changes.** The script never moves, re-commits, force-pushes or deletes a `release/*` branch.
  - `<n>` is 1 more than the highest `release/<v>-rc*` found locally or on the remote.
  - A name that already exists is refused.
- **Pushes.** There are exactly two, each on the author's word:
  - `git push <remote> release/<v>-rc<n>`;
  - the integration branch, fast-forward only, carrying the record commit.
  - Never `--force`, a tag, `main`, `--all`, `--mirror` or any other ref.
- **The author's checkout is never switched.** The cut is made in a temporary clone inside the state folder. The only change to the author's checkout is the record commit on the integration branch, made with an explicit pathspec (`git add -- <record> && git commit -m ... -- <record>`).
- **No value is ever printed.**
  - Never `env`, `printenv`, `set -x` or `declare -p`.
  - `docker compose config` only with `--quiet`; `docker inspect` only with `--format`.
  - Never `docker push`, `login`, `save` or `export`.
  - The record names no local absolute path (`test-boundaries.sh`).
- **Tests use only throwaway repositories.**
  - Every remote is a local bare repository in the test's temporary folder.
  - `HOME`, `GIT_CONFIG_GLOBAL`, `XDG_STATE_HOME` and `OCUTALON_RELEASE_STATE` point inside that folder.
  - Before it runs anything, the test checks that no remote URL is a network URL, and stops if one is.
- **Every command fits one 10-minute call.** `next` runs one step. `cut` (clone, npm and build) and `image` (docker build) are separate steps, each measured in Task 0.

**Never:**
- Run `release/release.sh` in this worktree or in any real checkout, against the GitHub repository, or with any network remote. In this build it runs only in throwaway repositories (U1, the owner's word). A throwaway's local bare remote may still be named `origin`, the script's default remote name.
- Tag, open a pull request, merge, publish notes or anything else, read the GitHub API, sign in to or publish to a registry, or reach the demo host. Those steps belong to the siblings, and even there they run only on the author's word.
- Edit:
  - `src/module.xml` (the script stamps the candidate's copy at run time);
  - Epic 15's `release/ipm-install.sh`, `release/ipm/*` and `src/**/Install/**`;
  - `.github/workflows/*`, `README.md`, `docker/tests/test-readme.sh`, `docker/tests/lib-live.sh`, `docker/Dockerfile` and `.gitignore`.
- Commit or push the draft notes. They stay in the author's checkout, for the author to edit and publish.
- Write `release/records/` of the real tree from any test.
- Report `pass` for the release. This story's steps end with `Result: stopped after notes: no gate has run (not a release)`, so there is no false all-clear.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First release, right version | No `v*` tag locally or on the remote. `start --version 1.0.0`. The kit ASK is answered `yes`. | State created; `NEXT cut`; exit 0 | No error expected |
| First release, wrong version | No `v*` tag. `--version 1.1.0` (or `0.1.0`) | `REFUSED the first release is 1.0.0`, exit 2 | Nothing written: no state, branch or record |
| Version already tagged | Tag `v1.0.0` on the remote only, or locally only | `REFUSED v1.0.0 is already tagged`, exit 2 | Nothing written |
| Kit not confirmed | First release; the kit ASK is answered `no` or reaches end of input | `REFUSED the author did not confirm the 1.0.0 kit`, exit 2 | Nothing cut |
| Bad start state | Tracked changes, or untracked files outside `release/records/`; not on the integration branch; local integration differs from `<remote>/<integration>`; `--rc` is not the next number; `node`, `npm`, `docker` or `git` missing | One `REFUSED <reason>` line, exit 2 | Nothing written |
| The cut | `next` after start | `release/1.0.0-rc1` holds one cut commit on the integration head. Its `src/module.xml` reads 1.0.0. `src/ocutalon/csp/index.html` and the rest of the built bundle are committed (force-added). The integration branch's `module.xml` is unchanged. `PASS cut <sha>` | npm or a build failure gives `FAIL cut <reason>` and no branch |
| Re-cut from the integration head | rc1 exists (also when only on the remote) | The next cut is `release/1.0.0-rc2`; rc1's SHA is unchanged | An existing rc2 name gives exit 2 |
| Re-cut carrying fixes | `--from release/1.0.0-rc1 --pick <sha>...` (each pick an integration-branch commit) | rc2 is rc1, then the picks (`cherry-pick -x`, in order), then the cut commit. The record's `Cut from:` names rc1's SHA and each pick | A pick that is not on the integration branch, or a conflict, gives `FAIL cut` and no branch |
| Version inside the image | `next` after cut | Built from the candidate's tree: `/opt/ocutalon/version` = `1.0.0` and the bundle's `index.html` is present. `PASS image`; the check image is removed | A mismatch or a missing base image gives `FAIL image <reason>`; the sequence stops before the push ASK |
| Push on the author's word | ASK `push` answered `yes` | The remote has `release/1.0.0-rc1` at the cut SHA, and nothing else new except the record commit | A `no` or end of input gives `STOPPED push`, exit 4, and no push; a later `next` asks again |
| Record at every stop | Any stop: an unanswered ASK, a FAIL, or the end of the steps | The record is written and committed on the integration branch, then ASK `record`. `yes` pushes it fast-forward | `no` gives `committed, not pushed`. A rejected (moved) push gives `not pushed: <integration> moved on <remote>`, and the stop line says to bring the checkout up to date and resume |
| Draft notes | `next` after push | Runs `release/notes.sh --version 1.0.0 --rc 1 --candidate release/1.0.0-rc1 --record <record>`. The row carries its `RESULT` (draft, dry run or fail) and the draft's path. The draft stays uncommitted | notes.sh exit 2 (for example, a draft already exists) gives `FAIL notes <reason>`. It never passes `--replace` |
| Hands-on time | Every ASK, including `kit` and `record` | `Hands-on time:` gives this candidate's sum, and the sum for this version over its earlier `rc*.md` records | Over 900 s: the line says `over the 15-minute target` and the script prints `WARN`. It does not refuse |
| No value printed | A planted `OCUTALON_TEST_SECRET=zz-planted-value` is in the environment during a full run | The value appears in no output line, in no record and in no shim log; there is no `docker push` or `login` call | -- |

</intent-contract>

## Code Map

- `release/lib-release.sh` (Story 11.3; 11.4 adds `notes_path`, 11.13 adds `release_previous_tag`) -- the shared library this story extends:
  - `record_path <v> <rc>` gives `release/records/<v>/rc<n>.md`;
  - `record_write <file> <section> [<heading>]` replaces only its own `## ` section, writes through a temporary file and `mv`, and gives a new file the heading `# OcuTalon <v> rc<n>`;
  - `release_config_read` and `host_run` are not used here (11.18 uses them with `DEMO_` keys).
  - Not built yet. 11.5 implements after 11.3, 11.11, 11.12, 11.4 and 11.13.
- `release/upgrade-harness.sh` (Story 11.2, built):
  - header lines 2-35 are the CLI-header precedent;
  - `:43-45` sources `ci/iris.sh`, `lib-online.sh` and `lib-upgrade.sh` (the sourcing precedent);
  - `plan` is its no-container dry run, and needs `--version` equal to the checkout's `manifest_version`;
  - `--previous <ref>` overrides the tag search (`resolve_previous` `:75`). This is the consumer of IA2.
- `release/notes.sh` (Story 11.13, planned):
  - `--version --rc [--candidate (default release/<v>-rc<n>)] [--record] [--eval] [--notes] [--areas] [--replace]`;
  - exit 0 `draft`, 1 `fail`, 2 refusal (an existing draft without `--replace`), 3 `dry run`;
  - prints `NOTES <file>` and `RESULT`. This is the consumer of IA1.
- `release/rehearse.sh` (11.3/11.11) and `release/checklist.sh` (11.4) -- default `--candidate release/<v>-rc<n>`. The rehearsal refuses a candidate with no `src/ocutalon/csp/index.html`, which is why this cut commits the bundle. Both are 11.14's to call.
- `docker/tests/lib-upgrade.sh:28` -- `stamp_version <manifest> <version>` (awk, first `<Version>` only).
- `docker/tests/lib-live.sh` -- source only; contended with Epics 12 and 29:
  - `:159` `ensure_web_bundle` (`npm --prefix web ci` when `node_modules` is missing, then `npm --prefix web run build`; `LIVE_REBUILD_WEB=1` forces it);
  - `:587` `manifest_version`.
- `src/module.xml:6` (`<Version>0.1.0</Version>`) and `:12` (`FileCopy ocutalon/csp/` to `${dataDir}csp/ocutalon-web/`) -- read only. Epic 15 changes the file but not these lines.
- `.gitignore` -- `src/ocutalon/csp/` is ignored ("release branches force-add the built UI bundle"), so use `git add -f`.
- `web/package.json:13` (`build`) and `web/angular.json` (output `../src/ocutalon/csp`) -- what `ensure_web_bundle` runs.
- `docker/Dockerfile:17-24` -- writes `/opt/ocutalon/version` from the first `<Version>`, and fails without `src/ocutalon/csp/index.html`.
- `.dockerignore` -- an allow-list (`src`, `docker/...`), so building from the clone's root is the same as building from a checkout.
- `docker/tests/test-compose-start.sh:279` -- precedent for `docker run --rm --entrypoint cat <image> /opt/ocutalon/version`.
- `docker/tests/lib-stub.sh` (`curl_shim`) -- precedent for a PATH shim that logs its calls. Its header says it must never be sourced with `lib-live.sh`, so the self-test writes its own `npm`, `node` and `docker` shims.
- `ci/units.sh:6` `CHECK_SCRIPTS` -- one flat line. Epics 12, 13 and 15 also append to it (a plain union).
- `docker/tests/test-ci-config.sh:629-652` (`units_violations`) -- every `docker/tests/test-*.sh` must be in exactly one list. No count is pinned.
- `ci/units.sh:150` `NOT_IRIS_INPUT_PATTERN` -- already covers `release/` and `docker/tests/test-*.sh`, so no IRIS group runs for this change.
- Spec 11.4 `no-outward` row -- `release/*.sh` must not contain `gh release`, `gh repo edit`, `--visibility`, or a public-site name.
- `docker/tests/test-boundaries.sh` -- refuses local absolute paths in committed files.

## Tasks & Acceptance

**Execution:**
- Precondition -- Stories 11.3, 11.4 and 11.13 are merged into this branch, so `release/lib-release.sh` (with `notes_path` and `release_previous_tag`) and `release/notes.sh` exist. If they are not, implement HALTs `blocked` with `missing prerequisite story` and names the missing ones.
- Task 0 (measure, figures into `## Verification`) -- in a scratch throwaway clone of this worktree's HEAD (never the worktree), time each of these:
  - `git clone --shared`, then `ensure_web_bundle` with `LIVE_REBUILD_WEB=1`;
  - `docker build -f docker/Dockerfile` of that tree, then the `docker run ... cat /opt/ocutalon/version` read.
  - If clone, `npm ci` and build together exceed about 6 minutes, the cut reuses the author checkout's `web/node_modules` (symlinked into the clone) when `web/package-lock.json` is byte-identical. That is decided now; record it under Spec Change Log only if it is used.
- `release/lib-release.sh` -- add these and use them everywhere instead of inline copies:
  - `candidate_branch <v> <rc>` gives `release/<v>-rc<n>`;
  - `release_tags <remote>` gives the `v*` tags, local and remote (`git ls-remote --tags`);
  - `next_rc <v> <remote>` gives 1 plus the highest rc found locally or on the remote.
  - Keep every existing function's behaviour, and keep its consumers' self-tests green.
- `release/release.sh` -- new. Header CLI as in Design Notes. Commands `start`, `next`, `resume` and `status`; steps `cut`, `image`, `push` and `notes`; the stop routine writes the record, commits it and runs ASK `record`; the step list is extensible (Design Notes). Exit codes: 0 a step done, or the end of the steps; 1 a step failed; 2 a refusal with nothing written; 4 stopped for the author's word.
- `docker/tests/test-release-sequence.sh` -- new, hermetic, mode 100755.
  - It builds a throwaway repository from `git archive HEAD` of the real tree: one commit on `feature/OCT_OcuTalon_MVP`, with `origin` a local bare repository.
  - It uses shimmed `npm`/`node` (the build writes a fake bundle with `index.html`) and a shimmed `docker` (`build` logs its context; `run ... cat /opt/ocutalon/version` echoes the context's first `<Version>`; a flag file makes it lie; it logs every call).
  - It has a clock seam and answers on stdin.
  - It covers every Matrix row, plus IA1 and IA2.
  - `--live` (never in CI) does the same with the real npm and docker build (IA3), and removes its image tag and folders. It runs in its own call. If Task 0's figures put it over about 8 minutes, it splits into `--live cut` and `--live image`, one per call, sharing the throwaway folder.
- `ci/units.sh` -- append `release-sequence` to the end of `CHECK_SCRIPTS` and change nothing else. Then re-run `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml`.

**Acceptance Criteria:**
- AC1 (refusals; REL-3, REL-9, as amended 2026-10-31):
  - **Given** a throwaway repository with no `v*` tag, **when** the author runs `start --version 1.1.0`, **then** the script exits 2 with `REFUSED the first release is 1.0.0`, and creates no state, branch or record.
  - **Given** a remote with `v1.0.0`, **when** `start --version 1.0.0` runs, **then** it refuses because the version is already tagged.
  - **Given** the kit ASK answered `no`, **when** `start --version 1.0.0` runs, **then** it refuses and nothing is cut.
- AC2 (the cut; REL-1, REL-7, AD-23): **Given** a confirmed start, **when** `next` runs the cut, **then**:
  - `release/1.0.0-rc1` is the integration head plus one commit that sets `src/module.xml` to 1.0.0 and adds the built bundle (`src/ocutalon/csp/index.html` and the rest);
  - the integration branch's `module.xml` is unchanged;
  - a second start cuts `rc2` without moving rc1, from the integration head or, with `--from release/1.0.0-rc1 --pick <sha>`, from rc1 plus the pick and a new cut commit;
  - the record's `Candidate:` and `Cut from:` lines name the version and the full SHAs.
- AC3 (the version inside the image; AD-23): **Given** the cut, **when** `next` runs `image`, **then**:
  - the image built from the candidate's tree reports `1.0.0` in `/opt/ocutalon/version` and holds the bundle, so a Docker install needs no Node.js;
  - with the shim reporting `0.1.0`, `FAIL image` stops the sequence before any push ASK.
- AC4 (the record; REL-1, REL-3, REL-7): **Given** any stop, **when** the stop routine runs, **then** `release/records/1.0.0/rc1.md` on the integration branch holds the `## Release sequence` section as in Design Notes, committed with only that path. Its lines are:
  - the candidate's full SHA;
  - one row per step run so far;
  - the hands-on time.
- AC5 (the first outward step; REL-1, REL-11): **Given** the cut, **when** the sequence reaches `push`, **then** it asks. `yes` pushes only the candidate branch. After a run that answers `yes` to every ASK, the bare remote's refs differ from before only by the new candidate branch and the integration branch's record commits: no tag, no `main` and nothing else. **Given** the push ASK answered `no` or reaching end of input, **when** the step ends, **then** the remote is unchanged, the script exits 4, and the next `next` asks again.
- AC6 (CON-1, NFR-11, AD-22): **Given** a full run with the planted variable in the environment, **when** the run ends, **then**:
  - the planted value is absent from every output line, the record and every shim log;
  - the docker shim saw no `push` or `login`;
  - a scan of `release/release.sh` and `release/lib-release.sh` finds no `docker push|login|save|export`, `printenv`, `set -x`, `declare -p`, `docker compose config` without `--quiet`, or `docker inspect` without `--format`;
  - a planted line in a copy of the script fails the scan with `file:line`.
- AC7 (REL-3, REL-8): **Given** a run whose ASKs are answered at known clock seam times, **when** it stops, **then** `Hands-on time:` equals the sum of the ASK windows for this candidate, plus the version's sum over the earlier candidate records. A planted 901 s window prints `WARN` and `over the 15-minute target`. The step list includes `notes`, which runs Story 11.13's generator.
- AC8 (resumable; Rule 18 (5)): **Given** a stop at any step, **when** `next` or `resume` runs again, **then** it continues at that step and never repeats a finished step. `status` prints `STATE 1.0.0 rc1 next <step>`, `RECORD <file>` and the hands-on time, and changes nothing.
- IA1 (Rule 1, a real consumer): **Given** the cut and pushed `release/1.0.0-rc1`, **when** the `notes` step runs the real `release/notes.sh`, **then** the record's notes row carries the `RESULT` and `NOTES` path that notes.sh printed, and, when notes.sh printed a `NOTES` path, that draft (at `notes_path 1.0.0 1`) is untracked in the checkout and in no commit.
- IA2 (Rule 1, a real gate reads the cut): **Given** the record this story wrote, **when** the real `release/upgrade-harness.sh plan --version 1.0.0 --rc 1 --previous <integration base sha> --record <that record>` runs from a clone checked out at `release/1.0.0-rc1`, **then**:
  - it accepts the candidate's stamped version;
  - it adds `## Upgrade harness` to the same file;
  - `## Release sequence` stays byte-identical;
  - `release.sh status` still reads it.
- IA3 (once, `--live`): **Given** the real Dockerfile, **when** the `image` step builds a throwaway candidate, **then** `/opt/ocutalon/version` reads `1.0.0` as the cut stamped it, and the check image is gone afterwards.
- Standing: every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- **AD-23:** the version lives in `src/module.xml`; the web bundle is built by Node only in CI and development and committed on the release branch; release steps check the version inside the built image.
- **AD-29:** `release/` and `release/records/<version>/` are Lane A's.
- **AD-22:** no registry, push or sign-in; `--quiet` and `--format` only; throwaways.
- For the siblings: **AD-25** (the update hook), **AD-5** (the storage diff against the highest `v*` tag) and **AD-29's** `STUB = 1` check (11.14).
- No AC contradicts an AD's Rule.

**CLI header (golden):**
```
# release/release.sh start --version <x.y.z> [--from release/<v>-rc<m> --pick <sha>...] [--integration <branch>] [--remote <name>] [--record <file>]
# release/release.sh next|resume|status [--version <v> --rc <n>]   (required when more than one state has steps left)
# Steps, in order: cut, image, push, notes  (Stories 11.14-11.18 insert their steps into STEPS)
# Exit: 0 step done / end of steps, 1 a step failed, 2 refused (nothing written), 4 stopped for the author's word
# State: ${OCUTALON_RELEASE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/ocutalon/release}/<v>-rc<n>/
# Test seam: OCUTALON_RELEASE_NOW names a file of epoch seconds read one per clock read (unset: date -u +%s)
```
- The defaults are `--integration feature/OCT_OcuTalon_MVP` and `--remote origin`. `--record` defaults to `record_path <v> <rc>` in the author's checkout.
- The step list is one ordered `STEPS` variable, with one `step_<name>` function per step. A sibling adds a step by adding its name and its function.

**Record section (golden; `record_write` keeps the other `## ` sections):**
```
## Release sequence
Result: stopped after notes: no gate has run (not a release)
Mode: release
Candidate: 1.0.0 rc1, release/1.0.0-rc1 at <40-hex sha>
Cut from: feature/OCT_OcuTalon_MVP at <40-hex sha>
Hands-on time: 2 min 41 s for this candidate; 2 min 41 s for 1.0.0 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-20T14:02:11Z to 2026-11-20T14:09:40Z

| Step | Result | Detail |
| --- | --- | --- |
| kit | confirmed | the author confirmed the 1.0.0 kit is on feature/OCT_OcuTalon_MVP at <short sha> |
| cut | pass | src/module.xml set to 1.0.0; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.0 in the image built from the candidate |
| push | pass | release/1.0.0-rc1 pushed to origin on the author's word |
| notes | fail | release/notes.sh: RESULT fail; draft release/records/1.0.0/rc1-notes.md (not committed) |
| record | pushed | committed to feature/OCT_OcuTalon_MVP and pushed on the author's word |
```
- A re-cut reads `Cut from: release/1.0.0-rc1 at <sha>, then <sha1> <sha2> cherry-picked from feature/OCT_OcuTalon_MVP`. 11.15 checks carry-over against this line.
- A stop reads `Result: stopped at <step>: <reason>` and a failure reads `Result: failed at <step>: <detail>`.
- 11.5's `Mode:` is always `release`. 11.18 adds `rehearsal`.

**Decided in-stage (unattended block: small, reversible, in intent):**
1. **The cut is made in a temporary clone** (`git clone --shared` into the state folder, removed when `image` passes or at the next start), so the author's checkout is never switched and no git worktree is created.
2. **The cut commit always exists** (`--allow-empty` on a re-cut whose bundle is unchanged), so the candidate's head SHA is the cut.
3. **Answers come only on stdin.** No pre-answer flag exists, so no outward step can be scripted past the author.
4. **The draft notes are never committed or pushed.** The repository has been public since 2026-10-31, so a pushed draft would be published.
5. **Over 15 minutes, the record shows it and prints `WARN`.** It does not refuse: REL-3 is a design target, and refusing to finish a release over the author's pace protects nothing.
6. **The Given "with the demo-path test green" is not checked here.** 11.14's full CI gate proves the candidate itself.
7. **The record push is fast-forward only.** A moved integration branch is reported, never rebased or merged by the script.
8. **The kit question is asked only for 1.0.0** (the criterion asks it of the first release).
9. **The `notes` step is not a gate.** Its row carries notes.sh's own `RESULT` (11.4's checklist judges the draft), and it stops only on a refusal.
10. **A new `start` is always allowed,** even while an earlier candidate of the same version waits at an ASK. The earlier state and record stay as they were, and `next`, `resume` and `status` then need `--version` and `--rc`.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Consumes:**
  - 11.3's `lib-release.sh`: `record_path`, `record_write`;
  - 11.4's `notes_path`;
  - 11.13's `release_previous_tag` and `release/notes.sh` (IA1, real);
  - 11.2's `release/upgrade-harness.sh plan` (IA2, real);
  - `docker/Dockerfile` (IA3, real);
  - `stamp_version`, `manifest_version` and `ensure_web_bundle`.
- **Consumed-by:**
  - 11.14: the gates run on the pushed candidate, from a clone at `release/<v>-rc<n>`. Their rows go into `## Release sequence`, inserted before `notes`, with the checklist after `notes`.
  - 11.15: the hands-on gate reads `Cut from:` for carry-over, and owns the `resume` refusal.
  - 11.16: the outward steps after the gates.
  - 11.17: the IPM artifact packs the bundle this cut commits.
  - 11.18: the update hook and the rehearsal candidate.
  - Epic 38 (38.1 to 38.3): the real 1.0.0 cut, stopping at the hands-on gate on `release/1.0.0-rc1`.

**Proposed split (smaller is better; for the lead; at most 6 pieces).** This story keeps criteria 1, 2, 7 and 8. Each sibling below is planned next in this epic, takes its criteria verbatim from epics.md Story 11.5, and adds its steps to `release/release.sh`'s step list:

- **Story 11.14, "The release sequence runs every gate on the pushed candidate":**
  > **Given** the pushed candidate
  >
  > **When** the gates run
  >
  > **Then** the full CI run, the release-candidate evaluation with the demo incident gate, the upgrade harness, the clean-machine rehearsal, the release checklist and the Contest Planner's REL-7 hands-on pass on this candidate (with no open finding the Contest Planner hasn't deferred: for 1.0.0, Stories 38.1 and 38.3 on `release/1.0.0-rc1`) must all pass, each result goes into the candidate's record, the sequence stops naming the gate that failed, and REL-5's override is the only override it accepts (REL-1, REL-5, REL-6, REL-7, CON-2, CON-5) [AMENDED 2026-10-31, owner decision, relayed by the Contest Planner; the owner: "One check, at 1.0.0" and "New Linux droplet"]
  >
  > **And** it refuses a candidate in which an enabled production item still answers "not implemented", so unfinished features stay off the demo path (REL-1, AD-29)

  It must face these facts:
  - No workflow runs on a push of `release/*`. Both workflows trigger on `push: [main, feature/OCT_OcuTalon_MVP, "OCT-epic*"]` and `pull_request`, and `test-ci-config.sh:189,246-250` pins that list. So "the full CI run" on the candidate needs `release/*` added to `ci.yml` and `lane-a.yml`, and to the pin. `.github/workflows/*` is outside Epic 11's footprint (lane-a.yml is contended with Epics 13 and 15). See Clarification Needed 2.
  - The FR-57 job (`ipm-install`) exists only on `origin/OCT-epic15`.
  - The release-candidate evaluation (`bash eval/run.sh --release-candidate`; exit 0 pass, 3 blocked; `--override "<reason>"`) runs on the author's machine with the real key. In this build it runs only as `--on-mock`, which is a dry run.
  - 11.2's harness `run` does not fit 10 minutes, so it runs one phase per call. Its `Required:` line still needs the 1.0.0 rule.
  - `rehearse.sh` exits 3 on a dry run, and a real pass needs 11.12.
  - `checklist.sh` needs the candidate at `HEAD` and the notes draft first.
  - The "not implemented" refusal can be static: an enabled item in `OcuTalon.Production` whose class has `Parameter STUB = 1` (AD-29; `Channel/Telegram/In.cls:11`, `Out.cls:7`).
- **Story 11.15, "The hands-on gate stops the sequence, and its resume command waits for a pass or a carry-over":**
  > **Given** the hands-on gate
  >
  > **When** the sequence reaches it
  >
  > **Then** it stops and names the candidate to install; the Contest Planner runs the pass and records it in the candidate's record, and the sequence is resumed with its resume command, which refuses to go on until the record holds a pass or a carry-over for this candidate; the time spent on the pass doesn't count toward the 15 minutes (REL-3, REL-7)
  >
  > **And** the release that ends a build step (1.0.0, the first release, with the web demo path and Telegram, then each later step's release) needs a fresh pass; a re-cut from the passed candidate plus the recorded fixes' commits (cherry-picked from the integration branch), whose only changes since that candidate are those fixes, carries the pass over, with the Contest Planner's note in its record, while a re-cut from the integration branch's head needs a fresh pass; other releases record a carry-over (REL-7, P29) [AMENDED 2026-10-31, owner decision, relayed by the Contest Planner; the owner: "One check, at 1.0.0" and "New Linux droplet"]

  It must face these facts:
  - Nothing defines the grammar of the Contest Planner's pass record. 11.15 defines a `## Hands-on pass` section: Result, Candidate SHA, findings with fix or deferral, carry-over note.
  - A carry-over is valid only when this story's `Cut from:` line names the passed candidate and only picks of the recorded fixes.
  - A rehearsal record never carries a pass over.
- **Story 11.16, "The sequence asks before each outward step after the gates":**
  > **Given** every gate passed
  >
  > **When** the sequence reaches each later step that acts outside the machine
  >
  > **Then** it stops for the author's word before each one: opening the release pull request from the candidate branch that passed, merging it into `main` only when every required check is green (it reads `main`'s branch protection, which the author sets up with the `ci.yml` and `lane-a.yml` checks required before the sequence first runs, and refuses if those checks aren't required; while the repository is private on a GitHub plan that offers no branch protection, which GitHub answers with HTTP 403, the sequence instead checks every job of the `ci.yml` and `lane-a.yml` runs for the pull request's head commit itself, merges only when each one has succeeded or was skipped by its own condition, and records in the candidate's record that it checked the jobs itself because branch protection was unavailable) [AMENDED 2026-10-25, owner decision, relayed by the Contest Planner; the owner: "We won't make the repo public until we release on Open Exchange." On GitHub Free a private repository has no branch protection, so the first public release merges to `main` while the repository is still private; the author makes it public together with the Open Exchange release, and the Contest Planner then sets up the branch protection for every later release], tagging the release, merging `main` back into the integration branch after the merge and the tag, so the version bump and the built web bundle are on it and the next candidate's pull request doesn't conflict with `main`, and updating the online demo; it never publishes the notes, which the author does (REL-1, REL-8, REL-11, AD-29)

  It must face these facts:
  - The repository has been public since 2026-10-31, and `gh api repos/jbrandtmse/OcuTalon/branches/main/protection` answers 404 "Branch not protected". By the criterion, the merge step refuses until the owner sets the protection; the 403 path applies only to a private repository.
  - It must never contain `gh release` (11.4's `no-outward`).
  - DW-27 is its inbox entry (Ledger, below).
- **Story 11.17, "The release's IPM artifact carries the built page":**
  > **Given** the release sequence packaging a candidate's IPM artifact
  >
  > **When** it builds the package
  >
  > **Then** it builds the web page and puts the built bundle into the package's resources, in `src/ocutalon/csp/` (which `src/module.xml`'s `FileCopy` already copies into `${dataDir}csp/ocutalon-web/`), before it packages the artifact, so the artifact is self-contained and a registry install works with no Node.js on the judge's machine; it records in the candidate's record the artifact it would publish, so Story 15.3 can install exactly that artifact; the registry publish itself stays the author's action, at 1.0.0, and the sequence asks for the author's word before anything goes out (REL-3, REL-11, AD-23) [ADDED 2026-10-31, decided by the Contest Planner under the owner's delegation]

  It must face these facts:
  - No script in the repository packages IPM, and no Epic 15 story names the artifact's command, file or location, so Task 0 measures `zpm "package"` on a throwaway.
  - `src/module.xml`, `release/ipm-install.sh` and `release/ipm/*` are Epic 15's contended files. If the packaging needs one of them changed, that part waits for Epic 15 or is split out.
  - Story 15.3 installs the recorded artifact from a local filesystem repository, so the record names its path, size and checksum.
- **Story 11.18, "The update hook updates the online demo, and a rehearsal candidate proves the sequence":**
  > **Given** the author's word to update the online demo
  >
  > **When** the update hook runs
  >
  > **Then** it copies a `git bundle` of the release tag `v<version>` to the demo host over SSH and calls `ocutalon-demo update <version>` there: the host builds the image from that bundle (no registry, and no repository access on the host) before the reset boundary and refreshes the golden copy there (restore it, start it on the new image so it upgrades in place with no visitor data, wait for ready, check the version, capture the new golden copy, start from it); before launch (`access` restricted) the command runs at once, blocks until ready and prints `{"result": "updated", "version": "<version>"}`, and after launch it prints `{"result": "scheduled", "at": "<nextReset>"}`, which the hook writes into the draft notes; a non-zero exit prints one line with the reason, which the sequence shows and records (REL-10, AD-25, CON-1)
  >
  > **And** the hook then reads `ocutalon-demo status`, one JSON object with `runningVersion`, `goldenVersion`, `lastReset` (UTC ISO 8601), `lastResetKind` (`scheduled` or `unscheduled`), `nextReset` (UTC ISO 8601), `pendingVersion` (or null) and `access` (`restricted` or `public`), and checks the running and golden-copy versions, or `pendingVersion` for a scheduled update; the host's address and SSH key come from the author's configuration outside the repository; with no demo host configured, it says so and the draft notes state that the online demo wasn't updated (REL-10, AD-25, CON-5)
  >
  > **And** the hook is tested against a throwaway compose project standing in for the demo host, which answers `status` and `update` exactly as above (both results and a failing update's non-zero exit), and whose update restore is exempt from the reset's version refusal: it checks that the golden copy holds the previous version and that the upgraded copy reports `<version>` before capture (REL-10, AD-25)
  >
  > **Given** a rehearsal candidate cut from the integration branch (its record marked as a rehearsal), a fixture pass record and the stand-in demo host
  >
  > **When** the author runs the sequence on it before the real 1.0.0 cut [AMENDED 2026-10-31, owner decision, relayed by the Contest Planner; the owner: "One check, at 1.0.0" and "New Linux droplet"]
  >
  > **Then** it pushes the candidate on the author's word, runs every gate, stops at the hands-on gate, refuses to resume until the fixture pass record is in the candidate's record, then resumes with the resume command; the author declines the release pull request, the merge, the tag and the merge back (a declined step is skipped and the sequence goes on), the update hook runs against the stand-in, copying a `git bundle` of the rehearsal candidate's commit because there is no tag, and the stand-in builds from it, a rehearsal record never carries a pass over to a real candidate, and the record holds the commit SHA, each gate's result and the hands-on time; this proves the sequence, and Epic 38 runs the real 1.0.0 cut through it (REL-1, REL-3, REL-7) [AMENDED 2026-10-31, owner decision, relayed by the Contest Planner; the owner: "One check, at 1.0.0" and "New Linux droplet"]

  It must face these facts:
  - No `ocutalon-demo` implementation exists anywhere, so the stand-in is built new. The precedents are the `check_demo_status` jq rules in `release/demo-host-check.sh:398-437` and the `write_status_fixture` in `test-online-host.sh:308-315`.
  - `host_run` and `release_config_read` take `DEMO_` keys in `release.conf`.
  - The hook's section goes into the draft through `record_write <notes> <section>`.
  - The rehearsal candidate must not be pushed as `release/1.0.0-rc1` to `origin`. The step epics' merge gate keys on that branch's existence. See Clarification Needed 3.

**Ledger inbox (Rule 17).** DW-27 (routed to this story's key) is addressed by routing, not closed here:
- **Story-closable part:** it goes to proposed Story 11.16. Its merge step reads `main`'s branch protection and refuses unless the `ci.yml` and `lane-a.yml` checks are required. Before merging, it also checks that every job of both workflows' runs for the pull request's head concluded `success`. A release pull request is always from a same-repository branch, so the fork guard never skips a job there.
- **Recommended trailer:** `routed` to proposed Story 11.16's sprint key, once the lead adds that story to the tracker.
- **The owner's residual (owner-only, a repository setting, never scripted):**
  - Set up branch protection on `main` with the `ci.yml` and `lane-a.yml` checks required.
  - Also decide how fork pull requests are kept from merging without a demo-path run. GitHub reports a job skipped by its `if:` as a successful check (inference from GitHub's documentation; the owner verifies at setup), so required checks alone let a fork pull request through. A rule that only release pull requests merge into `main` closes that gap.
  - **Recommended:** a `sprint-status.yaml` action item, `human=branch protection`.

**Contended paths (U14), checked at plan time** with `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for 12, 13, 15, 30, 31 and 4:
- `ci/units.sh` is changed by Epics 12, 13 and 15, all appending to `CHECK_SCRIPTS`. This story's change is the same one-word append (a union, as in 11.2, 11.3, 11.4 and 11.13).
- No other planned file is listed.
- **New files:** `release/release.sh`, `docker/tests/test-release-sequence.sh`.
- **Changed files:** `release/lib-release.sh` (this epic's), `ci/units.sh`.

**CI budget (REL-4; inference):** the hosted `checks` job gains one hermetic script, about +20 to 40 s. No IRIS group runs (`release/` and `docker/tests/test-*.sh` are not IRIS inputs).

## Clarification Needed (non-blocking: this story's plan does not depend on the answers)

1. **The split.** Accept the proposed split into Stories 11.14 to 11.18 (decide, product default 6, as at 11.4 and 11.11). The lead adds their blocks to epics.md with the `[ADDED ... split from Story 11.5 at its plan ...]` marker, plus the matching `[AMENDED ...]` marker on Story 11.5.
2. **CI on the candidate (before 11.14's plan).** "The full CI run" on `release/<v>-rc<n>` needs `release/*` among the push branches of `ci.yml` and `lane-a.yml`, and in `test-ci-config.sh`'s pinned list. That is a footprint extension into contended workflow files, so it goes to the orchestrator.
3. **The rehearsal candidate's name (before 11.18's plan).** A rehearsal cut named `release/1.0.0-rc1` on `origin` would satisfy the step epics' merge gate (AD-29). A distinct rehearsal branch name, or a throwaway remote, changes merge-gate semantics and Epic 38's flow, so it is a dependency statement (owner-only class 5).
4. **PRD wording (apply-and-report candidate for the lead).** REL-9, REL-7 and P29 still name 0.1.0 and 0.1.1 passes. The epics criteria carry the owner's 2026-10-31 decision ("One check, at 1.0.0"), and this story follows them. The recommended amendment restates REL-9 as "1.0.0 is the first release; 0.1.x is not cut", and REL-7 and P29 as one pass at 1.0.0.

## Verification

All commands run from the worktree root, each in its own foreground call with `timeout: 600000`. No IRIS stack and no lane lock are used. `release/release.sh` itself is run only by the self-test, inside its throwaway repository.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh` -- expected: every PASS line, exit 0, and the throwaway folder removed.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(loop)` Each consumer self-test of `lib-release.sh` that exists, each in its own call: `test-upgrade-harness.sh`, `test-rehearsal.sh`, `test-release-checklist.sh` and `test-release-notes.sh` -- expected: exit 0.
- `(once)` `bash docker/tests/test-release-sequence.sh --live` -- expected: `PASS image 1.0.0` from the real Dockerfile build (IA3). Afterwards `docker images --format '{{.Repository}}' | grep -c ocutalon-release-check` prints 0. Record Task 0's figures here.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash docker/tests/test-ci-changes.sh`, then `bash ci/changes.sh ci.yml`, each in its own call -- expected: exit 0, with release-only changes running no group.
- `(once)` `bash ci/checks.sh` in its four parts, one per call (`for s in <part>; do bash docker/tests/test-$s.sh || echo "FAILED $s"; done`) -- expected: no `FAILED`.

**Mutations to demonstrate (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**
- AC1: drop the no-tag 1.0.0 rule, so the 1.1.0 case starts.
- AC2: reuse rc1's name on a re-cut, so the immutability case fails.
- AC3: skip the version compare, so the lying-shim case passes the image step.
- AC4: commit with `git commit -a`, so the only-the-record case fails.
- AC5: push `--tags` as well, so the remote-refs case fails.
- AC6: echo the environment in a debug line, so the planted-value case fails.
- AC7: count step time into the hands-on sum, so the seam-time case fails.
- AC8: restart at `cut` after a stop at `push`, so the resume case fails.
- IA1: ignore notes.sh's RESULT, so the row case fails.
- IA2: write the section with a hand-rolled writer that drops other sections, so the harness-section case fails.

**Shared surfaces:**
- `CHECK_SCRIPTS` in `ci/units.sh`, read by `test-ci-config.sh`'s units rule.
- `lib-release.sh`'s function list, sourced by the harness, rehearsal, checklist and notes scripts and their self-tests.
- The record file's `## ` sections (written by every gate).
- Every test added or changed passes on a fresh environment, in either order. The self-test builds its own repository, bare remote, shims, state and record in its own temporary folder, and removes them. `--live` builds and removes only its own image tag.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
