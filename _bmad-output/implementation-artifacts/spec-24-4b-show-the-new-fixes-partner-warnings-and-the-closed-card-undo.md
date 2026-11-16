---
title: 'Story 24.4b: Show the new fixes, partner warnings and the closed-card undo on the cards'
type: 'feature'
created: '2026-11-15'
status: 'done'
baseline_revision: '6be7720280a3a1993cb06fd532b0c332eff26afa'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      A closed card drops the undo's card the moment its answer lands (and an approved, failed, rejected or expired undo shows nothing on it), so the answer gives no status, no audit line and no focus target on the closed card.
    evidence: |-
      The binding ruling says nothing is drawn once the undo is answered or expired. The page drops the card's in-flight call with the card, and F6b proves the answer only from the reply, the stored row and the trace header. A decision for the Contest Planner: keep the card while the answer is in flight, or show the status among the compact bands.
    location: >-
      web/src/app/incidents/incident-card.ts requests; web/src/app/incidents/incident-view.ts drawnOnClosed
    severity: medium
  - summary: >-
      Pin (c) reads the closed state once after the card leaves, with no settle step.
    evidence: |-
      A product path that reopens the incident asynchronously after the trace header would pass. IncidentManager refuses every event on a closed incident, so none is shown. What would settle it: a bounded poll of the incident's state after the undo reaches a terminal state.
    location: >-
      web/e2e/rail/step5-cards.spec.ts expectStillClosed
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Lane A's Stories 23.2, 23.3 and 23.5 are merged, and 24.4a made every setting value the cards show redacted on the server. Two things are still missing:
- A closed (compact) incident card draws no request card at all. An undo of a rollback, the one kind that may be asked for on a closed incident (`Fix.Kind.AskedClosed`), therefore has no card, and the rail's "Show in the chat" for it lands on the chat list (Contest Planner ruling V2).
- Nothing pins the step-5 kinds across surfaces: the suspend, resume, reroute, rollback, undo and partner-warning cards, rail rows, phone messages and Telegram texts, and their answered states. The existing pins (A12 to A14, 24.4a's F3b, F5, F5b and F7) check HTTP, two bands and the redaction only.

**Approach:**
- A compact card draws the request cards of the kinds that may be asked after the close (`undo_rollback` only) and no other. Their bands show on their own cards, never a second time among the compact card's bands.
- Pin every AC on its outermost surface: Playwright cases F1 to F4, F6 and F6b in `web/e2e/rail/step5-requests.spec.ts` (the card, the rail, the phone page), one Telegram method on the CI mock, and unit pins for the view rules.
- No server change. No payload field, route, catalog key, string, table or message property changes.

## Boundaries & Constraints

**Always:**
- The page decides nothing (AD-12). The kind rule reads only the approval payload's `fixKind` and mirrors the server's `Fix.Kind.AskedClosed` answer. Compactness comes from the payload's state, never from the drawn view.
- The phone and Telegram text is the server's catalog text (AD-32). Values on every surface are the server's (already redacted, 24.4a); the page redacts nothing.
- Tests seed fixture rows (`seedIncident`, `seedApproval`, `publishIncident`, `sendNotification`) and remove them, and the phone messages they made, in `finally`. They run on lane-D throwaways only.
- Code uses ASCII escapes for any non-ASCII character (Rule 14).

**Never:**
- No edit of a Lane A or bridge file. `Channel/Telegram/Out.cls`, `Watch/*`, `Fix/*` and `Msg/Catalog/*` stay unedited. The `BUTTONKINDS` mutation is applied and reverted byte-identical and never lands (V3).
- No new `/api/v1` route, live-event type, payload field, catalog key, fixed string, table, column, message property or dependency. `payloads.mjs --check` stays green with no interface change.
- No change to the incident's state or lifecycle. No other request kind on a closed card: a repair, suspend, resume, reroute, rollback or partner request stays undrawn there (A9 stays as it is).
- No second redactor. No edit of `Bridge/Redact.cls` (DW-1412 is being done separately).
- No edit of `irislib/`, `irissys/`, `_bmad/`, `.claude/`, `CLAUDE.md` or a done story's spec.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Closed card, undo pending | incident `closed`; the store holds a pending `undo_rollback` approval of it | the compact card draws that request card (dry run, "Nothing has changed yet.", Approve, Reject, expiry, Show details at its row's end); the incident-level actions row is gone | No error expected |
| Closed card, other kinds | incident `closed`; pending `suspend_item`, `rollback_setting`, `partner_warning` or repair approvals of it | no request card for any of them; the incident-level Show details row stays (A9) | Unchanged |
| Closed card, undo answered | the undo was rejected, expired or is done with a result | its card stays with its status, and its band when it has one; that band is NOT also among the compact card's bands | Band drawn once |
| Closed card, mixed | a done rollback with a result and a pending undo | the rollback's band stays among the compact bands; the undo has its card | No error expected |
| Open card | any state but `closed` | every request card, as today | Unchanged |
| Unknown or absent `fixKind` | an approval with no `fixKind` on a closed incident | not drawn | Not drawn |

</intent-contract>

## Code Map

All web paths are under `web/`. IRIS paths are under `src/ocutalon/cls/OcuTalon/`. Re-checked against HEAD f5bd8256 (24.4a merged).

**To change: the page**
- `src/app/incidents/incident-view.ts` -- module doc 1-33 (the compact card's bullets at 11-13 and 27-30); `IncidentContext` 97-114 (add `drawn`); `IncidentView.compact` 167-168 and `results` 181-182 (docs); `stateOf` 208 (exported; the card's compactness source); `bandsOf` 488-498 (carries each band's `ref`); `incidentView` 509-543, `results` at 540. `bandTexts` 500-506 stays unfiltered (the chat's announcements, `chat/chat-panel.ts:449`).
- `src/app/incidents/incident-card.ts` -- imports 3-16; component doc 40-57 ("a closed card keeps the chip row, the headline, the result band ..."); compact bands 111-113; request cards 114-128; incident-level actions and panel only without a request card 129-156; `view` 307-309; `requests` 311-312 (today `this.view().compact ? [] : requestsOf(...)`).

