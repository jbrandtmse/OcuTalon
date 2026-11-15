---
title: 'Story 24.4: Show the new fixes, partner warnings and setting changes on the cards'
type: 'feature'
created: '2026-11-15'
status: 'blocked'
baseline_revision: '243e45ba76ad628c995c3cb903aa5df8fe363e30'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Lane A's Stories 23.2, 23.3 and 23.5 are merged, and with them most of this story's display: every step-5 request already has its own dry run on the approval request card, the rail, the simulated phone and Telegram (Design Notes, "Already built"). Two parts are still missing:
- The evidence panel never lists the setting change that an incident names (AC3).
- The undo of a rollback, the one kind that can be asked for on a closed incident, gets no request card, because a closed (compact) incident card draws none (AC4).

Nothing pins the step-5 cards end to end in a browser either: A12 to A14 check HTTP and two bands, not the rendered dry runs, the phone or the cause line.

**Approach:**
- Add the setting-change rows to the evidence panel.
- Let a compact card draw the request card of an `undo_rollback` request.
- Pin every AC on its outermost surface: one Playwright spec for the cards, the rail and the phone; one Telegram method on the CI mock; unit pins for the two changes.
- No payload field, route, catalog key, table or Lane A file changes.

## Boundaries & Constraints

**Always:**
- The page decides nothing (AD-12). The card reads only the payload's fields (`settingChange`, `gapMinutes`, `requests`, the `approval` payloads) and renders text by interpolation only.
- Item names, setting names and values appear as IRIS shows them, in `mono`, in the evidence panel only (UX-DR78).
- The phone and Telegram text is the server's catalog text (AD-32). This story changes no catalog entry.
- Every new fixed string is in `INCIDENT_TEXTS` and in `ux-strings.test.mjs` with its ruling. Code uses ASCII escapes for any non-ASCII character (Rule 14).
- Tests seed fixture rows (`seedApproval`, `seedIncident`, `seedSettingChange`, `publishIncident`, `sendNotification`) and remove them, and the phone messages they made, in `finally`. They run on lane-D throwaways only.

**Never:**
- No edit of a Lane A file: `Watch/*`, `Fix/*`, `Channel/Telegram/*`, `Msg/Catalog/Watch.cls`, `Live/Payload/Incident.cls` and its parts. The one exception is the Rule 19 mutation in Verification, which is applied and reverted byte-identical and never lands.
- No new `/api/v1` route, live-event type, payload field, catalog key, table or column, and no new dependency.
- No values of a secret (`credential` true). No name of who made a change.
- No change to the incident's state or lifecycle. No change to a compact card's other request cards: a repair, suspend, resume, reroute, rollback or partner request on a closed incident stays undrawn, as A9 pins.
- No edit of `irislib/`, `irissys/`, `_bmad/`, `.claude/`, `CLAUDE.md` or a done story's spec.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Panel lists the change | incident with `settingChange` {item OrdersFromPartner, setting TargetConfigName, oldValue OrdersRouter, newValue OrdersRouterNew, detectedAt 14:08Z}, Show details open | after the Cause row: "Setting change" / "TargetConfigName on OrdersFromPartner" (mono), "Old value" / "OrdersRouter" (mono), "New value" / "OrdersRouterNew" (mono), "Detected" / the page time with its day | No error expected |
| Secret change | `credential` true, blank values | "Setting change" and "Detected" rows only, with no value rows | Values never shown |
| Empty value | `oldValue` "" (the setting was added) | the "Old value" row is left out; "New value" shows | Row omitted |
| No change named | no `settingChange`, or no setting or item in it | no new rows; the panel is as today | Nothing added |
| Closed card, undo pending | incident `closed`, store holds a pending `undo_rollback` approval of it | the compact card draws that request card (dry run, Approve, Reject, expiry); its band is in its card only, never also in the compact bands | No error expected |
| Closed card, other kinds | incident `closed` with a repair or rollback request | no request card (A9 unchanged); the compact bands as today | Unchanged |
| Closed card, undo answered | the undo was rejected or is done | its card stays, with its status (and its band when it has a result) | No error expected |

