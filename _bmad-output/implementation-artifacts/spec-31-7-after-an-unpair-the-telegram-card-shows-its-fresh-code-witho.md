---
title: 'Story 31.7: after an unpair, the Telegram card shows its fresh code without a gap'
type: 'bugfix'
created: '2026-11-03'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the integrate-forward head e75b90bc, T6 in `web/e2e/demo-path/telegram-page.spec.ts` saw the unpaired view 8169 ms and 8063 ms after "Telegram unpaired" appeared, against a bound of 8000 ms (line 891, second `watchWindow` at line 955), on CI runner 20, twice. Story 31.1's WebSocket delivers pairing events at once, so a new pairing round can start less than `CODE_SPACING_MS` (10 s) after the card's previous code request. The round's first request then waits out the spacing, and the code arrives after the 5 s "Telegram unpaired" view has ended. In between, the card is blank (`kind: 'none'`).

**Approach:** The first code request after each unpair goes out at once. An unpair is the store's `paired` turning true to false: the page's Unpair, a /stop, or a move. Every other request keeps the 10 s spacing and the 30 s retry. The card's request timing moves out of the Angular component into its framework-free module, `telegram-card-view.ts`, so that Node unit tests on a fake clock can pin both halves.

## Boundaries & Constraints

**Always:**
- Only one request is exempt per unpair: the first request that goes out after it. Every later request is spaced again, at least `CODE_SPACING_MS` after the previous one. This covers the next request of that round (a due time, a retry) and the first request of any round that starts without an unpair (a pause ending, a state or bot-name change, a refusal clearing).
- A failed request (not a 409) asks again `CODE_RETRY_MS` (30 s) later. A 409 shows the not-set-up view and stops asking until the key changes. A code's due time is `dueTime` (the earlier of its expiry and 10 minutes). All three are unchanged.
- The spacing still counts across rounds, so it outlives one asking, as `lastRequest` does today.
- The first value the card sees never counts as an unpair.
- Everything else the card does stays as it is: its views, their order, its announcements, its focus behaviour, its texts, the 5 s window, its countdown, and keeping the code only in memory, the link and the QR code.
- Doc comments state the new contract by replacing the old sentence (Rule 14). The card's own comment (lines 41-44, 56-60) currently says "never sooner than ten seconds after its previous request" and "usually held".

