---
title: 'DW-1426: a closed card announces its undo''s answer and moves focus to the headline'
type: 'feature'
created: '2026-11-16'
status: 'done'
baseline_revision: 'bd9a04133e2ddace3d8d87919da120495835adcf'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-24-4b-show-the-new-fixes-partner-warnings-and-the-closed-card-undo.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** On a closed incident card (Story 24.4b), the request card of a pending undo of a rollback leaves the moment its answer lands (the Contest Planner's ruling (a): a closed card draws nothing once the undo is answered). Nothing is announced and focus falls to the main region, so a keyboard or screen-reader user gets no outcome (DW-1426).

**Approach:** when an undo answered on a closed card leaves the card, announce the EXISTING answered text ("Approved from {channel} at {time}." / "Rejected from {channel} at {time}. Nothing was changed.", the catalog's `answered.*` texts the page already renders) once, through the page's existing polite announcer, and move focus to the incident card's headline. No new string; no server change.

## Boundaries & Constraints

- Web only: `web/src/app/incidents/incident-card.ts` (and `incident-view.ts` only if a pure helper is needed), their unit tests (`web/scripts/incident-view.test.mjs`, `incident-sources.test.mjs`), and the Playwright spec `web/e2e/rail/step5-cards.spec.ts` (F6b). Extend the page's existing announce and focus rules (the ones a lost Dismiss already uses; Rule 2) — no new live region, no new focus mechanism.
- Only for an undo answered on a CLOSED card, by this page's own press or by an answer that arrives from elsewhere while the card is shown. An open card is unchanged.
- The text is the existing answered text for the actual outcome (approved or rejected); an expiry is announced only if the page already announces expiries elsewhere with an existing text; otherwise not (say which in Design Notes).
- Announce once; never twice for one answer; nothing for a request that was never drawn on this page.
- The online demo is unaffected (no setting history, no undo).

</intent-contract>

## Tasks & Acceptance

**Execution:**
- [ ] `incident-card.ts`: when a drawn undo request on a compact (closed) card leaves because it was answered, announce its answered text once and move focus to the card's headline (make the headline programmatically focusable if needed, `tabindex="-1"`, without changing its look or the tab order).
- [ ] Unit pins in `web/scripts/` for the source shape (the announcer and the headline focus are used by the closed-card path) as the existing source tests do.
- [ ] Playwright F6b (`step5-cards.spec.ts`): after Approve and after Reject on a closed card's undo, the page's live region holds the exact answered text once and `document.activeElement` is the incident's headline; an open card's answer behaves as today.

**Acceptance Criteria:**
- Given a closed card drawing a pending undo, when the user approves it, then the existing "Approved from {channel} at {time}." text is announced once and focus moves to the incident headline. Mutation: skip the announcement -> F6b red; mutation: leave focus where the chat focus rule puts it -> F6b red.
- Given the same, when the user rejects it, then "Rejected from {channel} at {time}. Nothing was changed." is announced once and focus moves to the headline (same mutations, the reject case red).
- Given an open card, when an undo or any request is answered, then behaviour is unchanged (existing tests stay green).

## Spec Change Log

- 2026-11-16 (lead). Chartered by the Contest Planner's ruling "DW-1426: APPROVED as a small follow-up" (~08:30Z Nov 16, BINDING), quoted from `<coordination>/prompts/story-243-rulings-20261116.md`:

  > Once an undo is answered, announce the EXISTING "Approved/Rejected from…" text and move focus to the incident headline. No new string. Pin both behaviours, each with a mutation. It goes into 1.0.12 if it merges before the cut. It is not a cut item. The earlier ruling (a), "nothing once answered", was about drawing request cards. It was not about announcing the answer.

  Branch `OCT-epic24-dw1426` from feature c5c4186c (Story 24.4b merged).

## Review Triage Log

### 2026-11-16 -- Review pass
- verdicts: every finding of the four layers is on a row below (grouped rows keep their members) -- high 0; medium 2 and low 1 patched; the rest low and rejected as not user-reachable, by design, or the repository's own convention
- findings:
  - `[low]` `patch` blind #1 / edge #1: an incident that reopens in the same update that answers a drawn undo counts its still-drawn requests as gone -- the departure test now compares against the refs drawn now (`now = new Set(refs)`, kept only while closed); the source pin follows.
  - `[medium]` `patch` verification-gap #1 / blind #3: an answer from elsewhere (focus outside the card, announced once, no focus move) and "announced once" for that path had no pinning test -- F6b (d) added (phone reject, focus blurred first), mutation recorded.
  - `[medium]` `patch` verification-gap #2: AC3 (open card unchanged) had no mutation line and its new assertion could not fail on the `closed` gate -- mutation `closed` always true, red on the open-card tests, recorded; the assertion stays as an extra pin.
  - `[low]` `reject` verification-gap #3 / blind #2: no executed unit host for `noteDrawn` -- the project's own convention for card components is source-text pins plus the live F6b run; extracting a helper is more than a direct correction.
  - `[low]` `reject` edge #2: a drawn undo that leaves with no status is silent and focus falls to main -- not an answer; the spec announces answers only; not reachable through the store's states.
  - `[low]` `reject` edge #3: a pointer press that leaves focus on the body (Safari) gets no headline focus -- the same limit as the lost Dismiss rule this extends; no new mechanism allowed.
  - `[low]` `reject` edge #4, #5, #6, #7: focus on the phone's answer line, a detached card, a card re-created across the answer, a ref-less request -- theoretical, no user-reachable path shown; each fix adds a guard branch.
  - `[low]` `reject` edge #8 and #9, intent-alignment (text, period, expiry and cancelled): the text is the page's own existing answered text (no final period on Approve, as the open card shows it); expiry and cancellation are announced with the existing text the page already uses for an open card (Design Notes); by design.
  - `[low]` `reject` blind #4 (focus order guard), #5 (fixed 1500 ms waits, which are longer than the announcer gap and cannot give a false pass), #6 (hard-coded text regex), #7 (FOCUS_CALLS order), #8 (doc comment), #9 (release bookkeeping, owned by the lead); intent-alignment (the `MAIN_REGION` export is the shared rule's own constant, extending it as Rule 2 asks), and the remaining verification-gap notes (source-text pins are the codebase's convention; the whole-load announcement count is order-dependent only within one test that starts from a fresh page).

## Design Notes

- Governing: UX-DR131 (focus when the focused item disappears), the page's announce rule (one polite announcer), AD-12 (the page renders catalog text), 24.4b's closed-card ruling.
- Ledger: DW-1426 is resolved by this commit (the lead appends `resolved-by` at merge).
- Text: the announced text is the approval view's status text (`statusOf`), the page's own form of the answered text: "Approved from the web chat at {time}" (no final period, as the open card's status shows it) and "Rejected from the web chat at {time}. Nothing was changed.".
- Expiry: the page already announces an expired request's status (`answered.expired`, approval-request-card.ts `noteStore`, for an open card); the closed card announces it with the same existing text when a drawn undo leaves expired.
- Focus: `incident-card.ts` `noteDrawn` moves focus to the headline only when focus was inside the request card that left, and only after the chat's focus rule has put it on the main region (the same wait-for-the-other-rules step `noteStore` uses). An answer from elsewhere with focus elsewhere is announced but takes no focus.

## Verification

Lane D: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'`, fresh tag `e24dw26`. One call each, about 150 s.
- (loop) `npm --prefix web test` -- all pass.
- (once) `npm --prefix web run lint` and `npm --prefix web run build` -- exit 0.
- (once) `LIVE_REBUILD_WEB=1 ci/iris.sh live sign-in-2 --part 12/20` (step5-cards) on tag `e24dw26` -- passed.

- Run results (tag `e24dw26`, after the review patch and the added F6b (d) case): `npm --prefix web test` 2185 pass, 0 fail; `npm --prefix web run lint` and `npm --prefix web run build` exit 0; `LIVE_REBUILD_WEB=1 ci/iris.sh live sign-in-2 --part 12/20` 11 passed (10 before the added case).
- mutation: `incident-card.ts` `noteDrawn` announce call replaced by a no-op -> F6b Approve and Reject (b1 cases and the two closed-card cases) red on "the answer is announced" (4 failed); reverted, `cmp`-identical.
- mutation: `incident-card.ts` `noteDrawn` headline `.focus()` call replaced by a no-op (focus stays on the main region) -> the same four F6b tests red on `toBeFocused` (4 failed); reverted, `cmp`-identical.

- mutation (answer from elsewhere takes no focus): `noteDrawn` `const focused = ...holdsFocus...` replaced by `true` -> F6b (d) "answered elsewhere while focus is outside its card" red (1 failed, the other ten green); reverted, `cmp`-identical.
- mutation (open card unchanged): `incident-card.ts` `closed` made always true (`... || true`) -> the open-card cases red (7 failed: F1, F2, F3, F4, F6 and the F6b Approve and Reject b1 cases, where the open card's request card no longer stays drawn); reverted, `cmp`-identical.

**Shared surfaces:** the page's live region and focus rule (the chat panel's focus tests, `announce-focus-sources.test.mjs`). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

Summary: a closed incident card now announces the answered status of a drawn undo request, once, through the page's existing polite announcer, when the request leaves because it was answered (by this page's press or from elsewhere), and moves focus to the incident's headline when focus was inside the request card that left (after the chat's focus rule has run). No new string, live region, focus mechanism or server change; an open card is unchanged.

Files changed:
- `web/src/app/incidents/incident-card.ts`: the `closed` computed, the `noteDrawn` effect (announce once, focus the headline), the doc comment.
- `web/src/app/shared/focus-rule.ts`: `MAIN_REGION` exported for reuse.
- `web/scripts/incident-sources.test.mjs`, `approval-sources.test.mjs`, `announce-focus-sources.test.mjs`: source pins updated for the new shape; the incident card moves to the announcing and focusing list.
- `web/e2e/rail/step5-cards.spec.ts`: F6b asserts the announcement (once, exact text) and the headline focus for Approve and Reject; new F6b (d) for an answer from elsewhere.
- this spec: Design Notes, Verification, Triage Log.

Review: patches applied 3 (one low, two medium); none deferred; the rest rejected with the recorded reasons. Follow-up review recommended: false (no high patched, fewer than two mediums patched beyond the added tests).

Verification: `npm --prefix web test` 2185 pass; lint and build exit 0; `LIVE_REBUILD_WEB=1 ci/iris.sh live sign-in-2 --part 12/20` 11 passed on tag `e24dw26`; four mutations observed red and reverted `cmp`-identical (see Verification). The throwaway stack was torn down by the runner; no container of the tag remains.

Residual risks: focus moves only when it was inside the leaving request card and after the chat's focus rule (a body-focused Safari press gets the announcement but no focus move, as with a lost Dismiss).