</intent-contract>

## Code Map

All web paths are under `web/`. IRIS paths are under `src/ocutalon/cls/OcuTalon/`.

**To change**
- `src/app/incidents/incident-view.ts`:
  - `INCIDENT_TEXTS` 34-79 (`labelCause` 61, `labelItems` 64): add the new labels here.
  - `IncidentContext` 88-108: `itemTime` 98.
  - `settingCauseOf` 262-272 (built). `itemLinesOf` 343-360.
  - `panelOf` 362-391: the Cause row is at 364-367, and the setting rows go after it.
  - `bandsOf` 451-461; `incidentView` 472-505, with the compact `results` at 503.
- `src/app/incidents/incident-card.ts`:
  - The cause line is at 91-92 and the compact bands at 111-113.
  - The request cards are at 114-127; the own Show details row and panel when there is no request card are at 129-155.
  - `requests` is at 312 (`compact ? [] : requestsOf(...)`).
- `src/app/incidents/evidence-panel.ts` 17-42: draws rows generically. It needs no change unless lint asks for one.

**Already built (read only, evidence for Design Notes)**
- `src/app/approvals/approval-view.ts`:
  - `APPROVAL_TEXTS` 51-90.
  - `itemDryRunView` 260-275, `settingDryRunView` 278-293, `rerouteDryRunView` 296-310, `dryRunView` 313-344, `partnerView` 359-376.
  - `statusOf` 400-420, `approvalView` 423-455, `requestsOf` 213-226.
  - `resultView` 575-650, `settingResultView` 683-700, `bandOf` 740-742.
- `src/app/approvals/approval-request-card.ts`: the partner block is at 132-141, the dry-run rows at 146-175 (`.mono.before` 154, `.mono.after` 160) and the answer row at 177+ (`aria-label` approveName 183).
- `src/app/rail/rail-view.ts`: `RAIL_TEXTS` titles at 47-52 and `showInChat` at 57; `approvalTitle` 211-243; the approval row's jump at 269-275.
- `src/app/phone/phone-request.ts` `messageContext` 40-52 and `phone-view.ts` `blocksOf` 128 / `requestView` 158: the server's text, with the approval view's button names.
- `src/app/live/payloads.ts`: `SettingChange` 145-153, and `IncidentPayload` with `settingChange` and `gapMinutes` at 364-365. They are generated by `scripts/payloads.mjs`, and `npm run build` runs `--check`.
- IRIS:
  - `Live/Payload/Approval.cls` `FromRow` 117-168 (the partner part 127-138; the item, field, before, after, from, to and example 144-153) and `Live/Payload/Part/DryRun.cls` 28-43.
  - `Live/Payload/Incident.cls` `Change` 116-134 and `Live/Payload/Part/SettingChange.cls`.
  - `Fix/Kind.cls` `AskedClosed` 156-162; `Fix/Kind/UndoRollback.cls` `MOVES` 26 and `ASKEDSTATES` 28; `Watch/IncidentManager.cls:1076` (a closed incident takes only AskedClosed kinds).
  - `Msg/Catalog/Watch.cls`: `incident.suspendRequest` 818, `resumeRequest` 827, `rerouteRequest` 836, `partnerRequest` 960, `rollbackRequest` 1129, `undoRollbackRequest` 1144 and `settingChangeCause` 1155.
  - `Msg/Catalog/Core.cls`: `answered.approved` 87, `answered.rejected` 106, `answered.expired` 123 and `audit.recorded` 619.
  - `Watch/Notice.cls` 244-258 (the partner slots hold the whole notice and every "Name <address>").
  - `Channel/Telegram/Out.cls` 41-47 and 105-110 (`BUTTONKINDS` incident,approval; plain text; split whole with the buttons on the last part) and 262 (`inline_keyboard`).

**Tests to extend or add**
- `scripts/incident-view.test.mjs`:
  - setting cause 178-190, and the panel 380-437;
  - compact 249-266 and 636-730.
