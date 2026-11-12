---
title: 'Story 23.12: Take a rejected request off the status rail at once'
type: 'bugfix'
created: '2026-11-12'
status: 'done'
baseline_revision: '3a05e44f2f8f605b231851e168391e3a82956050'
baseline_commit: '3a05e44f2f8f605b231851e168391e3a82956050'
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

### Review Findings

Code review 2026-11-12 (first review; full mode; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 25 rows, 3 entries, all low and patched; no decision-needed, no defer). Rule 3: RA1, RA2, PA2 and PA3 are real-browser tests. Rule 6: no AC contradicts AD-12, AD-11, AD-4, AD-25, AD-32, AD-33 or AD-22 as written (ruling G2).

- [x] [Review][Patch] The 409 cases of the answer-press test did not check that `local` holds the request before `answered`, nor the expired reply's notice, though the QA line says they do [web/scripts/answer-press.test.mjs:76]: added `localThen` checks for `already_answered` and `expired`, and the expired reply's empty notice.
- [x] [Review][Patch] The "hands nothing over" test skipped the notice for 404 and no connection [web/scripts/answer-press.test.mjs:92]: they now expect `APPROVAL_TEXTS.gone` and `APPROVAL_TEXTS.busyNotice`, and every case checks its notice.
- [x] [Review][Patch] The header of `support/approvals.ts` said that "the answers specs" share `phoneOf` and `messageOf`, but `answers/close-loop.spec.ts` keeps its own copies [web/e2e/support/approvals.ts:13]: narrowed to `answers/answers.spec.ts` and `rail/rail-answer.spec.ts`.

