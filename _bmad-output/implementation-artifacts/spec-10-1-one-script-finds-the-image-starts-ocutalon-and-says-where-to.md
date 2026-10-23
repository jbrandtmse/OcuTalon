---
title: 'One script finds the image, starts OcuTalon and says where to sign in'
type: 'feature'
created: '2026-10-23'
status: 'done'
baseline_revision: '394e419563d0114e3af011c6f1709b12fc926607'
baseline_commit: '394e419563d0114e3af011c6f1709b12fc926607'
review_loop_iteration: 0
followup_review_recommended: false
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
  - When the `iris` service is already running and healthy, it prints the ready block at once, plus one line saying that `docker compose up -d --build` applies an update, and runs no `docker compose up` and no build, so a rerun never restarts or recreates a healthy OcuTalon. In every other state (no container, stopped, failed part-way, starting, unhealthy) it runs `docker compose up -d` and waits. [AMENDED 2026-10-23, CI rework, unattended ruling U-45 (veto): it read "It always runs `docker compose up -d`, so a rerun after an update rebuilds in place."; on the IRIS runner that second `up -d` rebuilt the image and recreated the healthy container, CI run 40021886810]
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
| Already healthy | Base and `.env` exist; the `iris` service answers `running healthy` before any `up` | Prints the ready block without a progress line, and the update line. No tag, no `compose up`. [AMENDED 2026-10-23, U-45] | No error expected |
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

- [x] [CI] iris (image): `live:install-script-live` failed 2 checks on the IRIS runner (x64, Docker Engine): the second run printed 2 progress lines, and `MEASURED: compose recreated the container on the second up -d` -- https://github.com/jbrandtmse/OcuTalon/actions/runs/40021886810 -- `install.sh`: before `docker compose up -d`, read the `iris` service's state with the allowed `docker compose ps --all --format '{{.State}} {{.Health}}' iris`; when it answers `running healthy`, print the ready block at once (the published port from `docker compose port iris 52773`, the README account, the elapsed time) and one line `To apply an update, run: docker compose up -d --build`, run no `compose up` and no build, and exit 0; in every other state keep today's `up -d` and wait. The base and architecture checks, the retag rule and the `.env` copy still run first, unchanged. `docker/tests/test-install-script.sh`: the "Already healthy" row asserts no `compose up` call and the update line; add rows for a container that is `running starting` and one that is `exited` before the run (both call `compose up -d` and wait). Keep the live unit's rerun checks exactly as written (same container, no progress line); they must pass on the IRIS runner. Update each touched pinning test's `mutation:` line.

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

### Review Findings

Code review of 2026-10-23 (epic-cycle, four layers: Blind Hunter, Edge Case Hunter, Verification Gap, Acceptance Auditor). The layers reported 29 rows, which grouped into 23 entries: 0 high, 2 medium, 20 low and 1 false. 11 were patched, 1 was deferred (DW-127), and 11 were dismissed (3 by-design, 8 rejected). Every patch was applied in the review pass, with its mutation line under `## Verification`.

