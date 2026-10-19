---
title: 'Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock'
type: 'feature'
created: '2026-10-19'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The repository has no CI. Nothing checks a push or a pull request. The IRIS tests run only by hand, on slot A or in throwaway stacks. Several of AD-2's, AD-3's, AD-5's, AD-13's and AD-19's CI checks don't exist yet. The pipeline also has no recorded IRIS test recipe, no worktree bootstrap and no lock for throwaway stacks.

**Scope (Rule 22 split, October 19).** The model mock moved to Story 0.11: the mock service, its scenarios, its scenario file format and its tests. This story leaves a named, empty place for the mock's tests in the hosted web job, and a CI override with no mock service. The title still says "with the model mock"; that part is 0.11's.

**Approach:**
- **Two workflow files.**
  - `.github/workflows/ci.yml` (Lane B) has three jobs:
    - a hosted `checks` job, which runs every static check;
    - a hosted `web` job: build, lint, unit tests, and the mock-test place;
    - a self-hosted `iris` matrix of five groups, which runs the `%UnitTest` shards and the live scripts in throwaway compose projects with the CI override.
  - `.github/workflows/lane-a.yml` (Lane A) has one empty `standalone-bridge` job, which Story 1.3 fills.
- **One local recipe.** `ci/iris.sh` runs the same IRIS units on a developer machine, piece by piece.
- **Skips.** A job skips its own steps only when nothing it checks changed since the newest commit whose run was fully green. Pull requests never skip.
- **The checks.** The missing checks are added to the existing scripts and oracles, plus one new script for class rules and one for the workflows (DW-11, DW-17).
- **Pipeline configuration.** Rule 21's last bullet records the recipe and the timings, and `parallel.yaml` gets the bootstrap and the throwaway lock.

## Boundaries & Constraints

**Always:**
- **Workflow hygiene.**
  - `permissions: contents: read` at the top of each workflow. A job-level `permissions` block holds only `contents: read` and `actions: read`.
  - No `pull_request_target` and no `workflow_run`. No `paths` or `paths-ignore` filter on any trigger, so the workflow itself is never skipped.
  - Every third-party action is pinned to a full commit SHA, with a version comment.
  - No `secrets.` reference. The automatic `github.token` is used only as `GH_TOKEN`, for reading workflow runs.
  - Every checkout sets `persist-credentials: false`.
- **The image never leaks (CON-1, REL-4).**
  - No job pulls, pushes, saves, exports, caches or uploads an IRIS image.
  - No `docker/*` action, no `actions/cache` step, and no `upload-artifact` in a self-hosted job.
  - The base image is used only as the preloaded `ocutalon-iris-base:2026.3.0AI.154.0`, through `IRIS_IMAGE`.
- **Fork pull requests.** Every self-hosted job carries the job-level guard `github.event_name == 'push' || github.event.pull_request.head.repo.full_name == github.repository`.
- **Every pushed commit keeps its own run.** Push events never share a concurrency group, so a push never queues behind, or cancels, another push's run. Only pull-request runs cancel their own superseded run.
- **A skip never turns a red into a green.** The comparison base is a commit whose push run of the same workflow concluded `success`. With no such commit, on any API error, and for every pull request, everything runs.
- **Throwaways only.**
  - The recipe and every live script use `docker/tests/lib-live.sh` projects, named `ocutalon-<label>-<run tag>-<epoch>-<pid>`. They never touch a slot or any other container.
  - Each job runs at most one IRIS stack at a time, and so does a developer machine.
  - Each stack is torn down with `docker compose -p <project> … down -v --rmi local`.
  - The throwaway override (`docker/tests/compose.throwaway.yml`) publishes no host port. Only the browser scripts publish a web port on 127.0.0.1, from 52800 to 52819.
- **Scanners.**
  - Every scanner prints `file:line` and its rule, never the matched text.
  - Every scanner reads only files that git tracks, or new files git doesn't ignore. It never reads `.env` or `.env.*` other than `.env.example`.
  - Every scanner first shows, on synthetic samples, that it flags a bad case and passes a good one.
  - No script contains what its own scanners flag. Bad samples are assembled at run time, as `test-boundaries.sh` does with `d="docker"`.
