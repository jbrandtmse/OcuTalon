---
title: 'Story 0.2: The package installs and upgrades itself at every start'
type: 'feature'
created: '2026-10-18'
status: 'done'
baseline_revision: 'd917978f8b680548f3bd010d94f33b8c69e03583'
baseline_commit: 'd917978f8b680548f3bd010d94f33b8c69e03583'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 0.1's image starts IRIS with OCUTALON but installs nothing: no IPM, no `ocutalon` package, no installer steps and no ready marker, so the container never turns healthy. A plain restart doesn't re-merge either (DW-1).

**Approach:** Add an after-start script, run through `iris-main --after`, that re-merges, clears readiness, installs IPM 0.10.10 from a release file in the image, version-gates and loads the one package (bridge resources first), runs the installer-step registry in AD-23's order, and writes the marker atomically. Also add:
- the registry and its step contract;
- `OcuTalon.Data.Public.Settings`, fully implemented;
- the standalone bridge installer (a stub);
- a stub for every step a later story fills.

## Boundaries & Constraints

**Always:**
- **Running the script.** It runs as the IRIS user under OS authentication and always exits 0. It stops at the first failure, logs the failing step, and leaves no marker behind (an old one included).
- **Order.** `iris merge` first (DW-1), then clear the marker and readiness, then IPM, the package, the steps, and the marker.
- **The ObjectScript part** runs in one `iris session`. `$$$` macros go only inside classes; they don't expand in terminal scripts.
- **`^OcuTalonPublic`** is reached only through `OcuTalon.Data.Public.Settings`, by every class and script, tests included. That class references only `$SYSTEM.Status` and ObjectScript functions, which AD-3's allow-list permits, so it uses `$SYSTEM.Status.Error` and never `$$$ERROR`.
- **Namespace switching.** Only `OcuTalon.Install.*` and `OcuTalon.Bridge.Installer` switch namespace, and only to `%SYS`, each class in one method with `New $NAMESPACE` (AD-3).
- **Bridge isolation.** Nothing under `src/bridge/` references another `OcuTalon` package (AD-2).
- **Upgrades** compile in place through IPM `load`. Never uninstall first (AD-13), and never use `-dev`, which turns off IPM's rollback.
- **Live runs** use a unique throwaway project each, at most one IRIS stack at a time, torn down by the test that started it (Rule 21).
- **Slot A** receives classes through `iris_doc_load` and runs tests through `iris_execute_tests`. Every call names `server: ocutalon-slot-a` and `namespace: OCUTALON`.
- **Scripts** are ASCII. The tests and `after-start.sh` run under bash 3.2 (the hermetic test runs the script on the host) and use only POSIX tools, docker, git, sed, grep and awk.

**Never:**
- **The stub steps' content** (users, web applications, SSL, `Demo`, Config Store, audit events, Telegram, `Production`): each later story fills its own (see Design Notes).
- **Other stories' scope:**
  - in `module.xml`, any `<Invoke>`, CPF resource or map-and-stop step (Epic 15);
  - `FileCopy` or a web application (0.3);
  - the purge-task declarations (1.11);
  - the online-demo keys (3.8).
- **Network and secrets:**
  - no network fetch at build or start;
  - no `docker push` or registry sign-in;
  - no `docker compose config` without `--quiet`, and no `docker inspect` without `--format`;
  - never read or print `.env`, and never print an environment value. Steps read only the variables named here (`OCUTALON_DEV`, `OCUTALON_ONLINE_DEMO` and the script's own `OCUTALON_IMAGE_VERSION`/`OCUTALON_PUBLIC_CLASSES`).
- **The judges' `docker-compose.yml` doesn't change.** No `container_name` anywhere.
- **Runtime targets:** never stop, wipe, restart or recreate `ocutalon-slot-a` or `-b`. Nothing comes from `irislib/` or `irissys/`.

## I/O & Edge-Case Matrix

Where each row runs:
- `test-install-start.sh` (live): rows 1–5;
- `test-install-upgrade.sh` (live): rows 6 and 7;
- `test-after-start.sh` (hermetic, with a fake `iris` on `PATH`): rows 8–10, plus row 7's shell side;
- `%UnitTest` on slot A: rows 11 and 12.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Fresh volume | first `up` | Docker reports `healthy`; the marker equals `/opt/ocutalon/version`. The log shows, in order: merge, the readiness step (nothing to clear on a fresh volume), IPM 0.10.10 installed in `%SYS` and mapped into OCUTALON only, package loaded (`not installed`), one `STEP` line per Design Notes order entry (the test writes the expected order out itself, never reading `Order()`), `RESULT OK`. `Get("ready")` is `1` and `Get("onlineDemo")` is `0` | none |
| 2 Same version, mapping removed by hand | `Config.MapGlobals` entry `IRIS.IF.*` deleted, data and private probes set, then stop and start | the mapping is back (DW-1); package `skipped`, so the compile time of `OcuTalon.Install.Registry` is unchanged; every step runs again; probes intact; healthy | none |
| 3 Dev reload | recreate with `docker-compose.dev.yml` (`OCUTALON_DEV=1`) | package loaded (`dev`), compile time changed, healthy | none |
| 4 Hidden public class | `OcuTalon.Data.Public.Settings` deleted from OCUTALON, then restart | load forced (`public classes`); the class is compiled again and resolves to `OCUTALON_PUBLIC`; healthy | none |
| 5 Bridge alone | in the running stack, a fresh Interoperability namespace `OCUBRIDGET` with no IPM; `LoadDir` of `/opt/ocutalon/src/bridge/cls`, then `OcuTalon.Bridge.Installer.Run()` | both return 1. The namespace holds no `OcuTalon` class outside `.Bridge` and `.BridgeExample`, and no `%IPM` | test fails |
| 6 Upgrade in place | probes set under V0, recreate with an image whose version is V0 plus one patch | installed and marker equal the new version; every step ran again; probes intact | none |
| 7 Step fails | an image (V0 plus one patch) whose `Step.SSL.Run` returns an error | the log names `SSL` as failed, and no later step ran. No marker, `Get("ready")` empty, container running with `RestartCount` 0, status never `healthy`. A next good image (plus two patches) reaches ready | logged |
| 8 Merge fails | fake `iris merge` exits 7; an old marker is present | exit 0, marker removed, no session started, log names `merge` | logged |
| 9 Session gives no result | fake session prints no `RESULT` line, or exits non-zero | exit 0, no marker, log names `session` | logged |
| 10 Other version | session prints `RESULT OK 9.9.9` | exit 0, no marker | logged |
| 11 Refused key | `Set("nosuch","x")`, `Set("ready",1)`, `Get("nosuch",.sc)` | error status naming the key; nothing stored; `Get` returns `""` | caller sees `%Status` |
| 12 `NextReset(now)` | anchor `2026-10-18T00:00:00Z`, interval `4` | now 17T23:00 gives 18T00:00; now 18T00:00 gives 18T04:00; now 18T05:30 gives 18T08:00; now 19T23:59:59 gives 20T00:00. No anchor, or an interval that is empty, `0` or not a number, gives `""` | none |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), read by range:
  - AD-2 L108–119, AD-3 L121–148, AD-5 L174–183, AD-13 L357, AD-19 L473–513, AD-23 L593–636, AD-27 L732–740, AD-29 L752–766;
  - ownership L995–1059, source tree L1119–1143, S1/S16/S19 L1197, L1212, L1215.
- **Epics** (`epics.md`): this story L782–816; the purge tasks, Story 1.11, L1319–1336; the `Public` step's online-demo writes, Story 3.8, L1972–1990.
- **S1 prior art** (read-only, outside the repo), under `../spikes/install/`:
  - `scripts/after-start.sh`: marker through a tmp file and `mv`, always `exit 0`;
  - `scripts/install.cos`: the one-liner pattern;
    - IPM: `%IPM.Storage.Module.NameOpen("zpm").VersionString`, then `$SYSTEM.OBJ.Load(file,"ck-d")`;
    - mapping: `Config.MapPackages.Exists("OCUTALON","%IPM")`, then `%IPM.Main.Shell("enable -map -ns OCUTALON -q")`;
    - package: `Shell("load <dir>")`, then `RESULT OK <v>`;
  - `Dockerfile`: `CMD ["--after", ...]`;
  - `spike-app/module.xml`: `<SourcesRoot>.</SourcesRoot>`, one `<Resource Name="X.PKG" Directory="bridge/cls"/>` per package;
  - `scratch/overlap/module.xml`: `OcuSpikeOv.Bridge.PKG` and then `OcuSpikeOv.PKG` together load correctly, which is this story's layout.
- **IPM 0.10.10** (`../spikes/install/ref/ipm-src/`, tag v0.10.10):
  - `Shell()` returns `%Status` (`Main.cls:838`);
  - `load` reruns the whole lifecycle even for the same version, refuses a downgrade, and is rolled back on error outside `-dev` (`Utils/Module.cls:1171, 1192, 1315`);
  - `enable -map -ns` adds a package mapping `%IPM` and a routine mapping `%IPM.*`; installing the release file maps nothing outside `%SYS` (`Main.cls:3617`, `preload/cls/IPM/Installer.cls:27`);
  - IPM adds a package mapping for any resource whose package isn't in the namespace's routine database. `OcuTalon` and `OcuTalon.Bridge` are, so none is added; if one appears, load with `-DNoMapping=1`;
  - a semver prerelease sorts lower, so upgrade tests bump the patch number.
