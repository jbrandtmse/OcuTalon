---
title: 'Story 36.7: Epic 36 burn-down: an upgrade removes the previous builds'' bundle files from the served web folder'
type: 'bugfix'
created: '2026-11-14'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-36-5-epic-36-burn-down-load-the-settings-history-and-usage-pages.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** IPM's `FileCopy` copies each new build over `csp/ocutalon-web/` and never deletes anything, and the Web step's `RemoveOldBundle` only cleans the old `csp/ocutalon/` folder. So every upgrade whose `main` hash changes leaves the previous build's `main-<hash>.js` in the served folder. The v1.0.9 rehearsal measured 28 served files against 27 built, with `./main-JCJUH3RN.js` extra (DW-1320). Leftovers from every earlier upgrade pile up too, and the online demo carries one from each release. DW-1320 blocks the 1.0.10 RC.

**Approach:** At every start, after its existing work, the Web step removes from `csp/ocutalon-web/` each top-level file whose name matches `STALEFILES` and that the installed build does not contain. It does this only when the served `index.html` is byte-equal to the installed build's. The installed build is the folder IPM's `FileCopy` read, located from the `ocutalon` module's `Root`. `release/upgrade-harness.sh` gains a permanent `stale-files` row. The row plants an old `main-ZZSTALE0.js` before the upgrade, and after the upgrade and after the restart it requires the served folder's file list to equal the candidate's build output.

## Boundaries & Constraints

**Always:**
- Only these files are deleted: top-level files of `csp/ocutalon-web/` whose names match `STALEFILES` (unchanged: `^(main|chunk|polyfills|styles)-[A-Za-z0-9]+\.(js|css)(\.map)?$`) and that the build folder lacks by name. The delete is never "anything not in the build".
- Nothing is deleted when there is no build folder, when the build folder has no `index.html`, or when the served `index.html` differs from it.
- The delete never fails the start. A file that can't be deleted gives a `WARN Web` line that names it.
- The Docker path and the IPM path behave the same (AD-23).
- Every test added or changed passes on a fresh environment, in either order.
- Lane B variables go on every `ci/iris.sh` and harness call, and run tags start with `e36s7`.

**Never:**
- No change to `STALEFILES`, the manifests (`src/module.xml`, `module.xml`), `FileCopy`, `RemoveOldBundle`'s behaviour, `web/`, `ci/units.sh` or `.github/workflows`.
- No public text: no README, GUIDE, `docs/`, release-note or web text, and no public claim.
- Nothing is deleted by hand on the online demo.
- Never `--rc`, nothing written under `release/records/`, no tag, no branch, no push, never slot B.
- No `git commit`, `git push` or anything else that triggers CI.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Upgrade | Served folder: new build + `main-OLD…js`, `.map`, `chunk-`/`polyfills-`/`styles-` names the build lacks | Those files are gone; every build file stays byte for byte | none |
| Survivors | `zz-keep.txt`, `main-AB12CD34.js.bak`, `Main-…js`, `main-zz_stale.js`, `assets/main-…js`, `zz/main-…js` | All kept (no match, or not top level) | none |
| A directory named like a bundle file | `main-OLD88888.js/` folder at the top level | Kept (files only) | none |
| Another build is served | Served `index.html` ≠ build's (same-version image rebuilt; wrong root) | Nothing deleted | none |
| No build folder | No IPM module (slot, bridge-only load), `root` "" or no `index.html` under either candidate | Nothing deleted, no warning | none |
| Stuck file | A stale file in a folder the IRIS user can't write | Other stale files deleted; step OK | one `WARN Web` line naming the file |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`:
  - class doc L20-21; `BUNDLEFOLDER` L41; `STALEFILES` L55 (read only);
  - `Run` L72-74 calls `Prepare($SYSTEM.Util.DataDirectory())`; `Prepare` L98-104;
  - `RemoveOldBundle` L313-344 is the sibling to extend, with the same marker read, `Entries` L378-389 (files only with `includeDirs` 0) and the `$Match` on `GetFilename`;
  - `DeleteFile` L392 returns an error (not used: the new delete warns).
