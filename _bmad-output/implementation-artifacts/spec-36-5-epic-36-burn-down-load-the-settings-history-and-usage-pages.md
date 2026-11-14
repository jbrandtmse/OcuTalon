---
title: 'Story 36.5: Epic 36 burn-down: load the Settings, History and Usage pages lazily'
type: 'refactor'
created: '2026-11-13'
status: 'done'
baseline_revision: 'c9ca6544ce3ea4999f32868c7a628118857139f7'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-36-context.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The installer's STALEFILES pattern (Install/Step/Web.cls) accepts only [A-Za-z0-9] in a bundle file's hash, but Angular's chunk optimizer names chunks with an [A-Za-z0-9_-] hash, so with the optimizer on, RemoveOldBundle leaves such chunk files in the old folder.
    evidence: |-
      Plan-stage scratch build of this story's design with the optimizer on (Angular's default for 3 or more lazy chunks) produced chunk-BAxI_vlj.js and, in another variant, chunk-BXm6-erL.js; STALEFILES is ^(main|chunk|polyfills|styles)-[A-Za-z0-9]+\.(js|css)(\.map)?$ and test-bundle-folder.sh expects the old folder to hold only its two zz files. @angular/build's own chunk-optimizer.js matches names with -[a-zA-Z0-9_-]{8}. This story keeps the optimizer off (NG_BUILD_OPTIMIZE_CHUNKS=0, esbuild's base32 names match) because a server change is ruled out; reopen if the optimizer is ever turned on.
    location: >-
      src/ocutalon/cls/OcuTalon/Install/Step/Web.cls Parameter STALEFILES (L55); web/package.json scripts.build
    severity: low
---

<intent-contract>

## Intent

