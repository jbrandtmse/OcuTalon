---
title: 'A date repair that could read either way names its evidence'
type: 'feature'
created: '2026-11-03'
status: 'done'
baseline_revision: '181ea67c117f94c29dae51527cb9261044c8dc3c'
baseline_commit: '181ea67c117f94c29dae51527cb9261044c8dc3c'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A date written MM/DD/YYYY or DD/MM/YYYY whose two numbers are both 12 or less is a valid date both ways ("11/03/2026" is November 3 or March 11). `Fix.Reformat` converts whichever source format the model names, so for such values the choice of reading rests on the model alone, and neither the diagnosis nor the dry run says why (DW-644). The demo partner sends today's date as MM/DD/YYYY, so until Nov 13 every demo value reads both ways.

**Approach:** The Diagnosis prompt gets the evidence rule: propose `repair_resend` for dates that read both ways only when a reason names the evidence (a value with a day above 12, or the chosen reading matching, within one day either way, the day each failed message arrived). Without evidence the reply is a data-format diagnosis with no fix (V1). The dry run of `repair_resend` enforces the same rule in code over every target value and its header's arrival time, and refuses (no request) when the values read both ways and nothing singles out the source reading. When every value reads both ways and the arrival evidence holds, the notice uses a variant catalog key whose dry-run paragraph carries U-249's line. The stored dry run keeps exactly its seven keys.

## Boundaries & Constraints

**Always:**
- Terms (used everywhere below). The *order formats* are `MM/DD/YYYY` and `DD/MM/YYYY`; each is the other's *other order*. For a target value in an order format: it is *one-way* when it reads in the source format and not in the other order (its day in the source reading is above 12); it is *two-way* when it reads in both. A two-way value's two readings are the *same date* when its month equals its day. A value *matches* a reading when that reading's date is within `ARRIVALDAYS` (1) days, either way, of the UTC date of its own failed header's `TimeCreated` (the arrival; `Watch.Reader.Evidence`'s `timeCreated`, as stored).
- Evidence for the source format (RepairResend `Evidence`), over the dry run's targets only:
  - `n/a` when the source format is not an order format (the rule does not apply);
  - `oneway` when any target value is one-way;
  - otherwise `arrival` when every target value whose readings differ matches the source reading (its other reading then lies at least 26 days from its arrival, so it never matches too);
  - `same` when every target value's readings are the same date: accepted, without the line (Q1 ruled (a), veto U-250: a value whose two readings are the same date is not ambiguous);
  - otherwise `none`.
- The dry run of `repair_resend` refuses with an error status (so FixExecutor's `Reason`, and IncidentManager's existing no-fix route: `incident.noFix` for the first request, V2 of 7.6 for a later round) exactly when `Evidence` is `none`.
- The dry run's example (`before`/`after`) is the first target whose value is one-way, else the first whose readings differ, else the first target (for a source that is not an order format: the first target, as today). So a raised request's `before` reads two ways with different readings exactly when every target value does.
- The notice uses `incident.withFixEitherWay` (later round: `incident.laterRequestEitherWay`) exactly when the request's source format is an order format and its dry run's `before` reads both ways with different readings; it then adds the slots `reading` ("month first" for `MM/DD/YYYY`, "day first" for `DD/MM/YYYY`) and `item` (the one form of the notice's `itemNoun` slot: the incident's noun, else the code noun, "message" when unknown). Otherwise the key is `incident.withFix` / `incident.laterRequest`, unchanged.
- U-249's line is the only new user-facing text, verbatim (Design Notes). Its `{count}` is the entry's `resendCount` slot (every target value reads both ways when it shows); this is the only fitting of the wording to slot names and types.
- The Diagnosis prompt stays static `XData INSTRUCTIONS` with no `{{` (AD-7). The reply check stays the bridge's alone (AD-8); no code parses a reason's wording.
- A data-format diagnosis may carry no fix (V1): then `fixKind`, `fixParameters` and `fixSummary` are all absent or empty; any one of them alone is still refused. Its notice is `incident.noFix` with its cause (open variant `no_fix`), and no dry run is asked.
- Producers send keys and slots, never text (AD-32). New catalog entries are one self-contained block right after the `incident.laterRequest` entry of `Msg/Catalog/Watch.cls`; no existing key's text changes.
- `Fix.Reformat` stays pure (no database, namespace or SQL; a value is only matched and cut, never evaluated; `Test.Fix.Reformat.TestStaticScan` keeps passing). Rule 14: ASCII escapes in code; comments state the contract.
- Tests run only on lane-B throwaways (warm for pure classes, fresh for production-driven ones), against the CI mock. No real model key, no Telegram.

**Never:**
- No change to `Bridge.Data.ApprovalRequest` `DRYRUNKEYS` or to any stored dry run's keys, to `Fix/Msg/**` (AD-16 lists their properties), to `RepairResend.CheckParameters` or `Fix.Kind.Check` (the eval demo gate's `parametersValid` calls them with field names only), or to the reply check's `CheckFix`.
- No edit to a contended path: `web/**`, `Channel/**`, `Core/**`, `Live/**`, `Msg/Catalog/Core.cls`, `Msg/Enum.cls`, `Test/Data/Tables.cls`, `src/bridge/**`, `ci/mock/test/constants.test.mjs`; `Demo/**`, `eval/**` and the e2e specs are read only. Nothing under `Install/**`, `docker/**`, `src/module.xml`, `src/cpf/**`, `install.sh`, `ci/units.sh` or the workflows.
- No new eval case and no change to any recorded eval case or its expectation.
- No other wording change; no time-zone conversion of the arrival (UTC date of `TimeCreated` plus the one-day tolerance is the whole rule).
- Nothing of another story; no AD edit; no `[Language = python]`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Arrival evidence, instance date differs from UTC date (U-249 Condition 2; DW-644) | 3 real failed orders, `orderDate` 2026-11-03 written MM/DD/YYYY (the instance-local date of an ET press at 21:00), each failed header's `TimeCreated` set to 2026-11-04T02:00:00Z; the default mock diagnosis (MM/DD/YYYY to YYYY-MM-DD) | One pending repair_resend request over the 3 ids; one `incident` Notification per recipient with key `incident.withFixEitherWay`, slots `reading` "month first", `item` "order", `resendCount` 3; its phone text holds "Example: order date 11/03/2026 becomes 2026-11-03. All 3 dates are valid whether read month first or day first. Read month first, they match the day each order arrived. I'll resend 3 repaired copies;". The mock logs only the diagnosis requests. Pin: `Test.Fix.EitherWay.TestDemoRepairWhenInstanceDateIsNotUtcDate` | none |
| The press writes the instance-local date | `Partner.Orders` with an empty date under a process `$ZTIMEZONE` chosen so that the local date differs from the UTC date | each order's `OrderDate` is the MM/DD/YYYY of the local date and differs from the UTC date's. Pin: `Test.Fix.EitherWay.TestPressWritesTheLocalDate` | none |
| Only ambiguous dates, arrival evidence (dry run) | 3 failed orders 11/03/2026, arrival 2026-11-03T15:00:00Z | targets all 3, no `Reason`, `before` "11/03/2026", keys exactly DRYRUNKEYS. Pin: `Test.Fix.DryRun.TestEitherWayWithArrival` | none |
| A day above 12 (line absent) | the existing 50 orders 10/16/2026 (`Test.Watch.Diagnose.TestDemoDiagnosis`, unchanged) | `incident.withFix`, its exact Dry run paragraph unchanged (no line), request raised. Pin: `Test.Watch.Diagnose.TestDemoDiagnosis` (`AssertWithFix` L194, L201) | none |
| Mixed one-way and two-way | failed orders 11/03/2026, 11/13/2026, 11/03/2026, arrival 2026-12-20T12:00:00Z (no arrival match) | accepted (`oneway`); `before` "11/13/2026"; the notice is `incident.withFix` (no line). Pins: `Test.Fix.DryRun.TestOneWayIsTheExample`, `Test.Watch.NoticeText.TestEitherWay` | none |
| Negative: ambiguous, no matching evidence | 3 failed orders 03/05/2026, arrival 2026-11-04T02:00:00Z, the default mock diagnosis proposing repair_resend | dry run refused (`Reason` starts "The dates read as valid dates both month first and day first"); no request; the incident is noticed open `no_fix` with `incident.noFix` and its cause; one Type 3 warning (LOGPROPOSE). Pins: `Test.Fix.DryRun.TestNoEvidenceIsRefused`, `Test.Fix.EitherWay.TestNoEvidenceNoRequest` | logged |
| Negative: the reply proposes no fix (V1) | a synthetic failure carrying `[[mock:diagnosis-noevidence]]`: data_format_change, elementAtFault OrderDate, no fixKind, fixParameters or fixSummary | accepted (no fallback); `incident.noFix` with the cause; no `DryRun` header; no request. Pin: `Test.Watch.Diagnose.TestNoEvidenceReply`; payload row `Test.Watch.Payload.TestPayloadAccepted` | none |
| Both readings match within a day (U-249 Condition 1; Q1 ruled (a), veto U-250) | 3 failed orders 11/11/2026, arrival 2026-11-11T15:00:00Z | accepted (`same`): request raised with `incident.withFix`, no line (the two readings are one date, so nothing is chosen silently). Pins: `Test.Fix.DryRun.TestBothReadingsMatch`, `Test.Fix.EitherWay.TestBothReadingsMatch`, `Test.Fix.Reformat.TestEvidence` | none |
| Tolerance edges | value 11/03/2026 with arrivals 2026-11-02, -03, -04 (match) and 2026-11-01, -05 (no match), each at 23:59:59Z and 00:00:00Z | `arrival` for the first three, `none` for the last two | none |
| Day first | source DD/MM/YYYY, value 03/11/2026, arrival 2026-11-03 | `arrival`; `reading` "day first"; one value: the one form "The date is valid whether read month first or day first. Read day first, it matches the day the order arrived." | none |
| Unknown noun | dry run `itemNoun` {message, messages} | `item` "message" | none |
| Later round | a later round's dry run over two-way values with arrival evidence | key `incident.laterRequestEitherWay`, kind approval, the line in its Dry run paragraph; no evidence: V2 of 7.6 (nothing sent, one warning) | logged |
| Not an order format | source YYYY-MM-DD, DD.MM.YYYY, YYYYMMDD or a number format | `n/a`: unchanged behaviour and keys | none |
| Arrival unreadable | a target with an empty or malformed `timeCreated` | that value never matches (fail closed) | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated. Lines as of `eeae8cba458cfb2d73ac6099d426926e979d03ce`.

