---
title: 'Story 33.3: Epic 33 burn-down'
type: 'bugfix'
created: '2026-11-04'
status: 'done'
baseline_revision: '58ecea1eea2b9302f0df94b10a5242f29bfa79ae'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-33-context.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** A saved demo mode reaches an open chat page only after a reload (DW-699), yet the Demo mode section confirms with the shared saved text, so the admin may think the switch failed.

**Approach:** The Demo mode section alone gets its own confirmation key with the ruled text (AC 1). Check thresholds keeps the shared text. No live refresh (DW-707, later).

## Boundaries & Constraints

**Always:** the new text verbatim from Story 33.3's AC, shown and announced where the shared text is today; Lane B web files only.

**Never:** any other new or changed text; a live refresh, event, `/state` or server change; an IRIS class, `EXPERIENCE.md`, `docker/**` or Lane A edit; a change to `z-settings-save.spec.ts`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Demo mode saved | 200 on `POST /v1/settings/demo-mode` | `p.saved` and one announcement hold the new text | No error expected |
| Thresholds saved | 200 on `POST /v1/settings/check-thresholds` | `p.saved` is exactly the shared text | No error expected |

</intent-contract>

## Code Map

- `web/src/app/settings/settings-view.ts:32` -- `SETTINGS_TEXTS.saved`.
- `web/src/app/settings/demo-mode-section.ts:21,160,224` -- doc, `savedText`, the announcement.
- `web/scripts/ux-strings.test.mjs:466` -- `SOURCES.ac`, keyed by story.
- `web/e2e/settings/settings.spec.ts:13,31` -- `SAVED`; `savedText` matches by substring, so the new text matches too. S7 (:403), S7b (:428): route-stub pattern. `recordAnnouncements`: `web/e2e/support/page.ts:56`.

## Tasks & Acceptance

