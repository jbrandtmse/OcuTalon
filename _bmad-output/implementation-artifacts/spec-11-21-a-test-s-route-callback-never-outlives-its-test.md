---
title: "Story 11.21: A test's route callback never outlives its test"
type: 'bugfix'
created: '2026-11-04'
status: 'done'
baseline_revision: '84cf459bad86fbdf36de3568deb0941417669e14'
baseline_commit: '84cf459bad86fbdf36de3568deb0941417669e14'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      A local `ci/iris.sh live online-demo` run fails its Story 16.6 probe-phase check unless OCUTALON_LIVE_DEADLINE is raised to the CI value.
    evidence: |-
      lib-live.sh defaults the unit deadline to 540 s; the online-demo browser run alone uses about 414 s, so test-online-demo.sh reports "only 126 s are left of the deadline" and fails with every spec green. CI sets 1200. Seen in this story's implement run; the same unit passed with OCUTALON_LIVE_DEADLINE=1200.
    location: >-
      docker/tests/test-online-demo.sh:1306
    severity: low
---

<intent-contract>

## Intent

**Problem:** On v1.0.0, main's `iris (browser)` went red twice with `route.fetch: Test ended`. A test's route callback was still waiting on `route.fetch` when its test ended, and Playwright reported the error against the next test (DW-640: `live.spec.ts` L8 then L9; DW-665: `socket.spec.ts` W10 then W11). Separately, two `leave.spec.ts` tests (L5, L6) in `live:online-session` hit the 5-minute test timeout with no named step. The online specs' helper waits have no bound of their own: the config sets no action or navigation timeout, and `irisScript` never times out.

**Approach:** Add one shared Playwright `test` in `web/e2e/support/fixtures.ts`. It overrides the `page` and `context` fixtures so that each test ends with `unrouteAll({ behavior: 'ignoreErrors' })` on its page, on every page of its context, and on the context itself. Every spec under `web/e2e` and `web/e2e-online` imports `test` from that module (a one-path import edit), and the per-spec `afterEach` copies are deleted. A node test in the hosted `web` job names any spec that does not import it. The online projects get a shared action and navigation bound in the Playwright config. `irisScript` gets a bound in those projects, and the bound's error names the script's first line.

## Boundaries & Constraints

**Always:**
- There is one mechanism, the `page` and `context` overrides in `web/e2e/support/fixtures.ts`. `web/e2e-online` imports it from there; it gets no copy of its own.
- The teardown tolerates a page or context that the test already closed (measured: `unrouteAll` on a closed target throws `Target page, context or browser has been closed`). Any other error still fails the test.
- Bounds sit only in `web/e2e/support/bounds.ts` and `web/playwright.config.ts`, plus the one Telegram-fixture override in `web/e2e-online/telegram.ts`. No spec carries a bound of its own.
- The bounds apply only to the five online projects (`online-demo`, `online-session`, `online-allowance`, `online-demo-path`, `online-visitors`). The `web/e2e` projects keep today's waits.
- A timed-out `irisScript` stops its child process, is never retried, and throws an error that names the bound and the first line of the script.
- Source text stays ASCII, and comments state the contract only (Rule 14).

