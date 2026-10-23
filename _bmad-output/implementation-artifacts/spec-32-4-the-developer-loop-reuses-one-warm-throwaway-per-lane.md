---
title: 'Story 32.4: The developer loop reuses one warm throwaway per lane'
type: 'chore'
created: '2026-10-23'
status: 'done'
baseline_revision: 'db24acfa79c875526149be46b2ce8cc142cc051a'
baseline_commit: 'db24acfa79c875526149be46b2ce8cc142cc051a'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the developer machine every `ci/iris.sh class` or `shard` call starts a fresh IRIS. On Stories 1.7 and 2.7 that was about half of each 5.7-hour story: 66 `class` calls averaging 1.7 minutes, more than half of each the start.

**Approach:**
- A new `ci/warm.sh up|down|status` starts and stops one warm throwaway per lane. It is a throwaway like any other, built on `lib-live.sh`'s `live_start`, and it holds its own lock, `warm-iris.lock`.
- `OCUTALON_WARM=1 ci/iris.sh class|shard` runs on that stack, with no new start. It first reloads every class changed since the stack's last load and deletes every class removed since then.
- `live`, `group`, `all`, the fresh-environment check and CI stay fresh, exactly as before.
- The story measures memory first (Task 0 gate). It then measures the same classes warm and fresh, and appends the recipe and the numbers to Rule 21.

## Boundaries & Constraints

**Always:**
- **Fresh checks stay fresh.** These never run warm:
  - `ci/iris.sh live` refuses `OCUTALON_WARM=1` with exit 2 before anything starts;
  - `group` and `all` unset it for their units;
  - CI never sets it, and no workflow names it or `ci/warm.sh`;
  - destructive tests (the live scripts) and the fresh-environment check (Rule 19) start fresh throwaways as before.
- **No stale code.** A warm run that exits 0 ran on a stack whose OcuTalon classes are the tree's `.cls` files, each compiled from its current content. A compile error fails the run, as it would on a fresh stack.
- **No other stale input.** A change to anything else the image or the stack is built from refuses the warm run. It never runs on the old version.
- **Locks.**
  - The warm stack holds `warm-iris.lock` in the lane's lock folder (`live_lock_dir`, so `OCUTALON_LOCK_DIR`). Fresh stacks keep `throwaway-iris.lock`.
  - So a lane has at most one warm and one fresh stack at a time, and its fresh runs never wait on its warm one.
  - With no lock folder (CI, a sequential run), no lock is taken.
  - The lock uses lib-live's protocol: an atomic create; the content `<OCUTALON_LOCK_OWNER> project=<P> acquired_at=<UTC>`; the `LOCK` lines; `OCUTALON_LOCK_WAIT` and the sleep bounds; exit 75 when busy.
- **The fresh path is unchanged.** It has the same lines (`STACK <title>: project <P>`, `READY <title> <s>s`, the `CLASS`, `SHARD` and `RUN` lines), the same exits and the same lock.
- **Teardown.** `ci/iris.sh teardown` with a warm stack's tag removes it like any throwaway. It also releases a `warm-iris.lock` whose `project=` carries that tag, and never another tag's lock.
- **Script rules.** ASCII; bash 3.2; both BSD and GNU tools; no new dependency. No `docker compose config` without `--quiet`, and no `docker inspect` without `--format` (AD-22).

**Never:**
- **Contended paths (Epic 2 and others).** Never edit:
  - `docker/tests/lib-live.sh`, or any `docker/tests/**` file except `test-ci-warm.sh` (new) and `test-ci-config.sh`;
  - `ci/mock/**`, `ci/compose.ci.yml`, `ci/changes.sh` or `.github/workflows/**`;
  - `release/**`, `src/**` or `web/**`;
  - anything under `_bmad/` except the Rule 21 append, and anything under `.claude/`.

  A mutation is never applied to a contended file, not even for a moment. The one exception to "never under `src/`" is the untracked `ZzWarm<k>` probe classes that the live test and the warm-against-fresh measurement create and remove. No tracked file changes, and the tree is byte-identical afterwards.
- **No change to CI.** No product code and no CI behaviour changes. The six groups, the skips and the workflows stay as they are.
- **Runtime limits.**
  - Never touch slots A or B, `ocutalon-aihub-test`, any `ocupilot*` container, `iris-community-edition`, or another lane's throwaways. Observing them with `docker stats --no-stream` is allowed.
  - Never read or print `.env`.
  - Never `git commit` or `git push`, and trigger no CI.

## I/O & Edge-Case Matrix

Rows assume the lane's variables (Rule 21) and a warm tag W, unless the row says otherwise. "Warm run" means `OCUTALON_WARM=1 OCUTALON_RUN_TAG=W ci/iris.sh class <C>` (or `shard <name> [--reverse]`).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Up | `ci/warm.sh up`, no warm stack in the lane | One project `ocutalon-warm-W-<epoch>-<pid>` with the stack's lines, `LOCK acquired warm-iris project=<P>`, and `WARM up project <P> tag W ready <s>s`. The state folder is written | exit 0 |
| Up again | Same tag, the stack is running | `WARM up: project <P> is already up`. No new project, and the lock is unchanged | exit 0 |
| Lane's warm lock held | `warm-iris.lock` names another project | `LOCK waiting: warm-iris ...`, then `LOCK busy: warm-iris is held by '<content>'`. Nothing starts | exit 75 |
| No lock folder | `OCUTALON_LOCK_DIR` names no folder | No `LOCK` line. The stack starts | exit 0 |
| Failed up | The image or the start fails, or the process is killed | The trap removes the project, releases `warm-iris.lock` and leaves no state folder | exit 1 (130 on a signal) |
| Fresh beside warm | The warm stack is up, then `ci/iris.sh class <C>` with the fresh tag and no `OCUTALON_WARM` | `LOCK acquired throwaway-iris`, with no `LOCK waiting` line. Runs as before | Its own verdict |
| No warm stack | Warm run, with no state for W | `FAIL WARM no warm stack for tag W: run ci/warm.sh up first`. Nothing starts, and no `LOCK` line | exit 1 |
| Nothing changed | Warm run right after up | `STACK <C>: warm project <P>`, `WARM reloaded 0, deleted 0`, `READY <C> <s>s (warm)`, then the `CLASS` and `RUN` lines. Still exactly one project of tag W | The class verdict |
| Changed or added classes | k `.cls` files changed or new since the last load | `WARM reloaded k, deleted 0`. The classes, with their subclasses, are compiled before any class runs | The class verdict |
| Removed or renamed | j classes gone from the tree, k files new or changed | `WARM reloaded k, deleted j`. Every class of the tree is then compiled, so a class that still names a removed one fails as on a fresh stack | See "Compile error" |
| Mapped package | The changed class is in a package mapped to `OCUTALON_PUBLIC` (`OcuTalon.Data.Public`, `OcuTalon.Web.Public`) | Loaded, compiled and deleted where the namespace's mapping puts it | As above |
| Compile error | A changed class does not compile | `FAIL WARM compile: <class>: <error>` (one line per error). No `CLASS` line. The next warm run compiles every class of the tree again | exit 1 |
| Other input changed | Any non-class file of the manifest changed, appeared or went: the Dockerfile, `.dockerignore`, `docker/ipm/`, `merge.cpf`, `after-start.*`, `healthcheck.sh`, `src/module.xml`, `src/short-names.tsv`, the web bundle, or a stack compose file | `FAIL WARM stale: <path> changed since warm up, and only classes reload: run ci/warm.sh down, then ci/warm.sh up`. Nothing runs | exit 1 |
| Stack gone | The state exists, but the container is not running (Docker restarted, or it was removed) | `FAIL WARM the warm stack <P> is not running: run ci/warm.sh down, then ci/warm.sh up` | exit 1 |
| Other checkout | The state of W was written from another repository root | `FAIL WARM the warm stack of tag W was built from another checkout` | exit 1 |
| Live refuses | `OCUTALON_WARM=1 ci/iris.sh live <name>` | `FAIL live units never run warm: unset OCUTALON_WARM`, with no `PORT` line and no preflight | exit 2 |
| Group and all | `OCUTALON_WARM=1 ci/iris.sh group <g>` (or `all`) | One `WARM ignored: group <g> runs every unit on a fresh stack` line. Every unit's process sees no `OCUTALON_WARM` | As before |
| Bad value | `OCUTALON_WARM=yes` for `class`, `shard`, `live`, `group` or `all` | `FAIL OCUTALON_WARM must be 1 (warm), or 0 or unset (fresh)` | exit 2 |
| Down | `ci/warm.sh down` | `ci/iris.sh teardown` for W (`LOCK released warm-iris project=<P>`, `TEARDOWN tag W: ...`). The state folder is removed, then `WARM down tag W` is printed. Run again: `TEARDOWN tag W: 0 project(s) removed, ...` and `WARM down tag W` | exit 0 |
| No tag | `ci/warm.sh up`, `down` or `status` without `OCUTALON_RUN_TAG`, or with a bad one | `ci/warm.sh needs OCUTALON_RUN_TAG: the warm stack's tag`, or the `FAIL OCUTALON_RUN_TAG ... must match ...` line | exit 2 |
| Orphan | A stage was killed with its warm stack up. Then `ci/iris.sh teardown` runs with W | The project goes, and the lane's `warm-iris.lock` naming a project of W is released. A lock of another tag is kept | exit 0 |
| Status | `ci/warm.sh status` | `WARM up project=<P> tag=W since=<UTC>` when it is running, otherwise `WARM none for tag W` | exit 0 when up, 1 otherwise |
| CI never warm | Every workflow file, and every code line under `ci/` | No workflow names `OCUTALON_WARM` or `ci/warm.sh`. No `ci/` code line assigns or exports `OCUTALON_WARM` | `FAIL` in `test-ci-warm.sh` |