- `src/ocutalon/cls/OcuTalon/Install/Step.cls:52` `Warn(text)` and `:66` `TakeWarnings()`. The registry prints them as `WARN Web <text>`.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls:74-96`: `Ipm` is the IPM entry point (Configure, After, so after the bundle copy). On the image it returns at once, and `docker/after-start.cos` runs `zpm "load /opt/ocutalon/src"` when the version changes, then `Registry.Run("after-start")` at every start.
- `src/module.xml:18` `<FileCopy Name="ocutalon/csp/" …>` and `module.xml:18` `<FileCopy Name="src/ocutalon/csp/" …>`. The drift rule of `docker/tests/test-pinned-sources.sh` pins the pair.
- IPM 0.10.10 (decoded from `docker/ipm/zpm-0.10.10.xml`, read only):
  - `%IPM.ResourceProcessor.FileCopy` copies at the start of Activate from `GetSource()` = `Module.Root _ Name`, with `CopyDir(src, dst, 'Overlay)`;
  - on UNIX, `%Library.File.CopyDir` overlays and only deletes a target file before overwriting it, so nothing is ever pruned;
  - on Windows, IPM deletes the whole target tree first;
  - `%IPM.Lifecycle.Base` Reload (L603-683) sets `Module.Root` to the load folder and saves it before Activate.
- Precedent for reading the module without a compile-time IPM dependency: `src/ocutalon/cls/OcuTalon/Web/Api.cls:1548` `$ClassMethod("%IPM.Storage.Module", "NameOpen", "ocutalon")`.
- `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls`:
  - header L1-5;
  - bundle tests L465-579 (`TestPrepareReadsTheNewFolder` calls `Prepare(data)` and stays valid: the real build folder's `index.html` differs from its seed);
  - helpers `Seed`/`SeedBundle`/`Tree` L594-640, to reuse.
  - Class `OcuTalon.Test.Web.Install`, shard `lane-b@rest`, group `shards-6`.
- `docker/tests/test-install-upgrade.sh` (unit `live:install-upgrade`, group `install-upgrade`): header row 6 L5-8; `index_first` L151; row 6 recreate L170-189; row 15 part 2 index check L197-202; `make_image_context` L34-42 (v1's bundle = v0's plus an `index.html` comment). `docker/tests/lib-live.sh:700` `container_tree_hashes`.
- `release/upgrade-harness.sh`:
  - header L1-53; `HARNESS_ON`/`HARNESS_ROWS` L70-73;
  - `storage_compare` L371-383 (sibling pure function); `record_rows`'s `title()` L393;
  - `row`/`note_row`/`pass`/`fail` L590-619; `api_get`/`signin` L633-652;
  - `phase_seed` L1405-1460 (families seeded after `signin`); `phase_upgrade` L1720-1797 and `phase_restart` L1799-1887 (family checks after `signin`, before `logout_all`).
- `docker/tests/test-upgrade-harness.sh` (hosted `checks`, `CHECK_SCRIPTS` "upgrade-harness"):
  - header L1-46; `rule()` L91-109;
  - `write_results` L445-460; `t_record` L478-497 (13 rows and 15 table lines, the row order string, "every row is not run" 13);
  - families pin L1075-1082; rule list at the end.
- `release/ipm-install.sh` (lane-a `ipm-install-p` job, part `b`): check 25 doc L87-89; `scratch_copy` L1170-1175; `reinstall_next` L1669-1735; `check_session` index precedent L466-470.
- `docker/tests/test-compose-file.sh:402-403`: the static check of the `FileCopy` line.
- `_bmad-output/implementation-artifacts/evidence/36-5-upgrade-from-v1.0.9.md`: the measured 28-vs-27 list and the phase-by-phase command form.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls`:
  - add `Parameter BUILDFOLDERS = "ocutalon/csp/,src/ocutalon/csp/";` (the bundle `FileCopy` source below the module root, in `src/module.xml` and in `module.xml`);
  - `ModuleRoot()`: the normalized `Root` of the IPM module `ocutalon`, "" when IPM or the module is absent (Try/Catch, `$ClassMethod`);
  - `BuildFolder(root = {..ModuleRoot()})`: the first `root_<rel>` of `BUILDFOLDERS` that holds `index.html`, else "";
  - `RemoveStaleBundle(servedDir, buildDir) As %Status`: the rule of the Boundaries and the Matrix, always OK, top level only, reusing `Entries` and `STALEFILES`;
  - `Prepare(dataDirectory, buildDirectory = {..BuildFolder()})`: after `RemoveOldBundle` succeeds, return `RemoveStaleBundle(data_BUNDLEFOLDER, buildDirectory)`;
  - update the class, `Run` and `Prepare` doc comments (contract only, Rule 14).
- `src/ocutalon/cls/OcuTalon/Test/Web/Install.cls`: extend the existing class, reusing its helpers (Rule 2), and update its header.
  - `TestRemoveStaleBundle`: every Matrix row but "Stuck file", with an exact `Tree` of what remains, the build folder unchanged, and a second run that changes nothing.
  - `TestRemoveStaleBundleWarns`: the stuck file. Make the folder read-only with `%File.SetReadOnly`, restore it after, check `TakeWarnings()`, and skip with `AssertSkipped` when the folder can't be made read-only.
  - `TestBuildFolder`: `ocutalon/csp/` alone, `src/ocutalon/csp/` alone, both (`ocutalon/csp/` wins), neither, and `root` "". On the image (`Demo.#VERSIONFILE` exists), `ModuleRoot()` is `/opt/ocutalon/src/`; elsewhere it is skipped.
  - `TestPrepareRemovesStale`: `Prepare(data, build)` removes a planted stale file from `data/csp/ocutalon-web/` and keeps the rest.
- `docker/tests/test-install-upgrade.sh`: before row 6's recreate, plant in `/durable/iris/csp/ocutalon-web/`:
  - stale: `main-ZZSTALE0.js`, `main-ZZSTALE0.js.map`, `chunk-ZZSTALE1.js`, `polyfills-ZZSTALE2.js`, `styles-ZZSTALE3.css`;
  - survivors: `zz-admin-note.txt`, `main-ZZSTALE4.js.bak`, `Main-ZZSTALE5.js`, `main-zz_stale.js`, `assets/main-ZZSTALE6.js`, `zz-admin/main-ZZSTALE7.js`.

  After row 15 part 2, add one check: no stale file is left, each survivor is there with its content, and `container_tree_hashes` of the served folder, without the survivors, equals that of `/opt/ocutalon/src/ocutalon/csp`. Extend the header's row 6 text.
- `release/upgrade-harness.sh`: the `stale-files` family, as Gate item 2 says. Also extend the header (a paragraph like the pairing, memory and document ones).
- `docker/tests/test-upgrade-harness.sh`: rule `stale-files` (`t_stale_files`, `b_stale_files`), the `t_record`/`write_results` updates and the header line (Gate item 2).
- `release/ipm-install.sh` `reinstall_next`, an IPM upgrade from a new folder:
  - the scratch copy also appends `<!-- <raised> -->` to `$copy/ocutalon/csp/index.html`, so that only a build folder read from the new root matches the served one;
  - before the `run`, plant `main-ZZSTALE0.js` and `zz-admin-note.txt` in `$SYSTEM.Util.DataDirectory()_"csp/ocutalon-web/"`, through an `iris_script`;
  - after `check_run_ok`, one `check_session`: the stale file is gone, the note stays, and the served `index.html` equals the copy's;
  - extend check 25's header text.
- `docker/tests/test-compose-file.sh`: one check that `Web.cls`'s `BUILDFOLDERS` holds both manifests' bundle `FileCopy` names, read from `src/module.xml` and `module.xml`.
- `_bmad-output/implementation-artifacts/evidence/36-7-upgrade-from-v1.0.9.md`, new and records only: the rehearsal's record section, the served and build lists, and the mutation run's `stale files` row.

**Acceptance Criteria:**
- AC1, removal. Given an installed vN whose served folder holds hashed bundle files that vN+1 lacks, when the container is recreated from vN+1, then each of them is gone and the served folder holds every file of the image's bundle byte for byte (`live:install-upgrade`, the new check).
- AC2, narrow. Given the same upgrade with the survivors planted, when it completes, then each survivor is kept with its content and nothing else beyond the bundle remains. The full rule is pinned by `TestRemoveStaleBundle` (survivors, guards, nested, `.map`, missing folders).
- AC3, IPM path (AD-23). Given an IPM install, when the install command runs with the next version from a new folder, then the planted stale file is gone, the planted note stays, and `index.html` is the new folder's (`release/ipm-install.sh b`, check 25).
- AC4, rehearsal (ruling point 3). Given `release/upgrade-harness.sh` run phase by phase with `--rehearsal --previous v1.0.9 --record <temp file>` on this checkout, when `report` runs, then `Result: pass`, the `stale files` row passes with the plant note, and the served list equals `src/ocutalon/csp/`'s 27 files after the upgrade and after the restart. With the `RemoveStaleBundle` call removed from `Prepare`, the row fails and names `./main-JCJUH3RN.js` and `./main-ZZSTALE0.js`.
- AC5, permanent row (ruling point 4). Given any harness run, when its record is written, then the table holds a `stale files` row after `private globals`, the row counts toward `Result:`, and `docker/tests/test-upgrade-harness.sh` passes with rule `stale-files`.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-23: one recipe, two install paths; static files in `csp/ocutalon-web/`; warnings through `Install.Step.Warn`.
- AD-5: only code is replaced at install.
- AD-29: `Install/Step/Web.cls` and `Test/Web/**` are Lane B's. So the unit test extends `Test/Web/Install.cls`, not the suggested `Test/Install/`, which is Lane A's.
- AD-22: CI units.

Nothing here contradicts an AD. Recommended to the lead (Rule 20, the lead's call): one AD-23 sentence saying that every start removes, from `csp/ocutalon-web/`, the top-level `STALEFILES` files that the installed build lacks.

**Why the step, and why the root:**
- The Web step already runs on both paths after the copy: at Configure on the IPM path, and after the load at every start on the image. A new manifest Invoke would need both manifests and the drift rule changed.
- The `index.html` guard makes a wrong or stale root harmless. The case it protects against: a same-version image whose bundle changed. That image is not reloaded, and without the guard its old served `main` would be deleted under the served page.
- The delete warns instead of failing. A leftover is harmless, while an install that is not ready is not. `RemoveOldBundle` fails because the old folder is served without sign-in (DW-5). That is not the case here.

**Extend, don't copy:**
- `RemoveStaleBundle` reuses `Entries` and `STALEFILES`.
- The tests reuse `Seed`/`SeedBundle`/`Tree`.
- `stale_compare` is a new pure function beside `storage_compare`, because it reports both directions (`EXTRA` and `MISSING`), while `storage_compare` reports only `MISSING`.

**Integration (Rules 1 and 2):** no new service. The consumers of `RemoveStaleBundle`:
- the after-start start (pinned by `live:install-upgrade`);
- the IPM install (`ipm-install.sh b`);
- the harness `stale-files` row.

**Consumes:**
- IPM's `FileCopy`, which copies first;
- `%IPM.Storage.Module.Root`.

**Ledger inbox:**
- DW-1320 is addressed in full (AC1 to AC5).
- DW-1300 (the optimizer's `_`/`-` chunk names) stays `wontfix-accepted`. With `STALEFILES` unchanged, such names would not be deleted either. `lazy-routes.test.mjs` pins `NG_BUILD_OPTIMIZE_CHUNKS=0`.

### Gate item 1: the file list for AC2, and the delete rule

What is written into `csp/ocutalon-web/`, found by reading `src/module.xml`, `module.xml`, `Web.cls`, the `Dockerfile`, `docker/after-start.{sh,cos}`, `web/angular.json`, `web/scripts/brand.mjs`, and every tag v1.0.0 to v1.0.9, and by grepping the tree for `ocutalon-web` and `BUNDLEFOLDER`:

| File or pattern | Written by | Matches `STALEFILES` | Fate |
| --- | --- | --- | --- |
| `index.html` | FileCopy (Angular build) | no | kept, overwritten by each copy |
| `3rdpartylicenses.txt` | FileCopy (`extractLicenses`) | no | kept |
| `main-<hash>.js` of the new build | FileCopy | yes | kept, because the build holds it |
| `chunk-<hash>.js`: 8 today (3 initial, 3 lazy pages, 2 shared, Story 36.5) | FileCopy (base32 names, `NG_BUILD_OPTIMIZE_CHUNKS=0`) | yes | kept, because the build holds them |
| `styles-<hash>.css` | FileCopy | yes | kept, because the build holds it |
| `assets/brand/*.png` (6, the favicon `favicon-32.png` among them) | FileCopy (`brand.mjs` copies `logo/web` into `web/public/assets/brand`) | no (nested) | kept |
| `assets/fonts/*.woff2` (5) and `assets/licenses/*.txt` (4) | FileCopy (`web/public`) | no (nested) | kept |
| an earlier release's `main-<hash>.js` | an earlier FileCopy | yes | deleted |
| `polyfills-<hash>.js` and `*.map` | no build since v1.0.0 makes them (no polyfills entry, no production source maps); an older or dev build could | yes | deleted when absent from the new build |
| any other name: an admin's file, or a nested or non-matching name | not OcuTalon | no | kept |

- Every release, v1.0.0 to v1.0.9, shipped exactly the same 19 names, and only `main`'s hash differs. So the online demo's leftovers are earlier `main`s, all of which are deleted.
- Today's build has 27 files (Story 36.5's measurement).
- At runtime nothing writes into the folder:
  - `Shell` only serves the folder through `%CSP.StreamServer`;
  - `SignInAssets` and `SplashAssets` are class parameters that are inlined;
  - after-start writes `/durable/ocutalon-after-start.log` and `/durable/ocutalon.ready`;
  - the `Dockerfile` writes `/opt/ocutalon` and `/durable` only;
  - the Web step reads `index.html` and deletes in `csp/ocutalon/`;
  - the Demo step removes only OCUORDERS's `csp/<namespace>`.
- The tests' plants (the harness, `test-install-upgrade.sh` and `ipm-install.sh`) are the only other writers.

**The rule.** Delete a file when all of these hold:
1. it is a top-level file of the served folder;
2. its name matches `STALEFILES`;
3. the new build folder has no file of that name;
4. the served `index.html` is byte-equal to the build's.

**Top level only:**
- Angular writes hashed files only at the output root, and nested files come unhashed from `web/public`.
- `STALEFILES` is defined as "the top-level files of a bundle".
- Going into subfolders would reach folders an admin may own, with no gain.

**Where the new build's list comes from at upgrade time:** the folder that `FileCopy` read.
- Through `src/module.xml`, that is `<module Root>ocutalon/csp/`: `/opt/ocutalon/src/ocutalon/csp/` on the image, `<extract>/ocutalon/csp/` for the IPM artifact.
- Through the repository's `module.xml`, it is `<Root>src/ocutalon/csp/`.
- The `Root` is read from IPM 0.10.10's Reload, which saves it before Activate. That is an inference, until `ipm-install.sh b` (AC3) measures it.

### Gate item 2: the harness row

- **Constants:** `SERVED_WEB=/durable/iris/csp/ocutalon-web`, `BUILD_WEB=src/ocutalon/csp` (the candidate checkout's own build output) and `STALE_PLANT=main-ZZSTALE0.js`. The `0` is outside esbuild's base32 hash alphabet, so no real build can have that name.
- **Family and row:**
  - `stale-files` is appended to `HARNESS_ON`.
  - In `HARNESS_ROWS` it goes right after `private-globals`, which keeps the `" pairing memory document"` tail pinned at L1080. The install-integrity rows sit together.
  - `title()` turns every `-` into a space, which gives `stale files`.
- **Pure functions:**
  - `stale_compare <build list> <served list>` prints `EXTRA <path>` and `MISSING <path>` lines and returns 1 when there is any. It returns 2 for an empty build list (no vacuous pass) and 0 when the lists are equal.
  - Stubbable readers: `served_tree` (`dc exec … find . -type f | LC_ALL=C sort`), `build_tree` and `web_status <path>` (a signed-in GET of `$base/ocutalon/<path>`).
- **Seed:** `seed_stale_files` runs in `phase_seed` after the document family, on the previous build. It writes the plant and checks that it exists, which gives a `seed` line, then adds `note_row "main-ZZSTALE0.js was planted in the served folder before the upgrade, standing in for an earlier upgrade's leftover"`.
- **Plant mode:** every mode plants, release runs included. It is a seed like the conversation and reminders. The record's row says so in its note, so it can't mislead, and it means the row exercises the delete even when two builds share a `main` hash. (Gate item 3 lists the alternative.)
- **Checks:**
  - `check_stale_files upgrade`, in `phase_upgrade` after the families: the list comparison, then `web_status` answers 404 for the plant and 200 for the build's `main-*.js`.
  - `check_stale_files restart`, in `phase_restart`: the list comparison.
  - A pass row reads 3 checks.
- **Record lines:**
  - `RECORD stale-files pass after the upgrade the served web folder holds exactly the candidate's 27 build files`
  - `RECORD stale-files pass after the upgrade /ocutalon/main-ZZSTALE0.js answers 404 and /ocutalon/main-<hash>.js 200`
  - `RECORD stale-files fail after the upgrade the served web folder differs from the candidate's build output (27 files): extra ./main-JCJUH3RN.js ./main-ZZSTALE0.js` (at most 10 names)
  - The table row: `| stale files | pass | 3 checks passed; main-ZZSTALE0.js was planted … leftover |`.
- **Hermetic self-test** (`t_stale_files`):
  - `stale_compare`: equal, extra, missing, both, and an empty build list;
  - `STALE_PLANT` matches `STALEFILES` as read from `Web.cls` (`grep -E`), and its hash part holds a character outside `[A-Z2-7]`;
  - the `HARNESS_ON`/`HARNESS_ROWS` placement;
  - the `declare -f` wiring of `phase_seed`, `phase_upgrade` and `phase_restart`;
  - `check_stale_files` over stubs: equal gives pass lines; an extra and a missing file give fail lines that name them; the plant answering 200 gives a fail;
  - `seed_stale_files` over a stub: success gives a seed line and the note; failure gives a fail line.
  - `b_stale_files`: `stale_compare() { return 0; }`.
  - `t_record`: 14 rows and 16 table lines, `stale files` after `private globals`, "every row is not run" 14, and `write_results` gains the id.
- **Mutation:** remove the `RemoveStaleBundle` call from `Prepare`, rebuild, and run the rehearsal's `build`, `seed`, `upgrade`, `report` and `down`. The row fails and names both files (AC4).

### Gate item 3: veto items (escalate; veto window)

1. **Deleting files on an admin's instance** (install behaviour). The delete is narrow: the four-part rule, top level only, and only for the build that is served. It is silent on success and a `WARN Web` line on failure. Recommendation: accept.
2. **An admin's own top-level file named like a bundle file** (for example `main-CUSTOM01.js`) is deleted at the next start, with no public text to warn of it (ruling point 5). The alternatives were rejected:
   - quarantine (a new folder on the volume);
   - deleting only names an earlier release shipped (earlier upgrades' names are not known).

   Recommendation: accept, because the pattern is OcuTalon's bundle namespace in its own served folder.
3. **Any other admin file survives** (AC2). Note: on a Windows IPM install, IPM 0.10.10's own `FileCopy` already deletes the whole folder before copying. That is pre-existing and unchanged. Recommendation: note only.
4. **Open tab across an upgrade.** An old tab opening a lazy page for the first time after the upgrade now gets a 404 for its old chunk until it reloads. This reverses Story 36.5's design note.
   - It matters on an IPM install, where sessions may survive.
   - On the image, IRIS restarts, and a sessionless chunk request already gets the sign-in page (an inference).

   Recommendation: accept with no handling. A chunk-load reload would be new web behaviour.
5. **Release tool footprint.** `release/upgrade-harness.sh` and `release/ipm-install.sh` are `release/**`: in `lane_a`'s footprint and not in Epic 36's `paths_hint`, so they are `footprint_extensions`. No in-progress epic names them, except Epic 11's wildcard "either lane's files" (its PART 2 stories are in backlog). Recommendation: proceed, because the ruling assigns point 4 here.
6. **Contended Lane B files.** `Install/Step/Web.cls` and `Test/Web/Install.cls` are named by in-progress Epics 21, 25 and 35. The edits are additive, so a plain union at integrate-forward. `docker/tests/test-{install-upgrade,upgrade-harness,compose-file}.sh` are an extension of Epic 36's footprint and are not contended. Recommendation: proceed.
7. **Planting in release runs.** The plant is recorded in the row's note. The alternative is a rehearsal-only option. Recommendation: plant always.
8. **Public text.** None is needed. The harness row is release evidence in the record, not a claim or a release-note line. Recommendation: confirm.
9. **Online demo.** Nothing is deleted by hand. The 1.0.10 update cleans it through this step, because every earlier `main` matches the pattern. 1.0.10's phase 2 then checks that the served folder matches the build. Recommendation: no action.
10. **Data retention.** These are build artifacts, not stored data, so there is no schema, format or retention change. No privilege or grant change either. Recommendation: none needed.

## Verification

`<lane-b vars>` = `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=36 stage=implement'`.

Tags: `e36s7i` (fresh), `e36s7iw` (warm), `e36s7b` (ipm), `e36s7h` (harness) and `e36s7m` (the harness mutation).

Rules for every run:
- one command per call, in the foreground, with `timeout: 600000`;
- never two test calls in one message;
- never slot B;
- at the end, also after a failure, run `ci/warm.sh down` and `ci/iris.sh teardown` for each tag, and the harness's `down`.

**Commands:**
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s7iw bash ci/warm.sh up` once, then `<lane-b vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e36s7iw bash ci/iris.sh class OcuTalon.Test.Web.Install`. Expected: pass.
- (loop) `bash docker/tests/test-upgrade-harness.sh`. Expected: all rules passed, `stale-files` included.
- (once) `bash ci/checks.sh`. Expected: every block PASS (`compose-file` and `upgrade-harness` among them).
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s7i bash ci/iris.sh class OcuTalon.Test.Web.Install` on a fresh stack. Expected: pass.
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s7i bash ci/iris.sh build`, then `… live install-upgrade`. Expected: all checks passed.
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s7b OCUTALON_LIVE_DEADLINE=1980 bash release/ipm-install.sh b` (about 530 s). Expected: all checks passed.
- (once) The harness rehearsal, phase by phase, tag `e36s7h`: `build --rehearsal --previous v1.0.9 --record <scratch>/36-7.md`, then `settings`, `seed`, `upgrade`, `restart`, `storage`, `report` and `down`. Expected: `RESULT pass`, and the `stale files` row passes with its note. One rerun of a row-6 readiness timeout is allowed (DW-1082).

**Mutations** (Rule 19; record each as `mutation: <change> -> <red test>`; restore the tree byte-identical):
- AC1: delete the `RemoveStaleBundle` call in `Prepare`. Then `live:install-upgrade`'s new check goes red.
- AC2: make `RemoveStaleBundle` skip the `STALEFILES` test. Then `TestRemoveStaleBundle` goes red (warm).
- AC3: make `ModuleRoot()` return the old root, `/opt/ocutalon-ipm/src/`. Then `ipm-install.sh b`'s check 25 stale line goes red.
- AC4: the same mutation as AC1, run with tag `e36s7m` as `build`, `seed`, `upgrade`, `report`, `down`. Then the `stale files` row fails and names `./main-JCJUH3RN.js` and `./main-ZZSTALE0.js`.
- AC5: drop `stale-files` from `HARNESS_ROWS`. Then `test-upgrade-harness.sh` rules `record` and `stale-files` go red.

**Shared surfaces:**
- the served folder's file set (`test-install-start` row 14, `test-bundle-folder`, and `test-online-demo`'s `main-*` pick);
- `Web.Prepare`'s signature (`Run`, `TestPrepareReadsTheNewFolder`);
- `HARNESS_ROWS` and `HARNESS_ON` and the record table (`t_record`, `t_record_contract`, the release records);
- `reinstall_next`'s scratch copy.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none. The run halted after planning, as the invocation directed. The spec goes to the Contest Planner at the spec gate. Gate items 1 to 3 are under `## Design Notes`, and the veto items await the Planner's ruling.
