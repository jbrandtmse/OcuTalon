---
title: 'Story 29.9: Epic 29 burn-down'
type: 'bugfix'
created: '2026-10-30'
status: 'done'
baseline_revision: '7e4b70acb87116fd6fbe7e0f97bf09f06b4ebc4a'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md'
warnings: [oversized, multiple-goals]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Two timing flakes still turn Epic 29's CI runs red with no defect behind them, and Epic 29's merge gates the online demo's public launch. DW-333: 38 sign-in sites (some of them `open()` helpers that many cases call) still give `main.main` only the default 10 s to reach `data-snapshot="loaded"`. A loaded host that answers the first GET `/state` late fails them (CI run 41149604870: `chat.spec.ts` C7, `open()` at :61). DW-429: L2 jumps the page's clock 20 s across the idle cap in one `page.clock.runFor`. `page.clock` also fakes `AbortSignal.timeout`, so the page's 3 s bound for the group sign-out lasts only about 10 ms of real time. The page can then leave before IRIS has ended the session, get the application instead of the splash, and lose `?since=` (CI run 41027546659: since parsed NaN).

**Approach:** Tests only. Wrap each remaining sign-in in the existing `loadedAfter` (or `signInReadmeLoaded`). In L2, and in L7, which crosses the cap the same way, let the page's clock run with the wall clock across the cap, so that the group sign-out's 3 s bound is real time again. Decline DW-432: its test-side fix would hide a real count mismatch (Design Notes). Prove each fix against its failure mode with a held response, then run each affected live unit once.

## Boundaries & Constraints

**Always:**
- Change only spec files under `web/e2e/**` and `web/e2e-online/**`, in the sites the Code Map lists.
- Every assertion stays as it is. A fix changes when a case waits, never what it expects: no removed or loosened `expect`, the 5 s `since` window included.
- Reuse `loadedAfter` and `signInReadmeLoaded` from `web/e2e/support/floor.ts` (Rule 2). They make no request of their own, so the cases that count `/state` requests (api row 13, frame F9, live) keep their counts.
- Prove each fix's failure mode with a held response (AC1, AC2). The scratch cases and holds are removed afterwards, and the tree is again exactly the story's change.
- Run every live unit on a named lane-C throwaway, one unit per foreground call (Verification).
- No local path, host detail or literal non-ASCII byte goes into a tracked file (Rule 14; the repository is public).

**Never:**
- No change to `src/`, `web/src/`, `docker/`, `ci/`, `release/`, or the support helpers (`web/e2e/support/**`, `web/e2e/sign-in/helpers.ts`, `web/e2e-online/support.ts`). No new helper.
- No longer timeouts, retries, `test.fixme`, `test.skip` or `test.fail` in the final tree.
- Do not touch Epic 12's `web/e2e/demo-path/telegram-*.spec.ts`, `reset.spec.ts` R9's plain sign-in (by design: it waits only for the resetting view), or any contended path.
- DW-432: D1 is not reordered (S1 before the seed), and `Bridge.Budget` and `StatusMonitor` are not changed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Sign-in, prompt `/state` | first GET `/state` answered in 1-2 s | case passes as today | none |
| Sign-in, late `/state` | first GET `/state` held 12 s | `loadedAfter` waits for the 200, then up to 10 s for `loaded`; case passes | a non-200 fails with "the snapshot is served" |
| Idle cap, prompt sign-out | L2 or L7; the page's `?IRISLogout=end&t=` answered in 1.5 s | splash at `?since=<load time>`, place-freed notice above both cards, context `/state` 401 | none |
| Idle cap, sign-out never answered | product bound `SIGN_OUT_LIMIT_MS` | the page leaves at 3 s (L4c pins it, unchanged) | none |

</intent-contract>

## Code Map

**The wait to reuse (read-only)**
- `web/e2e/support/floor.ts:135-152`:
  - `loadedAfter(page, action)` arms the GET `/state` wait before the action, expects 200, then waits 10 s for `data-snapshot="loaded"`;
  - `signInReadmeLoaded(page)` is `loadedAfter` around `signInReadme`.
- `web/playwright.config.ts:38-39`: case timeout 45 s, expect 10 s. So the `/state` wait is bounded by the case and the attribute by 10 s.
- Already fixed, leave as is:
  - the demo-path specs (Story 29.7);
  - the online sign-ins through `openSession`, `openVisitor` and `signInFromSplash` inside `loadedAfter`;
  - `banners.spec.ts` `open()` and `openFloor`;
  - `rail.spec.ts:82-87` R1's `open()` (its own inline wait for the answer, Story 16.4).

