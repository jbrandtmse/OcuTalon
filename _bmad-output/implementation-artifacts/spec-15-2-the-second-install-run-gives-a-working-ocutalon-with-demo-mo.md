---
title: 'Story 15.2: The second install run gives a working OcuTalon with demo mode off'
type: 'feature'
created: '2026-10-30'
status: 'ready-for-dev'
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
- Never edit a Lane B file outside the task group "Cross-lane (AD-33), awaiting the orchestrator's ruling".
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

**Cross-lane (AD-33), awaiting the orchestrator's ruling.** Build these only if the orchestrator rules them in; otherwise leave the files and the dependent checks out, and record that under "Measured in implement".
- [ ] DW-34 in `src/ocutalon/cls/OcuTalon/Data/Time.cls` (Lane B):
  - Add `ClassMethod ZoneFrom(tz As %String, tzDefined As %Boolean, localtimePath As %String, offsetMinutes As %Integer) As %String`, which is pure:
    - when TZ is defined, it returns TZ without a leading `:`, or "UTC" for "";
    - otherwise the part of the path after `zoneinfo/`, without `posix/` or `right/`, with a UTC alias (`UTC`, `Etc/UTC`, `Etc/UCT`, `UCT`, `Etc/Universal`, `Universal`, `Etc/Zulu`, `Zulu`) reported as `UTC`;
    - otherwise `UTC` for offset 0, `Etc/GMT-n`/`Etc/GMT+n` for whole hours (the sign is inverted), and `+hh:mm`/`-hh:mm` for other offsets.
  - `Zone()` calls it with `$SYSTEM.Process.TimeZone()`'s -1 test, `##class(%File).ResolvePath("/etc/localtime")` and the minutes of `$Horolog` minus `$ZTimeStamp`.
  - A Docker install, where TZ is unset and the path is `Etc/UTC` (measured), still reports `UTC`.
- [ ] DW-34 in `src/ocutalon/cls/OcuTalon/Test/Data/Time.cls` (Lane B): `TestZoneFrom` covers every branch.
- [ ] DW-34 in `release/ipm-install.sh` (Lane A, depends on the ruling): as the last check of path A, as root point `/etc/localtime` at `/usr/share/zoneinfo/America/New_York`. A new session must then give:
  - `TimeZone()=-1`;
  - `Zone()=America/New_York`;
  - `ToLocal("2026-01-15T12:00:00Z")=2026-01-15T07:00:00` and `ToLocal("2026-07-15T12:00:00Z")=2026-07-15T08:00:00`.
- [ ] DW-207 in `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` (Lane B):
  - Add `ClassMethod PlanNow(on As %Boolean, Output sc, Output kept, Output what) As %String`, which is `Plan(on, ##class(%SYS.Namespace).Exists(..#NAMESPACE), ..Owned(), ...)`. `Run` (:76-77) uses it.
