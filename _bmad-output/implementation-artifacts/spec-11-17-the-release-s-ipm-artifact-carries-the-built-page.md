---
title: 'Story 11.17: The release''s IPM artifact carries the built page'
type: 'feature'
created: '2026-11-01'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-5-one-scripted-sequence-cuts-a-release.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-14-the-release-sequence-runs-every-gate-on-the-pushed-candidate.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 11.5's cut builds the web bundle with Node.js and commits it on `release/<v>-rc<n>`, but nothing packages the candidate as an IPM artifact. Nothing checks that the artifact carries that bundle, and the candidate's record names no artifact. So Story 15.3 has no exact artifact to install from a local filesystem repository, and nothing shows that a registry install would need no Node.js.

**Approach:** Add one step, `ipm`, to 11.5's `STEPS`, between 11.14's `stubs` and `push`:

`cut image stubs ipm push ci eval upgrade rehearsal notes checklist hands-on pr merge tag mergeback demo`

The step runs entirely on the author's machine. It:
- takes the cut commit's tree, with the bundle the cut committed in `src/ocutalon/csp/`;
- installs that tree with IPM 0.10.10 in a throwaway build 154 container that has no network;
- packages it with `zpm "package ocutalon -only -path ..."`;
- copies the `.tgz` into the release state folder;
- checks that the artifact holds the module's name and version, the `FileCopy` of `ocutalon/csp/`, and every bundle file byte for byte, and that IPM's filesystem repository reads it;
- records the artifact's file, size and checksums in a new `## IPM artifact` section of the candidate's record.

Nothing goes out. The registry publish stays the author's own action. This story takes epics.md Story 11.17's one criterion, verbatim there.

## Boundaries & Constraints

**Always:**
- **The conventions of 11.5, 11.14, 11.15 and 11.16 hold:**
  - Bash 3.2 and ASCII; mode 100755; `umask 077`; the main guard;
  - `PASS|FAIL|WAIT <step> <detail>`, then `RECORD` and `RESULT`;
  - the stop routine (record, commit with an explicit pathspec, ASK `record`);
  - exit codes 0, 1, 2, 4 and 5;
  - no value printed; the record names no local absolute path.
- **The bundle is the cut's.** The step packages the tree of the recorded cut SHA (`git archive <cut sha> -- src docker/ipm`), read from the repository that holds `release/<v>-rc<n>` before the push, as 11.14's `stubs` reads it. It never builds the bundle again: a second build could differ from the committed one, and then the artifact would not be the candidate.
- **The throwaway.**
  - `docker run -d --pull never --network none --name ocutalon-release-ipm-<v digits>-rc<n>-<epoch>-<pid>` of `${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}`.
  - The run passes no `-e`, `--env`, `--env-file`, `-v`, `--mount` or `-p`.
  - Files go in and out only with `docker cp`, followed by `docker exec -u root <c> chmod -R a+rX` on what was copied in (measured: `docker cp` keeps the 600 modes of `umask 077`, which the IRIS user cannot read).
  - The whole packaging runs in one subshell. It holds lib-live's throwaway lock (`live_lock_claim` with `P` = the container name), and its EXIT trap removes the container (`docker rm -f -v`), releases the lock and removes the temporary tree.
  - The container name is written to the state before `docker run`. A later `next` removes a leftover container only under that recorded name.
- **The two-run install (Stories 15.1 and 15.2), detected and not assumed.**
  - In `%SYS`: load the tree's single `docker/ipm/zpm-*.xml` with `$SYSTEM.OBJ.Load(...,"ck-d")`, then run `zpm "enable -map -ns USER"`.
  - Then run `zpm "load /tmp/ocutalon-pkg/src"` in USER.
  - If USER's output has no `[USER|ocutalon]` line ending `Activate SUCCESS`, and namespace OCUTALON exists afterwards, run the same load in OCUTALON.
  - Package in the namespace whose load reached `Activate SUCCESS`. If neither did, the step fails.
  - Every session's full output goes to `<state>/ipm/<name>.log`. A failure prints only the last non-prompt line, through `detail_clean`.
