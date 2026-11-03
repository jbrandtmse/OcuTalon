# Epic 15 Context: Install into an existing IRIS with IPM

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 15 (1.0.0 kit, worked in Lane A's files) lets an IRIS user install OcuTalon into an existing AI Hub build 154 instance with its one IPM package, `ocutalon`. That package also contains and installs the bridge. The install is the same package run twice. The first run, in any namespace, creates OCUTALON and stops with the exact next command. The second run, in OCUTALON, installs and starts OcuTalon with demo mode off. An admin with a shell can run `iris merge` instead of the first run. The IPM install must be as durable as the Docker one: it survives restarts and reinstalls, and it upgrades in place. A CI job proves all of this on every push, and 1.0.0 and every later release must ship a working IPM package.

## Stories

- Story 15.1: The first install run creates OCUTALON and gives the next command
- Story 15.2: The second install run gives a working OcuTalon with demo mode off
- Story 15.3: An IPM install survives restarts and reinstalls, and every release proves it

## Requirements & Constraints

**Whole epic**
- The target is a clean build 154 instance with IPM 0.10.10. CI tests only the IRIS for Health image; the non-Health image is supported.
- An IPM install never changes the instance's services (no `%Service_CallIn`) and never runs an installer step outside OCUTALON. The installer refuses every other namespace and refuses a second OcuTalon namespace on the instance.
- There is one package, `ocutalon`, with no dependency on any other OcuTalon or bridge package. It installs `OcuTalon.Bridge` and `OcuTalon.BridgeExample`, and the example production is never started in OCUTALON.
- The model key is `ANTHROPIC_API_KEY` from the instance's environment and is never stored in IRIS. Without it, OcuTalon still starts and every decision takes the fixed-rules fallback.

**Second run (Story 15.2)**
- Before it, OCUTALON must exist, either from the first run or from `iris merge` followed by `zpm "enable -map -ns OCUTALON"`. The `zpm` command is needed because the CPF file maps no IPM.
- In OCUTALON, the run loads the bridge's resources first and runs the image's installer steps in their fixed order (see Technical Decisions). It ends with `OcuTalon.Production` running, every enabled item up and every runner resolving a model.
- **Install checks.** `OcuTalon.Web.Public`, `OcuTalon.Data.Public` and `^OcuTalonPublic` resolve to `OCUTALON_PUBLIC`, and every private storage global resolves to the private database.
- **Demo mode is off.** OCUORDERS doesn't exist, and the state snapshot has no demo guide, no simulated devices and no Break the feed.
- **Web and chat.** `/ocutalon/` serves the branded sign-in page, and the README account signs in. The public settings mark the install as not the online demo, so trace links use the local-and-IPM sign-in popover. A chat message gets an attention decision from the CI model mock.
- **Switching demo mode.** On the IPM install, `do ##class(OcuTalon.Core.Admin).SetDemoMode(1)` creates OCUORDERS, its databases and its mappings, and starts the Orders production. `SetDemoMode(0)` removes them again and touches no other namespace.
- **`docs/install-ipm.md`.** The story writes it from the FR-57 job's captured output. It covers:
  - both commands, with their real output, and that the first run ends early by design;
  - the `iris merge` alternative: `iris merge`, then `zpm "enable -map -ns OCUTALON"`, then the install command in OCUTALON;
  - that demo mode is off, and the command that switches it on;
  - that the model key comes from `ANTHROPIC_API_KEY`, and that without it decisions use fixed rules;
  - the README account, and how to change its password.

  Lane B has nothing to do here: its Story 31.3 adds the README's IPM section from this file.
- **Ledger items:**
  - DW-34: on an IPM install outside the image, `Data.Time.Zone()` and `ToLocal` must agree on the instance zone, even when `TZ` is unset on a host that isn't on UTC. Add a test.
  - DW-212: with the online-demo flag off, an instance whose `PasswordValidationRoutine` names another routine keeps both the setting and that routine exactly as they were, and an instance with none stays with none. Extend Story 3.8's `TestForeignGuardIsRefused` to assert that the foreign routine still exists after the flag-off run, and prove both cases on the IPM install.
  - DW-207: when `Install.Step.Demo.Plan` answers error because OcuTalon didn't create the instance's OCUORDERS, `SetDemoMode(1)` must refuse.
    - It refuses before the audit entry and before the settings write, and changes nothing.
    - It prints one terminal line in the style of the Install step lines. The line says that demo mode stays off and why (OCUORDERS exists and OcuTalon didn't create it), and names no customer data.
    - It leaves `demo.mode` at 0, so later starts still reach Production and Ready. Today it writes 1 first, and every later start stops at `STEP Demo FAILED`.
    - Prove both outcomes on the IPM install.
  - DW-223: `Install.Step.Demo.WithOrdersData` is a near-copy of `WithOrders` (about 18 of its 20 lines) and differs only in the resource list it edits.

**Durability and CI (Story 15.3)**
- **Restart.** Start with an IPM install holding a conversation, a pending reminder and a pending approval request, then restart the instance. `OcuTalon.Production` comes back through autostart. Once its items run, every area's `Reconcile()` runs with no after-start script: Lane A's re-arms `ApprovalHold`, and Lane B's re-arms `ReminderTimer`. All three records are intact, the reminder fires, and the request can still be answered. The test restarts the instance twice in a row and finds each waiter re-armed exactly once, with no duplicate process.
- **Reinstall.** Running the install command again in OCUTALON, with the same version or the next one, completes without errors or data loss and restarts every item on the new code. If the load fails part-way, IPM rolls it back, the previous version keeps running, and the namespace and databases stay in place for the next run.
- **The FR-57 job.** It lives in `.github/workflows/lane-a.yml` and runs on every push and pull request.
  - It runs on clean build 154 containers whose image is built on the IRIS runner and never cached, pushed or stored as an artifact.
  - It runs both install paths: two runs of the package, and `iris merge`, then `zpm "enable -map -ns OCUTALON"`, then one run.
  - It then restarts the instance and runs the install command again.
  - It keeps each run's full output.
  - It fails the build unless every check of Stories 15.1, 15.2 and 15.3 passes.
  - Pull requests from forks never run it on the IRIS runner, and it must fit in the 35-minute full-CI budget.
- **Story 9.1's IPM case.** This story turns it on: on an IPM install, `EvalIn` (`OcuTalon.Eval.In`) is disabled and the production's testing switch is off.
- **Release gate.** From 1.0.0 on, the release sequence stops any candidate on which the FR-57 job didn't pass.
- **Registry check.** Only after the author has published 1.0.0, and on the author's word, the README's two commands are run once from the registry on a clean build 154 instance. The result goes in the release notes.
- **Ledger items:**
  - DW-80: nothing runs the `Reconcile` declarations when the production starts on its own, which happens with an IPM autostart or with a stop and start that has no installer run. The every-start `Reconcile` rule covers this. Also test a restart of the production alone.
  - DW-306: row 21 of `docker/tests/test-production.sh` ("Start(15) with a WatchOps whose OnInit fails") printed nothing in two CI runs after Epic 5's merge. Give that row a longer wait or a retry when this story next edits the file.

## Technical Decisions

**Package layout and the IPM early step**
- **`src/module.xml`.**
  - Its first resource is the CPF resource `src/cpf/ocutalon.cpf` (processor `CPF`, phase `Initialize`, before).
  - The bridge's resources (`src/bridge/`) come next, then `src/ocutalon/` and the built web bundle.
  - Installer steps declared in it run in the order listed.
- **`ocutalon.cpf`.**
  - It is the image's merge file without `ModifyService %Service_CallIn` and without any IPM mapping.
  - It creates the four databases, the namespace with Interoperability, and the mappings.
  - It is idempotent and runs on every install and upgrade.
  - It runs outside IPM's transaction, so a failed install leaves the namespace and databases in place.
  - A CI check fails the build unless it differs from `docker/merge.cpf` only by the Docker-only `%Service_CallIn` and `%IPM` lines.
- **A step that must run before IPM's Reload** (the map-and-stop step) is a preload class.
  - It lives under `src/preload/cls/` and is declared in `module.xml` as a `.CLS` resource with `Preload="true"`.
  - It is called by `<Invoke ... Phase="Initialize" When="After"/>`.
  - IPM compiles it into the namespace the run happens in, and rolling back a stopped run removes it there.
  - Anything that must survive the stop, such as the IPM mapping into OCUTALON, is made with `$SYSTEM.Process.TransactionsSuspended(1)`, and the previous state is restored on every path.
  - IPM 0.10.10 can't stop a run without its `ERROR! ` prefix. Its only unprefixed stop, error code 7, makes `%IPM.Main.Shell()` report success for an install that didn't happen. So the first run's stop keeps the prefix, and the install document shows the real output.
- **The bridge installs on its own without IPM,** with `$SYSTEM.OBJ.LoadDir` and then `OcuTalon.Bridge.Installer`. A CI check fails any bridge class that references another OcuTalon package.

**Namespaces, databases and mappings**
- OCUTALON has four databases: code, data, private, and `OCUTALON_PUBLIC` with public Read.
- The public database holds only `OcuTalon.Web.Public`, `OcuTalon.Data.Public` and `^OcuTalonPublic`.
- The private database holds `OcuTalonP.*` and `OcuTalonBP.*` (each with the dot, so `^OcuTalonPublic` stays public), `^AI.Agent.Session*` and `^IRIS.IF.*`.
- Every mapping exists before any OcuTalon class compiles. A mapping created after a compile hides the classes, and only a reload from source brings them back. An uninstall never removes the public mapping before the classes.
- Only three kinds of class switch namespace, each in one method with `New $NAMESPACE`: `OcuTalon.Install.*` and `OcuTalon.Bridge.Installer` switch to `%SYS`, and `Install.Step.Demo` switches to OCUORDERS.
- OcuTalon never deletes Foundation artefacts, and on the non-Health image `Interop=1` only enables Interoperability.

**The installer on an IPM install**
- **How it runs.** The install calls `Registry.Run("ipm")`, and the steps run in this order:
  1. `OcuTalon.Bridge.Installer`
  2. `Public`, which writes the public settings and leaves readiness cleared
  3. roles and users
  4. web applications, SSL configurations and tasks (every area's `Tasks()`)
  5. `Demo`
  6. Config Store entries, after `RebuildRegistry`
  7. audit events
  8. Telegram, enabled only when `Included()` returns 1 and `TELEGRAM_BOT_TOKEN` is set, and otherwise recorded as `off`
  9. `Production`
  10. `Reconcile`
  11. the private-data check
  12. `Public`, which sets readiness last

  `Install.Step.Warn(text)` reports a warning without changing the step's result.
- **The `Production` step.**
  - On IPM it marks `OcuTalon.Production` autostart; the Docker install keeps it not autostart.
  - It starts the production, or restarts every item if it is running, and waits until every enabled item runs and every runner resolves a model.
  - It recovers a Troubled production and never cleans it or kills application data.
  - `EvalIn` is enabled only through the System Default Setting row the step writes from `OCUTALON_EVAL`.
- **Every production start runs `Reconcile`.** Whatever started the production, every area's `Reconcile()` runs once the items are running, and it is idempotent. The reconciler starts a new waiter for any pending `ApprovalRequest` or `Reminder` row whose process is gone, re-arming it from the row's times, and cancels any orphaned Workflow task.
- **The web bundle** goes in the instance data directory's `csp/ocutalon-web/` folder, through IPM's data-directory variable. It never goes through the CSP-directory variable and never into `csp/ocutalon/`. The `/ocutalon` shell serves files from that folder.
- **Upgrades.** Running jobs keep the old code until their item restarts.
  - Storage is append-only, and committed `Storage` blocks are never edited by hand.
  - Upgrade code never assumes that old rows have a value for a new property.
  - The production class holds structure only. Values live in System Default Settings, bridge tables or `OcuTalon.Data.Setting`, so a reinstall keeps them.

**Settings and secrets**
- **Keys and tokens** come only from environment variables.
- **The CI mock** is reached only through the CI-only endpoint overrides: `OCUTALON_MODEL_BASE_URL`, which ends in `/v1/`, and `OCUTALON_MOCK_KEY_HEADER=1` for the mock's default scripts.
- **Structural and seed values.** Structural values are rewritten on every install. Seed values are written only when absent; these are each runner's `Model` and the allow-listed values. So an admin's choices survive a reinstall.
  - `demo.mode` is seeded to "1" only when `/opt/ocutalon/version` exists (the image), and to "0" otherwise.
- **Without `OCUTALON_ONLINE_DEMO`,** `Public` writes only the flag (off) and, when no cap row exists, the seed cap 0. Public values go only through `OcuTalon.Data.Public.Settings`, and product values only through `OcuTalon.Data.Setting.Get`, never straight from globals.
- **`SetDemoMode`** requires `OcuTalonAdmin` or `%All`. It submits to `SettingsOps` through `Commands.Submit` with Origin `system`, and is audited through `Bridge.Audit.Record`.
- **Config Store entries** (`AI.LLM.OcuTalon<Agent>`) are instance-wide, and `Install.Step.Provider` is their only install-time writer.

**Demo mode inside an existing instance**
- The `Demo` step owns only an OCUORDERS whose default destinations are its own two databases, `OCUORDERS_CODE` and `OCUORDERS_DATA`. Their resources grant no public permission.
- **Demo mode on** creates:
  - the namespace, the two databases and the mappings, including the public ones;
  - `/ocutalon/trace/ocuorders/`;
  - the trace role's OCUORDERS grants;
  - Read on `%DB_OCUORDERS_DATA` for `OcuTalonServiceRole`.

  The step then starts the Orders production itself. A foreign OCUORDERS fails the on path.
- **Demo mode off** removes all of that, including the `%SYS` rows keyed by the namespace.
  - It keeps a foreign OCUORDERS, or one with any other production, logs a warning and records the `demoKept` mark.
  - It never deletes a user's data or fails the start, and never stops another production in OCUORDERS.

**Time**
- Times are stored and sent in UTC, as ISO 8601 to the second.
- `OcuTalon.Data.Time` is the only converter outside the bridge, and `OcuTalon.Bridge.Time` the only one inside it; both use the same zone source.
- Message text uses the instance's zone. Release 1 takes that zone from the container's `TZ`, which an IPM host may not set (DW-34).

**Security posture on someone else's instance**
- **Roles.** The installer creates `OcuTalonUser`, `OcuTalonAdmin` and `OcuTalonTraceViewer`.
- **The README account** is `ocutalon`/`ocutalon`, non-expiring, with no forced password change, and it holds all three roles.
- **The trace role** reads the data and code databases, never the private one.
- **The service user** `OcuTalonService` has login disabled, no services and a random password.
- **No OcuTalon role** holds `%All`, `%Development` or `%Ens_ProductionRun`.
- **The password guard** exists only with the online-demo flag on. With the flag off, the install clears only OcuTalon's own guard and never touches a foreign one (DW-212).
- **Instance-wide auditing** is never changed. The audit step warns and records the `instanceAuditing` status mark.

**CI and testing**
- **The FR-57 job** uses the CI model mock and runs on the IRIS runner, behind the fork guard.
- **No CI step pushes an image or signs in to a registry.** The AI Hub image never enters a cache or an artifact.
- **Two Docker commands could print the `env_file` values:** `docker compose config` runs only with `--quiet`, and `docker inspect` only with `--format`.
- **Tests** are `%UnitTest` classes under `OcuTalon.Test.<Area>`.
- **The developer instance** is load-and-compile only. IPM installs, restarts and destructive tests run only in throwaway stacks and CI.

**Who owns which files**
- **Lane A:**
  - the step registry, the CPF resource and the map-and-stop step;
  - `docker/merge.cpf`;
  - the roles, users, SSL, tasks, `Production`, `Public` and `Provider` steps;
  - `OcuTalon.Eval`, `lane-a.yml` and `release/` (Story 11.5's release sequence);
  - `docs/install-ipm.md`.
- **Lane B:**
  - the `Web` and `Demo` steps;
  - `OcuTalon.Core`, which includes `Admin` and `SettingsOps`;
  - `OcuTalon.Data.Time`, `.Data.Setting` and `.Data.Public`;
  - `ci.yml`, the rest of `docker/` (`docker/tests/` included), the rest of `ci/`, and the README.

  Only the owning lane edits a class.

## UX & Interaction Patterns

- **The sign-in page.** On an IPM install, the branded sign-in page shows at any address while signed out. Its help line reads "Use the IRIS account your install created; the README lists it." There is no forced password change.
- **With demo mode off,** the page has no context badge, no demo guide, no simulated phone or mailbox, and no Break the feed.
- **Trace links** use the local-and-IPM flow. The "Sign in to Visual Trace" popover appears on the first trace link in a browser session and from the menu, with "Don't show this again". While the popover is unseen, the link reads "Open in Visual Trace (shows sign-in help first)".
- **Sessions** last at least 8 hours locally. Each IRIS user has one durable OcuTalon session.

## Cross-Story Dependencies

- **Epic level.** Epic 15 depends on Epic 3, the installer core.
- **Story 15.1** is done. Stories 15.2 and 15.3 build on its CPF resource, its preload map-and-stop step and its FR-57 job.
- **Story 15.2** needs Epic 4 merged, because release 1's seed sets demo mode off.
- **Story 15.3** needs two epics merged:
  - Epic 9, because 15.3 turns on Story 9.1's IPM case;
  - Epic 11, because 15.3 adds the FR-57 gate to Story 11.5's release sequence.
- **DW-212** extends Story 3.8's `TestForeignGuardIsRefused`.
- **Ledger items in Lane B's files.** This epic otherwise stays in Lane A's files, so the story spec has to account for these:
  - DW-34: `OcuTalon.Data.Time`;
  - DW-207: `OcuTalon.Core.Admin` and `Install.Step.Demo`;
  - DW-223: `Install.Step.Demo`;
  - DW-306: `docker/tests/test-production.sh`.
- **Downstream:**
  - Lane B's Story 31.3 builds the README's IPM section from `docs/install-ipm.md`.
  - Story 19.2, where the IPM install downloads the embedding model into `<mgr>/fastembed/`, waits for this epic to merge.
  - Story 34.1, whose FastEmbed path check runs on an IPM install, also waits for this epic to merge.