**Never:**
- Don't edit `web/e2e/demo-path/telegram-page.spec.ts` or any other e2e spec. T6's bound stays at 8000 ms.
- Don't change the server: `Web/Api.cls` `PairingCode` (line 691) and every class under `src/`.
- Don't change `CODE_SPACING_MS`, `CODE_RETRY_MS`, `JUST_UNPAIRED_MS` or `CODE_LIFETIME_MS`.
- Don't touch a Lane A file outside `web/src/app/rail/telegram-card/**` and `web/scripts/telegram-card-view.test.mjs`. Don't touch `status-rail.ts`, `live/**` or `api/**`.
- Add no new file under `web/src` (`page-safety.test.mjs` lists the app's files), no new dependency, and no new page string.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Unpair inside 10 s (T6's move) | The last request was 2 s ago; `paired` turns true to false | The round's first request goes out at once (0 ms wait), and the code is held before the 5 s view ends | No error expected |
| Unpair long after | The last request was over 10 s ago (T5, T6's /stop) | Asks at once, as today | No error expected |
| The exempt request's code is due at once | Expiry in the past or unreadable | The next request waits until 10 s after the exempt one | No error expected |
| The exempt request fails | 500 or network error | Shows nothing, then asks again 30 s after the failure, with no second exemption | Retry as today |
| The exempt request is refused | 409 | The not-set-up view; asking stops until the key changes | As today |
| A new round with no unpair | A pause ends, or the state, bot name or refusal changes, inside 10 s of the last request | Waits until 10 s after the last request | No error expected |
| Two unpairs | Unpair, request, pair again, unpair, all inside 10 s | Each unpair's first request goes out at once (one exemption per unpair) | No error expected |
| Several unpairs before any request | `paired` turns true to false twice with no request in between | One exemption only: the first request goes out at once, and the request after it is spaced | No error expected |
| First value | A page loaded unpaired or paired | No exemption; the first ever request goes out at once (no previous request) | No error expected |

</intent-contract>

## Code Map

- `web/src/app/rail/telegram-card/telegram-card.ts` -- the component.
  - `lastRequest` (L210) is the spacing state.
  - The asking effect (L269-281) runs on each `askKey` change: it clears the held code, and returns early when the key is "" or refused.
  - `ask(key)` (L292-326):
    - `later(at)` (L296-298) waits `max(at, lastRequest + CODE_SPACING_MS) - now`; this is the delay that causes the gap;
    - `send` (L299-319) handles success with `later(due)`, a 409 with `refusedAt`, and any other failure with `later(now + CODE_RETRY_MS)`;
    - `later(0)` (L320) starts it, and the function it returns cancels the timer and the subscription.
  - The pairing effect (L248-267) detects true to false for the just-unpaired view. Don't grant the exemption there (Design Notes D2).
- `web/src/app/rail/telegram-card/telegram-card-view.ts` -- the framework-free module (erasable TS only, imports only types and the QR library). It holds `CODE_SPACING_MS` (L57), `CODE_RETRY_MS` (L60), `JUST_UNPAIRED_MS` (L51), `dueTime` (L122) and `asksForCode` (L112). The timing schedule goes here.
- `web/src/app/live/contact-watch.ts` -- the sibling pattern: a framework-free class with injected `setTimeout` and `clearTimeout`, tested on a fake clock.
- `web/scripts/fake-clock.mjs` -- the fake clock to reuse: `setTimeout`, `clearTimeout`, `advance`, `now` and `pending`.
- `web/scripts/telegram-card-view.test.mjs` -- the card's own unit spec, run with `node --test`. Extend it (Rule 2).
- `web/scripts/page-safety.test.mjs`, `announce-focus-sources.test.mjs`, `ux-strings.test.mjs` -- scan the card's files. They must stay green, with no new file and no new string.
- `web/e2e/demo-path/telegram-page.spec.ts` (read-only). It holds the e2e tests that cover the card's request timing:
  - T3 (L428): spacing inside a round, 9-16 s gaps, "no third request within 8.5 s";
  - T4 (L560): refused gets one request and none within 3 s; a 500 asks again only later;
  - T5 (L716): the page's Unpair;
  - T6 (L901, `watchWindow` L868-892): the pinning e2e test.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` L685-701 (read-only): `PairingCode` has no spacing of its own.

## Tasks & Acceptance

**Execution:**
- `web/src/app/rail/telegram-card/telegram-card-view.ts` -- Add a framework-free code-request schedule class, with injected `setTimeout`, `clearTimeout` and `now`. It owns:
  - the spacing memory, the last request time, which outlives one asking;
  - the one-shot unpair exemption: granted on a true-to-false `paired` change, never for the first value, and used up by the next request that goes out;
  - one asking at a time: request now, or as soon as the spacing allows; after a code, again at its due time; after a failure, `CODE_RETRY_MS` later; after a refusal, stop. Starting it returns its stop function.

  The component keeps the HTTP call and the signals, and the schedule decides only *when*. Update the module doc comment. Names are the implementer's choice; the behaviour is the contract. -- This is the fix, in a module Node can test.
- `web/src/app/rail/telegram-card/telegram-card.ts` -- Replace `lastRequest`, `later` and the timing inside `ask` with one schedule instance per card, built with `globalThis` timers and `Date.now`. On each run, before it starts an asking, the asking effect tells the schedule the current `paired` value, read untracked (D2). Rewrite the class doc's sentences on spacing and timing (L41-44, L56-60) to state the new contract. -- This wires the fix into the card without depending on the order in which effects run.
- `web/scripts/telegram-card-view.test.mjs` -- Extend it with a `describe` for the schedule on `fakeClock()`, covering every Matrix row:
  - the constants are 10 000 ms and 30 000 ms;
  - after an unpair, the request goes out at once, even 2 s after the last one (0 ms on the fake clock);
  - a new round with no unpair, inside 10 s, waits until exactly last + 10 000 ms (not one ms sooner);
  - after the exempt request, a code that is due at once waits until 10 s after it;
  - a failure asks again exactly 30 000 ms later, with no exemption;
  - a refusal stops asking (`pending` is 0);
  - one exemption per unpair, and two unpairs with no request in between still give one;
  - the first value grants nothing;
  - stop clears the timer.

  Add one source pin: `telegram-card.ts` builds the schedule and tells it `paired` inside the asking effect, before it starts asking, and keeps no `lastRequest` or own spacing arithmetic. Update the file's header comment. -- These are the Planner's condition and Rule 19.

**Acceptance Criteria:**
- AC1: Given a schedule whose last request went out 2 s ago, when `paired` turns true to false and a new asking starts, then the request goes out at once (unit, fake clock).
- AC2: Given an unpair whose exempt request has gone out, when the next request is wanted within 10 s (a code due at once, or a new round with no unpair), then it waits until 10 s after the previous request (unit).
- AC3: Given any request that fails with a status other than 409, the exempt one included, when the schedule reacts, then it asks again exactly `CODE_RETRY_MS` (30 s) later; and a 409 stops asking (unit).
- AC4: Given the card component, when its asking effect starts an asking, then it has told the schedule the current `paired` value first, and the component keeps no spacing of its own (source pin in the card's spec).
- AC5: Given the real stack (`ci/iris.sh live demo-path`, after `ci/iris.sh build`), when T6 runs /stop and the move, then each `watchWindow` sees the unpaired view between 4500 and 8000 ms after "Telegram unpaired" appeared, and T1 to T7 all pass (UX-DR14).

## Spec Change Log

## Review Triage Log

## Design Notes

**Task 0 (code reading at 121c0185; the analysis is confirmed).**
- Between the store's `paired` turning false and the code request, the only delay is in `later(0)`: `Math.max(at, this.lastRequest + CODE_SPACING_MS) - Date.now()` (`telegram-card.ts:297`). `PairingCode` (`Api.cls:691`) has no spacing of its own. `lastRequest` is kept across rounds (L209-210).
- The CI numbers fit this (inference; no timestamps were captured):
  - The page-load request is at t0. With live events at once, the steps from load to /stop take under 10 s, so the /stop round's request goes out at t0 + 10 s. Its code arrives late in the first window, but within 8 s.
  - The move follows about 2 s after that window ends (the `codeOf` and Pair fixtures). The move round's request then waits until 10 s after the /stop round's request, about 8 s after the move. That matches 8063 and 8169 ms.
  - With the fix, both rounds' first requests go out at once, so each code is held long before the 5 s view ends.
- No measurement was taken; code reading is enough, as the dispatch allows.

**Governing ADs (Rule 6).**
- AD-12: live events, with the WebSocket on local installs. It is the trigger, and is unchanged.
- AD-4: the pairing code is plaintext only in the HTTP response, and a new code replaces the session's earlier one. The exempt request uses the same route, so this is unchanged.
- AD-14: Telegram, and the QR code drawn in the browser. Unchanged.
- AD-29: lane files. `web/src/app/rail/telegram-card/**` and its unit spec are a footprint extension for this story only (U-243).

No AD Rule is contradicted. UX-DR14's "Telegram unpaired" 5 s is the timing this story protects. The 10 s spacing is an implementation detail; no PRD or UX target names it. The spine needs no change.

**Decided in-stage (unattended, small, reversible):**
- **D1. The timing moves into `telegram-card-view.ts`.** The Planner's condition asks the card's own unit spec to pin the immediate request and also the unchanged spacing and retry. That timing lives in an Angular component, and Node cannot run one. So the schedule moves into the card's existing framework-free module, the one the spec already imports. It follows `ContactWatch`'s injected-timer pattern and reuses `fake-clock.mjs`, with no new file (Rule 2: this extends the module rather than adding a sibling). The behaviour stays the same, apart from the exemption.
- **D2. The exemption is granted in the asking effect, not in the pairing effect.** Both effects react to one store change, and their relative order is not a contract. If the asking effect ran first, its request would already be scheduled with the spacing before a grant in the pairing effect landed. So the asking effect passes `paired` to the schedule (read untracked) just before it starts asking, and the schedule detects the true-to-false change itself.

  The edge case: the asking effect runs only when `askKey` changes. An unpair during a pause therefore grants when the pause ends and asking starts again, which still counts as "the first request after an unpair".
- **D3. The exemption costs no safety.** The spacing guards against a browser clock ahead of the server's, which would re-ask at each due time. An unpair comes from a user or a chat, never from the card's own timer, and gives one request, so the card still cannot loop.
- **D4. Real-runtime evidence (Rule 3) is T6, unchanged.** The source pin (AC4) is the cheap, local mutation target for the wiring. T6's red on the defect was seen twice on CI, on e75b90bc on runner 20. A local red without the fix depends on machine timing and is not guaranteed (inference).

**Integration ACs (Rule 1).** There is no new service: the card's own module is extended.
- **Consumes:** Story 12.3's asking and Story 12.5's just-unpaired view (`telegram-card.ts`), and Story 31.1's WebSocket pairing events (via `LiveState`; unchanged).
- **Consumed-by:** none. The schedule is private to the card.

**Footprint:** `web/src/app/rail/telegram-card/telegram-card.ts`, `telegram-card-view.ts` and `web/scripts/telegram-card-view.test.mjs`. Report these under `footprint_extensions:` (ruled under U-243). Ledger inbox: none.

## Verification

Use these variables on every `ci/iris.sh` call:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=31 stage=<stage>'
```

Use the tag `e31s7i` in implement; the lead's smoke uses its own `e31s7*` tag.

Run rules:
- Run one call at a time, in the foreground, with `timeout: 600000`. Never background a call and never use `Monitor`.
- If the harness moves a call to the background, poll its output in loops under 170 s, and never start a second copy.
- This story needs no IRIS MCP call. If you make one, it goes only to server `ocutalon-slot-a`, namespace `OCUTALON`, after `iris_server_info`.
- Never use a real model key or a real Telegram bot.

**Shared surfaces:** none of the lists, menus, rosters, schemas or counts that other tests assert on. The card's request timing is asserted by T3, T4, T5 and T6 (`telegram-page.spec.ts`), and all four must pass unchanged. The standing criterion is that every test added or changed passes on a fresh environment, in either order. The unit tests are hermetic (fake clock, no shared state), and the live unit starts a fresh throwaway.

**Commands:**
- (loop) `node --test web/scripts/telegram-card-view.test.mjs` -- expected: every case passes.
- (once) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes, including `page-safety`, `announce-focus-sources` and `ux-strings`.
- (once) `bash ci/checks.sh` -- expected: every block passes, including `test-boundaries` (ASCII, and no local path).
- (once) `OCUTALON_RUN_TAG=e31s7i ci/iris.sh build` -- expected: `BUILD the web bundle is built from this checkout`. This is also the app's type check (`ng build`).
- (once) `OCUTALON_RUN_TAG=e31s7i ci/iris.sh live demo-path` -- expected: passes. T1 to T7 are green, and T6's two windows are within 4500 to 8000 ms.
- (once) `OCUTALON_RUN_TAG=e31s7i ci/iris.sh teardown` -- expected: only the `e31s7i` projects are removed.

**Mutations (Rule 19; apply one, observe red, revert, then confirm `git status --short` and `git diff --stat` are unchanged):**
- AC1: make the exemption grant a no-op. Expected red: the unit case "after an unpair, the request goes out at once".
- AC2: never use up the exemption after a request. Expected red: the unit case "after the exempt request, a code that is due at once waits until 10 s after it".
- AC3: retry after a failure with the spacing in place of `CODE_RETRY_MS`. Expected red: the unit case "a failure asks again exactly 30 000 ms later".
- AC4: delete the component's call that passes `paired` to the schedule. Expected red: the source pin.
- AC5: the pre-fix head e75b90bc, where T6 was seen red twice on CI runner 20. A local red is not required (D4).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
