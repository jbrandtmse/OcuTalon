---
title: 'One script finds the image, starts OcuTalon and says where to sign in'
type: 'feature'
created: '2026-10-23'
status: 'done'
baseline_revision: '0ce80fd21437659672164fce39c7e4eb09705001'
baseline_commit: '0ce80fd21437659672164fce39c7e4eb09705001'
review_loop_iteration: 0
followup_review_recommended: true
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-10-context.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A judge who has loaded the build 154 image must today know the retag rule, the compose details and how to tell when OcuTalon is ready. Nothing checks the image's CPU, Docker, or the Compose 2.24 that the compose file's `env_file` form needs (DW-2), so a wrong setup fails late and unclearly.

**Approach:** Add a root `install.sh` (bash 3.2). It checks Docker, Compose and the image, and retags the image to the name the build uses. It creates `.env` from `.env.example` when none exists, then runs `docker compose up -d`. It shows progress until the compose health check passes, then prints the address and the README account. Two tests cover it:
- a stub-`docker` test on hosted Linux and on hosted macOS with `/bin/bash`, plus ShellCheck;
- a live unit on the IRIS runner that runs the real script, then the manual retag and a plain `docker compose up`, all in a throwaway project.

## Boundaries & Constraints

**Always:**
- **Before any change.** Every check (Docker CLI, daemon reachable, Compose plugin at 2.24 or later, a build 154 image whose architecture matches the daemon's) passes before anything is tagged, written or started. A failed check prints a plain-English message that names the problem and the exact fix, then exits 1.
- **Image candidates.** A Health candidate is a local image whose repository is `irishealth-community` or ends in `/irishealth-community`, with tag `2026.3.0AI.154.0`. A non-Health candidate has repository `iris-community` (or `/iris-community`) and the same tag.
- **The base name** is `${IRIS_IMAGE:-ocutalon-iris-base:2026.3.0AI.154.0}`, the name the Dockerfile's `FROM` receives through compose.
  - An existing base is never re-tagged.
  - A missing base is tagged from the chosen candidate. Tag by the image ID listed with it, so a reference that disappears between listing and tagging cannot fail the tag.
  - The chosen candidate is a Health one with the daemon's architecture if there is one, else a non-Health one. Ties go to the first reference in `LC_ALL=C` sort order.
- **The build argument.** The script exports `IRIS_IMAGE` for its compose call, so the build matches what it reports:
  - the non-Health image's own reference when the image in use is the non-Health one;
  - otherwise the base name.
- **What it says.** It says which image it used: IRIS for Health, IRIS (non-Health), or an existing base it cannot match to either, with the reference.
- **Architectures.** The daemon's architecture comes from `docker version --format '{{.Server.Arch}}'`. Image architectures come from `docker image inspect --format '{{.Architecture}}'`. `aarch64` counts as `arm64` and `x86_64` as `amd64`. Messages say "arm64" and "x64".
- **Where it runs.** The script `cd`s to its own folder, so it works from any directory.
- **Starting and waiting.**
  - It always runs `docker compose up -d`, so a rerun after an update rebuilds in place.
  - It polls `docker compose ps --all --format '{{.State}} {{.Health}}' iris` every 10 s and prints one progress line per poll, with the elapsed time and the state.
  - It waits up to 900 s. Two test-only overrides exist, `OCUTALON_INSTALL_POLL` and `OCUTALON_INSTALL_WAIT`. They take whole seconds, anything else falls back to the default, and nothing on the judges' path sets them.
- **When it is ready,** it prints:
  - the elapsed time;
  - `http://localhost:<port>/ocutalon/`, with the port taken from `docker compose port iris 52773`;
  - user `ocutalon` and password `ocutalon`.
- **When it stops or times out.** A stopped container (state `exited` or `dead`, or no container) or the end of the wait exits 1. The message names `docker compose logs iris` and the Troubleshooting section of README.md, and says that nothing was removed.
- **Source text.** `install.sh` is ASCII only, has LF line endings and git mode 100755.

**Never:**
- **Docker calls.** `install.sh` never runs `docker compose config`, and never runs `docker inspect` or `docker image inspect` without `--format`. It never runs push, login, logout, pull, save, export, rm, rmi, `image rm`, `volume rm`, prune, `compose down`, `compose stop` or `compose rm`, and never runs `sudo`.
- **`.env`.** It never reads, prints or overwrites `.env`. It only tests whether the file exists, and copies `.env.example` when it does not.
- **Shared runtimes.** No test of this story:
  - removes, re-tags or replaces `ocutalon-iris-base:2026.3.0AI.154.0`;
  - passes an image ID or the shared tag to `docker image rm`, or adds either to `LIVE_IMAGES`;
  - touches a slot or another lane's resources.
- **Contended files.** No edit to `docker/tests/lib-live.sh`, `docker/tests/test-ci-changes.sh`, `README.md`, `src/**`, `web/**`, `ci/mock/scenarios/**` or `.github/workflows/lane-a.yml`.
- **Out of scope:** the README text (Story 10.2), any Windows-native support (WSL only), and changes to `docker-compose.yml`, `.env.example` or `docker/Dockerfile`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First run, Health | Only `<prefix>/irishealth-community:2026.3.0AI.154.0` (daemon arch), no base, no `.env` | Names the Health image. Tags it as the base. Copies `.env.example` to `.env` byte for byte and says the key is empty. Runs `compose up -d` with `IRIS_IMAGE`=base. Prints progress lines, then the ready block with the published port, `ocutalon`/`ocutalon` and the elapsed time. Exits 0. | No error expected |
| Both images | Health and non-Health loaded, no base | Uses Health; it is the only `docker tag` source | No error expected |
| Only non-Health | Only `iris-community:2026.3.0AI.154.0` | Says IRIS (non-Health). Tags it as the base. `IRIS_IMAGE` = the non-Health reference. | No error expected |
| Prefixes and look-alikes | Bare, one-level and multi-level prefixes; `irishealth-community-x`, `myiris-community`, tag `2026.2` | Prefixed names match. Look-alikes and other tags are never candidates. | Look-alikes alone → "no image" row |
| Mixed CPUs | Health is x64 only, non-Health is arm64, daemon arm64 | Uses the non-Health arm64 image and says the Health image is for another CPU | No error expected |
| No image | No candidate, no base | Names the problem, the archive for this CPU (IRIS for Health AI Hub build 154, arm64 or x64) and `docker load -i <the archive file>`. No tag, no `.env`, no `up`. | exit 1 |
| Wrong CPU | Candidates exist but none matches the daemon | Names each image's CPU, the machine's CPU, the archive for this CPU and `docker load -i <the archive file>`. Nothing changes. | exit 1 |
| Existing base | Base present, matching architecture | No `docker tag`. Reports what the base is (Health or non-Health by ID match, else "existing image"), then continues. | No error expected |
| Existing base, wrong CPU | Base is x64, daemon arm64 | Gives the fix: load the arm64 archive, then `docker tag <loaded ref, named when one matches> <base>`. Nothing changes. | exit 1 |
| No Docker | `docker` not on PATH | Says to install Docker Desktop (macOS, Windows with WSL) or Docker Engine (Linux) | exit 1 |
| Daemon unreachable | `docker version` fails | Says Docker is not running or this user cannot reach it. Fixes: start Docker Desktop, `sudo systemctl start docker`, or add the user to the `docker` group. | exit 1 |
| No Compose plugin | `docker compose version` fails | Says to install the Compose plugin 2.24 or later (included with Docker Desktop; `docker-compose-plugin` package on Linux) | exit 1 |
| Compose too old (DW-2) | `--short` gives `2.23.3` or `v2.20.2` | Refuses before any change. Names the found version, the minimum of 2.24, and how to upgrade. | exit 1 |
| Compose new enough (DW-2) | `2.24.0`, `v2.40.3-desktop.1`, `5.5.0` (measured locally) | Accepted | No error expected |
| Existing `.env` | `.env` holds a sentinel value | `.env` is byte-identical afterwards. The sentinel never appears in stdout or stderr. | No error expected |
| Already healthy | Base and `.env` exist; the first poll answers `running healthy` | Prints the ready block without a progress line. No tag. | No error expected |
| Custom port | `compose port` prints `0.0.0.0:52999` | Address uses 52999 | No error expected |
| Never ready | Polls stay `running starting` past `OCUTALON_INSTALL_WAIT` | Prints the timeout message with the logs command and the README Troubleshooting section | exit 1, nothing removed |
| Container stops | A poll answers `exited` or `dead`, or answers nothing | Stop message with the logs command and the README section | exit 1, nothing removed |
| `up` fails | `compose up -d` exits non-zero | Plain message with the logs command and the README section | exit 1 |
| Other folder | Run as `bash <dir>/install.sh` from elsewhere | `.env` is created in `<dir>` | No error expected |

</intent-contract>

## Code Map

- `docker/Dockerfile:3-5` -- `ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0`, `FROM ${IRIS_IMAGE}`. Read only.
- `docker-compose.yml:2,10,14-18,21-26` -- `name: ocutalon`; passes `IRIS_IMAGE: ${IRIS_IMAGE:-...}`; optional `.env`; publishes `${OCUTALON_WEB_PORT:-52773}:52773`; health check with `start_period: 600s`. Read only.
- `.env.example` -- two empty variables. `test-compose-file.sh:310-323` pins its content, so do not edit it.
- `docker/tests/lib-live.sh`, used by the live unit but contended, so never edited:
  - `live_start` (53-84): sets `P`, `root`, `base_image`, the lock, `LIVE_FILES` (judges, decoy, throwaway, CI override, all absolute paths) and `trap live_cleanup EXIT`;
  - `live_web_port` (197-237): sets `web_port` and adds a `127.0.0.1` port file to `LIVE_FILES`;
  - `dc` (239-243); `wait_until` (282-293); `pass`, `fail`, `die` (269-278);
  - `live_cleanup` (261-267): `dc down -v --rmi local`, then `docker image rm -f` on `LIVE_IMAGES`. Never put an image ID or the shared tag there.
- `docker/tests/test-build-inputs.sh:20-31` -- precedent for a live script that runs its own compose command line.
- `docker/tests/test-bundle-folder.sh:151-154` -- sign in with the README account by curl, then check for `<app-root`.
- `docker/tests/test-ci-warm.sh:62-80,536-571` and `docker/tests/test-healthcheck.sh:14-50` -- stub executables on PATH with a call log, and a `check` helper.
- `ci/units.sh:6,35,60,74` -- `CHECK_SCRIPTS`, `group_units image`, `IRIS_INPUT`, `NOT_IRIS_INPUT_PATTERN` (keeps `.env.example`).
- `ci/iris.sh:369-388,463-500` -- `live <name>` runs `docker/tests/test-<name>.sh` from the root. `teardown` removes `^ocutalon-[a-z0-9-]+-<tag>-[0-9]{10}-[0-9]+([-_:]|$)` names, so it catches `$P-base:...` and `$P-src/...` and never the shared tag.
- `docker/tests/test-ci-changes.sh:241,254` -- contended, read only. Pins `.env.example` as running no group, and `install.sh` as unclassified (every group runs).
- `docker/tests/test-ci-config.sh`:
  - the runners rule at 207-211 and its description at 451;
  - the bad sample `runner-latest` at 366;
  - the header at 5-56;
  - `unit_reads` and `inputs_violations` at 924-976.
- `docker/tests/test-boundaries.sh:96,107-111` -- the scan scope (`$files`) and the must-scan list. `install.sh` is not in either yet.
- `.gitattributes` -- has no rule for root files other than `.env.example` and `.dockerignore`.
- `.github/workflows/ci.yml:28-39,86-125` -- the `checks` job, and the `iris` job's env (`IRIS_IMAGE`, `OCUTALON_LIVE_DEADLINE: "1200"`).

## Tasks & Acceptance

**Execution:**
- `install.sh` (new, mode 100755) -- implement the contract and matrix above. Header comment: what it does, the bash 3.2 rule, the two test-only overrides. Write it for bash 3.2 and BSD/GNU tools:
  - no `declare -A`, `mapfile`, `${v,,}`, `|&` or `&>>`;
  - no empty `"${a[@]}"` under `set -u`;
  - no `timeout`, `sed -i`, `grep -P`, `date -d` or `readlink -f`.
  It needs this to run on macOS's `/bin/bash`.
- `.gitattributes` -- add `install.sh text eol=lf`, so a Windows checkout used from WSL still runs it.
- `docker/tests/test-install-script.sh` (new, hermetic) -- covers every matrix row.
  - **Judge folder.** Copy `install.sh` and `.env.example` into a temporary judge folder.
  - **Stubs.** Put a stub `docker` and a stub `sleep` on PATH. The `sleep` stub logs its argument, then sleeps `STUB_SLEEP` seconds (default 0). The `docker` stub answers from per-scenario files (images list, architectures, server architecture, Compose version, one health line per poll with the last one repeated, the `up` exit code, the port line). It logs every call, and `IRIS_IMAGE` for `compose up`.
  - **Interpreter.** Run `install.sh` with `"$BASH"`.
  - **Per scenario, assert:**
    - the exit code;
    - the required output text;
    - that `docker tag` and `compose up` were or were not called, and their arguments;
    - the `.env` state.
  - **Across all scenarios, assert:**
    - every logged call matches an allow-list: `version --format`, `compose version`, `image ls --format`, `image inspect --format`, `tag`, `compose up -d`, `compose ps --all --format`, `compose port iris 52773`;
    - every logged sleep is at most 15;
    - `install.sh` holds `OCUTALON_INSTALL_WAIT:-900`;
    - `install.sh` has no CR byte;
    - `install.sh` has git mode 100755 when git tracks it (CI), else the executable bit (an uncommitted working tree).
  - **Bash version.** Print `BASH <version>`. When `OCUTALON_TEST_BASH_MAJOR` is set, fail unless it equals `BASH_VERSINFO[0]`.
  - **Text rules.** No key-shaped sentinel, and no forbidden docker words in the file's text (`test-boundaries` scans it).
- `docker/tests/test-install-script-live.sh` (new, live unit). The run order:
  1. `. "$(dirname "$0")/lib-live.sh"`, then `live_start t10`, `live_web_port`, and `trap` its own cleanup followed by `live_cleanup`.
  2. Record the ID of the base image and whether `$root/.env` exists.
  3. `docker tag "$base_image" "$P-src/irishealth-community:2026.3.0AI.154.0"`.
  4. Run `bash "$root/install.sh"` with `COMPOSE_PROJECT_NAME=$P`, `COMPOSE_FILE`=`LIVE_FILES` joined by `:`, `IRIS_IMAGE=$P-base:2026.3.0AI.154.0`, and `OCUTALON_INSTALL_WAIT` within the deadline.
  5. Assert: exit 0; a Health image named; `$P-base` has the base's ID; the printed URL's port is `web_port`; signing in at the printed URL with the printed user and password gives `<app-root`.
  6. Run it again. Assert the ready block prints without a progress line, the "existing" wording, and that the container ID is unchanged.
  7. `dc down` without `-v`.
  8. `docker image rm "$P-base:2026.3.0AI.154.0"` without `-f`. Assert it is gone and the shared tag's ID is unchanged.
  9. Run the manual command `docker tag "$P-src/irishealth-community:2026.3.0AI.154.0" "$P-base:2026.3.0AI.154.0"`.
  10. A plain `docker compose up -d` with the same environment and no script.
  11. Assert it reaches healthy, and that `docker volume inspect --format '{{.CreatedAt}}' ${P}_durable` is unchanged.

  Cleanup:
  - untag only the two `$P-` tags, without `-f`;
  - remove `$root/.env` only if this run created it;
  - then `live_cleanup`.
- `ci/units.sh` -- add `install-script` to `CHECK_SCRIPTS` and `live:install-script-live` last in `group_units image`. Leave `IRIS_INPUT` and `NOT_IRIS_INPUT_PATTERN` as they are.
- `.github/workflows/ci.yml`:
  - in `checks`, add the step `ShellCheck`: `shellcheck --version && shellcheck install.sh docker/tests/test-install-script.sh`;
  - add the job `install-macos` with `runs-on: macos-15`, `timeout-minutes: 10`, the same pinned checkout (`persist-credentials: false`), and the step `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh`;
  - add no job-level `if`, no secrets and no cache.
- `docker/tests/test-ci-config.sh`:
  - **runners:** accept `macos-15` as a hosted runner (so never-skipped applies), add the bad sample `macos-latest`, and update the header and the rule text;
  - **wiring:** pin the ShellCheck step in `checks` and the `install-macos` step text, each with a bad sample;
  - **inputs:** a live script may also read a path that no group claims, that `NOT_IRIS_INPUT_PATTERN` does not declare and that is not bookkeeping, because `ci/changes.sh` runs every group for it. A read of a declared non-input still fails. Add a pass sample and a fail sample, and update the header.
- `docker/tests/test-boundaries.sh` -- add `install.sh` to the `scan_files` scope at line 96 and to the must-scan list at lines 107-111, and update the header.

**Acceptance Criteria:**
- Given the hosted `checks` job, when CI runs, then `bash ci/checks.sh` runs `test-install-script.sh` on Linux with every matrix row passing, and the ShellCheck step passes on `install.sh` and the hermetic test.
- Given the `install-macos` job, when CI runs, then the hermetic test passes under `/bin/bash` 3.x.
- Given the IRIS runner's `image` group:
  - when `live:install-script-live` runs, then the real script reaches healthy in a throwaway project and its printed address and account sign in;
  - a rerun prints at once;
  - after the retag is removed and re-made by the manual command, a plain `docker compose up` reaches healthy on the same volume;
  - `ocutalon-iris-base:2026.3.0AI.154.0` keeps its ID throughout.

  This is the Integration AC: the consumer is the judges' compose path, which reads the base name that this script fixes.
- Given `test-boundaries.sh`, when it scans, then `install.sh` is in scope for the ASCII, push or sign-in, `config --quiet` and `inspect --format` rules.
- Given `test-ci-changes.sh` (unchanged), when it runs, then it still passes: `install.sh` stays unclassified (every group runs on its change, the new unit included) and `.env.example` stays declared.

## Spec Change Log

## Review Triage Log

### 2026-10-23 -- Review pass
- verdicts: 41 findings -- high 0, medium 6, low 30, false 5, maybe-false 0
- layers: Blind Hunter 10, Edge Case Hunter 15, Verification Gap 8, Intent Alignment 8 (its divergences, one row each)
- findings:
    - `[low]` `[patch]` Blind: Design Note 15's read-only branch (and the failed `cp` branch) has no test and no mutation line — real: deleting `[ ! -w . ]` left every test green. Patched: hermetic rows `read-only-folder` (skipped where the user can write to a mode 555 folder) and `cp-fails`, plus the mutation line.
    - `[medium]` `[patch]` Blind: the elapsed time and the 15-minute wait start when `up -d` returns, so the build is left out of "ready after" and of the wait — real: the figure feeds Story 11.3's first-start time. Patched: `started=$SECONDS` moved before `docker compose up -d`; the header comment, Design Note 14 and the hermetic row `up-takes-time` follow.
    - `[low]` `[reject]` Blind: `docker-compose.yml` is never checked before the tag and `.env` are written — the script lives beside the compose file, so a missing one means the script was copied away (not a supported use); the fix is a guard plus a row and the `.env.example` check already names the folder. reopen_if: a judge reports a failed `up` after a copied script.
    - `[low]` `[reject]` Blind: the `up -d` failure message does not name a busy port 52773 — the spec's row asks for the logs command and the README section, and the Troubleshooting section of Story 10.2 is where the usual causes (a busy port included) belong; extra text here is unspecified public wording.
    - `[low]` `[reject]` Blind: the README Troubleshooting section does not exist yet — Story 10.2 creates it and the spec's Consumed-by names the section; nothing in this story can add it (README.md is contended).
    - `[low]` `[patch]` Blind: the widened `inputs` rule — the comment in `ci/units.sh` did not say that `install.sh` stays unclassified, and `unclassified=0` meant "known". Patched: the comment now names the exception, and the variable is `known`. That every edit to `install.sh` runs all six groups is Design Note 12 (by-design; `test-ci-changes.sh` pins it).
    - `[low]` `[reject]` Blind: `macos-15` is accepted for any job by the `runners` rule — the spec's task says to accept `macos-15` as a hosted runner so never-skipped applies; the `install-macos` job's runner is pinned by the wiring rule (`macos-runner` sample).
    - `[medium]` `[patch]` Blind: the image tag is repeated in `install.sh`, the tests and the compose file, and nothing ties the script's copy to the compose default — real: a bump in one place leaves the judges' path tagging a different name, with every test green. Patched: a check that the script's `TAG` is the test's tag and the compose default's tag, with a mutation line.
    - `[low]` `[reject]` Blind: Ctrl-C during the wait prints nothing — the container keeps starting and a rerun is safe by design; a trap adds a branch and unspecified text. reopen_if: a judge reports confusion after an interrupted install.
    - `[low]` `[reject]` Blind: a failed `docker compose ps` is treated as a stopped container — the matrix row says a poll that "answers nothing" is a stop (exit 1, nothing removed), and a rerun resumes.
    - `[low]` `[patch]` Edge: a relative script path with `CDPATH` set resolves the folder through `CDPATH` — reproduced by the reviewer with a stub. Patched: `CDPATH='' cd -- "$here"`, with the row `cdpath` and a mutation line.
    - `[low]` `[reject]` Edge: a failed `docker image inspect` of the base name for a reason other than absence is read as absent — it needs a daemon that failed one call right after `docker version` passed; the guard adds a branch. reopen_if: a judge's existing base is re-pointed.
    - `[low]` `[reject]` Edge: a `cp` that fails midway (disk full) leaves a truncated `.env` — Design Note 9 makes `.env` a plain copy, the same as the manual `cp`.
    - `[low]` `[reject]` Edge: `.env.example` unreadable or `docker-compose.yml` missing is not checked — same root cause as the compose-file row above.
    - `[low]` `[reject]` Edge: a transient `docker compose ps` failure counts as a stop — same row as the Blind finding above (matrix: "answers nothing").
    - `[low]` `[reject]` Edge: command-line arguments (`--help`) are ignored and a full install starts — the script takes none by design; a usage branch is unspecified public text.
    - `[low]` `[reject]` Edge: a symlinked script cd's to the link's folder — the spec forbids `readlink -f` and names no symlink use.
    - `[low]` `[reject]` Edge: `OCUTALON_INSTALL_POLL=0` passes the whole-seconds check and spins — a test-only override that nothing on the judges' path sets.
    - `[low]` `[reject]` Edge: a docker call that never returns is not bounded — theoretical, and `timeout` is forbidden by the spec's portability list.
    - `[low]` `[reject]` Edge: a remote `DOCKER_HOST` makes `http://localhost` wrong — the spec's scope is a local Docker (macOS, Windows with WSL, Linux).
    - `[low]` `[patch]` Edge: the timeout message says the container "is still running" for any state, and the stop message says the container is "still there" when there is none — false claims in public text. Patched: the timeout names the state, the stop message says the script never removes anything.
    - `[low]` `[reject]` Edge: the live unit would pick another `irishealth-community` build 154 image with a different ID on a machine that holds one — the CI runner holds only the base name and a developer machine fails with a clear id mismatch.
    - `[false]` `[reject]` Edge (claim): `.env.example` stays a declared non-input, so an edit to it runs no group — Design Note 12 (by-design); `test-ci-changes.sh:241` pins it and its content is pinned to two empty variables.
    - `[medium]` `[patch]` Edge (claim): the live unit's `OCUTALON_INSTALL_WAIT` is computed before the script runs but the wait started after `up -d` — the same root cause as the clock finding; with the clock moved, the wait bounds the whole `up` and the poll.
    - `[low]` `[patch]` Edge (claim): the `wiring` header and PASS text say ShellCheck runs "before" the checks, which the rule does not compare. Patched: the order claim is removed from `test-ci-config.sh`.
    - `[medium]` `[patch]` Verification gap: `install.sh text eol=lf` is pinned by no test — real: deleting the line left every test green. Patched: `git check-attr eol` check in the hermetic test, with a mutation line.
    - `[low]` `[patch]` Verification gap: `fmt_time` (`N min M s`) is unpinned — swapping its operands left every test green. Patched: the function is cut out of `install.sh` and called with 45, 60 and 125, with a mutation line.
    - `[low]` `[reject]` Verification gap: the `LC_ALL=C` tie-break is unpinned — the effect is small (two same-tag, same-CPU candidates) and a pin needs a locale that sorts differently. reopen_if: a judge reports the wrong one of two same-CPU images used on a non-C locale.
    - `[low]` `[patch]` Verification gap: the 900 s default is pinned by source text only and the fallback value is unobserved — `max_wait=1` left every test green. Patched: the fallback rows (`soon`, empty) wait two real seconds, with a mutation line.
    - `[low]` `[patch]` Verification gap: the read-only folder and the `.env` copy failure have no test — same root cause as the first Blind finding (patched there).
    - `[low]` `[patch]` Verification gap (Rule 19): ACs and changes without a `mutation:` line (ShellCheck wiring and `CHECK_SCRIPTS`, the macOS pins beyond `/bin/bash`, the live rerun and sign-in, the boundaries scope, `install.sh` staying unclassified, the other inputs-widening branches). Patched: each mutation applied, seen red, reverted and written into `## Verification`.
    - `[low]` `[reject]` Verification gap (other): the live test is not linted and no hosted job syntax-checks it — Design Note 13 (it sources the contended `lib-live.sh`); it runs in the `image` group.
    - `[false]` `[reject]` Verification gap (hermeticity): the mode check reads git's index and the live unit needs the preloaded base — both are declared prerequisites (the AC names the mode; the unit's `die` names the missing base), and each test creates and removes the state it asserts on.
    - `[medium]` `[patch]` Intent: the elapsed time and the 900 s window start after `up -d` (the reading the diff took) — the same finding as the clock row above; patched there.
    - `[medium]` `[patch]` Intent: nothing compares the script's default base name with the compose file or the Dockerfile — the same finding as the tag row above; patched there.
    - `[low]` `[reject]` Intent: no README exists in the tree, so the "README account" and the Troubleshooting section are tied to nothing here — Story 10.2; the live unit pins the account by signing in.
    - `[false]` `[reject]` Intent: the Never rules are enforced by `test-boundaries.sh` more weakly than the intent states — the hermetic test scans every code line of `install.sh` for the forbidden words and checks the allow-list of the calls its cases reach; the two layers together cover the list.
    - `[low]` `[reject]` Intent: the matrix is checked against stub output only and the IRIS runner is a different Docker (overlay2, other Compose) than the machine of the measurement — the live unit runs the same `version`, `image ls`, `image inspect`, `compose ps` and `compose port` calls on real Docker; the runner difference is a residual risk, settled by the first `image` group run. reopen_if: the live unit is red on the runner.
    - `[false]` `[reject]` Intent: while untracked, the 100755 check falls back to the executable bit — the check reads git's mode once the file is tracked, and the finalize commit tracks it as 100755.
    - `[false]` `[reject]` Intent: changes outside `install.sh` (`test-ci-config.sh`, `ci/units.sh`, `.gitattributes`, `test-boundaries.sh`) were not named by the intent — each one is a task of the spec or a listed footprint extension.
    - `[low]` `[reject]` Intent: a change to `install.sh` runs every IRIS group because no group claims it — Design Note 12 (by-design).

