---
title: 'Story 15.2: The second install run gives a working OcuTalon with demo mode off'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: '5378faf493bb7cef87d59ad6d181c58d8b4499c0'
baseline_commit: '7fd58499ccc20305a6be8ccd49febdb9ff8e1e71'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 15.1, the install command run in OCUTALON loads and compiles the `ocutalon` package but runs no installer step, so an IPM install into an existing instance gives no running OcuTalon (FR-57, AD-23). Nothing marks the production autostart there, nothing reconciles waiters on a production start that no installer made, and there is no install document.

**Approach:** A second `<Invoke>` (Configure, After) calls a new `OcuTalon.Install.Registry.Ipm()`. Outside the image it commits IPM's open transaction, runs `Run("ipm")`, and opens the same transaction levels again; on the image it does nothing, because the after-start script runs the steps. On the `ipm` path the `Production` step marks the production autostart. A new Lane A item, `ReconcileIn`, runs every area's `Reconcile()` once the items run, on any start the `Production` step did not make. `release/ipm-install.sh` proves the second run on both install paths, and `docs/install-ipm.md` documents them from that run's output.

## Boundaries & Constraints

**Always:**
- One package, `ocutalon`, with no dependency, the bridge's resources first (AD-2). The steps run in `Registry.Order()`'s fixed order, which is unchanged. They run only in OCUTALON, because `Run` refuses every other namespace (AD-23).
- Every production start reconciles exactly once:
  - A start made by the `Production` step is reconciled by the installer's `Reconcile` step that follows it.
  - Any other start (instance autostart, the portal, `Ens.Director` from a session) is reconciled by `ReconcileIn`, once its items run.
- A Reload, Validate or Compile failure is still rolled back by IPM. `Ipm()` commits only inside Configure, which runs after Compile and after the bundle's FileCopy.
- IPM installs, `iris merge`, demo-mode switches and every fixture of a foreign namespace, routine or zone run only in throwaway stacks of `docker/tests/lib-live.sh`, one fresh stack at a time for the lane (AD-22, Rule 21).
- `docs/install-ipm.md` shows the real captured output of both commands, `ERROR!` included, and says that the first run ends early by design (AD-23's fallback, the runner's ruling).

**Never:**
- Never run the installer steps inside IPM's open transaction. Measured at plan: the production cannot start there (`ErrCanNotAcquireRuntimeLock`). Never use `NoTransaction`, `-dev` or `<Defaults>`, which would undo Story 15.1's rollback of the stopped first run.
- Never change an instance setting OcuTalon doesn't own, and never touch a namespace or database it didn't create. That covers services, a foreign `PasswordValidationRoutine` and its routine, `EnsembleAutoStart`, the host's zone, and a foreign OCUORDERS. No key or token goes into IRIS, a log or the trace. The chat check uses the CI mock through `keys_point`, never a key variable.
- Never mark autostart on the Docker path, and never clear an existing mark.
- Never edit a Lane B file or a Lane B test (U-177: the cross-lane group moved to Lane B; AD-33). `Test/Core/SettingsOps.cls` is also contended by Epic 9.
- Never edit a contended file:
  - `docker/tests/lib-live.sh`, `docker/tests/lib-online.sh`, `docker/tests/test-production.sh`, `docker/after-start.cos`;
  - `src/bridge/**`, `Install/Step/{Telegram,SSL,Tasks,Retention,Watch}.cls`, `Install/Task*`;
  - `.github/workflows/ci.yml`, `lane-a.yml`'s header comment and its `standalone-bridge` job;
  - `README.md`.
- Never add a unit to the `production`, `browser`, `install-fresh` or `install-upgrade` groups.
- Out of scope:
  - Story 15.3: instance restarts, reinstall and upgrade checks, the registry install (`zpm "install ocutalon"`), the release gate, Story 9.1's IPM case, DW-80 and DW-306.
  - Story 31.3: the README's IPM section.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Second run, path A | After the first run in USER: `zpm "load /opt/ocutalon-ipm/src"` in OCUTALON | The output shows Initialize through Activate `SUCCESS`, and between `Configure START` and `Configure SUCCESS` one `STEP <name> OK` line per name of `Registry.Order()`, in that order. `OcuTalon.Production` runs, `NotRunning()` and `UnresolvedRunners()` are empty, and `^Ens.AutoStart` is `OcuTalon.Production`. The module `ocutalon` is recorded with 0 dependencies, and the services are those of the baseline. USER and %SYS hold no OcuTalon class, routine, module record or `^OcuTalon` global. If a step writes such an item in %SYS by design, Task 0 names it under "Measured in implement" and the check excludes it by that name. `PasswordValidationRoutine` is still "". | A failed step prints `STEP <name> FAILED <text>`, and IPM ends with `ERROR! <text>`. The code stays installed, and the same command runs the steps again (measured on the update path) |
| Install checks | After the second run | `OcuTalon.Web.Public.*`, `OcuTalon.Data.Public.*` and `^OcuTalonPublic` resolve to `OCUTALON_PUBLIC`. `^OcuTalonP.*`, `^OcuTalonBP.*`, `^AI.Agent.Session*` and `^IRIS.IF.*` resolve to `OCUTALON_PRIVATE`. The output has `STEP PrivateData OK`. `index.html` is in `$SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/"`, which is `/ocutalon`'s Path. `OcuTalon.Data.Public.Settings` gives `onlineDemo` 0, and `ready` as `test-install-start.sh:74-85` expects it after a start. | - |
| Web and REST | The README account over HTTP | `GET /ocutalon/` serves `Sign in to OcuTalon` and not the online demo's `Try OcuTalon in two minutes`. `ocutalon`/`ocutalon` signs in (`<app-root`). `/ocutalon/api/v1/state` has `onlineDemo:false` and `demoMode:false`, and no `guide`, `phone` or `mailbox`. `POST demo/break-feed` answers 404. OCUORDERS doesn't exist. A chat message, with the keys pointed at the mock, ends in a turn whose decision has no `fallbackReason`. | - |
| Package | After the second run | One module whose name starts with `ocutalon`. `OcuTalon.Bridge.Installer` and `OcuTalon.BridgeExample.Production` are compiled. The example production is neither running nor the autostart production. | - |
| Demo switch | `do ##class(OcuTalon.Core.Admin).SetDemoMode(1)`, then `(0)`, in OCUTALON | On: SettingsOps' `MESSAGEON` line. OCUORDERS exists with `OCUORDERS_CODE` and `OCUORDERS_DATA` under `ManagerDirectory()`, the public package and global mappings exist, and `OcuTalon.Demo.Orders.Production` runs there. Off: the `MESSAGEOFF` line, and the namespace and both databases are gone. After each switch the list of the instance's other namespaces and USER's mappings are unchanged. | - |
| Start outside the step | `Ens.Director.StopProduction` and then `StartProduction("OcuTalon.Production")` from a session | Within 60 s, exactly one new Info row of `ReconcileIn` with `ReconcileIn.#LOGTEXT`, and still one after 3 more polls | A failed reconcile is one `$$$LOGERROR` row. Its warnings are one `$$$LOGWARNING` row each |
| Start by the step | `Registry.Run("ipm")` in a session | `STEP Reconcile OK`, and no new `ReconcileIn` Info row within 15 s | - |
| Path B | Fresh instance: `iris merge`, then `zpm "enable -map -ns OCUTALON"`. A foreign `ZzForeign` routine and `PasswordValidationRoutine=ZzOther^ZzForeign` exist in %SYS, and a foreign OCUORDERS on the `OCUFOREIGN_*` databases exists. Then the install command in OCUTALON | Every STEP line is `OK`, and `WARN Demo` names the kept namespace. The setting is still `ZzOther^ZzForeign`, `ZzForeign` still exists, the foreign OCUORDERS and its databases are unchanged, and the services are unchanged (DW-212) | - |
| Image load | `zpm "load ..."` on the Docker image, where `/opt/ocutalon/version` exists | `Ipm()` prints nothing, runs no step and leaves `$TLevel` as it found it. The after-start's own `Registry.Run("after-start")` runs the steps once | - |

</intent-contract>

## Code Map

- `src/module.xml:9-15`: the manifest.
  - :14 is the bundle FileCopy to `${dataDir}csp/ocutalon-web/`, already AD-23's path. Measured, it is `$SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/"`, the `/ocutalon` application's Path.
  - :15 is the MapAndStop Invoke. The new Invoke goes after it.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls`:
  - :12-15 `Order()`;
  - :43-68 `Run(caller)`, where `caller` is used only in the refusal at :45-47;
  - :78-92 `CallAreas`;
  - :126-140 `RunStep`, which calls `Run()` with no argument.
- `src/ocutalon/cls/OcuTalon/Install/Step.cls:52-69`: `Warn` and `TakeWarnings` on `^||OcuTalonStepWarnings`. The new `Caller()` follows this process-private pattern.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`:
  - :1-5 the header ("Never marks the production autostart ... an IPM install marks it in Story 15.2");
  - :46-57 `Run`;
  - :61-94 `Start`, whose branches are restart, recover then start, and start;
  - :98-121 `NotRunning()`;
  - `UnresolvedRunners`. Both `NotRunning()` and `UnresolvedRunners` are reused by `ReconcileIn`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Reconcile.cls:5-8`: `Run()` is `CallAreas("Reconcile")`. `ReconcileIn` calls this `Run()`, never a copy of it.
- The `Reconcile()` declarations, read only:
  - `Install/Step/Approvals.cls:8` calls `src/bridge/cls/OcuTalon/Bridge/Approval.cls:653`. It has no lock, so two runs at once can start two holds. That is why the start lock exists.
  - `Install/Step/Fix.cls:11` reports through `Warn`.
  - `Install/Step/Schedule.cls:17` calls `Schedule/Reminder.cls:217`. A production-job caller must save and restore the job's session ids (`Reminder.cls:17-18,176-177`).
  - `Install/Step/Web.cls:95` calls `Core/Conversation.cls:660`, a sweep. A second sweep restarts a running turn: an extra model call, still one reply (:31-32).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls:127-170` (read only, contended): `StartHold` saves and restores `$$$JobSessionId` and `$$$JobCurrentHeaderId`, defined or killed. `ReconcileIn` does the same around its call.
- `src/ocutalon/cls/OcuTalon/Production.cls:15-47`: the Lane A region. Its `FailurePoller` item (:37-41) has the shape for `ReconcileIn`: `Ens.InboundAdapter`, `CallInterval`, pool 1.
- `irislib/Ens/Director.cls`:
  - :1912-1935 `SetAutoStart(name, priority)` writes `^Ens.AutoStart`; there is no getter;
  - :35, :77, :117 `StartProduction` holds the runtime lock, and item jobs start after `OnStart`;
  - :1975-1997 `SystemStart` starts `^Ens.AutoStart` at instance start;
  - :1450-1490 `CreateBusinessService` is allowed inside a production job.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:
  - :13 and :623-630 the oracle header and rows; the `FailurePoller` row is the shape to follow;
  - :444-460 `TestExampleInstalledNotStarted`.
