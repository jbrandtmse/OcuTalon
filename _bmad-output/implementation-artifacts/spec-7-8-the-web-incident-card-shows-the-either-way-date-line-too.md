---
title: 'The web incident card shows the either-way date line too'
type: 'feature'
created: '2026-11-04'
status: 'done'
baseline_revision: '09afe57af1acf1246a406698788b1036eadc23d1'
baseline_commit: '09afe57af1acf1246a406698788b1036eadc23d1'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: 'At 1280x600 the incident card with the demo reply cause and fix summary already has Approve and Reject below the fold, with no either-way row.'
    evidence: 'Measured at plan (Design Notes, table): A6 conditions with the mock reply cause and fix summary, Approve bottom 555 against the list bottom 518, 37 px past it. A6 passes only because its fixture cause is one short line.'
    location: 'web/e2e/cards/approval-card.spec.ts A6; web/src/app/chat/chat-panel.ts'
    severity: 'med'
---

<intent-contract>

## Intent

**Problem:** Story 7.7 shows U-249's either-way line in the notice's Dry run paragraph only. People on the demo path approve on the web incident card, whose dry-run block does not show it (DW-645), so the evidence for a date repair's reading is missing where the decision is made. Until November 13 every date the demo partner sends is ambiguous this way.

**Approach:** `Live.Payload.Approval.FromRow` asks the notice's own rule (`Watch.Notice.Reading`) over the row's stored dry run and `FixParameters`, and carries the answer as two new payload fields, `eitherWay` and `reading`. Nothing new is stored. `web/scripts/catalog.mjs` cuts the line out of the two catalog entries that already hold it, so the page's generated catalog has it with no second typed copy, and `approval-view.ts` renders it as one unlabelled row of the dry-run block.

## Boundaries & Constraints

**Always:**
- One rule: the payload's `eitherWay` is 1 exactly when `Notice.Reading(dryRun, parameters)` is not empty, called with the row's stored dry run and `FixParameters`, the same two values `IncidentManager.Proposed` gave `WithFixKey` when it chose the notice's key (`row.DryRun = result.DryRun`, `row.FixParameters = ask.Parameters`). `reading` is that method's answer. Neither the page nor the payload class looks at a date.
- One wording: the words exist only in the catalog entries `incident.withFixEitherWay` and `incident.laterRequestEitherWay` of `Msg/Catalog/Watch.cls`. `catalog.mjs` derives the page's text from them and fails closed if the eight forms do not give one many form and one one form.
- The row's slots match the notice's for the same approval: `{reading}` is `dryRun.reading`, `{item}` is `dryRun.itemNoun.one` ("message" when absent, as the notice's code noun), the count and the one-or-many choice are `dryRun.resend` (the notice's `resendCount`).
- The row shows when `eitherWay` is true, `reading` is not empty and `resend` is a number of at least 1; otherwise it is absent. It stays on an answered request, as the block's other rows do, because the notice's line does not depend on the state.
- The row sits where the notice has the sentence: after After, before Will resend. It has no label and its own class (`dry-either`), never `dry-note`: `web/e2e/support/demo-path.ts` L314 and `web/e2e/floor/approval.spec.ts` L144 read `.dry-note` as one element.
- `FromRow` stays the one builder (live events, REST, the rail, `AnswersIn`). `payloads.ts` and `msg/catalog.ts` are generated, never hand-edited.
- CI mock only, lane-B throwaways only. Rule 14: ASCII, comments state the contract.

**Never:**
- No change to `DRYRUNKEYS`, to any stored dry run, to `Fix.Kind.RepairResend`, `Fix/Msg/**`, to `Bridge/**` or to any table. No stored flag.
- No text on the payload and no render in `Live/**`: AD-32 and the convention "Text OcuTalon sends" allow only `*Out` operations and the page to render.
- No second typed copy of the line in `APPROVAL_TEXTS` or anywhere under `web/src/app` but the generated catalog. No new key in `Msg/Catalog/*.cls`, and no change to `Msg/Catalog/Watch.cls` or `Test/Msg/Catalog.cls`.
- No new label or text. No change to the words of any row of the card.
- Nothing under `docker/**`, `Install/**`, `src/module.xml`, `module.xml`, `preload/**`, `src/cpf/**`, `release/**`, `install.sh`, `ci/units.sh`, the workflows, `Demo/**`, `eval/**`, `_bmad/`, `.claude/`. No existing e2e spec is edited but `web/e2e/support/iris.ts`, named below.
- DW-655 (the two keys copy their parents) is not fixed here.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Either way, real path (Integration AC; DW-645) | `Test.Fix.EitherWay` press: 3 orders 11/03/2026, arrival 2026-11-04T02:00:00Z; the real dry run, `Approval.Raise` and notice | `FromRow(row).DryRun`: `EitherWay` 1, `Reading` "month first", equal to the Notification's slots `reading`; `ItemNoun.One` = slot `item`; `Resend` = slot `resendCount`. Stored dry run keys still exactly DRYRUNKEYS | none |
| Either way on the card, many (DW-645) | pending request, dry run 50 of 50, `before` 11/04/2026, `FixParameters` sourceFormat MM/DD/YYYY | the row reads "All 50 dates are valid whether read month first or day first. Read month first, they match the day each order arrived.", between After and Will resend; the server's `Catalog.Render` of `incident.withFixEitherWay` for the same slots holds that text | none |
| One form, day first (DW-645) | resend 1, `before` 03/11/2026, sourceFormat DD/MM/YYYY | "The date is valid whether read month first or day first. Read day first, it matches the day the order arrived." | none |
| Later round | `TestLaterRoundKeepsTheLine`'s second request | its payload carries `eitherWay` true, `reading` "month first", resend 2: the rule needs no special case | none |
| Day above 12 (DW-645) | `before` 10/16/2026, or a mixed set whose example is 11/13/2026 | payload `eitherWay` false, no `reading`; no row | none |
| Same-date values only | `before` 11/11/2026 | as above: no flag, no row (U-250) | none |
| Mixed same-date and differing | `TestBothReadingsMatchMixedWithTolerance` | flag and row, as the notice shows the line (U-250) | none |
| No either-way case | sourceFormat YYYY-MM-DD; a `tool_call` or `setting` row with empty `FixParameters` | no flag, no row | none |
| Broken parameters | `FixParameters` "not json" | the dry run's other fields stay; no flag | none |
| Unknown noun | dry run `itemNoun` {message, messages}, or none | `{item}` "message" | none |
| Answered | the either-way request approved or rejected | the row stays; "Nothing has changed yet." goes | none |
| Reload | the page reloads with the request pending | the row is there from the snapshot (`Web/Api` through `FromRow`) | none |
| Short screen (Q1) | 1280x600, A6's conditions, the row showing | the headline, cause, dry-run count, Approve and Reject in the chat list's view | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated. Lines as of `ae68a4a1d6a2613ba9ee2a87c4d22f0861681af3`.

