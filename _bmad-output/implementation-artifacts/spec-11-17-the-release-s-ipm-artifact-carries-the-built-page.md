---
title: 'Story 11.17: The release''s IPM artifact carries the built page'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_revision: '5ab43766f4922c74f1571fa1ef516225b4934bb1'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-5-one-scripted-sequence-cuts-a-release.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The two-run install path (Epic 15's MapAndStop module) has only run against the self-test shim and plan-time measurements, never real IPM through step_ipm.
    evidence: |-
      --live ipm packages today's src/module.xml (one run, USER). The ns-check session (Config.Namespaces.Exists) and the load in OCUTALON are real-IRIS code that no real run has exercised under this script.
    location: >-
      release/release.sh ipm_pack
    severity: medium (unverified)
  - summary: >-
      The record's claim that the Content SHA-256 is the same for every packaging is shown on hand-made archives only, not on two real IPM packagings of one tree.
    evidence: |-
      IPM's package output differs byte for byte between runs (measured at plan); whether module.xml or other entries carry a per-run value that changes the content digest is not measured. A second package run in --live ipm and a digest comparison would settle it.
    location: >-
      release/release.sh step_ipm (Content SHA-256 line)
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Story 11.5's cut builds the web bundle with Node.js and commits it on `release/<v>-rc<n>`, but nothing packages the candidate as an IPM artifact. Nothing checks that the artifact carries that bundle, and the candidate's record names no artifact. So Story 15.3 has no exact artifact to install from a local filesystem repository, and nothing shows that a registry install would need no Node.js.

**Approach:** Add one step, `ipm`, to 11.5's `STEPS`, between `image` and `push`:

`cut image ipm push notes`

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
- **The conventions of 11.5 hold:**
  - Bash 3.2 and ASCII; mode 100755; `umask 077`; the main guard;
  - `PASS|FAIL|WAIT <step> <detail>`, then `RECORD` and `RESULT`;
  - the stop routine (record, commit with an explicit pathspec, ASK `record`);
  - exit codes 0, 1, 2, 4 and 5 (5, `WAIT`, is new in this story: a busy lane lock; nothing recorded; the next `next` runs the step again);
  - no value printed; the record names no local absolute path.
- **The bundle is the cut's.** The step packages the tree of the recorded cut SHA (`git archive <cut sha> -- src docker/ipm`), read in the repository that holds `release/<v>-rc<n>` (11.5's cut fetches the cut commit there from its state clone, then removes the clone), as 11.5's `image` step reads it. It never builds the bundle again: a second build could differ from the committed one, and then the artifact would not be the candidate.
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
  - 11.5's step list, stop routine, state, `manifest_version`, and its `git archive` read of the cut tree;
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
| Packaged | `image` passed. The cut tree tracks `src/ocutalon/csp/index.html` and the rest of the bundle; the base image is present; `next` | `<state>/ipm/ocutalon-1.0.0.tgz`. `PASS ipm ocutalon-1.0.0.tgz <bytes> bytes sha256 <64 hex>`, then `ARTIFACT <absolute path>`. `## IPM artifact` and the row (Design Notes); exit 0; the next step is `push` | The container is gone, and the lock is released |
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

**Base (built, at HEAD `63936d68`).** Story 11.5 is `done` and merged here: `release/release.sh`, `release/lib-release.sh`, `release/notes.sh` and `docker/tests/test-release-sequence.sh` exist. Stories 11.14, 11.15, 11.16 and 11.18 are NOT built (Epic 11 part 2) and are not prerequisites: no `stubs` step, no 11.14 tree reader, no `--cases` filter. If `release.sh`'s `STEPS`, `stop_routine` or `cmd_next` are missing, implement HALTs `blocked` with `missing prerequisite story`, naming them.

