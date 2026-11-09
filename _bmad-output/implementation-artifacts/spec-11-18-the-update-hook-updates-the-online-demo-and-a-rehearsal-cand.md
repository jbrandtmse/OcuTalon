---
title: 'Story 11.18: The update hook updates the online demo, and a rehearsal candidate proves the sequence (part A: the update hook and its stand-in)'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-16-the-sequence-asks-before-each-outward-step-after-the-gates.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing updates the online demo. The Contest Planner updated it by hand for 1.0.0 to 1.0.4, and no record says how. Story 11.16's `demo` step calls `release/demo-update.sh` through a fixed contract, but the hook does not exist, and there is no stand-in demo host to test it against (`release/demo-host-checks.md:58`, H19, still waits for "Story 11.5's stand-in").

**Approach:** Two pieces, tested by one new runner unit, `live:demo-update`:
- **`release/demo-update.sh`.** It keeps 11.16's call contract and AD-25's interface. It makes a one-ref `git bundle` and copies it over SSH (`host_run demo`, with `DEMO_` keys from the author's `release.conf`). It then runs `ocutalon-demo update <v>` and `ocutalon-demo status`, judges both answers, and writes its own record section and the draft notes' online-demo section.
- **A throwaway compose stand-in in `docker/tests/demo-standin/`.** It answers `status` and `update` as AD-25 says, builds the root `Dockerfile` from the copied bundle and keeps a golden-copy volume.

Story 11.29 (the rehearsal candidate, U-203) is planned separately. It builds on both pieces.

## Boundaries & Constraints

**Always:**
- **The conventions of 11.5 and 11.14 to 11.16 hold:**
  - Bash 3.2 and ASCII (Rule 14); scripts tracked at mode 100755; `umask 077`; the main guard;
  - every detail goes through `detail_clean`;
  - no environment value is printed: no `env`, `printenv`, `set -x` or `declare -p`;
  - never `docker push|login|save|export|pull`, and never a registry sign-in (CON-1).
- **11.16's call contract, exactly** (`spec-11-16…md:289-293`):
  - **The call:** `bash release/demo-update.sh --version <v> --rc <n> --ref <ref> --record <abs record> --notes <abs draft>`, run from the checkout's root with stdin closed. The progress lines come first (Public text).
  - **The last line and exit code:**
    - exit 0: `RESULT updated` or `RESULT scheduled <at>`;
    - exit 3 (the online demo was not updated, and nothing failed): the reason alone;
    - exit 1 (failed) or exit 2 (refused: no host contacted, nothing written): the reason alone.
  - 11.16 shows the last line as it is, and rows exit 3 as `not updated`.
- **The ref follows the record's `## Release sequence` `Mode:` line,** and the record's `Candidate:` line (`<v> rc<n>, <branch> at <sha>`, `release.sh:228`) must name `--version` and `--rc`.
  - **`Mode: release`** needs `--ref v<v>`. `v<v>` must be an annotated tag in the checkout whose commit's tree equals the candidate sha's tree. 11.16 tags `main`'s merge commit, whose tree is the cut's tree (`spec-11-16…md:283`), so the tag names exactly what the gates ran on.
  - **`Mode: rehearsal`** (Story 11.29's records) needs `--ref <the candidate's 40-hex sha>`, a candidate branch `rehearsal/<v>-rc<n>`, and `DEMO_STANDIN=yes`.
  - Anything else is refused.
- **The bundle holds exactly one ref:**
  - `refs/tags/v<v>` for a release;
  - `refs/heads/rehearsal/<v>-rc<n>` at the sha for a rehearsal.

  It is made in a temporary bare repository filled by `git fetch` from the checkout, so the checkout's refs never change and nothing is pushed. `git bundle verify` must pass. The bundle goes on stdin through `host_run demo` into `ocutalon-demo/bundles/ocutalon-<v>.bundle`, relative to the login folder: written as `.part`, then renamed.
- **The host's answers are judged; none is taken on trust:**
  - **`update`** must exit 0 with exactly `{"result":"updated","version":"<v>"}` or `{"result":"scheduled","at":"<UTC ISO 8601>"}`. Whitespace between JSON tokens is allowed; anything else fails. A non-zero `update` is shown and recorded as its one line.
  - **`status`** must have exactly AD-25's seven keys with their types (the rules of `check_demo_status`, `release/demo-host-check.sh:398-437`).
    - After `updated`: `runningVersion` and `goldenVersion` are `<v>`, `pendingVersion` is null, and `access` is `restricted`.
    - After `scheduled`: `pendingVersion` is `<v>`, `access` is `public`, and `nextReset` equals `at`.
  - **ssh exit 255** means the host could not be reached.
- **Configuration (AD-19, AD-25, CON-5).** A new `demo_config_read` reads only the `DEMO_` keys of `release_config_path`'s file.
  - **Keys:** `DEMO_SSH` (user@host) and `DEMO_KEY` are required together. `DEMO_PORT`, `DEMO_KNOWN_HOSTS` and `DEMO_STANDIN` (`yes` or unset) are optional.
  - **No demo host:** no file, or a file with no `DEMO_SSH`, means none is configured. The hook says so, exits 3 and contacts no host.
  - **Refusals (exit 2):**
    - a file inside the repository;
    - an unknown `DEMO_` key;
    - a missing `DEMO_KEY`;
    - a key or known-hosts file that cannot be read;
    - a `DEMO_STANDIN` other than `yes`.
  - **No value ever appears** in output, the record, the notes or a log. The record names the host only as `the configured demo host`, `a stand-in demo host (not the online demo)` or `none configured`.
- **Only the online demo counts as updated.** With `DEMO_STANDIN=yes`, in either mode, a good `updated` or `scheduled` ends with exit 3 and a stand-in reason line. 11.16's row then reads `not updated`, and the notes say a stand-in was updated.
- **The stand-in (`docker/tests/demo-standin/`) is test infrastructure:**
  - **Names.** Its compose project is named in lib-live's form, `ocutalon-demostandin-<OCUTALON_RUN_TAG>-<epoch>-<pid>`, so `ci/iris.sh teardown` removes it, and its images are named from the project.
  - **Lock.** Each live part holds the lane's `throwaway-iris.lock` through lib-live's `live_lock_claim` and `live_lock_release`.
  - **Build.** It clones the copied bundle and builds the **root `Dockerfile`** from the clone with `--pull=false`, on the local base image. It checks first that the base image is present, and never pulls (`up --pull never`).
  - **Volumes and the upgrade.** It has a `durable` and a `golden` volume. Its container runs the built image with the entrypoint replaced: it copies `/opt/ocutalon/version` to `/durable/ocutalon.version` (the model of IRIS's in-place upgrade), then writes `/durable/ocutalon.ready`.
  - **`update <v>`.** The image is built first, before any boundary. With `access` public, the command records `pendingVersion` and answers `scheduled` at `nextReset`. Otherwise:
    1. check that golden holds the running (previous) version (the exemption from the reset's version refusal);
    2. restore golden into durable, start it on the new image, wait for ready, and check that the copy reports `<v>`;
    3. stop, capture golden without the ready marker, and start from it;
    4. answer `updated`.
  - **Failures.** Any failure exits non-zero with one reason line and leaves golden unchanged.
  - **Stand-in-only commands:**
    - `init <v>`: the first golden copy, from a fresh start;
    - `reset`: applies a pending update; otherwise it restores golden, and refuses a golden whose version differs from the image's;
    - `access restricted|public`;
    - `fault <name>|none`;
    - `down`, which removes only its own project's containers, volumes, images and folders.
  - **Configuration.** The base image name, the interval and the anchor come from `standin.conf` in the login folder, which the test writes. No new file holds an image reference with a tag, because Epic 29's row-15 expression counts `name:digits` as a host:port.
- **Tests use only throwaways:** throwaway repositories, temporary `release.conf` files and `HOME`, and the local transport `docker/tests/demo-standin/ssh-local.sh`, set through 11.3's seam `OCUTALON_REHEARSAL_SSH`.
  - The transport checks the strict-host-key argv and runs the command in the host's login folder.
  - A logging `ssh` and `scp` shim that exits 97 sits first on `PATH`, so a missed seam fails the test instead of reaching a network.
- **Extend, don't copy (Rule 2):**
  - `host_run` gains a `demo)` arm of new lines only;
  - `release_config_path`, `release_in_repo`, `record_write`, `record_field` and `detail_clean` are reused unchanged;
  - lib-live's `live_tag_ok`, `live_lock_dir`, `live_lock_claim` and `live_lock_release` are called, never edited.

**Never:**
- **Never act outward.**
  - Do not touch the real online demo host, its address, its SSH key or its update endpoint. Do not open an SSH connection to any host.
  - No test reads the author's real `release.conf` or `~/.ssh`.
  - Do not push to origin, create or push a real tag, open or merge a pull request, publish anything, or run the real release sequence.
  - Do not use a real model key, a Telegram bot, the public IPM registry or any registry.
- Let any option, variable or configuration key answer an ASK or skip a gate.
- **Leave Epic 0's and Epic 29's lines alone.**
  - Do not edit `release/release.sh`: no rehearsal mode and no step change here (11.29's; Epic 0 owns its `:48` and `:575`).
  - Do not edit `docker/tests/test-release-sequence.sh`, `release/upgrade-harness.sh`, `ci/warm.sh`, `ci/iris.sh`, `docker/tests/lib-live.sh` or `docker/tests/test-ci-changes.sh` (Epic 0).
  - Do not edit `release/demo-host-check.sh`, `release/demo-load.sh`, `docker/tests/test-online-host.sh` or `lib-online.sh` (Epic 29), or `.github/workflows/*`.
  - Do not change `release_config_read` or any existing line of `host_run`.
- Write a host name, address, `host:port` or URL with a literal host in any new file. Commit draft notes.
- Add a test to the hosted `checks` job (CHECK_SCRIPTS).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Update before launch | `Mode: release`; `v1.0.6` annotated on a commit with the candidate's tree; fake host restricted | Bundle `refs/tags/v1.0.6` copied, then `update 1.0.6`, then `status`. PASS lines; record `Result: updated`; notes "now runs"; `RESULT updated`, exit 0 | -- |
| Update after launch | Fake host public | Status `pendingVersion` 1.0.6, `nextReset` = `at`; notes name `<at>`; `RESULT scheduled <at>`, exit 0 | `pendingVersion` null, or `nextReset` not `at`: exit 1 naming the field |
| Host refuses | `update` exits 4 with one line | Last line `the demo host did not update: <line>`; record `Result: failed` and `Reason:`; notes "wasn't updated"; exit 1 | Nothing retried |
| Bad answers | An extra JSON key; another version; `status` without `access`; running not `<v>` after `updated`; ssh exit 255; a failed copy | Exit 1 with the field-naming reason, or `could not reach the demo host (ssh exit 255)`; notes "wasn't updated" | -- |
| No host | No `release.conf`, or one without `DEMO_SSH` | `SKIP` line; no transport call; record `Host: none configured`; notes "wasn't updated"; exit 3 | -- |
| Refusals | Unknown `DEMO_` key; config inside the repository; unreadable key; release `--ref <sha>`; rehearsal `--ref v<v>`; tag on another tree; lightweight tag; Candidate line for another version or rc; no `## Release sequence`; no notes file; relative `--record`; no `jq`; a rehearsal without `DEMO_STANDIN=yes`; a rehearsal record whose branch is `release/*` | Exit 2; the last line names the key or rule, never a value | No host contacted; nothing written |
| Stand-in host | `DEMO_STANDIN=yes`, either mode, the host answers well | The stand-in reason line; record `Host: a stand-in demo host (not the online demo)`; exit 3 | -- |
| Rehearsal ref | `Mode: rehearsal`, branch `rehearsal/1.0.6-rc1`, `--ref <sha>`, `DEMO_STANDIN=yes` | Bundle lists exactly `refs/heads/rehearsal/1.0.6-rc1` at `<sha>`; exit 3 with the stand-in line | -- |
| Live stand-in | `init 1.0.5`; restricted `update 1.0.6` from the hook's bundle; then public `update 1.0.7`; then `reset` | `updated` with running and golden 1.0.6; `scheduled` at `nextReset` with pending 1.0.7; after `reset`, running and golden 1.0.7 | `fault upgrade-version`: exit 1, one line, golden unchanged. `reset` with a golden that differs from the image refuses, while the update's own restore passes |

</intent-contract>

## Code Map

**Preconditions (the implement stage HALTs `blocked`, `missing prerequisite story`, naming what is missing):**
- **Epic 0's Story 0.15 is integrated forward into OCT-epic11 first.** The stand-in builds the root `Dockerfile`, and 0.15 adds a guard that goes red otherwise.
  - Today the root `Dockerfile` exists only on `origin/OCT-epic0` (`729ec3598fc169f9bc848429c5aeb42804caad7b`, commit `9c32e85cdc83beafd2eed7565cefb73d99255e84` "move the Dockerfile to the repository root").
  - OCT-epic11 (`81fa659ad4a2d3ceb65ce95361cefe78463a8e1a`) still has `docker/Dockerfile` only.
- **Stories 11.15 and 11.16 do NOT need to be merged.** The hook stands alone: 11.16 calls it, and this story's tests call it directly with 11.16's contract.

**`release/lib-release.sh`** (sourced by the harness, rehearse.sh, checklist.sh, notes.sh and release.sh; the Planner reviews every hunk; new lines only):
- **New key lists**, after `:82-83` `REHEARSAL_KEYS`: `DEMO_KEYS="SSH KEY PORT KNOWN_HOSTS STANDIN"` and `DEMO_PATH_KEYS="KEY KNOWN_HOSTS"`.
- **The configuration reader:**
  - `:209` `release_config_path` and `:214` `release_in_repo` are reused.
  - `:228-308` `release_config_read` is left unchanged. It already ignores non-`REHEARSAL_` keys (`:251-254`), so `DEMO_` lines do not disturb rehearse.sh (already met; AC5 pins it).
  - New `demo_config_read <file>`. It returns 0 (configured), 3 (none) or 2 (refused, with the reason in `DEMO_WHY`).
  - It repeats only the line parser of `release_config_read` (`:239-276`). Rule 2's reason for the copy: the rehearsal reader's required keys and refusals are its own, and changing its body would reopen 11.3's reviewed lines, which the Planner's new-functions-only rule protects.
- **`:312-355` `host_run`:** insert a `demo)` arm into the real-mode `case` (`:332`):
  - `dest=${DEMO_SSH:-}; key=${DEMO_KEY:-}; port=${DEMO_PORT:-}; local REHEARSAL_KNOWN_HOSTS=${DEMO_KNOWN_HOSTS:-}`;
  - the shadowing `local` lets the existing argv lines (`:350-354`) serve both, with no existing line changed.
  - The dry branch stays as it is: `demo` returns 2 there, and the hook unsets `REHEARSAL_MODE` first.
- **New `demo_status_judge <json> <updated|scheduled> <v> [<at>]`:**
  - it prints one detail per broken rule, and nothing when the status is good;
  - it copies `check_demo_status`'s key-set and type expressions (`release/demo-host-check.sh:409-419`, `iso_re` at `:276`). Epic 29's script runs as a script and cannot be sourced; IA3 pins the two key lists equal.
- `:409` `record_write`, `:448` `record_field` and `:96` `detail_clean` are reused. `record_write`'s fallback heading covers any record name.

**`release/demo-update.sh`** (new, 100755):
- **Header (Rule 14, contract only):** the call contract, the ref and bundle rule, the host's two commands with their answers, the exit codes and the host-side bundle location.
- **Sources** `lib-release.sh`; **needs** `git`, `jq` (already a dependency of `release/demo-host-check.sh` and `ci/changes.sh`, which runs on the IRIS runner) and `awk`.
- **Order:** options; then the record, mode and candidate; then the ref check; then the configuration; then the bundle, the copy, `update` and `status`; then the judgment; then the record and notes writes. Its output is the Public text.

**`docker/tests/demo-standin/`** (new; test infrastructure; every script ends in `.sh`, so 11.4's `no-outward` scan, `release/checklist.sh:382`, reads them):
- **`ocutalon-demo.sh`** (POSIX sh, 100755): the stand-in host command.
  - The login folder's `bin/ocutalon-demo` is a symlink to it, made by the test.
  - It reads `standin.conf` (project, compose file, base image, interval, anchor, access, fault).
  - It prints the status JSON with `printf`, keys in `write_status_fixture`'s order (`docker/tests/test-online-host.sh:310-312`).
- **`compose.yml`:**
  - a top-level `name:` from `${STANDIN_PROJECT:?}` (AD-23);
  - one service `iris`: `image: ${STANDIN_IMAGE:?}`, user 51773, `stop_grace_period: 60s`, the replaced entrypoint, and the `durable` volume at `/durable`;
  - a `golden` volume that no service mounts. Copies between the volumes go through `docker run --rm` on the built image.
- **`ssh-local.sh`** (100755): the transport.
  - It refuses an argv without `-o BatchMode=yes`, `-o StrictHostKeyChecking=yes` and `-i <file>`.
  - It logs the argv (key path and destination masked) and the stdin byte count.
  - It runs `sh -c "<cmd>"` in `$DEMO_LOGIN_DIR`, with the login folder's `bin` first on `PATH`.
- **`fake-ocutalon-demo.sh`** (100755): the canned host for the hermetic cases. It answers from flag files, exits with planted codes, and logs each call.
- **`make-repo.sh`** (100755): makes a throwaway clone of the checkout's HEAD for the live parts.
  - It commits the root `Dockerfile`'s required placeholder `src/ocutalon/csp/index.html` and a `src/module.xml` version per release, and makes the annotated tags.
  - It lives here rather than in the live script, because `test-ci-config.sh`'s bundle-marker scan (`:1159-1186`) reads the live script. The unit reads no built bundle, so it belongs in `NO_WEB_BUNDLE_UNITS`. See Decided 6.

**`docker/tests/test-demo-update.sh`** (new; the unit `live:demo-update`; `ci/iris.sh live demo-update --part <p>` passes the arguments through, `ci/iris.sh:669`):
- **`--part fake`** (hermetic, no Docker): the Matrix's rows against the fake host, the static scans (AC7), the contract case (IA1), the real checklist row (IA2) and the drift pin (IA3).
- **`--part hook`** (live): claims the lock, then `make-repo` 1.0.5 and 1.0.6, then `init 1.0.5`, then the fault case, then the hook's real restricted update to 1.0.6 through `ssh-local.sh` with `DEMO_STANDIN=yes`, then `down`. It runs `down` and releases the lock on failure too.
- **`--part schedule`** (live): the same set-up with 1.0.6 and 1.0.7, then `init 1.0.6`, then the public update to 1.0.7 (`scheduled`), then `reset`, then the reset-refusal case, then `down`.
- **No part runs every part.** CI runs `fake`, `hook` and `schedule` in order, one per call. A live part FAILs, and never SKIPs, when the base image is absent.

**`ci/units.sh`** (Epic 11's own entries; Epic 0 changes only `IRIS_INPUT` here):
- `:115` `group_units production` gains `live:demo-update`;
- `:212` `NO_WEB_BUNDLE_UNITS` gains it;
- `:225-243` `group_input_pattern` gains a `live:demo-update)` arm beside the `sign-in-2|3` arm. It claims `docker/tests/test-demo-update\.sh$`, `docker/tests/demo-standin/`, `release/demo-update\.sh$` and `release/lib-release\.sh$`.
- `release/x.sh` still runs no group (`test-ci-changes.sh:257`).
- The comment block gains the unit's measured seconds, as the file's convention is.

**`docker/tests/test-ci-config.sh`** (new lines only): one pin that `live:demo-update` is in `production` and in `NO_WEB_BUNDLE_UNITS`, and that `group_input_pattern production` claims the four paths.

**Read only:**
- `release/demo-host-check.sh:276`, `:398-437`;
- `docker/tests/test-online-host.sh:310-312` and `:845` (the row-15 expression);
- `docker/tests/lib-live.sh:56`, `:70`, `:99`, `:116`, `:145`;
- `ci/iris.sh:634-669` (`cmd_live`) and `:755-790` (teardown by tag);
- `docker/tests/test-rehearsal.sh:383-470` (the stub-ssh precedent);
- the root `Dockerfile` (after 0.15). It writes `/opt/ocutalon/version` from the first `<Version>` (`docker/Dockerfile:38-41` today), fails without `src/ocutalon/csp/index.html`, and has `/durable` owned by 51773.

## Tasks & Acceptance

**Execution:**
- **Task 0** (measure before code; the figures go into `## Verification`). With lane D's values and the tag `e11s18i`:
  1. On a `make-repo` clone, time `docker build --pull=false -f Dockerfile` cold and warm (warm = the layer cache from `ci/iris.sh build`), and confirm that no image was pulled.
  2. In the built image with a fresh volume, run `docker run --rm --entrypoint sh <image> -c 'id -u; cat /opt/ocutalon/version; touch /durable/x; command -v sleep cp'`.
  3. Check `git bundle create` from a temporary bare repository filled by `git fetch` of an annotated tag, and of a sha under `refs/heads/rehearsal/...`; then `list-heads`, `verify` and `clone`.
  4. Confirm that `ci/iris.sh teardown` removes a project, volume and image named in the stand-in's form.
  5. Confirm that `bash ci/changes.sh` with a planted change to `release/demo-update.sh` would run `production` alone.
- `release/lib-release.sh` -- the key lists, `demo_config_read`, the `host_run` `demo)` arm, `demo_status_judge` -- the hook's helpers; every consumer's self-test stays green.
- `release/demo-update.sh` -- the hook, as Boundaries and Public text say.
- `docker/tests/demo-standin/{ocutalon-demo.sh,compose.yml,ssh-local.sh,fake-ocutalon-demo.sh,make-repo.sh}` -- the stand-in, the transport, the fake host and the repository maker.
- `docker/tests/test-demo-update.sh` -- `--part fake|hook|schedule`, covering every AC and IA.
- `ci/units.sh` and `docker/tests/test-ci-config.sh` -- the unit in `production`, its claims, and its pin.

**Acceptance Criteria:**
- **AC1 (update before launch; REL-10, AD-25, CON-1).** Given the fake host answering `updated`, when the hook runs with `--ref v1.0.6`, then:
  - the transport log shows, in order, the bundle copy (its stdin byte count equals the bundle's size), `ocutalon-demo update 1.0.6` and `ocutalon-demo status`, each with the strict-host-key argv;
  - the copied bundle verifies and lists exactly `refs/tags/v1.0.6`, with the candidate's tree;
  - the last line is `RESULT updated`, exit 0;
  - the record holds `## Online demo update` (Public text), and `## Release sequence` is byte-identical;
  - the notes hold the "now runs" line;
  - the checkout's refs are unchanged.

  Given a `Mode: rehearsal` record with `DEMO_STANDIN=yes`, when the hook runs with `--ref <sha>`, then the bundle lists exactly `refs/heads/rehearsal/1.0.6-rc1` at `<sha>`, and the hook exits 3 with the stand-in line.
- **AC2 (scheduled).**
  - Given the fake host answering `scheduled` with a matching status, when the hook runs, then the last line is `RESULT scheduled <at>`, exit 0, and the notes line names `<at>`.
  - Given `pendingVersion` null, or a `nextReset` other than `at`, then the hook exits 1 naming the field.
- **AC3 (failures shown and recorded).** Given each failing row of the Matrix, when the hook runs, then:
  - the last line is its reason (for a refused `update`, the host's own line), with exit 1;
  - the record holds `Result: failed` and `Reason:`;
  - the notes say the online demo wasn't updated.
- **AC4 (no demo host; CON-5).** Given no `release.conf`, or one without `DEMO_SSH`, when the hook runs, then:
  - it prints the `SKIP` line, and the last line `no demo host is configured, so the online demo wasn't updated`, exit 3;
  - there is no transport call;
  - the record holds `Host: none configured`, and the notes hold the "wasn't updated" line.
- **AC5 (configuration, refusals, no value; AD-19).**
  - Given each refusal row, when the hook runs, then it exits 2, with no transport call and no file written.
  - Given planted `DEMO_SSH` and `DEMO_KEY` values, when a full run ends, then neither appears in any output line, the record, the notes or the transport log.
  - Given a `release.conf` holding both `REHEARSAL_` and `DEMO_` keys, then `release_config_read` still accepts it, and `test-rehearsal.sh` still passes.
- **AC6 (the stand-in; REL-10, AD-25; live).** Given the live stand-in with golden 1.0.5 from `init`, when `--part hook` and then `--part schedule` run, then:
  - the hook's restricted update, built from its copied tag bundle, answers `{"result":"updated","version":"1.0.6"}`, and `status` shows running and golden 1.0.6;
  - the hook ends with exit 3 and the stand-in "now runs" line;
  - the public `update 1.0.7` answers `scheduled` at `nextReset` with pending 1.0.7, and `reset` then gives running and golden 1.0.7;
  - `fault upgrade-version` gives a non-zero exit, one line, and golden unchanged;
  - `reset` refuses a golden that differs from the image, while the update's restore over the previous version passes;
  - no image was pulled;
  - after each part, no container, volume, image or folder of its project remains, and the lane lock is released.
- **AC7 (static).** Given the new and changed files, when `--part fake`'s scans run, then:
  - every file is ASCII, the scripts are mode 100755, and the hook has `umask 077`;
  - there is no `docker push|login|save|export|pull`, `printenv`, `set -x` or `declare -p`;
  - the hook calls no `ssh`, `scp` or `git push` directly, and the stand-in builds only with `--pull=false`;
  - no file matches the row-15 expression (`test-online-host.sh:845`);
  - a line planted in a copy of each file fails each scan, naming `file:line`.
- **AC8 (CI placement; REL-4).** Given `ci/units.sh`, when the CI checks read it, then:
  - `live:demo-update` is in `production` and in `NO_WEB_BUNDLE_UNITS`;
  - a change to `release/demo-update.sh` or `docker/tests/demo-standin/` runs `production` alone, and `release/x.sh` runs no group;
  - `test-ci-config.sh` passes with the new pin, and `test-ci-changes.sh` passes unchanged.
- **IA1 (consumer: 11.16's `demo` step, through its call contract).** Given the contract of `spec-11-16…md:289-293`, when a test calls the hook exactly as 11.16 does, then the exit code and last line map to 11.16's rows as its Matrix states:
  - `updated` and `scheduled <at>` give exit 0 with the `RESULT` line;
  - no host, or a stand-in, gives exit 3, which 11.16 rows `not updated`;
  - a refused `update` gives exit 1 with `the demo host did not update: <line>`, which 11.16 shows as `FAIL demo release/demo-update.sh exited 1: <line>`.

  "Exactly as 11.16 does" means from the checkout's root, with stdin from `/dev/null`, absolute `--record` and `--notes`, and the output captured to a log.
- **IA2 (consumes 11.4's real `no-outward` row).** Given a throwaway clone of the tree with this story's files, when the real `release/checklist.sh` runs there, then its `no-outward` line reads PASS.
- **IA3 (drift pin with Epic 29).** Given `release/demo-host-check.sh`, when `--part fake` extracts its seven-key list, then the list equals `demo_status_judge`'s.
- **Standing (Rule 19).** Given a fresh environment, when the tests added or changed run in either order, then every one passes.

## Spec Change Log

## Review Triage Log

## Design Notes

**Consumed-by:**
- **11.16's `demo` step**, through its call contract. 11.16's own AC7 uses a stub hook. The real hook's join with the real step is proved by 11.29.
- **Story 11.29's rehearsal**, through the stand-in and the hook with a commit ref (`Mode: rehearsal`).
- **Epic 29's H19:** the Planner checks the real host's `ocutalon-demo` against this contract and the stand-in.

**Consumes:**
- 11.16: the contract (IA1);
- 11.3: `host_run`, its seam `OCUTALON_REHEARSAL_SSH`, and `release_config_path`;
- 11.5 and 11.14: the record's `Mode:` and `Candidate:` lines, and `record_write`;
- 11.13: the draft notes file;
- 11.4: the `no-outward` row (IA2);
- Epic 29: the status rules (IA3);
- lib-live: the lock and name helpers.

**Integration ACs (Rule 1):** IA1, IA2 and IA3.

**Extend, don't copy (Rule 2):**
- the `host_run` `demo)` arm extends `host_run`;
- the stand-in's naming and lock extend lib-live's helpers;
- `make-repo.sh` follows 11.14's `newcase` throwaway pattern;
- the fake host follows `test-rehearsal.sh:383-470`'s stub-ssh precedent.

The two copies, `demo_config_read`'s parser and `demo_status_judge`'s rules, carry their reasons in the Code Map.

**Governing ADs (Rule 6):**
- **AD-25:** the hook's interface, the two results, the one-line non-zero exit, the notes time, "no host: say so", and the golden-copy order and exemption that the stand-in follows.
- **AD-19:** configuration outside the repository; no value printed.
- **AD-22:** throwaways only, no registry, and the CI unit.
- **AD-23:** the image's version comes from the bundle's `src/module.xml`, through the root `Dockerfile` (0.15); every compose file has its own `name:`.
- **AD-29** (amended today, about the merge back): `release/` is Lane A's, and Epic 11 may change either lane's files. The merge back is 11.16's, and this story does not touch it.
- No AC contradicts an AD.

**Already met (not rebuilt):**
- `OCUTALON_REHEARSAL_SSH` in `host_run` (`lib-release.sh:346`);
- `release_config_read` ignores `DEMO_` lines;
- AD-25's status rules (`check_demo_status`);
- the record's `Mode: release` and `Candidate:` lines (`release.sh:227-228`).

**Not met:** no hook, no `ocutalon-demo` and no stand-in exist in the repository.

**Re-checked against the two-half plan (`set-aside/…-parts-A-B.reference.md`; part A carried over):**
- **Changed: the tag.** 11.16 puts `v<v>` on `main`'s merge commit (`spec-11-16…md:283`), not on the cut. So the hook checks that the tag's tree equals the candidate's tree, where the two-half plan checked that the tag pointed at the candidate's commit.
- **Changed: IA1.** 11.16 is not merged (`ready-for-dev`), so IA1 calls the hook through 11.16's written contract instead of the real `step_demo`. The two-half plan's `demostep` rule and every `test-release-sequence.sh` change move to 11.29.
- **Changed: the live part is split.** It is cut into `hook` and `schedule`, so that each call fits in about 150 s (Rule 18 (5)).
- **Changed: script names.** The stand-in's scripts end in `.sh`, so 11.4's scan reads them (`checklist.sh:382` reads only `.sh`, `.mjs` and `.js` files).
- **Changed: the placeholder bundle file.** It is written by `make-repo.sh` (see Decided 6).
- **Unchanged:** `lib-release.sh`'s line anchors, the `check_demo_status` lines, the CI figures (`production` 28.2 min on run 42584413449, `iris (production)` 08:38:41Z to 09:06:53Z; run 42593509898 skipped it), and the `checks` job (17.1 min on 42584413449, 15.8 min on 42593509898).

**Decided in-stage (small, reversible, within intent):**
1. **The reason alone on the last line.** A non-zero exit's last line is the reason alone, and exit 3 also covers "a stand-in was updated". 11.16 then rows it `not updated`, so no release row ever calls a stand-in "updated".
2. **The stand-in models only IRIS's in-place upgrade** (the version-marker copy). The image, the volumes and the golden-copy moves are real Docker objects. The upgrade itself is 11.2's harness's proof, and the real host is H19's.
3. **`DEMO_STANDIN=yes` marks a stand-in, and a rehearsal requires it.** A rehearsal can therefore never reach the online demo.
4. **The status check adds two rules:** `access` (`restricted` with `updated`, `public` with `scheduled`) and `nextReset` = `at`. A host that contradicts its own answer then fails.
5. **No polling.** The update blocks until ready, as AD-25 says. The hook runs in the author's terminal, which has no 10-minute cap.
6. **The placeholder `index.html` comes from `make-repo.sh`.** The unit reads no built bundle: the root `Dockerfile` needs only a file to exist. So `live:demo-update` is truthfully in `NO_WEB_BUNDLE_UNITS`, and the production group does not grow into web changes.
7. **The hook supports `Mode: rehearsal` now.** It accepts a commit ref with `Mode: rehearsal`, so Story 11.29 does not reopen the hook (Consumed-by).
8. **A live part FAILs when the base image is absent.** `ci/iris.sh`'s preflight already FAILs then (`ci/iris.sh:115-117`), and a SKIP would read as a pass.

**Contended paths and footprint:**
- Epic 0 (0.15) also changes `ci/units.sh` (only `IRIS_INPUT`, `:200`). This story's hunks there are `:115`, `:212` and `:225-243`.
- No line of `release.sh`, `test-release-sequence.sh`, `upgrade-harness.sh`, `ci/warm.sh`, `ci/iris.sh` or `lib-live.sh` is changed.
- **`footprint_extensions`:** `docker/tests/demo-standin/`, `docker/tests/test-demo-update.sh`, `ci/units.sh` (Epic 11 entries) and `docker/tests/test-ci-config.sh` (one pin).

**CI budget (REL-4):**
- `checks` does not grow: there is no new CHECK_SCRIPTS entry.
- `production` measured 28.2 min. `live:demo-update` adds about 3-5 min (inference: no IRIS start; four cached builds; the hermetic part under 1 min), which keeps the group under 35.
- Task 0 and the first CI run replace the inference. A projection over 35 min (2,100 s) is reported to the Planner, and the unit is never moved silently.

**Ledger (Rule 17):** the inbox is empty, and no entry is owned.

**PLANNER REPORT.** Each of these cannot be proved without acting outward, and nothing is built around it:
- the real host's `ocutalon-demo` and its bundle location (H19, the Planner on the host);
- the real SSH leg and key handling against the real host;
- a real `updated` or `scheduled` on the online demo.

The Planner proves them at the first daily release after 11.16 and this story merge, with the author's word.

### Public text

All new. Nothing names a host, an address, a rival entrant or "IRIS Couch". No README or docs line changes.

**`release/demo-update.sh`** (the author sees these lines in `<state>/demo.log`, and 11.16 shows the last one):
- **Progress lines:**
  - `PASS demo-update bundle ocutalon-<v>.bundle: <ref> at <short>, <bytes> bytes, copied to <host phrase>`
  - `PASS demo-update update answered <the host's JSON>`
  - `PASS demo-update status running <r>, golden <g>, pending <p>, access <a>, next reset <nr>`
  - `NOTE demo-update the configured host is a stand-in (DEMO_STANDIN=yes), not the online demo`
  - `SKIP demo-update no demo host is configured`
- **Last lines, exit 0:**
  - `RESULT updated`
  - `RESULT scheduled <at>`
- **Last lines, exit 3:**
  - `no demo host is configured, so the online demo wasn't updated`
  - `a stand-in demo host now runs <v>; the online demo wasn't updated`
  - `a stand-in demo host updates to <v> at <at>; the online demo wasn't updated`
- **Last lines, exit 1:**
  - `could not reach the demo host (ssh exit 255)`
  - `the bundle could not be made: <git's line>`
  - `the bundle could not be copied to the demo host (exit <n>)`
  - `the demo host did not update: <its line>`
  - `the demo host's answer is not one of the two results: <its line>`
  - `the demo host's status could not be read (exit <n>)`
  - `the demo host's status does not have AD-25's seven keys`
  - `the demo host's status <field> is <value>, not <expected>`
- **Last lines, exit 2:**
  - `refused: <rule> (configuration)`, where the rule is one of:
    - `the configuration file is inside the repository; keep it outside`
    - `unknown key <KEY>`
    - `DEMO_KEY is not set`
    - `<KEY> names no readable file`
    - `DEMO_STANDIN must be yes or unset`
  - `refused: --version, --rc, --ref, --record and --notes are all required`
  - `refused: --record and --notes take absolute paths`
  - `refused: --ref <ref> does not fit Mode: <mode> (a release takes v<v>, a rehearsal its candidate commit)`
  - `refused: v<v> is not an annotated tag holding the tree of the candidate <short>`
  - `refused: the record's candidate is <v'> rc<n'>, not <v> rc<n>`
  - `refused: a rehearsal's candidate is rehearsal/<v>-rc<n>, not <branch> (U-203)`
  - `refused: a rehearsal updates only a stand-in demo host (DEMO_STANDIN=yes)`
  - `refused: the record has no "## Release sequence" section`
  - `refused: the draft notes do not exist`
  - `refused: jq is not installed`
  - `refused: unknown option <opt>`
- **The host phrase** is one of `the configured demo host`, `a stand-in demo host (not the online demo)` or `none configured`.
- **Header:**
  - line 2: `# bash release/demo-update.sh --version <v> --rc <n> --ref <v<v>|candidate sha> --record <abs record> --notes <abs draft>   (Story 11.18; called by release.sh's demo step, Story 11.16)`;
  - the rest of the header holds the contract only (Rule 14).

**Record section** (`release/records/<v>/rc<n>.md`, or 11.29's rehearsal record):
```
## Online demo update
Result: updated | scheduled | not updated | failed
Mode: <release|rehearsal>
Candidate: <v> rc<n>, <branch> at <sha>
Host: <host phrase>
Bundle: <ref> at <sha>, <bytes> bytes
Update: <the host's JSON, or its one line>
Status: running <r>, golden <g>, pending <p>, access <a>, next reset <nr>
Reason: <the last line>          (only with not updated or failed)
Run: <ISO> to <ISO>
```
Lines that did not happen are left out. With no host, for example, there is no `Bundle:`, `Update:` or `Status:` line.

**Draft notes:** the section `## Online demo update` holds one of these lines:
- `The online demo now runs OcuTalon <v>.`
- `The online demo updates to OcuTalon <v> at its next scheduled reset, <at>.`
- `The online demo wasn't updated with this release.` (no host, and every failure)
- `The online demo wasn't updated: a stand-in demo host was updated instead (<mode>).`

**`release.conf` keys** (documented in the hook's header only; values are never shown):
- `DEMO_SSH` (user@host);
- `DEMO_KEY` (the private key file);
- `DEMO_PORT`;
- `DEMO_KNOWN_HOSTS` (a known-hosts file);
- `DEMO_STANDIN=yes` (marks a stand-in).

**The stand-in's `ocutalon-demo`** (`docker/tests/demo-standin/ocutalon-demo.sh`; what the author sees when checking H19 against it):
- **`status`** prints `{"runningVersion":"<r>","goldenVersion":"<g>","lastReset":"<ISO>","lastResetKind":"scheduled","nextReset":"<ISO>","pendingVersion":null,"access":"restricted"}`. `pendingVersion` is a string while an update is pending, `lastResetKind` may be `unscheduled`, and `access` may be `public`.
- **`update <v>`** prints `{"result":"updated","version":"<v>"}` or `{"result":"scheduled","at":"<ISO>"}`.
- **`init <v>`** prints `initialized <v>`, `reset` prints `reset to <v>`, `access <a>` prints `access <a>`, and `down` prints `removed <project>`.
- **One-line failures:**
  - `the bundle for <v> is missing`
  - `the bundle holds <n> refs, not one`
  - `the bundle's src/module.xml reads <x>, not <v>`
  - `the base image is not on this host`
  - `the image for <v> did not build`
  - `the golden copy holds <g>, not the running version <p>`
  - `the upgraded copy reports <x>, not <v>`
  - `the instance was not ready within <s> s`
  - `reset refused: the golden copy holds <g>, but the image is <i>`
  - `unknown command <c>`

**`docker/tests/test-demo-update.sh` header:** `# live:demo-update (Story 11.18): the update hook release/demo-update.sh against a fake host (--part fake) and a throwaway stand-in demo host (--part hook, --part schedule); never a real host or SSH connection`

## Clarification Needed (non-blocking: the plan does not depend on the answers; for the lead's veto window)

The two-half plan's veto items 1, 2 and 4, re-checked; its items 3 (the rehearsal's public text) and 5 (the split, now ruled) went with part B or are settled.

1. **Credential handling (veto: security posture).** The author's `release.conf` gets new keys: `DEMO_SSH`, `DEMO_KEY`, `DEMO_PORT`, `DEMO_KNOWN_HOSTS` and `DEMO_STANDIN`. They follow 11.3's `REHEARSAL_` rules: outside the repository, never printed, strict host keys, `BatchMode`.
2. **The host-side contract (veto: an AD detail).**
   - The bundle sits at `ocutalon-demo/bundles/ocutalon-<v>.bundle` and holds exactly one ref, and the host checks that its `src/module.xml` reads `<v>`. This is U-208's provisional location.
   - The recommendation is one sentence added to AD-25's "release hook's interface", which the Planner applies to the real host (H19).
3. **CI placement:** a new unit, `live:demo-update`, in `production` (28.2 of 35 min), so the `checks` job does not grow.

## Verification

**How to run.**
- Run each command in its own foreground call with `timeout: 600000`, from the worktree root, with `TMPDIR` in the stage's scratch folder and `ANTHROPIC_API_KEY` unset.
- Each call must finish in about 150 s. If a part nears 120 s in Task 0 or later, cut it into more self-contained parts by case (each building its own images), never by sharing state across calls, and record the new parts here.
- **Lane D values for every live call:**
  - `OCUTALON_LOCK_DIR=<coordination>/locks/lane-d`
  - `OCUTALON_TEST_WEB_PORT=52804`
  - `OCUTALON_LOCK_OWNER='epic=11 stage=<stage>'`
  - `OCUTALON_RUN_TAG` `e11s18i` (implement), `e11s18q` (QA) or `e11s18r` (review)
- At most one throwaway at a time; never a slot, `ocutalon-aihub-test`, any `ocupilot*` container, `iris-community-edition` or another lane.

**Commands:**
- `(loop)` `bash docker/tests/test-demo-update.sh --part fake` -- expected: `PASS all`. Covers AC1-AC5, AC7, IA1, IA2 and IA3 (hermetic, no Docker).
- `(once)` `ci/iris.sh live demo-update --part hook`, with the lane D values -- expected: AC6's restricted, fault and hook lines pass; then no `ocutalon-demostandin-*` container, volume or image remains, and the lock is released.
- `(once)` `ci/iris.sh live demo-update --part schedule`, with the lane D values -- expected: AC6's scheduled, reset and reset-refusal lines pass, and the same clean-up.
- `(once)` `ci/iris.sh teardown`, with the same tag -- expected: nothing left. Also run it after any failure.
- `(once)` `bash docker/tests/test-release-notes.sh`, `test-release-checklist.sh`, `test-upgrade-harness.sh` and `test-online-host.sh`, one per call -- expected: exit 0 (they source or read `lib-release.sh`).
- `(once)` `bash docker/tests/test-rehearsal.sh` -- expected: exit 0. 11.14 measured it at about 150 s. If the harness backgrounds it, leave it to CI's `checks` job (`rehearsal` is in CHECK_SCRIPTS), and say so in the Auto Run Result.
- `(once)` `bash docker/tests/test-release-sequence.sh libs` -- expected: `PASS all rules`. It sources `lib-release.sh`; 11.14 measured the batch `libs refusals cut` at 29 s.
- `(once)` `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh` and `bash ci/changes.sh ci.yml`, one per call -- expected: exit 0 (AC8; 11.14 measured 79-89 s, 36 s and under 1 s).
- `(once)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(once)` `git diff --stat` against the story base `81fa659ad4a2d3ceb65ce95361cefe78463a8e1a`, or the merge of 0.15 when that is the base -- expected: no `.github/workflows/*`, no `release/release.sh`, no `test-release-sequence.sh`, no `release/records/`, no Epic 0 or Epic 29 file from Boundaries.

**Mutations (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**

| AC | Mutation |
| --- | --- |
| AC1 | bundle the integration head instead of the tag |
| AC2 | skip the `pendingVersion` check |
| AC3 | print `RESULT updated` after a non-zero `update` |
| AC4 | call the host with no `DEMO_SSH` |
| AC5 | put `DEMO_SSH` in the PASS bundle line |
| AC6 | capture golden before the version check |
| AC7 | drop `--pull=false` |
| AC8 | leave `live:demo-update` out of `group_units production` |
| IA1 | map the stand-in success to exit 0 |
| IA2 | add a `gh release create` line to a stand-in script |
| IA3 | drop `access` from the key list |

**Shared surfaces:**
- the signature of `lib-release.sh`'s `host_run` (a new `demo` value), sourced by the harness, rehearse.sh, checklist.sh, notes.sh, release.sh and their self-tests;
- the record's and the draft notes' `## ` sections (a new `## Online demo update`);
- AD-25's status keys, shared with Epic 29's check;
- `ci/units.sh`'s `production` group and `NO_WEB_BUNDLE_UNITS`, which `test-ci-config.sh`, `test-ci-changes.sh` and `test-release-sequence.sh:2583` read.

Every test added or changed passes on a fresh environment, in either order. Each part builds and removes its own repositories, configuration, transport, stand-in project, volumes and images.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned part A only (the hook and its stand-in), from the two-half plan, re-checked on `81fa659ad4a2d3ceb65ce95361cefe78463a8e1a`. The implement stage first needs Story 0.15 integrated forward (Code Map, Preconditions).
