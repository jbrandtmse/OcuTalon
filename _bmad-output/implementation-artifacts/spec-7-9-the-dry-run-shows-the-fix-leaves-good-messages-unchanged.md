---
title: 'The dry run shows the fix leaves good messages unchanged'
type: 'feature'
created: '2026-11-06'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A repair and resend's dry run shows what the repair does to the broken messages, but not whether the same repair would also rewrite messages the production accepted. If the source format the diagnosis named is wrong, the reformatter would rewrite good values too, and nothing tells the user so before they approve (FR-25; owner decision of 2026-11-06T01:15Z).

**Approach:** Before a fix is offered, `RepairResend.DryRun` reads the newest N=20 good messages from the same source as its targets through one new read method of `Watch.Reader`, and applies the target test and `Fix.Reformat` to each in memory. If any would change, the dry run is refused with a reason (Story 7.7's NOEVIDENCE route: `incident.noFix`, nothing approvable). If none would change and at least one was checked, the with-fix and later-request notices use four new catalog variants whose Dry run paragraph has one more line with the count checked and the count changed. The two counts travel in the dry-run answer, and the stored row keeps exactly `DRYRUNKEYS`.

## Boundaries & Constraints

**Always:**
- Terms used below. A *target* is a message the dry run would resend (today's rule, unchanged). A *good message* for a target is an `Ens.MessageHeader` of the incident's namespace with Status 9 (Completed), IsError 0 and Type Request, whose SourceConfigName, TargetConfigName, MessageBodyClassName and SuperSession all equal the target header's (an empty SuperSession matches an empty one). Repaired copies of an earlier approved fix that completed are good messages too (their header is a clone: Task 0). The *reference* of a group of targets is the lowest target header id with that tuple of four values.
- *Checked* and *changed* (decided in-stage, Design Notes): every good message read counts as checked. A good message is changed exactly when the kind's target test on its body passes (the field is a stored field and `Reformat.Convert` reads its value in the source format) and the converted value differs from the current value, compared as text. A value that does not read in the source format is unchanged (the reformatter refuses it), and so is an empty value, a missing field or an unreadable body. A value that converts to itself is unchanged: `11/11/2026` from MM/DD/YYYY to DD/MM/YYYY, or `1234` from `1234.56` to `1234,56`. `11/11/2026` from MM/DD/YYYY to YYYY-MM-DD is changed.
- The read: `Watch.Reader.Good` reads, for each reference, at most the newest `RepairResend.GOODMAX` (20) good messages (highest header id first), with no duplicates. It reads them in `Reader.Current`, the one switching method (AD-3), under the same readable and not-current checks as `Evidence`, through the same per-header code (fields, body and status). The count checked is the real number found, 0 to 20 for each reference.
- The check runs after today's evidence refusal and only when the dry run has targets. It applies the same way to a later round's dry run.
- If any good message is changed, `DryRun` returns an error status with the reason `GOODCHANGED` (log only, through the redactor). `FixExecutor` then answers with that `Reason`, and `IncidentManager` takes its existing route: for the first request `incident.noFix` with the cause, open variant `no_fix`, no request and one Type 3 `LOGPROPOSE` warning; for a later round, 7.6's V2 (nothing sent, one `LOGLATER` warning).
- Otherwise the kind's dry run carries `DRYRUNKEYS` plus `goodCheck` `{"checked", "changed"}`. `IncidentManager.Proposed` stores in the row's `DryRun` only the keys of `DRYRUNKEYS`, and passes the whole answer to `Notice.WithFixKey` and `WithFixSlots`.
- The key: with `goodCheck.checked` of at least 1, `WithFixKey` gives the `...Checked` variant of the key it gives today (`incident.withFix`, `incident.laterRequest`, `incident.withFixEitherWay`, `incident.laterRequestEitherWay`). With 0 it gives today's key, unchanged. That is the zero-good-messages rule, pending the Planner's ruling (Design Notes, PT-a). `WithFixSlots` adds `goodChecked` and `goodChanged` (count) and `goodNoun` (text: the itemNoun's `one` form when goodChecked is 1, else its `other` form).
- Each new key copies its parent's `text`, `web`, slots, `source` and one form exactly, and adds the three slots and the ruled line (PT-a) in every form, between "...stay(s) unchanged." and " Nothing has changed yet.". The `source` is the parent's plus `; good-message line: Story 7.9 (owner decision 2026-11-06)`. The four keys are one self-contained block right after `incident.laterRequestEitherWay` in `Msg/Catalog/Watch.cls`, and no existing key's text changes.
- An approved request still runs only the row's `FixKind`, `FixParameters` and `FixTargets`, which are the ask's kind and parameters and the dry run's `Targets`. `Recheck` and `Execute` are unchanged and never touch a good message.
- Read only: the check writes, resends and queues nothing in either namespace, and calls no model.
- The proposed strings (Design Notes, "Proposed public text") are placeholders until the Planner rules. The implement stage starts only after the runner has relayed the ruling, and types the ruled strings exactly.
- CI mock only, lane-D throwaways or slot D only. Rule 14: ASCII escapes in code, and comments state the contract.

**Never:**
- No change to `DRYRUNKEYS`, to the stored dry run's keys, to `Bridge/**`, `Test/Data/Tables.cls`, `Live/**`, `web/**`, `Fix/Msg/**` properties, `Recheck`, `Execute`, `Plan`, `CheckParameters`, `Reformat` or `Fix/Executor.cls`.
- No second method that switches namespace, and no change to `Reader.Current`'s signature. The Reader change is limited to the blocks named in the Code Map (Reader.cls is contended by Epic 17).
- No new line in `Msg/Catalog/Watch.cls` outside the one appended block. No edit to an existing scenario under `ci/mock/scenarios/**`, and nothing under `ci/units.sh`, `docker/**`, `Demo/**`, `eval/**`, `Install/**`, the workflows, `_bmad/` or `.claude/`.
- No web incident card change (Design Notes, PT-d). Not fixed in passing: DW-318, DW-653, DW-655.

## I/O & Edge-Case Matrix

The good orders are sent with `Partner.Send(n, "YYYY-MM-DD", ref, "2026-11-05")` in the failures' own reference `ref`. Each failed order is MM/DD/YYYY, with the default mock diagnosis (MM/DD/YYYY to YYYY-MM-DD).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Fewer than 20, real path (Integration AC) | 5 good, then 3 failed (10/16/2026) in `ref` | one pending request; Notification key `incident.withFixChecked`, slots goodChecked 5, goodChanged 0, goodNoun "orders"; the phone text holds PT-a's line for 5 and 0; the stored `DryRun` has exactly DRYRUNKEYS. Pin: `GoodMessages.TestFewerThanTwentyGood` | none |
| Read only | the same run | `Fix.Snapshot` Diff of both namespaces over the dry-run ask is empty but the ask's session; the good headers' bodies and statuses are unchanged; `Mock.LogSince` holds only the diagnosis request(s); no Ens_Util.Log row in the dry-run session | none |
| More than 20 | 23 good, then 2 failed | goodChecked 20, the 20 newest by id. Pin: `GoodMessages.TestOnlyTheNewestTwenty` | none |
| One good | 1 good, then 3 failed | goodChecked 1, goodNoun "order" | none |
| Zero good (PT-a pending) | 3 failed only | `incident.withFix`, its text unchanged, no good slots; `goodCheck` {0, 0} in the DryRunResult, not stored. Pins: `GoodMessages.TestNoGoodMessages`, `Watch.Diagnose.TestDemoDiagnosis` (unchanged) | none |
| Demonstrated mutation (owner's test) | 3 good, one good body's OrderDate set to 11/05/2026 (`SetOrderDate`), then 3 failed | dry run refused (Reason starts "The repair would also change"), no request, incident open `no_fix`, notice `incident.noFix` with its cause, one LOGPROPOSE warning naming GOODCHANGED. Pin: `GoodMessages.TestOneChangedGoodWithholdsTheFix` | logged |
| Other sources and sessions | good orders in another ref; the completed OrdersFromPartner→OrdersToWarehouse headers; failed and queued headers | none of them is checked | none |
| Approval equals dry run, then later round | the first test's request approved (`Approval.Answer`), run to `result.allThrough`; then 2 more failed orders in `ref` | the row's FixKind/FixParameters/FixTargets equal the ask's and the DryRunResult's Targets; the copies name exactly the targets ("Resent <id>"); no good header has a copy and its body is unchanged; the later round's Notification key `incident.laterRequestChecked`, goodChecked 8 (5 good + 3 copies). Pin: `GoodMessages.TestApprovalRunsTheDryRunOnly` | none |
| Later round refused | as above, one good body set to 11/05/2026 before the later round | nothing sent for the round, one LOGLATER warning, the first request untouched | logged |
| Converts to itself, same date | pure: value 11/11/2026, MM/DD/YYYY to DD/MM/YYYY; to YYYY-MM-DD; `1234`, `1234.56` to `1234,56`; empty, missing field, empty body, YYYY-MM-DD under MM/DD/YYYY | unchanged, changed, unchanged, unchanged x4. Pin: `Fix.Kind.TestGoodChanges` | none |
| Empty SuperSession | untagged good and failed orders (`ref` "") | the untagged good are checked (instance scope) | none |
| Read fails | `Good` gives unreadable or not_current | dry run refused with a plain reason. No test of its own: `Good` runs the same two checks as `Evidence`, which `Test.Watch.Evidence` pins, and `Evidence` has already passed them in the same dry run | logged |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated. Lines as of `a24e83ef20733ae834e53da06fe8506e021ac938`.

**Changed (footprint):**
- `Fix/Kind/RepairResend.cls`: DryRun L117-236. The scoped loop L146-154 also keeps each failure's `sourceConfigName`, `targetConfigName`, `bodyClass` and `superSession`. The new check goes after the evidence refusal L199-206 and before the noun L207. The key loop L224-234 builds the dry run, and `goodCheck` is set after it. `Readable` L374 is the target test to reuse. Parameters go beside `NOEVIDENCE` L43. Class doc L1-25.
- `Watch/IncidentManager.cls`: `Proposed` L867. Store the stripped dry run at L914 (`row.DryRun = result.DryRun`). `WithFixKey` at L927 and L932 and `WithFixSlots` at L899-901 keep getting the whole `dryRun`. Docs L94 and L863.
- `Watch/Notice.cls`: parameters L50-63; `WithFixKey` L148; `WithFixSlots` L184; class doc L1-40.
- `Msg/Catalog/Watch.cls`: append after the `incident.laterRequestEitherWay` entry (L146-167), before `incident.fallback` (L168).
- `Test/Watch/Case.cls`: `SendOrders` L730 (always MM/DD/YYYY, L734).
- `Test/Watch/NoticeText.cls` (pure): `Render` L208, `TestWithFix` L278, `TestLaterRequest` L328, `TestEitherWay` L361, `AssertFixture` L441.
- `Test/Fix/DryRun.cls`: L154 and L213 assert the kind's keys are exactly DRYRUNKEYS.
- `Test/Fix/Kind.cls` (pure; `TestCheck...` L112-118 pattern).
- `Test/Fix/SnapshotDiff.cls` (pure, L45-101) and `Test/Fix/Snapshot.cls` (`Take` L35, `Diff` L144): 7.1's read-only proof, to extend.
- `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`: "Incident notice with approval request" L821-845; "Later approval request" L885-892.

**Contended, one self-contained block each (list them in the completion contract):**
- `Watch/Reader.cls` (Epic 17 changes the class doc after L31, adds code after `Failures` L175-196, and changes `Current`'s signature L255, its init L257-264, its config loop and the block before L305, and its Catch L497-506):
  - (1) a class-doc bullet after the Evidence bullet (L32-41, before L42);
  - (2) the public method `Good` after `Evidence` (L199-224, before `CredentialName` L226);
  - (3) inside `Current`'s key loop L308-315, a branch for the key `g<header id>`, and right after the loop (still inside `If evidence`, before `Set passes` L317) the block that resolves those keys into `headerIds` with `TOP ?` = the existing `limit` argument;
  - (4) one doc sentence in `Current`'s doc after L248. Touch none of Epic 17's lines.
- `Msg/Catalog/Watch.cls`: the one appended block. Epic 17 adds digest and button blocks elsewhere.
- `Test/Msg/Catalog.cls` (Epic 17 changes the same counts: 49 to 54 Watch keys): append the four keys to XData `Keys` (after L1090), `Fixtures` (after L1381) and `OneForms` (after the entry ending about L1173), and update the counts: Watch L81/L83 49 to 53, total L121 154 to 158, web wording L486-488 six to ten, noun forms L547 16 to 20, one forms L568 11 to 15. The count lines collide with Epic 17's, so the merger adds both sides (+4 here).

**Footprint extensions (name each):**
- `Test/Channel/TelegramChat.cls` `TestNotices` L459-513 (it sweeps every `incident.*` key: 15 to 19 keys, 21 to 25 rows; L468's approval kind gains the two later `...Checked` keys). No open epic touches it, but check `git diff --name-only` for 33/39/40/11 first.
- Doc lines only: `Fix/Kind.cls` L105 and `Fix/Msg/DryRunResult.cls` L1-3 ("exactly the keys of DRYRUNKEYS" becomes "the keys of DRYRUNKEYS, and the kind's own transient keys such as repair_resend's goodCheck, which are never stored"). No property changes.

**New:**
- `Test/Watch/GoodMessages.cls`. It extends `Test.Watch.Case`, runs fresh, and is in Area Watch, so `shard:lane-a@Checks,Install,Watch` runs it in group `shards` with no `ci/units.sh` entry. Patterns:
  - `Test/Fix/EitherWay.cls` `TestNoEvidenceNoRequest` L92-115 (L99-114 is the no-fix assertion set; `OnAfterOneTest` L49-56 removes warnings);
  - `Test/Fix/DryRun.cls` `TestFiftyOrdersChangeNothing` L109-159 (the `Snapshot.Take/Diff` and `Contract.Mock` `LogMark` L471 / `LogSince` L484 template);
  - `Test/Fix/Execute.cls` L59 (`Approval.Answer`), `Case` `WaitRun` L1748, `WaitResultNotices` L1975, `WaitCompleted` L1833, `Raised` L1591, `Noticed` L1618, `NoticeBodies` L1439, `Requests` L348, `HeadersBetween` L362, `SetOrderDate` L2023, `HeaderIds` L765, `AskDryRun` L2102, `DropIncidentRows` L1668.

**Read only, evidence:**
- `Fix/Executor.cls` L153-176: a kind's error becomes `Reason` (redacted, at most 1000), and the dry run passes through as `dryRun.%ToJSON()` (L164), so `goodCheck` reaches `Proposed` with no change. L958: copies are `ResendDuplicatedMessage(id, , original TargetConfigName, copy)`, with no new source.
- `Watch/IncidentManager.cls` `Proposed` L874-877 (Reason → warning → `Decline` L952 → `NoFix` L976, or `Unask` for a later round).
- `Watch/Reader.cls` L372: an evidence failure gives `headerId, sessionId, superSession, timeCreated, timeProcessed, sourceConfigName, targetConfigName, bodyClass, bodyId, status, isError, error, body`.
- `Fix/Reformat.cls` L43 `Convert`, L59 `Reads`. `Demo/Orders/{Partner,PartnerOrder,Translator,Transform}.cls` (Task 0).
- `web/e2e/demo-path/07-failure-paths.spec.ts` L82, L98 and `web/e2e/demo-path/telegram-approval.spec.ts` L98, L146 (`text.includes('Approve?')`), L184: later presses in the README session after 05's 50 copies completed, so their notices get the `...Checked` keys. `support/demo-path.ts` L301-329 checks the card and the buttons, not the notice text. `web/e2e-online/demo-path/demo-path.spec.ts` presses once.
- `Live/Payload/Approval.cls` (`FromRow` calls `Notice.Reading` over the stored dry run only) and `web/src/app/approvals/approval-view.ts` L220-239: unchanged.

## Tasks & Acceptance

**Execution:**
- Task 0 (implement stage, first fresh run of `Test.Watch.GoodMessages`; record under Verification):
  - (a) the Status, IsError and Type of the good headers `Good` returns (expected 9, 0, 1; inference for IsError and Type);
  - (b) that an untagged order's SuperSession reads back as "" and the empty-SuperSession row of the matrix holds;
  - (c) the class time on a fresh lane-D stack; if it is over 300 s, split the class in two (`GoodMessages`, `GoodMessagesLater`).
- `Watch/Reader.cls`:
  - Add `Good(namespace, production, item, references As %String, limit As %Integer, Output good As %DynamicArray) As %String`. `references` are comma-separated failed header ids. It gives read, unreadable or not_current like `Evidence`, under the same two checks, and calls `Current` with the keys `g<id>,...`, `limit` and `item`. `good` holds the snapshot's failures (the Evidence failure shape) and nothing else.
  - In `Current`: a key `g<id>` reads that header's SourceConfigName, TargetConfigName, MessageBodyClassName and SuperSession, then `SELECT TOP ? ID ... WHERE Status = 9 AND IsError = 0 AND Type = 1` with the four equal (an empty SuperSession matches only an empty one) `ORDER BY ID DESC`, and appends the ids not already listed. It calls no OcuTalon class there.
  - Update the class doc and `Current`'s doc. AD-3: no second switching method. Rule 2: the per-header read is Evidence's.
- `Fix/Kind/RepairResend.cls`:
  - Add `Parameter GOODMAX = 20;`, `Parameter GOODCHECK = "goodCheck";` and `Parameter GOODCHANGED` (the log reason, with the two counts: "The repair would also change {changed} of the {checked} messages from the same source that went through", filled in with `$Replace`).
  - Add a public pure `GoodChanges(body, parameters) As %Boolean`: `Readable(...) = ""` and the repaired value differs from the current one.
  - In `DryRun`, after the evidence refusal and only with targets: work out the references, call `Reader.Good(incident.Namespace, incident.Production, <the first group's ItemName>, references, ..#GOODMAX, .good)`, return an error for an outcome other than read, and count checked and changed. With changed above 0, return the GOODCHANGED error. Otherwise set `goodCheck` after the DRYRUNKEYS loop.
  - Update the class and method docs. AC 1, AC 3.
- `Watch/IncidentManager.cls`:
  - In `Proposed`, set `row.DryRun` to the JSON of a copy of `dryRun` holding only the keys of `DRYRUNKEYS` (in their order).
  - Pass the whole `dryRun` to `WithFixKey` and `WithFixSlots`, as today.
  - Update the docs (L94, L863). AC 2, AC 4.
- `Watch/Notice.cls`:
  - Add the parameters `KEYWITHFIXCHECKED`, `KEYLATERCHECKED`, `KEYWITHFIXEITHERCHECKED` and `KEYLATEREITHERCHECKED`.
  - `WithFixKey`: when `dryRun.goodCheck.checked` is at least 1, give the `...Checked` variant of today's choice.
  - `WithFixSlots`: then add `goodChecked`, `goodChanged` and `goodNoun`. A `goodCheck` that is not an object or has non-integer counts is refused like a bad dry run ("" with sc).
  - Update the class doc's key table. AC 2.
- `Msg/Catalog/Watch.cls`: one block with `incident.withFixChecked`, `incident.laterRequestChecked`, `incident.withFixEitherWayChecked` and `incident.laterRequestEitherWayChecked`, per Always, with the ruled line in all four forms (text, web, one.text, one.web) of each key. AC 2.
- `Test/Msg/Catalog.cls`: the four keys in `Keys`, `Fixtures` (the exact ruled texts) and `OneForms`, each appended right after the `incident.laterRequestEitherWay` lines, and the counts (Code Map). This is the shared surface.
- `Test/Channel/TelegramChat.cls`: the counts and the approval kind (Code Map). This is the shared surface.
- `Test/Watch/Case.cls`: add `SendOrders(count, traceRef, orderDate, dateFormat = "MM/DD/YYYY")`, with the default unchanged, and `WaitGood(ref, count)`, which waits for count Completed PartnerOrdersIn→OrdersFromPartner headers of ref. Update the class doc. Rule 2: extend, don't copy.
- `Test/Watch/GoodMessages.cls` (new): the matrix's production rows:
  - `TestFewerThanTwentyGood` (Integration AC and the read-only proof);
  - `TestOnlyTheNewestTwenty`;
  - `TestOneGood`;
  - `TestNoGoodMessages`;
  - `TestOneChangedGoodWithholdsTheFix`;
  - `TestOtherSourcesAndSessions` (it also calls `Reader.Good` directly: newest first, the limit, no failed or queued header);
  - `TestApprovalRunsTheDryRunOnly`, with the later round;
  - `TestLaterRoundRefused`;
  - `TestUntaggedOrders`.
  Each test uses its own ref, removes its warnings and drops its rows (`DropIncidentRows`). Add the class doc per Rule 14.
- `Test/Fix/Kind.cls`: `TestGoodChanges` (pure; the matrix row "Converts to itself").
- `Test/Fix/SnapshotDiff.cls`: `TestGoodBodyEditIsAChange` (pure: a changed body value of a header that is not in the allowed sessions is one Diff line), so the read-only proof's Diff is pinned for bodies of messages that went through.
- `Test/Fix/DryRun.cls`: L154 and L213 become "DRYRUNKEYS plus goodCheck", with `goodCheck` `{"checked": 0, "changed": 0}`.
- `Test/Watch/NoticeText.cls`: add `TestGoodLine` (pure). It covers `WithFixKey` for checked 0 and 1 across the four parents and later; `WithFixSlots` (goodNoun "order" or "orders", a bad `goodCheck` refused); and `Render` of each new key on phone, telegram and web, many and one forms, equal to the `Test.Msg.Catalog` fixtures.
- `EXPERIENCE.md`: under each of the two entries, a bullet with the ruled line and when it shows, marked `[ADDED 2026-11-06, Story 7.9, owner decision by the Contest Planner under the owner's delegation (2026-11-06T01:15Z); text ruled by the Planner at the spec gate]`. No existing line changes, the UJ-1 instance included, since a first press finds no good order.

**Acceptance Criteria:**
- AC 1: Given a validated repair_resend dry run with targets, when it runs, then it reads at most the newest 20 good messages for each reference through `Reader.Good`, and counts checked and changed by the rule in Always. Those counts are the ones the delivered notice's slots and rendered phone text show (`goodCheck` carries them there). During it nothing changes in either namespace and the mock receives no request.
- AC 2: Given a dry run whose check changed none of at least one checked good message, when the notice or later request is sent, then its key is the `...Checked` variant and every channel's text has the ruled line with the real counts. With none checked, the key and text are today's (pending PT-a).
- AC 3: Given a dry run whose check would change any good message, when it finishes, then no request is raised and the incident gets `incident.noFix` open `no_fix` (a later round: nothing sent), with one warning naming GOODCHANGED.
- AC 4: Given an approved request whose dry run had the check, when `FixExecutor` runs it, then it resends repaired copies of exactly the dry run's targets with the ask's kind and parameters, no good message is resent or changed, and the stored dry run has exactly `DRYRUNKEYS`.
- AC 5: Given the story's changes, when `live:demo-path` and `live:online-demo-path` run, then they pass. The later presses of 07 and T8 carry the line, and T8 still finds "Approve?".

## Spec Change Log

## Review Triage Log

## Design Notes

**Task 0 (plan stage).** Slot D (`ocutalon-slot-d`, IRIS 2026.3.0AI build 154U, checked with `iris_server_info`) has no OCUORDERS namespace (its namespaces are %SYS, HSCUSTOM, HSLIB, HSSYS, HSSYSLOCALTEMP, OCUTALON and USER), and OCUTALON holds no `Ens.MessageHeader` row (read-only `SELECT ... GROUP BY Status`, 0 rows). So these facts come from the code and from tests that already pass:
- *The same source.* A demo order fails at `OrdersFromPartner`. Its header is `PartnerOrdersIn` → `OrdersFromPartner`, body `OcuTalon.Demo.Orders.PartnerOrder`, Status 8, with IsError unset (`Translator.cls` doc; `Test.Demo.Production.TestOneOrderInEachFormat` L153-200). A good order has a header with the same source, target and body class, Status 9 and OrderDate "2026-10-16". Its second header, `OrdersFromPartner` → `OrdersToWarehouse` (a `WarehouseOrder` holding a day number), has another source and is not checked. Each order is in its own session and carries the batch's trace reference as SuperSession (`Partner.cls` L60-66).
- *Repaired copies are good messages.* `Ens.MessageHeader.NewDuplicatedMessage` (irislib `Ens/MessageHeader.cls` L458-503) clones the header (`%ConstructClone`). It keeps SourceConfigName and SuperSession unless a new source is given, sets the body class from the new body, and writes `Description` "Resent <id>". `Fix/Executor.cls` L958 passes no new source and the original's target. So after a fix, its completed copies (YYYY-MM-DD) are good messages of the same tuple (inference until Task 0 (a)).
- *What good orders hold.* YYYY-MM-DD ("2026-10-16", or a copy's repaired value). Under the demo's source format MM/DD/YYYY, `Reformat.Reads` refuses it, so it is unchanged and the demo repair keeps being proposed.
- *Which good messages the demo has.* `Partner.Send` is called with YYYY-MM-DD only by tests (`Test.Demo.Production`, `BreakFeedProduction`). The press (`Demo/PartnerTrigger.cls` L17, L74) always sends MM/DD/YYYY. So a first Break the feed on a fresh demo finds no good order: the line does not show (PT-a), and the notice is today's. A later press in the same session after an approved fix finds the copies (up to 20): `live:demo-path` 07 (two presses) and T8 show the line (Code Map). The online demo path presses once.
- *How to read the last 20.* There is no read of good messages yet (`Reader` reads Status 8 or headers by id). AD-3 allows one switching method, `Current`. The read goes in it as the key kind `g<id>`, reusing the `limit` argument, which the evidence mode does not use, so its signature does not change. The non-overlap with Epic 17's hunks was checked on `OCT-epic17` `073656c9`. Verification proves it with `git merge-file`.
- *Hermeticity.* `Case.SendOrders` sends MM/DD/YYYY only, and the only senders of good orders use fresh refs. Because good messages must share the target's SuperSession, no existing IRIS test changes its key (a sweep of `Test/Fix/*`, `Test/Watch/*` and the fixture-seeded specs). Caution: `Test.Fix.Raise.TestInstanceWatchers` (`Fail(n, "")`) would flip if any test left untagged completed orders. None does, and the new tests send untagged orders only in `TestUntaggedOrders`, then assert on that test's own rows. Because a stack's earlier untagged leftovers would count, that test asserts goodChecked at least the number it sent, and its key is the `...Checked` one.

**Decided in-stage (small, reversible, within the intent):**
- "Same source" is the tuple SourceConfigName, TargetConfigName, body class and SuperSession of a target, with one reference per distinct tuple. The SuperSession keeps the check inside the incident's scope (AD-4: one visitor's dry run never reads another's orders on the online demo) and makes tests hermetic. The body class makes the field exist. Rejected: SourceConfigName alone (other sessions' orders, the warehouse leg); scope through `FailurePoller.Scope` (an OcuTalon call cannot run inside the switch, and filtering after the read breaks "the last 20").
- Checked counts every good message read, and changed follows the rule in Always (the lead's item 2). The text comparison makes a value that converts to itself unchanged.
- Resent copies count as good messages: the production accepted them, and testing the repair on them proves it leaves its own output alone.
- The counts travel in `goodCheck` on the kind's answer (`DryRunResult.DryRun`), and the row stores only DRYRUNKEYS. Nothing stored changes (AD-16's stored keys; `Test.Data.Tables` L13 untouched), and no `Fix/Msg` property changes. Rejected: stored keys (a stored-format change, a veto item, a contended bridge edit and both pinning tests); a `DryRunResult` property (an AD-16 amendment); IncidentManager reading again (a second read and a time-of-check gap, as 7.7 found).
- `goodCheck` is present on every answer with targets, 0 and 0 included, so the two `Test.Fix.DryRun` assertions name it. The notice decides by `checked`.
- Catalog: four new variant keys, not a change to the four existing ones. An appended block is a plain union in a contended file, existing pins stay honest, and the catalog has no composition. It costs four more copies of the parents' text (DW-655's kind; noted for its owner). `goodNoun` is a text slot, because a noun slot follows the `count` slot only (`Msg/Catalog.cls` L198-209), as 7.7's `item` did.
- A failed good-message read refuses the dry run (fail closed). It is the same namespace and the same checks that `Evidence` just passed, so it is not expected (inference).
- The new tests go in a new Watch-area class: group `shards` measured 1,575-1,671 s clean (Epic 11 runner report, 2026-11-06T04:40Z), plus the class (estimated 150-300 s on CI, inference), stays under 35 minutes (2,100 s). `shards-2` (`lane-a@rest`, the Fix area) measured 2,031 s on `5fef1125` (2026-11-06T12:39Z), so no fresh Fix-area test is added there. `ci/units.sh` is unchanged.
- The refusal reason GOODCHANGED is a log reason, like NOEVIDENCE, never shown.
- Size: one implement pass (about 7.7's size). If the Planner rules a zero-form line (PT-a, option Z2), four more keys are needed. Proposed split then: 7.9 keeps the check, the refusal and the checked line, and a sibling 7.10 adds the zero form. Not split here.

**Proposed public text (for the Planner's ruling).** Every string below is a PLACEHOLDER until the Planner rules. The fixed-strings tests (`Test.Msg.Catalog` Fixtures, `Test.Watch.NoticeText.TestGoodLine`, `GoodMessages` phone-text assertions) are written with the ruled strings.
- **PT-a, the new notice line.**
  - Many and one (goodChecked 2 or more, or 1), inserted in `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` in the new block right after L167 (the end of `incident.laterRequestEitherWay`). In each of the four keys' `text`, `web`, `one.text` and `one.web`, it goes right after "I'll resend {resendCount} repaired copies; the originals stay unchanged." (one form: "I'll resend 1 repaired copy; the original stays unchanged.") and before " Nothing has changed yet.":
    - `Checked against the last {goodChecked} {goodNoun} from the same source that went through: {goodChanged} would change.`
    - With 20: "Checked against the last 20 orders from the same source that went through: 0 would change."
    - With 1: "Checked against the last 1 order from the same source that went through: 0 would change."
    - Alternative wording: `Of the last {goodChecked} {goodNoun} from the same source that went through, the repair would change {goodChanged}.`
  - The keys it goes into: `incident.withFixChecked`, `incident.laterRequestChecked`, `incident.withFixEitherWayChecked`, `incident.laterRequestEitherWayChecked`.
  - Zero good messages, recommended Z1: no line; the notice keeps today's key and text. It claims nothing, keeps every existing pin and the first demo press's text, and needs no keys. Option Z2: a zero line in four more keys, for example `No {goodNoun} from the same source had gone through yet, so there was nothing to check the repair against.` (goodNoun the `other` form).
  - Fewer than 20: the count is the real number (as above).
  - EXPERIENCE.md bullet (under L821's and L885's entries): `- **Checked against good messages** [ADDED 2026-11-06, ...]: when the dry run tried the repair on at least one message from the same source that went through, and it would change none of them, the Dry run paragraph adds, before "Nothing has changed yet.": "<the ruled line>"`.
- **PT-b, no-fix wording.** Reuse `incident.noFix` exactly, as the owner's scope says: `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:179-180`, "{count} {itemNoun} failed since {time}. {cause}. None of my fixes applies to this, so I'm not proposing one. Nothing was changed." No new user text. The refusal's log reason, which is not user text, is GOODCHANGED (above). The Planner may note what 7.7's review noted: "None of my fixes applies" fits loosely when the fix exists but would rewrite good messages.
- **PT-c, existing lines that change.** No existing catalog key or user-facing text changes. EXPERIENCE.md only gains the two bullets. The existing test lines that change are not public text (Code Map).
- **PT-d, the web incident card.** Should the card's dry-run block show the line too? Recommended: not in 7.9. The card is built from the stored row (`Live.Payload.Approval.FromRow`), which does not hold the counts. Showing them needs either the counts stored (a stored-format change, a veto item, and contended bridge and `Test/Data/Tables` edits) or a second read at payload time. 7.9's ACs name the notice's paragraph (as 7.7 did; 7.8 later added its card row). If wanted, plan it as a sibling story, the way 7.8 followed 7.7.
- **PT-e, demo visibility (a question, not text).** On a fresh demo the first press finds no good order, so with Z1 the line shows from the second press on (demo-path 07, T8) and never on the online demo's single press. Recommended: accept for the Saturday release. Having the press send a few good orders first would change Epic 4/16 files and the demo's timings.

**Governing ADs:**
- AD-3: Reader's one switching method; Fix calls Reader.
- AD-16: the kinds, read only, no model, the stored dry run's keys unchanged, and the executor trusting the row.
- AD-11: the row is the truth: approval runs the row's kind, parameters and targets.
- AD-15: IncidentManager is the one writer, and the notice variants: with fix, no fix, later request.
- AD-32: keys and slots only; Catalog renders in the `*Out` operations.
- AD-4: the scope through SuperSession.
- AD-6: Reader makes no AI Hub or Python call.
- AD-22: throwaways and the mock.
- AD-29 and AD-33: Lane A files.

No AD Rule is contradicted and no AD changes.

**Integration ACs, Consumes, Consumed-by (Rules 1 and 2):**
- `Reader.Good` is a new read method. Integration AC: matrix row 1. `RepairResend.DryRun` reads it over the real production, `IncidentManager` delivers `incident.withFixChecked`, and `SimPhoneOut`'s rendered phone text shows the line with the counts. The withholding row is the second Integration AC.
- Consumes:
  - 7.1: `RepairResend.DryRun`, `Readable`, `Fix.Snapshot`.
  - 7.2 and 7.6: `Proposed`, `NoFix`, `Decline`, V2.
  - 7.3: `Execute` and the row.
  - 7.7: the refusal route, the either-way keys and `Notice.WithFixKey`.
  - Epic 0: `Msg.Catalog` and the mock.
- Consumed-by: none; 7.9 is Epic 7's last story. The card row would be PT-d's sibling.

**Extend, don't copy (Rule 2):**
- `Good` reuses `Current`'s per-header Evidence read (no second reader).
- `GoodChanges` extends `Readable`.
- The new keys extend `WithFixKey` and `WithFixSlots` (no second builder).
- `SendOrders` gains `dateFormat`.
- The tests reuse `Fix.Snapshot`, `Contract.Mock` `LogMark`/`LogSince` and EitherWay's no-fix assertion set.
- The catalog copies its parents because it has no composition (the copy the catalog forces, as in 7.7).

**Ledger inbox:** none, and this story owns no ledger entries.

## Verification

`<laneD>` stands for `env OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root. Rules for every run:
- One command per foreground call with `timeout: 600000`, and never two IRIS test runs in one message.
- At most one fresh throwaway at a time in lane D. Pure classes may instead run on slot D (`server` `ocutalon-slot-d`, namespace `OCUTALON`, after `iris_doc_load` of the changed classes), one `iris_execute_tests` per message.
- The shards are left to CI.

**Commands:**
- (loop) `<laneD> OCUTALON_RUN_TAG=e7s9iw ci/warm.sh up`, once per stage. Expected: READY.
- (loop) `<laneD> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s9iw ci/iris.sh class <Class>`, one call each, for `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Fix.Kind` and `OcuTalon.Test.Fix.SnapshotDiff`. Expected: `CLASS ... passed`.
- (loop) `<laneD> OCUTALON_RUN_TAG=e7s9i ci/iris.sh class <Class>`, fresh, one call each:
  - `OcuTalon.Test.Watch.GoodMessages` (first: Task 0);
  - `OcuTalon.Test.Fix.DryRun`;
  - `OcuTalon.Test.Fix.EitherWay`;
  - `OcuTalon.Test.Fix.Raise`;
  - `OcuTalon.Test.Fix.Later`;
  - `OcuTalon.Test.Watch.Diagnose`;
  - `OcuTalon.Test.Watch.Evidence`.

  Expected: passed.
- (once) `<laneD> OCUTALON_RUN_TAG=e7s9i ci/iris.sh class OcuTalon.Test.Channel.TelegramChat`. Expected: passed.
- (once) `<laneD> OCUTALON_RUN_TAG=e7s9i ci/iris.sh build`, then `... live demo-path`, then `... live online-demo-path`, one call each. Expected: passed (AC 5). If one dies of its local deadline with no failed test, add `OCUTALON_LIVE_DEADLINE=900`.
- (once) `bash docker/tests/test-ci-config.sh`, `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh`, one call each. Expected: PASS.
- (once) The merge check. For each of `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` and `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`, write `git show $(git merge-base HEAD OCT-epic17):<path>`, the working file and `git show OCT-epic17:<path>` to three files under the stage's own scratch folder, then run `git merge-file -p --diff3 <ours> <base> <theirs> > /dev/null`. Expected: exit 0, no conflict. For `Test/Msg/Catalog.cls`, the count lines are expected to conflict; report them for the merger.
- (once) `<laneD> OCUTALON_RUN_TAG=e7s9iw ci/warm.sh down`, then `<laneD> OCUTALON_RUN_TAG=e7s9i ci/iris.sh teardown`. Run them also after a failure.

**Shared surfaces:**
- The message catalog: Watch keys 49 to 53, total 154 to 158, web wordings six to ten, noun forms 16 to 20, one forms 11 to 15 (`Test.Msg.Catalog`). Epic 17 changes the same count lines.
- `Test.Channel.TelegramChat.TestNotices`: 15 to 19 keys, 21 to 25 rows, and the approval kind of the two later `...Checked` keys.
- The kind's dry-run answer keys: DRYRUNKEYS plus `goodCheck` (`Test.Fix.DryRun` L154, L213). The stored DRYRUNKEYS (`ApprovalRequest`, `Test.Data.Tables` L13) and the web approval payload (`Live.Payload.Part.DryRun`, `Test.Live.Payloads`) are unchanged.
- The notice slot sets: `goodChecked`, `goodChanged` and `goodNoun` on the `...Checked` keys only (`Test.Watch.NoticeText`).
- The demo path's later notices: demo-path 07 and T8 now get the line, and T8 reads "Approve?".
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply (Rule 19).** The implement stage applies each one, observes red, reverts byte-identically, and records `mutation: ... -> ...`.

| AC | Mutation | Expected red |
|---|---|---|
| AC 1 | `Good` drops the SuperSession condition | `GoodMessages.TestOtherSourcesAndSessions` |
| AC 1 / cap | `GOODMAX` 25 | `GoodMessages.TestOnlyTheNewestTwenty` |
| AC 1 / rule | `GoodChanges` ignores the text comparison | `Fix.Kind.TestGoodChanges` (converts to itself) |
| AC 1 / read only | the `g` block in `Current` sets each good body's OrderDate to "x" and saves it | `GoodMessages.TestFewerThanTwentyGood` (the Snapshot Diff), `SnapshotDiff.TestGoodBodyEditIsAChange` stays green |
| AC 2 | `WithFixKey` ignores `goodCheck` | `GoodMessages.TestFewerThanTwentyGood`, `NoticeText.TestGoodLine` |
| AC 2 / zero | `checked >= 0` in place of `>= 1` | `GoodMessages.TestNoGoodMessages`, `Watch.Diagnose.TestDemoDiagnosis` |
| AC 3 (the owner's demonstrated mutation) | the GOODCHANGED refusal removed | `GoodMessages.TestOneChangedGoodWithholdsTheFix`, `TestLaterRoundRefused` |
| AC 4 | `Proposed` stores `result.DryRun` unstripped | `GoodMessages.TestApprovalRunsTheDryRunOnly` (stored keys) |
| AC 4 / targets | `Execute` gets the good ids added to the targets (test-only patch in `Proposed`: `row.FixTargets` plus one good id) | `GoodMessages.TestApprovalRunsTheDryRunOnly` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

The spec is planned for implementation. The strings under "Proposed public text" (PT-a to PT-e) are placeholders for the Planner's ruling, which the runner relays before any implement. Contended edits:
- `Watch/Reader.cls`: four self-contained blocks, not overlapping Epic 17's hunks.
- `Msg/Catalog/Watch.cls`: one appended block.
- `Test/Msg/Catalog.cls`: appended blocks, plus count lines that collide with Epic 17's.