**Problem:** Every route is eager, so the initial web bundle is 1,007.44 kB and the production build fails the unchanged 1MB `maximumError` (DW-1282: the cap must regain at least 50 kB of headroom, and the Planner's binding target is an initial total of at most 921 kB). The Settings page with its eight sections, the History page and the Usage page all ride in `main`.

**Approach:** Load the three page routes with `loadComponent`, move the few facts the eager shell needs from the page view modules (three titles, the unsaved prompt's three strings, `pageOf`, `settingsMatch`) into one small framework-free eager module that the view modules reference, and build with Angular's chunk optimizer off so every chunk name still matches the installer's bundle-file pattern. Behaviour, texts and server stay exactly as they are.

## Boundaries & Constraints

**Always:** Same page titles, headings, sections, data, `unsavedGuard` behaviour (S6/S6b/S6c), header current-page marking and `#/settings/<slug>` matching (one route, `settingsMatch`). Every string keeps its exact value; a view constant that moves is referenced, never copied. Hash routing and `canceledNavigationResolution: 'computed'` stay. Every test added or changed passes on a fresh environment, in either order. Lane B variables on every `ci/iris.sh` call; run tags start `e36s5`.

**Never:** No change to `web/angular.json` budgets (`maximumError` stays `1MB`, the 500kB warning stays). No server or ObjectScript change (`Install/Step/Web.cls` included), no `.github/workflows`, `release/**` or `ci/units.sh` change, no new user-facing text, no new dependency, no `@defer`. Do not edit other lanes' sections (25.4 Roles, 21.4 MCP; not on this branch). Never delete, skip, tag off or weaken a test. No `git commit` / `git push` / anything that triggers CI (CI HOLD).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Deep link, settings | Signed-in README admin; new page at `/ocutalon/#/settings`, then reload | Title "Settings · OcuTalon", h1 Settings, 8 section links, h2 Models, `GET /api/v1/settings` 200, header Settings `aria-current="page"` | no console error, no page error |
| Deep link, section | Same, at `#/settings/check-thresholds`, then reload | h2 Check thresholds and its fields; its section link current | as above |
| Deep link, history | Same, at `#/history`, then reload | Title "History · OcuTalon", h1 History (visually hidden), tablist with Decisions selected, `GET /api/v1/history/decisions` 200, header History current | as above |
| Deep link, usage | Same, at `#/usage`, then reload | Title "Usage · OcuTalon", h1 Usage, `GET /api/v1/usage` 200 and its table or empty text, header Usage current | as above |
| Leave dirty settings | Lazily loaded settings with an unsaved edit; a link | The unsaved prompt opens as today (S6) | Stay keeps page and values |
| Bundle-folder upgrade | Built bundle with `chunk-*.js` files seeded into the old folder | The restart removes every OcuTalon file there (live:bundle-folder) | n/a |

</intent-contract>

## Code Map

- `web/src/app/app.config.ts` -- the route table L22-28 and its eager imports L8-15 (`HistoryPage`, `HISTORY_TEXTS`, `SettingsPage`, `SETTINGS_TEXTS`/`settingsMatch`, `UsagePage`, `USAGE_TEXTS`); the doc comment L17-21 describes the routes. `unsavedGuard` stays imported eagerly.
- `web/src/app/header/current-page.ts:7` -- imports `pageOf` from `settings/settings-view` (the only other eager link into `settings/`).
- `web/src/app/settings/unsaved-guard.ts` -- eager by design (route `canDeactivate`); imports `unsaved-dialog.ts`, which imports `SETTINGS_TEXTS` (L4) for `unsaved`/`stay`/`leave` only. The guard itself does not change.
- `web/src/app/settings/settings-view.ts` -- framework-free, imported by Node tests as `.ts`. `SETTINGS_TEXTS.title` L31, `unsaved`/`stay`/`leave` L50-52, `pageOf` L175-188, `settingsMatch` L195-204; doc comment L1-26 ("imports only types", the `pageOf` bullet). Only `import type` today (L27).
- `web/src/app/history/history-view.ts:42-43` (`HISTORY_TEXTS.title`) and `web/src/app/usage/usage-view.ts:22-23` (`USAGE_TEXTS.title`) -- framework-free, Node-imported. `history-page.ts:18` imports `usage-view`; `usage-page.ts:7` imports `SETTINGS_TEXTS` (both stay inside lazy chunks).
- Precedent for a value import between Node-run view modules: `settings/on-call-view.ts:15` `import { SETTINGS_TEXTS } from './settings-view.ts';` (`tsconfig.json` has `rewriteRelativeImportExtensions`).
- `web/src/main.ts` -- the eager entry (imports `app/app`, `app/app.config`, `app/theme/theme`); the root of the import-graph pin.
- `web/package.json:13` -- `"build"`: `... && node scripts/brand.mjs && ng build`. `node_modules/@angular/build/src/utils/environment-options.js:153-176`: `NG_BUILD_OPTIMIZE_CHUNKS` (`0`/`false` disables; default threshold 3 lazy chunks); `src/builders/application/chunk-optimizer.js:251` renames chunks `-[hash]` with `[a-zA-Z0-9_-]`. esbuild's own chunk hash is base32 (`chunk-3ISEZWU6.js`).
- `web/angular.json:48-53` -- budgets; read only.
- Read only, the bundle-name consumers: `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls:55` `STALEFILES` and `RemoveOldBundle` L306-345; `docker/tests/test-bundle-folder.sh:129-134` (old folder must hold only the two zz files); `release/checklist.sh:166-178` (`note-about`: the not-affiliated note must be in a `main-*.js`); `Web/Public/Shell.cls:116-140` serves any file of the folder, `script-src 'self'` covers same-origin chunks.
- Node tests to touch: `web/scripts/settings-view.test.mjs:185-195` (pins the settings route text `{ matcher: settingsMatch, component: SettingsPage, ... }`; L39/L85-114 test `pageOf`, L197-205 `settingsMatch`, both imported from `settings-view.ts`); `web/scripts/ux-strings.test.mjs:41-77` `IMPORTED` and L1127-1132 (every `export const *_TEXTS` must be listed); comment headers `history-view.test.mjs:3` and `usage-view.test.mjs:4` ("imports only types").
- E2E: `web/playwright.config.ts:50` `SIGN_IN_2_DIRS` holds `settings` (project `sign-in-2` = unit `live:sign-in-2` = group `shards-4`, `ci/units.sh:146`). Helpers: `signInReadmeLoaded` (`e2e/support/floor.ts:252`), `NAV_LINKS_ADMIN` (`e2e/support/header-nav.ts:12`), console collection pattern `e2e/guide/guide.spec.ts:578-581` (no filter: a missing chunk shows as "Failed to load resource" and must fail), a second page in the signed-in context `e2e/history/history.spec.ts:180` (`copy.goto`). Pinning cases already there: `settings/settings.spec.ts` S1t L112 (title), S6 L325 (unsaved prompt); `history/history.spec.ts` H1 L121; `usage/usage.spec.ts` U1 L196; `settings/on-call.spec.ts` (36.4).
- Other specs that navigate to the three pages (regression surface): `e2e/banners/banners.spec.ts`, `e2e/frame/frame.spec.ts` (chromium, live:sign-in), `e2e/guide/more-to-try.spec.ts` (sign-in-3), `e2e/floor/browsers.spec.ts` (live:floor, three engines; L241-255 navigates to `#/history`), `e2e/demo-switch/z-settings-save.spec.ts` (live:demo-switch), `e2e/settings/{email,on-call,webhooks}.spec.ts` (sign-in-2).

## Tasks & Acceptance

**Execution:**
- `web/src/app/shared/page-shell-view.ts` (new) -- framework-free, erasable syntax, no imports: `SHELL_TEXTS` (`settingsTitle`, `historyTitle`, `usageTitle`, `unsaved`, `stay`, `leave`, the exact current strings, `·` escaped), `pageOf` and `settingsMatch` moved verbatim from `settings-view.ts` (with their doc comments). Doc comment: what the eager shell needs from the lazy pages, and that nothing under `settings/` (but the guard and its dialog), `history/` or `usage/` may be imported eagerly -- so the pages stay lazy chunks (DW-1282).
- `web/src/app/settings/settings-view.ts` -- `import { SHELL_TEXTS, pageOf, settingsMatch } from '../shared/page-shell-view.ts'`; `title`, `unsaved`, `stay`, `leave` reference `SHELL_TEXTS`; replace the two functions with `export { pageOf, settingsMatch }` (re-export, so every existing import and test keeps working); fix the doc comment (no longer "imports only types"; `pageOf` lives in page-shell-view).
- `web/src/app/history/history-view.ts`, `web/src/app/usage/usage-view.ts` -- `title: SHELL_TEXTS.historyTitle` / `usageTitle`, imported with the `.ts` extension; doc comments updated where they claim type-only imports.
- `web/src/app/settings/unsaved-dialog.ts` -- take its three texts from `SHELL_TEXTS` instead of `SETTINGS_TEXTS`.
- `web/src/app/header/current-page.ts` -- import `pageOf` from `../shared/page-shell-view`.
- `web/src/app/app.config.ts` -- the three rows become `loadComponent: () => import('./settings/settings-page').then((m) => m.SettingsPage)` (same for `history/history-page` `HistoryPage`, `usage/usage-page` `UsagePage`), titles from `SHELL_TEXTS`, `settingsMatch` from page-shell-view, matcher, guard, order and the Documents/wildcard rows unchanged; doc comment says the three pages load lazily and why.
- `web/package.json` -- build script ends `node scripts/brand.mjs && NG_BUILD_OPTIMIZE_CHUNKS=0 ng build` (reason in Design Notes; nothing else changes).
- `web/scripts/lazy-routes.test.mjs` (new, picked up by `node --test scripts/*.test.mjs`) -- (a) walks the static import graph from `src/main.ts` (relative `import ... from` and `export ... from`, skipping `import type`/`export type` and every `import(`) and asserts it reaches no file under `app/history/` or `app/usage/` and, under `app/settings/`, only `unsaved-guard.ts` and `unsaved-dialog.ts`; (b) asserts app.config.ts has exactly the three `loadComponent` rows with their titles, the settings row's matcher and `canDeactivate: [unsavedGuard]`; (c) reads `STALEFILES` from `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` and, while its hash class admits neither `_` nor `-`, asserts the build script sets `NG_BUILD_OPTIMIZE_CHUNKS=0`. Header comment states what it pins.
- `web/scripts/settings-view.test.mjs` -- update only the route-text pin (L189) to the `loadComponent` row; every other assertion unchanged.
- `web/scripts/ux-strings.test.mjs` -- add `['shared/page-shell-view.ts', ['SHELL_TEXTS']]` to `IMPORTED` (values already in SOURCES); fix the stale "imports only types" headers of `history-view.test.mjs` and `usage-view.test.mjs`.
- `web/e2e/settings/deep-link.spec.ts` (new; project sign-in-2) -- D1 `#/settings` and `#/settings/check-thresholds`, D2 `#/history`, D3 `#/usage`: sign the README admin in (`signInReadmeLoaded`), open a NEW page in the same context (a real document load at the hash), record `console` errors and `pageerror`s from before the goto, wait for the page's GET to answer 200, assert the matrix rows, then `reload()` and assert the same again; end with no error recorded. Self-contained, read-only (saves nothing).

**Acceptance Criteria:**
- Given this branch after the change, when `npm --prefix web run build` runs, then it succeeds with `maximumError` still `1MB`, prints an Initial total of at most 921 kB (expected about 879 kB), lists `settings-page`, `history-page` and `usage-page` under Lazy chunk files, every built `main-`/`chunk-`/`polyfills-`/`styles-` file name matches the installer's `STALEFILES`, and a `main-*.js` still holds the About dialog's not-affiliated note.
- Given the signed-in README admin, when each of `#/settings`, `#/settings/check-thresholds`, `#/history` and `#/usage` is opened by URL in a fresh page and then reloaded, then each renders as the matrix says, the header (`current-page.ts` `pageOf`, consumer of the new module) marks it current, and no console error or page error is logged (`deep-link.spec.ts` D1-D3).
- Given the existing node tests and the Playwright specs that open the three pages (settings/*, history, usage, banners, frame, more-to-try, floor/browsers, z-settings-save), when they run after the change, then they pass with no assertion changed but the settings route-text pin, including S6's unsaved prompt and on-call.spec.ts's On call section (Story 36.4) on the lazily loaded page.
- Given the bundle built by this change, when `live:bundle-folder` seeds it into the old folder and restarts, then the old folder holds only the two zz files (no chunk file left behind).

### Review Findings

Code review 2026-11-13 (four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 25 raw findings; 0 high, 1 medium, 6 low patched, 1 deferred to the ledger, 14 rejected). AC3 judged: S1/U1's web-first address reads are a legitimate test-only adaptation (a lazy route commits the hash with its content once the chunk loads; same final address, assertion no weaker). `NG_BUILD_OPTIMIZE_CHUNKS=0` and DW-1300 (wontfix-accepted, pinned by lazy-routes.test.mjs (c) and now by the built-name check) accepted. `initial-bundle.test.mjs` inside `npm --prefix web test` accepted: hermetic temp output, full suite 2000 pass in 14.5 s locally; CI builds it cold once more. Other lanes' `import('./roles-section')` / `import('./mcp-section')` become nested lazy chunks of the lazy Settings page; neither lane touches app.config.ts, the header, the guard, `pageOf`, `settingsMatch` or the moved strings.

- [x] [Review][Patch] (medium) The size pin summed only the files index.html names, and Angular writes at most 10 modulepreload links, so deeper initial chunks would go uncounted -- now follows static imports from the entry script through the chunks (as Angular counts its Initial total) and asserts every preloaded chunk is in that walk [web/scripts/initial-bundle.test.mjs:61]
- [x] [Review][Patch] (low) No automated check of built file names against STALEFILES or of the About note in a main-*.js (AC1) -- added to initial-bundle.test.mjs, reading STALEFILES from Web.cls and the note from about-dialog.ts [web/scripts/initial-bundle.test.mjs:84]
- [x] [Review][Patch] (low) initial-bundle.test.mjs header claimed it catches any page going eager and a warm cache in CI -- corrected (History alone stays under 921 kB; CI=true turns the cache off) [web/scripts/initial-bundle.test.mjs:1]
- [x] [Review][Patch] (low) The size build inherited the caller's other NG_BUILD_* variables -- dropped before the script's own are applied [web/scripts/initial-bundle.test.mjs:31]
- [x] [Review][Patch] (low) lazy-routes.test.mjs (b) history/usage/settings pins depended on each row staying on one line -- `[^}]*?` keeps them inside the row object [web/scripts/lazy-routes.test.mjs:105]
- [x] [Review][Patch] (low) settings-view.ts said the re-export is "for the page and its tests"; settings-page.ts uses neither function [web/src/app/settings/settings-view.ts:181]
- [x] [Review][Patch] (low) Doc drift: deep-link.spec.ts header said D1 to D3 (D4 exists); history-view.test.mjs header said the module imports types (it imports only page-shell-view.ts) [web/e2e/settings/deep-link.spec.ts:7]
- [x] [Review][Defer] The in-suite ng build could make the suite's wall-clock assertions flaky on a small hosted runner [web/scripts/initial-bundle.test.mjs:50] -- deferred: unverified (local full suite green); settled by a timing red in the ci web job's Unit tests step; DW-1302 wontfix-theoretical

Rejected:
- EC: D1/D4 hard-code On call, failing on a stack without on-call values -- false: sign-in-2's stack is not the online demo and D1 passed; settings.spec.ts S1 pins the same eight.
- EC/AA: no handler when a lazy chunk fails to load -- low, real; a handler needs new user-facing text (veto item); DW-1301 wontfix-accepted with reopen_if.
- EC: a failed chunk shows as a generic waitForResponse timeout -- low, diagnostics only after a failure is already reported.
- EC: lazy-routes (c) asserts nothing once STALEFILES admits `_`/`-` -- false: the flag is only needed while the pattern rejects them (by design).
- EC: concurrent ng builds share web/.angular -- low: local only (CI=true disables the cache), unlikely, no failure shown.
- VG: the size pin cannot catch the optimizer flag removed or History eager alone -- false: lazy-routes (a)/(c) pin those (recorded mutations).
- VG: `dialog toHaveCount(0)` before any action cannot fail -- false: a precondition that fails if any dialog is open on load; not a pinning assertion.
- AA: QA work is uncommitted at HEAD -- false as a code finding: stages may not commit; the lead commits.
- AA: AC3 wording vs the S1/U1 change -- low, by-design: disclosed in the Spec Change Log and judged legitimate; the fix would edit the spec.
- AA: SECTION_NAMES will need updating when 25.4/21.4 sections merge -- low: the e2e convention; whoever integrates second updates both lists.
- BH: Auto Run Result stale since QA -- fix edits the spec under review; this section records the QA additions.
- BH: QA additions overtake the Review Triage Log's BH4/VG2 reason -- fix edits the spec; recorded here.
- BH: CI builds twice and local npm test pays a build -- low: measured 14.5 s for the full suite locally; one cold build in a 15-minute job; reusing the in-place build would cost hermeticity.
- BH: the triage tally does not add up -- fix edits the spec.

## Spec Change Log

- 2026-11-13, implement stage: two existing e2e reads, `settings.spec.ts` S1 and `usage.spec.ts` U1, read `page.url()` right after the header-link click. A lazy route commits the hash only after its chunk loads, so both read `#/` (red). Decided in-stage (small, test-only): each read became the web-first `await expect(page, ...).toHaveURL(/#\/settings$/)` and `/#\/usage$/` (same expected address, now retried; the form `more-to-try.spec.ts` and S6 already use). AC3's "no assertion changed" holds for every other assertion; the app behaviour (the address ends at the page) is unchanged.

## Review Triage Log

### 2026-11-13 - Review pass
- verdicts: 24 findings (rows group members that share a root cause) - high 0, medium 0, low 17, false 7, maybe-false 0
- findings:
  - `[low]` `patch` BH7 doc drift: app.config.ts comment said the shell imports nothing else from settings/ "(but the guard)" while the dialog is also eager -- patched to "(but the guard and its dialog)"; the current-page.ts doc claim is not wrong (it lists the pages, not the module) -- not changed.
  - `[low]` `reject` BH1/EC1 no handler for a lazy chunk that fails after an upgrade -- Design Notes: FileCopy adds and never deletes in the live folder, so an open tab finds its own chunks; a handler would change behaviour.
  - `[false]` `reject` BH2/EC7 the env prefix is POSIX-only and works around STALEFILES -- the repo's scripts are bash, and widening STALEFILES is a server change the spec rules out (recorded under `deferred:`).
  - `[low]` `reject` BH3/VG1 test (c) pins source text, not built names, and AC4's mutation names (c) not live:bundle-folder -- the spec names (c) as AC4's pinning test and its mutation was run; AC1 asserts the built names and live:bundle-folder ran green; negligible.
  - `[low]` `reject` BH4/VG2 nothing locks the size win -- the unchanged 1MB `maximumError` fails the build on regrowth and (a)/(b) pin the graph; a tighter budget is an angular.json change the spec forbids.
  - `[low]` `reject` BH5/EC2/EC3/VG4 the regex import walker misses trailing comments, aliases, import-equals and has no export-from control -- no such form exists in the reached files; fixing means a parser, more than a direct correction.
  - `[low]` `reject` BH6/EC4/EC6/VG-other dangling waitForResponse and an unclosed page when a case fails first -- only noise after a failure already reported; negligible.
  - `[false]` `reject` BH6 the unsaved guard and Back are untested on a lazily loaded page -- S6, S6b and S6c ran green on the lazily loaded page (part 19/21).
  - `[false]` `reject` EC5 the new page may not carry the session -- D1-D3 passed with the session in the shared context.
  - `[low]` `reject` EC8 the claim that no assertion changed -- true except S1 and U1 (logged in the Spec Change Log); the code is right, a lazy route commits the hash after its chunk loads.
  - `[low]` `reject` VG3 header-marking (D1/D2) has no mutation of its own -- Rule 19 asks one mutation per AC and AC2's is recorded.
  - `[false]` `reject` VG-other banners.spec.ts:322 reads the hash right after a click -- the banner link is a plain href, so the hash is set synchronously; green in part 6/29.
  - `[low]` `reject` VG-other the route-text pin in settings-view.test.mjs now allows `\s*` between properties and overlaps (b); D1 hard-codes the eight section names (valid on sign-in-2's stack); lazy-routes.test.mjs reads Web.cls from outside web/ -- all accurate, none a defect (same pin text, the spec names the file, the node tests run from the repo checkout in CI).
  - `[false]` `reject` Intent-alignment: the diff implements the mechanism and tests the source graph, not the built size -- the build's Initial total (878.98 kB, at most 921) is a Verification command and the cap itself fails the build; descriptive only.

## Design Notes

**Governing ADs:** AD-13 (the shell serves every built file through `%CSP.StreamServer` with `script-src 'self'`, so same-origin lazy chunks need no server or policy change); AD-23 (the bundle folder and the installer's `RemoveOldBundle`/`STALEFILES`); AD-22 and the Consistency Conventions "Tests" row (Playwright specs under `web/e2e/`, CI units and groups); AD-29 (`web/` is Lane B's); the Conventions "Angular" row (standalone components, hash routing -- kept). No AD is contradicted.

**Measured (plan stage, scratch copy of this branch's `web/`, `ng build`, kB = 1,000 bytes):** today 1,007.44 kB (main 962.83 + styles 44.61). Three `loadComponent` routes with the views still eager: 909.83 kB. Plus the shell module (history/usage views out): 901.65 kB. Plus the dialog's texts in the shell module (settings-view out of the initial bundle): 889.87 kB with the optimizer on (lazy: settings-page 92.69, history-page 18.54, usage-page 13.16, two shared 10.45 / 4.60), **878.95 kB with `NG_BUILD_OPTIMIZE_CHUNKS=0`** (initial: main 280.90 + three chunks 233.35 / 221.05 / 99.03 + styles 44.61; lazy settings-page 90.25, history-page 18.11, usage-page 12.82, shared 10.44 / 4.58). The note-about string stayed in `main-*.js` in every variant. DW-1282: headroom under the cap goes from -7.44 kB to about +121 kB (target at least 50 kB; Planner target at most 921 kB) -- addressed in full.

**Decided in-stage:**
- Route-level `loadComponent` rather than the lanes' per-section `import()` pattern: the route row is the router's unit, one edit in `app.config.ts` moves the page and all eight sections (36.4's On call included) into one chunk, and per-section imports would mean eight edits inside `settings-page.ts`, the file lanes A and C edit, with `@defer`-style chunk overhead (measured worse for 36.4's section). The lanes' `import('./roles-section')` / `import('./mcp-section')` inside `settings-page.ts` keep working: they become nested lazy chunks of the lazy page, and `app.config.ts` is not in their diff. Whoever pushes second integrates forward (`settings-view.ts` is the one shared file with a small textual overlap).
- One eager module `shared/page-shell-view.ts` instead of keeping the view modules eager: the views pull 12 kB of history/usage code and the whole settings view (texts and form rules) into `main`. The view modules reference `SHELL_TEXTS` (no copy, Rule 2), and `settings-view.ts` re-exports `pageOf`/`settingsMatch` so no import elsewhere and no test changes.
- The guard stays eager and synchronous (its dialog takes its texts from the shell module) rather than `import()`-ing the dialog: same size (888.32 kB measured for the async variant), no change to when the prompt opens.
- Chunk optimizer off: with 3 or more lazy chunks Angular renames chunks with an `[A-Za-z0-9_-]` hash (measured `chunk-BAxI_vlj.js`); `STALEFILES` only matches `[A-Za-z0-9]`, so `live:bundle-folder` (group install-fresh) would go red on any build whose names hold `-` or `_`. Fixing the regex is a server change (ruled out), so the build keeps esbuild's base32 names; it also measured 11 kB smaller. `lazy-routes.test.mjs` (c) ties the flag to the regex; the regex gap is in `deferred:` for the lead.
- The deep-link spec is one file in `e2e/settings/` covering all three pages (project sign-in-2, unit `live:sign-in-2`, group `shards-4`): one spec per local command, no `ci/units.sh` change. A NEW page in the signed-in context is the deep link (a `goto` that only changes the hash would be a same-document navigation).
- After an in-place upgrade an open tab still finds its own chunk files (FileCopy adds, never deletes, in the live folder); no handling needed.

**Integration ACs (Rules 1/2):** the new module's consumers are `app.config.ts` (titles, matcher), `current-page.ts` (header marking, pinned by D1-D3's `aria-current`), `unsaved-dialog.ts` (S6) and the three view modules (ux-strings, settings/history/usage view tests).
- Consumes: Angular router `loadComponent`; Story 36.4's On call section, which rides on the lazy route (on-call.spec.ts).
- Consumed-by: Story 36.4's rework (rebased on the lazy routes, merges on top); Story 25.4 (Roles section, lane A) and Story 21.4 (MCP section, lane C) as lazy sections inside the lazy Settings page; every later page route (standing DW-1282 rule: new web code in lazy chunks). Recommended to the lead (Rule 20, its call): a Conventions note that page routes load with `loadComponent` and the shell imports only `page-shell-view.ts` from them.

## Verification

`<lane-b vars>` = `OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=36 stage=implement'`; fresh tag `e36s5i` (no warm stack: no IRIS class changes). One command per call, foreground, `timeout: 600000`, never two test calls in one message, never slot B. `<scratch>` is the stage's own scratch folder. At the end, also after a failure: `<lane-b vars> OCUTALON_RUN_TAG=e36s5i bash ci/iris.sh teardown`.

**Commands:**
- (loop) `npm --prefix web run build` -- expected: success; Initial total at most 921 kB (about 879); the three named lazy chunks. (~20 s)
- (loop) `node --test web/scripts/lazy-routes.test.mjs`, then the same for `settings-view.test.mjs`, `ux-strings.test.mjs`, `history-view.test.mjs`, `usage-view.test.mjs`, one call each -- expected: pass.
- (loop) `npm --prefix web run lint` -- expected: pass.
- (once) `ls src/ocutalon/csp | grep -E '^(main|chunk|polyfills|styles)-' | grep -vE '^(main|chunk|polyfills|styles)-[A-Za-z0-9]+\.(js|css)(\.map)?$'` -- expected: no output; and `grep -l 'OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.' src/ocutalon/csp/main-*.js` -- expected: one file.
- (once) `npm --prefix web test` -- expected: pass. `bash docker/tests/test-ci-config.sh` and `bash docker/tests/test-boundaries.sh` -- expected: pass.
- (once) `bash docker/tests/test-web-build.sh` -- expected: all PASS (fresh-copy build through the new script; about 1-2 min).
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s5i bash ci/iris.sh build` -- before any browser unit (Rule 21).
- (once) Part finding, no stack: `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json > <scratch>/l2.json`, then `node web/scripts/e2e-part.mjs k/n <scratch>/l2.json` until a PART names only `settings/deep-link.spec.ts`; likewise one part per file for `settings/{settings,on-call,email,webhooks}.spec.ts`, and with `e2e` (chromium) for `history/history.spec.ts`, `usage/usage.spec.ts`, `banners/banners.spec.ts`, `frame/frame.spec.ts`, with `e2e:sign-in-3` for `guide/more-to-try.spec.ts`.
- (loop) `<lane-b vars> OCUTALON_RUN_TAG=e36s5i bash ci/iris.sh live sign-in-2 --part k/n` (the deep-link part; about 93 s setup + the spec, ~150 s) -- expected: D1-D3 pass.
- (once) the same command for each other sign-in-2 part found above, and `live sign-in --part k/n` / `live sign-in-3 --part k/n` for theirs, one part per call -- expected: pass. A part is one whole file and cannot be cut below it; one over ~150 s still runs as one foreground call.
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s5i bash ci/iris.sh live bundle-folder` -- expected: all checks passed (about 75 s locally).
- (once) `<lane-b vars> OCUTALON_RUN_TAG=e36s5i bash ci/iris.sh live floor` (about 240 s, no --part; Chromium, Firefox, WebKit) and `live demo-switch` -- expected: pass.

**Shared surfaces:** the route table in `app.config.ts` (and its pin in `settings-view.test.mjs`); `pageOf` / `current-page.ts` and the header navigation's `aria-current`; `unsavedGuard`/`unsaved-dialog.ts`; `SETTINGS_TEXTS`, `HISTORY_TEXTS`, `USAGE_TEXTS` values and `ux-strings.test.mjs` `IMPORTED`; every e2e spec that navigates to /settings, /history, /usage (Code Map list); the initial-bundle budget and Initial total; the bundle's file names (`STALEFILES`, `live:bundle-folder`, `release/checklist.sh` note-about). Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; one per AC; record each as `mutation: <change> -> <red test>` and restore the tree byte-identical):**
- AC1: make History eager again (`import { HistoryPage }` + `component: HistoryPage`) -> `lazy-routes.test.mjs` (a)/(b) red, and the build's Initial total rises (record it).
- AC2: point the usage row's `loadComponent` at `HistoryPage` -> `deep-link.spec.ts` D3 red.
- AC3: drop `canDeactivate: [unsavedGuard]` from the settings row -> `settings.spec.ts` S6 red (its part).
- AC4: remove `NG_BUILD_OPTIMIZE_CHUNKS=0` from the build script -> `lazy-routes.test.mjs` (c) red (and the build emits `_`/`-` chunk names).

mutation: AC1, History made eager again (`import { HistoryPage }` + `component: HistoryPage` in app.config.ts) -> `lazy-routes.test.mjs` "no static import from the entry point reaches the History or Usage code" (a) and both `the routes` tests (b) red; the build's Initial total rose from 878.98 kB to 899.79 kB
mutation: AC2, the usage row's `loadComponent` pointed at `HistoryPage` -> `deep-link.spec.ts` D3 red (settings/deep-link part 12/15 of sign-in-2; D1 and D2 stay green)
mutation: AC3, `canDeactivate: [unsavedGuard]` dropped from the settings row -> `settings.spec.ts` S6 red (also S5b, S6b and S6c; part 19/21 of sign-in-2)
mutation: AC4, `NG_BUILD_OPTIMIZE_CHUNKS=0` removed from the build script -> `lazy-routes.test.mjs` (c) "stay inside the installer pattern while the optimizer is the only thing that keeps them there" red; the build emitted chunk-DxAZbMhD.js, chunk-K_0tuUr6.js and others with `_`/`-` names (Initial total 889.90 kB)

QA stage (tests only, nothing else changed; lane B, tag e36s5q, torn down):
- `web/scripts/initial-bundle.test.mjs` (QA, new): builds the app into a temporary folder (never src/ocutalon/csp/) with the flag of package.json's build script and asserts the files that the built index.html loads up front total at most 921,000 bytes (measured 878.98 kB). `node --test web/scripts/initial-bundle.test.mjs` passes (~2 s warm, ~20 s cold); `npm --prefix web test` 1999 pass.
- `web/e2e/settings/deep-link.spec.ts` D4 (QA, added to the implement stage's file): the unsaved-changes guard on the Settings page opened by address (section link and page link ask, Stay keeps the section and value, Leave goes on). `live sign-in-2 --part 12/15` (deep-link + email): 10 passed.
- Gap review: the sub-section deep link after a reload is already pinned by D1 (`#/settings/check-thresholds`, then `reload()`); S6/S6b/S6c/S5b pin the guard on the lazily loaded page reached by link presses; neither was duplicated.
mutation: AC1 size, Settings made eager again (`import { SettingsPage }` + `component: SettingsPage` in app.config.ts) -> `initial-bundle.test.mjs` "holds at most 921 kB of files that the page loads up front" red (initial total 978.35 kB over 921 kB, walked from the entry script; code review re-run 2026-11-13); History eager alone (899.79 kB) stays under the cap and is the import-graph pin's job
mutation: AC1/AC4 built names, `NG_BUILD_OPTIMIZE_CHUNKS=0` removed from the build script -> `initial-bundle.test.mjs` "names every bundle file as the installer's STALEFILES pattern expects" red (chunk-BLoI6j-L.js, chunk-DSUlC_sP.js; code review 2026-11-13)
mutation: AC3 guard on a deep-linked page, `canDeactivate: [unsavedGuard]` dropped from the settings row -> `deep-link.spec.ts` D4 red ("a section link asks first"; D1-D3 and email stay green)

## Auto Run Result

Status: done
Blocking condition: none

Summary: the Settings, History and Usage routes load with `loadComponent`; the facts the eager shell needs (three titles, the unsaved prompt's strings, `pageOf`, `settingsMatch`) moved into `shared/page-shell-view.ts`, which the view modules reference; the build runs with `NG_BUILD_OPTIMIZE_CHUNKS=0` so every chunk name matches the installer's STALEFILES. Measured Initial total 878.98 kB (was 1,007.44 kB; `maximumError` still 1MB; lazy: settings-page 90.25, history-page 18.12, usage-page 12.82 kB).

Files changed: `web/src/app/shared/page-shell-view.ts` (new eager module); `web/src/app/app.config.ts` (lazy rows); `web/src/app/settings/{settings-view,unsaved-dialog}.ts`, `history/history-view.ts`, `usage/usage-view.ts`, `header/current-page.ts` (reference the module); `web/package.json` (build flag); `web/scripts/lazy-routes.test.mjs` (new graph/route/flag pin); `web/scripts/{settings-view,ux-strings,history-view,usage-view}.test.mjs` (route-text pin, IMPORTED, headers); `web/e2e/settings/deep-link.spec.ts` (new D1-D3); `web/e2e/settings/settings.spec.ts` S1 and `web/e2e/usage/usage.spec.ts` U1 (address read made web-first, see the Spec Change Log).

Review: 24 findings from four layers; 1 patched (a doc comment), 23 rejected with recorded reasons (see the Review Triage Log); 0 deferred beyond the STALEFILES item already in `deferred:`. Follow-up review recommended: false (no high, one low patched).

Verification: `npm --prefix web run build` Initial total 878.98 kB; lazy-routes, settings-view, ux-strings, history-view, usage-view node tests, lint and `npm --prefix web test` (1998) pass; built names match STALEFILES and the not-affiliated note sits in `main-*.js`; test-ci-config, test-boundaries and test-web-build pass; lane-B throwaways (tag e36s5i, torn down): live sign-in-2 (deep-link with email, on-call, webhooks, settings 19/21 after the S1 fix), live sign-in (history, banners, frame, usage 28/29 after the U1 fix), sign-in-3 more-to-try, bundle-folder, floor (three engines), demo-switch all pass. Four mutations recorded under `## Verification`.

Residual risks: a hash read straight after a click on a link that becomes a `routerLink` to a lazy page races the chunk load (S1 and U1 were two such reads). The STALEFILES gap stays deferred. new_units: none.
