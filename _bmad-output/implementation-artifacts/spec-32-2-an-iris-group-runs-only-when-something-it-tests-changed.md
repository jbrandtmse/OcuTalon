---
title: 'Story 32.2: An IRIS group runs only when something it tests changed'
type: 'chore'
created: '2026-10-21'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Today `ci/changes.sh` gives the `iris` matrix one flag for all six groups: it is true whenever any path outside the pipeline's bookkeeping changed. So a push that changes only docs, Lane A's workflow, one live script or only the web sources still runs every IRIS group, about 45 runner-minutes, although most of them cannot be affected.

**Approach:**
- `ci/units.sh` declares an input pattern for each IRIS group. Each pattern is made of three parts:
  - the inputs every unit builds from;
  - the scripts of the group's own units;
  - the web bundle's inputs, unless every unit of the group is measured not to check the bundle.
- `ci/changes.sh --group <name>` decides each group against AD-22's base. Each `iris` job gates its own steps on its group's decision.
- Every uncertain case runs every group: a pull request, a push to `main`, a force push, a payload, base or diff that cannot be read, and a changed path that no pattern claims and no declaration excludes.

## Boundaries & Constraints

**Always:**
- **One base for every group.** It is AD-22's base, found as `ci/changes.sh` finds it today: the newest commit of HEAD's history whose push run of `ci.yml` concluded `success`, on any branch, or HEAD itself on a re-run of a green run.
- **Every group runs in full** in each of these cases:
  - any event that is not a push, such as a pull request;
  - a push to `main`;
  - a force push: the payload says `forced: true`, or its `before` is not an ancestor of HEAD, or `before` is unknown here;
  - a push whose event payload cannot be read;
  - no green ancestor;
  - any error from the runs API, the base or the diff;
  - a changed path that no group's pattern matches and that is neither bookkeeping nor in `NOT_IRIS_INPUT_PATTERN` (an unclassified path).
- **Inputs of every group:** `ci/`, `.github/workflows/ci.yml`, the whole of `src/`, and the image, compose and throwaway inputs.
- **The demo path's group (`browser`)** has every product source path as input (REL-2).
- **A skipped group's job still starts.** It runs `What changed` and skips `Build the web bundle` and `Run the group`. Its `Skipped` step prints `no input changed since <full base sha>`. It runs `Tear down` and concludes `success`. There is no workflow-level or job-level skip.
- **Outputs.** An output that `ci/changes.sh` cannot write fails the script (exit 1). `web=` and the `web` job's gates behave as before.
- **Protections from Story 32.1 keep holding.** No `docker push` and no registry sign-in. No cache or upload of the base image. A fork's pull request never reaches the IRIS runner. No `docker compose config` without `--quiet`, and no `docker inspect` without `--format`.
- **Script rules.** Scripts and the workflow are ASCII only (test-boundaries). They need only bash 3.2, git, jq, curl, and grep and awk in both their BSD and GNU forms. No new dependency.

**Never:**
- **Lane A's paths and planning files.** Never edit any of these:
  - `.github/workflows/lane-a.yml`, `ci/mock/scenarios/A/**`, `release/**`, `docker/merge.cpf`, `docs/**`, `src/bridge/**`, `src/cpf/**`, `eval/**`, or a Lane A package;
  - `_bmad/**`, the architecture spine or `.claude/**`.

  Patterns may name these paths as inputs.
- **`ci/units.sh` outside the new pattern entries.** Leave every existing entry as it is: `CHECK_SCRIPTS`, `WEB_SCRIPTS`, `SHARDS`, `shard_areas`, `IRIS_GROUPS`, `group_units`, `BROWSER_UNITS`, `WEB_INPUT_PATTERN`, `BOOKKEEPING_PATTERN` and `NOT_BOOKKEEPING_PATTERN`.
- **Files and settings that stay as they are.** Do not change:
  - `ci/iris.sh`, `docker/tests/lib-live.sh` or any live script;
  - the matrix, `runs-on`, `timeout-minutes`, the run tag or the triggers.

  Do not add `paths`, `paths-ignore`, or a job-level `if` that skips a job. Do not give `lane-a.yml` per-group skips.
- **No push, no CI trigger, no runtime.** Do not push, run `gh workflow run` or re-run a job. Do not use a dev slot or any IRIS instance. Do not start a throwaway: none is needed.

## I/O & Edge-Case Matrix

