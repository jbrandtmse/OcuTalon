# Epic 15 Context: Install into an existing IRIS with IPM

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

An IRIS user installs OcuTalon into an existing AI Hub build 154 instance with its one IPM package, `ocutalon`, which also installs the bridge. The install is the same package run twice: the first run (any namespace) creates OCUTALON and stops with the next command, and the second (in OCUTALON) gives a working OcuTalon with demo mode off. `iris merge` plus `zpm "enable -map -ns OCUTALON"` can replace the first run. Stories 15.1 and 15.2 are done and merged. The remaining work, Story 15.3, makes the IPM install as durable as the Docker one: it survives instance restarts, reinstalls and upgrades in place, CI proves this on every push, and every release from 1.0.0 on ships a working, Node-free IPM package with a judge-ready install guide.

## Stories

- Story 15.1: The first install run creates OCUTALON and gives the next command (done)
- Story 15.2: The second install run gives a working OcuTalon with demo mode off (done)
- Story 15.3: An IPM install survives restarts and reinstalls, and every release proves it

## Requirements & Constraints

**Restart durability.** Start with an IPM install holding a conversation, a pending reminder and a pending approval request, then restart the instance. `OcuTalon.Production` comes back through autostart, and every area's `Reconcile()` runs once its items run, with no after-start script. Lane A's `Reconcile()` re-arms `ApprovalHold` and Lane B's re-arms `ReminderTimer`. All three records stay intact, the reminder fires and the request can still be answered. The test restarts the instance twice in a row, and each waiter must be re-armed exactly once, with no duplicate process. DW-80 adds a test of restarting the production alone, with no instance restart and no installer run.

**Reinstall and upgrade.** Running the install command again in OCUTALON, with the same version or the next one, completes with no errors and no data loss, and restarts every item on the new code.
- "The load" means IPM's Reload, Validate and Compile phases. A failure there is rolled back by IPM: the previous version keeps running, and the namespace and databases stay.
- An installer step that fails after those phases is recovered by running the same command again (U-176).
- The FR-57 job's forced step failure on a reinstall, which Story 15.2 built, must re-run to completion and also pass 15.3's checks.

**The FR-57 job** (the `ipm-install` job in `.github/workflows/lane-a.yml`, which runs `release/ipm-install.sh`):
- It runs both install paths on clean build 154 containers: two runs of the package, and `iris merge`, then `zpm "enable -map -ns OCUTALON"`, then one run.
- It restarts the instance, runs the install command again, and fails unless every check of 15.1, 15.2 and 15.3 passes.
- Fork pull requests never run it on the IRIS runner, and it stays within the 35-minute CI budget.
- It turns on Story 9.1's IPM case: on an IPM install, `EvalIn` (`OcuTalon.Eval.In`) is disabled and the production's testing switch is off.

**Release gate.** From 1.0.0 on, the release sequence stops any candidate on which the FR-57 job did not pass.

**Package artifact proof, before any publish.**
- Install the exact artifact the release would publish (Story 11.17 builds the web page into it and records it) on a clean build 154 throwaway with no Node.js.
- Install through a local filesystem IPM repository: `zpm "repo"` pointing at the artifact's folder, then `zpm "install ocutalon"` and its two steps.
- Prove that `/ocutalon/` serves the branded sign-in page and that the README account signs in.
- The release notes record the artifact's size; a size over a few MB is reported to the Contest Planner.
- DW-576: first run `docker/tests/test-release-sequence.sh --live ipm` on a candidate that carries Epic 15's two-run (`MapAndStop`) `module.xml`. Only the one-run path has been proved live.

**Registry check.** Only after the author has published 1.0.0, and on the author's word, run the README's two commands once against the registry on a clean build 154 instance, and record the result in the release notes. The story itself never publishes.

**`docs/install-ipm.md` order.**
1. The registry install comes first. It starts with the line that enables the community registry on a fresh IPM 0.10.10, in its exact form and with its output, both measured on the throwaway (`zpm "enable -community"` is only an example). Then comes `zpm "install ocutalon"`, with the two-step namespace message.
2. The load-from-folder path, which needs Node.js, comes second, for developers.

Until the author publishes, the guide shows the real output of the local-repository install. The registry's own output replaces it after the publish.

**`SystemRequirements`.** `src/module.xml` declares `<SystemRequirements Version=">=2026.3" Interoperability="enabled"/>`.
- Measure that build 154 ("2026.3.0AI.154.0") still passes IPM's version comparison.
- Measure that the first run still works wherever Epic 15's flow runs it.
- `release/lib-release.sh`'s artifact checks must still pass.
- If the "AI" suffix or the Interoperability check gets in the way, raise a clarification. Never work around it.

