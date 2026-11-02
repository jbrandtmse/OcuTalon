---
title: 'Story 11.3: The clean-machine rehearsal installs and times the demo path (the install half, dry runs on throwaways)'
type: 'feature'
created: '2026-11-01'
status: 'done'
baseline_revision: 'f64cf74d0237b997705093b4fdab7c2b0b77b82b'
baseline_commit: 'f64cf74d0237b997705093b4fdab7c2b0b77b82b'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Release 1 has no clean-machine rehearsal (REL-6). Nothing copies a candidate to a clean host, installs it with `install.sh`, measures the first start or writes the result into the candidate's record. This build has no clean host, no driver host and no real key, so the script must be proved on throwaways, and a dry run must never count as a rehearsal pass.

**Approach:** Add `release/rehearse.sh`, built in phases like Story 11.2's harness.
- Its `install` phase reaches the clean host and the driver host over SSH, using the author's configuration file outside the repository.
- It copies the candidate branch as a `git bundle`, clones it, puts the configured `.env` beside it through stdin, and runs `install.sh`.
- It reads the printed address and sign-in details, has the driver host sign in there, and records the first start's duration.
- `report` writes the `## Clean-machine rehearsal` section of `release/records/<version>/rc<n>.md` through a new shared `release/lib-release.sh`.
- `--dry-run` swaps both hosts for stand-ins: a throwaway compose project with the CI mock for the clean host, and the machine the script runs on for the driver host. Its record and output say "dry run".

The timed runs and their bounds go to a proposed sibling, Story 11.11 (Design Notes, Proposed split).

## Boundaries & Constraints

**Always:**
- **No value is ever printed or recorded.** No value from `.env`, and no value from the configuration file (host names, addresses, ports, key paths) appears in the script's output or in the record.
  - The env file reaches the clean host only as the stdin of one remote `umask 077 && cat > .env`.
  - Neither file is ever `source`d, `.`-loaded, `cat`ed to the terminal or put on a command line.
  - `docker compose config` runs only with `--quiet`, and `docker inspect` / `docker image inspect` only with `--format` (NFR-11, AD-19, AD-22).
- **Every remote action goes through one function, `host_run <clean|driver> <command>`.** The command is a POSIX `sh` string, and stdin passes through.
  - Real mode runs `${OCUTALON_REHEARSAL_SSH:-ssh} -i <key> -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15 [-o UserKnownHostsFile=<file>] [-p <port>] -- <dest> <command>`.
  - Host keys stay strictly checked: no `StrictHostKeyChecking=no` and no `accept-new`.
  - `REHEARSAL_DRIVER_SSH=local` runs the driver's commands with `sh -c` on this machine.
  - Remote paths are relative to the login folder: `ocutalon-rehearsal/candidate.bundle` and `ocutalon-rehearsal/candidate`. Never `~`, and never an absolute path.
- **A dry run never runs `ssh`** and never reads the configuration file. Its stand-ins are:
  - for the clean host, `sh -c` in `<state>/standin/clean/`, with the throwaway's `COMPOSE_PROJECT_NAME`, `COMPOSE_FILE`, `IRIS_IMAGE` and `OCUTALON_INSTALL_WAIT`;
  - for the driver host, `sh -c` in `<state>/standin/driver/`.
  - The throwaway is a `docker/tests/lib-live.sh` project reached through `ci/iris.sh`, with the CI override and the mock, no key, the lane's lock, and the port from `OCUTALON_TEST_WEB_PORT`.
- **Result rules (no false all-clear).**
  - `fail` when any step failed.
  - Otherwise, in a dry run, `dry run`. In real mode, `not run` while any step is `not run` (the timed runs until Story 11.11), else `pass`.
  - Exit codes: 0 only for a real `pass`; 1 for `fail` or `not run`; 3 for `dry run`; 2 for usage, configuration, candidate or phase-order refusals (nothing started); 75 when lib-live's lane lock is busy.
- **Failure lines** read `FAIL run <run> step <step> bound <bound>: <detail>`.
  - In this story `<run>` is `install`, and `<bound>` is the step's limit or `-`.
  - The steps after a failed step are `not run`.