- **IRIS APIs:**
  - `%SYS.Namespace.GetRoutineDest(ns, routine, type)` and `GetPackageDest`, at `irislib/%SYS/Namespace.cls:116, 141`. They return `system^dir`, for example `^/durable/iris/mgr/ocutalon_public/`. Compare with `Config.Databases` in `%SYS`; IPM's own way is `DatabasesByDirectory` (ipm `Utils/Build.cls:553`).
  - `%SYS.Task`: `FindId(name)`, then `%New()` and `%Save()`. The codes are in `irislib/%syTask.inc:64–73`. Task settings are stored as `$lb` pairs and set with `AssignSettings`. `%SYS.Task.Definition` provides `OnTask()` and `TaskName` (`irislib/%SYS/Task/Definition.cls:21, 38`).
  - `Security.Roles` `Create`, `Modify` (`Resources` given as `"R:RW,S:U"`) and `Exists`, in `%SYS`, at `irissys/Security/Roles.cls:107, 259, 141`.
  - Subclasses: `$$GetAllDerivedClasses^%occLibrary`, plus the `Abstract` flag (`irislib/%AI/Catalog.cls:113–120`). A class and a package can share a name: `%SYS.Task` and `%SYS.Task.*` both exist.
  - `$SYSTEM.OBJ.LoadDir(dir,"ck-d",.err,1)` (`irislib/%SYSTEM/OBJ.cls:165`).
  - UTC ISO 8601 without zone conversion: `$TR($ZDT($ZTS,3,1)," ","T")_"Z"`, and back with `$ZDTH($TR($E(s,1,19),"T"," "),3,1)`. Never pass `$ZTS` to tformat 7.
- **Base-image probe (October 18):**
  - `iris-main` runs the `--after` command to completion and only then does its own `Files differ; merging` or `unchanged; skipping` and the `*.last_merge` copy.
  - `iris merge IRIS <file>` exits 0 on success and 7 when an action fails (`ERROR #503`, `#507` and `#520` at severity 1), and it logs `Merging <file> into ...` in `messages.log`.
  - `iris session IRIS -U %SYS` works inside `--after`.
- **Story 0.1 tests this story must update (Rule 19):**
  - `docker/tests/test-build-inputs.sh` L37–61: the COPY parsing doesn't expand a directory source or create decoy parents, and the `src/other.xml` decoy becomes legitimate;
  - `test-compose-file.sh`: L128–134, the exact `.dockerignore` list; L115–121, `files_keep_lf`; no check yet for `CMD`;
  - `test-compose-start.sh`:
    - L397–416, row 8's build directory, which lacks the new COPY sources;
    - L420–430, the `/opt/ocutalon` owners and modes (`module.xml` moves into `src/`);
    - row 7 and the `Merging` counts assume that nothing writes the marker;
  - `test-boundaries.sh` L82: it scans only `src/module.xml`.
- **IPM release file:** `../spikes/install/ipm/zpm-0.10.10.xml`, 1,593,780 bytes, sha256 `daa2adabd66b488f57187d29712e54b0c25bbe000794fbf2a35a882c458b788a`, ASCII, with no boundary-rule hit. Its licence is `../spikes/install/ref/ipm-src/LICENSE`: MIT, "Copyright (c) 2019 InterSystems Developer Community", sha256 `ad94a204521dfec7db27a44bd068e33d7f889cd2e4352f68bbb790b2291c888f`.

## Tasks & Acceptance

**Execution:**
- `docker/ipm/zpm-0.10.10.xml`, `docker/ipm/LICENSE` -- byte-identical copies of the two files above -- the pinned IPM Stack row, with its licence notice kept.
- `src/module.xml` -- add `<SourcesRoot>.</SourcesRoot>`, then `<Resource Name="OcuTalon.Bridge.PKG" Directory="bridge/cls"/>`, then `<Resource Name="OcuTalon.PKG" Directory="ocutalon/cls"/>`. `<Version>0.1.0</Version>` stays the first `<Version>` -- AD-2.
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls` -- `ClassMethod Run() As %Status`. It returns an error naming the namespace when that namespace isn't an Interoperability namespace (`%EnsembleMgr.IsEnsembleNamespace()`), and `$$$OK` otherwise. It holds nothing else yet -- AD-2.
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- the accessor:
  - `Get(key, Output sc) As %String`, for the fixed keys and `ready`;
  - `Set(key, value) As %Status`, for the fixed keys only (`ready` is refused); `""` removes the key;
  - `ClearReady()`, `SetReady()` (stores `1`) and `NextReset(now="") As %String`, as in row 12;
  - storage in `^OcuTalonPublic(key)`, no defaults applied, and the key list in a parameter.
  - AD-19.
- `src/ocutalon/cls/OcuTalon/Install/Step.cls` -- the abstract step contract, with do-nothing defaults: `Run() As %Status`, `Grants() As %DynamicArray`, `Reconcile() As %Status`, `Tasks() As %DynamicArray` and `Purge(daysToKeep As %Integer) As %Status` -- AD-23.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls` --
  - `Order()`, the fixed list in Design Notes;
  - `Areas()`, every compiled, non-abstract subclass of `OcuTalon.Install.Step` named `OcuTalon.Install.Step.*`, sorted by name;
  - `Run(caller) As %Status`, which refuses any namespace but OCUTALON, runs the order, writes `STEP <name> OK <s>s` or `STEP <name> FAILED <text>` for each step, and stops at the first failure;
  - `Purge(days)`, which calls every area's `Purge` and combines the failures.
- `src/ocutalon/cls/OcuTalon/Install/Step/` -- the steps listed in Design Notes:
  - `Public.cls`: `Run` sets `onlineDemo` to 1 when `OCUTALON_ONLINE_DEMO` is `1`, else 0; `Ready()` calls `SetReady`.
  - `Roles.cls`: composes roles from every area's `Grants()`. Per role it takes the union of permissions and creates the role, or modifies it to exactly that set. A role name that doesn't start with `OcuTalon` fails the step, naming the area.
  - `Tasks.cls`: for every area's `Tasks()` entry, creates the task in OCUTALON when `FindId(name)` is empty and leaves an existing task alone. A name that doesn't start with `OcuTalon`, or a duplicate name, fails the step.
  - `Reconcile.cls`: calls every area's `Reconcile()`.
  - `PrivateData.cls`: confirms that a sample name under each of the four private mappings (`OcuTalonP.Zz`, `OcuTalonBP.Zz`, `AI.Agent.SessionD`, `IRIS.IF.Zz`) and every `^OcuTalonP.`/`^OcuTalonBP.` storage global of a compiled `OcuTalon` class resolve to `OCUTALON_PRIVATE`, and that `OCUTALON_DATA` holds no global with a private prefix (`OcuTalonP.`, `OcuTalonBP.`, `AI.Agent.Session`, `IRIS.IF.`). It fails naming the first offender.
  - `Users`, `Web`, `SSL`, `Demo`, `Provider`, `Audit`, `Telegram` and `Production`: stubs whose `Run` returns `$$$OK`.
  - AD-19, AD-23, AD-24.