- `scripts/incident-sources.test.mjs:199` (the compact bands), and `scripts/approval-sources.test.mjs:316` (the `requests` regex pin).
- `scripts/ux-strings.test.mjs`: the `ruled` table at 813. 23.3's entries are at 1035-1050, and the place for the new entry is after them.
- `e2e/rail/rail-answer.spec.ts`: the model for a RAIL-user cross-surface spec. It uses `holdPolls`, `dropPhone`, `cleanFixtureRows` and cleanup in `finally`.
- `e2e/support/approvals.ts`:
  - `incidentOf` 40-61, `raise` 70-85, `phoneOf` and `messageOf` 87-88;
  - `noticeOnPhone` 109-119 and `phoneShows` 121-131.
- `e2e/support/iris.ts`:
  - `publishIncident` 182, `cleanFixtureRows` 704 and `seedApproval` 776 (`ApprovalFields` 748-767: fixKind, state and the answered fields);
  - `seedIncident` 1060 (with `settingChangeRef`) and `seedSettingChange` 1101 (Host, not a secret).
- `e2e/support/scan.ts` `scanContrast` 149 and `scanNames` 49. `e2e/floor/scan.spec.ts:31` switches the theme with `emulateMedia({ colorScheme })`.
- `e2e/cards/approval-card.spec.ts`: A9 is at 707 (it must stay green), and A12, A13 and A14 at 389, 518 and 468. No new case goes into cards: `playwright-projects.test.mjs:331-336` pins 32 cases there.
- `Test/Channel/TelegramOut.cls`: `TestButtons` 820 is the model, with `Request` 808 and `FixtureSlots`. `Test/Channel/TelegramChat.cls` `TestNotices` 453 already pins each step-5 key's Telegram text as the phone's.

## Tasks & Acceptance

**Execution:**
- `web/src/app/incidents/incident-view.ts`:
  - Add the five strings of Public text to `INCIDENT_TEXTS`.
  - In `panelOf`, right after the Cause row, add the setting-change rows from `payload.settingChange`, as the matrix says:
    - "Setting change": `{setting} on {item}`, in mono.
    - "Old value" and "New value": the values in mono. Each is left out when `credential` is true or its value is empty.
    - "Detected": `ctx.itemTime(detectedAt)`, not in mono, left out when it is unreadable.
  - Rows show only when both `setting` and `item` are set.
  - Export `AFTER_CLOSE_KINDS` (a `ReadonlySet` holding `undo_rollback`). Its doc names `Fix.Kind.AskedClosed` as the server rule it mirrors.
  - `IncidentContext` gains an optional `drawn?: ReadonlySet<string>`: the request Refs that the card draws as request cards. A compact card's `results` leave those Refs out. Update the module's doc bullets for both changes.
- `web/src/app/incidents/incident-card.ts`:
  - `requests` becomes `compact ? requestsOf(...).filter(by AFTER_CLOSE_KINDS on fixKind) : requestsOf(...)`.
  - Pass the drawn Refs into the incident context, so that no band shows twice.
  - Update the component doc to match.
