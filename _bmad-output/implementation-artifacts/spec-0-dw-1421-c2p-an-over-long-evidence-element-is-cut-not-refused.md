---
title: "DW-1421 C2' + C1 fix: an over-long evidence element is cut, not refused, and its remaining length refusal has a fixed tag (with the C5 confidence report)"
type: 'feature'
created: '2026-11-16'
status: 'done'
baseline_revision: '08f55bc99a2736acdbe5febb3ea180b215b4aaa0'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-0-dw-1421-diagnosis-refusals-name-their-rule-and-a-capture-harness.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-12-a-correct-diagnosis-is-never-refused-for-an-over-long-eviden.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1421 round 2; Contest Planner "DW-1421 C0 RESULTS and rulings", ~18:30Z Nov 16, BINDING):**
- C0 measured 5 runs on Haiku 5.5. Diagnose fell back 3 times on `orders-target-to-review`, every time on "Evidence element 1: N > 128" (N = 129, 137, 144): the model quoted the pack's settingChanges line, and the replies were otherwise correct. Decide fell back twice on `confidence-missing`. C2 and C3 never occurred.
- Rulings: C2 DROPPED, C3 DEFERRED. NEW C2' (not model-facing): in the DiagnosisPayload check, an evidence element over 128 characters is CUT to 128 at the last word boundary, ending in U+2026, instead of refusing the reply; each cut is recorded as a COUNT only; the cap on the NUMBER of elements (20) stays a refusal. C1 fix: "Evidence element N: X > Y" carries numbers, so it gets the FIXED tag `evidence-too-long`; check that no other rule string carries values. C5: report first (below, "C5 report"), build nothing.
- Where the refusal comes from (read from the code, baseline `ea4475096`): not `%OnValidateObject`. `Decide.CheckReply` (`Decide.cls:1023`) calls `%JSONImport`, whose generated import calls each literal's `IsValid` (`irislib/%JSON/Generator.cls:931-939`), so the `MAXLEN = 128` of `DiagnosisPayload.Evidence` (`DiagnosisPayload.cls:50`) fails the import with #9406 on `evidence`. `RefusalText` then traces the field (`RefusalImport`, `Decide.cls:1167-1217`) and checks each element with `EvidenceIsValid` (`RefusalCheck`, L1220-1229), and `RefusalPart` writes the #7201 as "Evidence element <n>: <length> > 128" (L1152).

**Approach:**
- **C2', the cut (Lane A, `Watch/Msg/DiagnosisPayload.cls` only):** the class overrides `%JSONImport`. Before the inherited import runs, every string element of the reply's `evidence` array that is longer than 128 characters is cut (rule below). The property keeps `MAXLEN = 128`, so validation still guards every path; no other field is touched. The number of cut elements goes into a new output-only property `EvidenceCut` (JSON `evidenceCut`), which Decide's existing export writes into the Decision row's Payload JSON only when it is not empty. Nothing is logged.
- **C1 fix (Lane A, `Bridge/Process/Decide.cls` and `REFUSALRULES`):** DiagnosisPayload's allowlist `REFUSALRULES` gains the pair `evidence-too-long:evidence`. `RefusalPart` writes a #7201 on a property as "ERROR #7201 rule <tag>" when the reply class lists a tag that ends in `-too-long` for that property's JSON field, with no position, length or limit. With the cut in place this remains reachable only when a reply filter lengthens a text (a custom `ReplyFilterClass`; the shipped `ReplyGuard` only deletes).
- **The capture harness (Lane A, `Test/Eval/CaptureTool.cls`):** `RuleOf` takes the tag of any "ERROR #<code> rule <tag>" part, not only #5001, so the harness counts the new form under `evidence-too-long`, field `evidence`.

## Boundaries & Constraints

**Always:**
- **Footprint.** All files are Lane A (Veto item 2). Lane C makes the edits under the Planner's DW-1421 round-2 ruling:
  - `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`: the `%JSONImport` override, the private cut helper, the property `EvidenceCut`, the pair `evidence-too-long:evidence` at the end of `REFUSALRULES`, the class doc (L1-19), the `Evidence` property doc (L49).
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `RefusalPart` (one new argument, one branch), a new private `LengthTag`, the two `RefusalPart` call sites (L1077, L1226), the `RefusalText` doc (L1036-1051).
  - `src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls`: `RuleOf` (and its doc and the class doc L8-10); `RuleOf` and `FieldOf` become public `[ Internal ]` so the test can pin them.
  - Tests: `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls`, `src/ocutalon/cls/OcuTalon/Test/Eval/Capture.cls`.
  - This spec.