**Changed (footprint):**
- `Agent/Diagnosis.cls` INSTRUCTIONS L20-45: key list L29-40 (`fixKind` L34, `fixParameters` L35, `fixSummary` L37), the format rule L42-43. The new bullets go after L43.
- `Fix/Reformat.cls`: `Reads` L56 and private `ParseDate` L67-84 (the shapes, the `$ZDateH(..., -1)` calendar check). `Readings` extends `ParseDate`.
- `Fix/Kind/RepairResend.cls`: `DryRun` L103-196 (the snapshot loop L128-135 keeps `scoped(id)` and `classes(id)`; add the arrival from `failure.timeCreated`; the target loop L155-166 picks the example L161-165); `Readable` L293. `CheckParameters` L35 stays unchanged.
- `Test/Fix/Reformat.cls` (pure): `TestConvertsDates` L40, `AssertTable` L51, `TestStaticScan` L184.
- `Test/Fix/DryRun.cls` (fresh; extends `Test.Watch.Case`): `Params` L48, `TestFiftyOrdersChangeNothing` L100 (DRYRUNKEYS L145), `TestLeftOutAndScope` L152 (the `SetOrderDate` pattern).
- `Test/Watch/Diagnose.cls` (fresh): `TestDemoDiagnosis` L62, `AssertWithFix` L148 (L194 key, L201 paragraph), `TestDiagnosisVariants` L234 (marker scenarios `diagnosis-nofix`, `diagnosis-unknown`), the synthetic `SendBatch` pattern L330.
- `Test/Agent/Instructions.cls` `TestDiagnosis` L133; `Test/Agent/RunnerFixture.cls` `DIAGNOSISTEXT` L90 (an exact copy of `ci/mock/scenarios/A/diagnosis.json`'s reply text; `Test/Agent/Runners.cls` L294 asserts it).

**Footprint extensions (not contended; name each in the commit):**
- `Watch/Msg/DiagnosisPayload.cls` `%OnValidateObject` L59-87 (the data_format_change branch L69-74) for V1.
- `Watch/Notice.cls`: `Key` L88, `WithFixSlots` L136 (count/time use `$Data`, 7.6), `Common` L241; parameters L37-48.
- `Watch/IncidentManager.cls` `Proposed` L867: slots L897-902, the later key L927, the first key L932.
- `Msg/Catalog/Watch.cls`: `incident.withFix` L78-98, `incident.laterRequest` L99-118 (the new block goes right after L118, before `incident.fallback`). Contended by Epic 33 only for its `digest.*` block: one appended block is a plain union (project block).
- `ci/mock/scenarios/A/diagnosis.json`, `diagnosis-late.json` (reasons), and a new `diagnosis-noevidence.json` (pattern: `diagnosis-nofix.json`). The mock picks by marker, then mock key; a date never selects a reply (`ci/mock/mock.mjs` L25-41, `select()` L422-451). `ci/mock/test/scenarios.test.mjs` derives its counts from the folder.
- `Test/Watch/Case.cls`: `Fail` L717, `SendOrders` L728 (`Partner.Send(count, "MM/DD/YYYY", traceRef, "2026-10-16")`), `WaitFailed` L750, `HeaderIds` L763, `Raised` L1589, `DropIncidentRows` L1666, `SetOrderDate` L2021, `AskDryRun` L2088.
- `Test/Watch/NoticeText.cls` (warm): `Row` L67, `Render` L203, `TestKeysAndVariants` L210, `TestWithFix` L268, `TestLaterRequest` L318.
- `Test/Watch/Payload.cls` (pure): `TestPayloadAccepted` L120, `TestPayloadRefused` L139 (its one-at-a-time loop L156-159 stays green under V1).
- `Test/Msg/Catalog.cls` (contended; ruled a plain-union append, Design Notes): `TestEntries` L74 (L80-83 counts and key sets, doc L3), the fixture message L121 ("123 keys"), `TestCountOfOneForms` L543 (L554 "9"), XData `Keys` L952, `OneForms` L1095, `Fixtures` L1199.

**Read only, evidence:**
- `Watch/Reader.cls` L372: each Evidence failure carries `timeCreated` (`Ens.MessageHeader.TimeCreated`, `Ens.DataType.UTC`, set by `$$$timeUTC` = `$zdatetime($ztimestamp,3,,3)`) as `YYYY-MM-DDThh:mm:ssZ`.
- `Watch/EvidencePack.cls` L4-5, L167: the model sees `firstAt`, `lastAt` and the sample's `at` (timeProcessed, UTC).
- `Fix/Executor.cls` L152-175: a kind's error status becomes `DryRunResult.Reason` (redacted, at most 1000).
- `Watch/IncidentManager.cls` L752 `Notice` (Key "" -> `Propose`), L777 `Propose`, L867-950 `Proposed` (Reason -> `Decline` -> `NoFix` L976), L1005 `Notification`.
- `Watch/ItemNoun.cls` L7-10: `PartnerOrder` = order/orders, DEFAULT message/messages.
- `Demo/Orders/Partner.cls` L29 `Orders` (public), L41-42 empty date = `$ZDATE($HOROLOG, 3)`, L50 MM/DD/YYYY, L83 `Send` (in-process `CreateBusinessService` + `ProcessInput`). `Demo/PartnerTrigger.cls` L17 DATEFORMAT MM/DD/YYYY, L67-75 empty date.
- `Live/Payload/Approval.cls` L85-103 maps the stored dry run key by key (the web card reads only these fields); `web/src/app/approvals/approval-view.ts` L40-44, L181 builds the card's dry run from them.
- `Channel/SimPhone/Out.cls` L57-63, `Channel/Telegram/Out.cls` L125, `Channel/SimMailbox/Out.cls` L42 render `CatalogKey` + `Slots`; no consumer keys on the name `incident.withFix` (grep of `Channel`, `Core`, `Live`, `Web`, `web/src`).
- `Eval/Report.cls` L417-425 scores causeCategory and elementAtFault only; `Eval/Gate.cls` L139-195 (demo gate: `orders-date-format`, `Fix.Kind.Check` with field names); `eval/orders-date-format`: 50 x "10/16/2026", arrival 2026-10-20 (day 16: `oneway`).
- `web/e2e/support/demo-path.ts` L296-322 finds the phone notice by its buttons and checks the web card's `.dry-count`; `web/e2e/answers/answers.spec.ts` L136-157 renders its own `incident.withFix` fixture (unchanged key).

## Tasks & Acceptance

**Execution:**
- Task 0 (implement stage; record each result under Verification):
  - (a) Measured at plan (slot B, read only): `$ZTIMEZONE` is per process and moves `$HOROLOG`, not `$ZTIMESTAMP` (see Verification). Re-check nothing.
  - (b) On the first fresh run of `Test.Fix.EitherWay`: the seconds from `WaitFailed` returning to the dry run's `DryRun` header (the margin for `SetArrival`). Expected (inference): 5 to 10 s. Under 3 s: move `SetArrival` before `WaitFailed`, onto the headers the partner service created for the batch (a marker such as `diagnosis-late` cannot ride on real orders), and record it.
  - (c) The class time of `Test.Fix.EitherWay` on a fresh stack; over about 180 s, split it in two classes.
- `Fix/Reformat.cls` -- add `OtherOrder(format)` ("DD/MM/YYYY" for "MM/DD/YYYY" and back, else "") and `Readings(value, format, Output source, Output other) As %Boolean`: 1 when the value reads in the format and in its other order (both through `ParseDate`, so `Reads`' length and emptiness checks apply), with `source` and `other` the `$ZDateH` day numbers of the two readings; else 0. Update the class doc. -- Rule 2: extends `ParseDate`/`Reads`; no second parser.
- `Fix/Kind/RepairResend.cls` -- (1) `Parameter ARRIVALDAYS = 1;`. (2) Public pure `Evidence(values As %DynamicArray, format As %String, Output twoWay As %Integer) As %String`: `values` holds `{"value", "arrived"}` (arrived UTC `YYYY-MM-DDThh:mm:ssZ`); it returns `n/a`, `oneway`, `arrival`, `same` or `none` per Always (Q1 ruled (a): a set whose every value reads the same date both ways gives `same`, accepted; `arrival` needs at least one value whose readings differ), and `twoWay` counts the two-way values (the AC's count). An empty or malformed `arrived` never matches. (3) `DryRun`: keep each scoped failure's `timeCreated`; after the target loop, call `Evidence` over the targets' values; `none` returns `$$$ERROR($$$GeneralError, "The dates read as valid dates both month first and day first, and nothing shows which: no date has a day above 12, and the dates do not all match, within a day, the day their message arrived")`; pick the example per Always. (4) Update the class doc (the evidence rule, the example rule, the refusal). -- AC 2, AC 3; DW-644.
- `Agent/Diagnosis.cls` -- INSTRUCTIONS: the `fixKind` bullet becomes `"fixKind": "repair_resend" only for a data_format_change that has a fix (see the dates that read both ways, below), otherwise leave it out.`; add after L43 the bullet: `- Dates that read both ways: a date written "MM/DD/YYYY" or "DD/MM/YYYY" whose day and month are both 12 or less is a valid date read month first and read day first. When the failed values of a date field read both ways, use "repair_resend" only if one of your reasons names the evidence for the source format: a failed value whose day is above 12 in that reading, so that it reads only one way, or that reading matching, within one day either way, the day each failed message arrived (the times in the evidence pack, "at", "firstAt" and "lastAt", are UTC). When both readings match the day a message arrived, that is no evidence. A date whose day and month are the same number reads as one date, so it needs no evidence. Without evidence, keep "causeCategory" "data_format_change" and "elementAtFault", leave out "fixKind", "fixParameters" and "fixSummary", and say in a reason that the date order cannot be told.` No `{{`. -- AC 1.
- `Watch/Msg/DiagnosisPayload.cls` (V1) -- in the data_format_change branch: when `FixKind`, `FixParameters` and `FixSummary` are all absent or blank, accept (elementAtFault still required, no `CheckFix`); otherwise the existing checks in their order. Update the class doc. -- AC 4.
- `Watch/Notice.cls` -- (1) `Key`: a data_format_change whose `FixSummary` is blank gives `KEYNOFIX` (so `Variant` gives no_fix and `Notice` sends it without `Propose`). (2) Parameters `KEYWITHFIXEITHER` ("incident.withFixEitherWay"), `KEYLATEREITHER` ("incident.laterRequestEitherWay"), `READINGS` ("MM/DD/YYYY:month first,DD/MM/YYYY:day first"). (3) `WithFixKey(dryRun, parameters, later = 0) As %String` per Always. (4) `WithFixSlots(..., count, time, parameters)`: a trailing optional `parameters` (JSON text or object); when `WithFixKey` would give an either-way key it adds `reading` and `item`. (5) Update the class doc (the key table and the slots). -- AC 3, AC 4; Rule 2: extends the with-fix builder.
- `Watch/IncidentManager.cls` -- `Proposed`: pass `ask.Parameters` to `WithFixSlots` (L899, L901) and take the key from `Notice.WithFixKey(dryRun, ask.Parameters, later)` (L927, L932); update the method and class docs. -- AC 3.
- `Msg/Catalog/Watch.cls` -- one block right after `incident.laterRequest`: `incident.withFixEitherWay` and `incident.laterRequestEitherWay`. Each copies its parent's `text`, `web`, slots, `source` and one form exactly, adds the slots `"reading": "text"` and `"item": "text"`, and inserts after "Example: {field} {before} becomes {after}." (same paragraph, one space): many form `All {resendCount} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived.`; one form (slot resendCount) `The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived.`. `source`: the parent's, followed by `; dry-run line: U-249 (owner delegate, 2026-11-03)`. -- AC 3.
- `ci/mock/scenarios/A/diagnosis.json` and `diagnosis-late.json` -- keep every field; the `reasons` become `["The failed orders all hold an order date in the new format.", "Read month first, each order date matches the day its order arrived, within a day, or has a day above 12; read day first, it does neither.", "The CI mock read the failed messages."]`. New `diagnosis-noevidence.json` (marker `diagnosis-noevidence`): `{"outcome":"act","causeCategory":"data_format_change","elementAtFault":"OrderDate","evidence":["failed_messages","OrderDate"],"cause":"The partner now sends the order date with slashes, and the production expects year, month and day with dashes.","itemNoun":{"one":"order","other":"orders"},"reasons":["The order dates read as valid dates both month first and day first, and no date has a day above 12 or matches the day its order arrived, so the date order cannot be told."],"confidence":0.6}`. -- AC 1, AC 4, AC 5.
- `Test/Agent/RunnerFixture.cls` -- `DIAGNOSISTEXT` = the new `diagnosis.json` reply text exactly. -- shared surface.
- `Test/Watch/Case.cls` -- `SendOrders(count, traceRef, orderDate = "2026-10-16")` and `Fail(count, traceRef, orderDate = "2026-10-16")` (default unchanged); new `SetArrival(headerId, utc) As %Status` beside `SetOrderDate` (OCUORDERS, `Ens.MessageHeader` `TimeCreated` := the UTC time as stored, `YYYY-MM-DD hh:mm:ss`). Update the class doc. -- Rule 2.
- `Test/Fix/Reformat.cls` -- `TestReadings` (two-way, one-way both directions, same date, not an order format, malformed, empty) and `TestEvidence` (every `Evidence` outcome; the tolerance edges row; the instance-vs-UTC row: 11/03/2026 arrived 2026-11-04T02:00:00Z is `arrival`; the Q1 row: 3 x 11/11/2026 arrived 2026-11-11T15:00:00Z is `same`, and 11/11/2026 with 03/05/2026 arrived 2026-11-04T02:00:00Z is `none`; unreadable arrival; `twoWay` counts). Class doc. -- pure.
- `Test/Fix/DryRun.cls` -- fresh rows `TestEitherWayWithArrival`, `TestOneWayIsTheExample`, `TestNoEvidenceIsRefused`, `TestBothReadingsMatch` (accepted: targets all 3, no `Reason`, `before` "11/11/2026") (per the matrix; `Fail(n, super, orderDate)`, `HeaderIds`, `SetArrival`, `Fixture`, `AskDryRun`). Class doc.
- `Test/Fix/EitherWay.cls` (new; extends `Test.Watch.Case`; fresh; Area `Fix`, so `lane-a@rest` runs it with no units entry; class doc per Rule 14) -- `TestDemoRepairWhenInstanceDateIsNotUtcDate` (Integration AC: the real diagnosis on the default mock, the real dry run, `Approval.Raise`, the delivered Notification and its phone text, `LogSince` with only the diagnosis requests), `TestNoEvidenceNoRequest`, `TestBothReadingsMatch` (3 x 11/11/2026 arrived 2026-11-11T15:00:00Z: one pending repair_resend request, the notice `incident.withFix` with no `reading` or `item` slot, its phone text without "whether read month first or day first"), `TestPressWritesTheLocalDate` (in OCUORDERS: `$ZTIMEZONE` := -840 when the UTC hour is 12 or later, else 720; `Partner.Orders` with an empty date; restore `$ZTIMEZONE`). Rows go with `DropIncidentRows`.
- `Test/Watch/Diagnose.cls` -- `TestNoEvidenceReply` (V1, the synthetic `SendBatch` pattern with `[[mock:diagnosis-noevidence]]`): no fallback, row category data_format_change and no fix summary, the notice `incident.noFix` with the cause, no `DryRun` header, no request. Class doc.
- `Test/Watch/NoticeText.cls` -- `TestEitherWay` (pure): `WithFixKey`/`WithFixSlots` for the matrix rows Day first, Unknown noun, Mixed (before 11/13), 10/16, 11/11, YYYY-MM-DD; `Render` of both new keys on telegram, phone and web, many and one forms, equal to the `Test.Msg.Catalog` fixtures; `TestKeysAndVariants` gains the fix-less data_format_change row (V1).
- `Test/Watch/Payload.cls` -- `TestPayloadAccepted` gains the fix-less data_format_change reply; `TestPayloadRefused` keeps its rows. Class doc.
- `Test/Agent/Instructions.cls` -- `TestDiagnosisEvidence`: INSTRUCTIONS hold `"MM/DD/YYYY" or "DD/MM/YYYY"`, `a day above 12` (as "day is above 12"), `within one day either way`, `the day each failed message arrived`, `When both readings match`, `reads as one date, so it needs no evidence`, `leave out "fixKind", "fixParameters" and "fixSummary"`.
- `Test/Msg/Catalog.cls` -- (contended; ruled a plain-union append) the two keys in `Keys`, `Fixtures` (exact texts per channel) and `OneForms`, each as one block right after the `incident.laterRequest` lines; counts 26 to 28 (L3, L81, L83), 123 to 125 (L121) and 9 to 11 (L5, L554).

- [ ] [QA] U-250 (answer #754): the Condition 1 test (`Test.Fix.EitherWay.TestBothReadingsMatch` and/or `Test.Fix.DryRun.TestBothReadingsMatch`, plus `Test.Fix.Reformat.TestEvidence`) pins the same-date outcome AND a mixed set: same-date value(s) plus one value whose readings differ and which matches its arrival only through the one-day tolerance (its instance-local date and the UTC date of its arrival differ, e.g. 11/03/2026 arriving 2026-11-04T02:00:00Z) -- accepted (`arrival`), the line shown as worded.

**Acceptance Criteria:**
- AC 1: Given the Diagnosis agent, when its INSTRUCTIONS are read, then they state that for dates that read both ways `repair_resend` is used only when a reason names a value with a day above 12 or the reading matching, within one day either way, the day each failed message arrived, that both readings matching is no evidence, and that without evidence the reply is a data_format_change with no fix; and the CI mock's demo reply names month first matching each order's arrival.
- AC 2: Given failed values that all read both ways with no arrival evidence, when the dry run of `repair_resend` runs, then it refuses, no approval request is raised, and the incident's notice is `incident.noFix` with its cause (DW-644).
- AC 3: Given failed values that all read both ways and match the chosen reading's arrival day within one day (also when the instance date and the UTC date differ), when the request is raised, then each recipient's notice renders U-249's line in its Dry run paragraph (many or one form, `reading`, `item`); given any value with a day above 12, the notice has no line.
- AC 4: Given a data_format_change reply with no fixKind, fixParameters or fixSummary, when the bridge checks it, then it is usable and the incident is noticed with `incident.noFix` and no dry run.
- AC 5: Given the demo partner's press (today's instance-local date, MM/DD/YYYY), when the demo incident is diagnosed on the CI mock, then it still gets its repair request (month first matching each order's arrival), `live:demo-path` and `live:online-demo-path` stay green, and the evaluation push run passes with no expected outcome changed.

## Spec Change Log

- After implement (the lead, 2026-11-03): owner-delegate answers U-250 (#754), U-251 (#755), U-252 (#756) recorded under Design Notes; one [QA] task added for U-250's extra Condition 1 case.

- U-249 applied at plan (answer 2026-11-03T21:34:43Z#748): new wording keyed on arrival, {item} slot, one-day tolerance both ways, both-readings-match = no evidence, instance-vs-UTC-date test.
- Spec gate, 2026-11-03 (the lead, unattended rulings): Q1 ruled (a) (veto U-250): same-date values are not ambiguous; a set of only such values is accepted without the line; the prompt carries the Q1 (a) sentence. V1 ruled accepted (veto U-251). Web incident card: notice-only in 7.7, the card row ledgered as DW-645 (escalated, veto U-252). `Test/Msg/Catalog.cls` XData `Keys`/`Fixtures`/`OneForms` blocks plus the counts: ruled a plain-union append (decide). Two variant keys copying their parents' text plus U-249's line: ruled within the wording rule (decide; no new wording). Status reset to draft for the re-plan.
- Re-plan, 2026-11-03: the rulings applied (the prompt bullet carries the Q1 (a) sentence and `TestDiagnosisEvidence` pins it; the three same-date tests expect `same`, accepted, no line; the Q1 mutation row; Q1, V1 and the contended notes rewritten as decided; the clarification section removed). Nothing else changed.

## Review Triage Log

### 2026-11-03 - Review pass
- verdicts: 20 findings - high 0, medium 3, low 16, false 1, maybe-false 0 (patched 6, rejected 14)
- findings:
  - `[low]` `reject` Blind 1 / Edge 1 / Verification-gap other: for a set that mixes a same-date value with arrival-matching differing values, the either-way line says all N dates match their arrival, which a same-date value need not -- the claim is overbroad but the repair is the same date whichever order is right (Q1 ruled (a), veto U-250), the mix needs same-date values that did not arrive within a day next to differing values that did, and the only fix changes the intent-contract's example rule; carried to the lead in the report.
  - `[low]` `reject` Blind 2: `incident.noFix` says "None of my fixes applies" although a fix would apply if the date order were known -- V1 ruled accepted (veto U-251) with exactly this existing text; any other wording is outside the one new line allowed (Clarification Needed for the lead, not a patch).
  - `[low]` `reject` Blind 3: the payload loosening applies to every data_format_change -- V1 ruled accepted (veto U-251); a reply with no fix is noticed honestly as `incident.noFix`, nothing is approvable.
  - `[medium]` `patch` Blind 4 / Verification-gap 1: the later round (`incident.laterRequestEitherWay`) had no end-to-end pin -- `EitherWay.TestLaterRoundKeepsTheLine` added (first request, two more orders, the approval Notification's key, slots and phone line); mutation line recorded and observed red.
  - `[low]` `reject` Blind 5 / Edge 5 / Verification-gap: `TestPressWritesTheLocalDate` reads the clock twice around a UTC midnight/noon -- a window of milliseconds; the fix (retry) adds more than it saves.
  - `[medium]` `patch` Blind 6 / Verification-gap: the arrival is set after `WaitFailed` and the margin was only logged -- `LogMargin` now asserts the DryRun header is not older than the setting of the arrival, so a lost race is red on any date.
  - `[low]` `reject` Blind 7: the "within one day" prose and `ARRIVALDAYS` can drift -- the phrase is pinned by `TestDiagnosisEvidence` and the number by the tolerance rows; a coupling test adds nothing.
  - `[low]` `reject` Blind 8: `Evidence` repeats `Reads`/`Readings` work and `twoWay` is unused in production -- cost is negligible for the dry run's size and `twoWay` is a contract output.
  - `[low]` `patch` Blind 9: the `DiagnosisPayload` class doc ran the new sentence into the semicolon list -- reworded (V1 sentence, then "It also requires ...").
  - `[low]` `reject` Edge 2: Plan/Execute do not re-run Evidence after approval -- the rule is the dry run's alone by contract (Never: no change to the recheck path), and the case needs a target to vanish between approval and execution.
  - `[false]` `reject` Edge 3: `parameters.%Get` before `CheckParameters` in DryRun -- the executor's `DryRun` wraps the call in Try/Catch and answers a plain reason; a non-object parameters value never reaches the kind from a stored request.
  - `[low]` `reject` Edge 4: `"fixParameters":{}` or a blank-with-whitespace fixKind is refused rather than treated as no fix -- the prompt tells the model to leave the keys out, and the refusal is the safe fallback (no false all-clear).
  - `[medium]` `patch` Verification-gap 2: AC 1's second half (the mock reply names month first matching arrival) had no assertion reading the words -- `TestDiagnosisEvidence` now asserts them on `RunnerFixture.DIAGNOSISTEXT` (kept equal to `diagnosis.json` by `Runners`); mutation line recorded and observed red.
  - `[low]` `patch` Verification-gap 3: mutation lines missing for the `item` slot, the later key and AC 5 -- the first two applied and observed red, AC 5 mapped to its pin; lines recorded.
  - `[low]` `patch` Verification-gap 4: `DryRun.TestNoEvidenceIsRefused` last row (DD.MM.YYYY) could not fail -- removed; `n/a` is pinned by `Reformat.TestEvidence`.
  - `[low]` `reject` Verification-gap 5: `NoticeText.TestEitherWay` one-form renders overwrite `reading` and `before` by hand -- the builder's `reading` and `item` are asserted in the case loop of the same test.
  - `[low]` `reject` Verification-gap 6: `Test/Msg/Catalog.cls` changed two lines beyond the ruled blocks -- both are counts of the same union kind ("four" to "six" web wordings; 13 to 15 noun keys), required by the two new keys; recorded under Design Notes (Decided in-stage) and reported to the lead.
  - `[low]` `reject` Intent audit: the prompt surface is pinned only by phrase tests (the mock never reads the prompt) -- inherent to "no real model key"; the code backstop pins the rule.
  - `[low]` `reject` Intent audit: the mock's canned reasons claim evidence on the negative scenario's data -- the code gate, not the wording, refuses (AD-8); the negative tests pin the gate.
  - `[low]` `reject` Intent audit: `DryRun.TestLeftOutAndScope` changed an expectation's input (01/02/2027 to 01/22/2027) -- its assertion is unchanged (the example is the lowest target) and the new example rule makes the one-way input necessary.


## Design Notes

**U-249 (owner delegate, at=2026-11-03T21:34:43Z#748)** (recorded exactly as given; it replaces the dispatch's earlier wording):
- Many values: 'All {count} dates are valid whether read month first or day first. Read {reading}, they match the day each {item} arrived.'
- One value: 'The date is valid whether read month first or day first. Read {reading}, it matches the day the {item} arrived.'
- `{reading}` is 'month first' or 'day first'. `{item}` is the incident's itemNoun `one` form: 'order' in the demo, 'message' when the noun is unknown (the repair isn't demo-only; IRIS sees when an item arrived, not when it was sent).
- The line stays hidden when any value has a day above 12.
- *Condition 1, time zones:* the arrival-day check allows one day either side (a partner's local date can differ from the instance date or the UTC date; the demo partner writes its own local date, so an exact match against a UTC header date would refuse the demo repair every evening ET). This tolerance applies to the evidence check (the reason the Diagnosis gives and any code check) and to the dry run's matching. With +/-1 day, a value whose month-first and day-first readings both land within a day of its arrival matches both ways: then neither reading is evidence, so no `repair_resend` and no line. Pin this in a test.
- *Condition 2, the test:* a test pins a press made at a time when the instance date and the UTC date differ; the demo repair must still be proposed, with the line shown.
- Fitting: the many form's `{count}` is the entry's `resendCount` slot (the line shows only when every target value reads both ways, so the values are the resend targets); `{reading}` and `{item}` are `text` slots (`noun` would pick "orders" by the count slot, and U-249 fixes the one form).

**Q1, ruled (a) (veto U-250): a value whose month equals its day reads as one date.**
- Measured: for a month and day that differ (both 12 or less), the two readings lie at least 27 days apart (every year 2025 to 2028; minimum 02/03 against 03/02). With one day of tolerance either way, "both readings land within a day of its arrival" can only happen when the month equals the day, where the two readings are the same date.
- So Condition 1's second half is exactly about values such as 11/11/2026. The demo partner writes 11/11/2026 on November 11 and 12/12/2026 on December 12 (instance-local; the CI stacks run in UTC); read literally, such a set never has evidence, the demo incident would get no repair on those days and `live:demo-path` would go red on those UTC days, against scope item 5 and U-249 Condition 2.
- Decided: a value whose two readings are the same date is not ambiguous, because the repair writes the same value whichever order is right. It needs no evidence and never shows the line. A set of only such values gives `Evidence` `same` (accepted, `incident.withFix`, no line); only values whose readings differ need arrival evidence, or a one-way value in the set. Condition 1's both-ways case cannot occur for values whose readings differ, and its tests pin the same-date outcome (`Reformat.TestEvidence`, `DryRun.TestBothReadingsMatch`, `EitherWay.TestBothReadingsMatch`). The prompt says so in its own words: "A date whose day and month are the same number reads as one date, so it needs no evidence."

**Owner-delegate answers (Contest Planner, relayed by the orchestrator, applied by the lead after implement, 2026-11-03):**
- U-250 at=2026-11-03T23:29:21Z#754: KEPT as ruled. A value whose two readings are the same date (11/11, 12/12) is not ambiguous: no line and no arrival evidence needed. Only values whose readings differ need evidence, and a mixed set shows the line as worded. The Condition 1 test pins the same-date outcome, PLUS one value whose readings differ and which matches arrival only through the one-day tolerance (the instance and UTC dates differ). (This settles the implement review's unpatched note on mixed same-date sets: the line stays as worded.)
- U-251 at=2026-11-03T23:29:21Z#755: KEPT. All three of fixKind, fixParameters and fixSummary absent: the existing incident.noFix notice with the model's cause, nothing approvable; any one or two alone still refused. Any eval re-baseline comes back as a veto item, never silently. (Its real-model merge condition is the orchestrator's, U-253; no real model key in this story.)
- U-252 at=2026-11-03T23:29:21Z#756: PARTLY KEPT. 7.7's AC is met by the notice's Dry run paragraph. The web-card row becomes Story 7.8 (added by the Planner on the feature branch), dispatched in Epic 7 once Epic 31 has merged; 7.7 never touches approval-view.ts or Live/Payload; DW-645 stays as it is.

**Rulings at the spec gate (the lead, 2026-11-03, unattended; policy 5086036):**
- Q1: ruling (a), veto U-250. A value whose month equals its day reads as one date; it needs no evidence and never shows the line. Only values whose readings differ need arrival evidence (or a one-way value in the set). The prompt carries the Q1 (a) sentence. Condition 1's test pins the same-date outcome (`same`, accepted, no line).
- V1: accepted, veto U-251.
- Web incident card: not in 7.7. The notice's Dry run paragraph carries the line (AC 3); the card row is DW-645 (escalated, owner burndown, for the decision sheet), veto U-252.
- `Test/Msg/Catalog.cls`: the two keys' entries in `Keys`, `Fixtures` and `OneForms`, each one self-contained block right after the `incident.laterRequest` lines, and the three counts: a plain-union append (decide). Edit no other line of that class.
- The two variant keys (`incident.withFixEitherWay`, `incident.laterRequestEitherWay`) copy their parents' text exactly and add only U-249's line: within the wording rule (decide).

**V1, ruled accepted (veto U-251): a data-format diagnosis may carry no fix.**
- Story 5.4's reply check refuses a data_format_change without fixKind, fixSummary and fixParameters. The story's AC needs a usable reply that does not propose `repair_resend` for a data-format cause. Chosen: all three absent together is accepted, and the incident gets `incident.noFix` with the model's cause ("{cause}. None of my fixes applies to this, so I'm not proposing one. Nothing was changed."): existing text, honest category, no false all-clear, nothing approvable.
- Rejected: telling the model to use another category (dishonest; eval scores the category); leaving the check as is (a compliant reply becomes `invalid`, a fallback that says "I couldn't work out the cause").
- Each field alone stays refused (the one-at-a-time rows of `Test.Watch.Payload` stay green). Reversal: restore the branch; the code backstop (the dry-run refusal) still prevents any no-evidence request.

**Where the evidence check lives, and which clock.**
- Prompt plus a code check in the dry run (`RepairResend.DryRun`, the path that calls `CheckParameters`). Only the dry run sees every target value and its header's arrival; the reply check sees one sample and its `timeProcessed`. A reply-check evidence check would turn a no-evidence reply into a fallback, and `CheckParameters` is also the eval gate's `parametersValid` check, which has no values. No code reads a reason's wording.
- The arrival is each failed header's `TimeCreated` (UTC, as stored; the dry run already reads it through `Reader.Evidence`). The reference day is its UTC date; the one-day tolerance covers any partner zone from UTC-12 to UTC+14, and so the instance date too. Comparing against the instance-local date would stack a second offset. Measured at plan (slot B): IRIS stores and `Reader` returns `TimeCreated` in UTC; `$ZTIMEZONE` moves `$HOROLOG` per process only (Verification).
- The line's condition reaches the notice without a new stored key: the example rule makes `before` two-way-with-different-readings exactly when every target value is, and the refusal makes every raised request of that kind carry arrival evidence. Rejected: a dry-run key (`DRYRUNKEYS` is pinned by `Test/Data/Tables.cls` L13, contended by Epic 39; AD-16 lists the keys; `Live/Payload/Part/DryRun.cls` is Lane B; a stored-format change); a `DryRunResult` property (an AD-16 amendment); IncidentManager re-reading the messages (a second read and a time-of-check gap).

**Where the new line reaches the user.**
- The incident notice's catalog text: the simulated phone (the demo path), Telegram and the simulated mailbox render `CatalogKey` + `Slots` server-side, so a variant key reaches all three with no channel change. The web page's catalog mirror lists only the keys the page renders (`web/scripts/catalog.mjs` L51), and `incident.withFix` is not one, so no web change is needed for the text.
- Decided (veto U-252): the web incident card is out of 7.7. Its dry-run block builds its lines from the stored dry run's fields (`web/src/app/approvals/approval-view.ts`, Epic 31; `Live/Payload/Part/DryRun.cls`, Lane B), so it does not show the line; that card row is ledgered as DW-645 (escalated, owned by burndown, not this story's). The ACs do not need it: the notice's Dry run paragraph is the dry run the story's AC names (7.2: "the incident notice carries the dry run"), and the demo's phone shows it. The line shows on the phone, Telegram and the mailbox, not in the web card's dry-run block.
- Decided (the lead's ruling, plain-union append): `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` (contended by Epics 31 and 40) takes the two keys in XData `Keys`, `Fixtures` and `OneForms`, each as one self-contained block right after the `incident.laterRequest` lines, and the three counts (26 to 28, 123 to 125, 9 to 11). No other line of that class changes. Without them `TestEntries`, `TestEveryKeyOnEveryChannel` and `TestCountOfOneForms` fail.

**The CI mock and the evaluation set.**
- Every eval incident case and the demo get the default `diagnosis` reply (markers are banned under `eval/`, `docker/tests/test-eval-set.sh` L45). Its new reason names month first matching each order's arrival (the demo's evidence) and the day above 12 (the evidence of every 10/16/2026 fixture and of `orders-date-format`), so it is true for both. `RunnerFixture.DIAGNOSISTEXT` follows it. No mock test pins reply text.
- No recorded eval case's expected outcome changes: no case holds dates that read both ways (`orders-date-format`: 50 x 10/16/2026, day 16; `results-decimal-comma`, `shipments-epoch-time`: not dates; every other incident case expects no fix kind; `mail-date-format-monday` is an item case). The eval path asks no dry run (`IncidentManager` L1377). The demo gate's `Fix.Kind.Check` is unchanged.

**Decided in-stage (small, reversible, within the intent):**
- Implement: `Test/Msg/Catalog.cls` also changes two count assertions, besides the ruled blocks and counts: `TestWebWording` (the entries with a web wording, four to six, the two new keys joined to the expected set) and `TestNounForms` (keys with a noun, 13 to 15). Both are counts of the same plain-union kind, forced by the two new keys; without them the class is red.
- Implement (footprint extension): `Test/Channel/TelegramChat.cls` `TestNotices` sweeps every `incident.*` and `result.*` Watch key, so it counts the two new keys (13 to 15 keys, 19 to 21 rows and notifications) and sorts `incident.laterRequestEitherWay` with `incident.laterRequest` as an approval; no in-flight epic touches it (precedent: the 30.5 count change). It needs no unit entry.
- Implement: `Test.Fix.EitherWay` gains `TestLaterRoundKeepsTheLine` (the later round's key, slots and phone line); `Press`'s `LogMargin` asserts the margin is not negative; `DryRun.TestLeftOutAndScope`'s second order is 01/22/2027 (one-way) so that the example stays the lowest target under the new example rule.
- Only the slash pair is ambiguous: the registry has no `MM.DD.YYYY`, so `DD.MM.YYYY`, `YYYY-MM-DD` and `YYYYMMDD` are `n/a`.
- Evidence and the line are judged over the dry run's targets (the values that read in the source format); left-out values do not count.
- The line sits in the Dry run paragraph right after the example sentence, so "Nothing has changed yet." still ends the block and the phone keeps the paragraph as its inset (`phone-view.ts` L113-136).
- The example is the first one-way target, else the first with differing readings, else the first; for the existing fixtures (all one-way) it is the first target, as before.
- The mock's reason text and the `diagnosis-noevidence` scenario are CI fixtures, not product text.
- The refusal sentence is a log reason (Type 3 warning through the redactor), never shown.
- No new eval case: a real-model case needs a recorded snapshot of real failures, and on the mock every case gets the one default reply; the rule is pinned by the prompt test, the mock marker and the dry-run backstop.
- No EXPERIENCE.md edit in this story (a planning artifact): the lead may append the dry-run row at its bookkeeping, away from Epic 33's and Epic 40's blocks.
- Re-plan: `Evidence` tests `same` before `arrival`, so a set of only same-date values gives `same` (the vacuous "every value whose readings differ" never yields `arrival`); a mix of same-date values and values whose readings differ is judged on the latter. `TestDiagnosisEvidence` also pins the Q1 (a) sentence.
- The Condition 2 test sets the data an ET evening press makes (the value the instance-local date, the arrival the next UTC day), because CI stacks run in UTC and a real press's date depends on the calendar; `TestPressWritesTheLocalDate` pins that the press path writes the process-local date.

**Governing ADs:** AD-7 (static INSTRUCTIONS, no `{{`; checked JSON reply), AD-8 (the bridge alone decides usability; V1 changes the check's content, not who decides), AD-11 (the row is the truth; the stored dry run is unchanged), AD-15 (the notice route and `Transitions`; IncidentManager the one writer), AD-16 (the kind validates; the dry run's keys unchanged; `Fix/Msg/**` unchanged), AD-22 (the mock by marker or mock key; throwaways), AD-26 (the incident's trace session, unchanged), AD-29 (Lane A: `Catalog.Watch`, the Fix and Watch areas), AD-31 (`FILTERED` unchanged), AD-32 (kind `incident`, the key tells the variants apart; keys and slots only), AD-33 (owners unchanged). Conventions: "Incident notice", "Approval requests", "Messages", "Redaction".

**Integration ACs, Consumes, Consumed-by (Rules 1 and 2):**
- Integration AC (matrix row 1): `IncidentManager` reads the real dry run, `Notice` picks `incident.withFixEitherWay`, and the recipient's phone message (`SimPhoneOut` rendering the delivered Notification) shows the line.
- Consumes: 7.1 (`RepairResend.DryRun`, `Fix.Reformat`), 7.2 (`Proposed`, `NoFix`, `Deliver`, `Notice.WithFixSlots`), 7.6 (`incident.laterRequest`, the later route and V2), 5.4 (`DiagnosisPayload`, `Agent/Diagnosis.cls`), Epic 0 (`Msg.Catalog`, the mock), Epic 6 (`SimPhoneOut`).
- Consumed-by: none in this epic (7.7 is its last story); the web card's dry-run line row is out of 7.7 (DW-645, veto U-252).

**Extend, don't copy (Rule 2):** `Readings` extends `ParseDate`/`Reads`; `Evidence` sits on the kind beside `Readable`; `WithFixKey` and `WithFixSlots`' `parameters` extend the with-fix builder (no second builder); `SendOrders`/`Fail` gain `orderDate`, and `SetArrival` sits beside `SetOrderDate`; `diagnosis-noevidence.json` copies the shape of `diagnosis-nofix.json`; the two catalog entries copy their parents' text, because the catalog has no composition and an existing key's text may not change (a copy the catalog forces).

**Ledger inbox:** DW-644 addressed by the matrix rows "Arrival evidence ...", "Negative: ambiguous ..." and the Execution tasks of `RepairResend.cls` and `Agent/Diagnosis.cls`.

**Footprint extensions:** `Watch/Msg/DiagnosisPayload.cls`, `Watch/Notice.cls`, `Watch/IncidentManager.cls`, `Msg/Catalog/Watch.cls` (one block), `ci/mock/scenarios/A/{diagnosis,diagnosis-late,diagnosis-noevidence}.json`, `Test/Watch/{Case,NoticeText,Payload}.cls`, `Test/Msg/Catalog.cls` (contended; plain-union append, ruled). `new_units:` none.

## Verification

`<laneB>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root. One command per foreground call with `timeout: 600000`; never two IRIS test runs in one message; a call the harness moves to the background is polled to completion in foreground loops under 170 s. A change under `ci/mock` refuses a warm run: make the mock edits first, or `ci/warm.sh down` then `up`.

**Commands:**
- (loop) `<laneB> OCUTALON_RUN_TAG=e7s7iw ci/warm.sh up`, once per stage, after the mock edits -- expected: READY.
- (loop) `<laneB> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s7iw ci/iris.sh class <Class>`, one call each: `OcuTalon.Test.Fix.Reformat`, `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Watch.Payload`, `OcuTalon.Test.Agent.Instructions`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Fix.Validation`, `OcuTalon.Test.Watch.Tell` -- expected: `CLASS ... passed`.
- (loop) `<laneB> OCUTALON_RUN_TAG=e7s7i ci/iris.sh class <Class>`, fresh, one call each: `OcuTalon.Test.Fix.EitherWay` (first: Task 0), `OcuTalon.Test.Fix.DryRun`, `OcuTalon.Test.Watch.Diagnose`, `OcuTalon.Test.Agent.Runners`, `OcuTalon.Test.Fix.Raise`, `OcuTalon.Test.Fix.Later`, `OcuTalon.Test.Watch.Notices` -- expected: passed.
- (once) `bash docker/tests/test-mock.sh` -- expected: every mock test passes.
- (once) `<laneB> OCUTALON_RUN_TAG=e7s7i ci/iris.sh shard lane-a --part k/12` for k = 1 to 12, one call each (split to `k/16` if a part nears 8 minutes) -- expected: passed; record each part's time.
- (once) `<laneB> OCUTALON_RUN_TAG=e7s7i ci/iris.sh shard lane-b --part k/3` for k = 1 to 3 -- expected: passed.
- (once) `<laneB> OCUTALON_RUN_TAG=e7s7i ci/iris.sh build`, then `<laneB> OCUTALON_RUN_TAG=e7s7i ci/iris.sh live demo-path`, then `<laneB> OCUTALON_RUN_TAG=e7s7i ci/iris.sh live online-demo-path` -- expected: passed (the demo repair, AC 5).
- (once) `<laneB> OCUTALON_RUN_TAG=e7s7ie bash eval/run.sh` -- expected: `eval/run: all checks passed`, the demo gate 10 of 10; no expected outcome changed.
- (once) `bash ci/checks.sh` -- expected: every script passes (the `{{` check, class rules, ASCII).
- (once) `<laneB> OCUTALON_RUN_TAG=e7s7iw ci/warm.sh down`, then `<laneB> OCUTALON_RUN_TAG=e7s7i ci/iris.sh teardown` and `<laneB> OCUTALON_RUN_TAG=e7s7ie ci/iris.sh teardown`; run them also after a failure.

**Shared surfaces:**
- `Catalog.Watch` key count 26 to 28 (total 123 to 125) and one-form count 9 to 11: `Test.Msg.Catalog` (`Keys`, `Fixtures`, `OneForms`).
- The Diagnosis prompt text: `Test.Agent.Instructions` (substring checks), `Test.Fix.Kind.TestInstructionsNameTheFormats` (unchanged, every format still quoted).
- The mock's recorded diagnosis replies: `Test.Agent.RunnerFixture.DIAGNOSISTEXT` / `Test.Agent.Runners` L294 (changed); `Test.Watch.Diagnose` pins cause, fix summary and parameters only (unchanged); a new marker scenario (the mock tests count the folder).
- The dry run JSON keys: unchanged (`Test.Fix.DryRun` L145, `Test.Data.Tables` L13 untouched). The dry run's example: unchanged for every existing fixture (all one-way).
- The reply check: one more accepted shape (`Test.Watch.Payload`); `Notice.Key` for that shape (`Test.Watch.NoticeText.TestKeysAndVariants`).
- The eval cases: none changes (Design Notes).
- `Case.SendOrders`/`Fail` keep their default date, so every existing Case-based test is unchanged.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply (Rule 19).** The implement stage applies each, observes red, reverts byte-identically, and records `mutation: ... -> ...` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | the evidence bullet removed from INSTRUCTIONS | `Instructions.TestDiagnosisEvidence` |
| AC 2 / negative | `DryRun` ignores `Evidence` `none` | `DryRun.TestNoEvidenceIsRefused`, `EitherWay.TestNoEvidenceNoRequest` |
| AC 2 / tolerance | `ARRIVALDAYS` 0 | `Reformat.TestEvidence` (edges), `EitherWay.TestDemoRepairWhenInstanceDateIsNotUtcDate` |
| AC 3 / line | `WithFixKey` always gives `incident.withFix` | `NoticeText.TestEitherWay`, `EitherWay.TestDemoRepairWhenInstanceDateIsNotUtcDate` |
| AC 3 / hidden | the example rule picks the first target | `DryRun.TestOneWayIsTheExample`, `NoticeText.TestEitherWay` (mixed) |
| AC 3 / reading | `READINGS` swapped | `NoticeText.TestEitherWay` (day first) |
| AC 4 | V1's branch removed | `Payload.TestPayloadAccepted`, `Diagnose.TestNoEvidenceReply` |
| Q1 | `Evidence` returns `none` for a same-date set (the literal reading) | `Reformat.TestEvidence`, `DryRun.TestBothReadingsMatch`, `EitherWay.TestBothReadingsMatch` |
| press | `TestPressWritesTheLocalDate` with `$ZTIMEZONE` left at 0 | that test (local and UTC dates equal) |

**Mutations applied (implement stage, Rule 19; each observed red, then reverted byte-identically, `git diff --stat` unchanged):**
- mutation: the evidence bullet removed from INSTRUCTIONS -> `Instructions.TestDiagnosisEvidence` red (nine assertions).
- mutation: `DryRun` stops returning the error for `Evidence` `none` (the check line removed) -> `DryRun.TestNoEvidenceIsRefused` red (reason and empty targets); `EitherWay.TestNoEvidenceNoRequest` red (variant, no request, notice, one warning).
- mutation: `ARRIVALDAYS` 0 -> `Reformat.TestEvidence` red (the five edge and instance-date rows); `EitherWay.TestDemoRepairWhenInstanceDateIsNotUtcDate` red (no request).
- mutation: `WithFixKey` always gives the plain key (`eitherWay` := 0) -> `NoticeText.TestEitherWay` red (keys); `EitherWay.TestDemoRepairWhenInstanceDateIsNotUtcDate` red (key, line in the notice and the phone message).
- mutation: the example rule removed (the example stays the first target) -> `DryRun.TestOneWayIsTheExample` red (both examples). `NoticeText.TestEitherWay` (mixed) stays green by design: it builds its dry run's `before` itself and does not run `RepairResend`.
- mutation: `READINGS` swapped -> `NoticeText.TestEitherWay` red (the fixture texts and the "month first" line, many and later forms).
- mutation: V1's branch in `DiagnosisPayload` removed (`If 0`) -> `Payload.TestPayloadAccepted` red (both fix-less rows); `Diagnose.TestNoEvidenceReply` red (accepted, cause, noun, variant, notice).
- mutation: `Evidence` returns `none` instead of `same` for a set of same-date values -> `Reformat.TestEvidence` red (the two same rows); `DryRun.TestBothReadingsMatch` red (and `DryRun.TestNothingReadable`, whose empty target set is the same case); `EitherWay.TestBothReadingsMatch` red (no request).
- mutation: `TestPressWritesTheLocalDate` with `$ZTIMEZONE` left at 0 -> that test red (local and UTC dates equal).
- mutation: the `item` slot takes the other form of the noun (`slots.itemNoun.other`) -> `NoticeText.TestEitherWay` red (the slots rows for month first, day first, unknown noun and own noun).
- mutation: the later branch of `IncidentManager.Proposed` takes its key from `WithFixKey({}, ...)` (the plain later key) -> `EitherWay.TestLaterRoundKeepsTheLine` red (the key, the phone line).
- mutation: the CI mock's demo reply loses its month-first-matches-arrival reason (`RunnerFixture.DIAGNOSISTEXT`) -> `Instructions.TestDiagnosisEvidence` red (AC 1, second half).
- AC 5: pinned by `EitherWay.TestDemoRepairWhenInstanceDateIsNotUtcDate` (its `ARRIVALDAYS` 0 mutation above is red) and, as verification runs, `live:demo-path`, `live:online-demo-path` and `eval/run.sh`.

**Task 0 results:**
- (a) Plan stage, slot B (`ocutalon-slot-b`, instance 62AB8833-CB21-11F1-9F31-AA10048473C6, build 154U), read only, 2026-11-03: `$ZTIMEZONE` 0 gave `$HOROLOG` 2026-11-03 22:00:10 and `$ZTIMESTAMP` 2026-11-03 22:00:10; after `Set $ZTIMEZONE=-840`, `$HOROLOG` 2026-11-04 12:00:10 and `$ZTIMESTAMP` unchanged; after `Set $ZTIMEZONE=720`, `$HOROLOG` 2026-11-03 10:00:10. The slot runs in UTC. `Ens.MessageHeaderBase.TimeCreated` is `Ens.DataType.UTC`, set by `$$$timeUTC` (`EnsUtil.inc` L24, `$zdatetime($ztimestamp,3,,3)`), so it is unaffected (read from `irislib`).
- (b) Implement stage, first run of `Test.Fix.EitherWay` (warm stack e7s7iw, the stack's product code as loaded; the test logs it): the DryRun header was created 10 seconds after `SetArrival` returned (`WaitFailed` returned just before it), so the margin is well over 3 s and `SetArrival` stays after `WaitFailed`.
- (c) `Test.Fix.EitherWay` class time on a fresh stack (e7s7i): 39.76 s (39.05 s on the final run); on the warm stack 39.19 s. Under 180 s: one class.

## Auto Run Result

Status: done
Blocking condition: none

Summary: a date written MM/DD/YYYY or DD/MM/YYYY that reads both ways now needs evidence. The Diagnosis prompt carries the rule (a day above 12, or the reading matching the failed messages' arrival within one day either way, both readings matching being no evidence, same-date values needing none); a reply with no fix is accepted (V1) and noticed as `incident.noFix`; `RepairResend.DryRun` enforces the rule in code (`Evidence`: n/a, oneway, arrival, same, none) and refuses on `none`; the notice uses `incident.withFixEitherWay` / `incident.laterRequestEitherWay` with U-249's line when every target reads both ways with differing readings.

Files changed (under `src/ocutalon/cls/OcuTalon/` unless stated):
- `Agent/Diagnosis.cls`: the evidence rule in the static prompt. `Fix/Reformat.cls`: `OtherOrder`, `Readings`. `Fix/Kind/RepairResend.cls`: `ARRIVALDAYS`, `Evidence`, example rule, refusal.
- `Watch/Msg/DiagnosisPayload.cls`: V1. `Watch/Notice.cls`: `WithFixKey`, `Reading`, slots `reading`/`item`, fix-less key. `Watch/IncidentManager.cls`: `Proposed` uses them. `Msg/Catalog/Watch.cls`: the two variant keys.
- `ci/mock/scenarios/A/{diagnosis,diagnosis-late}.json` (reasons), `diagnosis-noevidence.json` (new).
- Tests: `Test/Fix/{Reformat,DryRun,EitherWay(new)}`, `Test/Watch/{Case,Diagnose,NoticeText,Payload}`, `Test/Agent/{Instructions,RunnerFixture}`, `Test/Msg/Catalog` (ruled union plus two count lines), `Test/Channel/TelegramChat` (counts).

Review: 20 findings from 4 layers; 6 patched (later-round end-to-end test, margin assertion, mock-reason assertion, mutation lines, the DD.MM.YYYY row that could not fail, a class doc), 14 rejected with reasons in the triage log (0 high, 3 medium, all patched). Nothing deferred. Follow-up review recommended: false.

Verification (lane B, CI mock): warm classes Reformat, NoticeText, Payload, Instructions, Msg.Catalog, Fix.Kind, Fix.Validation, Watch.Tell passed; fresh classes EitherWay (about 40 s, 61 s with the added test), DryRun, Diagnose, Runners, Raise, Later, Notices passed; `docker/tests/test-mock.sh` 131 of 131; `lane-a` parts 1 to 12 of 12 passed (186 s to 460 s; part 4 first failed on `TelegramChat.TestNotices` counts, fixed, then passed); `lane-b` parts 1 to 3 passed (303 s to 397 s); `live demo-path` and `live online-demo-path` passed; `eval/run.sh` all checks passed, demo gate 10 of 10; `ci/checks.sh` all scripts passed (16 min total, run outside the 10-minute foreground cap by the harness, polled to completion). Stacks e7s7i, e7s7iw, e7s7ie torn down.

Residual risks: a set that mixes a same-date value with arrival-matching differing values gets the line "they match the day each order arrived", which the same-date value need not satisfy (the repair is identical either way; fixing it changes the contract's example rule); `incident.noFix` for a refused or fix-less date diagnosis says "None of my fixes applies" (V1, ruled); the web incident card does not show the line (DW-645).