## Design Notes

**Governing ADs:**
- **AD-23:** retag to `ocutalon-iris-base:2026.3.0AI.154.0`, prefer Health, the build argument for non-Health, the 15-minute wait, a health check with no session.
- **AD-22:** no push or sign-in, `config --quiet`, `inspect --format`, throwaways only, fork guard, no cache or artifact.
- **AD-5:** state on the named volume; a rerun reuses it.
- **AD-19:** keys only from `.env`; `.env.example` lists the names.
- **AD-29:** Lane B's files; runner C builds them.

**Decided in-stage:**
1. **AD-23 and the AC together.** The non-Health image is retagged to the base (AD-23: "retags whichever archive was loaded"), and the compose call also gets `IRIS_IMAGE` naming the non-Health reference (AC). Both resolve to one image ID, so a rerun and a later plain `docker compose up` build the same thing. This is not an intent gap.
2. **The base name is `${IRIS_IMAGE:-ocutalon-iris-base:...}`,** the same variable compose passes to `FROM`. The live unit points it at `$P-base:...`, so the shared tag is never removed or re-tagged.
   - The test's Health source is a new tag `$P-src/irishealth-community:...` on the shared image's ID. It is only added and removed, since the runner preloads only the base name.
   - A concurrent run's source tag has the same ID, so whichever the script picks, the result is the same.
   - The live job's "plain" `docker compose up` differs from a judge's only in variables the judges' file already reads (project name, `COMPOSE_FILE`, `IRIS_IMAGE`).