- The cut applies to `evidence` only, to string elements only, and never changes an element of 128 characters or fewer (byte for byte). The order and the number of elements are unchanged.
- The cut result is at most 128 characters, the U+2026 included (Design Notes, "The cut").
- The cut is recorded as a count only: `EvidenceCut` (an integer, the number of elements cut, empty when none). No text of an element, cut or kept, goes into a log, a trace row, a warning, a Decision column other than Payload's own `evidence`, or the harness stdout.
- `DiagnosisPayload.Evidence` keeps `MAXLEN = 128`, and `MAXEVIDENCE = 20` stays a refusal (`evidence-over-max`).
- A payload with no cut is exported byte for byte as before (no `evidenceCut` key).
- A reply that itself carries a field `evidenceCut` is refused as an unexpected property (#9404), exactly as before this change.
- `RefusalText`'s contract stands: a tag is shown only when the reply class lists it; never a reply value. The C1 rule "PIN, with a mutation, that a reply value can NEVER appear after 'rule'" covers the new form too.
- Every refused reply still falls back with reason `invalid`. Every other fallback reason is unchanged.
- ObjectScript stays ASCII (`docker/tests/test-boundaries.sh` L4, L34, L213): the ellipsis is written `$Char(8230)`. Comments state the contract, not review history. No absolute local path in any file.
- Every existing test passes, with only the pins listed under Tasks changed.

**Never:**
- Change any model-facing text: an INSTRUCTIONS block, a pack, a tool description (the Diagnosis prompt's lengths sentence, `Agent/Diagnosis.cls:41`, stays as it is; Design Notes).
- Change `DecisionPayload`, the triage path, any other field's length rule, `MAXEVIDENCE`, `Decide.CheckReply`, `Judge`, `Interpret`, `Conclude` or `Recheck`.
- Log, `$$$TRACE` or write anywhere the text of an evidence element, or log the count (Recheck must stay silent, and the payload class runs outside a host).
- Add a column, a table, a catalog key or a setting.
- Delete, skip or weaken a test beyond the pins this spec changes.

## I/O & Edge-Case Matrix

"Cut(e)" is the rule of Design Notes. "Accepted" means `CheckReply` OK and, through `Conclude`, Fallback 0.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 At the limit | one element of exactly 128 characters | Accepted; element unchanged byte for byte; `EvidenceCut` empty; no `evidenceCut` key in Payload | none |
| 2 One over | 129 characters, no space | Accepted; element = first 127 characters + U+2026 (128); `EvidenceCut` 1 | none |
| 3 Space at 128 | 127 letters, a space, one letter | Accepted; element = the 127 letters + U+2026 | none |
| 4 300, words | 300 characters of words and single spaces | Accepted; element = the text up to the last space at position 2..128, trailing white space removed, + U+2026; the original's next character is a space | none |
| 5 No boundary | one word longer than 128 (300 characters) | Accepted; first 127 characters + U+2026 | none |
| 6 Blank head | three spaces then 200 letters | Accepted; first 127 characters + U+2026 (the word-boundary head would be blank) | none |
| 7 Split pair | 126 letters, a surrogate pair, more letters | Accepted; 126 letters + U+2026 (the pair is never split) | only if Task 0 item 2 finds a pair counts 2 |
| 8 Several | three elements: 129, "h3", 200 | Accepted; the two long ones cut, "h3" unchanged, order kept; `EvidenceCut` 2; Payload `"evidenceCut":2` | none |
| 9 Other fields | elementAtFault of 129; a reason of 1001 | Refused as today: "ElementAtFault: 129 > 128", "Reasons element 1: 1001 > 1000" | fallback invalid |
| 10 Count cap | 21 elements, one of them 200 | Refused "ERROR #5001 rule evidence-over-max" | fallback invalid |
| 11 At the cap | 20 elements, one of them 200 | Accepted, `EvidenceCut` 1 | none |
| 12 Not a string | `"evidence": [12345]`, or an object element | Refused as today (#9406 "ERROR #9406 on Evidence" / "... element 1") | fallback invalid |
| 13 Model sends the count | a reply with `"evidenceCut": 3` | Refused "ERROR #9404: an unexpected property" | fallback invalid |
| 14 Object input | `%JSONImport` given a dynamic object with a long element | the payload is cut; the caller's object is unchanged | none |
| 15 Not JSON | text that does not parse | the same status as before (the inherited import's) | fallback invalid |
| 16 Filter lengthens | an element of 128 that a reply filter makes 132 (test filter `ProbeFilter`) | "After the reply filter ran: ...DiagnosisPayload refused the filtered payload: ERROR #7201 rule evidence-too-long" | fallback invalid |
| 17 Recheck of a cut reply | `Decide.Recheck` of row 8's text | 1, problem ""; no row, no log, no message | none |
| 18 Capture | a capture part "ERROR #7201 rule evidence-too-long" | rule `evidence-too-long`, field `evidence` | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `ea4475096`.

- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - class doc L1-19 (the evidence bullet L4; the REFUSALRULES sentence L18-19);
  - `REFUSALRULES` L36-38; `MAXEVIDENCE` L40-41;
  - `Evidence` L49-50: `list Of %String(%JSONFIELDNAME = "evidence", MAXLEN = 128)`;
  - `%OnValidateObject` L68-105: `##super()` L70, `evidence-over-max` L76;
  - `Blank` L142-145.
- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`: `REFUSALRULES` L9-11, `Confidence` L19-20, `%OnValidateObject` L24-37 (`confidence-missing` L35). Not changed.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `CheckReply` L1017-1034 (`%JSONImport` L1023, `%ValidateObject` L1024). Not changed;
  - `RefusalText` doc L1036-1051, body L1052-1094 (the non-#9406 part L1077-1080; the #5001 tag L1078);
  - `RefusalTag` L1102-1108 (the allowlist); `RefusalProperty` L1121-1138;
  - `RefusalPart` L1146-1164 (#7201/#7202 L1152, #7203/#7204 L1153);
  - `RefusalImport` L1167-1217; `RefusalCheck` L1220-1229 (its `RefusalPart` call L1226);
  - `Judge` L1665-1724: filter loop L1689-1707, the second validation L1708-1714, `confidence` L1721, export L1722. Not changed.
- `irislib/%JSON/Adaptor.cls` `%JSONImport` L71-92 (a plain method: parses a string or takes a dynamic object, then `%JSONImportInternal`); `irislib/%JSON/Generator.cls`: import calls `IsValid` per literal L931-939; every mapped field name, an output-only one included, is put in `proplist` before the include check (L605-615), so an output-only field in the input is ignored silently, not refused (hence the guard of row 13). `irislib/%Library/RegisteredObject.cls` L945-946: `%ValidateObject` calls `%OnValidateObject` first, then validates the properties.
- `src/ocutalon/cls/OcuTalon/Checks/ReplyGuard.cls` L1-13: the shipped filter only deletes phrases ("never adds or rewrites a word"). `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeFilter.cls` L8-15 prefixes "[f] " (lengthens by 4).
- `src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls`: class doc L8-12; `Parse` L228-258; `RuleOf` L260-265 (only "ERROR #5001 rule "); `FieldOf` L267-279.
- Precedents for the cut: `Watch/ErrorText.cls` `Summary` L64-90 (last space within max - 1, else a hard cut, then `$Char(8230)`, total at most max); `Memory/Learned.cls` `Fact` L32-41 (never splits a surrogate pair); `Core/Conversation.cls` L484, L944; `Bridge/Adapter/StepBuffer.cls` L275.
- Where the diagnosis evidence is shown (Veto item 1):
  - `Watch/Summary.cls` `Evidence` L288-309 (first evidence line that is more than a period) gives slot `summary.evidence`, `Msg/Catalog/Watch.cls` L762-766 ("Evidence: {evidence}.", slot type sentence);
  - `Msg/Catalog.cls` L191-200: a sentence slot that ends in U+2026 gets no period after it (L199);
  - the summary is sent by `Channel/Telegram/Out.cls` L212, `Channel/SimPhone/Out.cls` L79, `Channel/WebChat/Out.cls` L88, and read by `Web/History.cls` L161 and `Tools/RecentActivity.cls` L121 (the chat model reads it);
  - the incident card's evidence (`Live/Payload/Incident.cls` L158-179) is the failure groups, not the diagnosis evidence.
- Readers of the Decision Payload JSON (each picks keys by name, none rejects an extra key): `Watch/IncidentManager.cls` L803-815, `Eval/Sink.cls` L112-127, `Watch/Summary.cls` L296. `Decide.cls` L1886 copies it to the DecisionResponse (shown in Visual Trace).
- Tests that pin the old behaviour:
  - `Test/Watch/Payload.cls`: class doc L5-24; `TestPayloadAccepted` L126-153 (128 accepted, L150-152); `TestPayloadRefused` L155-228 (21 references L216-218, **129 refused L219-221**); `TestRefusalTrace` L314-358 (**"over the limit" L318-319, expected L339-340**); `AssertRule` L391-399; `RuleTags` L402-405; `TestRuleTags` L445-455 (**22 at L453**); `TestEveryRuleTagged` L458-488 (one `$$$ERROR` per own pair L480-486).
  - `Test/Eval/Capture.cls`: class doc L8; `SeedAll` **L250-257** (an over-long evidence element, rule "Evidence element 2: 129 > 128"); `TestRecheckIsSilent` L526-545 (**"over the limit" L529-530, verdict 0**); `TestNothingIsWrittenAnywhere` L784-796 (a 129 element; asserts writes only).
- Guards that must stay green: `Test/Watch/Payload.cls` `TestHostReplies` (payload fields equal the reply's), `Test/Bridge/ReplyCheck.cls` `TestRefusalTextForms` (DecisionPayload lists no `-too-long` pair, so its length forms are unchanged), `Test/Watch/Diagnose.cls`, `Test/Agent/Instructions.cls` (the prompt is unchanged), `Test/Bridge/CodeRules.cls`.

## Tasks & Acceptance

**Task 0 (measure first, lane-C throwaway, no model, no key; record under `## Verification`):**
1. On the warm stack, with a scratch subclass of DiagnosisPayload (scratchpad only, never committed) that has the output-only `%Integer` property: record that `%JSONExportToString` writes no key for it when it is "" and writes it when it is 2; and that `%JSONImport` of a text with that field succeeds and ignores it (so the guard of row 13 is needed). **Rule:** if an empty value is exported, use `%JSONINCLUDE = "OUTPUTONLY"` with `%JSONNULL = 0` on the property and measure again; if it is still exported, stop with `## Clarification Needed`.
2. Record `$Length($Char(128512))` and `$Length` of that character after a `%ToJSON`/`%FromJSON` round trip. **Rule:** 2 means the surrogate guard and row 7 are built; 1 means neither is.
3. Record the `DecomposeStatus` of `%ValidateObject` for a DiagnosisPayload object (partner_outage, valid otherwise) with one 129-character Evidence element inserted directly: the top code (expect 7201), param 2 (expect 128) and the embedded #5802 (expect "...:Evidence(1)").

**Execution:**
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - `/// The number of evidence references that %JSONImport cut to 128 characters (see the class description); empty when none was cut. Code-written, never model text; exported, never imported.`
    `Property EvidenceCut As %Integer(%JSONFIELDNAME = "evidenceCut", %JSONINCLUDE = "OUTPUTONLY", MINVAL = 1);` (no MAXVAL: the count is set before `%ValidateObject` runs, so a bound of 20 would add a second refusal part to a reply of 21 cut references, which row 10 pins as the single `evidence-over-max`);
  - `Method %JSONImport(input, %mappingName As %String = "") As %Status [ ServerOnly = 1 ]`:
    - sets `EvidenceCut` to "";
    - parses the input as the inherited method does (a dynamic object is copied with `%FromJSON(input.%ToJSON())`); when parsing throws, or the result is not a `%DynamicObject`, returns `##super(input, %mappingName)` (the same status as before; use `Return` inside Try/Catch);
    - when the object has the key `evidenceCut`, returns `$$$ERROR($$$JSONImportBadField, "evidenceCut", $Select(%mappingName = "": "class base", 1: %mappingName))` (the inherited #9404, as the generated code makes it);
    - when `evidence` is a `%DynamicArray`, replaces each element whose type is "string" and whose `$Length` is over 128 with `..Cut(element)` and counts them;
    - returns `##super(object, %mappingName)`, and on OK sets `EvidenceCut` to the count when it is over 0;
  - `ClassMethod Cut(text As %String) As %String [ Private ]`: the rule of Design Notes, with the limit as a parameter `EVIDENCEMAX = 128` (the property's MAXLEN; `TestEvidenceCut` pins that the two agree);
  - `REFUSALRULES`: append `,evidence-too-long:evidence`;
  - class doc: the evidence bullet (L4) says "each at most 128 characters: %JSONImport cuts a longer one (Cut) and counts the cuts in evidenceCut"; one sentence that `evidence-too-long` is the length tag that Decide shows for an Evidence element over 128 after the filter, and that a reply carrying `evidenceCut` is refused.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `RefusalPart(code, value, limit, property, position, replyClass As %String = "")`: before the #7201/#7202 forms, `If (code = 7201) && (property '= "") { Set tag = ..LengthTag(replyClass, property) If tag '= "" Quit "ERROR #7201 rule "_tag }`;
  - both callers pass `replyClass` (L1077, L1226);
  - new `ClassMethod LengthTag(replyClass As %String, property As %String) As %String [ Private ]`: the JSON field of the compiled property (`%JSONFIELDNAME`, else its name); the tag of the first pair of `$Parameter(replyClass, "REFUSALRULES")` whose field is that and whose tag ends in `-too-long` and matches `?1L.(1L,1N,1"-")`; else "". Doc: "The length tag of the property: a tag that REFUSALRULES of replyClass lists for the property's JSON field and that ends in -too-long; never a value of the reply";
  - `RefusalText` doc: a new bullet before the #7201 forms: "a #7201 on a property whose JSON field REFUSALRULES of replyClass lists with a tag that ends in -too-long is 'ERROR #7201 rule <tag>', with no position, length or limit".
- `src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls`:
  - `RuleOf`: a part of the form `"ERROR #"1.N" rule "` followed by a tag (`?1L.(1L,1N,1"-")`) gives the tag; any other part is itself;
  - `RuleOf` and `FieldOf` become `[ Internal ]` public class methods (they read no store and write nothing);
  - the class doc's rule sentence names "ERROR #<code> rule <tag>".
- Tests: below.

**Acceptance Criteria:**
- **AC 1 (the cut and its boundaries; rows 1-7, 11, 14, 15).** Given a usable reply with one more evidence element, when `Decide.CheckReply` checks it, then the result, the element and `EvidenceCut` are as the matrix says.
  - Pinning test: new `Test.Watch.Payload` `TestEvidenceCut`, one assertion group per row; each cut element is compared with the exact expected string, its `$Length` is at most 128 and its last character is `$Char(8230)`; `$Parameter(CLASS, "EVIDENCEMAX")` equals the compiled MAXLEN of `Evidence`.
  - Row 4's text is "abcdefghi " repeated 30 times (300 characters, spaces at 10, 20, ...): the expected element is its first 119 characters followed by `$Char(8230)` (120 characters).
  - Row 14 calls `%JSONImport` with a dynamic object and asserts the object's element is still the original.
- **AC 2 (several, and only evidence; rows 8, 9, 12).** Given row 8, the two long elements are cut and "h3" is unchanged, in order, and `EvidenceCut` is 2. Given row 9, each reply is refused with exactly the RefusalText shown. Given row 12, it is refused as at the baseline.
  - Pinning test: `TestEvidenceCut`.
  - Changed pin: `TestPayloadRefused` L219-221 ("an evidence reference of 129 characters" refused) becomes "an elementAtFault of 129 characters" refused; the 129 evidence case moves to `TestEvidenceCut` (accepted, cut).
- **AC 3 (the count cap stays a refusal; rows 10, 11).** Given 21 elements with one over-long, then "ERROR #5001 rule evidence-over-max"; given 20 with one over-long, accepted with `EvidenceCut` 1.
  - Pinning tests: `TestEvidenceCut`; the existing "21 evidence references" row (L216-218) and `TestRuleTags`' `evidence-over-max` row stay.
- **AC 4 (the model cannot set the count; row 13).** Given a usable reply with `"evidenceCut": 3`, then it is refused, RefusalText "ERROR #9404: an unexpected property", and no payload.
  - Pinning test: `TestEvidenceCut`.
- **AC 5 (counted only, never logged; rows 8, 17).** Given row 8's reply, each long element carrying a distinct marker after its 130th character, when `Decide.Conclude` concludes it (the test's `Conclude` helper, ReplyGuard), then:
  - Fallback 0; `{}.%FromJSON(row.Payload).evidenceCut` is 2 and the payload's `evidence` holds the cut elements;
  - no marker is in the row's Payload, Reasons or the response, and no `Ens_Util.Log` row after the mark holds a marker or comes from the method `%JSONImport`;
  - and for a usable reply with no long element, the row's Payload has no key `evidenceCut`.
  - Pinning test: new `Test.Watch.Payload` `TestEvidenceCutRecorded`.
  - `Test.Eval.Capture` `TestRecheckIsSilent`: a new label "an evidence element cut" (row 8's reply): verdict 1, problem "", and `Writes("Snap", ...)` is "". The label "over the limit" becomes an elementAtFault of 129 (still verdict 0).
  - `Test.Eval.Capture` `TestNothingIsWrittenAnywhere`: unchanged code; its label "over the limit" is renamed "an evidence element cut", since its 129 element is now cut: it pins that the cut writes nothing in any table, header or audit entry.
- **AC 6 (C1 fix: the fixed tag; rows 16, 9).** Given a partner_outage reply (`Outage()`) with one evidence element of 128 characters, when `Decide.Recheck` runs it with the filter `OcuTalon.Test.Bridge.ProbeFilter`, then it returns 0 and the problem is exactly "After the reply filter ran: OcuTalon.Watch.Msg.DiagnosisPayload refused the filtered payload: ERROR #7201 rule evidence-too-long" (the test kills `^||ZzProbeFilter`). Given a DiagnosisPayload object with a 129-character Evidence element inserted directly, then `RefusalText` of its `%ValidateObject` status is "ERROR #7201 rule evidence-too-long" and holds no digit after "rule". Given row 9, the elementAtFault part keeps its length form (no pair lists elementAtFault).
  - Pinning test: new `Test.Watch.Payload` `TestEvidenceTooLongTag`.
  - Changed pins: `TestRefusalTrace` "over the limit" (L318-319, L339-340) becomes an elementAtFault of 129, expected "...accepts: ElementAtFault: 129 > 128"; its class-doc lines L15-18 follow. `TestRuleTags` L453: 23 pairs, and the 23rd is `evidence-too-long:evidence` (L454 still compares the first 22 with `RuleTags()`).
- **AC 7 (one allowlist).** Given the two REFUSALRULES, then `TestEveryRuleTagged` holds with its own-rule count taken over the pairs whose tag does not end in `-too-long`, and each `-too-long` pair: names a field that is the JSON name of a compiled property with a numeric MAXLEN, is the only `-too-long` pair of its field, and is written in no `%OnValidateObject`.
  - Pinning test: `TestEveryRuleTagged`, extended.
- **AC 8 (the harness counts the tag).** Given the parts "ERROR #7201 rule evidence-too-long", "ERROR #5001 rule cause-blank", "ElementAtFault: 129 > 128", "ERROR #9404: an unexpected property" and "ERROR #7201 rule Evidence 2", then `RuleOf` gives `evidence-too-long`, `cause-blank` and the last three parts unchanged, and `FieldOf` gives `evidence`, `cause`, `elementAtFault`, "" and "".
  - Pinning test: new `Test.Eval.Capture` `TestRuleNames`.
  - Changed pin: `SeedAll` L250-257: the over-long evidence seed becomes an elementAtFault of 129 (marker kept in it), rule "ElementAtFault: 129 > 128", field `elementAtFault`; one more seed holds the old evidence reply and is counted under "passes the check" (the counts follow).
- Standing criterion (Rule 19): every test added or changed passes on a fresh environment, in either order.

### Review Findings

Round-2 review (2026-11-16, tier 1, full mode, acceptance auditor armed; diff `08f55bc99..e9aacec4f` without the bookkeeping files). Every patch was applied; no decision is needed and nothing is deferred.

- [x] [Review][Patch] (med) The "no trace row" half of `TestEvidenceCutRecorded` could not fail: outside a host `$$$TRACE` writes no row, so a trace of the count from the conclusion passed [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls:TestEvidenceCutRecorded]. Fixed: the conclusion of the cut reply now runs with trace logging on for the job (`%Ensemble("DoTrace")`, `%Ensemble("LogSystemTrace")`, `%QUIET`, each restored afterwards).
- [x] [Review][Patch] (med) No fresh-environment evidence for the new Watch tests (standing criterion) [Test.Watch.Payload, Test.Watch.Summary]. Fixed by runs: fresh `class` runs of both classes and the fresh `lane-a@Eval` shard (Verification, review runs).
- [x] [Review][Patch] (low) QA's record called a `null` `evidenceCut` "already pinned", but no test sent one [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls:TestEvidenceCut row 13]. Fixed: row 13 also sends `"evidenceCut": null`.
- [x] [Review][Patch] (low) "the parent lists no length tag" repeated the count check before it and never looked for a length tag [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls:TestEveryRuleTagged]. Fixed: it now asserts that the parent's list holds no "-too-long:".
- [x] [Review][Patch] (low) `TestEvidenceCutRecorded` read `response.Payload` and `response.Reasons` without checking for a response [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls:TestEvidenceCutRecorded]. Fixed: guarded, plus an assertion that the conclusion gives a response.
- [x] [Review][Patch] (low) The class doc said evidence-too-long is only for a reference lengthened by a filter. The refusal also gives it for a number element of more than 128 digits, and for a long reference of the reply as it came when the import refuses the list for another element [src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls:20-23]. Fixed: the doc names all three.
- [x] [Review][Patch] (low) The `TestOneReplyPerRule` doc gave confidence-missing no count [src/ocutalon/cls/OcuTalon/Test/Eval/Capture.cls:10]. Fixed: "confidence-missing and cause-blank twice".

Rejected or closed:
- by-design (spec-bound): `Cut` keeps no minimum head. A reference whose only space in the first 128 is early (e.g. "TargetConfigNames: <140 characters with no space>") becomes "TargetConfigNames:" + U+2026. This is the rule as specified: "the last space at a position p with 2 <= p <= L" (Design Notes) and the Planner's "at the last word boundary". `Watch.ErrorText.Summary` behaves the same way. A floor (e.g. fall back to the hard cut below L/2) needs a ruling. Before C2' such a reply fell back.
- by-design: only the space is a word boundary. Design Notes step 1 and the `ErrorText.Summary` precedent say so. A reference with tabs or line ends in place of spaces is cut hard, which is still valid and at most 128.
- by-design: `TestEvidenceTooLongTag`'s "holds no digit after rule" is implied by the exact equality before it. It is AC 6's clause written out.
- low, rejected: when the import refuses the evidence list for a non-string element, `RefusalImport` re-checks the reply as it came, so an uncut long string in the same list is reported as evidence-too-long too, and the harness takes that as the first rule. This needs a reply with both kinds of element. The reply is refused either way. A fix needs a reply-class hook in the generic Decide (AD-2).
- low, rejected: the test helper `MaxLen` (and the older `JsonField`) match only an explicit `%JSONFIELDNAME`, while `LengthTag` falls back to the property name. Every property of both reply classes declares `%JSONFIELDNAME`, and the convention predates this change.
- low, closed by this review's runs: QA ran no shell check after its commit. The eval-set rules, boundaries and class rules ran on the final tree (Verification).
- low, rejected: QA's `TestCutEvidence` (Test.Watch.Summary) is outside the footprint list. It is a test-only addition, recorded in the QA Record.
- low, rejected: Row 15's branches, AC 7's two sub-assertions and the `index > 3` exclusion have no mutation line. Each AC's pinning test has one.
- false: making `RefusalPart`'s `replyClass` required gives no compile error in ObjectScript. Each call site is pinned by a test with a mutation: `TestEvidenceTooLongTag` for `RefusalText`, row 12 for `RefusalCheck`.
- false: `Test.Watch.Summary` `TestCutEvidence` opening the Decision with no guard is not a risk. `Resolved` always creates the Decision through `Test.Data.Fixture`, and the sibling tests do the same.
- false: the line numbers in the Intent and Code Map are not out of date. The Code Map states them at `ea4475096`.
- rejected (the fix edits this spec's earlier record): the "Shared surfaces" sentence and the Size paragraph are out of date. Results lists Diagnose, RememberDecision and the eval-set `capture` rule as run. The round-1 triage line says the `EvidenceCut` reset is held by the new-payload assertion, but no test observes the reset, because every caller imports into a new object. `TestNothingIsWrittenAnywhere` keeps a refused row, which is stronger than AC 5's wording. The facts are recorded here.

## Design Notes

**Where the cut belongs.** The three options of the brief, against the code:
- *Raise MAXLEN and cut in `%OnValidateObject`*: rejected. `%JSONImport` already calls `EvidenceIsValid` (Generator L931-939), so MAXLEN would have to go; `%ValidateObject` runs `%OnValidateObject` before the property checks (RegisteredObject L945-946), so the cut would have to mutate the object inside a validation that `Judge` runs twice (L1024, L1709); and the property would lose its declared limit.
- *Cut in `Decide.Judge` or `CheckReply`*: rejected. Decide is the generic bridge (AD-2: it names only Bridge classes); it would need a new reply-class hook and touches every reply class.
- *Pre-process the reply JSON before import*: chosen, as an override of `%JSONImport` in DiagnosisPayload itself. It is one class, it runs exactly where the refusal fired, it leaves `MAXLEN = 128` (so the second validation still guards a filter that lengthens), it cannot touch another field or another reply class, and `CheckReply` is its only caller (grep of `%JSONImport` outside the tests: `Decide.cls:1023` only).

**The cut** (`Cut(text)`, limit L = `EVIDENCEMAX` = 128), for a string element with `$Length(text) > L`:
1. Find the last space (U+0020, the word boundary of `Watch.ErrorText.Summary`) at a position p with 2 <= p <= L. The head is `$Extract(text, 1, p - 1)` with trailing white space removed. A space at position L itself is a boundary, so a head of L - 1 whole characters is kept when the text breaks there (row 3).
2. When there is no such space, or the head is blank once white space is removed (row 6), the head is `$Extract(text, 1, L - 1)`, minus one more character when that would end on a high surrogate (55296-56319; built only if Task 0 item 2 finds a pair counts 2), as `Memory.Learned.Fact` does.
3. The result is head followed by `$Char(8230)`: at most L characters. **The ellipsis is inside the 128.** It must be: the property keeps MAXLEN 128 and `Judge` validates the payload again after the filter, so a 129-character result would be refused. It is also the repo's convention (`ErrorText.Summary`, `Learned.Fact`, `Conversation` L484 and L944, `StepBuffer` L275).
- A word longer than 128 with no boundary (row 5) is cut hard at 127 characters plus U+2026. The rule is stated in the class doc.
- ASCII: the class rules forbid non-ASCII in source (`test-boundaries.sh` L4, `non_ascii` L34, the rule L213), so the source writes `$Char(8230)`. The stored text then holds U+2026: one character (3 bytes in UTF-8) in the Payload JSON's `evidence` and in the DecisionResponse. It is shown only where Veto item 1 says. Telegram, the Simulated phone and the web chat already carry U+2026 from `ErrorText.Summary` in the incident notice.

**Counted only.** The count is `EvidenceCut`, output-only, exported into the Decision row's Payload JSON as `"evidenceCut": n` (n = elements cut) when n > 0, by `Judge`'s existing `%JSONExportToString` (L1722). Why not the other mechanisms:
- a `$$$LOGINFO` with the count: the cut runs inside `CheckReply`, which `Decide.Recheck` and the capture harness call too, and both are pinned silent (`TestRecheckIsSilent`, `TestNothingIsWrittenAnywhere`); the spine's logging row puts `$$$LOG*` in hosts (ARCHITECTURE-SPINE L1408), and a payload class is not one; a log in `Conclude` would need a new hook through `Interpret`/`Judge` (Decide, AD-2);
- the C1 tag mechanism: tags name refusals, and a cut reply is not refused;
- a Decision column: a schema change for a count that the payload can carry.
- The model can never set the count: the field is output-only, and the override refuses a reply that names it (an output-only field would otherwise be ignored silently, Generator L605-615), so the refusal is exactly the old #9404.
- AD-8 and the trace rules: no fallback reason or classification changes; no text and no count is written to the event log or a trace; the count is in the decision's own record, readable in Visual Trace through the DecisionResponse's Payload. No element text leaves the payload's own `evidence`.

**C1 fix: the fixed tag.** `RefusalPart` gets the reply class and, for a #7201 on a known property, looks for a listed `-too-long` tag of that property's JSON field (`LengthTag`). DiagnosisPayload lists one: `evidence-too-long:evidence`. One list stays the allowlist that the Planner ruled (C1 gate); the tag is taken from the class's compiled parameter, never from the status, so a reply value can never follow "rule". The form drops the element position, the length and the limit: "ERROR #7201 rule evidence-too-long". `TestEveryRuleTagged` treats `-too-long` pairs as Decide's length tags (no `$$$ERROR` in `%OnValidateObject`). With the cut in place the tag applies only to what still refuses for evidence length: a reply filter that lengthens a reference past 128 (no shipped filter does; `ProbeFilter` does, for the test), and the theoretical JSON number element of more than 128 digits (an import type error traced to its length).

**The rule-string audit** (every string that can name a refusal; "shown" means it reaches the warning or the harness):

| Source | String | Values or numbers? | Shown? |
|--------|--------|--------------------|--------|
| `REFUSALRULES` (both classes, 22 tags + `evidence-too-long`) | the tags | none: fixed lower-case words | yes, after "rule" |
| DecisionPayload L28 `outcome-unlisted` message | "The outcome '<Outcome>' is not one of ..." | the reply's outcome | no (param 1; only the tag is shown) |
| DecisionPayload L34, L35 | fixed sentences | none | no |
| DiagnosisPayload L72 `outcome-not-act` | quotes the outcome | reply value | no |
| L74 `cause-category-unlisted`, L90-92 (`fix-kind-`, `fix-parameters-`, `fix-summary-not-for-category`) | quote the causeCategory | reply value | no |
| L76 `evidence-over-max` | "more than 20 references" | the class constant 20 | no |
| L81 `format-fix-kind-unlisted` | the DiagnosedFor list | code constants | no |
| L86-88 `rollback-*` | quote the fixKind | reply value | no |
| L77, L79, L82-84, L95, L97-98, L102 (outer) | fixed sentences | none | no |
| L102 embedded `Fix.Kind.Check` status | quotes reply keys | reply values | no (embedded, not shown) |
| RefusalText #7201/#7202 "<Property>[ element <n>]: <length> > <limit>" | position and length from the reply, limit from the class | yes (numbers) | yes. Evidence now "rule evidence-too-long"; still numeric for Outcome (32), Reasons (1000), CauseCategory (32), ElementAtFault (128), FixKind (32), Cause (1000), FixSummary (1000) |
| RefusalText #7203/#7204 "<Property>: value > <limit>" | the class's limit only ("Confidence: value > 1") | constant only | yes |
| "ERROR #9406 on <Property> element <n>", "ERROR #<code> on <Property> element <n>" | the position | yes (a position) | yes |
| "; and <k> more" | a count | yes | yes (the harness skips it, `Parse` L249) |
| "ERROR #9404: an unexpected property", "ERROR #9406[ on <Property>]", "ERROR #5035" | none | none | yes |
| Nested properties (FixParameters.*, ItemNoun.*) | no label: "ERROR #7201" / "ERROR #9406" | none | yes |

So after the fix, the strings that still carry numbers are the length forms of the seven other limited properties and the element positions. The ruling names Evidence only, so this spec tags Evidence only; tagging another field is one more pair (e.g. `element-at-fault-too-long:elementAtFault`) and one test row, with no code (Veto item 6(iii)).

**The prompt.** `Agent/Diagnosis.cls:41` tells the model "a longer value makes the whole reply invalid: each "evidence" reference at most 128 characters". After C2' that is stricter than the code for evidence only. It is left as it is: it is model-facing (the ruling makes C2' not model-facing), and it still steers the model to short references.

**AD-8.** The rule's words, "`invalid` (JSON that fails validation)" (ARCHITECTURE-SPINE L318) and "Content that doesn't validate is unusable (AD-8)" (L271), still hold: the cut is part of the reply class's own import, before validation, and Decide alone classifies. They do not speak of a reply class normalising a field before it validates, so no AD text must change (Veto item 4). If the Planner wants a record, the sentence of L271:
- old: "Content that doesn't validate is unusable (AD-8)."
- new: "Content that doesn't validate is unusable (AD-8). A reply class may normalise one field before it validates: `DiagnosisPayload` cuts an evidence reference over 128 characters to 128, at its last word boundary and ending in U+2026, and records only the number of references cut (`evidenceCut` in the stored payload); more than 20 references is still invalid (DW-1421 C2')."

**Ledger inbox:** DW-1421 (C2', C1 fix). Status line per the run's DW process at merge, through `ledger.sh append`. C3 stays deferred in the backlog; C5 waits for the Planner's ruling on the report below.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | No catalog key, sentence or UI string changes. The diagnosis evidence IS user-visible: the first evidence line that is more than a period fills the slot of `summary.evidence` ("Evidence: {evidence}.", `Watch/Summary.cls` L288-309), the closed-incident summary that Telegram, the Simulated phone and the web chat send and that the web history and the recent_activity tool show. So a cut first line shows as "Evidence: <at most 127 characters of the model's reference>" followed by U+2026, with no period after it (the sentence slot ends at U+2026, `Msg/Catalog.cls` L199). U+2026 already ends a cut error summary in the incident notice (`Watch/ErrorText.cls` L87). Before C2' such a reply was a fallback, whose summary says "No cause was found: ..." instead. | Approve: model text in an existing slot, cut by the repo's existing rule. |
| 2 | (b) Cross-lane edits | `Watch/Msg/DiagnosisPayload.cls`, `Bridge/Process/Decide.cls`, `Test/Eval/CaptureTool.cls`, `Test/Watch/Payload.cls` and `Test/Eval/Capture.cls` are Lane A (`Watch/Msg` and `Bridge/Process` included). Lane C makes the edits under the Planner's DW-1421 round-2 ruling. `DecisionPayload.cls` is not changed. At plan time no unmerged `OCT-*` branch touches these files (each local `OCT-*` branch against `feature/OCT_OcuTalon_MVP`). | Grant. |
| 3 | (c) Stored data or schema | No class storage, column or table changes. The Decision row's Payload (a JSON text) of a diagnosis gains the optional key `evidenceCut` (an integer 1 to 20) only when a reference was cut; every other payload is byte-identical. Its readers pick keys by name and ignore it (`IncidentManager.cls` L803-815, `Eval/Sink.cls` L116-122, `Watch/Summary.cls` L296). A stored evidence reference may now end in U+2026. No migration. | Approve, with no migration. |
| 4 | (d) Architecture change | None required. AD-8 (spine L309-318, L271) still holds: the bridge alone classifies, `invalid` is still "JSON that fails validation", and the cut is the reply class's own import before validation. The wording does not cover a reply class normalising a field, so the optional record sentence (old and new, verbatim) is in Design Notes. | Approve with no AD change, or add the record sentence. |
| 5 | (e) Product behaviour change | A diagnosis whose only fault is an evidence reference over 128 characters is accepted, where it fell back `invalid`: the reference is cut (Design Notes) and counted in `evidenceCut`. Expected effect: the 3 of 5 `orders-target-to-review` fallbacks of C0 become diagnoses. More than 20 references, every other field's limit, a non-string element and a reply that names `evidenceCut` are refused as before. The warning for an evidence length refusal (now only after a filter that lengthens text) reads "ERROR #7201 rule evidence-too-long" in place of "Evidence element <n>: <length> > 128", and the capture harness counts it under `evidence-too-long`, field `evidence`. | Approve. |
| 6 | Design beyond the ruling | (i) The count lives in the stored payload (`evidenceCut`), not in a log: a log cannot carry it without breaking Recheck's pinned silence (the cut runs inside Recheck too) or adding a hook through Decide. (ii) The fixed tag is one more `REFUSALRULES` pair, which Decide finds by its `-too-long` suffix and the property's JSON field, so the allowlist stays one list; `TestEveryRuleTagged` exempts such pairs from its one-`$$$ERROR` count. (iii) The other length forms keep their numbers (audit table); each could get its tag with one pair and one test row, no code. Default: Evidence only, as ruled. (iv) The Diagnosis prompt's "a longer value makes the whole reply invalid" sentence (`Agent/Diagnosis.cls` L41) is now stricter than the code for evidence; it stays, being model-facing. (v) `CaptureTool.RuleOf` and `FieldOf` become public `[ Internal ]` so they can be pinned. | Approve (i), (ii), (v); rule (iii) (default Evidence only); note (iv). |

## Public text

None new. No catalog key, sentence or UI string is added or changed. A cut evidence reference ends in U+2026 inside a model-text slot (Veto item 1).

## Verification

Use a lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh`, `ci/warm.sh` and `eval/run.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag>`; fresh runs leave `OCUTALON_WARM` unset.
- One test class (or `Class:Method`) per foreground call, `timeout: 600000`, each under about 3 minutes, never two test calls in one message.
- No model and no key anywhere.

**Commands:**
- (once) `ci/warm.sh up` with the warm tag, then Task 0 items 1 to 3.
- (loop) Warm, each expected to pass: `ci/iris.sh class OcuTalon.Test.Watch.Payload`; `OcuTalon.Test.Eval.Capture`; `OcuTalon.Test.Bridge.ReplyCheck`; `OcuTalon.Test.Bridge.Decide`; `OcuTalon.Test.Fix.Validation`; `OcuTalon.Test.Bridge.CodeRules`.
- (once) Fresh, each expected to pass: `OcuTalon.Test.Watch.Diagnose:TestDiagnosisVariants`; `OcuTalon.Test.Agent.Instructions`; `ci/iris.sh shard lane-a@Eval` (or its classes, split).
- (once) `EVAL_SET_ONLY="capture eval-scripts" bash docker/tests/test-eval-set.sh` (no shell file changes, so this is a guard only).
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call: each exits 0.
- (once) `git diff --name-only ea4475096` lists only the footprint files; no added line holds a non-ASCII character or an absolute local path.
- (once, at the end, also after a failure) `ci/warm.sh down` with the warm tag; `ci/iris.sh teardown` for the fresh tag.

**Mutations (Rule 19).** One `mutation: <change> -> <test that went red>` line each; revert each byte for byte (`cmp` against a copy taken before it), and check `git status --short` and `git diff --stat` are as before. The planned mutations:
- C2', the cut:
  - the cut call removed from `%JSONImport` (import as before) -> `TestEvidenceCut` rows 2-8, 11 and `TestEvidenceCutRecorded` red;
  - the threshold `> 128` made `> 127` -> `TestEvidenceCut` row 1 (128 unchanged) red;
  - the ellipsis outside the limit (a head of 128 then U+2026) -> row 2 red (refused, 129 > 128);
  - the word boundary ignored (always the hard cut) -> rows 3, 4 red;
  - the boundary searched in 1..L-1 only -> row 3 red;
  - the blank-head fallback removed -> row 6 red;
  - the surrogate guard removed (if built) -> row 7 red;
  - the cut applied to `reasons` too -> `TestEvidenceCut` row 9 (the reason of 1001 accepted) red;
  - the cut dropping the elements after the 20th -> row 10 (21 elements accepted) red;
  - the copy of a dynamic-object input removed -> row 14 red.
- C2', the count:
  - `EvidenceCut` never set -> `TestEvidenceCutRecorded` and row 8 red;
  - `EvidenceCut` set to 1 per reply -> row 8 and `TestEvidenceCutRecorded` (2) red;
  - `EvidenceCut` given `InitialExpression = 0` -> `TestEvidenceCutRecorded` (no key without a cut) red;
  - the `evidenceCut` input guard removed -> row 13 red (accepted, the field ignored);
  - a `$$$LOGINFO` of the count added to `%JSONImport` -> `Test.Eval.Capture` `TestRecheckIsSilent` (an evidence element cut) and `TestEvidenceCutRecorded` red;
  - the same `$$$LOGINFO` with the element's text -> also the marker assertions of `TestEvidenceCutRecorded` red.
- C1 fix:
  - `LengthTag` returns "" -> `TestEvidenceTooLongTag` red (the length form with numbers);
  - the `-too-long` suffix test removed from `LengthTag` -> `TestEvidenceTooLongTag` red ("rule evidence-over-max", the first pair of field evidence);
  - the field test removed from `LengthTag` -> `TestEvidenceCut` row 9 red (ElementAtFault shown as evidence-too-long);
  - `evidence-too-long:evidence` removed from `REFUSALRULES` -> `TestEvidenceTooLongTag` and `TestRuleTags` (23) red;
  - a pair `reasons-too-long:reasonz` added to DiagnosisPayload's `REFUSALRULES` -> `TestEveryRuleTagged` red;
  - `RuleOf` back to the #5001 prefix only -> `Test.Eval.Capture` `TestRuleNames` red.

**Results (lane C warm throwaway, tag e0dw1421r2w, no model, no key; run by Lane C round 2).**

Task 0 (before any product edit; probes in a scratch class loaded into the warm container only, never in the tree):
- Item 1: a scratch subclass of DiagnosisPayload with the output-only `%Integer` `EvidenceCut` (`%JSONINCLUDE = "OUTPUTONLY"`, `MINVAL = 1`, no `%JSONNULL`): `%JSONExportToString` writes NO key when it is "" and writes `"evidenceCut":2` when it is 2, so the stop rule does not fire. `%JSONImport` of a text with `"evidenceCut": 3` succeeds (status OK) and ignores it (`EvidenceCut` stays ""), so the guard of row 13 is needed.
- Item 2: `$Length($Char(128512))` is 0 on this build (`$Char` of a code above 65535 gives the empty string, `$Ascii` -1), so the spec's probe character cannot be built that way. A surrogate pair built as `$Char(55357, 56832)` has `$Length` 2, and after `%ToJSON`/`%FromJSON` it is still 2 (first unit 55357); a JSON text with the escaped pair `\ud83d\ude00` also reads as 2 characters. Per the rule (2 = the guard is built): the surrogate guard and row 7 are built, and row 7 builds the pair as `$Char(55357, 56832)`.
- Item 3: `%ValidateObject` of a DiagnosisPayload (partner_outage, valid otherwise) with one 129-character Evidence element inserted directly: top code 7201, param 2 is 128, and the embedded status is #5802 with param 1 `OcuTalon.Watch.Msg.DiagnosisPayload:Evidence(1)`, as expected.

Runs (warm, one class per call), after the edits and again after the review patches: `OcuTalon.Test.Watch.Payload`, `OcuTalon.Test.Eval.Capture`, `OcuTalon.Test.Bridge.ReplyCheck`, `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Watch.Diagnose`, `OcuTalon.Test.Agent.RememberDecision` and `OcuTalon.Test.Agent.Instructions` passed; `OcuTalon.Test.Fix.Validation` and `OcuTalon.Test.Bridge.CodeRules` passed after the edits. Fresh (tag e0dw1421r2f, `ci/iris.sh shard lane-a@Eval`): passed, 24 classes, 316 s; torn down. `bash docker/tests/test-eval-set.sh`, split with `EVAL_SET_ONLY` into six calls that together name every rule (the `capture` rule alone in a call of its own): all rules passed. `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-class-rules.sh`: all rules passed (also after the patches). The spine lint reports only its baseline findings (the spine is not changed). No added line of any src file holds a non-ASCII character or an absolute local path. Every `ci/` and `eval/` command went through the lane-C wrapper; the warm and fresh stacks are down.

Test changes beyond the spec's list: `Test.Eval.Capture` `TestLinesHoldNoReplyText` pins the count line "CHK|decisions|33|1|32|33|34" (it follows the seed counts); `TestEvidenceCut` has two rows more than the matrix (row 3 with an earlier space before the space at 128, row 4 with a boundary after two spaces) so that the boundary range and the trailing-white-space strip can be killed; `TestEvidenceCutRecorded` also asserts that a new payload has no count (kills an `InitialExpression`).

Mutations (each applied to the one file, the class run red, the file restored byte for byte, `cmp` identical, the class green again on the same warm stack; `git diff --stat` unchanged after each):
- mutation: threshold `> 128` made `> 127` (cut applied to a 128 element) -> Test.Watch.Payload `TestEvidenceCut` row 1 (element and EvidenceCut) red
- mutation: threshold `> 128` made `> 129` -> `TestEvidenceCut` rows 2, 3 (both) and 8 red (refused, #9406 on evidence)
- mutation: threshold `> 128` made `> 299` (300-character texts cut only) -> `TestEvidenceCut` rows 2, 3, 6, 7, 8 and `TestEvidenceCutRecorded` red
- mutation: the cut call removed from `%JSONImport` (import as before) -> `TestEvidenceCut` rows 2-8, 10, 11, 14 and `TestEvidenceCutRecorded` red
- mutation: the ellipsis outside the limit (hard cut of 128, then U+2026) -> `TestEvidenceCut` rows 2, 5, 6, 8, 11, 14 red (refused, 129 > 128)
- mutation: the word boundary ignored (`" "` compared with `"~"`, always the hard cut) -> `TestEvidenceCut` row 4 (both: words, and after two spaces) red. Row 3 as the matrix words it (127 letters, no earlier space) gives the same text either way, so it is not red here
- mutation: the boundary searched in 1..L-1 only -> `TestEvidenceCut` row 3 "a space at 128 after an earlier one" red (the matrix's row 3 alone cannot tell, see above)
- mutation: the blank-head fallback removed (a head that starts with a space is kept blank) -> `TestEvidenceCut` row 6 red
- mutation: trailing white space of the head not removed -> `TestEvidenceCut` row 4 "a boundary after two spaces" red
- mutation: the surrogate guard removed (`If 0 Set head = ...`) -> `TestEvidenceCut` row 7 red
- mutation: the cut applied to `reasons` too (a reason over 1000 cut to 1000) -> `TestEvidenceCut` row 9 (the reason of 1001: accepted, not refused) red
- mutation: the cut dropping the elements after the 20th (`%Pop` while over 20) -> `TestEvidenceCut` row 10 and `TestPayloadRefused` "21 evidence references" red
- mutation: the copy of a dynamic-object input removed (`input` itself is cut) -> `TestEvidenceCut` row 14 (the caller's object is not changed) red
- mutation: `EvidenceCut` never set (`If 0 Set ..EvidenceCut = cut`) -> `TestEvidenceCut` rows 2-8, 11, 14 (EvidenceCut) and `TestEvidenceCutRecorded` red
- mutation: `EvidenceCut` set to 1 per reply -> `TestEvidenceCut` row 8 (count and export) and `TestEvidenceCutRecorded` red
- mutation: `EvidenceCut` given `[ InitialExpression = 0 ]` -> `TestEvidenceCutRecorded` ("a new payload has no count") and `TestEvidenceTooLongTag` red. The spec's "no key without a cut" is held by the import's reset to "", so the new-payload assertion is what catches it
- mutation: the `evidenceCut` input guard removed (`If 0 Return ...`) -> `TestEvidenceCut` row 13 red
- mutation: a `Ens.Util.Log` LogInfo of the count added to `%JSONImport` -> Test.Eval.Capture `TestRecheckIsSilent` ("an evidence element cut") and `TestRecordsAndLogsNothing`, and Test.Watch.Payload `TestEvidenceCutRecorded` (no log row from the import) red
- mutation: the same LogInfo with the element's text (in the cut loop) -> Test.Eval.Capture `TestRecheckIsSilent` and `TestRecordsAndLogsNothing`, and Test.Watch.Payload `TestEvidenceCutRecorded` (the marker and the import rows) red
- mutation: `LengthTag` returns "" -> `TestEvidenceTooLongTag` red (the length form with numbers; the 128 element after the filter)
- mutation: the `-too-long` suffix test removed from `LengthTag` -> `TestEvidenceTooLongTag`, `TestEvidenceCut` row 9 and `TestRefusalTrace` red (the first pair of the field wins: "rule evidence-over-max", "rule reasons-blank")
- mutation: the field test removed from `LengthTag` -> `TestEvidenceCut` row 9, `TestEvidenceTooLongTag` (elementAtFault) and `TestRefusalTrace` red (ElementAtFault shown as evidence-too-long)
- mutation: `evidence-too-long:evidence` removed from `REFUSALRULES` -> `TestEvidenceTooLongTag` and `TestRuleTags` (23) red
- mutation: a pair `reasons-too-long:reasonz` added to DiagnosisPayload's `REFUSALRULES` -> `TestEveryRuleTagged` (the field is no JSON name, no numeric MAXLEN) and `TestRuleTags` (24) red
- mutation: `RuleOf` back to the #5001 prefix only -> Test.Eval.Capture `TestRuleNames` red
- mutation: a reply value after "rule" (the #7201 length form quotes `value` instead of the tag) -> `TestEvidenceTooLongTag` red
- mutation (review patch): `, replyClass` dropped from the `RefusalCheck` call of `RefusalPart` -> `TestEvidenceCut` row 12, a number of 129 digits ("the refusal is ERROR #7201 rule evidence-too-long") red
- mutation (review patch): the `%GetTypeOf(i) = "string"` test removed from the cut condition -> `TestEvidenceCut` row 12, a number of 129 digits (accepted instead of refused) red
  Both were restored byte for byte (`cmp` identical) and the class was green again on the same warm stack.

**Shared surfaces:** the reply-check warning text (pinned in `Test.Watch.Payload`, `Test.Bridge.ReplyCheck`, `Test.Agent.RememberDecision`, `Test.Watch.Diagnose`), the capture harness's rule names (pinned in `Test.Eval.Capture` and rule `capture`), and the stored diagnosis Payload (read by IncidentManager, Eval.Sink and Watch.Summary). Run here: Payload, Capture, ReplyCheck (warm, green); `Test.Agent.RememberDecision`, `Test.Watch.Diagnose` and the `capture` rule of `test-eval-set.sh` are not run here.

**Size:** medium. Product: DiagnosisPayload (+45 lines: override, `Cut`, property, parameter, doc), Decide (+20: `LengthTag`, one branch, two call sites, doc), CaptureTool (+5). Tests: Payload (+130: three new tests, four changed pins), Capture (+30: one new test, three changed pins). One implementation pass, no shell change, no model run; the Planner's 5-run capture verifies.

**Review round 2 (lane C; warm tag e0dw1421q2w, fresh tag e0dw1421q2f; no model, no key, every `ci/` command through the lane-C wrapper).**

Mutations on the review patches. Each was applied to one file and run red on the warm stack; the file was restored with `cp` and `cmp` showed it identical. `git status --short` and `git diff --stat` were unchanged after each.
- mutation: `$$$TRACE("evidence references cut: "_<the payload's evidenceCut>)` in `Decide.Conclude` after setting `row.Payload` -> Test.Watch.Payload TestEvidenceCutRecorded red ("the conclusion writes no event log or trace row"). It was green before the patch, with trace logging off.
- mutation: the `evidenceCut` guard in `DiagnosisPayload.%JSONImport` tests the value (`object.evidenceCut '= ""`) instead of the key's presence -> Test.Watch.Payload TestEvidenceCut row 13 "with null" red (accepted, with a payload).
- mutation: the parent's REFUSALRULES gains `,reasons-too-long:reasons` -> Test.Watch.Payload TestEveryRuleTagged red ("the parent lists no length tag", and the two count and prefix checks).

Runs on the final tree:
- warm, one class per call: `OcuTalon.Test.Watch.Payload`, `OcuTalon.Test.Watch.Summary`, `OcuTalon.Test.Eval.Capture`, `OcuTalon.Test.Bridge.ReplyCheck` and `OcuTalon.Test.Bridge.Decide` passed;
- fresh: `ci/iris.sh shard lane-a@Eval` passed (24 classes, 360 s), `ci/iris.sh class OcuTalon.Test.Watch.Payload` passed (140 s), and `ci/iris.sh class OcuTalon.Test.Watch.Summary` passed. Its first try exited 75: the lane-C throwaway lock was held by the Epic 28 runner for 240 s. The retry waited for the lock (643 s in all, the class itself 8.6 s). Both tags are torn down;
- `bash docker/tests/test-eval-set.sh` in six `EVAL_SET_ONLY` calls that together name all 26 rules: five calls passed (57, 27, 36, 180 and 43 s). The `capture` call (203 s) failed once on "with the capture variable empty, the run is not the same, byte for byte, as with it unset", then passed on the same tree (234 s). This diff changes no shell file; it is ledgered as DW-1435, a flake, routed to burndown;
- `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-class-rules.sh` exited 0.

No added line holds a non-ASCII character or an absolute local path. The reversed-order shard runs remain the lead's pre-push check (Rule 21).

## C5 report

DW-1421 C5 (confidence-missing), report only, from the code at `ea4475096`. Nothing is built.

**1. What `DecisionPayload.confidence` drives.**
- Routing (the outcome chosen): nothing. No code reads the confidence's value to choose or change an outcome.
  - `Decide.Judge` sets the outcome from `payload.Outcome` (`Decide.cls:1715`) and changes it only by the user rule, on the provenance (L1716-1719). It copies the confidence as a number with two decimals (L1721).
  - `Core/Intake.cls:197-214` keeps Decide's Outcome, or tellnow for a fallback (L209-211). The `ItemDecision` it sends carries Outcome, Fallback and FallbackReason and no confidence (L229-231). `Intake.cls:186` acts on outcome act only.
  - `Core/Rule/Outcome.cls:18-27`, the OutcomeRouter's rule, routes on OwnerRef and Outcome only: digest goes to DigestStore, tellnow and act go to Notify for a session owner, and ignore goes nowhere.
  - `Bridge/Settings.cls:405-416` (TestAnswer) reads Fallback and FallbackReason only.
- Thresholds: none. No comparison of a confidence with a number exists in `src/`, `web/src` or `eval/`. The only bounds are the type's own `MINVAL = 0, MAXVAL = 1, SCALE = 2`: `DecisionPayload.cls:20` (import refuses a value outside them), `Bridge/Data/Decision.cls:30`, `Bridge/Msg/Result.cls:15` and `Live/Payload/Decision.cls:24`.
- The digest: nothing. DigestStore receives the ItemDecision, which has no confidence.
- The eval scorer: nothing. `Eval/Sink.cls:67-68` takes Fallback and FallbackReason, and L112-127 takes the payload's category, element, fix kind and parameters. `Eval/Gate.cls` and the `eval/` case files set no confidence expectation.
- Wording: no channel text. The only wording is the web UI's "Confidence {n}" (`web/src/app/chat/decision-view.ts:19`, `confidenceText` L113-116, `formatConfidence` L94-97, which turns an absent value into "0.00"). It is used:
  - in the decision strip (`chat/decision-strip.ts:233-239`), but not on a fallback and not when absent;
  - in the rail (`rail/rail-view.ts:334-336`, `rail/status-rail.ts:60`), on the same terms;
  - per `chat/notice-card.ts:21-22` (a fallback shows no confidence) and `rail/decision-row.ts:23`.
- Storage and transport:
  - the Decision row (`Decide.cls:1498`; fallback rows store "", L1610 and L1748), the DecisionResponse (L1883);
  - the live payload (`Live/Payload/Decision.cls:89`, `web/src/app/live/payloads.ts:249`);
  - the history API, which leaves it out when empty (`Web/History.cls:58`, `web/src/app/api/history-types.ts:35`).
- Model-facing text: `Agent/Triage.cls:33` ("Use a low number when the item is unclear") and L45 (a persona never changes it); `Agent/Diagnosis.cls:40`; `Agent/Chat.cls:83` (stays exact under a persona); `BridgeExample/Agent.cls:32`.
- What a MISSING confidence does today: `DecisionPayload.cls:35` refuses the reply (`confidence-missing`), and Decide records the fallback `invalid`.
  - For decide, Intake turns the fallback into tellnow (`Intake.cls:209-211`). A session owner gets a tell-now card with the Fallback flag and the generic reason "the model's reply couldn't be used". The model's reasons are dropped.
  - For diagnose, the incident is a fallback incident: no cause and no fix offer, with the `incident.fallback` notice.
  - This refusal is the only way the confidence affects routing.

**2. The most cautious value.** No confidence VALUE is more or less cautious than another. Every value from 0 to 1 routes the same, and no threshold exists, so no value can demote an act or a tellnow, and low confidence is treated neither as "tell now" nor as "digest". The values differ only in the number the web UI shows.

What does change attention is whether a reply missing its confidence is refused or accepted:
- **decide:** today's refusal gives tellnow, which routes like act (`Rule/Outcome.cls:25`) and above digest and ignore. Accepting the reply with ANY default lets the model's outcome stand, so it lowers attention exactly when that outcome is ignore or digest.
- **diagnose:** the outcome is always act (`DiagnosisPayload.cls:72`), and the incident is noticed either way. Accepting never lowers attention: it adds a cause and possibly an approval-gated fix offer.

**3. Each candidate default** (for a reply whose only fault is the missing confidence):

| Default | Stored / shown | decide routing | diagnose routing |
|---------|----------------|----------------|------------------|
| 0 | 0.00 / "Confidence 0.00" (reads as "certainly wrong") | the model's outcome: ignore and digest lower attention vs today | act, with cause and fix: not lower |
| 0.5 | 0.50 / "Confidence 0.50" (an invented midpoint) | same as 0 | same as 0 |
| 1 | 1.00 / "Confidence 1.00" (an overclaim) | same as 0 | same as 0 |
| absent ("" stored) | nothing shown: the strip, the rail, the history API and the live payload already leave an empty confidence out | same as 0 | same as 0 |
| "most cautious" = absent, plus for decide the floor ignore/digest -> tellnow (the user rule's mechanism, `Decide.cls:1716-1719`) | nothing shown | never below today's tellnow fallback; tellnow and act are kept | as absent |
| keep refusing (today) | fallback; nothing shown | tellnow (fallback) | fallback incident, no cause |

Notes on the last two rows:
- The floor needs a code-written reason line, like `USERANSWERED` (`Decide.cls:174`). That is new public text. Without it, the model's reasons argue for a digest under a tellnow chip.
- The floor also makes the eval score a model's ignore or digest as tellnow on such replies. The two C0 cases expect act (`eval/held-out/mail-claims-rejected-today`) and tellnow (`eval/mail-access-expires-today`), so the floor would hide a wrong outcome on the second one.
- "absent" changes a sentence of the spine: L271 says both payloads "carry ... a confidence between 0 and 1". It also changes `DecisionPayload`'s class doc ("a confidence that is present").

**4. Conclusion.** No numeric confidence is strictly the most cautious, because the code reads the value only to display it. So 0, 0.5 and 1 are not cautious choices, only displayed claims, and 1 is the least honest. The strictly most cautious server-side treatment is:
- **diagnose:** accept with the confidence absent. This never lowers attention and shows no invented number.
- **decide:** either keep the refusal, which already gives the highest attention (tellnow), or accept with the confidence absent AND the tellnow floor for ignore and digest. The floor needs one new code-written reason line (a public-text gate item) and blunts the eval for those replies.

Recommendation: if the Planner rules a server-side default, make it "absent" (not 0, 0.5 or 1). Apply it to diagnose always. For decide, apply it only together with the floor; otherwise keep decide's refusal and leave triage's missing confidence to the instruction change, which is model-facing and rides the post-cut Triage A/B. C0 saw the missing confidence only on decide (2 of 5), never on diagnose.

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 19 findings — high 0, medium 5, low 9, false 5, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind: `TestNothingIsWrittenAnywhere` lost its refused-by-import row — the row's reply is now cut, so a refused Recheck is no longer pinned to write nothing; patched: a label "over the limit" with an elementAtFault of 129 is back beside "an evidence element cut"
  - `[low]` `[patch]` Blind: the REFUSALRULES comment says "in rule order" but the 23rd pair is a length tag — patched: the comment now says the length tags follow the rules
  - `[low]` `[reject]` Blind: a stream input is not rewound before the `##super` fallback — `CheckReply` passes a string; no caller passes a stream; the fix adds a branch for an unreachable input
  - `[low]` `[reject]` Blind: the Size paragraph and the list of test changes lag the diff — the fix edits this build's spec
  - `[low]` `[reject]` Blind: `epics.md` story 5.12's example of a length failure names an evidence element — another story's planning block (Rule 11), and the text is an example, not a requirement
  - `[low]` `[reject]` Blind: only the space is a word boundary in `Cut` — by design (matrix rows 3 and 4 say "space"; `Watch.ErrorText.Summary` is the precedent); a model reference with newlines for spaces is cut hard, which is still valid
  - `[false]` `[reject]` Blind: `RememberDecision`, `Diagnose` and the `capture` rule were not run — they were run afterwards and passed (Verification)
  - `[low]` `[reject]` Edge: stream input after a failed parse (same as the third row)
  - `[low]` `[reject]` Edge: a white-space-only over-long reference is accepted as spaces and U+2026 — a model reference of only white space is not realistic and the fix adds a branch; the reference was refused before only because of its length
  - `[false]` `[reject]` Edge: a stored Payload that holds `evidenceCut` is refused if it is re-imported — no code re-imports a stored Payload (grep: `Decide.CheckReply` is the only caller of `%JSONImport`), and the field is output-only by the spec
  - `[medium]` `[patch]` Edge: the refused row of `TestNothingIsWrittenAnywhere` was dropped (same root cause as the first row; patched with it)
  - `[medium]` `[patch]` Verification-gap: the `RefusalCheck` call site of `RefusalPart` is pinned by no test — patched: `TestEvidenceCut` row 12 now sends a number of 129 digits and expects "ERROR #7201 rule evidence-too-long"; mutation recorded
  - `[medium]` `[patch]` Verification-gap: the string-only guard of the cut is pinned by no test (row 12's numbers are short) — patched with the same row; mutation recorded
  - `[medium]` `[patch]` Verification-gap: `TestNothingIsWrittenAnywhere` lost its refused row (same root cause as the first row; patched with it)
  - `[low]` `[reject]` Verification-gap: no mutation line for the `%mappingName` pass-through, the non-JSON branches, the reset of `EvidenceCut` and two AC 7 sub-assertions — the reset is held by the new-payload assertion of `TestEvidenceCutRecorded` and the non-JSON branches by row 15; the rest is not met in everyday use and each fix is more than a correction
  - `[false]` `[reject]` Verification-gap: the shared-surface classes were not run — they were run afterwards and passed
  - `[false]` `[reject]` Verification-gap: `test-eval-set.sh` reads `DiagnosisPayload.cls` and was not run — it was run and passed (all rules)
  - `[low]` `[reject]` Verification-gap: only the space is a word boundary (same as the sixth row)
  - `[false]` `[reject]` Intent-alignment: the 5-run live capture is not part of the diff — the intent assigns it to the Planner; no defect in the change

### 2026-11-16 - Review pass, round 2 (after QA round 2)
- verdicts: 26 findings from four layers (blind 9, edge 7, verification-gap 7, acceptance 3) - high 0, medium 2, low 14, false 3, plus 7 rejected because their fix edits this spec's earlier record; after grouping: 7 patched, 3 by-design, 5 low rejected or closed, 3 false, 1 spec-record group (see `### Review Findings`)
- patched: the trace half of `TestEvidenceCutRecorded` (med), fresh runs of the new Watch tests (med, runs), the `null` `evidenceCut` row, the parent's length-tag check, the response guard, the DiagnosisPayload class doc on where evidence-too-long appears, the Capture class doc count
- focus checks (acceptance auditor, confirmed): no element text reaches a log, a trace or the capture's stdout, and only a listed tag can follow "rule"; AD-8 holds (only `evidence` is normalised, every other refusal and the 20-element cap unchanged); the source is ASCII, `$Char(8230)` is inside the 128, and space-only boundaries are by design; the other seven length forms keep their numbers (only Evidence is tagged, by ruling); `CaptureTool.RuleOf`/`FieldOf` are public `[ Internal ]` on a `%RegisteredObject` in the Test package, called only from the eval shell scripts and tests, with no web or `$ClassMethod` path that can name them
- ledger: DW-1435 (the capture rule's flake, out of footprint, routed to burndown)
- follow-up review recommended: false (no high)

## Auto Run Result

Status: done
Blocking condition: none

- Summary: `DiagnosisPayload.%JSONImport` cuts an evidence element over 128 characters at the last word boundary (ending in U+2026, inside the 128) and counts the cuts in the output-only `EvidenceCut`, with nothing logged; a reply naming `evidenceCut` is refused as before. `REFUSALRULES` gains `evidence-too-long:evidence`; Decide shows "ERROR #7201 rule evidence-too-long" through `RefusalPart` and `LengthTag`; the capture harness's `RuleOf` takes any "ERROR #<code> rule <tag>" and `RuleOf`/`FieldOf` are public `[ Internal ]`. C5 is a report only; nothing is built for confidence.
- Files: `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls` (override, `Cut`, `EvidenceCut`, `EVIDENCEMAX`, the pair, docs); `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (`RefusalPart`, `LengthTag`, call sites, doc); `src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls` (`RuleOf`, `FieldOf`); `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls` and `src/ocutalon/cls/OcuTalon/Test/Eval/Capture.cls` (new tests and the changed pins); this spec.
- Review: 19 findings (high 0, medium 5, low 9, false 5); patches applied: the refused row of `TestNothingIsWrittenAnywhere` restored, the REFUSALRULES comment corrected, and a 129-digit number row in `TestEvidenceCut` (pins the `RefusalCheck` call site and the string-only guard); nothing deferred; every rejected finding has its reason in the triage log.
- Follow-up review recommendation: false (per the run's ruling, true only if a high was patched; none was).
- Verification: see `## Verification` (Task 0, 28 mutations, warm classes, the fresh `lane-a@Eval` shard, the eval-set script, boundaries, class rules, lint baseline).
- Residual risks: the Planner's 5-run capture is the live check that the 3 of 5 `orders-target-to-review` fallbacks become diagnoses; a cut evidence line shows in the closed-incident summary ("Evidence: ..." ending in U+2026) as Veto item 1 says; only the space is a word boundary.

## QA Record (lane C, 2026-11-16; stage qa round 2, warm tag e0dw1421q2w)

No model, no key, no `.env` read; every `ci/` command went through the lane-C wrapper. Product code is unchanged; only test files and this record changed.

**Checked and already pinned (no test added).**
- The cut against the I/O matrix: 128 (row 1), 129 (row 2), a space at 128 (row 3, two forms), 300 of words (row 4, two forms), no boundary (row 5), a blank head (row 6), a surrogate pair at 127-128 (row 7), several (row 8), the other fields (row 9), 21 against 20 elements (rows 10, 11), non-strings including a 129-digit number (row 12), the model's `evidenceCut` (row 13), a dynamic object (row 14) and text that is not JSON (row 15), all in `Test.Watch.Payload` `TestEvidenceCut` with the implement stage's mutations.
- A reply naming `evidenceCut` is refused with "ERROR #9404: an unexpected property" before any cut (row 13; the guard mutation is recorded). `null` as its value is also refused (the guard tests "unassigned").
- The cut through `Recheck` writes nothing (`Test.Eval.Capture` `TestRecheckIsSilent`, `TestNothingIsWrittenAnywhere`) and no marker reaches the capture's CHK lines (`TestLinesHoldNoReplyText`, the cut seed of `SeedAll`).
- The catalog renders a `summary.evidence` value ending in U+2026 with no full stop on the three channels (`Test.Msg.Catalog` `TestSummaryFixFullStop`).

**Gaps closed.**
1. The closed-incident summary had no test that carried a cut reference from the payload to the rendered line. Each part was pinned on its own: the export, `Watch.Summary.Evidence`, and the catalog with a literal value. New `Test.Watch.Summary` `TestCutEvidence` covers the whole path. A partner_outage reply with "abcdefghi " x 30 goes through `DiagnosisPayload.%JSONImport` and `%JSONExportToString`, and the export is stored as the diagnosis Decision's Payload; the incident is dismissed. The stored slot is the cut (119 characters + U+2026). On the web, the phone and Telegram the line is exactly "Evidence: <cut>", and no full stop follows the cut anywhere.
   - mutation: `Msg/Catalog.cls` `SlotText` without `|| (last = $Char(8230))` -> Test.Watch.Summary TestCutEvidence red (web, phone, telegram: the line and the no-full-stop assertions).
2. The count could be logged by the conclusion and no test would see it. `TestEvidenceCutRecorded` looked only for log rows that held a marker or came from `%JSONImport`, and `Recheck`'s silence pins do not run `Conclude`. `TestEvidenceCutRecorded` now also asserts that the conclusion of the cut reply writes no `Ens_Util.Log` row of the test's job (event log or trace), and that the Decision row names `evidenceCut` once, in the Payload, and in neither the row's nor the response's Reasons.
   - mutation: `Decide.Conclude` logs `"evidence references cut: "_<the payload's evidenceCut>` through `Ens.Util.Log.LogInfo` (source `Conclude`) after setting `row.Payload` -> Test.Watch.Payload TestEvidenceCutRecorded red (the new assertion only; every pre-existing assertion stayed green).
3. The capture harness's count of `evidence-too-long` was pinned only through `RuleOf`/`FieldOf` called directly (`TestRuleNames`). Nothing pinned it through `Run`: the Recheck problem, `Parse`, the summary's rule counts and the reply's file. New `Test.Eval.Capture` `TestLengthTagCounted` seeds one invalid diagnose decision whose reply's second evidence element is a JSON number of 129 digits. The cut leaves it, since it is not a string, and the import refuses it for its length. `Run` gives exactly one rule entry, "evidence-too-long", field `evidence`, count 1. The file holds stage `check`, that rule and field, and the problem "The reply check failed: ... accepts: ERROR #7201 rule evidence-too-long". The CHK lines hold neither the marker nor the digits, and they name the rule.
   - mutation: `CaptureTool.RuleOf` back to the #5001 prefix only -> Test.Eval.Capture TestLengthTagCounted (the summary and the file) and TestRuleNames red.

Each mutation was applied to one file and run red on the warm stack. The file was then restored with `cp` from a copy taken before, and `cmp` showed it identical. `git status --short` and `git diff --stat` were the same as before each mutation.

**Runs (warm, final QA tree).** `OcuTalon.Test.Watch.Payload`, `OcuTalon.Test.Watch.Summary`, `OcuTalon.Test.Eval.Capture`, `OcuTalon.Test.Bridge.ReplyCheck` and `OcuTalon.Test.Bridge.Decide` passed. No added line holds a non-ASCII character or an absolute local path.

**Decision.** The record is kept here, as round 1's QA did, and not in `tests/test-summary.md`.