`ci/changes.sh ci.yml --group <g>` on a push with a green base, unless the row says otherwise. "Runs" means `run=true`. "Skips" means `run=false` and `reason=no input changed since <base sha>`.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Web-only change | Only paths under `web/`, `logo/` or `_bmad-output/planning-artifacts/ux-designs/` changed | `install-fresh`, `install-upgrade`, `browser`, `shards` and `image` run; `production` skips; `web=true` | No error expected |
| `ci/` or the workflow | `ci/units.sh`, `ci/changes.sh`, `ci/mock/scenarios/A/x.json` or `.github/workflows/ci.yml` changed | All six run, and their reasons name the input paths (not the fallback) | No error expected |
| Product source | One of: `src/bridge/...`, `src/cpf/...`, `src/module.xml`, `docker/Dockerfile`, `docker/merge.cpf`, `docker/after-start.cos`, `docker/ipm/...`, `docker-compose.yml`, `docker-compose.dev.yml`, `.dockerignore`, `eval/...`, `docker/tests/lib-live.sh`, `docker/tests/compose.throwaway.yml` or `.gitattributes` | All six run (`browser` among them), each claimed by its pattern, not by the fallback | No error expected |
| One live script | `docker/tests/test-<unit>.sh` of a live unit of group `g` | Only `g` runs | No error expected |
| Declared non-input only | `docs/x.md`, `release/x.sh`, `README.md`, `CLAUDE.md`, `.claude/...`, `.github/workflows/lane-a.yml`, `.env.example`, `docker/tests/record-eval.sh`, or a check or web script (`docker/tests/test-boundaries.sh`, `test-web-build.sh`) | No group runs; `web` follows `WEB_INPUT_PATTERN` as before | No error expected |
| Bookkeeping only | Paths under `_bmad/` or `_bmad-output/` (outside ux-designs) | No group runs | No error expected |
| Unclassified path | `newdir/x.txt`, `install.sh`, `docker/other/x.sh` or `docker/tests/helper.sh` | All six run; each reason names the unclassified path | Fails toward running |
| Red, then bookkeeping | C0 green; C1 changes `docker/tests/test-production.sh` and its run is red; B1 is bookkeeping only | The base is C0; `production` runs; the other five skip | A red run is never a base |
| Re-run of a green HEAD | HEAD's own push run is green | `base` is HEAD; nothing changed; all six skip | No error expected |
| No base | A pull request, a push to `main`, no green ancestor, a runs API error, an answer that cannot be read | `base=` is empty; all six run; the reason names why | Fails toward running |
| Force push | The payload says `forced: true`; or `before` is not an ancestor of HEAD; or `before` is unknown | `base=` is empty; all six run; the reason names the force push | Fails toward running |
| Payload not readable | `GITHUB_EVENT_PATH` is unset or missing; the file is not JSON; or `forced` is not a boolean | `base=` is empty; all six run | Fails toward running |
| Changes not readable | `--paths-from` names a file that cannot be read (the test case). The existing, unchanged `git diff` failure branch (`ci/changes.sh` L95-97) ends the same way | `base=` is empty; all six run | Fails toward running |
| Outputs | `--group g`, and in a second call no `--group` | With `--group`, the outputs are `base`, `web`, `run` and `reason`; without it, `base`, `web` and `reason`. Both append them to `GITHUB_OUTPUT` and print one `GROUP <name> run=<true\|false>: <reason>` line per group, in matrix order | An output that cannot be written: `FAIL ci/changes.sh: cannot append to GITHUB_OUTPUT`, exit 1 |
| Bad group | `--group nosuch`, or `--group` with no value | Usage or `unknown group` line; nothing appended | exit 2 |
| The real skip (CI) | An `iris` job whose group's `run` is `false` | `Build the web bundle` and `Run the group` are skipped; `Skipped` prints `iris <g> skipped: no input changed since <sha>`; the job concludes `success` | An empty `run` output runs the group (`!= 'false'`) |

</intent-contract>

## Code Map

- `ci/units.sh`
  - L5-21: check scripts, web scripts and shards. Do not change.
  - L23-38: `IRIS_GROUPS` (L24) and `group_units` (L28-38). Read them, do not change them.
  - L40-41: `BROWSER_UNITS`, bare live names. This is the precedent for a per-unit list.
  - L43-49: `WEB_INPUT_PATTERN`. It must stay one single-quoted line, because `ci/mock/test/constants.test.mjs` L54-55 parses it with `/^WEB_INPUT_PATTERN='([^']*)'$/m`.
  - L51-53: `BOOKKEEPING_PATTERN` and `NOT_BOOKKEEPING_PATTERN`. Reuse them.
  - The new block goes after L53.
- `ci/changes.sh`
  - L1-15: the header contract. Rewrite it for the new outputs and fallbacks.
  - L22-37: argument parsing (`--paths-from`). Add `--group`.
  - L42-55: `emit` and `everything`. Extend both. Keep the rule that an output that cannot be written is a failure (L46-50).
  - L57-63: the event and `main` checks. The payload check goes right after them.
  - L65-90: the runs API and the base. Unchanged.
  - L92-98: the paths. Unchanged; `--paths-from` is the test seam.
  - L100-110: the per-path loop. Replace the `iris` flag with the per-group decision; `web` stays as it is.
- `.github/workflows/ci.yml`
  - L1-5: the header comment.
  - L84-124: the `iris` job; change L107 and L111-121.
  - L51-82: the `web` job. Unchanged.
- `docker/tests/test-ci-changes.sh`
  - L1-15: the header.
  - L52-57 `runs`, L59-85 `classify` and `expect`: the harness to extend.
  - L87-125: classifier cases. L117 (`docs/.gitignore`), L120 (`lane-a.yml`) and L121 (`docs/guide.md`) now run no group. The other `iris true` expectations become per-group sets.
  - L127-204: the base, red-then-bookkeeping and `main` cases.
  - L206-214: the output-count check (4 lines).
  - L216-237 and L274-290: calls without a payload. They must now get a valid payload, or they would pass for the payload reason instead of the one they test.
  - L246-256: the output file that cannot be written.
  - L258-262: a non-ASCII web path.