**Never:**
- No product code changes: `src/**`, `web/src/**`, `ci/mock/**` and `docker/**` stay untouched. If a product change seems needed, HALT with an intent gap.
- No changes to `ci/units.sh`, the workflows, the iris matrix or any `docker/tests/` file. Add no new CI unit or group.
- Do not rewrite a spec that another epic edits. Only its one import line changes. `web/e2e/api/pairing.spec.ts` (Epic 40) gets just the import path. `web/e2e/sign-in/helpers.ts` is not touched.
- In `web/e2e/support/iris.ts`, change only `runOnce`, `irisScript` and the imports they need. Epic 7 changes another part of this file.
- Keep every in-body `page.unrouteAll(...)` that comes before a further step of the same test, such as cleanup that needs the real network (`finally { unrouteAll; signOutGroup; ... }`, or a loop that re-routes). These are test logic. Only the `test.afterEach` copies go.
- Do not convert `web/e2e-rehearsal/` or `web/e2e-capture/`. They have their own configs, no spec there routes, and the ACs name only `web/e2e` and `web/e2e-online`.
- Do not commit the mutations.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Page callback in flight (DW-640, DW-665) | A test's `page.route` callback is waiting on `route.fetch` (an upstream that never answers) when the test ends | The page override unroutes with `ignoreErrors`. The next test passes. | none |
| Context callback in flight | Same, with the callback on `context.route` | The context override unroutes the context. The next test passes. | none |
| Second page of the context | Same, with the callback on `page.route` of a page opened by `context.newPage()` (like L5's `second`) | The context override unroutes every page of the context. The next test passes. | none |
| Page closed by the test | The test closes its fixture page after routing (like L6) | The teardown skips the closed target, and the test passes. | Only "has been closed" is swallowed. Any other error fails the test. |
| Spec not on the shared test | A `*.spec.ts` under `web/e2e` or `web/e2e-online` imports `test` from `@playwright/test`, or does not import it from `support/fixtures` | The `web` job's `route-cleanup` node test fails and names the file | n/a |
| Per-spec copy left | A spec's `test.afterEach` calls `unrouteAll` | The same node test fails and names the file | n/a |
| Hung IRIS script, online project | `irisScript` session never returns, in a test of an online project | Rejects after 90 s with `irisScript: no answer within 90 s from the script starting "<first line>"`. The child is killed and the script is not retried. | The test fails on that step |
| Telegram fixture call | `TelegramPageFixture` Start or Finish through `telegram.ts` `fixture()` | Bounded at 150 s, which is above the fixture's own longest wait chain (Start: WAITMONITOR 60 + 2 x WAITJOB 30 + WAITON 20 = 140 s), so the fixture's own reason wins when it fails | Same message form |
| IRIS script outside the online projects | `irisScript` in a `web/e2e` project or the rehearsal | Unbounded as today, because `web/e2e` fixtures wait up to 240 s on purpose (RunnerFixture SENDSECONDS) | unchanged |
| Hung page wait, online project | A click, `goto`, `waitForURL`, `waitForResponse`, `waitForEvent`, or `page.request` that never completes, on any page, including pages of `browser.newContext()` contexts | Fails at the action bound (30 s) or the navigation bound (60 s) with Playwright's `Timeout ... exceeded` naming the call. An explicit `timeout:` in a spec still wins. | n/a |

</intent-contract>

## Code Map

- `web/e2e/support/fixtures.ts` (new): the shared `test`.
  - `import { test as base, type BrowserContext, type Page } from '@playwright/test'`, then `export * from '@playwright/test'`, then `export const test = base.extend({ page, context })`. The local `test` shadows the star export, so a spec's import line changes only its path.
  - Teardown: `page` override, then `unroute(page)`. `context` override, then `unroute(p)` for each `context.pages()`, then `unroute(context)`.
  - `unroute(target)` calls `target.unrouteAll({ behavior: 'ignoreErrors' })` and swallows only an error whose message contains `has been closed`.
- `web/e2e/support/bounds.ts` (new). It must have no extensionless relative import and only erasable TS syntax, because `node --test` imports it directly (the same pattern `rehearsal-support.test.mjs` uses for `rehearsal.ts`). It exports:
  - `ONLINE_WAITS = { actionTimeout: 30_000, navigationTimeout: 60_000 }`
  - `ONLINE_IRIS_SCRIPT_MS = 90_000`
  - `TELEGRAM_FIXTURE_MS = 150_000`
  - `scriptBound(metadata)`: the project's `metadata.irisScriptMs` when it is a positive number, else `undefined`.
  - `runBounded(cmd, args, input, ms, step): Promise<string>`. It spawns with stdio `['pipe','pipe','ignore']`, collects stdout and resolves on `close`. When `ms` is set, a timer SIGKILLs the child, destroys its stdout, and rejects with `${step}: no answer within ${ms/1000} s`. The timer is cleared on `close` and on `error`.
- `web/e2e/support/iris.ts:73-108`: `runOnce` and `irisScript`.
  - `runOnce(script, ms)` calls `runBounded`. It must keep the line `irisSessionCommand(process.env, irisContainer)` inside `runOnce`, which `rehearsal-support.test.mjs:134-137` pins. The step label is `irisScript` plus the first non-empty line of the script, at most 80 characters.
  - `irisScript(script, ms = currentBound())`. `currentBound()` is `scriptBound(test.info().project.metadata)` inside try/catch, and `undefined` when there is no running test.
  - A rejection propagates. The 3-try loop retries only an answer with no `CHK|` line, as today.
  - Update its doc comment. Lines 1-72 and 109+ stay as they are, apart from the imports.
- `web/e2e-online/telegram.ts:27-40`: `fixture()` passes `TELEGRAM_FIXTURE_MS` to `irisScript`. This is one changed call and one import. It is outside the stated footprint, owned by no open epic, and reported as a footprint extension.
- `web/playwright.config.ts`: each of the five online projects gets `use: { ...devices['Desktop Chrome'], ...ONLINE_WAITS }` and `metadata: { irisScriptMs: ONLINE_IRIS_SCRIPT_MS }`, imported from `./e2e/support/bounds`. Add one header line. Nothing else changes, including the `web/e2e` projects, `timeout`, `expect` and `workers`.
- Specs that import `test` from `@playwright/test`: 70 files, each with one single-line import (`grep -rlE "import \{[^}]*\btest\b[^}]*\} from '@playwright/test'" --include='*.spec.ts' web/e2e web/e2e-online`). The integrate-forward also brings Epic 7's `web/e2e/cards/either-way.spec.ts`, which the same edit covers.
  - New path: `'../support/fixtures'` from `web/e2e/<dir>/`, `'../e2e/support/fixtures'` from `web/e2e-online/`, and `'../../e2e/support/fixtures'` from `web/e2e-online/<dir>/`.
- The `test.afterEach` copies to delete (a 3-line hook plus its blank line; nothing else in these hooks):
  - `chat/chat.spec.ts:28`, `chat/notice.spec.ts:22`, `chat/decision.spec.ts:24`
  - `banners/banners.spec.ts:43`, `rail/rail.spec.ts:35`, `phone/phone.spec.ts:20`, `trace/links.spec.ts:100` (the `signOutTrace` afterEach at :108 stays)
  - `floor/{browsers:33,words:34,layout:49,guide:30,scan:25,focus:36,keyboard:54,devices:43,announcements:48}.spec.ts`
  - `demo-path/telegram-page.spec.ts:192,348,695,852,982`
  - All paths are under `web/e2e/`.
- In-body `unrouteAll` calls that stay (each comes before a further step): `floor/keyboard.spec.ts:548`, `floor/guide.spec.ts:908`, `demo-path/telegram-page.spec.ts:210,596,630,643`, `e2e-online/{reset,busy,allowance/messages,session/sign-out-failed,session/sign-out,session/leave}.spec.ts`.
- DW-640 site: `web/e2e/live/live.spec.ts:343-370` (L8's `/events` callback with `route.fetch`). DW-665 site: `web/e2e/live/socket.spec.ts:37-43` (`stripPollEvents`). Each gets only the import change.
- Routing helpers covered through the importing spec's fixtures: `web/e2e/support/api.ts:27,83,114` (`changeSnapshot`, `holdPoll`, `holdState`) and `web/e2e/support/trace.ts:21` (`stubTraces`, on the context).
- `web/e2e-online/session/leave.spec.ts:307-386` (L5, L6): proof of the bounds, unchanged apart from the import.
- `web/scripts/playwright-projects.test.mjs`: computes the projects' spec lists from disk, so a new `web/e2e/live/` spec needs no change. Its row-18 run loads every chromium spec, so the new spec must do nothing at module top level.
- CI: the hosted `web` job runs `npm --prefix web run lint` (tsc over `e2e`, `e2e-online` and `playwright.config.ts`) and `npm --prefix web test` (`node --test scripts/*.test.mjs`) on any `web/` change. `live:sign-in` (group `browser`) runs the chromium project, every spec under `web/e2e` outside its project folders, so `web/e2e/live/` included.

## Tasks & Acceptance

**Execution:**
- [x] `web/e2e/support/fixtures.ts`: create the shared `test` as in the Code Map, with a header that states its contract: every test ends with no live route callback on its page, its context or the context's pages. (AC1)
- [x] `web/e2e/support/bounds.ts`: create the bounds and `runBounded` as in the Code Map. (AC4)
- [x] `web/e2e/support/iris.ts`: change `runOnce` and `irisScript` only, as in the Code Map. (AC4)
- [x] `web/e2e-online/telegram.ts`: `fixture()` passes `TELEGRAM_FIXTURE_MS`. (AC4)
- [x] `web/playwright.config.ts`: give the five online projects `ONLINE_WAITS` and the `irisScriptMs` metadata. (AC4)
- [x] Every `*.spec.ts` under `web/e2e` and `web/e2e-online`: change the path of the one `@playwright/test` import line to the shared fixtures module. Change nothing else on the line or in the file. (AC1, DW-640, DW-665)
- [x] The 21 `test.afterEach` copies in the Code Map: delete them. (AC1)
- [x] `web/e2e/live/route-cleanup.spec.ts` (new, no stack and no `OCUTALON_` variable). The pinning spec. (AC2, DW-640, DW-665)
  - `beforeAll` starts a `node:http` server on `127.0.0.1:0`. `/` serves a page whose `go()` fetches `/hang`. `/hang` never answers and counts its hits. `afterAll` runs `closeAllConnections()` and `close()`.
  - Four `test.describe.serial` pairs, each a leaver followed by a follower that passes on its own.
  - In pairs (a) to (c), the leaver installs a callback that awaits `route.fetch()` on `/hang`, triggers the fetch, polls until the server has the hit, and ends. The callback is on (a) the fixture page (`page.route`), (b) the context (`context.route`), or (c) a page from `context.newPage()` (`page.route`, using only the `context` fixture).
  - In pair (d), the leaver installs a `page.route` on the fixture page, triggers no fetch, and closes the page itself with `page.close()`.
  - The header states what it pins and that it needs only a local Chromium.
- [x] `web/scripts/route-cleanup.test.mjs` (new, hosted `web` job). (AC1, AC3)
  - It walks every `*.spec.ts` under `web/e2e` and `web/e2e-online`.
  - It fails, naming each offender, when a spec imports a value named `test` (or uses a default or namespace import) from `@playwright/test` or `playwright/test`, or does not import `test` from a path ending in `support/fixtures`.
  - It also fails when a spec's `test.afterEach` hook calls `unrouteAll`.
  - Source-pin `fixtures.ts`: overrides `page` and `context`, `ignoreErrors`, and the closed-target tolerance.
  - Self-test its classifier on inline samples: an offending `@playwright/test` line is flagged, the shared import passes, and a `type`-only import from `@playwright/test` passes. This keeps the check from being vacuous.
- [x] `web/scripts/bounded-waits.test.mjs` (new, hosted `web` job). It imports `bounds.ts` directly. (AC4)
  - `runBounded('sh', ['-c', 'exec sleep 30'], '', 500, 'step X')` rejects within 2 s with a message naming `step X` and `0.5 s`. The `it` has `{ timeout: 5000 }`.
  - A child that prints and exits resolves with its output.
  - `scriptBound` reads `irisScriptMs` and returns `undefined` for absent or non-positive values.
  - Bound sanity: `ONLINE_IRIS_SCRIPT_MS` and both `ONLINE_WAITS` values are at least 10 s and at most 120 s, and `TELEGRAM_FIXTURE_MS` is above 140 s and at most 150 s.
  - Source pins: each project of `web/playwright.config.ts` whose `testDir` starts with `./e2e-online` spreads `ONLINE_WAITS` and sets `irisScriptMs`, and no other project does. `iris.ts` `irisScript` takes the bound from `test.info().project.metadata`. `telegram.ts` `fixture()` passes `TELEGRAM_FIXTURE_MS`.
- [x] This spec: record the Verification results and the `mutation:` lines.

- [x] [Amend] `web/e2e/cards/either-way.spec.ts` (arrived with Epic 7's merge, 4238dc8f): change its one `@playwright/test` import line to the shared fixtures module, like the other 70 specs, so `route-cleanup.test.mjs` passes. Nothing else in the file. (AC1, AC3)
- [x] [Amend] Shared sign-in helper waits, each with its own bound shorter than the test timeout and a failure message naming the step and the response it waited for (AC7; epics.md Story 11.21, the Contest Planner's condition of 2026-11-04; DW-690, DW-691):
  - `web/e2e/support/floor.ts` `loadedAfter`: the `waitForResponse` for the snapshot's GET of `/ocutalon/api/v1/state` and the sign-in action it wraps are bounded; on expiry it fails naming the step ("the sign-in" or "the snapshot GET /ocutalon/api/v1/state") and its bound. (OCT-epic40 run 41929230934 `02-watch.spec.ts:61` timed out at 180 s inside `loadedAfter`'s `waitForResponse`.)
  - `web/e2e/support/navigate.ts` `gotoSettled`: bounded, naming the URL; and it also retries once on `net::ERR_ABORTED` (logging `NAV retry <url>` as for NETWORK_CHANGED): the page's own `location.replace` after a sign-out aborts the next navigation (DW-690: `07-failure-paths` L77's re-sign-in failed with `page.goto net::ERR_ABORTED` at `/ocutalon/`). Decided by the lead (decide, within intent): a second failure, and every other error, is still thrown.
  - `web/e2e-online/support.ts` `signInFromSplash` (its POST answer wait) and `openSession`: bounded and named.
  - `web/e2e/sign-in/helpers.ts` is an OPEN path of Epic 40 (it inserted a block at the top): do NOT edit it. Bound its waits (`submitSignIn`'s POST answer, `signInReadme`'s load) from the shared layer instead: (a) `loadedAfter` bounds the sign-in action it wraps, naming it; and (b) the shared fixture (`web/e2e/support/fixtures.ts`) gives every page a default timeout and navigation timeout below the test's own timeout (derived from `testInfo.timeout`, for example the smaller of a fixed cap and a share of it; measure, and keep every live unit green), so any wait without its own bound, in a helper or a spec, fails on its own timeout with Playwright's call name and the helper's stack line instead of the test timeout. A wait that passes an explicit timeout keeps it. Record the numbers and why in Design Notes.
  - A pinning test (hermetic, no stack, in `web/e2e/live/` like `route-cleanup.spec.ts`, so `live:sign-in` runs it): a response that never comes makes `loadedAfter` (and `gotoSettled`'s bound) fail within its bound with the named step in the message, well before the test timeout; mutation shown (remove the bound: the test times out instead), never committed. Plus a node source pin in `web/scripts/bounded-waits.test.mjs` if it fits.
  - Verification: re-run `live:online-session` (L5, L6), `live:sign-in` both parts, `live:demo-path` and `live:floor` (the units whose specs use these helpers most; `focus.spec.ts` P1 is in `live:floor`) on lane-B throwaways, one at a time, after the last patch.

- [x] [CI] `iris (shards)` `live:online-session`, run 41957022331 attempt 3 (job 127036912190, head a8868ad8, the AC4 proof's second run): `leave.spec.ts:354` L6 hit the 300 s test timeout again ("Test timeout of 300000ms exceeded.", no other error, no named step), and the docker check after it found "TelegramIn has a live job" (L6's `finally` never put the Telegram fixture back). Attempt 1 of the same run passed L6 in 9.5 s. Every bounded step of L6 is below 150 s, so either one call has no bound (for example `page.close()` at leave.spec.ts:367, which takes no timeout in Playwright) or a chain of slow but bounded steps summed past the test timeout. Either way AC7 / the Planner's condition ("fails with a message naming the step") was not met. Fix, in the shared layer (no per-spec copies; at most a one-line call change in a spec where a bare Playwright call must go through a shared bounded helper):
  - Deadline-aware bounds: every shared bounded wait (`boundedStep`, `runBounded` / `irisScript`, the Telegram fixture calls, `loadedAfter`, `gotoSettled`, `signInFromSplash`, `epochOf`) uses the smaller of its own bound and the time left before the running test's timeout minus a margin (about 10 s), so the last step of a slow chain fails naming itself before the test timeout, and the spec's `finally` (which puts the Telegram fixture back) still runs. Outside a test (no `test.info()`), the own bound alone.
  - Unbounded calls on the L5/L6 path: bound `page.close()` / `second.close()` and any other bare call there that takes no timeout, through a shared helper (named step).
  - Breadcrumbs for the next red: each shared bounded wait that takes longer than about 10 s prints one stdout line naming its step and its seconds (for example `SLOW irisScript "Set r=..." 37 s`), so a CI log shows where the time went even when no artifact is uploaded.
  - Pin the deadline cap with a hermetic test (a test with a short timeout whose bounded step would outlast it fails with the step's name, not the test timeout; mutation shown, never committed).
  - Verification after the last patch: lint; `npm --prefix web test`; the hermetic specs; `live:online-session` at least twice on lane-B throwaways (one at a time, torn down after each), with L5 and L6 passing; `live:sign-in` both parts once.

**Acceptance Criteria:**
- AC1 (one mechanism, DW-640, DW-665). Given every spec under `web/e2e` and `web/e2e-online`, when a test ends, then its routes are removed by the shared fixtures with `unrouteAll({ behavior: 'ignoreErrors' })`, no spec carries its own `afterEach` copy, and `route-cleanup.test.mjs` is green.
- AC2 (pinned). Given a route callback still waiting on `route.fetch` when its test ends (on the page, the context, or a second page of the context), when the next test runs, then neither fails with `route.fetch: Test ended`, and a page the test closed itself makes no error. `route-cleanup.spec.ts` is green in Chromium with no stack.
- AC3 (later specs). Given a spec added later under `web/e2e` or `web/e2e-online` that imports `test` from `@playwright/test`, when the `web` job runs, then `route-cleanup.test.mjs` fails and names the file. A spec that imports the shared test is covered with no further edit, including routes installed through a support helper.
- AC4 (bounded online waits). Given a test of an online project, when an `irisScript` session, a page action, a navigation, a response wait or a page request never answers, then it fails on its own bound (90 s, or 150 s for the Telegram fixture; 30 s; 60 s), well under the 120 to 300 s test timeouts, naming the step. `bounded-waits.test.mjs` is green.
- AC5 (proof on the stack). Given the story's tree on a lane-B throwaway, when `live:online-session` runs, then it passes with `leave.spec.ts` L5 and L6 green. When the `(once)` units run, each passes.
- AC6 (footprint). Given the diff since `story_base`, excluding `_bmad-output`, when listed, then it holds only the files in the Code Map and the spec import lines.
- AC7 (bounded sign-in helper waits; the Contest Planner's condition, 2026-11-04; DW-690, DW-691). Given a wait in the shared sign-in helpers (`loadedAfter`, `gotoSettled`, the sign-in helpers of `web/e2e/sign-in/helpers.ts` and `web/e2e-online/support.ts`) that never ends, when the test runs, then the wait fails on its own bound, shorter than the test timeout, with a message naming the step and the response it waited for; a hermetic test pins it (mutation shown). `gotoSettled` also retries once on `net::ERR_ABORTED`.

### Review Findings

Code review 2026-11-04 (bmad-code-review, first review; four layers; diff `ac2c4549..` working tree, `web/` only). 31 rows, 9 entries after grouping: high 0, med 3, low 6; 16 rows rejected.

- [x] [Review][Patch] (med; fix-risk low; in-story) "never retried" lost its only pin when QA removed the elapsed-time check: a retry-on-timeout mutation (about 11.5 s) stayed green inside the 45 s test timeout. `iris-script-bound.spec.ts` now counts session starts through a temp file (exactly one), no timing. [Blind+Edge+Verification+Acceptance]
- [x] [Review][Patch] (med; fix-risk low; in-story) `live:answers`, `live:cards` and `live:demo-switch` had not run since the shared fixture's default page waits changed. Measured on lane-B throwaways (`e11s21crc`, `e11s21cra`, `e11s21crd`, torn down after each): cards 28 passed, answers 23 passed, demo-switch 6 + 23 passed. [Acceptance]
- [x] [Review][Defer] (med; fix-risk high; in-story) The `request` fixture and `playwright.request.newContext()` have no timeout in the `web/e2e` projects (Playwright sets `_defaultContextTimeout = actionTimeout || 0`), so `signInOverHttp` still runs to the test timeout unnamed. DW-706 `escalated owner=burndown`: the fix replaces the built-in fixture, and an APIRequestContext cannot follow a later `test.setTimeout`. [Blind]
- [x] [Review][Patch] (low) `signInFromSplash` armed its POST wait with `wait + slack`, which a slow click could use up so Playwright's unnamed timeout won: now `2 * wait + slack`, as `loadedAfter` does. [Blind]
- [x] [Review][Patch] (low) The `irisScript` doc comment said the session "is killed": only its local command is (docker exec client or the exec shell); reworded. The in-container session itself stays as the earlier pass decided. [Blind+Edge]
- [x] [Review][Patch] (low) The fixture branch "a project that sets its own waits keeps them" had only a source pin: new `helper-waits.spec.ts` case under `test.use({ actionTimeout: 2_000, navigationTimeout: 3_000 })`. [Blind+Verification]
- [x] [Review][Patch] (low) `route-cleanup.test.mjs` walked only `*.spec.ts`; Playwright's default testMatch also runs `*.test.*` and js/mjs forms: the walker uses that pattern, with a classifier row. [Verification]
- [x] [Review][Patch] (low) The `playwright.config.ts` header said "Twelve projects" and left out `online-visitors`: corrected. [Blind]
- [x] [Review][Patch] (low) Rule 14: the `route-cleanup.spec.ts` header narrated history ("as live.spec.ts L9 and socket.spec.ts W11 did"): removed. [Acceptance]
- Rejected: `test.slow()` not followed (tracking it needs Playwright's private `_modifier`; documented residual, ran green); `loadedAfter`'s composite sign-in, sequential bounds and the ERR_ABORTED retry's fresh wait able to sum past the test timeout (each step is bounded and named as AC7 asks, and it takes two faults together); `irisScript` 3 x bound for sessions with no CHK line (not a hang; unchanged behaviour); ERR_ABORTED retry breadth (the lead's decision; a second failure and every other error is thrown, so a persistent failure is never masked; no `gotoSettled` site aborts on purpose); rehearsal and capture specs reaching the helper bounds (caps of 60 s and 90 s, above every wait those specs make; a sign-in that slow is a defect); intent-contract bullets superseded by AC7 (the fix edits the spec; the lead may restate); `submitSignIn` outside `loadedAfter` failing with Playwright's call name (the Amend item's accepted form, `helpers.ts` off-limits); the Telegram fixture's first line being generic (the matrix's message form); the `layout.spec.ts` comment (the comment named the deleted hook); `browser.newContext()` routes (Design Notes 3); 90 s not "within seconds" (the matrix's numbers).
- Rule 19 judgments: the `< 2000` ms checks in `bounded-waits.test.mjs` stay (at least 1.5 s of margin over 300 to 500 ms bounds on the hosted `web` job, which runs no stack, and they catch a bound that is too long but still under the 5 s test timeout). Every new hermetic spec is in `web/e2e/live/` (chromium project, `live:sign-in`); every new node test matches `scripts/*.test.mjs` (hosted `web` job). AC5 and AC6 carry no mutation by nature.
- Rule 3: exempt (test harness, no user-facing surface). Rule 6: AD-22 and AD-29 match; no CI job, unit or matrix change; no product path touched. `web/e2e/sign-in/helpers.ts` untouched; Epic 7's lines in `web/e2e/support/iris.ts` intact.

## Spec Change Log

- 2026-11-05 (rework iteration 3 of 3, trigger=ci, by the lead): the AC4 proof's second `iris (shards)` run went red on L6's test timeout with no named step; added the `[CI]` item (deadline-aware shared bounds, bounded closes, slow-step breadcrumbs).

- 2026-11-04 (rework iteration 1, trigger=scope_amendment, by the lead): epics.md Story 11.21 gained the Contest Planner's condition (bounded shared sign-in helper waits, named failures; DW-690, DW-691; `loadedAfter` in scope) after the implement pass; Epic 7's merge (4238dc8f) brought `web/e2e/cards/either-way.spec.ts`. Added the two `[Amend]` items and AC7. `web/e2e/sign-in/helpers.ts` stays untouched (Epic 40's open path).

## Review Triage Log

### 2026-11-04 - Review pass
- verdicts: 43 findings - high 0, medium 3, low 35, false 5, maybe-false 0 (rows in the order of the layers: Blind, Edge, Verification, Intent)
- findings:
  - `[low]` `[reject]` Blind: runBounded kills only the local docker exec or sh client, not the in-container iris session - pre-existing (the session was never stopped before), the kill only improves it, and the fix needs container-side process control; the Boundaries bullet says "its child process", which is what is killed.
  - `[medium]` `[patch]` Blind: bounded-waits.test.mjs never checks that the child is killed - patched: a pid-file test asserts the process is gone; mutation shown (kill deleted, red).
  - `[low]` `[patch]` Blind: bounds.ts header says "well under" the test timeouts and puts waitForResponse under navigationTimeout - patched: header and option comment reworded (waitForResponse follows actionTimeout).
  - `[low]` `[reject]` Blind: online waitForResponse calls without a timeout are now cut at 30 s - decided in Design Notes 5; all five online units ran green under the bounds.
  - `[low]` `[reject]` Blind: the page override is dead code - recorded in Design Notes; the intent names both overrides and the source pin holds it.
  - `[low]` `[reject]` Blind: browser.newContext() contexts are not unrouted - Design Notes 3; every such context is closed by its own test in finally, so no callback outlives the test.
  - `[low]` `[reject]` Blind: irisScript cannot opt out of the project bound - no caller needs it; an explicit large ms does it.
  - `[low]` `[reject]` Blind: route-cleanup.test.mjs misses double-quoted imports, afterAll and helper-based copies - contrived forms the repo's single-quote style and its "must import the shared test" rule already catch from the other side.
  - `[low]` `[reject]` Blind: brittle indexOf slices, the 140 s chain only in a comment, chunks.length >= 12 - the config pin no longer reads text chunks; the others are negligible.
  - `[low]` `[defer]` Blind: the local online-demo run needs OCUTALON_LIVE_DEADLINE=1200 - pre-existing harness default, outside the footprint; deferred (low).
  - `[low]` `[reject]` Edge: SIGKILL reaches only the local client - same as the first Blind row.
  - `[low]` `[reject]` Edge: an unroute error that is not "closed" in the pages loop skips the remaining targets - that error fails the test anyway; unlikely.
  - `[false]` `[reject]` Edge: the closed-target message may be worded differently - Task 0 measured the wording and mutation D shows the swallow is needed and works.
  - `[false]` `[reject]` Edge: a follower may pass vacuously before the leak surfaces - the mutations turn the followers red in the same run, so the race does not hide it.
  - `[false]` `[reject]` Edge: hits and held persist across retries - each leaver compares against a snapshot taken before its own fetch.
  - `[low]` `[reject]` Edge: importsOf only reads single-quoted imports, and the check has the same blind spots as above - contrived.
  - `[low]` `[reject]` Edge: afterEach hooks delegating to a helper escape the check - contrived.
  - `[false]` `[reject]` Edge: specs named *.test.ts escape the check - no such file exists under e2e or e2e-online, and Playwright's default testMatch is spec|test.
  - `[low]` `[reject]` Edge: a caller can pass ms 0 or NaN to runBounded - internal helper, one caller path.
  - `[false]` `[reject]` Edge: MOCK_MS (90 s) equals ONLINE_IRIS_SCRIPT_MS - MOCK_MS bounds page waits, not an irisScript session.
  - `[low]` `[reject]` Edge: a slow-but-valid online wait now fails at 30 s - same as the Blind row (Design Notes 5).
  - `[low]` `[reject]` Edge: browser.newContext() contexts are not guarded - same as the Blind row.
  - `[low]` `[patch]` Edge: the fixtures.ts header says ignoreErrors lets a callback finish - patched: it does not wait for the callback and ignores its error.
  - `[low]` `[reject]` Edge: the claim "stops its child process" - same as the first Blind row.
  - `[low]` `[reject]` Edge: the page override is covered by the context loop - same as the Blind row.
  - `[medium]` `[patch]` Verification: irisScript's default bound, no retry and first-line message are pinned by source regexes only - patched: the hermetic iris-script-bound.spec.ts drives irisScript through OCUTALON_E2E_IRIS_EXEC; three mutations shown red.
  - `[medium]` `[patch]` Verification: the online projects' options are pinned by text over the config - patched: the test loads the config and compares use and metadata values; two mutations shown red (it also showed the first draft of the patch had dropped the test, caught by the mutation).
  - `[low]` `[patch]` Verification: AC4 parts and the ignoreErrors option have no mutation line - patched: mutation lines added for each.
  - `[low]` `[reject]` Verification: AC5 and AC6 have no mutation line - AC5 is the live proof, AC6 the diff check; recorded as such.
  - `[low]` `[reject]` Verification: the page override has no failing test - same as the Blind row.
  - `[low]` `[reject]` Verification: the hosted web job pins fixtures.ts by source only - the behaviour runs in live:sign-in; accepted.
  - `[low]` `[reject]` Verification: the followers pass vacuously when run alone - serial pairs by design (Design Notes 7).
  - `[low]` `[reject]` Verification: runBounded kills only the local client - same as the first Blind row.
  - `[low]` `[reject]` Verification: each retry gets its own bound - a session that ends without CHK lines is not a hang; unchanged behaviour.
  - `[low]` `[reject]` Verification: a double-quoted import escapes the classifier - same as the Blind row.
  - `[low]` `[reject]` Verification: layout.spec.ts has a comment edit beyond the import - the comment named the deleted hook; layout.spec.ts is in the Code Map.
  - `[low]` `[reject]` Intent: readings A, B and C; the diff implements A - descriptive; B and C are covered by Design Notes 3 and by the live units.
  - `[low]` `[reject]` Intent: newContext contexts are not unrouted and the bounds' effect on them is untested - Task 0 measured the bounds on browser.newContext() pages.
  - `[low]` `[patch]` Intent: the bounds have no behavioural test, and the first-line detail is untested - patched through iris-script-bound.spec.ts (page waits stay as measured in Task 0).
  - `[low]` `[reject]` Intent: the evidence is a one-time run - the node and Chromium specs run in CI.
  - `[low]` `[reject]` Intent: the page override is covered by the source pin only - same as the Blind row.
  - `[low]` `[reject]` Intent: footprint extensions (tsconfig.e2e.json, rehearsal-support.test.mjs, the .ts import) - small and reversible, recorded in Design Notes; reported to the lead.
  - `[low]` `[reject]` Intent: iris.ts reads test.info() in a try/catch that returns undefined - outside a test there is no project bound; a throw inside a test cannot occur.

### 2026-11-04 - Review pass (rework iteration 1: the [Amend] items and AC7)
- verdicts: 31 findings - high 0, medium 2, low 29, false 0, maybe-false 0 (rows in the order of the layers: Blind, Edge, Verification, Intent)
- findings:
  - `[low]` `[reject]` Blind: loadedAfter bounds the sign-in by the navigation wait alone, though the action is goto then a POST wait, so a slow sign-in is cut and may blame the wrong step - a sign-in that needs more than 60 s (online) or 30 s (45 s tests) is already unhealthy, the inner steps are bounded by the same waits and also name themselves, and a longer outer bound would leave no room under the test timeout (AC7).
  - `[low]` `[reject]` Blind: the ERR_ABORTED retry is broad (re-navigates after a redirect, repeats a deliberate abort) and doubles the worst case - the retry is the lead's decision in the [Amend] item (DW-690); no gotoSettled site aborts on purpose.
  - `[low]` `[reject]` Blind: gotoSettled's bounded path has no unit-level test - `helper-waits.spec.ts` drives it in Chromium and its mutation is shown.
  - `[low]` `[reject]` Blind: navigate.ts imports `test` and swallows every error of `test.info()`; mixed `./bounds.ts` and `./bounds` imports - the catch is the "outside a test" case, the extension is explained in its comment; narrowing adds complexity for no reachable harm.
  - `[low]` `[patch]` Blind: test.slow() is not tracked and the setTimeout wrapper shadows the global timer - patched: the local is renamed `setTestTimeout`; test.slow() is recorded in Design Notes and ran green.
  - `[low]` `[patch]` Blind: loose elapsed-time assertions, a second-page assertion that proves nothing of the change, no case for signInFromSplash or epochOf - patched: the elapsed assertions are removed (the test timeout already detects a missing bound), the second-page case is split out without an explicit timeout, and two cases for the online helpers are added.
  - `[low]` `[reject]` Edge: the sign-in bound and the snapshot bound run in sequence, so their sum can exceed the test timeout - each bound is shorter than the test timeout as AC7 asks; it takes a slow sign-in and a hang together to reach the test timeout unnamed.
  - `[low]` `[reject]` Edge: a composite sign-in (goto, fill, POST) is bounded by the navigation wait only - same as the first Blind row.
  - `[low]` `[reject]` Edge: currentWaits ignores a spec's test.use({ actionTimeout }) - no spec under e2e or e2e-online sets such an option (searched).
  - `[low]` `[reject]` Edge: test.slow() leaves the waits sized to the old timeout - Design Notes record it; the three chat.spec.ts tests ran green on the 30 s default.
  - `[low]` `[reject]` Edge: the wait is a fixed share of the whole timeout and ignores the time already spent - same family as the sequence row; a share is what the item asks for, and a remaining-time rule adds a moving bound.
  - `[low]` `[reject]` Edge: the caps (60 s, 90 s) may cut a legitimate longer wait in a web/e2e spec - measured: the live units named in the item and all four online units ran green with no explicit timeout added.
  - `[low]` `[reject]` Edge: a wrapped TimeoutError message may match the retry pattern through its call log - theoretical: Playwright's goto call log holds no net::ERR_ABORTED line.
  - `[low]` `[reject]` Edge: no opt-out from the abort retry - same as the second Blind row.
  - `[low]` `[reject]` Edge: epochOf does not bound the body read after the headers - pre-existing and theoretical; the request, not the body, is what hangs in the incidents.
  - `[low]` `[reject]` Edge: the retry's own timeout error carries the gotoSettled prefix, not "unchanged" - the prefix is the contract of the bound; the error is still thrown.
  - `[low]` `[reject]` Edge: claim that each wait has a bound shorter than the test timeout but the chain does not - same as the sequence row.
  - `[low]` `[reject]` Edge: claim that helper bounds and page defaults disagree under test.use - same as the test.use row.
  - `[medium]` `[patch]` Verification: the signInFromSplash and epochOf bounds are pinned by source text only, with no mutation - patched: two hermetic cases in `helper-waits.spec.ts` (a held sign-in POST, a held state GET); both mutations shown red.
  - `[low]` `[patch]` Verification: the project-options branch of currentWaits is never exercised - patched: the rule is the pure `effectiveWaits` in bounds.ts, pinned by a node row; mutation shown red.
  - `[low]` `[reject]` Verification: the online units that use the changed helpers were not re-run after the amend - closed: online-session, online-allowance, online-visitors, online-demo-path and online-demo ran green after the last patch (Verification results).
  - `[medium]` `[patch]` Verification: the second-page assertion carries an explicit timeout and cannot fail from the fixture - patched: its own case with no explicit timeout; `giveWaits` as a no-op turns it red.
  - `[low]` `[reject]` Verification: gotoSettled retries after a near-full bound, so up to two bounds - same as the second Blind row.
  - `[low]` `[reject]` Verification: test.slow() is not seen - same as the test.slow rows.
  - `[low]` `[patch]` Verification: no mutation line for waitsFor and boundedStep - patched: three mutations shown red and written in Verification.
  - `[low]` `[patch]` Verification: the elapsed-time assertions give 1 to 2 s of margin on a loaded runner and detect nothing the test timeout does not - patched: removed (see the sixth Blind row).
  - `[low]` `[reject]` Intent: the diff changes web/e2e behaviour although the contract says those projects keep today's waits - AC7 and the Spec Change Log (epics.md Story 11.21, the Planner's condition) add exactly that; recorded in Design Notes, and the contract text is the lead's to restate.
  - `[low]` `[patch]` Intent: the 5 s margin and the share sit outside bounds.ts - patched: `WAIT_SLACK_MS` and `effectiveWaits` live in bounds.ts.
  - `[low]` `[patch]` Intent: no test runs a helper under an online project's options - patched through `effectiveWaits` (see the Verification rows); the online units ran green.
  - `[low]` `[reject]` Intent: pages of browser.newContext() get no fixture default - Design Notes 3 and the amend pass: the helpers bound themselves through currentWaits.
  - `[low]` `[reject]` Intent: boundedStep cannot cancel the work it bounds - the late outcome is dropped and caught; the page is closed with its test.

### 2026-11-05 - Review pass (rework iteration 3: the [CI] item)
- verdicts: 35 findings - high 0, medium 5, low 27, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: the cap docs promise "minus 10 s" while the 5 s floor can exceed the time left - `capToDeadline` clamps the floor to the time left less a second (at least 1 s); docs reworded; node row added.
  - `[low]` `[reject]` Blind: a fixed 10 s margin cuts a step in a test under about 25 s - the item names a margin of about 10 s; the online units' tests run 120 to 300 s, the `web/e2e` default 45 s.
  - `[medium]` `[patch]` Blind: `helper-waits.spec.ts` no longer tests the helpers' own bounds (the 12 s test hits the 5 s floor first) - the five helper cases set the running project's waits (3 s and 4 s, as the online projects do) and assert the anchored message with no cap note.
  - `[low]` `[patch]` Blind: SLOW inconsistent across `boundedStep`, `runBounded`, `gotoSettled` - `runBounded` skips it after its own kill, `gotoSettled` reports in `finally`; a double report is not possible (`irisScript` is not wrapped in `boundedStep`).
  - `[low]` `[patch]` Blind: new tests mostly read source text - behavioural SLOW rows (stubbed clock and log), the elapsed-time row and the retry row added; the `reportSlow` count pin replaced by two exact pins.
  - `[low]` `[patch]` Blind: module-level `startedAt` shadowed by locals - map renamed `testStarts`.
  - `[low]` `[reject]` Blind: page.close bound covers only the fixture context; `context.close()` and an explicit `gotoSettled` timeout stay unbounded - the item scopes the close to the L5/L6 path (fixture page and context); no close hang is evidenced elsewhere.
  - `[medium]` `[reject]` Edge: cleanup in a `finally` after a body cut at the margin gets at most the 5 s floor, so `finishTelegram` may be killed - the item fixes the margin at about 10 s; the `finally` runs and the next red's SLOW lines show its time; recorded under residual risks.
  - `[low]` `[patch]` Edge: floor can exceed the time left - same fix as the first row.
  - `[low]` `[reject]` Edge: `markTestStart` runs after earlier fixture setup, so time left is overestimated - the shared test's auto fixture is the first to run; the margin absorbs the rest.
  - `[false]` `[reject]` Edge: an unmarked test gets no cap - `route-cleanup.test.mjs` fails any spec not on the shared test, and hooks use no bounded wait.
  - `[low]` `[reject]` Edge: `gotoSettled` with an explicit `options.timeout` is not capped - an explicit timeout wins by the story's own rule.
  - `[low]` `[reject]` Edge: `runBounded` with no bound (the `web/e2e` projects) is not capped - their fixtures wait up to 240 s on purpose; the cap only shortens a bound that exists.
  - `[low]` `[patch]` Edge: a SLOW line prints after the kill in `runBounded` - guarded by `timedOut`.
  - `[low]` `[patch]` Edge: a slow `gotoSettled` that fails prints no SLOW line - reported in `finally`.
  - `[low]` `[reject]` Edge: explicit-timeout waits in `leave.spec.ts` (`expect.poll`, `landedOn`) are not capped - they are not shared bounded waits of the item; the `irisScript` calls inside the polls are capped.
  - `[low]` `[reject]` Edge: `boundedClose` skips `browser.newContext()` pages - same as the seventh row.
  - `[false]` `[reject]` Edge: `ownMs` of 0 becomes an unbounded timeout - no caller passes 0 (`waitsFor` returns the caps; `effectiveWaits` falls back on 0).
  - `[medium]` `[reject]` Edge (claim): the `finally` "still runs" but its calls get 5 s - same as the eighth row.
  - `[low]` `[reject]` Edge (claim): not every shared wait is capped - see the explicit-timeout and unbounded rows; documented in the docs of `gotoSettled` and `irisScript`.
  - `[medium]` `[patch]` Gap: `testTimeLeftMs`'s elapsed-time arithmetic is unpinned - `deadline-cap.spec.ts` marks the test as begun 8 s earlier and expects `12 s left` and a 5 s bound.
  - `[medium]` `[patch]` Gap: the `gotoSettled` retry bound and the explicit-timeout pass-through are unpinned - a spec case with a recording fake: first attempt about 10 s, retry 5 s, explicit 99 s unchanged.
  - `[low]` `[patch]` Gap: SLOW emission pinned by source text only - node rows with a stubbed clock and log for `boundedStep`, `runBounded` and `gotoSettled`.
  - `[low]` `[patch]` Gap: the close bound's options and `context.pages()` loop unpinned - a row asserts the options reach `close`; the loop was dead (a new context has no pages) and is deleted.
  - `[low]` `[reject]` Gap: pages of `browser.newContext()` have no bounded close - same as the seventh row.
  - `[low]` `[patch]` Other: source-text pins - the `reportSlow` count and the pages-loop pin replaced by exact pins and behavioural rows.
  - `[low]` `[patch]` Other: `assert.equal(DEADLINE_MARGIN_MS, 10_000)` can only fail on an edit - removed.
  - `[low]` `[patch]` Other: stale `mutation:` lines for the AC7 pins - rewritten below.
  - `[low]` `[patch]` Other: `page.close` case had no bound of its own, and the header said "Chromium only" - the case sets 12 s; the header names the one browser case.
  - `[low]` `[reject]` Other: `irisScript` is unbounded and uncapped in the non-online projects - by the story's rule (their fixtures wait up to 240 s).
  - `[low]` `[patch]` Other: SLOW after the kill in `runBounded` - same as the fourteenth row.
  - `[low]` `[reject]` Other: time left is overestimated by the setup before the auto fixture - same as the tenth row.
  - `[false]` `[reject]` Other: `capToDeadline` is evaluated at the call, after the wait was armed - `WAIT_SLACK_MS` keeps the helper's message first.
  - `[low]` `[reject]` Intent: native Playwright calls with their own timeouts stay static - the item lists the shared bounded waits; the SLOW lines name where the time goes if L6 goes red again.
  - `[low]` `[reject]` Intent: a chain of steps adding up to the deadline is not exercised live - `deadline-cap.spec.ts` "the time the test has already used" and the retry case pin the late-start shape without a stack.

## Design Notes

**Governing ADs.**
- AD-22: test tiers and CI. This story adds no mock behaviour and no CI unit. The new node tests run in the existing hosted `web` job, and the pinning spec runs in `live:sign-in`.
- AD-29: `web/` with its e2e specs and runner configuration is Lane B, and Epic 11 may change either lane's files.
- Consistency Conventions, Tests row: Playwright specs live under `web/e2e/`.
- No AC contradicts an AD's Rule.

**Rule 3.** This is a test-harness story with no user-facing surface, so it is exempt from Rule 3.

**Task 0, measured in the plan stage** (Playwright 1.64.1 and its Chromium, on the developer machine, from a scratch config outside the tree):
- A callback awaiting `route.fetch` on a never-answering local upstream when its test ends fails the next test, even an instant one, with exactly `"route.fetch: Test ended." while running route callback`. Playwright also prints `Consider awaiting await page.unrouteAll({ behavior: 'ignoreErrors' })`. This reproduced for `page.route`, `context.route` and `context.newPage()`'s `page.route`.
- With `page` and `context` overrides that unroute in teardown (the context override also loops over `context.pages()`), all three pass.
- `unrouteAll` on a closed page or context throws `Target page, context or browser has been closed`.
- Project-level `actionTimeout` and `navigationTimeout` bound `locator.click`, `page.waitForResponse`, `page.waitForURL`, `page.goto`, `page.request.get` and `browserContext.waitForEvent`, on the fixture page and on pages of `browser.newContext()`. Each failed at its bound, naming the call.
- (inference) `playwright.request.newContext()` keeps Playwright's documented 30 s request default, so it is already bounded.

**Decided in-stage.**
1. The mechanism is fixture overrides of `page` and `context`, not an auto fixture and not a `browser` dependency. Overrides start only when a test uses the fixture, so API-only tests (the `web` job's row-18 run, which has no browser) launch nothing. Their teardown runs right after the test's hooks, before Playwright closes the page.
2. Every spec imports the shared test, not only the specs that route. A static rule restricted to routing specs would miss routes installed through support helpers (`holdState`, `stubTraces` and later ones). "Every spec" is the only rule the check can enforce exactly. The cost is one import path per file. It also means a later spec that does not route is still named by the check (AC3's "a check names it" branch).
3. Contexts from `browser.newContext()` are not unrouted by the fixtures. Every such context in the tree is closed by its own test in `finally` (`host-pages`, `busy`, `reset`, `openVisitor`/`leaveVisitor`), so none outlives its test. Their pages get the online bounds through the config.
4. The `irisScript` bound comes from the project's `metadata.irisScriptMs`, read through `test.info()`. A uniform bound would cut legitimate `web/e2e` fixture waits of up to 240 s (RunnerFixture SENDSECONDS 240), and the AC scopes the bound to `web/e2e-online`.
   - 90 s exceeds every 60 s fixture wait that the online specs reach (Demo.Production WAITSECONDS 60, plus the session's start-up), and stays below the shortest online test timeout (120 s).
   - Only the Telegram fixture, whose own chain is up to 140 s, gets 150 s, so its reason, not ours, reports a real failure. L6's 300 s timeout leaves room for its `finally`.
5. Action and navigation bounds are 30 s and 60 s. Every online wait that needs longer already passes an explicit `timeout:` (for example `landedOn(..., 90_000)`, `landedOnSplash(second, 60_000)`), and an explicit timeout wins. The `(once)` runs of all five online units are the evidence.
6. `page.close()` gets no bound. It takes no timeout, and the specs call it with no `runBeforeUnload`. (inference) It does not wait on the page, and it is not in the AC's list.
7. The pinning spec goes in `web/e2e/live/`, the folder of both ledger sites, which the chromium project (`live:sign-in`) already runs. Each case is a serial leaver/follower pair, because the error lands on the test after the leaver. A reversed file order keeps each pair intact.

**Decided in implement (small, reversible, inside the intent).**
- `web/playwright.config.ts` imports `./e2e/support/bounds.ts` with the extension, because `web/scripts/playwright-projects.test.mjs` loads the config straight into Node, which resolves no extensionless relative import. `web/tsconfig.e2e.json` therefore gets `allowImportingTsExtensions: true` (it has `noEmit` and serves only the lint). Both files are footprint extensions.
- `web/scripts/rehearsal-support.test.mjs`: its source pin on `runOnce` asserted `spawn(cmd, args,`; `runOnce` now delegates the spawn to `runBounded`, so the assertion reads `runBounded(cmd, args,`. The pinned line `irisSessionCommand(process.env, irisContainer)` stays in `runOnce`. Footprint extension.
- `runBounded` takes an optional sixth parameter `detail`, so `irisScript` can add `from the script starting "<first line>"` to the message while the node test keeps the plain `<step>: no answer within <s> s` form.
- The `page` override is redundant with the `context` override's loop over `context.pages()`: removing only `unroute(page)` leaves the pinning spec green. It stays because the intent names both overrides, and the source pin in `route-cleanup.test.mjs` holds it. The pinning spec goes red on removing the page unroute and the pages loop together, and on removing the whole shared test.
- Review patches: `web/e2e/live/iris-script-bound.spec.ts` (new, hermetic, no browser: it points OCUTALON_E2E_IRIS_EXEC at a local command and sets the running project's metadata) pins `irisScript`'s message, the first line, no retry and the default bound; `bounded-waits.test.mjs` asserts the killed child is gone and reads the bounds from the loaded config instead of its text. Footprint extension: the new spec file.
- Locally `ci/iris.sh live online-demo` needs `OCUTALON_LIVE_DEADLINE=1200`, as CI sets: with the 540 s default the unit's probe phase is skipped after the 52 browser tests (414 s used), a red that is not a spec failure.

**Decided in the amend pass (bounded sign-in helper waits, AC7).**
- The shared test gives the page a default wait of a share of the test's own timeout: `waitsFor(testMs)` in `bounds.ts`, `min(cap, floor(2/3 x testMs))` with caps of 60 s (action, the default of `waitForResponse`, `waitForEvent`, `locator` waits, `page.request`) and 90 s (navigation, `goto`, `waitForURL`, `waitForLoadState`). The `context` fixture sets it with `setDefaultTimeout` and `setDefaultNavigationTimeout`, so the fixture page and every `context.newPage()` page inherit it. Results: a 45 s test (the config default) gets 30 s and 30 s; 90 s gets 60 s and 60 s; 120 s to 300 s get the caps. The expect timeout (10 s) is a separate setting and is untouched.
- Why 2/3 and these caps: every wait must fail before the test does, yet not cut a wait that is green today. Measured, not assumed: all of `live:online-session`, `live:sign-in` both parts, `live:demo-path` and `live:floor` ran green under it, with no spec given an explicit timeout (no one-line edits were needed). A looser share would leave a 45 s test almost no time to report; a smaller cap would cut the waits of the 120 s to 240 s tests that wait on a model turn without a timeout of their own.
- A project that sets `actionTimeout` or `navigationTimeout` (the five online projects: 30 s and 60 s) keeps its own: the fixture reads the option and sets nothing. A wait that passes `timeout:` keeps it.
- Many tests raise their timeout in the body (`test.setTimeout(150_000)` after the page exists), so the fixture wraps `testInfo.setTimeout` and recomputes the waits from the timeout in force. `test.slow()` called in a test body (three tests of `chat.spec.ts`) is not seen: those tests keep the share of their 45 s (30 s), and ran green. A `describe.configure({ timeout })` or a `test.slow(condition)` before the fixtures is seen at setup.
- Contexts from `browser.newContext()` are not fixtures and get no default wait in the `web/e2e` projects, as before (Design Notes 3). The shared helpers do not rely on the default: `loadedAfter`, `gotoSettled`, `signInFromSplash` and `epochOf` read the waits in force (`currentWaits()` in `navigate.ts`: the project's option when set, else `waitsFor` of the test timeout) and bound themselves.
- `loadedAfter` bounds the sign-in action with the navigation wait and the snapshot GET with the action wait, each through `boundedStep`, and fails with `loadedAfter the sign-in: no answer within <s> s` or `loadedAfter the snapshot GET /ocutalon/api/v1/state: no answer within <s> s`. The `waitForResponse` is armed before the sign-in, so its own timeout is the sum of both bounds plus 5 s: only `boundedStep`'s message can win. This is how `submitSignIn`'s POST answer and `signInReadme`'s load (in `web/e2e/sign-in/helpers.ts`, untouched) are bounded for every `loadedAfter` caller, and by the fixture default for the others.
- `gotoSettled` passes the navigation wait in force unless the options carry a timeout, turns Playwright's `TimeoutError` into `gotoSettled: no answer within <s> s from <url>` and retries once on `net::ERR_NETWORK_CHANGED` or `net::ERR_ABORTED`. Outside a test (the node test) it passes the options as they are. `navigate.ts` imports `./bounds.ts` with its extension, because `goto-settled.test.mjs` loads it straight into Node.
- `signInFromSplash` (the POST answer) and `epochOf` (so `openSession`) are bounded by the action wait in force and named (`signInFromSplash the answer to the sign-in POST`, `epochOf the GET /ocutalon/api/v1/state`).
- `effectiveWaits(testMs, use)` in `bounds.ts` is the one rule for which waits are in force (the project's option when set, else `waitsFor`); `currentWaits()` calls it, and a node test pins it. `WAIT_SLACK_MS` (5 s) is the one margin by which a wait armed before its step outlasts the helper's bound, so that the helper's message names the step.
- AC7 and the Spec Change Log supersede the Always bullet "the `web/e2e` projects keep today's waits" for the default page waits only: their fixtures' own long waits (240 s) are untouched.
- Footprint extensions of this pass: `web/e2e/live/helper-waits.spec.ts` (new pinning spec), `web/scripts/goto-settled.test.mjs` and `web/scripts/route-cleanup.test.mjs` (one pin follows the new `context` signature).

**Decided in the [CI] pass (deadline-aware bounds).**
- The cap is `capToDeadline(own)` in `bounds.ts`: `min(own, max(timeLeft - 10 s, floor))`, the floor being 5 s but never more than the time left less a second (at least 1 s). Time left is `testInfo.timeout` less the time since the shared test's auto fixture `testClock` marked the test (Playwright's `TestInfo` exposes no start time). A test that is not marked, or has no timeout, gets its own bound. `boundedStep`, `runBounded` (so `irisScript` and the Telegram fixture) and `gotoSettled` apply it at each call, so a retry and every step of a chain read the time then left. An explicit `timeout:` passed to `gotoSettled`, a bound-less `irisScript` (the `web/e2e` projects) and the waits that Playwright times itself are left as they were.
- `page.close()` of every page of the shared context is bounded by the action wait in force and the cap, in the `context` fixture (`boundedClose`, a listener on the context's `page` event), so L5's and L6's closes need no spec edit.
- A shared wait that settles after 10 s or more prints `SLOW <step> <s> s`; one that timed out prints only its error.
- Helper cases in `helper-waits.spec.ts` set the running project's waits (3 s and 4 s) so that the helper's own bound, not the cap, ends them.
- Not found: a product-path cause for L6's hang. The CI log holds no step name and no artifact; L6 passed in 8 to 9 s on four local throwaways. (inference) The hang is a chain of slow but individually bounded steps (the fixture calls are up to 150 s each) that summed past 300 s.

**Rule 1/2.**
- Shared components: `web/e2e/support/fixtures.ts` and `web/e2e/support/bounds.ts`.
- Integration ACs: AC1 and AC5. Consumer `live:sign-in`'s `live.spec.ts` (L8 then L9) and `socket.spec.ts` (W10 then W11) read `test` from the fixtures, and the unit shows no `route.fetch: Test ended`. Consumer `live:online-session`'s `leave.spec.ts` L5 and L6 run under the bounds and pass.
- Consumed-by: every spec under `web/e2e` and `web/e2e-online` in this story (the 70 files, Epic 7's `either-way.spec.ts`, and the online helpers `telegram.ts` and `support.ts` through `irisScript`); later stories' specs (Epics 33, 39 and 40), held by AC3's check.
- Consumes: Playwright 1.64.1's `test.extend` fixture overrides, `TestInfo.project.metadata`, and the project `use` options `actionTimeout` and `navigationTimeout`.
- Extend, don't copy: `fixtures.ts` replaces the 21 `afterEach` copies. `runBounded` extends `iris.ts` `runOnce`'s spawn, not a copy of it. `bounds.ts` is imported by the config and by `iris.ts`, so no number is repeated. `web/e2e-online/support.ts` needs no change, since it imports `irisScript` from `web/e2e/support/iris.ts`.

**Ledger.** DW-640 and DW-665 are addressed by AC1 and AC2 (the import on `live.spec.ts` and `socket.spec.ts`, and the pinning spec's pairs (a) and (c)). AC4 of `epics.md` (three green `iris (browser)` runs on `OCT-epic11`, with `iris (shards)` L5 and L6 green) belongs to the lead after the push, not to a stage task.

**Footprint extensions.** `web/e2e-online/telegram.ts` (one call, one import). No open epic owns it.

## Verification

Run every command from the epic worktree root (the `OCT-epic11` checkout), in the foreground with `timeout: 600000`, one live unit per call and never two in one message. `LANE` stands for this prefix:

`env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=11 stage=<stage>' OCUTALON_RUN_TAG=e11s21<stage>`

After each live unit, also after a failure, run `LANE bash ci/iris.sh teardown`. Use at most one throwaway at a time.

**Commands:**
- `(loop)` `npm --prefix web run lint`. Expected: exit 0 (tsc over every spec, the fixtures and the config).
- `(loop)` `node --test web/scripts/route-cleanup.test.mjs web/scripts/bounded-waits.test.mjs`. Expected: all pass.
- `(loop)` `npm --prefix web test`. Expected: all node tests pass, including `playwright-projects` and `rehearsal-support` with their source pins.
- `(loop)` `cd web && env -u OCUTALON_URL npx playwright test e2e/live/route-cleanup.spec.ts --project chromium`. Expected: 8 passed, with no `route.fetch: Test ended` and no `has been closed`.
- `(once, first, before any live unit)` `LANE bash ci/iris.sh build`. The bundle is rebuilt after the lead's integrate-forward (Rule 21).
- `(loop)` `LANE bash ci/iris.sh live online-session`. Expected: pass, with `leave.spec.ts` L5 and L6 in the passed list.
- `(once)` `LANE bash ci/iris.sh live sign-in --part 1/2`, then `--part 2/2` in a separate call. Expected: both pass. This holds `live.spec.ts`, `socket.spec.ts` (DW-640, DW-665), the new pinning spec and the chat, banners, rail, phone and links copies. If a part nears 9 minutes, use `--part k/3`.
- `(once)` `LANE bash ci/iris.sh live demo-path`. Expected: pass (28 of 28, and `telegram-page.spec.ts` without its five `afterEach` copies).
- `(once)` `LANE bash ci/iris.sh live floor`. Expected: pass (the nine floor copies removed; Chromium, Firefox and WebKit).
- `(once)` `LANE bash ci/iris.sh live online-demo`, then `live online-allowance`, then `live online-visitors`, then `live online-demo-path`, one per call. Expected: each passes under the online bounds.
- CI alone covers `live:answers` and `live:demo-switch` (in `iris (browser)` and `iris (shards-3)`) and `live:cards` (in `iris (shards)`), all on the pushed head. Their specs change only by the import path, and none of them held an `afterEach` copy.
- `git status --short` and `git diff --stat`. Expected: only the Code Map's files, and no leftover mutation.

**Mutations (Rule 19).** Apply each one, observe red, revert, and confirm the tree is byte-identical:
- AC1/AC2: delete the `unroute(page)` call in the `page` override. Expected red: `route-cleanup.spec.ts` pair (a)'s follower, with `route.fetch: Test ended`.
- AC2: delete the `context.pages()` loop in the `context` override. Expected red: pair (c)'s follower, with `route.fetch: Test ended`. Second mutation: delete the `unroute(context)` call. Expected red: pair (b)'s follower.
- AC2: replace the closed-target tolerance with a plain call. Expected red: pair (d)'s leaver, with `has been closed`.
- AC1/AC3: put `web/e2e/live/live.spec.ts` back on `'@playwright/test'`. Expected red: `route-cleanup.test.mjs`, naming that file. Second mutation: put the `afterEach` copy back in `chat/chat.spec.ts`. Expected red: the same test, naming that file.
- AC4: delete the timer in `runBounded`. Expected red: `bounded-waits.test.mjs`'s hang row (test timeout). Second mutation: drop the `ONLINE_WAITS` spread from the `online-session` project. Expected red: its config pin, naming `online-session`.

**Mutation results (Rule 19; each applied, red observed, reverted, tree byte-identical to the pre-mutation diff):**
- mutation: AC2 `unroute(page)` deleted from the `page` override: stays green (8 passed), because the `context` override unroutes every page. Together with the `context.pages()` loop deleted: red, pair (a) and pair (c) followers, `route.fetch: Test ended`. The base Playwright `test` with no overrides: red, the followers of (a), (b) and (c).
- mutation: AC2 `context.pages()` loop deleted: red, pair (c) follower, `route.fetch: Test ended`. `unroute(context)` deleted: red, pair (b) follower, `route.fetch: Test ended`.
- mutation: AC2 closed-target tolerance replaced by a plain call: red, pair (d) leaver, `page.unrouteAll: Target page, context or browser has been closed` (its follower did not run).
- mutation: AC1/AC3 `live/live.spec.ts` back on `'@playwright/test'`: red, `route-cleanup.test.mjs` names `e2e/live/live.spec.ts`. An `afterEach` unroute copy back in `chat/chat.spec.ts`: red, same test, names `e2e/chat/chat.spec.ts:27`.
- mutation: AC4 the timer in `runBounded` disabled: red, `bounded-waits.test.mjs` hang rows (5 s test timeout). `ONLINE_WAITS` spread dropped from `online-session`: red, config pin, `online-session`.

- mutation: AC2 `unrouteAll({ behavior: 'ignoreErrors' })` reduced to `unrouteAll()` in `unroute`: red, pair (a), (b), (c) followers, `route.fetch: Test ended`, and the `fixtures.ts` source pin.
- mutation: AC4 `child.kill('SIGKILL')` deleted from `runBounded`: red, `bounded-waits.test.mjs` "kills the command itself". `currentBound()` made to return undefined: red, `iris-script-bound.spec.ts` "the project bound applies when the call passes none" (45 s, the unbounded sleep). The detail dropped from `runOnce`'s step label: red, the first two `iris-script-bound.spec.ts` tests. `TELEGRAM_FIXTURE_MS` dropped from `telegram.ts` `fixture()`: red, its pin.
- mutation: AC4 `metadata: { irisScriptMs }` dropped from `online-session`: red, `bounded-waits.test.mjs` "gives each online project ...", `online-session: metadata.irisScriptMs`. The `ONLINE_WAITS` spread dropped from it: red, same test, `online-session: use.actionTimeout`.
- AC5 and AC6 have no mutation: AC5 is the live proof on the stack (the L5 and L6 hang this story bounds cannot be re-created cheaply), AC6 is the `git diff --stat` check.
- mutation: AC7 the `testInfo.setTimeout` wrapper removed from the `context` override: red, `helper-waits.spec.ts` "the shared test bounds a wait that has no timeout of its own" and "... a navigation ..." (`Test timeout of 9000ms exceeded`, the 30 s default being in force). `giveWaits` made a no-op: red, the same two.
- mutation: AC7 the `boundedStep` of the snapshot GET in `loadedAfter` replaced by `await state`: red, `helper-waits.spec.ts` "a snapshot that is never answered" (`Test timeout of 12000ms exceeded`). The `boundedStep` of the sign-in replaced by `await signInAction()`: red, "a sign-in that never ends" (same).
- mutation: AC7 `gotoSettled`'s bound removed (`wait` always undefined): red, `helper-waits.spec.ts` "gotoSettled: a navigation that is never answered" (`Test timeout of 12000ms exceeded`). The ERR_ABORTED retry removed from `RETRYABLE`: red, `goto-settled.test.mjs`, the two ERR_ABORTED rows.
- mutation: AC7 `signInFromSplash` returning `answered` unbounded (the `boundedStep` removed): red, `helper-waits.spec.ts` "signInFromSplash: a sign-in POST that is never answered" (`Test timeout of 12000ms exceeded`). `epochOf` awaiting `asked` unbounded: red, "epochOf: a state GET that is never answered" (same).
- mutation: AC7 `giveWaits` made a no-op (checked on `helper-waits.spec.ts` "the shared test bounds ..."): red, the wait case, the second-page navigation case and the navigation case (test timeout), so the context-wide default is pinned for a `context.newPage()` page too.
- mutation: AC7 `effectiveWaits` ignoring the project's options: red, `bounded-waits.test.mjs` "keeps the waits that the project sets". `boundedStep`'s timer delay multiplied by 1000: red, "rejects at its bound" (5 s test timeout). `WAIT_SHARE` set to 1: red, "gives a test a share of its timeout" and the `effectiveWaits` row.
- Every mutation above was reverted; `fixtures.ts`, `floor.ts`, `navigate.ts`, `bounds.ts` and `e2e-online/support.ts` were compared byte for byte with copies taken before the mutations.

**Verification results (implement stage):**
- `npm --prefix web run lint`: exit 0. `node --test` of the two new files: 25 passed. Hermetic `route-cleanup.spec.ts` and `iris-script-bound.spec.ts`: 11 passed. `npm --prefix web test`: 1330 of 1330. Hermetic `route-cleanup.spec.ts` on Chromium: 8 passed.
- `ci/iris.sh build`, then each unit on its own lane-B throwaway, torn down after each: `live online-session` 13 passed (L5 and L6 among them); `live sign-in --part 1/2` 138 passed; `--part 2/2` 124 passed (re-run after the review patches: 138 and 127 passed, the new `iris-script-bound.spec.ts` among them; `live online-session` re-run: 13 passed; the other units ran before the patches, which touched no code they run: comments, tests and the config's already-loaded values) (`live.spec.ts`, `socket.spec.ts` and `route-cleanup.spec.ts` among them); `live demo-path` 28 passed; `live floor` 107 passed; `live online-demo` 52 passed (with `OCUTALON_LIVE_DEADLINE=1200`, see Design Notes); `live online-allowance` 12 passed; `live online-visitors` 1 passed; `live online-demo-path` 7 passed.

**Verification results (amend pass, AC7):**
- `npm --prefix web run lint`: exit 0. `npm --prefix web test`: 1365 of 1365 (`route-cleanup`, `bounded-waits` and `goto-settled` among them; `route-cleanup.test.mjs` is green with `either-way.spec.ts` on the shared import). Hermetic `helper-waits.spec.ts` (5 passed), `route-cleanup.spec.ts` and `iris-script-bound.spec.ts` (11 passed) on Chromium.
- After the amend patches, each on its own lane-B throwaway (`e11s21impl2`), torn down after each: `ci/iris.sh build`; `live online-session` 13 passed (L5 and L6 among them); `live sign-in --part 1/2` 138 passed; `--part 2/2` 132 passed (`helper-waits.spec.ts` among them); `live demo-path` 28 passed; `live floor` 107 passed. No spec needed an explicit timeout.
- After the review patches (the helper cases added, `effectiveWaits` and `WAIT_SLACK_MS` extracted, no behaviour change): lint exit 0; `npm --prefix web test` 1366 of 1366; hermetic `route-cleanup`, `iris-script-bound` and `helper-waits` (8 cases) 19 passed; `live online-session` 13 passed; `live sign-in --part 2/2` 135 passed; `live online-allowance` 12 passed; `live online-visitors` 1 passed and `live online-demo-path` 7 passed (`OCUTALON_LIVE_DEADLINE=1200`); `live online-demo` 52 passed (same deadline). `live demo-path` and `live floor` were not re-run after the review patches: the patches changed no code that unit runs other than a behaviour-identical extraction.

**QA gap audit (qa stage):** no AC or matrix row lacked a pinning test, so no test file was added; AC5 (live proof) and AC6 (`git diff` footprint) have no mutation. `web/e2e/live/iris-script-bound.spec.ts` lost one elapsed-time assertion (`< 4000` ms; the spec's own test timeout already fails an unbounded run). Re-run: lint exit 0; 47 node tests (`route-cleanup`, `bounded-waits`, `goto-settled`) passed; 19 hermetic Chromium tests passed.
- mutation (QA): AC1 `e2e/live/socket.spec.ts` back on `'@playwright/test'` → `route-cleanup.test.mjs` red, naming `e2e/live/socket.spec.ts`.
- mutation (QA): AC2 `context.pages()` loop deleted from the `context` override → `route-cleanup.spec.ts` pair (c) follower red, `route.fetch: Test ended`.
- mutation (QA): AC3 a new `e2e/zz-qa-probe.spec.ts` importing `test` from `@playwright/test` → `route-cleanup.test.mjs` red, naming that file.
- mutation (QA): AC4 `metadata.irisScriptMs` dropped from `online-visitors` → `bounded-waits.test.mjs` red, `online-visitors: metadata.irisScriptMs`.
- mutation (QA): AC7 `loadedAfter`'s sign-in `boundedStep` replaced by `await signInAction()` → `helper-waits.spec.ts` "loadedAfter: a sign-in that never ends" red (`Test timeout of 12000ms exceeded`).
- Each reverted from a copy taken first; `git status --short` showed only the `iris-script-bound.spec.ts` edit afterwards.
- mutation (code review): AC4 `irisScript` retries a timed-out `runOnce` (catch, wait 5 s, continue) → `iris-script-bound.spec.ts` "... and is not tried again" red (`Received length: 3`, the session was started three times).
- mutation (code review): AC4 the fixture's `if (!actionTimeout)` / `if (!navigationTimeout)` guards removed → `helper-waits.spec.ts` "a project that sets its own waits > keeps them" red (`Timeout 2000ms exceeded` expected, 6000 ms in force).
- mutation (code review): AC3 `route-cleanup.test.mjs` `TEST_FILE` narrowed back to `/\.spec\.ts$/` → its row "walks every file name that Playwright runs as a test" red.
- Code review re-run after the patches: lint exit 0; `npm --prefix web test` 1367 of 1367; hermetic `route-cleanup`, `iris-script-bound` and `helper-waits` 20 passed; `live cards` 28, `live answers` 23, `live demo-switch` 6 + 23 passed on lane-B throwaways. Each mutation reverted from a copy; `git status --short` and `git diff --stat` identical to before.

- mutation: [CI] `boundedStep` without `capToDeadline`: red, `deadline-cap.spec.ts` "boundedStep: a step with a long bound ..." (`Test timeout of 12000ms exceeded`). `runBounded` without it: red, the `irisScript` case (same). `gotoSettled` without it: red, its case (same).
- mutation: [CI] `markTestStart` removed from the shared test: red, the `boundedStep`, `irisScript` and `gotoSettled` cases (test timeout). `testTimeLeftMs` ignoring the elapsed time: red, "the time the test has already used is counted" (10 s bound against the expected 5 s) and the retry case. The cap hoisted out of `gotoSettled`'s `go` (stale for the retry): red, the retry case.
- mutation: [CI] the `context.on('page', ...)` listener of `boundedClose` removed: red, "the shared test bounds the close of the fixture page and of a page of the context" (`Object.hasOwn(page, 'close')` false).
- mutation: [CI] `if (!over)` and `if (!timedOut)` removed from the SLOW reports: red, `bounded-waits.test.mjs` "boundedStep prints it ..." and "runBounded prints it ...". The `slowLine` threshold `>` instead of `>=`: red, its row. The margin dropped from `capToDeadline`, and the floor clamp removed: red, "shortens a bound to the time left ...".
- mutation: [CI] `loadedAfter`'s snapshot bound lengthened (`waits.action * 20`): red, `helper-waits.spec.ts` "loadedAfter: a snapshot that is never answered ..." (5 s with the cap note, against the own 3 s). This replaces the AC7 lines above for the helper cases: with a bound removed they now fail on the message and on the test timeout alike.
- Every [CI] mutation was reverted from a copy taken first; `bounds.ts`, `navigate.ts`, `floor.ts` and `fixtures.ts` were compared byte for byte afterwards.

**Verification results ([CI] pass):**
- `npm --prefix web run lint`: exit 0. `npm --prefix web test`: 1376 of 1376 (before the last two-line deletion; the touched files re-ran: `bounded-waits` and `route-cleanup` 42 passed). Hermetic Chromium: `route-cleanup`, `iris-script-bound`, `helper-waits` and `deadline-cap` 27 passed, then `deadline-cap` 7 passed after the last patch.
- Lane-B throwaways (tag `e11s21impl3`), one per call, torn down after each: `live online-session` 13 passed with L5 and L6 green (L6 8 to 9 s), six runs in all, the last two after the last patch; `live sign-in --part 1/2` 142 passed and `--part 2/2` 139 passed after the review patches (142 and 137 before them). No `SLOW` line appeared in any run.

**Shared surfaces:**
- the import line of every spec under `web/e2e` and `web/e2e-online`
- the chromium project's spec list and `live:sign-in`'s part cuts (one new file, `web/e2e/live/route-cleanup.spec.ts`, read from disk by `playwright-projects.test.mjs` and `e2e-part.mjs`)
- the `web/scripts` node test set (two new files)
- the online projects' `use` and `metadata` in `web/playwright.config.ts`
- `irisScript`'s signature (a new optional second parameter)
- `runOnce`'s body (pinned by `rehearsal-support.test.mjs`)

Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

This section covers the rework pass of iteration 3 (the `[CI]` item) only.

**Summary.** Every shared bounded wait now also stops at the time its test has left less 10 s (floor 5 s, never more than the time left less a second): `boundedStep` (so `loadedAfter`, `signInFromSplash`, `epochOf`), `runBounded` (so `irisScript` and the Telegram fixture) and `gotoSettled`, so the last step of a slow chain fails naming itself and the spec's `finally` runs. The shared test marks each test's start (auto fixture) and bounds `page.close()` of every page of its context (`page.close: no answer within <s> s`), which covers L5's and L6's closes with no spec edit. A shared wait that took 10 s or more prints `SLOW <step> <s> s`. No product path was found behind L6's hang (see Design Notes).

**Files changed.** `web/e2e/support/{bounds,fixtures,navigate,iris}.ts` (iris.ts: the doc comment of `irisScript` only), `web/e2e/live/deadline-cap.spec.ts` (new, hermetic, 7 cases), `web/e2e/live/helper-waits.spec.ts` (helper cases run under the project's own waits), `web/scripts/{bounded-waits,goto-settled,route-cleanup}.test.mjs`.

**Review.** 35 findings (medium 5, low 27, false 3). Patched 17 rows (medium 3, low 14): floor clamp and docs, helper cases pinning their own bounds, SLOW consistency, rows for the elapsed time, the retry, the SLOW lines and the close options, a dead loop deleted. Deferred: none. Rejected: 18 rows, each with its reason in the triage log (the margin and the cleanup floor are the item's own; explicit timeouts and bound-less `irisScript` stay as the story set them).

**Follow-up review recommended:** false (this pass patched no high).

**Verification.** See Verification results ([CI] pass).

**Residual risks.** (1) The root cause of the CI hang is unconfirmed: it did not reproduce locally and the log names no step. (2) A `finally` that starts after the body was cut at the margin gets at most the 5 s floor per call, so `finishTelegram` may still be killed and leave TelegramIn live; that red would now name the step and carry SLOW lines. (3) Playwright's own waits with an explicit timeout (`expect.poll`, `landedOn`) are not capped. (4) `page.close()` is bounded only on the shared context's pages.
