---
title: 'Story 11.19: Seeded check rows stay out of the heartbeat''s way unless a case asks for the real watch'
type: 'bugfix'
created: '2026-11-02'
status: 'done'
baseline_revision: '2a6f1677d09a92c0c90bc7341ba2dab7ace71b67'
baseline_commit: '2a6f1677d09a92c0c90bc7341ba2dab7ace71b67'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Browser specs seed check rows and then assert the seeded last run, result and finding. A real heartbeat tick runs every production row that is due and overwrites those fields, so the assertions flake (DW-349, 23 occurrences across every epic's CI). Story 11.1 gave `Test.Data.Fixture.Check` a default `NextDueAt` of now plus `CHECKAHEAD` (3600 s) on this branch, and `Test.Data.FixtureDefaults` pins it on the IRIS side. Nothing on the web side pins that every seeding path relies on that default. Nothing stops a later spec from making a row due without saying so, or from storing a check row some other way.

**Approach:** Task 0 (done at plan, below) traced every path that stores a check row for the browser specs. Every one goes through `Fixture.Check` with no `NextDueAt`, or with a time an hour ahead, so no seeding code changes. The story adds one source-reading node test, `web/scripts/check-seeds.test.mjs`, which `npm --prefix web test` finds. The test pins five things:
- `seedCheck` adds no due time of its own.
- An empty `nextDueAt` is still passed through, as the opt-in.
- Every opt-in has a `real watch` comment.
- Direct `Fixture.Check` calls pass no `NextDueAt` unless they carry the same comment.
- No e2e source stores a check row any other way.

It also writes the opt-in rule into `CheckFields.nextDueAt`'s doc comment. The fix lands with Epic 11 part 1, which carries 11.1's IRIS default to the integration branch.

## Boundaries & Constraints

**Always:**
- Edit only `web/scripts/check-seeds.test.mjs` (new) and the doc comment of `CheckFields.nextDueAt` in `web/e2e/support/iris.ts`.
- The IRIS default (`CHECKAHEAD = 3600`, set before `SetFields`) and its pin, `FixtureDefaults.TestCheckIsNotDue`, stay as they are.
- The test reads web source files only. It needs no stack, creates and removes nothing, and passes in any order and on a fresh checkout.
- Every assertion message names the file, and the line where the offence has one.
- Comments state the contract (Rule 14). Source is ASCII.

**Never:**
- Edit any spec file, including `banners.spec.ts`, `heartbeat.spec.ts` and `session.spec.ts`. Task 0 found none that needs it.
- Touch `docker/tests/lib-live.sh` or the Telegram specs (Epic 12).
- Touch `ci/units.sh`, `.github/workflows/*`, a CI job name or the iris matrix, or add a CI unit.
- Change product code (`Checks.Process`, `Watch.Ops`) or `Test.Data.Fixture`.
- Read IRIS sources from the web test.
- Work on DW-578 (banners B15 timeout), a separate flake class.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Default | `seedCheck(user, {...})` with no `nextDueAt` (13 calls in specs, plus `support/floor.ts` `seedFullPage`) | The script's fields object has no `NextDueAt`, so `Fixture.Check`'s hour-ahead default applies. The pin passes. | none |
| Explicit time | heartbeat H1 `nextDueAt: inMs(NEXT_DUE_MS)` (an hour ahead) | The time is passed as given. The pin passes: a non-empty time is the case's own choice. | none |
| Opt-in, marked | `nextDueAt: ''` with a `//` comment naming `real watch` on the same line or the comment lines directly above | `NextDueAt: ""` is passed and the row is due at the next tick. The pin passes. | none |
| Opt-in, unmarked | `nextDueAt: ''` (or `""`) with no such comment | The pin goes red. | The message names file:line. |
| Direct call | session.spec.ts S1 `Fixture).Check(s.Ref)` and S8 `Check(sN.Ref,"ZZNS",prod)` | They pass no fields, so the default applies. The pin passes. A `NextDueAt` on such a line without the marker is red. | The message names file:line. |
| Bypass | Any `web/e2e` or `web/e2e-online` `.ts` file whose code holds `BackgroundCheck).%New`, `INSERT INTO OcuTalon_Data.BackgroundCheck` or `UPDATE OcuTalon_Data.BackgroundCheck` (a `DELETE` is allowed) | The pin goes red. | The message names the file. |

</intent-contract>

## Code Map

- `web/e2e/support/iris.ts:835-877`: `CheckFields` and `seedCheck`.
  - `NextDueAt: fields.nextDueAt` (:864) goes through `properties()` (:670-672), which drops `undefined` and keeps `""`.
  - `Fixture.Check` gets the result through `fieldsObject(row)` (:870).
  - The doc comment of `nextDueAt` (:846-850) already cites DW-349. This story adds the opt-in rule there.
- `web/e2e/support/iris.ts:883`: `publishCheck` only publishes a `check` event through `Live.Publish`. It stores no row, so it is not a seeding path.
- `web/scripts/source-files.mjs`: reuse `sourceFiles(root, ['.ts'])` (name, text, code) and `code()` (strips comments). Extend, don't copy (Rule 2). The marker check reads `text`. The call and bypass checks read `code`.
- `web/scripts/floor-fixtures.test.mjs`: the sibling. It is a source-reading ratchet over the e2e helpers (`calls()` and per-file loops). Follow its shape.
- Read only:
  - `src/ocutalon/cls/OcuTalon/Test/Data/Fixture.cls:19,70-83`: `CHECKAHEAD` and `Check`.
  - `src/ocutalon/cls/OcuTalon/Test/Data/FixtureDefaults.cls`: the IRIS pin.
  - `src/ocutalon/cls/OcuTalon/Checks/Process.cls:289-301`: `Due`. A row is due when its `NextDueAt` is `""` or no later than the tick time plus 5 s. `Tick` uses `TickAt`, else now.
  - `src/ocutalon/cls/OcuTalon/Test/Schedule/StallFixture.cls:98`: `Tick()` writes a real tick at now, never in the future.
  - `src/ocutalon/cls/OcuTalon/Watch/Ops.cls:97`: a real watch is due at creation.

## Tasks & Acceptance

**Execution:**
- `web/e2e/support/iris.ts`: extend the doc comment of `CheckFields.nextDueAt`. Leave it unset for a row no tick runs (`Fixture.Check`'s default, an hour ahead). `""` is the opt-in for a case that wants the real watch to run the row, and that case says `real watch` in a `//` comment on the call's line or directly above it. `web/scripts/check-seeds.test.mjs` pins this. No code change.
- `web/scripts/check-seeds.test.mjs` (new): a header saying what it pins, then three `describe` blocks over `sourceFiles` of `web/e2e` and `web/e2e-online`.
  - (a) `seedCheck` adds no due time of its own. Its body (the code from `export async function seedCheck` to the next `export`) holds exactly one `NextDueAt`, as `NextDueAt: fields.nextDueAt,` with no `??` or `||`. It calls `Fixture).Check(` with `fieldsObject(row)`. `properties()` filters on `!== undefined` only, so `""` is kept.
  - (b) Opt-ins say so. Every line whose code holds `nextDueAt:` with an empty literal (`''`, `""` or two backticks), and every line holding `Fixture).Check(` whose code mentions `NextDueAt`, has `real watch` (case-insensitive) in a comment on that line or in the contiguous `//` or `*` comment lines directly above it.
    - Non-vacuity: `seedCheck(` calls (imports not counted) are found in each of answers/close-loop, banners, floor/focus, floor/guide, rail, trace/links, heartbeat and `support/floor.ts`.
    - Direct `Fixture).Check(` calls are found in `session/session.spec.ts`.
  - (c) No bypass: no file's code matches the bypass patterns of the matrix.
- `_bmad-output/implementation-artifacts/spec-11-19-...md`: record the Verification results and the mutation lines.

**Acceptance Criteria:**
- Given the story's tree, when `npm --prefix web test` runs, then `check-seeds.test.mjs` runs in it and passes. An unset `nextDueAt` reaches `Fixture.Check` with no `NextDueAt`, so the row gets the hour-ahead default (pinned on IRIS by `FixtureDefaults.TestCheckIsNotDue`, Story 11.1). (DW-349, AD-18)
- Given a spec that passes an empty `nextDueAt` or a direct `NextDueAt` without a `real watch` comment, or a source that stores a check row without `Fixture.Check`, when `npm --prefix web test` runs, then the pin goes red and names the file (and the line for an opt-in).
- Integration (Rule 1; consumers are the seeded specs): Given the story's tree on a fresh lane-A throwaway, when the sign-in unit (the chromium project, which excludes floor/ and answers/; CI's floor and answers units cover those seeds) runs in two parts, then:
  - banners B2/B7, rail R4/R5, session S1/S8, heartbeat H1 and trace links pass, and no seeded row shows a finding it was not seeded with ("No read access to its namespace").
  - Any red is recorded with its spec and case. A red outside DW-349's class (for example DW-578) is not this story's.
- Given the story's diff since `story_base`, when listed, then it holds only `web/scripts/check-seeds.test.mjs`, `web/e2e/support/iris.ts` and this spec: no spec file is edited.

## Spec Change Log

## Review Triage Log

### 2026-11-02 - Review pass
- verdicts: 14 rows (findings reported by more than one layer share a row) - high 0, medium 2, low 12, false 0, maybe-false 0
- findings:
  - `[medium]` `[patch]` (verification-gap) the `properties()` pin accepted a filter that also drops `''`, so the opt-in could silently stop working - the regex is now anchored on the whole filter expression; a mutation drops `''` and the pin goes red.
  - `[medium]` `[patch]` (verification-gap) `fieldsObject()` was outside the "adds no due time" pin - a new test pins `fieldsObject` as `JSON.stringify(properties)` alone; a mutation that injects `NextDueAt` makes it red.
  - `[low]` `[patch]` (blind, edge-case) the doc comment said the marker goes on "the call's line" while the pin checks the `nextDueAt` line or the lines above it, and a multi-line call is checked at the `nextDueAt` line - the doc comment now says "on the `nextDueAt` line or directly above it".
  - `[low]` `[patch]` (edge-case, blind) a quoted key `'nextDueAt': ''` escaped the empty-value match - the regex takes an optional quote; a sample pins it.
  - `[low]` `[reject]` (blind, edge-case) "not a real watch" satisfies the marker - a keyword marker is the decided form (Decided in-stage 1); no reachable spec writes that.
  - `[low]` `[reject]` (verification-gap, edge-case, intent) a past or "now" non-empty time, a variable, a `?? ''`, or a multi-line `Fixture.Check` fields object is not flagged - Decided in-stage 2 and the matrix limit the pin to literal empty values and same-line direct calls; the heartbeat H1 time is the case's own choice.
  - `[low]` `[reject]` (blind, edge-case, verification-gap) bypass patterns miss `%OpenId`/`%Save`, `INSERT OR UPDATE`, global writes - the matrix names exactly three patterns; no source in e2e or e2e-online uses any other route (grep: only `rowCount` and one DELETE name the table).
  - `[low]` `[reject]` (edge-case, blind) `web/e2e-rehearsal` and non-`.ts` files are not scanned - the folder holds no `seedCheck`, `Fixture.Check` or `BackgroundCheck` reference (grep), and the spec names `web/e2e` and `web/e2e-online`.
  - `[low]` `[reject]` (blind, edge-case) a stray `/*` in a string, or `//` in a template literal, can hide code from `code()` - the same comment stripping serves every source ratchet in `web/scripts/`; no such text sits in the scanned sources.
  - `[low]` `[reject]` (blind, verification-gap) the non-vacuity list names eight files - the spec requires exactly these; a rename turns the test red, which is the point.
  - `[low]` `[reject]` (edge-case) `properties()` renamed gives a misleading failure - the failure names iris.ts and the function; the message is enough.
  - `[low]` `[reject]` (blind) the spec's Auto Run Result read `ready-for-dev` mid-run - finalize rewrites it; (verification-gap) mutation lines for each sub-assertion - one mutation per AC is the rule, and the two patched pins now carry one each.
  - `[low]` `[reject]` (edge-case) the describe title "no e2e source stores a check row except through Fixture.Check" overclaims for product code a spec calls - the title is scoped to e2e sources by its own words.
  - `[low]` `[reject]` (intent-alignment, descriptive) the pin reads source text, not runtime values - this is the reading the Approach states (a source-reading node test); the runtime half is `FixtureDefaults.TestCheckIsNotDue` and the sign-in unit.

## Design Notes

**Governing ADs (Rule 6):**
- AD-18: `Checks` runs every check whose next-due time has passed, recording its last run and result. It is the overwrite this story keeps away from seeded rows.
- AD-15: the watch chain. The real watch of demo-path 02 and 04 stays the product path, with no seeding.
- AD-22: the testing and CI rules. No CI unit is added.
- AD-29: lanes and files. The story stays inside Lane A's footprint.

**Task 0: every path that stores a check row for a browser spec (read at HEAD `1a1eb571`):**

| Path | How it stores | Not-due default? |
|---|---|---|
| answers/close-loop:371, banners:220/446/447/948, floor/focus:160, floor/guide:164, rail:200/221/429/677, trace/links:290/291 | `seedCheck`, no `nextDueAt` | yes, from IRIS |
| `support/floor.ts:188` `seedFullPage` (floor/keyboard, scan, words) | `seedCheck`, no `nextDueAt` | yes |
| heartbeat:99 | `seedCheck` with `nextDueAt` now + 1 h (Story 8.2; its `NEXT_DUE_MS` doc says why) | not due, explicitly |
| session:69 (S1), :304 (S8) | direct `Fixture).Check(s.Ref)` and `(sN.Ref,"ZZNS",prod)`, no fields | yes |
| `publishCheck` (banners, rail, focus, guide) | an event only, no row | n/a |
| demo-path 02-watch / 04-incident, `web/e2e-online` | the real watch through the chat (`Watch.Ops`, due at creation), no seed | relies on the real watch, and 02 says so ("The real last run (DW-202)") |
| `support/guide.ts`, `demo-path.ts`, `devices.ts` and `Test.Demo.Production` methods reached from a spec | none stores a check row (`FixtureSession` is unit-test only) | n/a |
| ticks | the minute task and `StallFixture.Tick()` tick at now, never in the future | an hour ahead is never due |

No browser path bypasses the default, and no spec passes `""` today. DW-349's remaining reds come from 11.1's default not yet being on the integration branch. IRIS unit tests that seed through `Fixture.Check` (`GuideRefresh.TestHeldLock*`, `GuideApi`) get the same default. `Test.Checks.Runs` passes `""` on purpose.

**Decided in-stage:**
1. **The marker is the words `real watch` in a comment on or directly above the call.** It is the smallest checkable form of "says so".
2. **Only literal empty values are checked.** An explicit non-empty time, as in heartbeat H1, is the case's own choice and is not flagged.
3. **The web test reads no IRIS source.** `ci/units.sh`'s web input pattern does not cover `Test/Data/`, so such a read could go stale silently. The IRIS half stays with `FixtureDefaults`.
4. **heartbeat.spec.ts is not simplified to rely on the default.** It is outside the footprint and harmless.

**Integration ACs, Consumes and Consumed-by (Rules 1 and 2):** no new service. The story pins an existing helper contract.
- **Consumes:** Story 11.1's `Fixture.Check` default.
- **Consumed-by:** every browser spec that seeds checks (the Task 0 table) on every epic's CI after Epic 11 part 1 merges. The integration evidence is the sign-in unit above, then CI's `browser` and `shards` groups on the merged head.

**Ledger inbox (Rule 17): DW-349, addressed.** At adjudication it resolves to `resolved-by:11-19-...`, with this evidence:
- the pin;
- `FixtureDefaults`;
- the Task 0 table;
- the sign-in parts.

If a seeded case still flakes for another reason, that part stays open with `owner=burndown`, and the note names the case. DW-578 is out of scope.

**Contended paths:** `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` touches `web/e2e/support/iris.ts`, `web/scripts/check-seeds*` and `Test/Data/Fixture.cls` only on `OCT-epic11`.

## Verification

Run every command from the worktree root, each in its own foreground call with `timeout: 600000`. `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'`.

**Commands:**
- `(loop)` `node --test web/scripts/check-seeds.test.mjs`. Expected: every test passes.
- `(once)` `npm --prefix web test`. Expected: exit 0.
- `(once)` `npm --prefix web run lint`. Expected: exit 0.
- `(once)` `bash docker/tests/test-boundaries.sh`. Expected: exit 0.
- `(once)` `LANE ci/iris.sh build`, only if `web/` changed since `src/ocutalon/csp/` was built. Then `LANE ci/iris.sh live sign-in --part 1/2`, then `LANE ci/iris.sh live sign-in --part 2/2`, one per call (about 5 minutes each). Expected: every case passes. Record the times and any red with its case.

**Mutations (Rule 19), each applied, observed red, reverted, with `git status --short` and `git diff --stat` unchanged:**
- `NextDueAt: fields.nextDueAt ?? '',` in `seedCheck`: (a) goes red.
- `nextDueAt: ''` added to rail R4's `seedCheck` with no comment: (b) goes red at that line.
- `,{"NextDueAt":""}` added to session S1's direct `Fixture.Check` call: (b) goes red.
- `##class(OcuTalon.Data.BackgroundCheck).%New()` added to an irisScript line in `support/floor.ts`: (c) goes red.

**Shared surfaces:** `seedCheck`'s `CheckFields.nextDueAt` contract and `Fixture.Check`'s `NextDueAt` default. Every browser spec that seeds checks reads them, and none of their assertions change. Every test added or changed passes on a fresh environment, in either order.

**Results (implement stage):**
- `(loop)` `node --test web/scripts/check-seeds.test.mjs`: 10 tests in 3 suites, all pass.
- `(once)` `npm --prefix web test`: exit 0, 1231 tests, 0 fail (check-seeds.test.mjs included).
- `(once)` `npm --prefix web run lint`: exit 0.
- `(once)` `bash docker/tests/test-boundaries.sh`: exit 0, "all rules passed".
- `(once)` `ci/iris.sh build`: ok. `ci/iris.sh live sign-in --part 1/2`: exit 0, 119 passed (3.8m in Playwright, 5m32s wall). `--part 2/2`: exit 0, 114 passed (4.0m, 5m49s wall). No red; no seeded row showed a finding it was not seeded with. The lane-A lock folder was empty at the end.

**Mutation results (Rule 19), review pass:**
- mutation: `&& entry[1] !== ''` added to the filter in `properties()` (web/e2e/support/iris.ts): "keeps an empty nextDueAt, because properties() drops undefined only" red; reverted (cmp identical).
- mutation: `{ NextDueAt: "", ...properties }` in `fieldsObject()`: "adds no key in fieldsObject" and "seedCheck adds no due time of its own" red; reverted (cmp identical).

**Mutation results (Rule 19):** each file was backed up to the scratchpad, mutated, observed red, restored (`cmp` identical), and `git status --short` and `git diff --stat` matched the state before.
- mutation: `NextDueAt: fields.nextDueAt ?? '',` in `seedCheck` (web/e2e/support/iris.ts): (a) red, "seedCheck passes `NextDueAt: fields.nextDueAt,` and nothing more"; reverted.
- mutation: `nextDueAt: ''` added to rail R4's `seedCheck` (web/e2e/rail/rail.spec.ts:200), no comment: (b) red, names `e2e/rail/rail.spec.ts:200`; reverted.
- mutation: `,"ZZNS","Zz.Production",{"NextDueAt":""}` added to session S1's direct `Fixture.Check` call (web/e2e/session/session.spec.ts:69): (b) red, names `e2e/session/session.spec.ts:69`; reverted.
- mutation: `##class(OcuTalon.Data.BackgroundCheck).%New()` added to an irisScript line in web/e2e/support/floor.ts: (c) red, names `e2e/support/floor.ts`; reverted.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** Adds `web/scripts/check-seeds.test.mjs`, a source-reading node test that pins the web half of DW-349's fix: `seedCheck` adds no due time of its own (and `fieldsObject` and `properties()` add none or drop none), an empty `nextDueAt` still reaches `Fixture.Check` as the opt-in, every opt-in and every direct `Fixture.Check` call with `NextDueAt` says `real watch`, and no e2e source stores a check row except through `Fixture.Check`. The `CheckFields.nextDueAt` doc comment in `web/e2e/support/iris.ts` now states the opt-in rule. No seeding code, spec, CI or IRIS change.

**Files changed:**
- `web/scripts/check-seeds.test.mjs` (new): 11 tests in 3 suites.
- `web/e2e/support/iris.ts`: the doc comment of `CheckFields.nextDueAt` only.
- This spec: Verification results, mutation lines, triage log.

**Review:** 4 layers. Patches applied: 4 (2 medium: `properties()` pin anchored, `fieldsObject()` pinned; 2 low: doc-comment placement wording, quoted-key match). Deferred: none. Rejected: the findings listed in the triage log with their reasons.

**Follow-up review recommended:** false (no high patched, two medium patched; each patch carries a demonstrated mutation).

**Verification:** `node --test web/scripts/check-seeds.test.mjs` 11 of 11; `npm --prefix web test` 1232 of 1232; `npm --prefix web run lint` clean; `bash docker/tests/test-boundaries.sh` all rules passed; `ci/iris.sh live sign-in --part 1/2` 119 passed and `--part 2/2` 114 passed, no red, lock folder empty after. Mutations: four from the plan plus two from the review pass, each red then reverted.

**Residual risks:** the pin reads source text, so it relies on `FixtureDefaults.TestCheckIsNotDue` (Story 11.1) for the IRIS default; DW-349's remaining reds on the integration branch end only when Epic 11 part 1 carries that default. DW-349 is the ledger entry; the lead adjudicates it. DW-578 is out of scope.