Rejected:
- `false`: `answer-press.test.mjs` is untracked, so CI would lose it. QA's tests are left uncommitted by design, the lead commits them after the smoke gate, the file is not ignored, and `npm --prefix web test` runs it (1,938 tests).
- `low`: the Auto Run Result and the four-file loop command leave out QA's test. The fix edits the spec under review, and the Auto Run Result covers only the implement pass (Rule 14).
- `low`: the non-`HttpErrorResponse` error branch is not exercised. It calls the same `replied(call, 0, ...)` as status 0, whose notice is now pinned.
- `low`, by-design: the option name `answered` sits beside `BusyState.answered`. The spec names the option.
- `false`: a reply whose Ref differs from the pressed one. `Api.AnswerResponse` builds the view with `FromRow` of the row that the pressed Ref loads.
- `false`: a non-string `ref` or `state` in the reply. The payload is the server's `%JSON.Adaptor` view, read with the same cast as an event in `applyEvent`.
- `low`: `nextReply` is left unawaited when the press throws. The test already fails on the click's own error, and `answers.spec.ts` uses the same pattern.
- `low`, by-design (ruling G1): PA2 and PA3 also pass without the fix at the real poll rate. RA1 and RA2, with the polls held, pin "the reply alone". Closing the socket keeps PA2 and PA3 faithful to the online demo, where polling is the only live path. On a local install, X2 and X9 (socket open) and PA1 still cover the socket path, where `withAnswer` does nothing by design.
- `false`: PA3 waits with `phoneShows` and does not call `noticeOnPhone`. The persona flow sends the notice itself, and `noticeOnPhone` would send a second one (Design Notes 9).
- `low`, by-design: "phone view" is read as the simulated phone (Design Notes 1). The narrow layout renders the same rail component from the same store.
- `low`: no browser check covers the header Status count or Approve. The header reads `pendingApprovals`, which the rail-view test pins, and Design Notes 4 covers Approve.
- `false`: the words rule of `answer-press.ts`. The diff adds none of the words, and the source pin passes. The two baseline comment lines predate the story.
- `low`, by-design (G2, Rule 6 checked): AD-12 does not name the press reply as a source. It contradicts neither AD-12's Rule nor its Prevents: the reply is the same `FromRow` view (no drift), no cursor moves (no false gap), the state is the server's, and no extra poll runs (no double batch).
- `low`, by-design: a snapshot taken before the answer committed can bring `pending` back for one poll (Design Notes 6, wontfix-theoretical).
- `low`: the guards of `applyAnswer` are pinned by source text, and LiveState has no executed host. This review tried a Node host in `answer-press.test.mjs`, but Node's type stripping cannot load the `@Injectable` modules (SyntaxError). The source pin's mutation was observed red, and a reply after `stop()` changes nothing the user sees. reopen_if: a decorator-capable Node host lands in `web/scripts`.
- `low`: RA1's and RA2's "R1 does not come back" checks cannot fail through this change. They are dwell checks, and the live-store test carries criterion 4 with its mutation line. The fix would edit the spec's criterion.
- `low`: `floor/guide.spec.ts` has its own local `holdPolls`. It predates the story, it lives in a spec outside the story, and nothing collides at compile time.
- `low` (Rule 2, reviewer's own check): `rail-answer.spec.ts` defines its own `requestCard`, `rowOfRequest` and `nextReply` locators. Per-spec locators are the e2e tree's convention (`requestCard` is defined in five specs), and the shared helpers the spec named were moved, not copied.

## Spec Change Log

- 2026-11-12 (lead spec gate): added PA3 (phone Reject on a real request, gone within 5 s of the press), its AC and mutation; rulings G1-G3 under Design Notes.

## Review Triage Log

### 2026-11-12 — Review pass
- verdicts: 28 findings — high 0, medium 2, low 19, false 7, maybe-false 0
- findings:
  - `[low]` `[patch]` blind: PA2/PA3 header comment says only the reply can remove the row, but their polls run — the comment overclaimed (edge-case hunter's last two items and verification-gap's PA2/PA3 note are the same claim) — comment reworded: the socket is closed, the polls run, RA1/RA2 pin the reply alone.
  - `[false]` `[reject]` blind: PA3 depends on a phone message that may not exist — PA3 ran green on a fresh stack (row gone 85-99 ms after the press), so the persona flow does put the message on the phone.
  - `[false]` `[reject]` blind: the 5 s bounds disagree across specs — by design (ruling G1): fixture rows reply after about 5 s, so RA1/RA2 count from the reply; PA2/PA3 count from the press on a real hold.
  - `[medium]` `[patch]` blind and verification-gap: `applyAnswer` has no executed check for the stopped/no-store/unchanged-store guards (matrix "Page stopped") — added a source pin in approval-sources.test.mjs, the repo's style for LiveState (no test host runs it); mutation removing `this.stopped` observed red.
  - `[low]` `[reject]` blind: "no payload changes nothing" only documented — the `if (approval !== undefined)` pin exists and RA1 covers the 500 end to end; a runtime test of AnswerPress needs an Angular host the repo does not have for it.
  - `[low]` `[patch]` blind: late/expired replies not covered through the store, docs narrower than code — the withAnswer unit test now also covers `executing` and `expired` replies.
  - `[low]` `[reject]` blind: no e2e for Approve — decided in Design Notes 4 (same line, unit-covered, X2 stays as regression); adding a case is more than a direct correction.
  - `[false]` `[reject]` blind: wholesale replace may lose fields — the reply is the same FromRow view plus TraceLink that the events carry (spec Design Notes 2); no field the event view has is missing.
  - `[low]` `[reject]` blind: shared e2e helper footprint/noticeSlots placement — the spec orders the move; cosmetic.
  - `[low]` `[reject]` blind: holdMatching double release, waiting list not cleared — unchanged behaviour of the extracted holdState body; release is idempotent (the `released` flag).
  - `[low]` `[reject]` blind: fixed waits of 1.5 s — negative assertions need a dwell time; the spec names the 1.5 s.
  - `[false]` `[reject]` blind: heading string forms differ between rail-view.test and the spec — accessible name vs visible text, both exist in the rail today (rail.spec.ts uses the same name).
  - `[low]` `[reject]` edge: a poll or snapshot in flight at the press brings R1 back as pending — the accepted edge of Design Notes 6 (self-corrects at the next poll; wontfix-theoretical).
  - `[low]` `[reject]` edge: an older pending event steps the request back — events arrive in Seq order and the cursor does not move at the reply, so an older event is not delivered again; same accepted edge.
  - `[false]` `[reject]` edge: `answered` throws before `notify` — `applyAnswer` and `withAnswer` do not throw, and the host passes a one-line arrow.
  - `[low]` `[reject]` edge: host destroyed before the reply drops the reply — the same limit as `local` before this story; the poll still brings the answer.
  - `[low]` `[reject]` edge: `seqOf` reads a missing attribute as 0 — the attribute is always rendered on the loaded page (sibling specs rely on it); the loaded check precedes it.
  - `[low]` `[reject]` edge: held poll may flag Reconnecting during the reply — Design Notes 8 (hold of 5 to 8 s is under the 10 s threshold); no assertion reads it; RA1/RA2 passed.
  - `[false]` `[reject]` edge: PA3 does not call `noticeOnPhone` — the persona flow already sent the notice, so PA3 waits for the existing message (`phoneShows`); decided in implement (Design Notes 9).
  - `[low]` `[reject]` edge: PA3 gives a generic timeout instead of an intent-gap halt — PA3 passed, so the intent gap did not arise.
  - `[medium]` `[patch]` verification-gap: the "no reappearance" live-store test passed with a no-op `withAnswer`, and AC 4 had no mutation line — the test now asserts the reply's view and the unmoved cursors before the event; mutation line added; no-op mutation observed red in three tests.
  - `[low]` `[reject]` verification-gap: PA2/PA3 stay green with only `answered` removed — recorded in the mutation lines (they need the slower poll) and in Design Notes 3; RA1/RA2 guard the fix; the mutation lines already say so.
  - `[low]` `[reject]` verification-gap: host wiring pinned by source text only — the repo's style for Angular-bound hosts, and RA1/RA2 cover the behaviour in a browser.
  - `[low]` `[reject]` verification-gap: RA1's `readApproval` pending check is true without the fix — it pins "the server was not called", and the notice plus the still-listed row carry the failure case.
  - `[low]` `[reject]` verification-gap: a reply with no `ref` is untested — nothing observable depends on it.
  - `[false]` `[reject]` intent-alignment (descriptive): readings R1-R5 — the diff implements R1 with the simulated phone as the phone view (Design Notes 1); the header Status count reads the same `pendingApprovals` as the rail, which the rail-view test pins.
  - `[low]` `[reject]` intent-alignment: PA2/PA3 do not hold polls and do not assert the Status count — covered above; RA1/RA2 hold the polls.
  - `[low]` `[reject]` intent-alignment: Approve and the live socket path are not exercised in a browser — Design Notes 4 and 8; a local WebSocket push makes `withAnswer` a no-op by design.

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
9. **Decided in implement.** `rail-answer.spec.ts` and PA2/PA3 close the live socket (`blockLiveSocket`, `withProposal(..., pollsOnly)`) so the polls are the only live path, as on the online demo; on a local stack the WebSocket pushes the event with the reply and the pinning tests could not fail. `withAnswer` also returns the store for a reply with no `ref` (`ApprovalPayload.ref` is optional). PA3 reads the request Ref from the rail row's `data-row-key`, waits for the existing phone message with a new `phoneShows` helper in `support/approvals.ts` (which `noticeOnPhone` also uses), and asserts the card status as `/^Rejected from the simulated phone at \S+/`.

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
- mutation: web at the reply, the card passes `answered: () => undefined` (and the phone host the same, in one run) -> RA1 red at "R1 leaves the rail within 2 s of the reply" (R1 still listed with the polls held); applied, observed red, reverted.
- mutation: phone at the reply, the phone host passes `answered: () => undefined` (same run as the web one) -> RA2 red at the same assertion; applied, observed red, reverted.
- mutation: failed press, `press()` calls `this.options.answered({ ref, state: 'rejected' })` before the call -> RA1 red in its failure step (the 500 stand-in's notice does not show, because the card already shows the rejected view; RA2 stays green); applied, observed red, reverted.
- mutation: the unanswered request stays, `withAnswer` also drops every other pending request -> RA1 and RA2 red at "R2 stays listed", and the live-store "keeps the other pending request" test and the rail-view "keeps the other" test red; applied, observed red, reverted.
- mutation: no step back or reappearance, `withAnswer` without the `pending` guard -> the live-store "an executing request keeps its view" test red; applied, observed red, reverted.
- mutation: other session / unknown Ref, `withAnswer` also accepts a Ref the store does not hold -> the live-store "a Ref the store does not hold" test red; applied, observed red, reverted.
- mutation: real request within 5 s of the press, the card's `answered` removed AND `POLL_DELAY_MS` set to 8000 (PA2 and PA3 close the live socket with `blockLiveSocket`, so that a pushed event cannot remove the row; without it the mutation stayed green at about 100 ms, because the local stack pushes the event over the WebSocket) -> PA2 red at "the rail row is gone within 5 s of the press" (Expected 0, Received 1); applied, observed red, reverted.
- mutation: real request on the phone within 5 s of the press, the phone host's `answered` removed AND `POLL_DELAY_MS` set to 8000 (same run as the web one, same socket closure) -> PA3 red at the same assertion; applied, observed red, reverted. Unmutated, PA2 and PA3 pass with the row gone about 100 ms after the press.
- mutation: later approval event (AC 4, matrix "Later approval event"), `withAnswer` returns the store it was given -> the live-store "is followed by the request's own event" test red (it asserts the reply's view before any event), and the "replaces a pending request" test and the rail-view test red; applied, observed red, reverted.
- mutation: page stopped / no store (matrix "Page stopped"), `applyAnswer` without the `this.stopped` test -> the approval-sources "takes the reply into the live store only while the page runs" pin red; applied, observed red, reverted. (LiveState has no executing test host in `web/scripts`; the pin is the repo's style for it.)
- (QA) `web/scripts/answer-press.test.mjs` (new, run by `npm --prefix web test`): runs the real `AnswerPress` (real Angular signals, `HttpErrorResponse` and RxJS; a resolve hook gives the sources' relative imports their `.ts`) and pins the matrix rows that were only source-pinned: a 200 (Reject and Approve), a 409 `already_answered` and a 409 `expired` with a payload hand the request to `answered` once, after `local` holds it; a 403, 404, 400, 500, no connection, an empty 200 and a 409 without the request hand nothing over and leave the notice; and the hand-over through `withAnswer` takes the request off `pendingApprovals` while a failed press leaves it.
- (QA) mutation: reply with a payload, `replied` without `this.options.answered(approval)` -> answer-press.test.mjs red in three tests (200, late/expired, rail chain); applied, observed red, reverted.
- (QA) mutation: failed press (matrix "Failed press"), `answered` called outside the `if (approval !== undefined)` -> answer-press.test.mjs "hands nothing over for a reply with no payload" and the rail chain test red; applied, observed red, reverted.
- (QA) mutation: order, `answered` called before `this.local.set(approval)` -> answer-press.test.mjs "hands the request of a 200 over once, after local holds it" red; applied, observed red, reverted.
- (QA) mutation: host wiring, the card's and the phone's `answered` replaced by `() => undefined` -> the approval-sources "hands every reply" pin and the phone-request-sources "press through AnswerPress" pin red; applied, observed red, reverted.
- (QA) re-observed at the unit level (each applied, red, reverted): `withAnswer` a no-op (4 tests red: live-store, rail-view, answer-press), without the `pending` guard (live-store "has left pending"), accepting an unknown Ref (live-store "a Ref the store does not hold"), replacing the whole map (rail-view, live-store, answer-press), accepting a `pending` reply (live-store "still pending"), `applyAnswer` without `this.stopped` (approval-sources pin). The browser mutations (RA1, RA2, PA2, PA3) were observed by the implement stage and not re-run: no browser spec changed in QA.
- (review) mutation: failed press notice (matrix "Failed press"), `noticeOf`'s `gone` case returns `''` -> answer-press.test.mjs "hands nothing over for a reply with no payload ... and leaves the notice" red; applied, observed red, reverted (tree byte-identical).

## Auto Run Result

Status: done
Blocking condition: none

Summary: a press reply's request view now enters the live store at once, so a rejected (or approved) request leaves the status rail, its heading count and the Status count at the reply, with no poll. `withAnswer` (live-store.ts) replaces a request only while the store holds it as `pending` and moves no cursor; `LiveState.applyAnswer` applies it; `AnswerPress` hands every payload-carrying reply to a new required `answered` option; the chat card and the simulated phone pass it to `LiveState`. No public text, no server or route change.

Files changed (all under `web/**`):
- `web/src/app/live/live-store.ts`, `live-state.ts`: `withAnswer`, `applyAnswer`.
- `web/src/app/approvals/answer-press.ts`, `approval-request-card.ts`, `web/src/app/phone/phone-request.ts`: the `answered` option and the two hosts.
- `web/scripts/live-store.test.mjs`, `rail-view.test.mjs`, `approval-sources.test.mjs`, `phone-request-sources.test.mjs`: store, rail and source pins.
- `web/e2e/support/api.ts` (`holdPolls`, shared `holdMatching`), `support/approvals.ts` (moved helpers, `phoneShows`), `answers/answers.spec.ts` (imports only).
- `web/e2e/rail/rail-answer.spec.ts` (new): RA1 and RA2, with the polls held and the live socket closed.
- `web/e2e/persona-approval.spec.ts`: PA2 5 s bound and the new PA3 on the simulated phone (live socket closed).

Review: 4 layers, 28 rows in the Review Triage Log. Patches applied: 2 medium (the `applyAnswer` guard pin; the live-store "no reappearance" test strengthened with its mutation line), 2 low (PA2/PA3 comment; `executing` and `expired` replies in the unit test). Deferred: none. Rejected: the rest, each with its reason in the log. Follow-up review recommended: false.

Verification: `node --test` of the four unit files passes (loop); `npm --prefix web run lint` exits 0; `npm --prefix web test` passes, 1934 tests (once); `ci/iris.sh live sign-in-2 --part 8/12` (handoff run): RA1 and RA2 pass, reply 5.1-5.2 s after the press, row gone 8-9 ms after the reply; `ci/iris.sh live sign-in --part 17/24` (persona-approval.spec.ts): PA1-PA3 pass, row gone 85-105 ms after the press. Mutations observed red and reverted (tree byte-identical to the backups): see `## Verification`, including the compound PA2/PA3 mutation that needed the live socket closed to go red. Lane-D throwaway `e23s12i` torn down. Left to CI and the lead: `live:answers` (X2, X4, X8, X9), the whole `live:sign-in-2` and `live:sign-in`, `ci/checks.sh`.

Residual risks: PA2/PA3 count from the press on a real request and run their polls, so only RA1/RA2 pin that the reply alone removes the row; a snapshot or poll taken before the answer committed can bring the row back for one poll (Design Notes 6); Rule 20 candidate (AD-12 bullet) stays a design note (ruling G2).