3. **An existing base is used as it is,** and is identified by ID. Its CPU is checked. The fix for a wrong CPU is a `docker tag`, which moves the name. The script never re-points the name itself.
4. **"Compose v2"** means the `docker compose` plugin, version 2.24 or later. Version 5.5.0 is installed here, so a `^2\.` test would wrongly refuse it.
5. **The machine's CPU** is the daemon's architecture, not `uname -m`, which is wrong in a Rosetta shell.
6. **The script always runs `up -d`,** so a rerun after `git pull` upgrades in place (Stories 11.2 and 11.3). "At once" means the first poll is already healthy.
   - (inference) Compose keeps a container whose image ID and configuration are unchanged.
   - The live unit's rerun check measures this. If compose recreates the container anyway, the implement stage records it and escalates "at once" as an intent question. It does not weaken the check.
   - (measured, implement stage) With Docker Compose 5.5.0 and the containerd image store on Apple silicon, the second `up -d` rebuilt from cache and kept the healthy iris container: the container ID was unchanged and the ready block printed at once, with no progress line. The check stands as written and no intent question arises.
7. **Waiting.** It polls every 10 s, with one line per poll. `unhealthy` keeps waiting until the 15 minutes are up. Only `exited`, `dead` or no container counts as stopped.
8. **The archive** is named by product, build and CPU. No planning artifact records the download's file name, so the load command is `docker load -i <the archive file>`. Story 10.2's README says where to get it.
9. **`.env`** is a plain copy, the same as the manual `cp`. A stricter mode was not taken, because it is a security-posture change outside this story.
10. **Every failure exits 1.** The ready block includes the elapsed time, which Story 11.3 records as the first-start time.
11. **The live unit joins `image`,** the lowest measured group: 552 s on ci-b, against a mean of 669 s. A seventh group would break `test-ci-changes.sh`'s six-group pins, and that file is contended. The unit is about 2 to 3 minutes on ARM, and (inference) 5 to 7 minutes on ci-b. QA records the CI time. If the 1.25 balance rule is exceeded, the remedy is moving one unit within `ci/units.sh`.
12. **`install.sh` stays unclassified.** `test-ci-changes.sh:254` pins it, and that file is contended. A change to it runs every group, so the inputs rule is widened to accept unclassified reads.
    - `.env.example` stays declared (`:241`).
    - Its content is pinned to two empty variables, so no allowed edit changes the live unit.