- **Artifact checks.** Each check failure is a `FAIL ipm <what>`, and the step then deletes the copied-out file, so `<state>/ipm/` only ever holds a verified artifact. The checks:
  - the top-level `module.xml` names `<Name>ocutalon</Name>` and `<Version><v></Version>`, and has `<FileCopy Name="ocutalon/csp/"`;
  - every file the cut commit tracks under `src/ocutalon/csp/` is in the artifact as `ocutalon/csp/<rel>`, with the same bytes;
  - IPM's filesystem repository lists `ocutalon <v>` from the artifact, extracted to `/tmp/ocutalon-check/ocutalon-<v>/` (the layout measured below).
- **Extend, don't copy (Rule 2):**
  - 11.5's step list, stop routine, state and `manifest_version`;
  - 11.14's exit 5 (`WAIT`) and its pre-push tree reader;
  - 11.3's `record_write` and `detail_clean`;
  - lib-live's `live_lock_claim` and `live_lock_release` (source only).
  - New helpers go into `release/lib-release.sh`.
- **Tests:**
  - The hermetic self-test runs in 11.5's throwaway repository, with a `docker` shim that emulates the container (Tasks).
  - The real IPM runs only in `--live ipm`, with the lane-A variables, on a throwaway candidate, never in this worktree.

**Never:**
- Publish or upload anywhere. Configure a remote IPM repository (`repo -r`, `-url`, `-publish`). Run IPM's `publish`. Sign in to anything. Pull or push an image. `docker save` or `docker export`.
- Add an ASK, a `--publish` option or any pre-answer. This step sends nothing out, so it has no word to ask for. The existing ASKs still come before every outward step.
- Commit or track the artifact, or write it into the author's checkout. It stays in `<state>/ipm/`, outside the repository.
- Edit `src/module.xml`, `release/ipm-install.sh`, `release/ipm/*`, `src/**/Install/**`, `docker/ipm/*`, `docker/tests/lib-live.sh`, `.github/workflows/*`, `ci/units.sh`, `.gitignore` or `README.md`.
- Name a new file `release/ipm*`. That pattern is Epic 15's.
- Run `release/release.sh` in this worktree, in a real checkout, or against GitHub or any network remote.
- Use slot A or any shared instance for packaging.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Packaged | `stubs` passed. The cut tree tracks `src/ocutalon/csp/index.html` and the rest of the bundle; the base image is present; `next` | `<state>/ipm/ocutalon-1.0.0.tgz`. `PASS ipm ocutalon-1.0.0.tgz <bytes> bytes sha256 <64 hex>`, then `ARTIFACT <absolute path>`. `## IPM artifact` and the row (Design Notes); exit 0; the next step is `push` | The container is gone, and the lock is released |
| Two-run package | The tree's `module.xml` has Epic 15's CPF and `MapAndStop`. USER's load ends with the stop sentence, and OCUTALON then exists | Loaded again in OCUTALON and packaged there; same as Packaged | -- |
| One-run package | The tree's `module.xml` is today's (no CPF). USER's load reaches `Activate SUCCESS` | Packaged in USER; same as Packaged | -- |
| No bundle in the cut | `src/ocutalon/csp/index.html` is not in the cut commit | `FAIL ipm the candidate has no committed web bundle (src/ocutalon/csp/index.html)`; exit 1; record `Result: failed at ipm: ...` | No container started |
| Wrong version in the tree | `manifest_version` of the tree differs from `<v>` | `FAIL ipm src/module.xml reads <x>, not <v>` | No container |
| No base image | `docker image inspect --format '{{.Id}}' <image>` fails | `FAIL ipm the IRIS base image <name> is not on this machine` | Never pulls |
| Lane lock busy | `live_lock_claim` exits 75 | `WAIT ipm the lane's throwaway lock is busy`; exit 5; no record commit and no ASK | The next `next` runs `ipm` again |
| Install fails | Neither load reaches `Activate SUCCESS` | `FAIL ipm the package did not install: <last line>` | Container removed; logs kept in `<state>/ipm/` |
| Artifact incomplete | A bundle file missing or different; version or name wrong; no `FileCopy`; the repository lists nothing | `FAIL ipm the artifact <what>`, naming the first bundle path that differs | The `.tgz` is deleted |
| Re-run after a failure | `next` after `FAIL ipm` | A fresh container and a fresh artifact; the row and section show the latest attempt | -- |
| After a pass | `next` and `status` | `ipm` never runs again. `status` also prints `ARTIFACT <path> <bytes> <sha256>` | `status` changes nothing |
| Nothing goes out | A full run to `push` answered `no`, with a planted `OCUTALON_TEST_SECRET` | The shim log has `run` only with `--pull never --network none` and none of the forbidden flags; no `push`, `login` or `pull`; the planted value is in no output, record, log or shim log; the bare remote is unchanged | -- |