- `docker/tests/test-ci-config.sh`
  - L2-40: the header list of rules (the wiring bullet is L18-20).
  - L446-556: the `wiring` rule:
    - L491-492: the gate strings;
    - L502-505: the iris checks;
    - L524-536: the bad samples and their loop.
  - L561-566: `real_hits`.
  - L679-772: the `demo-path` rule. This is the pattern to follow: a `*_violations <tree>` function, `mk*` samples, one wanted message per bad sample, and `real_hits` on the real tree. Its `e2e_run` trick (L681-683) keeps the file from matching its own rule.
  - L773-880: the `groups` rule. The new `inputs` rule goes between L880 and L881, before the test-classes section.
- Read-only facts (do not edit):
  - `docker/tests/lib-live.sh` L53-84: `live_start` and the compose files of every unit.
  - `lib-live.sh` L155-183: `ensure_web_bundle`.
  - `lib-live.sh` L577: `STEP Web OK` in every unit's expected log.
  - `ci/iris.sh` L332-360: `cmd_group` calls `ensure_web_bundle`.
  - `docker/Dockerfile` L11-19 and `src/module.xml` L11: the `FileCopy` of `ocutalon/csp/`.
  - `docker/tests/test-boundaries.sh` L11-14 and L33-37: it scans every tracked file, this spec included, for local machine paths.
  - `docker/tests/test-demo-path-gate.sh` L51: it copies `ci/units.sh` into a scratch tree.

## Tasks & Acceptance

**Execution:**

`ci/units.sh`: after L53, add the block below. Each comment states its contract; the facts come from Design Notes "Task 0".

```bash
IRIS_INPUT='src/|docker/[^/]+$|docker/ipm/|docker/tests/lib-[^/]+\.sh$|docker/tests/compose\.[^/]+\.yml$|docker-compose[^/]*\.yml$|\.dockerignore$|eval/|ci/|\.github/workflows/ci\.yml$|\.gitattributes$|\.gitignore$'
WEB_BUNDLE_INPUT='web/|logo/|_bmad-output/planning-artifacts/ux-designs/'
NO_WEB_BUNDLE_UNITS="live:audit live:production live:production-restart live:storage-roundtrip"
NOT_IRIS_INPUT_PATTERN='^(\.claude/|[^/]+\.md$|LICENSE[^/]*$|NOTICE[^/]*$|docs/|release/|\.github/workflows/lane-a\.yml$|\.env\.example$|docker/tests/record-eval\.sh$|docker/tests/test-[^/]+\.sh$)'
```

- `IRIS_INPUT` holds unanchored alternatives: the inputs that every IRIS unit builds from or runs.
- `NO_WEB_BUNDLE_UNITS` lists unit ids whose checks never read, compare or serve the built web bundle.
- Add `group_input_pattern <group>`. It prints `^(<IRIS_INPUT>[|<WEB_BUNDLE_INPUT>]|docker/tests/test-<name>\.sh$...)`:
  - one `docker/tests/test-<name>\.sh$` per `live:<name>` unit of `group_units <group>`;
  - `WEB_BUNDLE_INPUT` unless every unit of the group is in `NO_WEB_BUNDLE_UNITS`. A new unit is therefore treated as checking the bundle.
  - It returns 1 for an unknown group.
- The comments say three more things:
  - a story that adds a unit, or gives one a new input, declares that input here;
  - a path that no pattern claims runs every group (`ci/changes.sh`);
  - a unit or test class that starts checking the bundle leaves `NO_WEB_BUNDLE_UNITS`.

Rationale: the patterns are the AC's declaration, and they move with a unit (Story 32.3).

`ci/changes.sh`: change the script as follows. Rationale: these are the AC's per-group decision and its fallbacks, which also protect the `web` job.

- **Arguments.**
  - Accept `--group <name>`.
  - With no value, print the usage line and exit 2.
  - For an unknown group, print `unknown group '<x>'; groups: <IRIS_GROUPS>` and exit 2.
  - Do both before anything is emitted.
- **Payload check.** For a push that is not to `main`, read `$GITHUB_EVENT_PATH` with jq. Each of these runs everything:
  - the payload is unset, cannot be read or is not JSON;
  - `.forced` is not a boolean;
  - `.forced` is true;
  - `.before` is not 40 hex characters;
  - `.before` is not 40 zeros (which mark a new ref) and `git merge-base --is-ancestor <before> HEAD` exits other than 0 (1: not an ancestor; 128: unknown).
  Each reason says which case it was.
- **Per-group decision.** After the paths are known, run one `grep -E "$(group_input_pattern g)"` per group over the paths file.
  - A grep that exits 2 or higher runs everything ("the input pattern of <g> could not be applied").
  - Find the unclaimed paths with awk, not `grep -vxF -f`, which behaves differently on BSD when the pattern file is empty.
  - An unclaimed path that is neither bookkeeping (`BOOKKEEPING_PATTERN` and not `NOT_BOOKKEEPING_PATTERN`) nor in `NOT_IRIS_INPUT_PATTERN` is unclassified. It makes every group run.
  - `web` is computed as before.