13. **ShellCheck:**
    - CI uses the 0.9.0 that the ubuntu-24.04 image ships (runner-images readme), so no new action or dependency is needed. Locally, `uvx --from shellcheck-py==0.9.0.6` runs 0.9.0 (measured), as a dev tool only.
    - The live test is not linted, because it sources the contended `lib-live.sh`.
    - The macOS job uses `macos-15`, whose `/bin/bash` is 3.2. It costs about one hosted macOS minute per push, as the AC requires.
14. **The elapsed time** printed in the progress lines and the ready block, and the 900 s wait, count from the start of `docker compose up -d`, so they include the image build. (decided at implement, then changed at review: the first version started the clock when `up -d` returned, which left the build out of the figure that Story 11.3 reads as the first-start time and out of the wait that the live unit bounds.)
15. **One extra check before any change** (decided at implement): when `.env` is missing and `.env.example` is absent or the folder is not writable, the script exits 1 with the fix before tagging or starting anything. It keeps "every check passes before anything changes" true for the file copy too.

**Extend, don't copy:**
- The live unit extends `lib-live.sh`'s throwaway helpers.
- Two small copies are justified, because `lib-live.sh` is contended and no shared stub library exists:
  - the stub-`docker` pattern, from `test-ci-warm.sh` and `test-healthcheck.sh`;
  - the 3-line sign-in curl, from `test-bundle-folder.sh:151-154`.
