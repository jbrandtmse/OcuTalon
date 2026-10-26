---
title: 'Story 15.1: The first install run creates OCUTALON and gives the next command'
type: 'feature'
created: '2026-10-26'
status: 'done'
baseline_revision: '03189a8e3a06ae2221e9f323a9c9c46de700b8f7'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon's one IPM package (`ocutalon`) installs only into a namespace that already has OcuTalon's databases and mappings, and IPM installs only into the namespace it runs in. So an admin with an existing AI Hub build 154 instance cannot start the install from their own namespace (FR-57, S19).

**Approach:** Make the package's first resource a CPF resource, `src/cpf/ocutalon.cpf`: the image's merge file without the Docker-only `%Service_CallIn` line. It creates OCUTALON, its four databases and AD-3's mappings before anything loads. Add one early step that maps IPM into OCUTALON and, outside OCUTALON, stops the run with the exact next command. A hermetic CI check keeps the two CPF files equal. A new FR-57 job in `lane-a.yml` proves three things on a clean build 154 instance: the first run, its repeat, and the `iris merge` alternative.

## Boundaries & Constraints

**Always:**
- One package, `ocutalon` (AD-2). The CPF element is the manifest's first resource. The three bridge-first `<Resource>` lines follow, unchanged, then everything else.
- `src/cpf/ocutalon.cpf` equals `docker/merge.cpf` with its `%Service_CallIn` and `%IPM` lines removed, and contains no line of either kind (AD-23).
- The stop sentence is exactly `OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.` The step returns it as a plain error status, so IPM 0.10.10 prints `ERROR! ` followed by the sentence, and `%IPM.Main.Shell()` returns that error. In OCUTALON the step returns OK and the install continues.
- The IPM mapping is made with transactions suspended, and the previous suspension state is restored on every path. This way the stopped run's rollback cannot undo the mapping.
- IPM installs, `iris merge` and namespace or database creation run only in throwaway stacks of `docker/tests/lib-live.sh`, never on a slot or any other instance (AD-22, Rule 21).
- The FR-57 job's image is built on the runner from the base image. It is never pulled, pushed, cached or uploaded (AD-29).