- **Outputs.**
  - Print and append `base`, `web` and `reason`, plus `run` when `--group` is given. The `iris` output is removed.
  - Print one `GROUP <g> run=<true|false>: <reason>` line per group of `IRIS_GROUPS`, to stdout only.
- **Group reasons.**
  - A skip: `no input changed since <40-hex base>`.
  - A run: `<k> input path(s) of <g> changed since <base>`.
  - An unclassified path: `<u> unclassified path(s) changed since <base>, the first <path>: every group runs`. When there is one, this reason replaces every group's own reason.
  - No base: `<why>: everything runs`, as today.
  - With `--group`, `reason` is that group's reason. Without it, `reason` is today's run-level reason.

`.github/workflows/ci.yml`:

- In the `iris` job, set `What changed` to `run: bash ci/changes.sh ci.yml --group ${{ matrix.group }}`.
- Gate `Build the web bundle` and `Run the group` on `if: steps.changes.outputs.run != 'false'`.
- Gate `Skipped` on `if: steps.changes.outputs.run == 'false'`, with `run: echo "iris ${{ matrix.group }} skipped: $REASON"` and `REASON: ${{ steps.changes.outputs.reason }}` in its `env`.
- In the header comment, say that each `iris` job runs its group only when `ci/changes.sh` finds a change to that group's inputs, and otherwise skips its own steps and concludes `success`.
- Change nothing else.

Rationale: this wires the consumer (the integration criterion).

`docker/tests/test-ci-changes.sh`: extend the harness and the cases, and rewrite the header list.

- **Harness.**
  - `classify` writes a default payload `{"forced": false, "before": "<40 zeros>"}` and passes `GITHUB_EVENT_PATH`. A variable overrides the payload, or removes it.
  - It passes `--group` when asked, and parses `run=` and the six `GROUP` lines.
  - Each check prints one PASS or FAIL line. A FAIL names the groups that ran against the groups wanted.
- **Cases.** Cover every row of the I/O matrix:
  - Derived from `group_units`: each live unit's script runs exactly its own group, and every other group skips it. So every group has a path that runs it and a path that skips it, however the units are grouped. `shards`, which has no live unit, runs on `src/ocutalon/cls/OcuTalon/Test/Core/X.cls`.
  - Literal: the web-only set (`web/src/app/app.ts`, `logo/web/x.png`, the ux-designs `DESIGN.md`, `web/e2e/demo-path/01-page.spec.ts`).
  - The `ci/` and workflow cases run all six.
  - Product-source samples run `browser` and are claimed by a pattern: the reason is not the unclassified one.
  - Each declared non-input runs no group.
  - The unclassified samples run all six.
  - The red-then-bookkeeping case is per group.
  - The force push, payload and paths-file fallbacks.
  - `reason=no input changed since <full base sha>` and the four `GITHUB_OUTPUT` lines with `--group`; three lines without it.
  - The bad-group exits.
- **Existing calls.** Every existing call that tests the runs API or its failure gets a valid payload, so it fails or passes for its own reason.

`docker/tests/test-ci-config.sh`:

- **The `wiring` rule.**
  - The iris job needs `bash ci/changes.sh ci.yml --group ${{ matrix.group }}`.
  - It needs the build and group steps under `steps.changes.outputs.run != 'false'`.
  - It needs a skip step under `steps.changes.outputs.run == 'false'` named `Skipped`, whose run line holds `$REASON` (`need_named`).
  - The `iris-gate` and `skip-step` samples rewrite the `run` conditions. Add a sample `group-arg`, whose classifier line drops `--group`. Each sample must be flagged.
- **A new rule `inputs`**, after the `groups` rule. `inputs_violations <tree>` sources the tree's `ci/units.sh` and reports each of these:
  - a name in `NO_WEB_BUNDLE_UNITS` that is no unit of a group;
  - a `live:` unit in it whose script has a code line (not a comment) that names `csp`, `ocutalon-web`, `npm --prefix web`, `live_web_port` or `check_security`;
  - a group of `IRIS_GROUPS` for which `group_input_pattern` fails, prints nothing, or does not match each of `ci/units.sh`, `.github/workflows/ci.yml` and `src/x`;
  - a `group_input_pattern` that answers for an unknown group.
  Then:
  - It follows the `demo-path` rule's form: a good tree, each bad sample drawing its own message, a sample whose marker appears only in a comment staying clean, and the real tree through `real_hits`.
  - It assembles its markers so that the file never matches its own rule.
  - Add an `inputs` bullet and the new wiring wording to the header list.

Rationale: this pins the gate's polarity, and keeps a unit that checks the bundle off the list a web-only push skips.