**DW-333: the sites to wrap (38 sites in 24 files; the enclosing function or case, the line of its 10 s wait, and the unit that runs it)**
- `live sign-in` (the chromium project):
  - `api/api.spec.ts` row 13 :125. Keep `instanceBaseline` inside the wrapped action, so its order against the page's boot is unchanged.
  - `chat/chat.spec.ts`: `open()` :61 (C7's red, and every chat case that calls it); C1 :140 (`signInReadme`).
  - `chat/decision.spec.ts` `open()` :99; `chat/notice.spec.ts` `open()` :51.
  - `frame/frame.spec.ts`: F1 :64, F2 :110, F3 :127 and F9 :505, all `signInReadme`.
  - `guide/guide.spec.ts` `open()` :109 (`signInReadme`).
  - `heartbeat/heartbeat.spec.ts` H1 :102; `live/live.spec.ts` `open()` :29.
  - `phone/phone.spec.ts` `open()` :38 (`signInReadme` after `changeSnapshot`; the fulfilled 200 answers the wait).
  - `reminder/chat.spec.ts` `open()` :109; `trace/links.spec.ts` `open()` :122.
  - `session/session.spec.ts`: S1 :80 and :106 (`firstState` and `secondState` stay armed); S3 :145; S3 (no further call) :184; S5 :234 (the action is the first `goto('/ocutalon/')` after the trace group sign-in); S7 :258.
  - `sign-in/shell.spec.ts` row 8: the Sign in click at :16, its wait at :38.
  - `sign-in/sign-in.spec.ts`:
    - row 5 :132: the Enter press;
    - DW-4 with a fragment :242 (two targets);
    - DW-4 after a wrong password :273;
    - DW-4 with no fragment :289 (two targets). The action is `submitSignIn`, and its `Response` is kept for the assertions after it.
- `live demo-switch`:
  - `demo-switch/badge.spec.ts` :24 and :51;
  - `demo-switch/mailbox.spec.ts` `openMailbox()` :56 and MB6 :301;
  - `demo-switch/phone.spec.ts` :35. All are `signInReadme`.
- `live floor`: `floor/announcements.spec.ts` `open()` :74 (the clock is installed first, which the Node-side wait ignores).
- `live answers`: `answers/answers.spec.ts` `open()` :68; `answers/close-loop.spec.ts` `open()` :114.
- `live cards`: `cards/approval-card.spec.ts` `open()` :100; `cards/incident-card.spec.ts` `open()` :100.
- `live online-demo`:
  - `web/e2e-online/reset.spec.ts` R2 :333-335: `fresh`'s click and `await answered` together form the action. That page is already on the splash, so not `signInFromSplash`, which navigates again.
  - `web/e2e-online/splash.spec.ts` S5 :420-421: the Enter press.
- Not sign-ins, out of scope: reloads, a new tab of a page that is already signed in (links V5, V7, V11, V12; layout; leave L5), the release of a held answer (live, scan, words, resume R3), and daily-cap AP's reload. None has gone red. reopen_if: one of them goes red with `data-snapshot` still loading.

**DW-429: the idle cap (Epic 29's own files)**
- `web/e2e-online/session/leave.spec.ts`:
  - L2 :101-143, with its header line :33-35;
  - the one jump `try { page.clock.runFor(20_000) } catch` :125-129, then `landedOn` :130 and `expectPlaceFreed` :60-74 (the `since` check :63-64).
- `web/e2e-online/session/idle-activity.spec.ts`: L7 :24-55, header :11-13, and the same jump `runFor(25_000)` :41-45 before its own `since` check :46-50.
- The product, read-only:
  - `web/src/app/session/session-gate.ts`: `leave()` :150-165 and `groupSignOut()` :167-184 (`AbortSignal.timeout(SIGN_OUT_LIMIT_MS)`, 3000);
  - `web/src/app/session/splash-address.ts` always writes a valid ISO `since`;
  - `web/src/index.html:6` `<base href="/ocutalon/">` with `withHashLocation()`. So the application served at `/ocutalon/?since=X` rewrites its address to `/ocutalon/#/` (`sign-in.spec.ts:243-244` documents the dropped query). `since` then reads NaN.
- `web/e2e-online/support.ts:66-68`: `landedOn` (`waitForURL`, until load).
- `web/e2e/support/clock.ts`:
  - `runUntil` :111-121 waits only for the requests that `recordTraffic` (:42-69) logs;
  - `recordTraffic` logs `/ocutalon/api/v1/` only, never the group sign-out.

**DW-432 (declined; read-only evidence)**
- `web/e2e-online/allowance/daily-cap.spec.ts` D1 :105-151: S2 opens, `seedUsage(20)`, then S1 opens (:118-120), and the banner check is at :137-140.
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls:29-41`: `State()` counts the Usage spend only in a process with the SQL privilege. A web process's `/state` gets the fault line instead.
- `src/ocutalon/cls/OcuTalon/Core/StatusMonitor.cls:1-15`: counts the spend and publishes only on a change.

## Tasks & Acceptance

**Execution:**
- Each `web/e2e/**` and `web/e2e-online/**` file in the DW-333 list: wrap the sign-in action in `loadedAfter` (for example `await loadedAfter(page, () => signIn(page, user, password))`), or replace `signInReadme(page)` with `signInReadmeLoaded(page)`.
  - Import from `../support/floor` (`../../e2e/support/floor` from `web/e2e-online/`).
  - Keep the line after it, the 10 s `data-snapshot` expect, as a re-check.
  - Keep every other line and assertion. Drop an import that is left unused.
  - This removes the race that failed C7.
- `web/e2e-online/session/leave.spec.ts`: in L2, delete the try/`runFor(20_000)`/catch at :125-129.
  - After the third `advance`, the page's clock runs on with the wall clock. The cap fires about 10 s later, the group sign-out's 3 s bound is real time, and `landedOn` (60 s) waits.
  - The header's L2 line states this as the case's contract (Rule 14). The rest of L2, `page.clock.resume()` included, stays.
- `web/e2e-online/session/idle-activity.spec.ts`: the same change for L7's `runFor(25_000)` at :41-45 (about 20 s of wall clock), and its header line.

**Acceptance Criteria:**
- **AC1 (DW-333; FR-15, AD-12, AD-22).** Given every case in the DW-333 list, when its first GET `/state` is answered more than 10 s after the sign-in, then the case still passes, because it waits for that answer (200) before its 10 s wait for `loaded`.
  - Pin: `chat.spec.ts` C7, with `/state` held 12 s.
- **AC2 (DW-429; AD-13).** Given L2 and L7 on the online-session stack, when the idle cap fires and the page's group sign-out is answered within its 3 s bound, then:
  - the page lands on the splash at `?since=` its load time, to the second;
  - the place-freed notice is above both cards;
  - the context's `/state` answers 401.
  - Pin: L2, with the page's `?IRISLogout=end&t=` request held 1.5 s.
- **AC3 (standing, Rule 19; FR-15).** Given the final tree, when each affected live unit runs once on its own fresh throwaway, then every unit passes, with no unchanged rerun. Every test added or changed passes on a fresh environment, in either order.

### Review Findings

Code review, 2026-10-30, full mode. Four layers ran: blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all on the session's model (no `model-overrides.yaml`, so full-opus). There were 20 findings. 6 of them form 3 patch entries (1 med, 2 low), all applied. None needed a decision, none was deferred, and 14 were rejected.

- [x] [Review][Patch] Ten sign-ins in `frame.spec.ts` still gave the snapshot only the bare 10 s wait, DW-333's root cause [web/e2e/frame/frame.spec.ts:170]
  - Sites: the F3 badge loop at :170 (two cases), F5 :232, F6 :240, :307, :324 and :337, F7 :383, and F8 :424, :466 and :487.
  - Each one is a `signInReadme` followed by a 10 s expect on the badge or on the account button. Both come from the snapshot: `header.ts` `accountName` reads "Account" until `/state` answers.
  - The fix swaps each for `signInReadmeLoaded` and keeps every expect after it.
  - The manual grep under Verification only matches `data-snapshot` waits, which is why it missed these sites.
  - Med, fix-risk low (the same swap as F1 to F3 and F9), in-story. Sources: blind-hunter and verification-gap.
- [x] [Review][Patch] L2's header claimed without condition that IRIS has ended the session before the page leaves [web/e2e-online/session/leave.spec.ts:36]
  - `groupSignOut()` leaves at IRIS's answer or at the 3 s bound, whichever comes first, so the claim holds only when IRIS answers within the bound.
  - The header now states that as what the case needs (Rule 14).
  - Low, fix-risk low, mechanical. Sources: blind-hunter and edge-case-hunter.
- [x] [Review][Patch] DW-4 resolved the 303's Location against the address after the page booted [web/e2e/sign-in/sign-in.spec.ts:241]
  - With the submit inside `loadedAfter`, `page.url()` is read after the router has rewritten the address (`/ocutalon/#/...`, query dropped), no longer at the posted address. A query-only Location would then resolve wrongly.
  - Both DW-4 sites (:241 and :294) now resolve against `response.url()`, the posted address, which is RFC 7231's base. The assertion's input is again what it was before the wrap.
  - Low, fix-risk low, mechanical. Source: edge-case-hunter.

**Evidence after the patches (lane C throwaways, tag `e29s9cr`, torn down):**
- `npm --prefix web run lint`: exit 0.
- `live sign-in --part 1/2`: 127 passed, 340 s.
- `live sign-in --part 2/2`: 96 passed, 330 s.
- `live online-session`: 12 passed, 1 skipped (L6, by design), 329 s.
- All passed first time. The bundle was built after the last `web/src` change, so no rebuild was needed.

**Rejected (14):**
- `low` (blind-hunter) The Auto Run Result and Design Notes still describe DW-432 as an open request for the lead. The fix would edit the spec under review, and `epics.md` already records the move to 31.3.
- `low` (blind-hunter, edge-case-hunter, acceptance-auditor; 3 findings) The Summary says "24 spec files under `web/e2e/**`" where it should say 22, and its folder glob covers more files than changed. The fix would edit the spec under review.
- `low` (blind-hunter) The Verification record leaves out the build, the `e29s9iw` teardown and the pass counts for two units. The fix would edit the spec under review. Nothing tagged `e29s9i` was left running when this review began.
- `false` (blind-hunter) Row 2's coverage is claimed beyond what was shown. Rule 19 asks for one demonstrated mutation per AC, and AC1's (C7) is recorded. The wording would be a spec edit.
- `low` (edge-case-hunter, 2 findings) A sign-in that never reaches the page now fails at the case timeout (45 s, or 240 s for R2) rather than at a named 10 s expect, and R2's `finally` may then not restore the reset anchor.
  - This only happens on a case that is already red. The fix would add a guard, or lies in `web/e2e/support/floor.ts`, which is forbidden.
  - reopen_if: a CI red where a wrapped sign-in times out at the case timeout and later cases of the same unit fail from what it left behind.
- `low` (edge-case-hunter) If IRIS takes more than 3 s to answer the group sign-out, L2 and L7 still go red with `since` NaN.
  - The 3 s is the product's bound (`SIGN_OUT_LIMIT_MS`, pinned by L4c). A timing assertion in the test would only rename a case that is already red.
  - What would make it real: a CI or demo log in which `?IRISLogout=end&t=` takes more than 3 s.
- `false` (verification-gap) AC3 has no `mutation:` line. AC3 is the standing fresh-run criterion and has no code under test to mutate; the recorded runs are its evidence.
- `false` (verification-gap) L7 has no red run of its own. Rule 19 asks for one mutation per AC, and AC2's pin, L2, has its recorded line.
- `low` (verification-gap) The committed tree cannot catch a revert on a fast host. This is by design: the spec requires the holds to be removed, and the mutations are recorded.
- `low` (acceptance-auditor) L7 does not assert AC2's "above both cards". This is by design: no assertion may be added, and L2's `expectPlaceFreed` covers it.
- `low` (acceptance-auditor) Design Notes still carry the DW-432 item for the lead. The fix would edit the spec under review; this duplicates the first DW-432 row.

## Spec Change Log

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 19 findings: high 0, medium 0, low 14, false 5, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the Auto Run Result still reads ready-for-dev: the section is rewritten at finalize, in this same pass.
  - `[low]` `[reject]` Blind: the planned AC1/AC2 mutation bullets duplicate the recorded `mutation:` lines: the fix edits this build's spec, and the recorded lines are the ones Rule 19 scans.
  - `[false]` `[reject]` Blind: AC3 evidence is missing: recorded under Auto Run Result at finalize (every unit, with seconds).
  - `[low]` `[reject]` Blind: L7 has no red run of its own: the spec pins AC2 on L2 (Design Notes, T0-a measured the mechanism); L7 uses the same helpers and went green on the final tree; a second mutation run is optional scope.
  - `[false]` `[reject]` Blind: nothing keeps the 3 s group sign-out premise in the suite: the product bound is pinned by L4c (unchanged), and the held 1.5 s run was the story's proof by design.
  - `[low]` `[reject]` Blind: the dead `[]` initializer in api row 13: cosmetic; `instanceBaseline` asserts non-empty itself.
  - `[low]` `[reject]` Blind: `loadedAfter` appended at the end of sorted import lists: cosmetic, lint is green.
  - `[low]` `[reject]` Edge: the DW-4 303/Location assertions run after `loadedAfter`, so a bad redirect reads as a /state wait timeout: still red; the spec prescribes this wrapping and keeps the assertions as they are.
  - `[low]` `[reject]` Edge: the row 5 303 assertion runs after the snapshot wait: same reason.
  - `[false]` `[reject]` Edge: a paused clock would never cross the cap: `install()` leaves the clock running, L2 keeps `resume()`, and L2 and L7 were green on the final tree.
  - `[low]` `[reject]` Edge: L2 leaves 10 s of wall clock for the "still there" check: the old jump had the same margin (the clock ran on during the checks); a larger margin is a spec change.
  - `[low]` `[reject]` Verification gap: AC3 has no `mutation:` line: the spec states it is the standing criterion and the final runs are its evidence.
  - `[low]` `[reject]` Verification gap: L7 has no mutation of its own (disposition defer): as for Blind's L7 row; spec pins AC2 on L2.
  - `[low]` `[reject]` Verification gap, other: the un-prefixed `AC1:`/`AC2:` plan lines sit beside the `mutation:` lines: spec text, same as the duplicate-bullets row.
  - `[false]` `[reject]` Intent: the late-/state and held-sign-out conditions are not committed as code: the Approach and Boundaries require the scratch cases to be removed; the proof is the recorded mutation run.
  - `[low]` `[reject]` Intent: L7 does not assert "notice above both cards" (AC2 wording is wider): L7's assertions are unchanged by the story's constraint (no assertion added or removed); not caused by this change.
  - `[low]` `[reject]` Intent: other raw sign-ins remain outside the list (frame, live, rail, focus, reminder, shell, links): the Code Map and Decided-in-stage 1 exclude reloads, held-state and new-tab sign-ins; the manual grep was reviewed by hand.
  - `[low]` `[reject]` Intent: the spec file itself sits outside `web/e2e/**`: the story's own record, written by the workflow.
  - `[low]` `[reject]` Intent: a failed sign-in now surfaces at the /state wait: duplicate of the Edge rows.

## Design Notes

**Ledger inbox (Rule 17):** `owned_ledger=3`, every entry answered.
- **DW-333:** addressed (AC1). These are the six occurrences' residual sites: every sign-in that still gave the snapshot only the bare 10 s wait. At adjudication: `resolved-by` this story, when the units are green.
- **DW-429:** addressed (AC2). L7 is the same root cause in the same unit, so it joins: leaving it would keep the flake class open in `live:online-session`. At adjudication: `resolved-by` this story.
- **DW-432:** declined.
  - Why: D1 is the one browser case where a page loads between the moment the counted Usage spend reaches the cap and the moment the day's mark lands. In that window `/state` and StatusMonitor disagree:
    - a web process holds no SQL privilege on Usage, so `Budget.State()` there counts the mark and the gateway's spend only (AD-20's status reads, AD-24's grants);
    - StatusMonitor counts the spend, publishes `dailyCap` at its next tick, and publishes nothing when the mark lands.
    - So a visitor who arrives in that window never gets the "daily cap" banner live. That is a real, user-facing gap.
  - What it rules out: signing S1 in before the seed would remove the only test that sees the gap, and would hide it. Any other test-side change weakens D1's banner check.
  - The right owner: a product story in which `/state` and StatusMonitor agree on `dailyCap` (for example, the monitor marks the day when its own reading reaches the cap). It touches `OcuTalon.Core.StatusMonitor` (Lane B) and possibly `src/bridge/**` (Lane A, contended).
  - For the lead at adjudication: re-own DW-432 to a Lane B story, recommended in Epic 31 (post-demo hardening). Adding the bullet to another epic's not-yet-planned story is the orchestrator's call (veto item 8). Until then, D1 stays under the flake rule (one rerun).
  - For the lead: Story 29.9's AC in `epics.md` names the daily-cap case ("no longer races the status monitor's first tick"), and this story does not deliver that clause. Amending the AC with DW-432's new owner is the lead's Rule 5 call (the ask-first tier: it narrows an AC).

**DW-429's mechanism.** Task 0 measured part of it; the rest is inference.
- **T0-a (measured, this plan; Playwright 1.64.1 Chromium, a local stand-in server that answers after 1.5 s, scratch only):**
  - Inside one `page.clock.runFor(20_000)`, a fetch with `AbortSignal.timeout(3000)` started at fake 10 s was aborted after 7 to 14 ms of real time (four runs).
  - With the clock running with the wall clock across the same timer, or after seven `runFor(1000)` steps, the fetch got its answer (11.5 s and 4.5 s in all).
  - The bundled clock source confirms it: `fakeAbortSignal` adds the timeout as a fake timer, and `_runTo` fires the timers one after another with a `setTimeout(0)` between them.
- **The CI red (inference):** the CI log shows NaN with the path `/ocutalon/` and no `signedOut`. That matches only the application's own rewritten address, `/ocutalon/#/`: the navigation reached IRIS while the session still existed.
- **Why not "wait for `since` to parse":**
  - in this failure the address never regains this page's `since`;
  - a later 401 exit would write the second page's load time, about 1800 s of page clock later, so the 5 s check fails anyway;
  - loosening that check would weaken L2.
- **The proof** is AC2's held sign-out. It is deterministic, because 1.5 s is far beyond the roughly 10 ms the fake bound leaves (T0-a). If the old jump with the hold does not go red, the cause is not this one: implement stops with a clarification and ships no DW-429 change.

**Architecture decisions (Rule 6):**
- AD-22: tests, throwaways and CI.
- AD-12: `/state`, the snapshot and polling.
- AD-13: the online demo's exits, the group sign-out and the splash's `since`.
- AD-20: the daily cap's status reads (DW-432).
- AD-29: lane files.

No AC contradicts an AD's Rule, and no NFR is unmeasurable (Rule 5).

**Integration ACs (Rule 1):** no service, module or shared component is introduced. No consumers in this story. Consumes: `loadedAfter` and `signInReadmeLoaded` (Stories 29.4 and 29.7), and the online-session and online-demo units.

**Extend, don't copy (Rule 2):** every DW-333 site reuses `loadedAfter` or `signInReadmeLoaded`. DW-429 removes code and adds none. `rail.spec.ts` R1's inline wait stays: it already waits for the answer, so replacing it is not a flake fix.

**footprint_extensions:** none of these is contended:
- `web/e2e/api/`, `answers/`, `cards/`, `chat/`, `demo-switch/`, `floor/announcements.spec.ts`, `frame/`, `guide/`, `heartbeat/`, `live/`, `phone/`, `reminder/chat.spec.ts`, `session/`, `sign-in/` and `trace/links.spec.ts`.

`web/e2e-online/**` is Epic 29's own.

**Decided in-stage:**
1. **"Signs in" means:** `signIn`, `signInReadme`, `submitSignIn`, `signInFromSplash`, a Sign in click or Enter on a sign-in form, and S5's first `/ocutalon/` after the trace group sign-in. Reloads and new tabs are excluded (Code Map).
2. **The re-check stays:** the snapshot expect after each wrapped action is kept, so the diff shows no assertion removed.
3. **api row 13** keeps its baseline read inside the action.
4. **The hold lengths:**
   - 12 s on `/state`: over the 10 s wait, under the 45 s case timeout; Stories 16.4 and 29.7 used it.
   - 1.5 s on the group sign-out: over the fake bound's ~10 ms, under the real 3 s bound.
5. **Mutation runs** use temporary scratch cases inside the spec under test, removed before the final runs.
6. **L7** joins DW-429.
7. **DW-432** is declined.

## Verification

Run every call in the foreground with `timeout: 600000`, one test call per message, against named lane-C targets.
- No IRIS MCP call is needed. Any that is made names `server: "ocutalon-slot-c"` and `namespace: "OCUTALON"`.
- `LANE` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=29 stage=implement'`.
- The fresh tag is `e29s9i` and the warm tag `e29s9iw`. No class runs, so warm mode is not used.
- If a unit dies of its 540 s deadline with no failed case, re-run it once with `OCUTALON_LIVE_DEADLINE=580`.

**Commands:**
- (loop) `npm --prefix web run lint`. Expected: exit 0 (tsc over the e2e specs).
- (once) `LANE OCUTALON_RUN_TAG=e29s9i bash ci/iris.sh build`. Expected: the bundle is built from this `web/src`, before any browser unit (Rule 21).
- (once) AC1's mutation run. Add a temporary 12 s hold on GET `/state` (a `page.route` that sleeps, then continues) to C7, and a temporary sibling `zz C7 old` that keeps the old `open()` (sign in, then the bare 10 s expect) under the same hold. Then run `LANE OCUTALON_RUN_TAG=e29s9i bash ci/iris.sh live sign-in --part 1/2`. Measured in this plan with `web/scripts/e2e-part.mjs`: part 1 holds the api, pairing, banners, chat, decision, notice, frame and guide specs (127 of 223 tests), and part 2 the other 11 files. Expected: `zz C7 old` is red at `toHaveAttribute` (10000 ms), and C7 is green. Then remove both, and `git diff` again shows only the story's change.
- (once) AC2's mutation run. Add a temporary hold to L2: a `page.route(/\/ocutalon\/\?IRISLogout=end&t=/)` that sleeps 1.5 s and then continues, catching the error when the page has already given the request up. Add a temporary sibling `zz L2 old` that keeps the one jump `runFor(20_000)` under the same hold. Run `LANE OCUTALON_RUN_TAG=e29s9i bash ci/iris.sh live online-session`. Expected: `zz L2 old` is red in `expectPlaceFreed` (since NaN, or no place-freed notice, because the application was served), and L2 is green. Remove both as above.
- (once) On the final tree, one call each, every one `LANE OCUTALON_RUN_TAG=e29s9i bash ci/iris.sh live <unit>`:
  - `sign-in --part 1/2` (about 5-6 min);
  - `sign-in --part 2/2` (about 5 min);
  - `demo-switch`, `floor` (up to about 9 min), `answers` and `cards` (about 3-6 min each, inference);
  - `online-demo` (about 3-6 min);
  - `online-session` (about 6-7 min, with L2 and L7 about 30 s longer).
  - Expected: each PASS, with no rerun (AC3).
- (once) `npm --prefix web test`. Expected: pass.
- (once) `bash ci/checks.sh`. Expected: every block passes (about 4 min).
- (once, before the finalize commit) `git diff --stat HEAD -- src web/src docker ci release web/e2e/support web/e2e/sign-in/helpers.ts web/e2e-online/support.ts web/e2e/demo-path _bmad-output/planning-artifacts/architecture`. Expected: no output.
- (once, at the end, also after a failure) `LANE OCUTALON_RUN_TAG=e29s9i bash ci/iris.sh teardown` and `LANE OCUTALON_RUN_TAG=e29s9iw bash ci/iris.sh teardown`. Expected: nothing tagged `e29s9i` or `e29s9iw` is left.

**Mutations (Rule 19), recorded as `mutation: <change> -> <test red>` when run:**
- AC1: the old `open()` (bare 10 s wait) with `/state` held 12 s -> `zz C7 old` red; C7 with `loadedAfter` and the same hold is green.
- AC2: the one jump `runFor(20_000)` across the cap with the group sign-out held 1.5 s -> `zz L2 old` red in `expectPlaceFreed`; L2 with the wall clock and the same hold is green.
- mutation: the old `open()` (sign in, then the bare 10 s `data-snapshot` expect) with GET `/state` held 12 s, as the scratch case `zz C7 old` in `chat.spec.ts` -> `zz C7 old` red at `toHaveAttribute` (10000 ms, `data-snapshot` still "loading"); C7 with `loadedAfter` and the same hold green (`ci/iris.sh live sign-in --part 1/2`: 127 passed, 1 failed, the scratch case; 346 s).
- mutation: the one jump `page.clock.runFor(20_000)` across the cap with the page's `?IRISLogout=end&t=` request held 1.5 s, as the scratch case `zz L2 old` in `leave.spec.ts` -> `zz L2 old` red in `expectPlaceFreed` (`since` NaN: "since is the time the page loaded, to the second", received NaN); L2 with the wall clock and the same hold green, and L7 green (`ci/iris.sh live online-session`: 12 passed, 1 failed, the scratch case, 1 skipped, L6; 262 s). Both scratch cases and holds removed afterwards; the tree is byte-identical to the story's change.
- AC3: the standing criterion. The final runs above are its evidence, so no mutation applies.

**Manual checks:**
- `grep -rn -B8 "data-snapshot', 'loaded')" web/e2e web/e2e-online | grep -E "await (signIn|signInReadme|submitSignIn|signInFromSplash)\(|press\('Enter'\)|exact: true \}\)\.click\(\)|await page\.goto\('/ocutalon/'\);"`. Expected, reviewed by hand: every hit is inside a `loadedAfter` action, is `rail.spec.ts` R1's `open()`, or precedes a reload or new-tab wait. No sign-in followed by a bare 10 s wait remains.

**Shared surfaces:** none. No list, menu, roster, schema or count that other tests assert on changes. `loadedAfter` and `signInReadmeLoaded` gain callers and are themselves unchanged. Each changed case still creates and removes its own state. Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Tests only. DW-333: every listed sign-in site (24 spec files under `web/e2e/**`, plus `web/e2e-online/reset.spec.ts` R2 and `splash.spec.ts` S5) is wrapped in `loadedAfter`, or uses `signInReadmeLoaded`; the 10 s `data-snapshot` expect stays after each as a re-check. DW-429: the 20 s and 25 s `page.clock.runFor` jumps are deleted from L2 and L7, so the page's clock crosses the idle cap with the wall clock and the group sign-out's 3 s bound is real time; their header lines state it. DW-432 stays declined (Design Notes).

**Files changed.**
- `web/e2e/{answers,api,cards,chat,demo-switch,floor,frame,guide,heartbeat,live,phone,reminder,session,sign-in,trace}/*.spec.ts` (22 files): sign-in actions wrapped in `loadedAfter` / `signInReadmeLoaded`, imports adjusted.
- `web/e2e-online/reset.spec.ts`, `web/e2e-online/splash.spec.ts`: R2's click plus `await answered`, and S5's Enter, wrapped in `loadedAfter`.
- `web/e2e-online/session/leave.spec.ts`, `web/e2e-online/session/idle-activity.spec.ts`: the clock jump removed; headers updated.
- This spec: `mutation:` lines, triage log and result.

**Review.** Four layers; 19 findings, all rejected (low or false, none high or medium); 0 patches applied, 0 deferred. Reasons are in the Review Triage Log. Follow-up review: not recommended (no patch applied).

**Verification (all on lane C throwaways, tag `e29s9i`, torn down; no unchanged rerun).**
- `npm --prefix web run lint`: exit 0.
- AC1 mutation (`live sign-in --part 1/2` with the scratch cases): `zz C7 old` red at `toHaveAttribute` (10000 ms), C7 green, 346 s.
- AC2 mutation (`live online-session` with the scratch cases): `zz L2 old` red in `expectPlaceFreed` (since NaN), L2 and L7 green, 262 s.
- Final tree, measured local seconds per unit: `sign-in --part 1/2` 325 s (127 passed); `sign-in --part 2/2` 319 s (96 passed); `demo-switch` 317 s; `floor` 365 s (105 passed); `answers` 338 s (20 passed); `cards` 232 s (19 passed); `online-demo` 384 s; `online-session` 284 s (12 passed, 1 skipped by design, L6). All PASS first time, no `OCUTALON_LIVE_DEADLINE` override needed.
- `npm --prefix web test`: 1127 pass, 6 s. `bash ci/checks.sh`: all scripts passed, 377 s.
- Footprint `git diff --stat` over the forbidden paths: no output. Manual grep reviewed by hand: remaining hits are inside a `loadedAfter` action, `rail.spec.ts` R1, or precede a reload, new-tab or held-answer release (`resume.spec.ts` holds `/state` on purpose).
- Matrix audit: rows 1 and 2 by the whole sign-in units (prompt and held `/state`, the latter by the C7 mutation run); rows 3 and 4 by L2/L7 and L4c in `online-session`.

**Residual risks.** The late-`/state` and held-sign-out proofs are one-off runs (scratch cases removed by design), not committed tests. L7 has no red run of its own; it shares L2's mechanism. A failed sign-in inside a wrapped action now shows as a `/state` wait timeout before the later status assertion.