**Never:**
- The package changes none of the instance's services, `%Service_CallIn` included.
- Outside OCUTALON, nothing runs or stays: no installer step, no OcuTalon class, global or module record, no role, no user `ocutalon` and no `/ocutalon` web application. The one exception is the step's own class, which compiles into the run namespace and is rolled back with the stopped run.
- No unprefixed-stop trick (an error coded as Ctrl-C, code 7). It makes `Shell()` report success for an install that did not happen.
- No edits to contended files: `ci/iris.sh`, `ci/warm.sh`, `docker/tests/test-ci-config.sh`, `docker/tests/test-install-start.sh`, `.github/workflows/ci.yml`, `docker/Dockerfile`, `docker/after-start.cos`, `docker-compose.yml`, `ci/compose.ci.yml`, `release/standalone-bridge.sh`. No edits to `lane-a.yml`'s header comment or its `standalone-bridge` job, and none to `docker/merge.cpf`.
- Out of scope:
  - Story 15.2: the second run in OCUTALON, `Registry.Run("ipm")`, the web bundle, demo mode and `docs/install-ipm.md`.
  - Story 15.3: restarts, reinstalls, the release gate and the registry install.
  - Runs with IPM's `-dev` or `-DNoTransaction=1`. Both commit IPM's transaction early (inference from IPM's source, `%IPM.Utils.Module` lines 1068, 1203 and 1227), and the documented commands never use them.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First run outside OCUTALON | Clean instance with IPM 0.10.10 in %SYS, enabled for USER only. `zpm "load /opt/ocutalon-ipm/src"` runs in USER. | The CPF creates `OCUTALON_CODE`, `_DATA`, `_PRIVATE` and `_PUBLIC`; only `%DB_OCUTALON_PUBLIC` has public Read. It creates OCUTALON (Globals `OCUTALON_DATA`, Routines `OCUTALON_CODE`, Interoperability on) and AD-3's seven mappings. The step maps the `%IPM` package and `%IPM.*` routines into OCUTALON from the database where `%IPM` resolves in USER. The output shows `Initialize FAILURE`, no `Reload START` and no `STEP ` line, and ends with `ERROR! ` followed by the stop sentence. Services are unchanged. No OcuTalon residue in USER, %SYS or OCUTALON (residue check). IPM answers in OCUTALON. | By design, the stop is the end of this run. IPM rolls back its transaction. |
| Repeat in USER | After the first run, the same command again in USER | Configuration and services are identical to after the first run. Same final line. No residue. | as above |
| Repeat in %SYS | After the first run, the same command in %SYS | Same as the repeat in USER | as above |
| Run in OCUTALON | IPM mapped into OCUTALON (Docker after-start load; Story 15.2's second run) | The step returns OK. Reload, Validate, Compile and Activate run. | No error expected |
| `iris merge` path | Fresh clean instance; `iris merge IRIS /opt/ocutalon-ipm/src/cpf/ocutalon.cpf` | Same namespace row, Interoperability flag, databases, resources and OCUTALON mappings as after the first run, minus the two `%IPM` mappings. Services are unchanged. | A merge exit other than 0 fails the check |

</intent-contract>

## Code Map

- `src/module.xml` -- the package manifest.
  - Lines 8-10 are the three bridge-first `<Resource>` lines that `test-pinned-sources.sh` pins.
  - Line 11 is the FileCopy line that `test-compose-file.sh:125-126` greps for.
  - Its first `<Version>` is read by `docker/Dockerfile:17` and by lib-live's `manifest_version`.
- `docker/merge.cpf` -- read only; `src/cpf/ocutalon.cpf` is derived from it. Line 18 is the Docker-only `ModifyService:Name=%Service_CallIn,Enabled=1,AutheEnabled=48`. Its four `Directory=` values are relative (`test-compose-file.sh:132-133`).
- `docker/after-start.cos:5,7` -- a consumer, read only (Lane B). Line 5 runs `enable -map -ns OCUTALON -q` from %SYS. Line 7 loads `/opt/ocutalon/src` in OCUTALON, so the Docker install now also runs the CPF merge and the step there.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls:43-47` -- `Run()` already refuses any namespace but OCUTALON. Unchanged.
- `release/standalone-bridge.sh` -- the sibling the FR-57 script follows:
  - :29-41 sources `ci/iris.sh`, then calls `setup_tag`, `preflight` and `live_start`;
  - :44-49 runs `dc up -d --build --wait --wait-timeout "$((deadline - SECONDS))"` and `live_track_image`;
  - :59-60 runs a direct `dc exec -T iris iris merge`;
  - :209-213 prints the summary and sets the exit code.
- `docker/tests/lib-live.sh` -- the throwaway recipe:
  - `live_start` :57-88 sets `P`, `tmp` and `deadline`, and sets `LIVE_FILES` to the judges' file, the decoy, `compose.throwaway.yml` and `ci/compose.ci.yml`. It also installs the cleanup trap and claims the lock.
  - Other helpers: `live_add_file` :151, `dc` :243-247, `live_track_image` :251, `pass`/`fail`/`die` :273-282, `wait_until` :286, `iris_script` :307-317 (keeps only `CHK|` lines), `compare_chk` :455, `check_session` :479.
- `ci/iris.sh` -- contended, read only. `setup_tag` :47; `preflight` :89 (checks the base image, pulls the mock image once); `build` :316; `teardown` :467-503 (removes `ocutalon-<label>-<tag>-<epoch>-<pid>`). It returns when sourced (:505).
- `ci/units.sh:6` -- `CHECK_SCRIPTS`. A name `<n>` is `docker/tests/test-<n>.sh`, which `ci/checks.sh` runs in the hosted `checks` job of `ci.yml`.
- `docker/tests/test-ci-config.sh` -- contended, read only. Its workflow rules bind the new job:
  - the exact fork guard (:176, :245);
  - `runs-on: [self-hosted, ocutalon]` (:207-211);
  - actions pinned as `owner/repo@<40 hex> # vX.Y.Z` (:218-219);
  - `persist-credentials: false` (:265);
  - a step that runs `ci/iris.sh` needs a later `if: always()` step that runs `ci/iris.sh teardown` (:251-262);
  - no `continue-on-error`, `actions/cache`, `docker/*` action or `upload-artifact` (:214, :221-222);
  - no `matrix` (:266-269);
  - lane-a only needs `standalone-bridge` to exist (:1667);
  - every `docker/tests/test-*.sh` is in exactly one list (:600-624).
- `docker/tests/test-pinned-sources.sh:54-67,139-146` -- `resources()` reads every `<Resource ` line, and `bridge_first` pins the first three. `each_resource_has_its_package` wants `src/<Directory>/<package path>/*.cls` for every resource, which a preload `.CLS` resource fails today.
- `docker-compose.yml`, `docker/tests/compose.throwaway.yml`, `ci/compose.ci.yml`, `.dockerignore` -- read only.
  - The judges' service `iris` builds `docker/Dockerfile` from context `.` with build argument `IRIS_IMAGE`. Its health check runs `/opt/ocutalon/healthcheck.sh`, and it mounts the volume `durable:/durable`.
  - The throwaway override resets ports and `env_file`, sets `restart: "no"` and mounts `./eval`.
  - The CI override adds the mock and its environment variables.
  - `.dockerignore` admits only `src`, `docker/ipm/zpm-0.10.10.xml`, `docker/ipm/LICENSE` and four `docker/` files.
- `docker/Dockerfile` -- read-only sibling (Lane B). Its `ENV ISC_CPF_MERGE_FILE`, `/opt/ocutalon/version` and after-start `CMD` are exactly what the clean image must not have.
- `docker/tests/test-pinned-sources.sh:1-36,148-152` and `docker/tests/test-class-rules.sh`, which runs synthetic samples before the real files -- templates for `test-cpf.sh`.
- `irislib/%SYSTEM/Process.cls:1873-1902` -- `TransactionsSuspended(switch)`. Changes made while suspended are not rolled back; the call returns the previous state.
- IPM 0.10.10, read from the pinned `docker/ipm/zpm-0.10.10.xml` (source extracted at plan time):
  - `%IPM.ResourceProcessor.CPF` takes `<CPF Name Directory Phase When/>`, with defaults `cpf`, `Initialize` and `Before`. Its file is `<root>/<SourcesRoot>/<Directory>/<Name>`. It applies the file with `iris merge <instance> <temp>` through `$zf(-100)`, so outside IPM's transaction, on every pass through Initialize.
  - `%IPM.Lifecycle.Base` `%Initialize` imports and compiles `<root>/preload/` into the current namespace.
  - An `<Invoke>` needs an existing class. Before runs ahead of `%Initialize`, After runs after it.
  - `%IPM.Main` `DisplayError` prints `ERROR! ` followed by `GetOneStatusText`.
  - Every phase runs inside IPM's transaction, which is rolled back on any failure.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0, measurement (throwaway only, tag `e15s1i`) -- the plan stage measured IPM's behaviour (Design Notes, "Measured at plan"). The confirmation is the first run of `release/ipm-install.sh`, once the tasks below have created it.
  - Record its `TIME` lines, the stack's ready seconds and any deviation under Design Notes, "Measured in implement".
  - If Compose cannot build `release/ipm/Dockerfile` because `.dockerignore` excludes it, put the same lines in `build.dockerfile_inline` of `release/ipm/compose.ipm.yml` instead and record why. It is an inference that the build works, because Docker always sends the Dockerfile.
- [ ] `src/cpf/ocutalon.cpf` -- create it from `docker/merge.cpf`'s lines, in order, without `ModifyService:Name=%Service_CallIn,Enabled=1,AutheEnabled=48`, with LF endings -- AD-23's CPF file.
- [ ] `src/preload/cls/OcuTalon/Install/Ipm.cls` -- create `OcuTalon.Install.Ipm` with `ClassMethod MapAndStop() As %Status` -- the second early step. It lives in IPM's preload tree because an Initialize-phase Invoke can only call a class that exists before Reload.
  - It saves the state from `$SYSTEM.Process.TransactionsSuspended(1)`, calls `##class(%IPM.Main).Shell("enable -map -ns OCUTALON -q")` inside a Try/Catch, and restores the saved state on every path.
  - It returns the mapping's error unchanged. Otherwise it returns `$SYSTEM.Status.Error(5001, "OcuTalon created namespace OCUTALON. Now run: zn ""OCUTALON"" then the same install command.")` when `$Namespace '= "OCUTALON"`, and `$$$OK` in OCUTALON.
  - No `Write`, no namespace switch, no other effect. The doc comment states this contract.
- [ ] `src/module.xml` -- three insertions; the order this gives is CPF merge, preload compile, step, then Reload:
  - after `<SourcesRoot>`, `<CPF Name="ocutalon.cpf" Directory="cpf" Phase="Initialize" When="Before"/>`, with the three `<Resource>` lines next and unchanged;
  - after `OcuTalon.PKG`, `<Resource Name="OcuTalon.Install.Ipm.CLS" Directory="cls" Preload="true"/>`;
  - after the FileCopy line, `<Invoke Class="OcuTalon.Install.Ipm" Method="MapAndStop" Phase="Initialize" When="After"/>`.
- [ ] `docker/tests/test-pinned-sources.sh` -- change only `each_resource_has_its_package` and its comment. A `.CLS` resource whose line has `Preload="true"` must name an existing file `src/preload/<Directory>/<class path>.cls`; every other resource keeps the package rule -- the step's class is a declared resource, so the package carries it (inference until Story 15.3's registry run).
- [ ] `docker/tests/test-cpf.sh` -- create the hermetic check (AD-23's CPF check and the manifest's first resource).
  - Form: a header that says what it pins, `set -u`, root found from `$0`, a temp dir with an EXIT trap, one PASS or FAIL line per check, exit 0 only when every check passes, no Docker, ASCII only.
  - Each rule first runs on synthetic files, one that keeps it and one that breaks it.
  - Rule 1: `src/cpf/ocutalon.cpf` has no line containing `%Service_CallIn` or `%IPM`.
  - Rule 2: `docker/merge.cpf` without its lines containing `%Service_CallIn` or `%IPM` equals `src/cpf/ocutalon.cpf` byte for byte.
  - Rule 3: the CPF file has the eight `CreateResource`/`CreateDatabase` lines of `OCUTALON_CODE`, `_DATA`, `_PRIVATE` and `_PUBLIC`, with `PublicPermission=R` on `%DB_OCUTALON_PUBLIC` and on no other resource. It has `CreateNamespace:Name=OCUTALON,Globals=OCUTALON_DATA,Routines=OCUTALON_CODE,Interop=1`. It has AD-3's seven mappings: globals `OcuTalonP.*`, `OcuTalonBP.*`, `AI.Agent.Session*` and `IRIS.IF.*` to `OCUTALON_PRIVATE`; global `OcuTalonPublic` and packages `OcuTalon.Web.Public` and `OcuTalon.Data.Public` to `OCUTALON_PUBLIC`.
  - Rule 4: `src/module.xml` has exactly one `<CPF ` element, `<CPF Name="ocutalon.cpf" Directory="cpf" Phase="Initialize" When="Before"/>`, and no `<Resource`, `<FileCopy` or `<Invoke` line comes before it.
- [ ] `ci/units.sh` -- append `cpf` to `CHECK_SCRIPTS`, and change nothing else -- the hosted `checks` job runs it, and `test-ci-config.sh`'s units rule requires it.
- [ ] `release/ipm/Dockerfile` -- create it -- a clean instance like an admin's: the first run, not a merge file, creates OCUTALON, and Story 15.2's demo seed finds no `/opt/ocutalon/version`.
  - `ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0`, then `FROM ${IRIS_IMAGE}`.
  - As root, copy `src/` to `/opt/ocutalon-ipm/src/` and `docker/ipm/zpm-0.10.10.xml` to `/opt/ocutalon-ipm/`. Files get mode 444 and directories 555. Then `USER 51773`.
  - No `ENV`, no `CMD`, nothing else.
- [ ] `release/ipm/compose.ipm.yml` -- create the override that `release/ipm-install.sh` adds after `live_start`'s files. Service `iris` builds `release/ipm/Dockerfile`; the context stays the repository root. Its health check is `["CMD-SHELL", "iris qlist | grep -q '\\^running'"]`. A header comment says what it changes and why.
- [ ] `release/ipm-install.sh` -- create the FR-57 script. Its header follows `standalone-bridge.sh`'s: what it proves, how to run it, the numbered checks. Its functions are named so that Stories 15.2 and 15.3 can extend them: snapshot, residue, run.
  - **Setup:** `setup_tag`, `preflight`, `live_start ipm`, `live_add_file "$root/release/ipm/compose.ipm.yml"`, `dc up -d --build --wait --wait-timeout "$((deadline - SECONDS))"`, `live_track_image`.
  - **Path A, two package runs:**
    - Precondition, `die` on failure: in %SYS, load `/opt/ocutalon-ipm/zpm-0.10.10.xml` with flags `ck-d`, then `enable -map -ns USER -q`. Take the baseline snapshot after this.
    - Check that OCUTALON does not exist yet.
    - Run `zpm "load /opt/ocutalon-ipm/src"` in USER, then in USER again, then in %SYS. Check each run against the matrix.
    - Check that `##class(%IPM.Main).Shell("version")` returns OK in OCUTALON.
  - **Path B, `iris merge`:**
    - `dc down -v`, then `dc up -d --wait`: a fresh instance from the same image. Check that it has no OCUTALON.
    - Take a services baseline, then run `dc exec -T iris iris merge IRIS /opt/ocutalon-ipm/src/cpf/ocutalon.cpf`.
    - Compare the OCUTALON view with path A's, without the two `%IPM` mapping lines, and check that the services are unchanged.
  - **Snapshot**, one %SYS session, one line per item:
    - every service with its enabled and authentication flags;
    - OCUTALON's namespace row and its Interoperability flag;
    - `OCUTALON*` databases with the last part of their directory;
    - `%DB_OCUTALON*` resources with their public permission;
    - OCUTALON's global, package and routine mappings with their database;
    - USER's package and routine mappings.
  - **Residue check:**
    - for USER, %SYS and OCUTALON: the counts of `OcuTalon*` class definitions, compiled classes and routine objects, and of the `ocutalon` module record;
    - for USER and %SYS: the count of `^OcuTalon*` globals;
    - instance-wide: `OcuTalon*` roles, user `ocutalon` and `/ocutalon*` web applications.
  - **Output:** print every install run's and the merge's full output between `OUTPUT begin <name>` and `OUTPUT end <name>`, with ANSI codes kept; compare with ANSI codes removed. Print `TIME <step> <s>s` lines.
  - **End**, like `standalone-bridge.sh`: `ipm-install: N check(s) failed (project $P)` and exit 1, or `ipm-install: all checks passed`.
- [ ] `.github/workflows/lane-a.yml` -- append job `ipm-install` at the end of `jobs:`; the header comment and `standalone-bridge` stay untouched -- the FR-57 job, whose log keeps every run's full output.
  - The fork guard, `runs-on: [self-hosted, ocutalon]` and `timeout-minutes: 30`.
  - env: `IRIS_IMAGE: ocutalon-iris-base:2026.3.0AI.154.0`, `OCUTALON_RUN_TAG: ${{ github.run_id }}-${{ github.run_attempt }}-ipm` and `OCUTALON_LIVE_DEADLINE: "1500"`.
  - Steps:
    1. checkout, pinned as in `standalone-bridge`, with `persist-credentials: false`;
    2. `bash ci/iris.sh build`;
    3. `bash release/ipm-install.sh`;
    4. `bash ci/iris.sh teardown` under `if: always()`.

**Acceptance Criteria:**
- Given `src/module.xml`, when it is read, then its first resource is `<CPF Name="ocutalon.cpf" Directory="cpf" Phase="Initialize" When="Before"/>`, ahead of the bridge's three resources and everything else. And `src/cpf/ocutalon.cpf` creates the four databases (`OCUTALON_PUBLIC` with public Read), OCUTALON with Interoperability and AD-3's mappings, with no `%Service_CallIn` and no `%IPM` line: `bash docker/tests/test-cpf.sh` passes.
- Given `docker/merge.cpf` and `src/cpf/ocutalon.cpf`, when the hosted `checks` job runs `bash ci/checks.sh`, then check `cpf` fails the build if the files differ in any line that is not a `%Service_CallIn` or `%IPM` line.
- Given a push or a same-repository pull request, when `lane-a` runs, then job `ipm-install` runs `release/ipm-install.sh` on the IRIS runner from an image built there and never cached, pushed or uploaded. Fork pull requests skip it, and it fails unless every check passes. Its log holds each install run's and the merge's full output between `OUTPUT` lines, and `bash docker/tests/test-ci-config.sh` passes.
- Given the first run has stopped, when the admin runs `zn "OCUTALON"`, then IPM answers there (`%IPM.Main.Shell("version")` returns OK), so the next command can start in OCUTALON. This is an Integration AC whose consumer is the admin's next command; the full second run is Story 15.2's.
- Given the Docker install, whose consumer `docker/after-start.cos` loads the package in OCUTALON, when a throwaway stack starts, then the CPF resource and the step pass through and the after-start log shows `STEP package loaded` and every installer step OK: `ci/iris.sh group install-fresh` and `group install-upgrade` pass (Integration AC).
- Given IPM 0.10.10, which allows no honest stop without its error prefix (Design Notes), when the first run stops, then the output keeps `ERROR!`, and `release/ipm-install.sh` checks that the final line, with ANSI codes removed, is exactly `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.`

## Spec Change Log

## Review Triage Log

### 2026-10-26 - Review pass
- verdicts: 30 findings reported (blind 7, edge-case 11, verification-gap 7, intent-alignment 5), logged in 14 grouped rows - high 0, medium 3 rows, low 8 rows, false 3 rows, maybe-false 0; 6 rows patched, 8 rejected
- findings:
  - `[medium]` `[patch]` blind 1, edge 3 and 11, gap 2: `test-cpf.sh` rules 1 and 3 are subset checks, so an extra service, mapping or database line in `src/cpf/ocutalon.cpf` passes (the header claims the package changes no service) - `cpf_content` now also requires the non-header line count to equal the 16 wanted lines, with a sample that adds a `%Service_Bindings` line; mutation recorded.
  - `[low]` `[patch]` gap 1, edge 6: rule 2's negative samples differ from the good one by more than the property they name (a header-only CRLF file, a service sample without `[Actions]`) - replaced by a full CRLF copy, a service sample with the header and an extra-mapping sample.
  - `[medium]` `[patch]` blind 4, gap 3: nothing guards that `lane-a.yml` keeps job `ipm-install` running `release/ipm-install.sh` (`test-ci-config.sh` is contended and only checks `standalone-bridge`) - rule 6 added to `test-cpf.sh` with samples; mutation recorded.
  - `[medium]` `[patch]` gap 5, intent 5, blind (last bullet): the preload resource and the one Invoke are pinned only by the live scripts - rule 5 added (exact preload resource, exactly one Invoke at Initialize, After); mutation recorded.
  - `[low]` `[patch]` gap 4: AC 4 (IPM answers in OCUTALON) and the path B comparison had no `mutation:` line - both mutations run, red observed, reverted byte-identical, lines written.
  - `[low]` `[patch]` blind 2 and gap other: the residue pass message and header say "outside OCUTALON" while the check also counts residue inside it - worded as "in USER, %SYS or OCUTALON".
  - `[low]` `[reject]` blind 3, intent 3 and 4: no `%UnitTest` class for `MapAndStop`, the continuation in OCUTALON, the returned status of `Shell()` - Decided in-stage 9 (no `%UnitTest` class); `install-start` in `group install-fresh` pins the OCUTALON branch and the mutation "stops in OCUTALON too" went red there.
  - `[low]` `[reject]` blind 5: the sentence is duplicated in the class and the script - the script is the independent oracle by design; the wording is fixed by the intent contract, so the "created namespace" text on repeat runs is by design.
  - `[low]` `[reject]` blind 6: `run_rc` is set and unread - a failed `dc exec` produces no matching output and fails `stops_with_next_command`; the fix adds a branch for a case nobody will meet.
  - `[low]` `[reject]` blind 7, edge 1 and 2, edge 7 to 10: deadline arithmetic below zero, other ANSI forms, other prompt shapes, a namespace changed by `Shell()`, a merge not yet visible - the arithmetic is the sibling `standalone-bridge.sh` pattern with a 1500 s deadline against a measured 100 s path A; the output forms are measured; `iris merge` is synchronous; none is reachable on the measured build.
  - `[false]` `[reject]` edge 5: rule 1 passes vacuously on a missing file - rule 2's `cmp` and rule 3 fail on a missing `src/cpf/ocutalon.cpf`.
  - `[false]` `[reject]` edge 4: `compare_chk` is a subset check - an extra non-%IPM line made by the step shows in the path A against path B view diff, because path B runs no step.
  - `[low]` `[reject]` intent 1, 2 and 5: the evidence uses `zpm "load <sources>"` on a bare base image - the matrix names that command and instance; the registry `install ocutalon` run is Story 15.3.
  - `[false]` `[reject]` intent 4 (the fourth preload resource line goes beyond three bridge-first lines) - the spec's Task adds it and `bridge_first` still passes.

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: one package, with the bridge's resources first.
- AD-3: the four databases, the mappings and mappings-first; `OcuTalon.Install.*` may switch namespace, and this story switches none.
- AD-23: the CPF resource first, the second early step, the stop, the `iris merge` alternative, no change to services, and the FR-57 job.
- AD-29: Lane A owns the CPF resource, the map-and-stop step, the CPF check, `lane-a.yml`'s FR-57 job and `release/`; the image is never pushed, cached or uploaded.
- AD-22: destructive tests run only on throwaways.

No AC contradicts an AD.

**Measured at plan** (2026-10-26, developer machine, ARM). A probe module carried the real CPF content, a preload step class and the same Invoke, on a lib-live throwaway (tag `e15s1plan`) of the base image `ocutalon-iris-base:2026.3.0AI.154.0` with IPM 0.10.10 from `docker/ipm/zpm-0.10.10.xml`. It was torn down afterwards (`TEARDOWN ... 0 left`).
- **Timings:** the stack was ready in 11 s. Loading IPM in %SYS and running `enable -map -ns USER` took 14 s. The first run in USER took 25 s, because `Interop=1` runs the Foundation installer for OCUTALON. The repeats took 1 to 2 s.
- **Output:** `[USER|probe]<TAB>Initialize START`, then the preload class's compile lines, then `[probe]<TAB>Initialize FAILURE`, then `ERROR! ` followed by the stop sentence, with `ERROR!` in ANSI red, and nothing after it.
  - `Shell()` returns an error whose `GetOneStatusText` is the sentence.
  - `$TLevel` and `TransactionsSuspended()` are back to 0 afterwards.
- **State after the stop:**
  - OCUTALON exists (`OCUTALON_DATA`/`OCUTALON_CODE`, Interoperability 1) with four databases in the relative directories `ocutalon_*`.
  - Only `%DB_OCUTALON_PUBLIC` has public `R`.
  - The seven AD-3 mappings exist, and `%IPM` plus `%IPM.*` are mapped into OCUTALON from `IRISSYS`.
  - The services are identical to before.
- **No residue:** USER, %SYS and OCUTALON hold no class definition, compiled class, routine object or module record of the step's package. IPM's rollback removed the preload compile, and the suspended mapping survived it.
- **Repeats:** the repeat in USER and the run in %SYS left identical snapshots and gave the same stop.
- **In OCUTALON:** the same module, run there, passed every phase, with the preload class overlapping the package resource.
- **Side notes:**
  - IPM's CPF processor leaves `zf100stdout` and `zf100stderr` in the process's directory; this is IPM's behaviour.
  - In %SYS, `enable -map -ns OCUTALON -q` printed IPM's version list despite `-q`; this is cosmetic.

**Measured in implement** (2026-10-26, developer machine, ARM; `release/ipm-install.sh`, tag `e15s1i`, final run all checks passed):
- `TIME ready 6s`, `first-user 24s`, `again-user 3s`, `again-sys 3s`, `ready-b 7s`, `merge 23s`; a whole run is about 90 s on this machine. Earlier runs measured ready 7 to 17 s and first-user 26 to 57 s.
- The stop output is as measured at plan. Piped into `iris session`, the last line is `ERROR! ` (red) plus the sentence, followed by a prompt line (`USER>`); the script's `final_line` skips blanks and prompt lines.
- Directory of a built-in-relative database is `ocutalon_*`; `Security.Resources.PublicPermission` reads `1` for Read and `0` for none; the OCUTALON mapping view of path A and B is 203 lines (system default routine maps included).
- Deviation: the build context needed no inline Dockerfile; Compose built `release/ipm/Dockerfile` despite `.dockerignore`.
- `ci/iris.sh group shards` takes 673 s (over one tool call's cap); it finished after being moved to the background.

**Not measured, so inference:**
- The hazard without suspension. Source: `Config.MapPackages` writes `^SYS("CONFIG")` inside IPM's transaction, while the CPF file and the active mapping are written outside it.
- IPM installed into a non-%SYS namespace, or mapped `-globally`. The step maps from wherever `%IPM` resolves in the run namespace.
- `-dev` runs.
- The plain IRIS image.
- x64 timings: the job is expected to take about 9 to 13 minutes on the runner (two first starts of about 150 to 230 s, IPM loads, three runs, one merge), inside REL-4's 35 minutes. The first CI run measures it.

**Behaviour notes (source, not exercised):**
- If the merge fails, IPM prints `ERROR! Error merging CPF file. $zf(-100) exited with <n>`, and Initialize stops before the step runs.
- If the mapping fails, the step returns IPM's error, and IPM prints that error instead of the sentence.

**Decided in-stage:**
1. **The step is a preload class**, `OcuTalon.Install.Ipm` at `src/preload/cls/...`, invoked at Initialize, After. `src/preload/` is IPM's fixed preload root. An Invoke can call only a class that already exists, and IPM's own module uses the same pattern. Its compile in the run namespace is undone by IPM's rollback (measured).
2. **The mapping runs with transactions suspended**, so the stop's rollback cannot undo part of it.
3. **The `ERROR!` prefix stays.** IPM 0.10.10 has no supported unprefixed stop. Its only one, an error code 7, makes `Shell()` return OK for an install that did not happen, which fails product default 3. AD-23's fallback applies: Story 15.2's document shows the real output and says that the first run ends early by design.
4. **The sentence has no backticks.** The epics' backticks are Markdown formatting.
5. **The clean image is the base image plus the package sources and the pinned IPM file, and nothing more.** IPM is installed in %SYS and enabled for USER only, so only the step can make IPM available in OCUTALON.
6. **The second non-OCUTALON namespace is %SYS**, IPM's home and an admin's usual prompt.
7. **The preload resource is declared now**, so the package carries it; `test-pinned-sources.sh` gets one branch for it. That file is not contended and lies in this epic's footprint, and Lane A's Story 1.3 last changed it.
8. **The job's files live in `release/`**: Lane A's folder, which is not an input of `ci.yml`'s groups (`NOT_IRIS_INPUT_PATTERN`). The check lives at `docker/tests/test-cpf.sh`, because `ci/checks.sh` runs only `docker/tests/test-<name>.sh`.
9. **No `%UnitTest` class.** The step's contract is only observable inside an IPM run. `release/ipm-install.sh` pins it outside OCUTALON, and `install-start` pins it inside.
10. **Job settings:** the job is named `ipm-install`, with tag suffix `-ipm` (neither tag ends the other, `-bridge`), `timeout-minutes: 30` and `OCUTALON_LIVE_DEADLINE` 1500.

**Integration ACs, Consumed-by and Consumes (Rules 1 and 2):** the two Integration ACs are the admin's next command and the Docker after-start load.

Consumed-by:
- **Story 15.2**, the second run in OCUTALON. It uses OCUTALON as the CPF created it, the IPM mapping, and `MapAndStop`'s OK in OCUTALON. It adds `Registry.Run("ipm")`, the bundle check, demo mode off and `docs/install-ipm.md`. It extends `release/ipm-install.sh` and its stack, which already includes `ci/compose.ci.yml`'s mock and has no `/opt/ocutalon/version`, and adds `zpm "enable -map -ns OCUTALON"` after path B.
- **Story 15.3** extends the same job with restarts and reinstalls, and proves that the registry package carries `cpf/ocutalon.cpf` and the preload class.

Consumes:
- `docker/merge.cpf`, as the CPF source;
- `Registry.Run`'s refusal outside OCUTALON;
- lib-live's throwaway recipe;
- the base image.

**Extend, don't copy (Rule 2):**
- `release/ipm-install.sh` extends `ci/iris.sh` and `lib-live.sh` the way `release/standalone-bridge.sh` does. It is a new script with different checks, not a copy.
- `src/cpf/ocutalon.cpf` is a copy of `docker/merge.cpf` that AD-23 forces, kept equal by `test-cpf.sh`.
- `release/ipm/Dockerfile` is a deliberate separate recipe of about six lines rather than a change to `docker/Dockerfile`, which is Lane B's file. The IPM job needs an instance without the merge file, after-start script, version file and health check that the image's recipe exists to add.
- `compose.ipm.yml` is separate from `compose.no-after-start.yml` because it changes the build and the health check, not the command.
- `MapAndStop` calls the same IPM command as `after-start.cos` line 5. A session script and an Invoke target share no code.

**Ledger inbox:** none.

**Footprint extension, for the lead's completion contract:** `src/preload/**` (new; no other epic owns it).

**Architectural weight, for the lead (Rule 20):** the second early step is a preload class that maps IPM with transactions suspended, and IPM keeps its `ERROR!` prefix. These refine AD-23's "second early step" and its "Presenting the stop" bullet without contradicting them. Recorded by the lead at the spec gate as the spine's Consistency Conventions row "IPM early step" (Rule 20 light path; AD-23's text unchanged).

## Verification

Every `[C]` command runs from the epic-15 worktree root, with `timeout: 600000`, in the foreground, one per call, and is prefixed with:

`OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=15 stage=implement' OCUTALON_RUN_TAG=e15s1i`

Each `[C]` command uses only throwaway stacks: `release/ipm-install.sh` uses its own lib-live project `ocutalon-ipm-e15s1i-*` (two fresh instances in turn), and the groups use `ci/iris.sh`'s projects. No warm stack and no slot or MCP call is needed. End with `[C] bash ci/iris.sh teardown`, also after a failure.

**Commands:**
- `bash docker/tests/test-cpf.sh` (loop) -- expected: every PASS, `exit 0`.
- `bash docker/tests/test-pinned-sources.sh` (loop) -- expected: `all checks passed`.
- `bash docker/tests/test-ci-config.sh` (loop) -- expected: exit 0 (lane-a's new job and `CHECK_SCRIPTS`).
- `[C] bash ci/iris.sh build` (loop; run it first on every pass that runs a live script) -- expected: `BUILD the web bundle is built`.
- `[C] bash release/ipm-install.sh` (loop) -- expected: `ipm-install: all checks passed`; the `OUTPUT` blocks and `TIME` lines are printed.
- `bash ci/checks.sh` (once) -- expected: no `checks: failed`.
- `[C] bash ci/iris.sh group install-fresh` (once) -- expected: pass. This is the Docker-path consumer: `install-start` plus `bundle-folder`.
- `[C] bash ci/iris.sh group install-upgrade` (once) -- expected: pass.
- `[C] bash ci/iris.sh group production` (once) -- expected: pass.
- `[C] bash ci/iris.sh group shards` (once) -- expected: pass.
- `[C] bash ci/iris.sh group image` (once) -- expected: pass.
- `[C] bash ci/iris.sh group browser` (once) -- expected: pass.
- `[C] bash release/standalone-bridge.sh` (once) -- expected: `all checks passed`.
- `[C] bash ci/iris.sh teardown` (once, last) -- expected: a `TEARDOWN tag e15s1i` line.

**Planned mutations (Rule 19; apply, see red, revert, confirm `git status --short` and `git diff --stat` unchanged, then write the `mutation:` lines here):**

| Mutation | Test that goes red | Pins |
|---|---|---|
| Move `<CPF>` below the bridge resource | `test-cpf.sh` rule 4 | manifest's first resource |
| Add `ModifyService:Name=%Service_CallIn,Enabled=1` to `src/cpf/ocutalon.cpf` | `test-cpf.sh` rules 1 and 2 | CPF check, services |
| Drop `PublicPermission=R` from both files | `test-cpf.sh` rule 3 | CPF content |
| `MapAndStop` returns `$$$OK` outside OCUTALON | `ipm-install.sh`'s first-run checks | first run |
| `MapAndStop` sets `^OcuTalonMark` in the run namespace while suspended | the repeat-run residue checks | repeat run |
| `MapAndStop` also passes `-repos` | path B's comparison | merge path |
| `MapAndStop` stops in OCUTALON too | `group install-fresh` | Docker consumer |
| Rename the preload file | `test-pinned-sources.sh` | preload resource |
| Change one character of the sentence in `MapAndStop` | `ipm-install.sh`'s final-line check | exact stop line |
| Drop the fork guard from job `ipm-install` | `test-ci-config.sh` | FR-57 job wiring |

**Mutation results (Rule 19; each applied, red observed, reverted, tree byte-identical):**
- mutation: `<CPF>` moved below the bridge resource -> `test-cpf.sh` FAIL rule 4.
- mutation: `ModifyService:Name=%Service_CallIn,Enabled=1` added to `src/cpf/ocutalon.cpf` -> `test-cpf.sh` FAIL rules 1 and 2.
- mutation: `,PublicPermission=R` dropped from both CPF files -> `test-cpf.sh` FAIL rule 3.
- mutation: `MapAndStop` returns OK outside OCUTALON -> `ipm-install.sh` FAIL on the stop check and the residue check of the first run, the repeat and the %SYS run (6 failures).
- mutation: `MapAndStop` sets `^OcuTalonMark` while suspended -> `ipm-install.sh` FAIL on the residue checks (USER `globals|1`; %SYS in the %SYS run).
- mutation: `MapAndStop` passes `-repos` -> `ipm-install.sh` FAIL on "the run in %SYS: the configuration changed" (the repeat in %SYS differs from the first run), not on path B's comparison.
- mutation: `MapAndStop` stops in OCUTALON too -> `ci/iris.sh live install-start` FAIL "row 1 the first start did not end ready within 400 s" (`group install-fresh` runs that unit first).
- mutation: preload file renamed -> `test-pinned-sources.sh` FAIL "each resource's package is in its directory below src/".
- mutation: one character of the sentence changed (`zn` to `zN`) -> `ipm-install.sh` FAIL on the stop check of all three runs.
- mutation: fork guard dropped from job `ipm-install` -> `test-ci-config.sh` FAIL `fork-guard`.
- mutation: `<Invoke ... MapAndStop ...>` line deleted from `src/module.xml` -> `test-cpf.sh` FAIL rule 5.
- mutation: `run: bash release/ipm-install.sh` line deleted from job `ipm-install` -> `test-cpf.sh` FAIL rule 6.
- mutation: `ModifyService:Name=%Service_Bindings,Enabled=1` appended to `src/cpf/ocutalon.cpf` -> `test-cpf.sh` FAIL rules 2 and 3 (rule 3 alone pins an extra line).
- mutation: `MapAndStop` skips `enable -map -ns OCUTALON` (returns OK) -> `ipm-install.sh` FAIL on "IPM answers in OCUTALON" and on the %IPM mappings of the first run (5 failures).
- mutation: path B merges a copy of the CPF file without the `IRIS.IF.*` mapping -> `ipm-install.sh` FAIL "path B: the OCUTALON view differs from path A's" (the only failure).

**Shared surfaces:**
- `src/module.xml`'s elements and their order: `test-pinned-sources.sh` `bridge_first` and `each_resource_has_its_package`, `test-compose-file.sh`'s FileCopy line, and the first `<Version>` that `docker/Dockerfile` and lib-live's `manifest_version` read.
- `ci/units.sh` `CHECK_SCRIPTS`: `test-ci-config.sh`'s units rule and `ci/checks.sh`.
- `lane-a.yml`'s `jobs:` map: `test-ci-config.sh`'s workflow rules and `has_job standalone-bridge`.
- The image's `/opt/ocutalon/src` tree: `test-build-inputs.sh`, `test-lib-live.sh` and `ci/warm.sh`'s manifest, all computed from the tree. A change to the `.cpf` or `module.xml` refuses a warm reload.
- The after-start's package load in OCUTALON, which now also runs the CPF merge and the step: every live unit that starts the image, and `release/standalone-bridge.sh`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** The package's first resource is now the CPF merge (`src/cpf/ocutalon.cpf`, the image's merge file without `%Service_CallIn`). A preload class, `OcuTalon.Install.Ipm.MapAndStop`, invoked at Initialize, After, maps IPM into OCUTALON with transactions suspended and, outside OCUTALON, stops the run with the exact next command (IPM keeps its `ERROR!` prefix). `docker/tests/test-cpf.sh` pins the CPF file, its equality with `docker/merge.cpf`, the manifest's first resource and early step, and the lane-a job. `release/ipm-install.sh` and the new lane-a job `ipm-install` prove the first run, its repeat in USER and %SYS, IPM answering in OCUTALON, and the `iris merge` alternative on throwaway stacks of a clean build 154 image.

**Files changed:**
- `src/cpf/ocutalon.cpf` (new): the CPF resource.
- `src/preload/cls/OcuTalon/Install/Ipm.cls` (new): the map-and-stop step.
- `src/module.xml`: the CPF element first, the preload resource, the Invoke.
- `docker/tests/test-cpf.sh` (new, hermetic, six rules each run first on samples) and `ci/units.sh` (`cpf` appended).
- `docker/tests/test-pinned-sources.sh`: one branch for a preload `.CLS` resource.
- `release/ipm-install.sh`, `release/ipm/Dockerfile`, `release/ipm/compose.ipm.yml` (new): the FR-57 script and its clean image.
- `.github/workflows/lane-a.yml`: job `ipm-install` appended.
- This spec: measurements, mutation lines, triage log.

**Review:** 30 findings from four layers, in 14 logged rows. Patched 6 (the CPF exactness check, rule 2's samples, a rule for the Invoke and preload resource, a rule for the lane-a job, two mutation runs with their lines, the residue wording); rejected 8 (by design, theoretical, or false) with reasons in the triage log. Deferred: none. No HIGH.

**Follow-up review recommended:** false (no HIGH, 3 MED patched, all test-side).

**Verification performed:** after the last patch, in the foreground on tag `e15s1i`: `test-cpf.sh`, `test-pinned-sources.sh`, `test-ci-config.sh`, `test-boundaries.sh` (via `bash ci/checks.sh`, all scripts passed), `ci/iris.sh build`, `release/ipm-install.sh` (all checks passed), `group install-fresh` (358 s) and `group install-upgrade` (357 s) passed, `release/standalone-bridge.sh` passed, and teardown left nothing. The handoff pass ran `group production`, `shards`, `image` and `browser` (all passed) on the same `src/`, `ci/` and `docker/` inputs; the later patches touched only `docker/tests/test-cpf.sh`, `release/ipm-install.sh` wording and the spec, so they were not run a second time. All 15 mutations (10 planned, 5 added) were applied, seen red and reverted byte-identical.

**Residual risks:** x64 timings of the new CI job and the plain IRIS image are unmeasured (inference); `group shards` takes about 673 s on the developer machine, over one tool call's cap, so split it if run again; `-dev` and `-DNoTransaction=1` runs are out of scope.

**Footprint extension (for the lead):** `src/preload/**` (new; no other epic owns it).
