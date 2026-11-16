---
title: 'Story 24.4b: Show the new fixes, partner warnings and the closed-card undo on the cards'
type: 'feature'
created: '2026-11-15'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
warnings: [oversized]
deferred: []
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

## Spec Change Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Plan only, as directed (halt after planning).
- The epic context was recompiled, because the planning artifacts were newer than it. The result is 11,708 bytes and starts with `# Epic 24 Context:`.
- Every Code Map line was re-checked against HEAD f5bd8256, which merges 24.4a.
- Nothing is NEW: no string, no veto item, and no cross-lane edit beyond V2 and V3.
- Warnings: `oversized`.
- No test was run.

Notes for the lead:
- DW-1412's ruling says lane D does it ahead of 24.4b. It is in `OCT-epic24-dw1412`, and this story touches no redactor file.
- Lane B's 23.13 (OCT-epic23) edits `incidentContext` and the card's `view` lines next to this story's hunks (plain union).
- Decided 2 draws a pending undo raised before the close too. EXPERIENCE.md's "asked after the close" describes the usual case, and the payload has no close time.