**Execution:**
- `web/src/app/settings/settings-view.ts` -- add `demoSaved` after `saved`; one header line naming its source (Story 33.3's AC) -- DW-699.
- `web/src/app/settings/demo-mode-section.ts` -- `savedText` and the announcement use `demoSaved`; update the doc's 200 line -- DW-699.
- `web/scripts/ux-strings.test.mjs` -- one `ac` entry holding the new text, keyed `'Story 33.3: Epic 33 burn-down (the Demo mode section\'s own confirmation, DW-699)'`.
- `web/scripts/settings-view.test.mjs` -- assert `demoSaved` exactly and `saved` unchanged.
- `web/e2e/settings/settings.spec.ts` -- S2 adds `expect(page.locator('p.saved')).toHaveText(SAVED)`; new S7c: `recordAnnouncements`, open Demo mode, route the POST to 200 `{"result":"done","sections":{"demo-mode":{"demoMode":<toggled>}}}`, toggle, save, `p.saved` `toHaveText(DEMO_SAVED)` and the announcements hold it; unroute in `finally`; add S7c to the header's case list.

**Acceptance Criteria:**
- Given an admin on the Demo mode section, when a save of the switch succeeds, then the section shows and announces "Saved. Applies within a minute. Recorded in the audit log. Reload the chat page after a minute to see the change." (DW-699)
- Given the Check thresholds section, when a save succeeds, then it shows exactly "Saved. Applies within a minute. Recorded in the audit log.", and no other section's text changes.
- Given the tests, when they run, then `ux-strings.test.mjs` covers the new key and `settings.spec.ts` pins both texts (S7c, S2).

## Spec Change Log

## Review Triage Log

### 2026-11-04 -- Review pass
- verdicts: 7 findings -- high 0, medium 0, low 4, false 3, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind 1, no component test ties the section to `demoSaved` -- S7c asserts both the shown text and the announcement in a real browser, and the live mutation (section back on `saved`) turned S7c red.
  - `[low]` `[reject]` Blind 2, "announced once" is a poll that passes at the first reading of 1 -- the display and the announcement are one handler call in `demo-mode-section.ts`, so a later duplicate has no path; a settle-and-recheck would add a wait for a case with no route.
  - `[false]` `[reject]` Blind 3, no check that `demoSaved` is absent on the pending-edit and 409 paths -- those branches are untouched by the diff (they never reach the saved text), and S7b already pins the 409 text.
  - `[false]` `[reject]` Blind 4, the 409 path gives no reload hint -- the intent limits the new text to the saved confirmation and forbids any other new text; spec-bound, by design.
  - `[low]` `[reject]` Blind 5, the sentence is spelled out in five places -- the tests state the text literally on purpose, so a drift in `demoSaved` turns them red; deriving it from `SAVED` would weaken the pin.
  - `[low]` `[reject]` Blind 6, the e2e file header still opens "Story 33.2" -- the header's case list now names S7c as the spec's task asks; a rename is cosmetic.
  - `[low]` `[reject]` Edge 1, the same claim as Blind 2 -- rejected for the same reason.

## Design Notes

**Governing ADs (Rule 6):** AD-12 (the page decides nothing; no live refresh added), AD-13, AD-22, AD-29 (Lane B files), AD-32 (wording from the planning documents). No conflict; no NFR tripwire.

**Ledger (Rule 17):** DW-699 addressed by the first two tasks and AC 1.

**Rule 1/2:** no new service or module. Consumes: 33.2's Demo mode section and `SETTINGS_TEXTS`. Consumed-by: none (DW-707 may drop the reload sentence). `demoSaved` is a sibling key of `saved`; no new helper.

**Decided in-stage:**
- `demoSaved` lives in `SETTINGS_TEXTS`, not `Catalog.Core`: the page's settings texts live there (33.2) and the server never renders it.
- Source kind `ac`: epics.md states the text verbatim and `EXPERIENCE.md` does not hold it, so no `EXPERIENCE.md` row.
- S7c stubs the 200 like S7 and S7b: a real switch would change the mode the part's other specs read. The real-path save stays in `z-settings-save.spec.ts` (substring locator still matches; unchanged, not re-run).

## Verification

Each `ci/iris.sh` call sets `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=33 stage=implement' OCUTALON_RUN_TAG=e33s3i` and `timeout: 600000`; `ci/iris.sh teardown` with the tag after each live run, also after a failure.

**Commands:**
- (loop) `node --test web/scripts/settings-view.test.mjs web/scripts/ux-strings.test.mjs` -- expected: pass.
- (loop) `npm --prefix web run build` -- expected: pass; it writes the bundle the live run serves.
- (once) `ci/iris.sh live sign-in --part 3/3` -- expected: pass; part 3 holds `settings/settings.spec.ts` (`e2e-part.mjs` on Playwright's listing).
- (once) `bash docker/tests/test-boundaries.sh` -- expected: pass.

**Shared surfaces:** `SETTINGS_TEXTS` (the `ux-strings` inventory and `SOURCES`, `settings-view.test.mjs`); the Demo mode saved line (`z-settings-save.spec.ts`, substring, unchanged).

**Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning tests (Rule 19; implement writes each `mutation:` line):** AC 1 -> S7c, mutation: the section uses `saved`; AC 2 -> S2, mutation: thresholds use `demoSaved` (both in one extra `live sign-in --part 3/3`, exactly S2 and S7c red, restored from backup, `git status --short` unchanged, bundle rebuilt); AC 3 -> `ux-strings.test.mjs`, mutation: drop the `ac` entry; exact text -> `settings-view.test.mjs`, mutation: change one word of `demoSaved`.

**Mutation results (observed at implement):** `mutation:` the section uses `saved` and thresholds use `demoSaved` -> `live sign-in --part 3/3` red on exactly S2 and S7c (71 passed, 2 failed); `mutation:` drop the `ac` entry -> `ux-strings.test.mjs` red ("has an entry for every inventory string"); `mutation:` `demoSaved` ends "after an hour" -> `settings-view.test.mjs` red. Each restored from a backup in the scratchpad; the diff was byte-identical afterwards, and the bundle was rebuilt.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** The Demo mode section shows and announces its own confirmation (`demoSaved`, the ruled text verbatim); Check thresholds keeps `saved`. No other text, server, IRIS, Lane A or stability-watch file changed.

**Files changed:**
- `web/src/app/settings/settings-view.ts` -- `SETTINGS_TEXTS.demoSaved` and a header line naming its source.
- `web/src/app/settings/demo-mode-section.ts` -- `savedText` and the announcement use `demoSaved`; doc updated.
- `web/scripts/ux-strings.test.mjs` -- one `ac` entry for the new text.
- `web/scripts/settings-view.test.mjs` -- asserts `demoSaved` exactly.
- `web/e2e/settings/settings.spec.ts` -- S2 pins the shared text exactly; new S7c pins the Demo text shown and announced.

**Review:** 0 patches applied, 0 deferred, 7 findings rejected (reasons in the triage log). Follow-up review recommended: false (nothing patched).

**Verification:** `node --test` of settings-view and ux-strings, 25 pass; web build passes; `ci/iris.sh live sign-in --part 3/3` 73 passed (S2 and S7c included); `docker/tests/test-boundaries.sh` all rules passed. Mutations: section on `saved` plus thresholds on `demoSaved` turned exactly S2 and S7c red; dropping the `ac` entry and changing one word of `demoSaved` turned the two node tests red; each restored byte-identical.

**Residual risks:** none known. The real-stack save in `z-settings-save.spec.ts` matches by substring and was not re-run (unchanged, per the spec).