- [x] [Review][Patch] (medium) The check `the last sleep never goes past the wait` was flaky: it expected the first sleep to be exactly 3 s, but the clock's second can tick between `started=$SECONDS` and the first poll, so the sleep is 2 s. Two layers reproduced it, one 3 times in 300 runs. It is now an awk check that every sleep is 1 to 3 s, and the stale mutation line was re-run. [docker/tests/test-install-script.sh:733]
- [x] [Review][Patch] (low) `sh install.sh` on Debian or Ubuntu (dash) stopped with `arithmetic expression: expecting EOF`, with no plain message. A bash guard now prints the command to use and "Nothing was changed.", and the new row `not-bash` runs the script under dash, skipped where the machine has none. [install.sh:20]
- [x] [Review][Patch] (low) The live unit's cleanup removed a `.env` that is a link to nothing, which install.sh keeps as an existing `.env`. It now treats a link as existing, with the same test as the script. [docker/tests/test-install-script-live.sh:64]
- [x] [Review][Patch] (low) An existing base on the wrong CPU with only a non-Health image of this CPU loaded had no row: dropping `|| pick n` left every test green. Added the row `base-wrong-cpu-non-health`. [docker/tests/test-install-script.sh:437]
- [x] [Review][Patch] (low) An unmatched existing base printed "matches neither the ... image loaded here", even when no image is loaded. It now says that no build 154 image loaded here has its ID, and the no-candidate row checks this. [install.sh:251]
- [x] [Review][Patch] (low) The forbidden-word scan missed `docker system|builder|buildx|network prune`, and `sudo` after `if`, `then`, `do`, `else`, `elif`, `while`, `until`, `(` or `!`. The pattern now covers them. [docker/tests/test-install-script.sh:800]
- [x] [Review][Patch] (low) The read-only folder row and the unreadable `.env` row printed `PASS` when they were skipped (a user who can write to mode 555 or read mode 000, such as root). They now print `SKIP`. [docker/tests/test-install-script.sh:564,678]
- [x] [Review][Patch] (low) The timeout message named the container state but not the health check (`unhealthy` or `starting`). It now prints `(state: running, health check: starting)`, and a check pins it. [install.sh:344]
- [x] [Review][Patch] (low) The lines for an existing Health or non-Health base did not name the image's reference, although the non-Health reference is what the build gets (the "What it says" rule). They now print it. [install.sh:246-248]
- [x] [Review][Patch] (low) The no-`.env.example` fix said to run install.sh from the OcuTalon folder, which the script already does with its `cd`. It now says to keep install.sh beside `docker-compose.yml` and `.env.example`, and to get `.env.example` back from the repository. [install.sh:141]
- [x] [Review][Patch] (low, Rule 19, closed in the pass) Some pins had no mutation line:
  - AC3's "on the same volume" (a live run with `dc down -v`);
  - the "Existing base" row, which is also AC3's "keeps its ID" (the live checks of the shared ID cannot be failed by install.sh);
  - the rows look-alikes, existing base on the wrong CPU, no Docker and already healthy.
  Each was applied, seen red and reverted, and written under `## Verification`. [_bmad-output/implementation-artifacts/spec-10-1-one-script-finds-the-image-starts-ocutalon-and-says-where-to.md, ## Verification]
- [x] [Review][Defer] (medium, unverified) `live:install-script-live` joins `image` with no x64 time on record, so Story 32.3's balance rule has not been checked for it. The rule is that no IRIS job runs more than about 25% over the mean of the six. [ci/units.sh:35] — deferred: maybe-false.
  - The estimate at compose-start's ARM-to-x64 ratio is about 810 to 920 s against a mean near 710 to 730 (inference).
  - The first CI run with the unit settles it: compare the `image` job's time with 1.25 times the mean of the six jobs. If it is over, move one unit (Design Note 11).
  - Ledger: DW-127, `routed owner=10-2-the-readme-gets-a-judge-from-download-to-sign-in`, the next story that touches `ci/units.sh`.
  - It does not re-open this story, because the time exists only after the push.

Dismissed, by-design (spec-bound, Rule 15):
- A crash loop (`restarting`) or a container left `unhealthy` by a failed start makes the script, and a rerun, wait the full 15 minutes. That is Design Note 7: only `exited`, `dead` or no container counts as a stop. The progress lines show the state, and the timeout message now names the health check.
- The live unit does not track a rebuilt `$P-iris` image. The spec's Never rules forbid putting an image ID into `LIVE_IMAGES`, because identical builds share an ID across concurrent projects. A rebuild that changed the image would also recreate the container, and the rerun check fails on that.
- An `IRIS_IMAGE` set only in `.env` is replaced by the value the script exports. The script never reads `.env` (Never rule), and `IRIS_IMAGE` is not a variable of `.env.example`.

Rejected:
- low: the ShellCheck step runs before `bash ci/checks.sh`, so a ShellCheck failure hides that run's check results. Linting first is a deliberate fail-fast order: moving the step only swaps which result hides the other, and the alternative is a step condition in a pinned workflow.
- low: the Auto Run Result's "about 170 checks" and the residual-risk line are stale. The fix would edit build-auto's sections of the spec under review.
- low: a base whose ID is tagged both `iris-community` and `irishealth-community` is reported as non-Health on a rerun (the build is the same image). This needs a hand-made double tag, and the fix is a second loop.
- low (wontfix-theoretical): a `docker version` answer that is only whitespace would make the daemon's CPU empty. It would become real if a Docker CLI answered `version --format '{{.Server.Arch}}'` with blank output and exit 0.
- low: a sourced `. install.sh` would close the user's shell on a failure. Nobody sources an install script, and the guard would add a branch.
- low: the `git check-attr` check fails outside a git checkout. The test always runs in a checkout.
- low: whole-number overrides longer than six digits fall back to the default. These are test-only overrides with an overflow cap, and QA pinned the case.
- false (settled by measurement): "the Linux side of AC1 has never run". In `ubuntu:24.04` (bash 5.2.21, dash, mawk, non-root), 200 checks passed. The only red was the `git check-attr` check, because the image has no git.

## Spec Change Log

- 2026-10-23, rework iteration 1 (trigger `ci`, run 40021886810): the healthy-rerun rule in Boundaries & Constraints and the "Already healthy" matrix row amended per ruling U-45 (veto); one `[CI]` item opened under Tasks & Acceptance; Design Note 6 records the CI measurement.

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

### 2026-10-23 -- Review pass of rework 1 (the `[CI]` item; diff since 394e419)
- verdicts: 23 findings -- high 0, medium 5, low 16, false 2, maybe-false 0
- layers: Blind Hunter 7, Edge Case Hunter 5, Verification Gap 6, Intent Alignment 5 (its divergences, one row each)
- findings:
    - `[medium]` `[patch]` Blind: the key instruction "add it to .env and run ./install.sh again" no longer applies a key, because a healthy container is now left alone — real (a container reads `.env` when it is created). Patched: the instruction names `docker compose up -d --force-recreate` (Design Note 16); two checks pin it, with a mutation line.
    - `[low]` `[patch]` Blind: the healthy path prints "ready after 0 s", a made-up time — the figure is the script's own wait, the ruling lists the elapsed time in the block, and the live unit matches the phrase. Kept; a check now pins it (`elapsed=754` goes red), and Design Note 16 says what the figure is.
    - `[low]` `[reject]` Blind: Design Notes 6, 10 and 14 contradict the ruling — the fix edits this build's spec; Design Note 6 is the lead's record of the ruling (reported to the lead: its headline line and the Auto Run Result's old follow-up paragraph are stale).
    - `[low]` `[patch]` Blind: the Auto Run Result describes the old tree and records no re-verification. Rewritten for this pass, with the final tree's results.
    - `[low]` `[reject]` Blind: the `[CI]` item is ticked but its IRIS-runner proof is not observed, and the live side cannot tell old code from new — the runner's next CI run is the lead's gate. The live check does tell them apart: the live mutation of the healthy branch goes red (below). The item says to keep the live rerun checks as written, so no assertion is added there.
    - `[low]` `[patch]` Blind: no row for `restarting` or `paused`, for a healthy service with a missing base or `.env`, or for the healthy path ending at the no-port message. Patched: rows for `restarting`, `paused`, `running` with no health check, and a healthy service with no base and no `.env`. The no-port message is shared with the first-run path and its row (`no-port`) stays.
    - `[low]` `[reject]` Blind: a failed `docker compose ps` before `up` reads as "no container" and so runs `up -d` on a healthy install — it needs a transient failure of one call after others succeeded, and the fix adds a branch with no specified behavior. reopen_if: a judge reports a restart on a rerun.
    - `[medium]` `[patch]` Edge: the same key instruction as the first Blind finding — patched there.
    - `[low]` `[reject]` Edge: `compose ps --all` can print several rows for `iris` (leftover one-off containers or replicas), and only the first is read — wontfix-theoretical: the compose file has neither, and every poll has read the first row since the story began. reopen_if: a rerun reports "stopped" beside one-off containers.
    - `[low]` `[patch]` Edge: no rows for `running` with no health check, `restarting` and `paused` — patched with the Blind rows.
    - `[low]` `[patch]` Edge (claim): the healthy block's 0 s is hard-coded — the same root cause as the second Blind finding.
    - `[low]` `[reject]` Edge (deletion): the no-published-port message no longer holds the elapsed time on the first-run path — the message names a case that cannot happen after a healthy start, and a figure there was not asked for; keeping it on one path adds a branch.
    - `[medium]` `[patch]` Verification gap: nothing pins that the base, architecture, retag and `.env` steps run before the healthy shortcut — real (a scratch copy with the decision moved ahead of the checks passed every test). Patched: rows `already-healthy-base-wrong-cpu` and `already-healthy-no-base-no-env`, with a mutation line.
    - `[medium]` `[patch]` Verification gap: the key instruction — the same root cause as the first Blind finding, patched there (the first-health row and the no-base healthy row assert the text).
    - `[low]` `[patch]` Verification gap: the elapsed time of the healthy block is not pinned — the same root cause as the second Blind finding, patched there.
    - `[low]` `[patch]` Verification gap (Rule 19): AC3's rerun checks have no `mutation:` line on the new code. Closed in the pass, not deferred: one live run on lane C (tag `e10s1k`) with `--force-recreate` in the healthy branch → red `MEASURED: compose recreated the container on the second up -d`, reverted, line written.
    - `[low]` `[reject]` Verification gap (other): Design Note 6's headline is stale — the same root cause as the first stale-notes finding.
    - `[false]` `[reject]` Verification gap (other): ShellCheck 0.9.0 was not confirmed on the new `for row` block and the `read_service` heredoc — `uvx --from shellcheck-py==0.9.0.6 shellcheck install.sh docker/tests/test-install-script.sh` ran clean on the reworked tree and again on the final one.
    - `[low]` `[reject]` Intent: the outcome (same container on real Compose) is measured only by the live unit, which now passes by construction — the item keeps the live unit's checks as written; the live mutation above shows they still go red when the branch recreates, and the IRIS runner's CI run is the outcome proof.
    - `[medium]` `[patch]` Intent: the retained "run ./install.sh again" key message points at a path that starts nothing — the same root cause as the first Blind finding.
    - `[low]` `[patch]` Intent: the healthy block says "ready after 0 s", a figure measured from nothing — the same root cause as the second Blind finding.
    - `[low]` `[reject]` Intent: the spec text is partly stale (Design Note 6, the follow-up paragraph) — the same root cause as the stale-notes finding; the paragraph is rewritten with the Auto Run Result.
    - `[false]` `[reject]` Intent: the healthy decision sits after the tag and `.env` steps — that is what the item orders ("still run first"), and the new rows pin the order; no bad outcome.

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
6. **[Superseded by ruling U-45, 2026-10-23: a healthy install gets no `up`; see the last bullet and Design Note 16.]** The plan's reading was: the script always runs `up -d`, so a rerun after `git pull` upgrades in place (Stories 11.2 and 11.3). "At once" means the first poll is already healthy.
   - (inference) Compose keeps a container whose image ID and configuration are unchanged.
   - The live unit's rerun check measures this. If compose recreates the container anyway, the implement stage records it and escalates "at once" as an intent question. It does not weaken the check.
   - (measured, implement stage) With Docker Compose 5.5.0 and the containerd image store on Apple silicon, the second `up -d` rebuilt from cache and kept the healthy iris container: the container ID was unchanged and the ready block printed at once, with no progress line. The check stands as written and no intent question arises.
   - (measured, CI run 40021886810, IRIS runner, x64, Docker Engine) The second `up -d` recreated the healthy container: the live unit's rerun printed 2 progress lines and the container ID changed. Ruled by the runner (unattended, veto U-45): a healthy install is detected first and gets the ready block at once with no `up` and no build, plus a one-line update hint (`docker compose up -d --build`); every other state still runs `up -d`. The planner's "a rerun after `git pull` upgrades in place" is dropped: no criterion of this story asks for it, and restarting a judge's running OcuTalon on a rerun is the unsafe side of the trade.
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
16. **The healthy rerun** (decided at the rework of U-45, confirmed at its review):
    - The ready block's figure is the script's own wait, so it reads `0 s` on the fast path. The line before the block says that the container was not started again, and the hermetic test pins the figure.
    - The key instruction is "add it to .env and run: docker compose up -d --force-recreate". A rerun of the script now leaves a healthy container alone, and a container reads `.env` when it is created, so "run ./install.sh again" would no longer apply a key. The wording is the script's own (the UX banner says "restart OcuTalon"), and it is changed only to keep the text true.

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
  - mutation: `exit 0` before the timeout message → red: `never ready: exit 1`, the three other `never ready` checks and `the last sleep never goes past the wait: every sleep is capped at the wait that is left (1 to 3 s)` (re-run at code review, after that check changed).
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
- AC3, the rest of the live unit (the rerun and the sign-in);
  - mutation: the printed password changed to `wrong` (one live run on lane C, before the rework; the line it touches is unchanged) → red: `the printed user and password do not sign in at the printed address`; the other sign-in checks stayed green, `ci/iris.sh teardown` removed nothing more, and the shared base kept its ID.
  - mutation: `docker compose up -d --force-recreate` in the healthy branch of `install.sh` (the rerun checks, same container and no progress line; one live run on lane C, tag `e10s1k`, at the review of the rework) → red: only `MEASURED: compose recreated the container on the second up -d`; `ci/iris.sh teardown` removed nothing more, the shared base kept its ID, and no `.env` was left. The hermetic side of the same clause is the mutation `docker compose up -d` in the healthy branch, under "Already healthy" below.
- AC4, the `test-boundaries.sh` scan;
  - mutation: drop `install.sh` from the arguments of `scan_files` → red: `scope: a file that must be scanned is not` (`not scanned: install.sh`).
- AC5, `install.sh` stays unclassified;
  - mutation: add `|install\.sh$` to `IRIS_INPUT` → red: `test-ci-changes` (`classifier: a top-level script: the reason of ... does not name install.sh`).

**QA pass (QA).** The qa stage read the matrix and the epic's criteria against the tests, measured which lines of `install.sh` the hermetic test never reaches (xtrace over a scratch copy), and ran 288 line-level mutants of `install.sh` against the hermetic test in a scratch copy (statement deleted, condition forced, operator or number swapped; 16 did not parse, 208 went red, 64 survived). It added no new test file: every gap went into an existing script. Files (QA):
- `docker/tests/test-install-script.sh` (QA, extended in place; 169 checks became 196, 197 with the bash-major check): the 15-minute wait observed through the capped first sleep (default and all three fallbacks, and a leading zero); `bash install.sh` with a bare name; image-side and base-side `aarch64`/`x86_64`; an image whose CPU cannot be read is never a match; a daemon or Compose that answers with nothing; `IRIS_IMAGE` names the base; `.env` as a link to nothing and `.env` that cannot be read; a poll with no health state; compose's messages stay on screen; the allow-list holds the exact arguments (`--short`, the formats, the service `iris`); `docker-compose.yml` has the service and port the script asks about. The old `OCUTALON_INSTALL_POLL=007` row could not fail (007 is 7 in octal too) and is now `08`.
- `docker/tests/test-ci-config.sh` (QA, extended in place): the `install-macos` job must have `timeout-minutes: 10`, with two bad samples (`macos-timeout-gone`, `macos-timeout-long`).

Mutations of the QA pass (each applied to the tracked file, run, seen red and reverted; `git status --short`, `git diff --stat` and a hash of `git diff` were identical before and after each):
- the 15 minutes, AC3 (progress for up to 15 minutes):
  - mutation: the fallback `max_wait=900` of the non-numeric case → `600` → red: `OCUTALON_INSTALL_WAIT='soon' waits 15 minutes (900 s)` and the `-5` row.
  - mutation: the default `:-900` → `:-600` → red: `OCUTALON_INSTALL_WAIT='' waits 15 minutes (900 s)`.
  - mutation: the seven-digit fallback `max_wait=900` → `600` → red: the `1234567` and the 20-digit rows.
  - mutation: `max_wait=$((10#$max_wait))` → `$(($max_wait))` → red: the `0900` row. Same for `poll=$((10#$poll))` → `$(($poll))` → red: `OCUTALON_INSTALL_POLL=08 is 8 s, in base 10`.
- run from any folder: mutation: `*) here=. ;;` → `here=/` → red: `bash install.sh, a name with no slash, from the script's own folder: exit 0` and `...: .env is created in that folder`.
- the CPU check (epic AC "checks that its CPU architecture matches"):
  - mutation: delete the `norm_arch` of the image's CPU → red: `an image that reports aarch64 is arm64` and the `x86_64` row.
  - mutation: delete the `norm_arch` of the base's CPU → red: `an existing base that reports x86_64 is amd64`.
  - mutation: `pick` also accepts an image with no readable CPU → red: the three `unreadable CPU` checks.
  - mutation: delete the empty-reference guard in `other_cpu_lines` → red: `wrong CPU: no line for an unknown CPU`.
- stop before any change (Docker, Compose):
  - mutation: `||` → `&&` in the daemon check → red: `daemon that answers with no architecture`.
  - mutation: `||` → `&&` in the Compose check → red: `Compose that answers with no version`.
- `.env` is never overwritten, read or printed:
  - mutation: drop `&& [ ! -L .env ]` → red: `a .env that is a link to nothing is an existing .env` and `...: nothing was written through it`.
  - mutation: after "Found .env", `grep -q ANTHROPIC_API_KEY .env` → red: `an unreadable .env: exit 0 with no permission error, so the script never reads .env`.
- the exact calls (AC "never `docker compose config`... without `--quiet`", allow-list):
  - mutation: `docker compose version --short` → `docker compose version` → red: `calls: every docker call of every case is on the allow-list`.
  - mutation: the poll names the service `iriz` → red: the same check.
  - mutation: rename the service `iris` to `oci` in `docker-compose.yml` → red: `docker-compose.yml: the service is iris and it publishes container port 52773`.
- the base name: mutation: `base=${IRIS_IMAGE:-...}` → `base=ocutalon-iris-base:$TAG` → red: `IRIS_IMAGE set: the image is tagged once, as that name` and `...: compose up gets that name`.
- progress lines: mutation: `if [ -n "$health" ]` → `if true` → red: `a poll with no health state: the line holds the elapsed time and the state only`.
- failure help: mutation: `docker compose up -d` gets `2>/dev/null` → red: `up fails: compose's own messages (both streams) stay on screen`.
- AC2, the macOS job's cost: mutation: `timeout-minutes: 10` → `60` in the `install-macos` job → red: `test-ci-config` rule `wiring`.

Left unpinned on purpose (the survivors of the sweep, judged equivalent or cosmetic): `set -u`; the `local` lines; the resets of `pick_ref`, `pick_id`, `state`, `health`, `base_info` and `image_lines`; `cp -n` for `cp`; the blank line before a failure message; the `here=/` branch for a script at the root of the disk (no test can put a file there); `-ge` against `-gt` at the exact end of the wait and at six digits; the words of the "Docker is running on", "Tagged it as", "Starting OcuTalon" and "To set a key" lines and the repository names inside the no-image message; the first of two same-ID refs (`break`); `live:install-script-live` being last, not first, in `group_units image` (no rule reads the order); `needs:` or `fetch-depth` added to the `install-macos` job.

**Live unit (QA).** `ci/iris.sh live install-script-live` on lane C, tag `e10s1q`, final tree: every check passed in 95 s wall (the implement stage measured 2 to 3 minutes). `ci/iris.sh teardown` for the tag removed nothing more, the shared base kept its ID before and after, and no `.env` was left in the tree.

**Code review pass.** Each mutation below was applied to the tracked file, run once, seen red and reverted. `git diff` hashed the same before and after each one.
- `install.sh` stops under a shell that is not bash. The row `not-bash` runs it with `dash` where the machine has one; ubuntu-24.04 and macOS both do.
  - mutation: the guard `if [ -z "${BASH_VERSION:-}" ]` → `if false` → red: `run by dash, not bash: exit 1 with the command to use`.
- The cap on each sleep. The check accepts 1 to 3 s, because the clock's second can tick between the start of `up -d` and the first poll.
  - mutation: delete the line that caps `step` at `max_wait - elapsed` → red: `the last sleep never goes past the wait: every sleep is capped at the wait that is left (1 to 3 s)` and the six `OCUTALON_INSTALL_WAIT=... waits 15 minutes` rows.
- An existing base is never tagged again (matrix row "Existing base").
  - This is also the pin for AC3's "keeps its ID throughout": the live unit's two shared-ID checks only guard the shared name against the test itself.
  - mutation: `if pick h || pick n; then tag_id=$pick_id; fi` before `case $base_kind in` → red: `existing base, Health|non-Health|unknown: no docker tag`, `already healthy: no docker tag` and `architecture names: an existing base that reports x86_64 is amd64 ...`.
- An existing base on the wrong CPU:
  - mutation: `if [ "$base_arch" != "$daemon_arch" ]` → `if false` → red: the eight `existing base, wrong CPU ...` checks.
  - mutation: `if pick h || pick n` → `if pick h` in that branch → red: `existing base, wrong CPU, only a non-Health image of this CPU: names it in the docker tag fix, nothing changed`.
- Prefixes and look-alikes:
  - mutation: `iris-community | */iris-community)` → `*iris-community)` → red: the three `look-alikes` checks.
- No Docker:
  - mutation: `if ! command -v docker ...` → `if false` → red: `no docker: says to install Docker Desktop or Docker Engine`.
- Already healthy prints at once and starts nothing (the hermetic side of AC3's "a rerun prints at once"; rewritten at the rework of ruling U-45, which reads the service before `up`; the stub answers the `before` file until `up` runs and the `health` lines after it):
  - mutation: print a progress line in the healthy branch → red: `already healthy: the ready block prints with no progress line`, and only that check.
  - mutation: run `docker compose up -d` in the healthy branch → red: `already healthy: no compose up, so no restart and no build`, and only that check.
  - mutation: ask only for `running` before `up` (drop the health test) → red: three checks each of the rows `running starting` and `running unhealthy` (`compose up -d runs once ...`, `it says it is starting and waits ...`, `no update line ...`).
  - mutation: `case $state in exited | dead) exit 1 ;; esac` right after the first read → red: three checks each of the rows `exited` and `dead` (`exit 0 with the ready block`, `compose up -d runs once ...`, `it says it is starting and waits ...`).
  - mutation: print the `Starting OcuTalon` line before the first read → red: `already healthy: it does not say it is starting`, and only that check.
  - mutation: the update line names `docker compose up -d` without `--build` → red: `already healthy: says it was not started again, and names the command that applies an update`, and only that check.
  - mutation: print the update line on every run (`if true`) → red: `first run, Health: says it is starting, and has no update line` and the `no update line` check of each of the five rows `running starting`, `running unhealthy`, `exited`, `dead` and `created`.
  - mutation: the `die` after a failed `up -d` becomes an `echo` → red: `up fails: exit 1` and `up fails: no poll afterwards (the only read of the service is the one before up)`.
  - mutation: move `started=$SECONDS` from before `docker compose up -d` to the start of the wait loop (re-run on the reworked script) → red: `the elapsed time counts from the start of compose up (the build is in it)`, and only that check.
  - mutation: delete the line that caps `step` at `max_wait - elapsed` (re-run on the reworked script) → red: the same seven checks as at the code review.
  - Review of the rework (each applied to the tracked file, run, seen red and reverted; `git diff` hashed the same before and after):
    - mutation: an early `read_service` and an exit 0 with the ready line right after the `OcuTalon install` line, so the healthy answer is decided before the checks → red: `already healthy, base for another CPU: exit 1 ...`, the three `already healthy, no base and no .env` checks, and (from the extra `compose ps` call) four `already healthy` checks and `up fails: no poll afterwards`.
    - mutation: `elapsed=0` → `elapsed=754` in the healthy branch → red: `already healthy: the wait it reports is 0 s, since the script waited for nothing`, and only that check.
    - mutation: the key instruction back to "run ./install.sh again." → red: `first run, Health: the key instruction names the command ...` and `already healthy, no base and no .env: .env is a byte for byte copy ..., with the key instruction`.
    - mutation: the healthy test before `up` loosened to "any state but exited, dead, created or none, with a health check that is not starting or unhealthy" → red: nine checks, three each of the rows `running` (no health check), `restarting` and `paused`.
- The timeout message names the health check:
  - mutation: drop `${health:+, health check: $health}` → red: `never ready: names the container's state and its health check`.
- An existing base's lines name its reference:
  - mutation: drop ` ($base_ref)` from the Health and non-Health lines → red: `existing base, Health: says IRIS for Health, its reference and the existing wording` and `existing base, non-Health: says IRIS (non-Health) and the reference the build uses`.
- The two corrected messages:
  - mutation: restore the old texts "It matches neither ... image loaded here" and "Run install.sh from the OcuTalon folder ..." → red: `existing base, unknown: says it matches neither`, `existing base, no candidate loaded: claims no loaded image, only that none has its ID` and `no .env.example: exit 1 before any change, with the fix`.
- The text scan's prune and sudo words:
  - mutation: an unreached `if false; then docker system prune -f; if sudo true; then :; fi; fi` before the changes → red: `install.sh text: no forbidden docker word or sudo command`. The old pattern matched neither line.
- AC3, "on the same volume":
  - mutation: `dc down` → `dc down -v` in step 4 of `test-install-script-live.sh`, then one live run on lane C (127 s, tag `e10s1r`) → red: only `the durable volume's CreatedAt changed ...`.
  - Every other check stayed green, `ci/iris.sh teardown` for the tag removed nothing more, and the shared base kept its ID.
- The Linux side of AC1, run before the first push:
  - `bash docker/tests/test-install-script.sh` in `ubuntu:24.04` (bash 5.2.21, dash as `/bin/sh`, mawk 1.3.4), as a non-root user with the tree mounted read-only and no network: 200 checks passed, and the read-only and unreadable rows ran.
  - The one red was `.gitattributes: install.sh keeps LF on every checkout`, because the image has no git. CI's checkout has git.
- Live unit on the final tree: `ci/iris.sh live install-script-live` on lane C, tag `e10s1r`.
  - Every check passed in 83 s. The rerun printed `ready after 1 s` with the same container.
  - Teardown removed nothing more, the shared base kept its ID, and no `.env` was left in the tree.

## Auto Run Result

Status: done
Blocking condition: none

Rework pass 1 (the `[CI]` item; ruling U-45). This section covers this pass only; the first pass is in the story's history.

**Summary.** `install.sh` now reads the `iris` service before it runs `docker compose up`. A service that answers `running healthy` gets the ready block at once (the published port, `ocutalon`/`ocutalon`, `0 s`), the line `To apply an update, run: docker compose up -d --build`, no `compose up`, no build, and exit 0. Every other state (none, starting, unhealthy, no health check, restarting, paused, exited, dead, created) runs `docker compose up -d` and waits as before. The Docker, Compose, image and architecture checks, the retag and the `.env` copy still run first. The key instruction now names `docker compose up -d --force-recreate`, because a rerun leaves a healthy container alone (Design Note 16).

**Files changed.**
- `install.sh`: the pre-`up` read (`read_service`, shared with the wait loop), the healthy branch, the update line, the key instruction.
- `docker/tests/test-install-script.sh`: the `before` answer of the stub; the "Already healthy" row; eight pre-state rows; two rows that pin the order of the checks before the healthy branch; checks for the `0 s` figure and the key instruction.
- This spec: the `[CI]` item ticked, the mutation lines, Design Note 16 and the triage log. The live unit and every contended file are unchanged.

**Review.** 23 findings from four layers: high 0, medium 5, low 16, false 2. Two root causes were patched at medium: the key instruction (four layers) and the missing pin on the order of the checks before the healthy branch. Low patches: the `0 s` pin, the extra pre-state rows, and the live mutation line for AC3's rerun clause (a live run on lane C, red as expected, closed in the pass). Nothing was deferred (`deferred:` stays empty). Rejected: Design Note 6's stale headline (the lead's record; reported here), a failed pre-read of `compose ps`, several `ps` rows, the elapsed time in the no-port message, and the rest with reasons in the triage log.

**Follow-up review recommended: false.** This pass patched no high.

**Verification performed (final tree).**
- `bash docker/tests/test-install-script.sh`: 243 checks pass. `OCUTALON_TEST_BASH_MAJOR=3 /bin/bash docker/tests/test-install-script.sh`: 244 checks pass, `BASH 3.2.57` printed.
- `uvx --from shellcheck-py==0.9.0.6 shellcheck install.sh docker/tests/test-install-script.sh`: no output, exit 0.
- `test-boundaries.sh`, `test-ci-config.sh` and `test-ci-changes.sh` (unchanged): all pass. `bash ci/checks.sh` (once, after the last patch): `checks: all scripts passed`.
- Live: `ci/iris.sh live install-script-live` on lane C, tag `e10s1j`: every check passed; the rerun printed "already running and healthy", `ready after 0 s` and the update line, with the same container. The tag's teardown removed nothing more, the shared base kept its ID before and after every live run, and no `.env` was left.
- Falsifiability (Rule 19): every pinning test touched has a `mutation:` line in `## Verification`, each applied, seen red and reverted.

**Residual risks.**
- The IRIS runner's next `image` group run is the proof that the rerun keeps the container on x64 with Docker Engine; lane C could not reproduce the recreate even before this change.
- Design Note 6's headline still says the script always runs `up -d`, and the Auto Run Result's older claims are gone with this rewrite; the lead owns Design Note 6.
- The key instruction's wording is the script's own (Design Note 16); it was changed only to stay true after the ruling.