- `install.sh` cannot source test helpers. It reads health through `docker compose ps`, while `lib-live.sh` uses `inspect` on a container ID.

**Consumed-by:**
- **Story 10.2:** the README states:
  - `./install.sh`;
  - the manual retag command `docker tag <the loaded .../irishealth-community:2026.3.0AI.154.0> ocutalon-iris-base:2026.3.0AI.154.0`;
  - a `## Troubleshooting` section, which the script names;
  - Compose 2.24 as the minimum.
- **Story 11.3:** the clean-machine rehearsal runs `install.sh` and reads its ready line.

**Consumes:**
- From Epic 0: `docker-compose.yml`, `docker/Dockerfile`, `docker/healthcheck.sh` and the users step's README account.
- From Epic 32: `lib-live.sh`, `ci/iris.sh`, `ci/units.sh` and `ci/changes.sh`.

**DW-2:** addressed for `install.sh` by the two Compose rows of the matrix. The README's half is Story 10.2's own criterion ("the minimum Compose version (2.24)"), so the residual re-owns to `10-2` at adjudication.

**Footprint extensions:**
- `docker/tests/test-ci-config.sh`
- `docker/tests/test-boundaries.sh`
- `.gitattributes`
- a second new script, `docker/tests/test-install-script-live.sh` (the units rule puts a hermetic test and a live test in different lists)

