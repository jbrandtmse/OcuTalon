---
title: 'Story 23.10: Partner notice and summary polish from the 1.0.7 demo pass'
type: 'bugfix'
created: '2026-11-11'
status: 'done'
baseline_revision: '0f105f8c0bd90dc7e6ee6c45d86b94bdc9c49ec8'
baseline_commit: '0f105f8c0bd90dc7e6ee6c45d86b94bdc9c49ec8'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** The Contest Planner's hands-on pass of 1.0.7 on the live demo found three judge-visible faults and one lag. (1) The demo's one partner contact is named for Results, but the guide's incident is the Orders feed, so the model wrote "Orders from Results Partner IT are delayed...". (2) A notice drafted for a resolved incident said "We are looking into a fix and will share updates." (3) The incident summary's "Fix:" line has no final full stop. (4) After Reject, the rail briefly still listed the rejected request.

**Approach:** All four items are ruled (verbatim terms below).
- (1) Rename the demo contact in the code fixture to "Orders Partner IT" <it@orders-partner.example>. It is already keyed to the Orders production.
- (2) Add the incident's state to the draft's facts, and append the ruled sentence to the draft instruction. A new CI mock case shows a resolved incident's draft, and its test checks that the model's request carries both.
- (3) Give `summary.fix` its full stop, and `summary.evidence` too (pre-approved by the Contest Planner, 2026-11-11T20:09:53Z: punctuation only, same rule as the Fix line). The catalog's period rule already prevents a double full stop.
- (4) The root cause is not a one-line refresh, so the rail lag goes to the ledger (DW-1159, routed med, Contest Planner ruling).

## Boundaries & Constraints

**Always:**
- Use the ruled strings exactly:
  - the contact `"Orders Partner IT"` with `"it@orders-partner.example"`;
  - the instruction sentence "If the incident is resolved, say that the affected orders went through after the fix, and don't say that work is still going on or that updates will follow.";
  - the summary lines "Fix: {fix}." and "Evidence: {evidence}." (no other wording change).