**`release/release.sh` (11.5; extend):**
- `:4` and `:5` header lines -- steps `cut, image, ipm, push, notes` (part 2's 11.14-11.16 and 11.18 insert theirs); exit adds `5 waited: the lane's throwaway lock is busy (nothing recorded; the next call runs the step again)`. `:24-26` gain one sentence on `ipm` (contract only, Rule 14). `:35` output becomes `PASS|FAIL|WAIT <step> <detail>`. `:36` adds tar, gzip and `sha256sum` or `shasum`.
- `:47` `STEPS="cut image push notes"` -> `"cut image ipm push notes"`.
- `:61` `state_root` -- its body moves to lib-release's `release_state_root`; `state_root` stays as a one-line call (its callers `find_state`, `cmd_start` unchanged). `:672` and `:865` build `sdir` with `release_state_dir "$version" "$rc"`.
- `:430` `step_fail` -- reuse for every `FAIL ipm` (it already maps `$sdir` to `<state>` and the checkout to `.`).
- `:538` `step_image`'s base default -- lift into a one-line `base_image` function used by `step_image` and `step_ipm` (no second copy of the default).
- `:542` `git archive "$(sget cand_sha)" | tar -x -C ...` -- the precedent `step_ipm` follows to read the cut tree (into `<state>/ipm-tree/`, removed by the step on every path).
- New `step_ipm`, after `step_image` (`:582`). Order: tree export; bundle and version refusals; the single `docker/ipm/zpm-*.xml`; `docker image inspect --format`; `sset ipm_container <name>` (and `docker rm -f -v` of an earlier recorded leftover); then the subshell. Inside the subshell set `root=$rel_root` before `live_lock_claim` (lib-live's `live_lock_dir` reads `$root`, which only `live_start` sets), and send its stdout and stderr to `<state>/ipm/run.log`, so lib-live's `LOCK` lines are not printed. The subshell's exit 75 is the WAIT; any other non-zero is a FAIL whose detail the subshell wrote to a state file. On pass: `sset ipm_result pass`, `sset ipm_ns <NS>`, write the section with `record_write "$(record_abs)" <section file>` at step time (the stop routine's `record_put` later replaces only `## Release sequence` and keeps this section byte for byte), print `PASS ipm ...` and `ARTIFACT <abs path>`, set `STEP_ROW=pass` and `STEP_DETAIL` to the row text. On fail: `sset ipm_result fail`, write the fail section (Design Notes), return 1. On busy: print the WAIT line, return 5, write nothing.
- `:732` `cmd_next` -- add `5) exit 5 ;;` before the `*)` branch: no `row_set`, no `stop_routine`, `next` unchanged.
- `:719` `cmd_status` -- after the `Result:` line, when `ipm_result` is `pass` and the file exists, print `ARTIFACT <abs path> <bytes> <sha256>`.
- Never touch `ask`, `stop_routine`, `record_render`, `record_put`, `record_commit`, `record_only`, `record_push` or `step_push` (Rule 2).

**`release/lib-release.sh` (11.3; extend, header lines `:5-44` list each new helper):**
- `release_state_root` and `release_state_dir <v> <rc>` -- lifted from `release.sh:61` (`${OCUTALON_RELEASE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/ocutalon/release}` and `/<v>-rc<n>`).
- `sha256_file <file>` -- the 64-hex digest only, from `sha256sum`, else `shasum -a 256`.
- `ipm_artifact_path <v> <rc>` -- `$(release_state_dir <v> <rc>)/ipm/ocutalon-<v>.tgz`.
- `ipm_artifact_check <tgz> <v> <tree>` -- one line per problem, empty when good; the name, version, `FileCopy` and bundle byte checks of Always (the repository listing is checked in the container, not here).
- `ipm_content_digest <tgz>` -- the SHA-256 of the sorted `<sha256>  <path>` lines of every regular file in the archive, extracted to a temporary folder that it removes.
- Keep every existing function; its consumers' self-tests stay green.

**`docker/tests/test-release-sequence.sh` (11.5; extend; already in `CHECK_SCRIPTS`):**
- `:4-28` header -- the new rules and `--live ipm`.
- `:38-45` argument loop -- `--live` stays IA3; `--live ipm` also runs the real `ipm` step on the same throwaway (one call).
- `:115-212` `mkshims` docker shim -- today it answers `image`, `build`, `run --rm --entrypoint`, `rmi`. Extend it (the image step's branch unchanged) to keep a fake container root per `--name` under `$SHIMSTATE`, and to answer: `run -d ...` (records the flags); `exec <c> iris qlist` (`^running`); `exec [-u root] <c> mkdir|chmod`; `cp` both ways; `rm -f -v`; `exec -i <c> iris session IRIS -U <ns>` reading the script on stdin:
  - `zpm "load <dir>"` outside OCUTALON prints 15.1's stop sentence when the copied `module.xml` has `MapAndStop`, and creates OCUTALON; otherwise `[<NS>|ocutalon]`, a tab and `Activate SUCCESS`;
  - the OCUTALON existence check answers from that state;
  - `zpm "package ocutalon -only -path <p>"` writes `<p>.tgz` with `tar -czf` of the copied `src/` (module.xml at the top);
  - `repo ... -list-modules` prints `ocutalon <version> @ <path>` from the extracted folder's `module.xml`;
  - flag files: `ipm-load-fail`, `ipm-drop-csp`, `ipm-byte`, `ipm-version`, `ipm-empty-repo`, `ipm-mapandstop` (the shim treats the module as Epic 15's).
- `:240` `mkseed` -- add `docker/ipm` to the archived paths (the tree's `zpm-0.10.10.xml`, 1.6 MB).
- `:324` `to_step` -- add the `ipm` stop: `push` now follows one more `rs '' next`.
- Every pin of the old order (Shared surfaces): `t_image` `NEXT push` (`:667`, `:706`) -> `NEXT ipm`; `t_record` `:875`; the explicit `rs` sequences of `t_push` (`:716`), `t_secret` (`:1169`), `t_pushes` (`:1291`, two runs), `t_hands`, `t_resume`, `t_notes`, `t_gate`, `t_word`, `t_cut`, `t_recut` -- search for every `rs '' next` chain and `NEXT ` pin.
- `newcase` (`:273`) -- export `OCUTALON_LOCK_DIR=$C/locks` (created empty) for every hermetic case, overriding a caller's lane value, so no hermetic run touches a real lock folder; `live_run` keeps the caller's.
- `:1152` `forbidden_scan` -- add `docker pull`, and on lines that hold `zpm` or `repo` followed by a blank: `publish`, ` -r `, `-url`. Patterns built from parts; planted lines give `file:line`.
- `:1347` `t_static` -- also `bash -n` and mode for `lib-release.sh` unchanged; no `release/ipm*` file in the diff.
- `:1377` `live_run` -- with `ipm`, one more real `next`, then asserts IA1.

**Read only:**
- `docker/tests/lib-live.sh:94-150` (`live_lock_dir` reads `$root`, `live_lock_claim` exits 75 after `OCUTALON_LOCK_WAIT` s, `live_lock_release`) and `:587` `manifest_version`. Epic 12 changes this file (no lock lines); source it, never edit it.
- `src/module.xml`: today `<Version>` at `:6` and `FileCopy` at `:12`. On `origin/OCT-epic15` it adds `CPF`, `MapAndStop` and `Registry.Ipm`; the step handles both forms.
- `docker/ipm/zpm-0.10.10.xml`: the pinned IPM, the only `zpm-*.xml`.
- `docker/after-start.cos:4`: loading IPM from its release file with `"ck-d"`.
- `release/ipm-install.sh` on `origin/OCT-epic15`: `run` (sessions through stdin, ANSI stripped with `strip_ansi`) and `final_line` (the last non-prompt line).
- `release/notes.sh`: never writes the record (`:46`), so IA2's byte-identity holds by construction; the test proves it.

## Tasks & Acceptance

**Execution:**
- Task 0 is done at plan (see Verification). Implement re-measures only the step's wall-clock in `--live ipm`, with the real bundle, and records it.
- `release/lib-release.sh` -- add `release_state_root`, `release_state_dir`, `sha256_file`, `ipm_artifact_path`, `ipm_artifact_check` and `ipm_content_digest`, with header lines -- the shared helpers the step and Story 15.3 read.
- `release/release.sh` -- `STEPS`, `state_root` via the lib, `base_image`, `step_ipm` as in the Matrix and Always, exit 5 in `cmd_next`, the `ARTIFACT` line in `cmd_status`, and the header -- the step itself.
- `docker/tests/test-release-sequence.sh` -- update 11.5's order pins for `ipm` first (the suite green again with `ipm` passing in the shim). Then add the shim, a case for every Matrix row, the ACs and IA2, the scan, and `--live ipm` (IA1). Reuse one advanced case per rule and toggle flags between `next` calls (as `t_image` does), to keep the hosted `checks` job fast.

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

- **2026-11-02, re-plan (orchestrator ruling "Re-plan 2026-11-02", decide; owner trim of Epic 11).** Trigger: Stories 11.14, 11.15 and 11.16 are not built (Epic 11 part 2), and the earlier plan stood on them. Amended: the Approach's step list (`cut image ipm push notes`, `ipm` between `image` and `push`); in Always, the conventions line (11.5's only; exit 5 marked as this story's), the bundle line (the cut tree read with `git archive <cut sha>` as 11.5's `image` step reads it, not by 11.14's pre-push reader), and the Extend line (no 11.14 item); the Matrix's Packaged row (`image` passed, not `stubs`); the Code Map, Tasks, Verification commands, mutation plan and Shared surfaces (11.5's pins only; no `--cases`); Consumes and Consumed-by; Decided in-stage 1 and 7 and new items 8 to 13. Every acceptance criterion, the Matrix's outcomes and every ruled fixed text (U-206) are unchanged. Known-bad state avoided: an implement pass HALTing on missing 11.14 prerequisites, or pulling part 2's steps in. KEEP: the Task 0 measurements, the record golden, the content digest and the 15.3 facts.

## Review Triage Log

### 2026-11-02 - Review pass
- verdicts: 31 findings (blind 8, edge-case 12, verification-gap 3 plus 8 other; the intent audit is descriptive) - high 0, medium 4, low 25, false 0, maybe-false 2
- findings:
  - `[medium]` `[patch]` git archive failure hidden by the pipe (blind 4, edge 1) - the export now writes a tar file and tests git archive and tar separately; failure gives the export line.
  - `[low]` `[patch]` an unchecked copied-out .tgz could stay after a kill (edge 2) - the failure branch of step_ipm removes it.
  - `[medium]` `[patch]` content digest never pinned to what it covers (verification-gap 1) - t_ipmlib now computes the expected digest independently and checks module.xml and a rename change it (mutation: hash without the file list -> ipmlib red).
  - `[medium]` `[patch]` IPM-load failure branch unreachable in the shim (verification-gap 2) - flag `ipm-iris-load-fail` and a case in ipmfail (mutation: the IPMLOAD OK guard replaced by true -> ipmfail red).
  - `[maybe-false]` `[defer]` two-run path never run against real IRIS (verification-gap 3, intent audit) - deferred, run --live ipm again once Epic 15's module.xml merges.
  - `[maybe-false]` `[defer]` "same for every packaging" untested on real IPM output (blind 2) - deferred; a second real package run would settle it.
  - `[low]` `[reject]` build 154 text fixed by the ruled wording and the default image (blind 1) - ruled fixed text (U-206).
  - `[low]` `[reject]` loose module.xml grep and one-way bundle compare (blind 3, edge 6, 7, other) - the tree's own version equals v before packaging and the package is made from that tree; the fix adds parsing for no reachable failure.
  - `[low]` `[reject]` WAIT clears the previous attempt's logs (blind 5, edge 10) - diagnostics of a failure already printed; fix needs a restructure of the state folder.
  - `[low]` `[reject]` scan fragility and evasions (blind 6, edge 12) - literal scan is the spec's AC4; evasion by variables is theoretical.
  - `[low]` `[reject]` session status ignored, uninformative detail, hung session, dead container waits 300 s, non-numeric wait, empty checksum tool, gitattributes (blind 7, edge 3, 4, 5, 8, 9) - no reachable failure shown or a guard-only fix.
  - `[low]` `[reject]` exit 5 callers (blind 8) - the spec introduces it for part 2's callers; next/status pinned by ipmwait.
  - `[low]` `[reject]` argument order `ipm --live` (edge 11) - documented form is `--live ipm`.
  - `[low]` `[reject]` release/ipm* status check, planted secret in artifact, vacuous lock grep when the lane variable is unset, readiness loop transitions, partial mutation lines, shim-versus-real surface (verification-gap other, intent audit) - the real surface is covered by --live ipm; the others cannot cause a user-reachable failure.

## Design Notes

**Re-plan 2026-11-02 (orchestrator ruling, decide; owner trim: Epic 11 ends after 11.17 for 1.0.0, 11.14 to 11.16 and 11.18 move to Epic 11 part 2).** Re-plan this story on Story 11.5's base alone; 11.14, 11.15, 11.16 are NOT built and must not be pulled in. Step order: `cut image ipm push notes`. `step_ipm` reads the cut tree itself with `git archive <cut sha>` from 11.5's state clone (no 11.14 pre-push tree reader). A busy lane lock is `step_ipm`'s own exit 5 (`WAIT`, nothing recorded), a code this story introduces; part 2's 11.14 adopts it and never redefines it. The `## IPM artifact` record keeps exactly the shape Story 15.3 reads: file name, size, SHA-256, content digest, `Published: no`. No acceptance criterion changes: the re-plan touches only the Approach, the Code Map and the Tasks, plus the self-test pins for 11.5's step list. Where older text in this spec names 11.14's `stubs`, exit 5 or tree reader, or 11.15/11.16 pins, this note wins. (Applied in this re-plan; see the Spec Change Log.)

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

**Record (golden; written with `record_write`; ruled under U-206, kept):**
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
- A failure reads `Result: fail` in the section (with the `Candidate:` and `Published:` lines, nothing else), and `failed at ipm: <detail>` in `## Release sequence`. A refusal before the tree is read (no cut) writes no section.

**Decided in-stage (unattended block: small, reversible, within the intent):**
1. **`ipm` comes before `push`.** A candidate whose artifact fails then never goes out, and Story 15.3's later gate finds the artifact already there. It comes after `image`, so 11.5's version check of the built image fails fast first.
2. **The artifact is IPM's own `.tgz`.** That is what `package` and `publish` produce. A filesystem repository needs it extracted (measured), and 15.3 does that.
3. **The content digest sits beside the file's SHA-256.** IPM's `package` is not byte-reproducible: two runs on one tree gave `9d43b0e2...` and `089e6c35...`. A later re-packaging, for example the author's publish (inference: `publish` runs `package` again), can then be matched to the recorded content.
4. **The throwaway is a plain `docker run --network none` of the base image, not lib-live's compose project.**
   - It needs no key, mock, port or volume.
   - No network means nothing can go out.
   - The shim stays small.
   - lib-live's lock still serializes it with the lane's other throwaways.
5. **The bundle is not rebuilt** (Always). The criterion's "builds the web page ... before it packages" is 11.5's cut, which this step packs.
6. **No ASK.** The step sends nothing out. The publish is the author's own, outside the sequence, and the record says so.
7. **The base image's default name** comes from one `base_image` function in `release.sh`, used by `step_image` and `step_ipm` (11.5 already holds the same default inline in `step_image`; lib-live sets it only inside `live_start`, and lib-live is source-only for this epic).
8. **"From 11.5's state clone" read as built.** 11.5's cut makes the commit in `<state>/clone`, fetches it into the author's repository as `release/<v>-rc<n>`, and removes the clone (`release.sh:516-524`); `step_image` then reads the tree with `git archive <cand_sha>` in that repository. `step_ipm` does the same into `<state>/ipm-tree/`. Same SHA, same tree, no clone kept.
9. **Exit 5 is handled in `cmd_next`, not in the stop routine.** A WAIT writes no row and no record and leaves `next` at `ipm`, so the stop routine (Rule 2: never redefined) is not touched. lib-live's `LOCK` lines go to `<state>/ipm/run.log`, never to standard output.
10. **The section is written at step time** with `record_write` (uncommitted, in `release/records/`, which `start` already tolerates); the next stop routine commits the record file with it. 11.5's `record_put` replaces only `## Release sequence`, so no record logic changes.
11. **Lane lock folder.** `step_ipm` sets `root=$rel_root` in its subshell, because lib-live's `live_lock_dir` reads `$root` (set only by `live_start`). The hermetic self-test pins `OCUTALON_LOCK_DIR` to a folder of its own in every case.
12. **The Matrix's "Nothing goes out" `run` check covers the `ipm` throwaway's `run -d` lines.** 11.5's `image` step reads its locally built check image with `run --rm --entrypoint`; those lines are 11.5's, and its own AC already pins them. The scan for `docker pull` covers both scripts whole.
13. **`--live ipm` is one call** (cut, image and ipm on one throwaway): 11.5 measured `--live` at 78 s and Task 0 the IPM flow at 97 s, so about 4 to 5 minutes with the real bundle (inference), inside the 10-minute cap. If it measures over about 8 minutes, implement splits it as 11.5's spec says for `--live`.
14. **In-stage choices of the implementation (small, reversible, within the intent):**
    - Extra failure line, not in the ruled list: `FAIL ipm the candidate holds no single docker/ipm/zpm-*.xml` (a candidate whose tree lacks exactly one IPM release file; it is written with the same `Result: fail` section) and `FAIL ipm the candidate's tree (src and docker/ipm) could not be exported` (no section: the tree was not read). Plain wording; the lead may rule on them.
    - `OCUTALON_RELEASE_IPM_WAIT` (default 300) is the test seam of the start wait; no other variable or option was added.
    - The sessions are four to six `iris session` runs (`ipm-load` with `zpm "enable -map -ns USER"`, `load-user`, optionally `ns-check` and `load-ocutalon`, `package`, `repo-add`, `repo-list`); each plain output is `<state>/ipm/<name>.log`, and `result.env` holds the namespace, the bundle's file count and the IPM file name for the record.
    - The listing is read as a line `ocutalon <v> ...` (measured live: `ocutalon 1.0.0 @ /tmp/ocutalon-check/ocutalon-1.0.0/`).
    - `--live ipm` stays one call; its output prints the load, listing and record lines it checked.
- **The step's IRIS start wait** is 300 s; a timeout reports through the ruled `FAIL ipm the package did not install: <line>` form, with the line `the throwaway instance was not running after 300 s`.

**New fixed texts (ruled under the veto window, U-206, 2026-11-01: kept as planned):**
- `Artifact: <file>, kept in the release state folder (<v>-rc<n>/ipm/), outside the repository; release.sh status prints its full path`
- `Content SHA-256: <hex> (over every file in the artifact; the same for every packaging of this candidate)`
- `Packaged by: IPM <x>, zpm "package ocutalon -only", in namespace <NS> of a throwaway build 154 instance with no network`
- `Web bundle: <n> files of src/ocutalon/csp/, index.html included, byte-identical to the candidate's`
- `Published: no; publishing to the package registry is the author's own action, outside this sequence`
- The row: `<file>, <bytes> bytes, SHA-256 <12 hex>; carries the candidate's web bundle; not published`
- The lines `FAIL ipm the candidate has no committed web bundle (src/ocutalon/csp/index.html)`, `FAIL ipm src/module.xml reads <x>, not <v>`, `FAIL ipm the IRIS base image <name> is not on this machine`, `FAIL ipm the package did not install: <line>`, `FAIL ipm the artifact <what>` and `WAIT ipm the lane's throwaway lock is busy`.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):**
- **Consumes:**
  - 11.5's `STEPS`, `cmd_next`, stop routine, state, cut SHA (`cand_sha`), committed bundle, `git archive` tree read and `manifest_version`;
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
  - **Epic 11 part 2:** Story 11.14 adopts exit 5 and never redefines it; Story 11.18's rehearsal runs this step.
  - **Epic 38:** the real 1.0.0 cut (until part 2 merges, the Contest Planner's hand steps read this record; epics.md, Epic 38's reading note of 2026-11-02).

**Epic 15 dependency: none waits.** The step edits none of Epic 15's files, and it packages whichever `module.xml` the candidate carries. Task 0 measured both today's and `origin/OCT-epic15`'s. The `FileCopy` of `ocutalon/csp/` is in both.
- Observed, not a finding: the package carries the `OcuTalon.Test.*` classes (341 entries), because they are part of `OcuTalon.PKG`. CI runs the units from the installed package (Rule 21), so this is by design.

**Ledger inbox (Rule 17):** none (`LEDGER slice` is empty, re-checked 2026-11-02).

**Previous story continuity:** 11.5 (done) is the base; its Code Map and spec are in `context:`.

**Contended paths (U14):** re-checked 2026-11-02 with `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` over every open epic branch.
- No other branch changes `release/release.sh`, `release/lib-release.sh` or `docker/tests/test-release-sequence.sh`.
- `origin/OCT-epic12` changes `docker/tests/lib-live.sh` (no lock or `manifest_version` lines); this story only sources it.
- Epic 15's `src/module.xml`, `release/ipm-install.sh` and `release/ipm/*` are read only.
- No `footprint_extensions`.

**CI budget:** the hermetic cases add one more `next` to each existing sequence and a few `ipm` cases to the `checks` job, about 20 to 40 s on the hosted runner (inference). `release/` and `docker/tests/test-*.sh` are not IRIS inputs, so no IRIS group runs.

## Verification

Every command runs from the worktree root, in its own foreground call with `timeout: 600000`. `release/release.sh` runs only inside the self-test's throwaway repository.

**Commands:**
- `(loop)` `bash docker/tests/test-release-sequence.sh <rule>...` for the rules being worked on, then the whole suite `bash docker/tests/test-release-sequence.sh` in one call (about 2 to 3 minutes) -- expected: `PASS all rules`, exit 0, and the throwaway folder removed.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(loop)` Each existing consumer self-test of `lib-release.sh`, one per call: `bash docker/tests/test-upgrade-harness.sh`, `bash docker/tests/test-rehearsal.sh`, `bash docker/tests/test-release-checklist.sh`, `bash docker/tests/test-release-notes.sh` -- expected: exit 0.
- `(once)` `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement' bash docker/tests/test-release-sequence.sh --live ipm` -- expected:
  - `PASS image 1.0.0` and `PASS ipm` from real IPM;
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
- Re-checked at the re-plan (2026-11-02): the base image `ocutalon-iris-base:2026.3.0AI.154.0` is on this machine; 11.5 measured its `--live` at 78 s.

**Mutations (Rule 19; applied one at a time, observed red, reverted with `cmp` against the backup; run in the self-test's own rules):**
- AC1: mutation: `ipm_artifact_check` skips the bundle-file byte compare (`elif false`) -> `ipmfail` red (`ipm-byte: exit got 0, wanted 1`, the file is kept, no `FAIL ipm the artifact holds a different ...`).
- AC2: mutation: the size is taken from the state file instead of the artifact -> `ipm` red (the `PASS ipm ... bytes` line, the record's section and the row).
- AC3: mutation: the package always runs in USER -> `ipm` red (`two-run: exit got 1`, the zpm calls, the namespace packaged in; the flag case too).
- AC4: mutation: `--network none` dropped from the throwaway's `docker run` -> `ipm` and `ipmnet` red (the exact run line; every run has no network).
- AC5: mutation: the subshell's exit 75 is treated as a failure (the `75)` branch of `step_ipm` renamed) -> `ipmwait` red (exit 1 not 5, no `WAIT` line, a record written and a commit made).
- AC6: mutation: the EXIT trap's `docker rm -f -v` removed -> `ipm` and `ipmfail` red (no `rm -f -v` in the shim log, a throwaway container left).
- AC7: mutation: `ipm_content_digest` hashes the `.tgz` bytes -> `ipmlib` red (`the content digest is the same for both packagings`).
- IA1: mutation: the shared `bundle_diff` compare (used by the hermetic `ipm` rule and by `--live ipm`) is pointed at a changed byte of the extracted file -> `ipm` red (`every bundle file of the candidate is in the artifact, byte for byte: got assets/a.txt`). Shown on the hermetic rule only; the live run was not repeated with it (about 2 minutes), and the helper is the same one.
- Review patches: mutation: `ipm_content_digest` hashes the file list without the bytes -> `ipmlib` red (`the digest ignores module.xml`, the independent expected value); the `IPMLOAD OK` guard replaced by `true` -> `ipmfail` red (`ipm-iris-load-fail`).
- IA2: mutation: `record_write` rewrites the whole file with its section -> `ipm` red (`the section is byte for byte after the notes step and the stop routine: got ''`).

**Measured in `--live ipm` (2026-11-02, Apple silicon, Docker 29.7.2, lane A, real IPM 0.10.10, today's `src/module.xml`):** whole call 77 s (first run 1 min 43 s with a cold npm cache); the `ipm` step 43 to 48 s (the container start, the IPM load, one package run in USER, the checks, the filesystem-repository listing). The artifact was 4,763,488 bytes with the real bundle of 19 files; IPM's filesystem repository listed `ocutalon 1.0.0 @ /tmp/ocutalon-check/ocutalon-1.0.0/`. Packaged in USER (no CPF in today's module). The container and the lane lock were gone afterwards. Epic 15's module (the two-run path) was measured at plan (Task 0) and is covered here by the shim only.

**Shared surfaces:**
- 11.5's `STEPS` list and every step-order pin of its self-test (`to_step`, the `NEXT push` pins of `t_image` and `t_record`, the `rs` chains of `t_push`, `t_secret`, `t_pushes`, `t_hands`, `t_resume`, `t_notes`, `t_gate`, `t_word` and `live_run`). This story updates each for `ipm`.
- The docker shim and its call log, which 11.5's `t_image` and `t_secret` read.
- `lib-release.sh`'s function list and header.
- `release.sh`'s exit codes (new 5) and header contract.
- The record's `## ` sections.
- Every test added or changed passes on a fresh environment, in either order. The self-test builds and removes its own repository, bare remote, shims, lock folder, state and record. `--live ipm` removes its container and its folders.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `release.sh` gains the `ipm` step (`cut image ipm push notes`): it exports the cut commit's tree with `git archive`, packages it with real IPM 0.10.10 in a `--network none --pull never` throwaway of the build 154 image under lane A's throwaway lock, copies out and verifies the `.tgz` (name, version, `FileCopy`, every bundle file byte for byte, IPM's filesystem repository listing), and writes `## IPM artifact` (Design Notes golden). A busy lock is exit 5 (`WAIT`, nothing recorded); `status` prints `ARTIFACT <path> <bytes> <sha256>`. Nothing is published or pulled.

**Files changed.**
- `release/release.sh`: `STEPS`, `base_image`, `step_ipm` and its helpers, exit 5 in `cmd_next`, the `ARTIFACT` line, header.
- `release/lib-release.sh`: `release_state_root`, `release_state_dir`, `sha256_file`, `ipm_artifact_path`, `ipm_artifact_check`, `ipm_content_digest`, `ipm_unpack`, `last_prompt_free_line`.
- `docker/tests/test-release-sequence.sh`: container-faking docker shim, order pins for `ipm`, rules `ipm`, `ipmfail`, `ipmwait`, `ipmnet`, `ipmlib`, the wider forbidden-form scan, `--live ipm`, a per-case lock folder.
- This spec: mutation lines, Design Notes item 14, triage log, deferred list.

**Review.** 31 findings from four layers. Patched: the git archive status hidden by the pipe; a copied-out unchecked `.tgz` left after a kill; the content digest pinned only by self-reference (now an independent expected value plus module.xml and rename sensitivity); the unreachable IPM-load failure branch (new shim flag and case). Deferred (both `medium (unverified)`): the two-run (MapAndStop) path never run against real IRIS; the "same for every packaging" claim shown only on hand-made archives. Rejected lows are listed in the triage log with reasons.

**Verification.** Whole `test-release-sequence.sh` PASS all rules (2 min 13 s) after the patches; `--live ipm` PASS after the patches (75 s whole call, `ipm` step 43 to 48 s, 19-file bundle, listing `ocutalon 1.0.0`, no `ocutalon-release-ipm-*` container, lane-A lock folder empty); every other script of `CHECK_SCRIPTS` run individually, exit 0 (`ci/checks.sh` itself not run as one call: past the 10-minute cap). Mutations for AC1 to AC7, IA1, IA2 and the two review patches observed red and reverted.

**Follow-up review recommended: true.** Three medium findings were patched, and the unverified risk is that the two-run path (Epic 15's `MapAndStop` module) and the cross-packaging digest equality are not yet run against real IPM; re-run `--live ipm` against a candidate that carries Epic 15's `module.xml` once it merges.

**Residual risks.** Two failure lines are outside the ruled list (`the candidate holds no single docker/ipm/zpm-*.xml`, `the candidate's tree (src and docker/ipm) could not be exported`); the test seam `OCUTALON_RELEASE_IPM_WAIT` was added.
