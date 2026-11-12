---
title: 'Story 23.12: Take a rejected request off the status rail at once'
type: 'bugfix'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** DW-1159. After Reject, the rail's Approval requests keeps the rejected request listed until the next poll applies its `approval` event. The card and the phone show the answer at once from the press reply, but that reply goes only into `AnswerPress.local`. The rail list, its heading count and the header's Status count read only the live store (`pendingApprovals(store)`). The store's approvals change only through `approval` events. `Bridge.Approval.Answer` publishes the event before it returns, but the page reads it only on the next poll, 1 to 2 s later.

**Approach:** The press reply already carries the request's full public view, the same `Live.Payload.Approval.FromRow` view that `/state` and the events serve. That view now goes into the live store at once. A pure `withAnswer(store, approval)` in `live-store.ts` replaces a request only while the store still holds it as `pending`, and it moves no cursor. `LiveState.applyAnswer` applies it. `AnswerPress` hands every reply that carries a payload to its host, and both hosts (the chat card, channel web, and the simulated phone, channel phone) pass it to `LiveState`. The same line covers Approve.

## Boundaries & Constraints

**Always:**
- Only the server's payload from a 200, 409 `already_answered` or 409 `expired` reply goes into the store (`answerOutcomeOf`'s `approval`). It goes in only while the store holds that Ref as `pending` and the payload is not `pending`.
- No cursor moves. The request's own `approval` event still applies when it arrives, and it replaces the view by Ref, idempotently.
- A reply with no payload (403, 404, 400, 500, no connection, a timeout) changes nothing. The request stays listed with the existing notice.
- One code path for both channels: the change goes into `AnswerPress` and the two hosts that build it.
- `answer-press.ts` must not contain the words "session", "user" or "disabled" anywhere, comments included (`approval-sources.test.mjs` pins this).
- Comments state the contract only (Rule 14). Non-ASCII goes in as escapes.

**Never:**
- Remove or mark the request at the press, before the server answers (the page would decide, and a failed press would flicker the row back).
- Start an extra poll from the reply.
- Change the server or the bridge: no change to `Approval.Answer`, `TASKSECONDS`, the route or AD-11's path.
- Open the WebSocket on the online demo.
- Remove `AnswerPress.local`. The phone's buttons follow only the server's edit of the message and the phone's own press, and the card's announce rule reads `local`.
- Add or change user-visible text.
- Edit the demo-path specs or any other contended file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reject on the card (web) | store: R1 and R2 `pending`; 200 reply with R1 `rejected` | R1 leaves the rail list, the heading count and the Status count at the reply, before any poll; R2 stays listed (DW-1159) | none |
| Reject on the simulated phone (phone) | same, pressed on the phone's message | same as web (DW-1159) | none |
| Approve (same line) | 200 reply with `approved` (or `executing`) | leaves at the reply; later events (executing, done) apply as before | none |
| Later approval event | store already holds the reply's view | the event replaces it by Ref with the same or a newer view; no reappearance | none |
| Reply older than the store | store already `executing`/`done`/`rejected` (an event got there first) | store unchanged (same object); no step back | none |
| Late press, expired | 409 `already_answered` / `expired` with payload | store takes the winner's or the expired view; leaves the rail | existing late or expired notice |
| Failed press | 403/404/400/500/0, no payload | store unchanged; the request stays listed | existing notice ("OcuTalon could not answer. Nothing was changed." for the 500 stand-in) |
| Other session / unknown Ref | payload whose Ref the store doesn't hold | store unchanged; no row appears. Another session's page changes only through its own stream | none |
| Pending payload | reply payload still `pending` | store unchanged | none |
| Page stopped | `LiveState` halted, or no store yet | nothing applied | none |

</intent-contract>

## Code Map

Product (web, change):
- `web/src/app/live/live-store.ts` -- framework-free, pure (it runs under Node).
  - Header doc 1-15: add the `withAnswer` bullet.
  - `put` 158-164 is the helper to reuse.
  - `applyEvent`'s `approvals` case 188-189 is the event path, which stays unchanged.
  - `applyEvents` 228-247: cursors.