- `web/scripts/incident-view.test.mjs`: pin each matrix row of the panel and of the compact card. That covers rows, order, mono, the secret, an empty value, no change, an undo kept out of `results` only when drawn, and the other kinds unchanged.
- `web/scripts/approval-sources.test.mjs`: change the `requests` regex at 316 to the new expression. `web/scripts/incident-sources.test.mjs`: pin that the drawn Refs reach the context.
- `web/scripts/ux-strings.test.mjs`: add one `ruled` entry with the five strings, citing the Planner's ruling of V1 at the spec gate. Never give them an invented source.
- `web/e2e/rail/step5-requests.spec.ts` (new, sign-in-2 project, RAIL user, `workers: 1`). Cases F1 to F6 run as described under Acceptance Criteria. Each case cleans its rows and its phone messages in `finally`.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls`: add `TestStepFiveRequests`, modelled on `TestButtons`, on its own chat id. For each of `incident.suspendRequest`, `resumeRequest`, `rerouteRequest`, `partnerRequest`, `rollbackRequest` and `undoRollbackRequest`, as kind `approval` with `FixtureSlots(key)`, the message:
  - is the catalog's telegram text, with no `parse_mode`;
  - its last part carries exactly Approve `approve:<ref>` and Reject `reject:<ref>`;
  - for the partner key, its text holds the whole fixture notice and every recipient.

**Acceptance Criteria:**
- AC1 (FR-26, FR-8; UX-DR75, 77, 83, 113): Given a pending request of each kind (`suspend_item`, `resume_item`, `reroute`, `rollback_setting`, `undo_rollback`) in one incident, when the page shows it, then:
  - the request card shows that kind's own dry run;
  - a suspend or resume shows "Before" "{item}: enabled" and "After" "{item}: disabled" (swapped for a resume);
  - a reroute shows its count line and "Message {example}: {to}";
  - a rollback or undo shows "{setting}: {value}" rows;
  - the Before and After rows are text-labelled and in the mono font;
  - "Nothing has changed yet." shows;
  - Approve and Reject are named "Approve: {title}" and "Reject: {title}" with the rail's lower-cased title;
  - the rail row has that title;
  - the phone message of its catalog notice has the dry-run sentence and two buttons with the same names;
  - and Telegram, on the CI mock, gets the same catalog text with inline Approve and Reject on its last part.
  - Pins: F1 to F3 and `TestStepFiveRequests`.
- AC2 (FR-29; UX-DR136, 146): Given a pending `partner_warning` request with two recipients, when it shows on the card, the phone and Telegram, then:
  - the card's partner block shows "To: " with both "Name <address>" entries, and the whole notice, before the answer row (DOM order);
  - the phone message and the Telegram text hold the whole notice and both recipients as plain text, before the buttons.
  - Pins: F4 and `TestStepFiveRequests`.
- AC3 (FR-27; UX-DR78, 146; Integration): Given a real `SettingChange` row and an incident that names it (`seedIncident` with `settingChangeRef`, first failure 4 minutes after `detectedAt`), when the page loads `/api/v1/state`, then:
  - the card shows "The feed broke four minutes after this setting changed: {setting} on {item}, at {time}.";
  - Show details lists the Setting change, Old value, New value and Detected rows, the first three in mono.
  - Pin: F5.
- AC4 (FR-8, FR-26, NFR-9; UX-DR74, 76, 79): Given requests of the new kinds that are answered, expire, run or are offered for undo, when each happens, then:
  - each card shows "Approved from {channel} at {time}.", "Rejected from {channel} at {time}. Nothing was changed." or "Expired at {time}. Nothing was changed.";
  - a done request's band is followed by "Recorded in the IRIS audit log.";
  - a Reject pressed on the phone shows on the card within 5 s of the reply;
  - an `undo_rollback` request appears as its own request card in the same incident, including on a closed incident.
  - Pins: F6 and the unit pins.
- AC5 (AD-12; UX-DR8, 33, 117; NFR-25): Given the web build, when it runs, then:
  - `payloads.mjs --check` passes (the TypeScript interfaces match `OcuTalon.Live.Payload`; this story changes none);
  - `ux-strings.test.mjs` covers every new string;
  - in F5 and F6 the cards have no unnamed control and no contrast failure (`scanNames`, `scanContrast`) in both the light and the dark scheme;
  - Tab reaches Show details and the undo card's Approve, in that order, with a visible focus ring.

## Spec Change Log

- 2026-11-15 (lead). **Gate ruled, Contest Planner ~21:00Z Nov 15 (BINDING)**, quoted in full from `<coordination>/prompts/story-244-rulings-20261115.md`:

  > # Story 24.4 rulings (Contest Planner, about 21:00Z on 2026-11-15). BINDING.
  > 
  > 24.4 is APPROVED, with one condition. It targets 1.0.12.
  > 
  > ## V1: the five new page strings, APPROVED verbatim
  > The strings are:
  > - "Setting change"
  > - "{setting} on {item}"
  > - "Old value"
  > - "New value"
  > - "Detected"
  > 
  > CONDITION:
  > - Old value and New value go through the SAME redactor as the rollback dry run's Before and After.
  > - They are left out for a credential or an empty value, as proposed.
  > - Pin it: a non-credential setting whose value holds a secret-shaped string, such as a URL with a token, shows redacted in the panel.
  > 
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
  > 
  > ## DW-1388
  > If B13 goes red again, report it to the Planner as a regression.

  Applied by the lead: EXPERIENCE.md's Incident card bullet gains the V2 sentence (with "and no other request card"). Added to Execution (binding): (a) "Old value" and "New value" go through the SAME redactor as the rollback dry run's Before and After (name it in the code; no second redactor), and are left out for a credential or an empty value; pin with a NON-credential setting whose value is secret-shaped (e.g. a URL with a token) that shows REDACTED in the panel, with a mutation (bypass the redactor -> red); (b) pin that a closed card draws NO other request kind (e.g. a pending fix or partner warning on a closed incident draws nothing), with a mutation; (c) pin that the rail's "Show in the chat" jumps to the undo request card on a closed incident, with a mutation; (d) report any B13 (DW-1388) red as a regression.

## Review Triage Log

## Design Notes

### Ground truth on the feature branch (HEAD 14f8c6c0; 23.2, 23.3, 23.5, 21.10, 21.11, 23.12, 36.1 and 36.2 merged)

| Kind | Raise (Lane A) | The row's dry run, as the `approval` payload carries it | Catalog key (Watch.cls) |
|---|---|---|---|
| suspend / resume | `ProposeFix` `suspend_item`/`resume_item` (Tools/WatchTools.cls:205) | `item`, `before`/`after` "enabled"/"disabled" (Approval.cls:150,148-149; DryRun.cls:28) | `incident.suspendRequest` 818, `resumeRequest` 827 |
| reroute | `reroute` (same) | `affected`, `resend`, `itemNoun`, `from`, `to`, `example` (Approval.cls:144-158; DryRun.cls:31-35) | `incident.rerouteRequest` 836 |
| roll back | diagnosis `rollback_setting` (Agent/Diagnosis.cls:34; Watch/SettingCause.cls) | `item`, `field`, `before` (now), `after` (old) (Approval.cls:147-150) | `incident.rollbackRequest` 1129 (its `{cause}` is the setting-cause sentence) |
| undo | `ProposeFix` `undo_rollback`, also on a closed incident (UndoRollback.cls:26-28; Kind.cls:156-162) | the same keys, before old, after new | `incident.undoRollbackRequest` 1144 |
| partner warning | `partner_warning`, drafted (23.5) | `notice`, `recipients` ["Name <address>"], `simulated` (Approval.cls:127-138; DryRun.cls:37-43) | `incident.partnerRequest` 960 |

The incident payload carries `settingChange` {item, target, setting, oldValue, newValue, credential, detectedAt} and `gapMinutes` (Incident.cls:61-63, 116-134). No fixture *request* is still needed for any kind: all of them raise on the feature branch. The new tests still seed fixture rows, because they need no model or production and are deterministic. Lane A's own tests (`Test.Watch.Rollback`, `Test.Fix.ItemKinds`, `Test.Fix.PartnerWarning`) cover the real raise.

### Already built (no work; this story only pins it in F1 to F6)

- **Cards:**
  - each kind's dry run: approval-view.ts 260-344; the partner block 359-376 and card 132-141; mono Before/After rows card 146-175;
  - "Nothing has changed yet." (approval-view.ts:70);
  - button names approval-view.ts 449-450 with the rail titles rail-view.ts 47-52;
  - statuses approval-view.ts 400-420 from Core.cls 87, 106 and 123;
  - bands and the audit line approval-view.ts 575-742 (`audit.recorded` Core.cls:619);
  - the rollback and undo bands (23.3).
- **Incident card:**
  - the setting-cause line incident-view.ts 262-272 and card 91-92 (`incident.settingChangeCause` Watch.cls:1155);
  - each kind's fix and fixing sentence incident-view.ts 274-301 (`CHAT_KINDS` 274);
  - an undo on an open or resolved incident is its own card, because `requestsOf` lists every approval of the incident (approval-view.ts:213-226).
- **Rail:** `approvalTitle` (rail-view.ts:211-243) and the jump (269-275).
- **Phone:** the server's text with the approval view's names (phone-request.ts:40-52; phone-view.ts:158).
- **Telegram:**
  - plain text, with buttons on every `incident` and `approval` notice that has an ApprovalRef, split whole (Out.cls:41-47, 105-110);
  - the step-5 texts equal the phone's (`TestNotices`, TelegramChat.cls:476);
  - the partner slots hold the whole notice and every recipient (Notice.cls:244-258).
- **Payload interfaces:** generated and checked (`payloads.mjs --check` in `npm run build`).

### Decided in-stage

1. The new strings are page constants in `INCIDENT_TEXTS`, as the panel's other labels are ("Cause", "Error"). No catalog key, because the panel is page-only (UX-DR78).
2. Row order: right after Cause. Item and setting names and values in mono; the time not in mono, as the "Failures by item" times show.
3. "Detected", not "Changed": `detectedAt` is when a check saw the change, so the text claims only that.
4. A secret's value rows and an empty value's row are left out, with no new "hidden" text. The target (Host or Adapter) is not shown, because the AC names item, setting, values and time.
5. `AFTER_CLOSE_KINDS` copies the server's `AskedClosed` answer (`undo_rollback` only today), because the page cannot read the kind classes' parameters. A later kind with `closed` in `ASKEDSTATES` must be added there; the unit pin names the rule.
6. The new e2e spec lives in `e2e/rail/` (sign-in-2, which takes `--part`). `live cards` cannot be cut into calls of about 150 s. The rail user's session is cleaned in `finally`, as in rail-answer.spec.ts (23.12).

### Governing ADs (Rule 6)

- AD-12: payloads with matching interfaces; the page decides nothing.
- AD-15: the incident's states. A closed incident takes only AskedClosed kinds, and its state is untouched here.
- AD-16: the dry run is the row's.
- AD-29 and AD-33: Lane B files only.
- AD-32: the server renders the phone and Telegram text; producers never render.
- AD-25: the online demo.

### Integration ACs, Consumes, Extend (Rules 1, 2)

- **Integration AC:** AC3. A real `SettingChange` row passes through `Live.Payload.Incident.FromRow` and `/api/v1/state` to the panel rows.
- **Consumes:**
  - 23.3: `settingChange`, `gapMinutes`, `incident.settingChangeCause` and the rollback and undo kinds;
  - 23.2: the item and reroute dry runs;
  - 23.5: the partner part;
  - 21.10 and 23.12: the answer paths;
  - Telegram Out's button rule.
- **Consumed-by:** none (no service introduced).
- **Extend, don't copy:**
  - the rows extend `panelOf`;
  - the compact rule extends `requests`;
  - the Telegram method reuses `TestButtons`' helpers (`Request`, `FixtureSlots`, `SentTo`);
  - the spec reuses `support/approvals.ts` and `support/iris.ts` helpers. No helper is copied.

### Ledger (Rule 17)

`LEDGER slice 24-4-show-the-new-fixes-partner-warnings-and-setting-changes-on-t` is empty: no entry to address. Related but not owned here: DW-1378 (escalated, owner burndown). A done undo's band reads `settingChange.newValue`, not the dry run's after. The fix needs a new request-part field (Lane A's payload), so this story declines it.

### Split (Rule 5)

There is no split. It is one goal, two small view changes and their pins. It is under the multiple-goals line. The spec is `oversized` only by length.

### Release and online demo

Target 1.0.12 or later. On the online demo the setting history is off (36.1 V4), so no incident names a change and the new rows never show. Rollback and undo refuse with ONLINESHARED, so the compact undo card never shows there either. The suspend, resume and partner cards are as today.

## Public text

**NEW** (V1; page constants in `INCIDENT_TEXTS`, evidence panel only):
- "Setting change"
- "{setting} on {item}"
- "Old value"
- "New value"
- "Detected"

**Existing, reused verbatim (no change):**
- "Nothing has changed yet.": `APPROVAL_TEXTS.nothingYet`; EXPERIENCE.md:325.
- "Before" and "After": `APPROVAL_TEXTS`; UX-DR77.
- "Approved from {channel} at {time}.": `answered.approved`, Core.cls:87; EXPERIENCE.md:717.
- "Rejected from {channel} at {time}. Nothing was changed.": Core.cls:106; EXPERIENCE.md:718.
- "Expired at {time}. Nothing was changed.": Core.cls:123; EXPERIENCE.md:719.
- "Recorded in the IRIS audit log.": `audit.recorded`, Core.cls:619; EXPERIENCE.md:738.
- "The feed broke {minutes} after this setting changed: {setting} on {target}, at {time}.": Watch.cls:1155. Approved at 23.3's gate, and EXPERIENCE.md:1163 holds its fixture.
- "Approve: {action}" and "Reject: {action}" (approval-view.ts:55-56), with the rail titles "Suspend {item}", "Resume {item}", "Reroute {n} {noun} to {to}", "Put {setting} on {target} back", "Undo the rollback of {setting} on {target}" and "Send a delay notice" (rail-view.ts:47-52; ruled at 23.2, 23.3 and 23.5).
- The six request keys' texts (Watch.cls 818, 827, 836, 960, 1129, 1144): unchanged.

## Veto items

- **V1 NEW: public text.** The five evidence-panel strings above.
  - Online demo: never shown, because there is no setting history there.
  - If refused, AC3's panel half needs the Planner's wording.
- **V2 NEW: card behaviour.** A closed (compact) incident card draws the request card of an `undo_rollback` request, and only that kind. Today a closed card draws no request card (Story 6.4; UX-DR74's "compacted" card).
  - The AC's "an undo arrives as its own approval request card in the same incident" requires it. 23.3 lets an undo be asked after the close (UndoRollback.cls:28), so on the web it is otherwise answerable only from the phone and Telegram, and the rail's "Show in the chat" jump lands nowhere.
  - Online demo: never, since the undo refuses there.
  - No text changes. For the lead (apply-and-report), add to EXPERIENCE.md's Incident card bullet (:316): "A closed card still shows the request card of an undo of a rollback asked after the close."
  - If V2 is refused, AC4's closed-incident clause needs a Rule 5 ask-first narrowing.
- **V3 NEW: footprint extension (Rule 11 (b)).** `web/scripts/{incident-view,incident-sources,approval-sources,ux-strings}.test.mjs` are outside `paths_hint`.
  - `ux-strings.test.mjs` gets one new `ruled` entry, appended. The others are Lane B's own view pins.
  - Online demo: none.
- **Cross-lane: none landing.**
  - No Lane A file is edited.
  - Telegram Out (Lane A) is read only. Its pin goes into `Test/Channel/TelegramOut.cls`, which is inside `paths_hint`.
  - The one Rule 19 mutation of `Channel/Telegram/Out.cls` `BUTTONKINDS` is applied and reverted, `cmp`-identical, and never committed.
- There is no new payload field, route, catalog key, table, column, role, grant, dependency or outward action.

## Verification

Every IRIS call runs from the worktree root with:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'
```

