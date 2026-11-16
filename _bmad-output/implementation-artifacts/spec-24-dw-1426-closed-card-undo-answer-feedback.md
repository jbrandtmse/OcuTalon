---
title: 'DW-1426: a closed card announces its undo''s answer and moves focus to the headline'
type: 'feature'
created: '2026-11-16'
status: 'ready-for-dev'
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

## Design Notes

- Governing: UX-DR131 (focus when the focused item disappears), the page's announce rule (one polite announcer), AD-12 (the page renders catalog text), 24.4b's closed-card ruling.
- Ledger: DW-1426 is resolved by this commit (the lead appends `resolved-by` at merge).

## Verification

Lane D: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'`, fresh tag `e24dw26`. One call each, about 150 s.
- (loop) `npm --prefix web test` -- all pass.
- (once) `npm --prefix web run lint` and `npm --prefix web run build` -- exit 0.
- (once) `LIVE_REBUILD_WEB=1 ci/iris.sh live sign-in-2 --part 12/20` (step5-cards) on tag `e24dw26` -- passed.

**Shared surfaces:** the page's live region and focus rule (the chat panel's focus tests, `announce-focus-sources.test.mjs`). Standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