- [ ] DW-223 in `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` (Lane B):
  - `WithOrders(resources, on, own As %List = {$ListBuild("%DB_"_..#CODEDB, "%DB_"_..#DATADB)})` uses `seen(name)` throughout.
  - `WithOrdersData(resources, on)` becomes `Quit ..WithOrders(resources, on, $ListBuild("%DB_"_..#DATADB))`, so its callers (:493, Lane A's `Watch/Grant`) stay.
- [ ] DW-207 in `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (Lane B):
  - In `Carry`, before `WriteAudit` (:58): when `command.DemoMode` and `Demo.PlanNow(1, .planSc)="error"`, `$$$LOGWARNING` and return `Result(0, "refused", "Demo mode stays off. "_##class(OcuTalon.Core.Admin).ErrorText(planSc)_" Nothing was changed.")`.
  - The sentence is `Plan`'s own (:115), which names no customer data.
  - The class doc lists the outcome `refused`. `Admin.SetDemoMode` prints it unchanged.
- [ ] DW-207 in `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls` and `SettingsOpsProbe.cls` (Lane B):
  - A probe seam `PlanNow` that does not count as a call.
  - `TestForeignRefused`: Ok 0, outcome `refused`, the exact message, 0 calls (no audit, no write, no step), and the row's value and `UpdatedAt` unchanged.
  - `TestForeignOffGoesThrough`: off with the same answer carries out as today.
- [ ] DW-223 in `src/ocutalon/cls/OcuTalon/Test/Demo/Step.cls` (Lane B): in `TestWithOrders`, add a case with an explicit one-element `own` list that gives `WithOrdersData`'s answers.
- [ ] DW-207 in `release/ipm-install.sh` (Lane A, depends on the ruling), path B after the install:
  - `run refuse-demo OCUTALON 'Do ##class(OcuTalon.Core.Admin).SetDemoMode(1)'`. Its final line is exactly the refusal, `Data.Setting.Get("demo.mode")` is still "0", the count of OcuTalon `Settings` audit entries is unchanged, and the foreign namespace and its databases are unchanged.
  - Then `run later-start OCUTALON 'Set sc=##class(OcuTalon.Install.Registry).Run("ipm") Write !,"CHK|run|",$SYSTEM.Status.IsOK(sc)'` shows `STEP Demo OK` (with `WARN Demo`), `STEP Production OK`, `STEP Ready OK` and `CHK|run|1`.

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
- Only if the orchestrator rules the cross-lane group in:
  - Given TZ unset and `/etc/localtime` at America/New_York, when a session asks, then `Zone()` and `ToLocal` agree (DW-34).
  - Given a foreign OCUORDERS, when `SetDemoMode(1)` runs, then it refuses before the audit and the write, prints the refusal line, leaves `demo.mode` 0, and a later `Registry.Run("ipm")` reaches `Production` and `Ready` (DW-207).
  - Given `WithOrdersData`, when `Test.Demo.Step.TestWithOrders` and `Test.Watch.Grant.TestHelper` run, then it gives the answers of `WithOrders` with a one-element `own` list (DW-223).

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: one package, the bridge's resources first, no dependency.
- AD-3: the mappings and their install checks, OCUORDERS owned by the Demo step, and an IPM install marking autostart.
- AD-5: every reconcile is idempotent, and the startup reconciler re-arms waiters.
- AD-17: the DW-207 refusal comes before the audit entry.
- AD-18: one converter and the instance zone (DW-34).
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
12. **The DW-207 line keeps within U-106's condition:** "Demo mode stays off.", then `Plan`'s sentence, then "Nothing was changed.". It names no database.
13. **DW-34 maps UTC aliases to `UTC`,** so the Docker installs and every existing zone assertion are unchanged.

**Cross-lane edits (AD-33) awaiting ruling:**
- `src/ocutalon/cls/OcuTalon/Data/Time.cls` and `Test/Data/Time.cls` (Lane B): `ZoneFrom` and `Zone()`, and `TestZoneFrom` (DW-34). There is no Lane A design: `Zone()` is the only zone source (AD-18).
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` (Lane B): `PlanNow` (DW-207, Rule 2) and `WithOrders` with an `own` list (DW-223). `Test/Demo/Step.cls`: the explicit-list case.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` (Lane B): the refusal before the audit (DW-207). `Test/Core/SettingsOps.cls` and `SettingsOpsProbe.cls`: `TestForeignRefused` and `TestForeignOffGoesThrough`.
- `release/ipm-install.sh` (Lane A): the DW-34 and DW-207 live checks, which depend on the rulings above.
- If DW-207 is ruled out, DW-207 stays routed. If DW-223 is ruled out, it is declined here as "Lane B's `Demo.cls`, not this story's". No contended file is in this list.

**Ledger inbox (Rule 17):**
- DW-212 is addressed by the `Test/Install/Users.cls` task and matrix row "Path B".
- DW-34, DW-207 and DW-223 are addressed by the cross-lane tasks above.

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
- `PlanNow` keeps `SettingsOps` from repeating `Run`'s two lines.

**Architectural weight, for the lead (Rule 20):**
- A Conventions row, "IPM steps":
  - The Configure, After Invoke `Registry.Ipm()` does nothing on the image.
  - Elsewhere it commits IPM's transaction (measured: `ErrCanNotAcquireRuntimeLock` inside it), runs `Run("ipm")` and opens the levels again.
  - A Reload, Validate or Compile failure is still rolled back. A step failure leaves the new code installed, and the next command runs the steps again.
  - Story 15.3's "if the load fails part-way, IPM rolls it back" therefore reads as the load phases.
- **The ownership-table row** `ReconcileIn` | `OcuTalon.Install.ReconcileIn` | A (AD-33). A note on AD-23's "every production start ... runs Reconcile": the `Production` step's start lock and `ReconcileIn`.
- **If DW-34 is ruled in,** AD-18's "In release 1 the instance zone is the container's `TZ`" gains "and, where TZ is unset, the operating system's zone (`/etc/localtime`)".

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
- Cross-lane only, if ruled in (loop): `[L] bash ci/iris.sh class OcuTalon.Test.Data.Time`, `... OcuTalon.Test.Demo.Step`, `... OcuTalon.Test.Core.SettingsOps`, `... OcuTalon.Test.Core.Admin` and `... OcuTalon.Test.Watch.Grant`: each passed.
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
| Cross-lane: `Zone()` back to TZ only | `Test.Data.Time.TestZoneFrom`, `ipm-install.sh a` DW-34 | DW-34 |
| Cross-lane: the `SettingsOps` guard removed | `Test.Core.SettingsOps.TestForeignRefused`, `ipm-install.sh b` | DW-207 |
| Cross-lane: `WithOrders` ignores `own` | `Test.Demo.Step.TestWithOrders`, `Test.Watch.Grant.TestHelper` | DW-223 |

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
- **Cross-lane:**
  - the `SettingsOps` outcomes: `Test.Core.SettingsOps`, `Test.Core.Admin.TestPrinted` and `test-demo-switch.sh`'s texts;
  - `Zone()`: `Test.Data.Time.TestUnsetZone`, `Test.Web.Api`:118, `Test.Agent.Render`:140, `Test.Tools.Reminders`:1052, `test-sign-in.sh`:248, `test-production.sh`:250 and `/state`'s `instanceZone`;
  - `WithOrders`: `Test.Demo.Step` and `Test.Watch.Grant`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Manual checks:**
- The `OUTPUT` blocks in `docs/install-ipm.md` equal those of the run the document cites, with ANSI codes removed.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