- **The record names machines only by operating system, CPU architecture and memory** (CON-5). A section written to a record replaces only its own `## Clean-machine rehearsal` section.
- **Portability.** Bash 3.2 (the author's Mac) and ASCII only (Rule 14). The scripts are mode 100755, start with `umask 077`, and run their main only when executed (`[ "${BASH_SOURCE[0]}" != "$0" ] && return 0`), so the self-test can source them.

**Never:**
- Contact a real host, use a real model key, or run the real rehearsal: that is Story 38.2.
- Build the N timed runs, the timing splits or the bounds: that is the proposed Story 11.11.
- Push, tag, or sign in to a registry.
- Write into `release/records/` from a test or a verification run (always pass `--record <tmp file>`).
- Touch the files of open epics: `docker/tests/lib-live.sh` (Epic 12), `release/standalone-bridge.sh` (Epic 13), `release/ipm-install.sh`, `src/module.xml`, `Install/**` (Epic 15), `.github/workflows/*`. The one exception is the `CHECK_SCRIPTS` line of `ci/units.sh`, which is shared by region (the 11.1 lead ruling).
- Make the live dry run a CI unit.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Config | `OCUTALON_RELEASE_CONFIG` or `${XDG_CONFIG_HOME:-$HOME/.config}/ocutalon/release.conf`, read as `KEY=value` with no expansion other than a leading `~/` in path keys | The keys `REHEARSAL_CLEAN_SSH`, `_CLEAN_KEY`, `_CLEAN_WEB`, `_DRIVER_SSH`, `_ENV_FILE`, and `_DRIVER_KEY` unless the driver is `local`, are set. Optional: `_CLEAN_PORT`, `_DRIVER_PORT`, `_KNOWN_HOSTS`. Keys without the `REHEARSAL_` prefix are ignored | Missing file or key, an unknown `REHEARSAL_` key, a config or env file inside the repository, or an env file readable by group or others: exit 2 with one line naming the key or the file kind, never its value. A `$(...)` in a value stays literal |
| Candidate | `--version <v> --rc <n> [--candidate <ref>]` | The default ref is `release/<v>-rc<n>`, or `HEAD` in a dry run. `<v>` must equal the ref's `src/module.xml` `<Version>` | Unknown ref, version mismatch, an `--rc` that is not a positive whole number, or (real mode) no `src/ocutalon/csp/index.html` in the commit ("Story 11.5 commits the web bundle on the candidate branch"): exit 2 |
| Dry-run candidate | `--dry-run`, ref without the built bundle | A temporary clone at the ref gets the worktree's built `src/ocutalon/csp/` (`git add -f`) and one local commit on branch `rehearsal/stand-in`, which is bundled. The record says it is a stand-in of `<sha>` with the built web bundle added | Bundle build fails: `ensure_web_bundle`'s FAIL line; exit 1 |
| Hosts | Both reachable | PASS hosts. The clean host has `git` and `docker` (`docker info --format`), and no container or volume labelled with project `${COMPOSE_PROJECT_NAME:-ocutalon}`. Each host's machine line is read (`uname -s`, `uname -m`, `/etc/os-release` `PRETTY_NAME` or `sw_vers -productVersion`, `/proc/meminfo` `MemTotal` or `sysctl -n hw.memsize`). Whether Node.js is on the clean host is recorded | SSH fails, a tool is missing, an OcuTalon container or volume exists, or (real mode) Node.js is present: `FAIL run install step hosts bound -: ...`; later steps `not run`; exit 1; nothing changed on either host |
| Copy | Hosts passed | The bundle is copied through `host_run`'s stdin and cloned with `git clone --branch`. The clone's `git rev-parse HEAD` equals the candidate sha. The detail gives the bundle size in KiB | HEAD differs, or the clone fails: FAIL copy |
| Install | Copy passed | The env file goes to the clone's `.env` through stdin (mode 600). `install.sh` runs in the clone. The wall-clock seconds of that call are the first start, install included; install.sh's "OcuTalon is ready after ..." text is kept beside them | Non-zero exit, or no `Open:`, `User:` or `Password:` line: FAIL install with install.sh's last 5 lines indented. Bound: `ready within <OCUTALON_INSTALL_WAIT or 900> s` |
| Sign-in | Install passed | The printed `http://localhost:<port>/ocutalon/` becomes `http://<REHEARSAL_CLEAN_WEB>:<port>/ocutalon/` (`127.0.0.1` in a dry run). The driver host signs in with the printed user and password, sent as a curl config on stdin (`curl -K -`), and the page holds `<app-root` | No `<app-root`: FAIL sign-in |
| Self-scan | Every phase's output appended to `<state>/output.log`; the section text | The `secrets` row passes when `env_file_hits` and `key_like` find nothing in the log or the section, and no configuration value appears in either | A planted value: FAIL secrets naming the variable or key name and the line count, never the value |
| Dry run, end to end | `run --dry-run --rc 1 --record <tmp>` | install, report, down. `RESULT dry run`; exit 3. The section reads `Result: dry run`, `Mode: dry run` and the dry-run note; the rows hosts, copy, install, sign-in and secrets pass; `demo path runs` is `not run` | down leaves no project, container, volume or image of the tag, no lane lock and no state folder |
| Real, every step passes | Stubbed hosts (self-test) | `Result: not run` (the timed runs row); `RESULT not run`; exit 1 | No error expected |
| Phase order | `report` or `install` again without a fresh tag; no `OCUTALON_RUN_TAG` | One refusal line; exit 2 | `down` may always run |
| Plan | `plan --rc 1 [--dry-run]` | Prints the candidate, the version, the sha, the hosts as "configured", "local" or "stand-in", the phases and the record path. Starts nothing; exit 0 | Same refusals as Candidate |

</intent-contract>

## Code Map

**Siblings and helpers to reuse**
- `release/standalone-bridge.sh:33-48` -- the release-script pattern: source `ci/iris.sh`, then `setup_tag; preflight; live_start <label>`, `live_track_image`, and print `READY ... <s>s`.
- `ci/iris.sh`:
  - :54 `setup_tag` (OCUTALON_RUN_TAG rule; exit 2);
  - :96 `preflight` (the mock's image);
  - :534 `cmd_teardown` (removes every project and image of the tag).
  - The file can be sourced; `release/standalone-bridge.sh` does.
- `docker/tests/lib-live.sh` (read only; Epic 12 contends it):
  - :58-90 `live_start` sets `P`, `root`, `tmp`, `deadline`, `LIVE_FILES` (judges' file, `$tmp/decoy.yml`, throwaway override, CI override), then the lock and `ensure_web_bundle` (:160);
  - :202-241 `live_web_port` writes `$tmp/port.yml` (`127.0.0.1:<port>:52773`) and adds it;
  - :111 and :140 `live_lock_claim` and `live_lock_release` (`LIVE_LOCK_FILE`, `LIVE_LOCK_CONTENT`, exit 75);
  - :252 `live_track_image`, :266 `live_cleanup`, :274-283 `pass`, `fail`, `die`, :287 `wait_until`.
- `ci/warm.sh:20-23, 39-60` -- the cross-call state pattern: save the project, the lock file and its content, then drop the trap; a later call re-attaches and checks the lock content. Its functions are warm-specific, so the pattern is copied, not called.
- `docker/tests/test-install-script-live.sh`:
  - :22-31 the throwaway's image names: `test_base=$P-base:<TAG>`, and `src_ref=$P-src/irishealth-community:<TAG>` tagged from `base_image`, with their own removal;
  - :42-56 `COMPOSE_FILE` from `LIVE_FILES`, then `env COMPOSE_PROJECT_NAME= COMPOSE_FILE= IRIS_IMAGE= OCUTALON_INSTALL_WAIT= bash install.sh`;
  - :82-101 parsing `Open:`, `User:` and `Password:`, and the curl sign-in that looks for `<app-root`.
  - It is a top-level script and cannot be sourced: the about 15 lines are copied (Rule 2 reason).
- `install.sh` (read only):
  - :32-43 `OCUTALON_INSTALL_POLL` and `OCUTALON_INSTALL_WAIT` (default 900);
  - :312-319 the `.env` lines ("Found .env. It was not changed.");
  - :390-399 the final output: "OcuTalon is ready after <t>.", then `  Open:      http://localhost:<port>/ocutalon/`, `  User:      ocutalon`, `  Password:  ocutalon`;
  - exit 1 on `die`.
  - It runs from its own folder with plain `docker compose`, which is `docker-compose.yml` (`name: ocutalon`) unless `COMPOSE_*` are set.
- `docker/tests/compose.throwaway.yml` -- resets `ports` and `env_file`, so the stand-in `.env` never reaches the container. `ci/compose.ci.yml` -- the mock, no key; `./ci/mock` is mounted from the first compose file's folder (the clone).
- `docker/tests/lib-keys.sh:15-30` -- `KEY_LIKE_ERE`, `key_like`, and `key_value_hits`, which reads the value inside awk and never prints it. The new `env_file_hits` sits beside it.
- `docker/tests/test-boundaries.sh`:
  - :40-62 `risky_docker_calls`;
  - :95 the `files` scope list, which does not hold `release/` today;
  - :98 and :203-205 the all-files local-path and `key_like` rules, which already cover `release/`.
- `release/demo-host-check.sh:46-47, 170` -- the `PASS|FAIL|SKIP <id> <text>` lines and the "exit 3 = not a pass" precedent.
- `docker/tests/test-online-host.sh:842-868` -- row 15 pins only the two Epic 29 scripts (it forbids `ssh`). The new scripts stay out of it.
- `_bmad-output/implementation-artifacts/spec-11-2-upgrades-and-restarts-keep-every-record-working.md` (ready-for-dev, not built):
  - Tasks: `record_section`, `record_write <file> <section>`, and "a missing file is created with `# OcuTalon <version> rc<n>`";
  - Design Notes: the `## Upgrade harness` section contract and the phase and state pattern.

**CI recipe**
- `ci/units.sh:6` -- `CHECK_SCRIPTS`; add `rehearsal` at the end. `:150` `NOT_IRIS_INPUT_PATTERN` already declares `release/` and `docker/tests/test-*.sh` non-inputs, so no IRIS group runs on this story's files.
- `docker/tests/test-ci-config.sh:633-648` -- every `docker/tests/test-*.sh` must sit in exactly one list. No pin names check scripts.
- `docker/tests/test-ci-changes.sh:245` -- pins "release runs no group"; unchanged.

**Facts the dry run relies on**
- `.gitignore:28` ignores `src/ocutalon/csp/`. The bundle holds `index.html` plus hashed assets.
- `docker/Dockerfile:11` copies `src/`, so the image from the clone serves the bundle that the clone holds.
- `.dockerignore` is an allow-list (`src`, the docker files).
- `src/module.xml:6` holds `<Version>0.1.0</Version>` today.

## Tasks & Acceptance

**Execution:**
- `(Task 0, measure)` On the first dry run, record in Verification:
  - each phase's seconds, and the first start;
  - that the stand-in's mock mounts the clone's `ci/mock`: `docker inspect --format '{{range .Mounts}}{{.Source}} {{end}}'` on the mock container. If Docker Desktop cannot mount a folder under `TMPDIR`, put `<state>` where it can, and say so here;
  - install.sh's printed lines on the stand-in.
- `release/lib-release.sh` -- new, sourced, with these functions:
  - `release_config_read <file>` (the Config row);
  - `host_run <clean|driver> <command>` (Always; mode from `REHEARSAL_MODE`: `real` or `dry`);
  - `record_path <version> <rc>`;
  - `record_write <file> <section> [<heading>]`. It replaces the section whose `## ` title matches the section's first line, up to the next `## ` line or the end of the file, or appends it. It creates the file and its folder with `<heading>`, by default `# OcuTalon <v> rc<n>` from a `.../<v>/rc<n>.md` path, else `# OcuTalon candidate record`. It writes through a temporary file and `mv`.
  - If `release/upgrade-harness.sh` already defines `record_write`, move that definition here, keep its behaviour, make the harness source this file, and keep `docker/tests/test-upgrade-harness.sh` green. Otherwise add a `deferred:` item asking that Story 11.2 source this file.
- `docker/tests/lib-keys.sh` -- add `env_file_hits <env file> <file>...`. It prints `file:line NAME` for each line that holds the non-empty value of a `NAME=value` line of the env file. Values are read inside awk and never printed; it returns 1 when a file cannot be read. Update the header.
- `release/rehearse.sh` -- new. The header is the usage and the contract for Story 11.5. It sources `lib-release.sh` and `lib-keys.sh`, and sources `ci/iris.sh` only in a dry run.
  - **Commands:** `plan`, `install`, `report`, `down`, `run` (install, report, then always down; each phase is its own `bash release/rehearse.sh <phase>` process). The options are `--version`, `--rc`, `--candidate`, `--record` and `--dry-run`, taken by `plan`, `install` and `run`, and stored in the state.
  - **The state** is `${TMPDIR:-/tmp}/ocutalon-rehearsal-<OCUTALON_RUN_TAG>/` (mode 700). It holds `options`, `results` (`step|result|detail`), `output.log`, `machine.clean`, `machine.driver`, `install.out`, `candidate.bundle`, `phase.<name>`, and `standin/` (P, the lock file and its content, the image names, and `clean/`, `driver/` and `env`).
    - Phases need `OCUTALON_RUN_TAG`; `run` defaults it to `reh-<epoch>`.
    - Each phase starts with `exec > >(tee -a <state>/output.log) 2>&1`.
  - **`install`:** the steps hosts, copy, install and sign-in from the matrix, each writing a PASS or FAIL line and its row.
    - In a dry run, before the steps: `setup_tag`, `preflight`, `live_start rehearse`, `live_web_port`, the image names of `test-install-script-live.sh:22-31`, the stand-in candidate and the stand-in env file. That file is written with `umask 077` and holds `ANTHROPIC_API_KEY=dry-run-canary-<random hex>` and `OCUTALON_REHEARSAL_CANARY=<random hex>`, so the self-scan has values to look for.
    - The stand-in `COMPOSE_FILE` is `LIVE_FILES` with the worktree root replaced by the clone's path.
    - At the end it saves the state and drops lib-live's trap (`ci/warm.sh`'s pattern). A `die` before the save tears the project down through `live_cleanup`.
  - **`report`:** runs the self-scan, then builds the section (Design Notes) and writes it with `record_write` to `--record` or to `record_path`. It prints `RECORD <file>` and `RESULT <result>`, and exits by the Result rules.
  - **`down`:** in a dry run, `cmd_teardown` for the tag, the image-name removal, then `live_lock_release` with the saved lock content (refused if the content differs). In both modes it removes the state and prints `TEARDOWN`. In real mode the clean host keeps its install, and the line says so.
- `docker/tests/test-rehearsal.sh` -- new, hermetic (no container, no network). It sources the two release files and lib-keys, and pins:
  - `release_config_read`: every refusal of the Config row; a literal `$(touch <marker>)` value creates no marker;
  - `host_run` through a stub `OCUTALON_REHEARSAL_SSH` that logs its argv and the size of its stdin: the options, the destination, `--`, the port and known-hosts cases, `local`, and no env-file value in any argv. In dry mode the stub is never called;
  - the parsers (`parse_install` on canned install.sh output, with each missing line; `machine_line` for Linux and Darwin input, with no host name; `hosts_verdict` on each failure);
  - the FAIL line grammar, the Result rules and the exit codes;
  - `record_write` (create with the heading, replace, append, another section kept byte for byte, no duplicate);
  - `env_file_hits` (a planted value is found and named, and its value never appears in the output).
  - In a synthetic git repository (a copy of the two release files, `lib-keys.sh`, a `src/module.xml` and a placeholder `src/ocutalon/csp/index.html`, committed on `release/1.0.0-rc1`), with stub hosts answering by command, it runs the copied script for real:
    - `install` with an OcuTalon volume on the clean host (hosts FAIL, later rows `not run`, exit 1);
    - a clone HEAD mismatch (copy FAIL);
    - install.sh exiting 1 (install FAIL with its bound);
    - every step passing, then `report` (`RESULT not run`, exit 1), with the section's machine lines holding no stub host name.
  - On the real tree: `plan --rc 1 --dry-run` exits 0 and starts nothing (a stub `docker` on `PATH` fails the case if it is called); `plan --version 9.9.9 --rc 1 --dry-run` exits 2; `report` with no state exits 2.
  - Static rules on both release files: no `source` or `.` of a variable path other than the three libraries (`lib-release.sh`, `lib-keys.sh`, `ci/iris.sh`), no `cat "$...env..."` to stdout, `umask 077`, mode 100755, ASCII, no `StrictHostKeyChecking=(no|accept-new)`, and no `docker (push|login|save|export)`.
- `docker/tests/test-boundaries.sh` -- add `'release/*.sh'` to the `files` scope (:95), so `risky_docker_calls` and the ASCII rule cover every release script (Rule 2: extend). If a release script that already exists fails, stop and report it under `deferred:`, rather than changing an open epic's file.
- `ci/units.sh` -- add `rehearsal` to the end of `CHECK_SCRIPTS`, and nothing else. Then run `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml`.

**Acceptance Criteria:**
- **AC1 (hosts and copy; FR-55, REL-6, AD-25).** Given a configuration outside the repository, when `rehearse.sh install` runs in real mode against hosts, then:
  - every remote action goes through `host_run` with the configured key, BatchMode and strict host keys;
  - the clean host is checked as the Hosts row says;
  - a `git bundle` of the candidate branch is copied through stdin and cloned, and the clone's HEAD is the candidate commit.
  - This is pinned in the self-test on stub hosts.
- **AC2 (install and first start; FR-55, NFR-22, AD-23).** Given the clone, when the install step runs, then:
  - the env file becomes its `.env` through stdin only;
  - `install.sh` runs there and reaches ready;
  - the printed address, mapped to the clean host's web address, signs in from the driver host with the printed user and password;
  - the record's install row gives the first start's seconds, install included.
- **AC3 (no value printed; NFR-11, AD-19).** Given any run, when it ends, then neither the output log nor the record holds a value of the env file or the configuration file, the `secrets` row says so, and the static rules hold. A planted value fails the row and names only the variable.
- **AC4 (a failed step; REL-6, CON-5).** Given a failure at any install step, when the rehearsal ends, then:
  - its line reads `FAIL run install step <step> bound <bound>: <detail>`;
  - later steps are `not run`;
  - `Result: fail` and exit 1 block the release;
  - the record's machine lines give only the operating system, the CPU architecture and the memory.
- **AC5 (dry run; REL-6, NFR-11).** Given this build, when `run --dry-run --rc 1 --record <tmp>` runs on the developer machine with lane A's variables, then the stand-ins do the work:
  - a throwaway compose project with the CI mock stands in for the clean host;
  - the machine the script runs on, in its own folder, stands in for the driver host;
  - no `ssh` runs;
  - every install row passes, `demo path runs` is `not run`, the record and the output say dry run, and the exit is 3;
  - `down` leaves nothing of the tag.
- **AC6 (record writer; integration: consumer `rehearse.sh report`).** Given a record file that already holds another `## ` section, when `report` writes, then that section stays byte for byte, the rehearsal section appears once (replaced on a second report), and a missing file is created with `# OcuTalon <v> rc<n>`. A real run whose steps all passed reads `Result: not run` and exits 1, because the timed runs are not built.
- **AC7 (interface for Story 11.5).** Given the header's usage, when `plan`, `run`, a phase out of order or a bad option runs, then they behave as the matrix's Plan, Phase order and Candidate rows say, and the header documents the commands, the configuration keys, the section lines and the exit codes.
- **AC8 (the boundary rules reach `release/`).** Given `test-boundaries.sh`, when it runs on the tree, then its docker-call and ASCII rules cover `release/*.sh` and pass.

### Review Findings

Code review, 2026-11-01 (follow-up review; four layers, full-opus tier; 32 raw findings grouped into 15 entries: 0 high, 5 medium, 10 low; all patched but one low, ledgered as DW-531).

- [x] [Review][Patch] (med) The configuration scan read only `NAME=value` lines exactly as written, so a quoted or spaced line, an expanded `~/` path and the host of a `user@host` were never looked for (AC3) [release/rehearse.sh:config_values, scan_run] -- `report` also scans the values as `release_config_read` set them, with `<KEY>_HOST` for each destination's host; hits are de-duplicated.
- [x] [Review][Patch] (med) "Host keys stay strictly checked" depended on the user's ssh configuration (a `StrictHostKeyChecking accept-new` there accepted a first key, and the env file then went to that host) [release/lib-release.sh:host_run] -- `host_run` passes `-o StrictHostKeyChecking=yes`; the headers say so.
- [x] [Review][Patch] (med) The stub printed the same user and password, so a swapped or fixed sign-in passed (AC2) [docker/tests/test-rehearsal.sh:mkstub] -- the stub prints `ocu-user` and `ocu-pass-1`; the stub run asserts both in the curl config.
- [x] [Review][Patch] (med) The clean-host probe never ran in a test, so a wrong label filter or a dropped `-a` would certify a host with a leftover stack (Hosts row) [docker/tests/test-rehearsal.sh:t_parsers] -- the probe runs on stub docker, git and node, its counts feed `hosts_verdict`.
- [x] [Review][Patch] (med) The dry run's compose-file mapping and its `down` (image removal, lane-lock release) had no hermetic test (AC5) [release/rehearse.sh:standin_files, cmd_down] -- the mapping is `standin_files`, with a unit case; rule dry-down runs `down` on a hand-made dry state with a stub docker.
- [x] [Review][Patch] (low) The `OCUTALON_INSTALL_WAIT` passed to the remote install.sh was never asserted [docker/tests/test-rehearsal.sh:t_stub_runs]
- [x] [Review][Patch] (low) `plan` was never run with a local driver [docker/tests/test-rehearsal.sh:t_candidate]
- [x] [Review][Patch] (low) `REHEARSAL_CLEAN_WEB` had two definitions (one read like `host:port`) [release/lib-release.sh, release/rehearse.sh headers] -- both say a name or address, no scheme and no port.
- [x] [Review][Patch] (low) `REH_STEPS` was defined and never used [release/rehearse.sh]
- [x] [Review][Patch] (low) The scope loop printed `printf: write error: Broken pipe` [docker/tests/test-boundaries.sh:112,119] -- `grep -qxF -- "$f" <<< "$files"`.
- [x] [Review][Patch] (low) An `--rc` with a second line passed the line-wise check [release/rehearse.sh:parse_options] -- a `case` pattern.
- [x] [Review][Patch] (low) The header said no configuration value is put on a command line; ssh's arguments name the destination, key and port [release/rehearse.sh header]
- [x] [Review][Patch] (low) lib-live's `live_start` replaces the EXIT trap, so a failure inside it left the state and refused the next `install` on the tag [release/rehearse.sh:cmd_install] -- `install` removes a state whose install phase did not finish.
- [x] [Review][Patch] (low) A dry `down` said the lock was removed when `live_lock_release` kept it [release/rehearse.sh:cmd_down] -- the line defers to the LOCK line.
- [x] [Review][Defer] (low) `tag_ok` repeats lib-live's `live_tag_ok` (Rule 2, weak reason) [release/rehearse.sh:tag_ok] -- DW-531, wontfix-accepted, reopen_if the tag rule changes in lib-live alone.

Rejected:
- low, spec-bound: a dry run with no `--record` writes `release/records/<v>/rc<n>.md` (the spec names the default, and the section reads `Result: dry run`).
- low, spec-bound: the sign-in step passes on `<app-root` without proving a signed-out page lacks it (the Sign-in row defines the check, as the sibling `test-install-script-live.sh` does).
- low, theoretical: `command -v node`/`docker` in a non-interactive ssh shell miss nvm, Homebrew and `/usr/local/bin` (Story 38.2's clean host is a fresh Linux droplet with system packages; real on a macOS or nvm clean host).
- low, theoretical: after a secrets hit the Candidate, host and Run lines are not withheld or re-scanned (they come from fixed probes and options).
- low: a symlinked env file is refused with the chmod hint (fails closed; resolving links reopens a repository-path bypass).
- low, spec-bound: `env_file_hits` in `lib-keys.sh`, an IRIS input (the Tasks place it there).
- low: an interrupted `run` skips `down` (a signal path; `down` or `ci/iris.sh teardown` with the tag recovers).
- low: an unreadable scan input reads "found a value" in the withheld text (fails closed; the files are the script's own).
- false: setup FAIL lines outside the step grammar (the Dry-run candidate row allows `ensure_web_bundle`'s FAIL line; the step grammar is for steps).
- low: the in-repository refusal checks this checkout only (the main checkout's `.env` is gitignored; nothing is printed or committed).
- low, spec-bound: install.sh's last lines in a failed row may name a path (the Install row puts them there; `test-boundaries.sh` refuses a local path in a committed record).

## Spec Change Log

## Review Triage Log

### 2026-11-01 -- Review pass
- verdicts: 31 findings reported (Blind 10, Edge 15, Gap 6; the intent audit is descriptive and reported none), grouped by root cause into the rows below -- 4 medium (patched), 5 low patched, 9 low rejected, 0 high, 0 false, 0 maybe-false
- findings:
  - `[medium]` `[patch]` Blind: the secrets scan skipped `install.out`, the likeliest place for a leak -- `install.out` joins the scanned files (`scan_run`); pinned by a stub run with a value only in install.sh's output.
  - `[medium]` `[patch]` Blind, Edge, Gap: `run --record <relative>` resolved against the repository root in the install child -- the child starts in the caller's folder; pinned by a stub run from another folder.
  - `[medium]` `[patch]` Edge: a secrets hit still wrote install.sh's tail into the record through the other rows -- every other row's detail is withheld on a hit; pinned by a stub run whose install tail holds the value.
  - `[medium]` `[patch]` Gap: the sign-in failure branch was never run (a mutation to always pass stayed green) -- a stub run with a page lacking `<app-root` pins the FAIL line, row and result.
  - `[low]` `[patch]` Edge: `hosts_verdict` read `$c$v`, so one missing count passed -- each count is checked; two parser cases.
  - `[low]` `[patch]` Edge: `record_write` failure was unchecked in `report` -- it returns non-zero and `report` prints FAIL and exits 1; an empty section title is refused.
  - `[low]` `[patch]` Edge: `run` left the state when the install died before it was saved -- `run` calls `down` then ("then always down").
  - `[low]` `[patch]` Gap: the dry record's Mode, stand-in and note lines had no hermetic pin -- rule dry-section with its own break.
  - `[low]` `[patch]` Blind, Gap: `b_phase_order` and `b_real` were dead stubs and the no-tag case did not unset the tag -- stubs removed, the tag is unset and the refusal text is asserted; the hosts-failure run asserts the secrets row.
  - `[low]` `[reject]` Blind, Edge: `host_run` does not wrap the command in `sh -c` remotely, no `ServerAliveInterval`, ssh config could weaken host keys -- the spec fixes the exact ssh command line (Boundaries); the author's host login shell is POSIX-compatible in practice.
  - `[low]` `[reject]` Blind: the clean-host check ignores cached images -- the Hosts row defines the check; the dry run's first start is layer-cached and Task 0 says so.
  - `[low]` `[reject]` Blind: `OCUTALON_REHEARSAL_SSH` honoured in real mode -- the spec names it as the test seam (`${OCUTALON_REHEARSAL_SSH:-ssh}`).
  - `[low]` `[reject]` Blind: a symlink can hide a repository file from the in-repository check -- unlikely, and the fix adds link resolution.
  - `[low]` `[reject]` Blind: real `down` keeps the `.env` on the clean host -- spec-bound (down says the clean host keeps its install; Story 38.2's host is a throwaway).
  - `[low]` `[reject]` Blind: every usage error prints the whole header -- cosmetic.
  - `[low]` `[reject]` Edge: stand-in without a built bundle, an older ref without compose files, an empty `REHEARSAL_CLEAN_WEB` with a port, a non-atomic state claim, `env_file_hits` with an inline comment or leading space, a value of 7 characters or fewer, no `curl` HTTP status for the sign-in (the sibling test does the same), trap order when `live_start` fails (down now cleans it) -- theoretical or spec-bound, or decided in-stage (item 10); the dry run's `live_start` builds the bundle first.
  - `[low]` `[reject]` Gap: branch-level stub cases for a silent host, a failed bundle copy, a failed env write -- the parsers and verdicts that decide them are pinned; a stub case per branch adds more than 15 lines each.
  - `[low]` `[reject]` Intent: no divergence beyond the spec's own scope -- the end-to-end dry run is a live loop command by the spec, and is not a CI unit.

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-19 | the key lives only in the host's `.env`; it is never stored, printed or recorded |
| AD-22 | dry runs on throwaways with the CI override and the mock, no real key; the docker-call rules |
| AD-23 | `install.sh`, the image retag and the first start; the web bundle is committed on the candidate, and the Docker install needs no Node.js |
| AD-25 | the release scripts reach hosts only over SSH with the author's configuration outside the repository, and copy a `git bundle` |
| AD-29 | `release/` is Lane A's; `ci/units.sh` is shared by region |
| AD-15 | not used here: it governs Story 11.11's timing splits |

No AC contradicts an AD.

**The record section** (indented two spaces here so that no section scan reads it; in the record each line starts at column 1; the order is fixed):
```
  ## Clean-machine rehearsal

  Result: dry run
  Mode: dry run
  Candidate: 1.0.0 rc1, branch rehearsal/stand-in at <full sha>, a stand-in of <full sha> with the built web bundle added
  Clean host: Linux (Ubuntu 24.04.1 LTS), x86_64, 15.6 GiB memory; Node.js absent
  Driver host: macOS 26.0.1, arm64, 64.0 GiB memory
  Run: <UTC start> to <UTC end>
  Note: A dry run on throwaway stand-ins for the clean host and the driver host, with the CI mock in place of the model. It is not a rehearsal pass; the real rehearsal is Story 38.2's.

  | Step | Result | Detail |
  | --- | --- | --- |
  | hosts | pass | both hosts answered; git and Docker on the clean host, no OcuTalon container or volume |
  | copy | pass | git bundle of 412 KiB; the clone is at the candidate commit |
  | install | pass | install.sh reached ready; first start 187 s, install included |
  | sign-in | pass | the driver host signed in at the printed address as the printed user |
  | secrets | pass | no .env or configuration value in the output or the record |
  | demo path runs | not run | the timed runs come with Story 11.11 |
```
- In real mode: `Mode: rehearsal`, no `Note:`, and the candidate's own branch.

**Interface for Story 11.5 (Consumed-by).**

| Link | Who |
| --- | --- |
| Consumed-by | Story 11.5's rehearsal gate: `OCUTALON_RUN_TAG=<t> bash release/rehearse.sh run --version <v> --rc <n>` (add `--dry-run` for its rehearsal candidate, which has no hosts). It reads `Result:` and `Mode:`. Only exit 0 with `Result: pass` passes |
| Consumed-by | Story 11.5's update hook may reuse `release_config_read` and `host_run` (a `DEMO_` prefix in the same file) |
| Consumed-by | Story 11.11 adds the `runs` phase between `install` and `report`, and the bounds rows |
| Consumed-by | Story 38.2 runs `run` for real with the Contest Planner's configuration |
| Consumed-by | Story 11.4's notes read the first start from the section |
| Consumed-by | Story 11.2's harness, which writes its section through `record_write` |
| Consumes | `install.sh`; `ci/iris.sh` and `docker/tests/lib-live.sh` (the throwaway); `ci/compose.ci.yml` and the mock; `docker/tests/lib-keys.sh` |

- **Integration ACs (Rule 1).** AC6 covers the record writer, which `report` consumes. Beyond that, no consumers in this story; the first outside consumer will be Story 11.5.

**Extend, don't copy (Rule 2).**
- The record writer is the one shared copy in `lib-release.sh`. Story 11.2's planned `record_write` moves there, or sources it.
- The value scan extends `lib-keys.sh`.
- The docker-call and ASCII rules extend `test-boundaries.sh`'s scope rather than being written again.
- The throwaway reuses `ci/iris.sh` and `lib-live.sh` as `standalone-bridge.sh` does.
- Two copies remain, each with its reason:
  - about 15 lines of `test-install-script-live.sh` (a top-level script, and lib-live is Epic 12's contended file);
  - `ci/warm.sh`'s state pattern (its functions are warm-specific).

**Decided in-stage.**
1. **The driver stand-in** is the machine the script runs on, in its own folder. A container driver would need a Playwright image, a new dependency, and the real driver is also a Mac running Playwright locally.
2. **Strict host keys.** The author adds each droplet's key (or names `REHEARSAL_KNOWN_HOSTS`). This is the safe default, and the configuration key makes it convenient.
3. **One configuration file**, `release.conf`, with prefixed keys, so Story 11.5's demo-host keys can join it.
4. **Dry-run Node.js.** In a dry run, the clean stand-in shares this machine, so Node.js on it is recorded but not failed. In real mode it fails (Story 38.2: a clean host has no Node.js).
5. **The self-scan is a recorded row in both modes**, so a real record also states it.
6. **Not a CI unit.** It follows Story 11.2's precedent (the lead's ruling 3), so REL-4's budget is unchanged. The hermetic self-test runs in the hosted `checks` job, which adds a few seconds.
7. **A real run cannot pass until Story 11.11** adds the timed runs (`Result: not run`).
8. **The `secrets` step always runs**, in `report`, also after a failed install step: AC3 says the row speaks for any run. The steps hosts, copy, install and sign-in are the ones that become `not run` after a failure.
9. **The log is written through a pipeline** (`phase | tee -a <state>/output.log`) rather than `exec > >(tee ...)`, so that `output.log` is complete when the phase returns and `report` cannot scan a half-written log. The exit code is the phase's own (`PIPESTATUS`).
10. **`env_file_hits` reads values of 8 characters or more.** A short value such as `0` or `true` is in every log, so scanning it would fail every real run; a key, a token and a host address are longer.
11. **Options.** `--rc` is always required. `--version` is optional in a dry run and with `--candidate` (the version is the ref's `<Version>`), and required in a real run without `--candidate` (the default ref needs it). A real candidate must be a local branch (the bundle and the clone use its name); the branch name may hold only letters, digits and `._/-`.
12. **No ssh text is shown.** `host_run`'s own stderr is discarded (an ssh error names the host), so a remote command redirects its own stderr to its stdout (`2>&1`) when its text matters. A failed `hosts` step says to run the ssh command by hand.
13. **Rule 2 moves.** Besides `record_write`, `env_get`, `env_set` and `detail_clean` moved from `release/upgrade-harness.sh` to `release/lib-release.sh` (the options and the result details of both scripts need them); the harness sources the library. `release/upgrade-harness.sh` keeps no other change.
14. **The throwaway's temporary files move into the state.** `decoy.env`, `decoy.yml` and `port.yml` are copied to `<state>/standin/compose/` (the decoy file's path rewritten), the `COMPOSE_FILE` of the stand-in points at them and at the clone's compose files, and lib-live's temporary folder is removed at the save.
15. **Smaller choices.** A real `plan` reads the configuration like `install` (the same refusals); `down` with no state removes nothing and exits 0 (without a state the mode is unknown); a dry-run stand-in commit is made with `--allow-empty`, so a candidate that already holds the bundle still gets its stand-in commit; in real mode `OCUTALON_INSTALL_WAIT` of the caller is passed to the remote `install.sh` as `env OCUTALON_INSTALL_WAIT=<n>`.
16. **Review pass.** When the secrets step finds a value, `report` withholds every other row's detail from the record (`withheld: the secrets step found a value in this run`), because the rows carry install.sh's last lines. The scan also reads `install.out`. `run` starts its install child in the caller's folder, so a relative `--record` lands there, and `run` calls `down` when the install phase died before it was saved. `record_write` returns non-zero when the record cannot be written (the report then prints a FAIL line and exits 1), and `hosts_verdict` refuses a reply that lacks the containers or the volumes count.

**Proposed split (smaller is better; for the lead).**
- **Story 11.11, "The rehearsal runner times the demo path and checks every bound (dry runs on throwaways)",** right after 11.3, takes these verbatim:
  - the second criterion (the rehearsal runner, N runs, the report's splits and every bound);
  - from the third, "a failed run or a missed bound … names the run, the step and the bound";
  - from the fourth, "a run set with a planted missed bound that fails the rehearsal and names the run, the step and the bound".
- Story 11.5 then composes 11.3 and 11.11.
- Its plan may split again, into the timing collector and bounds report, and the N-run driver. It must also face these facts:
  - The demo-path specs assume a first run: `02-watch.spec.ts:39-52`, `web/e2e/support/demo-path.ts:211`, `04-incident.spec.ts:62`. Run again (`Data/GuideState.cls:67-82`) reopens only steps 3 to 5.
  - The specs' exec channel is the local `docker exec` (`web/e2e/support/iris.ts:26-41, 73`).
  - Row times are whole seconds (`Data/Time.cls:18-20`), so the 2 s and 5 s bounds need message-header times or browser clocks.
  - Nothing exposes `Usage.LargestRequestTokens` over HTTP.
  - A reminder has no `FiredAt`; its `Late` flag is NFR-10's 10 s.
  - The specs have no tell-now step.
  - Twenty runs exceed one 10-minute call.

**Ledger (Rule 17).** This story owns no entries.

**Contended paths (U14).** Every file this story changes is listed under Tasks. Checked against the diffs of `origin/OCT-epic12`, `-13`, `-15`, `-30` and `-31` at plan time:
- New files: `release/rehearse.sh`, `release/lib-release.sh`, `docker/tests/test-rehearsal.sh`.
- Changed:
  - `docker/tests/lib-keys.sh` (one function appended);
  - `docker/tests/test-boundaries.sh` (the scope list);
  - `ci/units.sh` (the `CHECK_SCRIPTS` line only, contended by 12, 13 and 15 and shared by region: a plain union);
  - possibly `release/upgrade-harness.sh` (this epic's).
- No other contended file is touched. Epic 29's release files are read only.

## Clarification Needed (non-blocking: the plan does not depend on the answer)

1. Accept the proposed split into Story 11.11 (decide, product default 6, as at 11.1 and 11.7). If it is rejected, re-plan 11.3 with the runner criteria. This spec stays valid as its first part.

## Verification

**Commands:**
- `(loop)` `bash docker/tests/test-rehearsal.sh` -- expected: every PASS line, exit 0.
- `(loop)` `bash docker/tests/test-boundaries.sh` -- expected: exit 0, with `release/*.sh` in scope.
- `(loop)` `bash docker/tests/test-ci-config.sh && bash docker/tests/test-ci-changes.sh && bash ci/changes.sh ci.yml` -- expected: exit 0. `rehearsal` is in exactly one list.
- `(loop)` `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement' OCUTALON_RUN_TAG=e11s3d bash release/rehearse.sh run --dry-run --rc 1 --record "${TMPDIR:-/tmp}/e11s3-dry/rc1.md"` (`timeout: 600000`) -- expected:
  - `RESULT dry run`, exit 3, and the section as in Design Notes;
  - then `docker ps -a --format '{{.Names}}' | grep -c e11s3d` prints 0, and the lane folder holds no lock of this run.
  - If anything is left, run `ci/iris.sh teardown` with the same tag and the same three lane variables.
  - Record Task 0's figures here.
- `(loop, only if release/upgrade-harness.sh exists)` `bash docker/tests/test-upgrade-harness.sh` -- expected: exit 0.
- `(once)` `bash ci/checks.sh` -- expected: every check script passes.

**Mutations to demonstrate (Rule 19; one per AC, recorded here as `mutation: <change> → <test red>`):**
- AC1: drop `-o BatchMode=yes` from `host_run`, so the stub-argv case fails.
- AC2: compute the first start before install.sh runs, so the live dry run's install detail and the record case fail.
- AC3: echo the env file's line, so the planted-value case and the static rule fail.
- AC4: add `uname -n` to `machine_line`, so the no-host-name case fails.
- AC5: `host_run` in dry mode calls the stub ssh, so the dry-mode stub case fails.
- AC6: make `record_write` always append, so the replace case fails.
- AC7: let `report` run with no state, so the order case fails.
- AC8: add `docker compose config` without `--quiet` to `rehearse.sh`, so `test-boundaries.sh` fails.

**Task 0, measured on the first dry runs (developer machine, Docker Desktop, arm64, tag e11s3d, lane A):**
- Phases, `run --dry-run` (three runs): `install` 88 to 90 s, `report` 0.1 s, `down` 6.3 s; the whole `run` 96 s. The first start (the seconds of the `install.sh` call, install included) was 82 to 84 s (install.sh said "ready after 1 min 21 s" to "1 min 23 s"); the image build was layer-cached, so a cold build adds to it. `live_start` and the stand-in candidate (clone, force-added bundle, commit, `git bundle` of 22 MiB) take about 5 s.
- The mock mounts the clone's folder: `docker inspect --format '{{range .Mounts}}{{.Source}} {{end}}'` on the mock container gave `<TMPDIR>/ocutalon-rehearsal-<tag>/standin/clean/ocutalon-rehearsal/candidate/ci/mock` and the mock-log volume. The iris container mounts the clone's `eval/` the same way (through Docker Desktop's host mount). Docker Desktop mounts a folder under `TMPDIR` as it is, so `<state>` stays under `TMPDIR`.
- install.sh's printed lines on the stand-in: "OcuTalon install"; "Docker is running on arm64, and Docker Compose is 5.5.0."; "Image: IRIS for Health, build 154 (...)"; "Tagged it as <P>-base:<tag>, the name that OcuTalon's own image is built from."; "Found .env. It was not changed."; the "Starting OcuTalon with docker compose up -d ..." line and the compose and build output; "Waiting, <n> s so far: container running, health check starting" every 10 s; then "OcuTalon is ready after 1 min 22 s.", `  Open:      http://localhost:52801/ocutalon/`, `  User:      ocutalon`, `  Password:  ocutalon`.
- The record read: `Result: dry run`, `Mode: dry run`, the five passing rows and `demo path runs | not run`; `docker ps -a` for the tag printed 0 afterwards, and the lane folder held no lock. A held lane lock made `run --dry-run` exit 75 with no state left.

**Mutations demonstrated (Rule 19; each applied, observed red, reverted byte-identical):**
- mutation: AC1: drop `-o BatchMode=yes` from `host_run` -> `test-rehearsal.sh` rule host-run red (the stub-argv case lacks `BatchMode=yes`).
- mutation: AC2: compute the first start before `install.sh` runs -> rule stub-runs red (the install row no longer gives a first start of 1 s or more); the live dry run's detail would read `first start 0 s`.
- mutation: AC3: `cat` the env file in the install step -> rules stub-runs (the output log holds the value, the secrets row fails on a passing run) and static (`cat of an env file`) red.
- mutation: AC4: add `uname -n` to `machine_line` -> rules parsers (the line holds this machine's host name) and stub-runs (the machine lines differ) red.
- mutation: AC5: `host_run` leaves dry mode (`dry)` renamed) so dry calls the stub ssh -> rule host-run red (the stub log is not empty, the stand-in folders are not used).
- mutation: AC6: make `record_write` never match its section, so it always appends -> rules record and stub-runs red (two sections, the old text kept), and `test-upgrade-harness.sh` rule record red.
- mutation: AC7: let `report` run with no state (the refusal removed) -> rules phase-order and real-tree red (exit 1, not 2).
- mutation: AC8: add `docker compose config` with no `--quiet` to `release/rehearse.sh` -> `test-boundaries.sh` rule "docker calls" red (`release/rehearse.sh:452`).
- mutation: AC4 (review pass, sign-in): the sign-in step passes whatever the page holds -> rule stub-runs red (a page with no `<app-root` no longer fails the step, the row or the result).
- mutation: AC3 (review pass, withheld text): the report no longer withholds the other rows' text after a secrets hit -> rule stub-runs red (the record holds the value; the withheld text is missing).
- mutation: AC3 (review pass, install.sh's full output): `install.out` removed from the scanned files -> rule stub-runs red (a value only in install.sh's output passes the secrets step).
- mutation: AC7 (review pass, relative record): `run` starts its install child in the repository folder instead of the caller's -> rule stub-runs red (the record is written into the repository).
- mutation: AC5 (review pass, dry record): the dry section reads `Mode: rehearsal` (the mode option forced to real) -> rule dry-section red (its own synthetic break `b_dry_section` goes red the same way).

**QA stage (2026-11-01; mutations re-applied by the QA stage, each observed red and reverted byte-identical, `git status --short` and `git diff` checksums unchanged):**
- mutation: AC1: drop `-o BatchMode=yes` from `host_run`'s ssh arguments -> `test-rehearsal.sh` rule host-run red.
- mutation: AC2: `first=$((t0 - t0))` in `step_install` -> rule stub-runs red.
- mutation: AC3: `cat "$(env_file_path)"` at the top of `step_install` -> rules stub-runs and static red.
- mutation: AC4: `uname -n` appended to `machine_line`'s output -> rules parsers and stub-runs red.
- mutation: AC5: `dry)` renamed in `host_run` -> rule host-run red.
- mutation: AC6: `record_write` never matches its section -> rules record and stub-runs red.
- mutation: AC7: `report`'s phase-order refusal replaced by `if false` -> rules phase-order and real-tree red.
- mutation: AC8: `docker compose config > /dev/null` added to `release/rehearse.sh` -> `test-boundaries.sh` rule "docker calls" red; a non-ASCII character there -> rule "ascii" red. (Detection note: the rule needs a space or end of line after `config`, so `config;` is not seen; nothing in `release/` has that shape.)
- (QA) `docker/tests/test-rehearsal.sh` rule record gains four cases for the shared writer's other direction (the upgrade harness's `## Upgrade harness` section replaced once while the `## Clean-machine rehearsal` and checklist sections stay byte for byte). mutation: the section terminator in `record_write` narrowed so a replaced section swallows the next one -> rule record red ("the checklist section after it is kept").
- Harness section shape (AC6 integration): `git diff f64cf74d..HEAD -- release/upgrade-harness.sh` removes only `env_get`, `env_set`, `detail_clean` and `record_write` and adds the `lib-release.sh` source line; every caller passes its own heading, `record_section` is untouched, and `test-upgrade-harness.sh` (rules record and record-contract) is green.
- QA live dry run (tag e11s3q, lane A, `--record` in the scratchpad): `RESULT dry run`, exit 3, first start 82 s, install phase 88 s; afterwards no container, volume, image, state folder or lane lock of the tag; `git status` shows no record under `release/records/`.
- QA loop at HEAD: `test-rehearsal.sh` (12 rules), `test-boundaries.sh`, `test-upgrade-harness.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `ci/changes.sh ci.yml` all pass.

**Code review (2026-11-01; each mutation applied, observed red and reverted, `git status --short` and `git diff` checksums unchanged):**
- mutation: AC1 (strict host keys): `-o StrictHostKeyChecking=yes` removed from `host_run` -> rules host-run and stub-runs red.
- mutation: AC3 (configuration as used): `config_values` prints only the `_HOST` lines -> rule stub-runs red (the spaced, quoted `REHEARSAL_CLEAN_WEB` passes the secrets step).
- mutation: AC2 (printed user and password): `signin_config "$url" "$PI_PASSWORD" "$PI_USER"` in `step_signin` -> rule stub-runs red.
- mutation: AC2 (install bound): the `env OCUTALON_INSTALL_WAIT=` prefix dropped -> rule stub-runs red.
- mutation: Hosts row (the probe): the containers filter's label misspelled, and separately `-a` dropped from `docker ps` -> rule parsers red.
- mutation: AC5 (stand-in compose files): the worktree arm of `standin_files` removed -> rule parsers red.
- mutation: AC5 (down): `live_lock_release` removed from `cmd_down` -> rule dry-down red.
- mutation: AC7 (plan, local driver): `hd=configured` always -> rule candidate red.
- mutation: AC7 (`--rc`): the length and digit arms of the `--rc` pattern removed -> rule candidate red.
- Code-review loop: `test-rehearsal.sh` (13 rules), `test-boundaries.sh` (no broken-pipe line), `test-upgrade-harness.sh` and `test-ci-config.sh` pass. Live dry run (tag e11s3cr, lane A, `--record` in the scratchpad): `RESULT dry run`, exit 3, first start 82 s, install phase 88 s, 94 s in all; afterwards no container, volume, image, state folder or lane lock of the tag, and nothing under `release/records/`.

**Loop results at hand-off:** `test-rehearsal.sh` all 11 rules pass; `test-boundaries.sh` passes with `release/*.sh` in scope (no existing release script failed it); `test-upgrade-harness.sh`, `test-storage.sh`, `test-ci-config.sh`, `test-ci-changes.sh` and `ci/changes.sh ci.yml` exit 0 (no pin of `test-ci-config.sh` needed an update); `rehearsal` is in `CHECK_SCRIPTS` only.

**Shared surfaces:**
- `CHECK_SCRIPTS` in `ci/units.sh`, read by the units rule of `test-ci-config.sh`.
- The scope of `test-boundaries.sh`, which now covers every `release/*.sh`.
- `lib-keys.sh`'s function list, which other scripts source.
- Every test added or changed passes on a fresh environment, in either order. The self-test builds its own repository and stubs, and the dry run brings up its own throwaway and removes it.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `release/rehearse.sh` (commands plan, install, report, down, run) copies a candidate as a `git bundle` to a clean host over SSH through the one `host_run`, clones it, puts the env file beside it through stdin, runs `install.sh`, times the first start, signs in from the driver host, self-scans for env and configuration values, and writes the `## Clean-machine rehearsal` section through the new shared `release/lib-release.sh`. `--dry-run` swaps both hosts for a lane-A throwaway with the CI mock and the local machine, and reads `Result: dry run`, exit 3. A real run whose steps all pass reads `Result: not run` (exit 1) until Story 11.11.

**Files.**
- `release/rehearse.sh` -- new, the rehearsal.
- `release/lib-release.sh` -- new: `release_config_read`, `host_run`, `record_path`, `record_write`, plus `env_get`, `env_set`, `detail_clean` moved from the harness.
- `release/upgrade-harness.sh` -- sources the library; its record writer moved out (self-test unchanged and green).
- `docker/tests/lib-keys.sh` -- `env_file_hits` appended.
- `docker/tests/test-rehearsal.sh` -- new hermetic self-test, 12 rules; a `checks` script.
- `docker/tests/test-boundaries.sh` -- `release/*.sh` in scope.
- `ci/units.sh` -- `rehearsal` appended to `CHECK_SCRIPTS`.

**Review.** Patches applied: 4 medium (install.out scanned; relative `--record` under `run`; other rows withheld from the record on a secrets hit; sign-in failure pinned) and 5 low (count check in `hosts_verdict`, `record_write` failure, `run` calls `down` after an unsaved install, dry-section rule, dead test stubs and the no-tag case). Deferred: none. Rejected with reasons: see the Review Triage Log (9 low rows).

**Follow-up review recommended: true.** Two or more medium entries were patched (4). The unverified risk: the real-mode SSH path (remote shell quoting, host-key behaviour, `curl -K -` on a real driver) is proved only on stub hosts and the local stand-in; Story 38.2 is its first real run.

**Verification.** `test-rehearsal.sh` 12 rules pass; `test-boundaries.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `ci/changes.sh ci.yml`, `test-upgrade-harness.sh` pass; `ci/checks.sh` passes (rehearsal 18 s); the live dry run (tag e11s3d, lane A) printed `RESULT dry run`, exit 3, first start 95 s, 101 s install phase; afterwards no container, volume, image, state folder or lock of the tag remained. Mutations for AC1 to AC8 and the review-pass pins are recorded under Verification.

**Residual risks.** The stand-in bundle is about 22 MiB (full history). Cached image layers make the dry run's first start shorter than a cold one. `test-boundaries.sh` prints a harmless `printf: write error: Broken pipe` from its scope loop.