</intent-contract>

## Code Map

**Prerequisites.** Stories 11.3, 11.4, 11.13, 11.5 and 11.14 must be merged into this branch (11.15 and 11.16 too if they are built first; their pins move by one step). Today `release/` holds `lib-release.sh`, `rehearse.sh`, `upgrade-harness.sh`, `standalone-bridge.sh` and Epic 29's files, and 11.5 and 11.14 are `ready-for-dev`. If `release.sh`, its stop routine, or 11.14's exit 5 and `stubs` step are missing, implement HALTs `blocked` with `missing prerequisite story`, naming them.

**Files:**
- `release/release.sh` (11.5; extended by 11.14 to 11.16) -- insert `ipm` after `stubs` in `STEPS`, add `step_ipm`, and make `status` print the `ARTIFACT` line. The header comment gains the step (contract only, Rule 14). New state keys: `ipm_container`, `ipm_ns` and `ipm_result`.
- `release/lib-release.sh` -- add these helpers:
  - `sha256_file <file>`: the 64-hex digest only, from `sha256sum`, else `shasum -a 256`;
  - `ipm_artifact_path <v> <rc>`: `<state>/ipm/ocutalon-<v>.tgz`. It uses 11.5's state-folder rule; if 11.5 kept that rule inline in `release.sh`, lift it here as `release_state_dir <v> <rc>` and use it in both;
  - `ipm_artifact_check <tgz> <v> <tree>`: one line per problem, empty when the artifact is good; it runs the checks under Always;
  - `ipm_content_digest <tgz>`: the SHA-256 of the sorted `<sha256>  <path>` lines of every regular file in the archive, so two packagings of one tree give one value.
  - Keep every existing function and its consumers' self-tests.