## Verification

**Commands.** Run each in the foreground with `timeout: 600000`. Live runs use lane C's variables. `$LANE_C_LOCKS` stands for `"$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-c"`, which resolves to the main checkout's lane-C lock folder (measured: it exists).

Never write the absolute home path in this file: `test-boundaries.sh`'s local-path rule scans tracked specs.
- (loop) `bash docker/tests/test-install-script.sh` -- expected: every matrix row passes; `BASH 3.2.57` printed.
- (loop) `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh` -- expected: the same, as the macOS job runs it.
- (loop) `uvx --from shellcheck-py==0.9.0.6 shellcheck install.sh docker/tests/test-install-script.sh` -- expected: no output, exit 0.
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: all PASS, the new samples included.
- (loop) `bash docker/tests/test-boundaries.sh` -- expected: all PASS, with `install.sh` scanned.
- (loop) `bash docker/tests/test-ci-changes.sh` -- expected: all PASS, with the file unchanged.
- (loop) `docker image inspect --format '{{.Id}}' ocutalon-iris-base:2026.3.0AI.154.0` before and after the live run -- expected: identical.
- (loop) `OCUTALON_LOCK_DIR="$LANE_C_LOCKS" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=10 stage=implement' OCUTALON_RUN_TAG=e10s1i bash ci/iris.sh live install-script-live` -- expected: every PASS, `test-install-script-live: all checks passed`, exit 0.
- (loop) `OCUTALON_LOCK_DIR="$LANE_C_LOCKS" OCUTALON_LOCK_OWNER='epic=10 stage=implement' OCUTALON_RUN_TAG=e10s1i bash ci/iris.sh teardown` -- expected: only tag `e10s1i` removed. Run it after every live run, the failed ones included.
- (once) `bash ci/checks.sh` -- expected: `checks: all scripts passed`.