**DW-306.** When this story edits `docker/tests/test-production.sh`, give row 21 ("Start(15) with a WatchOps whose OnInit fails") a longer wait or a retry. It is a recurring CI flake.

**Throughout.** An IPM install never changes the instance's services and never runs installer steps outside OCUTALON. Keys come only from environment variables, and the CI model mock stands in for the model.

## Technical Decisions

- **Install sequence (already built).** `module.xml` lists the CPF resource `src/cpf/ocutalon.cpf` first (Initialize, before), then the preload `OcuTalon.Install.Ipm.MapAndStop` (Initialize, After), then `OcuTalon.Install.Registry.Ipm` (Configure, After).
  - `Ipm()` does nothing on the image (when `/opt/ocutalon/version` exists).
  - Elsewhere, `Ipm()` commits IPM's transaction to level 0, runs `Registry.Run("ipm")`, and reopens the same transaction levels on every path. The production cannot start inside IPM's transaction.
  - On the IPM path, the `STEP`/`WARN` lines print to the command's output. A step that fails after the commit adds `STEP <name> FAILED: the new OcuTalon code is installed. Run the same install command again.`
- **Exactly one reconcile per production start.** Only the `ipm` caller marks `OcuTalon.Production` autostart (`Ens.Director.SetAutoStart`, after a successful start); the Docker path never marks or clears it.
  - A start made by the `Production` step holds the lock `^OcuTalon.Install.Start` and is reconciled by the installer's `Reconcile` step.
  - Any other start (instance autostart, the portal, a session) is reconciled by the Lane A item `OcuTalon.Install.ReconcileIn` once its items run.
  - The `Reconcile()` declarations are idempotent.
- **Waiters and upgrades.** `ApprovalHold` and `ReminderTimer` are the only long-timer processes. Their rows (`ApprovalRequest`, `Reminder`) are the source of truth, and the reconciler re-arms a pending row whose process is gone, timed from the row's times, and cancels orphaned Workflow tasks.
  - Storage is append-only, and upgrade code never assumes a new property has a value on old rows.
  - The production class holds structure only, so a reinstall keeps settings.
  - Running jobs keep the old code until their item restarts.
- **Durability of the install.** The CPF merge runs outside IPM's transaction, so a failed install leaves the namespace and databases in place for the next run. The web bundle lives under the instance data directory's `csp/ocutalon-web/`.
- **Release sequence.** `release/release.sh` runs the steps `cut image overview ipm push notes`. `step_ipm` packages and records the artifact (Story 11.17, done).
- **CI hygiene.** No CI step pushes an image or signs in to a registry, and the AI Hub image never enters a cache or an artifact. `docker compose config` runs only with `--quiet`, and `docker inspect` only with `--format`. Restarts and destructive tests run only in throwaway stacks, never on the developer instance.
- **Ownership.** Lane A owns the installer core, `lane-a.yml`, `release/` and `docs/install-ipm.md`. `docker/tests/` is in Epic 15's footprint for this story's edits.

## UX & Interaction Patterns

- With demo mode off, an IPM install shows the branded sign-in page at `/ocutalon/`. The README account is `ocutalon`/`ocutalon`, with no forced password change.
- There is no demo guide, simulated phone or mailbox, or Break the feed. Trace links use the local-and-IPM sign-in popover.

## Cross-Story Dependencies

- **Already merged:**
  - 15.1 and 15.2, which give the CPF resource, `MapAndStop`, the IPM steps, `ReconcileIn`, autostart, the U-176 forced-failure path, and `release/ipm-install.sh` paths a, r and b;
  - Epic 9, which supplies Story 9.1's IPM case;
  - Story 11.17, which supplies the IPM artifact and its record.
- **Not built yet:** Story 11.14, the release sequence's full gate list, is in Epic 11 part 2 (backlog, after rc1). The FR-57 release gate must work with `release/release.sh` as it stands.
- **Lane B's waiters:** `ReminderTimer` and its `Reconcile()` are Lane B's. The restart test exercises them but does not change them.
- **Downstream:**
  - Story 31.3 builds the README's IPM section in the order this guide uses;
  - Stories 19.2 and 34.1 wait for Epic 15 to merge;
  - Epic 38's 1.0.0 checks rely on a working IPM package.