**Acceptance Criteria:**
- **The patterns are declared.** Given this story's `ci/units.sh`, when `group_input_pattern` prints the pattern of each of the six groups, then each pattern holds the shared inputs (`src/`, `ci/`, the workflow, the image and compose inputs, `eval/`) and the script of each of its live units. Each also holds `web/`, `logo/` and the ux-designs folder, except `production`'s, whose units are all in `NO_WEB_BUNDLE_UNITS`. `test-ci-config.sh` prints `PASS inputs` (REL-2, AD-22).
- **The patterns are covered.** Given the change detection, when `bash docker/tests/test-ci-changes.sh` runs (it is the `ci-changes` script of the hosted `checks` job), then it covers each group's pattern with at least one changed path that runs the group and one that skips it. That includes the web-only change, which runs `browser` and the bundle groups the plan lists and skips `production`, and a `ci/` change that runs every group. It ends `test-ci-changes: all checks passed`.
- **Integration: `ci.yml` reads the decision.** Given `ci.yml`, when its `iris` matrix job runs, then the job reads its own group's decision (`run`) from `ci/changes.sh ci.yml --group <its group>` and runs `Build the web bundle` and `Run the group` unless `run` is `false`, or else runs `Skipped` with the reason. `test-ci-config.sh` prints `PASS wiring`, and flags each sample `iris-gate`, `skip-step` and `group-arg`.
- **The guard rule works.** Given a `ci/units.sh` that lists `live:install-start` (or any unit whose script names the bundle in a code line) in `NO_WEB_BUNDLE_UNITS`, or names a unit no group has, when `test-ci-config.sh` runs, then it prints `FAIL inputs` with that violation and exits 1.
- **Every check script passes.** Given the finished tree, when `bash ci/checks.sh` runs, then it ends `checks: all scripts passed`. That includes `boundaries`, `ci-config`, `ci-changes` and `demo-path-gate`.
- **Real CI (the lead's check, see Verification).** Given the lead's push of this story, when CI runs, then every group runs in full and every `iris` job's `What changed` logs six `GROUP` lines. On the first later push that skips at least one group, each skipped job concludes `success` and logs `no input changed since <sha>`.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs.**
- **AD-22:** "A job skips its own steps, never the workflow, only when nothing it checks changed since the newest commit whose push run of the same workflow succeeded". Pull requests, no such commit and API errors run everything. A push to `main` always runs everything. The demo path is `live:demo-path`, first in `browser`. This story keeps that Rule and makes "what it checks" per group. The force push, the unreadable payload and the unclassified-path cases are stricter fallbacks. They do not contradict the Rule.
- **AD-29:** Lane B owns `ci/` (except `ci/mock/scenarios/A/`), `docker/` (except `docker/merge.cpf`) and `ci.yml`. Lane A owns `lane-a.yml`, which keeps its own behaviour.

No acceptance criterion contradicts an AD's Rule, and no NFR is unmeasurable.

**Task 0: measured at planning (read-only, on HEAD `323da7688ea3578964dbef999405abff4dd4df1f`).**
1. **Every unit builds from the whole product.**
   - Every live unit and shard starts its stack with `live_start` (`lib-live.sh` L53-84). The stack uses `docker-compose.yml`, `docker/Dockerfile` (it COPYs `src/`, `docker/ipm/`, `docker/merge.cpf`, `docker/healthcheck.sh` and `docker/after-start.*`), `.dockerignore`, `docker/tests/compose.throwaway.yml` (which mounts `./eval` read-only in every throwaway) and `ci/compose.ci.yml` (the mock, mounting `./ci/mock`).
   - Every stack installs the whole `ocutalon` package, the bridge included. Its `FileCopy` copies the bundle (`src/module.xml` L11).
   - Every unit's expected log holds `STEP Web OK` (`lib-live.sh` L577). The Web step fails without `index.html` (`src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` L172-177, `BundleCheck`).
   - `install-start` adds `docker-compose.dev.yml` (`test-install-start.sh` L290) and uses `lib-scan.sh` (L49). `storage-roundtrip` uses `lib-scan.sh` (L21). `compose-start` uses `docker/tests/compose.no-after-start.yml` (L20).
   - `build-inputs` reads `.dockerignore`, `docker/Dockerfile` and every file of `src/` and `docker/ipm/` (L49-51, L99).
   - Hence `IRIS_INPUT`.
2. **Who checks the built web bundle.** "Checks" means the unit reads, compares or serves the bundle's files.

   | Group | Unit | Checks the bundle? | Evidence |
   | --- | --- | --- | --- |
   | `install-fresh` | `install-start` | Yes | Hashes every file of the image's bundle against the installed copy (`test-install-start.sh` L117-130) |
   | `install-upgrade` | `install-upgrade` | Yes | Changes and hashes `index.html` through three rebuilt images, and checks the `/ocutalon` application's `Path` and `ServeFiles` (`check_security`) (L38, L170-218) |
   | `install-upgrade` | `audit` | No | Only `STEP Web OK` |
   | `browser` | `demo-path` | Yes | Playwright against the served page (`01-page.spec.ts` L22-25) |
   | `browser` | `sign-in` | Yes | Always rebuilds the bundle, which reads `web/`, `logo/web/` and the ux-designs `DESIGN.md`, and fetches its scripts, fonts and brand images (`test-sign-in.sh` L23; `sign-in.spec.ts` L23-37) |
   | `browser` | `bundle-folder` | Yes | Lists, hashes and serves the installed copy (`test-bundle-folder.sh` L76-167) |
   | `image` | `compose-start` | Yes | Stats every file of the image, the bundle included; any entry that is not a regular file or directory, or has another owner or mode, fails (`test-compose-start.sh` L300-304) |
   | `image` | `build-inputs` | Yes | Checks the bundle's files against the build context's allow-list, and the Dockerfile's refusal without the bundle (L64-65, L99-106) |
   | `image` | `storage-roundtrip` | No | Scans `*.cls` only |
   | `production` | `production`, `production-restart` | No | Only `STEP Web OK` (`test-production.sh` L68; `test-production-restart.sh` L29) |
   | `shards` | the 33 test classes | No | They read no installed bundle file and send no request to the web application. `Test.Web.Install` and `Test.Web.Shell` use temp-folder fixtures and their own applications; `Test.Contract.Mock`'s HTTP request goes to the mock |

   A grep of the code lines for `csp`, `ocutalon-web`, `npm --prefix web`, `live_web_port` or `check_security` finds 0 hits in `audit`, `production`, `production-restart` and `storage-roundtrip`. It finds 2 to 14 hits in every unit marked Yes except `compose-start`, which stats the bundle without naming it.
3. **Web-generated files under `src/`.** The only tracked file under `src/` that the web tooling generates is `src/ocutalon/cls/OcuTalon/Web/Public/SignInAssets.cls` (`web/scripts/tokens.mjs` L365). It is covered by `src/`.
4. **Paths no IRIS unit reads.** No unit and no test class reads `docs/`, `release/`, root `*.md`, `.claude/`, `lane-a.yml`, `.env.example` (only the check scripts and the decoy list of `build-inputs` name it), `docker/tests/record-eval.sh` (a manual recording tool), or the check and web scripts. "README" in the live scripts names the `ocutalon` account, not a file. `lib-live.sh` reads `_bmad/custom/parallel.yaml` (L98) only to find the developer lock folder, which CI does not have.
5. **A probe of the planned patterns over the 649 tracked paths.** It used the patterns above against `git ls-files`, with BSD `grep -E` on the developer machine, in scratch:
   - each group claims 261 to 330 paths;
   - 74 paths are bookkeeping;
   - 237 are declared non-inputs, 219 of them under `.claude/`;
   - **0 are unclassified**;
   - `web/src/app/app.ts` runs every group but `production`.
6. **Skips conclude `success` (measured).** In run 39611256782 (commit `e50e2b4a11942583cf52b390e73c2fa2db5c4cd1` on `OCT-epic32`, bookkeeping only), every `iris` job skipped `Build the web bundle` and `Run the group`, its `Skipped` step succeeded, and the job and the run concluded `success`. That run found its base, `143ff70d96cdb6e57c71905420430d43d9abfb21`, from a green run on `feature/OCT_OcuTalon_MVP`, so "on whatever branch it ran" already holds.
7. **The force push (measured in a scratch repository).**
   - `git merge-base --is-ancestor <old head> <new head>` exits 1 after a history rewrite, 128 for a commit that is not in the repository, and 0 for a real ancestor.
   - GitHub's push payload documents `before` ("The SHA of the most recent commit on ref before the push") and `forced` ("Whether this push was a force push of the ref").
   - That the payload file exists on our self-hosted runners is (inference) until the lead's run shows a skip. If it does not exist, every group runs, which fails safe.
8. **Merge commits (measured in a scratch repository).** On a merge of the feature branch into the epic branch, `git rev-list HEAD` lists both sides newest first by commit date, so the base can be a commit on either side. `git diff --name-only <base> HEAD` then lists the other side's changes since that base: from the feature side's green head only the epic's paths, and from the epic side's green head only the feature's paths.
   - This is sound as a comparison of trees: each path outside the diff is byte-identical to the base, where the group passed.
   - It stays sound across classifier changes, because every pattern lives in `ci/units.sh`. That is under `ci/`, an input of every group, so a base from before a pattern change always runs every group.
9. **One base is enough** for "a group whose base run wasn't a success runs in full". The base is the head of a push run that concluded `success`: it is asked for with `status=success` and filtered on `.conclusion == "success"` (`ci/changes.sh` L70, L81). A run concludes `success` only when every job did. So every group of the base run either passed, or skipped on inputs that an earlier green run had checked. A red group's change stays in the diff until a green run covers it (I/O row "Red, then bookkeeping").
10. **Baseline.** Before any change, `test-ci-changes.sh` passed 53 checks in 2 s and `test-ci-config.sh` passed every rule in 5 s, on the unchanged tree.

**Decided in-stage.**
1. **Composed patterns.** A group's pattern is composed from per-unit facts rather than written out as six literals. So a unit's script and its bundle input move with the unit when Story 32.3 rebalances, and a new unit defaults to checking the bundle. The output is still an anchored ERE of path alternatives, matched with `grep -E`, which is the style of `WEB_INPUT_PATTERN`.
2. **`shards` runs on a web change, although no class checks the bundle today.** A shard runs every test class of its areas, and either lane may add a class that reads the installed bundle. No static rule can tell, because `Test.Web.Install` names the bundle folder for its own fixtures. Including shards keeps the pattern right when a lane adds a class, at the cost of one shards job (about 6 minutes of runner time) per web-only push. `production` has two live scripts, so the static `inputs` rule guards it.
3. **The guard against an unread path is a runtime rule, not a static tree rule.** A changed path that no pattern claims and nothing declares runs every group. No path can therefore fall outside every group, whichever lane adds it. A static "every tracked path is classified" rule would add no safety, and could turn Lane A's checks red for a top-level path that Lane B has not classified yet. Today the tree has 0 unclassified paths (Task 0, 5). The tests assert that product-source samples are claimed by a pattern, so a pattern gap still shows up as a red test.
4. **The declared non-inputs are only the measured ones** (Task 0, 4). `release/`, `docs/`, `LICENSE` and `NOTICE` are declared ahead of time, so that Lane A's documentation and release folders never fall back to running everything. A story whose unit starts reading one of them moves it.
5. **Gate polarity `run != 'false'`.** An empty or misnamed output runs the group instead of skipping it (product default 3). The `web` job keeps `== 'true'`, which is outside this story.
6. **The `iris` output is removed.** Nothing reads it after this change, and a flag shared by six groups invites a wrong gate. `run` with `--group`, together with the six `GROUP` log lines, replaces it. The skip line carries the full base sha.
7. **Force push detection uses `forced` and `before`.** A `before` that is not an ancestor of HEAD, or is unknown, is treated as a force push. A payload that cannot be read runs everything. The `web` job gets the same fallbacks, because it calls the same script.
8. **One `grep -E` per group** over the paths file, instead of one per path. A full-tree diff is about 650 paths.
9. **No live unit runs in this story.** No live script, `lib-live.sh` or `ci/iris.sh` changes. What a live run would prove is proved here by the hermetic tests and the lead's CI run.
10. **The `inputs` rule's marker list is a heuristic** with a safe direction. It only keeps bundle-checking units off the skip list. `compose-start` checks the bundle without a marker, but it is not on the list.

**Rule 2 (extend, don't copy).**
- `ci/changes.sh` is extended: its `emit`, `everything`, fallback chain, base and `--paths-from` seam. It is not replaced.
- `docker/tests/test-ci-changes.sh` is extended: `commit`, `runs` and `classify`, and its `OCUTALON_CI_RUNS_FILE` and `--paths-from` seams.
- `NOT_IRIS_INPUT_PATTERN` follows `BOOKKEEPING_PATTERN`. `NO_WEB_BUNDLE_UNITS` follows `BROWSER_UNITS`. `group_input_pattern` sits beside `group_units`.
- The `inputs` rule follows the `demo-path` rule's form.
- One copy, with its reason: `WEB_BUNDLE_INPUT` repeats three alternatives of `WEB_INPUT_PATTERN`. It cannot be derived from it, because `constants.test.mjs` parses that pattern as one literal line, and the bundle's inputs are a different set from the `web` job's.

**Integration ACs.**
- Consumed-by:
  - the `iris` matrix of `ci.yml` (this story: integration AC 3, and the lead's run);
  - the `web` job (the shared fallbacks);
  - Story 32.3: a full run needs a change under `ci/`, a moved unit's inputs move with it, and the literal web-only set in `test-ci-changes.sh` changes only if a unit in `NO_WEB_BUNDLE_UNITS` moves.
- Consumes:
  - `group_units` and `IRIS_GROUPS` (Story 32.1);
  - `BOOKKEEPING_PATTERN` and `NOT_BOOKKEEPING_PATTERN`;
  - the runs API;
  - `$GITHUB_EVENT_PATH`.

**Ledger inbox.** None.

**Footprint.**
- In the footprint: `ci/units.sh` (new pattern entries only), `ci/changes.sh` and `.github/workflows/ci.yml`.
- Lane B extensions, which the lead reports: `docker/tests/test-ci-changes.sh` and `docker/tests/test-ci-config.sh`.

**Lead-owned records (optional wording; Rule 20; not implement tasks).**
- **AD-22's "CI as built".** After "...so a skip never turns a red into a green", add:
  > Each IRIS group's inputs are declared in `ci/units.sh` (`group_input_pattern`: the shared inputs, the group's own scripts, and the web bundle's inputs unless its units are measured not to check the bundle). A force push, a push payload that cannot be read, and a changed path that no group claims and no declaration excludes also run every group [AMENDED 2026-10-21, Story 32.2].

  If the lead writes it on a later day, the marker takes that day's date.
- **Rule 21.** A bullet "Skips (Story 32.2)" with the same two sentences, plus: "a web-only push runs every group but `production`".

## Verification

**Runtime targets.** No dev slot and no IRIS instance: this story changes CI configuration only, so no stage touches `ocutalon-slot-b` or any MCP profile. No stage needs a throwaway. If a stage starts one anyway, it does so only through `ci/iris.sh` with these settings:
- the stage's tag: `OCUTALON_RUN_TAG=e32s2i` (implement), `e32s2q` (QA), `e32s2r` (review) or `e32s2l` (lead);
- `OCUTALON_LOCK_OWNER='epic=32 stage=<stage>'` and `OCUTALON_LOCK_WAIT=120`;
- one call at a time, and then `ci/iris.sh teardown` with the same tag;
- `LOCK busy` means: run the same call again.

Every command runs from the epic worktree's root, in the foreground, with `timeout: 600000`. Keep this spec free of local machine paths: `boundaries` scans it.

**Commands:**
- `(loop)` `bash docker/tests/test-ci-changes.sh`. Expected: only PASS lines, then `test-ci-changes: all checks passed`; exit 0. About 10 s.
- `(loop)` `bash docker/tests/test-ci-config.sh`. Expected: `PASS wiring`, `PASS inputs`, `PASS groups`, `PASS units` and `PASS demo-path`, then `test-ci-config: all rules passed`; exit 0. About 6 s.
- `(loop)` `bash -c '. ci/units.sh; for g in $IRIS_GROUPS; do echo "$g $(group_input_pattern $g)"; done; group_input_pattern nosuch; echo "rc=$?"'`. Expected: six anchored patterns, of which only `production`'s lacks `web/`, then `rc=1`.
- `(once)` The two scripts in both orders: `bash docker/tests/test-ci-config.sh && bash docker/tests/test-ci-changes.sh`, then the reverse. Expected: both pass both times (Rule 19).
- `(once)` `bash ci/checks.sh`. Expected: `checks: all scripts passed`. About 20 to 30 s.
- `(once)` `git status --short`. Expected: only the five files of the Execution list and this spec.
- `(CI)` For the lead only:
  - **The push of this story's commit.** It changes `ci/`, so it runs every group. Pass when all of these hold:
    - the `ci` run of that commit concludes `success`;
    - all six `iris (<group>)` jobs ran `Run the group` (not skipped);
    - each job's `What changed` log shows six `GROUP <name> run=true: …` lines and its own `run=true`.

    Read the logs with `gh run view <id> --log` and the jobs with `gh api repos/jbrandtmse/OcuTalon/actions/runs/<id>/jobs`.
  - **The first later push whose changes skip at least one group.** A bookkeeping-only push skips all six; a web-only push skips `production`; the integrate-forward merge may skip some. Pass when all of these hold:
    - each skipped `iris (<group>)` job concludes `success`, with `Build the web bundle` and `Run the group` skipped;
    - its `Skipped` step prints `iris <group> skipped: no input changed since <sha>`, where `<sha>` is the full sha of a commit whose `ci` push run concluded `success`;
    - the run's conclusion is `success`.

    If no such push occurs before the epic merges, the lead records that and observes the skip on the first push after the merge.
  - **What each check proves.**
    - The hermetic tests prove the classification, the base, every fallback, the outputs and the wiring text.
    - Only a real run proves that GitHub evaluates `steps.changes.outputs.run != 'false'` as planned, that a step-level skip still concludes the job `success` (already measured on run 39611256782), and that our runners' event payload carries `forced` and `before`.
    - A real force push is owner-only (it rewrites pushed history), so the force push is proved only by the hermetic test and GitHub's documentation.

**Planned mutations (Rule 19; one per AC; the implementer applies each, observes red, reverts, and records it as `mutation: ... → ...`).**
- **AC 1:** add `live:install-start` to `NO_WEB_BUNDLE_UNITS`. Wanted red: the web-only case in `test-ci-changes.sh` (`install-fresh` skipped), and `FAIL inputs` (`test-install-start.sh` names `csp`).
- **AC 2:** drop `docker/[^/]+$` from `IRIS_INPUT`. Wanted red: the product-source cases for `docker/Dockerfile` and `docker/merge.cpf`. All groups still run, through the fallback, but the cases are no longer claimed by a pattern.
- **AC 2:** remove the unclassified fallback. Wanted red: the `newdir/x.txt` case.
- **AC 2:** skip the `forced` check. Wanted red: the force-push case.
- **AC 2:** treat a missing payload as `forced: false`. Wanted red: the payload-not-readable case.
- **AC 2:** accept `failure` runs as a base. Wanted red: the per-group red-then-bookkeeping case.
- **AC 3:** set the `Run the group` gate to `steps.changes.outputs.run == 'true'`. Wanted: `FAIL wiring`.
- **AC 3:** drop `--group` from the classifier line. Wanted: `FAIL wiring`.
- **AC 4:** list `live:sign-in` in `NO_WEB_BUNDLE_UNITS`. Wanted: `FAIL inputs` naming `test-sign-in.sh`.
- **AC 5** is the aggregate of the others, and **AC 6** is the lead's CI evidence: neither has a local mutation.

**Shared surfaces:**
- the outputs of `ci/changes.sh` (`base`, `web` and `reason` kept; `iris` removed; `run` added with `--group`; the `GROUP` lines) and its fallbacks. Read by `ci.yml`'s `web` and `iris` jobs and by `test-ci-changes.sh`;
- the `wiring` rule of `test-ci-config.sh` (the exact classifier line and gates of the `iris` job);
- the new names in `ci/units.sh`. That file is sourced by `ci/iris.sh`, `ci/checks.sh`, `ci/changes.sh` and `test-ci-config.sh`, and copied by `test-demo-path-gate.sh`. `WEB_INPUT_PATTERN` stays one literal line for `ci/mock/test/constants.test.mjs`;
- the `iris` job's `Skipped` line, which the lead's CI evidence reads.

No list that another test counts changes size: `CHECK_SCRIPTS`, `WEB_SCRIPTS`, the groups and the shards are unchanged.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
