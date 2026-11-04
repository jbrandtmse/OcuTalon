---
title: "Story 11.21: A test's route callback never outlives its test"
type: 'bugfix'
created: '2026-11-04'
status: 'done'
baseline_revision: '79a8aca3e2016d544fc3fc4f1e18f353a9629eb3'
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

**Acceptance Criteria:**
- AC1 (one mechanism, DW-640, DW-665). Given every spec under `web/e2e` and `web/e2e-online`, when a test ends, then its routes are removed by the shared fixtures with `unrouteAll({ behavior: 'ignoreErrors' })`, no spec carries its own `afterEach` copy, and `route-cleanup.test.mjs` is green.
- AC2 (pinned). Given a route callback still waiting on `route.fetch` when its test ends (on the page, the context, or a second page of the context), when the next test runs, then neither fails with `route.fetch: Test ended`, and a page the test closed itself makes no error. `route-cleanup.spec.ts` is green in Chromium with no stack.
- AC3 (later specs). Given a spec added later under `web/e2e` or `web/e2e-online` that imports `test` from `@playwright/test`, when the `web` job runs, then `route-cleanup.test.mjs` fails and names the file. A spec that imports the shared test is covered with no further edit, including routes installed through a support helper.
- AC4 (bounded online waits). Given a test of an online project, when an `irisScript` session, a page action, a navigation, a response wait or a page request never answers, then it fails on its own bound (90 s, or 150 s for the Telegram fixture; 30 s; 60 s), well under the 120 to 300 s test timeouts, naming the step. `bounded-waits.test.mjs` is green.
- AC5 (proof on the stack). Given the story's tree on a lane-B throwaway, when `live:online-session` runs, then it passes with `leave.spec.ts` L5 and L6 green. When the `(once)` units run, each passes.
- AC6 (footprint). Given the diff since `story_base`, excluding `_bmad-output`, when listed, then it holds only the files in the Code Map and the spec import lines.

## Spec Change Log

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

**Rule 1/2.**
- Shared components: `web/e2e/support/fixtures.ts` and `web/e2e/support/bounds.ts`.
- Integration ACs: AC1 and AC5. Consumer `live:sign-in`'s `live.spec.ts` (L8 then L9) and `socket.spec.ts` (W10 then W11) read `test` from the fixtures, and the unit shows no `route.fetch: Test ended`. Consumer `live:online-session`'s `leave.spec.ts` L5 and L6 run under the bounds and pass.
- Consumed-by: every spec under `web/e2e` and `web/e2e-online` in this story (the 70 files, Epic 7's `either-way.spec.ts`, and the online helpers `telegram.ts` and `support.ts` through `irisScript`); later stories' specs (Epics 33, 39 and 40), held by AC3's check.
- Consumes: Playwright 1.64.1's `test.extend` fixture overrides, `TestInfo.project.metadata`, and the project `use` options `actionTimeout` and `navigationTimeout`.
- Extend, don't copy: `fixtures.ts` replaces the 21 `afterEach` copies. `runBounded` extends `iris.ts` `runOnce`'s spawn, not a copy of it. `bounds.ts` is imported by the config and by `iris.ts`, so no number is repeated. `web/e2e-online/support.ts` needs no change, since it imports `irisScript` from `web/e2e/support/iris.ts`.

**Ledger.** DW-640 and DW-665 are addressed by AC1 and AC2 (the import on `live.spec.ts` and `socket.spec.ts`, and the pinning spec's pairs (a) and (c)). AC4 of `epics.md` (three green `iris (browser)` runs on `OCT-epic11`, with `iris (shards)` L5 and L6 green) belongs to the lead after the push, not to a stage task.

**Footprint extensions.** `web/e2e-online/telegram.ts` (one call, one import). No open epic owns it.

## Verification

Run every command from the worktree root `/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/epic-11`, in the foreground with `timeout: 600000`, one live unit per call and never two in one message. `LANE` stands for this prefix:

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

**Verification results (implement stage):**
- `npm --prefix web run lint`: exit 0. `node --test` of the two new files: 25 passed. Hermetic `route-cleanup.spec.ts` and `iris-script-bound.spec.ts`: 11 passed. `npm --prefix web test`: 1330 of 1330. Hermetic `route-cleanup.spec.ts` on Chromium: 8 passed.
- `ci/iris.sh build`, then each unit on its own lane-B throwaway, torn down after each: `live online-session` 13 passed (L5 and L6 among them); `live sign-in --part 1/2` 138 passed; `--part 2/2` 124 passed (re-run after the review patches: 138 and 127 passed, the new `iris-script-bound.spec.ts` among them; `live online-session` re-run: 13 passed; the other units ran before the patches, which touched no code they run: comments, tests and the config's already-loaded values) (`live.spec.ts`, `socket.spec.ts` and `route-cleanup.spec.ts` among them); `live demo-path` 28 passed; `live floor` 107 passed; `live online-demo` 52 passed (with `OCUTALON_LIVE_DEADLINE=1200`, see Design Notes); `live online-allowance` 12 passed; `live online-visitors` 1 passed; `live online-demo-path` 7 passed.

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

**Summary.** One shared Playwright `test` (`web/e2e/support/fixtures.ts`) overrides `page` and `context` and ends every test with `unrouteAll({ behavior: 'ignoreErrors' })` on the page, every page of the context and the context. All 70 specs under `web/e2e` and `web/e2e-online` import it, and the 21 `afterEach` copies are gone. The online projects bound actions (30 s), navigations (60 s) and `irisScript` sessions (90 s, 150 s for the Telegram fixture), and a timed-out session is killed, never retried, and named by its first line.

**Files changed.** `web/e2e/support/fixtures.ts` (new, the shared test); `web/e2e/support/bounds.ts` (new, bounds and `runBounded`); `web/e2e/support/iris.ts` (`runOnce`, `irisScript`); `web/e2e-online/telegram.ts` (fixture bound); `web/playwright.config.ts` (online projects' waits and metadata); 70 spec files (one import line each, 21 hooks deleted); `web/e2e/live/route-cleanup.spec.ts` (new, the AC2 pairs); `web/e2e/live/iris-script-bound.spec.ts` (new, hermetic `irisScript` bound); `web/scripts/route-cleanup.test.mjs` and `web/scripts/bounded-waits.test.mjs` (new, hosted `web` job). Footprint extensions: `web/tsconfig.e2e.json` (`allowImportingTsExtensions`), `web/scripts/rehearsal-support.test.mjs` (one pin follows `runOnce`), `web/e2e-online/telegram.ts`, `web/e2e/live/iris-script-bound.spec.ts`.

**Review.** Patches applied: 3 medium, 4 low (child-killed assertion, hermetic `irisScript` spec, config pin on loaded values, mutation lines, two comment corrections). Deferred: 1 low (local online-demo deadline default). Rejected: the rest, each with its reason in the triage log.

**Follow-up review recommended:** false (no high patched, one medium-class patch group only).

**Verification.** See the Verification section: lint, 1330 node tests, 11 hermetic Chromium tests, and every live unit named there green on lane-B throwaways, each torn down.

**Residual risks.** A timed-out `irisScript` kills the local client only, not the in-container session. The `page` override is covered by the source pin, not by a failing test. Online waits that need more than 30 s must pass an explicit timeout. AC4 (three green `iris (browser)` runs) is the lead's after the push.
