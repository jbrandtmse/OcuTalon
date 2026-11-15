---
title: 'Story 24.4a: Show setting values redacted everywhere, and the setting change in the evidence panel'
type: 'feature'
created: '2026-11-15'
status: 'draft'
baseline_revision: '1fc32ac5a2cb80e7be0c66800f34f8e58cf63cfd'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-24-context.md'
warnings: [oversized, multiple-goals]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Lane A's Stories 23.2, 23.3 and 23.5 are merged, and with them most of this story's display: every step-5 request already has its own dry run on the approval request card, the rail, the simulated phone and Telegram (Design Notes, "Already built"). Three parts are still missing:
- The evidence panel never lists the setting change that an incident names (AC3).
- The undo of a rollback, the one kind that can be asked for on a closed incident, gets no request card, because a closed (compact) incident card draws none (AC4).
- [AMENDED 2026-11-15, redactor ruling] A setting's values reach people raw. The rollback and undo dry run (card, phone, Telegram, web chat), their result notices and the incident's setting change carry the value exactly as IRIS holds it, so a setting whose value holds a secret (a URL with a token) shows it everywhere. Two Ens message bodies carry the raw values into the trace: `Fix.Msg.DryRunResult.DryRun` and the notices' `Msg.Notification.Slots` (Design Notes, "Trace and logs").

Nothing pins the step-5 cards end to end in a browser either: A12 to A14 check HTTP and two bands, not the rendered dry runs, the phone or the cause line.

**Approach:**
- Add the setting-change rows to the evidence panel.
- Let a compact card draw the request card of an `undo_rollback` request.
- [AMENDED 2026-11-15, redactor ruling] Redact on the SERVER with the one redactor, `OcuTalon.Bridge.Redact.Text`, wherever a setting's before, after, old or new value is shown: the approval payload's dry run, the incident payload's `settingChange`, and the slot fill of the four notice keys. The dry-run answer carries the redacted values and a hand-off reference to the raw ones, never the raw values. The stored dry run and the value the rollback writes stay raw. `Redact.Text` gains the one missing common secret shape (`key=`). No web redactor.
- Pin every AC on its outermost surface: one Playwright spec for the cards, the rail, the panel and the phone; two Telegram methods on the CI mock; a production test for the raw restore and the trace; unit pins for the rest.
- No payload field, route, catalog key, table, column or message property changes.

## Boundaries & Constraints

**Always:**
- The page decides nothing (AD-12). The card reads only the payload's fields (`settingChange`, `gapMinutes`, `requests`, the `approval` payloads) and renders text by interpolation only.
- Item names, setting names and values appear as the server sends them, in `mono`, in the evidence panel only (UX-DR78).
- The phone and Telegram text is the server's catalog text (AD-32). This story changes no catalog entry.
- Every new fixed string is in `INCIDENT_TEXTS` and in `ux-strings.test.mjs` with its ruling. Code uses ASCII escapes for any non-ASCII character (Rule 14).
- [AMENDED 2026-11-15, redactor ruling] Every setting value a person can see, and every Ens message body or log line that holds one, has gone through `OcuTalon.Bridge.Redact.Text` on the server. The stored `ApprovalRequest.DryRun`, the `SettingChange` row and the value the rollback or undo writes stay raw, byte for byte.
- Test fixtures build every secret-shaped value from fragments (no key-like string in a file). Tests seed fixture rows (`seedApproval`, `seedIncident`, `seedSettingChange`, `publishIncident`, `sendNotification`) and remove them, and the phone messages they made, in `finally`. They run on lane-D throwaways only.

**Never:**
- [AMENDED 2026-11-15, redactor ruling] No edit of a Lane A or bridge file beyond those the redactor ruling grants (`Live/Payload/Incident.cls` `Change`, the slot fill in `Watch/SettingCause.cls`, `Bridge/Redact.cls` for the pattern, and their test classes) and the NEW items under Veto items once ruled. `Channel/Telegram/*`, `Msg/Catalog/Watch.cls`, `Watch/Notice.cls` and the kind classes stay unedited. The Rule 19 mutations are applied and reverted byte-identical and never land.
- [AMENDED 2026-11-15, redactor ruling] No second redactor, in the web or anywhere else, and no redaction of the stored dry run, the `SettingChange` row or the value written.
- No new `/api/v1` route, live-event type, payload field, catalog key, table, column, message property or dependency.
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
| [AMENDED] Token-bearing value | a non-secret change whose `OldValue` is `https://feed.example.test/orders?token=<t>` | the payload's `oldValue`, the "Old value" row, the rollback card's After, the notices' `{after}` (web chat, phone, Telegram) all read `https://feed.example.test/orders?token=[redacted]`; `<t>` appears nowhere a person, the trace or a log sees | Redact fails closed (its UNCHECKED text) |
| [AMENDED] Plain value | `OrdersRouter` | shown byte for byte on every surface | No error expected |
| [AMENDED] Rollback of a token-bearing value | approved `rollback_setting` of that change | the item's setting is the raw token URL again, byte for byte; the stored dry run holds the raw values; every view is redacted | A failed hand-off take is a dry run that could not be worked out: nothing is raised, nothing stored redacted |
| Closed card, undo pending | incident `closed`, store holds a pending `undo_rollback` approval of it | the compact card draws that request card (dry run, Approve, Reject, expiry); its band is in its card only, never also in the compact bands | No error expected |
| Closed card, other kinds | incident `closed` with a repair or rollback request | no request card (A9 unchanged); the compact bands as today | Unchanged |
| Closed card, undo answered | the undo was rejected or is done | its card stays, with its status (and its band when it has a result) | No error expected |

</intent-contract>

## Code Map

All web paths are under `web/`. IRIS paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`.

**To change: the page (unchanged from the approved plan)**
- `src/app/incidents/incident-view.ts`: `INCIDENT_TEXTS` 34-79 (`labelCause` 61, `labelItems` 64); `IncidentContext` 88-108 (`itemTime` 98); `settingCauseOf` 262-272 (built); `itemLinesOf` 343-360; `panelOf` 362-391 (Cause row 364-367, the setting rows go after it); `bandsOf` 451-461; `incidentView` 472-505 (compact `results` 503).
- `src/app/incidents/incident-card.ts`: cause line 91-92, compact bands 111-113, request cards 114-127, own Show details 129-155, `requests` 312 (`compact ? [] : requestsOf(...)`).
- `src/app/incidents/evidence-panel.ts` 17-42: generic rows; no change unless lint asks.

**To change: the server redaction (redactor ruling)**
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls` (bridge, GRANTED): class doc 12-18 (names the patterns); `PatternList` 192-217, the `If kv` key rules 208-215; `KeyPattern` 225-238 (the SENSITIVEKEYS names; `key` is NOT one, and must not become one: `SensitiveKey` suffix-matches, so `monkey`, `cacheKey`, `dedupKey` would turn sensitive, and `TestSensitiveKeys` :50 pins 25 names).
- `Live/Payload/Approval.cls` (Lane B, in footprint; named by the grant): `FromRow` fix branch 144-153, `part.Before` 148 and `part.After` 149 (raw today). The `Kind = "setting"` branch 120-125 (`SettingText` 226-233) is a persona proposal (`Core/SettingsOps.cls:548-553`), not a production setting: not touched.
- `Live/Payload/Incident.cls` (Lane A, GRANTED): `Change` 116-134, `OldValue` 127 and `NewValue` 128 (raw today); doc 114-115.
- `Watch/SettingCause.cls` (Lane A, GRANTED; the slot fill): `RollbackSlots` 271-286 (before/after 277-278, set 283-284), `UndoSlots` 289-310 (298-299, set 307-308), `ResultSlots` 332-350 (after 337, set 347); private `Text` 383-386; class doc 13-14. `{reason}` of `result.settingSavedNotApplied` (338/348) is already redacted upstream (`Fix/Executor.cls:201,637`; `Fix/Run.cls:389`).
- `Watch/Notice.cls` (granted, NOT edited): it only delegates the fill: `AskedSlots` 243 → `UndoSlots`, `WithFixSlots` 344 → `RollbackSlots`, `ResultSlots` 446 → `SettingCause.ResultSlots`.
- `Fix/Executor.cls` (Lane A, NEW): `DryRun` 185-205 fills `DryRunResult.DryRun` from `dryRun.%ToJSON()` at 192 (raw before/after of the setting kinds).
- `Watch/IncidentManager.cls` (Lane A, NEW): the two receive sites of a `DryRunResult`: `Proposed` 970 (parse 991-995; raise `StoredDryRun` 1054) and the chat ask path (`AskDryRun` 1338-1343, parse 1191). `StoredDryRun` 1345-1360 keeps only `DRYRUNKEYS`. `ResultExtra` 1720-1738 reads `after` from the stored (raw) dry run at 1731; the redaction in `ResultSlots` covers it.
- `Fix/Msg/DryRunResult.cls` (Lane A, NEW, doc only): its doc 1-4 already allows "the kind's own transient keys ... which are never stored"; it names the new `values` key.

