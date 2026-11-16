---
title: "DW-1421 round 3: the evidence cut keeps at least 64 characters at a word boundary, every length refusal has a fixed tag with no number, and a diagnosis may leave its confidence out (none stored, none shown)"
type: 'feature'
created: '2026-11-16'
status: 'done'
baseline_revision: '0575abeba6c9d0fe40021576914260d8486421b9'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-0-dw-1421-c2p-an-over-long-evidence-element-is-cut-not-refused.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-0-dw-1421-diagnosis-refusals-name-their-rule-and-a-capture-harness.md'
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1421 round 3; Contest Planner "DW-1421 round 3", ~17:15Z Nov 16, BINDING):**
- **Cut floor.** Round 2's `DiagnosisPayload.Cut` keeps the text before the last space at or before position 128, however short. A reference whose only early space is near its start ("TargetConfigNames: <140 characters with no space>") becomes "TargetConfigNames:" plus U+2026 (round-2 review, "by-design (spec-bound)"). Ruling 1: if that space leaves fewer than 64 characters, cut mid-word instead: 127 characters plus U+2026. Add a test row for a reference whose only space is early.
- **C1 for the other seven fields.** Round 2 tagged only Evidence. The length refusals of Outcome, Reasons, CauseCategory, ElementAtFault, FixKind, Cause and FixSummary still read "<Property>[ element <n>]: <length> > <limit>" (round-2 audit table). Ruling 2: give each length refusal its own fixed tag, in the field-too-long style; no rule string may contain a number; one test row per field.
- **C5, missing confidence.** Ruling 3: decide KEEPS its refusal (it falls back to tellnow, the cautious direction). Diagnose defaults a missing confidence to ABSENT (display only); the UI must show no "Confidence" line, not 0; pin it. Decide's question goes to the post-cut Triage A/B as its own measured instruction question: not built here.

**Approach:**
- **Cut floor (Lane A, `Watch/Msg/DiagnosisPayload.cls`):** a new parameter `EVIDENCEFLOOR = 64`. In `Cut`, the blank-head test becomes `$Length(head) < ..#EVIDENCEFLOOR` (the head measured after its trailing white space is removed). A blank head is empty after that strip, so it is one case of the floor. The hard cut and its surrogate guard are unchanged.
- **C1 (Lane A, data only):** seven new `-too-long` pairs. `outcome-too-long:outcome` and `reasons-too-long:reasons` go in `DecisionPayload.REFUSALRULES`, because the properties are the parent's and the triage reply class is `DecisionPayload` itself. `DiagnosisPayload.REFUSALRULES` repeats the parent's list first, as it must, and appends `cause-category-too-long:causeCategory`, `element-at-fault-too-long:elementAtFault`, `fix-kind-too-long:fixKind`, `cause-too-long:cause` and `fix-summary-too-long:fixSummary` after `evidence-too-long:evidence`. Round 2's `Decide.LengthTag` already resolves any listed `-too-long` tag by the property's JSON field, so `Decide.cls` is NOT changed. The test probe `ProbeReplyCheck` gets its own REFUSALRULES with no length tag, so the generic numeric forms stay pinned for a reply class that lists none. A test pins that no tag holds a digit, and that every limited top-level field of both classes has exactly one tag.
- **C5 (Lane A + Lane B):** a new parameter `DecisionPayload.CONFIDENCEREQUIRED = 1`. The rule `confidence-missing` (`DecisionPayload.cls:35`) fires only when `$Parameter($this, "CONFIDENCEREQUIRED")` is true. `DiagnosisPayload` sets it to 0. A diagnosis without confidence is accepted. Its Decision row stores Confidence "" (as fallback rows already do), its Payload JSON has no `confidence` key, and the live payload has none, so the incident card's decision strip shows no "Confidence" item (it already guards `undefined`). Web (Lane B): the strip's line-1 items move into a pure `stripMeta` in `decision-view.ts`, so that a node test can pin "no Confidence line" on the incident card's view model. Decide (triage) still refuses.

## Boundaries & Constraints

**Always:**
- **Footprint.** Lane C makes the edits under the Planner's DW-1421 round-3 ruling. The commits go on top of `0575abeba` on `OCT-epic0-dw1421`. Never force-push.
  - Lane A product: `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls` (CONFIDENCEREQUIRED, the guard on L35, two pairs, class and parameter docs); `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls` (EVIDENCEFLOOR, one line of `Cut`, CONFIDENCEREQUIRED = 0, REFUSALRULES, docs).
  - Lane A tests: `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls`, `src/ocutalon/cls/OcuTalon/Test/Eval/Capture.cls`, `src/ocutalon/cls/OcuTalon/Test/Bridge/ReplyCheck.cls` (class doc only), `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeReplyCheck.cls` (its own REFUSALRULES).
  - Lane B: `web/src/app/chat/decision-view.ts` (new `stripMeta`), `web/src/app/chat/decision-strip.ts` (its `meta` calls `stripMeta`), `web/scripts/decision-view.test.mjs`, `web/scripts/incident-view.test.mjs`.
  - Architecture: `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` L271 (Veto item 4; only if the Planner approves the amendment).
  - This spec.
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` is touched ONLY if Task 0 item 1 says so (one line of `Judge`).
- The cut is still at most 128 characters, U+2026 included. It still applies to string elements of `evidence` only, never changes an element of 128 characters or fewer, and keeps the order and the count. `EvidenceCut` is unchanged.
- A tag is a fixed name from the class's compiled parameter, never a value of the reply. No tag holds a digit. A length refusal of a listed field shows "ERROR #7201 rule <tag>", with no position, length or limit.
- `RefusalText`'s contract stands: no reply value can follow "rule" (C1 gate pin).
- Decide (DecisionPayload, CONFIDENCEREQUIRED 1) refuses a reply with no confidence exactly as at the baseline: "ERROR #5001 rule confidence-missing", fallback `invalid`, tellnow.
- A diagnosis without a confidence stores Confidence "" (empty, never 0) on the Decision row and the DecisionResponse. Its Payload JSON and its live payload have no `confidence` key (not 0, not null). A diagnosis WITH a confidence is stored and shown as before.
- ObjectScript stays ASCII (`$Char(8230)`). Comments state the contract, not review history. No absolute local path in any file.
- Every existing test passes, with only the pins listed under Tasks changed.

**Never:**
- Change model-facing text: an INSTRUCTIONS block, a pack, a tool description. `Agent/Diagnosis.cls:40` still asks for a confidence, and `Agent/Triage.cls:33` is unchanged. Decide's missing confidence is the post-cut Triage A/B's question: build nothing for it.
- Change `Decide.cls` (beyond Task 0 item 1's conditional line), `CaptureTool.cls`, `Judge`'s classification, the fallback reasons, `MAXEVIDENCE`, any MAXLEN, or `Live/Payload/Decision.cls`, `Web/History.cls`, `rail-view.ts`, `notice-card.ts`.
- Tag the Confidence range form, drop element positions, or remove error codes (see the number audit). These need a ruling (PLANNER REPORT).
- Log or trace the text of a reference, or a confidence value.
- Add a column, a table, a catalog key, a UI string or a setting.
- Delete, skip or weaken a test beyond the pins this spec changes.

## I/O & Edge-Case Matrix

"Accepted" means `CheckReply` OK and, through `Conclude`, Fallback 0. "a/b/e x n" means n copies of the letter. "Hard cut" means the first 127 characters plus U+2026.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| F1 Early space only | "TargetConfigNames: " + e x 140 (159 chars; the only space at 19) | Accepted; hard cut: "TargetConfigNames: " + e x 108 + U+2026 (128); `EvidenceCut` 1 | none |
| F2 Kept 64 | a x 64 + " " + b x 100 (165; space at 65) | Accepted; a x 64 + U+2026 (65 chars): the word cut is kept | none |
| F3 Kept 63 | a x 63 + " " + b x 100 (164; space at 64) | Accepted; hard cut: a x 63 + " " + b x 63 + U+2026 (128) | none |
| F4 Kept 63 after the strip | a x 63 + "  " + b x 100 (165; last space at 65, head before the strip 64) | Accepted; hard cut: a x 63 + "  " + b x 62 + U+2026 (128) | none |
| F5 Round-2 rows | rows 1 to 8 and 11 to 14 of `TestEvidenceCut` (heads 119 or 127; no space; blank head; surrogate pair) | Unchanged results; row 6 (blank head) now goes through the floor | none |
| L1 outcome | diagnose reply, outcome of 33 characters | Refused; RefusalText "ERROR #7201 rule outcome-too-long" | fallback invalid |
| L2 reasons | one reason of 1001 | "ERROR #7201 rule reasons-too-long" (no element position) | fallback invalid |
| L3 causeCategory | 33 characters | "ERROR #7201 rule cause-category-too-long" | fallback invalid |
| L4 elementAtFault | 129 characters | "ERROR #7201 rule element-at-fault-too-long" | fallback invalid |
| L5 fixKind | 33 characters | "ERROR #7201 rule fix-kind-too-long" | fallback invalid |
| L6 cause | 1001 characters | "ERROR #7201 rule cause-too-long" | fallback invalid |
| L7 fixSummary | 1001 characters (Usable, data_format_change) | "ERROR #7201 rule fix-summary-too-long" | fallback invalid |
| L8 evidence | a JSON number of 129 digits; a 128 element after `ProbeFilter` | "ERROR #7201 rule evidence-too-long" (round 2, unchanged) | fallback invalid |
| L9 Triage | `DecisionPayload`: outcome of 33; a reason of 1001 | "ERROR #7201 rule outcome-too-long"; "ERROR #7201 rule reasons-too-long" | fallback invalid |
| L10 After the filter | Outage() with a cause of 997, `Recheck` with `ProbeFilter` ("[f] " makes it 1001) | 0; problem "After the reply filter ran: OcuTalon.Watch.Msg.DiagnosisPayload refused the filtered payload: ERROR #7201 rule cause-too-long" | fallback invalid |
| L11 A class with no length tag | `ProbeReplyCheck`: note of 105; a reason of 1005 | "Note: 105 > 100"; "Reasons element 2: 1005 > 1000" (the generic form, unchanged) | fallback invalid |
| L12 Harness | the part "ERROR #7201 rule element-at-fault-too-long" | rule `element-at-fault-too-long`, field `elementAtFault` | none |
| C1 Diagnose, no key | Usable() or Outage() without `confidence` | Accepted; `payload.Confidence` "" | none |
| C2 Stored | C1 through `Conclude` | Fallback 0; row.Confidence "" (length 0); row Payload JSON has no `confidence` key; response.Confidence ""; `Live.Payload.Decision.FromRow(row)` exports no `confidence` key | none |
| C3 Diagnose, null | `"confidence": null` | As Task 0 item 2 measures: accepted and absent when the import gives ""; else the refusal it gives today | per Task 0 |
| C4 Diagnose, 0 | `"confidence": 0` | Accepted; row.Confidence 0; Payload `"confidence":0`; live payload `confidence` 0 (absent is not 0) | none |
| C5 Diagnose, out of range | `"confidence": 85` | Refused "Confidence: value > 1" (unchanged; a number case, see the audit) | fallback invalid |
| C6 Decide, no key | `DecisionPayload`, no `confidence` | Refused "ERROR #5001 rule confidence-missing"; through Conclude: fallback invalid, tellnow (existing pins) | fallback invalid |
| C7 Capture | a diagnose fallback whose reply has no confidence | `Recheck` 1; rule "passes the check" | none |
| C8 Web, incident card | the diagnosis decision payload has no `confidence` key | the footer strip's line-1 items hold no item that starts "Confidence" | none |
| C9 Web, 0 and fallback | confidence 0, not a fallback; confidence 0.9 on a fallback | "Confidence 0.00" shown; none on the fallback | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `0575abeba`.

- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`:
  - class doc L1-5 ("and a confidence that is present", L4);
  - `REFUSALRULES` L9-11 (doc L9-10: "A tag is lower-case letters, digits and hyphens");
  - `Confidence` L19-20;
  - `%OnValidateObject` L24-37, with `confidence-missing` at L35.
  - Inherited by `DiagnosisPayload` and by the test probe `Test/Bridge/ProbeReplyCheck.cls` (no REFUSALRULES of its own, L5-25). It is the triage reply class (`Production.cls` L32, L43; `BridgeExample/Production.cls` L31).
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - class doc L1-23 (L1-2 "outcome, reasons and confidence are the parent's"; L18-23 the tags and the length tag);
  - `REFUSALRULES` L40-42; `EVIDENCEMAX` L47-48;
  - the limited properties: `CauseCategory` L51 (32), `ElementAtFault` L54 (128), `Evidence` L57 (128), `FixKind` L60 (32), `Cause` L66 (1000), `FixSummary` L69 (1000). Nested `FixParameters` and `ItemNoun` are object properties;
  - `%JSONImport` L80-107; `Cut` L109-126 (doc L109-110; the blank-head test L120; the hard cut and surrogate guard L121-123);
  - `%OnValidateObject` L129-166 (`##super()` L131).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`. NOT changed (except Task 0 item 1):
  - `RefusalText` L1053-1097; `RefusalTag` L1104-1109;
  - `LengthTag` L1148-1166: the first pair of `$Parameter(replyClass, "REFUSALRULES")` whose field is the property's `%JSONFIELDNAME` and whose tag ends in `-too-long`;
  - `RefusalPart` L1169-1190: the tag branch L1171-1174 comes before the numeric forms L1177-1180;
  - `RefusalImport` L1193-1243 and `RefusalCheck` L1246-1255 pass the property and the position;
  - `Judge` L1691-1750: `Set confidence = $Number(payload.Confidence, 2)` L1747; export L1748.
  - The row: L1524 `row.Confidence = confidence`. Fallback rows store "" (L1636, L1774). `ResponseFromRow` L1909.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Decision.cls`: `Confidence` L24 (`%Numeric`, no `%JSONNULL`); `FromRow` L89. `Web/Api.cls` `PayloadObject` L1549-1553 exports it with `%JSONExportToString`. `Web/History.cls` L58 sets `confidence` only when not "" (decide rows only, `Ownership.cls` L89, L1244).
