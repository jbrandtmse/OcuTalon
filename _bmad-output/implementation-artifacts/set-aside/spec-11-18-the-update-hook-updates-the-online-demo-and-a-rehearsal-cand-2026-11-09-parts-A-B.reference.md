---
title: 'Story 11.18: The update hook updates the online demo, and a rehearsal candidate proves the sequence'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-16-the-sequence-asks-before-each-outward-step-after-the-gates.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-15-the-hands-on-gate-stops-the-sequence-and-its-resume-command.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-11-14-the-release-sequence-runs-every-gate-on-the-pushed-candidate.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Nothing updates the online demo. The Contest Planner updated it by hand for 1.0.0 to 1.0.4, and no record says how (`release/records/1.0.0/rc4.md:121` only states "The online demo runs 1.0.0"). Story 11.16's `demo` step calls `release/demo-update.sh` through a fixed contract, but the hook does not exist, and there is no stand-in demo host to test it against. Nothing has run the whole sequence (11.14's gates, 11.15's hands-on gate, 11.16's outward steps) end to end, and `release.sh` has no rehearsal mode. A rehearsal cut as `release/*` would trip the step epics' rc1 merge gate and reach the public origin (U-203).

**Approach:** Two halves, each usable alone (see Design Notes, "Split proposal").
- **A. The hook and the stand-in.**
  - `release/demo-update.sh` keeps 11.16's call contract and AD-25's interface. It makes a one-ref `git bundle`, copies it over SSH (`host_run demo`, with `DEMO_` keys from the author's `release.conf`), runs `ocutalon-demo update <v>` and then `ocutalon-demo status`, and judges both answers. It writes its own record section and the draft notes' online-demo section.
  - A throwaway compose stand-in in `docker/tests/demo-standin/` answers `status` and `update` as AD-25 says. It builds the image from the copied bundle and keeps a golden-copy volume.
  - Both are tested by a new runner unit, `live:demo-update`.
- **B. Rehearsal mode.**
  - `release.sh start --version <v> --rehearsal` cuts `rehearsal/<v>-rc<n>` and works only against local bare repositories. Its record reads `Mode: rehearsal`.
  - The outward steps never act in it, and `demo` passes the cut commit to the hook.
  - The proof is a run from the cut to `demo` with 11.14's fixture gates and a fixture pass record, first against the fake host and then against the live stand-in.

## Boundaries & Constraints

**Always:**
- **The conventions of 11.5 and 11.14 to 11.16 hold:**
  - Bash 3.2 and ASCII (Rule 14); scripts tracked at mode 100755; `umask 077`; the main guard;
  - answers only on stdin through `ask`; exit codes 0, 1, 2, 4 and 5 keep their meaning;
  - every detail goes through `detail_clean`;
  - no environment value is printed (no `env`, `printenv`, `set -x` or `declare -p`);
  - never `docker push|login|save|export|pull`, and never a registry sign-in (CON-1).
- **The hook keeps 11.16's call contract exactly.** The call is `bash release/demo-update.sh --version <v> --rc <n> --ref <ref> --record <abs record> --notes <abs draft>`, run from the author's checkout with stdin closed. The contract's lines and exit codes:
  - progress lines first (Public text);
  - the **last line**:
    - exit 0: `RESULT updated` or `RESULT scheduled <at>`;
    - exit 3 (the online demo was not updated, and nothing failed): the reason alone;
    - exit 1 (failed) or 2 (refused, nothing sent and nothing written): the reason alone.
  - 11.16 shows that last line as it is.
- **The ref comes from the record's `## Release sequence` `Mode:`.**
  - `Mode: release` needs `--ref v<v>`: an annotated tag in the checkout that points at the candidate's commit (the `Candidate:` sha).
  - `Mode: rehearsal` needs `--ref <the candidate's 40-hex sha>`.
  - Anything else is refused.
- **The bundle** holds exactly one ref:
  - `refs/tags/v<v>` for a release;
  - `refs/heads/rehearsal/<v>-rc<n>` at the cut sha for a rehearsal, because a rehearsal has no tag.

  It is made in a temporary bare repository filled by `git fetch` from the checkout. The checkout's refs never change, and nothing is pushed. `git bundle verify` must pass. The bundle goes over `host_run demo` on stdin into `ocutalon-demo/bundles/ocutalon-<v>.bundle` (relative to the login folder): written as `.part`, then renamed.
- **The host's answers are judged; none is taken on trust:**
  - `update` exits 0 with exactly `{"result":"updated","version":"<v>"}` or `{"result":"scheduled","at":"<UTC ISO 8601>"}`. Whitespace between JSON tokens is allowed; anything else fails.
  - A non-zero `update` is shown and recorded as its one line.
  - `status` has exactly AD-25's seven keys, with their types: the rules of `check_demo_status`, `release/demo-host-check.sh:398-437`.
  - After `updated`: `runningVersion` and `goldenVersion` are `<v>`, `pendingVersion` is null and `access` is `restricted`.
  - After `scheduled`: `pendingVersion` is `<v>`, `access` is `public`, and `nextReset` equals `at`.
  - ssh exit 255 means the host could not be reached.
- **Configuration (AD-19, AD-25, CON-5).** A new `demo_config_read` reads only `DEMO_` keys from `release_config_path`'s file. Its rules:
  - **Keys:** `DEMO_SSH` (user@host) and `DEMO_KEY` are required together. `DEMO_PORT`, `DEMO_KNOWN_HOSTS` and `DEMO_STANDIN` (`yes` or unset) are optional.
  - **No demo host:** no file, or a file with no `DEMO_SSH`, means no demo host is configured. The hook says so, exits 3 and contacts no host.
  - **Refusals (exit 2):** a file inside the repository, an unknown `DEMO_` key, a missing or unreadable key or known-hosts file, and a `DEMO_STANDIN` other than `yes`.
  - **Values stay private.** None is ever printed, recorded or logged. The record names the host only as `the configured demo host`, `a stand-in demo host (not the online demo)` or `none configured`.
- **Only the online demo counts as updated.**
  - With `DEMO_STANDIN=yes`, in either mode, a successful `updated` or `scheduled` ends with exit 3 and a stand-in reason line. 11.16's row therefore reads `not updated`, and the notes say a stand-in was updated.
  - In `Mode: rehearsal`, a configured host without `DEMO_STANDIN=yes` is refused (exit 2) before any contact.
- **The stand-in (`docker/tests/demo-standin/`)** is test infrastructure:
  - **Project and images:** a compose project named in lib-live's form, `ocutalon-demostandin-<OCUTALON_RUN_TAG>-<epoch>-<pid>`, so `ci/iris.sh teardown` removes it. Its images are named from the project.
  - **Lock:** each live part holds the lane's `throwaway-iris.lock` through lib-live's `live_lock_claim`/`live_lock_release`.
  - **Build:** it clones the copied bundle and builds the **root `Dockerfile`** from it, on the local base image with `--pull=false`. It checks first that the base image is present, and never pulls.
  - **Volumes:** a `durable` volume and a `golden` volume.
  - **The modelled upgrade:** the container runs the built image with its entrypoint replaced. It copies `/opt/ocutalon/version` to `/durable/ocutalon.version`, which stands for IRIS's in-place upgrade, then writes `/durable/ocutalon.ready`.
  - **`update <v>`** follows AD-25's order: build before the boundary. With `access` public, it records `pendingVersion` and answers `scheduled` at `nextReset`. Otherwise:
    1. check that golden holds the running (previous) version (the update's exemption from the reset's version refusal);
    2. restore golden into durable, start on the new image, wait for ready, and check that the upgraded copy reports `<v>`;
    3. stop, capture golden without the ready marker, and start from it;
    4. answer `updated`.
  - **Failures:** any failure exits non-zero with one reason line and leaves golden unchanged.
  - **Stand-in-only commands:** `init <v>` (the first golden copy, from a fresh start), `reset` (applies a pending update; otherwise restores golden and refuses one whose version differs from the image's), `access restricted|public`, `fault <name>|none` and `down`. It removes only its own project's containers, volumes, images and folders.
- **Rehearsal mode (U-203).** `start --version <v> --rehearsal` sets `mode=rehearsal` in the state once. From then on:
  - the branch is `rehearsal/<v>-rc<n>`, the record `release/records/<v>/rehearsal-rc<n>.md`, the draft notes `release/records/<v>/rehearsal-rc<n>-notes.md` and the state folder `<v>-rehearsal-rc<n>`;
  - `next_rc` counts only `rehearsal/<v>-rc*` branches;
  - the record's `Mode:` reads `rehearsal`;
  - `next`, `resume` and `status` take `--rehearsal`. Without it they see only release states; with it, only rehearsal states;
  - every candidate name that release.sh prints, records or passes to a gate comes from the state's branch, never from a literal `release/`.
- **The rehearsal's guards** each print `REFUSED`, exit 2, and write or push nothing:
  - at `start`, any remote of the checkout whose URL is not a local path to a bare repository (named by the remote's name only, never its URL);
  - `--from` (a rehearsal is cut from the integration branch), and `--record`;
  - at `push`, a state branch outside `rehearsal/<v>-rc<n>`, which covers any `release/*` name (the pinned U-203 refusal), or a remote that is no longer a local bare repository.
- **In a rehearsal nothing goes out.**
  - `pr` still asks. A `no` is 11.16's skip; a `yes` FAILs (exit 1) before any `gh` or `git` call, and the next `next` asks again.
  - `merge`, `tag` and `mergeback` follow 11.16's "earlier step did not happen" rule. Their own `yes` paths FAIL in the same way, for a state planted past `pr`.
  - `demo` does not need the tag in a rehearsal. It asks the stand-in question and calls the hook with `--ref <cut sha>`.
- **Extend, don't copy (Rule 2):**
  - `release_config_path`, `release_in_repo`, `host_run` (a `demo)` branch), `record_write`, `record_field`, `candidate_branch`, `next_rc`, `record_path`, `notes_path`, `release_state_dir` and `earlier_hands` (each takes an optional trailing kind argument, and its default output stays byte-identical);
  - 11.14's `to_step` fixtures and `gh_repo` seam;
  - 11.15's `hands_put`;
  - 11.16's `step_demo`, `outward_word` and `to_outward`;
  - lib-live's lock and name helpers.
- **Tests use only throwaway repositories, local bare remotes, temporary `release.conf` files and HOME, and the local transport `docker/tests/demo-standin/ssh-local`** (through 11.3's seam `OCUTALON_REHEARSAL_SSH`). The transport checks the strict-host-key argv and runs the command in the host's login folder. It is never a real `ssh`.

**Never:**
- Touch the real online demo host, its address, its SSH key or its update endpoint. Open an SSH connection to any host. Read the author's real `release.conf` or `~/.ssh` in any test.
- Push to origin, create or push a real tag, open, merge or comment on a pull request, publish anything, or run the real release sequence. Use a real model key, a Telegram bot, the public IPM registry or any registry.
- Let any option, variable or configuration key answer an ASK, skip a gate, write a hands-on pass, or let a rehearsal record carry a pass over (REL-7: the Contest Planner's and the owner's).
- Have the script delete a branch on origin, or contact origin in a rehearsal.
- Edit `release.sh`'s header line ~48 ("Needs bash") or `step_image` (~575); `docker/tests/test-release-sequence.sh` lines ~200, ~511, ~1032 or ~2908; `release/upgrade-harness.sh`, `ci/warm.sh`, `ci/iris.sh`, `docker/tests/lib-live.sh`, `docker/tests/test-ci-changes.sh` (Epic 0); Epic 29's `release/demo-host-check.sh`, `release/demo-load.sh`, `docker/tests/test-online-host.sh` or `lib-online.sh`; `.github/workflows/*`; or the rc1 merge gate (`git ls-remote --heads origin release/1.0.0-rc1`).
- Add `rehearsal/*` to any workflow trigger. Commit the draft notes. Write a host name, address, `host:port` or URL with a literal host in any new file.
- Add a test to the hosted `checks` job (17.1 of its 20 minutes on run 42584413449).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Update before launch | `Mode: release`, `--ref v1.0.6` annotated on the candidate sha; fake host restricted | bundle `refs/tags/v1.0.6` copied, then `update 1.0.6`, then `status`. PASS lines; record `Result: updated`; notes "now runs"; `RESULT updated`, exit 0 | -- |
| Update after launch | fake host public | status `pendingVersion` 1.0.6, `nextReset` = `at`; notes name `<at>`; `RESULT scheduled <at>`, exit 0 | `pendingVersion` null, or `nextReset` not `at`: exit 1 |
| Host refuses | `update` exits 4 with one line | last line `the demo host did not update: <line>`; record `Result: failed` with the reason; notes "wasn't updated"; exit 1 | nothing retried |
| Bad answers | an extra JSON key; another version; `status` without `access`; running not `<v>` after `updated`; ssh exit 255; a failed copy | exit 1 with the field-naming reason or `could not reach the demo host (ssh exit 255)`; notes "wasn't updated" | -- |
| No host | no `release.conf`, or no `DEMO_SSH` | `SKIP` line; no transport call; record `Host: none configured`; notes "wasn't updated"; exit 3 | -- |
| Refusals | unknown `DEMO_` key; config in the repository; unreadable key; release `--ref <sha>`; rehearsal `--ref v<v>`; tag on another sha; no `## Release sequence`; no notes file; no `jq`; a rehearsal without `DEMO_STANDIN=yes` | exit 2; last line names the key or rule, never a value | no host contacted; nothing written |
| Stand-in host | `DEMO_STANDIN=yes`, any mode, host answers well | the stand-in reason line; record `Host: a stand-in demo host (not the online demo)`; exit 3 | -- |
| Live stand-in | golden 1.0.5 (`init`); restricted; `update 1.0.6` from the bundle; then public `update 1.0.7`; then `reset` | `updated`, running and golden 1.0.6; `scheduled` at `nextReset` with pending 1.0.7; after `reset`, running and golden 1.0.7 | `fault upgrade-version`: exit 1, one line, golden unchanged; `reset` with a golden that differs from the image refuses, while the update's own restore passes |
| Rehearsal start | `start --version 1.0.6 --rehearsal`; every remote a local bare repository | state `1.0.6-rehearsal-rc1`, branch `rehearsal/1.0.6-rc1`, record `rehearsal-rc1.md` with `Mode: rehearsal` | a network-URL remote (configured, never contacted), `--from release/1.0.6-rc1`, any `--from`, `--record`: REFUSED, nothing written |
| Push guard | the state's branch planted as `release/1.0.6-rc1` | REFUSED with the U-203 line at `push` | the bare remote unchanged |
| Rehearsal run | 11.14's fixture gates; 11.15's fixture pass; fake host or stand-in | push yes, every gate, hands-on stop, resume refused, pass written by the test, resume, `pr` declined, `merge`/`tag`/`mergeback` SKIP, `demo` yes with `--ref <cut sha>`; row `not updated` with the stand-in line; end text | `yes` at `pr`: FAIL rehearsal line, no `gh` call, asked again |

</intent-contract>

## Code Map

**Preconditions (the implement stage HALTs `blocked`, `missing prerequisite story`, naming what is missing):**
- Stories 11.15 and 11.16 are merged into OCT-epic11: `step_hands_on` reads `## Hands-on pass`, and `STEPS` ends `... hands-on pr merge tag mergeback demo`, with `step_demo`, `outward_word` and the self-test's `to_outward` and `hands_put`.
- Epic 0's Story 0.15 is merged into OCT-epic11 (the lead integrates it forward first). The `Dockerfile` is at the repository root and `docker/Dockerfile` is gone. Today the root `Dockerfile` exists only on `origin/OCT-epic0` (`729ec359`).

**`release/lib-release.sh`** (shared by the harness, rehearse.sh, checklist.sh, notes.sh and release.sh; the Planner reviews every hunk; additions and tiny extensions only):
- `:82-83` `REHEARSAL_KEYS`. New: `DEMO_KEYS="SSH KEY PORT KNOWN_HOSTS STANDIN"` and `DEMO_PATH_KEYS="KEY KNOWN_HOSTS"`.
- `:209` `release_config_path`, `:214` `release_in_repo`, `:228-308` `release_config_read`: the `REHEARSAL_` reader, left unchanged. The new `demo_config_read <file>` repeats only its line parser (Rule 2's copy reason: the rehearsal reader's required keys and refusals are the rehearsal's own, and changing its body would reopen 11.3's reviewed lines, which the Planner's new-functions-only rule protects). Returns 0 (configured), 3 (none) or 2 (refused, with `DEMO_WHY`).
- `:312-355` `host_run`: add a `demo)` branch to the real-mode `case` (`DEMO_SSH`, `DEMO_KEY`, `DEMO_PORT`, `DEMO_KNOWN_HOSTS`, with the same option list as `clean`). The dry branch stays as it is: `demo` returns 2 there. The hook unsets `REHEARSAL_MODE`.
- `:359-363` `record_path`, `notes_path`, `candidate_branch`; `:379` `next_rc`; `:102` `release_state_dir`. Each takes an optional last argument `rehearsal`, and with no argument its output is unchanged.
- `:448` `record_field`, `:409` `record_write`: reused. The record's fallback heading `# OcuTalon candidate record` covers `rehearsal-rc<n>.md`, so `record_write` is not changed.
- New `demo_status_judge <json> <updated|scheduled> <v> [<at>]`: one detail per broken rule, empty when good. It copies `check_demo_status`'s key-set and type expressions (Epic 29's script runs as a script and is not sourceable). An IA pins the two key lists equal.

**`release/demo-update.sh`** (new, 100755). The header holds the call contract, the bundle rule, the host's two commands with their answers, the exit codes and the host-side bundle location (Rule 14: contract only). It sources `lib-release.sh`, needs `git`, `jq` and `awk`, and runs: options, then record and mode, then the ref check, then the config, then the bundle, then the copy, then `update`, then `status`, then the judgment, then the record and notes writes. Its output is the Public text.

**`release/release.sh`** (1909 lines before 11.15 and 11.16; the Planner reviews every hunk):
- `:2-3` usage: `start` gains `[--rehearsal]`, and `next|resume|status` gains `[--rehearsal]`. A new header line 8 holds the U-203 sentences, and `cli_usage` (`:1622`, `sed -n '2,7p'`) prints lines 2 to 8.
- `:166` `earlier_hands` gains an optional prefix argument (`rc` by default; `rehearsal-rc` in a rehearsal). The real sums already skip `rehearsal-rc*.md` through the glob `rc*.md` (Already met).
- `:227` `echo "Mode: release"` becomes the state's mode.
- `:1027-1060` `step_push`: the rehearsal push guard comes before the ASK.
- `:1644-1678` `find_state`: filter by the state's `mode` key against `--rehearsal`. `load_state` uses the kind-aware `release_state_dir`.
- `:1747-1860` `cmd_start`:
  - `--rehearsal` parsed beside `--remote` (`:1756`); the guards before anything is written;
  - `mode` stored with `sset`;
  - `next_rc`, `candidate_branch`, `record_path` and `release_state_dir` called with the kind (`:1806`, `:1817`, `:1832`, `:1839`).
  - The `--from` refusal (`:1823-1824`) is unchanged.
- `:1867-1905` `release_main`: `--rehearsal` for `next|resume|status`.
- 11.16's `step_pr`, `step_merge`, `step_tag` and `step_mergeback` each get a rehearsal `FAIL` on `yes` before any `gh` or `git` call. `step_demo` gets the rehearsal branch: no tag needed, the stand-in ASK, `--ref <cut sha>`.
- `:1507` (rehearsal gate) and `:1071`/`:1575` already pass `"$branch"`. That is reused, not changed.

**`docker/tests/demo-standin/`** (new; test infrastructure):
- `ocutalon-demo` (POSIX sh, 100755): the stand-in host command. It reads `standin.conf` (project, compose file, base image, interval, anchor, access, fault) from its login folder, which the test writes. Its status JSON is printed with `printf`, keys in `write_status_fixture`'s order (`docker/tests/test-online-host.sh:308-312`).
- `compose.yml`:
  - a top-level `name:` (AD-23);
  - one service `iris`, `image: ${STANDIN_IMAGE}`, user 51773, `stop_grace_period: 60s`, the replaced entrypoint, and the `durable` volume at `/durable`;
  - a `golden` volume that no service mounts. Copies go through `docker run --rm` on the built image.
- `ssh-local` (100755): the local transport. It refuses an argv without `-o BatchMode=yes`, `-o StrictHostKeyChecking=yes` and `-i <file>`, and logs the argv (with the key path and destination masked) and the stdin byte count to a log file. It then runs `sh -c "<cmd>"` in `$DEMO_LOGIN_DIR`, with the host's `ocutalon-demo` first on `PATH`.
- `fake-ocutalon-demo` (100755): the canned host for hermetic cases. It answers `update` and `status` from flag files, exits with planted codes, and logs each call.

**`docker/tests/test-demo-update.sh`** (new, the unit `live:demo-update`):
- `--part fake`: the hook's hermetic cases, then `bash docker/tests/test-release-sequence.sh rehearsalmode rehearsalrun demostep`.
- `--part hook`: the live stand-in in release mode. It claims the lock, builds the stand-in, runs the cases, and runs `down` (also on failure).
- `--part rehearsal`: the live stand-in, then `rehearsalrun` with `OCUTALON_TEST_DEMO_STANDIN=<login dir>`, then the stand-in's status and bundle checks, then `down`.
- No part runs every part: CI runs `fake`, `hook` and `rehearsal` in order.
- It prints `SKIP` and exits 0 only when the base image `ocutalon-iris-base:2026.3.0AI.154.0` is absent and `CI` is unset. In CI an absent image FAILs.

**`docker/tests/test-release-sequence.sh`** (shared by 11.5 and 11.14 to 11.17):
- `:150` `rule`. New `runner_rule <name> <fn>`: it runs only when named, so the default run (the `checks` job) does not grow. The header says so, and so does a `t_static` pin that every `runner_rule` name appears in `test-demo-update.sh`.
- New runner rules after the existing ones: `rehearsalmode` (AC7, AC9, AC11), `rehearsalrun` (AC8, AC10, IA2, IA3) and `demostep` (IA1).
- They reuse `newcase` `:792` (the local bare origin), `rs` `:820`, `gh_runs`/`gh_green` `:848`/`:865`, `set_real` `:885`, `to_step` `:937`, 11.15's `hands_put` and 11.16's `to_outward`.
- The self-test's own `ssh` shim (`:416-419`) stays a network marker. The hook reaches the host only through `OCUTALON_REHEARSAL_SSH=<ssh-local>`.

**`ci/units.sh`** (Epic 11's own entries only; Epic 0 changes only `IRIS_INPUT` here):
- `group_units production` gains `live:demo-update`;
- `NO_WEB_BUNDLE_UNITS` gains it;
- `group_input_pattern` gains a `live:demo-update)` case claiming `docker/tests/test-demo-update\.sh$`, `docker/tests/demo-standin/`, `docker/tests/test-release-sequence\.sh$`, `release/demo-update\.sh$`, `release/release\.sh$` and `release/lib-release\.sh$`. `release/x.sh` still runs no group (`test-ci-changes.sh:257` stays green).
- `docker/tests/test-ci-config.sh`: only the pins that list the production group's units, if any name them.

**Read only:**
- `release/demo-host-check.sh:398-437`;
- `docker/tests/test-online-host.sh:308-312`;
- `docker/tests/lib-live.sh` (`:56` `live_tag_ok`, `:70` the project-name form, `:99` `live_lock_dir`, `:116` `live_lock_claim`, `:145` `live_lock_release`);
- `ci/iris.sh` (`:755-777` teardown by tag; `cmd_live` passes extra arguments to the script);
- `docker/tests/test-rehearsal.sh:383-470` (the stub-ssh precedent);
- the root `Dockerfile` (after 0.15). It writes `/opt/ocutalon/version` from the first `<Version>` (`docker/Dockerfile:38-41` today), fails without `src/ocutalon/csp/index.html`, and has `/durable` owned by 51773 (`:9`, `:46`).

## Tasks & Acceptance

**Execution:**
- **Task 0** (measure, before code; figures into `## Verification`):
  - On a scratch throwaway repository, time `docker build --pull=false -f Dockerfile` of a bundle clone with a placeholder `src/ocutalon/csp/index.html`, and confirm that no image was pulled.
  - In the built image with a fresh volume, run `docker run --rm --entrypoint sh <image> -c 'id -u; cat /opt/ocutalon/version; touch /durable/x; command -v sleep cp'`.
  - Check `git bundle create` from a temporary bare repository filled by `git fetch` of a tag, and of a sha under `refs/heads/rehearsal/...`, then `list-heads`, `verify` and `clone`.
  - Confirm `ci/iris.sh teardown` removes a project, volume and image named in the stand-in's form.
- `release/lib-release.sh` -- the helpers above -- every consumer's self-test stays green.
- `release/demo-update.sh` -- the hook -- part A.
- `docker/tests/demo-standin/{ocutalon-demo,compose.yml,ssh-local,fake-ocutalon-demo}` -- the stand-in, the transport and the fake host -- part A.
- `docker/tests/test-demo-update.sh` -- `--part fake|hook|rehearsal`, covering AC1 to AC6, AC12 and IA5 -- part A (its `rehearsal` part and the runner rules are part B).
- `ci/units.sh` (and `docker/tests/test-ci-config.sh` only if a pin lists the production group's units) -- the unit in `production` -- part A.
- `release/release.sh` -- rehearsal mode, the guards, the kind-aware names, the outward-step rehearsal FAILs, `step_demo`'s rehearsal branch, the header and usage -- part B.
- `docker/tests/test-release-sequence.sh` -- `runner_rule` and the three runner rules -- B (with `demostep` in A). Update every existing pin that a kind argument or the header line touches.

**Acceptance Criteria:**
- **AC1 (update before launch; REL-10, AD-25, CON-1).** Given the fake host answering `updated`, when the hook runs with `--ref v1.0.6`, then:
  - the transport log shows, in order, the bundle copy (stdin bytes equal to the bundle's size), `ocutalon-demo update 1.0.6` and `ocutalon-demo status`, each with the strict-host-key argv;
  - the copied bundle verifies and lists exactly `refs/tags/v1.0.6` at the candidate sha;
  - the last line is `RESULT updated`, exit 0;
  - the record holds `## Online demo update` (Public text), with `## Release sequence` byte-identical;
  - the notes hold the "now runs" line.
- **AC2 (scheduled).** Given the fake host answering `scheduled` with a matching status, when the hook runs, then the last line is `RESULT scheduled <at>`, exit 0, and the notes line names `<at>`. Given `pendingVersion` null, or a `nextReset` other than `at`, when the hook runs, then it exits 1 naming the field.
- **AC3 (failures shown and recorded).** Given each failing row of the Matrix, when the hook runs, then the last line is its reason (the host's own line for a refused `update`), with exit 1. The record holds `Result: failed` and `Reason:`, and the notes say the online demo wasn't updated.
- **AC4 (no demo host; CON-5).** Given no `release.conf`, or one without `DEMO_SSH`, when the hook runs, then:
  - the `SKIP` line, and the last line `no demo host is configured, so the online demo wasn't updated`, exit 3;
  - no transport call;
  - the record holds `Host: none configured`, and the notes hold the "wasn't updated" line.
- **AC5 (configuration, refusals, no value; AD-19).** Given each refusal row, when the hook runs, then it exits 2, with no transport call and no file written. Given planted `DEMO_SSH` and `DEMO_KEY` values, when a full run ends, then neither appears in any output line, record, notes or transport log. `test-rehearsal.sh` still passes with `release_config_read` unchanged.
- **AC6 (the stand-in; REL-10, AD-25; live).** Given the live stand-in with golden 1.0.5 from `init`, when `--part hook` runs, then:
  - the restricted `update 1.0.6`, built from the copied tag bundle, answers `{"result":"updated","version":"1.0.6"}`, and `status` shows running and golden 1.0.6;
  - the hook against it ends with exit 3 and the stand-in "runs" line;
  - the public `update 1.0.7` answers `scheduled` at `nextReset` with pending 1.0.7, and `reset` then gives running and golden 1.0.7;
  - `fault upgrade-version` gives a non-zero exit, one line, and golden unchanged;
  - `reset` refuses a golden that differs from the image, while the update's restore over the previous version passes;
  - no image was pulled;
  - after the part, no container, volume, image or folder of the project remains, and the lane lock is released.
- **AC7 (U-203).** Given `start --version 1.0.6 --rehearsal`, when it cuts and pushes, then:
  - the branch is `rehearsal/1.0.6-rc1`, and the record is `rehearsal-rc1.md` with `Mode: rehearsal`;
  - the bare remote holds no `release/*` ref after any step.

  Given a configured network-URL remote, `--from release/1.0.6-rc1`, `--record`, or a planted `release/1.0.6-rc1` branch in the state, when `start` or `push` runs, then each is REFUSED with its Public-text line, and nothing is written or pushed. A test pins the header's and the usage's U-203 lines.
- **AC8 (the rehearsal proves the sequence; REL-1, REL-3, REL-7).** Given a rehearsal candidate, 11.14's fixture gates, a fixture pass record written by the test and a host, when the author runs the sequence, then:
  - it asks before the push and pushes `rehearsal/1.0.6-rc1` on `yes`;
  - every gate step writes its row;
  - `hands-on` stops (exit 4), and `resume` is refused (exit 2) until the test writes the pass;
  - after the pass, `pr` is declined (SKIP), and `merge`, `tag` and `mergeback` SKIP with no ASK;
  - `demo` asks the stand-in question and calls the hook with `--ref <cut sha>`, and the bundle holds `refs/heads/rehearsal/1.0.6-rc1` at the cut sha;
  - the record holds the cut sha, each gate's result, the `demo` row `not updated` with the stand-in line, and `Hands-on time:` equal to the sum of the ASK windows.

  It runs with the fake host (hermetic), and with the live stand-in (`--part rehearsal`), whose running version is 1.0.6 afterwards.
- **AC9 (no carry-over; REL-7).** Given the rehearsal's passed record, when a real candidate tries to use it, then:
  - `start --version 1.0.6 --from rehearsal/1.0.6-rc1` in release mode is refused (already met: `release.sh:1823-1824`; pinned);
  - a real candidate whose source record reads `Mode: rehearsal` is refused by 11.15's R8 (pinned).
- **AC10 (nothing goes out in a rehearsal; REL-11).** Given a rehearsal at `pr` (and at `merge`, `tag` and `mergeback` in a state planted past `pr`), when the author answers `yes`, then:
  - the rehearsal FAIL, exit 1, and no `gh` call for that step in the shim log;
  - the bare remote unchanged, and the same ASK on the next `next`.

  After a full rehearsal, the bare remote's refs are only `rehearsal/1.0.6-rc1` and the integration branch, with its record commits.
- **AC11 (separate hands-on sums).** Given `rehearsal-rc1.md` and a real `rc1.md` of the same version, when either record's `Hands-on time:` is written, then the real record's earlier-candidates sum excludes the rehearsal's windows, and the rehearsal's sum covers only rehearsal records.
- **AC12 (static).** Given the new and changed files, when the static scans run, then:
  - they are ASCII, the scripts are mode 100755, and the hook has `umask 077`;
  - there is no `docker push|login|save|export|pull`, `printenv`, `set -x` or `declare -p`;
  - the hook has no direct `ssh`, `scp` or `git push`, and the stand-in builds only with `--pull=false`;
  - there is no IP address, `localhost`, `host:port` or URL with a literal host (Epic 29's row-15 expression);
  - `ci.yml` and `lane-a.yml` hold no `rehearsal/`;
  - a planted line in a copy fails each scan with `file:line`.
- **AC13 (CI placement; REL-4).** Given `ci/units.sh`, when the CI checks read it, then:
  - `live:demo-update` is in `production` and in `NO_WEB_BUNDLE_UNITS`;
  - `bash ci/changes.sh` with a change to `release/demo-update.sh` runs `production` alone, and with `release/x.sh` runs no group;
  - `test-ci-config.sh` and `test-ci-changes.sh` pass (the latter unchanged).
- **IA1 (consumes 11.16's real `demo` step).** Given the real `release.sh` at `demo` with the real hook and the fake host, when `yes` is answered, then:
  - `updated` gives the row `updated`;
  - `scheduled` gives the row `scheduled` with `<at>`;
  - no host, or a stand-in, gives `not updated` with the hook's last line;
  - a refused `update` gives 11.16's `FAIL demo release/demo-update.sh exited 1: the demo host did not update: <line>`.
- **IA2 (consumes 11.15's real gate).** Given a rehearsal at `hands-on`, when AC8's stop, `resume` and fixture pass run, then the stop, the refusal and the pass come from 11.15's real `step_hands_on`: its STOPPED and NOTE lines, R1 and P1, with the rehearsal branch in each text.
- **IA3 (consumes 11.14's real gate steps).** Given a rehearsal candidate and 11.14's fixtures, when the gate steps run, then each gate row comes from 11.14's real step, and the `ci` gate's logged `gh run list` names `--branch rehearsal/1.0.6-rc1` and never `release/`.
- **IA4 (consumes 11.4's real `no-outward` row).** Given the tree with this story's files, when the real `release/checklist.sh` `no-outward` row runs, then it passes.
- **IA5 (drift pin with Epic 29).** Given `release/demo-host-check.sh`, when the self-test extracts its key list, then the seven-key list extracted from `release/demo-host-check.sh` equals `demo_status_judge`'s.
- **Standing (Rule 19).** Given a fresh environment, when the tests added or changed run in either order, then every one passes.

## Spec Change Log

## Review Triage Log

## Design Notes

**Already met (not rebuilt):**
- **A release-mode `--from` never names a rehearsal branch:** `release.sh:1823-1824` accepts only `release/$version-rc<m>`. AC9 pins it.
- **`--integration` refuses `rehearsal/*`:** `release.sh:1783`.
- **Real hands-on sums skip rehearsal records:** `earlier_hands` globs `rc*.md` (`release.sh:169`), and rehearsal records are `rehearsal-rc*.md`.
- **No workflow triggers on `rehearsal/*`:** 11.14 added only `release/*`. AC12 pins it.
- **The `gh` seam for a local-path remote:** `gh_repo` (`lib-release.sh:628`, 11.14). The rehearsal's `ci` gate reads through it, and without the seam `ci` fails, so there is no false pass.
- **The program seam for ssh:** `OCUTALON_REHEARSAL_SSH` in `host_run` (`lib-release.sh:346`).
- **AD-25's status rules:** `check_demo_status` (`release/demo-host-check.sh:398-437`), reused by a pinned copy.
- **The gates already take the candidate from `$branch`:** `release.sh:1071`, `:1507`, `:1575`.
- **A rehearsal record never carries a pass over:** 11.15's `Mode: release` rule (R8) once 11.15 lands. This story only pins it.
- **Not met:** no hook, no `ocutalon-demo` and no stand-in exist anywhere in the repository (`spec-11-5…md:428`). `release/demo-host-checks.md:58` (H19) still waits for "Story 11.5's stand-in". No record says how the demo was updated by hand.

**Governing ADs (Rule 6):**
- **AD-25:** the hook interface, the two results, the one-line non-zero exit, the notes time, "no host: say so", and the golden-copy order and exemption, which the stand-in follows.
- **AD-19:** configuration outside the repository; no value printed.
- **AD-22:** throwaways only, no registry, and the CI unit.
- **AD-23:** the image's version comes from the bundle's `src/module.xml`, through the root `Dockerfile` (0.15). Every compose file has its own `name:`.
- **AD-29:** `release/` is Lane A's, and Epic 11 may change either lane's files. The rc1 gate keys on `release/1.0.0-rc1`, which a rehearsal never creates.
- No AC contradicts an AD.

**Decided in-stage (small, reversible, within intent):**
1. **A non-zero exit's last line is the reason alone**, and exit 3 also covers "a stand-in was updated". 11.16 then rows it `not updated`, and no release-mode row ever calls a stand-in "updated", with no new row text in `release.sh`.
2. **The stand-in models only IRIS's in-place upgrade** (the version-marker copy). The image, the volumes and the golden-copy moves are real Docker objects. The upgrade itself is 11.2's harness's proof, and the real host is H19.
3. **The rehearsal's gates are 11.14's fixtures.** A real gate cannot pass on a throwaway. The hands-on pass is a fixture written by the test (11.15's form), never by the script.
4. **`yes` at an outward step in a rehearsal FAILs and sends nothing.** This is stricter than "declines" and never looser. It also stops a `gh` seam that names a real repository from opening a real pull request.
5. **`DEMO_STANDIN=yes` marks a stand-in**, and a rehearsal requires it. A rehearsal can therefore never reach the online demo.
6. **The status check adds `access`** (`restricted` with `updated`, `public` with `scheduled`) and `nextReset = at`, so a host that contradicts its own answer fails.
7. **No polling.** The update blocks until ready, as AD-25 says. The hook runs in the author's terminal, which has no 10-minute cap.
8. **Rehearsal names sit beside the real ones** (`rehearsal-rc<n>.md`, `<v>-rehearsal-rc<n>`), so no real path, sum, rc number or state pick sees them.
9. **The stand-in lives in `docker/tests/demo-standin/`** (test infrastructure, not `release/`), and the production group claims that path. It is not left unclaimed, where it would run every group.
10. **The end text stays 11.16's** `stopped after demo: not merged and tagged (not a release)`. The record's `Mode: rehearsal` already marks it.

**Split proposal (recommended; the lead decides; product default 6).** One pass is large (inference, against 11.14's +436/+190/+1300 in one pass): `demo-update.sh` about +260 lines, `lib-release.sh` about +110, the stand-in files about +260, `test-demo-update.sh` about +550, `release.sh` about +130, and the self-test about +450.
- **11.18:** part A, the hook and the stand-in: AC1-AC6, AC12, AC13, IA1, IA4 and IA5. Its consumer is 11.16's `demo` step.
- **A sibling, 11.29 (the next free number in Epic 11):** part B, rehearsal mode and the end-to-end proof: AC7-AC11, IA2 and IA3, with the epics.md criterion "Given a rehearsal candidate..." and U-203 moved verbatim.

Each half is shippable alone. The Tasks above are tagged by part.

**Rules 1 and 2:**
- **Integration ACs:** IA1 (the consumer is 11.16's `step_demo`, and the observable effect is its row and line), IA2, IA3, IA4 and IA5.
- **Consumes:**
  - 11.16: `step_demo` and the contract, `outward_word`, `to_outward` (IA1, real);
  - 11.15: `step_hands_on` and the record form (IA2, real);
  - 11.14: the gate steps, `to_step`, `gh_repo`, `record_field` (IA3, real; the gate scripts are fixtures);
  - 11.5: the cut, push, `ask`, the state and `stop_routine`;
  - 11.4: the `no-outward` row (IA4);
  - 11.3: `host_run`, `record_write` and `release_config_path`;
  - 11.13: the draft notes;
  - Epic 29: the status rules (IA5);
  - lib-live: the lock and name helpers.
- **Consumed-by:**
  - 11.16's `demo` step, through the contract;
  - the Contest Planner's daily releases (1.0.6 on), through the proved sequence;
  - Epic 29's H19: the Planner checks the real host's `ocutalon-demo` against this contract and the stand-in.
- **Extend, don't copy:** as in Boundaries. The two copies, `demo_config_read`'s parser and `demo_status_judge`'s rules, carry their reasons in Code Map.

**Ledger (Rule 17):** the inbox is empty, and no entry is owned.

**Contended paths:**
- No path of Epic 41, 17 or 32 is touched.
- Epic 0 (0.15) also changes `ci/units.sh` (`IRIS_INPUT` only), `release/release.sh` (`:48`, `:575`) and `docker/tests/test-release-sequence.sh` (`:200`, `:511`, `:1032`, `:2908`). This story's hunks are elsewhere in each file.
- `test-ci-changes.sh` is Epic 0's and is not edited.
- **`footprint_extensions`:** `docker/tests/demo-standin/`, `docker/tests/test-demo-update.sh` and `ci/units.sh` (Epic 11 entries).

**CI budget (REL-4).**
- `checks` does not grow: the new rules are runner-only.
- `production` measured 28.2 min on run 42584413449 (11.14's head). `live:demo-update` adds about 2-4 min there (inference: no IRIS start, cached layers, the self-test's rehearsal rules at about 60-90 s), which stays under 35.
- A change to the claimed release files now runs `production` alone.

**PLANNER REPORT:** each of these cannot be proved without acting outward, and nothing is built around it:
- the real host's `ocutalon-demo` and its bundle location (H19, the Planner on the host);
- the real SSH leg and key handling against the real host;
- a real `updated` or `scheduled` on the online demo.

The Planner proves them at the first daily release after this story merges, with the author's word.

### Public text

New, for the lead's veto ruling (product default 3). None names a host, address, rival entrant or "IRIS Couch".

**`release/demo-update.sh`** (the author sees these lines in `<state>/demo.log`, and 11.16 shows the last one):
- `PASS demo-update bundle ocutalon-<v>.bundle: <ref> at <short>, <bytes> bytes, copied to <host phrase>`
- `PASS demo-update update answered <the host's JSON>`
- `PASS demo-update status running <r>, golden <g>, pending <p>, access <a>, next reset <nr>`
- `NOTE demo-update the configured host is a stand-in (DEMO_STANDIN=yes), not the online demo`
- `SKIP demo-update no demo host is configured`
- **Last lines:**
  - exit 0: `RESULT updated` and `RESULT scheduled <at>`.
  - exit 3:
    - `no demo host is configured, so the online demo wasn't updated`
    - `a stand-in demo host now runs <v>; the online demo wasn't updated`
    - `a stand-in demo host updates to <v> at <at>; the online demo wasn't updated`
  - exit 1:
    - `could not reach the demo host (ssh exit 255)`
    - `the bundle could not be made: <git's line>`
    - `the bundle could not be copied to the demo host (exit <n>)`
    - `the demo host did not update: <its line>`
    - `the demo host's answer is not one of the two results: <its line>`
    - `the demo host's status could not be read (exit <n>)`
    - `the demo host's status does not have AD-25's seven keys`
    - `the demo host's status <field> is <value>, not <expected>`
  - exit 2:
    - `refused: <rule> (configuration)`, where the rule is one of:
      - `the configuration file is inside the repository; keep it outside`
      - `unknown key <KEY>`
      - `DEMO_KEY is not set`
      - `<KEY> names no readable file`
      - `DEMO_STANDIN must be yes or unset`
    - `refused: --ref <ref> does not fit Mode: <mode> (a release takes v<v>, a rehearsal its cut commit)`
    - `refused: v<v> is not an annotated tag on the candidate <short>`
    - `refused: a rehearsal updates only a stand-in demo host (DEMO_STANDIN=yes)`
    - `refused: the record has no "## Release sequence" section`
    - `refused: the draft notes do not exist`
    - `refused: jq is not installed`
    - `refused: unknown option <opt>`
- The host phrase is one of `the configured demo host`, `a stand-in demo host (not the online demo)` or `none configured`.

**Record section** (`release/records/<v>/rc<n>.md` or `rehearsal-rc<n>.md`):
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
Lines that did not happen are left out (no host: no `Bundle:`, `Update:` or `Status:`).

**Draft notes**: the section `## Online demo update`, with one line:
- `The online demo now runs OcuTalon <v>.`
- `The online demo updates to OcuTalon <v> at its next scheduled reset, <at>.`
- `The online demo wasn't updated with this release.` (no host, and every failure)
- `The online demo wasn't updated: a stand-in demo host was updated instead (<mode>).`

**The stand-in's `ocutalon-demo`** (`docker/tests/demo-standin/ocutalon-demo`; what the author sees when checking H19 against it):
- `status` prints `{"runningVersion":"<r>","goldenVersion":"<g>","lastReset":"<ISO>","lastResetKind":"scheduled","nextReset":"<ISO>","pendingVersion":null,"access":"restricted"}`. `pendingVersion` is a string when an update is pending, `lastResetKind` may be `unscheduled`, and `access` may be `public`.
- `update <v>` prints `{"result":"updated","version":"<v>"}` or `{"result":"scheduled","at":"<ISO>"}`.
- One-line failures:
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

**`release/release.sh`:**
- Usage line 2 gains `[--rehearsal]` after `[--rc <n>]`. Line 3 reads `# release/release.sh next|resume|status [--version <v> --rc <n>] [--rehearsal]   (required when more than one state has steps left)`.
- New header and usage line 8: `# --rehearsal cuts rehearsal/<v>-rc<n>, never a release/* branch, and works only against local bare repositories; it never goes to origin (U-203). A rehearsal branch accidentally pushed to origin is deleted when the rehearsal ends, by the author or the Contest Planner; this script never contacts origin in a rehearsal.`
- REFUSED lines:
  - `REFUSED a rehearsal never uses a release/* branch: <name>; rehearsal candidates are rehearsal/<v>-rc<n> (U-203)`
  - `REFUSED a rehearsal works only against local bare repositories; remote <name> is not one`
  - `REFUSED a rehearsal candidate is cut from the integration branch; --from is not taken`
  - `REFUSED a rehearsal's record is release/records/<v>/rehearsal-rc<n>.md; --record is not taken`
- `FAIL <step> a rehearsal never opens the release pull request, merges, tags or merges back; nothing went out`
- `ASK demo Update the stand-in demo host to <v> from rehearsal/<v>-rc<n> (<short>)? [yes/no]`
- Record `Mode: rehearsal`.

**Self-test header lines** (`docker/tests/test-release-sequence.sh`):
- `runner rules run only when named; live:demo-update (docker/tests/test-demo-update.sh) runs them on the IRIS runner`
- `rehearsalmode (Story 11.18, AC7, AC9, AC11) rehearsal names, the U-203 refusals, no carry-over to a real candidate, separate hands-on sums`
- `rehearsalrun  (Story 11.18, AC8, AC10, IA2, IA3) a rehearsal from the cut to demo: fixture gates, the hands-on stop and a fixture pass, declined outward steps, the hook with the cut commit`
- `demostep      (Story 11.18, IA1) the real demo step with the real hook and the fake host`

No README or docs line changes.

## Clarification Needed (non-blocking: the plan does not depend on the answers; for the lead's veto window)

1. **Credentials handling (veto 1).** These are new keys in the author's `release.conf`: `DEMO_SSH`, `DEMO_KEY`, `DEMO_PORT`, `DEMO_KNOWN_HOSTS` and `DEMO_STANDIN`. They follow the same rules as 11.3's `REHEARSAL_` keys: outside the repository, never printed, strict host keys.
2. **The host-side contract (veto 9: an AD detail).** The bundle at `ocutalon-demo/bundles/ocutalon-<v>.bundle` holds exactly one ref, and the host checks that its `src/module.xml` reads `<v>`. This is U-208's provisional location. The recommendation is one sentence added to AD-25's "release hook's interface", which the Planner applies to the real host (H19).
3. **Public text (veto 5),** as listed above, and in particular the U-203 header line. Deleting a branch on origin is owner-only, so the text says who deletes it, and the script never does.
4. **CI placement:** a new unit `live:demo-update` in `production` (28.2 of 35 min), with runner-only rules, so the `checks` job does not grow.
5. **The split proposal** above.

## Verification

Run each command in its own foreground call with `timeout: 600000`, from the worktree root. Use `TMPDIR` in the stage's scratch folder, with `ANTHROPIC_API_KEY` unset. Each call must finish in about 150 s; if a part nears 120 s, split it with named rules and record the new parts here. `release/release.sh` and the hook run only inside the self-tests' throwaways.

Lane D values for every live call: `OCUTALON_LOCK_DIR=<coordination>/locks/lane-d`, `OCUTALON_TEST_WEB_PORT=52804`, `OCUTALON_LOCK_OWNER='epic=11 stage=<stage>'` (the stage's name: `implement`, `qa` or `review`) and `OCUTALON_RUN_TAG` `e11s18i` (implement), `e11s18q` (QA) or `e11s18r` (review).

**Commands:**
- `(loop)` `bash docker/tests/test-demo-update.sh --part fake` -- expected: `PASS all`. AC1-AC5, AC12, IA5, and the runner rules through the self-test. If it nears 120 s, run the self-test's runner rules as separate calls below.
- `(loop)` `bash docker/tests/test-release-sequence.sh rehearsalmode`, then `rehearsalrun`, then `demostep`, one per call -- expected: `PASS all rules`.
- `(once)` `ci/iris.sh live demo-update --part hook` with the lane D values -- expected: AC6 passes, then no `ocutalon-demostandin-*` container, volume or image remains, and the lock is released.
- `(once)` `ci/iris.sh live demo-update --part rehearsal` with the lane D values -- expected: AC8's live lines pass.
- `(once)` `ci/iris.sh teardown` with the same tag -- expected: nothing left (also run it after any failure).
- `(once)` The existing default batches of `test-release-sequence.sh`, one batch per call, as 11.14 to 11.16 measured them -- expected: `PASS all rules`, and the default run lists no runner rule.
- `(once)` `bash docker/tests/test-rehearsal.sh`, `test-release-checklist.sh`, `test-release-notes.sh`, `test-upgrade-harness.sh` and `test-online-host.sh`, one per call -- expected: exit 0.
- `(once)` `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-ci-changes.sh` and `bash ci/changes.sh ci.yml`, one per call -- expected: exit 0 (AC13).
- `(once)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0.
- `(once)` `git diff --stat` against the story base -- expected: no `.github/workflows/*`, no Epic 0 line listed in Boundaries, no `release/records/`.

**Mutations (Rule 19; one per AC, recorded as `mutation: <change> -> <test red>`):**

| AC | Mutation |
| --- | --- |
| AC1 | bundle the integration head instead of the tag |
| AC2 | skip the `pendingVersion` check |
| AC3 | print `RESULT updated` after a non-zero `update` |
| AC4 | call the host with no `DEMO_SSH` |
| AC5 | put `DEMO_SSH` in the PASS bundle line |
| AC6 | capture golden before the version check |
| AC7 | `candidate_branch` ignores the kind |
| AC8 | skip `--ref <cut sha>` in rehearsal (the tag rule applies) |
| AC9 | accept `rehearsal/` in the release-mode `--from` |
| AC10 | let `yes` at `pr` call `gh pr create` in a rehearsal |
| AC11 | `earlier_hands` globs `*rc*.md` |
| AC12 | drop `--pull=false` |
| AC13 | leave `live:demo-update` out of `group_units production` |
| IA1 | map the stand-in success to exit 0 |
| IA5 | drop `access` from the key list |

**Shared surfaces:**
- `lib-release.sh` signatures (`record_path`, `notes_path`, `candidate_branch`, `next_rc`, `release_state_dir`, `host_run`), sourced by the harness, rehearse.sh, checklist.sh, notes.sh and their self-tests;
- `release.sh`'s usage lines, state folder names, `Mode:` line and outward-step paths, which 11.5's and 11.14 to 11.16's pins read;
- the record's and the draft notes' `## ` sections;
- AD-25's status keys, shared with Epic 29's check;
- `ci/units.sh`'s production group and `NO_WEB_BUNDLE_UNITS`, which `test-ci-config.sh` and `test-ci-changes.sh` read.

Every test added or changed passes on a fresh environment, in either order. Each part builds and removes its own repositories, bare remotes, configuration, transport, stand-in project, volumes and images.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