- The warm tag is `e24s4iw`; the fresh tag is `e24s4i`.
- Each line below is one foreground call (`timeout: 600000`) that ends inside about 150 s.
- One test class per call. Never two test calls in one message.
- The web suite and each Playwright part are calls of their own.
- After any `web/` change, `ci/iris.sh build` comes before a browser unit.

**Shared surfaces:**
- `INCIDENT_TEXTS` and the `ux-strings` inventory and `ruled` table.
- The panel rows of `incident-view.test.mjs` 380-437.
- The compact card's request list and `results`: `incident-view.test.mjs` 636-730, `incident-sources.test.mjs:199`, `approval-sources.test.mjs:316`, and `approval-card.spec.ts` A9 (CI's `live:cards`).
- The RAIL user's session and phone feed: `rail.spec.ts` R1 to R19 expect them empty.
- TelegramOut's mock call log: use a chat id of the method's own.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `npm --prefix web test`: passes.
- (once) `npm --prefix web run lint`: passes.
- (once) `npm --prefix web run build`: passes, with `payloads.mjs --check`, `catalog.mjs --check` and no budget error.
- (once) `... OCUTALON_RUN_TAG=e24s4iw ci/warm.sh up`: ready.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Channel.TelegramOut`: `CLASS ... passed`.
- (once) `... OCUTALON_RUN_TAG=e24s4iw ci/warm.sh down`.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh class OcuTalon.Test.Channel.TelegramOut`: passes on a fresh stack.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh build`: the image and the web bundle.
- (loop) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh live sign-in-2 --part k/N`, for the part that holds `rail/step5-requests.spec.ts`:
  - Find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json` into the scratch folder, then `node web/scripts/e2e-part.mjs`.
  - Choose N so the part ends inside about 150 s (about 93 s of it is setup). Split the spec into two files if one part cannot hold it.
  - Then (once) the part that holds `rail/rail-answer.spec.ts` and `rail.spec.ts`, as the shared-session regression. All pass.
- (once) `bash docker/tests/test-class-rules.sh`: passes.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh teardown`.
- (once, CI) `live:cards`: A9 and A12 to A14 stay green. Locally it cannot fit one call of about 150 s, and CI's `shards` group runs it.
- (once, the lead) Fresh-environment check: the `--part` holding the spec, forward and `--reverse` (Rule 19), and `ci/iris.sh shard lane-b --part k/n` holding `Test.Channel.TelegramOut`, forward and reversed.

