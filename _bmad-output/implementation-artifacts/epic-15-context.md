# Epic 15 Context: Install into an existing IRIS with IPM

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 15 (1.0.0 kit, Lane A's files) makes OcuTalon installable into an existing AI Hub build 154 instance with its one IPM package, `ocutalon`. That package also contains and installs the bridge. The install is two runs of the same package: the first, in any namespace, creates OCUTALON and stops with the exact next command, and the second, in OCUTALON, installs and starts OcuTalon with demo mode off. An admin with a shell can run `iris merge` instead of the first run. The IPM install must hold up as well as the Docker install: it comes back after restarts, reinstalls and upgrades in place, and a CI job proves this on every push. 1.0.0 and every later release must ship a working IPM package.

## Stories

- Story 15.1: The first install run creates OCUTALON and gives the next command
- Story 15.2: The second install run gives a working OcuTalon with demo mode off
- Story 15.3: An IPM install survives restarts and reinstalls, and every release proves it

## Requirements & Constraints

- A clean build 154 instance with IPM 0.10.10 gets a working OcuTalon with demo mode off. It is one package with no dependency on any other OcuTalon or bridge package, and it installs `OcuTalon.Bridge` and `OcuTalon.BridgeExample`. The example production is never started in OCUTALON.
- **First run:** it creates the four databases, the namespace with Interoperability and the package and global mappings before any OcuTalon class loads. It then maps IPM into OCUTALON and stops with exactly: "OcuTalon created namespace OCUTALON. Now run: `zn "OCUTALON"` then the same install command." Show this without IPM's error prefix if IPM allows it. A repeat run outside OCUTALON changes nothing and stops the same way. No installer step ever runs outside OCUTALON.
- **The `iris merge` path** must give the same namespace, databases and mappings as the first run. The CPF file maps no IPM, so `zpm "enable -map -ns OCUTALON"` comes next.
- **The instance's services are never changed** by an IPM install, including `%Service_CallIn`.
- **Second run:** the page is served with no Node.js. With demo mode off, OCUORDERS doesn't exist and the state snapshot has no guide, simulated devices or Break the feed. `/ocutalon/` serves the branded sign-in page, and the README account (`ocutalon`/`ocutalon`, non-expiring, no forced change) signs in. The public settings mark the install as not the online demo. A chat message gets an attention decision.
- **Model key:** it comes from `ANTHROPIC_API_KEY` in the instance's environment. Without it, OcuTalon starts and every decision takes the fallback route.
- **Demo mode on an IPM install:** it is seeded off and can be switched with `do ##class(OcuTalon.Core.Admin).SetDemoMode(1)`. Switching on creates OCUORDERS, its databases and mappings, and starts the Orders production. Switching off removes them and touches no other namespace. A foreign OCUORDERS is kept, with a warning and the `demoKept` mark.
- **Durability:** after an instance restart, a conversation, a pending reminder and a pending approval request are all intact, and the waiters are re-armed exactly once, with no duplicate `ApprovalHold` or `ReminderTimer`. The test restarts the instance twice in a row. Rerunning the install command with the same version or the next one loses no data and restarts every item on the new code. A part-way load failure is rolled back by IPM, and the previous version keeps running.
- **On an IPM install** `EvalIn` stays disabled and the production's testing switch stays off. This turns on Story 9.1's IPM case.
- **Open items:**
  - DW-34: `Data.Time.Zone()` and `ToLocal` must agree on the instance zone when `TZ` is unset on a non-UTC host, with a test.
  - DW-212: with the online-demo flag off, a foreign `PasswordValidationRoutine` and its routine are left exactly as they were, and an instance with none stays with none. Add the assertion that the foreign routine still exists after the flag-off run, and prove both cases on the IPM install.
  - DW-80: a production restart on its own, without an installer run, must still run every `Reconcile()`. Test it.
- **Release gate:** the release sequence stops unless the FR-57 job passed on that candidate. Publishing to the registry happens only on the author's word. After publishing, the registry install is run once on a clean instance, and the result is recorded in the release notes.

## Technical Decisions

- **`src/module.xml`**
  - Its first resource is the CPF resource `src/cpf/ocutalon.cpf` (processor `CPF`, phase `Initialize`, before). The bridge's resources (`src/bridge/`) come next, then everything else (`src/ocutalon/`), plus the built web bundle.
  - Installer steps declared in `module.xml` run in the order listed.
- **`src/cpf/ocutalon.cpf`**
  - It is the image's merge file without `ModifyService %Service_CallIn` and without any IPM mapping.
  - It creates `OCUTALON_PUBLIC` with public Read, plus the code, data and private databases.
  - The mappings: `OcuTalon.Web.Public`, `OcuTalon.Data.Public` and `^OcuTalonPublic` go to the public database. `OcuTalonP.*`, `OcuTalonBP.*`, `AI.Agent.Session*` and `IRIS.IF.*` go to the private database.
  - It is idempotent and runs on every install and upgrade.
  - It runs outside IPM's transaction, so a failed install leaves the namespace and databases in place for the next run.
  - A CI check fails the build unless `docker/merge.cpf` and this file differ only by the Docker-only `%Service_CallIn` and `%IPM` lines.
- **A second early step maps IPM into OCUTALON**, then stops when the run is outside OCUTALON. IPM can only install into the namespace it runs in. The installer refuses to run in any other namespace.
- **Same steps as the image.** An IPM install calls `Registry.Run("ipm")`. Steps run in this order:
  1. `OcuTalon.Bridge.Installer`
  2. `Public`, which leaves readiness cleared
  3. roles and users
  4. web applications, SSL and tasks
  5. `Demo`
  6. Config Store entries
  7. audit events
  8. Telegram, enabled only when `Included()` returns 1 and `TELEGRAM_BOT_TOKEN` is set
  9. `Production`, which waits until every enabled item runs and every runner resolves a model, and recovers a Troubled production without ever cleaning it
  10. `Reconcile`
  11. the private-data check, which confirms that the private storage globals resolve to the private database
  12. `Public` sets readiness last
- **Autostart.** On an IPM install the `Production` step marks `OcuTalon.Production` autostart. The Docker install keeps it not autostart. Every production start, whatever started it, runs every area's idempotent `Reconcile()` declaration once the items are running. Lane A's declaration re-arms `ApprovalHold` and Lane B's re-arms `ReminderTimer`.
- **Demo-mode seed:** `demo.mode` is seeded "1" only when `/opt/ocutalon/version` exists (the image) and "0" otherwise. It is written only when absent, so a later switch survives reinstalls.
- **Web bundle:** it goes under the instance's data directory (`csp/ocutalon-web/`), through IPM's data-directory variable. It never goes through IPM's CSP-directory variable or into `csp/ocutalon/`.
- **Install checks:** the public packages and `^OcuTalonPublic` must resolve to `OCUTALON_PUBLIC`, and every private storage global must resolve to the private database. A mapping created after a compile hides classes. The CPF-first order prevents that, and an uninstall never removes the public mapping before the classes.
- **Upgrades:** running jobs keep the old code until their item restarts. Storage is append-only, and committed `Storage` blocks are never hand-edited.
- **The FR-57 job** lives in `.github/workflows/lane-a.yml`, on the IRIS runner and behind the fork guard.
  - It builds a clean build 154 image on the runner and never caches, pushes or stores it as an artifact.
  - It uses the CI model mock and keeps each run's full output.
  - It runs both paths: two package runs, and `iris merge`, then `zpm "enable -map -ns OCUTALON"`, then one run. It then restarts and reinstalls.
  - It fails the build unless every check of all three stories passes. It must fit inside the 35-minute full-CI budget.
- **Where testing happens:** IPM installs, restarts and destructive tests run only in throwaway stacks and CI, never on the developer instance, which is load-and-compile only.
- **Who owns which files:**
  - Lane A: the CPF resource and map-and-stop step, `docker/merge.cpf`, the installer core steps (roles, users, SSL, tasks, `Production`, `Reconcile`, `Public`), `lane-a.yml`, `release/` and `docs/install-ipm.md`.
  - Lane B: the `Web` and `Demo` steps, `OcuTalon.Data.Time`, `ci.yml`, the rest of `docker/` and the README.

## UX & Interaction Patterns

- **The page on an IPM install** shows the branded sign-in page at any address while signed out. Its help line reads "Use the IRIS account your install created; the README lists it."
- **With demo mode off** there is no context badge, no demo guide, no simulated phone or mailbox, and no Break the feed.
- **Visual Trace links** use the local-and-IPM flow: the "Sign in to Visual Trace" popover appears on the first trace link in a browser session and from the menu, with "Don't show this again".
- **`docs/install-ipm.md`** (Story 15.2), in plain English, covers:
  - both commands with their real captured output, and that the first run ends early by design;
  - the `iris merge` alternative, followed by `zpm "enable -map -ns OCUTALON"`;
  - that demo mode is off, and the command that switches it on;
  - the `ANTHROPIC_API_KEY` source, and the fixed-rules fallback without it;
  - the README account and how to change its password.

## Cross-Story Dependencies

- **Epic level:** depends on Epic 3, the installer core.
- **Story level:**
  - Story 15.2 needs Epic 4 merged, because release 1's seed sets demo mode off.
  - Story 15.3 needs Epic 9 merged, for Story 9.1's IPM case for `EvalIn`.
  - Story 15.3 also needs Epic 11 merged, for Story 11.5's release sequence, which gets the FR-57 gate.
- **Within the epic:** each story builds on the one before. 15.2's second run assumes 15.1's first run or `iris merge`, and 15.3's job runs all of 15.1's and 15.2's checks.
- **DW-212** extends Story 3.8's `TestForeignGuardIsRefused`.
- **Downstream:**
  - Lane B's Story 31.3 adds the README's IPM section from `docs/install-ipm.md`. Story 15.2 needs no Lane B action.
  - Story 19.2 (the IPM install downloads the embedding model) waits for this epic to merge.
  - Story 34.1 (its FastEmbed path check on an IPM install) waits for this epic to merge.
