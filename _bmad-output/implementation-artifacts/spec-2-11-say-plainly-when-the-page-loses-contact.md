---
title: 'Story 2.11: Say plainly when the page loses contact'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: 'ef499d489c5c8e343489fbdcecc859abafaa9fa2'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** When the page stops hearing from OcuTalon, it says nothing.
- `LiveState` (Story 2.2) retries a failed poll every second, forever, and the page looks current.
- Story 2.10's banner stack already holds the two banners of the page's own conditions, "Reconnecting" and "Unreachable", but `banner-stack.ts:152` passes `own: []`, so neither can ever show.
- So a user whose server went away keeps typing into a page that receives nothing, and is never told that new messages may be delayed.

**Approach:**
- **The live-event service watches its own contact.** A small framework-free module, `contact-watch.ts`, inside `LiveState` counts from the last answer of the live path (in release 1, polling only):
  - 10 s with no answer: `reconnecting`;
  - 30 s: `unreachable`;
  - the next answer: back to `ok`.
- **While unreachable, the page retries every 10 seconds**, so the banner's words are true.
- **The banner stack** shows `LiveState.contact` as its page's own conditions, through Story 2.10's catalog, closing rule, announcements and focus rule. Unreachable replaces Reconnecting, so it takes focus when Reconnecting held it.
- **Recovery uses Story 2.2's path:** the next poll brings the missed events, or the snapshot reloads when a `seq` skipped, and both banners clear.
- **The connection tests** run in a real browser against a real stack. They make the server unreachable with `page.route` and control the page's clock with `page.clock`.

## Boundaries & Constraints

**Always:**
- **The contact watch: `web/src/app/live/contact-watch.ts` (new).**
  - It is framework-free, like `shared/busy-state.ts`: erasable TypeScript syntax only, it imports nothing, and its timers are injected (`setTimeout`, `clearTimeout`, `onChange`). So Node runs it as it is.
  - **Its exports:**
    - `ContactState` = `'ok' | 'reconnecting' | 'unreachable'`;
    - `RECONNECTING_AFTER_MS = 10_000`, `UNREACHABLE_AFTER_MS = 30_000`, `UNREACHABLE_RETRY_MS = 10_000`;
    - `BUSY_STATUS = 503`;
    - the class `ContactWatch`;
    - `pollDelay(state, elapsedMs, normalMs)`.
  - **`ContactWatch`:**
    - `state` starts at `ok`, with no timer armed.
    - `answered()` sets `ok` and arms both thresholds again, counted from that call: `reconnecting` at 10 s and `unreachable` at 30 s.
    - `stop()` clears the timers and sets `ok`. It is final: any `answered()` after it does nothing.
    - `onChange(state)` is called once per actual change.
  - **`pollDelay`:**
    - `unreachable` gives `max(0, UNREACHABLE_RETRY_MS - elapsedMs)`, where `elapsedMs` is the time since the poll that just ended started, so each attempt starts 10 s after the previous one started;
    - `ok` and `reconnecting` give `normalMs`.
- **What counts as an answer (Decided 2).**
  - These count:
    - a poll whose response was applied (`applyEvents` gave no reload);
    - a snapshot that `accept()` took in (the first load, a Retry, or a reload after a skip or a new epoch);
    - a `/events` or `/state` answer with `BUSY_STATUS`. That is the busy state, which Story 16.5 shows. The proxy never turns an `/ocutalon/api/` 503 into a page (AD-13, AD-25).
  - Nothing else counts: a network error, a timeout (`POLL_TIMEOUT_MS`), or any other status. A 401 stays the session gate's.
- **`LiveState` (`web/src/app/live/live-state.ts`), the one live-event service (Conventions "Angular").**
  - It owns one `ContactWatch`, built with `globalThis.setTimeout`, `globalThis.clearTimeout` and an `onChange` that sets a new public signal, `readonly contact = signal<ContactState>('ok')`.
  - It calls `answered()` at every answer above, but only from the first `accept()` on. That call is the first to arm the watch. Before it, the page shows Story 2.2's load states, never these banners. A 503 on the first `/state` is Story 2.2's load failure, and arms nothing.
  - `poll()` records the time it starts.
  - Every `schedulePoll()` waits `pollDelay(contact(), now - pollStart, POLL_DELAY_MS)`. The cadence of an answered page stays 1 to 2 s (`POLL_DELAY_MS`, `POLL_TIMEOUT_MS` and L1, L8, L12, L13 unchanged).
  - `stop()` also stops the watch. That covers a 401 (`SessionGate.onSignedOut`), Sign out and Story 16.4's idle stop, which uses the same `stop()`.
  - The class doc says all of this.
- **The banner stack (`web/src/app/banners/banner-stack.ts`).**
  - `input` passes `own: []` while the contact is `ok`, else `[contact]`, from `this.live.contact()`.
  - Everything else is Story 2.10's, unchanged:
    - "Reconnecting… New messages may be delayed." (info, `info` icon, Close) stacks last;
    - "Can't reach OcuTalon. Retrying every 10 seconds." (danger, `circle-alert`, no Close, no action) stacks third;
    - texts come from `catalog.ts` (`banner.reconnecting` `:17`, `banner.unreachable` `:11`), and each banner is announced once when it appears after the first snapshot;
    - a closed Reconnecting stays away while the condition holds, and its record drops when the condition clears, so the next outage shows it again;
    - no banner is a live region.
  - **The replacement focus rule (Decided 5).** `banner-view.ts` exports `REPLACED_BY: Readonly<Partial<Record<BannerId, BannerId>>> = { reconnecting: 'unreachable' }`. In `keepFocus`, when the banner that held focus (itself, or its Close) leaves and its replacement is shown after the render, focus moves to the replacement banner with no scroll. Otherwise Story 2.10's rule applies: the next banner, else the previous one, else `main.main`.
- **Recovery** is Story 2.2's path, unchanged:
  - the first answered poll brings the events missed after the cursors, applied idempotently;
  - a skipped `seq` or a new epoch reloads the snapshot once;
  - the banners clear when that answer or reload is applied (Decided 3);
  - nothing is announced on the clear.