- `docker/tests/test-release-sequence.sh` (11.5; extended by 11.14 to 11.16) -- extend it; no new `CHECK_SCRIPTS` entry.
  - The docker shim keeps a fake container root per `--name` under its folder, and logs every call. It answers:
    - `image inspect --format` (a flag file makes it fail);
    - `run -d`;
    - `exec ... iris qlist` (`^running`);
    - `exec mkdir` and `exec -u root chmod`;
    - `cp` in both directions;
    - `rm -f -v`;
    - `exec -i ... iris session IRIS -U <ns>`, which reads the script on stdin:
      - `zpm "load <dir>"` outside OCUTALON prints 15.1's stop sentence when `module.xml` has `MapAndStop`, and creates OCUTALON; otherwise it prints `[<NS>|ocutalon]` and `Activate SUCCESS`;
      - `zpm "package ocutalon -only -path <p>"` writes `<p>.tgz` with `tar -czf` of the copied `src/` (module.xml at the top);
      - `repo ... -list-modules` prints `ocutalon <version> @ <path>` for the folder's `module.xml`;
    - flag files make the load fail, drop `ocutalon/csp/`, change one bundle byte, change the version, or empty the repository listing.
  - Add `--cases ipm` if 11.15 added `--cases`.
  - Add `--live ipm`: the real base image and IPM on a throwaway candidate cut with a real bundle (11.5's `--live` folder, or its own cut). It asserts the matrix's Packaged row against real IPM, then no container whose name starts with `ocutalon-release-ipm-` and no lock of it.
- Read only:
  - `src/module.xml`: today `<Version>` at `:6` and `FileCopy` at `:12`. On `origin/OCT-epic15` it adds `CPF`, `MapAndStop` and `Registry.Ipm`; the step handles both forms.
  - `docker/ipm/zpm-0.10.10.xml`: the pinned IPM, the only `zpm-*.xml`.
  - `docker/tests/lib-live.sh:94-150`: `live_lock_dir`, `live_lock_claim` (it exits 75 when the lock is busy, hence the subshell), `live_lock_release`; and `:587` `manifest_version`.
  - `docker/after-start.cos:4`: the precedent for loading IPM from its release file with `"ck-d"`.
  - `release/ipm-install.sh` on `origin/OCT-epic15`: the precedents for `run` (sessions through stdin, ANSI stripped with `strip_ansi`) and `final_line` (the last non-prompt line).

## Tasks & Acceptance

**Execution:**
- Task 0 is done at plan (see Verification). Implement re-measures only the step's wall-clock in `--live ipm`, with the real bundle, and records it.
- `release/lib-release.sh` -- add the four helpers.
- `release/release.sh` -- `step_ipm` as in the Matrix and Always, the `ARTIFACT` line, and the header.
- `docker/tests/test-release-sequence.sh` -- update the `STEPS`, row and order pins of 11.5 and 11.14 to 11.16 for `ipm`. Then add the shim, a case for every Matrix row, the ACs and IA2, the scan below, and `--live ipm` (IA1).

**Acceptance Criteria:**
- **AC1 (the bundle in the artifact; REL-3, AD-23):** **Given** a cut whose tree tracks the bundle, **when** `next` runs `ipm`, **then** the `.tgz` holds every tracked `src/ocutalon/csp/` file, byte for byte, as `ocutalon/csp/<rel>`, under a `module.xml` with `ocutalon`, `<v>` and the `FileCopy` of `ocutalon/csp/`. **Given** each shim flag (a dropped bundle, a changed byte, a wrong version), **when** the step runs, **then** it fails naming the problem, the file is gone, and no push ASK follows.
- **AC2 (the record; REL-11, for 15.3):** **Given** a pass, **when** the stop routine commits the record, **then** `## IPM artifact` holds the lines of the Design Notes golden: the file name, the size in bytes equal to `wc -c`, the SHA-256 equal to `sha256_file`, the content digest, the candidate's full SHA and the namespace packaged in. The record contains no local absolute path, and `status` prints `ARTIFACT` with the file's absolute path, its size and its SHA-256.
- **AC3 (the two-run install):** **Given** a tree whose `module.xml` has `MapAndStop`, **when** the step runs, **then** the shim log shows the load in USER, then in OCUTALON, and the package in OCUTALON. **Given** today's `module.xml`, **when** the step runs, **then** the log shows the load and the package in USER only.
- **AC4 (nothing goes out; REL-11, AD-22, CON-1):** **Given** the full run in the Matrix's last row, **when** it ends, **then** that row holds. A scan of `release/release.sh` and `release/lib-release.sh` finds no IPM publish command, no `repo -r`, `-url` or `-publish`, and no `docker pull`. The test builds those patterns from parts, and a planted line in a copy fails the scan with `file:line`.
- **AC5 (refusals and waits):** **Given** no bundle in the cut, a wrong tree version, or no base image, **when** `ipm` runs, **then** it fails before any `docker run`. **Given** a busy lane lock (`OCUTALON_LOCK_DIR` at a test folder with a planted lock, `OCUTALON_LOCK_WAIT=0`), **when** `ipm` runs, **then** it prints `WAIT ipm`, exits 5, writes no record, and the next `next` runs `ipm` again.
- **AC6 (clean-up and resume; Rule 18 (5)):** **Given** a pass or a failure after `docker run`, **when** the step returns, **then** the shim shows `rm -f -v` of the recorded container and the step's own lock file is gone. **Given** the busy-lock case, **when** it returns, **then** no `docker run` happened and the planted lock is kept. **Given** a pass, **when** `next` runs, **then** it goes to `push` and never runs `ipm` again.
- **AC7 (one content, any packaging):** **Given** two packagings of one tree whose `.tgz` bytes differ (the test changes a file's mtime between them; real IPM differs anyway, measured below), **when** `ipm_content_digest` runs on both, **then** it gives one value.
- **IA1 (`(once)`, real IPM, Rule 1):** **Given** `--live ipm` on a throwaway candidate with the real bundle, **when** the real step runs, **then**:
  - IPM 0.10.10's filesystem repository lists `ocutalon 1.0.0` from the extracted artifact;
  - the artifact holds the real bundle byte for byte;
  - the run's `--network none` container is gone afterwards, and the lock is released.
- **IA2 (the record's readers):** **Given** the record after `ipm`, **when** the later real `release/notes.sh` step (11.5's IA1) and the stop routine write their sections, **then** `## IPM artifact` stays byte-identical, and `status` still prints the `ARTIFACT` line.
- **Standing:** every test added or changed passes on a fresh environment, in either order.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- **AD-2:** one IPM package, `ocutalon`, with the bridge first, plus the built bundle.
- **AD-23:**
  - the version is in `src/module.xml`;
  - the bundle is built by Node only in CI and development, and committed on the release branch;
  - static files go to `${dataDir}csp/ocutalon-web/` through the `FileCopy`;
  - IPM 0.10.10 is pinned;
  - an IPM install is two runs of the same package.
- **AD-22:** no registry, push, pull or sign-in; destructive and stateful work only on throwaways; `--format` and `--quiet` only.
- **AD-29:** `release/` is Lane A's; Epic 15 owns `src/module.xml`, `release/ipm*` and `Install/**`.
- No criterion contradicts an AD.

**Record (golden; written with `record_write`):**
```
## IPM artifact
Result: pass
Candidate: 1.0.0 rc1, release/1.0.0-rc1 at <40-hex sha>
Artifact: ocutalon-1.0.0.tgz, kept in the release state folder (1.0.0-rc1/ipm/), outside the repository; release.sh status prints its full path
Size: 2486113 bytes
SHA-256: <64 hex>
Content SHA-256: <64 hex> (over every file in the artifact; the same for every packaging of this candidate)
Packaged by: IPM 0.10.10, zpm "package ocutalon -only", in namespace OCUTALON of a throwaway build 154 instance with no network
Web bundle: 19 files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's
Published: no; publishing to the package registry is the author's own action, outside this sequence
```
- The step's row reads `| ipm | pass | ocutalon-1.0.0.tgz, 2486113 bytes, SHA-256 <first 12 hex>; carries the candidate's web bundle; not published |`.
- A failure reads `Result: fail` in the section, and `failed at ipm: <detail>` in `## Release sequence`.

**Decided in-stage (unattended block: small, reversible, within the intent):**
1. **`ipm` comes before `push`.** A candidate whose artifact fails then never goes out, and Story 15.3's later gate finds the artifact already there. It comes after `stubs`, so the static check fails fast first.
2. **The artifact is IPM's own `.tgz`.** That is what `package` and `publish` produce. A filesystem repository needs it extracted (measured), and 15.3 does that.
3. **The content digest sits beside the file's SHA-256.** IPM's `package` is not byte-reproducible: two runs on one tree gave `9d43b0e2...` and `089e6c35...`. A later re-packaging, for example the author's publish (inference: `publish` runs `package` again), can then be matched to the recorded content.
4. **The throwaway is a plain `docker run --network none` of the base image, not lib-live's compose project.**
   - It needs no key, mock, port or volume.
   - No network means nothing can go out.
   - The shim stays small.
   - lib-live's lock still serializes it with the lane's other throwaways.
5. **The bundle is not rebuilt** (Always). The criterion's "builds the web page ... before it packages" is 11.5's cut, which this step packs.
6. **No ASK.** The step sends nothing out. The publish is the author's own, outside the sequence, and the record says so.
7. **The base image's default name** (`ocutalon-iris-base:2026.3.0AI.154.0`, overridable by `IRIS_IMAGE`) is a one-line copy of lib-live's default. lib-live sets it only inside `live_start`, and lib-live is source-only for this epic.

**New fixed texts, for the lead to rule (veto window: public text, since records are pushed):**
- `Artifact: <file>, kept in the release state folder (<v>-rc<n>/ipm/), outside the repository; release.sh status prints its full path`
- `Content SHA-256: <hex> (over every file in the artifact; the same for every packaging of this candidate)`
- `Packaged by: IPM <x>, zpm "package ocutalon -only", in namespace <NS> of a throwaway build 154 instance with no network`
- `Web bundle: <n> files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's`
- `Published: no; publishing to the package registry is the author's own action, outside this sequence`
- The row: `<file>, <bytes> bytes, SHA-256 <12 hex>; carries the candidate's web bundle; not published`
- The lines `FAIL ipm the candidate has no committed web bundle (src/ocutalon/csp/index.html)`, `FAIL ipm src/module.xml reads <x>, not <v>`, `FAIL ipm the IRIS base image <name> is not on this machine`, `FAIL ipm the package did not install: <line>`, `FAIL ipm the artifact <what>` and `WAIT ipm the lane's throwaway lock is busy`.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Consumes:**
  - 11.5's `STEPS`, stop routine, state, cut SHA, committed bundle and `manifest_version`;
  - 11.14's exit 5 and pre-push tree reader;
  - 11.3's `record_write` and `detail_clean`;
  - lib-live's lock;
  - `docker/ipm/zpm-0.10.10.xml`;
  - Epic 15's `src/module.xml`, read as it stands;
  - IPM 0.10.10's `package` and filesystem `repo` (IA1, real);
  - 11.13's `notes.sh` (IA2, real).
- **Consumed-by:**
  - **Story 15.3:** before any publish, it installs this artifact on a clean throwaway with no Node.js. It reads `## IPM artifact`, finds the file with `ipm_artifact_path` (or `status`'s `ARTIFACT` line), and checks its SHA-256.
    - Measured for it (Task 0): a filesystem repository whose folder holds only the `.tgz` lists nothing. One whose folder holds the extracted artifact (`<root>/ocutalon-<v>/module.xml`, `repo -name <n> -fs -depth 2 -path <root>/`) lists `ocutalon <v> @ <root>/ocutalon-<v>/`, and `zpm "load <file>.tgz"` takes the `.tgz` directly.
    - Its criterion's "(Story 11.5 builds it into the package's resources)" now means this story. That wording is for the orchestrator; it is not this epic's block.
  - **Story 11.18:** the rehearsal runs this step.
  - **Epic 38:** the real 1.0.0 cut.

**Epic 15 dependency: none waits.** The step edits none of Epic 15's files, and it packages whichever `module.xml` the candidate carries. Task 0 measured both today's and `origin/OCT-epic15`'s. The `FileCopy` of `ocutalon/csp/` is in both.
- Observed, not a finding: the package carries the `OcuTalon.Test.*` classes (341 entries), because they are part of `OcuTalon.PKG`. CI runs the units from the installed package (Rule 21), so this is by design.

**Ledger inbox (Rule 17):** none (`LEDGER slice` is empty).

**Previous story continuity:** 11.10 (done) touched web e2e only, so there is nothing shared. The working base is 11.5, 11.14 and 11.16's plans.

**Contended paths (U14):** checked at plan time with `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` over every open epic branch.
- No other branch changes `release/release.sh`, `release/lib-release.sh` or `docker/tests/test-release-sequence.sh`.
- Epic 15's `src/module.xml`, `release/ipm-install.sh` and `release/ipm/*` are read only.
- No `footprint_extensions`.

**CI budget:** the hermetic cases add a few seconds to the `checks` job (inference). `release/` and `docker/tests/test-*.sh` are not IRIS inputs, so no IRIS group runs.

## Verification

Every command runs from the worktree root, in its own foreground call with `timeout: 600000`. `release/release.sh` runs only inside the self-test's throwaway repository.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh` (or `--cases ipm`, then the other parts, one per call, when 11.15's filter exists) -- expected: exit 0, and the throwaway is removed.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(loop)` Each existing consumer self-test of `lib-release.sh`, one per call -- expected: exit 0.
- `(once)` `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement' bash docker/tests/test-release-sequence.sh --live ipm` -- expected:
  - `PASS ipm` from real IPM;
  - then `docker ps -a --format '{{.Names}}' | grep -c '^ocutalon-release-ipm-'` prints 0, and the lane folder holds no lock of the run.
  - Record the step's wall-clock here.
- `(once)` `bash ci/checks.sh` in its parts, one per call -- expected: no `FAILED`.

**Task 0 (measured at plan, 2026-11-01, developer machine, Apple silicon, Docker 29.7.2).** On a lane-A throwaway of the base image (lock held as `epic=11 stage=plan`, then torn down), with IPM from `docker/ipm/zpm-0.10.10.xml`:
- **Timings:**
  - IRIS ready: 6 to 12 s;
  - IPM load in `%SYS`: 13 to 15 s;
  - `zpm "enable -map -ns USER"`: about 2 s;
  - `docker cp` of `src/` (9 MB): about 1 s.
- **`origin/OCT-epic15`'s module:**
  - USER's load stopped with `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.` in 14 to 42 s;
  - the load in OCUTALON reached `[OCUTALON|ocutalon]`, a tab and `Activate SUCCESS`, with every `STEP ... OK`, in 30 s;
  - `zpm "package ocutalon -only -path /tmp/ocutalon-ipm/ocutalon-1.0.0"` took 1 to 2 s and wrote `ocutalon-1.0.0.tgz` (plus an empty folder of that name);
  - the whole flow took 97 s with `--network none`.
- **Today's module:** the load in USER (or a new interoperability namespace) reached `Activate SUCCESS` in 24 to 29 s, and the package took 1 s.
- **The artifact:** top-level `module.xml` (re-serialized; `Version` and `FileCopy` kept, `<Packaging>` dropped), `bridge/cls`, `ocutalon/cls`, `ocutalon/csp/` with every bundle file, and for Epic 15's module also `cpf/` and `preload/cls`.
  - With a 2-file stand-in bundle it was 1.69 MB (Epic 15's module) or 1.91 MB (today's).
  - The real bundle is 3.5 MB in 19 files, so the real artifact will be larger (to be measured in `--live ipm`).
  - Two packagings of one tree gave different SHA-256s.
  - `zpm "load <tgz>"` in OCUTALON reinstalled it (every STEP OK), and `${dataDir}csp/ocutalon-web/index.html` existed afterwards.
  - Filesystem repositories behaved as recorded under Consumed-by.

**Mutations to demonstrate (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**
- AC1: skip the bundle-file compare, so the changed-byte case passes.
- AC2: write the size from the tree instead of the file, so the size check fails.
- AC3: always package in USER, so the two-run case fails.
- AC4: drop `--network none`, so the shim-log case fails.
- AC5: treat 75 as a failure, so the WAIT case fails.
- AC6: skip the trap's `rm -f -v`, so the clean-up case fails.
- AC7: hash the `.tgz` bytes in `ipm_content_digest`, so the two-packagings case fails.
- IA2: write the section with a hand-rolled writer, so the byte-identical case fails.

**Shared surfaces:**
- The `STEPS` list, the rows and the step-order pins of 11.5's and 11.14 to 11.16's self-test cases. This story updates each pin for `ipm`.
- The docker shim and its call log, which 11.5's AC6 reads.
- `lib-release.sh`'s function list.
- The record's `## ` sections.
- Every test added or changed passes on a fresh environment, in either order. The self-test builds and removes its own repository, bare remote, shims, state and record. `--live ipm` removes its container and its folders.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
