---
title: 'Story 31.7: after an unpair, the Telegram card shows its fresh code without a gap'
type: 'bugfix'
created: '2026-11-03'
status: 'done'
baseline_revision: '9436ea4f614d8395f6750dadfeaea82ead6cc73e'
baseline_commit: '9436ea4f614d8395f6750dadfeaea82ead6cc73e'
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

### Review Findings

Code review (2026-11-03, review_mode full; layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor). 0 decision-needed, 9 patch (all applied), 1 defer, 8 rejected.

- [x] [Review][Patch] (medium; fix-risk low: one stronger regex in the source pin; in-story) The AC4 pin let a guarded call through: `if (key !== '') this.schedule.paired(...)` kept every position check green, while a paired card (key "") would never tell the schedule `true`, so no exemption would ever be granted [web/scripts/telegram-card-view.test.mjs:345]. The pin now requires the call as the first, unconditional statement of the untracked block; mutation line below.
- [x] [Review][Patch] (medium; fix-risk low: the pin's slice is bounded and one count assertion added; in-story) The 409 pin let `reply.failed()` at the top of the error handler through, so a refused card could ask every 30 s with T4 (3 s window) still green [web/scripts/telegram-card-view.test.mjs:356]. The pin now bounds the error handler and requires exactly one reply call, after the 409 return; mutation line below.
- [x] [Review][Patch] (low; fix-risk low: one added case; in-story) No case for the Matrix row "Unpair long after" [web/scripts/telegram-card-view.test.mjs:167]. Added: an unpair 12 s after the last request asks at once, and the next request is spaced 10 s after it.
- [x] [Review][Patch] (low; fix-risk low: comment re-wrap) The class doc's last just-unpaired line was 180 characters [web/src/app/rail/telegram-card/telegram-card.ts:59]. Re-wrapped.
- [x] [Review][Patch] (low; fix-risk low: one doc sentence) `CodeSchedule.start` did not state its one-asking-at-a-time rule [web/src/app/rail/telegram-card/telegram-card-view.ts:106]. Added: the caller ends the previous asking first (the card does so through the effect's cleanup).
- [x] [Review][Patch] (low; fix-risk low: one guard) The asking-effect slice ran to the end of the file if its end marker went missing [web/scripts/telegram-card-view.test.mjs:330]. The slice is now empty, and the pin red, unless both markers are found.
- [x] [Review][Patch] (low; fix-risk low: a rename) The AC3 case's name claimed "with no second exemption", which cannot fail there (the 30 s retry is later than the 10 s spacing either way; the AC2 mutation pins that property) [web/scripts/telegram-card-view.test.mjs:230]. Renamed.
- [x] [Review][Patch] (low; fix-risk low: a rename) "cancels the request in flight" over-claimed: `stop` runs after the second request was answered [web/scripts/telegram-card-view.test.mjs:298]. Renamed to "cancels the latest request".
- [x] [Review][Patch] (low; fix-risk low: tracking lines) The Verification mutation lines were not in Rule 19's `mutation: <change> -> <red test>` form (the form sibling specs use). Every pinning mutation was re-applied on the patched tree, seen red, reverted (byte-identical), and written below in that form.
- [x] [Review][Defer] (low; fix-risk low; out-of-footprint) `web/scripts/fake-clock.mjs`'s header lists the modules whose tests use it and leaves out `telegram-card-view.ts` [web/scripts/fake-clock.mjs:1] -- deferred: outside the U-243 footprint; DW-641 `wontfix-accepted`, reopen_if a story edits fake-clock.mjs and leaves the card's module out of its list.

**Rejected:**
- (low) The cycle log's `dev_complete` line records `story_base=9436ea4f` while its `stage_spawned` line records `9cd97066`: the runner's bookkeeping, which this stage may not write; passed to the runner.
- (false) The spec frontmatter says `done` while sprint status says `review`: the pipeline's normal state during review; this stage sets sprint status.
- (low) AC5 records no T6 `watchWindow` timings: the fix is an edit of the Auto Run Result; the evidence is T6 green under its unchanged 8000 ms bound.
- (low) The earlier triage log's counts and its "Intent alignment" tag disagree: the fix is an edit of a past triage record, not of the code.
- (false) A pair and unpair inside one stretch where the key is "" for another reason (paused, off, no bot name) never reach the schedule: pairing needs an inbound /start, and no update is processed while paused (the getUpdates 409 pause in `Channel/Telegram/In.cls`), off, or with no bot name. `wontfix-theoretical`: real if a pairing could land during a pause.
- (low) `Date.now` stepping backward holds the next request for the size of the step: unchanged from before this story (the old `lastRequest` used the same clock); a guard adds complexity for an NTP step.
- (false) The `now` option's doc ("on the clock that setTimeout counts") against `Date.now`: it states what the schedule needs of the injected clock, which `Date.now` meets apart from the clock steps above.
- (by-design) AC5 has no mutation demonstrated on this tree: D4 (T6's red on the defect was seen on CI at e75b90bc; a local red depends on machine timing).

## Spec Change Log

## Review Triage Log

### 2026-11-03 -- Review pass
- verdicts: 17 findings from the layers (the intent audit is descriptive and files none) -- high 0, medium 5, low 7, false 5, maybe-false 0; grouped rows below name their members
- findings:
  - `[medium]` `patch` Blind 1, Edge 3, Gap 2: the refusal test never refuses, so the 409 half of AC3 has no unit pin -- renamed the test to what it shows; added a source pin that the 409 branch returns before `reply.failed()`, with a mutation line.
  - `[low]` `patch` Blind 2, Gap 3: "the first value grants nothing" cannot fail (the first request is at once either way) -- rewrote it so the first value (unpaired) arrives after an earlier request and must still wait out the spacing; mutation line added.
  - `[medium]` `patch` Blind 6, Gap 1: the AC4 pin slices on comment markers and passes when the call sits below the early returns -- the pin now asserts the call comes before `if (key === '')`, and the slice is bounded from its own start; mutation line added.
  - `[low]` `patch` Blind 5, Edge 5: "the code is held before the 5 seconds end" over-claims and the line is unwrapped -- reworded to "normally held when the 5 seconds end" and re-wrapped.
  - `[low]` `patch` Edge 4: the module doc and `CODE_SPACING_MS` doc say nothing of the exemption -- added a paragraph to the module doc and the exception to the constant's doc.
  - `[false]` `reject` Blind 3, Edge 1, Edge 2 (an unpair seen late, or never, during a pause; an exemption that does not expire) -- the spec's D2 and D3 name this: the grant lands when asking next starts and costs one request; an unpair inside a pause is "the first request after an unpair" when the pause ends.
  - `[false]` `reject` Blind 4: `CodeReply` called twice leaves a stray timer -- the component calls it once per request (an HTTP observable emits once); not reachable.
  - `[false]` `reject` Blind 7: no case with an exempt request and a future due time -- the exemption is used up by the request it covers, so `later` never sees it set with a due time; unreachable.
  - `[low]` `reject` Gap (mutation lines are not literally `mutation:`; AC5 has none; no post-fix green in the diff) -- the Verification section's mutation lines are the project's form; AC5 is D4; the post-fix green of `live demo-path` is in the Auto Run Result.
  - `[low]` `reject` Gap other (component wiring has no executed host outside e2e) -- the spec chose source pins plus T3 to T6 (D4); the live run passed.
  - `[low]` `reject` Intent alignment (descriptive: R2 and R3 readings of the unpair as a store event, the grant without an expiry) -- the diff implements the spec's stated reading (D2, D3); no divergence from the intent contract.

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
- AC1: make the exemption grant a no-op (`CodeSchedule.paired` sets `exempt = false` on a true-to-false change). Observed red (6 cases), among them "after an unpair, the request goes out at once". Reverted; tree byte-identical.
- AC2: never use up the exemption after a request (delete `this.exempt = false` in `send`). Observed red (3 cases), among them "after the exempt request, a code that is due at once waits until 10 s after it". Reverted; tree byte-identical.
- AC3: retry after a failure with the spacing in place of `CODE_RETRY_MS` (`later(now())`). Observed red (1 case): "a failure asks again exactly 30 000 ms later, the exempt request included, with no second exemption". Reverted; tree byte-identical.
- AC4: delete the component's call that passes `paired` to the schedule. Observed red (1 case): the source pin "tells it the paired value inside the asking effect, untracked, before it starts asking". Reverted; tree byte-identical.
- AC3 (409 half): make the component's 409 branch call `reply.failed()` before it returns. Observed red (1 case): the source pin "a 409 shows the not-set-up view and returns without a reply, so the schedule stops asking". Reverted; tree byte-identical.
- First value: let the first `paired` value grant (`this.before !== false` in `CodeSchedule.paired`). Observed red (1 case): "the first value grants nothing: a card whose first value is unpaired still waits out the spacing". Reverted; tree byte-identical.
- AC4 (placement): move the component's `paired` call below the asking effect's early returns. Observed red (1 case): the source pin "tells it the paired value inside the asking effect, untracked, before it starts asking". Reverted; tree byte-identical.
- (QA) Spacing half of AC2: drop the spacing (`const earliest = at` in `CodeSchedule.start`). Observed red (5 cases), among them "a new round with no unpair waits until exactly 10 s after the last request". Reverted; tree byte-identical.
- (QA) Re-run of every line above at the QA stage (AC1 6 red, AC2 3 red, AC3 1 red, AC4 1 red, 409 half 1 red, first value 1 red, AC4 placement 1 red): all still accurate; each reverted from a backup, tree byte-identical. mutations_demonstrated=8. No test file was added in QA: the existing cases cover both halves of the Planner's condition (the immediate first request after an unpair; the unchanged 10 s spacing and 30 s retry for every later request).
- AC5: the pre-fix head e75b90bc, where T6 was seen red twice on CI runner 20. A local red is not required (D4).

Pinning mutations in Rule 19's form, re-applied on the tree after code review's patches (27 cases); each was seen red, reverted from a backup, and the file confirmed byte-identical:
- mutation: `CodeSchedule.paired` sets `exempt = false` on a true-to-false change -> 6 red, among them "after an unpair, the request goes out at once, even 2 s after the last one" (AC1).
- mutation: `this.exempt = false` deleted from `send` -> 4 red, among them "after the exempt request, a code that is due at once waits until 10 s after it" and "an unpair long after the last request asks at once, and the request after it is spaced again" (AC2).
- mutation: `const earliest = at` in `start` (no spacing) -> 6 red, among them "a new round with no unpair waits until exactly 10 s after the last request" (AC2, spacing half).
- mutation: the failure retry scheduled at `now()` in place of `now() + CODE_RETRY_MS` -> "a failure asks again exactly 30 000 ms later, the exempt request included" red (AC3).
- mutation: the 409 branch calls `reply.failed()` before it returns -> "a 409 shows the not-set-up view and returns without a reply, so the schedule stops asking" red (AC3, 409 half).
- mutation: `reply.failed();` added as the error handler's first statement -> the same 409 pin red (AC3, 409 half).
- mutation: `this.before !== false` in `CodeSchedule.paired` -> "the first value grants nothing: a card whose first value is unpaired still waits out the spacing" red (first value).
- mutation: the component's `this.schedule.paired(...)` call deleted -> "tells it the paired value inside the asking effect, untracked, before it starts asking" red (AC4).
- mutation: that call moved below the early returns, just before `onCleanup(this.ask(key))` -> the same AC4 pin red (AC4, placement).
- mutation: that call guarded as `if (key !== '') this.schedule.paired(...)` -> the same AC4 pin red (AC4, unconditional).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The Telegram card's request timing moved into the framework-free `CodeSchedule` (`telegram-card-view.ts`). The first request after an unpair (the store's `paired` turning true to false) goes out at once; every other request keeps the 10 s spacing, and a failure retries after 30 s. A 409 stops the asking. The card builds one schedule and tells it `paired` (untracked) at the start of each run of its asking effect, before the early returns. Doc comments were replaced to state the new contract.

**Files changed** (`footprint_extensions:` web/src/app/rail/telegram-card/telegram-card.ts, web/src/app/rail/telegram-card/telegram-card-view.ts, web/scripts/telegram-card-view.test.mjs, ruled under U-243):
- `web/src/app/rail/telegram-card/telegram-card-view.ts`: `CodeSchedule`, `CodeScheduleOptions`, `CodeReply`; module and constant docs.
- `web/src/app/rail/telegram-card/telegram-card.ts`: `lastRequest`, `later` and the timing in `ask` replaced by the schedule; class docs.
- `web/scripts/telegram-card-view.test.mjs`: schedule cases on `fakeClock()` for every Matrix row, and three source pins on the wiring.
- This spec: mutation lines, triage log.

**Review.** 17 findings from the layers: 10 of them in 5 entries patched (the refusal case now has a 409 source pin and an honest name; the first-value case now discriminates; the AC4 pin now requires the call before the early returns; the "held before 5 s" claim was softened and wrapped; the module and constant docs now state the exemption), 0 deferred, 7 rejected with reasons in the triage log (design notes D2 and D3, unreachable calls, and non-defects). Patched entries by verdict: medium 2, low 3. `followup_review_recommended: false`: each patched test was mutation-checked (red observed, reverted).

**Verification.** `node --test web/scripts/telegram-card-view.test.mjs` 26 of 26. `npm --prefix web test` 1301 of 1301. `bash ci/checks.sh` all scripts passed (run after the last patch). `OCUTALON_RUN_TAG=e31s7i ci/iris.sh build` built the bundle. `ci/iris.sh live demo-path` 28 of 28 passed, T1 to T7 green (T3 to T6 unchanged), run before and again after the last patch. Teardown of `e31s7i` done. Mutations for AC1 to AC4, the 409 half, the first value and the AC4 placement each went red and were reverted.

**Residual risks.** The component's wiring has no Node test host: it is pinned by source text and by T3 to T6 on the real stack. T6's pre-fix red was seen only on CI (D4). An unpair inside a pause grants its exemption when asking next starts (D2).