- Where a diagnosis's confidence is shown: only in the incident card's footer strip.
  - `web/src/app/incidents/incident-card.ts` L179-186 (`app-decision-strip` with `strip.decision`); `incident-view.ts` `decisionOf` L457-460, `strip` L557-560.
  - `web/src/app/chat/decision-strip.ts` `meta` L233-245: `confidence !== undefined` and not a fallback, then `confidenceText`.
  - The rail and the history list decide rows only (`rail-view.ts` L416-420 `kind === 'decide'`; `Ownership.cls` L1244, L89).
  - Visual Trace shows the DecisionResponse's Confidence (empty for such a row).
- `web/src/app/chat/decision-view.ts`: module doc L1-12 (imports types only; Node runs it); `formatConfidence` L94-97 (absent gives "0.00"); `confidenceText` L113-116.
- Tests that pin what changes:
  - `Test/Watch/Payload.cls`:
    - class doc L1-30 (TestRefusalTrace L14-20; TestRuleTags L21-22; TestEveryRuleTagged L23-25; TestEvidenceCut L26-28; TestEvidenceTooLongTag L32);
    - `TestRefusalTrace` expected L348 ("ElementAtFault: 129 > 128");
    - `RuleTags` L410-413; `RuleReply` L416-443 (confidence-missing L421);
    - `TestRuleTags` L453-464 (L461-463: 23 pairs, the first 22, the 23rd);
    - `TestEveryRuleTagged` L467-513 (L472 three, L473 `$List(pairs, 1, 3)`, L493 `index > 3`, the tag pattern L483, L512 "the parent lists no length tag");
    - `TestEvidenceCut` L581-662 (row 9 L619-624);
    - `TestEvidenceTooLongTag` L723-745 (L739 "keeps its length form").
  - `Test/Eval/Capture.cls`:
    - class doc L7-10 ("each rule once, confidence-missing and cause-blank twice, 'passes the check' three times");
    - `SeedAll` L177-305: the loop over `RuleTags` L180-193 (skips L185); the triage seed L215-221; "passes the check" L222-229 (`= 1` at L229); the elementAtFault seed L255-261;
    - `TestRuleNames` L397-410.
  - `Test/Bridge/ReplyCheck.cls`: doc L10-12, rows 2 and 6 (L287, L314) and form a (L383) use the probe's Reasons. They stay as they are because the probe lists no length tag.
  - Decide's refusal stays pinned by `Test/Bridge/Decide.cls` L653 ("no confidence"), `Test/Agent/RememberDecision.cls` (`DEMOTAIL` L32, `TestProbeShapeIsTheDemoWarning`), `Test/Eval/Capture.cls` L215-221 and ReplyCheck row k (L404-405).
  - `web/scripts/decision-view.test.mjs` L177-190; `web/scripts/incident-view.test.mjs` `DECISION` L41, `view` L72, the strip L101-106; `web/scripts/rail-view.test.mjs` L676-680 (a decide row with no confidence shows none; unchanged).
