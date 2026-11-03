# Epic 15 Context: Install into an existing IRIS with IPM

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

An IRIS user installs OcuTalon into an existing AI Hub build 154 instance with its one IPM package, `ocutalon`, which also installs the bridge. The install is the same package run twice. The first run, in any Interoperability-enabled namespace (USER on build 154), creates OCUTALON and stops with the next command. The second run, in OCUTALON, gives a working OcuTalon with demo mode off. `iris merge` plus `zpm "enable -map -ns OCUTALON"` can replace the first run. Stories 15.1-15.3 are done: the two-run install, demo mode off, restart and reinstall durability, and the FR-57 CI job. The remaining story, 15.4, makes every release from 1.0.0 on prove its IPM package. That means a release gate on the FR-57 job, a Node-free install of the exact artifact from a local IPM repository (which needs OCUTALON to see the first namespace's repositories), and a judge-facing guide that opens with the registry install.

## Stories

- Story 15.1: The first install run creates OCUTALON and gives the next command (done)
- Story 15.2: The second install run gives a working OcuTalon with demo mode off (done)
- Story 15.3: An IPM install survives restarts and reinstalls (done)
- Story 15.4: Every release proves the IPM package, and the guide opens with the registry install

## Requirements & Constraints

**Release gate.** From 1.0.0 on, the release sequence stops any candidate on which the FR-57 job did not pass. The candidate is pushed only at the `push` step, and `lane-a` doesn't run on `release/*` branches. So the gate is a release step that runs the job's own command, `bash release/ipm-install.sh`, on the candidate's exported tree with the candidate's artifact, after `ipm` and before `push`. The script's exit contract is already defined: 0 pass, 75 busy, 1 fail, 2 usage. The step writes a record section for the FR-57 job, and any failure stops the release before `push`. Story 11.14 will later call this step, or read the `ipm-install` job of its full CI run.

**Exact-artifact install, before any publish.**
- Install the exact artifact the release would publish on a clean build 154 throwaway with no Node.js. Story 11.17 builds the web page into that artifact and records it.
- Install it through a local filesystem IPM repository: `zpm "repo"` pointing at the artifact's folder, then `zpm "install ocutalon"` and its two steps.
- Prove that `/ocutalon/` serves the branded sign-in page and that the README account signs in.
- The release notes record the artifact's size. A size over a few MB is reported to the Contest Planner (iteration-1 threshold: 5,000,000 bytes).
- In CI, when no artifact is given, package the module installed by the first install path and check it with lib-release's artifact check.
- Measured on today's code: the second command in OCUTALON fails with "No repositories are configured and enabled in this namespace", because IPM keeps repositories per namespace. The repository mapping below fixes this.

**Repository mapping (U-232, kept with conditions).**
- The first run's map-and-stop step also maps IPM's repository definitions (`^IPM.Repo.Definition` D/S/I) from the run namespace into OCUTALON. Use IPM's own `enable -map -repos -ns OCUTALON -q` if IPM 0.10.10 supports it, otherwise the equivalent global mapping; measure which on a throwaway.
- The definitions are mapped as they are, never copied, created, edited or printed. No test or log prints a definition's fields.
- Uninstall removes only the mapping, never the first namespace's repository data. A test compares a hash of the definitions' global before and after uninstall, and never prints the hash.
- The guide says plainly that OCUTALON shares the first namespace's repositories, so adding or removing one in either namespace changes both.
- If the security overview or its generated lists describe OCUTALON's mappings, list this mapping there too.

**Registry install.** This story never publishes. It delivers:
- the guide's registry section, measured on a clean build 154 throwaway up to the point that needs the published package;
- an after-publish checklist row, `registry-install`, that reads `later` until the author confirms;
- a release-notes slot, `### Registry install`.

After the author publishes 1.0.0, and on the author's word, the README's two commands run once against the registry on a clean instance, and the result goes into the release notes.

**`docs/install-ipm.md` rewrite, registry first.**
1. The registry install comes first. It opens with the line that enables the community registry on a fresh IPM 0.10.10: its exact form and its output, both measured (`zpm "enable -community"` is only an example). Then comes `zpm "install ocutalon"` with the two-step namespace message.
2. The load-from-folder path, which needs Node.js to build the page, comes second, for developers.

Until the publish, the guide shows the real output of the local-repository install; the registry's own output replaces it afterwards. The rewrite must keep U-231's advice: run the first command in USER, and quote IPM's refusal in a namespace without Interoperability, such as %SYS. Keep the existing content as well: `iris merge`, demo mode, the model key, the README account and the U-176 re-run line.

**DW-576.** Run `docker/tests/test-release-sequence.sh --live ipm` on a candidate that carries Epic 15's two-run `module.xml` before relying on 11.17's artifact record. So far only the one-run path has been proved live.

**Throughout.**
- An IPM install never changes the instance's services and never runs installer steps outside OCUTALON.
- `SystemRequirements` (`>=2026.3`, Interoperability enabled) stays as written.
- Keys come only from the environment, and the CI model mock stands in for the model.
- The FR-57 job must stay within its 35-minute budget; 15.3 projected about 23.5 minutes.
- Each local live call must fit the 10-minute command cap: split the run, and never raise the timeout.

## Technical Decisions

- **Install sequence.** `module.xml` lists, in order:
  1. the CPF resource `src/cpf/ocutalon.cpf` (Initialize, before);
  2. the preload map-and-stop step (`OcuTalon.Install.Ipm`, under `src/preload/cls/`, Initialize, After);
  3. `OcuTalon.Install.Registry.Ipm` (Configure, After).
- **Map-and-stop rules.** Configuration it keeps when the run stops is made with transactions suspended, restoring the previous state on every path. The repository mapping follows the same rule. The stop keeps IPM's `ERROR! ` prefix: IPM 0.10.10 has no honest unprefixed stop.
- **Spine edits.** Adding the repository mapping changes the spine's "IPM early step" wording, and the AD-23 sentence still says "first in any namespace". A runner never amends an AD, so report both to the orchestrator.
- **Release tooling.**
  - `release/release.sh` runs the steps `cut image overview ipm push notes`, and the new step slots in after `ipm`.
  - `release/lib-release.sh` already has the artifact path, unpack and check helpers.
  - `release/ipm-install.sh` has the modes `a` (two runs), `r` (forced failure and recovery) and `b` (`iris merge`, restarts, next-version reinstall); the repository install is a new part of that script.
- **CI and live hygiene.**
  - No CI step pushes an image or signs in to a registry, and the AI Hub image never enters a cache or an artifact.
  - Fork pull requests never run on the IRIS runner.
  - Installs run only in throwaway stacks (`release/ipm/Dockerfile`: no after-start script and no version file), one fresh stack at a time.
  - `docker compose config` runs only with `--quiet`, and `docker inspect` only with `--format`.
- **Ownership.** Lane A owns the installer core, `release/`, `lane-a.yml` and `docs/install-ipm.md`. The README is Lane B's.

## UX & Interaction Patterns

- The guide is the judge's path to the IPM bonus. Show real measured output, plain words, and the two commands first.
- With demo mode off, an IPM install shows the branded sign-in page at `/ocutalon/`. The README account is `ocutalon`/`ocutalon`, with no demo guide, simulated devices or Break the feed.

## Cross-Story Dependencies

- **Consumed from done work:**
  - Stories 15.1-15.3 give the CPF resource, map-and-stop, the IPM steps, autostart and `ReconcileIn`, the U-176 forced-failure path, the %SYS refusal check, and `release/ipm-install.sh` with modes `a`, `r` and `b`.
  - Story 11.17 builds the IPM artifact (with the built page) and records it.
- **Story 11.14** (backlog, after rc1) builds the pushed-candidate gate list and will call the FR-57 release step. The gate must work with `release/release.sh` as it stands today.
- **Downstream:**
  - Story 31.3 (Lane B) builds the README's IPM section from this guide, in the same registry-first order.
  - Stories 19.2 and 34.1, and Epic 38's 1.0.0 checks, rely on this install path.
  - Story 15.4 must ship before rc1.