- `web/src/app/live/live-state.ts`.
  - Class doc 32-57.
  - `store` 94.
  - `applyPushed` 141-159 is the sibling pattern: read `store()`, return when `stopped` or no store, set only when the result is a new object.
- `web/src/app/approvals/answer-press.ts`.
  - `AnswerPressOptions` 13-24.
  - Class doc 26-38: "`local`: the view the host shows while the store's own payload is still pending".
  - `replied` 85-94: `this.local.set(approval)` only when `approval !== undefined`.
- `web/src/app/approvals/approval-request-card.ts`.
  - Doc 85-91.
  - Injections 480-485.
  - `new AnswerPress` 488-494.
  - `shown` 496-500 is the existing rule (local only while the stored request is pending).
  - `noteStore` 538-556: it announces an answer from elsewhere when the store goes pending to answered. It now also runs at a phone press's reply. It stays silent while focus is on the phone's answer line (`focusOnAnswer`).
- `web/src/app/phone/phone-request.ts`.
  - Doc 58-69.
  - Injections 222-227.
  - `new AnswerPress` 230-236.
  - `view` 238-240 reads `answer.local()`, not the store's state, for its buttons.

Consumers (read the store, no change):
- `rail/rail-view.ts`: `pendingApprovals` 339-345, `railView` 364-392, `personaReadKey` 351-356.
- `rail/status-rail.ts:276`.
- `header/header.ts:438`: the Status count.
- `chat/chat-panel.ts:164,327`.
- `phone/simulated-phone.ts:271,294`.