- **No local machine path in any tracked file**, this story's own spec and Rule 21's text included. Name the session's scratchpad in words, never by its absolute path. Never write a runner host's paths or address.
- **Bash 3.2** (the macOS host's bash) for every script that runs on a developer machine. ASCII only, and comments state contracts (Rule 14).

**Never:**
- **No outward actions.** Never push, run `gh workflow run` or `gh run rerun`, or change a GitHub repository setting, branch protection or the runner host. Never SSH to the runner.
- **Not this story's work.** The mock service, its scenarios and its tests (0.11); the demo-path specs (0.8); the standalone-bridge job's content (1.3); the evaluation job (Epic 9); branch protection (11.5).
- **Pipeline rules.** Never edit `_bmad/custom/skill-rules.md` outside Rule 21's last bullet. Never edit `.claude/` or `CLAUDE.md`.
- **IRIS references.** Never load, copy, compile or commit anything from `irislib/` or `irissys/`.
- **Containers and slots.** Never stop, remove or recreate `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or a slot.
- **No new dependency** beyond the two GitHub actions and `@types/node` named in Design Notes.

## I/O & Edge-Case Matrix

Where each row runs:
- Rows 1–2: the hosted jobs.
- Rows 3–8: `ci/iris.sh` (CI and local).
- Rows 9–12: `docker/tests/test-ci-changes.sh` (hermetic) and the first real run.
- Row 13: `test-compose-file.sh`.
- Row 14: `test-production-restart.sh`.
- Rows 15–16: `test-ci-config.sh`.
- Row 17: a temporary worktree.
- Row 18: `test-lib-live.sh`.
- Row 19: the shards.
- The AC 3 rules are in the second table.

| # | Scenario | Input / State | Expected | Error Handling |
|---|---|---|---|---|
| 1 | Web job | push or PR that changes a web input; fresh checkout on `ubuntu-24.04` | `setup-node` restores the npm cache keyed on `web/package-lock.json`. `test-web-build.sh` runs in place: `npm ci`; `npm run build` (both `--check`s); `git status --short` empty; the bundle checks. Then `npm run lint` (e2e type check, and `node --check` on each `scripts/*.mjs`) and `npm test` (`node --test`). The step "Mock tests: none until Story 0.11" runs no test and says so | red, naming the step |
| 2 | Checks job | any push or PR | `bash ci/checks.sh` runs every script of `CHECK_SCRIPTS`, each to its end, and prints one block per script. It exits 1 naming each failed script. It is never skipped | red |
| 3 | IRIS group | `ci/iris.sh group <g>` | Fails at once, saying so, when `ocutalon-iris-base:2026.3.0AI.154.0` is missing. Otherwise: the web bundle is built if missing; each unit of the group runs in order, each in its own project with the CI override; one `UNIT <unit> passed\|failed <s>s` line per unit; exit 1 naming the failed units | red |
| 4 | Shard | `ci/iris.sh shard <name> [--reverse]` | One throwaway, `docker compose up -d --build --wait`. Then every test class of the shard's areas runs, in name order (reversed with `--reverse`). A test class is a non-abstract `.cls` under `Test/<Area>/` (either source tree) with a `Method Test…`. Each class runs through `%UnitTest.Manager` with no load. One `CLASS <name> passed\|failed <s>s` line per class, plus each failed assertion's description. The project is torn down | exit 1 when a class failed, ran no test, or is not compiled |
| 5 | One class | `ci/iris.sh class <Class>` | row 4 for that class alone | unknown class: exit 2 |
| 6 | Live unit | `ci/iris.sh live <name>` | runs `docker/tests/test-<name>.sh` with the run tag. `sign-in` runs `npx --prefix web playwright install chromium` first | the script's exit |
| 7 | Pieces | `build`, then one `shard`/`class`/`live` per call, then `teardown`, all with the same `OCUTALON_RUN_TAG` | `teardown` removes only the projects, volumes and images whose names carry `-<tag>-`. `list` prints the groups and units | a tag holding `slot`, or not matching `[a-z0-9-]+`: exit 2 |
| 8 | Two jobs at once | two groups on one host | Project names, image tags and volumes differ: the tag is `<run_id>-<run_attempt>-<group>`. The web port is 52810 plus the runner's number when `RUNNER_NAME` ends in `-<n>`, and the first free port otherwise | none |
| 9 | Classifier | the changed paths since the base | `web` is true for any of: `web/**`, `src/ocutalon/cls/OcuTalon/Live/**`, `src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls`, `_bmad-output/planning-artifacts/ux-designs/**`, `logo/**`, `ci/**`, `docker/tests/test-web-build.sh`, `.github/workflows/ci.yml`. `iris` is true unless every path is under `_bmad/` or under `_bmad-output/` outside `planning-artifacts/ux-designs/` | none |
| 10 | Base | push; the workflow's push runs that concluded success | The base is the first commit of `git rev-list HEAD` with such a run (HEAD itself on a re-run of a green run). On `pull_request`, with no such commit, or on an API failure: no base, and both flags true. Outputs: `base`, `web`, `iris`, `reason` | fails open: everything runs |
| 11 | Red, then bookkeeping | C0 green; C1 code, red; B1 bookkeeping only | B1's base is C0, so B1 runs C1's code again, and is green only if it passes | none |
| 12 | A skipped job | `web` or `iris` false | The later steps are skipped. One line names the base and the reason. The job succeeds; teardown still runs | none |
| 13 | CI override | `ci/compose.ci.yml` | `name: ocutalon-ci`; service `iris` gets `OCUTALON_EVAL: ${OCUTALON_EVAL:-0}` and nothing else. No ports, no `env_file`, no key variable. Any other service is named `mock` (0.11). The judges' file names no `ci/` file and no mock (CON-3). Both files parse together (`config --quiet`) | FAIL names the check |
| 14 | `OCUTALON_EVAL` pass-through | row 19 of `test-production-restart.sh`: `OCUTALON_EVAL=1` in the environment of `dc up`, with no extra compose file; then unset | as Story 0.6's row 19: `EvalIn` enabled and the System Default Setting row 1, then disabled and 0 | none |
| 15 | Fork PR | `pull_request` whose head repository is not this one | Every self-hosted job's `if:` is false. The hosted jobs run with a read-only token. Nothing caches or uploads an image | `test-ci-config.sh` FAIL |
| 16 | Workflow rules | both workflow files | `test-ci-config.sh` passes the rules listed in Tasks, and flags each rule's bad sample | FAIL: `file:line rule` |
| 17 | Bootstrap | a new detached worktree | `bootstrap` installs `web/`'s dependencies and links `irislib` and `irissys` to the main checkout's folders. `bootstrap_check` exits 0, and `git status --short` is empty | none |
| 18 | Throwaway lock | the `locks/` folder under `parallel.yaml`'s `worktree_base` (`.worktrees/.coordination/locks/`) of the main checkout exists | `live_start` creates `throwaway-iris.lock` atomically and prints `LOCK acquired`. A second run prints `LOCK waiting`, retries every 30–90 s for up to `OCUTALON_LOCK_WAIT` (240 s), then exits 75 naming the holder. Cleanup deletes only its own lock and prints `LOCK released`. Without that folder (CI, or a sequential run) no lock is taken | exit 75 |
| 19 | Every class in a throwaway | the 27 test classes | each passes in its shard on a fresh throwaway with the installed package, forward and reversed | Task 0's fixes |

AC 3's rules. Each rule is first shown to flag its bad sample, then run on the real tree.

| Rule | Fails on | Implementation | Runs in | New? |
|---|---|---|---|---|
| bridge-refs (AD-2) | an `OcuTalon.Bridge` or `.BridgeExample` class naming another `OcuTalon` package, as a class or as a table | `bridge_refs` moves from `test-install-start.sh` row 5 into `lib-scan.sh`. `test-class-rules.sh` runs it, and row 5 calls it | `checks`; IRIS `install` | moved |
| ai-allowlist (AD-2) | `%AI`, `EnsLib.AI` or `EnsLib_AI` in code outside the whole packages `OcuTalon.Bridge`, `.BridgeExample`, `.Agent`, `.Tools`, `.Docs`, `.Memory`, `.Mcp`, `.Install` and `.Test` | `test-class-rules.sh` | `checks` | new |
| duplicate `DEFAULTGLOBAL` (AD-3) | two classes or two registry rows sharing a global | `test-storage.sh` `registry-duplicate`, `registry-row`, `registry-class` | `checks` | existing |
| storage block (AD-5) | a storage-bearing class without a `Storage Default` block | `test-storage.sh` `storage` | `checks` | existing |
| release-diff (AD-5) | Any of: a stored class's block whose lines at the previous release tag are not a subsequence of its lines at HEAD; a stored class that HEAD removed; a shallow clone. With no release tag: `PASS release-diff: no release tag yet` | `test-storage.sh`, new rule, with synthetic git repositories as samples | `checks` | new |
| roundtrip (AD-5, DW-11) | a class whose compiled `Storage` block, exported after the install's load and compile, differs from the committed file; or a set of compared classes that differs from the set of committed blocks | `docker/tests/test-storage-roundtrip.sh`, live, with an in-run control | IRIS `image` (DW-11's "IRIS checks job") | new |
| docker-calls (CON-1, AD-22) | in a script, workflow or `ci/` file: `push`, `login`, `save` or `export`, `--push` or `--cache-to`; `inspect` without `--format`; `config` or `convert` without `--quiet` | `test-boundaries.sh` `risky_docker_calls`: scope gains `.github/` and `ci/`, plus the new forms | `checks` | extended |
| image-actions (CON-1, REL-4) | a `docker/*` action, `actions/cache`, or `upload-artifact` in a self-hosted job | `test-ci-config.sh` | `checks` | new |
| paths and keys (CON-5) | a local machine path (a home or volume folder with a name segment, a `/private/<tmp\|var\|etc>/` path, a Windows user path) or a key-like string, in any tracked or new file | `test-boundaries.sh` `local_path` and `key_like`: scope is every file; the path pattern needs a name segment | `checks` | extended |
| public-packages (AD-3) | a class of `OcuTalon.Web.Public` or `OcuTalon.Data.Public` whose superclasses, member types, `##class` calls, `$SYSTEM` members or dynamic dispatch go outside AD-3's allow-list; `$SYSTEM.Encryption` outside a generator method | `Test.Web.Status.TestReferencesOnlyThePublicAllowList`, extended from 2 classes to every class of both packages | IRIS `shards` (lane-b); slot A | extended |
| public-global (AD-19) | `OcuTalonPublic` on a code line of `src/` or `docker/after-start.cos`, outside `OcuTalon/Data/Public/Settings.cls` | `test-class-rules.sh` | `checks` | new |
| lane-regions (AD-5, AD-29) | missing or reordered markers; an item outside both regions; an item in the other lane's region, by the package split, or by the ownership table for the `EnsLib` items | `Test.Install.Production.TestDefinition` and `Test.Install.ProductionRules` (Story 0.6) | IRIS `shards` (lane-a); slot A | existing |
| unchecked-prepare (AD-13, DW-17) | outside the methods `OcuTalon.Data.Session:ForUser` and `OcuTalon.Live.Event:Since`: a `%Prepare` whose second argument is not `1`, a `%PrepareClassQuery` whose third argument is not `1`, or `%ExecDirectNoPriv` / `%ExecDirectNoPrivNoAudit`, even when the call spans lines or its SQL text holds commas and parentheses. Also an allow-list entry that matches no call | `test-class-rules.sh` | `checks` | new |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), by line:
  - AD-2 L109–120 (boundary check L117, `%AI` allow-list L119);
  - AD-3 L122–149 (public allow-list L135);
  - AD-5 L175–184 (storage block and diff L181);
  - AD-13 L341–384 (unchecked prepares L362);
  - AD-19 L477–517 (`^OcuTalonPublic` L516);
  - AD-22 L575–596 (override L581, `OCUTALON_EVAL` L593, image rules L596);
  - AD-23 L598–642;
  - AD-29 L758–773 (regions L768, workflow files L770);
  - Deployment table L1102–1130.
- **Epics** (`_bmad-output/planning-artifacts/epics.md`): this story L941–982 (DW-11 L980, DW-17 L982); 0.8 L984–999; 0.11 L1034–1049; 1.3 L1157 (its job in `lane-a.yml`).
- **PRD** (`_bmad-output/planning-artifacts/prds/prd-OcuTalon-2026-10-16/prd.md`): CON-1 L1212, CON-3 L1223, CON-5 L1227; REL-2 L1285; REL-4 L1289–1293 (30 minutes).
- **Pipeline:**
  - `_bmad/custom/skill-rules.md` L252: the bullet to replace. Rule 21 is L238–255.
  - `_bmad/custom/parallel.yaml`: `worktree_base` L5; `runtime_locks` L24–32; the bootstrap comments L34–39.
  - `.claude/commands/epic-cycle.md` L686–699 ("CI Is a Gate"): read only, and owner-only (see Design Notes).
- **Existing scripts:**
  - `docker/tests/lib-live.sh`:
    - `live_start` L20–41 (P at L23, deadline L28, LIVE_FILES L35);
    - `ensure_web_bundle` L52–80;
    - `live_web_port` L94–134;
    - `dc` L136;
    - `live_cleanup` L150–154;
    - `iris_script` L190;
    - `check_items_run` L462.
  - `docker/tests/compose.throwaway.yml`: unchanged.
  - `docker/tests/test-boundaries.sh`:
    - the scanners L26–58;
    - `scan_rule` L76–96;
    - the file scope L101–137;
    - the samples L141–180.
  - `docker/tests/test-install-start.sh` row 5 L194–245 (`bridge_refs` L199–208, its control L210–235).
  - `docker/tests/test-storage.sh`: the checker L31–163, the trees L174–224, the rules L261–295.
  - `docker/tests/test-production-restart.sh` row 19 L73–90 (the extra file L75–76, and `live_pop_file` L88).
  - `docker/tests/test-compose-file.sh`: the `check` helper L13, the compose rows L72–91, the dev-override pattern to mirror L178–199.
  - `docker/tests/test-web-build.sh`: the copy L35–60, the build L62–76, the checks L78–131.
  - `docker/tests/test-lib-live.sh`: the stub pattern L18–60.
- **Existing classes:**
  - `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls` L123–166 (`TestReferencesOnlyThePublicAllowList` and `Outside`).
  - The two allowed unchecked prepares: `src/ocutalon/cls/OcuTalon/Live/Event.cls` L38 (`Since`) and `src/ocutalon/cls/OcuTalon/Data/Session.cls` L50 (`ForUser`).
  - `Install/Step/PrivateData.cls` L31 prepares with the check on.
  - The lane-region oracles: `Test/Install/Production.cls` (`TestDefinition`, `Items()` L233) and `Test/Install/ProductionRules.cls`.
  - The public packages: `Web/Public/{ApiBase,Login,Shell,SignInAssets,Status}.cls` and `Data/Public/Settings.cls`.
- **Web:** `web/package.json` (scripts; no lint or test script yet); `web/tsconfig.json` (strict); `web/scripts/*.test.mjs` (3 `node:test` files); `web/playwright.config.ts`.
- **IRIS reference** (read only):
  - `irislib/%UnitTest/Manager.cls`: `RunTest` L386; `DebugRunTestCase` L428 (`/norecursive/noload/run/nodelete`); `Root()` L1910.
  - `irislib/%UnitTest/Result/TestCase.cls` L13: `Status` 0 failed, 1 passed, 2 skipped.
  - `irislib/%SQL/Statement.cls`: `%ExecDirectNoPriv` L437; `%Prepare(text, checkPriv = 1)` L519; `%PrepareClassQuery(…, pFlags)` L570, whose bit 1 is the privilege check (L580).
- **Measured October 19, plan stage (read-only):**
  - **Runners.** `ocutalon-ci-1` and `ocutalon-ci-2` are online, labelled `self-hosted, Linux, X64, ocutalon`.
  - **Repository.** Private, `allow_forking` true; default workflow permissions `read`; no workflow yet; no tag.
  - **Runner host** (from its notes): Docker 29.9.1, Compose v5.6.0, Node 24.22, `git`, `jq`, `curl`. No `gh`. Only the Health base image, so the non-Health runs stay local `(once)` checks.
  - **Actions:**
    - `actions/checkout` v7.0.1 is `3d3c42e5aac5ba805825da76410c181273ba90b1` (MIT, July 17);
    - `actions/setup-node` v7.0.0 is `820762786026740c76f36085b0efc47a31fe5020` (MIT, July 14; it has `cache` and `cache-dependency-path`).
  - **Slot A `%UnitTest` history** (`%UnitTest_Result.TestCase`, average seconds per class):
    - `Live.Publish` 4.36 (one run took 125 s);
    - `Contract.Checker` 1.61;
    - `Install.Registry` 0.41;
    - every other class under 0.25.
  - **Test classes.** 30 `.cls` under `Test/`. 27 are test cases. The other 3 are `Test.Contract` (abstract base), `Test.Core.ProductionItems` (oracle rows) and `Test.Web.StubRequest` (a helper). `src/module.xml`'s `OcuTalon.PKG` resource covers `OcuTalon.Test`. `test-production.sh` already calls `Test.Install.Production.Items()` inside a throwaway. (inference: the IPM install compiles every test class; Task 0 measures.)
  - **Unchecked prepares.** Exactly two in `src/`: `Event.cls:38` and `Session.cls:50`. `OcuTalonPublic` appears only in `Settings.cls` (and in `merge.cpf`'s mapping, which is not a class).
  - **Paths and keys across every tracked file:**
    - the key-like pattern: no hit;
    - the current path pattern: two hits in Story 0.1's spec (generic mentions with no user name);
    - the pattern with a name segment: no hit.
  - **`.gitignore` and symlinks** (git 2.50.1, a scratch repository): `irislib/` does not ignore a symlink named `irislib` (`?? irislib`); `/irislib` does.
  - **Reference folders:** `irislib/%Library/DynamicObject.cls` and `irissys/Security/` exist.
  - **Local tools:**
    - `jq` 1.7.1, `curl`, `shasum`, BSD `awk`, Ruby with YAML;
    - no PyYAML, no YAML module in `web/node_modules`, no `timeout`.
  - **Type checks:** `tsc` over `web/e2e/**` and `playwright.config.ts` fails only for want of Node's types (`process`, `node:crypto`).
  - `@types/node` 24.19.1 (MIT, October 1).

## Tasks & Acceptance

**Execution:**

**Task 0a: measure, before the recipe.** Record each result under Verification, and label anything not measured `(inference)`. Hold one throwaway at a time. The developer machine is ARM; the runner is x64.
- **How the test classes reach a throwaway.** In one `lib-live.sh` throwaway, count the compiled `OcuTalon.Test.*` classes (expected 30). Measure the exact session script that runs one class from the installed package: `%UnitTest.Manager.RunTest(":<class>", "/noload/nodelete/norecursive")` or `DebugRunTestCase`. Also measure:
  - whether `^UnitTestRoot` matters;
  - where the result lands (`%UnitTest_Result.TestInstance` / `TestCase` / `TestAssert`);
  - that a failing assertion gives `Status` 0 and a skipped one 2.
  
  If the package does not hold them, choose `docker compose cp` plus `$SYSTEM.OBJ.LoadDir` of the test tree, and record why.
- **Compose.**
  - `docker compose up -d --build --wait` with the CI override returns once the stack is healthy;
  - `down -v --rmi local` removes the project's image (whose tag is `<project>-iris`);
  - a project can be found from its containers, its volumes and its images.
- **DW-11's export.** Is `$SYSTEM.OBJ.ExportUDL` of a compiled class byte-identical to its file, or only its `Storage` block? The control's mutation (the third slot removed from `Bridge.Process.Decide`'s block, as in 0.6) must make the export differ from the mutated file.

Shared shell and the CI override (`docker/tests/`, `ci/`; Lane B):
- `docker/tests/lib-live.sh`:
  - P becomes `ocutalon-<label>-${OCUTALON_RUN_TAG:+<tag>-}<epoch>-<pid>`;
  - the deadline is `${OCUTALON_LIVE_DEADLINE:-540}` (CI sets 1200);
  - LIVE_FILES gains `ci/compose.ci.yml` after the throwaway override;
  - the throwaway lock of row 18:
    - claimed in `live_start`, before anything starts, and released in `live_cleanup`;
    - its content is Rule 12's: `epic=` and `stage=` come from `OCUTALON_LOCK_OWNER` when that is set, plus `project=<P>` and `acquired_at=<UTC>`;
    - the `LOCK` lines are printed for the stage to log.
  
  The STEP list and `expected_run` don't change.
- `docker/tests/lib-scan.sh` (new; sourced, functions only):
  - `scan_rule` (test-boundaries' contract, with the file list passed in);
  - `bridge_refs`, moved from row 5;
  - the in-scope file lists (`git ls-files -co --exclude-standard`, minus `.env` and `.env.*` other than `.env.example`).
- `ci/compose.ci.yml` (new), the CI-only override (row 13). AD-22, CON-3.

The recipe (`ci/`, Lane B):
- `ci/units.sh` (sourced; bash 3.2, no associative arrays). Every list is defined here once:
  - `CHECK_SCRIPTS`: `boundaries storage class-rules ci-config ci-changes compose-file pinned-sources after-start healthcheck lib-live`;
  - `WEB_SCRIPTS`: `web-build`;
  - the shards: `lane-a` = `Agent Bridge Install`, and `lane-b` = `Contract Core Data Live Msg Web`;
  - the groups, in matrix order:
    - `install` = `live:install-start live:install-upgrade`;
    - `production` = `live:production live:production-restart live:audit`;
    - `browser` = `live:sign-in live:bundle-folder`;
    - `shards` = `shard:lane-a shard:lane-b`;
    - `image` = `live:storage-roundtrip live:build-inputs live:compose-start`;
  - the web inputs and the bookkeeping set of rows 9–10.
- `ci/iris.sh`, the IRIS test recipe:
  - **Subcommands** (rows 3–8): `list`, `groups`, `build`, `shard <name> [--reverse]`, `class <Class>`, `live <name>`, `group <name>`, `teardown`, `all`.
  - **`all`** runs every group in turn, as a convenience; no Verification command depends on it.
  - **The tag.** `OCUTALON_RUN_TAG` defaults to `local-<epoch>-<pid>`. The pieces of one run share it.
  - **In CI** (when `RUNNER_NAME` ends in `-<n>`) it exports `OCUTALON_TEST_WEB_PORT` = 52810 + n.
  - **Shards** go through `live_start "shard-<name>"`, with the session script Task 0a measured.
  - **No developer instance.** It never names a slot.
- `ci/changes.sh`, the classifier and base of rows 9–12:
  - It uses `curl` and `jq` only, so it runs on both kinds of runner. It reads `GITHUB_EVENT_NAME`, `GITHUB_REPOSITORY`, `GITHUB_API_URL`, `GH_TOKEN`, and the workflow file name as an argument.
  - It queries `actions/workflows/<file>/runs?event=push&status=success&per_page=100`.
  - It writes `base`, `web`, `iris` and `reason` to `$GITHUB_OUTPUT` when that is set, and to stdout.
  - Test seams: `OCUTALON_CI_RUNS_FILE` (the API's answer) and `--paths-from <file>`.
- `ci/checks.sh`: runs `CHECK_SCRIPTS` (row 2).

**Task 0b: measure, with the recipe.**
- **Every test class in a throwaway** (row 19). Run `ci/iris.sh shard lane-a` and `shard lane-b`, forward and `--reverse`.
  - A class that needs slot-only state (no production running, a key in the environment, slot fixtures) is fixed in the test, with its Rule 22 ruling in the Spec Change Log. For example, `$$$AssertSkipped` where the production runs, as 0.6 did.
  - A product defect goes into frontmatter `deferred:`.
  - DW-9's `Test.Install.Users` flake is recorded if it shows; it is not fixed here.
- **Timings.**
  - per class (`TestCase.Duration`);
  - per shard, from the call's start to its teardown;
  - per live script;
  - the time to a ready stack.
  
  These feed Rule 21 and the group balance. Rebalance the groups in `ci/units.sh` so that no group exceeds about 15 minutes on the runner (inference: about twice the ARM time), keeping every unit in exactly one group.
- **Linux tools** (optional, once). Run `bash ci/checks.sh` in a `docker run --rm` container of the public `ubuntu:24.04` image, with `git` and `jq` added in the container. This catches GNU/BSD and mawk/BSD-awk differences. `test-compose-file.sh` may be left out of that run, since it needs the Docker CLI. Never use the AI Hub image for it. If it can't be run, the first real run is the evidence (inference until then).

The scripts (`docker/tests/`, Lane B):
- `test-boundaries.sh`:
  - it sources `lib-scan.sh`;
  - paths and keys cover every in-scope file, binaries skipped with `grep -I`;
  - the path pattern needs a name segment, and still flags its `path.bad` sample;
  - the ASCII and docker-call scopes gain `.github/` and `ci/`;
  - `risky_docker_calls` gains `save`, `export` and `--cache-to`, each with a bad sample;
  - the must-be-scanned list gains `.github/workflows/ci.yml`, `.github/workflows/lane-a.yml`, `ci/iris.sh`, `ci/compose.ci.yml`, `CLAUDE.md`, `_bmad/custom/skill-rules.md` and `_bmad-output/implementation-artifacts/sprint-status.yaml`.
- `test-class-rules.sh` (new, static) holds the rules `bridge-refs`, `ai-allowlist`, `public-global` and `unchecked-prepare` of the second table.
  - Each rule first runs on synthetic classes: one that breaks it, one that keeps it, and one with a comment-only mention.
  - `unchecked-prepare`'s samples are:
    - a two-line call;
    - SQL text with commas and parentheses;
    - `checkPriv` as a variable;
    - the allowed method;
    - another method of an allowed class;
    - a stale allow-list entry.
- `test-install-start.sh`: row 5 calls `bridge_refs` from `lib-scan.sh`, and keeps its checks.
- `test-storage.sh`: the new `release-diff` rule of the second table.
  - The previous tag is the highest `v[0-9]*` tag merged into HEAD, other than a tag on HEAD itself.
  - Its samples are synthetic repositories: append-only (pass), changed value (flag), removed class (flag), no tag (the no-op), and a shallow clone (FAIL).
- `test-storage-roundtrip.sh` (new, live, label `t07rt`). After `up --wait`:
  - it exports every compiled `OcuTalon.*` class that has a storage definition into a temporary folder in the container;
  - it compares each `Storage` block with `/opt/ocutalon/src`'s file;
  - it requires the compared set to equal the set of committed blocks.
  
  Its control:
  - load a copy of `Bridge.Process.Decide` with one slot removed, compile, export: the export must differ from the copy;
  - reload the original: the export must equal it.
- `test-production-restart.sh`: row 14. It drops the extra `eval.yml` file and its `live_pop_file`.
- `test-compose-file.sh`: CI override checks for row 13.
- `test-web-build.sh`: with `OCUTALON_WEB_BUILD_IN_PLACE=1`, and only when `GITHUB_ACTIONS` is `true` and the checkout is clean, it builds in place instead of copying, and runs the same checks.
- `test-lib-live.sh`: hermetic checks for the run tag in P, the deadline override, and the lock (claim, wait, exit 75, foreign lock kept).
- `test-ci-changes.sh` (new, hermetic): rows 9–12 on a synthetic repository with fake run lists (PR, no runs, API error, rerun of a green HEAD).

IRIS classes:
- `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls`: `TestReferencesOnlyThePublicAllowList` covers every class whose name starts with `OcuTalon.Web.Public.` or `OcuTalon.Data.Public.`, read from the class dictionary so a new class is covered. It checks, beside `Outside`'s `##class`, `$SYSTEM` and dispatch scan:
  - the superclasses (`%CSP.*`, dynamic objects and the two packages);
  - the property, return and argument types (also a datatype class);
  - `$SYSTEM.Encryption` only in a method whose `CodeMode` is a generator.
  
  The negative samples gain an `Extends` and a type outside the list, and `$SYSTEM.Encryption` in a plain method. AD-3. Rule 2: this extends the scan; it doesn't copy it.

Web (Lane B):
- `web/package.json` and `web/package-lock.json`:
  - devDependency `@types/node` `24.19.1`, exact;
  - `"lint": "tsc -p tsconfig.e2e.json && for f in scripts/*.mjs; do node --check \"$f\" || exit 1; done"`;
  - `"test": "node --test scripts/*.test.mjs"`.
- `web/tsconfig.e2e.json`: extends `tsconfig.json`, `noEmit`, `types: ["node"]`, and includes `e2e/**/*.ts` and `playwright.config.ts`.

Workflows:
- `.github/workflows/ci.yml` (`name: ci`, Lane B):
  - **Triggers:** `push` to `main`, `feature/OCT_OcuTalon_MVP` and `OCT-epic*`, and `pull_request`.
  - **Top level:** `permissions: contents: read`, and `concurrency` with `group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || github.run_id }}` and `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`.
  - **`checks`** (`ubuntu-24.04`, 15 min): checkout (`fetch-depth: 0`, `fetch-tags: true`), then `bash ci/checks.sh`.
  - **`web`** (`ubuntu-24.04`, 15 min; job permissions `contents: read` and `actions: read`), with these steps:
    1. checkout (`fetch-depth: 0`);
    2. `bash ci/changes.sh ci.yml`, with `GH_TOKEN: ${{ github.token }}`;
    3. if `web`: `setup-node` (`node-version: 24`, `cache: npm`, `cache-dependency-path: web/package-lock.json`); the in-place `test-web-build.sh`; `npm --prefix web run lint`; `npm --prefix web test`;
    4. the mock-test step;
    5. a skip line when `web` is false.
  - **`iris`** (`[self-hosted, ocutalon]`, 40 min; job permissions `contents: read` and `actions: read`; fork guard; matrix `group: [install, production, browser, shards, image]`, `fail-fast: false`).
    - Env: `IRIS_IMAGE`, `OCUTALON_RUN_TAG: ${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.group }}`, `OCUTALON_LIVE_DEADLINE: 1200`.
    - Steps:
      1. checkout (`fetch-depth: 0`);
      2. `ci/changes.sh ci.yml` with `GH_TOKEN`;
      3. if `iris`: `ci/iris.sh build`, then `ci/iris.sh group ${{ matrix.group }}`;
      4. a skip line;
      5. `if: always()`: `bash ci/iris.sh teardown`.
  - Pins: `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1` and `actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0`. AD-22, AD-29, REL-2, REL-4.
- `.github/workflows/lane-a.yml` (`name: lane-a`, Lane A): the same triggers, permissions and concurrency, and one job, `standalone-bridge`: `[self-hosted, ocutalon]`, the fork guard, 10 min, and one step that says the job is empty until Story 1.3. AD-29.
- `docker/tests/test-ci-config.sh` (new, static), over `.github/workflows/*.yml` in their fixed layout (two-space indent, one key per line, flow lists for `runs-on` and the matrix). Each rule has a bad and a good sample:
  - **permissions:** top level exactly `contents: read`; a job-level block only `contents: read` and `actions: read`;
  - **triggers:**
    - `push.branches` holds `main`, `feature/OCT_OcuTalon_MVP` and `OCT-epic*`;
    - `pull_request` has no filter;
    - no `pull_request_target`, `workflow_run`, `paths` or `paths-ignore`;
  - **concurrency:** the group expression uses `github.run_id` for non-PR events, and `cancel-in-progress` is the PR-only expression;
  - **pins:** `owner/repo@<40 hex> # v<x.y.z>`, and no `docker://`;
  - **runners:** `ubuntu-24.04` or `[self-hosted, ocutalon]`;
  - **fork guard** on every self-hosted job;
  - **secrets:** no `secrets.`, and `github.token` only as `GH_TOKEN`;
  - **image-actions:** see the second table;
  - **teardown:** `if: always()` with `ci/iris.sh teardown` in every job that runs `ci/iris.sh`;
  - **matrix:** ci.yml's `group:` list equals `ci/iris.sh groups`;
  - **units:**
    - every `docker/tests/test-*.sh` is in exactly one of `CHECK_SCRIPTS`, `WEB_SCRIPTS` or one group;
    - every `Test/<Area>/` folder of either source tree is in exactly one shard;
    - every class with a `Method Test…` sits in an area folder;
  - **lane-a:** the file exists with the job `standalone-bridge`;
  - **yaml:** `ruby -ryaml` parses each file. It prints `SKIP` when Ruby is missing, which never counts as a pass.

Pipeline configuration:
- `.gitignore`: add `/irislib` and `/irissys`, keeping `irislib/` and `irissys/` (measured: only the anchored form ignores a symlink).
- `_bmad/custom/parallel.yaml`:
  - `bootstrap`: `npm --prefix web ci --no-audit --no-fund`, then, for `irislib` and `irissys`, a symlink to the main checkout's folder (found through `git rev-parse --git-common-dir`) when the name is free and the folder exists;
  - `bootstrap_check`: `test -d web/node_modules/@angular/core && test -f irislib/%Library/DynamicObject.cls && test -d irissys/Security && test -z "$(git status --short)"`;
  - `runtime_locks`: `{name: throwaway-iris, stages: [], stale_minutes: 20}`, with a comment that `lib-live.sh` claims it while a throwaway stack runs.
- `_bmad/custom/skill-rules.md`: replace Rule 21's last bullet, and nothing else, with:
  - the recipe;
  - the shard, class and live commands;
  - the fresh-environment use: `shard` forward, then `--reverse`;
  - the hosted checks (`bash ci/checks.sh`);
  - the groups;
  - the measured per-class, per-shard and per-script timings, with the machine;
  - "two workflows run per push";
  - "QA adds the first real run's duration".
  
  No local path.

Workflow files, final Task 0 item:
- Parse both with `ruby -ryaml`.
- Optionally download one pinned `actionlint` release binary (MIT) into the session's scratchpad with `gh release download`, run it, and record its version. Never install it globally.
- Not measurable before the first real run (inference until QA reads it): `RUNNER_NAME`'s format; on `ubuntu-24.04`, `docker compose`, `dash`, `ruby` and the sha256 tool; the runs API's filters.

Tests: the scripts above. Every rule's bad sample is observed red in each run. The pinning mutations are under Verification.

QA stage (not this stage). After the lead pushes the implement commit, read the runs of both workflows with `gh run list --commit <sha>` and `gh run view <id> --log-failed`; a red is a finding. Add the run's wall-clock and per-job durations (`gh run view <id> --json jobs`) to Rule 21's entry.

**Acceptance Criteria:**
- **AC1, the jobs.**
  - Given a push to `OCT-epic0`, when CI runs, then `gh run list --commit <sha>` shows one `ci` run and one `lane-a` run.
  - In the `ci` run, `checks` and `web` ran on `ubuntu-24.04`, and the five `iris (<group>)` jobs on `ocutalon-ci-1` or `-2`. Each IRIS unit ran in its own compose project with the CI override and was torn down (rows 2–4).
  - Given a developer machine, when `ci/iris.sh` runs `build`, then each shard and live unit one per call, then `teardown`, then the same units pass against throwaway projects, and no project of the tag is left (rows 3–8).
- **AC1, the skips.**
  - Given a push whose diff from its base touches no web input, or only bookkeeping paths, when `web` or an `iris` job runs, then it skips its own steps, naming its base, and the workflow still runs.
  - Given the red-then-bookkeeping history, a pull request, no green ancestor, or an API failure, when the jobs run, then nothing is skipped (rows 9–12).
- **AC2.**
  - Given the CI override, when a throwaway starts with `OCUTALON_EVAL=1` in its environment, then `EvalIn` is enabled; without it, it is disabled (row 14).
  - Given the judges' compose file, when `test-compose-file.sh` runs, then it has no mock and no `ci/` reference (row 13).
- **AC3.** Given the repository, when the checks run (the `checks` job and the IRIS oracles of the second table), then each rule flags its bad sample, the real tree passes, and `release-diff` prints its no-op line.
- **AC4.** Given this story's tree, when the workflow files are listed, then `ci.yml` holds `checks`, `web` and `iris`, and `lane-a.yml` holds the empty `standalone-bridge` job (row 16).
- **AC5.** Given a pull request from a fork, when CI starts, then no self-hosted job runs, and no job caches or uploads an image (rows 15–16).
- **AC6.**
  - Given the two workflows, when `test-ci-config.sh` reads them, then both run on pushes to `main`, `feature/OCT_OcuTalon_MVP` and `OCT-epic*` and on every pull request, and no push run is queued or cancelled by another.
  - Given Rule 21 and `parallel.yaml`, when a fresh worktree is bootstrapped and two throwaway runs contend, then the recipe, the timings and the runner are recorded, the worktree stays clean, and the lock holds (rows 17–18).
- **DW-11.** Given a throwaway after the install, when `test-storage-roundtrip.sh` runs, then every committed `Storage` block equals the compiled export, and the in-run control is red as designed.
- **DW-17.** Given `src/`, when `test-class-rules.sh` runs, then only `Session.ForUser`'s and `Live.Event.Since`'s unchecked prepares pass, and any other unchecked prepare or a stale allow-list entry fails, naming `file:line`.
- **Every test class.** Given a fresh throwaway with the installed package, when each shard runs forward and reversed, then all 27 test classes pass (row 19).

## Spec Change Log

## Review Triage Log

## Design Notes

**ADs:**
- AD-2: the bridge boundary and the `%AI` allow-list.
- AD-3: the public packages' allow-list and the duplicate `DEFAULTGLOBAL`.
- AD-5: storage blocks, the release diff and the lane regions.
- AD-13: unchecked prepares (DW-17).
- AD-19: `^OcuTalonPublic`.
- AD-22: the CI override, the shards, CI's rules and `EvalIn`.
- AD-23: the start sequence and readiness behind `up --wait`.
- AD-29 and AD-33: the lanes, the two workflow files and the item ownership.
- CON-1, CON-3, CON-5, REL-2 and REL-4.

No AC contradicts an AD. No NFR tripwire: REL-4's 30 minutes is measurable, though at risk (see the time budget).

**Surfaces that no stage can reach.** AC5's outer surface is a pull request from a fork. Opening one needs a fork, which is outward-facing, so no stage can do it. Its pins are `test-ci-config.sh`'s fork-guard and image-actions rules, on the condition GitHub documents (inference until a fork pull request exists). AC1 and AC6's run behaviour are read on the first real run, by QA.

**Rule 22 rulings** (each as: question → choice (rejected: …)):

*Skips and the comparison base:*
- Rule 22 ruling: what base does a skip compare with? → The newest commit in HEAD's history whose push run of the same workflow concluded `success`. A skip only repeats a verdict that a green run reached on the same inputs. Pull requests, no base and API errors run everything. (rejected: `github.event.before`, which turns a red code head's bookkeeping successor green; running everything always, which costs a hosted minute and about 25 runner-minutes for each bookkeeping push.)
- Rule 22 ruling: may the IRIS jobs skip on a push that changes only `_bmad-output/` and `_bmad/`? → Yes, by steps: each `iris` job checks out, computes its flags itself and skips the rest, so the jobs and their names are the same in every run. `_bmad-output/planning-artifacts/ux-designs/` doesn't count as bookkeeping, because the web build reads `DESIGN.md`. A bookkeeping head therefore still needs a runner online for a few seconds. (rejected: skipping whole jobs through a hosted planning job, which is billed every run and holds every IRIS job behind it; never skipping.)

*Scan scope:*
- Rule 22 ruling: are `_bmad-output/` and the agent files in the path and key scans? → Yes. Every tracked or new file is scanned, as the AC says, `_bmad-output/`, `_bmad/`, `.claude/` and `CLAUDE.md` included. The path pattern needs a name segment, so a generic mention of a home folder is not a hit (measured: no hit in the tree). As a result, a spec or log that cites a machine path turns CI red until the lead fixes it. A hit under `.claude/` or in `CLAUDE.md` is the owner's to fix. (rejected: leaving `_bmad-output/` to CON-5's release checklist, which narrows the AC; the bare `/Users/` pattern, which flags two generic mentions in Story 0.1's spec.) VETO WINDOW.

*Lint, shards and grouping:*
- Rule 22 ruling: what is "lint"? → A strict type check of what `ng build` doesn't check (the Playwright specs, their helpers and `playwright.config.ts`), plus `node --check` of the build scripts. This needs `@types/node` 24.19.1 (MIT, pinned exactly). (rejected: ESLint with angular-eslint, which adds more dependencies and configuration for rules the strict compiler already holds; no lint, which drops an AC item.) VETO WINDOW.
- Rule 22 ruling: how are the `%UnitTest` classes sharded? → Two shards, each a union of whole areas aligned with the lanes. `lane-a` is Agent, Bridge and Install; `lane-b` is Contract, Core, Data, Live, Msg and Web. Measured on slot A, a whole shard's tests take seconds, so each shard costs one stack start. DW-9's flake is in `lane-a`, and each `CLASS` line names its class. (rejected: one shard per area, nine stack starts; one shard, which isn't sharding by area (AD-22).)
- Rule 22 ruling: which live scripts run in CI? → All ten, in every run, on the Health image. The non-Health runs stay local `(once)` checks, because the runner has only the Health base. The hermetic and static scripts run in `checks`, and `test-web-build.sh` in `web`. (rejected: live scripts only on pull requests, which drops checks from the epic pushes the gate reads.)
- Rule 22 ruling: how do two jobs on one host avoid each other's ports? → `OCUTALON_TEST_WEB_PORT` = 52810 + the runner's number. (rejected: the first free port, which two jobs can pick at the same moment.)

*Where each check lives:*
- Rule 22 ruling: where do the new class rules live? → `test-class-rules.sh`, beside a `lib-scan.sh` that holds the shared scanner contract and `bridge_refs`. (rejected: growing `test-boundaries.sh`, which scans other scopes.)
- Rule 22 ruling: what implements AC 3's lane-region and public-package checks? → The IRIS oracles. The existing `Test.Install.Production` and `Test.Install.ProductionRules` cover the lane regions. `Test.Web.Status` is extended from 2 classes to the 6 classes of both packages. These are the checks in "the checks" that need IRIS, and they run in the shards. (rejected: shell copies in the hosted job, which Rule 2 forbids without a reason stronger than speed.)
- Rule 22 ruling: what is DW-11's round trip, and where is "the IRIS checks job"? → A live script that compares the `Storage` blocks of a throwaway's compiled classes with the image's sources, with an in-run control. It runs in the IRIS group `image`, beside the other image checks. That group is DW-11's IRIS checks job, named `image` so it isn't confused with the hosted `checks` job. (rejected: a `%UnitTest` class, which can't run on slot A, where the image's sources don't exist; another row of `test-install-start.sh`, whose deadline is already used.)
- Rule 22 ruling: what does DW-17's check scan, and what does its allow-list name? → The three call forms that turn the privilege check off. Its allow-list is keyed by class and method; an entry that matches no call fails, so the list never names more than the code holds. Embedded SQL is not scanned, because AD-13 governs prepares. (rejected: keying by file, which would let a new method in an allowed class pass.)
- Rule 22 ruling: what is "differs other than by appending"? → The lines of the block at the tag must be a subsequence of the lines at HEAD. A shallow clone fails rather than claim there is no tag. (rejected: comparing `<Value>` counts, which misses a changed value.)

*Infrastructure and configuration:*
- Rule 22 ruling: where does the CI override live? → `ci/compose.ci.yml` (the spine's `ci/`, Lane B), with `name: ocutalon-ci`, after the throwaway override in `LIVE_FILES`. The throwaway override is unchanged. (rejected: merging the two files.)
- Rule 22 ruling: how do the IRIS jobs get the web bundle? → `ci/iris.sh build` builds it once per job, from the runner's warm npm cache. (rejected: an artifact from `web`, which would hold the IRIS jobs back and be missing when `web` skips.)
- Rule 22 ruling: how do runtime locks cover throwaway stacks? → `lib-live.sh` claims `throwaway-iris.lock` in the coordination folder while a stack runs. `parallel.yaml` lists the lock with `stages: []`. (rejected: a stage-scoped lock, which would serialize whole implement and QA stages across lanes.)
- Rule 22 ruling: how does a worktree get the reference folders? → Symlinks, plus the anchored `.gitignore` patterns, since the trailing-slash patterns don't ignore a symlink (measured). (rejected: copies, which CLAUDE.md forbids; `info/exclude`, which lives in the shared git folder.)
- Rule 22 ruling: where does `lane-a.yml`'s empty job run? → On `[self-hosted, ocutalon]`, with the fork guard, where Story 1.3 runs it. (rejected: a hosted placeholder, billed for every push.)
- Rule 22 ruling: concurrency? → Pull requests cancel their own superseded run. Pushes get a group per run, so they are never queued or cancelled: GitHub cancels a pending run when a third one joins its group. (rejected: a per-branch group; no group at all, which lets pull-request runs pile up.)
- Rule 22 ruling: where are the mock's tests? → A named step, "Mock tests: none until Story 0.11", that runs no test and says so. 0.11 replaces it. (rejected: a step that silently passes when `ci/mock/` is missing.)
- Rule 22 ruling: what deadline do the live scripts get on the runner? → 1200 s through `OCUTALON_LIVE_DEADLINE`, since a first start there takes about 2 minutes (inference for the scripts with several starts). Locally it stays 540 s.
- Rule 22 ruling: how is the bootstrap tested without breaking Rule 10? → In a detached worktree in the scratchpad, only while the working directory is the main checkout (`git rev-parse --git-dir` equals `--git-common-dir`). Inside a provisioned epic worktree, the test is skipped and recorded `(inference)`. (rejected: a `git clone`, whose common folder holds no reference folders.)

**Time budget (REL-4, inference).** Estimated from the ARM timings, doubled for the runner:
- about 55 runner-minutes over the five groups, so about 28 minutes of wall-clock on two runners;
- plus about 2 minutes of hosted jobs, which run in parallel.

Task 0b's local timings and QA's first real run settle it. If a run is over 30 minutes:
- the lead may rebalance the groups (`ci/units.sh` only);
- changing the 30-minute figure, or moving checks off epic pushes, is a decision for the owner.

**Integration ACs (Rule 1):**
- The lead's fresh-environment check (Rule 19) consumes `ci/iris.sh shard <name>` forward and `--reverse`, and reads the `CLASS` lines (Verification).
- `/epic-cycle`'s pre-flight and CI gate consume the runs of both workflows for the pushed sha (QA, AC1).
- The orchestrator's bootstrap consumes `parallel.yaml` in a fresh worktree (row 17).
- Later first consumers are 0.8, 0.11 and 1.3.

**Consumes:**
- 0.1: the image, the compose file, `test-compose-file.sh` and `test-build-inputs.sh`;
- 0.2: `lib-live.sh` and the live install scripts;
- 0.3: the web build, `test-web-build.sh`, `test-sign-in.sh`, Playwright and `signIn()`;
- 0.4: `test-storage.sh` and the contract oracles;
- 0.5: `Test.Web.Status`, `Live.Event.Since` and `Session.ForUser`;
- 0.6: `OcuTalon.Production`, the item oracles, `test-production*.sh`, `EvalIn` through `OCUTALON_EVAL`, and row 5's `bridge_refs`.

**Consumed-by:**
- 0.8: the `browser` group and the IRIS job, for the demo-path specs.
- 0.9 and 0.10: their test classes join the shards by area, and their live scripts join a group.
- 0.11: the mock service in `ci/compose.ci.yml`, and the mock-test step in `web`.
- 1.3: `lane-a.yml`'s `standalone-bridge` job.
- Epic 9: the evaluation job in `lane-a.yml`, with `OCUTALON_EVAL=1`.
- 11.5: branch protection over the `ci` and `lane-a` checks.
- `/epic-cycle`: the CI gate, Rule 21's recipe, and `parallel.yaml`'s bootstrap and lock.
- Every later story: a new `Test.<Area>` must join a shard (`test-ci-config.sh` fails otherwise).

**Reuse (Rule 2):**
- `bridge_refs` and `scan_rule` move into `lib-scan.sh`, so no copy is made.
- The public-package scan is extended in place.
- The lane-region check is the 0.6 oracles.
- The live scripts and the shards share `lib-live.sh`.
- The web job reuses `test-web-build.sh`.
- `test-production-restart.sh` row 19 now pins the pass-through.

**Ledger inbox:**
- DW-11 is addressed by the roundtrip rule, its task and its AC.
- DW-17 is addressed by the unchecked-prepare rule, its task and its AC.
- No entry is declined.

**Owner-only (Rule 22.4), for the Contest Planner:**
- **The CI gate reads one run.** `/epic-cycle`'s gate (`.claude/commands/epic-cycle.md` L690 and L893) reads `gh run list --branch … --commit <sha> … -L 1`. With two workflow files it sees only one of them. Recommended wording: "list every run for the sha (`-L 20`) and require each workflow's run to conclude `success`". Until then the lead checks both runs by hand.
- **Repository settings.** Keep "run workflows from fork pull requests" off for this private repository, and set branch protection at 11.5. The job-level fork guard holds either way.
- **Spend.** No spend beyond the hosted minutes the ACs require: about 2–5 billed minutes a run (inference).

**VETO WINDOW (Rule 22.3), for the lead's FYI:**
- the two GitHub actions (MIT, pinned) and `@types/node` 24.19.1 (MIT);
- the scan scope ruling;
- the IRIS jobs' token permission (`actions: read`);
- the skip rule.

**Spine updates for the lead (Rule 20):**
- **AD-22:**
  - `ci/compose.ci.yml` (`name: ocutalon-ci`);
  - the lane-aligned area shards and the five IRIS groups;
  - the skip rule (the green-ancestor base; steps, never workflows);
  - all live scripts on the Health image in CI;
  - the `image` group as the IRIS checks job.
- **AD-29:** `ci.yml`'s jobs and `lane-a.yml`'s `standalone-bridge` job on the IRIS runner.
- **AD-13:** a CI check allows unchecked prepares only for `Session.ForUser` and `Live.Event.Since`, by class and method (DW-17).
- **AD-3:** the public-package check covers every class of both packages.
- **AD-5:** the release diff is a line subsequence against the highest earlier `v*` tag, and CI runs a round trip.
- **Stack:** `@types/node` 24.19.1, `actions/checkout` v7.0.1 and `actions/setup-node` v7.0.0, with their SHAs.

**Size, and where to split it (for the lead):** this story is oversized: about 15 new or changed scripts, 2 workflows and the configuration. The clean line:
- **0.7:** the workflows, the recipe and `lib-live.sh`, the skips, the CI override, `test-ci-config.sh`, `test-ci-changes.sh`, the wiring of the existing checks, the path and key scope, the web lint and tests, Rule 21, `parallel.yaml` and `.gitignore`. That is rows 1–19, and the existing and extended rules of the second table.
- **0.12** (the next number in Epic 0): the new AC 3 rules, `release-diff`, roundtrip (DW-11), `ai-allowlist`, `public-global` and `unchecked-prepare` (DW-17), with the `Test.Web.Status` extension. It follows 0.7, because its checks run in 0.7's jobs.

## Verification

**Runtime targets:**
- Throwaway projects `ocutalon-<label>-<tag>-*` through `lib-live.sh`, one at a time, each torn down by its own trap or by `ci/iris.sh teardown` with the same tag. The tags are `v07a` for the recipe and the script defaults otherwise.
- Slot A (`ocutalon-slot-a`, profile `ocutalon-slot-a`, `namespace: OCUTALON` on every call) only for `Test.Web.Status`, and for any test class Task 0b changes, one class per call. Check its identity first with `iris_server_info` (build 154).
- GitHub: read-only `gh api` only.
- Nothing is pushed; the lead pushes. No other container is touched.

Every command finishes in one foreground call. Docker and npm calls pass `timeout: 600000`.

**Commands:**
- `(loop)` One call each, expected exit 0:
  - `bash docker/tests/test-boundaries.sh`;
  - `test-storage.sh`;
  - `test-class-rules.sh`;
  - `test-ci-config.sh`;
  - `test-ci-changes.sh`;
  - `test-compose-file.sh`;
  - `test-pinned-sources.sh`;
  - `test-after-start.sh`;
  - `test-healthcheck.sh`;
  - `test-lib-live.sh`.
- `(loop)` `bash ci/checks.sh`. Expected: exit 0, one block per script, and `release-diff`'s no-op line.
- `(loop)` `ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }' .github/workflows/ci.yml .github/workflows/lane-a.yml`. Expected: exit 0.
- `(loop)` `npm --prefix web ci`, then `npm --prefix web run build`, then `npm --prefix web run lint`, then `npm --prefix web test`, one call each. Expected: exit 0.
- `(loop)` `OCUTALON_RUN_TAG=v07a bash ci/iris.sh build`, then `shard lane-a`, then `shard lane-b`, one call each. Expected: exit 0, and a `CLASS` line for each of the 27 classes.
- `(loop)` `OCUTALON_RUN_TAG=v07a bash ci/iris.sh live storage-roundtrip`, then `live production-restart`, one call each. Expected: exit 0.
- `(loop)` `OCUTALON_RUN_TAG=v07a bash ci/iris.sh teardown`. Expected: then `docker ps -a --filter label=com.docker.compose.project --format '{{.Label "com.docker.compose.project"}}' | grep -c v07a` is 0, and no `-v07a-` volume or image is left.
- `(once)` `shard lane-a --reverse`, then `shard lane-b --reverse`. Expected: exit 0.
- `(once)` `class OcuTalon.Test.Install.Users`. Expected: exit 0, or a recorded DW-9 occurrence.
- `(once)` `live` for each of `compose-start`, `install-start`, `install-upgrade`, `sign-in`, `audit`, `bundle-folder`, `production` and `build-inputs`, one call each. Expected: exit 0, with the timings recorded.
- `(once)` `bash docker/tests/test-web-build.sh` (copy mode). Expected: exit 0.
- `(once)` Bootstrap, only from the main checkout (see its ruling):
  - `git worktree add --detach` into the session's scratchpad, then run `bootstrap` and `bootstrap_check` there. Expected: exit 0, and `git status --short` there empty.
  - Then `git worktree remove --force` and `git worktree prune`. Expected: `git worktree list` is as before.
- `(once)` Slot A: `iris_doc_load` of `Test/Web/Status.cls` (`compile: true`), then `iris_execute_tests` `OcuTalon.Test.Web.Status`. Expected: 0 failed.
- `(once)` Optional: actionlint from the scratchpad, and `ci/checks.sh` in an `ubuntu:24.04` container (Task 0b).

**Shared surfaces:**
- `.github/workflows/ci.yml` and `.github/workflows/lane-a.yml`: their job names and checks, which 11.5 and the CI gate read;
- `ci/compose.ci.yml`, now in every live test's `LIVE_FILES`;
- `docker/tests/lib-live.sh`'s project names, deadline and lock;
- the coordination lock `throwaway-iris.lock`;
- the throwaway project names `ocutalon-<label>-<tag>-<epoch>-<pid>` and their image tags `<project>-iris`;
- the host ports 52800–52819 (52811 and 52812 on the runner);
- Rule 21's section in `_bmad/custom/skill-rules.md`;
- `_bmad/custom/parallel.yaml`;
- `.gitignore`;
- `ci/units.sh`'s lists, which `test-ci-config.sh` compares with `ci.yml`;
- the scopes and samples of `test-boundaries.sh` and `test-storage.sh`;
- `Test.Web.Status`'s class list;
- in throwaways, `^UnitTest.Result`;
- the npm cache and the Playwright browser cache on the runner.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, see red, revert; `git status --short` and `git diff --stat` unchanged):
- AC1: `Test.Agent.Constants` expecting a wrong `MOCKKEY` → `shard lane-a` exits 1 with that class's `CLASS … failed` line, and `group shards` exits 1 naming `shard:lane-a`.
- AC1, skips:
  - `ci/changes.sh` using the parent commit as its base → `test-ci-changes.sh` red at red-then-bookkeeping;
  - `_bmad-output/planning-artifacts/ux-designs/` treated as bookkeeping → `test-ci-changes.sh` red at the `DESIGN.md` case.
- AC2:
  - `OCUTALON_EVAL: "0"` hard-coded in `ci/compose.ci.yml` → `test-production-restart.sh` row 19 red;
  - `ports:` added to the override → `test-compose-file.sh` red.
- AC3, one per new or extended rule:
  - `%Prepare("SELECT 1", 0)` added to `Data/Setting.cls` → `unchecked-prepare` red at that line;
  - `ForUser` renamed in the allow-list → stale-entry red;
  - `##class(%AI.Agent)` in a `Watch` class → `ai-allowlist` red;
  - `$Get(^OcuTalonPublic("ready"))` in `Web/Public/Status.cls` → `public-global` red;
  - a value changed in a synthetic tagged repository → `release-diff` red;
  - `docker save` in a scratch `ci/` file → `docker-calls` red;
  - a home path with a name in a scratch tracked-file copy → `paths` red;
  - `Extends OcuTalon.Data.Setting` in a copy of `Status` on slot A → `Test.Web.Status` red;
  - the control of `test-storage-roundtrip.sh` disabled → its control check is red.
- AC4: `lane-a.yml` deleted → `test-ci-config.sh` `lane-a` red.
- AC5:
  - the fork guard removed from `iris` → `fork guard` red;
  - an `actions/cache` step added → `image-actions` red.
- AC6:
  - `cancel-in-progress: true` → `concurrency` red;
  - `OCT-epic*` dropped from the triggers → `triggers` red;
  - `/irislib` dropped from `.gitignore` → the bootstrap worktree's `git status --short` shows `?? irislib`;
  - a foreign lock file → `test-lib-live.sh` lock check red when cleanup deletes it.
- DW-11: the third slot removed from `Decide`'s committed block → `test-storage-roundtrip.sh` red naming `Decide`.
- DW-17: see AC3.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Planning summary (October 19).**
- **Sources.** The spec was planned against:
  - the committed `epic-0-context.md` and Story 0.6's spec (continuity);
  - the spine, by line range: AD-2, AD-3, AD-5, AD-13, AD-19, AD-22, AD-23, AD-29, the Stack and the Deployment table;
  - the PRD's CON-1, CON-3, CON-5, REL-2 and REL-4;
  - `epics.md` (0.7, 0.8, 0.11, 1.3);
  - the ledger inbox (DW-11, DW-17).
- **Read-only measurements.** Slot A's identity and `%UnitTest` history; the runners, the repository settings and the action SHAs through `gh api`; and, in a scratch repository, `.gitignore` against a symlink.
- **Checks.** No intent gap; no AC contradicts an AD; no NFR tripwire. REL-4 is at risk, labelled `(inference)`, and is settled by Task 0b and the first real run.
- **For the lead.** The split line for 0.12; the owner-only item about `/epic-cycle`'s one-run CI gate; the VETO WINDOW items; the spine updates (Design Notes).
