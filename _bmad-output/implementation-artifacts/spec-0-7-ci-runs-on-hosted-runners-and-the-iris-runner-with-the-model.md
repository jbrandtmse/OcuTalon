---
title: 'Story 0.7: CI runs on hosted runners and the IRIS runner, with the model mock'
type: 'feature'
created: '2026-10-19'
status: 'done'
baseline_revision: '80abb60cc9ab3de021f9daf9bcb3b38d66504938'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      .gitattributes forces LF for docker/**, src/** and web/** but not for ci/**, so a Windows checkout with core.autocrlf=true would give ci/*.sh CRLF line endings and break them.
    evidence: |-
      The recipe and the classifier run only on Linux runners and on a developer machine with bash, so nothing is broken in CI; docker/** has the rule because the image copies its scripts. Adding `ci/** text=auto eol=lf` is a one-line change to a file this story may not edit.
    location: >-
      .gitattributes
    severity: low
  - summary: >-
      release-diff reads the files at HEAD (git show), not the working tree, so a hand edit of a committed Storage block shows red only after it is committed.
    evidence: |-
      The same edit is caught earlier by the roundtrip rule on the image (which builds from the working tree) and by the storage rule for a missing block. Reading the working tree would need a rule for files that are new and untracked.
    location: >-
      docker/tests/test-storage.sh
    severity: low
  - summary: >-
      The public-package check in Test.Web.Status scans ##class calls, $SYSTEM members, dynamic dispatch, superclasses and declared types, but not embedded SQL, query bodies, direct global references or macros, so a pre-sign-in class could read private data without failing CI.
    evidence: |-
      AD-3 says the two public packages reference nothing outside the allow-list. The scope of this story extends the existing scan with superclasses, types and $SYSTEM.Encryption; the scan before it covered the same ##class, $SYSTEM and dispatch forms, and no public class today uses embedded SQL or a private global (not verified beyond the six classes read by the scan). The public-global rule of test-class-rules.sh covers only ^OcuTalonPublic.
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Web/Status.cls
    severity: medium
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

Implement stage, October 19. No intent gap: no AC contradicts an AD, and no NFR can't be implemented. Rule 22 rulings made alone (each as: question -> choice (rejected: ...)):

- Rule 22 ruling: how does a shard run a test class from the installed package? -> One `iris session` per class: `Set ^UnitTestRoot="/tmp/"`, then `%UnitTest.Manager.RunTest(":<Class>", "/noload/nodelete/norecursive")`, then the result is read through `%UnitTest.Result.TestInstance`, `TestSuite`, `TestCase`, `TestMethod` and `TestAssert`. Measured (Task 0a): the 30 `OcuTalon.Test.*` classes are compiled by the package install, and `^UnitTestRoot` matters, because the manager checks its folder even with no load (rejected: leaving it empty, which fails with "Directory name ... is invalid"; `docker compose cp` and `LoadDir`, which the package makes unnecessary).
- Rule 22 ruling: which compiled classes does DW-11's round trip compare? -> Those with a `%Dictionary.CompiledStorage` row whose class has no `GeneratedBy`: 53, equal to the 53 source files with a Storage block. Fourteen more classes have storage rows: the generated `MessagesReceived` and `MessagesSent` classes of the business processes (rejected: all 67, which could never equal the committed set).
- Rule 22 ruling: whole file or Storage block? -> The Storage block, as the spec says. Measured: `ExportUDL` of each of the 53 compiled classes is byte-identical to its committed file, so the block comparison is the weaker of two true statements (rejected: a whole-file comparison, which would turn red on a harmless formatting difference).
- Rule 22 ruling: is a `%Prepare` with no second argument unchecked? -> No. `checkPriv` defaults to 1, and `PrivateData.cls` and about forty test calls rely on it; only an explicit second argument other than `1` is flagged, and likewise a third argument of `%PrepareClassQuery` (its `pFlags` defaults to 1). An allow-list entry is stale when no unchecked call sits in its method. The synthetic classes are judged by their own allow-list, so that a change to the real list is judged on `src/` alone (rejected: flagging a missing argument, which would flag 40 correct calls).
- Rule 22 ruling: what is a name segment in the path scan? -> A letter or digit right after the home or volume folder. Measured: Story 0.1's spec holds `/Users/...`, a generic mention with no name, which the first pattern flagged.
- Rule 22 ruling: what are the types and superclasses that `Test.Web.Status` allows? -> Superclasses: `%CSP.*`, dynamic objects and the two packages. Types: the same, and the system datatype classes (`%`-prefixed, `ClassType` datatype: `%String`, `%Integer`, `%Boolean`, `%Status`); every other class, a datatype class of another package included, is outside. `$SYSTEM.Encryption` is allowed when every use of it lies in the body of a method whose `CodeMode` is `generator` or `objectgenerator` (counted, so one more use outside fails) (rejected: no `%` types, which would flag every `As %String`).
- Rule 22 ruling: what does `ci/iris.sh build` do, and what is a valid tag? -> `build` checks the base image and always rebuilds the web bundle from the checkout; `group`, `shard`, `class` and `live` build it only if missing. A tag has at least 3 characters, so that the `-<tag>-` of a teardown can't match `-a-` in `lane-a`; `teardown` needs an explicit tag and also removes leftover containers by name (rejected: a defaulted tag for teardown, which matches nothing).
- Rule 22 ruling: how does `ci/changes.sh` call the API? -> On the repository of the current directory, with the token on curl's standard input, so that no command line holds it (rejected: `-H` on the command line).
- Rule 22 ruling: what is in the throwaway lock? -> Rule 12's line with `OCUTALON_LOCK_OWNER` (for example `epic=0 stage=implement`, default `epic=unknown stage=throwaway`) followed by `project=<P> acquired_at=<UTC>`. Test seams: `OCUTALON_LOCK_DIR`, `OCUTALON_LOCK_SLEEP_MIN`, `OCUTALON_LOCK_SLEEP_MAX`.
- Rule 22 ruling: how exact is `test-ci-config.sh`? -> The concurrency group, the cancel expression and the fork guard are compared as exact strings, so a change to them is a deliberate change here too. A missing Ruby prints `SKIP yaml` and the test still exits 0, with the skip named on the last line.
- Rule 22 ruling: does `release-diff` read the working tree? -> No, the committed files at the tag and at HEAD (in `deferred:`).
- Rule 2: `test-install-start.sh` row 5 keeps its two sample classes, as the spec says ("keeps its checks"); they are a copy of the `bridge-refs` samples of `test-class-rules.sh`, so that row 5 still checks its own scanner when run alone. `bridge_refs` itself moved to `lib-scan.sh` and is not copied.
- Not addressed, because it can't be measured before the first real run (inference until QA reads it): `RUNNER_NAME`'s format (the recipe reads a trailing `-<n>` and falls back to the first free port); `docker compose`, `dash`, `ruby` and the sha256 tool on `ubuntu-24.04`; the runs API's filters (`ci/changes.sh` filters `conclusion` and `event` again).

Review pass, October 19 (patches the implement stage applied itself after the review layers reported). Rule 22 rulings made alone:

- Rule 22 ruling: does `release-diff` also pin each slot to its property? -> Yes. Besides the line subsequence, every old triple of data element, slot line and the property line below it must still exist at HEAD, because a slot put before an existing one keeps every old line in order while it moves the old property to a new number (rejected: the subsequence alone, as AD-5 words it, which lets old rows read the wrong property without a red). Spine update for the lead: AD-5's check also requires that each slot keeps its number and property.
- Rule 22 ruling: which tag is the previous release when a pre-release exists? -> `versionsort.suffix=-` sorts `v1.0.0-rc1` before `v1.0.0`, so `v1.0.0` is the previous release once it exists (rejected: git's default order, which puts a release candidate after its release and checks a later tree against it).
- Rule 22 ruling: how does `ci/iris.sh teardown` match a tag? -> By the project name shape `ocutalon-<label>-<tag>-<epoch>-<pid>` with a 10-digit epoch, followed by nothing or by `-`, `_` or `:` and a suffix. A tag that extends or equals part of another run's tag, a slot, a name outside `ocutalon-` and the preloaded base image never match. A tag must not end another run's tag (rejected: the substring `-<tag>-`, which a tag such as `iris` matches in the base image's name).
- Rule 22 ruling: which key shapes does CON-5's scan cover? -> Also GitHub fine-grained tokens (`github_pat_`) and DigitalOcean tokens (`dop_v1_`), each with a bad sample (rejected: the four shapes of Story 0.1, which miss the token kinds this project's own tooling uses). VETO WINDOW (security posture, a stricter scan).
- Rule 22 ruling: how is `ci/iris.sh` tested without a Docker stack? -> It returns when sourced, finds its root through `BASH_SOURCE`, and `test-ci-config.sh` sources it with stubs for `dc` and `docker` to judge `run_class` and `teardown` (Rule 2: no copy of either function).
- `test-install-upgrade.sh` counted its compose files to decide whether to drop its previous build context, which was three before `ci/compose.ci.yml` joined `LIVE_FILES`; it now tracks the context file by a flag and checks that the base files, the CI override included, stay.
- `live_cleanup` runs `dc down` only when the compose file list exists, so an exit between the lock claim and the file list still releases the lock.
- `test-ci-config.sh` gained: secrets and `github.token` are looked for in run blocks, in any case and with a bracket; a missing or block-style matrix fails; the teardown step must come after the steps that run `ci/iris.sh`; `.yaml` files count as workflow files; the `lane-a` control is a file that exists with another job; the `wiring` rule (step ids, `if:` gates, run commands and the iris job's tag, image and deadline); and hermetic tests of `ci/checks.sh`, `run_class` and `teardown`.
- Not changed, with the reason in the Review Triage Log: the web job's lint and unit tests rely on the in-place build's `npm ci` (a fallback to the copy leaves them red, never green); a skipped assertion counts as passed (Story 0.6's `$$$AssertSkipped`, printed as a `SKIP` line); the throwaway lock has no queue or stale takeover (the content names `acquired_at`, and exit 75 is the documented retry).

## Review Triage Log

### 2026-10-19 - Review pass 1
- verdicts: 52 findings (blind-hunter 11, edge-case-hunter 28, verification-gap 13; the intent-alignment auditor reported readings, no finding) - high 0, medium 19, low 30, false 2, maybe-false 1
- intent-alignment: no divergence between the intent and the diff beyond what the spec labels `(inference)` (the GitHub runtime and the x64 runner, read on the first real run) and the recipe behaviour that the verification-gap findings below pinned.
- findings:
  - `[medium]` `[patch]` teardown matches `-<tag>-` as a substring, so a tag such as `iris` or `shard` removes other runs' resources and untags the preloaded base image (BH1) - anchored to the project name shape; `test-ci-config.sh` `teardown` runs it against a stub
  - `[low]` `[reject]` the throwaway lock can starve a waiter because each unit of `group` re-claims it at once (BH2) - the lock exists only where the coordination folder does; `group` and `all` are conveniences; exit 75 is the documented retry; a fair queue is more than a correction
  - `[medium]` `[patch]` `release-diff` passes a slot put before an existing one (BH3) - slot triples must survive; sample `inserted-slot`
  - `[medium]` `[patch]` the previous tag sorts a pre-release after its release (BH4) - `versionsort.suffix=-`; sample `prerelease`
  - `[low]` `[patch]` `ai-allowlist` misses the table form `%AI_...` (BH5) - the regex lets `_` follow `%AI`; sample `ai_bad4`
  - `[low]` `[reject]` the yaml rule skips when Ruby is missing and `ci/checks.sh` shows the block as passed (BH6, VG6 part) - the hosted image ships Ruby, GitHub parses the workflow files itself, and the last line of the block says `skipped: yaml`
  - `[low]` `[reject]` a skipped assertion counts as passed and has no count (BH7) - Story 0.6's `$$$AssertSkipped` is intended, and each skip prints a `SKIP` line
  - `[low]` `[patch]` the spec's `image` timing (159 s) disagrees with Rule 21 (150 s) (BH8) - the spec now names both runs
  - `[low]` `[patch]` `key_like` misses `github_pat_` and `dop_v1_` tokens (BH9) - two alternatives and samples
  - `[medium]` `[defer]` the public-package check ignores embedded SQL, query bodies, private globals and macros (BH10, EC26) - the blind spot predates this story and is outside the spec's scope; in `deferred:`
  - `[low]` `[reject]` the web job's lint and tests depend on the in-place build's `npm ci` (BH11) - a fallback to the copy leaves them red (`tsc: not found`), never green, and the build step's output names the mode
  - `[low]` `[patch]` `git diff --name-only` quotes a non-ASCII path, so a web path with an accent skips the web job (EC1) - `core.quotePath=false`; case in `test-ci-changes.sh`
  - `[low]` `[reject]` a test class that inherits all its `Test` methods has no `Method Test` line and never runs (EC2) - the spec defines a test class by that line
  - `[low]` `[reject]` a hanging test class stalls until the job timeout (EC3) - classes take under 2 s, `timeout-minutes` bounds the job, and no portable `timeout` exists on the developer machine
  - `[medium]` `[patch]` same root cause as BH1 (EC4)
  - `[low]` `[patch]` `printf '%.2f'` rejects IRIS's decimal point under a comma locale (EC5) - the line runs in the C locale
  - `[medium]` `[patch]` an exit between the lock claim and the compose file list leaves the lock held (EC6) - `live_cleanup` skips `dc down` without files; test `a cleanup before the compose files exist`
  - `[low]` `[reject]` a non-numeric `OCUTALON_LIVE_DEADLINE` aborts `live_start` (EC7) - CI sets 1200 and a developer sets a number; the cleanup now releases the lock anyway (EC6)
  - `[low]` `[reject]` no age check on a stale lock (EC8) - Rule 12 lets the orchestrator sweep it, and the busy line names `acquired_at`
  - `[low]` `[reject]` a quoted or absolute `worktree_base` is not read (EC9) - the file has `.worktrees` unquoted; Rule 12's folder is relative to the main checkout
  - `[low]` `[reject]` `OCUTALON_LOCK_SLEEP_MAX` below `MIN` is a division by zero (EC10) - test seams only, never set by a caller
  - `[maybe-false]` `[reject]` `docker image rm -f <id>` untags another job's image of the same id (EC11) - the line predates this story; what would settle it: two concurrent builds of one context on the runner giving one image id, and the second job's recreate failing
  - `[low]` `[patch]` `scan_files` skips a file with a non-ASCII name because git quotes it (EC12) - `core.quotePath=false`; test `scan_files`
  - `[low]` `[reject]` `bridge_refs` matches the package name in one case only (EC13) - moved verbatim from Story 0.6; a lower-case reference is not used anywhere
  - `[low]` `[reject]` `grep -I` skips a file with invalid UTF-8 (EC14) - measured: BSD grep also skips it in the C locale, so a locale prefix does not help, and no such file exists
  - `[low]` `[reject]` `docker buildx build --output type=tar` is not a risky call (EC15) - the spec lists `push`, `login`, `save`, `export` and `--cache-to`
  - `[medium]` `[patch]` a `secrets.` reference inside a run block, or written `Secrets['K']`, is not flagged (EC16) - the check runs before the run-block shortcut and in any case; samples `secret-block`, `secret-bracket`, `token-block`
  - `[medium]` `[patch]` a missing or block-style matrix lets a group drop out unseen (EC17, and the matrix part of VG6) - `ci.yml` needs a flow-list matrix equal to `ci/iris.sh groups`; samples `matrix-block`, `matrix-missing`
  - `[low]` `[patch]` the teardown step may come before the steps it cleans up (EC18) - it must come after; sample `teardown-early`
  - `[low]` `[patch]` a workflow saved as `.yaml` is not read (EC19) - both extensions
  - `[low]` `[reject]` `%AI` in a `.inc`, `.mac` or `.int` file is not scanned (EC20) - none exists below `src/`; a package is a path of classes
  - `[low]` `[reject]` an unchecked prepare reached through `$classmethod` with the name in a string (EC21) - dynamic dispatch is itself outside the public packages and unused in `src/`
  - `[medium]` `[patch]` `test-install-upgrade.sh` pops `ci/compose.ci.yml` at its first build context (EC22) - it counted three files, now four; a flag and a check
  - `[medium]` `[patch]` same root cause as BH4 (EC23): the pre-release sorts above its release
  - `[low]` `[reject]` `git status --short` that fails prints nothing, so the build runs in place (EC24) - the earlier `git ls-files` and the checkout step fail first
  - `[low]` `[reject]` same root cause as BH11 (EC25): lint and tests need the in-place build's `npm ci`
  - `[medium]` `[defer]` same root cause as BH10 (EC26's SQL half is the same blind spot)
  - `[false]` `[reject]` the removed fixed class list no longer requires `Status` and `ApiBase` (EC27) - `>= 6` classes are required, so deleting either of the six is red
  - `[false]` `[reject]` a reader may think `build-inputs` ran with the CI override (EC28) - it builds an image and starts no stack, and the AC speaks of units that start one
  - `[medium]` `[patch]` `ci/checks.sh` has no executed test (VG1) - `test-ci-config.sh` runs a copy against stub scripts
  - `[medium]` `[patch]` the wiring of `ci.yml` (step ids, gates, run commands, run tag) is unpinned (VG2) - the `wiring` rule with nine samples
  - `[medium]` `[patch]` the verdict guards of `run_class` have no hermetic host (VG3) - `ci/iris.sh` is sourceable; eight cases
  - `[medium]` `[patch]` the selection of `teardown` is untested (VG4) - a stub `docker` with fixtures of other tags, a slot, an outside name and the base image
  - `[medium]` `[patch]` same root cause as BH1 (VG-other 1): the selection of `teardown` matches a substring
  - `[medium]` `[patch]` the API request and the token delivery of `ci/changes.sh` are untested (VG5) - a fake `curl` records its arguments and standard input
  - `[low]` `[patch]` the `lane-a` control reads a file that does not exist (VG6) - a file that exists with another job; the dead `rm` is gone
  - `[low]` `[patch]` the dead `rm -f` of the `lane-a` control (VG-other 3) - removed with the control
  - `[medium]` `[patch]` `release-diff` has no sample for a tag that HEAD does not hold (VG7) - sample `unmerged-tag`
  - `[medium]` `[patch]` the dictionary helpers of `Test.Web.Status` are never shown to flag (VG8) - `TestDefinitionScansFindWhatIsOutside` on definitions in memory
  - `[low]` `[patch]` `test-lib-live.sh` and `test-ci-changes.sh` inherit `OCUTALON_LIVE_DEADLINE` and `GITHUB_OUTPUT` (VG9) - unset in the probe; a leak check
  - `[low]` `[patch]` the `.env` filter of `lib-scan.sh` has no executing test (VG10; the layer proposed `defer`) - test-boundaries `scan_files` lists a made-up repository
  - `[low]` `[reject]` `scan_rule` expands the file list unquoted (VG-other 2) - no tracked file has a space or a glob character, and the scanners are Story 0.1's pattern


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

**Results (implement stage, October 19).** Machine: the developer's Apple silicon Mac (ARM), Docker Desktop, warm layer cache, compose 5.5.0, bash 3.2. The runner is x64; its figures are `(inference)` until QA reads the first run. Run tag `v07a` throughout; every throwaway was torn down by its own trap, and `ci/iris.sh teardown` with the tag found nothing left (no container, volume, network or image of `-v07a-`).

*Task 0a, measured.*
- The package install compiles all 30 `OcuTalon.Test.*` classes (27 test cases, 3 helpers), so the shards load nothing. `^UnitTestRoot` matters: empty, `RunTest(":<Class>", "/noload/nodelete/norecursive")` logs "Finding directories ... Directory name ... is invalid" and runs nothing; set to `/tmp/` it runs the class from the namespace and leaves the class compiled. A line of an `iris session` can't hold a `$$$` macro.
- Results land in `^UnitTest.Result`, read through `%UnitTest.Result.TestInstance` (newest id), `TestSuite` named `(root)`, `TestCase` named by the class, `TestMethod` and `TestAssert`. A failing assertion gives `Status` 0 on the assertion, its method, the case and the suite; a skipped assertion gives 2 on the assertion and its method (the case is then 1 or 0 by the other methods); a passing one gives 1. A class that isn't compiled leaves a suite with status 0, no case, and the error "Compiled class ... does not exist"; the recipe checks `%Dictionary.CompiledClass` first. One class takes less than 1 s through its own session.
- Compose: `docker compose up -d --build --wait` with the CI override returned healthy after 56 s (the first start, image build included); `down -v --rmi local` removed the container, `<project>_durable`, `<project>_default` and the image `<project>-iris:latest`. A project is found by the label of its containers, and by name from its volumes, networks and images, all of which carry the project name.
- DW-11: `ExportUDL` of the compiled class is byte-identical to the committed file for all 53 classes with storage (not only the block). The control: `Decide` with its third slot removed, loaded and compiled, exports with the slot back (it differs from the copy); the original, loaded again, exports equal to its file.
- A `docker compose cp` prints the copied host path on its error stream; the scripts discard it.

*Task 0b, with the recipe.* All 27 classes passed in a fresh throwaway, forward and reversed, on the first run, so no test was changed and nothing went to `deferred:` for a product defect. DW-9's `Test.Install.Users` flake did not show in five runs.
- Time to a ready stack: 52 to 57 s. Per class, every class took under 0.4 s except `Install.Registry` 0.9 to 1.1 s, `Live.Publish` 1.3 s and `Contract.Checker` 1.6 to 1.9 s.
- Per shard (call start to teardown): `lane-a` 56 to 61 s, `lane-b` 62 to 65 s.
- Per live script: `compose-start` 80 s, `install-start` 151 s, `install-upgrade` 164 s, `production` 83 s, `production-restart` 87 s, `audit` 76 s, `sign-in` 68 s, `bundle-folder` 75 s, `storage-roundtrip` 57 to 81 s, `build-inputs` 4 s.
- Per group: `install` 315 s, `production` 246 s, `browser` 143 s, `shards` 126 s, `image` 150 s (980 s in all; a second run of the group took 159 s). Doubled for the runner (inference), the slowest group is about 11 minutes, below the 15-minute bound, so the groups were not rebalanced; about 33 runner-minutes over two runners (inference), about 17 minutes of wall-clock, with the hosted jobs in parallel. REL-4's 30 minutes holds on this estimate (inference).
- Linux tools: `bash ci/checks.sh` in a public `ubuntu:24.04` container (arm64, `docker run --rm`, with git 2.43.0, jq 1.7 and Ruby 3.2.3 added; mawk 1.3.4, GNU tools, bash 5.2): every script passed except four `docker compose config --quiet` checks of `test-compose-file.sh`, which need the Docker CLI that the container lacks (the spec allows leaving it out). The image was pulled once for this run; no IRIS image was used.
- Workflow files: both parse with `ruby -ryaml`. actionlint 1.7.12 (MIT, downloaded to the session's scratchpad with `gh release download`, never installed globally) reports nothing once the custom label `ocutalon` is configured in a config file kept in the scratchpad; without it, its only complaint is that label.
- Tools added: `@types/node` 24.19.1 (exact, MIT, `web/package.json`); nothing else.

*Commands run, all exit 0.* `bash docker/tests/test-boundaries.sh`, `test-storage.sh`, `test-class-rules.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-compose-file.sh`, `test-pinned-sources.sh`, `test-after-start.sh`, `test-healthcheck.sh` and `test-lib-live.sh`, one per call; `bash ci/checks.sh` (about 20 s, with `release-diff`'s line `PASS release-diff: no release tag yet`); the YAML parse; `npm --prefix web ci`, `run build`, `run lint`, `test` (41 tests); `ci/iris.sh build`, `shard lane-a`, `shard lane-b`, both again with `--reverse`, `class OcuTalon.Test.Install.Users`, `live` for all ten scripts, `group shards` and `group image`, `teardown`; `bash docker/tests/test-web-build.sh` in copy mode, and in place in a scratch repository with `GITHUB_ACTIONS=true` and a clean tree; the bootstrap in a detached worktree of the scratchpad (`git status --short` empty, `bootstrap_check` exit 0, the worktree removed and `git worktree list` as before); slot A (build 154, profile `ocutalon-slot-a`, namespace `OCUTALON`): `Status.cls` loaded with `compile: true`, then `iris_execute_tests` `OcuTalon.Test.Web.Status`: 6 passed, 0 failed.

*Mutation results (Rule 19; each applied, red observed, reverted; `git status --short` and `git diff --stat` identical after each).*
- AC1: mutation: `"triage"` -> `"triageX"` in `Test.Agent.Constants` -> `ci/iris.sh group shards` exit 1 with `CLASS OcuTalon.Test.Agent.Constants failed`, `UNIT shard:lane-a failed` and `GROUP shards failed: shard:lane-a`.
- AC1, skips: mutation: `ci/changes.sh` takes the second commit of `git rev-list HEAD` as its base -> `test-ci-changes.sh` red at "red then bookkeeping". Mutation: `NOT_BOOKKEEPING_PATTERN` matches nothing in `ci/units.sh` -> `test-ci-changes.sh` red at the DESIGN.md case.
- AC2: mutation: `OCUTALON_EVAL: "0"` in `ci/compose.ci.yml` -> `test-production-restart.sh` row 19 red ("the row is 1 and EvalIn answers CreateBusinessService"). Mutation: `ports:` in the override -> `test-compose-file.sh` red (two checks).
- AC3: mutation: `%Prepare("SELECT 1", 0)` in `Data/Setting.cls` -> `unchecked-prepare` red at `Setting.cls:50`. Mutation: `ForUser` renamed in the allow-list -> red at `Session.cls:50` and at the stale entry. Mutation: `##class(%AI.Agent)` in `Watch/Ops.cls` -> `ai-allowlist` red at `Ops.cls:11`. Mutation: `$Get(^OcuTalonPublic("ready"))` in `Web/Public/Status.cls` -> `public-global` red at `Status.cls:51`. Mutation: `is_subsequence` always true in `test-storage.sh` -> `release-diff` red for the changed value, the removed slot and the version-sorted tag. Mutation: a scratch `ci/` file with a docker save -> `docker calls` red at `ci/<file>:1`. Mutation: a home path with a name in a scratch file -> `paths` red at its line. Mutation: a class `OcuTalon.Web.Public.ZzMutant`, a copy of `Status` that extends `OcuTalon.Data.Setting`, loaded on slot A -> `Test.Web.Status` red at "extends and types its members with nothing outside the allow-list" (the class is covered because the list is read from the dictionary); deleted again, the test is green. Mutation: the slot removal of the control disabled in `test-storage-roundtrip.sh` -> red "the mutation did not change the copy of Decide".
- AC4: mutation: `lane-a.yml` moved away -> `test-ci-config.sh` `lane-a` red.
- AC5: mutation: the fork guard removed from `iris` -> `fork-guard` red at `ci.yml:82`. Mutation: an `actions/cache` step added -> `image-actions` red.
- AC6: mutation: `cancel-in-progress: true` -> `concurrency` red. Mutation: `OCT-epic*` dropped -> `triggers` red. Mutation: `/irislib` dropped from `.gitignore` -> the bootstrap worktree's `git status --short` shows `?? irislib` and `bootstrap_check` exits 1. Mutation: the cleanup deletes any lock -> `test-lib-live.sh` red at "a lock that another run holds is kept"; mutation: no `set -C` in the claim -> red at the exit 75 and the takeover; mutation: `exit 1` for `exit 75` -> red. Mutation: the run tag dropped from `P`, and the deadline override ignored -> `test-lib-live.sh` red. Mutation: the web port base 52800 in `ci/iris.sh` -> `test-ci-config.sh` `recipe` red. Mutation: an unlisted `docker/tests/test-<x>.sh` -> `units` red.
- DW-11: mutation: the third slot removed from `Decide`'s committed block -> `test-storage-roundtrip.sh` red, naming `OcuTalon.Bridge.Process.Decide`.
- DW-17: see AC3.
- Web lint: mutation: a type error in `playwright.config.ts` -> `npm --prefix web run lint` exit 2 (TS2322); mutation: a syntax error in `web/scripts/tokens.mjs` -> exit 1 (`node --check`).
- `ci/checks.sh`: mutation: an unknown name in `CHECK_SCRIPTS` -> that block fails, the other scripts still run, and the last line names the failed scripts.

*Review patches (Rule 19; each applied, red observed, reverted; `git status --short` and `git diff --stat` identical after each).*
- AC1, `ci/checks.sh`: mutation: `exit 1` -> `exit 0` at its end -> `test-ci-config.sh` `checks.sh` red.
- AC1, `ci/iris.sh run_class`: mutation: the `ran no test` guard made unreachable -> `class verdict` red at "a class that ran no test"; mutation: the `compiled` guard made unreachable -> `class verdict` red at "a class that is not compiled" and "a session that printed nothing".
- AC1, `ci/iris.sh teardown`: mutation: the pattern back to the substring `-<tag>-` -> `test-ci-config.sh` `teardown` red (it removes another tag's, a slot's and an outside project); mutation: `grep -v slot` dropped -> `teardown` red.
- AC1, skips: mutation: `core.quotePath=false` dropped from `ci/changes.sh` -> `test-ci-changes.sh` red at "a web path with a non-ASCII name" and at the API case; mutation: the runs URL changed -> red at "API: the runs of this workflow"; mutation: the token on curl's command line -> red at "API: the token goes to curl on its standard input"; mutation: `GITHUB_OUTPUT=""` dropped from the API-failure runs -> red at "the runs that name no output file of their own".
- AC1, install-upgrade: mutation: `use_image_context` counting files (`-gt 3`) again -> `ci/iris.sh live install-upgrade` stops with "the compose files after a build context are not the base files plus that context".
- AC3, `release-diff`: mutation: the slot-triple check removed -> `test-storage.sh` red at "a slot put before an existing one is not flagged"; mutation: `--merged HEAD` removed -> red at "a tag on an unmerged branch"; mutation: `versionsort.suffix=-` removed -> red at "a pre-release tag".
- AC3, `ai-allowlist`: mutation: `_` excluded again after `%AI` -> `test-class-rules.sh` red at the `%AI_Agent.Session` sample.
- AC3, paths and keys: mutation: the `.env` filter of `scan_files` removed -> `test-boundaries.sh` red at "scan_files"; mutation: `core.quotePath=false` removed from `scan_files` -> red at "scan_files"; mutation: the `dop_v1_` alternative removed -> red at "sample 4"; mutation: the `github_pat_` alternative removed -> red at "sample 3".
- AC3, `Test.Web.Status` (slot A, build 154): mutation: the `CodeMode` filter of `GeneratorTextOf` removed -> `TestDefinitionScansFindWhatIsOutside` red at "the text of a plain method is not"; mutation: the property type check emptied in `DefinitionOutside` -> the same test red at "a superclass, a property type, a return type and an argument type outside the list are found". The original reloaded: 7 of 7 pass.
- AC5/AC6, `test-ci-config.sh`: mutation: the secrets check skipped in run blocks -> `secrets` red at `secret-block`; mutation: `secrets.` only, without a bracket -> red at `secret-bracket`; mutation: the matrix required only when present -> `matrix` red at `matrix-missing`; mutation: the teardown allowed at any position -> `teardown` red at `teardown-early`; mutation: the lint `need(...)` line removed -> `wiring` red at the `lint` sample; mutation: `.yaml` dropped from the listing -> `workflow files` red; mutation: `has_job` ignoring the job name -> `lane-a` red.
- AC6, `lib-live.sh`: mutation: `dc down` always run in `live_cleanup` -> `test-lib-live.sh` red at "a cleanup before the compose files exist"; mutation: `OCUTALON_LIVE_DEADLINE` left in the probe's environment, with `OCUTALON_LIVE_DEADLINE=1200` exported -> red at "the deadline is 540 s by default".

*Re-run after the review patches (all exit 0).* `bash ci/checks.sh`; the YAML parse; `npm --prefix web ci`, `run build`, `run lint`, `test`; `ci/iris.sh build`, `shard lane-a`, `shard lane-b`, `live storage-roundtrip`, `live production-restart`, `teardown`; slot A `Test.Web.Status`: 7 of 7. The `(once)` lines ran again after the last patch (see the Auto Run Result).

## Auto Run Result

Status: done
Blocking condition: none

**Implement and review (October 19).**
- **Summary.**
  - Both workflow files, the recipe, the shared test shell, the new and extended checks, the web lint and tests, the pipeline configuration and Rule 21's recipe are implemented as specified. The model mock stays out (Story 0.11); `web` holds the named empty step "Mock tests: none until Story 0.11".
  - The story was kept whole. No intent gap, no AD conflict, no NFR tripwire.
  - Task 0a and 0b were measured first; the results, the Rule 22 rulings and every mutation are under Verification and the Spec Change Log. Everything that only a hosted runner or the self-hosted runner can show stays `(inference)` for QA.
- **Files changed.**
  - `.github/workflows/ci.yml`, `.github/workflows/lane-a.yml`: the `checks`, `web` and `iris` jobs, and the empty `standalone-bridge` job.
  - `ci/iris.sh`, `ci/units.sh`, `ci/changes.sh`, `ci/checks.sh`, `ci/compose.ci.yml`: the IRIS recipe, its lists, the classifier and base, the checks runner and the CI override.
  - `docker/tests/lib-live.sh`: run tag in project names, deadline override, CI override in the file list, the throwaway lock, and a cleanup that releases the lock even before the file list exists.
  - `docker/tests/lib-scan.sh`: `scan_rule`, `scan_files` and `bridge_refs`, shared by the scanners.
  - `docker/tests/test-ci-config.sh`, `test-ci-changes.sh`, `test-class-rules.sh`, `test-storage-roundtrip.sh`: new scripts (workflow rules and hermetic tests of the recipe; the classifier; the class rules; DW-11's round trip).
  - `docker/tests/test-boundaries.sh`, `test-storage.sh`, `test-compose-file.sh`, `test-install-start.sh`, `test-install-upgrade.sh`, `test-lib-live.sh`, `test-production-restart.sh`, `test-web-build.sh`, `test-build-inputs.sh`: extended scopes and rules (paths, keys and docker calls; `release-diff`; the CI override; the run tag; the lock; the in-place web build; the `OCUTALON_EVAL` pass-through).
  - `src/ocutalon/cls/OcuTalon/Test/Web/Status.cls`: the public-package scan covers every class of both packages, read from the dictionary, with superclass, type and `$SYSTEM.Encryption` checks and in-memory samples.
  - `web/package.json`, `web/package-lock.json`, `web/tsconfig.e2e.json`: `@types/node` 24.19.1, the `lint` and `test` scripts and the e2e type-check configuration.
  - `.gitignore`, `_bmad/custom/parallel.yaml`, `_bmad/custom/skill-rules.md` (Rule 21's last bullet only): the anchored reference-folder patterns, the bootstrap and the throwaway lock, and the recipe with its timings.
- **Review (one pass, four layers).**
  - 52 findings: 29 patched (17 medium, 12 low), 2 deferred (the same public-package blind spot twice, one `deferred:` item beside the implement stage's two), 21 rejected (each with its reason in the Review Triage Log). No intent gap and no bad spec.
  - The patches are mostly tests that pin behaviour the first pass left unpinned (`ci/checks.sh`, `run_class`, `teardown`, the runs API request, the workflow wiring, `release-diff`'s tag choice and slot check, the early cleanup), plus these corrections: `teardown` matches a tag by the project name shape, not as a substring; `test-install-upgrade.sh` no longer drops the CI override; a pre-release tag sorts before its release; a slot put before an existing one fails `release-diff`; a non-ASCII path name is read as it is; secrets in run blocks are flagged.
- **Follow-up review recommended: true.** Seventeen medium findings were patched, and most of the patch is new test code in `test-ci-config.sh` (the `wiring`, `checks.sh`, class-verdict and teardown cases, which source `ci/iris.sh` with stubs) and in `test-storage.sh` (`release-diff`'s slot check). They were run under bash 3.2 on the developer machine and under bash 5.2 and mawk in a public ubuntu container, but not on the hosted runner. The unverified risk is a layout or portability difference there (awk, `git` sort options, `curl -K -`) that the first real run of `ci.yml` shows.
- **Verification performed.** Every `(loop)` and `(once)` line of Verification ran after the last patch and exited 0: `bash ci/checks.sh` (about 20 s; `release-diff` prints its no-op line), the YAML parse, `npm ci`, `build`, `lint` and `test` (41 tests), `ci/iris.sh build`, both shards forward and reversed (27 classes), `class OcuTalon.Test.Install.Users`, all ten live scripts, `teardown` (nothing left of tag `v07a`), the bootstrap in a detached worktree of the scratchpad (clean, `bootstrap_check` 0, the worktree removed), and slot A's `Test.Web.Status` (7 of 7, build 154). `bash ci/checks.sh` also ran in a public `ubuntu:24.04` container (git 2.43.0, mawk 1.3.4, bash 5.2): every script passed except the four `docker compose config --quiet` checks of `test-compose-file.sh`, which need the Docker CLI that the container lacks.
- **Residual risks.**
  - All `(inference)` items stay for QA: the GitHub runtime (fork pull requests, the runs API filters, `RUNNER_NAME`'s format, the tools on `ubuntu-24.04`), the x64 timings and REL-4's 30 minutes, and two jobs on one host.
  - The owner-only items (the one-run CI gate in `/epic-cycle`, repository settings), the VETO WINDOW items and the spine updates are listed under Design Notes and the Spec Change Log for the lead.
  - The handoff subagent ran `docker compose ... config --format json | jq` once without `--quiet` to read the `OCUTALON_EVAL` pass-through; only one `environment` value reached its output and `.env` was not read, so no secret was shown. It pulled the public `ubuntu:24.04` image once and ran `npx playwright install chromium`. No IRIS image was pulled or pushed.
  - Nothing was pushed or committed before finalize.

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