- `src/ocutalon/cls/OcuTalon/Install/Task/Purge.cls` -- a `%SYS.Task.Definition` with `TaskName` "OcuTalon purge" and `Property DaysToKeep As %Integer [ InitialExpression = 90 ]`. `OnTask()` returns `Registry.Purge(..DaysToKeep)` -- AD-27. Story 1.11 declares it in a `Tasks()` and adds `Bridge.Purge`.
- `docker/after-start.sh` -- the shell side, in this order:
  1. `iris merge IRIS "$merge"`;
  2. `rm` the marker and any stale tmp files;
  3. export `OCUTALON_IMAGE_VERSION` (from the version file) and `OCUTALON_PUBLIC_CLASSES` (class names derived from the `.cls` files under the image's `OcuTalon/{Web,Data}/Public/`);
  4. one `iris session IRIS -U %SYS < "$cos"`;
  5. the marker, only on `RESULT OK <image version>`: a tmp file in the marker's directory, then `mv`.

  The run's log is rewritten each start at `/durable/ocutalon-after-start.log`, and a one-line summary per step goes to stdout. The paths can be overridden only for the hermetic test (`OCUTALON_READY_MARKER`, `OCUTALON_VERSION_FILE`, `OCUTALON_MERGE_FILE`, `OCUTALON_SRC_DIR`, `OCUTALON_SESSION_SCRIPT`, `OCUTALON_AFTER_START_LOG`). Always `exit 0`. Use no `set -x`, `env` or other output of the environment -- AD-23, DW-1.
- `docker/after-start.cos` -- one guarded one-liner per phase, each printing a `STEP` line:
  1. in OCUTALON, `ClearReady()` when `OcuTalon.Data.Public.Settings` is compiled;
  2. in `%SYS`, install IPM when it is missing or older than 0.10.10;
  3. map IPM when `%IPM` isn't mapped into OCUTALON;
  4. check each public class: compiled, and its routine (`GetRoutineDest`) in the `OCUTALON_PUBLIC` directory;
  5. `load /opt/ocutalon/src` when the installed `ocutalon` version differs from the image's, `OCUTALON_DEV` is `1`, or step 4 failed (log the reason), then confirm the installed version equals the image's;
  6. `Registry.Run("after-start")`;
  7. `RESULT OK <installed version>`.

  Later lines are skipped once a step has failed.
- `docker/Dockerfile` --
  - COPY `src/` to `/opt/ocutalon/src/`, `docker/ipm/` to `/opt/ocutalon/ipm/`, and `merge.cpf`, `healthcheck.sh`, `after-start.sh` and `after-start.cos` to `/opt/ocutalon/`;
  - take the version from `/opt/ocutalon/src/module.xml`, keeping the empty-version failure;
  - make everything root-owned and read-only (files 444; directories, `healthcheck.sh` and `after-start.sh` 555);
  - add `CMD ["--after", "/opt/ocutalon/after-start.sh"]`.
- `.dockerignore`, `.gitattributes` -- the allow-list gains `src` (all of it), the two scripts and the two `docker/ipm/` files. Add `src/** text eol=lf`.
- `docker-compose.dev.yml` -- `name: ocutalon-dev` and `services.iris.environment.OCUTALON_DEV: "1"`, nothing else. It is used with `-f docker-compose.yml -f docker-compose.dev.yml`.
- `docker/tests/lib-live.sh` -- move the live helpers out of `test-compose-start.sh` (`dc`, `iris_script` with its retry, the deadline and waits, `merge_count`/`merge_errors`, the teardown trap). Add `copy_build_context <dir>` (the Dockerfile's COPY sources, directories expanded) and `wait_started_ready`, which waits for this start's log end line and then Docker's `healthy`. It must never accept a previous start's log or health, so either remove the log before each stop or match a start stamp the script writes on its first line. The three live tests source it -- Rule 2.
- `docker/tests/compose.no-after-start.yml`, `docker/tests/test-compose-start.sh` --
  - the override replaces the CMD so that no after-start script runs, which keeps 0.1's rows (no marker gives `starting`, and the `Merging` counts) valid;
  - row 8 builds from `copy_build_context`;
  - the owner and mode list follows the new `/opt/ocutalon` layout.
- `docker/tests/test-compose-file.sh`, `test-build-inputs.sh`, `test-boundaries.sh` --
  - pin the new allow-list, the LF rule for the new files, `CMD`, and the dev file (`name: ocutalon-dev`, `OCUTALON_DEV` "1", no mock, no `container_name`, `config --quiet` passing with both files);
  - expand directory COPY sources;
  - scan all of `src` and `docker-compose.dev.yml`.
- `docker/tests/test-after-start.sh` -- rows 8–10, plus:
  - row 7's shell side: a `STEP SSL FAILED` transcript leaves no marker and the log names `SSL`;
  - the success path: marker written through a tmp file, none left over;
  - order: merge before session, as seen by the fake `iris`.

  Its own fake `iris` is a copy (see Design Notes, Reuse).
- `docker/tests/test-install-start.sh`, `docker/tests/test-install-upgrade.sh` -- the live matrix rows, each with a unique `-p ocutalon-t02{s,u}-<epoch>-$$`, a 540 s deadline and an EXIT trap that runs `down -v --rmi local`. Upgrade images are built from `copy_build_context` with the version bumped (and, for row 7, `SSL.cls` replaced) through an override with an absolute temporary build context.
- `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/PrivateData.cls` -- the `%UnitTest` classes for rows 11–12 and the ACs below. Each saves and restores every public key it touches through the accessor. The fixture area is created and compiled in `OnBeforeAllTests` and deleted with its role, its task and its `^OcuTalonTest` nodes in `OnAfterAllTests`.

**Acceptance Criteria:**
- Given a fixture class `OcuTalon.Install.Step.ZzFixture<n>` created by the test, when `Areas()`, the `Roles`, `Tasks` and `Reconcile` steps and the purge task's `OnTask` run, then:
  - the fixture is discovered, and the abstract base and an `OcuTalon.Install.Step` subclass outside that package are not;
  - its declared role holds exactly its declared resources;
  - its task (declared `Suspended`, so it never runs) exists once with the declared schedule and `DaysToKeep`, and a second run leaves a changed `DailyStartTime` and `DaysToKeep` alone;
  - its `Reconcile` runs once per run;
  - its `Purge` receives the task's `DaysToKeep` (`OcuTalon.Test.Install.Registry`).
- Given OCUTALON with its mappings, when `Step.PrivateData` runs, then it passes, and with `^OcuTalonP.ZzPlanted` written straight into `OCUTALON_DATA` it fails naming that global (`OcuTalon.Test.Install.PrivateData`).
- Given the accessor, when a fixed key is set, read, removed with `""`, and readiness is cleared and set, then each read returns what was stored, and the `Public` step writes `onlineDemo` 0 without `OCUTALON_ONLINE_DEMO` (`OcuTalon.Test.Data.PublicSettings`).
- Given Story 0.1's tests, when they run against this story's tree, then all five pass with only the updates named above, and the judges' `docker-compose.yml` is byte-identical to its committed version.

### Review Findings

Code review 2026-10-18 (four layers, all at the session's tier). 39 rows from the layers plus 1 reviewer row; 15 entries survive triage: 0 high, 2 med, 13 low. Each entry lists severity / fix-risk / footprint / spec-status (Rule 15).

- [x] [Review][Patch] A same-version restart can report `healthy` from the previous start's marker. The script dropped the marker only after `iris merge`, so a probe during the merge saw IRIS running and the old marker; a failed step then stayed `healthy` for about 30 s (3 probes), and `up --wait` could return before the steps ran. The epic's AC says the script "first deletes the ready marker". Fix: `drop_marker` before the merge, and `--before "rm -f /durable/ocutalon.ready"` in the CMD, so the marker is gone before IRIS can report running. The merge still precedes every install step (DW-1). [docker/after-start.sh:37-58, docker/Dockerfile:26] — med / low (two moved lines and one CMD argument; live-verified) / in-story / clear (spec Order line to be reworded by the lead)
- [x] [Review][Patch] `src/** text eol=lf` forces text handling onto every file under `src/`, including the committed web bundle the spine puts at `src/ocutalon/csp/` (a PNG's signature holds CRLF), so a binary is corrupted on commit. Fix: `text=auto eol=lf`, which keeps LF for every text file, like `docker/**`. [.gitattributes:5] — med / low / in-story / clear (spec intent, LF, kept)
- [x] [Review][Patch] Two failure paths do not name their cause. A failed `mktemp -d` was reported as "could not copy" the merge file, and a failed transcript `mktemp` ended with no `STEP` line. [docker/after-start.sh:40,78] — low / low / in-story / clear
- [x] [Review][Patch] The two QA test scripts are mode 644, unlike every other `test-*.sh` (755). [docker/tests/test-lib-live.sh, docker/tests/test-pinned-sources.sh] — low / low / in-story / clear
- [x] [Review][Patch] The two QA test scripts are missing from `## Verification` commands. [spec ## Verification] — low / low / in-story / clear
- [x] [Review][Patch] The image-mode check rejects a zero-byte file under `src/`, because GNU `stat` prints `regular empty file`. [docker/tests/test-compose-start.sh:301,305] — low / low / in-story / clear
- [x] [Review][Patch] The dev compose file's header does not say that it is its own project, with its own volume and the same web port. [docker-compose.dev.yml:1-2] — low / low / in-story / clear
- [x] [Review][Patch] The header of `test-pinned-sources.sh` claims that every checker runs on breaking and keeping samples; only some do (Rule 14). [docker/tests/test-pinned-sources.sh:8-9] — low / low / in-story / clear
- [x] [Review][Patch] No test makes `PrivateData`'s storage-global confirmation fail: `Run()` could stop passing the storage globals to `Check` and stay green. [src/ocutalon/cls/OcuTalon/Test/Install/PrivateData.cls] — low / low / in-story / clear
- [x] [Review][Patch] The IPM "older than 0.10.10" branch of the session has no test. [docker/tests/test-install-start.sh row 2] — low / low / in-story / clear
- [x] [Review][Patch] `TestRoleNameRefused`'s "no role was created" cannot fail: the refused area sorts before the only area with grants, so nothing was composed before the refusal. [src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:111-121] — low / low / in-story / clear
- [x] [Review][Patch] `TestRefusedKeys` labels an assertion "nothing was stored under the unknown key", which a refusing `Get` cannot observe; relabel it to what it checks. [src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls:54-64] — low / low / in-story / clear
- [x] [Review][Patch] `TestMappingMismatchFails` relies on namespace `USER`; `%SYS` always exists and never maps the private globals. [src/ocutalon/cls/OcuTalon/Test/Install/PrivateData.cls:80] — low / low / in-story / clear
- [x] [Review][Patch] `wait_started_ready` accepted a start that ended `not ready` while Docker still reported `healthy`. Row 4's intermediate wait has no log check after it. [docker/tests/lib-live.sh:145-152] — low / low / in-story / clear
- [x] [Review][Patch] Rule 2: `marker()` is copied in both live install tests; it belongs in `lib-live.sh` with the other shared helpers. [docker/tests/test-install-start.sh:31, docker/tests/test-install-upgrade.sh:23] — low / low / in-story / clear

All 15 were applied in the review pass (mutations and runs are under `## Verification`, "Code review additions"). For the lead, text that now trails the code:
- the intent's **Order** line and the Tasks list for `after-start.sh` still say "`iris merge` first, then `rm` the marker": the code now deletes the marker first (in the CMD's `--before` and again at the script's top), then merges, then clears readiness in the session. This matches the epic's AC ("first deletes the ready marker") and AD-23's numbered step 1, and keeps DW-1's merge before every install step;
- the Tasks line `src/** text eol=lf` is now `text=auto eol=lf`, which keeps LF for every text file;
- AD-23's DW-1 sentence: the copy keeps its intent. Verified live: `iris merge IRIS /opt/ocutalon/merge.cpf` logs `unchanged; skipping` and leaves a hand-removed `IRIS.IF.*` mapping missing, while the copy (in the container's `/tmp`, created by `mktemp -d`, owned by the IRIS user, byte-identical by `cp`, removed right after the merge) restores it, and `/durable/iris` keeps one `*.last_merge` record across starts.

Rejected:
- `false` — `*.last_merge` records pile up because the copy is merged from a new path at every start (blind, edge, verification-gap, auditor). A live probe found exactly one record, `^opt^ocutalon^merge.cpf.last_merge`, after a first start and two restarts and after merging a fixed-path copy: `iris merge` writes no record for the path it merges.
- `false` — the three `%UnitTest` classes have no executed host (verification-gap). They run on slot A through the spec's `(loop)` `iris_execute_tests` commands; CI wiring is Story 0.7's AC.
- `false` — a compose `command:` override drops the after-start script (edge). The spec mandates `CMD`, the judges' file sets no command, and the override is the documented test seam (`compose.no-after-start.yml`).
- `low` — the Roles step keys role names case-sensitively, while IRIS does not (blind, edge). It needs two areas to spell one role in different case, and the fix adds normalization. reopen_if: two `Grants()` spell one role differently.
- `low` — a downgrade (an older image on the volume) never becomes ready (blind, edge). It fails loudly with IPM's refusal under `STEP package FAILED`, no downgrade is promised, and the fix adds a branch.
- `low` — `Declared` accepts a `%DynamicObject` whose values are objects (blind). Theoretical: a string or a flat object already errors naming the area.
- `low` — the IPM load's success is not read back (edge). Theoretical: the file is pinned by sha256, and `ipm-map` calls `%IPM.Main` next.
- `maybe-false` — a container killed mid-load leaves half-compiled code (edge). IPM's load runs in a transaction rolled back at recovery; if it happened, later steps fail loudly and `OCUTALON_DEV=1` recovers. Settle with a kill -9 during a live upgrade.
- `low` — roles no longer declared keep their grants (edge). Theoretical: no version removes a role yet.
- `low` — `iris_script` and `dc exec` have no per-call time limit (edge). No hang was shown, and a portable timeout needs a tool macOS lacks.
- `low` — readiness stays `1` when the merge fails (edge, auditor). Spec-bound: row 8 starts no session after a failed merge, and readiness is cleared only through the accessor in the session.
- `low` — the dev file publishes the same host port (edge). Spec-bound: the file holds only the name and `OCUTALON_DEV` (pinned); the header now says so.
- `low` — AD-23's DW-1 sentence names the image's file, not the copy (auditor). The fix edits the spine, which is the lead's at story commit (Rule 20). The intent is kept: verified live that a direct merge of the image's file is skipped (`unchanged; skipping`) and the copy repairs the mapping.
- `low` — no install check confirms where `^OcuTalonPublic` resolves (auditor). Story 0.1's live test pins its destination, the merge recreates the mapping at every start, and Story 15.2's AC adds it to the install checks.
- `low` — row 1's "mapped into OCUTALON only" checks only `USER` (auditor). Row 5 catches a `%ALL` mapping; the Health image's HS namespaces map `%IPM` themselves (residual risk noted).
- `low` — a source scan for namespace switching would flag the test fixture's XData (auditor). Theoretical until Story 0.7 designs that check.
- `low` — `sha256sum`/`shasum` are outside the script tool list (auditor). The Stack row's pin needs a digest, and the script falls back between the two hosts' tools.

## Spec Change Log

### 2026-10-19 -- As built, after code review (lead)
- Order: the image's `CMD` deletes the marker with `iris-main --before`, before IRIS starts, and `after-start.sh` deletes it again at its top; then the merge (DW-1), readiness, IPM, package, steps, marker. The intent's "`iris merge` first, then clear the marker" is superseded by this order, which also matches the epic's "first deletes the ready marker".
- The merge runs on a fresh temporary copy of the image's merge file, because build 154's `iris merge` skips a path whose `*.last_merge` record is unchanged.
- `.gitattributes` uses `src/** text=auto eol=lf`, not `text eol=lf`, so committed binaries under `src/` stay intact.
- AD-23 now records all three, plus the step contract this spec fixed under Design Notes.

## Review Triage Log

### 2026-10-18 — Review pass
- verdicts: 56 findings — high 0, medium 2, low 49, false 5, maybe-false 0
- findings:
  - Blind Hunter (10):
    - `[low]` `[reject]` Two failure paths lose their cause on stdout (the registry's refusal outside OCUTALON, the merge output) — the cause is in `/durable/ocutalon-after-start.log` (the log contract); the refusal is unreachable because phase 4 enters OCUTALON; the fix adds output paths.
    - `[low]` `[reject]` The `iris session` run has no time limit — no hang was shown for this story's steps (all return at once); a guard needs `timeout`, which is not POSIX (macOS hosts run the hermetic test); later steps that wait (Story 0.6) own their timeouts.
    - `[false]` `[reject]` The version gate is untested against a failed package load — AD-23 records that IPM rolls a failed load back (S1 tested a compile failure), so the next start sees the old version and loads again.
    - `[low]` `[patch]` The shared 540 s deadline can cut row 7's 40 s watch short and still pass — the watch now has to run its full 40 s (`test-install-upgrade.sh`); the deadline itself is the spec's.
    - `[low]` `[reject]` The purge task does not validate `DaysToKeep` — an admin-only input, and the spec has `OnTask` pass the value on; each area's `Purge` (Story 1.11) owns what a value means; a guard is added behaviour the spec does not ask for.
    - `[low]` `[reject]` The pinned IPM release has no provenance or checksum test — the file is byte-identical to the spike's (sha256 checked at review, no CR bytes, so `eol=lf` leaves it alone); Story 10.2's README carries the notice.
    - `[low]` `[reject]` The `ipm-map` phase ignores the status of `Config.Databases.Get` — the database exists whenever the merge succeeded, and a merge failure stops the run earlier; the check would only reword a message.
    - `[low]` `[reject]` Test classes ship in `OcuTalon.PKG` and a dead test run could leave a fixture area — the spec puts the tests under `src/ocutalon/cls/OcuTalon/Test/`; the fixtures exist only while a test runs, and `Clean()` removes leftovers at the next run.
    - `[low]` `[reject]` Negative-path unit tests are missing (`Registry.Run`, `Declared`, `Tasks.Check`, `Roles.Add`) — the acceptance criteria name the prefix and duplicate checks, which are tested; stop-at-first-failure of `Registry.Run` is pinned live by row 7; the rest are guards beyond the spec.
    - `[low]` `[reject]` `OCUTALON_ONLINE_DEMO` is not in `.env.example` — the judges' compose file does not pass it, and the online-demo keys belong to Story 3.8.
  - Edge Case Hunter (12):
    - `[low]` `[reject]` Early finishes do not clear readiness — row 8 says no session starts after a failed merge, so nothing can clear it there.
    - `[low]` `[reject]` `Areas()` ignores an error from `GetAllDerivedClasses` — the call does not fail for a compiled class; theoretical.
    - `[low]` `[reject]` `NextReset` throws for an interval that carries the next slot past year 9999 — the interval comes from the `Public` step's configuration (Story 3.8); the fix adds a guard for a value no one sets.
    - `[low]` `[reject]` A package reload for a misplaced public class has no re-check — the spec's phase 5 only confirms the version; row 4 pins the class's destination after the reload.
    - `[low]` `[reject]` `Registry.Run`'s refusal prints no `STEP` line — the same finding as the first Blind Hunter row.
    - `[false]` `[reject]` `iris merge` can exit 0 after a failed action — the base-image probe (Code Map) records exit 7 for a failed action.
    - `[low]` `[reject]` `Config.Databases.Get` status is ignored — the same finding as the Blind Hunter row.
    - `[low]` `[reject]` `DaysToKeep` is not validated — the same finding as the Blind Hunter row.
    - `[low]` `[reject]` The session has no timeout — the same finding as the Blind Hunter row.
    - `[low]` `[reject]` A time with an offset or no `Z` is read as UTC — the contract says times are UTC with `Z`, and the writer is Story 3.8.
    - `[false]` `[reject]` `Step.Tasks` has no OCUTALON guard — `Registry.Run` refuses any other namespace, and the step is reached only through it.
    - `[low]` `[reject]` `PrivateData` reads only the data, index, id and stream locations — a class with SQL map storage does not exist in the product, and the spec names "storage globals".
  - Verification Gap Reviewer (7, then 14 other findings):
    - `[medium]` `[patch]` The Reconcile and Purge "other areas still ran" assertions cannot fail (the failing fixture sorted last) — the failing fixture is now `ZzBad<n>`, which sorts before `ZzFixture<n>`; mutation recorded (`Quit` after the first failure).
    - `[low]` `[reject]` `TestRefusedKeys` reads "nothing stored" through the refusing accessor — the intent has every class and script, tests included, reach `^OcuTalonPublic` only through `Settings`, so a direct read would break that rule.
    - `[medium]` `[patch]` The mapping confirmations of `PrivateData` never run in the failing direction — `TestMappingMismatchFails` runs the check through a runtime subclass against namespace `USER`; mutation recorded.
    - `[low]` `[patch]` The prefix filter of `StorageGlobals` is unpinned — a second fixture class with a global that is not private is asserted absent; mutation recorded.
    - `[low]` `[reject]` The "resolves to" branch of the public-class check has no test — after the merge restores the mappings the branch is close to unreachable, and a live test needs mapping changes outside the matrix.
    - `[low]` `[patch]` The marker-write failure leg is unpinned — `test-after-start.sh` gains four checks with an unwritable marker directory; mutation recorded.
    - `[low]` `[reject]` The three `%UnitTest` classes have no executed host in the repo — the intent runs rows 11 and 12 as `%UnitTest` on slot A; the CI host is Story 0.7.
    - `[low]` `[patch]` AC 3 has no `mutation:` line — three lines written, each demonstrated red and reverted.
    - `[low]` `[patch]` AC 4 has no `mutation:` line — one line written (`!src` dropped from `.dockerignore`), demonstrated red in two tests and reverted.
    - `[low]` `[reject]` Some AC 1 bullets have no line of their own — one demonstrated mutation per AC is the bar; AC 1 now has three.
    - `[low]` `[reject]` Row 7's Docker side (`Quit` after a failed step, `exit 0`) has no line — the spec's mutation for rows 7 and 9 is the marker without a `RESULT` line, recorded for both tests.
    - `[low]` `[reject]` Row 8's `drop_marker` has no line — one mutation per row, and the spec's mutation for rows 2 and 8 is recorded.
    - `[low]` `[reject]` Row 9's `session_rc` check has no line — the reviewer confirmed the test catches it; one mutation per row is recorded.
    - `[low]` `[reject]` Row 12's other legs have no line — one mutation per row is recorded.
    - `[low]` `[reject]` Row 11's store-before-refuse variant has no line — the same finding as the second Verification Gap row.
    - `[low]` `[reject]` `TestPublicStep` skips when `OCUTALON_ONLINE_DEMO` is 1, and the flag-on branch is untested — AC 3 names the flag-off case; the flag-on values belong to Story 3.8.
    - `[low]` `[patch]` `TestFixedKeysRoundTrip` takes its keys from the class under test — it now asserts the contract's list of thirteen; mutation recorded.
    - `[low]` `[patch]` Row 3's compile-time check has no guard for an empty "before" value — the guard is added.
    - `[low]` `[reject]` `Clean()` resets the fixture counter — the number is always 1, which is harmless: the tests create and remove their own fixtures.
    - `[low]` `[reject]` A killed run leaves readiness cleared on the instance it ran against — the tests run on slot A and throwaway stacks only.
    - `[low]` `[reject]` On a same-version restart the old marker stays valid while the merge runs — the spec's order (merge, then clear the marker and readiness) and AD-23 put it there; recorded as a residual risk.
  - Intent Alignment Auditor (13 divergences):
    - `[low]` `[reject]` Row 7's `RestartCount` 0 holds trivially under the throwaway override's `restart: "no"`, and "never healthy" is watched for 40 s inside the 600 s start period — the `Running` check catches an exit; the throwaway override is Story 0.1's.
    - `[low]` `[reject]` The flag-on path of the `Public` step has no assertion — the same finding as the Verification Gap row.
    - `[low]` `[patch]` No test observes the STEP summary in the container's output — `test-install-start.sh` row 1 now checks `docker logs`; it passes.
    - `[low]` `[reject]` `after-start.cos` and `Registry.Run`'s refusal run only in the live tests — the matrix places them there.
    - `[false]` `[reject]` The script has six path overrides and the intent names four — the spec's Tasks list names all six.
    - `[low]` `[reject]` Slot A compiles the classes directly, not through IPM — the spec's Verification says so, and rows 1–7 run the IPM path live.
    - `[low]` `[reject]` A stale `ready` stays when the accessor class is missing and a later step fails — the spec and AD-23 clear readiness only when the class exists; the case needs a deleted class and a failing step together.
    - `[low]` `[reject]` Rows 6 and 7 are chained, so the failing image is V0 plus two — the semantics are the same: a failing image newer than the installed one.
    - `[low]` `[reject]` Story 0.1's live test runs with `--after /bin/true` — the spec's Tasks list asks for that override.
    - `[low]` `[reject]` The dev file's `name:` is checked statically, since live rows use `-p` — the spec's Tasks list asks for the static checks.
    - `[low]` `[reject]` Network and ASCII rules are checked by text scans only — that is `test-boundaries.sh`'s design from Story 0.1.
    - `[false]` `[reject]` The session script prints environment values — it prints the image version, the script's own variable that the spec names and that the `RESULT` contract carries.
    - `[low]` `[reject]` `mktemp` is not POSIX — Story 0.1's tests already use it, and it exists on macOS and Linux.

## Design Notes

**ADs:**
- AD-2: one package, bridge first; the bridge loads alone.
- AD-3: namespace switching; the public package allow-list.
- AD-5: only code is replaced.
- AD-13: upgrades compile in place.
- AD-19: the accessor and the `Public` step; structural or seed.
- AD-22: throwaway stacks.
- AD-23: the recipe, the script's order, the health check, the private-data check.
- AD-24: the roles composed here are what Story 0.3 fills.
- AD-27: the purge task.
- AD-29: lanes; Epic 0 builds the registry and the accessor.
- AD-33: one owner per step.

Spikes S1, S16 and S19.

**Order** (`Registry.Order()`), with each step's lane and filler:

| # | Step | Lane | In this story | Filled by |
| --- | --- | --- | --- | --- |
| 1 | `Bridge.Installer` | A | stub | 0.4–0.6, Epic 1 |
| 2 | `Public` | A | flag | 3.8 |
| 3 | `Roles` | A | composer | 0.3 |
| 4 | `Users` | A | stub | 0.3 |
| 5 | `Web` | B | stub | 0.3 |
| 6 | `SSL` | A | stub | the first story that needs a client SSL configuration |
| 7 | `Tasks` | A | built | 1.11, and later areas |
| 8 | `Demo` | B | stub | 0.6 |
| 9 | `Provider` (Config Store) | A | stub | 1.1 |
| 10 | `Audit` | A | stub | 0.4, then 3.7 |
| 11 | `Telegram` | A | stub | 12.1 |
| 12 | `Production` | A | stub that starts nothing | 0.6 |
| 13 | `Reconcile` | A | built | areas' declarations |
| 14 | `PrivateData` | A | built | — |
| 15 | `Ready` (`Public.Ready`) | A | built | — |

- The stub steps' content belongs to the stories in the table. Each fills its own step without re-ordering.
- `PrivateData` is built here: AD-23 ends every start with that check, and no other story builds it.
- A class under `OcuTalon.Install.Step.*` that isn't in the order (for example Lane B's `Schedule`, AD-18) only declares; its `Run` is never called.

**Contracts fixed here** (cross-lane; the lead may record them in the spine, Rule 20):
- `Grants()` entries are `{"role","resource","permission"}`. An empty `resource` declares the role alone, and role names start with `OcuTalon`.
- `Tasks()` entries are `{"name","taskClass","description","task":{<%SYS.Task property>:value},"settings":{<task property>:value}}`, with names starting `OcuTalon`.
- The public keys are `onlineDemo`, `demoUser`, `demoPassword`, `readonlyUser`, `readonlyPassword`, `resetIntervalHours`, `resetAnchor`, `lastReset`, `lastResetKind`, `proxyAddress`, `connectionCap`, `connectionReserve` and `messageAllowance`, plus `ready`. Times are UTC ISO 8601 with `Z`. Defaults are the `Public` step's job (3.8), not the accessor's.
- The log contract is `STEP` and `RESULT`, with the log rewritten each start at `/durable/ocutalon-after-start.log`.
- Epic 15's IPM path calls `Registry.Run("ipm")`.

**Structural or seed (AD-19):**
- The public settings and the roles are structural: rewritten every start.
- Tasks are seed: created once.
- The helper for System Default Settings (`structural`/`seed`) joins `OcuTalon.Install.Step` with its first user, Story 1.1, so every step shares it.

**IPM file:** the release file and its licence live in `docker/ipm/` (Lane B's `docker/`) and ship in `/opt/ocutalon/ipm/`. Story 10.2's README points to the notice. This adds no new dependency: it is the pinned Stack row.

**Integration ACs:**
- The after-start script consumes the registry and the accessor, and produces the marker and readiness. Docker's health monitor consumes the marker (rows 1, 6 and 7).
- Within this story, the `Public` step consumes the accessor (row 1).

**Consumed-by:**
- 0.3: the Roles declarations and the `Users`/`Web` steps; the login page reads the accessor.
- 0.4: the `Audit` step, `Setting.Get` delegating to the accessor, and the first private classes that `PrivateData` checks.
- 0.5: `/ocutalon/public/status` reads `ready` and `NextReset`.
- 0.6: `Production` and `Demo`.
- 0.7: CI runs `docker/tests/test-*.sh` and the shards, plus the public-package and `^OcuTalonPublic` checks.
- 1.1: `Provider`.
- 1.11: the purge declarations.
- 3.8: the `Public` step's online-demo values.
- 12.1: `Telegram`.
- Epic 15: `Registry.Run("ipm")`.

**Consumes:** Story 0.1's image, `merge.cpf`, health check, marker contract and allow-list.

**Reuse (Rule 2):**
- Every step extends `OcuTalon.Install.Step`.
- The live helpers move into `lib-live.sh`, extracted from `test-compose-start.sh`.
- The script's test-only path variables follow `healthcheck.sh`'s convention.
- `test-after-start.sh` keeps its own fake `iris`, because `test-healthcheck.sh`'s answers only `qlist`.
- The S1 scripts are adapted, not copied: they are outside the repo and were disposable.

**Ledger inbox:** DW-1 is addressed: `after-start.sh` merges first, and rows 2 and 8 test it.

## Verification

**Commands:**
- `(loop)` `bash docker/tests/test-after-start.sh` -- expected: exit 0, PASS for rows 7 (shell side) to 10 and the order.
- `(loop)` `bash docker/tests/test-healthcheck.sh`, `bash docker/tests/test-compose-file.sh`, `bash docker/tests/test-build-inputs.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-lib-live.sh` and `bash docker/tests/test-pinned-sources.sh`, one per call -- expected: exit 0 each.
- `(loop)` `bash docker/tests/test-compose-start.sh` (`timeout: 600000`) -- expected: exit 0 in under 9 minutes, with nothing named `ocutalon-t01-*` left behind.
- `(loop)` `bash docker/tests/test-install-start.sh` (`timeout: 600000`) -- expected: exit 0 for rows 1–5 in under 9 minutes, with nothing named `ocutalon-t02s-*` left behind.
- `(loop)` `bash docker/tests/test-install-upgrade.sh` (`timeout: 600000`) -- expected: exit 0 for rows 6–7 in under 9 minutes, with nothing named `ocutalon-t02u-*` left behind.
- `(loop)` `iris_doc_load` on `server: ocutalon-slot-a`, `namespace: OCUTALON`, with `compile: true` and `flags: "ck"`, after `iris_server_info` confirms build 154 and slot A's ports (1990/52790). Make two calls, so that each glob's base is a package root: first `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls` -- expected: every class compiles.
- `(loop)` `iris_execute_tests` with `level: class` and the same server and namespace, one call each for `OcuTalon.Test.Data.PublicSettings`, `OcuTalon.Test.Install.Registry` and `OcuTalon.Test.Install.PrivateData`, waiting for each before the next -- expected: 0 failed.
- `(once)` `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 bash docker/tests/test-install-start.sh` (`timeout: 600000`) -- expected: exit 0. This is the same Dockerfile on the non-Health image.
- `(once)` `git status --short` -- expected: only the files listed in Tasks.

**Shared surfaces:**
- Story 0.1's pins on the Dockerfile's COPY set, the `.dockerignore` list, `files_keep_lf`, the `/opt/ocutalon` modes, row 8's build directory and `test-boundaries.sh`'s scope (all updated here).
- Slot A's OCUTALON gains the `src` classes. The fixture role, task and class are created and removed by the tests.
- Every test added or changed passes on a fresh environment, in either order.

**Mutations to record (Rule 19):**
- Row 1: swap `Tasks` and `SSL` in `Order()`; `test-install-start.sh` should go red.
  - mutation: `"Web", "SSL", "Tasks", "Demo"` in `Registry.Order()` -> `test-install-start.sh` red (`row 1`, `row 2`, `row 3`, `row 4`: the log differs from the expected phases and steps)
- Rows 2 and 8, DW-1: delete the `iris merge` call; `test-install-start.sh` (mapping not restored) and `test-after-start.sh` should go red.
  - mutation: `merge_out=$(iris merge IRIS ...)` replaced by `merge_out=""` in `after-start.sh` -> `test-after-start.sh` red (6 checks: merge before session, merge on a copy, and the four row 8 checks; re-demonstrated at code review after the marker moved before the merge) and `test-install-start.sh` red (row 2: the restart ended with `PrivateData FAILED ... IRIS.IF.Zz`, so `row 2 the restart did not end ready within 200 s`)
  - mutation: `iris merge IRIS "$merge_file"` (the image's file itself) in place of the merge of the temporary copy in `after-start.sh` -> `test-install-start.sh` red (row 2: the restart ended with `PrivateData FAILED ... IRIS.IF.Zz`, so `row 2 the restart did not end ready within 200 s`; `iris merge` skips a path whose `*.last_merge` record is unchanged)
  - mutation: the failure leg of the marker write replaced by `finish "ready $image_version"` in `after-start.sh` -> `test-after-start.sh` red (`marker not writable: the log names the marker`, `marker not writable: the log ends not ready`)
- Row 2: make the gate always load; red.
  - mutation: `Set why="always"` in `after-start.cos` -> `test-install-start.sh` red (`row 1` to `row 4` log checks, and `row 2: the compile time of OcuTalon.Install.Registry changed`)
- Row 3: ignore `OCUTALON_DEV`; red.
  - mutation: `dev=0` in `after-start.cos` -> `test-install-start.sh` red (`row 3: the log differs`, `row 3: the compile time ... is unchanged after the dev start`)
- Row 4: skip the public-class check; red.
  - mutation: `Set bad=""` before the load decision in `after-start.cos` (the check's result is discarded) -> `test-install-start.sh` red (`row 4 the restart did not end ready within 200 s`)
- Row 5: make `Bridge.Installer` reference `OcuTalon.Install.Registry`; red.
  - mutation: `Quit ##class(OcuTalon.Install.Registry).Order() '= ""` in place of `Quit $$$OK` in `Bridge.Installer.Run()` -> `test-install-start.sh` red (exit 1; `row 5: the bridge loads and installs alone ... (1 of 6 values differ)`)
- Row 6: load only when nothing is installed; `test-install-upgrade.sh` should go red.
  - mutation: `Set why=$Select(inst="":"not installed",1:"")` in `after-start.cos` -> `test-install-upgrade.sh` red (`STEP session FAILED 'RESULT OK 0.1.0', the image is 0.1.1`, so `row 6 the upgrade did not end ready within 200 s`)
- Rows 7 and 9: write the marker without a `RESULT` line; both tests should go red.
  - mutation: the `-z "$result"` and `!= "RESULT OK $image_version"` checks deleted from `after-start.sh` -> `test-after-start.sh` red (5 checks: rows 7, 9 and 10 write a marker) and `test-install-upgrade.sh` red (`row 7: the marker holds '0.1.2'`, `row 7: Docker reported healthy`)
- Row 11: let `Set` accept any key; red.
  - mutation: `Quit 1` in `Settings.IsFixedKey` -> `OcuTalon.Test.Data.PublicSettings:TestRefusedKeys` red
- Row 12: use `>=` at the boundary; red.
  - mutation: `at <= from` in place of `at < from` in `Settings.NextReset` -> `OcuTalon.Test.Data.PublicSettings:TestNextReset` red (`at the anchor: the next slot`)
- AC 1: let the task step overwrite an existing task, and drop the package-prefix filter; red.
  - mutation: `Tasks.Create` deletes an existing task of the name and creates it again -> `OcuTalon.Test.Install.Registry:TestTasksStep` red (`the changed start time is kept`)
  - mutation: the `OcuTalon.Install.Step.` prefix test deleted from `Registry.Areas` -> `OcuTalon.Test.Install.Registry:TestAreas` red (`a subclass outside OcuTalon.Install.Step is not`)
  - mutation: `Quit` after the `AppendStatus` in `Registry.CallAreas`, so the loop stops at the first failing area -> `OcuTalon.Test.Install.Registry:TestReconcileStep` and `:TestPurge` red (`the other areas still ran`)
- AC 2: drop the scan of the data database; red.
  - mutation: `Set found = ""` in place of the first `$Order` over `OCUTALON_DATA`'s globals in `PrivateData.Check` -> `OcuTalon.Test.Install.PrivateData:TestPlantedGlobalFails` red
  - mutation: `If 0 {` in place of the mismatch test of the sample-global loop in `PrivateData.Check` -> `OcuTalon.Test.Install.PrivateData:TestMappingMismatchFails` red (`a namespace without the private mappings fails`)
  - mutation: `If 1 {` in place of the `OcuTalonP.`/`OcuTalonBP.` prefix test in `PrivateData.StorageGlobals` -> `OcuTalon.Test.Install.PrivateData:TestPrivateStorageGlobals` red (`a global without a private prefix is not`)
- AC 3: a rewritten key list, a readiness that stores 0, and an online-demo flag that is always 1; red.
  - mutation: `lastRest` in place of `lastReset` in `Settings`'s `KEYS` -> `OcuTalon.Test.Data.PublicSettings:TestFixedKeysRoundTrip` red (`the fixed keys are the contract's thirteen`)
  - mutation: `Set ^OcuTalonPublic(..#READY) = 0` in `Settings.SetReady` -> `OcuTalon.Test.Data.PublicSettings:TestReadiness` red (`ready is 1`)
  - mutation: `Set demo = 1` in `Step.Public.Run` -> `OcuTalon.Test.Data.PublicSettings:TestPublicStep` red (`onlineDemo is 0 without OCUTALON_ONLINE_DEMO`)
- AC 4: drop `!src` from `.dockerignore`; red.
  - mutation: the `!src` line deleted from `.dockerignore` -> `test-compose-file.sh` red (`dockerignore: every copied file or directory is allowed`) and `test-build-inputs.sh` red (`dockerignore: the build context differs from the files the Dockerfile copies`)
- The dev file: `OCUTALON_DEV: "0"`; `test-compose-file.sh` should go red.
  - mutation: `OCUTALON_DEV: "0"` in `docker-compose.dev.yml` -> `test-compose-file.sh` red (`dev: the file holds only the project name and OCUTALON_DEV "1"`, `dev: OCUTALON_DEV is "1" for the iris service`)

**QA additions (QA):** the QA pass (2026-10-18) closed weak or missing pins for Tasks bullets that no test covered. Each mutation below was applied, seen red, and reverted; a sha256 manifest of the tree (332 files) was byte-identical after every revert.
- Test files created (QA):
  - `docker/tests/test-pinned-sources.sh` -- static: the IPM release file and licence are the Stack row's files (size and sha256), the file's own VERSION is 0.10.10, the licence keeps its notice, `after-start.cos` names that file and version; `src/module.xml` has `<SourcesRoot>.</SourcesRoot>` and the bridge package as the first resource, then the product package, each package present in its directory.
  - `docker/tests/test-lib-live.sh` -- hermetic (stubs for `dc`, `started_at` and `health_status`): `start_log_complete`, `wait_started_log` and `wait_started_ready` never accept a previous start's log, a log without its end line, an unhealthy container or a container that started again; `copy_build_context` copies exactly the Dockerfile's COPY set with directories expanded; `log_steps`, `manifest_version` and `bump_patch`.
- Test files changed (QA):
  - `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls` -- `TestOrder` pins the exact order of AD-23 (it pinned only the count and both ends); new `TestStepDefaults`, `TestPurgeTaskDefaults` (task name, 90 days by default) and `TestRun` (a probe subclass of the registry over fixture steps: one line per step, stop at the first failure, an exception is a failed step, a clean run).
  - `docker/tests/test-after-start.sh` -- row 8's second leg: the merge file cannot be copied.
- Mutations demonstrated in the QA pass (5 re-demonstrations of the implement pass's lines, 13 new):
  - mutation: the `!src` line deleted from `.dockerignore` (AC 4, re-demonstrated) -> `test-compose-file.sh` red (`dockerignore: every copied file or directory is allowed`)
  - mutation: the `OcuTalon.Install.Step.` prefix test deleted from `Registry.Areas` (AC 1, re-demonstrated) -> `OcuTalon.Test.Install.Registry:TestAreas` red (`a subclass outside OcuTalon.Install.Step is not`)
  - mutation: `Set found = ""` in place of the first `$Order` over `OCUTALON_DATA`'s globals in `PrivateData.Check` (AC 2, re-demonstrated) -> `OcuTalon.Test.Install.PrivateData:TestPlantedGlobalFails` red (all four planted globals)
  - mutation: `Set ^OcuTalonPublic(..#READY) = 0` in `Settings.SetReady` (AC 3, re-demonstrated) -> `OcuTalon.Test.Data.PublicSettings:TestReadiness` red (`ready is 1`)
  - mutation: `at <= from` in place of `at < from` in `Settings.NextReset` (row 12, re-demonstrated) -> `OcuTalon.Test.Data.PublicSettings:TestNextReset` red (`at the anchor: the next slot`)
  - mutation: `"Tasks", "SSL"` in place of `"SSL", "Tasks"` in `Registry.Order()` (row 1) -> `OcuTalon.Test.Install.Registry:TestOrder` red (`the order of AD-23`); the previous `TestOrder` stayed green under this swap, so only the live test saw it
  - mutation: the `Quit` after the `STEP ... FAILED` line deleted from `Registry.Run` (row 7) -> `OcuTalon.Test.Install.Registry:TestRun` red (7 assertions: the failure is lost, the step after it runs)
  - mutation: `Throw exception` in place of `Set sc = exception.AsStatus()` in `Registry.RunStep` (row 7) -> `OcuTalon.Test.Install.Registry:TestRun` red (`the throwing step is reported FAILED with its text`)
  - mutation: `Quit [{"role":"OcuTalonZzDefault"}]` in place of `Quit []` in `Step.Grants` -> `OcuTalon.Test.Install.Registry:TestStepDefaults` red (`Grants declares nothing`)
  - mutation: `InitialExpression = 9` in place of `90` in `Task.Purge.DaysToKeep` -> `OcuTalon.Test.Install.Registry:TestPurgeTaskDefaults` red (`DaysToKeep is 90 by default`, `the areas received 90 days`)
  - mutation: one byte appended to `docker/ipm/zpm-0.10.10.xml` -> `test-pinned-sources.sh` red (`the release file is 1593780 bytes`, `the Stack row's file (sha256)`)
  - mutation: the two `<Resource>` lines swapped in `src/module.xml` -> `test-pinned-sources.sh` red (`the first two resources are the bridge package, then the product package`)
  - mutation: `Copyright (c) 2020` in `docker/ipm/LICENSE` -> `test-pinned-sources.sh` red (`the licence is the file of IPM v0.10.10 (sha256)`, `the licence keeps its copyright notice`)
  - mutation: `ipmwant="0.10.11"` in `docker/after-start.cos` -> `test-pinned-sources.sh` red (`the session's file and wanted version agree`, `the wanted version is the pinned 0.10.10`)
  - mutation: the begin-stamp comparison deleted from `start_log_complete` in `lib-live.sh` -> `test-lib-live.sh` red (3 checks: a previous start's complete log is accepted)
  - mutation: `true` in place of `[ "$before" = "$after" ]` in `wait_started_ready` -> `test-lib-live.sh` red (`a container that started again meanwhile is not accepted`)
  - mutation: `echo "$src"` in place of `find "${src%/}" -type f` in `copied_files` -> `test-lib-live.sh` red (`the copied files differ from the files the Dockerfile names`, `a copied file differs from its original`)
  - mutation: `merge_rc=0` in place of `merge_rc=1` for the failed copy in `after-start.sh` -> `test-after-start.sh` red (3 checks of `row 8 merge file missing`)
- Not pinned, with the reason (QA decisions):
  - AC 4's "judges' `docker-compose.yml` is byte-identical" is a story-scoped fact, not a permanent test: a hash pin would break Story 0.3 and later whenever they legitimately touch the file. It holds: `git diff d917978..HEAD -- docker-compose.yml` is empty, and `test-compose-file.sh` pins its properties.
  - `Registry.Run`'s refusal outside OCUTALON needs a second namespace that holds the package; phase 4 of `after-start.cos` always enters OCUTALON first, so it stays unreachable and unpinned (rejected in review too).
  - Row 11's "nothing stored" for an unknown key cannot be read back through the accessor, which refuses that key; reading `^OcuTalonPublic` directly would break the rule that only `Settings` reaches it. The `ready` leg of the row reads back and is pinned.
  - The AD-3 allow-list of the public packages and the `^OcuTalonPublic` single-accessor rule belong to Story 0.7's checks.

**Code review additions (CR, 2026-10-18).** Each mutation below was applied, seen red and reverted; a sha256 manifest of the tree (332 files) and `git status --short` were identical afterwards, and slot A got back the unmutated class each time.
- mutation: `drop_marker` moved from before the merge to after `STEP merge OK` in `after-start.sh` (the order before review) -> `test-after-start.sh` red (`the old marker was gone before the merge, so no health probe during the merge sees it`, and four row 8 checks)
- mutation: `CMD ["--after", "/opt/ocutalon/after-start.sh"]` (no `--before`) in `docker/Dockerfile` -> `test-compose-file.sh` red (`dockerfile: CMD deletes the ready marker before IRIS starts, ...`). A throwaway probe showed that build 154's `iris-main` runs `--before "rm -f /durable/ocutalon.ready"` as a shell command line: the marker was gone after that start, and it was still there in the control start with `--after` alone.
- mutation: `src/** text eol=lf` in `.gitattributes` -> `test-compose-file.sh` red (`gitattributes: files under src/ are text only when git detects text, ...`)
- mutation: the `ready` end-line test deleted from `wait_started_ready` in `lib-live.sh` -> `test-lib-live.sh` red (`a start that ended not ready is not accepted, even while Docker still reports healthy`)
- mutation: `merge_rc=0` in place of `merge_rc=1` for the failed copy in `after-start.sh` (re-demonstrated) -> `test-after-start.sh` red (3 checks of `row 8 merge file missing`)
- mutation: `merge_out="could not copy $merge_file"` in place of the temporary-directory message in `after-start.sh` -> `test-after-start.sh` red (`row 8 no temporary directory: the log names the merge and the directory`)
- mutation: `Quit ..Check($Namespace)` in place of `Quit ..Check($Namespace, .storage)` in `PrivateData.Run` (AC 2) -> `OcuTalon.Test.Install.PrivateData:TestStorageGlobalMismatchFails` red (`a storage global outside OCUTALON_PRIVATE fails the check`, `the error names the storage global`)
- mutation: `If $$$ISERR(sc) Do ..Apply(.roles) Quit sc` in `Roles.Run` (apply what was composed despite the refusal) -> `OcuTalon.Test.Install.Registry:TestRoleNameRefused` red (`no role was created`)
- mutation: `m.Version.Follows(FromString(ipmwant))` in place of `FromString(ipmwant).Follows(m.Version)` in `after-start.cos` (the IPM "older than" gate) -> `test-install-start.sh` red (`row 2`, `row 3`, `row 4`: the log differs; row 2 records IPM as 0.10.9 and expects `installed 0.10.10 (was 0.10.9)`)

**Code review verification:** on the patched tree `test-after-start.sh` (55 checks), `test-lib-live.sh` (18), `test-pinned-sources.sh`, `test-compose-file.sh` (41), `test-boundaries.sh`, `test-healthcheck.sh` and `test-build-inputs.sh` pass; live `test-install-start.sh` (98 s, 31 checks, and 73 s with `IRIS_IMAGE=iris-community:2026.3.0AI.154.0`), `test-install-upgrade.sh` (102 s, 22) and `test-compose-start.sh` (66 s, 34) pass, each in its own throwaway project with nothing left behind. Slot A (build 154, port 52790): `PrivateData` 5/5, `Registry` 11/11, `PublicSettings` 5/5; no fixture class, role, task or `^OcuTalonTest` node remains.

**QA verification:** `test-after-start.sh` (53 checks), `test-healthcheck.sh`, `test-compose-file.sh` (40), `test-boundaries.sh` (6 rules), `test-pinned-sources.sh` (14), `test-lib-live.sh` (17) and `test-build-inputs.sh` pass; live `test-install-start.sh`, `test-install-upgrade.sh` and `test-compose-start.sh` pass, each in its own throwaway project with nothing left behind. Slot A (build 154), after loading both globs: `PublicSettings` 5/5, `Registry` 11/11, `PrivateData` 4/4; no fixture class, role, task, planted global or `^OcuTalonTest` node remains, and `ready` and `onlineDemo` read as before.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The after-start script (`docker/after-start.sh`, with its ObjectScript session `docker/after-start.cos`) now installs IPM 0.10.10 from the release file in the image, version-gates and loads the one package, runs the 15-step registry in AD-23's order and writes the marker atomically; a failure at any point leaves no marker and the container running. The registry, the step contract, `OcuTalon.Data.Public.Settings`, the bridge installer, the 13 step classes (five built: `Public`, `Roles`, `Tasks`, `Reconcile`, `PrivateData`; eight stubs) and the purge task are in `src/`. Story 0.1's image files and five tests are updated for the new layout, and the live helpers moved into `docker/tests/lib-live.sh`.

**Files changed.**
- Image: `docker/Dockerfile`, `.dockerignore`, `.gitattributes`, `docker-compose.dev.yml` (new), `src/module.xml`, `docker/ipm/zpm-0.10.10.xml` and `docker/ipm/LICENSE` (byte-identical to the spike's copies, sha256 checked).
- After-start: `docker/after-start.sh`, `docker/after-start.cos`.
- Classes: `src/bridge/cls/OcuTalon/Bridge/Installer.cls`; `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls`; `.../Install/{Registry,Step}.cls`; `.../Install/Step/*.cls`; `.../Install/Task/Purge.cls`; `.../Test/{Data/PublicSettings,Install/Registry,Install/PrivateData}.cls`.
- Tests: new `docker/tests/{lib-live.sh,compose.no-after-start.yml,test-after-start.sh,test-install-start.sh,test-install-upgrade.sh}`; updated `test-compose-start.sh`, `test-compose-file.sh`, `test-build-inputs.sh`, `test-boundaries.sh`. `docker-compose.yml` is untouched.

**Deviation for the lead (Rule 20 candidate).** `docker/after-start.sh` merges a fresh temporary copy of the merge file, not the image's file itself: on build 154 `iris merge` does nothing for a path whose `*.last_merge` record is unchanged, so the literal `iris merge IRIS "$merge"` never restores a mapping removed by hand (DW-1). Demonstrated at review: merging the image's file directly makes row 2 end `PrivateData FAILED ... IRIS.IF.Zz`. The order (merge first) and the merge file are unchanged. AD-23's DW-1 sentence ("re-runs `iris merge` with the image's merge file at every start") could name the copy.

**Review.** 56 findings from four layers: high 0, medium 2, low 49, false 5. Patched 10, all in tests or test scripts (no product code changed in review): the failing fixture area now sorts before the healthy one so "the other areas still ran" can fail (medium); `PrivateData`'s mapping confirmation is run in the failing direction through a runtime subclass against namespace `USER` (medium); a fixture with a global that is not private pins the storage-prefix filter; an unwritable marker directory in `test-after-start.sh`; the exact thirteen public keys in `TestFixedKeysRoundTrip`; row 3's empty-value guard; row 7's full 40 s watch; a `docker logs` check of the STEP summary in row 1; and `mutation:` lines for AC 3 and AC 4 plus the new tests. Deferred: none. Rejected: 46 findings, each with its reason in the Review Triage Log (guards beyond the spec, duplicates, theoretical cases, and findings whose fix the intent excludes).

**Follow-up review recommended: true.** Two medium findings were patched. Unverified risk: the two new test seams (`TestMappingMismatchFails` relies on namespace `USER` resolving the sample globals outside `OCUTALON_PRIVATE`; the `ZzBad<n>` ordering relies on name collation) have had only the author's mutation runs, no second reviewer.

**Verification.** Every `(loop)` command passed on the final tree: `test-after-start.sh` (48 checks), `test-healthcheck.sh`, `test-compose-file.sh`, `test-build-inputs.sh`, `test-boundaries.sh`; live `test-compose-start.sh` (72 s), `test-install-start.sh` (88 s, 30 checks), `test-install-upgrade.sh` (101 s, 22 checks), each in its own throwaway project with nothing left behind; slot A (build 154, port 52790): both `iris_doc_load` calls compiled, `PublicSettings` 5/5, `Registry` 8/8, `PrivateData` 4/4, and no fixture class, role, task or `^OcuTalonTest` node remains. The `(once)` run `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 bash docker/tests/test-install-start.sh` passed (56 s, 30 checks); `git status --short` lists only the files in Tasks. Mutations: all recorded lines were demonstrated red and reverted with a byte-identical tree (sha256 manifest before and after).

**Residual risks.**
- On a same-version restart the old marker stays valid while IRIS comes up and the merge runs, so Docker can report `healthy` for those seconds before this start's session has cleared readiness. This follows the spec's order (merge, then clear the marker) and AD-23.
- A hung step has no timeout: the container stays `starting`, then `unhealthy`, with no end line in the log. Steps that wait (Story 0.6's `Production`) should bound their own waits.
- In the health image HSLIB and HSSYS already map `%IPM`, so row 1 asserts "mapped into OCUTALON and not into USER", not "only OCUTALON".
- The log carries the full IPM install transcript (about 700 lines on a first start).
- Rows 6 and 7 are chained on one stack, so row 7's failing image is V0 plus two and the next good one V0 plus three.