- The fixture stays demo-only, read-only, in code, with an example-domain address (Fix.PartnerContacts' contract). It keeps id 1 and `OcuTalon.Demo.Orders.Production`.
- Facts still hold no message body, sample error, setting value or evidence (AD-16, Story 23.5). The state is a code-written value from the incident row.
- Model-facing changes go on the Planner's next RC-eval checklist (Design Notes). CI proves only what the code sends to the model.

**Never:**
- Do not rename the sample incoming email "Results Partner IT <it@results-partner.example>". That covers `Channel.SimMailbox.In` `PARTNERFROM`/`PARTNERBODY`, the mailbox's `fromPrefill`, `eval/mail-*` cases, EXPERIENCE's sample-email table and their tests.
- No README or EXPERIENCE edit: no line names the recipient (Design Notes).
- No web source change, no new route, setting, table, live-event type, dependency, privilege or catalog key. No change to `Fix.Executor*`, the transition table or the summary's composition.
- No sampling parameter, no model or token change (owner-fixed values).
- No edit under `irislib/`, `irissys/`, `docs/**` or the spine.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Contact | demo mode on, `PartnerContacts.For("OcuTalon.Demo.Orders.Production")` | `[{"id":1,"name":"Orders Partner IT","address":"it@orders-partner.example"}]` | demo mode off → `[]` (unchanged) |
| Facts, resolved | incident State `resolved` | lines: Partner: Orders Partner IT / Production / **Incident state: resolved** / Failed item / Failures / First / Last / Cause | No error expected |
| Facts, other states | `open`, `awaiting_approval`, `fixing` | `Incident state: open` / `awaiting approval` / `fixing` (underscores read as spaces) | No error expected |
| Instruction | any draft | `SYSTEMNOTE` = the Story 23.5 text + " " + the ruled sentence | No error expected |
| Resolved draft (mock) | resolved incident, cause marker `[[mock:partner-notice-resolved]]`, the ask turn | one pending `partner_warning` request to contact 1; its notice has neither "looking into" nor "will share updates" (case-insensitive); the logged draft request holds "Incident state: resolved" and the ruled sentence | No error expected |
| Old pending notice | a request raised before the upgrade (`to` it@results-partner.example), approved after | the existing re-check skips it with RECHECK "Orders Partner IT is no longer a partner contact of Orders"; nothing is sent | existing `result.partnerNotSent` |
| Fix line | FixSummary "...after you approve" | "Fix: ...after you approve." | No error expected |
| Evidence line | evidence "OrderDate 16/10/2026 in the sample" | "Evidence: OrderDate 16/10/2026 in the sample." | same own-stop rule as the Fix line |
| Fix line, own stop | FixSummary ending "." / "?" / "!" / "…" | exactly one "." / the mark kept and no "." added | No error expected |
| Sample email | the mailbox sample `partner-notice` | still from Results Partner IT <it@results-partner.example> | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls:16` -- the XData fixture row (Lane A, not contended). Its class doc needs no change.
- `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls` -- (not contended) has the following anchors:
  - `SYSTEMNOTE` (38);
  - `Facts` (58-79): Partner, Production, Failed item, Failures, First, Last and an optional Cause;
  - the class doc's Facts bullet (8-9).

  `incident.State` is one of `WARNABLE` = open, awaiting_approval, fixing, resolved (`Tools/WatchTools.cls:103`).
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:1233-1253` `DraftRequest` -- the carrier Text = `Facts`, `SystemNote` = `SYSTEMNOTE`. `Bridge/Adapter/Agent.cls:1146` puts the SystemNote into the user message, so the mock log holds it. No change here.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls:774-780` -- `summary.fix` (contended, Epics 22 and 35). `Msg/Catalog.cls` `SlotText` (~152-176): before a "." in the text, it drops one trailing "." of the value and keeps "?", "!" or U+2026 without the text's ".". `Watch/Summary.cls:101` fills `fix` from `Clean(incident.FixSummary)`.
- Tests that pin the fixture (all contended, Epic 22 `Test/Fix/**`):
  - `Test/Fix/PartnerWarning.cls`: doc 5; `ADDRESS` 36; the SYSTEMNOTE pin 100; `TestFacts` 108-128 (incident helper 438, default State `open`); and 136, 169, 198-212, 236, 325, 332, 472;
  - `Test/Fix/PartnerDraft.cls`: `ADDRESS` 31; `TestDraftRequest` 120-142 (a resolved incident, `request.input` at 142); and 175-189 (dry run, slots, phone and web text), 569;
  - `Test/Fix/PartnerTurns.cls`: `ADDRESS` 22; `NOTICE` 27 (scenario `partner-notice`); the subject at 83; `Asked` 181 (calls `ResolvedIncident(a)` at 189); `ResolvedIncident` 216-221 (cause marker `[[mock:partner-notice]]`); `Turn` 247 (`LogMark`/`LogSince`); also callers at 130 and 165.

  Helpers: `Test.Agent.RunnerFixture` `FindRequests(entries, text)` (1112) and `Messages(logged)` (1124); `Test.Contract.Mock` `LogMark`/`LogSince`.
- `ci/mock/scenarios/A/partner-notice.json` -- the marker scenario to copy for the new one. Marker = name = file name. Its grammar is in `ci/mock/scenarios.mjs` (`MATCH_TYPES`, prompt-containment rule 321-324). `mock.mjs` selection order 26-34: marker first.
- Summary pins:
  - `Test/Msg/Catalog.cls:1659`, the `summary.fix` Fixture;
  - `TestEveryKeyOnEveryChannel` (124);
  - the `source` rule 847 (non-empty ASCII);
  - `Test/Watch/Summary.cls:141`, the line "Fix: repair the date and resend the orders" (`$Piece` 9-15, line count unchanged), with 478 as a substring check that still holds.
- Self-contained stand-ins that keep "Results Partner IT" (they never read the fixture, so they stay green). Leave them as they are:
  - `Test/Channel/TelegramApproval.cls:415`, `Test/Demo/Guide.cls:187,334`, `Test/Demo/SimMailboxOut.cls:101,281`;
  - `Test/Eval/Report.cls:501`, `Test/Fix/Kind.cls:104`, `Test/Live/Payloads.cls:379-393`;
  - `Test/Msg/Catalog.cls:1680,1690`, `Test/Watch/Summary.cls:717-718`;
  - `web/e2e/cards/approval-card.spec.ts:469-540`, `web/scripts/approval-view.test.mjs:188-236`, the doc example at `web/src/app/approvals/approval-view.ts:124`.
- The inbound sample (must not change): `Channel/SimMailbox/In.cls:44,48`, `Test/Demo/SimMailboxIn.cls:108`, `web/src/app/mailbox/mailbox-view.ts:40`, `web/scripts/mailbox-view.test.mjs:31,128`, `web/scripts/ux-strings.test.mjs:435`, `web/e2e/demo-switch/mailbox.spec.ts:125-184`, `web/e2e/floor/devices.spec.ts:512`, `eval/mail-*/case.json`.
- Rail (to ledger, not edited): `web/src/app/rail/rail-view.ts:340`, `live/live-store.ts:188`, `approvals/answer-press.ts` `replied`, `approval-request-card.ts:488-542`, `live/live-state.ts:19`, `Core/BridgeSink.cls:144-162`.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls` -- line 16: `"name": "Orders Partner IT", "address": "it@orders-partner.example"`. Id and production unchanged.
- [ ] `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls`:
  - `SYSTEMNOTE`: append, after the existing text and one space, the ruled sentence verbatim.
  - `Facts`: right after the Production line, add `$Char(10)_"Incident state: "_$Translate(incident.State, "_", " ")`.
  - The class doc's Facts bullet names the state.
- [ ] `ci/mock/scenarios/A/partner-notice-resolved.json` -- new marker scenario, the shape of `partner-notice.json`, with one reply text: "Orders sent from your feed failed because the date format of the orders changed. The fix has run, and the affected orders went through after it." Check that no B prompt (`grep '"prompt"' ci/mock/scenarios/B/*.json`) is contained in the new SYSTEMNOTE sentence or in the "Incident state:" line, so the keyless draft still matches only `partner-notice-draft`.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- `summary.fix` and `summary.evidence`:
  - texts `"Fix: {fix}."` and `"Evidence: {evidence}."`;
  - each `source` gains "; full stop: Story 23.10, Contest Planner ruling 2026-11-11".
  - Before editing pins, `grep -rn 'Evidence: ' src web` and update only the pins that render `summary.evidence` (expected: `Test/Msg/Catalog.cls:1657`, `Test/Watch/Summary.cls:141`). The `Evidence:` lines in `Test/Core/WebChatOut.cls:680`, `Test/Channel/TelegramOut.cls:679`, `Test/Demo/SimPhoneOut.cls:192` and `web/e2e/chat/notice.spec.ts:720` are expected to be self-contained escaping fixtures: confirm they do not render the catalog key, and leave them unchanged if so (if one does render it, update it and record it under Design Notes).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls`, `PartnerDraft.cls`, `PartnerTurns.cls`:
  - replace every "Results Partner IT" with "Orders Partner IT", and every "it@results-partner.example" with "it@orders-partner.example";
  - PartnerWarning: the SYSTEMNOTE pin (100) gains the sentence; the `TestFacts` expected text gains "Incident state: open" after the Production line; add one assertion that a `resolved` incident's Facts hold `Incident state: resolved` and an `awaiting_approval` one's `Incident state: awaiting approval`;
  - PartnerDraft 142: also assert `request.input` holds "Incident state: resolved".
- [ ] `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls`:
  - `ResolvedIncident(session, marker As %String = "partner-notice")` puts `[[mock:<marker>]]` in the cause;
  - `Asked` gains a trailing `marker As %String = "partner-notice"` and passes it on;
  - append `TestResolvedDraftSaysTheOrdersWentThrough` at the end of the class: take `LogMark`, then `Asked("resolved", ..., "partner-notice-resolved")`. Assert the request's `parameters.text` and its dry-run `notice` have no "looking into" and no "will share updates" (`$ZConvert(..., "L")`) and its recipient is "Orders Partner IT". Among the logged requests that `FindRequests` finds by "partner-notice-resolved", take the draft: the one whose `RunnerFixture.Messages` text holds "Write a short delay notice" (the ask turn's context may also carry the cause's marker). Assert that it holds "Incident state: resolved" and the ruled sentence, and assert that exactly one such draft request exists;
  - add one header bullet for the new test.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`:
  - Fixture 1659: text "Fix: repair the date and resend the orders."; Fixture 1657: text "Evidence: OrderDate 16/10/2026 in the sample.";
  - add `TestSummaryFixFullStop`: render `summary.fix` on web and telegram with fix "Resend the 50 orders after you approve" → "...approve."; with "...orders." → exactly one "."; with "...now?" → ends "?" with no "." after it. Also render `summary.evidence` with "OrderDate 16/10/2026 in the sample" → "...sample." and with a value ending "." → exactly one ".".
- [ ] `src/ocutalon/cls/OcuTalon/Test/Watch/Summary.cls:141` -- "Evidence: OrderDate 16/10/2026 in the sample." and "Fix: repair the date and resend the orders." in the expected lines.

**Acceptance Criteria:**
- AC1: Given demo mode on and an incident on the Orders production, when a partner warning is drafted, raised, approved and delivered, then every surface names "Orders Partner IT" <it@orders-partner.example>:
  - the draft's Partner fact;
  - the dry run's recipients;
  - the request's phone and web text ("I drafted a delay notice about this incident for Orders Partner IT <it@orders-partner.example>.");
  - the delivered mail's subject "Simulated delay notice to Orders Partner IT <it@orders-partner.example>".

  (`Test.Fix.PartnerWarning`, `PartnerDraft`, `PartnerTurns:TestApprovedNoticeIsSentByteForByte`.)
- AC2: Given the Simulated mailbox, when the sample `partner-notice` is sent or the compose form opens, then the sender is still "Results Partner IT <it@results-partner.example>". (Existing `Test.Demo.SimMailboxIn:TestSamples` and `mailbox-view.test.mjs`, unchanged.)
- AC3: Given an incident in each warnable state, when `Facts` builds the draft's input, then it holds exactly one line "Incident state: <state>" (underscores as spaces) after the Production line, and still no sample error, fix summary, element or evidence. (`Test.Fix.PartnerWarning:TestFacts`.)
- AC4: Given a resolved incident, when the user asks to warn the partner, then the draft request the model receives holds "Incident state: resolved" and the ruled sentence verbatim. (`Test.Fix.PartnerDraft:TestDraftRequest`; the mock log in `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough`; the SYSTEMNOTE pin.)
- AC5 (the ruled mock case): Given a resolved incident whose draft the CI mock answers with `partner-notice-resolved`, when the request is raised, then the notice shown for approval contains neither "looking into" nor "will share updates", and the request is pending to contact 1. (`PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough`.)
- AC6: Given a closed incident with a fix summary and evidence, when its summary renders on any channel, then the lines read "Fix: <fix>." and "Evidence: <evidence>." with exactly one final full stop each, and a value that ends in "?", "!" or "…" keeps its mark with no "." added. (`Test.Msg.Catalog:TestSummaryFixFullStop` and the Fixture; `Test.Watch.Summary`.)

### Review Findings

Code review (epic-cycle code-review stage, 2026-11-11; full mode, four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 23 raw findings, 3 entries after triage, 17 rejected).

- [x] [Review][Patch] (med, fix-risk low, in-story) A fix summary or a first evidence line that is only a period (after whitespace and invisible characters) made the stored summary unrenderable on every channel: with the new "Fix: {fix}." and "Evidence: {evidence}." texts the catalog drops the value's period before the text's and then refuses the empty slot (ERROR #5001 "the slot 'evidence' is empty", observed). It is 23.6's period-element defect (its `Shown(element) '= "."` guard) brought to the two lines 23.10 gave a full stop. `Build` now leaves out a fix line that is only a period, and `Evidence` takes the first evidence line that is more than a period; `TestPeriodFixAndEvidence` pins both. [src/ocutalon/cls/OcuTalon/Watch/Summary.cls:101,274]
- [x] [Review][Patch] (low, fix-risk low, in-story) The changed Evidence-line pins in `Test.Core.WebChatOut`, `Test.Channel.TelegramOut` and `Test.Demo.SimPhoneOut` had not been run in any stage: run on a lane-D warm stack, all three passed. The Playwright pin `web/e2e/chat/notice.spec.ts` N20 stays with CI, which gates the merge. [src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls:680]
- [x] [Review][Defer] (med, fix-risk med, in-story) The ruled resolved-incident sentence tells the model to say the affected orders went through, but Facts carry only the state, and `Watch.Transitions` resolves on "fixing + finished" whatever the run's failed-again or skipped counts (a suspend or reroute also resolves). A partial fix therefore drafts the same success claim. [src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls:38] — deferred: DW-1165 `decision-pending owner=burndown` (a product call on ruled text: give Facts the fix outcome and make the sentence conditional). The user still approves the exact text, and it sits with the Planner's RC-eval item.

Rejected:
- blind: the new test has no positive "went through" check / the banned list is narrower than the instruction (2) — the reply is canned CI text. Routing is already falsified by the default reply's "looking into", and the real wording is the RC-eval item (Decided in-stage 4).
- blind: task boxes are unticked — the fix would edit the spec under review, and it is build-auto bookkeeping.
- blind: the RECHECK line for a retired-address request says "Orders Partner IT is no longer a partner contact" — by-design: it is the matrix row "Old pending notice" verbatim.
- blind: the `approval-view.ts:124` doc comment still names Results Partner IT — by-design: the Code Map lists it as a stand-in to leave, and the Never list forbids web source changes.
- blind: the diff carries `unattended-inbox-snapshot.md` / `epics.md` hunks — false: they came in with the feature merge-forward, not the story's code.
- edge: the state changes between the draft and the approval — low. The approver sees and approves the exact text, and a guard would add a state check and re-draft path (complexity).
- edge: a value ending ".)" renders ".)." — low, a model-written edge. Fixing it changes the shared `SlotText` rule (complexity).
- verification-gap: no `mutation:` line for the AC1 `PartnerDraft`/`PartnerTurns`, AC4 `PartnerDraft` and AC6 own-stop pins (3) — false: Rule 19 asks for one demonstrated mutation per AC, and AC1, AC4 and AC6 each have one recorded.
- verification-gap: "will share updates" only fails if the fixture is edited — already triaged as a deliberate limit; noted.
- verification-gap / QA note: `PartnerTurns`' "and the whole instruction" compares with the Parameter — judged not a defect. It can fail: a SystemNote dropped or truncated on its way to the model's logged request makes it red. The wording is pinned by the verbatim literal on the next line and by `TestContract`, so AC4's pin stands.
- acceptance: AC3's "exactly one line" is checked by substring for three states — false: `Facts` builds the line without branching on the state, and the `open` case is an exact match of every line, which would show a duplicate.
- acceptance: AC3's "no evidence" clause has no seeded pin — low and pre-existing (23.5). `Facts` reads only Incident fields and has no path to the decision payload. reopen_if: `Fix.Kind.PartnerWarning.Facts` opens a Decision.
- acceptance: the "Old pending notice" row does not assert that nothing is sent — false in effect: the skip-then-send-nothing path for a recipient that does not match the fixture is pinned by `TestTamperedRowSendsNothing`, and the retired address takes the same `Recheck` path.
- acceptance: `TestSummaryFixFullStop` calls `RenderAt`, not `Render` — false: AD-32 names `RenderAt` as the test form of the same renderer.

## Spec Change Log

- 2026-11-11 (plan): Story inserted on 2026-11-11 from the Contest Planner's 1.0.7 demo-pass ruling (`.coordination/prompts/epic-23-story-2310-ruling.md`, ~14:30Z, under the owner's delegation). It runs after 23.7 and before 23.9 on lane D. Item 4 is planned as a ledger entry (frontmatter `deferred`), because its cause is not a one-line refresh.
- 2026-11-11 (spec gate): the orchestrator's gate rulings recorded under Design Notes (contended hunks plain union; mock case accepted; item 4 a veto item, U-318), then the Contest Planner's: item 4 reversed to DW-1159 (routed med; frontmatter `deferred` emptied, the lead filed it), and the Evidence line's full stop added (pre-approved).

## Review Triage Log

### 2026-11-11 - Review pass
- verdicts: 16 findings - high 0, medium 1, low 3, false 12, maybe-false 0
- findings:
  - `[false]` `[reject]` blind 1 / edge 1: the resolved sentence has no fix-outcome data (failed again, skipped) - the sentence is ruled verbatim by the Contest Planner and Facts is ruled to hold only the state (AD-16); by design, spec-bound.
  - `[false]` `[reject]` blind 2 / edge 2: the sentence hard-codes "orders" - the same ruled sentence; the demo has one production.
  - `[false]` `[reject]` blind 3: only `resolved` has an instruction - spec-bound (ruled sentence), Decided in-stage 3.
  - `[false]` `[reject]` blind 4 / verification-gap 1: the "no looking into" assertions read the canned reply - Decided in-stage 4: the falsifiable part is the logged request, and the real-model check is on the Planner's RC-eval checklist.
  - `[low]` `[patch]` blind 5 / edge 4: `TestSummaryFixFullStop` loops web and telegram but claims every channel - added "phone" to the loop (mailbox has no summary line); green.
  - `[medium]` `[patch]` blind 6: no test pins the retired address `it@results-partner.example` against the matrix row "Old pending notice" - added a `Recheck` assertion in `PartnerWarning:TestRecheck`; green.
  - `[low]` `[patch]` blind 7 / verification-gap 4: the `TestFacts` header bullet omits the state line - bullet updated.
  - `[false]` `[reject]` blind 8: the positional `Asked` call is easy to get wrong - the new test asserts the marker's effect through the log (exactly one draft with the state line), so a wrong comma count goes red.
  - `[false]` `[reject]` edge 3: a blank or non-warnable state in Facts - `Facts` is reached only for the WARNABLE states (`WatchTools`); no reachable failure.
  - `[low]` `[patch]` edge 5 / verification-gap 3: `fixing` is not in the `TestFacts` state loop (AC3 lists each warnable state) - added; green.
  - `[false]` `[reject]` edge 6: "exactly one draft" fails on a retry or a log gap - the draft turn is a single mock-answered turn; the spec requires the assertion.
  - `[false]` `[reject]` verification-gap 2: the "whole instruction" assertion derives from the code under test - the verbatim literal on the next line and the `TestContract` pin catch a changed SYSTEMNOTE (mutation demonstrated).
  - `[false]` `[reject]` verification-gap (AC5 note): the canned-reply assertions - same as blind 4; a deliberate limit recorded in the spec.
  - `[false]` `[reject]` intent-alignment readings A-D: descriptive; the diff implements the code-and-CI reading the spec rules (model wording is the Planner's RC-eval item).
  - `[false]` `[reject]` intent-alignment: other stand-in tests keep "Results Partner IT" - the spec lists them as self-contained and leaves them.
  - `[false]` `[reject]` intent-alignment: DW-1159 not visible in the diff - the lead filed it at the spec gate; no code is in scope.

## Design Notes

**The ruling (verbatim, Contest Planner, 2026-11-11):**

> 1. Wrong partner on the demo: the demo's one partner contact is the fixture "Results Partner IT" <it@results-partner.example>, but the guide's incident is the ORDERS feed (the simulated partner that sends orders to PartnerOrdersIn), so the model wrote "Orders from Results Partner IT are delayed…". PUBLIC TEXT (fixture, ruled): rename the demo contact to "Orders Partner IT" <it@orders-partner.example>. Update the README and EXPERIENCE lines that name the recipient, and the tests. If the fixture keys contacts by production, key it to the Orders production.
> 2. Notice on a resolved incident: [...] the draft's facts include the incident's state; the draft instruction gains, verbatim: "If the incident is resolved, say that the affected orders went through after the fix, and don't say that work is still going on or that updates will follow." Model-facing: it goes on the Planner's next RC-eval checklist. Add an eval or mock case: a resolved incident's draft has no "looking into" or "will share updates".
> 3. Incident summary, the "Fix:" line (23.6's catalog): it lacks its final full stop ("…after you approve"). Add the full stop and fix the pin.
> 4. LOW: after Reject, the status rail's Approval requests briefly kept showing the rejected request. If the cause is a one-line refresh, fix it in 23.10; otherwise ledger it.

**Item 1, README and EXPERIENCE: no recipient line to change.** Neither file names the partner-warning recipient. They say "simulated". The final lines, unchanged, for the PART READY report:
- README.md:56: "- **Partner delay notices.** Ask OcuTalon in the chat to warn the partner about an incident's delay. It drafts a short notice from the incident's count, times, affected flow and cause, never from a message's contents, and raises it as an approval request that shows the exact text and every recipient. Nothing is sent until you approve. In demo mode the partner contacts are simulated and the approved notice goes to the Simulated mailbox, not to a real inbox; without demo mode there are no partner contacts yet, so no notice is drafted. Try it: after the guide's incident, More to try, *Warn the partner*."
- EXPERIENCE.md:250 (More to try item "Warn the partner"): "... it comes as an approval request that shows the exact text and the recipients, simulated contacts. Approve it, then open the Simulated mailbox to read the notice exactly as you approved it. Nothing goes to a real inbox."
- EXPERIENCE.md:1064: "... On the demo the recipients are simulated contacts, and the approved notice goes to the Simulated mailbox."

No new line is proposed. The card, phone and mailbox show the renamed contact on their own.

**Decided in-stage:**
1. The inbound sample sender stays "Results Partner IT" (the default). It is a different fixture: a certificate notice from the Results partner about its results endpoint. Keeping it leaves the demo's story consistent: Orders partner = delay-notice contact, Results partner = certificate email.
2. Only tests that read `Fix.PartnerContacts` change (the three `Test/Fix/Partner*` classes). Self-contained stand-ins keep "Results Partner IT" because they model arbitrary data and stay green, and most of them sit in contended files (Code Map list). This keeps the change smaller.
3. The state line is "Incident state: <State>", with underscores as spaces, placed after Production. It is model-facing text, not public, and it matches the ruled sentence's word "resolved".
4. The ruling's "eval or mock case" is met with a CI mock case (smaller). No eval kind drafts a partner notice today (the kinds are item, incident, digest, all-clear, command, documents, injection and user-turn), and adding one is new scope. A mock reply is canned, so the falsifiable part of AC4/AC5 is the logged model request: the state line and the sentence. The model's real behaviour is the Planner's RC-eval item below.
5. The existing `partner-notice` and `partner-notice-draft` replies ("We are looking into it and will keep you informed.") stay unchanged. They are CI-only canned text. Editing them is a contended "other" hunk with no product effect, and `NOTICE` pins them byte for byte.
6. Item 3 needs no new guard. `Msg.Catalog.SlotText` already drops a value's trailing "." before the text's "." and keeps "?", "!" or "…" (Code Map). `TestSummaryFixFullStop` pins it for this key.
7. Item 4 goes to the ledger (filed by the lead at the spec gate as DW-1159, routed med owner=burndown, per the Contest Planner ruling below). The cause is that the rail reads only the live store, which only the asynchronously published `approval` event updates. The fix is a store function, a LiveState method and two hosts, not a one-line refresh.

**Spec-gate rulings (orchestrator, 2026-11-11T20:09Z, `.coordination/prompts/epic-23-rulings-2310-gate.md`):**
1. The contended "other" hunks listed below (Watch.cls `summary.fix`, `Test/Fix/PartnerWarning`, `PartnerDraft`, `PartnerTurns`, the new mock scenario) are approved as plain unions. Condition: the lead re-checks Epics 21, 22 and 35 right before the implement spawn. A new hunk on one of these files keeps both sides at integrate; a behaviour choice is a Clarification.
2. Ruling item 2 met by the CI mock case: accepted (the RC-eval item goes to the Planner).
3. Ruling item 4 (rail after Reject): first decided as a veto item (inbox U-318), then REVERSED by the Contest Planner (2026-11-11T20:09:53Z, owner's delegation): DW-1159, routed, med, owner=burndown until its follow-up story exists (approvals/phone/rail, dispatched by the orchestrator after 21.2 merges; acceptance: a browser test presses Reject and the request is gone from the rail within 5 s, web and phone). No 23.10 rework.
5. Contest Planner, same ruling: the summary's "Evidence:" line gets its final full stop in 23.10 (pre-approved; punctuation only, same rule as the Fix line).
4. The "Decided in-stage" items stand.

**For the Planner's next RC-eval checklist (model-facing):** with the real model, on a guide incident that is resolved, ask "Warn the partner about the delay.". The drafted notice says the affected orders went through after the fix, addresses Orders Partner IT, and has no "looking into", "will share updates" or other words saying work is still going on.

**Observations for the Planner (not in scope, no action taken):**
- The suspicious sample email's sender "Order Partner Support <support@order-partner.example>" is now a lookalike of the real contact's domain (`orders-partner.example`). That fits its role as a suspicious email.

**ONLINE-DEMO behaviour:** demo-visible text changes only:
- the partner request's recipients on the card, phone and Telegram, and the Simulated mailbox's subject, now read Orders Partner IT <it@orders-partner.example>;
- a resolved incident's notice should say the orders went through (model-drafted live, never canned);
- the summary's Fix line ends with a full stop.

Nothing new changes production state. There is no new route, setting or table. A notice raised before the upgrade and approved after it is skipped by the existing re-check, with RECHECK and nothing sent. Demo sessions reset, and requests expire after 24 h.

**Integration ACs:** No consumers in this story. It introduces no service, module or shared component (a fixture row, a fact line, an instruction sentence, a catalog full stop and one mock scenario). Consumed-by: none. Consumes: `Fix.PartnerContacts`, `IncidentManager.DraftRequest`, `Msg.Catalog` (Stories 23.5 and 23.6), unchanged.

**Extend, don't copy (Rule 2):**
- `ResolvedIncident` and `Asked` gain an optional marker, so the new test does not copy the fixture.
- The new scenario follows `A/partner-notice.json`.
- `TestSummaryFixFullStop` uses `Msg.Catalog.Render` as the Fixture test does.

**Architecture decisions:**
- AD-6 / AD-30: the draft is a bridge turn with a code-written SystemNote.
- AD-10 / AD-14: untrusted, fresh turn.
- AD-16: fix kinds and the partner-warning kind; facts exclude body, sample, settings and evidence.
- AD-22: CI mock scenarios; RC eval.
- AD-25: online demo, simulated contacts.
- AD-29 / AD-33: lanes and contended files.
- AD-32: one catalog renderer.

No AC contradicts an AD Rule. No NFR is touched.

**Contended touches (the orchestrator rules "other" hunks as plain unions):**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` (Epics 22, 35): other. In `summary.fix` and `summary.evidence`, the text literal gains its final ".", and each `source` literal gains "; full stop: Story 23.10, Contest Planner ruling 2026-11-11" (4 lines).
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls` (Epic 22): other. String-literal renames (doc 5, 36, 112, 136, 169, 198-212, 236, 325, 332, 472), the SYSTEMNOTE pin literal (100), one added line in `TestFacts`' expected text (112) and two added assertions in `TestFacts`.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerDraft.cls` (Epic 22): other. String-literal renames (31, 142, 175-189, 569) and one condition added at 142.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerTurns.cls` (Epic 22): other. `ADDRESS` (22), the subject literal (83), `Asked`'s signature (181) and its call (189), `ResolvedIncident`'s signature and cause literal (216, 219), one header bullet. Appended block: the new test method at the end of the class.
- `ci/mock/scenarios/A/partner-notice-resolved.json` (Epics 21, 22): new file.

- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` (Epic 35, found at the pre-implement re-check; the spec gate's first overlap check was invalid): `origin/OCT-epic35` adds three `settings.webhook*` keys and fixtures and moves the Core count to 143 and the fixture total to 222. 23.10 touches only the `summary.fix` / `summary.evidence` fixture texts and appends `TestSummaryFixFullStop`; it adds no key and changes no count. Separate hunks, both sides kept at integrate (orchestrator gate ruling 1). Edit nothing else in this file.

Not contended: `Fix/PartnerContacts.cls`, `Fix/Kind/PartnerWarning.cls`, `Test/Watch/Summary.cls`.

**Public text and veto items:** Public text is only the ruled strings: the contact name and address, and the Fix and Evidence full stops (Evidence pre-approved by the Contest Planner, 2026-11-11T20:09:53Z). Model-facing text is the ruled sentence plus the "Incident state:" label (agent text, never shown). The mock reply is CI-only. Veto items: none (no security, privilege, stored-data shape, guarantee or dependency change; the new mock case file is allowed).

**Ledger inbox (Rule 17):** none owned by this story. The rail lag is DW-1159 (routed owner=burndown, filed at the spec gate).

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`. Each call should finish in about 150 s, and never put two test runs in one message.

Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`. Use the fresh tag `e23s10i` and the warm tag `e23s10iw`. At the end, also after a failure, run `ci/warm.sh down` (warm tag), then `ci/iris.sh teardown` with each tag. Write the scenario file before `warm.sh up`: a change under `ci/mock` refuses warm runs.

**Shared surfaces:**
- the partner contact's name and address (`Fix.PartnerContacts`), pinned in `Test.Fix.PartnerWarning`, `PartnerDraft` and `PartnerTurns` (every pin renamed; the stand-ins and inbound-sample pins in the Code Map stay as they are);
- the Facts lines (`TestFacts`);
- the exact SYSTEMNOTE (`PartnerWarning` pin 100; the B prompt `partner-notice-draft` must still be its prefix);
- the catalog's `summary.fix` Fixture and its key list (`Test.Msg.Catalog`);
- the summary's lines (`Test.Watch.Summary:141`);
- the mock scenario set (`ci/mock/test/scenarios.test.mjs` validity).

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `ci/warm.sh up` with `OCUTALON_RUN_TAG=e23s10iw`. Re-up (`down`, then `up`, one call each) after any change to `Fix/Kind/PartnerWarning.cls`, `Fix/PartnerContacts.cls` or `ci/mock/**`, so the production's jobs and the mock hold the new code. Then run `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23s10iw ci/iris.sh class <Class>`, one call each:
  - `OcuTalon.Test.Fix.PartnerWarning`
  - `OcuTalon.Test.Fix.PartnerDraft`
  - `OcuTalon.Test.Fix.PartnerTurns`
  - `OcuTalon.Test.Msg.Catalog`
  - `OcuTalon.Test.Watch.Summary`
  - `OcuTalon.Test.Demo.SimMailboxIn` (AC2, unchanged)

  Expected: each prints `CLASS ... passed`.
- (loop) `bash docker/tests/test-mock.sh` -- expected: pass (the new scenario is valid).
- (once) `bash ci/checks.sh` -- expected: every block passes.
- (once) `OCUTALON_RUN_TAG=e23s10i ci/iris.sh class OcuTalon.Test.Fix.PartnerTurns` on a fresh stack -- expected: passed. The production-job code path runs on a fresh stack.
- No web source or web test file changes, so `npm --prefix web test` is not required. If implement touches any `web/` file, add it as a (once) line and run the WHOLE suite.
- Left to CI: the browser units, `live:demo-path`, the shards and the lead's fresh-environment check, forward and `--reverse`.

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:**
- AC1: the fixture name back to "Results Partner IT" → `Test.Fix.PartnerWarning` (the `For` and dry-run pins).
- AC2: `SimMailbox.In` `PARTNERFROM` set to the Orders contact → `Test.Demo.SimMailboxIn:TestSamples`.
- AC3: `Facts` without the state line → `Test.Fix.PartnerWarning:TestFacts`.
- AC4: `SYSTEMNOTE` without the ruled sentence → `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough` (the logged request) and the SYSTEMNOTE pin.
- AC5: the `partner-notice-resolved` reply given "We are looking into it." → `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough`.
- AC6: `summary.fix` text back to "Fix: {fix}" → `Test.Msg.Catalog:TestSummaryFixFullStop` and `Test.Watch.Summary`; `summary.evidence` back to "Evidence: {evidence}" → the same two.

**Mutations run (Rule 19):**
- mutation: fixture name back to "Results Partner IT" -> `Test.Fix.PartnerWarning` red (`TestFacts`, `TestNoContacts`, `TestParametersAndDryRun`, `TestRecheck`, `TestTamperedRowSendsNothing`, `TestApprovedNoticeIsSentByteForByte`)
- mutation: `SimMailbox.In` `PARTNERFROM` set to the Orders contact -> `Test.Demo.SimMailboxIn:TestSamples` red
- mutation: `Facts` without the state line -> `Test.Fix.PartnerWarning:TestFacts` red (the exact lines and both state assertions)
- mutation: `SYSTEMNOTE` without the ruled sentence -> `Test.Fix.PartnerWarning:TestContract` (the instruction pin) red, and `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough` red ("with the sentence for a resolved incident", run together with the next mutation on a re-upped warm stack)
- mutation: the `partner-notice-resolved` reply given "We are looking into it." -> `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough` red (the "looking into" assertions)
- mutation: `summary.fix` and `summary.evidence` text back to "Fix: {fix}" / "Evidence: {evidence}" -> `Test.Msg.Catalog` red (`TestSummaryFixFullStop` and `TestEveryKeyOnEveryChannel`) and `Test.Watch.Summary:TestFixedDismissed` red

**QA (Rule 19), mutations re-observed on lane-D throwaways (QA):** no new test file and no gap found; every AC and matrix row already has a pin.
- (QA) mutation: `partner-notice-resolved` reply given "We are looking into it." and `SYSTEMNOTE` without the ruled sentence (one run) -> `PartnerTurns:TestResolvedDraftSaysTheOrdersWentThrough` red (both "looking into" assertions for AC5; "with the sentence for a resolved incident" for AC4). Note: its "and the whole instruction" assertion reads the Parameter, so it stays green; the verbatim-literal assertion and the `TestContract` pin carry AC4.
- (QA) mutation: fixture back to "Results Partner IT" -> `Test.Fix.PartnerWarning` red (`TestNoContacts`, `TestParametersAndDryRun`, `TestRecheck`, `TestApprovedNoticeIsSentByteForByte`, ...) for AC1.
- (QA) mutation: `Facts` without the state line -> `Test.Fix.PartnerWarning:TestFacts` red (exact lines and the resolved, awaiting_approval and fixing assertions) for AC3; `SYSTEMNOTE` without the sentence -> `TestContract` "the draft instruction" red.
- (QA) mutation: `summary.fix` and `summary.evidence` text without the full stop -> `Test.Msg.Catalog` red (`TestSummaryFixFullStop`, `TestEveryKeyOnEveryChannel`, `TestLocalInstallEveryKey`) and `Test.Watch.Summary:TestFixedDismissed` red for AC6.
- (QA) mutation: `SimMailbox.In` `PARTNERFROM` set to the Orders contact -> `Test.Demo.SimMailboxIn:TestSamples` red for AC2.
- Each mutation was reverted and `git status --short` was empty afterwards; `Test.Fix.PartnerTurns` passed on a fresh stack on the clean tree.
- (CR) mutation: drop the period guards in `Watch.Summary` (`Build`'s `Shown(fix) '= "."` and `Evidence`'s `Shown(line) '= "."`) -> `Test.Watch.Summary:TestPeriodFixAndEvidence` red (a fix line kept, the evidence slot ".", and ERROR #5001 "the slot 'evidence' is empty" on web, phone and Telegram). Reverted, and `git diff --stat` was byte-identical; the class passed again. On the same lane-D warm stack, `Test.Core.WebChatOut`, `Test.Channel.TelegramOut` and `Test.Demo.SimPhoneOut` passed.

**Found at implement:** three Test classes outside the Code Map render the `summary.evidence` key (not self-contained, contrary to the expectation under Tasks), so their Evidence line gains its full stop: `Test/Core/WebChatOut.cls`, `Test/Channel/TelegramOut.cls`, `Test/Demo/SimPhoneOut.cls`. `web/e2e/chat/notice.spec.ts` N20 (line ~720) also renders it and pins 'Evidence: OrderDate was <i>16/10/2026</i>' with `toEqual`; it is a Playwright spec (a test file, no web source), updated by the lead in this pass to 'Evidence: OrderDate was <i>16/10/2026</i>.' as Tasks step 4 directs when a pin renders the key.

## Auto Run Result

Status: done
Blocking condition: none

**Summary:** The demo contact is "Orders Partner IT" <it@orders-partner.example>. The draft's Facts hold "Incident state: <state>" after the Production line and SYSTEMNOTE carries the ruled sentence. The CI mock has a `partner-notice-resolved` case. `summary.fix` and `summary.evidence` end in a full stop. The rail lag is DW-1159 (ledgered by the lead).

**Files changed:**
- `src/ocutalon/cls/OcuTalon/Fix/PartnerContacts.cls`: the fixture row.
- `src/ocutalon/cls/OcuTalon/Fix/Kind/PartnerWarning.cls`: SYSTEMNOTE sentence, the state line in Facts, docs.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`: the two full stops and their sources.
- `ci/mock/scenarios/A/partner-notice-resolved.json`: the new marker scenario.
- `src/ocutalon/cls/OcuTalon/Test/Fix/PartnerWarning.cls`, `PartnerDraft.cls`, `PartnerTurns.cls`: renames, the state and sentence pins, `TestResolvedDraftSaysTheOrdersWentThrough`, the retired-address re-check row.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`: two fixture texts and `TestSummaryFixFullStop`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Summary.cls`, `Test/Core/WebChatOut.cls`, `Test/Channel/TelegramOut.cls`, `Test/Demo/SimPhoneOut.cls`: the Evidence line's full stop.
- `web/e2e/chat/notice.spec.ts`: N20's expected Evidence line (a test pin, no web source).

**Review:** 16 findings; patches applied 4 (1 medium: retired-address re-check row; 3 low: phone in the full-stop loop, `fixing` in the Facts loop, the stale header bullet); deferred 0; the rest rejected with reasons in the triage log.

**Follow-up review recommended:** false (no patched high; one patched medium).

**Verification:** warm lane-D stack: `Test.Fix.PartnerWarning`, `PartnerDraft`, `PartnerTurns`, `Test.Msg.Catalog`, `Test.Watch.Summary`, `Test.Demo.SimMailboxIn` all passed after the last patch; `docker/tests/test-mock.sh` 134/134; all 32 `ci/checks.sh` scripts passed (run one by one, the whole script exceeds the 10-minute cap); `PartnerTurns` passed on a fresh stack; `npm --prefix web test` 1912/1912. Playwright `notice.spec.ts` N20 not run here (left to CI). Stacks torn down.

**Residual risks:** the real model's wording for a resolved incident is the Planner's RC-eval item; Epic 35 touches `Test/Msg/Catalog.cls` (separate hunks, both kept at integrate).