- Guards that must stay green: `Test/Bridge/Contracts.cls` (DecisionPayload props, L233-240; parameters are not pinned); `Test/Live/Payloads.cls`; `Test/Web/HistoryApi.cls` L166; `Test/Watch/Summary.cls` `TestCutEvidence`; `Test/Watch/Diagnose.cls`; `Test/Agent/Instructions.cls`; `Test/Bridge/CodeRules.cls`; `docker/tests/test-bridge-guide.sh` (it reads `DecisionPayload.cls`'s JSON field names, L327; `docs/bridge-guide.md` L262 "a missing confidence is `invalid`" stays true of DecisionPayload).
- Spine: `ARCHITECTURE-SPINE.md` L271 ("both carry plain-English reasons and a confidence between 0 and 1, which the incident card and Visual Trace show for a diagnosis too"). UX: `EXPERIENCE.md` L293 ("A fallback decision omits confidence"): no change needed (Veto item 4).

## Planner ruling on this plan (Contest Planner, ~17:45Z Nov 16; BINDING)

- APPROVED as planned: the cut floor 64 with rows F1-F4 and their mutations; the seven length tags, every limited field "<field>-too-long" with no digit, and `TestEveryRuleTagged`'s extra checks; C5 (`CONFIDENCEREQUIRED` 1 on DecisionPayload and 0 on DiagnosisPayload, a missing confidence stored "" never 0 with no key, the `stripMeta` pin, decide still refuses).
- **Q1, Option R: YES.** Build the fixed tag `confidence-out-of-range` (Option R below is now part of the build, Task "Option R"). Q2 (element positions) and Q3 (error codes, "; and k more") stay as they are.
- Design choices (i) to (v): ALL APPROVED. Spine L271: APPROVED verbatim, with the marker.
- Behaviour change APPROVED: a diagnosis missing only its confidence is accepted, where today it falls back.
- ONE CHECK from code before merge (the build does not wait for it): can any refusal or rule string ever reach a MODEL prompt (a repair or retry turn, a tool result carrying the check's problem text)? Report YES or NO with file and line evidence in PART READY. If YES, the merge waits for a Planner ruling.
- After PART READY, round 3 gets its own re-capture by the Planner.

**Task "Option R" (ruled; build it):**
- `DecisionPayload.REFUSALRULES` appends `confidence-out-of-range:confidence` after `reasons-too-long:reasons` (the parent's list is then 3 rules, 2 length tags, 1 range tag). `DiagnosisPayload.REFUSALRULES` repeats the parent's whole list first, so it holds 31 pairs. The REFUSALRULES docs name range tags ("a tag that ends in -out-of-range is the range tag of a field with a MINVAL or MAXVAL, which no rule raises").
- `Decide.LengthTag` takes a suffix argument (default "-too-long"), keeping its tag pattern check. `RefusalPart`: before the generic #7203/#7204 form, a #7203 or #7204 on a property whose field has a listed tag ending in `-out-of-range` is "ERROR #<code> rule <tag>", with no value or limit. The method doc (L1039-1041) adds that line. Nothing else in Decide changes.
- `ProbeReplyCheck` keeps its own list (no length or range tag), so `Test.Bridge.ReplyCheck` row 3 and form j keep pinning the generic "Confidence: value > 1" form.
- Tests: in `TestLengthTags` (or a sibling `TestRangeTag`), one row each for DecisionPayload (`"confidence": 85`, decide) and DiagnosisPayload (`"confidence": 85`, diagnose) and one for a negative confidence: `RefusalText` is exactly "ERROR #7203 rule confidence-out-of-range" (or #7204 for the negative), with no digit after the code; `CaptureTool.RuleOf` is the tag and `FieldOf` is `confidence`. A mutation (drop the RefusalPart branch) must fail them. `TestEveryRuleTagged`: every `-out-of-range` pair names a top-level field with a numeric MINVAL or MAXVAL, none is written in a `%OnValidateObject`, no tag holds a digit, and each class has exactly one range tag for `confidence`. `TestRuleTags`: the list without its `-too-long` and `-out-of-range` pairs equals `RuleTags()`; the class list holds 31 pairs. Any seed or count in `Test.Eval.Capture` that this moves is a changed pin, recorded.

## Planner rulings after the review (Contest Planner, ~18:45Z Nov 16; BINDING)

- Model-prompt check: an indirect YES (the self-watch path, see the review). Ruling, verbatim: "refusal tags can reach the diagnosis model only via read_event_log when OcuTalon watches its own production; same exposure class as before; no A/B (no eval coverage); Planner ruling 2026-11-16". Ledgered as DW-1437 (LOW, a future self-watch eval case).
- Bridge guide, in round 3, exactly three changes to `docs/bridge-guide.md` (PUBLIC TEXT: the exact old and new text goes to the Planner before it lands): (a) the DecisionResponse table's Confidence row: a diagnosis may have none, and the card then shows none; (b) one sentence on `CONFIDENCEREQUIRED` (1 on DecisionPayload, 0 on DiagnosisPayload); (c) one sentence that refusal rules are fixed tags such as `<field>-too-long` and `confidence-out-of-range`, with no values. `docker/tests/test-bridge-guide.sh` stays green.
- Round 3 merges on green CI plus the Planner's round-3 verification re-capture.
- Bridge guide text APPROVED (~19:00Z Nov 16): (a) and (c) verbatim; (b) replaced by the Planner's text ("A reply with another field or a field of the wrong type is `invalid`, and so is a reply without a confidence when its class requires one. The class parameter `CONFIDENCEREQUIRED` says whether it does: ..."). `test-bridge-guide.sh` rule `confidencetext` pins the three lines as whole lines (a one-character change of the guide turns it red). Ledgered DW-1438 (LOW): CLOCKTIME refuses a cause that quotes a field's own date-time value (report-only, shipments-day-first-date).

## Tasks & Acceptance

**Task 0 (measure first, lane-C warm throwaway, no model, no key; record under `## Verification`):**
1. Record `$Number("", 2)` (expect ""). **Rule:** if it is not "", `Judge` L1747 becomes `Set confidence = $Select(payload.Confidence = "": "", 1: $Number(payload.Confidence, 2))`, `Decide.cls` joins the footprint, and the Judge mutation below applies.
2. Record what `DiagnosisPayload.%JSONImport` gives for a reply with `"confidence": null`: the status and `Confidence`. **Rule:** if OK and "", row C3 expects acceptance with the confidence absent. Otherwise row C3 expects that refusal. No code is changed for either.
3. Record `%JSONExportToString` of a DiagnosisPayload with Confidence "" (expect no `confidence` key), and of `Live.Payload.Decision.FromRow` for a row with Confidence "" (expect no key). **Rule:** if either writes the key (null or ""), stop with `## Clarification Needed`: hiding it would change a shared serializer.
4. Grep `eval/`, `docker/tests/lib-stub.sh`, `docker/tests/test-mock.sh` and `src/ocutalon/cls/OcuTalon/Test` for a diagnose reply with no `confidence` that a test or a stub expects to fall back. Record each hit. Any such pin is a changed pin of this spec.

**Execution:**
- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`:
  - a new parameter before `REFUSALRULES`:
    - `/// 1 when a reply must carry a confidence (the rule confidence-missing). A subclass whose confidence is only shown sets it to 0: a reply without one is then accepted and has none (DiagnosisPayload, DW-1421 C5).`
    - `Parameter CONFIDENCEREQUIRED = 1;`
  - L35: `If (..Confidence = "") && $Parameter($this, "CONFIDENCEREQUIRED") Quit $$$ERROR($$$GeneralError, "The confidence is missing", "confidence-missing")`. `$this` reads the value of the object's own class at run time, so a subclass's 0 applies to this inherited method;
  - `REFUSALRULES` = `"outcome-unlisted:outcome,reasons-blank:reasons,confidence-missing:confidence,outcome-too-long:outcome,reasons-too-long:reasons,confidence-out-of-range:confidence"` (Option R, ruled);
  - its doc (L9-10): "The fixed name of each rule of %OnValidateObject and the JSON field it reads, as tag:field, comma-separated, then the length tag of each limited field (field-too-long), which no rule raises; a subclass lists these first, then its own. A tag is lower-case letters and hyphens, with no digit. Decide shows a tag in a refusal only when the reply class lists it here, and never a value of the reply.";
  - class doc L4: "and a confidence that is present" becomes "and a confidence that is present unless CONFIDENCEREQUIRED is 0". L5 adds: "Each limited field has a length tag, field-too-long, that Decide shows for a text over its limit (DW-1421)."
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - `/// A diagnosis may leave out its confidence: it is only shown, so a reply without one is accepted, its decision stores none and nothing is shown, never 0 (DW-1421 C5).` / `Parameter CONFIDENCEREQUIRED = 0;`
  - `/// The fewest characters that a cut at a word boundary keeps: when the text before the last space at or before EVIDENCEMAX is shorter, once its trailing white space is removed, Cut cuts mid-word (DW-1421 round 3).` / `Parameter EVIDENCEFLOOR = 64;`
  - `Cut` L120: `If $ZStrip(head, "*W") = "" {` becomes `If $Length(head) < ..#EVIDENCEFLOOR {`. Nothing else in `Cut` changes;
  - `Cut` doc L109-110: "The head is the text before the last space at a position of 2 to EVIDENCEMAX, with trailing white space removed, when it keeps at least EVIDENCEFLOOR characters; otherwise (no such space, a shorter head, or a blank one) it is the first EVIDENCEMAX - 1 characters (less one, when the cut would end on the first half of a surrogate pair).";
  - `REFUSALRULES` (exact before Option R; 30 pairs, and 31 with `confidence-out-of-range:confidence` inserted after `reasons-too-long:reasons` per Task "Option R") = `"outcome-unlisted:outcome,reasons-blank:reasons,confidence-missing:confidence,outcome-too-long:outcome,reasons-too-long:reasons,outcome-not-act:outcome,cause-category-unlisted:causeCategory,evidence-over-max:evidence,cause-blank:cause,format-no-fix-element-blank:elementAtFault,format-fix-kind-unlisted:fixKind,format-fix-element-blank:elementAtFault,format-fix-summary-blank:fixSummary,format-fix-field-blank:fixParameters.field,rollback-fix-parameters:fixParameters,rollback-fix-summary:fixSummary,rollback-element-unlisted:elementAtFault,fix-kind-not-for-category:fixKind,fix-parameters-not-for-category:fixParameters,fix-summary-not-for-category:fixSummary,item-noun-blank:itemNoun,time-of-day-in-cause:cause,time-of-day-in-fix-summary:fixSummary,fix-parameters-check:fixParameters,evidence-too-long:evidence,cause-category-too-long:causeCategory,element-at-fault-too-long:elementAtFault,fix-kind-too-long:fixKind,cause-too-long:cause,fix-summary-too-long:fixSummary"`. Its doc (L40-41): "the parent's list (its rules and its length tags), then this class's own rules in rule order, then this class's length tags";
  - class doc:
    - L1-2 add: "the confidence may be left out (CONFIDENCEREQUIRED is 0), and the decision then has none";
    - L18: "the parent's three (a diagnosis never meets confidence-missing) and this class's nineteen";
    - L20-22: "A tag that ends in -too-long is a length tag, one for each limited field: the parent's outcome-too-long and reasons-too-long, and this class's evidence-too-long, cause-category-too-long, element-at-fault-too-long, fix-kind-too-long, cause-too-long and fix-summary-too-long. Decide's RefusalText shows 'ERROR #7201 rule <tag>' for a text over the limit of that field, with no position, length or limit. No tag holds a digit." Keep the evidence-too-long sentence on where it still occurs.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeReplyCheck.cls`: `/// The parent's rules without its length tags: the probe is the reply class that lists no length tag, so the tests of OcuTalon.Bridge.ReplyCheck pin Decide's generic forms ("<Property>[ element <n>]: <length> > <limit>").` / `Parameter REFUSALRULES = "outcome-unlisted:outcome,reasons-blank:reasons,confidence-missing:confidence";`
- `web/src/app/chat/decision-view.ts`: `import type { DecisionPayload } from '../live/payloads';` (types only). Add:
  - `/** The items of a strip's line 1 after the chip and the flag: the confidence, unless it is a fallback or the decision has none (absent is not 0), then the cost when given. */`
  - `export function stripMeta(decision: DecisionPayload | undefined, fallback: boolean, cost: number | undefined): string[]`. It holds the body of `decision-strip.ts`'s `meta` as it is: `confidence !== undefined` and `!fallback` push `confidenceText(confidence)`; a cost that is not undefined pushes `formatCost(cost)`.
  - The module doc adds one bullet: "stripMeta gives the strip's line 1 after the chip: no confidence on a fallback or when the decision has none".
- `web/src/app/chat/decision-strip.ts`: `meta = computed(() => stripMeta(this.decision(), this.fallback(), this.cost()))`; import `stripMeta` and drop the import of `confidenceText` and `formatCost` if they are no longer used there. No template change.
- Tests: below.

**Acceptance Criteria:**
- **AC 1 (the cut floor; F1-F5).** Given a reply whose only evidence element is the input, when `CheckReply` checks it, then the element is exactly as the matrix says, at most 128 characters, ending in U+2026, with `EvidenceCut` 1.
  - Pinning test: `Test.Watch.Payload` `TestEvidenceCut`, new rows "row 16, a reference whose only space is early" (F1), "row 17, a word boundary that keeps 64" (F2), "row 18, a word boundary that keeps 63" (F3) and "row 19, 63 kept once two spaces are removed" (F4), each through `AssertCut`. Plus `$Parameter(CLASS, "EVIDENCEFLOOR") = 64`. Rows 1-15 are unchanged.
- **AC 2 (one tag per limited field; L1-L9, L12).** Given a reply with exactly one field over its limit, when `CheckReply` refuses it, then `RefusalText` is exactly "ERROR #7201 rule <tag>" and the text holds no digit after "#7201".
  - Pinning test: new `Test.Watch.Payload` `TestLengthTags`, one row per field. L1-L7 use DiagnosisPayload, and L9 uses `OcuTalon.Bridge.Msg.DecisionPayload` with a decide reply `{"outcome", "reasons", "confidence"}`.
  - For each row it also asserts `CaptureTool.RuleOf(part)` is the tag and `CaptureTool.FieldOf(part, tag, class)` is the field.
  - Changed pins:
    - `TestRefusalTrace` L348 becomes `first_"ERROR #7201 rule element-at-fault-too-long"` (class doc L15-18 follows);
    - `TestEvidenceCut` row 9 becomes "ERROR #7201 rule element-at-fault-too-long" and "ERROR #7201 rule reasons-too-long";
    - `TestEvidenceTooLongTag` L739 becomes "ERROR #7201 rule element-at-fault-too-long", label "an elementAtFault of 129 has its own length tag";
    - `Test.Eval.Capture` `SeedAll` L255-261: the elementAtFault seed's rule is "element-at-fault-too-long", field `elementAtFault`, count key renamed;
    - `TestRuleNames` adds the part "ERROR #7201 rule element-at-fault-too-long" (rule `element-at-fault-too-long`, field `elementAtFault`). Its other parts are unchanged, since "ElementAtFault: 129 > 128" still pins the generic part's path.
- **AC 3 (after the filter; L10).** Given Outage() with a cause of 997 characters, when `Decide.Recheck` runs it with `OcuTalon.Test.Bridge.ProbeFilter`, then it returns 0 with the problem L10 states (the test kills `^||ZzProbeFilter`).
  - Pinning test: `TestLengthTags`.
- **AC 4 (a class with no length tag keeps the generic form; L11).** Given `ProbeReplyCheck`, then `Test.Bridge.ReplyCheck` rows 1, 2, 5, 6 and form a pass unchanged.
  - Pinning test: `Test.Bridge.ReplyCheck` (no code change; its doc L10-12 adds "(the probe lists no length tag)").
- **AC 5 (the allowlists; no number, complete).** Given the two REFUSALRULES:
  - every tag of both lists matches `1L.(1L,1"-")`, with no digit;
  - the class's list starts with its parent's whole list (`$List(pairs, 1, $ListLength(parentPairs))`), and the own-rule pairs are counted from `$ListLength(parentPairs) + 1`;
  - the parent lists 3 rules and 2 length tags;
  - for EACH class, every compiled top-level property that has a `%JSONFIELDNAME` and a numeric MAXLEN has exactly one `-too-long` pair for that field. For DiagnosisPayload that is 8: its 6 and the parent's 2 in the prefix. For the parent it is 2;
  - the rest of the test is unchanged: each `-too-long` pair names a numeric-MAXLEN field, and none is written in a `%OnValidateObject`.
  - Pinning test: `TestEveryRuleTagged`, changed. L512 "the parent lists no length tag" becomes "the parent lists outcome-too-long:outcome and reasons-too-long:reasons", and the doc L23-25 follows.
  - Also `TestRuleTags`:
    - the class's list holds 31 pairs (30 plus Option R's range tag);
    - the list without its `-too-long` pairs equals `RuleTags()`, in order;
    - its `-too-long` pairs, in order, are a new `LengthTags()` = `"outcome-too-long:outcome,reasons-too-long:reasons,evidence-too-long:evidence,cause-category-too-long:causeCategory,element-at-fault-too-long:elementAtFault,fix-kind-too-long:fixKind,cause-too-long:cause,fix-summary-too-long:fixSummary"`;
    - and (C5) `confidence-missing` is asserted ACCEPTED for DiagnosisPayload, not refused (AC 6).
- **AC 6 (C5, diagnose: absent; C1-C4, C7).** Given a diagnose reply with no `confidence` key, then:
  - `CheckReply` with DiagnosisPayload is OK with `payload.Confidence` "";
  - through `Conclude` (ReplyGuard): Fallback 0; `$Length(row.Confidence)` 0; `{}.%FromJSON(row.Payload).%GetTypeOf("confidence")` "unassigned"; `response.Confidence` "";
  - `{}.%FromJSON(json).%GetTypeOf("confidence")` is "unassigned" for `Live.Payload.Decision.FromRow(row).%JSONExportToString(.json)`;
  - for C4 (`"confidence": 0`), row.Confidence is 0 with `$Length` 1, and the payload and the live payload carry the number 0;
  - C3 is as Task 0 item 2 recorded;
  - `$Parameter` of CONFIDENCEREQUIRED is 1 for DecisionPayload, 0 for DiagnosisPayload, and 1 for ProbeReplyCheck.
  - Pinning test: new `Test.Watch.Payload` `TestConfidenceAbsent`.
  - Changed pins:
    - `TestRuleTags`: confidence-missing is accepted for DiagnosisPayload with Confidence "";
    - `Test.Eval.Capture` `SeedAll`: the loop skips `confidence-missing` (as it skips cause-blank and outcome-not-act, L185). After the usable seed, one diagnose seed `RuleReply("confidence-missing")` with a marker is expected as "passes the check" (stage "", field ""). L229 becomes `Set count("passes the check") = $Get(count("passes the check")) + 1`, and the count is 4 in all;
    - `confidence-missing` is counted once, from the triage seed L215-221;
    - the class doc L7-10: "one diagnose reply for each of the 21 rules that a diagnosis can meet, a diagnose reply with no confidence (it passes, DW-1421 C5), ...; each rule once, cause-blank twice, 'passes the check' four times".
    - The decision counts (33 | 1 | 32 | 33 | 34) and `TestLinesHoldNoReplyText`'s CHK line are unchanged.
- **AC 7 (C5, decide keeps its refusal; C6).** Given a decide reply with no confidence, `CheckReply` with DecisionPayload is refused with RefusalText "ERROR #5001 rule confidence-missing".
  - Pinning tests: `TestConfidenceAbsent` (the decide row), plus the unchanged `Test.Bridge.Decide` L653, `Test.Agent.RememberDecision` `TestProbeShapeIsTheDemoWarning` and `Test.Eval.Capture`'s triage seed.
- **AC 8 (C5, the web shows no Confidence line; C8, C9).**
  - `decision-view.test.mjs`, new `describe('stripMeta')`:
    - a diagnose decision `{ref, kind: 'diagnose', outcome: 'act', reasons: 'r'}` with no confidence key, not a fallback, cost 0.0006, gives `['$0.0006']`, and no item starts "Confidence";
    - the same with `confidence: 0` gives `['Confidence 0.00', '$0.0006']`;
    - with `confidence: 0.94`, `['Confidence 0.94', '$0.0006']`;
    - a fallback with confidence 0.9 and no cost gives `[]`;
    - an undefined decision and an undefined cost give `[]`.
  - A source assertion in the same file: `decision-strip.ts` calls `stripMeta(` and does not call `confidenceText(`.
  - `incident-view.test.mjs`, new `it`:
    - with the incident's decision `{ ...DECISION, kind: 'diagnose' }` without its `confidence` key, `card.strip.decision` has no `confidence` property, and `stripMeta(card.strip.decision, card.strip.fallbackReason !== undefined, card.strip.cost)` holds no item that starts "Confidence";
    - with `DECISION` it holds "Confidence 0.94".
- Standing criterion (Rule 19): every test added or changed passes on a fresh environment, in either order.

## Design Notes

**The cut floor.** `Cut(text)`, with L = `EVIDENCEMAX` = 128 and F = `EVIDENCEFLOOR` = 64, for a string over L characters:
1. Find the last space (U+0020) at a position p with 2 <= p <= L. The head is `$Extract(text, 1, p - 1)` with trailing white space removed (round 2, unchanged).
2. **The floor:** if the head now holds fewer than F characters (`$Length`, the unit that MAXLEN counts), or there was no such space (head ""), the head is `$Extract(text, 1, L - 1)`, less one character when that ends on a high surrogate (55296-56319). This is round 2's hard cut and guard, unchanged.
3. The result is head plus `$Char(8230)`, at most L characters.
- **At exactly 64:** a head of 64 is kept, so a space at position 65 with no white space before it gives 64 characters plus U+2026 (F2). A head of 63 is cut mid-word (F3). The floor counts the head AFTER its trailing white space is removed, the characters that are actually kept. So a space at 65 that follows another space keeps 63 and cuts mid-word (F4). That row tells a floor counted before the strip apart from one counted after it.
- **The blank-head fallback** of round 2 (`$ZStrip(head, "*W") = ""`) is subsumed: a head of only white space is empty after the ">W" strip, 0 < 64. The test is replaced rather than kept beside the floor, so that no branch is dead. Row 6 still pins it, through the floor.
- **The surrogate guard** applies only to the hard cut. A word-boundary head ends just before a space, so it cannot end on the first half of a pair the cut made. The floor and the 128 limit both count UTF-16 units, as `$Length` and MAXLEN do. Round 2's Task 0 measured a pair as 2.
- **Not handled:** a head that is long enough but ends in many spaces before the strip (for example 60 letters, then 60 spaces, then a word) has the strip remove them and then falls under the floor, so the hard cut keeps those spaces before U+2026. That is valid and at most 128. It is not a model shape seen in C0, and a branch for it is not ruled.
- The 64 is a literal parameter, as ruled, not EVIDENCEMAX / 2.

**C1: where the seven tags live, and how they resolve.**

| Field | Property | Limit | Class that declares it | Pair | In which REFUSALRULES |
|-------|----------|-------|------------------------|------|-----------------------|
| outcome | Outcome | 32 | DecisionPayload | `outcome-too-long:outcome` | DecisionPayload, and DiagnosisPayload's copy of the parent's prefix |
| reasons | Reasons (list) | 1000 | DecisionPayload | `reasons-too-long:reasons` | same |
| causeCategory | CauseCategory | 32 | DiagnosisPayload | `cause-category-too-long:causeCategory` | DiagnosisPayload |
| elementAtFault | ElementAtFault | 128 | DiagnosisPayload | `element-at-fault-too-long:elementAtFault` | DiagnosisPayload |
| fixKind | FixKind | 32 | DiagnosisPayload | `fix-kind-too-long:fixKind` | DiagnosisPayload |
| cause | Cause | 1000 | DiagnosisPayload | `cause-too-long:cause` | DiagnosisPayload |
| fixSummary | FixSummary | 1000 | DiagnosisPayload | `fix-summary-too-long:fixSummary` | DiagnosisPayload |
| evidence | Evidence (list) | 128 | DiagnosisPayload | `evidence-too-long:evidence` (round 2) | DiagnosisPayload |

- **Inheritance.** REFUSALRULES is a parameter, so a subclass that overrides it replaces it. The convention, pinned by `TestEveryRuleTagged`, is that the subclass's string starts with the parent's whole string. `Decide.LengthTag` and `RefusalTag` read `$Parameter(replyClass, "REFUSALRULES")`, the list of the reply class itself, never the parent's. So the triage reply class (DecisionPayload) needs the outcome and reasons pairs in its own list, and DiagnosisPayload gets them by its copy of the parent's prefix. Putting them only in DiagnosisPayload would leave triage's warnings and the capture's decide counts with numbers ("Reasons element 2: 1005 > 1000"). The capture harness re-checks decide replies against DecisionPayload (`CaptureTool` L6, `Decide.ReplyClassOf`).
- **Resolution.** `RefusalPart` (unchanged) turns a #7201 on a known property into "ERROR #7201 rule <tag>" when `LengthTag` finds, in the reply class's list, the first pair whose field is the property's `%JSONFIELDNAME` and whose tag ends in `-too-long` (and matches the tag form). For outcome, the pairs of field `outcome` are outcome-unlisted, outcome-too-long and outcome-not-act, and only the second ends in `-too-long`. The import path (`RefusalImport`, then `RefusalCheck`) and the second check after the filter (#7201 with an embedded #5802) both reach `RefusalPart` with the property. So no Decide code changes, and AD-2's generic Decide stays untouched.
- **The probe.** `ProbeReplyCheck` inherits the parent's REFUSALRULES. Without an override, its Reasons rows in `Test.Bridge.ReplyCheck` would lose the generic numeric form ("Reasons element 2: 1005 > 1000", "and 1 more" over five distinct parts). That form stays product behaviour for any reply class that lists no length tag (the bridge is generic; a bridge user's class). The probe therefore lists the parent's three rules only, and those rows keep pinning the generic form unchanged. The probe is a test class (`Test/Bridge`), never a ReplyClass of the production.
- **No digits.** The allowlist itself must hold no digit: `TestEveryRuleTagged` narrows the tag form to letters and hyphens. Decide's `RefusalTag` and `LengthTag` patterns still allow a digit. They are filters against reply values, unchanged, and the test pins the lists.

**The number audit.** Every string that can follow the reply class in a refusal ("shown" means it reaches the warning, `Recheck`'s problem or the harness). The harness's "rule string" is the tag of "ERROR #<code> rule <tag>", else the part itself (`CaptureTool.RuleOf`).

| Shown part | Digits after round 3 | Origin of the digits | Covered by ruling 2? | This spec |
|------------|----------------------|----------------------|----------------------|-----------|
| "ERROR #5001 rule <tag>" (22 rules) | the code 5001 only; the tag none | fixed IRIS code | tag: yes | tags pinned digit-free |
| "ERROR #7201 rule <tag>" (8 length tags) | the code 7201 only | fixed IRIS code | yes (the length refusals) | all 8 fields tagged |
| "<Property>[ element <n>]: <length> > <limit>" | length, position, limit | reply and class | yes for the 8 fields of the two classes | gone for both reply classes; remains only for a class with no length tag (the test probe; a bridge user's class) |
| "Confidence: value > 1" / "Confidence: value < 0" (#7203/#7204) | the limit 1 or 0 | class constant (MAXVAL, MINVAL), not the reply | NOT clearly: a range refusal, not a length refusal. It IS a shown rule string with a number, and a model can reach it (for example confidence 85, row C5) | unchanged; PLANNER REPORT Q1 |
| "ERROR #9406 on <Property> element <n>" (an object or array as a list element of reasons or evidence) | the code and the position n | the reply's structure (a position, not a value) | no (a type refusal) | unchanged; Q2 |
| "ERROR #<code> on <Property> element <n>" (any other code on a list element) | the code and n | as above; not reachable today for the two classes' %String lists, whose only element check is MAXLEN | no | unchanged; Q2 |
| "; and <k> more" | k | a count of parts | no: not a rule string (the harness skips it, `CaptureTool.Parse` L249) | unchanged |
| "ERROR #9404: an unexpected property", "ERROR #5035", "ERROR #7207 on Confidence", "ERROR #9406[ on <Property>]" | the code only | fixed IRIS codes | no: constants, not values. Round 2's approved form "ERROR #7201 rule evidence-too-long" keeps its code, and the harness parses "ERROR #<code> rule" | unchanged; Q3 |
| Nested fields over their limit (fixParameters.*, itemNoun.*) | the code only ("ERROR #9406 on FixParameters", or a bare "ERROR #7201" after the filter) | fixed code | not among the seven | unchanged (no number beyond the code; not tagged) |

My reading: ruling 2 is about the length refusals ("Give each length refusal its own fixed tag"), and "No rule string may contain a number" binds those tags and the shown refusal of those rules. This spec does that completely, for every limited top-level field of both reply classes. The Confidence range form, the element positions and the error codes are outside that reading. The first is the closest case: it is a shown rule string that holds a number, but the number is a class constant, not a reply value. None is changed without a ruling.

**Option R (the Planner ruled Q1 YES, ~17:45Z Nov 16: built; see Task "Option R").** Add a pair `confidence-out-of-range:confidence` to DecisionPayload's list. Then `Decide.RefusalPart` adds a branch: a #7203 or #7204 on a property whose field has a listed tag ending in `-out-of-range` is "ERROR #<code> rule <tag>". This is a Decide change: `LengthTag` generalised by a suffix argument. Then one test row, a mutation, and `TestEveryRuleTagged` treats `-out-of-range` as it does `-too-long`. ReplyCheck row 3 and form j stay on the probe. About 15 lines.

**C5: where, how, what is stored, what is shown.**
- **Where:** `DecisionPayload.%OnValidateObject` L35 (`confidence-missing`), inherited: `DiagnosisPayload.%OnValidateObject` calls `##super()` first (L131).
- **How (diagnose only):** a parameter `CONFIDENCEREQUIRED`, 1 in DecisionPayload and 0 in DiagnosisPayload. The check reads it with `$Parameter($this, ...)`, the value of the object's own class at run time, so the result does not depend on how the class compiler handles `..#` in an inherited method. Rejected alternative: a `DiagnosisPayload.%OnValidateObject` that swallows the parent's `confidence-missing` error. It depends on that check being the parent's last, it would silently hide any rule the parent adds after it, and it puts a parent rule's tag in the subclass's code (`TestEveryRuleTagged` counts tags by class). The parameter is generic (a bridge user's reply class may set it) and adds no `$$$ERROR`.
- **What is stored:** `Judge` L1747 `$Number("", 2)` (Task 0 item 1, expected "") gives the row's Confidence "", as fallback rows already store. The payload's `%JSONExportToString` writes no `confidence` key for an empty %Numeric (Task 0 item 3; round 2's Task 0 measured the same for an empty %Integer). The DecisionResponse copies "" (L1909).
- **What is shown:**
  - the live payload (`Live.Payload.Decision.FromRow`, exported by `%JSONExportToString`) has no `confidence` key;
  - the web's `DecisionPayload.confidence?: number` is then `undefined`;
  - the incident card's strip already pushes the confidence only when it is not `undefined` and not a fallback. `formatConfidence(undefined)` would say "0.00", but nothing calls it for an absent value. AC 8 pins that, through the incident card's view model;
  - the history API and the rail list decide rows only, and the history API leaves an empty confidence out anyway;
  - Visual Trace shows the DecisionResponse with an empty Confidence;
  - no channel text names a confidence.
- **What does not change:**
  - no routing reads the confidence (round-2 C5 report): a diagnosis is always act, and the incident is noticed either way;
  - accepting a diagnosis that lacks only its confidence gives the incident a cause and, where valid, an approval-gated fix offer, in place of a fallback incident. It never lowers attention;
  - the eval scorer reads no confidence;
  - C0 saw no diagnose `confidence-missing`, so the expected change in the eval numbers is none.
- **Decide** is untouched: `CONFIDENCEREQUIRED` 1, the same refusal, the same tellnow fallback. Its question rides the post-cut Triage A/B. Nothing here is model-facing.

**AD-8.** "Content that doesn't validate is unusable" still holds. Which content validates is the reply class's own rule, and DiagnosisPayload now accepts an absent confidence. The spine sentence that both payloads "carry ... a confidence" becomes inaccurate for a diagnosis, hence Veto item 4.

**Ledger inbox:** DW-1421 round 3 (cut floor, C1 for seven fields, C5 diagnose). Status line through `ledger.sh append` at merge, per the run's DW process. Decide's missing confidence is carried to the post-cut Triage A/B (no new DW unless the Planner wants one).

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | None. No catalog key, sentence or UI string is added or changed. "No Confidence line" is the existing strip rule for an absent confidence (`decision-strip.ts` L237), now reached by a diagnosis without one, so it is a removed number, not new text. Two behaviours change what a user may see, inside existing slots: (i) a cut evidence reference whose early space left fewer than 64 characters now shows 127 characters of the model's reference plus U+2026 in `summary.evidence` (in place of a short head plus U+2026); (ii) an incident whose diagnosis lacked only its confidence shows the cause and fix sentences of an accepted diagnosis, in place of the fallback notice. The refusal warnings are internal (the event log, Recheck, the capture), not public. | Approve: no new text. |
| 2 | (b) Cross-lane edits | Lane A: `Bridge/Msg/DecisionPayload.cls`, `Watch/Msg/DiagnosisPayload.cls` and the tests `Test/Watch/Payload.cls`, `Test/Eval/Capture.cls`, `Test/Bridge/ReplyCheck.cls` (doc), `Test/Bridge/ProbeReplyCheck.cls`. Lane B: `web/src/app/chat/decision-view.ts`, `web/src/app/chat/decision-strip.ts` (a behaviour-preserving extraction of the strip's line-1 items into `stripMeta`, so the ruled pin can be a node test), `web/scripts/decision-view.test.mjs`, `web/scripts/incident-view.test.mjs`. `Decide.cls` only if Task 0 item 1 says so. Lane C makes every edit under the Planner's round-3 ruling. At plan time none of the 28 unmerged `OCT-*` branches touches any of these files (each against `feature/OCT_OcuTalon_MVP`). | Grant, Lane A and Lane B. |
| 3 | (c) Stored data or schema | No class storage, column or table changes. A non-fallback diagnosis Decision row may now hold Confidence "" (until now only fallback rows did), and its Payload JSON then has no `confidence` key. The DecisionResponse copies "". Readers: Live.Payload.Decision omits the key (Task 0 item 3); History lists decide rows only and omits "" anyway; IncidentManager, Eval.Sink and Watch.Summary read no confidence. REFUSALRULES and the two new parameters are class parameters, not stored. No migration. | Approve, with no migration. |
| 4 | (d) Architecture change | One sentence of ARCHITECTURE-SPINE L271 becomes inaccurate: both payloads "carry ... a confidence between 0 and 1, which the incident card and Visual Trace show for a diagnosis too". The amendment, old and new verbatim, is under "Spine text". AD-8, AD-2 and AD-26 hold unchanged: Decide is not changed, `invalid` is still JSON that fails the reply class's validation, and Confidence stays an AD-26 field that may be empty. EXPERIENCE.md L293 ("A fallback decision omits confidence, because fixed rules chose it") needs no change: a decision with none has nothing to show. | Approve the L271 amendment. |
| 5 | (e) Product behaviour change | (i) Cut floor: an evidence reference over 128 whose last space at or before 128 leaves fewer than 64 characters is cut mid-word, 127 characters plus U+2026. Before, it was the short head plus U+2026. Every other cut is byte-identical. (ii) Length refusals: for all eight limited fields, the warning, Recheck's problem and the capture's rule read "ERROR #7201 rule <field>-too-long" in place of "<Property>[ element <n>]: <length> > <limit>". For outcome and reasons this includes triage (DecisionPayload) refusals. (iii) A diagnosis whose only fault is a missing confidence is accepted (cause, fix offer if valid, no confidence shown) where it fell back `invalid`. A diagnosis with a confidence and every triage decision are unchanged, and triage still refuses a missing confidence. | Approve. |
| 6 | Design beyond the ruling | (i) The outcome and reasons tags live in DecisionPayload (the parent), so that triage refusals and the capture's decide counts carry no number too; DiagnosisPayload repeats the parent's list first. (ii) `ProbeReplyCheck` (test only) lists the parent's rules without length tags, so ReplyCheck keeps pinning Decide's generic numeric form for a class that lists none. (iii) C5 is a generic bridge parameter `CONFIDENCEREQUIRED` (1 by default) read with `$Parameter($this, ...)`, not an override that swallows the parent's error. (iv) The web's strip line-1 items move into a pure `stripMeta` (Lane B, no visible change) so that "no Confidence line" is pinned by a node test. (v) `TestEveryRuleTagged` also pins that every limited top-level field of each class has exactly one length tag, and that no tag holds a digit. (vi) The number cases outside the length refusals (the Confidence range form, element positions, error codes, "; and k more") are not changed. Option R is specified but not built. | Approve (i) to (v); rule (vi) (PLANNER REPORT). RULED ~17:45Z Nov 16: (i)-(v) approved; Q1 Option R YES; Q2, Q3 unchanged. |

## Spine text

ARCHITECTURE-SPINE.md L271, the sentence in the bullet that begins "`OcuTalon.Agent.Input` is the one renderer".
- Old: "Triage and Diagnosis answer with one JSON object, checked against the `%JSON.Adaptor` class named in the runner's `ReplyClass` setting (`OcuTalon.Bridge.Msg.DecisionPayload`, `OcuTalon.Watch.Msg.DiagnosisPayload`; both carry plain-English reasons and a confidence between 0 and 1, which the incident card and Visual Trace show for a diagnosis too)."
- New: "Triage and Diagnosis answer with one JSON object, checked against the `%JSON.Adaptor` class named in the runner's `ReplyClass` setting (`OcuTalon.Bridge.Msg.DecisionPayload`, `OcuTalon.Watch.Msg.DiagnosisPayload`; both carry plain-English reasons and a confidence between 0 and 1, which the incident card and Visual Trace show for a diagnosis too; a diagnosis may leave its confidence out (`CONFIDENCEREQUIRED` is 0 in `DiagnosisPayload`), and its decision then stores none and the incident card shows none, never 0, while a triage reply without one is still invalid)."
- Marker, at the end of the bullet: "[AMENDED 2026-11-16, DW-1421 round 3 (C5), Contest Planner ruling ~17:15Z Nov 16: it read "both carry plain-English reasons and a confidence between 0 and 1, which the incident card and Visual Trace show for a diagnosis too)."]"

No other AD text changes.

## Public text

None new. No catalog key, sentence or UI string is added or changed (Veto item 1).

## Verification

Use a lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh`, `ci/warm.sh` and `eval/run.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag>`. Fresh runs leave `OCUTALON_WARM` unset.
- One test class (or `Class:Method`) per foreground call, `timeout: 600000`, each under about 3 minutes, never two test calls in one message. In a release quiet window, take the lane's warm or throwaway lock after teardown.
- No model and no key anywhere. Never read `.env`.

**Commands:**
- (once) `ci/warm.sh up` with the warm tag, then Task 0 items 1 to 3 (a scratch routine or the terminal in the warm container only, never in the tree); item 4 is a grep.
- (loop) Warm, each expected to pass: `ci/iris.sh class OcuTalon.Test.Watch.Payload`; `OcuTalon.Test.Eval.Capture`; `OcuTalon.Test.Bridge.ReplyCheck`; `OcuTalon.Test.Bridge.Decide`; `OcuTalon.Test.Agent.RememberDecision`.
- (once) Warm guards: `OcuTalon.Test.Watch.Summary`, `OcuTalon.Test.Watch.Diagnose`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Web.HistoryApi`, `OcuTalon.Test.Bridge.Contracts`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Agent.Instructions`.
- (once) Fresh: `ci/iris.sh shard lane-a@Eval` (or its classes, split), and `ci/iris.sh class OcuTalon.Test.Watch.Payload`.
- (loop, no stack) `node --test web/scripts/decision-view.test.mjs web/scripts/incident-view.test.mjs`; then once `node --test web/scripts/`, `npm --prefix web run lint` and `npm --prefix web run build` (the build output is git-ignored).
- (once) `EVAL_SET_ONLY="capture eval-scripts" bash docker/tests/test-eval-set.sh` (guard only; no shell file changes); `bash docker/tests/test-bridge-guide.sh`; `bash docker/tests/test-boundaries.sh`; `bash docker/tests/test-class-rules.sh`: one per call, each exits 0.
- (once, if the spine is amended) the spine lint (`.claude/skills/bmad-architecture/scripts/lint_spine.py` on the spine) reports only its baseline findings.
- (once) `git diff --name-only 0575abeba` lists only the footprint files; no added line holds a non-ASCII character or an absolute local path.
- (once, at the end, also after a failure) `ci/warm.sh down` with the warm tag; `ci/iris.sh teardown` for the fresh tag.

**Mutations (Rule 19).** One `mutation: <change> -> <test that went red>` line each. Revert each byte for byte (`cmp` against a copy taken before it), and check that `git status --short` and `git diff --stat` are as before. The planned mutations:
- Cut floor:
  - the floor test back to round 2's blank test (`$ZStrip(head, "*W") = ""`) -> `TestEvidenceCut` rows 16, 18 and 19 red;
  - `< ..#EVIDENCEFLOOR` made `'> ..#EVIDENCEFLOOR` (64 cut mid-word) -> row 17 red;
  - `EVIDENCEFLOOR` made 63 -> row 18 red (and the parameter assertion);
  - the floor measured before the trailing strip (`$Length($Extract(text, 1, position - 1))`) -> row 19 red;
  - the floor test removed entirely (`If 0 {`) -> rows 6, 16, 18 and 19 red (a blank head gives U+2026 alone).
- C1:
  - the five new DiagnosisPayload pairs removed -> `TestLengthTags` rows L3-L7 and L10, `TestEveryRuleTagged` (a limited field with no tag) and `TestRuleTags` (30) red;
  - the two parent pairs moved out of DecisionPayload into DiagnosisPayload only -> `TestLengthTags` row L9 and `TestEveryRuleTagged` (the parent's limited fields; the list starts with the parent's) red;
  - `cause-too-long:cause` and `fix-summary-too-long:fixSummary` swapped to `cause-too-long:fixSummary,fix-summary-too-long:cause` -> `TestLengthTags` rows L6, L7 and L10 red;
  - a tag renamed with a digit (`fix-kind-too-long` to `fix-kind-too-long2`, also in the test's expectations) -> `TestEveryRuleTagged` (no digit) red;
  - `ProbeReplyCheck`'s REFUSALRULES override removed -> `Test.Bridge.ReplyCheck` rows 2 and 6 and form a red;
  - `Decide.LengthTag` returns "" -> `TestLengthTags` (every row) red.
- C5:
  - DiagnosisPayload `CONFIDENCEREQUIRED = 1` -> `TestConfidenceAbsent` (C1, C2), `TestRuleTags` (confidence-missing accepted) and `Test.Eval.Capture` `TestOneReplyPerRule` red;
  - the guard reads the parent's value (`$Parameter("OcuTalon.Bridge.Msg.DecisionPayload", "CONFIDENCEREQUIRED")`) -> `TestConfidenceAbsent` C1 red;
  - DecisionPayload `CONFIDENCEREQUIRED = 0` -> `TestConfidenceAbsent` (the decide row), `Test.Bridge.Decide` "no confidence" and `Test.Agent.RememberDecision` red;
  - `Judge` L1747 made `Set confidence = +payload.Confidence` (0 for "") -> `TestConfidenceAbsent` C2 (row Confidence) red;
  - `Live/Payload/Decision.cls` `Confidence` given `%JSONNULL = 1` (exports null) -> `TestConfidenceAbsent` C2 (live payload key) red;
  - `stripMeta`'s `confidence !== undefined` removed -> `decision-view.test.mjs` (stripMeta, absent) and `incident-view.test.mjs` (the diagnosis strip) red;
  - `decision-strip.ts` `meta` back to its own inline body -> the source assertion of `decision-view.test.mjs` red.

**Results (implementation, lane-C warm throwaway tag e1421r3i, no model, no key):**

Task 0 (no stop rule fired):
- Item 1: `$Number("", 2)` is "" (length 0). `Judge` is unchanged and `Decide.cls` joins the footprint only for Option R.
- Item 2: `DiagnosisPayload.%JSONImport` of a reply with `"confidence": null` gives status OK and `Confidence` "" (length 0). Row C3 therefore expects acceptance with the confidence absent (pinned in `TestConfidenceAbsent`).
- Item 3: `%JSONExportToString` of a DiagnosisPayload with Confidence "" is `{"outcome":"act"}` (no `confidence` key); of `Live.Payload.Decision.FromRow` for a row with Confidence "" it has no `confidence` key (`%GetTypeOf` "unassigned").
- Item 4: no test, stub or eval script expects a diagnose reply without a confidence to fall back. The only hits are `Test.Watch.Payload` `RuleReply("confidence-missing")` (used by `TestRuleTags`, now asserted accepted) and the `Test.Eval.Capture` `SeedAll` loop (it skips `confidence-missing` and seeds one passing diagnose reply); the decide-side pins (`Test.Bridge.Decide` L653, `Test.Agent.RememberDecision`, ReplyCheck row k, the triage seed) stay.

Warm tests (all passed; methods/asserts): `Test.Watch.Payload` 16/777; `Test.Eval.Capture` 12/589; `Test.Bridge.ReplyCheck` 7/191; `Test.Bridge.Decide` 76/3055; `Test.Agent.RememberDecision` 4/56; guards `Test.Watch.Summary` 34/600, `Test.Watch.Diagnose` 5/172, `Test.Live.Payloads` 24/787, `Test.Web.HistoryApi` 7/301, `Test.Bridge.Contracts` 5/92, `Test.Bridge.CodeRules` 19/459, `Test.Agent.Instructions` 8/287. Fresh (tag e1421r3f): `Test.Watch.Payload` passed; `shard lane-a@Eval` passed (24 classes, 354 s).

Node: `node --test web/scripts/decision-view.test.mjs web/scripts/incident-view.test.mjs` 123/123; `npm test` 2202/2202; `npm run lint` and `npm run build` pass. Shell guards: `test-boundaries.sh`, `test-bridge-guide.sh`, `test-class-rules.sh`, `test-eval-set.sh` (capture, eval-scripts) all rules passed. Spine lint: 13 low findings (the baseline, all placeholders).

Changed pins: `TestRefusalTrace` (element-at-fault-too-long), `TestEvidenceCut` row 9, `TestEvidenceTooLongTag` (elementAtFault), `TestRuleTags`, `TestEveryRuleTagged`, `Test.Eval.Capture` (the loop skips confidence-missing, one passing no-confidence diagnose seed, the elementAtFault seed, `TestRuleNames` one more part, "passes the check" 4).

Mutations (each reverted byte for byte, cmp identical):
- mutation: floor test back to `$ZStrip(head, "*W") = ""` -> TestEvidenceCut rows 16, 18, 19 red
- mutation: `'> ..#EVIDENCEFLOOR` -> TestEvidenceCut row 17 red
- mutation: EVIDENCEFLOOR 63 -> TestEvidenceCut the parameter assertion, rows 18 and 19 red
- mutation: floor measured before the trailing strip -> TestEvidenceCut row 19 red
- mutation: `If 0 {` in Cut -> TestEvidenceCut (rows 2, 5, 6, 7, 8, 14, 16, 18, 19) and TestEvidenceCutRecorded red
- mutation: the five DiagnosisPayload pairs removed -> TestEveryRuleTagged, TestEvidenceCut, TestEvidenceTooLongTag, TestLengthTags, TestRefusalTrace, TestRuleTags red
- mutation: the parent's two length pairs removed from DecisionPayload -> TestLengthTags (L9) and TestEveryRuleTagged red
- mutation: cause and fix-summary pairs swapped -> TestLengthTags and TestRuleTags red
- mutation: `fix-kind-too-long2` -> TestEveryRuleTagged, TestLengthTags, TestRuleTags red
- mutation: ProbeReplyCheck REFUSALRULES override removed -> Test.Bridge.ReplyCheck TestRefusalNamesTheLimitNotTheReply and TestRefusalTextForms red
- mutation: `LengthTag` never matches (`If 0 &&`) -> TestLengthTags, TestRangeTag, TestEvidenceCut, TestEvidenceTooLongTag, TestRefusalTrace red
- mutation: RefusalPart's range branch dropped (Option R) -> TestRangeTag red
- mutation: DiagnosisPayload CONFIDENCEREQUIRED 1 -> TestConfidenceAbsent and TestRuleTags red (Payload); TestOneReplyPerRule red (Capture)
- mutation: the guard reads the parent's value -> TestConfidenceAbsent and TestRuleTags red
- mutation: DecisionPayload CONFIDENCEREQUIRED 0 -> TestConfidenceAbsent (the decide row), Test.Bridge.Decide TestReplyCheck ("no confidence") and Test.Agent.RememberDecision TestProbeShapeIsTheDemoWarning red
- mutation: Judge `Set confidence = +payload.Confidence` -> TestConfidenceAbsent red
- mutation: Live.Payload.Decision Confidence with %JSONNULL = 1 -> TestConfidenceAbsent red
- mutation: stripMeta without `confidence !== undefined` -> decision-view.test.mjs (stripMeta) and incident-view.test.mjs (the diagnosis strip) red
- mutation: decision-strip.ts `meta` back to an inline body -> the source assertion of decision-view.test.mjs red
All planned mutations were run.
Review mutations (QA + code review round 3, lane-C warm throwaway tag e1421r3q; each reverted byte for byte, cmp identical, `git status --short` and `git diff --stat` as before):
- mutation: Judge `Set confidence = $Select(+payload.Confidence: $Number(payload.Confidence, 2), 1: "")` (a confidence of 0 taken for absent) -> TestConfidenceAbsent red (C4: the row's and the answer's confidence, the live payload's type and value)
- mutation: `confidence-out-of-range:confidence` removed from DecisionPayload.REFUSALRULES only -> TestEveryRuleTagged (the parent's one range tag) and TestRangeTag (both decide rows) red

Model-prompt check (Planner's one check): NO. A refusal or rule string reaches only the event-log warning (`Decide.cls` Conclude logs the problem with `$$$LOGWARNING`, redacted) and the `problem` that `Decide.Recheck` returns; nothing outside `Decide.cls` and the test classes (the capture harness `Test.Eval.CaptureTool`) calls `Recheck` or `RefusalText`. The second-model retry (`TryRetry`) sends a clone of the request, never the problem text, and no agent, tool or retry turn reads RefusalText.

**Size:** small to medium.
- Product: DecisionPayload +6 lines (parameter, guard, pairs, docs); DiagnosisPayload +8 (two parameters, one line of `Cut`, the list, docs); ProbeReplyCheck +3.
- Web: `decision-view.ts` +15; `decision-strip.ts` -10 / +3.
- Tests: Payload +140 (`TestLengthTags`, `TestConfidenceAbsent`, four cut rows, `LengthTags()`, six changed pins); Capture +15 (one seed, three changed pins); node tests +40.
- Spine: one sentence.
- One implementation pass, no shell change, no model run. No Decide change unless Task 0 item 1.

## Auto Run Result

Status: in-review (implemented; review not run by this stage)
Blocking condition: none

- Summary: the cut floor (EVIDENCEFLOOR 64, measured after the trailing strip), eight length tags and the confidence range tag with no digit (Option R, `Decide.LengthTag` takes a suffix and `RefusalPart` has one branch), and C5 for diagnose (CONFIDENCEREQUIRED 0: accepted, stored "", no key, no Confidence line via the pure `stripMeta`), with decide's refusal kept. The spine L271 amendment is made verbatim with its marker.
- Files: see Boundaries, "Footprint"; `Decide.cls` changed for Option R only (Task 0 item 1 did not require the Judge line).
- Verification: see `## Verification`, "Results".
- Follow-up review recommendation: false.
- Deviations: none from the spec.

## Review (QA + code review, round 3)

Combined QA and code-review stage over `f783b3829..09670b2a0`: four review layers (Blind Hunter, Edge Case Hunter, Verification Gap, Acceptance Auditor) and a QA pass against AC 1 to AC 8. Every binding point checked holds:
- DecisionPayload lists 6 pairs and DiagnosisPayload 31; no tag holds a digit; all eight limited fields are tagged "<field>-too-long"; the range tag applies only to a class that lists it; ProbeReplyCheck keeps the generic forms.
- The floor (EVIDENCEFLOOR 64) is measured after the trailing strip, and the surrogate guard is unchanged. Rows F1 to F4 match the matrix.
- C5 reads `$Parameter($this, ...)`. A diagnosis without a confidence stores "", with no key in the payload or the live payload, and decide still refuses one. `stripMeta` keeps the strip's behaviour.
- The spine L271 amendment and its marker match "Spine text" verbatim.
- Decide changed only in LengthTag's suffix, RefusalPart's range branch and one doc line.

Rule 3: the server half runs on IRIS (the stored row, the payload and `Live.Payload.Decision`'s serializer). The strip's wiring is pinned in a browser by `web/e2e/chat/decision.spec.ts` (confidence shown, none on a fallback). The web change is a pure extraction pinned by node.

### Review Findings

- [x] [Review][Patch] MED: TestConfidenceAbsent ran a check (C6) after Decide.Conclude had ended the test's ReplyCheck, against the class's own contract, and set no `..Mark`, so a red run left Conclude's warnings behind. Fix: C6 moved before the conclusions, and `..Mark` set first [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls TestConfidenceAbsent]
- [x] [Review][Patch] LOW: the class doc says a null confidence is "stored with none", but the test only checked it. Fix: `AssertStored("C3, a null confidence", nulled, "")` [Payload.cls TestConfidenceAbsent]
- [x] [Review][Patch] LOW: C4 checked only the type of the stored payload's confidence. Fix: AssertStored also checks the stored value [Payload.cls AssertStored]
- [x] [Review][Patch] LOW: `{}.%FromJSON(row.Payload)` threw on an empty payload after the assertion failed. Fix: the guard also quits on an empty payload [Payload.cls AssertStored]
- [x] [Review][Patch] LOW: the DecisionPayload REFUSALRULES doc did not state Option R's range-tag rule. Fix: "A tag that ends in -out-of-range is the range tag of a field with a MINVAL or MAXVAL, which no rule raises." [src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls REFUSALRULES doc]
- [x] [Review][Patch] LOW: the decision-strip docs did not name a decision without a confidence or `stripMeta`. Fix: comments only [web/src/app/chat/decision-strip.ts class doc, `meta`]
- [x] [Review][Patch] LOW (Rule 19): C4 and the DecisionPayload range pair had no `mutation:` line. Both were run and recorded under Verification.
- [ ] [Review][Needs ruling] MED, escalated to the Planner, out of footprint: the model-prompt check is a conditional, indirect YES, not NO.
  - Decide.Conclude logs the refusal as a Type 3 warning in its session (`Decide.cls` L1516).
  - Watch.Reader reads every Ens_Util.Log row of a failed message's session, text included (`Watch/Reader.cls` L919, L966-991).
  - The diagnosis tool `read_event_log` returns those rows' text to the model, redacted only for secrets (`Watch/EvidencePack.cls` L373-397, L214-217; `Tools/Watch.cls` L15). `PushMessages` falls back to event-log rows when a snapshot has no failures (L364-368).
  - `Reader.Productions` (L119-138) leaves out OcuTalon's own production only on the online demo.
  - So when OcuTalon watches its own production and a failure shares a session with a refused reply, the rule string ("ERROR #7201 rule <tag>", or a numeric form for a class with no tag) can reach the Diagnosis agent in a tool result.
  - The rule strings hold no reply value. The path is the same before and after this round. Per the Planner's ruling, the merge waits for a Planner ruling on this YES. Nothing is patched: the fix would be outside the footprint (Watch or EvidencePack).
- [ ] [Review][Needs ruling] LOW, optional public text: `docs/bridge-guide.md` names neither CONFIDENCEREQUIRED nor the REFUSALRULES tag forms. Its DecisionResponse table says Confidence is "0 to 1", with no note that an accepted diagnose response may have none. The bridge default (CONFIDENCEREQUIRED 1) keeps the guide true for a bridge user's class. Docs are public text outside the footprint.

Rejected:
- The spec text still describes the plan before Option R (matrix row C5, Veto item 6 (vi), the audit row, Size, "Deviations: none"). The fix would edit the spec under review. The Planner's ruling (Task "Option R") supersedes row C5, which now expects "ERROR #7203 rule confidence-out-of-range". The implementation follows the ruling.
- Decide's RefusalTag and LengthTag patterns still allow a digit: by-design, per Design Notes "No digits" (they are filters against reply values; the lists are pinned).
- LengthTag now also resolves range tags under its old name: by-design (Task "Option R": "LengthTag takes a suffix argument").
- Nested limited fields (fixParameters.*, itemNoun.*) carry no tag: by-design (the number audit, "not among the seven").
- `confidenceText(undefined)` gives "Confidence 0.00": wontfix-theoretical. Every caller guards it. It would become real with a new caller that skips the guard (Design Notes C5).
- The limited-field check skips a property with no `%JSONFIELDNAME`: wontfix-theoretical. Every property of both classes declares one. It would become real with a limited property that has none.
- `notice-card.ts` and the server property docs ("0 to 1") do not mention an absent confidence: `notice-card.ts` is a never-change file, and the property docs stay true (fallback rows were already empty).
- Capture L229 keeps `= 1`, and the new seed adds `+ 1`: equivalent, since the count is 4 either way.
- Weak assertions that are redundant but harmless: AssertTag's digit check after an exact equality; the fixture checks in `incident-view.test.mjs`; the `kind: 'diagnose'` that `decisionOf` ignores; the source assertion (structural, as AC 8 asks).

Reruns (warm, tag e1421r3q, all passed; methods/asserts): `Test.Watch.Payload` 16/786; `Test.Eval.Capture` 12/589; `Test.Bridge.ReplyCheck` 7/191; `Test.Bridge.Decide` 76/3055. Node: `npm test` 2202/2202; `npm run lint` passes. `test-boundaries.sh`: all rules passed. Spine lint: 13 low (the baseline). The warm stack is torn down.

Status: done. No open HIGH or MED in the code. The escalated model-prompt YES holds the merge, as the Planner's ruling says.