**Shared surfaces:** these are what other tests assert on:
- `ci/units.sh` `CHECK_SCRIPTS` and `group_units image`, read by `test-ci-config.sh` units, groups and inputs, by `test-ci-changes.sh`'s per-unit loop, and by `ci/iris.sh list`;
- the job list and the `checks` steps of `.github/workflows/ci.yml`, read by `test-ci-config.sh`;
- the `test-boundaries.sh` scan scope;
- the local image tags under `$P-`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests** (the implement stage wrote one `mutation:` line for each; every mutation was applied, run, seen red and reverted, and the file was byte-identical afterwards by `cmp` and `shasum`):
- the Health-first choice: swap the preference → the "both images" row goes red;
  - mutation: swap the two `pick` calls of the missing-base branch, so non-Health is tried first → red: `both images: Health is the only docker tag source` and six more checks of `test-install-script.sh`.
- the non-Health `IRIS_IMAGE` value;
  - mutation: set `build_image` to the base name in the non-Health branch → red: `only non-Health: IRIS_IMAGE is the non-Health reference`, its prefixed twin and `mixed CPUs: IRIS_IMAGE is the non-Health reference`.
- the arch refusal: skip the check → the "wrong CPU" row;
  - mutation: make `pick` accept any candidate whose CPU is known → red: `wrong CPU: exit 1`, `wrong CPU: names each image's CPU`, the other `wrong CPU` checks that name the fix, three `mixed CPUs` checks and `tie: a candidate for another CPU is skipped`.
- the Compose minimum (DW-2): accept 2.23 → red;
  - mutation: change the minor-version test from 24 to 23 → red: `Compose 2.23.3: refused (exit 1) with the found version and the minimum` and `Compose 2.23.3: nothing changed`.
- `.env` never overwritten;
  - mutation: make the `.env` test always true, so the script copies `.env.example` over an existing file → red: `existing .env: byte for byte the same afterwards`, `existing .env: says that it was not changed`, `existing .env: no copy message` and `existing empty .env: stays empty`.
- the published port, not 52773;
  - mutation: set `port` to 52773 instead of the port compose reports → red: the three `custom port` checks and `no published port: exit 1 and says so`.
- timeout and stop exit 1;
  - mutation: `exit 0` before the timeout message → red: `never ready: exit 1` and three more, including `the last sleep never goes past the wait`.
  - mutation: `exit 0` before the stopped-container message → red: `container stops (exited|dead|NONE): exit 1` and the two checks that follow each.
- the call allow-list: add an unconditional `compose down` → red;
  - mutation: run `docker compose $cmd` with `cmd=down` right after the first message (hidden from the text rule on purpose) → red: `calls: every docker call of every case is on the allow-list`, and only that check.
- the live manual-retag phase: skip the manual `docker tag` → the plain `up` fails;
  - mutation: replace the manual `docker tag "$src_ref" "$test_base"` of `test-install-script-live.sh` by `true`, then `ci/iris.sh live install-script-live` on lane C → red: `a plain docker compose up -d exited 1` and `the plain docker compose up did not reach healthy`; `ci/iris.sh teardown` for the tag removed nothing more, and the shared base kept its ID.
- the macOS pin: remove `/bin/bash` from the job → `test-ci-config` goes red;
  - mutation: `run: OCUTALON_TEST_BASH_MAJOR=3 docker/tests/test-install-script.sh` in the `install-macos` job → red: `wiring: ci.yml does not run what its jobs are for, or a sample is not flagged`.
- the inputs widening: a declared-path read still fails.
  - mutation: delete the line of `inputs_violations` that counts a `NOT_IRIS_INPUT_PATTERN` match as known → red: the samples `i-reads-declared-test`, `i-reads-declared-md` and `i-reads-declared-example` no longer draw their violation, and `inputs` fails.
  - mutation: delete the line that counts a bookkeeping path as known → red: `inputs: the sample i-reads-bookkeeping does not draw ...`. Delete the line that asks every other group's pattern → red: `inputs: the sample i-reads-other-group does not draw ...`.

The review pass added these pinning tests and mutation lines (each applied, run, seen red and reverted; the tree was byte-identical afterwards by `git status`, `git diff --stat` and a hash of the diff):
- the clock of the elapsed time and the wait starts at `compose up -d` (`up-takes-time`: a stub `up` that takes 1 s);
  - mutation: move `started=$SECONDS` from before `docker compose up -d` to the start of the wait loop → red: `the elapsed time counts from the start of compose up (the build is in it)`.
- the read-only folder check of Design Note 15 (`read-only-folder`, skipped where the user can write to a mode 555 folder anyway, such as root);
  - mutation: replace `[ ! -w . ]` by `false` → red: `read-only folder, no .env: exit 1 with the fix` and `read-only folder, no .env: nothing changed`.
- the script's own folder with a relative path and `CDPATH` set (`cdpath`);
  - mutation: replace `CDPATH='' cd -- "$here"` by `cd "$here"` → red: `relative script path with CDPATH set: exit 0 in the script's own folder` and `...: .env is created in the script's folder`.
- `fmt_time` (the function is cut out of `install.sh` and called with 45, 60 and 125);
  - mutation: swap the quotient and the remainder in the `N min M s` branch → red: `fmt_time: 60 s is '1 min 0 s'` and `fmt_time: 125 s is '2 min 5 s'`.
- the fallback of `OCUTALON_INSTALL_WAIT` (`soon` and the empty value, with real 1 s sleeps, so a fallback of 1 s ends the wait);
  - mutation: set the default and the case fallback to 1 → red: both `OCUTALON_INSTALL_WAIT=... falls back to the default` rows (and the source-text check).
- `.gitattributes` keeps `install.sh` at LF (`git check-attr eol`);
  - mutation: delete the `install.sh text eol=lf` line → red: `.gitattributes: install.sh keeps LF on every checkout`.
- the script's `TAG` is the tag of the compose file's default image;
  - mutation: change the default image tag in `docker-compose.yml` to `.153.0` → red: `install.sh: its TAG is this test's tag and the tag of the compose file's default image`.