**Read only (evidence)**
- Approval view `src/app/approvals/approval-view.ts`: `APPROVAL_TEXTS` 51 (`approveName`/`rejectName` 56-57, `nothingYet` 70); `requestsOf` 213-227 (drops `cancelled`, sorts by `raisedAt`); `itemDryRunView` 260-275; `settingDryRunView` 278-293; `rerouteDryRunView` 296-310; `dryRunView` 313-344; `partnerView` 359-376; `statusOf` 400-420; `approvalView` 423-455 (names 449-450); `resultView` 575.
- `src/app/approvals/approval-request-card.ts`: `section[data-part="approval"][data-key]` 116; partner block 132-141; dry rows 146-175 (`.mono.before` 154, `.mono.after` 160, `.dry-note` 173); Approve and Reject 179-208 (`aria-label` 183, 197); status 209-219; Show details at the row's end 220-238 (so Tab order is Approve, Reject, Show details); band 241-243; expiry 244-246.
- Rail: `src/app/rail/rail-view.ts` titles 47-52 (`undoRollback` 52), `showInChat` 57, `approvalTitle` 211-243, jump 270-274; `status-rail.ts` `requestCard` selector 39, `jump` 297-301 (the card when drawn, else the chat list).
- Phone: `src/app/phone/phone-view.ts` `requestView` 158-186 (names from the same `approvalView`, 183-184).
- Server rule mirrored: `Fix/Kind.cls` `AskedClosed` 156-162; `Fix/Kind/UndoRollback.cls` `MOVES` 26, `ASKEDSTATES` 28 (the only kind with `closed`; `Fix/Kind.cls:55` default, `PartnerWarning.cls:35`).
- Catalog keys (`Msg/Catalog/Watch.cls`): `incident.suspendRequest` 818, `resumeRequest` 827, `rerouteRequest` 836, `partnerRequest` 960, `rollbackRequest` 1129, `undoRollbackRequest` 1144; `Msg/Catalog/Core.cls` `answered.approved` 87, `answered.rejected` 106, `answered.expired` 123, `audit.recorded` 619. Their fixtures: `Test/Msg/Catalog.cls` 1862-1899.
- `Watch/Notice.cls` `AskedKey` 224, `AskedSlots` 231-286 (the real fill of the five asked kinds; a partner's recipients joined as "Name <address>, ...").
- `Channel/Telegram/Out.cls` `BUTTONKINDS` 115 (used at 227): mutation target only.

**Tests to extend or add**
- `scripts/incident-view.test.mjs` -- `context` helper 26-39; compact case 249-261; result bands 721-806.
- `scripts/incident-sources.test.mjs` -- the compact bands pin 199-203 (`cardTemplate`, `card`).
- `scripts/approval-sources.test.mjs` -- the `requests` regex at 316 (inside 308-320).
- `e2e/rail/step5-requests.spec.ts` (24.4a; 209 lines) -- header 11-18; `KIND` 22; `incidentCard`/`requestCard` 39-40; `open`/`openLive` 43-57; `textOf` 60. Its F3b, F5, F5b and F7 stay as they are.
- Models: `e2e/rail/rail-answer.spec.ts` (`nextReply` 50-52, RA2 148-163: a phone Reject); `e2e/answers/close-loop.spec.ts` `request` 144-157 (seeding answered and expired states), C9 590-616; `e2e/answers/answers.spec.ts` X6 jump 522-534 (`toBeFocused`); `e2e/cards/approval-card.spec.ts` A9 707-724, A13 518+ (partner dry run with `recipients` objects).
- Support: `e2e/support/approvals.ts` (`today` 21, `refOf` 27, `incidentOf` 40-62, `raise` 70-84, `phoneOf`/`messageOf` 87-88, `phoneShows` 121-129); `e2e/support/iris.ts` (`irisScript` 108, `chk` 126, `publishIncident` 182, `quoted` 204, `sinkEvent` 497, `sendNotification` 684, `askedSlots` 707-720, `cleanFixtureRows` 722, `seedApproval` 794, `seedIncident` 1078); `e2e/support/scan.ts` `scanNames` 49, `scanContrast` 149; `e2e/support/floor.ts` `railOf`, `applied`, `CARD_MS`.
- `Test/Channel/TelegramOut.cls` -- `Request` 810, `TestRedactedValue` 823-866 (24.4a, chat 8650), `TestButtons` 868-954 (the model); chat ids in use 8620-8650; `Test/Channel/LiveCase.cls` `FixtureSlots` 665.

## Tasks & Acceptance

**Execution (in dependency order):**
- `web/src/app/incidents/incident-view.ts` -- Export `AFTER_CLOSE_KINDS` (a `ReadonlySet<string>` holding `undo_rollback`; its doc names `Fix.Kind.AskedClosed` and says a later kind with `closed` in `ASKEDSTATES` is added here) and `drawnOnClosed(approval)` (true only when `fixKind` is in the set). `IncidentContext` gains optional `drawn?: ReadonlySet<string>` (the request Refs the card draws as request cards). In `incidentView`, a compact card's `results` leave out the bands whose ref is in `ctx.drawn`; `bandTexts` stays unfiltered. Update the module doc and the `compact`/`results` docs. -- Imports stay type-only (Node runs the module as it is).
- `web/src/app/incidents/incident-card.ts` -- `requests` becomes: on a closed incident, `requestsOf(...)` filtered by `drawnOnClosed`; otherwise `requestsOf(...)`. Closedness comes from the payload (`stateOf(this.incident().state)?.chip === 'closed'`), not from `view().compact`, which would be circular because `drawn` feeds the view. `view` passes `drawn` (the Refs of `requests()`) in the context. Update the component doc and the `requests` doc. -- Extends the existing computed; no new component.
- `web/scripts/incident-view.test.mjs` -- Pin each matrix row of the view: `drawnOnClosed` is true for `undo_rollback` only (false for '', `repair`, `suspend_item`, `resume_item`, `reroute`, `rollback_setting`, `partner_warning`, `email`, absent); a compact card with `drawn` holding the undo's ref keeps the other requests' bands and drops only the undo's; without `drawn` every band stays (today's cases unchanged); `drawn` has no effect on a non-compact card; `bandTexts` keeps every band.
- `web/scripts/incident-sources.test.mjs` -- Pin that the card computes its closedness from the payload with `stateOf`, filters by `drawnOnClosed` only then, and passes the drawn Refs into the context.
- `web/scripts/approval-sources.test.mjs` -- Change the `requests` regex at 316 to the new expression.
- `web/e2e/support/iris.ts` -- Add `fixtureSlots(key)`: an `irisScript` that returns `##class(OcuTalon.Test.Channel.LiveCase).FixtureSlots(key).%ToJSON()` (the catalog fixture's slots), for the rollback's phone notice, which has no asked fill. Extend, don't copy: it reuses `irisScript`, `quoted` and `chk`.
- `web/e2e/rail/step5-requests.spec.ts` -- Add F1, F2, F3, F4, F6 and F6b (see the Playwright cases below), each cleaning its rows and phone messages in `finally`. Update the header doc. If one `--part` cannot hold the file in about 150 s, split the new cases into `web/e2e/rail/step5-cards.spec.ts` (it joins sign-in-2 by its folder).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls` -- Add `TestStepFiveRequests` on chat 8660: for each of `incident.suspendRequest`, `resumeRequest`, `rerouteRequest`, `partnerRequest`, `rollbackRequest`, `undoRollbackRequest`, send kind `approval` with `FixtureSlots(key)` (the partner's `recipients` slot replaced by two "Name <address>" entries joined by ", ", as `AskedSlots` joins them) and its own Ref. Assert each text equals `Catalog.Render(key, slots, "telegram")`, no `parse_mode` is sent, and the message's last part carries exactly Approve `approve:<ref>` and Reject `reject:<ref>`. Assert the partner text holds the whole notice and both recipients. Update the class doc.

**Acceptance Criteria:**
- AC1 (FR-26, FR-8; UX-DR75, 77, 83, 113; Integration): Given a pending request of each kind (`suspend_item`, `resume_item`, `reroute`, `rollback_setting`, `undo_rollback`), when it shows, then:
  - the card shows that kind's own dry run with text-labelled Before and After rows in mono: suspend "{item}: enabled" then "{item}: disabled" (swapped for resume); reroute its count line and "Message {example}: {from}" then "Message {example}: {to}"; rollback and undo "{setting}: {value}";
  - "Nothing has changed yet." shows;
  - Approve and Reject are named "Approve: {title}" and "Reject: {title}", with the rail row's title lower-cased at its first letter;
  - the rail row has that title;
  - the phone message of its catalog notice holds the notice's text and two buttons with the same names;
  - Telegram, on the CI mock, gets the catalog's telegram text with inline Approve and Reject on its last part and no parse mode.
  - Pins: F1, F2, F3 and `TestStepFiveRequests`.
- AC2 (FR-29; UX-DR136, 146): Given a pending `partner_warning` request with two recipients, when it shows, then the card's partner block shows "To: " with both "Name <address>" entries and the whole notice before the answer row (DOM order), and the phone message and the Telegram text hold the whole notice and both recipients as plain text. Pins: F4 and `TestStepFiveRequests`.
- AC3 (FR-8, FR-26, NFR-9; UX-DR74, 76, 79): Given requests of the new kinds that are answered, expire, run or are offered for undo, when each happens, then:
  - each card shows "Approved from {channel} at {time}.", "Rejected from {channel} at {time}. Nothing was changed." or "Expired at {time}. Nothing was changed.";
  - a done request's band is followed by "Recorded in the IRIS audit log.";
  - a Reject pressed on the simulated phone shows on the card within 5 s of the answer's reply;
  - an `undo_rollback` request appears as its own request card in the same incident.
  - Pin: F6.
- AC4 (Contest Planner ruling V2; AD-15): Given a closed incident whose store holds a pending `undo_rollback` request and pending requests of other kinds, when the page shows it, then:
  - the compact card draws the undo's request card and no other request card;
  - an answered undo's band shows once, on its card;
  - the rail's "Show in the chat: Undo the rollback of {setting} on {target}" focuses the undo's request card in the chat.
  - Pins: F6b and the `incident-view.test.mjs` compact cases.
- AC5 (AD-12; UX-DR8, 33, 117; NFR-25): Given the web build and the closed card of AC4, when it runs, then:
  - `payloads.mjs --check` passes with no interface change, and `ux-strings.test.mjs` passes with no new string;
  - in F6b the card has no unnamed control and no contrast failure (`scanNames`, `scanContrast`) in the light and the dark scheme;
  - Tab from the composer reaches the undo card's Approve, Reject and Show details in that order, each with a visible focus ring.
  - Pin: F6b.
- Playwright cases (sign-in-2, RAIL user, page clock 14:30 UTC):
  - F1: suspend and resume requests in one incident row (`seedIncident`), with the card, rail and phone checks of AC1. The phone notices use `askedSlots`.
  - F2: a reroute, with the same checks.
  - F3: a rollback and an undo with plain values, with the same checks. The undo's phone notice uses `askedSlots`, and the rollback's uses `fixtureSlots('incident.rollbackRequest')`.
  - F4: a partner warning with two recipients (dry run as A13's, with two `recipients` objects), with AC2's checks. The phone notice uses `askedSlots`.
  - F6: in one incident:
    - a done suspend with a result, its band and the audit line;
    - an expired reroute;
    - a pending resume rejected from its phone message, with the card's status within 5 s of the reply, as in RA2;
    - a done rollback with a pending undo (two request cards in raised order).
  - F6b: a closed incident (published closed after `raise`, as A9) with a pending undo, a pending suspend and a pending partner warning:
    - only the undo's card is drawn, with Show details on its row;
    - the rail jump focuses the undo's card;
    - the scans pass in both schemes, and the Tab order holds;
    - after the undo is published rejected, its card stays with its status;
    - after it is published done with a result, its band shows once (`[data-part="result"]` count 1 in the incident card).
  - F6b is extended with the closed-card ruling's pins (binding; the ruling is quoted in the Spec Change Log, with the implement stage's reading above it):
    - (a) only a PENDING undo's card is drawn on a closed card: no other kind (no repair, resend, new rollback, suspend or partner), and nothing once the undo is answered (rejected or done) or expired. Pin the expired state too (published `expired` after the pending one: no request card of it is drawn and the card keeps its status per the matrix row "undo answered").
    - (b1) an undo raised BEFORE the close, then the incident is closed (raise and publish open, then publish closed): the card shows it, and Approve and Reject from that card work (a click answers through the real answer path) and are audited exactly as on an open card (same audit line and answer status as the open-card case in F6).
    - (b2) an undo raised AFTER the close shows (this is the base F6b case).
    - (c) answering an undo from a closed card (approve and reject, each in its own case) does not reopen the incident or change its status: the card's chip, state and `incident.state` from `/api/v1/state` stay `closed` after the answer.
    - The rail's "Show in the chat" jump lands on (focuses) the undo card on a closed incident.
    - Mutations to demonstrate red and revert `cmp`-identical: (a) draw every kind on a closed card (drop the `drawnOnClosed` filter) -> (a) red; also make the filter keep an answered or expired undo -> (a) red; (b1) filter the closed card's undo by a "raised after" rule, or drop the undo from the card when the incident is closed after it was raised -> (b1) red; (b2) `compact ? []` -> (b2) and the jump red; (c) make the closed card's undo answer reopen the incident (or fake a state change in the test's fixture check) -> (c) red, or if no product path exists to mutate, assert and record that the answer path carries no state write by pinning the unchanged `incident.state`; Show-in-chat: make `jump` land on the chat list (`compact ? []`) -> the jump pin red.
    - Compactness stays computed from the payload (`stateOf(incident().state)?.chip === 'closed'`), not from the drawn view.

### Review Findings

Code review 2026-11-16 (Tier 1, full mode, baseline `6be77202`, diff `6be77202..8b096f1f -- src web`; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, all run). 27 rows: high 0, med 4, low 23. Each row: severity, fix-risk, footprint, spec-status, disposition.

- [x] [Review][Patch] MED, fix-risk low, in-story, clear. **Reject on an undo raised before the close was never pressed** (acceptance auditor; ruling (b) Pin 1 names "approve and deny"). F6b (b1) now runs once with Approve and once with Reject, each against an open-card control with the same action.
- [x] [Review][Patch] MED, fix-risk low, in-story, clear. **"Audited exactly as on an open card" compared no audit entry, and `headers: 1` was a constant** (all four layers). `answerFromCard` now reads the answer's Approval audit entry (`approvalAudit`, through `Test.Bridge.AuditLog.Wait`, marker = the request's Ref) and the measured header delta. The closed and open answers must be equal, and the entry must be `{change: answered, from: pending, to: approved|rejected, irisUser, channel: web, kind: fix}`.
- [x] [Review][Patch] MED, fix-risk low, in-story, clear. **Every answer pressed left a `Data.Precedent` row on the RAIL user's session** (blind hunter; Rule 19 hermeticity; Boundaries "remove them in finally"). Measured on a fresh stack: 7 rows per run (F6 1, the two b1 cases 2 each, the two (c) cases 1 each). `release()` now removes them by SourceRef (`removePrecedentsOf`, `support/memory.ts`, beside `removePrecedent`).
- [ ] [Review][Decision] MED, fix-risk low, in-epic, spec-bound. **A closed card gives no outcome after its undo is answered** (blind hunter; edge hunter 1 and 2; implement deferral 1). The ruling's "nothing once answered" removes the card when the answer reply lands. Nothing announces the status, and focus goes to the main region. This is a product call, filed as `decision-pending` **DW-1426** (owner burndown, for the Planner). The recommendation is to announce the existing `answered.*` text and focus the incident's headline, as a lost Dismiss already does (`chat-panel.ts` `incidentHeadline`). An approved but still executing undo is the same root cause.
- [x] [Review][Reject] LOW, fix-risk low, in-story, clear. **Implement deferral 1 said "focus falls to the body", which is wrong.** Measured: focus lands on `main.main`, through the chat panel's focus rule (UX-DR131: a gone item leaves focus to the main region). It is now pinned in `expectAnsweredAway`. Mutation: turning off the chat panel's `keepFocus` gives `body`, and four cases go red. This conforms to the page rule; where focus should go instead is part of DW-1426.
- [x] [Review][Dismiss] LOW, wontfix-theoretical. **The card's in-flight answer call is dropped with the card.** The card leaves only after the store holds the undo as non-pending: the reply's `LiveState.applyAnswer`, or the live answer event, and the server has recorded the answer before either. A failed or timed-out call leaves the undo pending, so the card stays and shows its notice. It would become real if a store update could mark an undo answered before the server records the answer.
- [x] [Review][Dismiss] LOW, wontfix-theoretical. **Implement deferral 2: pin (c) has no settle step.** It is neither flaky nor vacuous for its scope. The seeded request (`Test.Data.Fixture.Approval`) has no ResultTarget and no ApprovalHold, so no ApprovalOutcome reaches IncidentManager in this test. The answer path (AnswersIn, AnswerOps, `Approval.Answer`) has finished by the time the reply and the header are read, so there is nothing later to wait for. Correction of the implement stage's reason: IncidentManager does not "refuse every event on a closed incident". `Closed()` handles an approved MOVES-0 request with `Move(incident, incident.State, ResultNotice)`, which writes the row in the same state. The server's "stays closed" is pinned by `Test.Watch.Rollback` TestUndoAfterClose and `Test.Fix.Asked`/`PartnerDraft`. It would become real if a seeded request carried ResultTarget `IncidentManager` and a hold; then wait for that outcome header to complete before reading.
- [x] [Review][Patch] LOW. **The "no band" checks after a rejected or expired undo could not fail**, because the fixture payload gives them no result (verification gap). They are relabelled as fixture checks; the server owns that property.
- [x] [Review][Patch] LOW. **The expired step had no mutation of its own** (verification gap). Run: `drawnOnClosed` keeps an expired undo. See `## Verification`.
- [x] [Review][Patch] LOW. **The expired step left reject/phone answer fields on an expired row** (blind hunter, edge hunter, acceptance auditor). The expiry now clears them.
- [x] [Review][Patch] LOW. **The "raised after the close" undo had `raisedAt` 14:17, before `ClosedAt` 14:20** (blind hunter). It is now 14:22.
- [x] [Review][Patch] LOW. **The unit kind lists used `repair`, not the real `repair_resend`** (blind hunter). `repair_resend` and `email` are added.
- [x] [Review][Patch] LOW. **`AFTER_CLOSE_KINDS` was a hand-kept mirror** (blind hunter). A new unit case derives the set from `Fix/Kind/*.cls` (each NAME whose ASKEDSTATES, or the base class's, lists `closed`) and compares it. Mutation: see `## Verification`.
- [x] [Review][Patch] LOW. **The `incident-card.ts` component doc said a compact card always has its own actions row** (acceptance auditor). It is reworded.
- [x] [Review][Patch] LOW. **Comment and message mismatches** (blind hunter): the F6 order message, the `Closed` doc, `expectPhone`'s unused return value, and the 200-character header line in `step5-requests.spec.ts`.
- [x] [Review][Patch] LOW. **The last `SentTo(chatId)` assertion of `TestStepFiveRequests` read the mock's whole chat log** (verification gap; not self-contained). It is removed; each kind keeps its `before`-based checks. TelegramOut passed on a fresh stack.
- [x] [Review][Patch] LOW. **A `route.fetch` rejection hid behind a 30 s poll** (edge hunter). It is caught and reported as status -1 with its error.
- [x] [Review][Patch] LOW. **The (c) approve case did not check the reply** (blind hunter). It does now.
- [x] [Review][Patch] LOW. **A misleading unit title** (verification gap): the case that hand-builds `drawn` is retitled.
- [x] [Review][Dismiss] LOW, by-design. **The F1 to F3 phone checks compare the server's text with itself** (blind hunter). Decided 6 and AD-32: the server renders the text, and `TestStepFiveRequests` pins it against the catalog render.
- [x] [Review][Dismiss] LOW, by-design. **F6 does not pin the audit line after the band** (acceptance auditor). The order is fixed in one component template (`result-band.ts`: `.text`, then `p.audit`).
- [x] [Review][Dismiss] LOW, wontfix-theoretical. **A ref-less drawn request puts '' into `drawn`** (edge hunter). The store keys every approval by its ref. It would become real with an approval payload that has no ref.
- [x] [Review][Dismiss] LOW, wontfix-theoretical. **`FixtureSlots` could be a non-object** (edge hunter). The Catch fails the test with the error, so it is never silent.
- [x] [Review][Dismiss] LOW, wontfix-theoretical. **IncidentManager's AnswerNotice might arrive after `release()`** (verification gap). Seeded requests have no ResultTarget, so no outcome is sent; this is the same fact as deferral 2.
- [x] [Review][Dismiss] LOW, wontfix-accepted, out-of-footprint. **`rail-answer.spec.ts` RA2 leaves one Precedent row per run too**, the same root cause in another story's file. `reopen_if=` a test of the RAIL user asserts its precedents or the Memory card's "Your answers" list.
- [x] [Review][Dismiss] LOW. **The AC2 Telegram `$Find` has no mutation of its own** (verification gap). Rule 19 asks for one mutation per AC, and AC2's is F4's.
- [x] [Review][Dismiss] LOW. **The expired state is pinned after a rejected one, not after a pending one** (acceptance auditor). The view reads only the store's state; the stale fields are cleared now, and the expired step has its own mutation.

Rule 2 note: the patch's `auditClock` in `support/iris.ts` copies the one-line `auditMark` of `support/partner-contacts.ts` and `support/on-call.ts`. Those are feature modules that assert with `expect`; the generic reader belongs with `answerHeaders` in `iris.ts`.

## Spec Change Log

- 2026-11-16 (implement stage, literal reading of the closed-card ruling). The ruling's pin (a) governs where the matrix rows "Closed card, undo answered" and "Closed card, mixed" and F6b's "its card stays with its status" differ: a closed card draws a request card ONLY for an undo that is still pending, and none once the undo is answered, rejected, expired or done. An answered undo's result band (when it has one) is then one of the compact card's own bands, shown once; a rejected or expired undo has no card and no band. `drawnOnClosed` therefore holds both rules: the kind is in `AFTER_CLOSE_KINDS` and the approval's state is `pending`. The intent-contract block is read-only and keeps its wording; this entry supersedes the two matrix rows.
- 2026-11-16 (lead). **24.4b closed-card ruling, Contest Planner ~04:30Z Nov 16 (BINDING)**, quoted in full:

  > ## 24.4b closed-card ruling (Contest Planner, ~04:30Z Nov 16). BINDING.
  > A closed card draws EVERY undo that is still pending, whenever it was raised. Lane D's proposal is APPROVED.
  > V2 restricted the KIND of card, not when it was raised. A pending approval with no card anywhere is the worse failure.
  > 
  > CONDITIONS. Pin (a) to (c), each with a mutation:
  > - (a) **What a closed card draws:**
  >   - a request card only for an undo whose request is still pending;
  >   - no other kind: no repair, no resend, no new rollback;
  >   - nothing once the undo is answered or has expired.
  > - (b) **Raised before or after the close:**
  >   - Pin 1: an undo raised BEFORE the close, then the incident is closed. The card shows it, and approve and deny from that card work and are audited exactly as on an open card.
  >   - Pin 2: an undo raised AFTER the close.
  > - (c) **No reopening:** answering an undo from a closed card does not reopen the incident or change its status.
  > - (d) **EXPERIENCE.md wording:** in the same story, reword "asked after the close" to match, for example "an undo that is still waiting for an answer, whether it was asked before or after the close". This is a wording change only: no new page strings.
  > - (e) **Online demo:** unaffected, because it has no setting history.
  > 
  > After 24.4b, lane D runs 24.3's spec gate.
  > 
  > DW-1412 is verified, and the 1.0.12 cut blocker is cleared. Feature runs 43796568063 and 43796568152 need reporting only if they go red.

  Applied by the lead: (d) EXPERIENCE.md's Incident card sentence reworded (marker and old text). Binding on the implement stage: pins (a) only a PENDING undo's card on a closed card, no other kind, nothing once answered or expired; (b) pin 1 an undo raised BEFORE the close, then the close: shown, approve and deny work and are audited as on an open card; pin 2 an undo raised AFTER the close; (c) answering from a closed card does not reopen the incident or change its status; each with a mutation; (e) online demo unaffected.

- 2026-11-15 (plan). Story 24.4b carved from the parent 24.4 plan (pre-split) and 24.4a's "Moved to Story 24.4b" list, under the binding rulings below. Re-checked every Code Map line against HEAD f5bd8256, which merges 24.4a. Kept from the parent: AC1, AC2, AC4 (as AC3 and AC4 here), AC5's card part, F1 to F4, F6, `TestStepFiveRequests`, the four V3 files, and `AFTER_CLOSE_KINDS` with the implement stage's design note (compactness from the payload, `drawn` in the context).
  - F6 is split into F6 and F6b.
  - `fixtureSlots` was added for the rollback's phone notice.
  - The Tab order follows the DOM: Approve, Reject, then Show details. The parent's "Show details, then Approve" was wrong for a request card's row.
  - `ux-strings.test.mjs` needs no change, because no string is new.
- 2026-11-15 (lead's rulings, quoted from `<coordination>/prompts/story-244-rulings-20261115.md`, Contest Planner ~21:00Z Nov 15, BINDING):

  > ## V2: APPROVED
  > - A closed incident card draws only a rollback's undo request card.
  > - Add the one-line EXPERIENCE.md addition.
  > - Pin both of these:
  >   - a closed card draws no other request kind;
  >   - "Show in the chat" jumps to the undo request card.
  >
  > ## V3: GRANTED as a footprint extension
  > - The four web/scripts test files are allowed.
  > - The BUTTONKINDS mutate-and-revert in a test is fine, provided it is never committed.
  > - Leaving DW-1378 out is correct.

  And from the RE-PLAN RULINGS (~22:00Z), SPLIT: YES: "> **24.4b** follows. It covers V2's closed-card undo and the cross-surface pins. It also targets 1.0.12, but does not block it." The EXPERIENCE.md line is already applied (`EXPERIENCE.md:316`, "A closed card still shows the request card of an undo of a rollback asked after the close, and no other request card.").

## Review Triage Log

### 2026-11-16 - Review pass
- verdicts: 26 findings - high 0, medium 3, low 21, false 1, maybe-false 1
- findings:
  - `[medium]` `[defer]` Closed-card answer gives no feedback: the card (status, audit line) leaves the moment the answer lands, a failed call goes with it, focus drops to the body, and a rejected, expired or failed undo is silent on the closed card (blind hunter 1) - the literal reading of the binding ruling ("nothing once answered or expired"); a decision for the Contest Planner whether the card should stay while the answer is in flight. Deferred with the edge-case layer's "approved or failed undo shows nothing" (same root cause).
  - `[low]` `[reject]` Reject on an undo raised before the close is not exercised (blind hunter 2; edge hunter 5) - the same card and answer path as the after-close Reject case, which F6b covers; not worth a second long test.
  - `[low]` `[reject]` The open-card control is compared on the reply, the row and the header, not the status text (blind hunter 3; edge hunter 4) - the card is gone after the answer by the ruling, so a status cannot be compared; the audit evidence is the stored row and the trace header.
  - `[medium]` `[patch]` Mutation of `requestsOf` was marked "not re-run" (blind hunter 4) - re-run on the final tree: F3, F6 and four F6b cases red, reverted `cmp`-identical; the `mutation:` line rewritten.
  - `[low]` `[patch]` No recorded green run of the unit tests, TelegramOut, lint, build (blind hunter 5) - run on the final tree and recorded under `## Verification`.
  - `[low]` `[reject]` `AFTER_CLOSE_KINDS` is a hand-kept mirror of the server's `AskedClosed` (blind hunter 6) - Decided in-stage 1 (AD-12: the page cannot read the kind classes); its unit pin names the rule.
  - `[low]` `[patch]` The Spec Change Log wording "the ruling is the first entry" is stale (blind hunter 7) - reworded; the Auto Run Result section rewritten at finalize.
  - `[low]` `[reject]` Source pins match exact formatting; `stateOfApi` walks the body (blind hunter 8) - the `requests` regex pin is a spec task; the walker keys on `ref`, a string `state` and `count`, which only an incident row has; no wrong match is shown.
  - `[low]` `[reject]` F6b base is one long scenario (blind hunter 9) - each step asserts its own state; stale answered fields do not change any assertion; splitting costs a stack start per case.
  - `[low]` `[reject]` `TestStepFiveRequests` has a redundant size assertion (blind hunter 10) - harmless and cheap.
  - `[low]` `[reject]` Edge hunter 1 (approved, executing or failed undo shows nothing on the closed card) - grouped with the first finding; the ruling's pending-only rule.
  - `[false]` `[reject]` A drawn request with no ref puts '' into the drawn set (edge hunter 2) - every approval of the store is keyed by its ref; a ref-less approval cannot be drawn.
  - `[low]` `[reject]` AC4's text says "its card stays with its status" (edge hunter 3; gap other 8) - superseded by the first Spec Change Log entry; a fix would edit the spec.
  - `[maybe-false]` `[defer]` Pin (c) reads the closed state once, with no settle step (gap 1) - IncidentManager refuses every event on a closed incident (no product path reopens), so no async flip is shown; what would settle it: a bounded poll after the undo's execution; deferred as unverified medium.
  - `[low]` `[patch]` The "no effect on a non-compact card" unit case could not fail (gap 2) - now deep-equals the whole view with and without `drawn`.
  - `[low]` `[reject]` Several assertions have no `mutation:` line of their own (gap 3) - Rule 19 asks one demonstrated mutation per AC; each AC has one (AC1 three, AC2, AC3, AC4 several, AC5).
  - `[low]` `[reject]` `headers: 1` is a constant in the compared objects (gap 4) - the real header check is the poll inside `answerFromCard`.
  - `[low]` `[reject]` The done band and audit line assert on a hand-published payload (gap 5) - the answer's audit evidence is the stored row and the trace header; the band is the page's reading of a published result.
  - `[low]` `[reject]` Telegram text check is self-referential (gap 6) - it compares with the catalog's own render, which is what AD-32 requires; the buttons and parse mode are independent assertions.
  - `[low]` `[reject]` Redundant `SentTo` size assertion (gap 7) - same as blind 10.
  - `[low]` `[reject]` Intent audit: the cases are in `step5-cards.spec.ts`, not `step5-requests.spec.ts` - the spec's own Tasks allow the split.
  - `[low]` `[reject]` Intent audit: closed state, requests and results are seeded and published by the harness - the model of every case of this suite (24.4a, close-loop); not a defect.
  - `[low]` `[reject]` Intent audit: the no-reopen guarantee is a server property the diff does not change - pinned as unchanged state after the answer.

## Design Notes

### Decided in-stage

1. The kind rule is a copy of the server's `AskedClosed` answer (`undo_rollback` only today), because the page cannot read the kind classes' parameters (AD-12). Its unit pin names the rule. A later kind with `closed` in `ASKEDSTATES` must be added there.
2. A pending undo raised before the close is drawn too. The payload carries no close time and no new field is allowed. Closing does not cancel a pending request (`Watch/IncidentManager.cls` cancels one only when its raise's notice fails, 1033 and 1223), so that request is still answerable on the phone and the rail. It is still "a rollback's undo request card", which is what V2 rules. EXPERIENCE.md's "asked after the close" describes the usual case; an undo is asked after the close in nearly every flow.
3. The band of a drawn request is shown only on its request card: the compact `results` leave out the refs in `drawn`. `bandTexts` keeps all of them, so the chat still announces each result once.
4. Show details moves to the first drawn request card's row, as on an open card. The incident-level actions row shows only with no request card (unchanged template rule).
5. F6b also checks the Tab order of the undo card. 24.4a's Decided 16 moved this pin here.
6. Phone notices use the server's real fill (`askedSlots`) for the five asked kinds. The rollback, a diagnosed kind, has no asked fill, so its notice uses the catalog fixture's slots (`fixtureSlots`), never a hand-written copy. The phone pins check the buttons' names and that the text is the server's message; the text itself is the catalog's (AD-32).
7. `TestStepFiveRequests` uses `FixtureSlots`, as the approved parent plan did, with two recipients for the partner. The real `AskedSlots` fill reaches Telegram in 24.4a's `TestRedactedValue`. The step-5 phone and Telegram text is unchanged since 23.2, 23.3 and 23.5, whose own tests pin it.

### Governing ADs (Rule 6)

- AD-12 (`ARCHITECTURE-SPINE.md:445`): the page reads payload fields only and decides nothing. The interfaces are unchanged.
- AD-15 (551): a closed incident takes only AskedClosed kinds. Its state is untouched here.
- AD-16 (599): each card shows the row's own dry run.
- AD-32 (1288): the server renders the phone and Telegram text.
- AD-29 (1167) and AD-33 (1308): lane files. This story edits Lane B's web and test files only, plus the V3 scripts.

### Integration ACs, Consumes, Extend (Rules 1, 2)

- **Integration ACs:** F1 to F4, F6 and F6b run seeded rows through `Approval.FromRow` and `/api/v1/state` to the card and rail. Their phone legs send real `Notify` notices, filled by `AskedSlots`, to the phone page. `TestStepFiveRequests` runs TelegramOut against the CI mock.
- **Consumes:** 23.2 (item and reroute kinds), 23.3 (rollback, undo, `AskedClosed`), 23.5 (partner), 24.4a (redacted payload values; `step5-requests.spec.ts`; `askedSlots`), 21.10 and 23.12 (the answer paths), and Telegram Out's button rule.
- **Consumed-by:** none. No service is introduced.
- **Extend, don't copy:**
  - The kind filter extends the card's `requests` computed.
  - `drawn` extends `IncidentContext`.
  - `fixtureSlots` reuses `irisScript` and `LiveCase.FixtureSlots`.
  - The Telegram method reuses `TestButtons`' helpers (`Notification`, `FixtureSlots`, `SentTo`, `LastId`).
  - The e2e cases reuse `support/approvals.ts`, `support/iris.ts` and the RA2 and close-loop patterns.
  - No helper is copied.

### Contention and sequencing

- Lane B, OCT-epic23 (Story 23.13, in QA):
  - `incident-card.ts`: `incidentContext` gains an `approvals` parameter, and the `view` computed passes `this.approvals()`. This story edits the same `view` lines (it adds `drawn`) and the `requests` computed two lines below.
  - `incident-view.ts`: `IncidentContext` gains `approvals`, and `result` gains `simulated`.
  - It also edits `approval-sources.test.mjs` and `incident-view.test.mjs`.
  - The hunks are adjacent. Plain union: whoever pushes second integrates, keeps both and flags it. The union of `incidentContext` takes both the `approvals` parameter and `drawn`.
- DW-1412 (`Redact.Text` signature parameters) is in its own worktree (`OCT-epic24-dw1412`). The DW-1412 ruling says lane D does it ahead of 24.4b. This story touches no redactor file, so the plan does not overlap it. The implement stage starts when the lead releases it.

### Ledger (Rule 17)

`LEDGER slice 24-4b-show-the-new-fixes-partner-warnings-and-the-closed-card-undo` is empty: there is no entry to address. Related but not owned: DW-1378 (a done undo's band reads `settingChange.newValue`; `routed owner=burndown`). V3 says leaving it out is correct.

### Size, release and online demo

- Size: 7 web files (2 source, 3 unit tests, 1 e2e helper, 1 spec) and 1 IRIS test class. One goal. The spec is above the token aim (`oversized`).
- Target: 1.0.12, not a blocker.
- Online demo: no rollback or undo is raised there (the setting history is off, ONLINESHARED), so the closed-card undo never shows. The other kinds' cards are as today.

## Public text

**None new.** Every text is existing and reused verbatim:
- "Nothing has changed yet." (`APPROVAL_TEXTS.nothingYet`)
- "Before" and "After"
- "Approve: {action}" and "Reject: {action}" with the rail titles (`rail-view.ts` 47-52)
- "Show in the chat: {action}" (`rail-view.ts` 57)
- `answered.approved`, `answered.rejected`, `answered.expired` and `audit.recorded` (`Core.cls` 87, 106, 123, 619)
- The six request keys' texts (`Watch.cls` 818, 827, 836, 960, 1129, 1144)

## Veto items

- **V2 (APPROVED 21:00Z):** the closed card draws the request card of an `undo_rollback` request, and only that kind. The EXPERIENCE.md line has already been applied.
- **V3 (GRANTED 21:00Z):** the footprint extension. This story uses `web/scripts/incident-view.test.mjs`, `incident-sources.test.mjs` and `approval-sources.test.mjs`; `ux-strings.test.mjs` needs no edit. It also covers the `BUTTONKINDS` mutate-and-revert in `Channel/Telegram/Out.cls`, which is never committed.
- **NEW:** none. There is no new string, role, grant, dependency, outward action, or cross-lane edit beyond V2 and V3.

## Verification

Every IRIS call runs from the worktree root with:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'
```

- The warm tag is `e24s4biw` and the fresh tag is `e24s4bi`. Run IRIS MCP lookups only on `ocutalon-slot-d`/`OCUTALON`.
- Each line below is one foreground call (`timeout: 600000`) that ends inside about 150 s. Run one test class (or one `Class:Method`) per call, and never two test calls in one message.
- The web suite and each Playwright part are calls of their own. After any `web/` change, `ci/iris.sh build` comes before a browser part.

**Shared surfaces:**
- The compact card's request list and `results`:
  - `incident-view.test.mjs` 249-261 and 721-806;
  - `incident-sources.test.mjs` 199-203;
  - `approval-sources.test.mjs` 316;
  - `approval-card.spec.ts` A9 707-724 (CI `live:cards`; a repair request, so it stays green);
  - `close-loop.spec.ts` C1 and C9 (repair requests: no request card on the closed card; CI `live:answers`);
  - `answers.spec.ts` X6 (the rail jump; CI `live:answers`).
- `IncidentContext`, whose other reader is `chat-panel.ts:449` (`bandTexts`, unfiltered). Lane B's 23.13 adds `approvals` to it (see Contention).
- `step5-requests.spec.ts`: 24.4a's F3b, F5, F5b and F7 are unchanged and must still pass.
- The RAIL user's session and phone feed: `rail.spec.ts` R1 to R19 expect them empty.
- TelegramOut's mock call log: each method uses its own chat id (8660 is new).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `npm --prefix web test` -- passes.
- (once) `npm --prefix web run lint` -- passes.
- (once) `npm --prefix web run build` -- passes, with `payloads.mjs --check`, `catalog.mjs --check` and no budget error.
- (once) `... OCUTALON_RUN_TAG=e24s4biw ci/warm.sh up` -- ready.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4biw ci/iris.sh class OcuTalon.Test.Channel.TelegramOut` -- `CLASS ... passed`.
- (once) `... OCUTALON_RUN_TAG=e24s4biw ci/warm.sh down`.
- (once) `... OCUTALON_RUN_TAG=e24s4bi ci/iris.sh class OcuTalon.Test.Channel.TelegramOut` -- passes on a fresh stack.
- (once) `bash docker/tests/test-class-rules.sh` -- passes.
- (once) `... OCUTALON_RUN_TAG=e24s4bi ci/iris.sh build` -- the image and the web bundle.
- (loop) `... OCUTALON_RUN_TAG=e24s4bi ci/iris.sh live sign-in-2 --part k/N` for each part that holds the new cases.
  - Find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json`, written into the scratch folder, then `node web/scripts/e2e-part.mjs`.
  - Choose N so that each part ends inside about 150 s (about 93 s of it is setup).
  - Then (once) run the parts that hold `rail/rail-answer.spec.ts` and `rail.spec.ts`, the shared-session regression.
  - All pass.
- (once) `... OCUTALON_RUN_TAG=e24s4bi ci/iris.sh teardown`.
- (once, CI) `live:cards` (A9, A12 to A14), `live:answers` (C1, C9, X6) and the `shards` group (`Test.Channel.TelegramOut`) stay green.
- (once, the lead) Fresh-environment check (Rule 19), each forward and `--reverse`:
  - the `--part`s holding the new cases;
  - the lane shard part holding `Test.Channel.TelegramOut`.

**Mutations (Rule 19; at least one per AC):** record each as `mutation: ... -> ...`, revert it, and check that `git status --short` and `git diff --stat` are unchanged.
- AC1:
  - Swap `dry?.before` and `dry?.after` in `itemDryRunView` -> F1 red.
  - Remove `mono` from the `before` span (`approval-request-card.ts:154`) -> F1 red.
  - Remove `approval` from `Out.cls` `BUTTONKINDS` -> `TestStepFiveRequests` red. This is Lane A's file: revert it `cmp`-identical; it never lands (V3).
- AC2: make `partnerView` keep only the first recipient -> F4 red.
- AC3: draw no request card on a closed card (`[]` in place of the filter) -> F6b red, which is AC4's. AC3's own mutation: make `requestsOf` drop `undo_rollback` approvals -> F6 red (no undo card in the open incident).
- AC4:
  - Put back `compact ? []` in `requests` -> F6b red (no undo card; the rail jump lands on the list) and the unit compact case red.
  - Drop the `drawnOnClosed` filter (draw every kind) -> F6b's "no other kind" red.
  - Add `rollback_setting` to `AFTER_CLOSE_KINDS` -> the unit kind case red.
  - Leave `drawn` out of the `results` filter -> F6b's "band once" and its unit case red.
- AC5: set `.mono` in `approval-request-card.ts` to `color: var(--surface)` -> F6b's `scanContrast` red.

**Manual checks:** none beyond the commands.

**Mutations run (implement stage; each reverted `cmp`-identical, `git status --short` and `git diff --stat` unchanged):**
- mutation: swap `dry?.before` and `dry?.after` in `itemDryRunView` -> F1 red ("suspend_item: the Before row, in mono": expected "OrdersToWarehouse: enabled", got "disabled")
- mutation: remove `mono` from the `before` span (`approval-request-card.ts:154`) -> F1, F2, F3 and F6b red (the `.mono.before` row is not found)
- mutation: remove `approval` from `Out.cls` `BUTTONKINDS` -> `TestStepFiveRequests` red (every kind: "has the buttons on its last part only" and "has exactly Approve and Reject"); `Out.cls` restored `cmp`-identical from a scratch copy and never left changed
- mutation: `partnerView` keeps only the first recipient -> F4 red ("the To line names both recipients")
- mutation: `.mono { color: var(--surface) }` as the spec words it -> NOT red: `.before` and `.after` set their own colour after `.mono` and win. Applied to `.before` and `.after` instead (`color: var(--surface)`) -> F6b `scanContrast` red ("span.mono ... text 1.16:1 is under 4.5:1")
- mutation: `requests` returns nothing on a closed incident (`asked.filter((one) => drawnOnClosed(one) && false)`, compactness still read from the payload's state) -> F6b red (base, raised-before, approve and reject cases: "the undo has its request card on the closed incident", the rail jump has no card to focus) and the two source pins red (`approval-sources.test.mjs` the `requests` expression, `incident-sources.test.mjs` the closedness pin)
- mutation: Show-in-chat jump lands on the chat list when the card is not drawn (`status-rail.ts` `jump` takes `CHAT_LIST` whenever `document.querySelector(card) === null || card`) -> only the F6b jump pin red ("the rail jump focuses the undo card in the chat": expected focused, received inactive), the other eight cases green
- mutation: `drawnOnClosed` ignores the state (kind only: `return typeof approval.fixKind === 'string' && AFTER_CLOSE_KINDS.has(...)`) -> the two unit pins red ("draws an undo on a closed card only while its request is pending", the `incident-sources.test.mjs` state-and-kind source pin) and F6b red in four cases: base ("a rejected undo has no request card on the closed card"), raised-before, approve and reject ("the answered undo is not drawn any more")
- mutation: drop the kind filter (`drawnOnClosed` returns `approval.state === 'pending'`) -> F6b red ("no other kind has a card" in the base case; "no request card of any kind is drawn" in the approve and reject cases, where the other kinds' pending requests appear) and the three unit pins red (kind, pending, source)
- mutation: leave `drawn` out of the `results` filter -> F6b base red ("the incident payload gives the still pending undo a result: its band shows once in the incident card", expected 1, received 2) and the `incident-view.test.mjs` case "leaves out only the band of a request drawn as a request card" red
- mutation: filter the closed card's undo by a "raised after" rule (`raisedAt` later than the incident's `lastAt`) -> only the (b1) case red ("the closed card still shows the pending undo"); the base, approve and reject cases stay green; the two source pins red
- mutation: the test's fixture check sets the incident row to `open` before `expectStillClosed` reads it (no product path reopens an incident: IncidentManager refuses every event on a closed one) -> the (b1), approve and reject cases red ("the incident's row stays closed": expected "closed", received "open")
- mutation: add `rollback_setting` to `AFTER_CLOSE_KINDS` -> the `incident-view.test.mjs` cases "names the undo of a rollback as the only kind asked after the close" and "draws an undo on a closed card only while its request is pending" red
- mutation: `requestsOf` drops `undo_rollback` approvals -> F3, F6 and every F6b case red (no undo card): re-run in the review pass on the final tree (`ci/iris.sh build`, then `live sign-in-2 --part 12/20`: 6 failed, 3 passed); reverted `cmp`-identical, `git status --short` and `git diff --stat` unchanged
- Closed-card answers: the answered undo is no longer drawn, and the page drops the card's call with the card (`takeUntilDestroyed`) when the live answer event reaches it before the reply. The page's own response event therefore may never fire; F6b reads the answer through a route (`route.fetch` then `route.fulfill`) that records the reply (200 and the approval it returns), the stored row and the one trace header, and compares them with an open-card control. The session's `/api/v1/state` rail lists pending requests only, so it proves that the answered undo is no longer pending and that the incident is still `closed`.
- Unit and static runs on the final tree: `npm --prefix web test` 2178 pass, 0 fail (after the review patch to the non-compact case, `node --test web/scripts/incident-view.test.mjs` 82 pass); `npm --prefix web run lint` exit 0; `npm --prefix web run build` exit 0 (so `tokens.mjs --check`, `payloads.mjs --check` and `catalog.mjs --check` pass, no interface change); `bash docker/tests/test-class-rules.sh` exit 0; `OcuTalon.Test.Channel.TelegramOut` passed on a fresh stack (tag `e24s4bi`, 24 s, includes `TestStepFiveRequests`) and on the warm stack in the first pass. Not re-run by this stage: the CI groups (`live:cards`, `live:answers`, `shards`) and the lead's fresh-environment check.
- Code review (2026-11-16, tag `e24s4bcr`, fresh; `ci/iris.sh build`, then `live sign-in-2 --part 12/20`, which still holds `step5-cards.spec.ts` alone, now 10 tests). Each mutation was reverted `cmp`-identical, and `git status --short` and `git diff --stat` were unchanged:
  - mutation: the chat panel's focus effect does not call `keepFocus` -> the (b1) Approve and Reject cases and the (c) approve and reject cases red ("the pressed button left with its card: focus is on the main region, not the body": expected "main", received "body")
  - mutation: `drawnOnClosed` keeps an expired undo (`state === 'pending' || state === 'expired'`) -> base F6b red at its expired step ("an expired undo has no request card": expected 0, received 1)
  - mutation: `AFTER_CLOSE_KINDS` adds `rollback_setting` -> `incident-view.test.mjs` red, including the new source-derived case ("holds exactly the kinds whose class lists closed among its ASKEDSTATES")
  - measured: `release()` failing whenever `removePrecedentsOf` removed rows -> F6 1, (b1) 2 and 2, (c) 1 and 1 (the precedents the answers recorded), the other cases 0
  - final tree: part 12/20 10 passed (B13 to B19 rows pass); `OcuTalon.Test.Channel.TelegramOut` passed fresh (27 s); `npm --prefix web test` 2179 pass; lint and build exit 0. Not re-run: parts 11/20 and 13/20 (only a header comment changed in `step5-requests.spec.ts`).
- Run on the lane-D throwaways of tag `e24s4bi` (fresh; `sign-in-2` parts 11/20, 12/20 and 13/20: rail-answer and rail, the step5-cards file alone at 9 tests in about 45 s, step5-requests and reminder); all green on the unmutated tree.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A closed incident card now draws the request card of an `undo_rollback` request that is still pending, whenever it was raised, and no other kind. Nothing is drawn for an undo that is answered, rejected, expired or done; an answered undo's result band is then one of the compact card's own bands, shown once. Compactness is read from the payload's state, never from the drawn view. The step-5 kinds are pinned on the card, the rail and the phone page (F1 to F4, F6, F6b) and on the Telegram mock (`TestStepFiveRequests`). No server, payload, route, catalog, string or table change.

**Files changed.**
- `web/src/app/incidents/incident-view.ts`: `AFTER_CLOSE_KINDS`, `drawnOnClosed` (kind and pending), `IncidentContext.drawn`, the compact `results` filter.
- `web/src/app/incidents/incident-card.ts`: `requests` filters a closed incident by `drawnOnClosed`; `view` passes the drawn Refs.
- `web/scripts/incident-view.test.mjs`, `incident-sources.test.mjs`, `approval-sources.test.mjs`: the view and source pins.
- `web/e2e/support/iris.ts`: `fixtureSlots`, and an optional answered-fields argument of `setApprovalState`.
- `web/e2e/rail/step5-cards.spec.ts` (new): F1 to F4, F6 and four F6b cases; `web/e2e/rail/step5-requests.spec.ts`: its header points to it.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls`: `TestStepFiveRequests` (chat 8660).
- This spec: Spec Change Log entry (the literal reading of the closed-card ruling), Verification, triage log.

**Review.** 26 findings from four layers: 4 patched (the `requestsOf` mutation re-run, the non-compact unit case, the recorded green runs, a stale spec sentence), 2 deferred (the closed card's silence after an answer, a decision for the Contest Planner; pin (c) without a settle step, unverified), 20 rejected with reasons in the triage log. Patched by verdict: medium 1, low 3. Follow-up review: not recommended.

**Verification.** `npm --prefix web test` 2178 pass; lint, build (with `payloads.mjs --check`, `catalog.mjs --check`) and `docker/tests/test-class-rules.sh` exit 0; `TelegramOut` passed fresh and warm; `sign-in-2` parts 11/20, 12/20 and 13/20 all green on the unmutated tree; every mutation shown red and reverted `cmp`-identical (see `## Verification`). B13 (DW-1388) did not go red. Teardown done, no container or lock left.

**Residual risks.**
- The closed card drops the undo's card when the answer lands: no status, no audit line, focus falls to the body (deferred, for the Contest Planner).
- The answer reply is not observable by the page for an undo answered from a closed card (the page drops the call with the card); the server records the answer regardless.
- Lane B's 23.13 edits the same `incidentContext` and `view` hunks: plain union, keep both `approvals` and `drawn`.
- Not run here: CI groups `live:cards`, `live:answers`, `shards`, and the lead's fresh-environment check (Rule 19).