- `src/ocutalon/cls/OcuTalon/Test/Install/ProductionRules.cls`:
  - :47-50 the name fallback `$Case(name, "OcuTalonApprovals": "A", ...)`;
  - :143-151 `LaneOfClass`, which has no `OcuTalon.Install.` prefix.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`: :123-126 the order pin; :229-245 `TestReconcileStep`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls`:
  - :58-64 the guard's names;
  - :89-133 `Accounts` and `CheckGuard`;
  - :279-300 `Unguard`, which clears only `GUARDENTRY` and deletes only `OcuTalonPasswordGuard` and its `New` copy.
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` (destructive, throwaways only):
  - :758-779 `TestForeignGuardIsRefused` (row 12);
  - :712-737 row 11;
  - :900-921 `MakeForeign` and `RemoveForeign`;
  - `Test/Install/PasswordGuard.cls:79-84` `RoutineExists`.
- `release/ipm-install.sh`:
  - :44-158 the functions;
  - :91-127 `residue` and `check_no_residue` want every count at 0. That is valid only before the second run;
  - :162-173 the stack;
  - :175-265 path A;
  - :267-303 path B; `view()` at :296 drops `%IPM` lines;
  - :305-309 the summary.
- `release/ipm/Dockerfile` and `release/ipm/compose.ipm.yml` set no `ISC_DATA_DIRECTORY`. Measured: `DataDirectory()` is `/usr/irissys/`, `ManagerDirectory()` is `/usr/irissys/mgr/`, and `$Username` in `iris session` is `irisowner`.
  - The stack has `ci/compose.ci.yml`'s mock and environment: `OCUTALON_MODEL_BASE_URL`, `OCUTALON_MOCK_KEY_HEADER=1` and a dummy `TELEGRAM_BOT_TOKEN`.
  - It has no `ANTHROPIC_API_KEY`.
  - It publishes no port until `live_web_port` runs before `dc up`.
- `docker/tests/lib-live.sh` (read only, contended): `live_web_port` :202, `wait_until` :287, `iris_script` :308, `compare_chk` :456, `check_session` :480, `session_value` :488. `check_demo_on` and `check_demo_off` (:811, :873) read the after-start log, so they don't work here.
- `docker/tests/lib-online.sh` (read only, contended):
  - `next_probe` needs `probe_file`;
  - `logout_all`;
  - `online_signin <jar> "" "" ocutalon ocutalon` needs `base` and `tmp`;
  - `keys_point` and `keys_restore` (:106-117) use `Test.Agent.RunnerFixture`, measured as installed by the package. Its `GuardReason` allows only the CI override's environment.
- Lane B patterns, read only:
  - `docker/tests/test-demo-switch.sh`: sign-in :57-61, state parse :71-79, `run_admin` :138-155 with texts :49-52, chat post and wait :228-239, break-feed 404 :308-312;
  - `docker/tests/test-online-demo.sh:1289-1324`: decision and `fallbackReason` from `/events`;
  - `docker/tests/test-install-start.sh`: :74-85 the `onlineDemo`, `settings-dest` and `ready` checks; :275-285 the foreign OCUORDERS fixture;
  - `Web/Public/Login.cls:13,15` the sign-in page texts;
  - `Web/Api.cls:737-791` `/state` (`onlineDemo` :758, `demoMode` :759, demo-only members :776-784).
- `docker/tests/test-cpf.sh`:
  - :3-15 the header;
  - :94-105 rule 5, which rejects only another Initialize Invoke (a sample at :216 accepts Activate);
  - :107-130 rules 6 and 7;
  - the samples, then the real files at :282-288.
  - This epic's own check (Story 15.1).
- `.github/workflows/lane-a.yml:43-62`: job `ipm-install` (30 min, deadline 1500 s). `test-cpf.sh` rule 6 pins its exact `run: bash release/ipm-install.sh`.
- `ci/units.sh`:
  - :17 the lane-a areas;
  - :41-42 the pieces: `Install` runs in `shards`, the rest in `shards-2`;
  - :135 `NOT_IRIS_INPUT_PATTERN` excludes `docs/` and `release/`.
- `README.md:140-146,209-223`: the README account and its password change in Docker form. Read only; the document gives the IPM form.
- `irislib/%SYSTEM/Process.cls:1831-1846`: `TimeZone()` returns -1 when TZ is undefined. `irislib/%Library/File.cls:162-175`: `ResolvePath`.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0, confirmation** (throwaway; tag `e15s2i`). The plan measured the transaction behaviour, the paths and the zone (Design Notes, "Measured at plan").
  - The first run of `release/ipm-install.sh a` confirms the rest:
    - `/ocutalon/` is served on the published port;
    - `irisowner` may call `SetDemoMode`;
    - `keys_point` works on this stack;
    - `ReconcileIn` reconciles inside its production job with the session ids restored.
  - Record `TIME` lines and deviations under Design Notes, "Measured in implement". If the in-job reconcile fails, have `ReconcileIn` `JOB` `Install.Step.Reconcile.Run()` in a process of its own, and record why.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step.cls`: add `ClassMethod Caller() As %String`, which returns `$Get(^||OcuTalonStepCaller)`, the entry point that `Registry.Run` names. Its doc says who sets it.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Registry.cls`, two changes:
  - **Record the caller.** `Run(caller)` sets `^||OcuTalonStepCaller=caller` after its namespace check and before the loop, and kills it before it returns.
  - **Add `ClassMethod Ipm(versionFile As %String = {##class(OcuTalon.Install.Step.Demo).#VERSIONFILE}) As %Status`**, the IPM entry point:
    - When the version file exists, it returns OK and does nothing.
    - Otherwise it saves `$TLevel` and `TCommit`s to level 0. It runs `..Run("ipm")` inside Try/Catch. It then `TStart`s back to the saved level on every path and returns the status.
    - Its doc states that a Reload, Validate or Compile failure is still IPM's rollback, and that steps can't run inside IPM's transaction.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`, four changes:
  - **The start lock.** Add `Parameter STARTLOCK = "^OcuTalon.Install.Start"`. `Start(wait)` takes `Lock +@..#STARTLOCK` with a timeout of `WAITSECONDS` and releases it on every path. On a timeout it fails, naming the lock holder's purpose ("another start of OcuTalon.Production, or its reconcile").
  - **`ClassMethod Starting() As %Boolean`.** It returns 1 when another process holds the lock (a probe with timeout 0, released at once).
  - **`ClassMethod AutoStart(caller As %String) As %Status`.** For `"ipm"` it calls `##class(Ens.Director).SetAutoStart(..#PRODUCTION)`; for any other caller it returns OK and changes nothing.
  - **`Run`** calls `..AutoStart(..Caller())` after `Start` succeeds. Update the header (:1-5) to say what the step does now.
- [ ] `src/ocutalon/cls/OcuTalon/Install/ReconcileIn.cls` (new), the item `ReconcileIn`. It extends `Ens.BusinessService` with `Parameter ADAPTER = "Ens.InboundAdapter"`, and has `Parameter LOGTEXT` and `Parameter WAITWARNSECONDS = 60`.
  - **`OnInit`** sets `ByStep = ##class(OcuTalon.Install.Step.Production).Starting()` and records the start time.
  - **`OnProcessInput`** acts on `Next(byStep, done, missing, waited, warned)`, a pure class method that returns `skip`, `wait`, `warn` or `run`:
    - `warn` logs one `$$$LOGWARNING` naming the items not running.
    - `run` takes `STARTLOCK` with a timeout of 30 s. If it gets it, it saves the session ids (`Approval.cls:127-170`'s pattern), calls `##class(OcuTalon.Install.Step.Reconcile).Run()`, logs each `TakeWarnings()` line as `$$$LOGWARNING` and an error as `$$$LOGERROR`, restores the ids, releases the lock, logs `$$$LOGINFO(..#LOGTEXT)` and sets `Done`. If it doesn't get the lock, it waits for the next poll.
    - It always returns OK.
  - Its doc states the exactly-once rule.
- [ ] `src/ocutalon/cls/OcuTalon/Production.cls`: in the Lane A region only, add `<Item Name="ReconcileIn" ClassName="OcuTalon.Install.ReconcileIn" PoolSize="1" Enabled="true">` with the `Adapter` setting `CallInterval` 5, shaped like `FailurePoller`.
- [ ] `src/module.xml`: after the MapAndStop line, add `<Invoke Class="OcuTalon.Install.Registry" Method="Ipm" Phase="Configure" When="After"/>`.
- [ ] `docker/tests/test-cpf.sh`: add rule 8 with samples (one that keeps it, one that breaks it) and a header line. `src/module.xml` must have exactly one line, this exact Invoke, and it comes after the MapAndStop line. Leave rules 1-7 unchanged.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`: add `TestIpmOnTheImage`.
  - `TStart`, then set `^OcuTalonTest("Registry", ..Number, "ipm")=1`, then call `Ipm(<an existing temp file>)`. Assert OK and `$TLevel` 1.
  - `TRollback`, then assert that the node is gone. `Ipm()` committed nothing, so it ran no step.
  - The caller handoff (`Caller()` to `AutoStart`) is pinned by `TestAutoStart` and the IPM and Docker live checks; `Run` runs every real step, so no unit test calls it.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`, two changes:
  - **The oracle row:** `{"lane": "A", "name": "ReconcileIn", "class": "OcuTalon.Install.ReconcileIn", "pool": 1, "enabled": 1, "stub": 0, "settings": [{"target": "Adapter", "name": "CallInterval", "value": "5"}]}`, with a line in the header comment.
  - **`TestAutoStart`:** save `^Ens.AutoStart`. `AutoStart("after-start")` leaves it as it was, and `AutoStart("ipm")` sets `OcuTalon.Production`. Restore it in `OnAfterOneTest`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/ProductionRules.cls`: add `"ReconcileIn": "A"` to the name fallback at :48.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/ReconcileIn.cls` (new; area Install): `TestNext` covers every branch of the pure `Next`:
  - `byStep` gives `skip`;
  - `done` gives `skip`;
  - missing items and `waited` under 60 give `wait`;
  - over 60, once, give `warn`, then `wait`;
  - nothing missing gives `run`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` (DW-212): in `TestForeignGuardIsRefused`, after the refused flag-on run and after the flag-off run, assert `$ClassMethod(guard, "RoutineExists", "ZzForeign")`. Change nothing else.
- [ ] `release/ipm-install.sh`: extend the functions; don't copy them.
  - **Argument.** No argument means path A then path B, which is the job.
    - `a`: path A only.
    - `b`: path A's precondition and first run, kept as the reference for path B's comparison, then path B.
    - The header lists the new numbered checks.
  - **Stack.** Call `live_web_port` before `dc up`, and set `base`, `probe_file` and `probes`.
  - **Libraries.** Source `docker/tests/lib-online.sh` for `online_signin`, `logout_all`, `next_probe`, `keys_point` and `keys_restore`.
  - **`residue <scope>`** takes an optional list of namespaces, so that after the second run the USER and %SYS counts are still checked for 0 while the instance-wide counts are skipped.
  - **Path A, after check 6:**
    - `run second-ocutalon OCUTALON "$INSTALL"`, then the matrix rows "Second run, path A", "Install checks", "Web and REST", "Package", "Demo switch", "Start outside the step" and "Start by the step", in that order.
    - The chat check runs `keys_point` before and `keys_restore` after, also on a failure.
    - Its `OUTPUT` and `TIME` lines like every run. The demo switches go through `run` too, so their output is kept.
  - **Path B, after check 7:**
    - `run enable-ocutalon %SYS 'zpm "enable -map -ns OCUTALON"'`;
    - the DW-212 fixture, following `MakeForeign`'s routine;
    - the foreign OCUORDERS fixture, following `test-install-start.sh:275-285`;
    - `run second-merge OCUTALON "$INSTALL"`, then the matrix row "Path B".
  - **End.** The summary is unchanged.
- [ ] `docs/install-ipm.md` (new; `docs/` is new), written from the `OUTPUT` blocks of a passing `release/ipm-install.sh a` run. Copy them with ANSI codes removed and nothing else changed. It covers:
  - **What you need:** an AI Hub build 154 instance with IPM 0.10.10, and the package folder. That is the repository's `src`, with the web page built once on any machine with Node.js 24.15 or later (`npm --prefix web ci`, then `npm --prefix web run build`). The instance needs no Node.js.
  - **The first command**, `zpm "load <folder>"` in any namespace, with its real output ending `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.`, and that this run ends early by design.
  - **The second command** in OCUTALON, with its real output and its `STEP` lines.
  - **The `iris merge` alternative:** `iris merge <instance> <folder>/cpf/ocutalon.cpf`, then `zpm "enable -map -ns OCUTALON"`, then the install command in OCUTALON.
  - **Demo mode:** off, `do ##class(OcuTalon.Core.Admin).SetDemoMode(1)` to switch it on (OcuTalonAdmin or %All), what it creates, and `(0)`.
  - **The model key:** `ANTHROPIC_API_KEY` in the environment that IRIS starts with, never stored in IRIS. Without it, decisions use fixed rules.
  - **The README account:** `ocutalon`/`ocutalon` at `/ocutalon/`, and its password change in a %SYS session with `Security.Users.Modify`, as README:209-223 gives it.
  - **No local path, key or token** (`test-boundaries.sh`).
- [ ] `.github/workflows/lane-a.yml`: unchanged. Only if `TIME` totals of `a` and `b` together go over 8 minutes locally: in job `ipm-install` only, set `timeout-minutes: 35` and `OCUTALON_LIVE_DEADLINE: "1980"`. Rule 7 needs the deadline under timeout times 60.

**Owner decision U-176 (the answer of 2026-10-31T00:05:17Z#534, the owner's delegate, the Contest Planner): keep the commit at Configure, After, with four conditions. Work only these items in this pass.**
- [x] [Owner U-176 (1)] `src/ocutalon/cls/OcuTalon/Install/Registry.cls`: when `Ipm()`'s `Run("ipm")` fails after the commit, the install command reports failure (it already returns the error to IPM, so IPM prints `Configure FAILURE` and `ERROR! ...`; keep that, never let IPM's success line stand alone) and `Ipm()` prints exactly one more terminal line, in the Install step style of `Run`'s `STEP <name> ...` lines, that names the failed step, says that the new code is installed, and says to run the same install command again. Suggested text (decide the exact wording in the same plain style and record it): `STEP <name> FAILED: the new OcuTalon code is installed. Run the same install command again.` Name the step from the run itself (the first failed step), never a guess. The Docker path (`Run("after-start")`) is unchanged. Pin it with a unit test in `Test.Install.Registry` if a pure seam allows (for example a class method that builds the line from a step name), and in the live check below.
- [x] [Owner U-176 (2)] `release/ipm-install.sh`, path A, after the existing checks (the FR-57 job's harness is here, so it is built in this story): a **forced step failure on a reinstall** through a test-only seam, never a switch in the shipped package. The seam lives only in the test: inside the throwaway, copy the package folder to a scratch folder of the container and change one installer step there so that its `Run()` returns an error (for example a Lane A step such as `Install/Step/Approvals.cls` or one that is safe to fail; never edit the real source tree), then `zpm "load <scratch folder>"` in OCUTALON as the reinstall. Before it, seed recognisable data that a reinstall must keep (for example a row the earlier checks already created, or a setting value; read it back by value). Prove: the command reports the failure (IPM's `ERROR!` and no success line alone), the U-176 (1) line names that step, the data is still there, OCUTALON and its four databases still exist; then the real folder's `zpm "load ..."` again completes, every `STEP ... OK`, the production runs, and the checks of Stories 15.1 and 15.2 pass again (reuse the existing check functions; do not copy them). Then a **failed Compile**: a second scratch copy with one class that does not compile; `zpm "load ..."` fails, IPM rolls it back, and the previous version keeps running (the production still runs with nothing missing, a class of the package still answers as before, and the module version is unchanged). Each `zpm` run goes through `run` so its `OUTPUT` and `TIME` lines are kept. Keep `a`'s local time well inside the 10-minute cap (split into a new argument, for example `r`, if needed, and list it in the header); the no-argument job line stays the same. If the job's local total of `a` plus `b` (plus any new argument) goes over 8 minutes, apply the spec's existing lane-a.yml rule (job `ipm-install` only: `timeout-minutes: 35`, `OCUTALON_LIVE_DEADLINE: "1980"`).
- [x] [Owner U-176 (3)] `docs/install-ipm.md`: one line that says the same: if a step fails after the code has loaded, the command reports the failure and names the step, the new code stays installed, and running the same command again finishes the install; a failure while IPM loads or compiles the code is rolled back and the previous version keeps running. Keep every existing rule of the document (real output, no local path, key or token).
- [x] [Owner U-176 (4)] Done by the lead: Story 15.3's criterion in `epics.md` carries the reading ("the load" means IPM's Reload, Validate and Compile phases), and 15.3 gains the named AC that the same forced-failure re-run also passes Story 15.3's own checks once they exist.

**Acceptance Criteria:**
- Given the first run has created OCUTALON, or `iris merge` and `zpm "enable -map -ns OCUTALON"` have, when the install command runs in OCUTALON, then the matrix rows "Second run, path A", "Install checks" and "Path B" hold: `release/ipm-install.sh a` and `b` pass. This is an Integration AC whose consumer is IPM's Configure Invoke, and its effect is a running OcuTalon.
- Given an IPM install, when its install checks and the web and REST checks run, then the rows "Web and REST" and "Package" hold.
- Given the IPM install with demo mode off, when `SetDemoMode(1)` and then `SetDemoMode(0)` run in a terminal session, then the row "Demo switch" holds.
- Given the production was started by anything but the `Production` step, when its items run, then `ReconcileIn` reconciles exactly once. Given the `Production` step started it, when its items run, then `ReconcileIn` does nothing and only the installer's `Reconcile` step reconciles. These are the rows "Start outside the step" and "Start by the step"; the Integration AC's consumer is an `Ens.Director` start from a session.
- Given the Docker image, whose `docker/after-start.cos` loads the package and then runs `Registry.Run("after-start")`, when a throwaway stack starts, then `Ipm()` runs no step during the load, the production is not autostart, and every live unit passes:
  - the `(once)` units of `## Verification`, among them `live install-start`, `live production` (its row 13 asserts `^Ens.AutoStart` empty) and `live reminder-restart` (its `WARN Reconcile` line);
  - and `Test.Install.Registry.TestIpmOnTheImage`.
  This is an Integration AC.
- Given the manifest, when `bash docker/tests/test-cpf.sh` runs, then rules 1-8 pass, and `test-pinned-sources.sh`'s `bridge_first` still pins the bridge's resources first.
- Given an instance whose `PasswordValidationRoutine` is "" or names a foreign routine, when the install runs with the online-demo flag off, then the setting is unchanged and the foreign routine still exists. This holds in `Test.Install.Users.TestForeignGuardIsRefused`, and on the IPM install in path A ("") and path B (foreign) (DW-212).
- Given the captured output of a passing run, when `docs/install-ipm.md` is read, then it covers every point of its task, its output blocks equal that run's `OUTPUT` blocks with ANSI codes removed, and `bash docker/tests/test-boundaries.sh` passes.

- Given an IPM reinstall in OCUTALON where one installer step fails after the commit (a test-only scratch copy of the package), when the install command runs, then it reports the failure, prints one Install-style line naming the step that says the new code is installed and to run the same command again, keeps the data, OCUTALON and its databases, and the same command with the real package then completes and passes the checks of Stories 15.1 and 15.2 (U-176 (1), (2)).
- Given an IPM reinstall whose Compile fails (a test-only scratch copy), when the install command runs, then IPM rolls it back and the previous version keeps running (U-176 (2)).
- Given `docs/install-ipm.md`, when it is read, then one line says what a failed step after the load means and that running the same command again finishes the install (U-176 (3)).

### Review Findings

Code review of 2026-10-31, the story's first review (`baseline_commit` 7fd58499 to HEAD 904e6d11 plus QA's uncommitted work). Layers: blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all on the session's model. 37 rows; 18 entries after grouping (high 1, medium 2, low 15); 15 rows rejected. Every patch was applied in this review, and three lows are closed in the ledger.
- [x] [Review][Patch] (high, fix-risk low) Rule 9's ANSI sample had no ESC byte: `sed "s/.../\033[32m.../"` gives `0`/`\0` text, not ESC. On GNU sed (the hosted `checks` job, ubuntu-24.04) the doctored line still parses as `STEP Reconcile OK`, so "rule 9 on samples" FAILED and CI would go red [docker/tests/test-cpf.sh:320]. Fixed: the sample now appends a real ESC line built with `printf '\033'`. `test-cpf.sh` passes under BSD tools and in `ubuntu:24.04` (it failed there before the fix).
- [x] [Review][Patch] (medium, fix-risk low) The failed-reconcile path of `ReconcileIn` had no pinning test: one Error row, one Warning row per warning, no Info row, the job's ids put back, and no repeat (the error column of matrix row "Start outside the step") [src/ocutalon/cls/OcuTalon/Test/Install/ReconcileIn.cls:52]. Fixed: `TestFailedReconcile` polls a shadow instance over a fixture area whose `Reconcile` warns, changes the ids and fails. Two mutations are recorded under Verification.
- [x] [Review][Patch] (medium, fix-risk low) U-176 (2) asks that the recovery run pass "the checks of Stories 15.1 and 15.2". Neither the second run nor the recovery run compared OCUTALON's configuration with the first run's, which is Story 15.1's check 3 [release/ipm-install.sh:340]. Fixed: `check_second_run` also runs `same_config` against snapshot `first`. The full job passes 97 checks, and the mutation is under Verification.
- [x] [Review][Patch] (low) Rule 9 passed a document that lacks a step the order gained, and it wrote an unused `order.names` [docker/tests/test-cpf.sh:306]. Fixed: the STEP lines must give every name of `Registry.Order()` once, in order, and a new sample covers that. Mutation under Verification.
- [x] [Review][Patch] (low) The `ReconcileIn` doc said a start by the step is always reconciled by the `Reconcile` step that follows it. When the `Production` step fails after starting, the run stops before that step, and only the re-run that the failure asks for reconciles [src/ocutalon/cls/OcuTalon/Install/ReconcileIn.cls:6]. Fixed in the contract. The behaviour itself is by design.
- [x] [Review][Patch] (low) StartLock had an assertion that could not fail on its own: a second `Starting()` while the lock is held [src/ocutalon/cls/OcuTalon/Test/Install/StartLock.cls:35]. Removed. The TryLock part pins "the probe takes nothing".
- [x] [Review][Patch] (low) StartLock did not assert its lock-free shadow instance, so that half could be skipped and still pass [src/ocutalon/cls/OcuTalon/Test/Install/StartLock.cls:65]. Fixed.
- [x] [Review][Patch] (low) `check_web` could read a sign-in page that an earlier call left behind (the recovery run) [release/ipm-install.sh:388]. Fixed: the file is removed before the GET.
- [x] [Review][Patch] (low) "Start by the step" passed on two empty counts, and the demo switch's namespace comparison passed on two empty lists [release/ipm-install.sh:529, :289]. Fixed: the check requires a count, and each list must name USER.
- [x] [Review][Patch] (low) Rule 2: the `Registry.Order()` query was pasted four times in the script [release/ipm-install.sh:224]. Fixed with `registry_order`.
- [x] [Review][Patch] (low) Two descriptions were stale: the mode help said `a` runs checks 1 to 14, and the job step was named "Run the first install run and the merge" [release/ipm-install.sh:62, .github/workflows/lane-a.yml:58]. Fixed.
- [x] [Review][Patch] (low) The document never mentioned `WARN` lines, although path B prints `WARN Demo` [docs/install-ipm.md:58]. Fixed with one clause: a warning does not fail the step (AD-23).
- [x] [Review][Patch] (low) The document's precondition did not say that IPM is in %SYS, which the `iris merge` path's `zn "%SYS"` needs [docs/install-ipm.md:7]. Fixed to match the measured precondition (check 1).
- [x] [Review][Patch] (low) The document said path B "gives the same OcuTalon", which is more than path B checks [docs/install-ipm.md:126]. Fixed: path B runs the same installer steps.
- [x] [Review][Patch] (low) The document said the first run "does not load any OcuTalon code", directly above output that compiles `OcuTalon.Install.Ipm` [docs/install-ipm.md:27]. Fixed: the run leaves no OcuTalon code installed, as check 4 shows.
- [x] [Review][Defer] (low, fix-risk med) No unit test covers `ReconcileIn`'s caller path with `ByStep` 0: `NotRunning()` passed into `Next`, and the one warning [src/ocutalon/cls/OcuTalon/Install/ReconcileIn.cls:55]. Deferred: DW-475 `wontfix-accepted`, with the `reopen_if` probe in the ledger. A down item in a unit test would need a TempStop of a live production item.
- [x] [Review][Defer] (low, fix-risk med) A start-lock window: `Ens.Job.Start` registers a job, which `NotRunning()` counts as alive, before its `OnInit` runs, so the step can release `STARTLOCK` before `ReconcileIn` probes it [src/ocutalon/cls/OcuTalon/Install/Step/Production.cls:99]. Deferred: DW-476 `wontfix-theoretical`. It has never been observed: "start by the step" stayed flat in every run, including this review's (1 to 1, 2 to 2), and a second reconcile is idempotent (AD-5). The ledger names the probe and the fix.
- [x] [Review][Defer] (low) AD-23's sentence "WARN ... in the after-start log only" predates the IPM path, where `Run` prints warnings to the command's output, and path B's `WARN Demo` check reads them there. Deferred: DW-477 `by-design` (spec-bound), noted for the lead's next spine update (Rule 20).

**Rejected:**
- `[low]` blind 2: `ReconcileIn` reconciles again when only its own job restarts. The areas' reconciles are idempotent (AD-5), an item-only restart is rare, and a latch would need new state.
- `[low]` blind 3: the 30 s lock wait inside a poll can overlap a restart's 30 s stop. The 30 s is the task's own value, and the window is the few seconds after a start that no installer made.
- `[low]` blind 4 and auditor 2: no live instance restart, and the document's restart sentence. Restarts are Story 15.3's (out of scope). The sentence states AD-3's design, and the real-output rule covers the output blocks.
- `[low]` blind 5 (the `Start` part): the lock-timeout failure and the release after a throw have no unit test. The first is a 60 s wait, and a process's locks are released when it ends.
- `[low]` blind 6 (part): deleting the second command's code block keeps rule 9 green. The Configure output block stays, and no realistic edit does that.
- `[low]` blind 7 (part): two formats of the failure line. Both are printed, the step's own line and then `FailureLine`, and line 107 is the owner's wording (U-176 (3)).
- `[low]` blind 8 (part): the privileges the install needs. Nothing below `%All` was measured.
- `[low]` blind 9 (part): the 120 s margin between deadline 1980 s and the 35-minute timeout. These are the spec's own values (item 16), and rule 7 keeps the deadline inside the timeout.
- `[low]` blind 11: `Ipm` commits transaction levels it does not own. This is spec-bound (the task and the "IPM steps" row commit to level 0), and no package depends on `ocutalon`.
- `[false]` auditor 3 (b): a reconcile in progress would make a new start look like the step's. The lock holder is a job of the previous production. It ends before the next start's items initialize, and its lock is released with it.
- `[low]` auditor 5: `ReconcileIn` does not wait for runner models. The task text and AD-23 say "once the items run"; the Code Map line is spec text.
- `[low]` edge 4: an unlock inside a transaction is deferred. No caller runs in one, because `Ipm` commits to level 0 first. Theoretical.
- `[low]` edge 5: `Start(wait)` waits `WAITSECONDS` for the lock. That is the task's own value.
- `[low]` edges 6 and 7: a lock that is never obtained, and an exception on every poll. Only `Start` holds the lock and always releases it, and nothing outside `Reconcile` throws repeatedly. Theoretical.
- `[low]` edge 8: a step that leaves a transaction open. No step opens one (already adjudicated in implement's review).
- `[low]` edge 9: `TempFilename` returning no file in `TestIpmOnTheImage`. It creates the file, and the assertion before the call already fails loudly. Theoretical.
- `[low]` edge 10: StartLock's holder job takes the lock after the 10 s wait. That needs something else holding the start lock for 10 s at test time. Theoretical.
- `[false]` gap, other 2: QA's files are uncommitted. The lead commits them after the smoke gate; this stage may not commit.
- `[low]` gap, other 3: the shared-surfaces list misses `Test/Bridge/Approval.cls:622` and `Test/Agent/Models.cls:65`. Neither asserts the old shape (the lock is uncontended there), and the fix would edit the spec.

Rule 3: the deliverables are an install command and its document. `release/ipm-install.sh` runs the real commands on throwaway instances and asserts output, HTTP status codes and bodies, and side effects (97 checks in this review). Rule 6: no AD is contradicted. I checked AD-2, 3, 5, 19, 22, 23, 24, 29 and 33 and the "IPM steps" and `ReconcileIn` rows; the only issue is the wording note DW-477.

## Spec Change Log

- 2026-10-31, after the first implement pass (lead): the owner decision U-176 (via the Contest Planner, answer 2026-10-31T00:05:17Z#534) kept the commit at Configure, After, with conditions; the lead re-opened the spec (`in-progress`) with the four `[Owner U-176]` items and their acceptance criteria. The answer U-177 (#535) kept the Lane B routing and named Story 31.1 as the first owner of DW-34, DW-207 and DW-223.

- 2026-10-31, spec gate (lead): the orchestrator's ruling U-177 (option B) removed the task group "Cross-lane (AD-33), awaiting the orchestrator's ruling", its acceptance criteria, its verification line, its three mutation rows and its shared surfaces; DW-34, DW-207 and DW-223 are declined (moved to Story 31.3). The Lane A scope, DW-212 included, is unchanged. The spine rows "IPM steps" and the `ReconcileIn` ownership row were written at this gate (veto U-176 for the step-failure reading).

## Review Triage Log

### 2026-10-30 — Review pass
- verdicts: 23 findings — high 0, medium 3, low 19, false 0, maybe-false 1 (blind hunter 9, edge-case hunter 11, verification-gap 5 plus 4 others after merging duplicates across layers; intent alignment reported descriptively, no findings)
- findings:
  - `[low]` `[patch]` path B guard in `release/ipm-install.sh` reads the cumulative `$fails`, so a failed path A check aborts path B with the wrong message (blind, edge) - fixed: the guard compares `$fails` with its value before the IPM load.
  - `[medium]` `[patch]` `TestAutoStart` kills `^Ens.AutoStart` with its subnodes and leaves `LastProduction` (blind, edge, gap) - fixed: the subtree and `LastProduction` are saved with `Merge` into process-private globals and put back in `OnAfterOneTest`.
  - `[low]` `[reject]` a failed reconcile is never retried (blind, edge) - by design: the spec says a failed reconcile is one `$$$LOGERROR` row, and a retry every poll would log one per 5 s; the class doc now says it is not repeated until the item starts again.
  - `[low]` `[patch]` `ReconcileIn` queries `NotRunning()` on every poll even when it will skip (blind) - fixed: asked only while neither `ByStep` nor `Done`.
  - `[medium]` `[patch]` `Registry.Ipm` non-image branch (commit loop, reopened levels, failure) has no unit test (blind, gap) - fixed: `Test.Install.Registry.TestIpmRunsTheSteps` on the probe registry, with two mutation lines.
  - `[low]` `[reject]` `Run` leaves `^||OcuTalonStepCaller` set if a step throws (blind, edge) - `RunStep` catches every exception, so nothing escapes the loop; `Ipm`'s own Catch kills it for the rest.
  - `[low]` `[patch]` `docs/install-ipm.md` names "the test instance of the repository's install check" (blind) - fixed: "a new instance". The node name in the captured output stays, because the output is copied unchanged.
  - `[low]` `[reject]` the document has no removal or troubleshooting section (blind) - beyond the spec's list of points, and removal is not measured.
  - `[low]` `[reject]` the `${cspdir}` mutation proves less than its label (blind) - already recorded in "Measured in implement" and replaced by a mutation that does go red.
  - `[maybe-false]` `[reject]` `ReconcileIn.OnInit` could see the lock free if an item is Alive before its `OnInit` runs (edge) - "Start by the step" passed in every run (no extra row); a double reconcile is idempotent (AD-5), so at most low.
  - `[low]` `[reject]` `Done` resets when the `ReconcileIn` job restarts alone (edge) - a restart of the item is a start of that item; the areas' `Reconcile()` are idempotent (AD-5).
  - `[low]` `[reject]` `Ipm` should commit levels a step left open (edge) - no step opens a transaction; theoretical.
  - `[low]` `[patch]` the document says the first command can be run again "in any namespace" (edge) - fixed: USER or %SYS, and in OCUTALON it is the second run.
  - `[low]` `[reject]` the document says nothing of a kept foreign OCUORDERS under Demo mode (edge) - the effect of `SetDemoMode` on it is not measured; a claim would be unmeasured text.
  - `[low]` `[reject]` the chat poll loop does not stop on a non-202 (edge) - costs 90 s on a red run only.
  - `[low]` `[reject]` rule 8 accepts the Invoke inside an XML comment (edge) - theoretical; the manifest has no comments.
  - `[medium]` `[patch]` the `Run` to `Caller()` to `AutoStart` handoff is not asserted in a unit test (gap) - fixed: `TestIpmRunsTheSteps` records `Caller()` in a fixture step for "ipm" and "after-start" and asserts none is left.
  - `[low]` `[reject]` `ReconcileIn.Reconcile` wiring (id restore, warnings) is pinned only by an Info-row count (gap) - Task 0 measured the in-job reconcile; a unit test needs a stubbed step; no failure shown.
  - `[low]` `[patch]` the chat check accepts a done turn with no decision (gap) - fixed: `n/a` now fails; the run shows the mock turn carries a decision.
  - `[low]` `[patch]` ACs without a mutation line from a non-Lane-B change (gap) - fixed: install checks, autostart and package, and path B each have a demonstrated mutation. "Demo switch" and the `/state`, `break-feed` and chat parts of "Web and REST" can only be mutated in Lane B classes (U-177) and stay without a line.
  - `[low]` `[patch]` `TestIpmOnTheImage` and the Task text claim no unit test calls `Run` (gap, other) - fixed in the test's doc; `TestIpmRunsTheSteps` now calls it over fixture steps.
  - `[low]` `[reject]` `TestIpmOnTheImage` assumes `$TLevel` 0 at its start (gap, other) - the unit-test manager opens no transaction; `TestIpmRunsTheSteps` uses a base level.
  - `[low]` `[reject]` the Demo-switch comparison excludes names that start with `OCUORDERS` (gap, other) - recorded in "Measured in implement"; path B's `foreign_orders` covers a foreign one.

### 2026-10-30 — Review pass (rework: owner decision U-176)
- verdicts: 31 findings — high 0, medium 9, low 20, false 2, maybe-false 0 (rows group findings by layer and number: blind 6, edge 11, gap 8, intent 6)
- findings:
  - `[low]` `[patch]` blind 1, edge 8, gap 3: a `Run` that fails without a failed step (refused namespace) or throws has no test for "no failure line" — added `Test.Install.Registry.TestIpmWithoutAFailedStep` (two cases) and its mutation line (dropping the `failed '= ""` guard goes red).
  - `[low]` `[reject]` blind 1 (the thrown-`Run` half), edge 7: no line when `Run` itself throws — `RunStep` catches a step's exception, so `Run` throws only on a platform fault; the owner's condition names a step, and the test now pins the behavior.
  - `[low]` `[reject]` blind 2, edge 10, gap 8: the 2-minute margin between deadline 1980 s and `timeout-minutes: 35` — the values are the spec's own 8-minute rule (item 16); `test-cpf.sh` rule 7 pins the deadline inside the timeout.
  - `[medium]` `[patch]` blind 3, gap 4: the failed-compile check accepted any `ERROR!` line — the check now also requires the undefined macro's name in the output (red when the scratch class compiles, shown by the mutation run).
  - `[medium]` `[patch]` blind 4, edge 1, edge 2, gap 7: the module version `0.1.0` was hard-coded in three places, so the planned v0.1.1 bump would redden the job and make the compile copy's version equal the real one — the script now reads the real version and raises its patch number.
  - `[low]` `[reject]` blind 5: the document says a Reload or Validate failure is also rolled back, though only Compile is exercised — the wording is the owner's (U-176 (3)) and the lead's reading of "the load" in `epics.md` (item 4).
  - `[low]` `[reject]` blind 6: new spec items 14-16 sit before 12-13 — cosmetic, and the fix edits this build's spec.
  - `[low]` `[reject]` edge 3: the scratch-compile copy checks only the last output line — with `set -e` a failed step aborts, and the new cause check goes red if the broken class is missing.
  - `[false]` `[reject]` edge 4: the `Audit` row `sed` matches nothing when Audit is first or last — Audit is mid-order, and a non-match makes `want` equal the order, so the check fails loudly.
  - `[false]` `[reject]` edge 5: a WARN line between the step's line and the failure line — the Audit seam returns before any `Warn`, and `Run` writes warnings after the step's line, where this seam has none.
  - `[low]` `[reject]` edge 6: the `Write` of the failure line throws inside the `Try` — a device error on the terminal; theoretical.
  - `[low]` `[patch]` edge 9: `IpmCaptured` left its temp file when the open failed — the capture file is deleted on that path.
  - `[low]` `[patch]` edge 11, gap 6: the header of check 16 claimed the module is recorded with the scratch copy's version, which no check reads — the claim is removed.
  - `[medium]` `[patch]` gap 1, gap 2, gap 5: no `mutation:` lines for the forced-failure seam, the failed-compile seam, the kept data and the recovery run — each mutation was applied, seen red and reverted (the diff hash equal before and after), and the five lines are in `## Verification`.
  - `[low]` `[reject]` intent 1: the failing run is `zpm "load <scratch>"` and the re-run the documented command, not a repeat of the failing command — the scratch folder is the test-only seam; the documented command is the install command the line tells the user to run.
  - `[low]` `[reject]` intent 2: "the new code" is the scratch Audit class at the same version, not a newer version — IPM refuses a lower version over a higher one (measured), and `Audit.Run()` returning the scratch error shows the loaded code is the one in place.
  - `[low]` `[reject]` intent 3: no 15.3 AC in the diff — the lead added it in `epics.md` (item 4), outside this story's files.
  - `[low]` `[reject]` intent 4: the production's state at the failed point is not asserted — it is asserted after the recovery run and in the failed-compile case; the owner's conditions do not ask for it.
  - `[low]` `[reject]` intent 5: two `STEP <name> FAILED` lines per failure — the first is `Run`'s existing line, the second is the owner's added line; the script's `step_names` skips it.
  - `[low]` `[reject]` intent 6: the document's captured-output blocks show no failure — the owner asked for one line, and the real-output rule covers the captured runs.

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: one package, the bridge's resources first, no dependency.
- AD-3: the mappings and their install checks, OCUORDERS owned by the Demo step, and an IPM install marking autostart.
- AD-5: every reconcile is idempotent, and the startup reconciler re-arms waiters.
- AD-18: read only; DW-34 (the instance zone where TZ is unset) moved to Lane B (U-177), so this story changes no zone code.
- AD-19: keys only from the environment, and the `demo.mode` seed is "0" off the image.
- AD-22: destructive work only on throwaways.
- AD-23: the IPM install runs the same steps, `Production` marks autostart, and every production start reconciles.
- AD-24: the README account, and the guard only with the online-demo flag on (DW-212).
- AD-29 and AD-33: lanes, and a new item's owner.

No AC contradicts an AD.

**Measured at plan** (2026-10-30, developer machine, ARM, lane B; throwaways `e15s2pm1` and `e15s2pm2`, both torn down by their trap). The probe copied the package into `/tmp/probe` and added a class calling `Registry.Run("ipm")` from `<Invoke ... Phase="Configure" When="After"/>`.
- **Inside IPM's transaction it fails.** The probe ran with transactions suspended, at `$TLevel` 1.
  - Every step up to `Telegram` reported OK, then `STEP Production FAILED ERROR <Ens>ErrCanNotAcquireRuntimeLock: Could not acquire runtime global lock within timeout '30'`. IPM printed `Configure FAILURE`, `Activate FAILURE` and `ERROR! ...`, and rolled back the classes and the module record.
  - The steps' %SYS writes and the copied bundle stayed behind.
- **After `TCommit` to level 0 it works.**
  - Every `STEP ... OK` line printed, in order, inside `Configure START`/`SUCCESS`, and the steps took 1.6 s. `TStart` back to level 1, then IPM's commit, gave `Activate SUCCESS`.
  - Afterwards: the production was running with nothing missing, `^Ens.AutoStart` was empty, the module was `0.1.0` with 0 dependencies, and the bundle was in `DataDirectory()_"csp/ocutalon-web/"`, which is also the `/ocutalon` Path.
  - `demo.mode` was 0, OCUORDERS was absent, `OcuTalon.Test.Agent.RunnerFixture` was compiled, and the bridge example was compiled but not running.
- **Running the same load again** (IPM's update path) ran Configure and every step again, all OK.
- **Times:** ready 7 to 22 s, IPM load 13 to 15 s, first run 25 to 29 s, second run 29 s, and again 30 s.
- **Instance settings:** `EnsembleAutoStart` is 1 on the base image. `DataDirectory()` is `/usr/irissys/` and `ManagerDirectory()` is `/usr/irissys/mgr/`.
- **A session `StopProduction`/`StartProduction`** worked, with every item running after 5 s.
- **DW-34 is real.**
  - With TZ unset and `/etc/localtime` changed from `Etc/UTC` to `America/New_York`:
    - `TimeZone()=-1`;
    - `Data.Time.Zone()=UTC`;
    - `ToLocal("2026-01-15T12:00:00Z")=2026-01-15T07:00:00` and July gives `08:00:00`;
    - `$ZTimeZone=300`;
    - `ResolvePath("/etc/localtime")` gives `/usr/share/zoneinfo/America/New_York`.
  - The base image's `/etc/localtime` points at `Etc/UTC`.

**Measured in implement** (2026-10-31, developer machine, ARM, lane B; throwaway tag `e15s2i`, torn down; `release/ipm-install.sh a` passed with 42 checks, `b` with 30).
- `TIME` lines of `a`: ready 12 s, first run 31 s, repeat in USER 2 s, in %SYS 3 s, Shell() 4 s, second run 34 s, demo on 1 s, demo off 5 s, stop and start 0 s, Registry.Run("ipm") 1 s. `b`: ready 12 s, first run 36 s, ready (second stack) 15 s, merge 31 s, enable 1 s, second run 33 s. The two together stay well under 8 minutes, so `lane-a.yml` is unchanged.
- Task 0 confirmed: `/ocutalon/` is served on the published port; `irisowner` (OS login, `%All`) may call `SetDemoMode`; `keys_point` and `keys_restore` work on this stack (the chat turn is done with no `fallbackReason`); `ReconcileIn` reconciles inside its production job with the session ids restored (one Info row after a session's start, no second one after three more polls), so the fallback of a `JOB` process was not needed.
- The second run's output has `Activate START` before `Configure START`, and `Activate SUCCESS` after `Configure SUCCESS`; the 15 `STEP` lines sit between `Configure START` and `Configure SUCCESS`.
- USER and %SYS hold no OcuTalon class, routine, module record or `^OcuTalon` global after the second run: no step writes such an item there by design, so the check excludes none.
- `Config.Namespaces` lists the databases `OCUORDERS_CODE` and `OCUORDERS_DATA` as namespaces while they exist, so the demo-switch check of "the instance's other namespaces" leaves out every name that starts with `OCUORDERS`.
- IPM's `%IPM.Storage.Module` table name is a reserved word in SQL; the package check reads the table name from the compiled class (`SqlQualifiedNameQ`).
- Path B needs IPM loaded on the fresh instance before `zpm "enable -map -ns OCUTALON"`, so the script loads `zpm-0.10.10.xml` first and takes the services baseline after it.
- `${cspdir}` and `${dataDir}csp/` are the same folder (`/usr/irissys/csp/`) in this image, so the planned mutation "FileCopy target `${cspdir}`" stays green here; the bundle-path mutation uses another target folder name instead.

**Not measured, so inference:**
- x64 time: `a` plus `b` will take about 6 minutes locally and about 15 to 17 minutes on the runner, inside the job's 30 minutes.
- `ReconcileIn`'s in-job reconcile; Task 0 confirms it.
- The plain IRIS image.
- `EnsembleAutoStart` set to 0 on an admin's instance would stop the autostart; OcuTalon never changes it.

**Decided in-stage:**
1. **The entry point is `Registry.Ipm()` at Configure, After.**
   - Configure runs on every `load` and update after Compile and the bundle copy (measured). `zpm "ocutalon configure"` also reaches it, with no transaction.
   - Committing is the only measured way to start the production from the command. A failed step then leaves the new code installed and the next command runs the steps again, as on the Docker path.
2. **Nothing happens on the image.** The version file is the image's marker, the same `VERSIONFILE` that seeds `demo.mode`. This leaves `docker/after-start.cos` unchanged and runs no step twice.
3. **Autostart is marked after a successful start, on `ipm` only.** The Docker path neither marks nor clears it.
4. **The caller reaches the steps through `Install.Step.Caller()`.** This is the process-private pattern of `Warn`, so no step's `Run()` signature changes.
5. **"Every start" is delivered by a lock and an item.**
   - `Production.Start` holds a start lock, and `ReconcileIn`'s `OnInit` probes it.
   - The lock is in `Start`, not `Registry.Run`, so every test that calls `Production.Start` directly keeps its own reconcile counts. Examples are `Test.Schedule.Reminders` :1023 and `Test.Agent.Conversation` :158.
   - The item, not `OnStart` in the production class, because `OnStart` runs before any item job and the class holds structure only (AD-5).
   - Polling every 5 s; one warning after 60 s of waiting.
6. **`ReconcileIn` lives in `OcuTalon.Install`.** It composes the installer's own `Reconcile` step. The package isn't in `LaneOfClass`, so the test gets a name entry, as `OcuTalonApprovals` has.
7. **`release/ipm-install.sh a|b`** keeps each local call well under the 10-minute cap. The job's call has no argument, which keeps rule 6.
8. **Path B is "an instance with its own things".** The foreign guard and the foreign OCUORDERS are its fixtures. Path A proves "none stays none".
9. **The document shows the tested `load` form.** The registry form and its output are Story 15.3's, after the registry check.
10. **The chat check reuses `keys_point` and `keys_restore`,** the CI path of every other mock check. The package carries `Test.Agent.RunnerFixture` (measured).
11. **The new tests go in the Install area.**
    - The `Test.Install` class changes run in `shards`' piece `lane-a@Checks,Install,Watch`, because the pieces are cut by area. `Test.Install.ReconcileIn` is pure and takes under 1 s.
    - `ci/units.sh` doesn't change.
14. *(U-176 (1))* `Registry.FailureLine(step)` is the suggested text, `STEP <step> FAILED: the new OcuTalon code is installed. Run the same install command again.`; the step is `Run`'s new `Output failed` (the first failed step); with no failed step (a refused namespace) `Ipm` writes no extra line.
15. *(U-176 (2))* The script's seam is a scratch copy in the container: one with `Install/Step/Audit.cls` returning an error (version kept, because IPM refuses a downgrade: "Cannot downgrade ocutalon from version 0.1.1 to 0.1.0"), one with `Install/ZzScratchBroken.cls` (an undefined macro, so Compile fails), a changed `Registry.Order()` and version 0.1.1. "The new code is installed" is read as `Audit.Run()` returning the scratch error. New argument `r` (A's first and second run, then the reinstalls); `a` = checks 1 to 14.
16. *(U-176 (2))* `a` 144 s, `r` 258 s, `b` 137 s (539 s summed, over 8 minutes; the full job measured 433 s), so job `ipm-install` of `lane-a.yml` has `timeout-minutes: 35` and `OCUTALON_LIVE_DEADLINE: "1980"`.
17. *(U-176 (1))* A `Run` that returns an error without a failed step (the refusal of another namespace) or throws gives `Ipm`'s error status and no failure line; `Test.Install.Registry.TestIpmWithoutAFailedStep` pins it.
18. *(U-176 (2))* The script reads the module's real version and raises its patch number for the compile copy, so a release bump needs no edit; the compile check also requires the undefined macro's name in the output.
12. *(Withdrawn by U-177: DW-207 moved to Lane B.)*
13. *(Withdrawn by U-177: DW-34 moved to Lane B.)*

**Cross-lane ruling (U-177, the orchestrator, 2026-10-31, option B).** The cross-lane group left this story (moved to Lane B; the answer of 2026-10-31T00:05:17Z#535 kept the routing and named Story 31.1): no Lane B class or Lane B test is edited, `Test/Core/SettingsOps.cls` is left alone, and no AD-18 or AD-33 text changes. The plan's measured DW-34 facts above stay as a record for Story 31.3.
- Declined DW-34 (moved to Lane B (U-177): Lane B classes, AD-33)
- Declined DW-207 (moved to Lane B (U-177): Lane B classes, AD-33)
- Declined DW-223 (moved to Lane B (U-177): Lane B classes, AD-33)

**Ledger inbox (Rule 17):**
- DW-212 is addressed by the `Test/Install/Users.cls` task and matrix row "Path B".
- DW-34, DW-207 and DW-223 are declined above (U-177) and re-owned by the orchestrator to `31-1-push-live-events-over-a-websocket-on-local-installs`, the first Lane B story inside 1.0.0 that runs with their files free (DW-207 only once Epic 9 has merged; else the next Lane B story, 31.3 at the latest).

**Integration ACs, Consumed-by and Consumes (Rules 1 and 2).**

The Integration ACs: IPM's Configure Invoke running the install command, an `Ens.Director` start from a session, and the Docker after-start load.

Consumed-by:
- **Story 15.3:**
  - the restart test relies on the autostart mark and on `ReconcileIn` re-arming waiters;
  - the reinstall goes through the same Invoke, whose update path was measured;
  - DW-80's production-alone restart is `ReconcileIn`'s path.
- **Story 31.3** builds the README's IPM section from `docs/install-ipm.md`.
- **Stories 19.2 and 34.1** run on this IPM install path.

Consumes:
- Story 15.1's CPF resource, `MapAndStop`, `release/ipm-install.sh` and its image;
- `Registry.Order()` and every step;
- every area's `Reconcile()`;
- `Core.Admin.SetDemoMode`;
- lib-live and lib-online;
- `Test.Agent.RunnerFixture`;
- the CI model mock.

**Extend, don't copy (Rule 2):**
- `ReconcileIn` calls `Install.Step.Reconcile.Run()` and `Production.NotRunning()`, and copies only `StartHold`'s save and restore of two job ids. That is 10 lines in a contended bridge file it can't call for this.
- `Ipm()` and `MapAndStop` differ on purpose: one commits, the other suspends.
- `residue` gets a scope rather than a copy.
- `release/ipm-install.sh` copies about 15 lines of curl and state parsing from `test-demo-switch.sh`, whose helpers are local to that Lane B script. The shared libraries are contended, so no common helper can be made there now.

**Architectural weight, for the lead (Rule 20):**
- A Conventions row, "IPM steps":
  - The Configure, After Invoke `Registry.Ipm()` does nothing on the image.
  - Elsewhere it commits IPM's transaction (measured: `ErrCanNotAcquireRuntimeLock` inside it), runs `Run("ipm")` and opens the levels again.
  - A Reload, Validate or Compile failure is still rolled back. A step failure leaves the new code installed, and the next command runs the steps again.
  - Story 15.3's "if the load fails part-way, IPM rolls it back" therefore reads as the load phases.
- **The ownership-table row** `ReconcileIn` | `OcuTalon.Install.ReconcileIn` | A (AD-33). A note on AD-23's "every production start ... runs Reconcile": the `Production` step's start lock and `ReconcileIn`.

**Footprint extension, for the lead:** `src/ocutalon/cls/OcuTalon/Production.cls` (Lane A region), `src/ocutalon/cls/OcuTalon/Test/Install/**` and `docs/`.

**Shared-by-region files:**
- `src/ocutalon/cls/OcuTalon/Production.cls` (Lane A region only);
- `src/module.xml`;
- `Test/Install/Production.cls`'s oracle, where Epic 30 may also add rows.

## Verification

Run every `[L]` command from the epic-15 worktree root, in the foreground, one per call, with `timeout: 600000`. Prefix each with:

`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=15 stage=implement' OCUTALON_RUN_TAG=e15s2i`

Every `[L]` command uses only fresh throwaways. The `class` and `shard` calls are not warm, because the production and the steps change; `Test.Install.Users` is destructive. End with `[L] bash ci/iris.sh teardown`, also after a failure.

**Commands:**
- `bash docker/tests/test-cpf.sh` (loop): every PASS, exit 0.
- `bash docker/tests/test-pinned-sources.sh` (loop): `all checks passed`.
- `bash docker/tests/test-boundaries.sh` (loop): exit 0.
- `[L] bash ci/iris.sh build` (loop; first on every pass that runs IRIS): `BUILD the web bundle is built`.
- `[L] bash ci/iris.sh class OcuTalon.Test.Install.Registry` (loop): `CLASS ... passed`.
- `[L] bash ci/iris.sh class OcuTalon.Test.Install.Production` (loop): passed.
- `[L] bash ci/iris.sh class OcuTalon.Test.Install.ProductionRules` (loop): passed.
- `[L] bash ci/iris.sh class OcuTalon.Test.Install.ReconcileIn` (loop): passed.
- `[L] bash ci/iris.sh class OcuTalon.Test.Install.Users` (loop): passed.
- `[L] bash release/ipm-install.sh a` (loop): `ipm-install: all checks passed`, with the `OUTPUT` and `TIME` lines.
- `[L] bash release/ipm-install.sh b` (loop): `ipm-install: all checks passed`.
- `bash ci/checks.sh` (once): no `checks: failed`.
- `[L] bash release/ipm-install.sh` (once), only when `a`'s and `b`'s `TIME` lines sum to under 8 minutes; otherwise CI's job is its first full run: all checks passed.
- `[L]` (once), one call each, every one expected to pass:
  - `ci/iris.sh live install-start`, `live bundle-folder`, `live online-session`, `live online-allowance`, `live cards`;
  - `live install-upgrade`, `live audit`, `live online-demo`, `live demo-switch`;
  - `live production`, `live production-restart`, `live reminder-restart`;
  - `live demo-path`, `live sign-in --part 1/2`, `live sign-in --part 2/2`, `live answers`;
  - `shard lane-a@Checks,Install,Watch`, `live floor`;
  - `shard lane-a@Agent,Bridge`, `shard lane-a@Fix,Tools,Digest`;
  - `live storage-roundtrip`, `live build-inputs`, `live compose-start`;
  - `shard lane-b@Contract,Core,Data,Demo`, `shard lane-b@Live,Msg,Schedule,Web`, `live install-script-live`.
- `[L] bash release/standalone-bridge.sh` (once): `all checks passed`.
- `[L] bash ci/iris.sh teardown` (once, last): a `TEARDOWN tag e15s2i` line.

**Planned mutations (Rule 19).** Apply each, see red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged. Then write the `mutation:` lines here.

| Mutation | Test that goes red | Pins |
|---|---|---|
| `Ipm()` runs `Run("ipm")` without committing | `ipm-install.sh a` (`STEP Production FAILED`, as measured) | second run |
| `Ipm()` returns OK at once | `ipm-install.sh a` (no STEP lines) | second run |
| `Ipm()` ignores the version file | `Test.Install.Registry.TestIpmOnTheImage` | image load |
| Delete the Configure Invoke line | `test-cpf.sh` rule 8, `ipm-install.sh a` | manifest |
| `AutoStart` marks for every caller | `Test.Install.Production.TestAutoStart`; `live production` row 13 (once) | Docker not autostart |
| `AutoStart` never marks | `ipm-install.sh a` autostart check | IPM autostart |
| `Start` takes no lock | `ipm-install.sh a` "Start by the step" | exactly once |
| `ReconcileIn` never runs `Reconcile` | `ipm-install.sh a` "Start outside the step" | every start |
| `Next` ignores the missing items | `Test.Install.ReconcileIn.TestNext` | once the items run |
| `ReconcileIn` item removed from `Production.cls` | `Test.Install.Production` oracle | item |
| `Unguard` also deletes the routine of a foreign setting | `Test.Install.Users`, `ipm-install.sh b` | DW-212 |
| FileCopy target `${cspdir}` | `ipm-install.sh a` (bundle, sign-in page) | bundle path |
| `Public.RunLocal` writes `onlineDemo` 1 | `ipm-install.sh a` ("Web and REST") | not the online demo |
| The Demo step's create skips the public mappings | `ipm-install.sh a` ("Demo switch") | demo on |

Mutation results (applied one at a time, red observed, reverted; `git status --short` and the `git diff` hash equal before and after each):
- mutation: `Ipm()` without the commit loop (`While 0`) -> red: `ipm-install.sh a` shows `STEP Production FAILED ... ErrCanNotAcquireRuntimeLock` and fails the second run, install, web and package checks.
- mutation: `Ipm()` returns OK at once -> red: `ipm-install.sh a` has no `STEP` line (14 checks fail, from "second run").
- mutation: `Ipm()` ignores the version file -> red: `Test.Install.Registry.TestIpmOnTheImage` ("the node is gone: Ipm committed nothing").
- mutation: delete the Configure Invoke line -> red: `test-cpf.sh` rule 8. (`ipm-install.sh a` was not run with this one: with no Invoke no step runs, which the "returns OK at once" run shows.)
- mutation: `AutoStart` marks for every caller -> red: `Test.Install.Production.TestAutoStart` (three asserts). `live production` row 13 was not run (parent's list).
- mutation: `AutoStart` never marks -> red: `ipm-install.sh a`, the second-run session check (the `autostart` value).
- mutation: `Start` takes no lock -> red: `ipm-install.sh a` "start by the step" (ReconcileIn's Info rows went 2 -> 3).
- mutation: `ReconcileIn` never reaches the run branch -> red: `ipm-install.sh a` "start outside the step" (rows 0 -> 0).
- mutation: `Next` ignores the missing items (`If 1 Quit "run"`) -> red: `Test.Install.ReconcileIn.TestNext` (six asserts).
- mutation: the `ReconcileIn` item removed from `Production.cls` -> red: `Test.Install.Production.TestDefinition` (the oracle: item count and item 19).
- mutation: `Unguard` also deletes the routine of a foreign setting -> red: `Test.Install.Users.TestForeignGuardIsRefused` ("and the foreign routine still exists"). `ipm-install.sh b` was not run with it.
- mutation: FileCopy target `${dataDir}csp/ocutalon-bundle/` (the planned `${cspdir}` is the same folder here) -> red: `ipm-install.sh a` (bundle, sign-in page, sign-in).
- mutation: `Ipm()` skips the reopening of the levels (`While 0` for the `TStart` loop) -> red: `Test.Install.Registry.TestIpmRunsTheSteps` ("and opens the level again", "and opens both levels again", the node written after the call).
- mutation: `Step.Caller()` always returns "ipm" -> red: `Test.Install.Registry.TestIpmRunsTheSteps` ("and the steps ran with the caller after-start", "no caller is left after the run").
- mutation: `src/cpf/ocutalon.cpf` without the `OcuTalonPublic` global mapping, and `AutoStart` marking `OcuTalon.BridgeExample.Production`, in one run -> red: `ipm-install.sh a` "install checks: the public package and global ...", "second run: ... is the autostart production", "package: ... not the autostart production", the sign-in page, and the first run's mappings.
- mutation: `Unguard` also deletes the routine of a foreign setting, on path B -> red: `ipm-install.sh b` "path B: the foreign password-validation setting and routine are unchanged" and "every STEP line ... OK".
- mutation: `Ipm()` without its `FailureLine` write -> red: `Test.Install.Registry.TestIpmRunsTheSteps` ("the last line names the step that failed", "written once") and `ipm-install.sh r` ("the line after the failed step is not the one install line").
- mutation: `Ipm()` writes `FailureLine("Ready")` on every path -> red: `TestIpmRunsTheSteps` ("and writes no failure line", "the last line names the step that failed").
- mutation: `FailureLine` without "the new OcuTalon code is installed" -> red: `Test.Install.Registry.TestFailureLine`.
- mutation: `Ipm()` writes the failure line without the `failed '= ""` guard -> red: `Test.Install.Registry.TestIpmWithoutAFailedStep` ("and writes no failure line, because no step failed (case 1)"; case 2, a throwing `Run`, stays green because the `Catch` path never reaches the write).
- mutation: the scratch Audit step returns OK instead of the error (the seam's step succeeds) -> red: `ipm-install.sh r`, "failed step": the IPM `FAILURE`/`ERROR!` check, the STEP-lines check, the one-install-line check and "the installed Audit class is not the scratch copy's".
- mutation: the scratch compile class is valid (the scratch Compile succeeds) -> red: `ipm-install.sh r`, "failed compile": the `Compile FAILURE` check, the cause check (the undefined macro is not named), "an installer step ran" and the rollback state check.
- mutation: the seeded status mark is cleared after the failed reinstall -> red: `ipm-install.sh r`, "failed step: the seeded status mark ..." and "recovery run: the seeded status mark ...".
- mutation: the recovery run loads the failing scratch copy again instead of the real folder -> red: `ipm-install.sh r`, "recovery run": the one-STEP-OK-line check, `STEP PrivateData OK`, the public settings, "start by the step", and "the Audit class is the real one again".
- Not run: "`Public.RunLocal` writes `onlineDemo` 1" and "the Demo step's create skips the public mappings": both are Lane B classes (U-177), which this stage does not edit, not even to mutate.

**QA additions (Rule 8, Rule 19).** Files: `src/ocutalon/cls/OcuTalon/Test/Install/StartLock.cls` (QA, new; area Install, so `shard lane-a@Checks,Install,Watch` runs it; no `ci/units.sh` change) and `docker/tests/test-cpf.sh` (QA, rule 9 for `docs/install-ipm.md`, in CHECK_SCRIPTS already). The "Demo switch" row and the `/state`, `break-feed`, OCUORDERS and chat parts of "Web and REST" are pinned by the checks of `release/ipm-install.sh`; their classes are Lane B (U-177) and were not edited, so the mutations below change the script's own conditions (a seeded state, a wrong expected value or a skipped switch) in a Lane A file, one run each. Each was applied, seen red and reverted; `git status --short` was equal before and after.
- mutation: the chat check no longer points the keys at the CI mock (`keys_point` skipped) -> red: `ipm-install.sh a`, "web: the chat turn's reply carries fallbackReason 'no_key'".
- mutation: a seeded state, `SetDemoMode(1)` run before the web checks -> red: `ipm-install.sh a`, "web: /state is 'false|true|guide,phone,mailbox'", "web: POST demo/break-feed answered '409'" and "web: OCUORDERS state is '1|1|1'".
- mutation: the expected "on" text is `MESSAGEOFF` -> red: `ipm-install.sh a`, "demo switch: SetDemoMode(1) did not print the MESSAGEON line".
- mutation: the public package mapping of OCUORDERS removed after the switch is on -> red: `ipm-install.sh a`, "demo switch: on, ... the public package and global are mapped" (1 of 6 values differ, `CHK|web`).
- mutation: a stray namespace created while demo mode is on -> red: `ipm-install.sh a`, "demo switch: the other namespaces or USER's mappings changed when demo mode went on" (and, as the stray stays, "... went off").
- mutation: `SetDemoMode(0)` skipped -> red: `ipm-install.sh a`, "demo switch: SetDemoMode(0) did not print the MESSAGEOFF line" and "after SetDemoMode(0) OCUORDERS state is '1|1|1'".
- mutation: the foreign OCUORDERS' routines database changed after the second run (path B) -> red: `ipm-install.sh b`, "path B: the foreign OCUORDERS changed, from 'OCUFOREIGN_DATA/OCUFOREIGN_CODE|11|00' to 'OCUFOREIGN_DATA/USER|11|00'".
- mutation: a service toggled after the second run (path B) -> red: `ipm-install.sh b`, "path B second run: a service changed".
- mutation: the expected `WARN Demo` namespace is another name -> red: `ipm-install.sh b`, "path B: no single WARN Demo line that names OCUORDERS".
- mutation: `docs/install-ipm.md` without its `SetDemoMode(0)` lines -> red: `test-cpf.sh` rule 9.
- mutation: `Install/Ipm.cls` STOP reworded -> red: `test-cpf.sh` rule 9 (the document's `ERROR!` line no longer equals the code's).
- mutation: `Registry.FailureLine` reworded -> red: `test-cpf.sh` rule 9 (the document's failure line, and the sample that builds on it).
- mutation: a step of `Registry.Order()` renamed -> red: `test-cpf.sh` rule 9 (the document's STEP line names a step that the order lacks).
- mutation: an ANSI code appended to the document -> red: `test-cpf.sh` rule 9.
- mutation: `Step.Production.Starting()` returns 0 for a held lock -> red: `Test.Install.StartLock` (`TestStartingSeesAnotherProcess` "Starting is 1", `TestItemDefersToTheStep` "the item sees the start of the Production step").
- mutation: `Step.Production.Starting()` keeps the lock it probed -> red: `Test.Install.StartLock.TestStartingSeesAnotherProcess` ("and it holds it": the holder job cannot take a lock that the test's own process kept).
- mutation: `ReconcileIn.OnInit` sets `ByStep` 0 -> red: `Test.Install.StartLock.TestItemDefersToTheStep` (three asserts).
- Tests (QA): `Test.Install.StartLock` pins the start lock that makes "every start is reconciled exactly once" (`Starting()` and `ReconcileIn.OnInit`), which `TestNext` (a pure method fed `byStep`) and the live row "Start by the step" did not pin on their own. The body of `ReconcileIn.Reconcile` (session-id restore, one `$$$LOGWARNING` row per warning, `$$$LOGERROR`, no repeat) is pinned by `Test.Install.ReconcileIn.TestFailedReconcile` (code review), with a fixture area as the seam. Not unit-tested, only live: the lock-timeout failure of `Production.Start` (a 60 s wait).

**Code review additions (Rule 19).** Each mutation was applied, seen red and reverted; `git status --short` and the `git diff` hash were equal before and after.
- mutation: `ReconcileIn.Reconcile` without its `If $$$ISERR(sc)` branch (a failed reconcile logs the Info row) -> red: `Test.Install.ReconcileIn.TestFailedReconcile` ("its failure is one Error row naming the area", "and no Info row says that it reconciled"), on the warm stack `e15s2cw`.
- mutation: `ReconcileIn.Reconcile` without the save and restore of `$$$JobSessionId` and `$$$JobCurrentHeaderId` -> red: `TestFailedReconcile` ("the job's session id is put back after the reconcile", "and its current header id, which was not defined, is killed again").
- mutation: a global mapping `ZzMutation` created in OCUTALON between the first and the second run (a seeded state in the script) -> red: `ipm-install.sh a`, "second run: the configuration changed" (the comparison with the first run's snapshot, Story 15.1's check 3, which the recovery run repeats).
- mutation: `Registry.Order()` gains a step (`"ZzAdded"`) -> red: `test-cpf.sh` rule 9 (the document's STEP lines no longer give every step of the order).
- Verified after the patches: `test-cpf.sh` (BSD tools and `ubuntu:24.04`), `test-boundaries.sh`, `test-pinned-sources.sh`, `ci/checks.sh` (all scripts passed); on warm stack `e15s2cw`, `class OcuTalon.Test.Install.ReconcileIn` and `StartLock` and `shard lane-a@Checks,Install,Watch` (35 classes passed); full `release/ipm-install.sh` on a fresh throwaway `e15s2c` (97 checks passed). Teardown of `e15s2c` and `e15s2cw` left nothing.

**Shared surfaces:**
- **The production's item list,** now with `ReconcileIn`. Read by:
  - the `Test.Install.Production` oracle and lib-live's reader of it (every live unit's "every item runs" check);
  - `Test.Install.ProductionRules`;
  - `test-production.sh`'s item rows.
- **`Production.Start`'s new lock,** used by every test that calls it: `Test.Schedule.Heartbeat`, `Test.Schedule.Reminders` and `Test.Agent.Conversation`.
- **The after-start log's `STEP` and `WARN` lines,** unchanged: `after-start.sh`, `lib-live.sh:594` and `test-reminder-restart.sh:229-233`.
- **`^Ens.AutoStart`:** `test-production.sh` row 13 and `lib-live.sh:860`.
- **`src/module.xml`:**
  - `test-cpf.sh` and `test-pinned-sources.sh`;
  - `ci/warm.sh`'s manifest (a change refuses a warm reload);
  - `test-build-inputs.sh`.
- **`release/ipm-install.sh`'s check list,** read by lane-a's job.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Manual checks:**
- The `OUTPUT` blocks in `docs/install-ipm.md` equal those of the run the document cites, with ANSI codes removed.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The second install command now gives a working OcuTalon. `Registry.Ipm()` (Configure, After) commits IPM's open transaction, runs `Run("ipm")` and reopens the levels; on the image it does nothing. The `Production` step marks the production autostart for the caller `ipm` only, and holds a start lock. The new `ReconcileIn` item reconciles every start that the step did not make. `release/ipm-install.sh a|b` proves both install paths, and `docs/install-ipm.md` documents them from captured output.

**Files changed.**
- `src/module.xml`: the Configure, After Invoke of `Registry.Ipm`.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls`: `Ipm()`, and `Run` records the caller.
- `src/ocutalon/cls/OcuTalon/Install/Step.cls`: `Caller()`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`: start lock, `Starting()`, `AutoStart(caller)`.
- `src/ocutalon/cls/OcuTalon/Install/ReconcileIn.cls` (new): the item.
- `src/ocutalon/cls/OcuTalon/Production.cls`: the item in Lane A's region.
- `docker/tests/test-cpf.sh`: rule 8.
- `src/ocutalon/cls/OcuTalon/Test/Install/{Registry,Production,ProductionRules,Users}.cls` and the new `Test/Install/ReconcileIn.cls`: `TestIpmOnTheImage`, `TestIpmRunsTheSteps`, `TestAutoStart`, the oracle row, the name entry, `TestNext`, and the DW-212 asserts.
- `release/ipm-install.sh`: the argument, the second run and path B.
- `docs/install-ipm.md` (new): the install document.

**Review findings.** 23 findings; 10 patched (medium 3, low 7), none deferred, 13 rejected with their reasons in the triage log.

**Follow-up review recommended:** false. No high was patched and the three medium patches (test hermeticity, a unit test of `Ipm`, the caller handoff test) added tests only.

**Verification performed.**
- Static: `test-cpf.sh` (rules 1-8), `test-pinned-sources.sh`, `test-boundaries.sh` and `ci/checks.sh` pass.
- Classes on fresh throwaways: `Test.Install.Registry`, `Production`, `ProductionRules`, `ReconcileIn`, `Users` pass.
- `release/ipm-install.sh a`, `b` and the full run pass (path A 42 checks, path B 30).
- Every `(once)` unit passed on the first pass, among them the live units, the shard pieces and `standalone-bridge.sh`. After the review patches (which changed `ReconcileIn`'s skip path, tests, the script and the document) the units that run the production or the installer were run again and passed: the full `ipm-install.sh`, `ci/checks.sh`, `live production`, `live production-restart`, `live reminder-restart`, `live install-start` and `shard lane-a@Checks,Install,Watch`. The other units do not depend on the patched code and were not repeated.
- Mutations: every mutation of the spec's table that edits a Lane A file went red and was reverted with the diff hash unchanged; the two that edit Lane B classes were not run (U-177).
- Teardown of tag `e15s2i` removed nothing left over.

**Residual risks.**
- `ReconcileIn.OnInit` reads the start lock once; a start that lets the item run before its `OnInit` could be reconciled twice (idempotent; never observed).
- The "Demo switch" and `/state` parts of "Web and REST" have no demonstrated mutation, because their classes are Lane B (U-177).
- A failed reconcile of `ReconcileIn` is not repeated until the item starts again.

### Rework pass (owner decision U-176)

Status: done
Blocking condition: none

**Summary.** `Registry.Ipm()` now writes one more line after a failed step's own line, `STEP <name> FAILED: the new OcuTalon code is installed. Run the same install command again.` (from `FailureLine`, naming the first failed step from `Run`'s new `Output failed`), and still returns the error to IPM, so `Configure FAILURE` and `ERROR!` follow. `release/ipm-install.sh` gains checks 16 to 18 and the argument `r`: a reinstall from a test-only scratch copy whose Audit step fails (the command reports the failure, the data, OCUTALON and its four databases stay), the real folder again (the checks of 15.1 and 15.2 pass), and a scratch copy that fails Compile (IPM rolls it back, the previous version keeps running). `docs/install-ipm.md` has the one paragraph. Job `ipm-install` of `lane-a.yml` has `timeout-minutes: 35` and `OCUTALON_LIVE_DEADLINE: "1980"` (the spec's 8-minute rule).

**Files changed.** `src/ocutalon/cls/OcuTalon/Install/Registry.cls`, `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`, `release/ipm-install.sh`, `docs/install-ipm.md`, `.github/workflows/lane-a.yml`.

**Review findings.** 31 findings; 6 patched (medium 3 groups, low 3), none deferred, the rest rejected with their reasons in the triage log.

**Follow-up review recommended:** false. No high was patched.

**Verification performed.** `test-cpf.sh`, `test-pinned-sources.sh`, `test-boundaries.sh`, `ci/checks.sh`, `ci/iris.sh build` and `class OcuTalon.Test.Install.Registry` pass; `release/ipm-install.sh a` (42 checks), `b` (30), `r` and the full job (95 checks, 433 s) pass. Eight mutations were applied, seen red and reverted (the diff hash equal before and after); their lines are in `## Verification`. Teardown of tag `e15s2j` left nothing.

**Residual risks.** Reload and Validate failures are not exercised by a forced-failure check (only Compile is); the document states the rollback for all three phases as the owner's wording and IPM's behavior.