**Changed (footprint, U-252):**
- `Live/Payload/Approval.cls`: `FromRow` L62, the dry-run mapping L85-103 (add after the `itemNoun` block, inside the Try); its doc above L62.
- `Live/Payload/Part/DryRun.cls`: L1 doc ("its keys are the keys of ... DRYRUNKEYS"), properties. payloads.mjs takes `%Boolean(...) [ InitialExpression = 0 ]` as the other payload classes write it.
- `web/src/app/live/payloads.ts`: generated (`npm --prefix web run payloads`).
- `web/src/app/approvals/approval-view.ts`: `DryRunView` L67, `dryRunView` L181 (gets `ctx`), its call L268, class doc. `ctx.render` is `renderPageText`; `nounFor` L173, `numberOf`, `textOf`, `APPROVAL_TEXTS.nounOne` L52 are the helpers to reuse.
- `web/src/app/approvals/approval-request-card.ts`: template L123-134 (the row goes between the After and Will resend blocks), styles L271-321, imports L16-31 (`HEIGHT_QUERIES`).

**Footprint extensions (name each in the completion contract):**
- `Watch/Notice.cls` L155 `Reading`: drop `[ Private ]`, nothing else but its doc line and class doc L15-19 (no behaviour change; no open epic touches the file).
- `web/scripts/catalog.mjs`: `LISTED_KEYS` L52, `TEXT_SLOT_KEYS` L101, `pageText` L188, `generate` L336-368, header L10-39. Not contended.
- `web/src/app/msg/catalog.ts`: generated (`npm --prefix web run catalog`).
- `web/scripts/catalog.test.mjs` (real-tree key list L94-102, fixture `WATCH` L460), `web/scripts/approval-view.test.mjs` (`deepEqual` L65), `web/scripts/approval-sources.test.mjs` (`order` L177), `web/scripts/playwright-projects.test.mjs` (L264-270, `cards.length` 20).
- `web/scripts/floor-sources.test.mjs`: `used` L460-461 pins `HEIGHT_QUERIES`' only user; header L10.
- `web/src/app/shared/layout-view.ts`: doc L8 only (`HEIGHT_QUERIES` and its value do not change).
- `web/e2e/support/iris.ts`: `ApprovalFields` L693, `seedApproval`'s `properties` L732 (`Fixture.SetFields` already sets any row property).
- `web/e2e/cards/either-way.spec.ts`: new. Pattern: `approval-card.spec.ts` (A6 L320), `web/e2e/support/approvals.ts` `raise`, `incidentOf`, `refOf`; `irisScript` of `iris.ts` L93 for the server's render.
- `Test/Fix/EitherWay.cls` (Story 7.7's), `Test/Watch/Diagnose.cls` L65.

**Contended, one self-contained edit each (report them):**
- `Test/Live/Payloads.cls` (Story 39.7 may edit it): one method appended after `TestNotificationFromRow` L730, two lines in the `OcuTalon.Live.Payload.Part.DryRun` block of the XData L1045-1054 (`TestContracts` L77 pins each property). The second to merge makes the plain union, then regenerates `payloads.ts`.
- `Test/Bridge/CodeRules.cls` (Epic 33 adds other lines): two names appended to each of `CALLBACKHELPERS` L78 and `SINKCLASSES` L89, and their docs. Re-check `git diff --name-only origin/feature/OCT_OcuTalon_MVP...OCT-epic<N>` for 33, 39, 40 and 11 before editing.

**Read only, evidence:**
- `Watch/Notice.cls` L147-175 `WithFixKey`, `Reading`, `READINGS` L62; L221-225 `reading` and `item` slots; `Common` L292 (`itemNoun`).
- `Watch/IncidentManager.cls` `Proposed` L867: slots L899-901, the row L914, L916 (`row.DryRun`, `row.FixParameters`), the key L927, L932. L635 and L709 are the only writers of `Incident.ItemNoun`, both before the dry run is asked.
- `Fix/Kind/RepairResend.cls` L207-215: the dry run's `itemNoun` is the incident's, else the code noun. So `dry.itemNoun.one` equals the notice's `item` for every raised request.
- `Fix/Reformat.cls` L77 `Readings`: pure.
- `Msg/Catalog/Watch.cls` L119-163: the eight forms of the line; each is bounded by "becomes {after}. " and " I'll resend".
- `Core/BridgeSink.cls` L160, L341, `Web/Api.cls` L532, L891, `Core/AnswersIn.cls` L94: the callers of `FromRow`. `BridgeSink` runs in the gate's callback (DW-177), which is why `CodeRules` lists what `FromRow` calls.
- `web/src/app/shared/layout-view.ts` L28: the `(height < 680px)` query; `web/src/app/guide/demo-guide.ts` L22, L496: how a component writes it. `web/src/app/chat/chat-panel.ts` L115-122: following stops at the headline.

## Tasks & Acceptance

**Execution:**
- `Watch/Notice.cls` -- `Reading` loses `[ Private ]`; its doc says the approval payload uses it too; update the class doc. -- one rule, two callers (Rule 2).
- `Live/Payload/Part/DryRun.cls` -- add `Property EitherWay As %Boolean(%JSONFIELDNAME = "eitherWay") [ InitialExpression = 0 ];` and `Property Reading As %String(%JSONFIELDNAME = "reading", MAXLEN = 32);`; the class doc says the two are worked out for the payload and never stored. -- AC 1; DW-645.
- `Live/Payload/Approval.cls` -- in `FromRow`'s Try, after the noun: `Set reading = ##class(OcuTalon.Watch.Notice).Reading(dry, row.FixParameters)`, and when not empty set `part.EitherWay = 1`, `part.Reading = reading`; update the doc. -- AC 1, AC 2; DW-645.
- `web/src/app/live/payloads.ts` -- regenerate. -- the type.
- `Test/Bridge/CodeRules.cls` -- append `OcuTalon.Watch.Notice,OcuTalon.Fix.Reformat` to `CALLBACKHELPERS` and to `SINKCLASSES`, and say so in their docs. -- the callback scan must cover what `BridgeSink` now reaches (no %AI, no Python; DW-177).
- `web/scripts/catalog.mjs` -- add a derived key, `incident.eitherWayLine`: `LINE_KEY`, `LINE_PARENTS` (the two entries) and the two anchors (`becomes {after}. `, ` I'll resend`) as constants; in `generate`, before the listed loop, cut the many form from each parent's `text` and `web` and the one form from each `one.text` and `one.web`, refuse (CatalogError naming the key) a missing parent, a missing anchor or forms that differ, and put a synthetic entry `{text, slots, one: {slot: 'resendCount', text}}` with the slots the cut text uses plus `resendCount`, taken from the parent's `slots`, through the existing `pageText` checks. Add the key to `LISTED_KEYS` and `TEXT_SLOT_KEYS`. Update the header. -- AC 5; Rule 2: extends the listed-key path, so `PAGE_TEXTS`, `PAGE_SLOTS`, `PAGE_ONE_FORMS` and `renderPageText` need no change.
- `web/src/app/msg/catalog.ts` -- regenerate.
- `web/src/app/approvals/approval-view.ts` -- `DryRunView` gains `eitherWay: string` ("" when the row is absent); `dryRunView(approval, pending, ctx)` renders `ctx.render('incident.eitherWayLine', { resendCount: String(resend), reading, item })` per Always; update the class doc. -- AC 3, AC 4; DW-645.
- `web/src/app/approvals/approval-request-card.ts` -- `@if (dry.eitherWay) { <div class="dry-either">{{ dry.eitherWay }}</div> }` between the After and Will resend blocks; the inherited text colour, no new token; update the doc. -- AC 3; DW-645.
- `web/src/app/approvals/approval-request-card.ts` -- Under `@media ${HEIGHT_QUERIES.compact}` (imported from `../shared/layout-view`, as `demo-guide.ts` does) and only while the row shows (a class on `.dry`), a CSS grid with `minmax(0, 1fr)` columns puts Before and After on one line and "Nothing has changed yet." on the count line. No word, no DOM order and no row in any other state changes. -- AC 6; Q1, option (a).
- `web/scripts/floor-sources.test.mjs` -- `used` gains `app/approvals/approval-request-card.ts`; the header's line on the one height query names the card too. -- the test pins `HEIGHT_QUERIES`' users.
- `web/src/app/shared/layout-view.ts` -- the doc line of `HEIGHT_QUERIES` names the card's short-screen arrangement beside the guide's compact row; no code changes. -- the doc states the contract.
- `web/e2e/support/iris.ts` -- `ApprovalFields.fixParameters?: string`, passed as `FixParameters`. -- the fixture needs the row's parameters.
- `Test/Live/Payloads.cls` -- `TestApprovalEitherWay` from unsaved rows, with the matrix rows Day above 12, Same-date, No either-way, Broken parameters, month first and day first, the `%JSONExport` shape (`eitherWay` true with `reading`; `eitherWay` false with no `reading` key), and the row's `DryRun` text unchanged; the two XData lines; class doc. -- the story's payload test; DW-645.
- `Test/Fix/EitherWay.cls` -- a private `AssertCardFields(request, slots)` that opens the row and asserts `FromRow`'s `EitherWay`, `Reading`, `ItemNoun.One`, `Resend` against the slots; called in `TestDemoRepairWhenInstanceDateIsNotUtcDate`, `TestBothReadingsMatchMixedWithTolerance` and `TestLaterRoundKeepsTheLine`; `TestBothReadingsMatch` asserts `EitherWay` 0. Class doc. -- Integration AC.
- `Test/Watch/Diagnose.cls` `TestDemoDiagnosis` -- `FromRow` of the 10/16/2026 request: `EitherWay` 0, `Reading` "". -- the day above 12 on the real path.
- `web/scripts/catalog.test.mjs` -- real tree: the key in the key list (count 50 to 51), its many and one texts equal U-249's words, `renderPageText` for 3 and 1, and each of the eight catalog forms holds the text. Fixture: `WATCH` gains the two parents; refusals for a missing parent, a missing anchor, and a one form that differs in one parent. -- AC 5.
- `web/scripts/approval-view.test.mjs` -- the `deepEqual` gains `eitherWay: ''`; new `describe`: many, one, day first, `resend` 1 against `affected` 50, unknown and missing noun, flag with no reading, reading with no flag, flag with no `resend`, answered. -- the story's web test.
- `web/scripts/approval-sources.test.mjs` -- `order` gains `dry.eitherWay` between `dry.after` and `dry.resendLine`; `dry-either` is not `dry-note`; `APPROVAL_TEXTS` holds no "valid whether read". -- AC 3, AC 5.
- `web/e2e/cards/either-way.spec.ts` -- E1 many: the row's exact text, its place, `irisScript` of `Catalog.Render("incident.withFixEitherWay", ..., "phone")` holds it, and it is still there after a reload; E2 one form, day first; E3 no row for 10/16/2026, 11/11/2026 and sourceFormat YYYY-MM-DD; E4 an answered request keeps it; E5 at 1280 by 600 under A6's conditions the five parts are `toBeInViewport({ ratio: 1 })`. -- Rule 3, real runtime.
- `web/scripts/playwright-projects.test.mjs` -- `range('E', 1, 5)` in `cards/either-way.spec.ts`; `cards.length` 25. -- shared surface.

**Acceptance Criteria:**
- AC 1: Given an approval whose date repair's dry run found every value valid both ways (the notice used an either-way key), when the approval payload is built for a live event, REST or the rail, then its `dryRun` carries `eitherWay` true and `reading` "month first" or "day first", equal to the notice's `reading` slot, with the dry run's other fields.
- AC 2: Given an approval with any value with a day above 12 in the example, same-date values only, or no either-way case, when the payload is built, then `eitherWay` is false and there is no `reading`.
- AC 3: Given that either-way approval on the web incident card, when the card shows its dry-run block, then one unlabelled row between After and Will resend shows U-249's line word for word as the notice shows it, in the same one or many form and with the same `{reading}` and `{item}`, and it stays when the request is answered.
- AC 4: Given an approval of AC 2 on the card, when the card shows its dry-run block, then no such row exists and every other row reads as it does today.
- AC 5: Given the catalog, when the page's catalog is generated, then its text comes from the catalog entries alone, and the generator refuses (exit 1) a line that differs between the entries or cannot be found; no other file under `web/src/app` holds the words.
- AC 6 (Q1): Given 1280x600 under DESIGN.md's acceptance conditions and the row showing, when the card lands, then the headline, cause, dry-run count, Approve and Reject are in the chat list's view without scrolling.
- AC 7: Given the story's changes, when the stored dry run and the tests are read, then `DRYRUNKEYS` and the stored keys are unchanged, and `live:demo-path`, the cards, floor, answers and online-demo units, the web unit tests and the catalog tests pass.

### Review Findings

Code review, 2026-11-04: full tier, four layers (blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor), no failed layer. 24 raw findings, 17 entries: high 0, med 4, low 13; 3 rejected. Every patch is applied; the runs and mutations are under Verification, "Code-review stage".

- [x] [Review][Patch] (med; fix-risk low; in-story) The matrix row Reload and E1's task were pinned by a `/state` read, not by the card: `page.reload()` changed nothing the test looked at, and a fixture incident is an event only. E7 seeds a noticed incident, so the card is drawn from the snapshot, and asserts the row on it; E1's decorative reload goes [web/e2e/cards/either-way.spec.ts]
- [x] [Review][Patch] (med; fix-risk low; in-story) AC 5's fail-closed path had four refusal branches with no case: the end anchor twice, a form with no text, an empty sentence, a slot typed differently in the two parents. Each has a fixture now [web/scripts/catalog.test.mjs]
- [x] [Review][Patch] (low; fix-risk low; in-story) "Nothing overflows" at a narrow width had no test: the grid has a height condition alone and E4 to E6 ran at 1280 wide. E8 renders it at 640 by 360 and 320 by 360; it passes, so the claim holds [web/e2e/cards/either-way.spec.ts]
- [x] [Review][Patch] (low; fix-risk low; in-story) The generator did not check that a parent's one form is chosen by `resendCount`, the slot the card chooses by: a parent chosen by `count` would have stayed green and split the card from the notice. `eitherWayLine` refuses it, with a fixture [web/scripts/catalog.mjs]
- [x] [Review][Patch] (low; fix-risk low; in-story) The real-tree case's hand loop over `Watch.cls` never ended if the XData's closing lines were gone, hanging the run. It uses the generator's `readEntries` [web/scripts/catalog.test.mjs]
- [x] [Review][Patch] (low; fix-risk low; in-story) The class docs said the two fields are never stored, against U-267: `Live.Event`'s Payload text keeps them. They now say not kept on the request or in its dry run [src/ocutalon/cls/OcuTalon/Live/Payload/Part/DryRun.cls, Approval.cls]
- [x] [Review][Patch] (low; fix-risk low; in-story) `EitherWay`'s doc misstated the rule ("every value of the example", no source format). It states `Reading`'s rule [src/ocutalon/cls/OcuTalon/Live/Payload/Part/DryRun.cls]
- [x] [Review][Patch] (low; fix-risk low; in-story) Absence for a day above 12 was pinned for month-first sources only. `TestApprovalEitherWay` gains 16/10/2026 under DD/MM/YYYY [src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls]
- [x] [Review][Patch] (low; fix-risk low; in-story) `.dry-either` had no wrapping rule, unlike the card's other free text, though it carries `{item}` [web/src/app/approvals/approval-request-card.ts]
- [x] [Review][Patch] (low; fix-risk low; in-story) `catalog.mjs` exported four constants nothing imports [web/scripts/catalog.mjs]
- [x] [Review][Patch] (low; fix-risk low; in-story) The AC 6 `mutation:` line was stale ("E5 only"): re-observed, E4, E5 and E8 go red. Line corrected under Verification
- [x] [Review][Patch] (low; fix-risk low; in-story) AC 3 "stays when answered" and AC 2 "no either-way case" had no observed red: both mutations applied and recorded under Verification
- [x] [Review][Patch] (low; fix-risk low; in-story) Test headers narrated the stage that wrote them ("E6 (QA)", "Story 7.8 (QA)"), against Rule 14 [web/e2e/cards/either-way.spec.ts, web/scripts/either-way-line-sources.test.mjs]
- [x] [Review][Defer] (med; fix-risk med; out-of-footprint) With the demo reply's cause, Approve stays past the list at 1280x600 with the row showing, about 36 px (inference: 593 less the 39 the grid saves), so AC 6 holds for short causes only. The grid gives back the row's height, so this is DW-668's overrun, not a new one [web/src/app/chat/chat-panel.ts] -- deferred: occurrence on DW-668, routed owner=burndown
- [x] [Review][Defer] (med; fix-risk low; in-story) From 680 to 707 px tall, with the guide open and the demo reply, the row puts Approve up to 28 px past the list (inference from the plan's table) [web/src/app/approvals/approval-request-card.ts] -- deferred: DW-671 by-design, ruling Q1 sets the threshold at 680
- [x] [Review][Defer] (low; fix-risk low; out-of-footprint) EXPERIENCE.md names neither the row nor the arrangement -- deferred: DW-672 wontfix-accepted, the lead's bookkeeping, Epic 40 is changing the file
- [x] [Review][Defer] (low; fix-risk low; out-of-footprint) `docker/tests/test-cards.sh`'s header omits `either-way.spec.ts` -- deferred: DW-673 wontfix-accepted, the spec's Never list keeps `docker/**` out of this story
- [x] [Smoke] (med; fix-risk low; in-story; Rule 19 hermeticity) `live cards` failed E6 once at the lead's smoke (fresh lane-B throwaway, the bundle built from the reviewed tree) and passed on an unchanged rerun: "the same date both ways: After is below Before, not beside it", expected >= 535.98, received 484.98. The second card of the loop is measured with five separate `boundingBox` calls while the chat list may still be following the new card to the bottom, so the parts are measured in different scroll positions (After's top read 52 px above Before's bottom). The fix must make E6 measure the block's parts in one consistent layout (for example one `evaluate` that reads every part's rect relative to the `.dry` block, after the card is settled), and apply the same to the helpers E4, E5 and E8 share (`edgesOf` / `beforeAndAfterShareALine`), keeping every assertion's meaning; if the layout itself moves after the card is drawn (a product cause), fix that instead and say so. Re-observe E6's and AC 6's `mutation:` lines (they must still go red) and update them. Show it stable: `live cards` passes three times in a row on fresh lane-B throwaways after `ci/iris.sh build` [web/e2e/cards/either-way.spec.ts]

**Rejected:**
- `low`: the closing records (Auto Run Result, Tasks, Footprint extensions) trail the QA stage's counts and files. The fix edits the spec's record; Rule 14 has each pass report its own runs, and the current counts are under Verification.
- `low`: the grid has no width condition. Spec-bound: Decided in-stage holds it to height alone, as ruling Q1 says; E8 now shows it does no harm.
- `false`: the other live units were not re-run after QA. QA changed test files only, so they had nothing new to run against.

## Spec Change Log

- 2026-11-04, the lead: plan halted on Q1 and Q2; ruled (Design Notes, Rulings), U-266 and U-267 filed, the project block's scope item 5 corrected, status reset to draft for the re-plan.
- 2026-11-04, re-plan: reconciled with the Rulings. The short-screen task is no longer provisional, and the matrix's short-screen row no longer points at a removed section (the one edit inside the intent block). Answer (c) cites U-267. Found at this pass: `floor-sources.test.mjs` L460-461 pins `HEIGHT_QUERIES`' users, so the short-screen task names that query, the test's pin and the doc of `layout-view.ts`. AC 7 gains a mutation row. AC 6, E5 and the short-screen task are kept; nothing was re-measured.

## Review Triage Log

### 2026-11-04 - Review pass
- verdicts: 18 findings - high 0, medium 3, low 15, false 0, maybe-false 0 (rows group findings that share a root cause)
- findings:
  - `[medium]` `patch` Blind 3 and the Verification-Gap layer: under 680px tall an answered either-way request leaves the cell beside the count line free, so Before lands beside the head and After drops to row 2; nothing tests the arrangement or the answered state at that height - fixed: the template sets `has-note` from `nothingYet`, the CSS gives the head the whole line when there is no note, and E4 (answered, 1280x600) and E5 (pending) assert Before and After share a line below the count line and the note sits on the count line (helper `beforeAndAfterShareALine`).
  - `[medium]` `patch` Blind 4 and Verification-Gap: nothing asserts the short-screen arrangement itself (same root cause as the row above) - fixed by the same assertions; mutation recorded in Verification.
  - `[low]` `reject` Blind 1 and Edge-Case 1: `Reading` could throw on a non-string `before` and drop the whole dry run - the stored dry run is written only by `RepairResend` with string values, and a parse failure already drops the dry run today; a guard adds a branch for a state nothing reaches.
  - `[low]` `reject` Blind 2 and Edge-Case 2: the flag does not look at `resend`, so a payload can say `eitherWay` for a dry run with no resend - spec-bound (Always: `eitherWay` is 1 exactly when `Reading` is not empty; the page's `resend >= 1` check is the spec's own); a raised date repair always has `resend >= 1`.
  - `[low]` `reject` Blind 5: the class doc of `Test.Bridge.CodeRules` is out of step - the doc of each of the two parameters carries the change; the class doc names no list.
  - `[low]` `reject` Blind 6 and Verification-Gap other finding 1: the per-key extra-slot loop of `catalog.test.mjs` skips the derived key - its slots are pinned by the real-tree `deepEqual`, by the fixture cases and by the generator's own check; the loop's fixture builds a catalog class entry, which the derived key cannot be.
  - `[low]` `reject` Blind 7 and Verification-Gap other finding 2: E1 compares the server's render for the many form only - the one form is compared to all four one texts of the catalog entries by `catalog.test.mjs`; a wording drift there fails the generator.
  - `[low]` `reject` Blind 8: `DAY` is taken at module load - the page clock, the seeded times and the server script use the same constant.
  - `[low]` `reject` Edge-Case 3 and 4: no `IsObject` guard on `RefIndexOpen` in two tests - a missing row fails the test loudly, which is the intended red.
  - `[low]` `reject` Edge-Case 5: a request raised before Story 7.7 shows the line though its notice never did - accepted by the lead as veto U-266 (Design Notes, Rulings).
  - `[low]` `reject` Verification-Gap: AC 3 (stays when answered), AC 4 (other rows) and AC 5 (missing parent or anchor) clauses have no mutation of their own - each AC has its recorded mutation, the clauses are pinned by E4, the `deepEqual` and the fixture refusals, and a mutation per clause is more than the table asks.
  - `[low]` `reject` Intent audit (descriptive): the short-screen grid, the visibility change and the `CodeRules` lists go beyond the intent's lists - all are in the spec's Tasks and Rulings (Q1 option a; U-267).

### 2026-11-04 - Review pass (rework iteration 1, the Smoke item)
- verdicts: 15 findings - high 0, medium 1, low 11, false 3, maybe-false 0 (rows group findings that share a root cause)
- findings:
  - `[medium]` `patch` Verification-Gap: the AC 6, AC 6 / answered and AC 4 mutation lines predate the one-pass helper, so a selector or origin slip in `layoutOf` could keep E4, E5 and E6 green unseen - fixed: all three mutations re-applied on the current spec, red observed, reverted byte-identically; lines under Verification, "Rework stage".
  - `[low]` `reject` Verification-Gap other 1: the race fix has no pinning test - the race is nondeterministic; the Smoke item's own evidence is three consecutive `live cards` passes, recorded under Verification.
  - `[low]` `reject` Verification-Gap other 2 and Edge-Case 5: E6 and the others measure right after `.dry` appears, with no settled signal - the offsets are read in one layout pass relative to the block, so scroll cannot move them, and the block and its children come from one template pass; three runs passed.
  - `[low]` `reject` Blind 1: `getBoundingClientRect` gives a zero rect for a hidden part, so the null checks pass - a hidden note gives `top = -origin`, which fails the "note is on the count line" and "note is below the rows" comparisons; nothing hides the note.
  - `[low]` `reject` Blind 2: the `Number.NaN` fallbacks are awkward - the not-null assertion fails first; cosmetic.
  - `[low]` `reject` Blind 3: the thrown message does not name the missing part and `evaluate` does not retry - the callers wait on `.dry` and its row text first, and the old per-element waits are what hid the race.
  - `[low]` `reject` Edge-Case 1: `.dry-resend` is also a `dry-row`, so index 0 and 1 shift if Before or After were absent - the old code used the same indices, and every request in E4 to E6 has both rows (E1 to E3 pin the part list).
  - `[false]` `reject` Edge-Case 2: `layoutOf` cannot see the either-way row land before After - E1, E2, E4 and E7 pin the part order with `partsOf`; the helper is not their check.
  - `[low]` `reject` Edge-Case 3: a wrapped `.dry-note` would read as missing - `partsOf` pins it as a direct child; hypothetical.
  - `[low]` `reject` Edge-Case 4: `noteBesideCount` false does not check the note is off the count line - E4 has no note; E6 asserts the note below the rows.
  - `[low]` `reject` Edge-Case 6: E6 does not compare the note with Will resend - unchanged assertion, outside the Smoke item.
  - `[low]` `reject` Verification-Gap on the not-null guards: no assertion that cannot fail was found; recorded as a pass, no action.
  - `[false]` `reject` Intent audit (descriptive): the diff touches no feature code - the pass is a test rework by the lead's instruction.
  - `[false]` `reject` Intent audit (descriptive): the test reaches the card through a fixture row and `BridgeSink`, not a live incident - unchanged by this pass; E1 and E7 are the story's Integration ACs.
  - `[low]` `reject` Intent audit (descriptive): the diff implements the broad reading (every geometry measurement of the spec) - the Smoke item asks for exactly that.

## Design Notes

**Rulings (the lead, 2026-11-04, on the plan's Q1, Q2 and point (c)).**
- Q1, decide: option (a). The line "Rows of the card that exist today do not change" was the lead's own, in the stage's project block; neither the story's acceptance criteria nor the dispatch says it, and it is withdrawn. So there is no conflict and no exception: what binds is the AC (one row in the dry-run block, word for word) and DESIGN.md's acceptance test with EXPERIENCE.md's "Shorter than 680" row. Below 680 px tall, and only while the row shows, the CSS-only arrangement of the Tasks applies. No word changes. Rejected: (b), which weakens a stated guarantee; (c), which leaves the dry-run block.
- Q2, veto U-266: accepted as a known limit. A request raised on a build without Story 7.7 can show the line with no evidence check behind it. Exposure as stated to the owner: 1.0.0 ships without 7.7, so every answered record from 1.0.0 still in retention is in scope after the upgrade, not only a 24 h pending window. Rows raised on a build with 7.7 are exact, because the row and the notice use the same function on the same values. No flag is stored.
- Point (c), veto U-267: the two derived fields may reach `Live.Event`'s Payload JSON text. Additive; no table, `DRYRUNKEYS` or stored dry run changes.
- Checked by the lead: the notice's key is stored on no row tied to an approval (`Data.Delivery`, `Data.Incident`, `Data.SimMessage`; `Data.Turn.ReplyCatalogKey` has no approval link), so reading it back is not an option. `CALLBACKHELPERS` and `SINKCLASSES` in `Test/Bridge/CodeRules.cls` are two-name appends; Epic 33 changes other lines of that file, so this is a plain union.

**Answers to the stage's four questions.**
- (a) *How the page gets the text:* from the generated web catalog, `incident.eitherWayLine`, which `catalog.mjs` cuts from the two catalog entries. The words stay typed once in `Msg/Catalog/Watch.cls` (in the entries Story 7.7 shipped) and are never typed in `web/`. Rejected: server-rendered text on the payload, because AD-32 and "Text OcuTalon sends" name who renders and a payload builder is not among them, so it needs an AD amendment; and it would still have to cut the line out of a whole notice. Rejected: a new catalog key for the line alone, because the catalog has no composition, so it would type the wording again beside the entries (DW-655 is that copy's owner), in a file Epic 33 is changing. Rejected: a copy in `APPROVAL_TEXTS`.
- (b) *Many and one, `{reading}`, `{item}`:* the same three values as the notice. The one-or-many choice is `resend` (the entry's one form names `resendCount`, which is `dryRun.resend`). `reading` comes from the same method. `item`: the notice takes the incident's noun at `Proposed`; the dry run took the same noun moments before (`RepairResend` L207-215; `Incident.ItemNoun` is written only before the dry run is asked, IncidentManager L635, L709), and its fallback to the body class's noun is not reachable because L635 always stores one. So `dry.itemNoun.one` is the notice's `item`; `AssertCardFields` pins it on the real path.
- (c) *Stored data: no change.* `DRYRUNKEYS`, the stored dry run, the `ApprovalRequest` row and every table are unchanged, and no flag is stored: the flag and the reading are worked out on the way out from what the row already holds. The Lane B mapping `FromRow` does change, by two derived fields. The one stored place they reach is the `Payload` JSON text of `Live.Event` rows, which holds whatever the payload class exports: two more keys in that text, no schema, format or retention change (AD-12: a payload is the current public view). The lead filed this as veto U-267 (Rulings).
- (d) *Label:* none is needed. The row carries U-249's line alone, as `dry-note` carries its sentence. There is no new text and no veto item here.

**Why the payload asks `Notice`.** The rule needs the source format, which is in `FixParameters` and is not on the payload; the page cannot decide. `Live/Payload` has called other areas' pure readers before (`Status` calls `Schedule.Heartbeat`), and no check forbids it (`docker/tests/test-boundaries.sh` scans other things). Moving `Reading` to `Fix.Reformat` would change a Story 7.7 class for no gain.

**Governing ADs:** AD-11 (the row is the truth: the payload reads it), AD-12 (the payload is the full public view; `payloads.mjs`), AD-16 (the stored dry run's keys unchanged; the Fix area untouched), AD-32 and the convention "Text OcuTalon sends" (who renders; the page renders from `msg/catalog.ts`), AD-29 and AD-33 (lanes and owners; U-252's exception), AD-6 and DW-177 (what runs in the callback), AD-22 (throwaways, the mock). No AD Rule is contradicted; no AD changes.

**Integration ACs, Consumes, Consumed-by (Rules 1 and 2):**
- No new service. Integration ACs: matrix row 1 (`FromRow` reads the real raised row, and its fields equal the delivered Notification's slots) and E1 (the page reads the real payload through `BridgeSink` and `Web/Api` and draws the row; the server's renderer holds the same text).
- Consumes: 7.7 (`Notice.Reading`, the two catalog entries, `Test.Fix.EitherWay`), 6.2 (the card, `approval-view.ts`), Epic 0 (`Msg.Catalog`, `payloads.mjs`, `catalog.mjs`).
- Consumed-by: none; 7.8 is Epic 7's last story.

**Extend, don't copy (Rule 2):** `FromRow` calls `Notice.Reading` (no second rule); the derived key goes through `pageText`, `PAGE_ONE_FORMS` and `renderPageText` (no second renderer); `dryRunView` reuses `textOf`, `numberOf` and the context's `render`; `either-way.spec.ts` uses `raise` of `support/approvals.ts`.

**Ledger inbox:** DW-645 is addressed by the matrix rows marked DW-645 and by the Execution tasks that cite it.

**Decided in-stage (small, reversible, within the intent):**
- The row stays on an answered request: the block stays as a record and the notice's line does not depend on the state (the epic context leaves this to the spec).
- `eitherWay` is a `%Boolean` with `InitialExpression = 0`, as every other payload flag, so `false` is present on each dry run. It is an added key; `TestContracts` pins the part's properties and this story updates it. A grep of the web and Core tests finds no other test that compares the dry run's whole key set.
- The row's class is `dry-either`, inheriting the block's ink colour: it is evidence for the decision, not an aside. No new design token.
- The derived key's name, `incident.eitherWayLine`, is a page key only and no catalog class holds it; the generator's header says so.
- A row with `eitherWay` and no numeric `resend` is absent: no count, no sentence. The notice requires `resend` of at least 1 too (`WithFixSlots`).
- `EXPERIENCE.md`: no edit here (a planning artifact, and Epic 40 is changing it); the lead may append the dry-run row at its bookkeeping, as for Story 7.7.
- `docker/tests/test-cards.sh`'s comment lists the cases and stays stale by one file: `docker/**` is frozen until the tag.
- The short-screen rule uses `HEIGHT_QUERIES.compact`, not a typed `(height < 680px)`: `layout-view.ts` holds the page's one height query and `demo-guide.ts` is how a component writes it (Rule 2). So `floor-sources.test.mjs`'s pin of its users and the doc line of `layout-view.ts` change; neither path is in an open epic's diff.
- The rule stays on a height condition alone, as the ruling says; at a narrow width `minmax(0, 1fr)` and `.mono`'s `overflow-wrap: anywhere` wrap the values and nothing overflows.
- AC 7 gains a mutation row, the one AC without one; matrix row 1's keys are pinned by the existing `Test.Fix.DryRun` L154, L213, which the shards run.

**Footprint extensions:** the list under Code Map. `new_units:` none (`web/e2e/cards/` is the cards project's folder; `Test/Live`, `Test/Fix`, `Test/Watch` and `Test/Bridge` are in their shards). Contended, reported: `Test/Live/Payloads.cls`, `Test/Bridge/CodeRules.cls`.

**Measured at plan (the 1280x600 rule).** A lane-B throwaway of the cards unit, Chromium, the current bundle, a scratch spec outside the repository with the same set-up as A6; the row was put into the real DOM with its two forms. All values in px from the top of the viewport; the chat list ends at 518 at 600 tall and 638 at 720 tall. Both forms wrap to two lines at the block's 510 px width (the width at 1280) and move Approve down 38 px.

| Viewport, guide | Cause and fix summary | Approve bottom today | With the row | Past the list's end |
|---|---|---|---|---|
| 1280x600, hidden (A6's conditions) | A6's fixture (short) | 509 | 547 | 29 |
| 1280x600, hidden | the mock's demo reply | 555 | 593 | 75 (37 of it today) |
| 1280x600, compact | the mock's demo reply | 589 | 626 | 108 (71 of it today) |
| 1280x720, open | A6's fixture | 542 | 580 | none (58 to spare) |
| 1280x720, open | the mock's demo reply | 589 | 626 | none (12 to spare) |
| 1280x600, hidden, Before and After on one line and the note on the count line | A6's fixture | | 508 | none (10 to spare) |

## Verification

`<laneB>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root. One command per foreground call with `timeout: 600000`; never two IRIS test runs in one message; a call the harness moves to the background is polled to completion in foreground loops under 170 s.

**Commands:**
- (loop) `npm --prefix web run payloads` and `npm --prefix web run catalog`, then `node web/scripts/payloads.mjs --check` and `node web/scripts/catalog.mjs --check` -- expected: exit 0.
- (loop) `node --test web/scripts/catalog.test.mjs web/scripts/approval-view.test.mjs web/scripts/approval-sources.test.mjs web/scripts/floor-sources.test.mjs web/scripts/payloads.test.mjs web/scripts/playwright-projects.test.mjs` -- expected: all pass.
- (loop) `<laneB> OCUTALON_RUN_TAG=e7s8iw ci/warm.sh up`, once per stage -- expected: READY.
- (loop) `<laneB> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s8iw ci/iris.sh class <Class>`, one call each: `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Core.BridgeSink` -- expected: `CLASS ... passed`.
- (loop) `<laneB> OCUTALON_RUN_TAG=e7s8i ci/iris.sh class <Class>`, fresh, one call each: `OcuTalon.Test.Fix.EitherWay`, `OcuTalon.Test.Watch.Diagnose` -- expected: passed.
- (loop) `<laneB> OCUTALON_RUN_TAG=e7s8i ci/iris.sh build`, then `<laneB> OCUTALON_RUN_TAG=e7s8i ci/iris.sh live cards` -- expected: passed, E1 to E5 included. If it dies of its local deadline with no failed test, add `OCUTALON_LIVE_DEADLINE=900` on the call.
- (once) `npm --prefix web test` and `npm --prefix web run lint` -- expected: pass.
- (once) `<laneB> OCUTALON_RUN_TAG=e7s8i ci/iris.sh live <unit>`, one call each after the last web change: `demo-path`, `floor`, `answers`, `online-demo`, `online-demo-path` -- expected: passed.
- (once) `<laneB> OCUTALON_RUN_TAG=e7s8i ci/iris.sh shard lane-b --part k/3` for k = 1 to 3, one call each -- expected: passed.
- (once) `<laneB> OCUTALON_RUN_TAG=e7s8i ci/iris.sh shard lane-a --part k/12` for k = 1 to 12, one call each (split to `k/16` if a part nears 8 minutes) -- expected: passed.
- (once) `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-web-build.sh`, one call each -- expected: every line PASS. Not `ci/checks.sh` (about 22 minutes).
- (once) `<laneB> OCUTALON_RUN_TAG=e7s8iw ci/warm.sh down`, then `<laneB> OCUTALON_RUN_TAG=e7s8i ci/iris.sh teardown`; run them also after a failure.

**Shared surfaces:**
- The `Part.DryRun` properties: `Test.Live.Payloads` `TestContracts` and its XData (two added); `payloads.ts`.
- `PAGE_TEXTS` count 50 to 51 and the key list: `web/scripts/catalog.test.mjs`. The generator now needs the two parents, so its fixture `WATCH` gains them.
- `DryRunView`'s shape: `approval-view.test.mjs` `deepEqual`.
- The card template's printed order: `approval-sources.test.mjs` `order`.
- The cards project's cases, 20 to 28: `playwright-projects.test.mjs`.
- `CALLBACKHELPERS` and `SINKCLASSES`: `Test.Bridge.CodeRules`.
- `HEIGHT_QUERIES`' users: `floor-sources.test.mjs` `used`.
- The card's height on the demo path: `web/e2e/support/demo-path.ts` reads `.dry-note` and `.dry-count`, unchanged by the new class. With the demo's real dates the row shows in `live:demo-path` until November 13 and not after; nothing asserts it there, because the date decides.
- `DRYRUNKEYS`, the stored dry run, the catalog classes and `Test.Msg.Catalog`: unchanged.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply (Rule 19).** The implement stage applies each, observes red, reverts byte-identically, and records `mutation: ... -> ...` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | `FromRow` no longer sets `EitherWay` | `Payloads.TestApprovalEitherWay`, `EitherWay.TestDemoRepairWhenInstanceDateIsNotUtcDate`, E1 |
| AC 1 / reading | `READINGS` swapped | `Payloads.TestApprovalEitherWay` (and Story 7.7's `NoticeText.TestEitherWay`) |
| AC 2 | `Reading` ignores whether the readings differ | `Payloads.TestApprovalEitherWay` (10/16, 11/11), `Diagnose.TestDemoDiagnosis`, `EitherWay.TestBothReadingsMatch` |
| AC 3 / form | the view passes `affected` as `resendCount` | `approval-view.test.mjs` (`resend` 1 of 50) |
| AC 3 / item | the view passes the `other` noun | `approval-view.test.mjs` |
| AC 3 / place | the row after Will resend | `approval-sources.test.mjs`, E1 |
| AC 4 | the view ignores `eitherWay` and tests `reading` alone | `approval-view.test.mjs` (reading with no flag) |
| AC 5 | one word changed in one form of `incident.laterRequestEitherWay` | the generator exits 1; `catalog.test.mjs` fixture refusal |
| AC 6 | the short-screen rule removed | E5 |
| AC 7 | `FromRow` writes `eitherWay` back into `row.DryRun` | `Payloads.TestApprovalEitherWay` (the row's `DryRun` text unchanged) |

**Mutations applied (Rule 19, implement stage).** Each was applied, observed red, and reverted byte-identically (`cmp` against a copy taken before it, and the whole `git diff` equal to the one taken before the first mutation).

- mutation: AC 1 `FromRow` no longer sets `EitherWay` -> red: `Payloads.TestApprovalEitherWay` (slot B); fresh `EitherWay` fails `TestDemoRepairWhenInstanceDateIsNotUtcDate`, `TestBothReadingsMatchMixedWithTolerance` and `TestLaterRoundKeepsTheLine` ("the payload carries the flag and the notice's reading"); `live cards` fails 4 (E1, E2, E4, E5).
- mutation: AC 1 / reading `READINGS` swapped -> red: `Payloads.TestApprovalEitherWay` and `NoticeText.TestEitherWay` (slot B).
- mutation: AC 2 `Reading` ignores `first = second` (whether the readings differ) -> red: `Payloads.TestApprovalEitherWay` (the 11/11 case: "same date both ways", its JSON and "it is false"), fresh `EitherWay.TestBothReadingsMatch`. `Diagnose.TestDemoDiagnosis` stays GREEN under this mutation: 10/16/2026 does not read as a date in the other order, so `Reformat.Readings` refuses it before the `first = second` test. The table's expectation of a red `Diagnose` here is wrong for this mutation (and 10/16 in `Payloads` also stays green; 11/11 is what pins it).
- mutation: AC 2 / day above 12 `FromRow` sets the flag whatever `Reading` answers (`If reading '= ""` replaced by `If 1`) -> red: fresh `Diagnose.TestDemoDiagnosis` ("a day above 12 (10/16/2026) reads one way, so the approval payload has no either-way flag"). This is the mutation that pins the Diagnose assertion.
- mutation: AC 3 / form the view passes `affected` as `resendCount` -> red: `approval-view.test.mjs` (the many form and the "resend 1 of 50" cases).
- mutation: AC 3 / item the view passes the `other` noun -> red: `approval-view.test.mjs` (5 cases).
- mutation: AC 3 / place the row after Will resend -> red: `approval-sources.test.mjs` (2 cases), and `live cards` fails E1, E2 and E4 (after rebuilding the bundle with `ci/iris.sh build`; a run on the old bundle stays green).
- mutation: AC 4 the view tests `reading` alone and ignores `eitherWay` -> red: `approval-view.test.mjs` ("is absent unless the flag is true ...").
- mutation: AC 5 one word changed in the one form of `incident.laterRequestEitherWay` -> the generator exits 1 ("incident.eitherWayLine: the one form of the line differs ..."), `catalog.test.mjs` real-tree cases fail (current catalog.ts; the eight forms). The fixture refusal cases pass by design: they build their own broken fixtures and assert the refusal.
- mutation: AC 6 / answered the rule `.dry.has-either:not(.has-note) .dry-head` removed -> red: E4 only (Before and After no longer share a line below the count line); with the rule E4 and E5 pass. Re-observed at the rework stage on the one-pass helper (selector made never to match -> E4 red, 27 passed).
- mutation: AC 6 the short-screen rule disabled (`@media ${HEIGHT_QUERIES.compact} and (width < 1px)`) -> red: E4 and E5 ("Before and After share a line") and E8 ("640 by 360: the arrangement applies"); with the rule all pass. Re-observed at code review and again at the rework stage (E4, E5, E8 red; 25 passed).
- mutation: AC 7 `FromRow` writes `eitherWay` back into `row.DryRun` -> red: `Payloads.TestApprovalEitherWay` ("the row's stored dry run is unchanged").

**Implementation notes (decided in-stage, small, within the intent).**
- The matrix row "Reload" is E7, on a seeded noticed incident: `raise`'s published incident is an event only, which a reload does not redraw, so E1 does not carry it.
- The compact rule sets `.dry-row` to `auto minmax(0, 1fr)` columns (not the 84 px key column) while the row shows, so the half-width cells keep room for the value; the rule changes only `.dry.has-either` under `HEIGHT_QUERIES.compact`, and the Will resend row gets the extra class `dry-resend` (a hook for `grid-column: 1 / -1`; no text, order or other row changes).
- The derived key is listed last in `LISTED_KEYS` and `TEXT_SLOT_KEYS` (its slots `reading` and `item` are text slots).
- Class tests that need no runtime of their own (`Payloads`, `CodeRules`, `NoticeText`, `BridgeSink`, and the mutation runs of `Payloads` and `NoticeText.TestEitherWay`) ran on slot B (namespace OCUTALON) after `iris_doc_load` of the changed classes, not in a warm throwaway; `EitherWay`, `Diagnose` and `live cards` ran in fresh lane-B throwaways with tag `e7s8i`, torn down at the end.
- The bundle is rebuilt (`ci/iris.sh build`) before each `live cards` run that follows a web change; a run on an older bundle does not see the change.

**QA stage (Rule 19).** AC 1 to AC 4, AC 6 and AC 7 are pinned by tests that have their `mutation:` line above; nothing was added for them. Two gaps were found against the ACs and the matrix and closed:

- `web/scripts/either-way-line-sources.test.mjs` (QA): AC 5's "no other file under `web/src/app` holds the words" was pinned only for the approvals folder (`approval-sources.test.mjs`); this scans every source of the page, comments included, and finds the line in `msg/catalog.ts` alone, once as the many form and once as the one form.
- `web/e2e/cards/either-way.spec.ts` E6 (QA), with `playwright-projects.test.mjs` (`range('E', 1, 6)`, `cards.length` 26): "no row in any other state changes" at 1280x600. A request with no row (a day above 12, the same date both ways) keeps Before above After and the note below the rows; nothing pinned that the short-screen grid belongs to the row alone.

- mutation: AC 5 / the line typed in a second page source (`web/src/app/chat/chat-panel.ts` gains a line holding "they match the day each order arrived") -> red: `either-way-line-sources.test.mjs` ("is typed in the generated catalog and in no other source of the page"); reverted byte-identically (`cmp` against a copy, `git status --short` and `git diff` equal to the ones taken before).
- mutation: AC 4 / short-screen rule leaks to every card (`.dry.has-either {` of the compact block becomes `.dry {`) -> red: `live cards` E6 ("a day above 12: Before is below the count line"), and A6 as well (Approve out of view); reverted byte-identically, bundle rebuilt. Re-observed at the rework stage on the one-pass helper (E6 and A6 red, 26 passed).

QA runs: `node --test` of the new file and `playwright-projects.test.mjs` pass; `npm --prefix web test` 1326 pass; `npm --prefix web run lint` clean; `live cards` 26 passed (E6 included) in the throwaway `e7s8q`, torn down (0 left). No IRIS class changed in this stage, so no class run.

**Code-review stage (Rule 19).** Each mutation was applied, observed red, and reverted byte-identically (`git status --short` and `git diff` equal to the ones taken before it).

- mutation: Reload `fromSnapshot` sets `dryRun.eitherWay` false on the rail's approvals -> red: E7 only ("the row, from the snapshot").
- mutation: short-screen overflow `.dry.has-either` gets `repeat(2, 240px)` columns -> red: E8 only ("320 by 360: no part passes the block's right edge").
- mutation: AC 3 / answered `eitherWay: pending ? eitherWayOf(...) : ''` -> red: `approval-view.test.mjs` ("stays on an answered request").
- mutation: AC 2 / no either-way case `Notice.Reading` treats YYYY-MM-DD as MM/DD/YYYY -> red: `Payloads.TestApprovalEitherWay` ("a source format that is not an order format: no flag"), slot B.
- mutation: AC 5 / the end anchor twice, the once-check dropped -> red: `catalog.test.mjs` ("refuses a form whose anchor is missing or occurs twice").
- mutation: AC 5 / a form missing, the `typeof text` check dropped -> red: `catalog.test.mjs` ("refuses a parent with a form missing").
- mutation: AC 5 / an empty sentence, the `line === ''` check dropped -> red: `catalog.test.mjs` ("refuses a form with nothing between its anchors").
- mutation: AC 5 / slot types, the type check dropped -> red: `catalog.test.mjs` ("refuses a slot of the line whose type differs").
- mutation: AC 5 / the one form's slot, the `resendCount` guard dropped -> red: `catalog.test.mjs` ("refuses a one form that is not chosen by resendCount").

Code-review runs: `live cards` 28 passed (E7 and E8 included) in the throwaway `e7s8c`, torn down (0 left); `npm --prefix web test` 1330 pass; `npm --prefix web run lint` clean; `Payloads` 15 of 15 on slot B; `catalog.mjs --check` and `payloads.mjs --check` exit 0; `test-class-rules.sh` and `test-boundaries.sh` pass. The bundle was rebuilt from the clean tree after the last mutation.

**Rework stage (Rule 19, the Smoke item).** The cause was in the test: E6 (and `edgesOf`, which E4 and E5 shared) read the parts of the dry-run block with separate `boundingBox` calls in page coordinates, so a chat list still following the new card to the bottom put each read at another scroll position. `layoutOf` now reads the count line, Before, After and the note in one `evaluate`, as offsets from the block's own top edge; E4, E5 (through `beforeAndAfterShareALine`) and E6 use it, and every assertion keeps its threshold and meaning. E8 measures edges inside one `evaluate` already. The product's layout does not move after the card is drawn, so `approval-request-card.ts` is unchanged and `live demo-path` was not needed.

- mutation: AC 6 the short-screen rule disabled (`@media ${HEIGHT_QUERIES.compact} and (width < 1px)`), one-pass helper -> red: E4 and E5 ("Before and After share a line") and E8 ("640 by 360: the arrangement applies"); 25 passed; reverted byte-identically (`cmp` against a copy, `git status --short` and `git diff --stat` equal to the ones taken before).
- mutation: AC 4 / short-screen rule leaks to every card (`.dry.has-either {` of the compact block becomes `.dry {`), one-pass helper -> red: E6 ("a day above 12: Before is below the count line") and A6 (Approve out of view); 26 passed; reverted byte-identically.
- mutation: AC 6 / answered the selector of `.dry.has-either:not(.has-note) .dry-head` made never to match, one-pass helper -> red: E4 ("Before and After share a line"); 27 passed; reverted byte-identically.

Rework runs: `npm --prefix web run lint` clean; `playwright-projects.test.mjs` 27 pass; after `ci/iris.sh build`, `live cards` passed 28 of 28 three times in a row, each on a fresh lane-B throwaway of tag `e7s8rwi`; the bundle was rebuilt from the restored tree and the tag torn down (0 left).

## Auto Run Result

Status: done
Blocking condition: none

Summary (rework iteration 1, this pass only): the Smoke item is closed. The E6 race was in the test: the block's parts were measured with separate `boundingBox` calls while the chat list could still be scrolling. `layoutOf` in `web/e2e/cards/either-way.spec.ts` now reads every part in one `evaluate`, relative to the block's top edge; `beforeAndAfterShareALine` (E4, E5) and E6 use it with unchanged assertions plus a not-null check on the note. No product file changed.

Files changed: `web/e2e/cards/either-way.spec.ts` (the helper); this spec (the Smoke item ticked, the triage entry, the mutation lines, this result).

Review: 15 findings from four layers, none high; one medium patched (the mutation lines of the helper's three pinning mutations, re-observed red), the rest rejected as low, false or descriptive, each with its reason in the Review Triage Log; deferred 0 new items. Follow-up review recommended: false (no high patched).

Verification performed (all pass): `npm --prefix web run lint`; `node --test web/scripts/playwright-projects.test.mjs` (27); `ci/iris.sh build` then `live cards` three times in a row, 28 of 28 each, on fresh lane-B throwaways; three mutations red and reverted byte-identically; the throwaway tag `e7s8rwi` torn down (0 left).

Residual risks: the race fix has no pinning test of its own (the race is nondeterministic); its evidence is the three consecutive passes. The lead re-runs the smoke and the fresh check.