</intent-contract>

## Code Map

- `ci/iris.sh` (Lane B, in the footprint):
  - L2-28 is the header and usage. `usage` (L36-38) prints the comment block up to `set -u`. The `nosuchcommand` pin wants its last line, `Needs bash 3.2 or later ...`. Add the `OCUTALON_WARM` line above it.
  - Functions that warm.sh reuses: L42-68 `setup_tag`; L84-111 `preflight`; L115-117 `class_of`; L129-137 `test_classes`; L165-212 `run_class`, which runs one class through `iris_script OCUTALON` and is unchanged.
  - L215-240 `run_classes`. Its start (L219-229: preflight, live_start, STACK, `dc up -d --build --wait`, live_track_image, READY) is the part that the warm branch replaces and that `warm up` reuses.
  - The commands: L277-302 `cmd_shard`, L304-312 `cmd_class`, L324-337 `cmd_live`, L339-367 `cmd_group`, L369-380 `cmd_all`. `group` and `all` start each unit as `bash "$root/ci/iris.sh" ...`.
  - L385-418 `cmd_teardown`, matching `^ocutalon-[a-z0-9-]+-$tag-[0-9]{10}-[0-9]+`. L421: sourced, the file defines functions and runs nothing.
- `docker/tests/lib-live.sh`. Read-only (Epic 2 contended). Build on these functions:
  - L46 `live_tag_ok`. L53-84 `live_start`: it sets P, tmp and LIVE_FILES, claims the lock, sets `trap live_cleanup EXIT`, and calls `ensure_web_bundle`. A label of `warm` gives `ocutalon-warm-<tag>-<epoch>-<pid>`.
  - L89-103 `live_lock_dir`: a set `OCUTALON_LOCK_DIR` that is no folder means no lock.
  - L106-132 `live_lock_claim` and L135-144 `live_lock_release`. Both hard-code `throwaway-iris`.
  - Helpers: L147 `live_add_file`, L239-243 `dc`, L247-251 `live_track_image`, L261-267 `live_cleanup`, L303-313 `iris_script` (keeps `CHK|` lines and retries an empty session 3 times), and L413-425 `dockerfile_copy_sources` and `copied_files` (the files of the Dockerfile's COPY lines, the web bundle included).
- `docker/tests/test-ci-config.sh` (in the footprint):
  - Header bullets L36-44 (`recipe`) and L50-53 (`teardown`).
  - L1137 `iris_env`, which unsets `OCUTALON_RUN_TAG`, `OCUTALON_TEST_WEB_PORT` and `RUNNER_NAME`. Add `OCUTALON_WARM`, so that a caller's exported value cannot turn the `live` pins into the warm refusal.
  - L1163, the `nosuchcommand` pin. L1206, L1368 and L1526: subshells that unset the same variables.
  - L1545-1602, the teardown fixture: a stubbed `docker`, tag `abc-7`, `cmd_teardown` sourced. It sets no `OCUTALON_LOCK_DIR`, so give it a temporary folder.
  - L598-650 `units_violations`: every `docker/tests/test-*.sh` must be in exactly one of CHECK_SCRIPTS, WEB_SCRIPTS or a group.
- `docker/tests/test-lib-live.sh` L467-530. Read-only. It shows how to test a lock hermetically: a lock folder of its own, the claim, the wait, exit 75, a foreign lock kept, and the exit trap.
- `ci/units.sh` L6 `CHECK_SCRIPTS`. The hosted `checks` job runs each of its scripts with no argument (`ci/checks.sh`).
- `ci/iris.sh` sources `ci/units.sh` and `lib-live.sh`. `.github/workflows/ci.yml` L99-125 sets `OCUTALON_RUN_TAG`, `OCUTALON_LIVE_DEADLINE` and no `OCUTALON_WARM`, and runs `ci/iris.sh build`, `group` and `teardown` (read-only).
- The image and the stack (read-only):
  - `docker/Dockerfile` copies `src/` to `/opt/ocutalon/src/`, and `after-start.cos` installs the package with IPM `load /opt/ocutalon/src` into OCUTALON at every start (AD-23).
  - `src/module.xml` has the resources `OcuTalon.Bridge.PKG` (`bridge/cls`) and `OcuTalon.PKG` (`ocutalon/cls`), and the web bundle as a FileCopy.
  - `docker/tests/compose.throwaway.yml` mounts `./eval` read-only, relative to the repository root. The warm override mounts `./src` the same way.
  - `src/` holds only `.cls` files, plus `module.xml`, `short-names.tsv` and the ignored bundle `src/ocutalon/csp/`.
- IRIS APIs (irislib `%SYSTEM/OBJ.cls`):
  - `Load(file, qspec, ...)` at L101 (marked Deprecated, still in use: `after-start.cos` L4 loads the IPM release with it).
  - `Compile(.classes, qspec, .errorlog)` at L204: a name, a comma list or an array; flag `b` includes subclasses.
  - `Delete(.classes, qspec, .errorlog)` at L448.
  - `GetDependencies` at L1733.
- `_bmad/custom/skill-rules.md`. Rule 21's CI recipe list ends at L284 (the "Eighth real run" bullet). L286 is `Why: ...`. The new bullets go between them, and nothing else changes.
- `_bmad/custom/parallel.yaml` L33-35: `throwaway-iris` has `stale_minutes: 20`, and no `warm-iris` entry exists. Read-only; see Design Notes, "For the lead".

## Tasks & Acceptance

**Execution:**

**Task 0, memory first. A gate: no code before it passes.** On the developer machine, with lane C's variables and the fresh tag `e32s4i`:

1. **Read the machine.** `docker info --format '{{.MemTotal}} {{.NCPU}}'`, and `docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}'` (read-only). Record:
   - the Docker VM's memory and CPUs;
   - each slot's memory;
   - the sum of every running container that is not a throwaway (no `ocutalon-<label>-<tag>-` name).
2. **Measure a throwaway.** One scratch script in the session's scratchpad (never in the repository) sources `ci/iris.sh` and calls `setup_tag`, `preflight` and `live_start task0`. It then brings the stack up as `run_classes` does, and in the same call:
   - records `docker stats` of the project's containers right after `READY`: **a fresh throwaway**;
   - runs `run_class` over every class of `lane-a` and `lane-b`, then records `docker stats` again: **a warm throwaway after a shard run**;
   - inside the stack, times `$SYSTEM.OBJ.Load("/opt/ocutalon/src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls","-d")`, which must return OK, and a compile of every class of the tree with `"c-d"`;
   - exits, and its trap tears the stack down. Then run `ci/iris.sh teardown` with `e32s4i`.

   The throwaway's memory is the sum over its project's containers (`iris` and `mock`).
3. **The gate.** Projected = the non-throwaway sum + 3 x (fresh + warm after shard). It must be at most 0.85 x the VM's memory.
   - If it holds, record every number in Design Notes, "Task 0 (implement)", and continue.
   - If it does not, set `status: blocked`. The blocking condition is `intent gap: three lanes with one warm and one fresh stack each do not fit the Docker VM`, with every number. Then stop.
   - If `Load` cannot import a UDL `.cls` file, record that, and use the import call that works (for example `$SYSTEM.OBJ.LoadDir` on a folder holding the file). That is a decided-in-stage note, not a halt.

**Then:**

- `ci/iris.sh`. Rationale: the warm runs and the fresh-only guards in the one recipe (AD-22).
  - **`warm_mode`.** It prints `warm` for `OCUTALON_WARM=1`, and `fresh` when the variable is unset, empty or `0`. Any other value gets the "bad value" line and exit 2.
  - **`run_classes`.** Move its start (L219-229) into two functions, byte-identical in output:
    - `stack_start <label>`: preflight and `live_start`;
    - `stack_ready <title>`: the `STACK` line, `dc up -d --build --wait`, `live_track_image` and the `READY` line.

    Then:
    - in warm mode, source `$root/ci/warm.sh` and call `warm_attach "$title"` (exit 1 when it fails) instead of the two;
    - the class loop and the summary lines are shared.

    `ci/warm.sh` is sourced nowhere else in `ci/iris.sh`, so a run without `OCUTALON_WARM=1` (CI) never loads it.
  - **`cmd_live`.** After the name check and before `setup_tag`: when `warm_mode` says `warm`, print the refusal and exit 2.
  - **`cmd_group` and `cmd_all`.** When `warm_mode` says `warm`, print the `WARM ignored` line once and `unset OCUTALON_WARM` before running any unit.
  - **`cmd_teardown`.** After the removals, read `$(live_lock_dir)/warm-iris.lock`. When its `project=` value matches the tag's pattern, delete it and print `LOCK released warm-iris project=<P>`; otherwise keep it. Keep the `TEARDOWN` line last.
  - **The header and usage.** Add one usage line above `Needs bash ...`: `OCUTALON_WARM=1 ci/iris.sh class|shard ...` runs on the warm throwaway of the tag (`ci/warm.sh up`) after reloading the changed classes, and `live`, `group` and `all` never run warm.
- `ci/warm.sh` (new, executable like `ci/iris.sh`). The warm lifecycle, and the warm functions that `ci/iris.sh` sources. Run, it requires `OCUTALON_RUN_TAG` (exit 2 without it), sources `ci/iris.sh`, and dispatches `up`, `down` and `status`; anything else prints usage and exits 2. Sourced, it defines functions and runs nothing. Its header states the contract (Rule 14). It holds:
  - **The state folder.** `${TMPDIR:-/tmp}/ocutalon-warm-<tag>/` holds:
    - the project name P, the repository root, the up time, and the manifest;
    - the stack's compose files: a decoy key file and its yml, written like `live_start`'s, and `warm.yml`, which mounts `./src` read-only at `/opt/ocutalon/warm-src`;
    - a `failed` marker after a reload that did not end OK.

    Every later `dc` call uses the up's file list: the judges' file, the decoy yml, the throwaway override, the CI override and `warm.yml`.
  - **The manifest.** One `<hash> <path>` line, sorted by path, for each file of `copied_files`, plus `docker/Dockerfile`, `.dockerignore`, `docker-compose.yml`, `docker/tests/compose.throwaway.yml` and `ci/compose.ci.yml`. The hashes come from `git hash-object --stdin-paths`. A class is a path `src/<tree>/cls/**.cls`, named with `class_of`.
  - **The warm lock.** Derive the lock pair from lib-live's own functions: `declare -f live_lock_claim live_lock_release`, `sed 's/throwaway-iris/warm-iris/g'`, then `eval`. Install the pair in the `warm up` process only, after `lib-live.sh` is sourced, so that `live_start`'s claim point and `live_cleanup`'s release serve `warm-iris.lock`. Fail closed (exit 1, `FAIL WARM the warm lock could not be derived from lib-live.sh`) when the derived text still names `throwaway-iris` or no longer names `warm-iris.lock`.
  - **`warm_up`.**
    1. With the state of the tag present and the container running, print the "already up" line and exit 0. With the state present but the container stopped, run `warm_down` first.
    2. `setup_tag`, then `stack_start warm` with the derived lock installed (preflight, then `live_start`, which claims `warm-iris.lock` and ensures the web bundle).
    3. Write the state folder's compose files, point LIVE_FILES at them, and extend the exit trap so that a failure also removes the folder.
    4. Compute the manifest now: after the web bundle is ensured, and before the build.
    5. `stack_ready warm`.
    6. Write the state, clear the trap, remove `tmp`, and print `WARM up ...`.
  - **`warm_down`.** Run `cmd_teardown` for the tag, which brings down every project of the tag and releases its warm lock. Then remove the state folder and print `WARM down tag <tag>`. It needs no state.
  - **`warm_status`**, as the matrix says.
  - **`warm_attach <title>`**, which the warm branch of `run_classes` calls.
    - It checks, in this order: the state exists, the root matches, and the container is running. Each failure has its matrix line and exit 1.
    - It sets P and LIVE_FILES from the state, and a private `tmp` whose trap removes only that `tmp`.
    - It prints `STACK <title>: warm project <P>`, then runs `warm_reload`, then prints `READY <title> <s>s (warm)`.
  - **`warm_reload`.**
    1. Diff the tree's manifest against the stored one. A changed, added or removed non-class path refuses with the "stale" line. Otherwise D is the classes gone from the tree, and L is the class files that are changed or new.
    2. Run one IRIS session in OCUTALON with `iris_script`. The lists go in as array lines, one per item, never as one long line. The session:
       - deletes each class of D that exists (`$SYSTEM.OBJ.Delete(...,"-d")`);
       - imports each file of L from `/opt/ocutalon/warm-src/` without compiling (`$SYSTEM.OBJ.Load(...,"-d")`, or Task 0's call);
       - compiles: every class of the tree (`"c-d"`) when D is not empty or the `failed` marker is set, otherwise L's classes with their subclasses (`"cb-d"`);
       - prints a `CHK|` line for each deleted, imported and compile result, and one for each error.
    3. Update the stored manifest entry by entry: drop a path once its class is deleted, and set a path once its file is imported. So an import or delete that failed is tried again, and a file imported but never compiled is deleted once it leaves the tree.
    4. Set or clear the `failed` marker, then print exactly one `WARM reloaded <n>, deleted <m>` line (n files imported, m classes deleted). When the whole tree was compiled, also print `WARM compiled every class (<k>): <after a delete|after a failed reload>`.
    5. On any error, print the `FAIL WARM compile: ...` lines (or `FAIL WARM the IRIS session of <P> printed nothing`) and return 1.
- `ci/units.sh`. Append `ci-warm` to `CHECK_SCRIPTS`. Rationale: the hermetic mode of the new test runs in the hosted `checks` job and in `ci/checks.sh`, and `units_violations` requires every test script in exactly one list.
- `docker/tests/test-ci-warm.sh` (new, executable like the other test scripts). Header: what it pins and what it needs (Rule 14).
  - **Default mode is hermetic.** It starts nothing and needs bash, git and the Docker CLI only. It uses its own `TMPDIR` and lock folder, and stubs `dc`, `docker`, `iris_script`, `preflight`, `live_start` and `bash` where needed. It prints one PASS or FAIL line per check, and `test-ci-warm: all checks passed`. Each scanner first flags a synthetic bad sample. The checks:
    - the CI rule (the matrix row);
    - the `live` refusal: exit 2, its line, and no `PORT` line, with `IRIS_IMAGE=ocutalon-no-such-image:0`, so that a missing refusal would show as exit 1;
    - a bad value gives exit 2;
    - `group` with `OCUTALON_WARM=1`: a stub `bash` shows that each unit sees no `OCUTALON_WARM`, and the `WARM ignored` line is printed;
    - "no warm stack": exit 1, and nothing started;
    - "nothing changed": `stack_start`, `stack_ready` and `live_start` are never called, `STACK ...: warm project <P>` and `WARM reloaded 0, deleted 0` are printed, and the class verdict comes from the stubbed session;
    - the fresh branch still calls preflight, `live_start` and `dc up`, and prints the same `STACK` and `READY` lines;
    - `ci/warm.sh` without a tag, or with a bad one, gives exit 2;
    - the derived lock: it claims `warm-iris.lock` with the content grammar; a held `warm-iris.lock` gives exit 75 and the lock stays untouched; a held `throwaway-iris.lock` does not block it, and `live_lock_claim` from `lib-live.sh` still takes `throwaway-iris.lock` while `warm-iris.lock` is held; the release removes only its own lock;
    - a failed up (stubbed `dc up` fails) leaves no lock file in the lane folder and no state folder;
    - the derivation guard;
    - `warm_reload` over synthetic manifests: changed, added, removed and renamed classes give the right import, delete and compile lists and the right `WARM reloaded n, deleted m` line; a full compile after a delete or after the `failed` marker; a compile error gives exit 1 with the marker set and the next run's full compile; a non-class change gives the "stale" refusal; a class imported but not compiled and then removed from the tree is deleted;
    - `warm_down`: teardown of the tag, then the state is gone and the lock is released;
    - `warm_status`.
  - **`--live` mode (the developer machine only, never CI).** It needs lane variables and `OCUTALON_RUN_TAG=T`, and no warm stack up in the lane. It uses T for its warm stack and `Tf` for its fresh run, and its EXIT, INT and TERM trap runs `ci/warm.sh down` for T, teardown for `Tf`, and removes its probe files. Its steps:
    1. `ci/warm.sh up`, then `up` again: the "already up" line.
    2. With the warm stack up, a fresh `ci/iris.sh class OcuTalon.Test.Agent.Constants` with `Tf`: `LOCK acquired throwaway-iris`, no `LOCK waiting`, and it passes.
    3. A warm `class` of the same class: `WARM reloaded 0, deleted 0`, it passes, and there is still exactly one project of tag T.
    4. A warm `shard lane-a`, which passes.
    5. **Probes.** Untracked classes `OcuTalon.Data.Public.ZzWarm<k>Target` (a mapped package) and `OcuTalon.Test.Data.ZzWarm<k>Probe`, with k unique per run:
       - new: `reloaded 2`, and the probe passes;
       - the target changed to a new answer, with the probe expecting it: `reloaded 2`, and it passes;
       - the target renamed to `ZzWarm<k>Target2`, with the probe calling the new name and asserting that the old class is neither defined nor compiled: `reloaded 2, deleted 1`, and it passes;
       - a new `ZzWarm<k>Child` (in `OcuTalon.Test.Data`) that extends `ZzWarm<k>Target2`: `reloaded 1`, and the probe passes;
       - `ZzWarm<k>Target2` removed from the tree, with the child kept: `deleted 1`, then the compile of every class fails on the child, so exit 1 with `FAIL WARM compile` and no `CLASS` line, as a fresh stack's package load would fail;
       - every probe removed, then a warm `class OcuTalon.Test.Agent.Constants`: the rest are deleted, every class compiles (the `failed` marker), and it passes.
    6. `ci/warm.sh down`: the lock is gone, the project is gone, and the state is gone.

    The tree must be byte-identical before and after (`git status --short`). It prints `test-ci-warm: all live checks passed`, and must finish within about 8 minutes, in one call. If it cannot, split it into `--live up` and `--live probes` and record why.
- `docker/tests/test-ci-config.sh`.
  - `iris_env` and the three `unset` subshells (L1206, L1368, L1526) also clear `OCUTALON_WARM`.
  - The teardown fixture uses its own `OCUTALON_LOCK_DIR`. In it, a `warm-iris.lock` naming `ocutalon-warm-abc-7-<epoch>-<pid>` is released. One naming `ocutalon-warm-abd-7-<epoch>-<pid>` (another tag) is kept, and so is one naming `ocutalon-warm-abc-7-1-<epoch>-<pid>` (the tag `abc-7-1`, which extends `abc-7`).
  - Rewrite the header's `teardown` bullet and its `PASS teardown` wording to say so.
- **Measure warm against fresh (after the code, in one stage, lane C).** Run each of these in its own call and record its wall-clock:
  - fresh `shard lane-a`, `shard lane-b` and `class OcuTalon.Test.Install.Users`, with tag `e32s4i`, each followed by teardown;
  - `ci/warm.sh up` with `e32s4iw`;
  - warm `shard lane-a`, `shard lane-b` and the same class;
  - the same class again after one new, untracked probe class (`ZzWarm<k>`, in `OcuTalon/Test/Install/`) is added. Remove the probe after one more warm run, which prints `deleted 1`;
  - `docker stats --no-stream` of the warm project after the shards;
  - `ci/warm.sh down`.

  Write the times into Design Notes, "Warm against fresh (implement)". Rationale: pre-ruled item 7, and the recipe AC.
- `_bmad/custom/skill-rules.md`. Append only: insert two sub-bullets after L284, under Rule 21's CI recipe, with the measured values written in. Change nothing else. The text is in Design Notes, "The Rule 21 append".

**Acceptance Criteria:**
- **AC 1, memory first.** Given the developer machine before any code, when Task 0 runs, then Design Notes records:
  - the Docker VM's memory and CPUs;
  - the memory of a slot, of a fresh throwaway, and of a throwaway after both shards;
  - the sum of the other long-running containers;
  - the projected use of three lanes with one warm and one fresh stack each.

  The projected use is at most 0.85 x the VM's memory, or the story is blocked with those numbers as an intent gap. The same figures are in the Rule 21 append.
- **AC 2, one warm stack per lane with its own lock (as amended).** Given lane C's lock folder, when `ci/warm.sh up` runs, then:
  - exactly one project of the warm tag runs, and the lane folder holds `warm-iris.lock` naming it;
  - a warm `class` or `shard` runs on it with no new project and no `LOCK` line;
  - a fresh run in the same lane takes `throwaway-iris.lock` without a `LOCK waiting` line.

  Shown by `test-ci-warm.sh` (hermetic) and by `--live` steps 1 to 4.
- **AC 3, no stale classes.** Given a warm stack, and a tree whose classes changed, were added, were removed or were renamed since the last load, when a warm `class` or `shard` runs, then:
  - it prints exactly one `WARM reloaded <n>, deleted <m>` line with the right counts;
  - a removed or renamed class is gone from the stack (the probe's "old class neither defined nor compiled" assertion);
  - a class that extends a removed class fails to compile with exit 1, as on a fresh stack;
  - a change to any non-class input refuses the run.

  Shown by `test-ci-warm.sh` and `--live` step 5.
- **AC 4, fresh checks stay fresh.** Given `OCUTALON_WARM=1`, when `ci/iris.sh live <name>` runs, then it exits 2 before anything starts. When `group` or `all` runs, then every unit runs without `OCUTALON_WARM`. And every workflow file and every `ci/` code line is free of it. `bash docker/tests/test-ci-warm.sh` prints PASS for each of these.
- **AC 5, lifecycle.** Given a warm stack, when `ci/warm.sh down` runs, or a failed or killed `warm up` triggers its trap, or `ci/iris.sh teardown` runs with the warm tag after its stage was killed, then the project, its volumes and its image are gone and `warm-iris.lock` is released. A lock naming another tag is kept, and the state folder is gone. `bash docker/tests/test-ci-config.sh` prints `PASS teardown` for the lock cases.
- **AC 6, the recipe is recorded with its times.** Given the finished tree, when Rule 21 is read, then it holds the warm-mode recipe: when stages use it, the warm tag, never exporting the variable, what never runs warm, the orphan cleanup, and the limit on what the start does. It also holds Task 0's memory and the warm and fresh times of the same classes measured in one stage. Rule 21's other text is unchanged (`git diff` adds lines only).
- **AC 7, integration (Rule 1).** Given a stage on any lane that follows the appended recipe, when it runs `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag> ci/iris.sh class <Class>` against its real warm stack, then the call prints `WARM reloaded`, `READY ... (warm)` and the class's real `CLASS` verdict. It finishes without a new IRIS start, in less time than the fresh call of the same class measured in this story. The evidence is `test-ci-warm.sh --live` steps 3 to 5 and the warm-against-fresh measurement.
- **AC 8, nothing else changed.** Given the finished tree, when `bash ci/checks.sh` runs, then it ends `checks: all scripts passed`. Fresh `shard lane-a` and `shard lane-b` pass with their usual lines. And `git diff --stat` of every contended path in Never is empty.

## Spec Change Log

### 2026-10-23: AC 2 amended before planning (Rule 5 tier 1, intent kept, pre-ruled with the Contest Planner under the owner's delegation)
- **Original wording (epics.md, Story 32.4, AC 2):** "...one throwaway starts for the lane and holds the lane's throwaway lock until `warm down`..."
- **Amended:** "...holds the lane's own warm lock (`warm-iris.lock` in the lane's lock folder, beside the fresh stacks' `throwaway-iris.lock`) until `warm down` ..., so a lane holds at most one warm and one fresh stack at a time, and its `live` units and fresh-environment check never wait on its own warm stack".
- **Why:** holding `throwaway-iris.lock` for the warm stack's life would make the same lane's `live` units and fresh-environment check wait on it, and exit 75 (`LOCK busy`) after `OCUTALON_LOCK_WAIT`. The intent (one warm stack per lane, and the fresh checks as strict as before) is kept.
- **KEEP:** a lane holds two lock files, one for warm and one for fresh. CI and sequential runs take no lock.

## Review Triage Log

### 2026-10-23 - Review pass
- verdicts: 40 findings - high 0, medium 2, low 34, false 4, maybe-false 0
- findings:
  - Blind hunter:
    - `[low]` `[patch]` Concurrent warm runs on one stack are unguarded - real only when two agents run warm calls at once, which Rule 18 forbids; a run lock needs stale-lock handling and an output line the matrix does not specify, so the fix is the Rule 21 clause "never run two warm calls at once on one stack" (decision 28).
    - `[low]` `[patch]` Rule 21 contradicts itself ("at most one throwaway per runner") - the appended bullet now names the warm stack as the one exception.
    - `[low]` `[patch]` Compile-error naming is unpinned, and a failed compile can end with no FAIL line - the live regex is now `FAIL WARM compile: OcuTalon\.Test\.Data\.ZzWarm<k>Child: ` (green against real IRIS in the live run); a fallback line `FAIL WARM compile: the compile of <P> failed and gave no error text` and hermetic cases q3 and q4 were added; attributing an error of an unlisted subclass to the changed superclass is cosmetic (the error text keeps the real class) and stays.
    - `[low]` `[patch]` Subclass recompilation (`cb-d`) never shown, and Design Note 7's limit missing from Rule 21 - measured: a probe whose subclass method inlines its parent's parameter passed after only the parent changed, with `cb-d` and with `c-d` (the class compiler also recompiles the subclass; flag `b` is "Include sub classes", irislib `%SYSTEM/OBJ.cls` L1406), so subclasses are current either way; the Rule 21 append now states the limit.
    - `[false]` `[reject]` Re-running on one warm stack is not evidenced - measured on one warm stack: `shard lane-a` three times (once with `--reverse`), `shard lane-b` twice and the `Users` class four times, all passed.
    - `[low]` `[patch]` Recorded figures differ from the measurement - Rule 21 now says "added" for the class that was added and carries the warm stack's 3.14 GiB (31.6 GiB, 50.5 %); a stack kept for hours is not claimed.
    - `[low]` `[reject]` A warm run without `OCUTALON_RUN_TAG` names an invented tag - it fails with exit 1 and prints that tag; refusing earlier needs a branch before `setup_tag` in two commands.
    - `[low]` `[reject]` `warm up` and `status` do not detect a stale stack - the matrix fixes "already up" and "running"; the stale refusal follows on the next run and names the path.
    - `[low]` `[reject]` Reusing the warm tag for a fresh run is only a convention - decision 2 fixes the convention; tearing down the warm tag is the operator's explicit act.
  - Edge case hunter:
    - `[low]` `[patch]` Concurrent warm runs - same root cause as the first blind-hunter row (Rule 21 clause).
    - `[low]` `[patch]` A missing stored manifest reads as "nothing changed" - verified: BSD awk cannot open the file, prints nothing and the pipeline exits 0; `warm_reload` now refuses (test s9).
    - `[low]` `[reject]` A partial manifest when `git hash-object` fails - needs an unreadable file, and a partial manifest fails closed (a stale refusal) on the next run.
    - `[low]` `[reject]` `OCUTALON_EVAL` differs from the one at `warm up` - the Production install step reads it at the start, which Rule 21 already says comes from `warm up`.
    - `[low]` `[reject]` `warm down` while docker fails - needs an unreachable daemon, in which case `up` fails too; the TEARDOWN line prints the leftovers.
    - `[low]` `[reject]` A later call with another `TMPDIR` or lock folder - decision 3; `down` works by tag, and a new `up` prints the lock's holder.
    - `[low]` `[reject]` Error attribution for a class whose name extends a listed one - cosmetic.
    - `[low]` `[patch]` `warm_script` comment lists a second parameter - removed.
    - `[low]` `[reject]` Editor swap files refuse a run - fails closed, names the path, and a restart is a minute.
    - `[medium]` `[patch]` `ci/mock` is not in the manifest - verified: `ci/compose.ci.yml` mounts `./ci/mock` into the mock, which loads it at its start; the manifest now covers `ci/mock` except `test/` (decision 26; tests s7, s8).
    - `[low]` `[patch]` `ci/iris.sh teardown` leaves the state folder - AC 5 says it is gone; `cmd_teardown` removes it (decision 25) and the fixture of `test-ci-config.sh` asserts it.
    - `[false]` `[reject]` A failed session prints no `WARM reloaded` line - the Tasks prescribe the `FAIL WARM the IRIS session of <P> printed nothing` line for that case; AC 3's single line is for a run that reloads.
  - Verification gap:
    - `[low]` `[patch]` The `compile_seen` branch is untested - case q3.
    - `[low]` `[patch]` A failed delete, and its retry, are untested - cases q1 and q2.
    - `[low]` `[patch]` `bash ci/warm.sh status|down` is never run as a command - three command-line checks added.
    - `[low]` `[patch]` "Exactly one `WARM reloaded` line" is asserted by presence - counts added for a class run, a warm shard (hermetic) and live step 4.
    - `[low]` `[reject]` The IRIS session text runs only under `--live` - decision 12 (CI cannot start IRIS); the class-naming regex is tightened under the third blind-hunter row.
    - `[low]` `[reject]` Sub-bullets of ACs without a `mutation:` line - Rule 19 asks one per AC; AC 1, 6 and 8 are record criteria and AC 7's is AC 3's, as the spec says; a line was added for each test changed in this pass.
    - `[low]` `[patch]` Order dependence and two comparisons that can pass on nothing - `[ -n "$holder" ]` guards and an existence check added; the r and s chain stays, because it is one scenario that builds its own tree per script run and restructuring it exceeds a direct correction (the new q cases each use a tree and state of their own).
    - `[low]` `[patch]` AC 5's third case (the state folder after a teardown) - same root cause as the `ci/iris.sh teardown` row above.
    - `[low]` `[patch]` A compile that fails with no error rows exits 1 with no FAIL line - same root cause as the third blind-hunter row.
    - `[low]` `[patch]` The header says a bad value gives exit 2 "for every command" - reworded to class, shard, live, group and all.
  - Intent alignment:
    - `[low]` `[reject]` The IRIS-side logic is exercised only by `--live` - same as the verification-gap row on the session text.
    - `[low]` `[reject]` The "last load" is host-side state keyed by tag and `TMPDIR` - same as the `TMPDIR` row.
    - `[medium]` `[patch]` Inputs not hashed - `ci/mock` is real (the `ci/mock` row); `OCUTALON_EVAL` is a start-time effect, and the web sources are not an input of a class run (the built bundle under `src/` is hashed).
    - `[low]` `[patch]` Dependents wider than subclasses - the Rule 21 limit (the fourth blind-hunter row).
    - `[low]` `[reject]` The fresh-environment check has no code gate - the spec ties it to the recipe (its evidence shows no `WARM` line); `live`, `group` and `all` are gated in code.
    - `[false]` `[reject]` Fresh path unchanged is pinned with stubs - descriptive, no defect: the real fresh `shard` runs of this pass and live step 2 print the same lines.
    - `[false]` `[reject]` `ci/units.sh` gains `ci-warm` - the spec's own Task (`units_violations` needs every test script in a list); no workflow, group or skip changed.
    - `[low]` `[patch]` "after one class changed" measured an added class - the same wording fix as the figures row.
    - `[low]` `[reject]` No per-class comparison of warm and fresh verdicts - no AC asks for one; both shards pass warm and fresh, and the live steps assert real verdicts.

## Design Notes

**Governing ADs.**
- **AD-22.**
  - `ci/iris.sh` stays the one recipe that runs the IRIS units, and every stack is a throwaway compose project.
  - The image protections hold: no push, no cache, `docker compose config` only with `--quiet`, and `docker inspect` only with `--format`.
  - AD-22's sharding rule ("each shard in its own compose project") binds the runs on the IRIS runner, which this story leaves as they are. The fresh-environment check also keeps each shard on its own fresh project. The warm mode is a developer-machine loop outside that rule's scope, so no AC contradicts it, and the spine needs no edit (Rule 20): the recipe is recorded in Rule 21.
- **AD-29.** Lane B owns `ci/` and `docker/`. Runner C builds this story in Lane B's files and owns no packages.
- **AD-23** (read-only). The package installs at every start (IPM `load /opt/ocutalon/src`). That is why a warm stack's start-time effects come from `warm up`, which is the limit stated in the recipe.

**Task 0 at planning (read-only, 2026-10-23).** `docker info`: 67,302,940,672 bytes (62.68 GiB), 16 CPUs, aarch64, Docker 29.7.2. `docker stats --no-stream`:

| Container | Memory |
| --- | --- |
| `ocutalon-slot-a` | 1.435 GiB |
| `ocutalon-slot-b` | 1.321 GiB |
| `ocutalon-slot-c` | 1.298 GiB |
| `iris-community-edition` | 1.379 GiB |
| `ocupilot` | 1.78 GiB |
| `ocupilot-b-ci` | 3.277 GiB |
| `ocupilot-ci` | 2.704 GiB |
| `ocupilot-slot-b` | 1.634 GiB |

- The non-throwaway sum is 14.83 GiB.
- One lane A throwaway was starting: 1.33 GiB for `iris` at 194 % CPU, plus 19 MiB for `mock`.
- With Rule 21's 2.4 GiB per stack (inference), three lanes with two stacks each project 14.83 + 6 x 2.4 = 29.2 GiB, which is 47 % of the VM. The 0.85 gate (53.3 GiB) fails only above about 6.4 GiB per stack (inference). The implement stage's Task 0 measures the real figures.

**Task 0 (implement), 2026-10-23, before any code, lane C, tag `e32s4i`.** The gate holds.
- `docker info`: 67,302,940,672 bytes (62.68 GiB), 16 CPUs. The slots: A 1.381 GiB, B 1.47 GiB, C 1.303 GiB.
- The running containers that are not throwaways: `ocupilot-ci` 2.245, `ocupilot-b-ci` 2.456, `ocutalon-slot-c` 1.303, `ocutalon-slot-b` 1.47, `ocutalon-slot-a` 1.381, `ocupilot` 1.367, `ocupilot-slot-b` 1.633 and `iris-community-edition` 1.38 GiB: **13.235 GiB** in all. (Another epic's throwaway, 2.573 GiB plus 19 MiB, was running and is not in the sum.)
- A fresh throwaway right after `READY` (57 s): `iris` 2.971 GiB plus `mock` 19.58 MiB, **2.990 GiB**.
- The same throwaway after `run_class` over all 33 classes of both shards (16 s): `iris` 3.037 GiB plus `mock` 22.2 MiB, **3.059 GiB**.
- Projected: 13.235 + 3 x (2.990 + 3.059) = **31.38 GiB**, which is 50.1 % of the VM. The gate (0.85 x 62.68) is 53.28 GiB, so it holds with 21.9 GiB to spare.
- After the code, the warm stack of the measurement held 3.119 GiB plus 21.5 MiB (3.140 GiB) after both shards; with that figure the projection is 31.63 GiB (50.5 %).
- `$SYSTEM.OBJ.Load("/opt/ocutalon/src/ocutalon/cls/OcuTalon/Test/Agent/Constants.cls","-d")` returned OK in 0.032 s, so a UDL `.cls` file loads with `Load` as it is. A `"c-d"` compile of an array of all 208 classes (`c("<class>")=""`) returned OK in 0.669 s; a compile with the log on of five classes showed each class at about 6 ms, so the figure is real and not an empty compile.

**Warm against fresh (implement), 2026-10-23, lane C, one stage, each run in its own call.** Wall-clock of the call; the fresh tag is `e32s4i`, the warm tag `e32s4iw`, and every fresh run was followed by teardown.

| Run | Fresh | Warm |
| --- | --- | --- |
| `shard lane-a` (9 classes) | 56 s (`READY` 52 s) | 2 s |
| `shard lane-b` (24 classes) | 67 s (`READY` 51 s) | 12 s |
| `class OcuTalon.Test.Install.Users` | 54 s (`READY` 51 s) | 0.36 s (three repeats: 0.35 to 0.36 s) |
| the same class after one new untracked class (`WARM reloaded 1, deleted 0`) | | 0.47 s |
| the same class after that class was removed (`WARM reloaded 0, deleted 1`, then `WARM compiled every class (208): after a delete`) | | 1.47 s |
| `ci/warm.sh up` | | 56 s (`READY` 57 s) |
| `ci/warm.sh down` | | 2.3 s |

- `test-ci-warm.sh --live` (up, a fresh class beside it, a warm class and shard, the six probe steps, down) took 1 min 57 s, inside the 8 minutes of the contract, so it was not split.
- `test-ci-warm.sh` (hermetic) takes 6 s; `test-ci-config.sh` 8 s.
- A warm `class` call costs 0.4 s where the fresh call costs 54 s: the saving per call is the start, 51 s on this machine today. (The Problem's 1.7-minute average was measured on Stories 1.7 and 2.7.)

**Decided in-stage.** Each is reversible inside this story.
1. **`ci/warm.sh up|down|status`, sourced by `ci/iris.sh` only in warm mode.**
   - CI never sets `OCUTALON_WARM`, so the CI path never loads the warm code.
   - `ci/iris.sh` keeps its subcommands. Its usage gains one line, and the `nosuchcommand` pin is unchanged.
   - The static CI check reduces to "no workflow names `OCUTALON_WARM` or `ci/warm.sh`".
2. **Each stage has two tags: a fresh one, and a warm one that ends in `w`** (for example `e32s4i` and `e32s4iw`).
   - The teardown after each fresh call must not match the warm stack.
   - A tag must not end another run's tag. `e32s4iw` does not end in `e32s4i`, and teardown's `-<tag>-<10 digits>` pattern keeps the two apart.
3. **The state folder is `${TMPDIR:-/tmp}/ocutalon-warm-<tag>/`.**
   - It is outside the repository and works with or without a lock folder.
   - macOS clears per-user temporary files only after days unused or at a restart (inference), never during a stage.
   - If the state is lost, warm runs refuse with "no warm stack". `ci/warm.sh down` needs no state, because it tears down by tag.
   - The lock folder is not used for state: the orchestrator's sweep reads it.
4. **"Changed since the last load" is decided by a manifest of content hashes (`git hash-object --stdin-paths`).**
   - It covers every file the image is built from (lib-live's `copied_files`) and every file the stack is defined by.
   - It is computed after the web bundle is ensured and before the build, so a file edited during the build is reloaded once more, and never missed.
   - It is updated entry by entry as imports and deletes succeed.
5. **Only classes reload. Any other input refuses**, because no reload can apply a new Dockerfile, merge file, after-start script, IPM release, manifest, bundle or compose file. `down` plus `up` takes about a minute, and the refusal names the path.
6. **The stack reads the tree through a read-only mount of `./src`** at `/opt/ocutalon/warm-src`. This is the throwaway override's own way of mounting `./eval`. Nothing is copied into the container, and the path is relative, so no local path is written anywhere.
7. **What is compiled.**
   - Normally the imported classes with their subclasses (`b`).
   - Every class of the tree after any delete, or after a failed reload. A class that still names a removed class then fails to compile, as a fresh stack's package load would.
   - Limit (inference): a change that reaches a class neither changed nor a subclass (for example a method generator that reads another class) recompiles only on a fresh stack. The fresh check runs one before every commit.
8. **What the start did is not redone.** The installer steps' effects and the running production's items come from `warm up`. A story that changes them proves the change on a fresh stack (the recipe says so). Unit tests that call a step's methods directly run the reloaded code.
9. **The warm lock is derived, not copied.**
   - `live_lock_claim` and `live_lock_release` hard-code `throwaway-iris`, and `lib-live.sh` is Epic 2's contended path. So `ci/warm.sh` derives the pair from the sourced functions (`declare -f`, `sed`, `eval`), and installs it in the `warm up` process before `live_start`.
   - `live_start`'s claim point (before anything starts) and `live_cleanup`'s release then serve `warm-iris.lock`, and the protocol stays in one place.
   - A derivation that no longer yields the warm name fails closed, and `test-ci-warm.sh` pins it.
   - Fallback: if the derivation proves unworkable, a copy of the two functions with the name changed, with its reason recorded here (Rule 2).
10. **`warm down` is the tag's teardown, plus removing the state folder.** `cmd_teardown` gains the release of a `warm-iris.lock` whose project carries its tag, so the same command clears an orphan of a killed stage.
11. **`group` and `all` unset `OCUTALON_WARM`**, with one `WARM ignored` line, so they "start fresh stacks exactly as before" (pre-ruled). `live` refuses, as the AC says. A value other than `1`, `0` or empty gives exit 2.
12. **`test-ci-warm.sh` is hermetic by default and registered in `CHECK_SCRIPTS`.** Its `--live` mode starts real stacks and runs on the developer machine only.
    - Rule 8 exemption: CI cannot run the live mode, because CI never uses a warm stack (AD-22, pre-ruled 4).
    - The live mode is the story's integration evidence, run by the implement stage, QA and the lead.
13. **Task 0's gate is "projected at most 0.85 x the VM's memory".** That leaves about 9 GiB for the VM's kernel, BuildKit and page cache. It is a developer-tool limit, not a product target.
14. **The live probes are untracked `ZzWarm<k>` classes**, one in a mapped package (`OcuTalon.Data.Public`) and one in `OcuTalon.Test.Data`, so `cmd_class` accepts the probe. The trap removes them. The tree is checked byte-identical before and after. Steps 3 and 4 run before any probe exists, so no shard meets one.
15. **`ci/warm.sh status` is included** (3 lines), so a stage can see its warm stack without parsing `docker ps`.

16. **`stack_ready <title> <start second>`** takes the start second as its second argument. The spec names one argument; reading the caller's `started` through dynamic scope would tie `warm up` to a variable of `run_classes`. The `READY` seconds still count from the start of the call, the lock wait included.
17. **`warm_mode` prints the mode and returns 2 for a bad value; `warm_check` (new) sets `WARM_MODE` or ends the run with exit 2** in the calling shell, because an `exit` inside `$(warm_mode)` would end only the substitution. `fresh_only` (new, used by `group` and `all`) unsets `OCUTALON_WARM` whatever its value, so `0` does not reach a unit either.
18. **`ci/warm.sh` never sources `ci/iris.sh` when it is itself sourced.** Run, it sources `ci/iris.sh` and dispatches; sourced by `ci/iris.sh` (warm mode) or the test, it defines functions and returns. So the two files cannot source each other in a loop.
19. **The manifest leaves out `.DS_Store` files and hashes raw bytes** (`git hash-object --no-filters --stdin-paths`). A Finder file in `src/` is no input of the image or the stack, and it would refuse every warm run; a filter in `.gitattributes` must not make the same bytes hash differently.
20. **`warm up` copies the decoy key file that `live_start` wrote into the state folder** and writes only the yml and `warm.yml` itself, so the decoy content stays in one place (Rule 2). `LIVE_FILES` keeps the judges' file, the throwaway override and the CI override as `live_start` built them.
21. **Compile errors name their class.** The IRIS session decomposes the compile status and, for each error text, names the class of the compile list that the text mentions (the longest name wins), so the line reads `FAIL WARM compile: <class>: <error>`; an error that names no class of the list prints without one. Control characters (CR, LF, NUL, tab) in any text become spaces, so one error is one line. A failed delete or import prints `FAIL WARM delete|import: <item>: <error>`, and a session that printed no compile result prints `FAIL WARM compile: the IRIS session of <P> did not report the compile`; all of them set the `failed` marker.
22. **The reload runs no IRIS session when nothing changed and no marker is set**: `WARM reloaded 0, deleted 0` costs one manifest comparison (about 0.04 s), not a session.
23. **Counts.** `reloaded <n>` counts the imports that returned OK, and `deleted <m>` the classes of the removed files that are gone from the stack (a class that was never loaded counts as gone).
24. **The live test's cleanup trap** runs `ci/warm.sh down` for the warm tag and teardown for the fresh tag on every exit, after it has checked that the lane holds no warm stack, so it never tears down a stack of an earlier stage.
25. **`warm_state_dir` lives in `ci/iris.sh`, and `cmd_teardown` removes the tag's state folder** (review pass). AC 5 says the state folder is gone after `ci/iris.sh teardown` with the warm tag; before, only `warm down` and a failed `up` removed it. `ci/warm.sh` uses the same function.
26. **The manifest also covers `ci/mock`, except its node tests** (review pass). The mock service mounts the folder read-only and loads it at its start, so a change to it is an input the warm stack cannot apply (the contract's "No other stale input"). `ci/mock/test/` is read by `node --test` only.
27. **A warm run fails closed on its own bookkeeping** (review pass). A missing or empty stored manifest refuses the run (BSD awk prints nothing for a missing file, which read as "nothing changed"). A compile that fails with no error row prints `FAIL WARM compile: the compile of <P> failed and gave no error text`.
28. **The Rule 21 append states four limits** (review pass): the warm stack is the one exception to "at most one throwaway IRIS stack per runner at a time"; a class neither changed nor a subclass of a changed class is not recompiled `(inference)`; two warm calls at once on one stack race (Rule 18), and the code takes no run lock, because a lock needs stale-lock handling and an output line the matrix does not specify; the figures say "added" where the measured class was added, and carry the warm stack's 3.14 GiB.

**Rule 2 (extend, don't copy).** Extended:
- `run_classes`: its start becomes `stack_start` and `stack_ready`, which `warm up` reuses, and it gains the warm branch;
- `cmd_teardown`: the warm lock;
- `live_start` and `live_cleanup`: reused as they are, through the derived lock pair;
- reused unchanged: `live_lock_dir`, `copied_files`, `dc`, `iris_script`, `live_track_image`, `ensure_web_bundle`, `setup_tag`, `preflight`, `class_of`, `test_classes` and `run_class`;
- in `test-ci-config.sh`: the `recipe` helper `iris_env` and the teardown fixture.

`test-ci-warm.sh` follows `test-lib-live.sh`'s lock-test pattern (L467-530) and `test-ci-config.sh`'s stubbed-`docker` pattern, as tests of new code, not copies. There is no copy unless the fallback of decision 9 is taken.

**Integration ACs (Rule 1) and linkage (Rule 2).**
- Consumed-by:
  - every implement, QA and code-review stage, and the lead's architecture-decision verifications, on lanes A, B and C, through Rule 21's appended recipe, from the first plan spawn after Epic 32 merges. In this epic's worktree, Story 32.4's own QA and review stages consume it first;
  - the lead's Rule 19 fresh check reads the absence of `WARM` lines.
- Consumes:
  - from `lib-live.sh`, unchanged: `live_start`, `live_cleanup`, `live_lock_claim`, `live_lock_release`, `live_lock_dir`, `live_tag_ok`, `dc`, `iris_script`, `live_track_image`, `ensure_web_bundle` and `copied_files`;
  - from `ci/iris.sh`: `setup_tag`, `preflight`, `run_class`, `test_classes`, `class_of` and `cmd_teardown`;
  - `ci/units.sh`.
- The integration AC is the "Integration (Rule 1)" item, shown by `--live` against a real warm stack.

**Ledger inbox.** None.

**For the lead (not implement tasks).**
- `parallel.yaml` lists no `warm-iris` lock.
  - A warm lock is held for a whole stage, so a sweep keyed on `throwaway-iris`'s 20 minutes could report it as stale.
  - Its content names the owner and the project, and Rule 12's sweep confirms that the owner is dead before it deletes.
  - Whether to add a `warm-iris` entry is the orchestrator's call, because `_bmad/` is not this story's.
- After this story, the lead's Rule 19 fresh check stays `ci/iris.sh shard lane-a` and `lane-b`, forward and `--reverse`, with no `OCUTALON_WARM`. Its evidence shows `STACK ...: project` and no `WARM` line.

**The Rule 21 append (implement writes it after L284, with the measured values in place of each `<...>`).**

```
  - **Warm mode (Story 32.4, from <date>).** A stage that runs `class` or `shard` more than once may hold one warm throwaway for its lane instead of starting IRIS for every call. With the lane's variables, `OCUTALON_LOCK_OWNER` and the stage's warm tag (its fresh tag followed by `w`, for example `e32s4iw`, so that the teardown of the fresh tag never matches it): `ci/warm.sh up` once; then each run as `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag> ci/iris.sh class <Class>` or `shard <name> [--reverse]`, one per call; and at the stage's end, also after a failure, `ci/warm.sh down`, which tears down the warm tag. Each warm run first prints `WARM reloaded <n>, deleted <m>`: it loads and compiles the classes changed or added since the stack's last load and deletes those removed or renamed (every class of the tree is compiled after a delete or a failed reload), and a change to anything else the image or the stack is built from refuses the run (`ci/warm.sh down`, then `up`). The warm stack holds `warm-iris.lock` in the lane's folder and fresh stacks keep `throwaway-iris.lock`, so a lane runs at most one warm and one fresh stack and its fresh runs never wait on its warm one. Set `OCUTALON_WARM` on the warm call only; never export it. Stages that use it: implement (its `(loop)` class and shard runs), QA, code review (its mutation runs) and the lead's architecture-decision verifications. Never warm: `live` (it refuses `OCUTALON_WARM`), destructive tests, `group` and `all` (they unset it), the fresh-environment check (its evidence shows `STACK ...: project` and no `WARM` line) and CI. What the start does (the installer steps, the production's items) comes from `warm up`, so a story that changes it proves the change on a fresh stack. A stage that ended without `ci/warm.sh down` leaves an orphan: `ci/iris.sh teardown` with its warm tag removes it and releases its lock.
    - **Measured (Story 32.4, <date>, the developer machine, lane C).** Docker VM <m> GiB and <c> CPUs; a slot <s> GiB; a fresh throwaway <f> GiB right after ready; a throwaway after both shards <w> GiB; the other long-running containers <o> GiB; three lanes with one warm and one fresh stack each, beside them: <p> GiB of <m> (<pct> %). The same classes warm and fresh in one stage: `shard lane-a` fresh <a1> s, warm <a2> s; `shard lane-b` fresh <b1> s, warm <b2> s; `class OcuTalon.Test.Install.Users` fresh <u1> s, warm <u2> s, and <u3> s after one class changed; `ci/warm.sh up` <up> s and `down` <dn> s; every class of the tree compiled after a delete <fc> s.
```

## Verification

**Runtime targets (Rule 21, lane C).**
- Every `ci/iris.sh`, `ci/warm.sh` and live-script call sets:
  - `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-c`;
  - `OCUTALON_TEST_WEB_PORT=52803`;
  - `OCUTALON_LOCK_OWNER='epic=32 stage=<stage>'` and `OCUTALON_LOCK_WAIT=240`;
  - the stage's tags: fresh `e32s4i`, warm `e32s4iw` and live test `e32s4it`/`e32s4itf` (implement); `e32s4q`, `e32s4qw` and `e32s4qt` (QA); `e32s4r`, `e32s4rw` and `e32s4rt` (review); `e32s4l`, `e32s4lw` and `e32s4lt` (lead).
- Every IRIS check runs on throwaway stacks, never on a slot. This story needs no dev slot: `ocutalon-slot-c` stays untouched, and no MCP call is made.
- At most one fresh and one warm throwaway for lane C at a time. The live test needs the stage's own warm stack down first.
- Each call ends with `ci/iris.sh teardown` (or `ci/warm.sh down`) for the tags it used. `LOCK busy` means: run the same call again.
- Tear down only what this session started.
- Every command runs from the epic worktree's root, in the foreground of its own call, with `timeout: 600000`.
- Keep this spec free of local machine paths, because `boundaries` scans it.

**Commands:**
- `(loop)` `bash docker/tests/test-ci-warm.sh`. Expected: a PASS line for every check, then `test-ci-warm: all checks passed`, exit 0. It starts no container. About 20 s (inference).
- `(loop)` `bash docker/tests/test-ci-config.sh`. Expected: `PASS recipe`, `PASS teardown` (twice) and every other rule, then `test-ci-config: all rules passed`, exit 0. About 9 s.
- `(once)` `bash docker/tests/test-lib-live.sh`. Expected: `test-lib-live: all checks passed`, with the file unchanged. About 16 s.
- `(once)` The two hermetic scripts in both orders: `bash docker/tests/test-ci-warm.sh && bash docker/tests/test-ci-config.sh`, then the reverse. Expected: both pass both times (Rule 19).
- `(once)` `bash ci/checks.sh`. Expected: a block for `ci-warm` and `checks: all scripts passed`. About 70 s.
- `(once)` With the lane variables, `OCUTALON_LOCK_OWNER='epic=32 stage=implement'` and `OCUTALON_RUN_TAG=e32s4it`: `bash docker/tests/test-ci-warm.sh --live`, with no warm stack of lane C up. Expected: `test-ci-warm: all live checks passed`, exit 0, and `git status --short` the same before and after. At most about 8 minutes. Then `ci/iris.sh teardown` with `e32s4it`, and again with `e32s4itf`, one call each. Expected: `TEARDOWN tag ...: 0 project(s) removed` (the test's own trap has already removed them).
- `(once)` With the lane variables and `OCUTALON_RUN_TAG=e32s4i`, run `bash ci/iris.sh shard lane-a`, then `bash ci/iris.sh shard lane-b`, one per call (the fresh path, unchanged). Expected: `STACK ...: project ocutalon-shard-lane-a-e32s4i-...`, `READY`, a `CLASS ... passed` line for each class, `SHARD ... passed`, no `WARM` line, exit 0. About 60 to 90 s each. Then `ci/iris.sh teardown` with `e32s4i`.
- `(once)` `git status --short`, and `git diff --stat -- docker/tests/lib-live.sh docker/tests/test-production.sh docker/tests/test-pinned-sources.sh ci/mock ci/compose.ci.yml ci/changes.sh .github release src web .claude`. Expected:
  - the modified and new files are only `ci/iris.sh`, `ci/warm.sh`, `ci/units.sh`, `docker/tests/test-ci-config.sh`, `docker/tests/test-ci-warm.sh`, `_bmad/custom/skill-rules.md` and this spec;
  - the diff stat is empty;
  - `git diff -- _bmad/custom/skill-rules.md` shows only added lines.

**Planned mutations (Rule 19).** One per AC. Apply each to a saved copy of the file under test, never to a contended file. Observe red, restore from the copy with `git status --short` and `git diff` byte-identical, and record each as `mutation: ... → ...`.
- **AC 2:** in `ci/warm.sh`, drop the `sed` rename, so that `warm up` claims `throwaway-iris.lock`. Wanted: a red `test-ci-warm.sh`, from the derived-lock checks (no `warm-iris.lock`, and the fresh claim blocked) and the guard.
  - A second mutation drops the warm branch of `run_classes`. Wanted: red from "nothing changed", because `live_start` was called.
  - mutation: `ci/warm.sh` `warm_lock_text` with `| sed 's/throwaway-iris/warm-iris/g'` replaced by `| cat` -> red, `test-ci-warm.sh` 20 checks: the derivation guard fails closed (`FAIL WARM the warm lock could not be derived from lib-live.sh`, exit 9 in the claim checks, exit 1 in every `up` check); `test-ci-config.sh` stays green.
  - mutation: `ci/iris.sh` `run_classes` without its warm branch (always `stack_start` and `stack_ready`) -> red, `test-ci-warm.sh` 8 checks: the warm-run refusals and "nothing changed" (the calls were `stack_start|stack_ready|iris_script`, not `iris_script`).
- **AC 3:** skip the delete list in `warm_reload`. Wanted: a red hermetic rename case (`deleted 0`, wanted 1), and a red `--live` step 5, where the probe's old class is still compiled.
  - A second mutation compiles only L after a delete. Wanted: red, because the full-tree compile is missing from the hermetic compile list, and in `--live` step 5 the child of the removed `Target2` stays compiled, so the run exits 0 where exit 1 is wanted.
  - mutation: `ci/warm.sh` `warm_reload` with the `D)` branch that fills the delete list replaced by `: ;;` -> red, `test-ci-warm.sh` 6 checks (removed class `deleted 0`, renamed class, imported-but-never-compiled class) and `--live` 4 checks (step 5: the renamed probe sees its old class, `deleted 0` everywhere, the subclass probe fails).
  - mutation: `ci/warm.sh` `warm_reload` compiling the classes of `$tmp/load` instead of the whole tree after a delete or a failed reload -> red, `test-ci-warm.sh` 5 checks (`WARM compiled every class (0)`, the marker never clears) and `--live` step 5 (the removed superclass: the run exits 0 and prints `READY` and `CLASS`, where exit 1 with `FAIL WARM compile` is wanted).
  - mutation (review pass, non-class inputs): `ci/warm.sh` `warm_manifest` without its `find ci/mock ...` part -> red, `test-ci-warm.sh` 1 check (a changed `ci/mock/server.mjs` no longer refuses the run). With the stored-manifest guard of `warm_reload` disabled -> red, 1 check (BSD awk cannot open the file, prints nothing, and the run exits 0 with `WARM reloaded 0, deleted 0`).
  - mutation (review pass, exactly one reload line): `ci/iris.sh` `run_classes` calling `warm_attach` inside the class loop -> red, `test-ci-warm.sh` 2 checks (a class run prints 2 `WARM reloaded` lines, a shard of 9 classes prints 10).
  - mutation (review pass, a failed delete is tried again): `ci/warm.sh` `warm_reload` counting a failed delete as done -> red, `test-ci-warm.sh` 4 checks (exit 0 where 1 is wanted, the class leaves the stored manifest, no second delete). Without the "gave no error text" fallback -> red, 1 check (q4); without the `compile_seen` branch -> red, 2 checks (q3). `ci/warm.sh` dispatching `status` to `warm_up` -> red, 2 checks (the command-line status checks).
- **AC 4:** drop `cmd_live`'s refusal. Wanted: red, with exit 1 from the preflight and not exit 2.
  - A second mutation adds `export OCUTALON_WARM=1` in `cmd_group` of `ci/iris.sh`. Wanted: red from the CI rule and the group check.
  - mutation: `ci/iris.sh` `cmd_live` without its `warm` refusal -> red, `test-ci-warm.sh` 1 check: exit 1 with the `PORT` line and the base-image failure, where exit 2 is wanted.
  - mutation: `ci/iris.sh` `cmd_group` with `export OCUTALON_WARM=1` after `fresh_only` -> red, `test-ci-warm.sh` 2 checks: the CI rule (`ci/iris.sh:401`) and the group check (`warm=1` in each unit's process).
- **AC 5:** drop the warm-lock release from `cmd_teardown`. Wanted: `FAIL teardown` in `test-ci-config.sh`, and a red `warm_down` check.
  - A second mutation installs the derived lock after `live_start`. Wanted: red from the derived-lock claim check (no `warm-iris.lock`) and from the "failed up" check (a `throwaway-iris.lock` left in the lane folder).
  - mutation: `ci/iris.sh` `cmd_teardown` without `warm_lock_release "$pattern"` -> red: `FAIL teardown` in `test-ci-config.sh`, and 3 checks in `test-ci-warm.sh` (`warm_down` does not release the lock, and `up` over the state of a stopped stack waits for it and exits 75).
  - mutation: `ci/warm.sh` `warm_up` with `warm_lock_install` moved after `stack_start warm` -> red, `test-ci-warm.sh` 8 checks: `up` prints `LOCK acquired throwaway-iris` and leaves `throwaway-iris.lock` in the lane folder, a held `warm-iris.lock` does not stop it, a held `throwaway-iris.lock` does, and the drift check sees `preflight` and `live_start` run first. The "failed up" check shows the wrong `LOCK acquired` line but no leftover file here, because the derived release deletes whatever file `LIVE_LOCK_FILE` names.
  - mutation (review pass, the state folder after a teardown): `ci/iris.sh` `cmd_teardown` without its `rm -rf` of the tag's state folder -> `FAIL teardown` in `test-ci-config.sh`.
  - Every mutation was applied to a saved copy of `ci/iris.sh` or `ci/warm.sh` (both in this story's footprint), observed red, and restored; the checksums of the tree equal the ones taken before the first mutation (and, for the review pass, before each one).
- **AC 1 and AC 6** are a measurement and a record: no local mutation. **AC 8** aggregates the others. **AC 7** is `--live`'s evidence; its mutation is AC 3's first.

**Shared surfaces:**
- `ci/units.sh` `CHECK_SCRIPTS` (+`ci-warm`). `units_violations` and `ci/checks.sh` read it, and `ci/iris.sh list` prints it.
- `ci/iris.sh`'s usage text (one new line, above the last line that `nosuchcommand` pins).
- `run_classes`' output lines: the fresh lines are byte-identical, and the warm lines are new. The lead's fresh-check evidence and CI's logs read them.
- `cmd_teardown`'s output: a new `LOCK released warm-iris ...` line before `TEARDOWN`. The teardown rule of `test-ci-config.sh` reads it.
- `cmd_live`, `cmd_group` and `cmd_all`'s behaviour under `OCUTALON_WARM`.
- The lane lock folders: a new file name, `warm-iris.lock`.
- `iris_env` and the `unset` subshells of `test-ci-config.sh`, which every recipe pin uses.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

Plan stage (2026-10-23): planned from the story key on the epic path, with the committed `epic-32-context.md` (valid; no planning file newer) and Story 32.3 (`done`) for continuity. Read-only observations only: `docker info` and `docker stats --no-stream`. No stack started, no slot touched, nothing committed.

Implement and review (2026-10-23, lane C):
- **Summary.** The developer loop reuses one warm throwaway per lane. `ci/warm.sh up|down|status` starts and stops it with its own `warm-iris.lock` (derived from lib-live's lock functions, fail-closed); `OCUTALON_WARM=1 ci/iris.sh class|shard` reloads the changed classes (and deletes the removed ones) on it, refuses any other changed input, and starts nothing. `live` refuses the variable, `group` and `all` drop it, CI never names it, and `cmd_teardown` releases the tag's warm lock and removes its state. The Task 0 gate held (31.4 GiB projected, 50.1 % of the 62.68 GiB VM), and the recipe with the measured numbers is appended to Rule 21.
- **Files.** `ci/warm.sh` (new): the warm lifecycle, the manifest and the reload. `ci/iris.sh`: `stack_start`/`stack_ready`, the warm branch, the `live`, `group`, `all` guards, `warm_state_dir`, the teardown additions, the usage line. `ci/units.sh`: `ci-warm` in `CHECK_SCRIPTS`. `docker/tests/test-ci-warm.sh` (new): hermetic checks and `--live`. `docker/tests/test-ci-config.sh`: `OCUTALON_WARM` cleared in the recipe helpers, the teardown fixture for the lock and the state folder. `_bmad/custom/skill-rules.md`: the two Rule 21 sub-bullets (added lines only). This spec.
- **Review.** 40 findings from four layers: high 0, medium 2, low 34, false 4. Patched (21 findings in 15 entries, by root cause: 1 medium, 14 low): the `ci/mock` input, the state folder after a teardown, the missing-manifest guard, the compile fallback line, the failed-delete, no-compile-result, status and exactly-one-line tests, the live regex, the vacuous lock comparisons, three comments or headers, and four Rule 21 clauses. Rejected with their reasons in the Review Triage Log: 15 low, 4 false. Deferred: none.
- **Follow-up review.** Not recommended (`followup_review_recommended: false`): one medium entry was patched and no high, and each patched hermetic check has a demonstrated mutation.
- **Verification.** `(loop)`: `test-ci-warm.sh` (all checks passed, 6 s) and `test-ci-config.sh` (all rules passed, `PASS teardown` twice). `(once)` after the last patch: `test-lib-live.sh` passed; the two hermetic scripts passed in both orders; `bash ci/checks.sh` ended `checks: all scripts passed` with a block for `ci-warm`; `test-ci-warm.sh --live` ended `all live checks passed` in 1 min 58 s with `git status --short` unchanged (the tag teardowns removed 0 projects); fresh `shard lane-a` (54 s) and `shard lane-b` (69 s) passed with `STACK ...: project`, no `WARM` line; the contended paths show an empty `git diff --stat`, and `git diff` of `_bmad/custom/skill-rules.md` removes no line. Extra checks of the review: one warm stack ran `shard lane-a` three times (once `--reverse`) and `shard lane-b` twice, all passed; a subclass probe showed the subclass current after a parent-only change.
- **Residual risks.** A warm run recompiles only the imported classes and their subclasses (the whole tree after a delete or a failed reload), so a change that reaches another class through a generator is proved on a fresh stack (the Rule 21 text says so, `(inference)`). Two warm calls at once on one stack race; the recipe forbids it and the code takes no run lock. `parallel.yaml` lists no `warm-iris` lock (for the lead, DW-111 already filed).