Server (read-only evidence):
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`.
  - `Answer` 322-348: `Fire` (BridgeSink, which publishes the `approval` event) runs after the unlock and before the return, so the event is committed before the reply.
  - `AnswerLocked` 375-389 saves the row, then `CompleteHoldTask`.
  - `CompleteHoldTask` 611-640 polls up to `TASKSECONDS` = 5 (line 63) for the hold's Workflow task. A fixture row has no hold, so its reply always takes about 5 s. A real request's task exists, so its reply is short (inference).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`: `AnswerApproval` 667-681, then `AnswerResponse` 700-735. The reply's `approval` is `Live.Payload.Approval.FromRow(row, sessionRef)` plus the TraceLink: the same view as `/state` and the events.
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls` `Approved` 144-162.

Tests:
- `web/scripts/live-store.test.mjs`: the snapshot helper 18-50, describes 107-301.
- `web/scripts/rail-view.test.mjs`: imports `pendingApprovals`, `railView`, `fromSnapshot` and `applyEvents` (16, 21).
- `web/scripts/approval-sources.test.mjs`.
  - 122-131: the BusyState pins.
  - 139-149: the call pins, including `doesNotMatch(press.code, /session|user/i)` and the card's `new AnswerPress({ answer: ..., channel: 'web',` regex.
  - 158-164: `noteStore`.
- `web/scripts/phone-request-sources.test.mjs:127-133`: the phone's `new AnswerPress({ answer: ..., channel: 'phone',` regex. The new option goes AFTER `channel` so both regexes still match.
- `web/e2e/answers/answers.spec.ts`.
  - `ANSWER` 32, `phoneOf`/`messageOf` 57-59, `noticeSlots` 76-90, `noticeOnPhone` 96-111, `nextReply` 124-127.
  - X5's 500 stand-in 470-480: `{error:{code:'failed', message:'OcuTalon could not answer. Nothing was changed.'}}`.
  - X2 244-309 and X9 663-711 assert that the rail row leaves within `ONE_UPDATE_MS` of the reply, and that the card does not announce an answer that took focus on the phone. Both must stay green.
- `web/e2e/support/approvals.ts`: `raise` 67-81, and the doc 6-11 ("what the answers unit's specs share").
- `web/e2e/support/api.ts`.
  - `POLLS` 63.
  - `holdState` 117-137: the waiting-list hold to generalise.
  - `holdPoll` 83: not usable here. It stops the page's clock, and the reply must render while the polls are held.
- `web/e2e/support/floor.ts`: `loadedAfter` 225, `railOf` 53, `CARD_MS` 41.
- `web/e2e/rail/rail.spec.ts`: the RAIL user, whose session R1-R19 expect empty (R1 counts 0); the `approvals(page, n)` heading locator 75.
- `web/e2e/persona-approval.spec.ts`: PA2 139-151 is a real `setting` request with a real hold, rejected on the web card; `TITLE` and the rail row locator come from PA1 126.
- `web/playwright.config.ts:52`: `SIGN_IN_2_DIRS` includes `rail`, so a new spec under `rail/` runs in the project `sign-in-2` with no config change.

## Tasks & Acceptance

**Execution:**
- `web/src/app/live/live-store.ts` -- add `export function withAnswer(store: LiveStore, approval: ApprovalPayload): LiveStore`. When `store.approvals` holds `approval.ref` with state `pending` and `approval.state` is set and is not `pending`, it returns `{ ...store, approvals: put(store.approvals, ref, approval) }`. Otherwise it returns `store` itself (same object). Cursors are untouched. Add a header bullet stating this contract. -- One pure place, which every reader of the store follows.
- `web/src/app/live/live-state.ts` -- add `applyAnswer(approval: ApprovalPayload): void`, shaped like `applyPushed`: no-op when stopped or with no store; `store.set` only when `withAnswer` returned a new object. Add one sentence to the class doc. -- The page's one store.
- `web/src/app/approvals/answer-press.ts` -- add the required option `answered: (approval: ApprovalPayload) => void`, documented as "gets the request as a done, late or expired reply shows it, for the page's live store". In `replied`, call `this.options.answered(approval)` right after `this.local.set(approval)`, inside the same `if`. Update the class doc's reply bullet. -- Both channels share one path. Keep the words "session", "user" and "disabled" out of this file.
- `web/src/app/approvals/approval-request-card.ts` and `web/src/app/phone/phone-request.ts` -- `private readonly live = inject(LiveState);` and, in `new AnswerPress({...})` right after the `channel` line: `answered: (approval) => this.live.applyAnswer(approval),`. One doc sentence each. -- The two hosts.
- `web/scripts/live-store.test.mjs` -- add a `describe('an answer\'s reply (withAnswer)')`. A pending request takes a `rejected` reply, and also an `approved` one. The other pending request is kept. Cursors are unchanged and the input is not mutated. Each of these returns the same object: a store that holds the request as `executing` (or `rejected`), a Ref the store doesn't hold, and a reply that is still `pending`. Then `applyEvents` with the request's `approval` event (the same view) leaves it answered, and a later `executing` event replaces it. -- These rows pin the matrix.
- `web/scripts/rail-view.test.mjs` -- `railView(withAnswer(store, rejected R1))`: the approvals section holds R2 alone, with heading "Approval requests (1)", and `pendingApprovals` has length 1. -- Pins the rail surface.
- `web/scripts/approval-sources.test.mjs` and `web/scripts/phone-request-sources.test.mjs` -- pin that `replied` calls `this.options.answered(approval)` inside `if (approval !== undefined)` right after `this.local.set(approval)`, and that each host passes `answered: (approval) => this.live.applyAnswer(approval)`. Existing pins stay. -- Source shape, as these files do for the press.
- `web/e2e/support/api.ts` -- extract `holdState`'s body into a private `holdMatching(page, url: string | RegExp, first?)`. `holdState` calls it with `**${STATE}`. A new `export function holdPolls(page)` calls it with `POLLS` and returns the same `{ release, held }`. -- Extends the sibling rather than copying it.
- `web/e2e/support/approvals.ts` -- move `noticeSlots` and `noticeOnPhone` (with the phone and message locators they use) here from `answers.spec.ts`, exported unchanged, and update the doc. `answers.spec.ts` imports them, with no other change. -- Shared by both units' specs, not copied.
- `web/e2e/rail/rail-answer.spec.ts` (new, project `sign-in-2`) -- two cases as the RAIL user (`fixtureUser('RAIL')`, signed in through `loadedAfter`). Each first asserts that the simulated phone shows. Each `raise`s R1 and R2 in one incident, asserts both rows and "Approval requests, 2", and removes its rows (`cleanFixtureRows`) and phone messages (`dropPhone`) in `finally`. In both cases, the moment the row is gone, assert that `data-session-seq` still equals its value from before the press, so that no poll has answered. Log `RAIL RA<n> <channel>: reply <a> ms after the press, row gone <b> ms after the reply`.
  - **RA1 (web):**
    1. Route the answer call to the X5 500 stand-in and press Reject on R1's card. The notice shows, R1 is still listed after 1.5 s, and the row is still `pending` (`readApproval`).
    2. Unroute. `holdPolls`, arm `nextReply`, press Reject on the card, and await the 200.
    3. The R1 row is gone within 2000 ms of the reply (PAGE_MS). R2 stays listed, with "Approval requests, 1".
    4. Release the polls. Wait until `data-session-seq` is above its value from before the press. R1 is still absent then, and again 1.5 s later.
  - **RA2 (phone):** `noticeOnPhone` for R1, then the same sequence as RA1's steps 2 to 4, pressing Reject on the phone's message. -- These pin DW-1159 in the browser, with the poll path held so that only the reply can remove the row.
- `web/e2e/persona-approval.spec.ts` -- in PA2, before the Reject click, assert that the rail row `railOf(page).locator('li.row').filter({ hasText: TITLE })` has count 1. Take the time and click. Then assert that the row has count 0 with `{ timeout: 5000 }`, and log the ms from the click. -- The Planner's "within 5 s of the press" on a real request (a real hold, so no fixture wait).
- `web/e2e/persona-approval.spec.ts` -- [Lead spec gate, ruling G1] add a phone case PA3 beside PA2: the same real persona `setting` request with its hold, Rejected on the simulated phone's message (use `noticeOnPhone` from `support/approvals.ts`), with the rail row's count 1 before the press and 0 within `{ timeout: 5000 }` of the press, logging the ms; it cleans up its row and phone messages like PA2. If the persona flow cannot put the request on the simulated phone, HALT with an intent gap naming why (do not drop the case). -- The Planner's "within 5 s, on the web and on the phone view" on a real request.

**Acceptance Criteria:**
- Given R1 and R2 pending on the rail and the page's polls held, when the user presses Reject on R1's chat card, then R1 leaves the rail list and the heading count within 2 s of the 200 reply, with no poll applied, and R2 stays listed (DW-1159, RA1).
- Given the same, when the user presses Reject on R1's simulated phone message, then the same holds (DW-1159, RA2).
- Given a press whose reply fails (the 500 stand-in), when it is answered, then R1 stays listed and the existing notice shows (RA1).
- Given the rail already dropped R1 at the reply, when the polls resume and the page applies R1's `approval` event, then R1 does not reappear (RA1, RA2, live-store test).
- Given a real request (a persona `setting` request with its hold) on the rail, when the user presses Reject on the web card, then its row is gone within 5 s of the press (PA2).
- Given the same real request, when the user presses Reject on its simulated phone message, then its rail row is gone within 5 s of the press (PA3; Contest Planner acceptance, DW-1159).
- Given any of the matrix's store states, when `withAnswer` runs, then it gives the matrix's result, and the rail view counts accordingly (live-store and rail-view tests).
- Integration (Rule 1): given the status rail (`status-rail.ts` via `railView` and `pendingApprovals`) reading the live store, when a press reply reaches `LiveState.applyAnswer` while the polls are held, then the rail's row leaves, an effect that the reply alone produces (RA1, RA2).

## Spec Change Log

- 2026-11-12 (lead spec gate): added PA3 (phone Reject on a real request, gone within 5 s of the press), its AC and mutation; rulings G1-G3 under Design Notes.

## Review Triage Log

## Design Notes

**Root cause.** The rail, its count and the Status count read `pendingApprovals(store)`. Only an `approval` event changes a request in the store. The event is committed before the reply leaves the server (`Approval.Answer`: `Fire` before `Quit`), but the page reads it only on its next poll (`POLL_DELAY_MS` 1000 after the previous answer, plus the round trip). So the request outlives the reply by up to about 1 to 2 s. That is the "briefly" in the 1.0.7 pass. No Task 0 was needed: the code shows it.

**Decided in-stage:**
1. **"Phone view" is the simulated phone** (channel `phone`). The UX has no phone-width view. Under 1024 px it has the "Narrow window" stacked layout (EXPERIENCE.md 507-509), which renders the same rail component from the same store. The guide's own text says "press Reject in the chat or on the Simulated phone" (`more-to-try.spec.ts:105`). The stacked layout gets no separate test.
2. **The reply may update the store (AD-12).** AD-12 builds the store from `/state` plus events and says nothing about a press reply. The reply's `approval` is the same full public view by Ref (`FromRow` plus TraceLink) that a snapshot or an event carries. It enters the store only while the store still holds the request as `pending`. AD-11's one path never returns to `pending`, so it never steps the view back. It moves no cursor, so the event still applies idempotently. Nothing is published, so AD-33's single publisher holds. The page decides nothing: the state is the server's.
   - **Rule 20 candidate for the lead.** This constrains the store's contract. If the lead judges it architectural, the proposed AD-12 Rule bullet is: "A press reply's `approval` payload (200, or 409 with a payload) enters the store at once, replacing the request by Ref only while the store holds it as `pending`; it moves no cursor."
3. **The 5 s bound.** Press-to-gone is the server's reply time plus the page's part after the reply. This story makes the page's part a render (well under NFR-9's 2 s), never a poll. The server's part on a fixture row is about 5 s by construction (`CompleteHoldTask` waits `TASKSECONDS` for the task of a hold that a fixture row doesn't have). So no fix, of any kind, can show "5 s from the press" on fixture rows, and the answers unit counts its NFR-9 bounds from the reply for that reason. Therefore:
   - RA1 and RA2 pin the fix from the reply, with the polls held.
   - PA2 asserts 5 s from the press on a real request.
   - On the phone, a real request's press goes through the same `AnswerPress`, the same route and the same `Answer` as the web press, so its server time is PA2's (inference).
   - On a real request the bound held before this story too (a short reply plus one poll), which is why the pinning tests hold the polls.
4. **Approve is covered by the same line.** `withAnswer` takes whatever non-pending view the reply carries. The unit tests cover `approved`. X2 (Approve on the phone, row leaves after the reply) stays green and gets faster. No new Approve browser case.
5. **Alternatives rejected.**
   - Removing the row at the press: the page would decide, and the failed press would flicker it back (violates AD-12 and the failure row).
   - An immediate poll from the reply: it still waits a round trip after the reply, and it races the one-at-a-time poll loop (AD-12 prevents a double batch).
   - A rail-only overlay: the rail, the header count and the persona key would each need it, while the store reaches all of them.
6. **Accepted edge (not guarded).** If a skipped Seq or an epoch change makes the page reload `/state` in the instant around a press, and the server computed that snapshot before the answer committed, the snapshot can bring `pending` back until the next poll (at most one update). It corrects itself, because that poll carries the answered event. This is the `wontfix-theoretical` class.
7. **Home of the browser test.** `rail/` in the `sign-in-2` unit (`live:sign-in-2`, CI group `shards-4`), not `answers/`. The answers unit (about 335 s locally, Story 11.9) has no `--part`, so it can't run inside the 150 s foreground cap. `sign-in-2` takes `--part k/n`. `answers.spec.ts` X2 and X9 stay as regression checks.
8. **Holding polls.** A route that holds `/events?` requests until release (`holdPolls`, the generalised `holdState`). Expected hold: about 5 to 8 s, under the 10 s Reconnecting threshold. A slower host may show Reconnecting during the hold, which no assertion reads.

**Lead spec-gate rulings (2026-11-12, runner D, policy 5086036):**
- G1 (decide): the Contest Planner's acceptance for DW-1159 reads "a browser test presses Reject and the request is gone from the rail within 5 s, on the web and on the phone view". RA1/RA2 pin the fix from the reply with the polls held (fixture rows reply after about 5 s, so "from the press" cannot discriminate there); PA2 (web) and the added PA3 (simulated phone) assert the Planner's bound from the press on a real request. Together they meet the acceptance literally on both channels.
- G2 (decide): no AD-12 amendment. AD-12 is cited by done stories' specs, so any amendment would be a re-architecture under the doctrine's U7(c); the plan is consistent with AD-12 as written (the store holds only server views by Ref, idempotently; no cursor moves) and with AD-11 and AD-33, and where the spine is silent the simplest consistent option is chosen (product default 4). The Rule 20 candidate stays here as a design note only.
- G3 (decide): `live:answers` (X2, X4, X8, X9) is run by the lead on a fresh lane-D throwaway in the fresh-environment check, not left to CI alone.

**Second session.** The reply returns only to the page that pressed, with that page's session's view (`FromRow(row, sessionRef)`), and `withAnswer` ignores a Ref the store doesn't hold. Another session's page (on a local install, an instance request seen by several sessions) changes only through its own stream, as before (AD-4, NFR-9). On the online demo, only the owning session sees the request.

**Online demo.** Reject on the demo works as on a local install. The rail drops the request when the reply reaches the page, and the demo's polling (its only live path, owner-fixed value 3) then brings the same view. No WebSocket is involved. On a local install with the WebSocket, an event that arrives first makes `withAnswer` a no-op.

**Time cost (inference until a run measures it).** `rail-answer.spec.ts`: two cases of about 20 s each locally (about 5 s of each is the fixture's reply), so about 100 to 150 s on CI in `shards-4`. That group is planned at 1,644 s of units (Story 0.20's plan in `ci/units.sh`), so it ends up about 1,800 s (30 min), under the 32 min group limit. PA2 adds no time. No new unit, no `new_units:` entry.

**Architecture decisions:**
- AD-12: live store, polling, idempotent events.
- AD-11: the row is the truth, and states never return to `pending`.
- AD-4: ownership; the reply carries the session's own view.
- AD-25: the online demo, polling only.
- AD-32: no new text.
- AD-33: one publisher per event type (nothing is published here).
- AD-22: tests.
- AD-29: footprint; web is outside Epic 23's graph, reported by the lead as a footprint extension.
- No AC contradicts an AD Rule. No NFR is touched (NFR-9's 2 s from the reply is met with margin).

**Integration ACs (Rule 1):**
- Consumed-by: the status rail, the header's Status count, the Persona card's read key, the chat card and the phone (all existing readers of the store).
- Consumes: `AnswerPress` (Stories 6.2/6.3), `LiveState`/`live-store` (AD-12), and the `POST /approvals/:ref/answer` reply (Story 6.2).
- No new service.

**Extend, don't copy (Rule 2):**
- `withAnswer` reuses `put` and lifts the card's `shown` rule (local only while the store is pending) to the store.
- `applyAnswer` follows `applyPushed`.
- `holdPolls` and `holdState` share one private helper.
- `noticeSlots` and `noticeOnPhone` move to `support/approvals.ts` rather than being copied.

**PUBLIC TEXT for the Planner:** none. No string is added or changed. No `/api/v1` route changes, so the real-HTTP route rule doesn't apply.

**Files touched:**
- `web/src/app/live/live-store.ts`, `web/src/app/live/live-state.ts`
- `web/src/app/approvals/answer-press.ts`, `web/src/app/approvals/approval-request-card.ts`, `web/src/app/phone/phone-request.ts`
- `web/scripts/live-store.test.mjs`, `web/scripts/rail-view.test.mjs`, `web/scripts/approval-sources.test.mjs`, `web/scripts/phone-request-sources.test.mjs`
- `web/e2e/support/api.ts`, `web/e2e/support/approvals.ts`, `web/e2e/answers/answers.spec.ts` (imports only), `web/e2e/rail/rail-answer.spec.ts` (new), `web/e2e/persona-approval.spec.ts`

All are under `web/**`, the footprint extension the lead reports.

**Ledger inbox (Rule 17):** DW-1159 is addressed by the first two ACs, RA1 and RA2, and the matrix rows marked DW-1159.

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`. Each call should finish in about 150 s, and never put two test runs in one message.

Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`. The fresh tag is `e23s12i`. The story changes no class, so it needs no warm stack: `e23s12iw` is reserved and unused. At the end, also after a failure, run `ci/iris.sh teardown` with `e23s12i`.

**Shared surfaces:**
- the RAIL user's Approval requests list and count. R1-R19 of `rail.spec.ts` expect the session empty, so RA1 and RA2 remove their rows and phone messages in `finally`;
- the `sign-in-2` project's spec list and its `--part` cut (`playwright-projects.test.mjs`, `e2e-part.test.mjs`);
- `holdState`'s callers (unchanged signature);
- `answers.spec.ts`'s moved helpers;
- the store contract (`live-store.test.mjs`);
- the press's source pins.

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `node --test web/scripts/live-store.test.mjs web/scripts/rail-view.test.mjs web/scripts/approval-sources.test.mjs web/scripts/phone-request-sources.test.mjs` -- expected: all pass (under 1 s today).
- (loop) `npm --prefix web run lint` -- expected: exit 0 (tsc of the e2e tree and `node --check` of the scripts).
- (loop) After every change under `web/src`, and before any browser run: `<lane> OCUTALON_RUN_TAG=e23s12i ci/iris.sh build`. A local `live` run serves the bundle and never rebuilds it.
- (loop) `<lane> OCUTALON_RUN_TAG=e23s12i ci/iris.sh live sign-in-2 --part k/n`, with the part that holds `rail/rail-answer.spec.ts`. Pick n so that the part fits about 150 s; its first line prints `PART k/n` and its files, and the setup is about 93 s. -- expected: RA1 and RA2 pass, and the `RAIL RA<n>` lines show the reply-to-gone ms.
- (once) `npm --prefix web test` -- expected: every test passes (1,925 tests, 14 s measured at planning).
- (once) `<lane> OCUTALON_RUN_TAG=e23s12i ci/iris.sh live sign-in --part k/n`, with the part that holds `persona-approval.spec.ts`. Add `OCUTALON_LIVE_DEADLINE=1500` if the part nears the default deadline, as Story 23.5 did. -- expected: PA1 and PA2 pass, and the logged press-to-gone ms is under 5000.
- Left to CI: `ci/checks.sh`, the whole `live:sign-in-2` (shards-4), `live:sign-in` (shards-10), and `live:answers` (shards-7). The last one runs X2, X4, X8 and X9, the card-announcement regressions that this change times differently: the store now moves at a phone press's reply. The lead's fresh-environment check runs forward and `--reverse`.

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:**
- Web at the reply: the card passes `answered: () => undefined` → RA1 red (R1 still listed with the polls held).
- Phone at the reply: the phone host passes `answered: () => undefined` → RA2 red.
- Failed press: `press()` calls `this.options.answered({ ref, state: 'rejected' })` before the call → RA1's failure step red (R1 gone after the 500).
- The unanswered request stays: `withAnswer` also drops every other pending request → RA1/RA2 R2 assertion red, and the live-store "the other pending request is kept" test red.
- No step back or reappearance: `withAnswer` without the `pending` guard → the live-store "an executing request keeps its view" test red.
- Other session / unknown Ref: `withAnswer` adds a Ref the store doesn't hold → the live-store "a Ref the store doesn't hold" test red.
- Real request within 5 s of the press: the card's `answered` removed AND `POLL_DELAY_MS` set to 8000 → PA2 red. This is the smallest change that breaks the bound on a real request: without the fix, the poll alone still meets 5 s.
- Real request on the phone within 5 s of the press: the phone host's `answered` removed AND `POLL_DELAY_MS` set to 8000 → PA3 red.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only (halt after planning). The root cause comes from the code: the rail reads only the live store, and the press reply skipped it. The fix is that the reply's payload enters the store while the request is still pending, through one `AnswerPress` option and two hosts, which covers Approve too. The pinning browser tests hold the polls: `rail/rail-answer.spec.ts` (sign-in-2, shards-4). PA2 asserts 5 s from the press on a real request. No public text, no route change, footprint `web/**` only. Rule 20 candidate (AD-12 bullet) for the lead under Design Notes.