- AC1, `CHECK_SCRIPTS` and the ShellCheck step;
  - mutation: remove `install-script` from `CHECK_SCRIPTS` → red: `test-ci-config` rule `units: the test scripts, the shards and the areas`.
  - mutation: remove the `ShellCheck` step from `ci.yml` → red: `test-ci-config` rule `wiring`.
- AC2, the macOS job beyond `/bin/bash`;
  - mutation: remove `OCUTALON_TEST_BASH_MAJOR=3` from the step → red: rule `wiring`.
  - mutation: stop accepting `macos-15` in the `runners` rule → red: rules `runners` and `never-skipped` (the sample `skip-macos-job`).
- AC3, the rest of the live unit (the rerun and the sign-in; one live run on lane C with two mutations at once);
  - mutation: `docker compose up -d --force-recreate` and the printed password changed to `wrong` → red: `the second run prints ... progress line(s), or no ready block`, `MEASURED: compose recreated the container on the second up -d` and `the printed user and password do not sign in at the printed address`; the other checks stayed green, `ci/iris.sh teardown` removed nothing more, and the shared base kept its ID.
- AC4, the `test-boundaries.sh` scan;
  - mutation: drop `install.sh` from the arguments of `scan_files` → red: `scope: a file that must be scanned is not` (`not scanned: install.sh`).
- AC5, `install.sh` stays unclassified;
  - mutation: add `|install\.sh$` to `IRIS_INPUT` → red: `test-ci-changes` (`classifier: a top-level script: the reason of ... does not name install.sh`).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A root `install.sh` (bash 3.2) checks Docker, the daemon, Compose 2.24 or later and a build 154 image for the daemon's CPU before it changes anything. It names the image it used, gives it the base name (an existing base is never moved), creates `.env` from `.env.example` when there is none, runs `docker compose up -d`, prints a progress line per 10 s poll, and prints the published address and the README account when the compose health check passes. A stop or the end of the 15 minutes exits 1 with the logs command and the README section. A hermetic stub-`docker` test (about 170 checks) runs in `checks` on Linux and in the new `install-macos` job under `/bin/bash`; a live unit in the `image` group runs the real script, a rerun, and the manual retag with a plain `docker compose up`, in a throwaway project.

**Files changed.**
- `install.sh` (new, 100755): the script.
- `docker/tests/test-install-script.sh` (new): the hermetic test, one case per matrix row plus the review's additions.
- `docker/tests/test-install-script-live.sh` (new): the live unit.
- `ci/units.sh`: `install-script` in `CHECK_SCRIPTS`; `live:install-script-live` last in the `image` group; a comment that `install.sh` stays unclassified.
- `.github/workflows/ci.yml`: the `ShellCheck` step in `checks` and the `install-macos` job.
- `docker/tests/test-ci-config.sh`: `macos-15` as a hosted runner, the ShellCheck and macOS wiring pins with bad samples, and the widened `inputs` rule with its samples.
- `docker/tests/test-boundaries.sh`: `install.sh` in the scan scope and the must-scan list.
- `.gitattributes`: `install.sh text eol=lf`.
- This spec: Design Notes 14 and 15, the mutation lines, the triage log.

**Review.** 41 findings from four layers: high 0, medium 6, low 30, false 5. Fifteen rows were patched, in eleven entries; three of the entries were medium: the clock of the elapsed time and the wait now starts at `compose up -d` (the build counts), the script's `TAG` is pinned to the compose file's default image tag, and the LF rule of `.gitattributes` is pinned by `git check-attr`. The low patches: `CDPATH` guard on the script's own `cd`, the timeout and stop messages claim only what is true, a test for the read-only folder and the failed `.env` copy, `fmt_time` pinned, the fallback of `OCUTALON_INSTALL_WAIT` observed, the order claim removed from the `wiring` header, a clearer `known` flag and a comment in `ci/units.sh`, and the missing mutation lines of Rule 19 demonstrated and written. Twenty-six rows were rejected with their reasons in the triage log; none was deferred (`deferred:` stays empty).

**Follow-up review recommended: true.** The first pass patched three medium entries. The unverified risk: the live unit has run only on lane C (Apple silicon, containerd image store, Compose 5.5.0). Whether the second `up -d` keeps the container on the IRIS runner (x64, Docker Engine, an older Compose) is measured by the first `image` group run in CI; if compose recreates the container there, the check stands as written and "prints at once" becomes an intent question (Design Note 6). The `install-macos` job and the ShellCheck step (0.9.0 on the hosted image) have not run on a hosted runner either.

**Verification performed (final tree).**
- `bash docker/tests/test-install-script.sh` and `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh`: all checks pass; `BASH 3.2.57` printed.
- `uvx --from shellcheck-py==0.9.0.6 shellcheck install.sh docker/tests/test-install-script.sh`: no output, exit 0.
- `test-ci-config.sh`, `test-boundaries.sh` and `test-ci-changes.sh` (unchanged): all pass.
- Live: `ci/iris.sh live install-script-live` on lane C, tag `e10s1i`: every check passed (first run ready after 1 min 2 s; the rerun printed at once with the same container; the plain `docker compose up -d` reached healthy on the same volume). The shared base `ocutalon-iris-base:2026.3.0AI.154.0` kept its ID before and after every live run, `ci/iris.sh teardown` for the tag found nothing left, and no `.env` was left in the tree.
- `bash ci/checks.sh` (once, after the last patch): `checks: all scripts passed`.
- Falsifiability (Rule 19): every pinning test has a `mutation:` line in `## Verification`, each applied, seen red and reverted with the tree byte-identical.

**Residual risks.**
- The first CI runs are the only evidence for the hosted macOS job, ShellCheck 0.9.0 on the hosted image, and the live unit on the IRIS runner (its time inside the `image` group, 2 to 3 minutes on ARM, is for QA to record against the 1.25 balance rule).
- `README.md` has no Troubleshooting section yet; Story 10.2 creates it, and the script's messages name it. DW-2's README half is Story 10.2's.
- An edit to `install.sh` runs every IRIS group, by Design Note 12.
- The edits outside the Code Map are the footprint extensions the spec lists (`test-ci-config.sh`, `test-boundaries.sh`, `.gitattributes`, `test-install-script-live.sh`); none of the contended files was edited.