**Mutations (Rule 19; record each as `mutation: … → …`; revert and check that `git status --short` and `git diff --stat` are unchanged):**
- AC1: swap `dry?.before` and `dry?.after` in `settingDryRunView`, and F3 goes red. Also remove `mono` from the `before` span, and F1 goes red (the font check).
- AC1 (Telegram half): remove `approval` from `Out.cls` `BUTTONKINDS`, and `TestStepFiveRequests` goes red. This is Lane A's file: revert it `cmp`-identical, and it never lands.
- AC2: make `partnerView` join only the first recipient, and F4 goes red.
- AC3: make `panelOf` skip the setting rows, and F5 goes red, as do the `incident-view.test.mjs` panel cases.
- AC4: put back `compact ? []` in `requests`, and F6 (the closed undo) and the unit compact case go red. Leave `drawn` out of `results`, and the unit "no band twice" case goes red.
- AC5: drop the new `ruled` entry, and `ux-strings.test.mjs` goes red. Set `.label` in `evidence-panel.ts` to `color: var(--surface)`, and the F5 dark-scheme `scanContrast` goes red.

**Manual checks:** none beyond the commands.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: the Planner's V1 CONDITION (Old value and New value go through the SAME redactor as the rollback dry run's Before and After; pin: a non-credential setting with a secret-shaped value shows REDACTED) names a redactor that does not exist. The rollback and undo dry run is `settingDryRunView` in `web/src/app/approvals/approval-view.ts`, which interpolates `dry.before` and `dry.after` unredacted through `APPROVAL_TEXTS.settingRow`. Server side, `Live/Payload/Approval.cls` `FromRow` and `Incident.cls` `Change` copy the values raw. No code under `web/src` redacts, and the only value redactor in the repo, `OcuTalon.Bridge.Redact.Text`, is not on either path. The only protection today is `Watch.Reader.CredentialName`, which blanks a secret by setting name (the `credential` flag). The pin cannot go green, and writing a page-side redactor would be a second redactor with an invented pattern list (against the ruling and AD-12). Owner or Planner decision needed (security posture, a veto item), one of: (1) the new rows follow the rollback card exactly (left out for a credential or an empty value, otherwise shown as is) and the REDACTED pin and mutation are dropped; (2) Lane A redacts on the server (`Incident.Change` and `Approval.FromRow` run the values through `OcuTalon.Bridge.Redact.Text`), a Lane A edit and a cross-lane footprint extension, which gives rollback, undo and the panel one redactor; (3) a new page-side redactor, with its pattern list ruled. No file was edited by the implement stage; the only change is this spec.

Design note for the re-dispatch: a compact card's `requests` computed must not read `view().compact` when `drawn` feeds the view's `results` (circular). Compute compactness from the payload (`stateOf(incident().state)?.chip === 'closed'`) before building the context.

B13 (DW-1388): not run; no test was run.