- **The connection tests: `web/e2e/banners/banners.spec.ts`, B13 to B16 (Decided 7).**
  - They use the chromium project, user `BANNERS`, and real HTTP.
  - "Server unreachable" means every page request under `/ocutalon/api/v1/` is aborted with `route.abort('connectionrefused')`, then unrouted for the recovery (Decided 8).
  - The page's clock is Playwright's `page.clock`:
    - `install()` runs before sign-in, so time flows naturally, as L6 does (`live.spec.ts:272`);
    - `fastForward` and `runFor` cross the thresholds;
    - a check on the browser side leaves at least 1.5 s of margin either side of a threshold, because natural time keeps flowing between steps;
    - the exact thresholds are pinned by `contact-watch.test.mjs`.

**Never:**
- **No server change.** No ObjectScript, REST route, `/state` or `/events` key, event type, stored property, table or global; no role or grant; no dependency.
- **No second poller and no WebSocket** (Story 31.1). Story 2.2's cadence of an answered page and its first-load states stay as they are.
- **No new public text.** The two banners use the catalog's UX texts verbatim, with the single "…" character, written as its Unicode escape in code, as `catalog.ts:17` has it (Rule 14). The clear is silent. No toast and no modal.
- **No lost-contact banner** for a 401, a 503, a stopped page, or before the first snapshot.
- **Tests:**
  - never stop or pause IRIS or its web server to make it unreachable, and never publish on the instance stream (Story 2.2's Decided 13);
  - never run the `Test.Core.*Production`, `Test.Live.Publish`, `Test.Web.Install`, `Test.Install.Registry` or `Test.Demo.Production` classes on slot B (Story 2.10's list).
- **Contended paths are read-only:**
  - `src/bridge/**`;
  - `OcuTalon/{Agent,Tools,Digest,Install,Schedule,Checks,Eval,Watch}/**`;
  - `Data/Public/**` and `Data/{StatusMark,Time,Reminder}.cls`;
  - `Core/Commands*.cls` and `Msg/Tick.cls`;
  - `Test/{Agent,Bridge,Install,Tools,Digest,Schedule}/**`;
  - `ci/mock/scenarios/{A,B}/**`, `web/e2e/demo-path/0{2,3}-*.spec.ts` and `release/**`;
  - `.github/workflows/lane-a.yml`, `ci/iris.sh` and `ci/warm.sh`;
  - `docker/tests/test-pinned-sources.sh`, `test-production.sh`, `test-ci-warm.sh` and `test-ci-config.sh`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Answered | Polls answered 200 every 1 to 2 s | `contact` stays `ok`; no own banner; cadence unchanged | — |
| Unreachable | Every `/ocutalon/api/v1/` request refused after the load | 10 s after the last answer: Reconnecting (info, last, Close), announced once. 30 s: Unreachable replaces it (danger, before the warnings, no Close), announced once. From then on, polls start 10 s apart | Polls in the first 30 s keep the 1 s retry (L8 holds) |
| Server hangs | A poll held with no answer (L13) | Reconnecting shows 10 s after the last answer while the poll is still out; the next answered poll clears it | The poll is given up at `POLL_TIMEOUT_MS`, as before |
| Error answers | `/events` answers 500, 404 or 403 | No answer: the same timeline as Unreachable | — |
| Busy | `/events` answers 503 for 40 s | An answer: no own banner, polls at 1 to 2 s | Story 16.5 shows the busy text |
| Signed out | A poll answers 401 | Story 2.2's sign-in page with "You were signed out…"; the watch stops | — |
| Stopped on purpose | Sign out pressed (`/session/end` held), or Story 16.4's idle stop | `stop()`: a shown own banner leaves at once, and none shows however long nothing answers | — |
| Recovery | A `status` event published during the outage; the route lifted | The next poll applies it: its banner shows, and Reconnecting or Unreachable leaves in the same update, unannounced | — |
| Recovery with a skip | The first answer after recovery skips a `seq` | `/state` reloads once; a row seeded during the outage shows; the banners clear when the snapshot applies | A reload that fails: still no answer, so the timeline goes on from the last answer |
| Closed Reconnecting | Close pressed at 15 s | Hidden for the rest of this outage; Unreachable still shows at 30 s; after recovery, the next outage shows Reconnecting again, announced | — |
| Focus | Reconnecting, or its Close, holds focus at 30 s | Focus moves to the Unreachable banner, with no scroll | Other banners: Story 2.10's next, previous, `main.main` |
| Not loaded | `/state` never answered | Story 2.2's "Couldn't load your session." with Retry; no own banner | — |

</intent-contract>

## Code Map

**Page (Lane B, edit or new)**
- `web/src/app/live/live-state.ts`:
  - `POLL_DELAY_MS` `:17` and `POLL_TIMEOUT_MS` `:23` (unchanged);
  - the class doc `:28-37`;
  - `stop()` `:107-114`;
  - `fetchSnapshot` `:120-145` (a 401 is skipped at `:138`);
  - `accept` `:148-160`;
  - `schedulePoll` `:175-183`;
  - `poll` `:189-199` (its error handler `:196`);
  - `applyPoll` `:202-220` (reload `:208-214`).
- `web/src/app/shared/busy-state.ts:1-108`: the sibling pattern for `contact-watch.ts` (framework-free, injected timers, `onChange`).
- `web/src/app/banners/banner-stack.ts`:
  - the class doc `:32-45`;
  - `input` `:147-153` (`own: []` at `:152`);
  - `announce` `:199-214`;
  - `keepFocus` `:237-261`.
- `web/src/app/banners/banner-view.ts`:
  - `OwnCondition` `:35`;
  - `BANNERS` `:61-71` (`unreachable` `:64`, `reconnecting` `:70`);
  - `OWN_CONDITIONS` `:74`;
  - `activeBanners` `:149-174` (own conditions `:155-159`).
- `web/src/app/session/session-gate.ts`: `onSignedOut` `:26-33` and `signOut` `:36-48`. Both call `live.stop()`, so neither changes.
- `web/src/app/api/envelope.interceptor.ts:31-36`: a 401 goes to the gate. Unchanged.
- `web/src/app/msg/catalog.ts:11,17`: the two texts. Generated; do not edit.
- `web/src/app/header/header.ts:140-142`: the Account menu's "Sign out" item.

**Page tests**
- `web/scripts/busy-state.test.mjs:15-44`: `fakeClock`, which moves to `web/scripts/fake-clock.mjs` (Rule 2).
- `web/scripts/banner-view.test.mjs`: own conditions `:121-122,189-190,208,281-292`.
- `web/scripts/banner-styles.test.mjs:5`: its header says no browser spec renders Reconnecting yet. That stops being true.
- `web/e2e/banners/banners.spec.ts`:
  - the header `:18-31`, and `afterEach` `unrouteAll` `:35-37`;
  - `slot`, `banner`, `banners` and `stack` `:70-76`;
  - `open` `:79-83`, `applied` `:86-90`, `turn` `:93-95` and `clear` `:98-102`;
  - `expectLook` `:120-140`, and `CIRCLE_ALERT` `:113`;
  - the cases B1 to B12 `:169-686`.
- `web/e2e/support/iris.ts`: `publishStatus` `:723`, `seedCheck` `:662` and `cleanFixtureRows` `:575`.
- `web/e2e/support/page.ts:47-72`: `recordAnnouncements`, `announcements` and `announcementCount`.
- `web/e2e/live/live.spec.ts`:
  - L3's skip injection `:152-175`, the pattern for B15;
  - L6's `clock.install` and `runFor` `:269-312`;
  - L13 `:539-570`, whose doc says nothing else on the page changes.
- `web/e2e/session/session.spec.ts:88`: `getByRole('menuitem', { name: 'Sign out' })`.
- `docker/tests/test-sign-in.sh`: the header `:38-40` and the PASS and FAIL labels `:238` and `:244` ("Story 2.10's B1-B12").
- Read only:
  - `web/playwright.config.ts:6-8,36-39`: chromium covers everything but `e2e/demo-path/`;
  - `docker/tests/test-demo-path.sh:7-10`: an unknown spec file fails the demo-path unit;
  - `node_modules/playwright-core/types/types.d.ts`: `Clock`, where `install` lets time flow naturally, and `fastForward` fires due timers at most once.

## Tasks & Acceptance

**Execution:** No Task 0 is needed. No server code changes. The page's clock under Playwright is known: L6 drives `install` and `runFor`, and the installed types document that time flows naturally after `install`.

1. `web/src/app/live/contact-watch.ts` (new): `ContactState`, the four constants, `ContactWatch` and `pollDelay`, as Boundaries says, each documented. This is the watch.
2. `web/src/app/live/live-state.ts`: own the watch, add `contact`, call `answered()` at each answer (Decided 2), record the poll's start, use `pollDelay` in `schedulePoll`, and stop the watch in `stop()`. Replace the class doc. This wires the watch into the one live-event service.
3. `web/src/app/banners/banner-view.ts`: add `REPLACED_BY`, documented with the module doc. `web/src/app/banners/banner-stack.ts`: `own` from `live.contact()`, and the replacement step in `keepFocus`, with the class doc updated. These show the two banners.
4. `web/scripts/fake-clock.mjs` (new, a helper, not a test): `fakeClock` moved from `busy-state.test.mjs`, which imports it.
5. `web/scripts/contact-watch.test.mjs` (new). The matrix's timing edges:
   - nothing is armed before the first `answered()`;
   - at 9 999 ms the state is `ok`, at 10 000 `reconnecting`, at 29 999 still `reconnecting`, at 30 000 `unreachable`;
   - `answered()` gives `ok` from either state and counts again from that call;
   - `onChange` fires once per change and never for a repeat;
   - `stop()` gives `ok`, leaves no timer pending, and ignores a later `answered()`;
   - `pollDelay` gives `normalMs` for `ok` and `reconnecting`, 10 000 minus the elapsed time for `unreachable`, and 0 at or past 10 000;
   - `BUSY_STATUS` is 503;
   - the module imports nothing.
6. `web/scripts/banner-view.test.mjs`: `REPLACED_BY` is exactly `{ reconnecting: 'unreachable' }`, and each replacement is a banner id. `web/scripts/banner-styles.test.mjs`: update the header line `:5`.
7. `web/e2e/banners/banners.spec.ts`: the header names Story 2.11's connection tests. Add four cases:
   - **B13: the server unreachable.**
     - Set-up: the case publishes `noModelKey` itself (as B3 does), records announcements, installs the clock, signs in, and makes the server unreachable.
     - Before 10 s: no own banner.
     - After 10 s: Reconnecting, with `expectLook` `info`, the `info` icon, a Close named "Close", no action, last in the stack, and announced once.
     - Focus is put on its Close.
     - Before 30 s: Reconnecting is still there, and there is no Unreachable.
     - After 30 s: Unreachable, with `expectLook` `danger`, `CIRCLE_ALERT`, no Close and no action. It sits before `noModelKey`, Reconnecting is gone, Unreachable is announced once, and focus is on the Unreachable banner.
     - The retry cadence: stepping the clock 1 s at a time for 20 s, the page makes 2 or 3 `/events` attempts, where a 1 s cadence would make about 20.
     - Clean-up: `noModelKey` is cleared in `finally`.
   - **B14: recovery.**
     - Outage: Reconnecting shows; Close it at about 15 s. It is still away at about 25 s, and Unreachable shows at 30 s.
     - Missed content: a `heartbeatStalled` status is published during the outage.
     - Recovery: the route is lifted and the clock moves 10 s. The heartbeat banner shows, and Unreachable leaves, in the same applied update, with no announcement of the clear.
     - A second outage shows Reconnecting again, announced.
     - Clean-up: the condition is cleared in `finally`.
   - **B15: recovery with a skip.**
     - During an outage, `seedCheck` writes a check.
     - On recovery, the first answered poll is given a skipped `seq` (L3's injection). `/state` is requested exactly once more, and the seeded check shows in the rail. Within `ONE_UPDATE_MS` of that, both own banners are gone; a later poll would come up to 10 s after. The page stays `loaded`.
     - Clean-up: `cleanFixtureRows` in `finally`.
   - **B16: not lost contact.**
     - Busy: every `/events` request is answered with status 503 (any body: the page reads only the status). The clock is stepped 1 s at a time for 40 s. The page makes at least 15 `/events` attempts, where the unreachable cadence would make about 4, and shows no own banner.
     - Errors, the contrast: the same route answers 500 instead. After 10 s of clock, Reconnecting shows.
     - Stopped: the route holds `/session/end`, and Sign out is pressed. Reconnecting leaves at once, because a stopped page claims no lost contact. 35 s of clock pass, stepped as above. No `/events` request is made, and no own banner shows. When `/session/end` is released, the sign-in page shows.
8. `web/e2e/live/live.spec.ts`: L13 also asserts Reconnecting during the hung poll and its clear after the next answer (the sweep), and its doc follows. The "Not loaded" row needs no new browser case: the stack renders nothing until the store exists (`banner-stack.ts:147-153`), and `accept()` resets the watch, so an early-armed watch has no observable effect there.
9. `docker/tests/test-sign-in.sh`: the header line and the PASS and FAIL labels read "Story 2.10's B1-B12 and Story 2.11's B13-B16".
10. **The sweep (shared surfaces).**
    - Search `web/e2e/` for every route that refuses, fails or holds `/events` or `/state` for 10 s or more after the load (today only L13).
    - Search for every count of `[data-banner]`, of the slot's height, or of announcements in such a case, and update each.

**Acceptance Criteria:**
- **Lost contact (UX-DR91, UX-DR14, UX-DR116; AD-12).**
  - **Given** the page has loaded its snapshot,
  - **when** no live request answers for 10 s (the server refuses, errs or hangs),
  - **then:**
    - the closable info banner "Reconnecting… New messages may be delayed." appears, last in the stack, announced once;
    - at 30 s the unclosable danger banner "Can't reach OcuTalon. Retrying every 10 seconds." replaces it, before the warning banners, announced once, and takes focus if Reconnecting held it;
    - from then on the page retries every 10 seconds.

  Tests: B13, B16 (the 500 contrast), L13, `contact-watch.test.mjs`, `banner-view.test.mjs`.
- **Recovery (UX-DR91, AD-12).**
  - **Given** either banner shows,
  - **when** a live request answers again,
  - **then:**
    - the missed content loads into place: the events after the cursors, or the reloaded snapshot when a stream's `seq` skipped;
    - both banners clear in that update, unannounced;
    - a closed Reconnecting stays away for the rest of its outage and returns, announced, at the next one.

  Tests: B14, B15, `contact-watch.test.mjs`.
- **Not lost contact (AD-13, AD-25).**
  - **Given** an API 503, a 401, or a page that stopped polling on purpose (Sign out; Story 16.4's idle stop uses the same `stop()`),
  - **when** 30 s or more pass,
  - **then:**
    - no lost-contact banner shows;
    - a 503 counts as an answer (Story 16.5 shows the busy text);
    - a 401 goes to the sign-in page as Story 2.2 does.

  Tests: B16, `contact-watch.test.mjs`, and `session.spec.ts` S3 (Story 2.2's two 401 cases, unchanged).
- **The CI connection tests (NFR-9, AD-12).**
  - **Given** the CI demo-path environment (the `browser` group's throwaway stack),
  - **when** the connection tests B13 to B16 run in `live:sign-in`,
  - **then**, with the server unreachable, the two banners appear in order with the page's clock controlled by the test.

  Tests: B13.
- **Integration (Rule 1).**
  - **Given** `ContactWatch` inside the real `LiveState`,
  - **when** the real polling of a real stack loses and regains contact,
  - **then** the consumer `BannerStack` shows and clears the two banners in the page.

  Tests: B13 to B16.

## Spec Change Log

## Review Triage Log

### 2026-10-24 — Review pass
- verdicts: 23 findings — high 0, medium 3, low 16, false 4, maybe-false 0
- findings (layers in order: blind-hunter 1-7, edge-case-hunter 8-13, verification-gap 14-20, intent-alignment 21-23):
  - `[low]` `reject` 1. A 503 counts as busy on its status alone, so a 503 that is not IRIS's would reset the watch — the spec makes an API 503 the busy state and the page reads only the status (Boundaries "What counts as an answer", AD-25, B16); the fix edits the intent. A dead upstream behind Caddy answers 502 or 504, not 503. reopen_if=Story 16.5 tells busy from other 503s by the `X-OcuTalon-Busy` marker.
  - `[low]` `reject` 2. Late or batched timers (a hidden tab, a sleep) fire both thresholds before the in-flight answer lands — Decided 3 counts from the last answer, so a page that heard nothing for 30 s or more shows the banners and the next answer clears them; the fix (visibility handling) adds branches and changes the specified count. reopen_if=a user reports the banner on waking.
  - `[medium]` `patch` 3. The `/state` 503 branch and its loaded guard have no test — shares root cause with 14 and 16: the reload leg of the answer rule is unpinned. Patched: B16's fourth phase (a 503 of the held reload clears Reconnecting); mutation recorded.
  - `[low]` `patch` 4. banner-view.test.mjs's replacement cases do not test the replacement, and the fallback focus branch is untested — the table is pinned by the `deepEqual`; the fallback shares root cause with 15. Patched: B14 asserts where focus lands; mutation recorded.
  - `[low]` `patch` 5. live-state.ts comments say polls come 1 to 2 s apart "at every other time" and that the next poll follows after POLL_DELAY_MS — a poll given up takes 11 s, or no wait while unreachable. Patched: both comments reworded.
  - `[low]` `reject` 6. L13's new assertion has about 2 s of slack (the third poll starts 1 s after the second is given up at +11 s, the banner shows at +10 s) — Task 8 asks for Reconnecting during the hung poll, and the 10 s threshold against the 10 s poll limit is the spec's own timing. reopen_if=L13 fails on a loaded runner at the `starts.length` check.
  - `[low]` `reject` 7. B15's route order lets a poll in the few milliseconds between the skip route and `lift()` skip the abort — wontfix-theoretical: the unreachable cadence is 10 s, so the window is milliseconds. reopen_if=B15 fails with `states` other than 2.
  - `[low]` `reject` 8. Same claim as 1 (a 503 that is not IRIS's) — rejected for the reason in 1.
  - `[low]` `reject` 9. Same claim as 2 (timers late after a sleep or in a hidden tab) — rejected for the reason in 2.
  - `[low]` `reject` 10. A poll with a skipped `seq` whose reload fails or hangs leaves Reconnecting and Unreachable showing while polls answer — spec-bound: the matrix row "Recovery with a skip" says a reload that fails is still no answer, and counting it would claim contact while the snapshot is stale (a false all-clear). Its pinning is 16.
  - `[low]` `reject` 11. A 200 poll answer without an `events` array throws in `applyEvents` and ends the loop — a path that exists in Story 2.2's code and that the server's contract rules out. reopen_if=a server answer with no `events` is seen.
  - `[low]` `reject` 12. R13's `runFor(60_000)` crosses both thresholds with no real time for polls to answer — Decided 16: R13 asserts the rail's text only and passed in both full runs. reopen_if=R13 or L6 asserts a banner count or the slot's height.
  - `[low]` `patch` 13. Same claim as 5 (the live-state.ts comment) — patched with 5.
  - `[medium]` `patch` 14. The `/state` 503 clause of "what counts as an answer" is pinned by no test (deleting the branch kept B13 to B16 green) — patched with 3.
  - `[low]` `patch` 15. Closing Reconnecting moves focus through the new `REPLACED_BY` code, and no test asserts where focus lands — patched with 4: a B14 assertion; the mutation `replacement ?? next ?? previous` is red.
  - `[medium]` `patch` 16. The banners clearing only when the reloaded snapshot applies is not pinned: moving `answered()` above the reload branch keeps B15 green — patched in B16's fourth phase with an instant check that Reconnecting stays while the reload is held; the mutation is red.
  - `[false]` `reject` 17. Sub-claims of the ACs ("announced once", "before the warnings") have no mutation line of their own — Rule 19 asks one demonstrated mutation per AC, and each AC has at least one: Lost contact 5, Recovery 2, Not lost contact 4; the 401 clause rests on S3, unchanged.
  - `[low]` `reject` 18. banner-view.test.mjs:255-256 repeats the own-condition cases and never reads `REPLACED_BY` — harmless duplicates beside the order assertion, which can fail; no caller diverges.
  - `[false]` `reject` 19. contact-watch.test.mjs's source-text check "adds little" — it can fail (three patterns) and pins the spec's "imports nothing, erasable syntax"; the finding names no harm.
  - `[low]` `reject` 20. B14's fixed 1.5 s wait and B15's route-order window — a negative wait for "nothing else announced", acceptable; the layer found no leftover state or order dependence.
  - `[low]` `reject` 21. Matrix rows with no case of their own (Not loaded, 401 and idle stop, 404 and 403, a failing reload, Retry, a `/state` 503) — the plan settled Not loaded (Task 8), the 401 (S3, unchanged) and the status family (the 500 stands for it); the two real gaps are 14 and 16, patched.
  - `[false]` `reject` 22. L13 is edited though the intent says "unchanged" — the intent keeps L13's cadence constants and assertions, and Task 8 names this edit.
  - `[false]` `reject` 23. fake-clock.mjs, the test-sign-in.sh labels and the banner-styles header go beyond the intent's text — Tasks 4, 9 and 6 name them.

## Design Notes

**Governing ADs and conventions (Rule 6).**
- **AD-12:**
  - polling `/events` with two cursors is release 1's live path;
  - events apply idempotently, and a skipped `seq` reloads the snapshot;
  - the page never opens a WebSocket on the online demo.

  This story reads AD-12's "every 1 to 2 seconds" as the cadence of an answered live path (Decided 4).
- **AD-13:**
  - a 401 stops polling and returns to sign-in (or to the splash on the online demo);
  - the idle cap stops polling;
  - polling keeps the online demo's 120-second CSP session alive. A 10-second retry stays well inside it.
- **AD-25:** the Angular client shows the busy state for an API 503, and the proxy never replaces an `/ocutalon/api/` answer. So a 503 is an answer, not lost contact.
- **AD-32:** the page renders only from `catalog.ts`.
- **AD-22:** the tests are Playwright specs on a throwaway stack, and Node tests in `web/scripts/`.
- **AD-29:** `web/` is Lane B's.
- **AD-33:** no new event type and no new publisher.
- **Conventions:** Angular (one typed API client and one live-event service), Live events, Text OcuTalon sends, and Tests.

No AC contradicts an AD's Rule.

**Rule 5:** no NFR is unmeasurable. The thresholds and the cadence are timer values under an injected clock (Node) and under Playwright's clock (browser).

**Decided in-stage** (small, reversible, within the intent):
1. **The story is not split.** It adds one framework-free module, the wiring in `LiveState` and the stack, and four browser cases.
2. **"An answer"** is a poll that was applied, a snapshot that was taken in, or a 503 of either request.
   - Anything else is no answer: a refused connection, a timeout, a 500, a 404 or a 403. From the page, all of them mean the same thing: new messages are not arriving.
   - A 401 stays the session gate's.
3. **The 10 s and 30 s are counted from the last answer,** as the UX words it ("after 10 seconds with neither push nor poll answering"). The watch is armed by the first snapshot.
   - So a hung poll shows Reconnecting while it is still out.
   - The banners clear when the recovering answer has been applied. After a skip, that is the reloaded snapshot, so content and banners change together.
4. **While unreachable, polls start 10 s apart** (`UNREACHABLE_RETRY_MS`).
   - The banner says "Retrying every 10 seconds.", and text claims only what the product does. A 1-second retry would make it untrue.
   - In the first 30 s the 1 s retry stays (L8), and an answered page keeps AD-12's 1 to 2 s.
   - This is an implementation detail of the error path, not a product target.
5. **Unreachable is Reconnecting's replacement** (UX-DR131: focus moves "to its replacement"). It is the only replacement among the nine banners, so `REPLACED_BY` holds one entry. Story 2.12 tests the page-wide focus rule.
6. **The clear is silent.** The UX gives no recovery text, and Story 2.10's Decided 8 adds no public text.
7. **"The CI demo-path environment" is the CI `browser` group's throwaway stack,** the one `live:demo-path` and `live:sign-in` both start from the image with the CI override.
   - The connection tests are chromium specs in `banners.spec.ts`, run by `live:sign-in`. They reuse its banner helpers (`expectLook`, `stack`, `open`, `turn`, `clear`) and its fixture user.
   - They do not go under `web/e2e/demo-path/`:
     - that project holds only UJ-1's six step specs, and `demo-path-summary.mjs` fails on an unknown spec file (`test-demo-path.sh:7-10`);
     - its stack has no fixture user;
     - Story 2.12 uses the same phrase for browser runs that can't be step specs.
8. **"The server unreachable" is the page's API requests refused in the browser** (`page.route` with `connectionrefused`). The hang variant is L13's held poll. Stopping IRIS or its web server is destructive and slow, and it would end the other specs' sessions.
9. **The watch is a module inside `LiveState`, not a service.** Conventions "Angular" allows one live-event service, and the epic says to add no second poller.
10. **The poll's start is read from `performance.now()`,** the page's monotonic clock, not from `Date.now()`. A step of the system clock then cannot make the elapsed time negative, and Playwright's clock fakes both alike.
11. **A 503 of a `/state` request counts as an answer only once the page has loaded** (`status() === 'loaded'`, which covers the reload after a skip). A 503 on the first load or on a Retry is Story 2.2's load failure and arms nothing.
12. **`ContactWatch` has a read-only `state` getter and a `ContactOptions` type,** as `BusyState` has `view` and `BusyOptions`. `LiveState` reads the `contact` signal, not the getter.
13. **The browser checks that a banner has come wait `ONE_UPDATE_MS`, and the clock moves in 1 s steps (`runSteps`).** The page's clock keeps flowing while an expectation waits, so the default 10 s wait would let a late banner pass. The negative checks (no banner yet) pass at once and keep at least 1.5 s of margin. The first refusal comes one poll delay (1 s) after the last answer, so a run of N steps puts the page N + 1 s or a little more from its last answer.
14. **B14 and B15 turn `noModelKey` on first and clear it in `finally`.** B14 needs the exact stack. B15 needs a poll answered before the outage, so the watch is armed by a poll as well as by the snapshot, and the "accept() does not call answered()" mutation fails on the reload and not on an unarmed watch.
15. **B14 pins "in the same applied update" with `recordStacks`,** a `MutationObserver` that records the slot's banner ids after each change (`window.stacks`). The heartbeat banner's first stack has no Unreachable, and the stack before it has.
16. **The sweep (Task 10).** Only L13 refuses or holds `/events` for 10 s or more after the load, and it now asserts Reconnecting and its clear. Every other route answers within seconds, so none shows an own banner: L8 (two 500s in a row, 1 s apart), L12 (one poll held about 4 s), L3, L9, L10 (skips and reloads), C8 and the chat helpers (answers with some events cut, never refused), L6 and L7 and the other `/state` routes (before the first snapshot, which arms nothing). `rail.spec.ts` R13 moves the page's clock 60 s with `runFor` over real polls, so its watch may show a banner during the jump. It asserts the rail's text only, and it passes. No spec counted `[data-banner]`, the slot's height or announcements in such a case.
17. **`fake-clock.mjs` has no `.test` suffix,** so `node --test scripts/*.test.mjs` does not run it as a suite, and `npm run lint` still checks its syntax.
18. **B16 has a fourth phase for the reload after a skip (review pass).** With Reconnecting showing, one `/events` answer carries a skipped `seq` (L3's injection) and the `/state` reload is held. Reconnecting stays while the reload is out, because a poll that finds a skip is no answer until the snapshot is taken in. A 503 of the reload then clears it, because a 503 is an answer. The 500s go on, and Reconnecting returns after 10 s, so the Sign out phase still starts from a shown banner.
19. **"Stays" checks are instant counts (review pass).** `toHaveCount(1)` waits for the banner to appear, and the page's clock keeps flowing while it waits, so a banner that left and came back after 10 s would pass it. B16's check that Reconnecting stays reads `count()` once.

**For the lead (Rule 20, your call).** Decided 4 constrains Story 31.1's fallback and Stories 16.4 and 16.5. A Consistency Conventions sentence, for example appended to "Live events", would keep them from drifting: "While no live path has answered for 30 s, the page retries every 10 s; a 503 is an answer (the busy state), a 401 ends polling". No AD amendment is needed.

**Lead's ruling at the spec gate (2026-10-24).** Decided 4's sentence is written into the Conventions "Live events" row (decide; AD-12 extended to the unanswered case, not contradicted).

**Veto-window items:** none. No stored data, role, grant, dependency or new public text. The two texts are the UX's.

**Integration ACs (Rule 1).** `ContactWatch` is a new module. Its consumer in this story is `LiveState`, whose `contact` signal `BannerStack` reads. B13 to B16 exercise the real stack, with real polling and the real `LiveState`.

**Consumed-by:**
- **2.12:** the accessibility floor tests both banners: the string test of "Reconnecting…", and the focus and announcement rules.
- **16.4:** the idle stop calls `LiveState.stop()`, which ends the watch.
- **16.5:** the busy state for an API 503. The watch already counts a 503 as an answer, so the busy text and Unreachable never show together.
- **31.1:** a WebSocket message is an answer of a live path. The socket calls `answered()` like a poll, and the banners then mean "neither push nor poll answered".

**Consumes:**
- 2.2: `LiveState`, its polling and reload, and the session gate;
- 2.10: `banner-view.ts` (own conditions, closing), and `banner-stack.ts` (announcements, focus, look);
- 2.1: `Announcer`, the banner tokens and `main.main`;
- 0.9 and 2.5: `catalog.ts`'s two texts.

**Extend, don't copy (Rule 2).**
- `ContactWatch` follows `BusyState`'s pattern (framework-free, injected timers, `onChange`) and does not extend it. `BusyState` is one call's busy and notice machine. A shared base would carry two unrelated machines.
- `fakeClock` moves to `web/scripts/fake-clock.mjs`, shared by both tests. It is not copied.
- The banners, closing, announcements and focus are Story 2.10's code, given `own` and one replacement entry.
- B15's skip reuses L3's injection pattern.

**Ledger (Rule 17):** no entry is owned by this story (the inbox is empty).

## Verification

**IRIS.** This story changes no ObjectScript, so no slot call is needed. If a stage makes one:
- every IRIS MCP call names `server: ocutalon-slot-b` and `namespace: OCUTALON`;
- the first call is `iris_server_info` (build 154, port 1991);
- there is one `iris_execute_tests` call per message.

**Throwaway commands** are `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_RUN_TAG=e2s211i OCUTALON_LOCK_OWNER='epic=2 stage=implement' bash ci/iris.sh <piece>`.
- `<main checkout>` is the main checkout's absolute path. It is typed only at the prompt, never in a tracked file.
- Run one piece per call with `timeout: 600000`, and end with `teardown` on the same tag and variables.
- `LOCK busy` (exit 75) means contention: wait and run it again.
- QA uses `e2s211q` and review uses `e2s211r`.

**Every other command** runs in the foreground with `timeout: 600000`.

**Commands:**
- (loop) Each in its own call: `npm --prefix web test`, `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `bash docker/tests/test-web-build.sh`, `bash docker/tests/test-boundaries.sh`. Expected: exit 0. The new `contact-watch.test.mjs` and `banner-view.test.mjs` cases pass.
- (loop) Throwaway, one piece per call: `build`; `live sign-in`; `teardown`. Expected:
  - B13 to B16 and L13 pass, with every other chromium spec;
  - B6 and the demo-path "not built" case skip, as before;
  - teardown leaves nothing.
  - The time budget: about 384 s of the local 540 s deadline before this story. The four cases add about 30 to 50 s (inference), and CI's 1200 s holds.
- (once) `bash ci/checks.sh`. Expected: exit 0.
- (once) Throwaway, one piece per call: `build`; `live demo-path`; `live bundle-folder`; `teardown`. Expected: both pass, with the demo path's floor unchanged. Together with `live sign-in`, these are the `browser` group.

**Planned mutations (Rule 19).** For each one: apply it, observe red, restore a byte-identical tree (`git status --short` and `git diff --stat` unchanged), and record `mutation: … → …` here.

| AC | Mutation | Expected red |
| --- | --- | --- |
| Lost contact | `RECONNECTING_AFTER_MS` 20 000 | `contact-watch.test.mjs`; B13 (no banner after 10 s) |
| Lost contact | `UNREACHABLE_AFTER_MS` never fires | `contact-watch.test.mjs`; B13 |
| Lost contact | `pollDelay` ignores `unreachable` | `contact-watch.test.mjs`; B13 (about 20 attempts) |
| Lost contact | `REPLACED_BY` empty | `banner-view.test.mjs`; B13 (focus on `noModelKey`) |
| Lost contact | `banner-stack` keeps `own: []` | B13 |
| Recovery | `applyPoll` does not call `answered()` | B14 (Unreachable stays) |
| Recovery | `accept()` does not call `answered()` | B15 (Unreachable stays after the reload) |
| Not lost contact | A 503 not counted as an answer | B16 (Reconnecting at 10 s of 503s) |
| Lost contact | Any HTTP error answer counted as an answer | B16 (no Reconnecting after 10 s of 500s) |
| Not lost contact | `ContactWatch.stop()` leaves its timers armed | `contact-watch.test.mjs` |
| Not lost contact | `LiveState.stop()` does not call the watch's `stop()` | B16 (Reconnecting stays after Sign out) |

**Mutations observed (Rule 19).** Each one was applied alone, run, and restored from a copy. After every restore `git status --short`, `git diff --stat` and a hash of the whole diff and of the new files matched the state before it. The browser runs used the throwaway stack `e2s211i` with the `chromium` project narrowed to the case named; the Node runs used `node --test web/scripts/contact-watch.test.mjs web/scripts/banner-view.test.mjs`.
- mutation: `RECONNECTING_AFTER_MS` 20 000 -> `contact-watch.test.mjs` (thresholds, 9 999 and 10 000, answer and recount, onChange, stop); B13 ("after 10 s Reconnecting shows", 0 banners); L13 ("10 s after the last answer Reconnecting shows")
- mutation: the 30 s timer's `this.change('unreachable')` removed -> `contact-watch.test.mjs` (the 29 999 and 30 000 case, the recount case); B13 ("after 30 s Unreachable shows", 0 banners)
- mutation: `pollDelay` returns `normalMs` for every state -> `contact-watch.test.mjs` ("is 10 000 minus the elapsed time for unreachable"); B13 ("twice or three times in 20 s", 17 attempts)
- mutation: `REPLACED_BY` = `{}` -> `banner-view.test.mjs` ("are exactly Unreachable replacing Reconnecting"); B13 ("focus moved to the banner that replaced the one that held it", focus not on Unreachable)
- mutation: `banner-stack.ts` `own: []` -> B13 ("after 10 s Reconnecting shows")
- mutation: `applyPoll` without its `this.watch.answered()` -> B14 ("and Unreachable has left", 1 banner)
- mutation: `accept()` without its `this.watch.answered()` -> B15 ("and both banners are gone within one live update of that", 1 banner)
- mutation: a 503 not counted (`isBusy` compares `BUSY_STATUS + 1`) -> B16 ("a 503 is an answer: no banner of its own", 1 banner)
- mutation: any HTTP error counted as an answer (`isBusy` true for a status of 100 or more) -> B16 ("the same route answering 500: after 10 s Reconnecting shows", 0 banners)
- mutation: `ContactWatch.stop()` without `cancelTimers()` -> `contact-watch.test.mjs` ("gives ok at stop(), leaves no timer pending, and ignores an answer after it")
- mutation: `LiveState.stop()` without `this.watch.stop()` -> B16 ("a stopped page claims no lost contact: Reconnecting leaves at once", 1 banner)
- mutation: `fetchSnapshot` without its `/state` 503 branch (`onError()` alone) -> B16 ("a 503 of the reload is an answer: Reconnecting leaves", 1 banner)
- mutation: `applyPoll` calls `this.watch.answered()` before its reload branch -> B16 ("while the reload is out nothing has answered: Reconnecting stays", 0 banners)
- mutation: `keepFocus` picks `replacement ?? next ?? previous` -> B14 ("focus goes to the banner before it, as no banner replaces Reconnecting yet", focus inactive)

**Shared surfaces:**
- `.banner-slot`'s content: an own banner now shows in any spec whose live requests get no good answer for 10 s after the load. Today that is only L13, which Task 8 updates. Any count of `[data-banner]`, the slot's height, or announcements in such a spec changes (Task 10).
- `LiveState`:
  - the new `contact` signal;
  - `stop()` also ends the watch;
  - the retry cadence after 30 s with no answer (L8's 1 to 2 s holds before that).
- `banner-stack.ts`'s focus rule gains the replacement step. B5 and B10 are unchanged, because no other banner has a replacement.
- `busy-state.test.mjs`: `fakeClock` moves to `fake-clock.mjs`.
- `test-sign-in.sh`'s labels and `banner-styles.test.mjs`'s header.
- No server surface changes: the instance stream, `/state` and `/events` are untouched.

Every test added or changed passes on a fresh environment, in either order:
- B13 to B16 install their own clock and routes. `afterEach` unroutes them.
- They publish only on the `BANNERS` user's own session stream and clear every condition they turn on in `finally`. B15 removes its seeded check with `cleanFixtureRows`.
- B16's Sign out ends only its own browser context's CSP session. Every case signs in again.
- The Node tests use the fake clock only.

**Manual checks:** none.

## Auto Run Result

Status: done
Blocking condition: none

**Implemented change.** The page now says plainly when it loses contact.
- `ContactWatch` (new, framework-free) counts 10 s and 30 s from the last answer of the live path. `LiveState` owns it, exposes `contact`, and counts an applied poll, an accepted snapshot and a 503 as answers. While unreachable, polls start 10 s apart. `stop()` ends the watch.
- `BannerStack` shows Reconnecting and Unreachable from `contact` through Story 2.10's catalog, closing rule and announcements. `REPLACED_BY` makes focus move from Reconnecting to Unreachable.
- Browser cases B13 to B16 and L13's additions run in a real stack with `page.route` and `page.clock`. `contact-watch.test.mjs` pins the exact thresholds.

**Files changed.**
- `web/src/app/live/contact-watch.ts` (new): the watch, its constants and `pollDelay`.
- `web/src/app/live/live-state.ts`: the watch, `contact`, the answer rule, the 10 s retry, `stop()`, the class doc.
- `web/src/app/banners/banner-view.ts`: `REPLACED_BY`.
- `web/src/app/banners/banner-stack.ts`: `own` from `contact`, the replacement step in `keepFocus`.
- `web/scripts/contact-watch.test.mjs` (new), `web/scripts/fake-clock.mjs` (new, moved from `busy-state.test.mjs`), `web/scripts/busy-state.test.mjs`, `web/scripts/banner-view.test.mjs`, `web/scripts/banner-styles.test.mjs`: Node tests and the shared fake clock.
- `web/e2e/banners/banners.spec.ts`: B13 to B16. `web/e2e/live/live.spec.ts`: L13 asserts Reconnecting during the hung poll and its clear.
- `docker/tests/test-sign-in.sh`: header and PASS and FAIL labels name B13 to B16.

**Review.** Four layers reported 23 findings: high 0, medium 3, low 16, false 4.
- Patched (3 entries): the reload leg of the answer rule was unpinned (a 503 of `/state`, and the banners clearing only when the reloaded snapshot applies), so B16 gained a fourth phase; focus after closing Reconnecting was unasserted, so B14 asserts it; two live-state.ts comments overclaimed the cadence and were reworded. Three mutations were added and observed red.
- Deferred: none.
- Rejected with reasons (rows 1, 2, 6 to 12, 17 to 23 of the triage log): a 503 counted by status alone is the spec's and AD-25's rule; late timers after a sleep follow Decided 3; the reload that fails is the matrix's own "still no answer"; the rest are theoretical, pre-existing, duplicate or already settled by a task.
- Follow-up review recommended: false. The patches are test-only apart from two comments, and each is demonstrated by a mutation (patched entries: medium 1, low 2).

**Verification performed.**
- `npm --prefix web test` 388 pass; `npm --prefix web run lint`, `node web/scripts/catalog.mjs --check`, `bash docker/tests/test-web-build.sh` and `bash docker/tests/test-boundaries.sh` exit 0.
- Throwaway `live sign-in` (tag e2s211i): 186 passed and 2 skipped, B13 to B16 and L13 among the passes, 403 s of the local 540 s deadline (398 s on the first run; about 384 s before this story). `live demo-path` passed (floor 3 of 3), `live bundle-folder` passed, `bash ci/checks.sh` exit 0, teardown left nothing.
- Fourteen mutations recorded under `## Verification`, each applied alone, seen red and restored byte-identical.

**Residual risks.**
- A 503 counts as an answer by status alone (the spec and AD-25). A 503 from anything other than IRIS in front of a dead IRIS would hide the banners; Story 16.5 can narrow it with the `X-OcuTalon-Busy` marker.
- After a sleep or in a long-hidden tab the thresholds can fire before the first answer lands, so a banner may flash and clear.
- B13's "before 30 s" checks have about 5 s of margin on this host, and L13's new check about 2 s.

**Plan stage (2026-10-24).** The plan halted after planning, as the dispatch asked.
- It reused the committed `epic-2-context.md` (aa2910e) without recompiling it.
- It took Story 2.10 as the continuity context.
- It ran no runtime measurement and started no throwaway.
- It changes no server code.
- **One recommendation is flagged for the lead:** the Conventions sentence under "For the lead" (Decided 4).
- The ledger inbox was empty.