**Already built (read only, evidence)**
- Approval view: `src/app/approvals/approval-view.ts` `APPROVAL_TEXTS` 51-90, `itemDryRunView` 260-275, `settingDryRunView` 278-293, `rerouteDryRunView` 296-310, `dryRunView` 313-344, `partnerView` 359-376, `statusOf` 400-420, `approvalView` 423-455, `requestsOf` 213-226, `resultView` 575-650, `settingResultView` 683-700, `bandOf` 740-742. `approval-request-card.ts`: partner block 132-141, dry-run rows 146-175 (`.mono.before` 154, `.mono.after` 160), answer row 177+ (`aria-label` 183).
- Rail `src/app/rail/rail-view.ts`: titles 47-52, `showInChat` 57, `approvalTitle` 211-243, jump 269-275. Phone `src/app/phone/phone-request.ts` 40-52, `phone-view.ts` `blocksOf` 128 / `requestView` 158. Payload interfaces `src/app/live/payloads.ts` `SettingChange` 145-153, `settingChange`/`gapMinutes` 364-365 (generated; `npm run build` runs `--check`).
- IRIS: `Live/Payload/Part/DryRun.cls` 28-43 (Before/After MAXLEN 1000), `Part/SettingChange.cls` (Old/NewValue MAXLEN 2000); `Fix/Kind.cls` `AskedClosed` 156-162; `Fix/Kind/UndoRollback.cls` `MOVES` 26, `ASKEDSTATES` 28, `DryRun` 40-55, `Approved` 110-121 (reads the STORED dry run's raw `after` for a System Default Setting undo); `Fix/Kind/RollbackSetting.cls` `DryRun` 79-91, `Restored` 100-104, `Entry` 219-228 (the write reads the `SettingChange` row, never the dry run); `Watch/IncidentManager.cls:1076` (a closed incident takes only AskedClosed kinds).
- Catalog `Msg/Catalog/Watch.cls`: `incident.suspendRequest` 818, `resumeRequest` 827, `rerouteRequest` 836, `partnerRequest` 960, `rollbackRequest` 1129, `undoRollbackRequest` 1144, `settingChangeCause` 1155, `result.settingRestored` 1165, `result.rollbackUndone` 1182; `Msg/Catalog/Core.cls` `answered.*` 87, 106, 123, `audit.recorded` 619.
- Renderers that take the slots as given: `Channel/SimPhone/Out.cls:83-88` (stores `Data.SimMessage.Text`), `Channel/Telegram/Out.cls:174,212` (sends to Telegram); `Watch/Notice.cls` 244-258 (partner slots).
- `Core/SecretHandoff.cls` (Lane B Core, AD-19): `Put` 26, `Take` 52 (deletes the resource; a second take fails plainly), `Discard` 77.
- Payload consumers that read only Item, Field, To, Affected, ItemNoun (unaffected): `Core/AnswersIn.cls:111`, `Channel/Telegram/In.cls:477-481`.
- Leak helpers: `Test/Core/SecretHandoff.cls` `TraceLeaks` 240 (Ens.MessageBodyD/S, MessageHeaderD, Util.LogD), `Test/Agent/RunnerFixture.cls` `LogRowsHolding` 297; model `Test/Core/CommandsStep4.cls` `AssertNoLeak` 473.

**Tests to extend or add**
- Page: `scripts/incident-view.test.mjs` (setting cause 178-190, panel 380-437, compact 249-266 and 636-730); `scripts/incident-sources.test.mjs:199`; `scripts/approval-sources.test.mjs:316`; `scripts/ux-strings.test.mjs` `ruled` 813, entries of 23.3 at 1035-1050.
- e2e: model `e2e/rail/rail-answer.spec.ts` (`holdPolls`, `dropPhone`, `cleanFixtureRows`, `finally`); `e2e/support/approvals.ts` (`incidentOf` 40-61, `raise` 70-85, `phoneOf`/`messageOf` 87-88, `noticeOnPhone` 109-119, `phoneShows` 121-131); `e2e/support/iris.ts` (`irisScript` 108, `publishIncident` 182, `sendNotification` 684, `cleanFixtureRows` 704, `seedApproval` 776 with `dryRun.before/after`, `seedIncident` 1060, `seedSettingChange` 1101, `dropSettingChange` 1126); `e2e/support/scan.ts` `scanContrast` 149, `scanNames` 49; `e2e/cards/approval-card.spec.ts` A9 707, A12 389, A13 518, A14 468 (no new case in cards: `playwright-projects.test.mjs:331-336` pins 32).
- `Test/Bridge/Redact.cls`: `TestPatterns` 71, `TestPlainText` 221-229, `TestIdempotent` 231-246 (a hand-written list), `TestUrlCredentials` 333-343, `Check` 372 (asserts the result and that a second pass changes nothing).
- `Test/Watch/SettingCause.cls` (runs on a slot or a throwaway): fixtures `Change` 68, `Incident` 88, `Snapshot` 55; `TestPayload` 369-388.
- `Test/Watch/Rollback.cls` (throwaway and CI only, fresh): `ChangeRows` 202, `Request` 220, `Change` 230-252, `Prepare` 254, `Run` 412-450 (stores `answer.DryRun` as the fixture request's dry run at 423), `TestIncidentNamesTheChange` 578-634 (the real raise through `[[mock:diagnosis-rollback]]`), `TestUndoAfterClose` 636-673; `Test/Watch/Case.cls` `AskDryRun` 2257.
- `Test/Channel/TelegramOut.cls`: `TestButtons` 820 is the model (`Request` 808, `FixtureSlots`, `SentTo`).

## Tasks & Acceptance

**Execution (in dependency order):**
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls` -- In the `If kv` block, add the bare `key=` shape: a key named exactly `key` (any case), not preceded by a letter, digit, `_`, `.` or `-`, then optional spaces, `=`, optional spaces and a value, as the existing key rule takes a value (a run up to a space, quote, comma, semicolon or ampersand, or a quoted value with its quotes kept); the value becomes `[redacted]`. `:` is not a separator for it. Do not add `key` to SENSITIVEKEYS. Update the class doc's pattern list. -- The ruling's shapes: `user:password@` (207), `token=` and `access_token=` (key rule), `Bearer` (202) are present; plain `key=` (a Google-style `?key=`) is the one missing.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls` -- Add `TestSettingValueShapes`: through `Check`, `https://feed.example.test/orders?token=<t>&format=x` gives `...?token=[redacted]&format=x`; `?access_token=<t>` and `https://svc:<p>@feed.example.test/x` are redacted; the new `?key=<t>&x=1`, `key = <t>`, `KEY=<t>` and `key="a b"` are redacted; `monkey=1`, `keyboard=on`, `cacheKey=1`, `key: value` and a plain `OrdersRouter` are kept. Add a `key=` text to `TestIdempotent`'s list. Update the class doc's bullets. Fixtures from fragments.
- `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls` -- One private helper (name it, e.g. `Shown(value)`) returns `##class(OcuTalon.Bridge.Redact).Text(..Text(value))`. `RollbackSlots`, `UndoSlots` and `ResultSlots` set `before`/`after` from it, after their empty checks (which keep reading the raw value). Setting and target names stay as they are. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls` -- In `Change`, `part.OldValue` and `part.NewValue` are `Redact.Text` of the row's values; an empty value stays empty. Update its doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` -- In the fix branch, `part.Before` and `part.After` are `Redact.Text` of `dry.before` and `dry.after` (for every fix kind: suspend's "enabled"/"disabled" and repair dates are unchanged by it). The persona `Kind = "setting"` branch is not touched. Update the class or method doc.
- `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` (NEW, V5) -- In `DryRun`, for a kind whose `TARGETTYPE` is `setting`: offer `{"before", "after"}` (raw, as JSON) through `OcuTalon.Core.SecretHandoff.Put`, set the answer's `before`/`after` to their `Redact.Text` form and add the transient key `values` with the reference. A failed `Put` is a dry run that could not be worked out (the existing internal-error reason). Add one public class method (e.g. `TakeValues(dryRun As %DynamicObject) As %Status`) that takes the reference, puts the raw `before`/`after` back into the object and removes `values`; a dry run without `values` is left as it is (test doubles, other kinds). Every caller takes it at once, so no resource waits.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` (NEW, V5) -- Right after each `DryRunResult.DryRun` is parsed (in `Proposed` and on the chat ask path), call `TakeValues`. On failure, treat it like a dry run that could not be worked out on that path (the no-fix route, or the ask's refusal), with one redacted Type 3 warning; never raise with a redacted dry run. `StoredDryRun` then stores the raw values, as today.
- `src/ocutalon/cls/OcuTalon/Fix/Msg/DryRunResult.cls` (NEW, V5; doc only) -- The doc names the transient `values` reference of the setting kinds and that their `before`/`after` are redacted in the message. No property or storage change.
- `src/ocutalon/cls/OcuTalon/Test/Watch/SettingCause.cls` -- Add `TestShownRedacted`: with a fixture change whose old value is a token URL (from fragments) and one with plain values, (a) `Incident.FromRow(...).SettingChange` Old/NewValue are redacted and plain values unchanged, and the stored `SettingChange` row is raw; (b) `Approval.FromRow` of an in-memory `ApprovalRequest` (Kind fix, FixKind `rollback_setting`, then `undo_rollback`) has redacted `DryRun.Before/After`, and `row.DryRun` is unchanged; (c) `RollbackSlots`, `UndoSlots` and `ResultSlots` (`result.settingRestored`, `result.rollbackUndone`) give redacted `before`/`after`, and the catalog's phone text rendered from them holds `[redacted]` and not the token. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Rollback.cls` -- (1) `Run` takes the values of its `AskDryRun` answer (`TakeValues`) before it stores the fixture request, so fixture requests hold what IncidentManager would store. (2) Add `TestTokenValueRestoredRaw`: `Change(a, "Host", <token URL>, <plain URL>, ...)` through the real raise (`[[mock:diagnosis-rollback]]`, as `TestIncidentNamesTheChange`), then approve and execute the real request. Assert: the stored `ApprovalRequest.DryRun` `after` is the raw token URL; `Approval.FromRow` After, the incident payload's OldValue and the `incident.rollbackRequest` and `result.settingRestored` notices' slots and phone text are redacted; `Effective(...)` equals the raw token URL byte for byte; and `TraceLeaks(<t>)` is "", `LogRowsHolding(mark, <t>)` is 0, and no `Live.Event` Payload and no `Data.SimMessage` Text holds `<t>`. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls` -- Add `TestStepFiveRequests` (as approved: for each of `incident.suspendRequest`, `resumeRequest`, `rerouteRequest`, `partnerRequest`, `rollbackRequest`, `undoRollbackRequest`, kind `approval` with `FixtureSlots(key)`, the catalog's telegram text with no `parse_mode`, the last part with exactly Approve `approve:<ref>` and Reject `reject:<ref>`, and the partner text holding the whole notice and every recipient). Add `TestRedactedValue`: an `incident.undoRollbackRequest` whose slots come from `Watch.Notice.AskedSlots("undo_rollback", <dry run with a token URL>, <incident>)` is sent with `[redacted]` and without the token; each method on its own chat id.
- `web/src/app/incidents/incident-view.ts` -- Add the five strings of Public text to `INCIDENT_TEXTS`. In `panelOf`, right after the Cause row, add the rows from `payload.settingChange`: "Setting change" `{setting} on {item}` in mono; "Old value" and "New value" in mono, each left out when `credential` is true or its value is empty; "Detected" `ctx.itemTime(detectedAt)`, not mono, left out when unreadable. Rows show only when both `setting` and `item` are set. The values are shown as the server sends them (already redacted); the page redacts nothing. Export `AFTER_CLOSE_KINDS` (a `ReadonlySet` holding `undo_rollback`; its doc names `Fix.Kind.AskedClosed`). `IncidentContext` gains `drawn?: ReadonlySet<string>` (the request Refs the card draws as request cards); a compact card's `results` leave those out. Update the module doc.
- `web/src/app/incidents/incident-card.ts` -- `requests` becomes `compact ? requestsOf(...).filter(by AFTER_CLOSE_KINDS on fixKind) : requestsOf(...)`, with compactness computed from the payload (`stateOf(incident().state)?.chip === 'closed'`), not from `view().compact` (circular, since `drawn` feeds the view). Pass the drawn Refs into the context. Update the component doc.
- `web/scripts/incident-view.test.mjs` -- Pin each matrix row of the panel and of the compact card: rows, order, mono, the secret, an empty value, no change, a server-redacted value shown as given, an undo kept out of `results` only when drawn, the other kinds unchanged.
- `web/scripts/approval-sources.test.mjs` -- Change the `requests` regex at 316 to the new expression. `web/scripts/incident-sources.test.mjs` -- Pin that the drawn Refs reach the context.
- `web/scripts/ux-strings.test.mjs` -- Add one `ruled` entry with the five strings, citing the Planner's V1 ruling. Never an invented source.
- `web/e2e/support/iris.ts` -- Add `askedSlots(kind, dryRun, incidentRef)`: an `irisScript` that returns `Watch.Notice.AskedSlots(kind, dryRun, <the incident row>, .sc).%ToJSON()` (the real server fill), for `sendNotification`. Extend, don't copy: it reuses `irisScript`, `quoted` and `chk`.
- `web/e2e/rail/step5-requests.spec.ts` (new; sign-in-2 project, RAIL user, `workers: 1`) -- Cases F1 to F7 as the ACs describe; each cleans its rows, setting changes and phone messages in `finally`. Split into two files if one `--part` cannot hold it in about 150 s.

**Acceptance Criteria:**
- AC1 (FR-26, FR-8; UX-DR75, 77, 83, 113): Given a pending request of each kind (`suspend_item`, `resume_item`, `reroute`, `rollback_setting`, `undo_rollback`) in one incident, when the page shows it, then:
  - the request card shows that kind's own dry run;
  - a suspend or resume shows "Before" "{item}: enabled" and "After" "{item}: disabled" (swapped for a resume);
  - a reroute shows its count line and "Message {example}: {to}";
  - a rollback or undo shows "{setting}: {value}" rows, with plain values byte for byte;
  - the Before and After rows are text-labelled and in the mono font;
  - "Nothing has changed yet." shows;
  - Approve and Reject are named "Approve: {title}" and "Reject: {title}" with the rail's lower-cased title;
  - the rail row has that title;
  - the phone message of its catalog notice has the dry-run sentence and two buttons with the same names;
  - and Telegram, on the CI mock, gets the same catalog text with inline Approve and Reject on its last part.
  - Pins: F1 to F3 and `TestStepFiveRequests`.
- AC2 (FR-29; UX-DR136, 146): Given a pending `partner_warning` request with two recipients, when it shows on the card, the phone and Telegram, then the card's partner block shows "To: " with both "Name <address>" entries and the whole notice before the answer row (DOM order), and the phone message and the Telegram text hold the whole notice and both recipients as plain text, before the buttons. Pins: F4 and `TestStepFiveRequests`.
- AC3 (FR-27; UX-DR78, 146; Integration): Given a real `SettingChange` row and an incident that names it (`seedIncident` with `settingChangeRef`, first failure 4 minutes after `detectedAt`), when the page loads `/api/v1/state`, then the card shows "The feed broke four minutes after this setting changed: {setting} on {item}, at {time}.", and Show details lists the Setting change, Old value, New value and Detected rows, the first three in mono. Pin: F5.
- AC4 (FR-8, FR-26, NFR-9; UX-DR74, 76, 79): Given requests of the new kinds that are answered, expire, run or are offered for undo, when each happens, then each card shows "Approved from {channel} at {time}.", "Rejected from {channel} at {time}. Nothing was changed." or "Expired at {time}. Nothing was changed."; a done request's band is followed by "Recorded in the IRIS audit log."; a Reject pressed on the phone shows on the card within 5 s of the reply; an `undo_rollback` request appears as its own request card in the same incident, including on a closed incident; a closed card draws no other request kind (a pending repair or partner warning on it draws nothing); and the rail's "Show in the chat" of the undo jumps to its request card on the closed incident. Pins: F6 and the unit pins.
- AC5 (AD-12; UX-DR8, 33, 117; NFR-25): Given the web build, when it runs, then `payloads.mjs --check` passes (this story changes no interface); `ux-strings.test.mjs` covers every new string; in F5 and F6 the cards have no unnamed control and no contrast failure (`scanNames`, `scanContrast`) in both the light and the dark scheme; and Tab reaches Show details and the undo card's Approve, in that order, with a visible focus ring.
- AC6 (redactor ruling: the views; AD-31 Redaction; NFR-11): Given a non-secret setting change whose old value is a token-bearing URL, when it is shown, then the web approval card's rollback After (F3b), the evidence panel's "Old value" (F5b), the phone page's undo request message (F7) and the Telegram text (`TestRedactedValue`) read `...?token=[redacted]` and hold no token, while a plain value is shown byte for byte (F3, F5). Unit pins: `TestShownRedacted`.
- AC7 (redactor ruling: NOT redacted; AD-16): Given an approved rollback of a token-bearing value, when it runs, then the item's setting is the raw value again, byte for byte, the stored `ApprovalRequest.DryRun` holds the raw values, and every view of it is redacted. Pin: `TestTokenValueRestoredRaw`.
- AC8 (redactor ruling: trace and logs; AD-1, AD-19): Given that run, when it has ended, then no Ens message body, header or event-log row (`TraceLeaks`, `LogRowsHolding`), no stored live event payload and no phone message holds the token: `DryRunResult` carries the redacted values and a hand-off reference, and the notices' `Slots` the redacted values. Pin: `TestTokenValueRestoredRaw`.
- AC9 (redactor ruling: patterns): Given `Redact.Text`, when a text holds a URL `user:password@`, `token=`, `access_token=`, `key=` or `Bearer`, then the secret is `[redacted]`, the rest is kept and a second pass changes nothing; `monkey=`, `keyboard=`, `cacheKey=`, `key:` and plain text are kept. Pin: `TestSettingValueShapes`.
- Playwright cases (`step5-requests.spec.ts`): F1 suspend and resume; F2 reroute; F3 rollback and undo with plain values, and F3b a rollback whose seeded dry run holds a token URL (card After redacted, no token in the card's text); F4 partner warning; F5 the setting-change cause line and panel rows (AC3, AC5), and F5b a `seedSettingChange` with a token-URL old value (panel redacted); F6 answers, bands, the phone Reject within 5 s, the closed card's undo request card, no other kind on a closed card, and the rail jump (AC4, AC5); F7 an undo notice whose slots come from `askedSlots` on the phone page (redacted, no token).

## Spec Change Log

- 2026-11-15 (lead). **RE-PLAN RULINGS, Contest Planner ~22:00Z Nov 15 (BINDING)**, quoted in full:

  > ## RE-PLAN RULINGS (Contest Planner, ~22:00Z). BINDING.
  > 
  > ### V5: GRANTED
  > Lane D may edit:
  > - Fix/Executor.cls;
  > - Watch/IncidentManager.cls;
  > - Fix/Msg/DryRunResult.cls (doc only);
  > - the Test/Watch/Rollback helper.
  > 
  > Fix/Executor.cls is also changed by lane C's DW-1205, so the plain-union rule applies there.
  > 
  > How it works:
  > - DryRunResult carries the redacted values plus a Core.SecretHandoff reference.
  > - IncidentManager takes the raw values once, for the store.
  > 
  > CONDITIONS. Pin each of these:
  > - The handoff entry is deleted when it is taken.
  > - An entry that is never taken expires within SecretHandoff's existing limit.
  > - After a rollback, the Ens trace message bodies for that run (DryRunResult and Notification) contain the redacted marker and NOT the raw token.
  > - The undo of a System Default still works from the stored raw value, and the byte-for-byte restore pin still holds.
  > 
  > ### V4: CONFIRMED
  > - Web, phone and Telegram show "[redacted]", Redact.Text's existing marker.
  > - The new bare key= shape in Redact.Text is APPROVED, with its pin.
  > 
  > ### SPLIT: YES
  > - **24.4a** goes FIRST and is the 1.0.12 BLOCKER. It covers:
  >   - redaction on every display path;
  >   - V5;
  >   - the V1 panel rows.
  > - **24.4b** follows. It covers V2's closed-card undo and the cross-surface pins. It also targets 1.0.12, but does not block it.
  > - Charter both in epics.md with markers. The orchestrator re-records epics_md_hash at the merge.
  > 
  > ### Contention
  > At integrate, flag lane B's Paged hunk next to Change in Live/Payload/Incident.cls. Union the two and keep both.

  Applied by the lead: `epics.md` splits Story 24.4 into **24.4a** (this spec, renamed from `spec-24-4-...`; redaction on every display path, V5 and the V1 evidence-panel rows; the 1.0.12 blocker) and **24.4b** (V2's closed-card undo and the cross-surface pins; its spec is carved from this plan later), with `[AMENDED/ADDED 2026-11-15, Contest Planner split]` markers. Status reset to `draft` for a re-plan narrowed to 24.4a.

- 2026-11-15 (plan, re-plan iteration 2). Folded in the REDACTOR RULING. Intent amended (marked `[AMENDED 2026-11-15, redactor ruling]` at each change): the Problem names the raw values and the two message bodies; the Approach adds server redaction with `Bridge.Redact.Text`, the hand-off reference in the dry-run answer and the `key=` shape; Always adds the redaction and the raw store and write; Never replaces "no Lane A file" with the granted list (plus NEW V5 once ruled) and adds "no second redactor; nothing stored redacted"; the matrix gains the token, plain and restore rows. AC4 gains V2's two pins; AC6 to AC9 added for the ruling; F3b, F5b and F7 added. V1's five strings, V2 and V3 kept; the implement stage's note (compact from the payload) is in the card task. Found during the trace check: `Fix.Msg.DryRunResult.DryRun` carries the raw values and is needed raw by the store (`UndoRollback.Approved`), so the reference form needs `Fix/Executor.cls` and `Watch/IncidentManager.cls`, beyond the grant: flagged NEW V5.

- 2026-11-15 (lead). **REDACTOR RULING, Contest Planner ~21:30Z Nov 15 (BINDING; supersedes V1's condition; a 1.0.12 BLOCKER)**, quoted in full:

  > ## REDACTOR RULING (Contest Planner, ~21:30Z). BINDING. OPTION 2, EXTENDED, and a 1.0.12 BLOCKER
  > 23.3 shipped the exposure to feature, so it must close before the 1.0.12 cut. It supersedes V1's condition above.
  > 
  > ### One redactor, on the SERVER
  > Use OcuTalon.Bridge.Redact.Text, applied on the server everywhere a setting's before, after, old or new value is SHOWN:
  > 1. **Approval payload.** In Live/Payload/Approval.cls, the rollback's and the undo's Before and After.
  > 2. **Incident payload.** In Live/Payload/Incident.cls, Change, which feeds the new evidence-panel rows.
  > 3. **Notice texts** (web chat, phone page, Telegram). Fill these slots from the REDACTED value; the slot fill is in Watch/Notice and SettingCause:
  >    - incident.rollbackRequest and incident.undoRollbackRequest: {before} and {after};
  >    - result.settingRestored and result.rollbackUndone: {after};
  >    - any summary line that carries a value.
  > 4. **Trace and logs.** Check the Ens trace and the logs. If any message body carries the raw before or after, make it carry a reference or the redacted value instead, and pin that.
  > 
  > ### NOT redacted
  > The stored ApprovalRequest.DryRun and the value the rollback writes stay raw, because execution must restore the exact earlier value.
  > - Pin: a rollback of a token-bearing URL restores it byte for byte, while every view of it is redacted.
  > 
  > ### Pins
  > - A token-bearing URL is redacted on the web card, the phone page, the Telegram text and the evidence panel.
  > - A plain value is unchanged.
  > 
  > ### Grant
  > Lane D may edit Live/Payload/Approval.cls, Live/Payload/Incident.cls, and the slot fill in Watch/Notice and SettingCause, under this ruling.
  > 
  > ### Redact.Text patterns
  > If Redact.Text's patterns miss a common secret shape (URL user:password, token=, key=, Bearer), add the pattern IN Redact.Text itself, so logs benefit too. Write no second redactor in the web.
  > 
  > ### Contention
  > Lane B (23.8, the DW-1396 follow-up) and lane C (DW-1205) are also working in Watch and Fix. The rule is a plain union: whoever pushes second integrates and flags any overlapping hunks.

  The implement stage had blocked on V1's condition (no redactor existed: `RollbackSetting.DryRun` L86-90 stores raw values; `Live/Payload/Approval.cls` L122-123/L148-149 and `Incident.cls` `Change` copy raw; the web interpolates raw). Status reset to `draft` for a re-plan that folds this ruling in.

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

### Ground truth on the feature branch (HEAD 1fc32ac5; 23.2, 23.3, 23.5, 21.10, 21.11, 23.12, 36.1 and 36.2 merged)

| Kind | Raise (Lane A) | The row's dry run, as the `approval` payload carries it | Catalog key (Watch.cls) |
|---|---|---|---|
| suspend / resume | `ProposeFix` `suspend_item`/`resume_item` (Tools/WatchTools.cls:205) | `item`, `before`/`after` "enabled"/"disabled" (Approval.cls:150,148-149; DryRun.cls:28) | `incident.suspendRequest` 818, `resumeRequest` 827 |
| reroute | `reroute` (same) | `affected`, `resend`, `itemNoun`, `from`, `to`, `example` (Approval.cls:144-158; DryRun.cls:31-35) | `incident.rerouteRequest` 836 |
| roll back | diagnosis `rollback_setting` (Agent/Diagnosis.cls:34; Watch/SettingCause.cls) | `item`, `field`, `before` (now), `after` (old) (Approval.cls:147-150) | `incident.rollbackRequest` 1129 |
| undo | `ProposeFix` `undo_rollback`, also on a closed incident (UndoRollback.cls:26-28; Kind.cls:156-162) | the same keys, before old, after new | `incident.undoRollbackRequest` 1144 |
| partner warning | `partner_warning`, drafted (23.5) | `notice`, `recipients` ["Name <address>"], `simulated` (Approval.cls:127-138; DryRun.cls:37-43) | `incident.partnerRequest` 960 |

The incident payload carries `settingChange` and `gapMinutes` (Incident.cls:61-63, 116-134). All kinds raise on the feature branch; the new tests still seed fixture rows because they need no model or production and are deterministic. Lane A's own tests (`Test.Watch.Rollback`, `Test.Fix.ItemKinds`, `Test.Fix.PartnerWarning`) cover the real raise.

### Where a setting value reaches a person (redactor ruling, item 1; file:line)

| Surface | Fill site | Today | After |
|---|---|---|---|
| Web approval card, rail, `/api/v1/state`, answer response, approval live event | `Live/Payload/Approval.cls:148-149` (callers `Core/BridgeSink.cls:198,525`, `Web/Api.cls:830,1535`) | raw | `Redact.Text` |
| Web incident card and evidence panel, incident live event | `Live/Payload/Incident.cls:127-128` (callers `Web/Api.cls:1490`, `Watch/IncidentManager.cls:390,1445`) | raw (blank for a secret) | `Redact.Text` |
| `incident.rollbackRequest` {before} {after} (web chat, phone, Telegram) | `Watch/SettingCause.cls:277-278,283-284` via `Watch/Notice.cls:344` | raw | `Redact.Text` |
| `incident.undoRollbackRequest` {before} {after} | `Watch/SettingCause.cls:298-299,307-308` via `Watch/Notice.cls:243` | raw | `Redact.Text` |
| `result.settingRestored`, `result.rollbackUndone` {after} | `Watch/SettingCause.cls:337,347` via `Watch/Notice.cls:446`, from `Watch/IncidentManager.cls:1731` (the stored dry run's after) | raw | `Redact.Text` |
| `result.settingSavedNotApplied` {reason} | `Watch/SettingCause.cls:338,348` | redacted upstream (`Fix/Executor.cls:201,637`) | unchanged |
| Summary lines (`summary.requestedRollback`, `requestedUndoRollback`, `settingRestored`, `rollbackUndone`, `settingNotChanged`) | `Watch/Summary.cls:159-160,207-208` | no value (time, setting, target) | unchanged |
| Phone message store, Telegram send | `Channel/SimPhone/Out.cls:83-88` (`Data.SimMessage.Text`), `Channel/Telegram/Out.cls:174,212` | rendered from raw slots | rendered from redacted slots; no edit |
| Evidence pack to the model | `Watch/SettingCause.cls:169` | already redacted | unchanged |
| Digest, email, web chat bubbles | `Digest/NeedsYou.cls`, `Channel/Email/Out.cls:304`, `Channel/WebChat/Out.cls:51,82-83` | no value | unchanged |
| Telegram press reply, Telegram answer slots | `Channel/Telegram/In.cls:477-481`, `Core/AnswersIn.cls:111` | Field, Item, To, count only | unchanged |
| Persona proposal card (`Kind = "setting"`) | `Live/Payload/Approval.cls:120-125` | persona parts, not a production setting | unchanged (Decided 8) |

### Trace and logs (redactor ruling, item 4; file:line)

- **`Fix.Msg.DryRunResult.DryRun`** (Ens.Response) carries the raw `before`/`after` of the setting kinds: filled at `Fix/Executor.cls:192` from `RollbackSetting.cls:89-90` and `UndoRollback.cls:52-53`; received by `Watch/IncidentManager.cls` at 930 (async, `Proposed` 970) and 1340 (sync, chat ask), stored raw by `RaiseFix` at 1054. It is needed raw downstream (the store; `UndoRollback.Approved` 110-121 compares the stored `after`), so it gets a reference, not a lossy value: the redacted values plus a `SecretHandoff` reference that IncidentManager takes at once (V5).
- **`OcuTalon.Msg.Notification.Slots`** carries the raw values for the four keys: approval notices built at `Watch/IncidentManager.cls:1422` (rollback) and on the ask path (undo), result notices at 1684; sent through `Tell` 1896 → `SendNotice` 1862 → Notify → TelegramOut, SimPhoneOut, WebChatOut. Display only: fixed by the slot fill (granted).
- **`OcuTalon.Live.Event.Payload`** (persistent, not a message; `Live/Publish.cls:103-111`) stores the payload JSON: fixed by the payload redaction.
- No raw value in: `Fix.Msg.DryRun.Parameters` (`{"change": ref}`), `Fix.Msg.Execute` (ApprovalRef), `Fix.Msg.FixResult.Reason` (redacted at `Fix/Executor.cls:637`), `Bridge.Msg.ApprovalStart`/`ApprovalOutcome`/Workflow (Ref only), `Bridge.Msg.Request.Input` (the pack, redacted at `SettingCause.cls:169`), `Msg.Command.ProposeFix`/`CommandResult` (no values). The plan entry `{expect, value}` is passed in-process (`RollbackSetting.cls:187`), never in a message.
- **Logs and audit:** every log call on these paths already wraps its text in `Redact.Text` (`Watch/IncidentManager.cls` 1007, 1013, 1179-1214, 1566, 1712, 1886-1906; `Fix/Executor.cls` 201, 319-1354; `Fix/Run.cls` 234-389; `Watch/SettingHistory.cls` 44, 48), and their texts hold no value (refusal texts name setting, item and target only). The rollback's Action audit entry (`Fix/Executor.cls:785-831`) and the Approval entries (`src/bridge/cls/OcuTalon/Bridge/Approval.cls:569-619`) hold no value, and `Audit.Write` redacts anyway. No `$$$TRACE` or `$$$LOG` in the kinds, `SettingCause`, `Notice`, `Summary` or `Live`. No log line needs a change; `TestTokenValueRestoredRaw` pins it (`LogRowsHolding`).

### Decided in-stage

1. The new strings are page constants in `INCIDENT_TEXTS`, as the panel's other labels are ("Cause", "Error"). No catalog key, because the panel is page-only (UX-DR78).
2. Row order: right after Cause. Item and setting names and values in mono; the time not in mono, as the "Failures by item" times show.
3. "Detected", not "Changed": `detectedAt` is when a check saw the change, so the text claims only that.
4. A secret's value rows and an empty value's row are left out, with no new "hidden" text. The target (Host or Adapter) is not shown, because the AC names item, setting, values and time.
5. `AFTER_CLOSE_KINDS` copies the server's `AskedClosed` answer (`undo_rollback` only today), because the page cannot read the kind classes' parameters. A later kind with `closed` in `ASKEDSTATES` must be added there; the unit pin names the rule.
6. The new e2e spec lives in `e2e/rail/` (sign-in-2, which takes `--part`). `live cards` cannot be cut into calls of about 150 s. The rail user's session is cleaned in `finally`, as in rail-answer.spec.ts (23.12).
7. The redaction sits in `SettingCause` only (one private helper), because `Notice` only delegates the fill; `Watch/Notice.cls` stays unedited although granted. The empty checks keep reading the raw value, and `Redact.Text` never empties a non-empty value.
8. The approval payload redacts `Before`/`After` for every fix kind, not only the two setting kinds: one rule with no kind list, and it leaves "enabled"/"disabled" and dates as they are (Test.Live.Payloads :352, :850, :1154, :1172 stay green). The persona branch is not a production setting and stays as it is.
9. The `key=` shape is a pattern of its own, not a SENSITIVEKEYS name: a name there is suffix-matched in JSON keys, and `monkey`, `cacheKey` or `dedupKey` would turn sensitive across every log; `TestSensitiveKeys` pins 25 names. `=` only, so the prose "key: value" and JSON pairs keep their meaning. It sits in the `If kv` block with the other key rules (string values of JSON reach it through `Nested`). A prose "primary key = Ref" is redacted too (acceptable for a backstop).
10. A redacted value can be longer than the raw one (`token=ab` gives `token=[redacted]`); the payload parts' MAXLEN (1000 and 2000) is not enforced on JSON export, and the kinds refuse values over 1,000 characters (`VALUEMAX`), so no cut is added. The implement stage confirms export with a 1,000-character token URL in `TestShownRedacted`.
11. A failed hand-off take never stores a redacted dry run (that would change what `UndoRollback.Approved` compares and lose the raw value); it is treated as a dry run that could not be worked out.

### Governing ADs (Rule 6)

- AD-12: payloads with matching interfaces; the page decides nothing.
- AD-15: the incident's states. A closed incident takes only AskedClosed kinds, and its state is untouched here.
- AD-16: the dry run is the row's: the stored dry run stays raw.
- AD-19 and AD-1: a value kept out of messages travels by `SecretHandoff` reference (the step-4 pattern), taken once.
- AD-31 and the Consistency Conventions' Redaction row: one redactor, `OcuTalon.Bridge.Redact`, as the backstop.
- AD-29 and AD-33: lane files; the redactor ruling's grant and V5 are one-time exceptions.
- AD-32: the server renders the phone and Telegram text; producers never render.
- AD-25: the online demo.
- For the lead (Rule 20): the grant and V5, once ruled, are one-time AD-33 exceptions ("Story 24.4 changes Lane A's `Live/Payload/Incident.cls` `Change`, `Watch/SettingCause.cls`, `Bridge/Redact.cls` [and V5's files] and their tests, under the redactor ruling; the ownership tables don't change"), and the Redaction convention gains "a production setting's value shown to a person, or carried in a message, goes through the redactor on the server; the stored dry run and the value written stay raw".

### Integration ACs, Consumes, Extend (Rules 1, 2)

- **Integration ACs:** AC3 (a real `SettingChange` row through `Incident.FromRow` and `/api/v1/state` to the panel); AC6's F5b (the same path, redacted), F7 (the real `AskedSlots` fill through Notify to the phone page) and `TestRedactedValue` (the same fill through TelegramOut to the CI mock); AC7 and AC8 (`TestTokenValueRestoredRaw`, the running production end to end).
- **Consumes:** 23.3 (`settingChange`, `gapMinutes`, `incident.settingChangeCause`, the rollback and undo kinds and their slots); 23.2 (item and reroute dry runs); 23.5 (the partner part); 21.10 and 23.12 (the answer paths); Telegram Out's button rule; `Bridge.Redact.Text`; `Core.SecretHandoff`.
- **Consumed-by:** none (no service introduced; `TakeValues` is a helper of the dry-run answer, used by IncidentManager and the Rollback test helper).
- **Extend, don't copy:** the rows extend `panelOf`; the compact rule extends `requests`; the redaction reuses `Bridge.Redact.Text` (no second redactor) and `Core.SecretHandoff` (no second hand-off); the Telegram methods reuse `TestButtons`' helpers (`Request`, `FixtureSlots`, `SentTo`); the leak checks reuse `TraceLeaks` and `LogRowsHolding`; `askedSlots` reuses `irisScript`; the spec reuses `support/approvals.ts` and `support/iris.ts`. No helper is copied.

### Contention (redactor ruling; plain-union rule: whoever pushes second integrates and flags)

- Lane B (`OCT-epic23`, today Story 23.4's DW-1396 rework; 23.8 is still backlog): `Live/Payload/Incident.cls` adds `Do ..Paged(payload, row)` right after `Do ..Change(payload, row)` and a new `Paged` method directly above `Change`'s doc comment. This story edits `Change`'s doc (114-115) and body (127-128): adjacent hunks, a likely textual conflict on the doc lines; union keeps both. `Watch/IncidentManager.cls`: lane B's hunks are at 311, 1413, 1467, 1854 and 2010+; V5's edits are at 970-995, 1186-1194 and 1338-1360: no overlap expected. Lane B also edits `Channel/Telegram/Out.cls`, `Msg/Catalog/Watch.cls`, `Test/Live/Payloads.cls` and `Test/Msg/Catalog.cls`, which this story does not touch (its payload pins are in `Test.Watch.SettingCause` for that reason).
- Lane C (`OCT-epic21-dw1205`): `Test/Fix/Asked.cls` and `Test/Fix/PartnerDraft.cls`, not touched here. `Test.Fix.Asked`'s `DryRunResult` doubles (240-248) carry no `values` key, so `TakeValues` leaves them as they are; run it as a regression.

### Size and split (Rule 5)

The story now holds two independently shippable goals: the server redaction (a 1.0.12 blocker) and the card display. It stays one story, as the Planner made it. Recommended split line, NOT applied: **24.4a** = the redactor ruling (Redact pattern, payload and slot redaction, V5, the panel rows of V1, which depend on it; AC3, AC6 to AC9; F5, F5b, F7, `TestRedactedValue`, `TestShownRedacted`, `TestTokenValueRestoredRaw`, `TestSettingValueShapes`) and **24.4b** = the closed-card undo of V2 and the cross-surface pins (AC1, AC2, AC4, AC5; F1 to F4, F6, `TestStepFiveRequests`).

### Ledger (Rule 17)

`LEDGER slice 24-4-show-the-new-fixes-partner-warnings-and-setting-changes-on-t` is empty: no entry to address. Related, not owned: DW-1378 (escalated, owner burndown): a done undo's band reads `settingChange.newValue`, not the dry run's after; the fix needs a new request-part field (Lane A's payload), so this story declines it.

### Release and online demo

Target 1.0.12. On the online demo the setting history is off (36.1 V4), so no incident names a change, no rollback or undo is raised (ONLINESHARED), and none of the new rows, cards or redacted values ever shows there. The suspend, resume and partner cards are as today.

## Public text

**NEW** (V1; page constants in `INCIDENT_TEXTS`, evidence panel only):
- "Setting change"
- "{setting} on {item}"
- "Old value"
- "New value"
- "Detected"

**Existing server text, newly visible by the redactor ruling:** `[redacted]` (`Bridge.Redact` `REDACTED`) inside a shown value on the card, the panel, the phone and Telegram; and, when a value cannot be checked, `[redacted: the text could not be checked]` (`UNCHECKED`). Covered by the ruling (V4).

**Existing, reused verbatim (no change):**
- "Nothing has changed yet.": `APPROVAL_TEXTS.nothingYet`; EXPERIENCE.md:325.
- "Before" and "After": `APPROVAL_TEXTS`; UX-DR77.
- "Approved from {channel} at {time}.": Core.cls:87; EXPERIENCE.md:717. "Rejected from {channel} at {time}. Nothing was changed.": Core.cls:106; EXPERIENCE.md:718. "Expired at {time}. Nothing was changed.": Core.cls:123; EXPERIENCE.md:719. "Recorded in the IRIS audit log.": Core.cls:619; EXPERIENCE.md:738.
- "The feed broke {minutes} after this setting changed: {setting} on {target}, at {time}.": Watch.cls:1155 (23.3's gate; EXPERIENCE.md:1163).
- "Approve: {action}" and "Reject: {action}" (approval-view.ts:55-56), with the rail titles of rail-view.ts:47-52 (ruled at 23.2, 23.3 and 23.5).
- The six request keys' texts and the two result keys' texts (Watch.cls 818, 827, 836, 960, 1129, 1144, 1165, 1182): unchanged.

## Veto items

- **V1 (APPROVED 21:00Z): public text.** The five evidence-panel strings above; the condition is superseded by the redactor ruling.
- **V2 (APPROVED 21:00Z): card behaviour.** A closed card draws the request card of an `undo_rollback` request, and only that kind; EXPERIENCE.md line applied by the lead.
- **V3 (GRANTED 21:00Z): footprint.** `web/scripts/{incident-view,incident-sources,approval-sources,ux-strings}.test.mjs`.
- **GRANTED by the redactor ruling** (Lane A and bridge files; listed, not NEW):
  - `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls` (`Change`; Lane A).
  - `src/ocutalon/cls/OcuTalon/Watch/SettingCause.cls` (`RollbackSlots`, `UndoSlots`, `ResultSlots` and a private helper; Lane A). `Watch/Notice.cls` is granted and not edited.
  - `src/bridge/cls/OcuTalon/Bridge/Redact.cls` (the `key=` pattern and its doc; bridge, Lane A).
  - Their tests in Lane A test classes: `src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls` (`TestSettingValueShapes`, `TestIdempotent`'s list, the doc), `src/ocutalon/cls/OcuTalon/Test/Watch/SettingCause.cls` (`TestShownRedacted`), `src/ocutalon/cls/OcuTalon/Test/Watch/Rollback.cls` (`TestTokenValueRestoredRaw`, the ruling's restore pin).
  - `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` is named by the grant and is already in Epic 24's `paths_hint` (Lane B).
- **V4 (covered by the ruling, for the record): visible marker.** `[redacted]` and `UNCHECKED` reach the card, the panel, the phone and Telegram as part of a value.
- **V5 NEW: beyond the grant (Lane A files) and security posture.** The ruling's item 4 requires it: `Fix.Msg.DryRunResult.DryRun` carries the raw before/after into the trace, and is needed raw by the store.
  - Change: `src/ocutalon/cls/OcuTalon/Fix/Executor.cls` (`DryRun` answers redacted values plus a `SecretHandoff` reference in the transient key `values`; a new `TakeValues`), `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` (takes the values at its two receive sites; a failed take raises nothing), `src/ocutalon/cls/OcuTalon/Fix/Msg/DryRunResult.cls` (doc only), and `Test/Watch/Rollback.cls` `Run` (takes the values before storing its fixture request).
  - No message property, table, column or storage changes. `SecretHandoff` is Lane B's (read only here).
  - Online demo: none (no setting kind runs there).
  - If refused: AC8's `DryRunResult` half needs the Planner's alternative: (a) accept it as a known residual of the trace (purged with the trace), or (b) the message carries the redacted values and IncidentManager rebuilds the raw ones from the `SettingChange` row (exact for a rollback and a production-level undo; a System Default Setting undo's `after` is in no row, so that undo would need the production read again in IncidentManager).
- No new payload field, route, catalog key, table, column, role, grant, dependency or outward action.

## Verification

Every IRIS call runs from the worktree root with:

```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=24 stage=implement'
```

- The warm tag is `e24s4iw`; the fresh tag is `e24s4i`. Run IRIS MCP lookups only on `ocutalon-slot-d`/`OCUTALON`.
- Each line below is one foreground call (`timeout: 600000`) that ends inside about 150 s. One test class (or one `Class:Method`) per call. Never two test calls in one message.
- The web suite and each Playwright part are calls of their own. After any `web/` change, `ci/iris.sh build` comes before a browser unit.

**Shared surfaces:**
- `Redact.Text`'s output (used by logs everywhere). Every test that asserts it: `Test.Bridge.Redact` (all methods; `TestSensitiveKeys` :50 pins 25 names, unchanged); `Test.Bridge.Steps` (392, 437, 501), `Test.Bridge.Gate` (1789), `Test.Bridge.Runner` (303, 716, 777), `Test.Bridge.Audit` (233, 267, 361), `Test.Bridge.StepsText`, `Test.Agent.Steps` (253, 302), `Test.Agent.RenderMemory` (290, 383), `Test.Channel.TelegramOut` (`TestButtons` 889-891, `TestToolCallTooLong` 940-948), `Test.Core.BridgeSink` (918, 1159), `Test.Checks.Runs` (1708), `Test.Fix.DryRun` (526), `Test.Watch.Poller` (458), `Test.Watch.Evidence` (189, 213), `Test.Watch.NoticeText` (755, 768), `Test.Eval.Cases` (`FileProblems` 921-926, the fixed point over `eval/**`), `Test.Eval.Record` (560, 869, 1157), `Test.Tools.Reminders` (760), `Test.Demo.PartnerTrigger` (64). No fixture of them holds a bare `key=` (searched: Test classes, docker/tests, ci, web/scripts, web/e2e, eval); the e2e `redactLine` (`web/e2e/support/diagnose.ts:236`) is a separate test helper and unaffected.
- The values of the setting kinds' views (plain values, unchanged by redaction): `Test.Fix.Asked` 177, `Test.Fix.ItemKinds` 406-452, `Test.Watch.Rollback` 421, 609, 617-662, `Test.Watch.SettingCause` `TestPayload` 377-383, `Test.Channel.TelegramApproval` 414-420, `Test.Live.Payloads` 352, 850, 1154, 1172, `Test.Watch.Summary` 790, `Test.Msg.Catalog` 1861-1866, `approval-card.spec.ts` A14 472-494.
- The shape of `DryRunResult.DryRun` for the setting kinds (V5): `Test.Watch.Rollback` `Run` 420-423, `Test.Watch.Case` `AskDryRun` 2257, `Test.Fix.Asked` doubles 240-248.
- `INCIDENT_TEXTS` and the `ux-strings` inventory and `ruled` table; the panel rows of `incident-view.test.mjs` 380-437; the compact card's request list and `results` (`incident-view.test.mjs` 636-730, `incident-sources.test.mjs:199`, `approval-sources.test.mjs:316`, `approval-card.spec.ts` A9 in CI's `live:cards`).
- The RAIL user's session and phone feed (`rail.spec.ts` R1 to R19 expect them empty); TelegramOut's mock call log (each method its own chat id); `$SYSTEM.Event` hand-off resources (none may remain after a test).

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `npm --prefix web test` -- passes.
- (once) `npm --prefix web run lint` -- passes.
- (once) `npm --prefix web run build` -- passes, with `payloads.mjs --check`, `catalog.mjs --check` and no budget error.
- (once) `... OCUTALON_RUN_TAG=e24s4iw ci/warm.sh up` -- ready.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Bridge.Redact` -- `CLASS ... passed`.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Watch.SettingCause` -- passed.
- (loop) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Channel.TelegramOut` -- passed.
- (once) `... OCUTALON_WARM=1 OCUTALON_RUN_TAG=e24s4iw ci/iris.sh class OcuTalon.Test.Fix.Asked`, then (once) the same for `OcuTalon.Test.Fix.ItemKinds` and `OcuTalon.Test.Live.Payloads` -- passed (the V5 and payload regressions).
- (once) `... OCUTALON_RUN_TAG=e24s4iw ci/warm.sh down`.
- (once each, fresh) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh class OcuTalon.Test.Watch.Rollback:TestTokenValueRestoredRaw`, then `...:TestIncidentNamesTheChange`, `...:TestUndoAfterClose` and `...:TestUndoSystemDefaultChanged` (the stored `after` that `Approved` compares) -- each passed. A method that cannot end inside about 150 s is left to CI's `shards` group and recorded so.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh class OcuTalon.Test.Channel.TelegramOut` -- passes on a fresh stack.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh build` -- the image and the web bundle.
- (loop) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh live sign-in-2 --part k/N`, for the part that holds `rail/step5-requests.spec.ts`: find k/N with `npm --silent --prefix web run e2e:sign-in-2 -- --list --reporter=json` into the scratch folder, then `node web/scripts/e2e-part.mjs`; choose N so the part ends inside about 150 s (about 93 s of it is setup). Then (once) the part that holds `rail/rail-answer.spec.ts` and `rail.spec.ts`, as the shared-session regression. All pass.
- (once) `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-redact-shapes.sh` -- pass.
- (once) `... OCUTALON_RUN_TAG=e24s4i ci/iris.sh teardown`.
- (once, CI) `live:cards` (A9 and A12 to A14 stay green) and the `shards` group (every class of the shared surfaces above).
- (once, the lead) Fresh-environment check: the `--part` holding the spec, forward and `--reverse` (Rule 19), and `ci/iris.sh shard lane-a --part k/n` and `lane-b --part k/n` holding `Test.Bridge.Redact`, `Test.Watch.SettingCause` and `Test.Channel.TelegramOut`, forward and reversed.

**Mutations (Rule 19; record each as `mutation: … → …`; revert and check that `git status --short` and `git diff --stat` are unchanged):**
- AC1: swap `dry?.before` and `dry?.after` in `settingDryRunView` → F3 red. Remove `mono` from the `before` span → F1 red. Remove `approval` from `Out.cls` `BUTTONKINDS` → `TestStepFiveRequests` red (Lane A's file: revert `cmp`-identical; never lands).
- AC2: make `partnerView` join only the first recipient → F4 red.
- AC3: make `panelOf` skip the setting rows → F5 and the `incident-view.test.mjs` panel cases red.
- AC4: put back `compact ? []` in `requests` → F6 (closed undo) and the unit compact case red. Leave `drawn` out of `results` → the unit "no band twice" case red. Drop the `AFTER_CLOSE_KINDS` filter (draw every kind on a closed card) → F6's "no other kind" and its unit case red. Point the undo's request card id elsewhere → F6's rail jump red.
- AC5: drop the new `ruled` entry → `ux-strings.test.mjs` red. Set `.label` in `evidence-panel.ts` to `color: var(--surface)` → F5's dark-scheme `scanContrast` red.
- AC6: copy `dry.after` raw in `Approval.cls` → F3b and `TestShownRedacted` (b) red. Copy `change.OldValue` raw in `Incident.cls` → F5b and (a) red. Return `..Text(value)` from the `SettingCause` helper → F7, `TestRedactedValue` and (c) red.
- AC7: have `StoredDryRun` store the dry run without `TakeValues` (redacted values) → `TestTokenValueRestoredRaw`'s stored-raw assertion red. Have `RollbackSetting.Restored` return `Redact.Text(row.OldValue)` → its byte-for-byte assertion red.
- AC8: have `Fix/Executor.cls` `DryRun` keep the raw before/after in the message → `TestTokenValueRestoredRaw`'s `TraceLeaks` red.
- AC9: remove the new `key=` pattern → `TestSettingValueShapes` red; drop the "not preceded by" guard → its `monkey=1` case red.

**Manual checks:** none beyond the commands.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Re-plan (iteration 2) after the REDACTOR RULING. The previous run's block (V1's condition named a redactor that did not exist) is resolved by the ruling: server redaction with `OcuTalon.Bridge.Redact.Text`. One NEW item for the spec gate: V5 (the dry-run answer's raw values into the trace need `Fix/Executor.cls` and `Watch/IncidentManager.cls`, beyond the grant). Warnings: `oversized`, `multiple-goals` (split line recommended under Design Notes, not applied). B13 (DW-1388): not run; no test was run.
