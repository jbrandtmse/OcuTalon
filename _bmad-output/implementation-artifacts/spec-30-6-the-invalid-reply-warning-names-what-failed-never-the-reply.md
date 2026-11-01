---
title: 'The invalid-reply warning names what failed, never the reply'
type: 'bugfix'
created: '2026-10-31'
status: 'done'
baseline_revision: '97b4405e8a1f016e26251716fda39747dac5f23b'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** When `Decide` refuses a decide or diagnose reply as `invalid`, `Conclude` logs one trace warning whose text is IRIS's error text of the reply check (`Judge`: `GetErrorText`, or "After the reply filter ran: " plus its first 400 characters). That text can quote the model's own reply: `#7201`/`#7203`/`#7204` with `#5802` quote the value, a reply class's `%OnValidateObject` error quotes it ("The causeCategory '...' is not one of ..."), and `#9404` quotes an unknown field's name. On a local install that watches OcuTalon's own production, `Watch.Reader` can carry the event log into a later model request, so U-193 kept that corner only on the condition that the warning quotes no reply content (DW-498). Separately, `Test.Agent.KeyScan:123` (`x [ "a"_y`) can never fail, and no check rejects that form (DW-505).

**Approach:**
- `Judge` gets the original status of the check (a new trailing output of `CheckReply`, whose own status and text stay as they are).
- A new `Decide.RefusalText` builds the words of each error from its code, the reply class's own property name, the element position, the numeric limit and a computed length. It never uses a value, an IRIS message text or a field name taken from the reply.
- Both paths use it: the first check and the check after the reply filter.
- DW-505: parenthesise KeyScan:123, and add a class-rules check with one allow-listed Lane B line, whose fix the lead routes to Lane B.

## Boundaries & Constraints

**Always:**
- The warning stays one Type 3 warning per invalid reply, in the decision's trace session, through `Bridge.Redact.Text`, and starts "The reply check refused the reply of the decision <Ref>: " (AD-8, AD-26). Other fallbacks log none.
- A warning's text is made only of fixed words, the reply class name (the runner's `ReplyClass` setting at run time, AD-2), names of compiled properties of that reply class, element positions, numeric limits, computed lengths and error codes. It holds no value of the reply, not even redacted and not even in part. It also holds no IRIS message text and no JSON field name taken from the reply (U-193).
- `CheckReply`'s returned status and its text stay byte for byte as they are. They are pinned by `Test.Fix.Kind`, `Test.Fix.Validation`, `Test.Watch.Payload.AssertRefused` and `Test.Bridge.Decide`. Its existing 3-argument callers keep working.
- Every product-code change stays inside `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (the tests and the class-rules check change too). Bridge code names no other OcuTalon package (AD-2; `bridge-refs` checks it).
- Source text is ASCII (Rule 14). Comments state the contract.

**Never:**
- Never change the reply classes (`Bridge.Msg.DecisionPayload`, `Watch.Msg.DiagnosisPayload`) or their messages.
- Never change "No reason is left once the reply filter has run", `Conclude`'s warning line, or Story 30.1's DW-483 retry.
- Never edit Lane B files: `Test/Data/PublicSettings.cls`, `Test/Core/Observe.cls` (use it read-only) and `web/**`.
- No new test class, no new CI unit, and no `ci/units.sh` change. Never touch `.github/workflows/lane-a.yml`.
- Never run these tests on the slot: it is for load and compile only.

## I/O & Edge-Case Matrix

Notation:
- `P` is `OcuTalon.Test.Bridge.ProbeReplyCheck` (Note `MAXLEN` 100, `FILTERED` Note; Reasons `MAXLEN` 1000; Confidence 0 to 1).
- `D` is `OcuTalon.Watch.Msg.DiagnosisPayload`.
- `M` is a unique marker: "zzmark" plus `Bridge.Ids.NewRef()`. "No M" means the warning holds neither M nor any part of it.
- `W1(x)` is "The reply check refused the reply of the decision <Ref>: The reply check failed: the reply is not one JSON object that <class> accepts: " followed by x.
- `W2(x)` is "The reply check refused the reply of the decision <Ref>: After the reply filter ran: <class> refused the filtered payload: " followed by x.
- `ProbeFilter` puts "[f] " (4 characters) in front of each text it filters.
- Each warning is read back from `Ens_Util.Log` (`Test.Core.Observe.Warnings`).

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | First check: a text over its limit (AC 1) | P; note is M, padded to 105 characters | Exactly `W1("Note: 105 > 100")`. No M | -- |
| 2 | First check: a list element over its limit (AC 1) | P; reasons `["A reason.", M padded to 1,005]` | `W1("Reasons element 2: 1005 > 1000")`. No M | -- |
| 3 | First check: a value outside its limits (AC 1) | P; confidence 2, then confidence -3 | `W1("Confidence: value > 1")`, then `W1("Confidence: value < 0")`. The value itself never appears | -- |
| 4 | First check, diagnosis shape (AC 1) | D; `Test.Watch.Payload`'s Usable() plus a second evidence element of 129 characters | `W1("Evidence element 2: 129 > 128")`. Before, the pin was the lowercase field "evidence" | -- |
| 5 | After the filter: a text over its limit (AC 2) | P with `ProbeFilter`; note is M padded to 98 characters (the first check passes) | `W2("Note: 102 > 100")`. No M | -- |
| 6 | After the filter: several elements, and the cap (AC 2) | P with `ProbeFilter`; six reasons, each its own marker padded to 998 characters | `W2("Reasons element 1: 1002 > 1000; Reasons element 2: 1002 > 1000; Reasons element 3: 1002 > 1000; Reasons element 4: 1002 > 1000; Reasons element 5: 1002 > 1000; and 1 more")`. No marker | -- |
| 7 | Not one JSON object (AC 3) | P; the text M plus " is not JSON" | `W1("ERROR #5035")`. No M | -- |
| 8 | An unknown field (AC 3) | P; a usable reply plus a field named M | `W1("ERROR #9404")`. No M. Today the warning holds M | -- |
| 9 | The class's own check quotes a value (AC 3) | P; outcome M (32 characters at most). D; causeCategory a key-shaped value (Payload's "key in a refused value") | `W1("ERROR #5001")`. No M; neither the key nor "[redacted]" | -- |
| 10 | A value of the wrong type (AC 3) | P; reasons M (a string, not a list). P; confidence M | `W1("ERROR #9406 on Reasons")`; `W1("ERROR #7207 on Confidence")`. No M | -- |
| 11 | A check that throws (AC 3) | P; `^\|\|ZzProbeReplyCheck("throwAt")` 1 | `W1("ERROR #5035")`, without "The probe check throws" | -- |
| 12 | After the filter: the class's own check (AC 2, AC 3) | D; Payload's "invalid after the filter" (cause "No problems.", which ReplyGuard deletes) | `W2("ERROR #5001")` with class D | -- |
| 13 | Nothing left after the filter | Payload's "no reason left after the filter" | "No reason is left once the reply filter has run", as today | -- |
| 14 | Live, in the running production (outermost surface) | `Test.Watch.Diagnose`'s invalid-reply marker; the mock reply is `{"outcome":"maybe","reasons":"none","confidence":2}` | The one warning in the decision's trace session starts with the Ref and ends with "OcuTalon.Watch.Msg.DiagnosisPayload accepts: ERROR #9406 on Reasons" | -- |
| 15 | The forms (pure `RefusalText`, built statuses, class P) | (a) `#7201` (a value of 42 characters, limit 32) with an embedded `#5802` "P:Reasons(6)"; (b) `#7202` (2 characters, 3) with "P:Note"; (c) `#5659` "P:Outcome"; (d) a `#5802` naming a property that P lacks; (e) `#7201` with the limit "abc" and "P:Note"; (f) "<Ens>ErrGeneral" with M; (g) two equal `#5001`; (h) seven distinct errors; (i) `$$$OK` | (a) "Reasons element 6: 42 > 32"; (b) "Note: 2 < 3"; (c) "ERROR #5659 on Outcome"; (d) "ERROR #7201"; (e) "ERROR #7201 on Note"; (f) "ERROR <Ens>ErrGeneral", with no M; (g) "ERROR #5001" once; (h) five parts, then "; and 2 more"; (i) "an error" | -- |
| 16 | Unchanged behaviour | cut_off, refusal and an emptied turn; `CheckReply` called directly | No warning (`TestOtherFallbacksLogNothing`). One warning per invalid reply. `CheckReply`'s text is the same as today | -- |
| 17 | DW-505: KeyScan | `Test.Agent.KeyScan:123` | `text [ ("agent steps "_stepId)`: green as it is, red when the step id it expects is wrong | -- |
| 18 | DW-505: the class-rules check | Synthetic samples, then the `.cls` files of `src/` | Flags each sample that breaks the rule, at its assertion's first line, as file:line only. Flags none that keep it or only mention it in a comment. `src/` passes with KeyScan fixed and the one allow-list entry. An entry that matches no assertion fails as stale | -- |

</intent-contract>

## Code Map

Class paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/`, `docker/` or `ci/`.

**The bridge (`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`, Lane A)**
- `:1` `Include Ensemble` (gives `$$$ERROR`, `$$$ISERR`).
- `:40-52` class doc: the `CheckReply` and filter bullet.
- `:601-618` `CheckReply(text, replyClass, Output payload)`:
  - import `:609`, validate `:610`;
  - the catch `:612`, which gives `#5035` for an exception;
  - the wrapper at `:615` stays.
- `:623` `Unfenced`: reuse it for the `#9406` value lookup.
- `:775-798` Conclude doc; `:781-782` describe the warning.
- `:799` Conclude, `:816` `problem`, `:826` Interpret call.
- `:834` the warning line. It stays as it is.
- `:904-913` Interpret doc; `:911` describes `problem`.
- `:933-1005` Judge:
  - `:942-946` path 1 (`GetErrorText(checked)`);
  - `:955` no reason left (unchanged);
  - `:976-982` path 2 (`"After the reply filter ran: "_$Extract(GetErrorText, 1, 400)`).
- Precedent for `%Dictionary.Compiled*` reads in production jobs: `Bridge/Ext/Accessor.cls:81`, `Bridge/RequestSize.cls:23`.
- `Bridge/Msg/DecisionPayload.cls:19-32`: `%OnValidateObject` quotes the outcome (read only).

**Reply classes and doubles (read only)**
- `Watch/Msg/DiagnosisPayload.cls:51-82`: `%OnValidateObject`'s value-quoting errors; Evidence `MAXLEN` 128.
- `Test/Bridge/ProbeReplyCheck.cls`: Note `MAXLEN` 100, `FILTERED` Note, the throwAt global.
- `Test/Bridge/ProbeFilter.cls`: the "[f] " prefix, `^||ZzProbeFilter`.
- `Checks/ReplyGuard.cls:1-13`: it only deletes text and never lengthens it.

**Tests**
- `Test/Bridge/ReplyCheck.cls`:
  - `:1-10` doc;
  - `:20-37` OnBefore/OnAfterOneTest;
  - `:40-51` NewRequest, `:54-59` Reply;
  - `:62-65` Conclude helper (do-nothing filter, its own Ref);
  - `:116` TestBothChecksSeeTheRequest.
- `Test/Watch/Payload.cls`:
  - `:14-18` doc, `:32` REFUSED;
  - `:228-268` TestRefusalTrace, with the pins at `:251-262`;
  - `:270` TestOtherFallbacksLogNothing.
- `Test/Watch/Diagnose.cls`: `:19-20` doc ("holds the reply check's text"), `:285-288` the invalid-reply pin.
- `ci/mock/scenarios/A/invalid-reply.json`: the mock reply (read only).
- `Test/Core/Observe.cls:81` LastLog, `:89` Warnings, `:102` RemoveWarnings (Lane B: use only).
- 3-argument `CheckReply` callers, unchanged: `Test/Bridge/Decide.cls:3229`, `Test/Fix/Kind.cls:254`, `Test/Fix/Validation.cls:43`, `Test/Watch/Payload.cls:84`.
- `Test/Agent/KeyScan.cls:123` (method TestKeyIsStoredNowhere, `:43`). Find's form is "agent steps <ID>" (`:251`).

**The class-rules check (`docker/tests/test-class-rules.sh`)**
- `:1-24` header, one bullet per rule.
- `:38-43` ALLOW_UNCHECKED and SAMPLE_ALLOW.
- `:84-171` `unchecked_prepares`, the sibling to extend:
  - joined file text and `lineof`;
  - class and member tracking, comment lines blanked;
  - the Class:Method allow-list with `STALE`.
- `:205-231` `write_class`, `expect_flagged`, `expect_clean`.
- `:288-386` the unchecked-prepare block, with `name_stale` at `:291`.
- `:426-430` exit.
- `docker/tests/lib-scan.sh`: `scan_files`, `scan_rule`.
- `Test/Data/PublicSettings.cls:105` (Lane B, method TestNextReset `:91`): the one other hit.

## Tasks & Acceptance

**Execution:**
- [x] Task 0: no measurement is left. The platform facts were measured at planning (Design Notes). The fresh `Test.Watch.Diagnose` run confirms them in a production job.
- [x] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` (rows 1-16; DW-498):
  - `CheckReply` gains a trailing `Output cause As %Status`. It is the status of the import or the validation before it is wrapped (`$$$OK` when the reply passes). The returned status and its text are unchanged. Add a doc line.
  - New `ClassMethod RefusalText(cause As %Status, replyClass As %String, text As %String = "") As %String` gives the words of each error of `cause`, in DecomposeStatus order:
    - **Property and position.** They come from an embedded `#5802`, or from a `#5659`, whose first parameter is "<class>:<Property>" or "<class>:<Property>(<n>)". The name is used only when `%Dictionary.CompiledProperty` has it on `replyClass`.
    - **Length forms.** `#7201` and `#7202` with a property and a numeric limit (parameter 2) give "<Property>[ element <n>]: <length> > <limit>" (or `<`). The length is `$Length` of parameter 1.
    - **Value forms.** `#7203` and `#7204` give "<Property>[ element <n>]: value > <limit>" (or `<`).
    - **`#9406` (import).** The first parameter is a JSON field. Among `replyClass`'s compiled properties, the one whose `%JSONFIELDNAME` (else its name) equals it is checked against the reply's own value: `text`, through `Unfenced`, parsed as a `%DynamicObject`.
      - A list property whose value is an array: each element, in order, is checked with `$ClassMethod(replyClass, <Property>_"IsValid", element)`. An element that is an object or an array gives "ERROR #9406 on <Property> element <n>".
      - A scalar property whose value is not an object or an array: the value is checked the same way.
      - Each failing check gives its own part by the forms above, with that check's code and limit.
      - When no check fails, or the value has another shape, is missing, or the text is not an object, the part is "ERROR #9406 on <Property>". When the field names no compiled property, it is "ERROR #9406".
    - **The rest.** Any other error gives "ERROR #<code>" (or "ERROR <code>" for a code that is not a number), plus " on <Property>[ element <n>]" when a property is known.
    - **Joining.** Parts are distinct, joined by "; ", at most 5, then "; and <k> more". With no part, the text is "an error". It never throws: an exception inside gives "an error".
  - `Judge` path 1: `problem` = "The reply check failed: the reply is not one JSON object that "_replyClass_" accepts: "_`RefusalText(cause, replyClass, text)`.
  - `Judge` path 2: `problem` = "After the reply filter ran: "_replyClass_" refused the filtered payload: "_`RefusalText(checked, replyClass)`.
  - Update the docs of the class, Conclude, Interpret and Judge.
- [x] `Test/Bridge/ReplyCheck.cls`:
  - The Conclude helper gains a filter argument (default as today) and returns its Ref.
  - New helpers: Marker(), and Warning(ref, .text) through `Test.Core.Observe.Warnings(mark, .text, "Conclude", REFUSED_ref)`.
  - OnBeforeOneTest keeps the mark (`Test.Core.Observe.LastLog()`). OnBefore/OnAfterOneTest kill `^||ZzProbeFilter`, and OnAfterOneTest removes the REFUSED warnings after the mark, also after a failure.
  - New tests:
    - `TestRefusalNamesTheLimitNotTheReply` (rows 1, 2, 3, 5, 6);
    - `TestOtherRefusalsNameTheCode` (rows 7-11);
    - `TestRefusalTextForms` (row 15, on statuses built with `$SYSTEM.Status.Error`, `EmbedStatus` and `AppendStatus`).
  - Each Conclude case asserts the whole warning text, a count of 1 and "no marker". `TestRefusalTextForms` asserts the text `RefusalText` returns.
  - Update the doc (AC 1-4).
- [x] `Test/Watch/Payload.cls` TestRefusalTrace (rows 4, 9, 12, 13):
  - Pin the exact `W1`/`W2` text of each case.
  - "Over the limit" asserts "Evidence element 2: 129 > 128". It no longer asserts "evidence".
  - "Key in a refused value" asserts "ERROR #5001", with neither the key nor "[redacted]".
  - Update the doc `:14-18`.
- [x] `Test/Watch/Diagnose.cls:287` (row 14): also assert that the warning ends with "OcuTalon.Watch.Msg.DiagnosisPayload accepts: ERROR #9406 on Reasons". Update the doc `:19-20`.
- [x] `Test/Agent/KeyScan.cls:123` (row 17; DW-505): `Do $$$AssertTrue(text [ ("agent steps "_stepId), "Find sees an agent step: "_text)`.
- [x] `docker/tests/test-class-rules.sh` (row 18; DW-505; footprint extension):
  - A new rule `assert-concat`: in the first argument of `$$$AssertTrue(`, `$$$AssertNotTrue(`, `$$$AssertEquals(` and `$$$AssertNotEquals(`, no `_` at the top level to the right of a top-level `[`, `]` or `]]`, or their `'` forms.
  - "Top level" means outside string literals (`""` escapes), parentheses, braces and JSON-array brackets. A `[` is the operator when the significant character before it ends an operand (a letter, a digit, `)`, `}`, `"` or `'`); otherwise it opens an array. A `]` closes an array only when one is open.
  - It scans joined text, so an assertion that spans lines is named at its first line.
  - Comment lines are not code, as in `unchecked_prepares`.
  - `ALLOW_CONCAT="OcuTalon.Test.Data.PublicSettings:TestNextReset"`, as Class:Method with `STALE` and `name_stale`. A comment names Lane B's routed fix: once the line is fixed, the entry goes in the same change.
  - Samples:
    - **Flagged** (one line each): `text [ "agent steps "_stepId, "l: "_text`; `now ] $Translate(a, " ", "T")_"Z", "l"`; `x '[ "a"_y`; `x ]] "a"_y, 1`; `x '] "a" _ y, 0`; and a two-line one, named at its first line.
    - **Clean:** `text [ ("a"_y), "l: "_t`; `(x [ "a")_y`; `x_y [ z`; `x [ y, "l "_z`; `x [ y && (a_b = c)`; `[1,2].%ToJSON()_"", "[1,2]"`; `..F([1, 2]) [ "a"`; `x = "a [ b_c"`; `If x [ "a"_y Quit` (not an assertion); comment and doc lines; an allowed Class:Method.
    - A stale entry is reported.
  - Scan `scan_files src | grep '\.cls$'`. Add the header bullet.
- [x] Slot B: `iris_doc_load` and compile the changed classes (`server` `ocutalon-slot-b`, `namespace` `OCUTALON`, identity checked with `iris_server_info`), 0 errors.

**Acceptance Criteria:**
- Given a reply whose check fails on a length or datatype rule, when `Decide` refuses it as `invalid`, then its one trace warning names the failing property and the limit, with the measured length where it applies ("Evidence element 2: 129 > 128"). It is built from the error code, the reply class's own property and the limit, and quotes none of the reply (rows 1-4, 15; U-193, DW-498).
- Given a reply that fails its check again after the reply filter ran, when `Decide` refuses it, then the "After the reply filter ran" warning follows the same rule (rows 5, 6, 12).
- Given any other check failure (not one JSON object, an unknown field, a reply class's own error, a wrong JSON type, a check that throws), when the warning is written, then it names the error code and the reply class and quotes no reply content (rows 7-11).
- Given the tests in `OcuTalon.Test.Bridge`, when they run, then a refused reply whose failing value carries a unique marker gives a warning without the marker, on both paths. The live warning of the running production follows the rule (rows 1-14), and every product-code change is inside `Bridge/Process/Decide.cls`.
- Given `Test.Agent.KeyScan` and `docker/tests/test-class-rules.sh`, when they run, then KeyScan's step assertion can fail, and `assert-concat` flags the `x [ "a"_y` form everywhere in `src/` except the one allow-listed Lane B line (rows 17, 18; DW-505).

## Spec Change Log

## Review Triage Log

### 2026-10-31 - Review pass
- verdicts: 20 rows covering every finding of the four layers (grouped by root cause) - medium 2 (patched), low 18 (2 patched, 16 rejected as by-design, defensive or not worth the added state), high 0, false 0, maybe-false 0
- findings:
  - `[low]` `[patch]` Blind: the wrapper sentence is written twice (CheckReply, Judge), and a change of only the colon was pinned by no test - fixed: one Parameter CHECKFAILED feeds both, and ReplyCheck pins Judge's side to the same words.
  - `[low]` `[reject]` Blind: "an error" is shared by `$$$OK`, an empty decomposition and a caught exception - the spec fixes that text; the catch is defensive and unreachable from outside.
  - `[low]` `[reject]` Blind: a class's own #5001, #9404 and #5035 name no property - by design (rows 7-9; naming one would need a value-dependent rule).
  - `[low]` `[reject]` Blind: the key/[redacted] pin is gone - by design: row 9 pins that neither appears, and Conclude's Redact.Text call is unchanged.
  - `[low]` `[reject]` Blind and Edge: RefusalNumber accepts digits-first limits only - IRIS limits of the reply classes are such; any other form degrades to "ERROR #<code> on <Property>", which is safe; widening adds a pattern for no reachable case.
  - `[low]` `[reject]` Blind and Edge: assert-concat does not skip trailing comments, block comments or string literals holding an assertion token, and scans only `.cls` - only a false positive on rare text; `src/` passes; fix adds scanner state.
  - `[low]` `[reject]` Blind: the allow-listed Lane B line stays - by design (U-193 routing, DW-505 option ii); the stale check removes the entry with the fix.
  - `[low]` `[reject]` Blind: the Auto Run Result and the "reverted byte for byte" note - bookkeeping, written at finalize; each revert was checked with `git diff --stat`.
  - `[low]` `[reject]` Edge: RefusalProperty ignores the class part of "<class>:<Property>" - the name printed is the reply class's own compiled property; no reply content is reachable.
  - `[medium]` `[patch]` Edge: RefusalAdd compared every new part with all earlier ones, quadratic in a list of invalid elements - fixed: a subscript index (`parts("seen", part)`).
  - `[low]` `[reject]` Edge: a %JSONMAPPING or array-collection property degrades to the bare code - graceful, and no reply class uses either.
  - `[low]` `[reject]` Edge: other operators (=, <, >, &&) and nested positions are not flagged - by design (spec scope; `=`, `<`, `>` had no hit).
  - `[low]` `[reject]` Edge: the allow-list is per Class:Method - by design (the spec names Class:Method).
  - `[low]` `[reject]` Edge: no `.cls` file would make awk read stdin - `src/` always has them.
  - `[low]` `[reject]` Edge claims (two): the rule's reach and the property check - restate rows covered above.
  - `[medium]` `[patch]` Verification gap: RefusalImport's `Unfenced` was pinned by no test (a fenced reply) - fixed: a fenced row 1 case in TestRefusalNamesTheLimitNotTheReply, mutation recorded.
  - `[low]` `[patch]` Verification gap: the object or array list element form was pinned by no test - fixed: a row 10 case, mutation recorded.
  - `[low]` `[reject]` Verification gap: the catch-all "an error" path and the %JSONINCLUDE skip have no test - theoretical; ProbeReplyCheck has no such property and the catch is defensive.
  - `[low]` `[reject]` Verification gap: per-method allow-list, redundant marker assertions, row 14's dependence on the mock reply - by design or harmless.
  - `[low]` `[reject]` Intent alignment: seven descriptive items (readings A-E; no divergence found; the frozen CheckReply text is read by Judge no more) - descriptive only.

## Design Notes

**Architecture decisions (Rule 6).**
- AD-8: `Decide` alone decides `invalid`, and a fallback keeps no model text. The warning now keeps none either.
- AD-2: the reply class comes from the `ReplyClass` setting, and `Decide` names no OcuTalon package.
- AD-31: the reply filter and the redactor are the bridge's. `Redact.Text` stays around the warning.
- AD-26: the warning stays in the decision's trace session.
- AD-22: the tests run on throwaway stacks, with no new unit.
- AD-33: Lane B's `PublicSettings` line is routed to Lane B, not edited.
- No AD's Rule is contradicted.

**Measured at planning (slot B, `ocutalon-slot-b`, build 154U, port 52791; in-memory objects only, nothing saved or compiled).**
- **`%JSONImport` checks datatype parameters itself.** A value over its `MAXLEN`, outside `MINVAL`/`MAXVAL`, or of the wrong JSON type fails the import with `#9406`. Its parameters are only the JSON field and the mapping ("Unexpected format for value of field, evidence, using class base mapping"), with no value, no limit and no element.
  - The import walks the class's properties in order: the mock reply fails on `reasons` whatever the JSON order.
  - So the AC's limit and length on the first check come from the property's own generated `<Property>IsValid` check. For list properties it checks one element: `EvidenceIsValid` gives `#7201` with limit 128 and no `#5802`.
  - The DW-498 evidence (that `#7201` quotes the value on the first check) is right only for `%ValidateObject`. The first check's real leaks are `#5001` from a reply class's own check and `#9404`'s field name.
- **`%ValidateObject` gives `#7201`/`#7203`/`#7204`.** Parameter 1 is the value (in full: 142 of 142 characters) and parameter 2 the limit, with an embedded `#5802` whose parameter 1 is "Class:Property", or "Class:Property(n)" for a list element (1-based).
  - It lists every failing element, in order, and it adds `%OnValidateObject`'s `#5001` (which runs even when a property fails).
  - It does not validate nested objects: a 304-character `ItemNoun.One` passed although One has `MAXLEN` 128. ReplyGuard never lengthens text, so this is not reachable today (not this story's).
- **Other codes.**
  - Not JSON, or a JSON string: `#5035` "Parsing error".
  - A JSON array: `#9406` on `outcome`.
  - A `%OnValidateObject` that throws: `#5035`, whose Data parameter holds the exception text.
  - An unknown field: `#9404`, with the field's name.
- **Built statuses match.** `$SYSTEM.Status.Error(7201, v, 32)` with `EmbedStatus(..., Error(5802, "P:Reasons(6)", v))` and `AppendStatus` decompose like IRIS's own. An Ens code decomposes as "<Ens>ErrGeneral".
- **The DW-505 form.** A rough scan of `src/`'s `.cls` assertions found exactly two hits: KeyScan:123 and PublicSettings:105. Adding `=`, `<` and `>` still found only those two. `Test.Web.Splash`'s six are already fixed.

**Decided in-stage.**
- **How the status reaches `Judge`.** It comes through `CheckReply`'s new trailing `Output cause`, inside `Decide.cls`, as the epic context asks. The returned status is unchanged, so every pin of its text holds. Copying the import and validation into `Judge` was rejected (Rule 2).
- **Where names come from.** A property name is used only when it is compiled on the reply class, and a limit only when it is numeric. This makes "no reply content" provable: every piece of the text comes from code or from the class definition.
- **The forms.**
  - Lengths follow the AC's example: "Evidence element 6: 42 > 32".
  - A value limit withholds the value: "Confidence: value > 1".
  - Anything else is "ERROR #<code>", plus " on <Property>" when the property is known. The class is named by the sentence around it.
  - Path 2's sentence names the class: "<class> refused the filtered payload".
- **The cap.** At most 5 distinct parts, then "and <k> more". This replaces the 400-character cut.
- **The tests' home.** The marker pins go in `Test.Bridge.ReplyCheck`: `ProbeReplyCheck` and `ProbeFilter` reach both paths in-process (the AC asks for `OcuTalon.Test.Bridge`). `Test.Watch.Payload` keeps the diagnosis shapes. `Test.Watch.Diagnose` adds the live pin.
- **The rule's scope.**
  - It covers the operators DW-505 names (`[`, `]`, `]]` and their `'` forms) in the four comparing assertions.
  - `=`, `<` and `>` share the precedence trap but had no hit, so they stay out (smaller).
  - A non-assertion line is out of scope.
- **DW-505's Lane B line: option (ii).** `PublicSettings.cls:105` has the defect form, so option (i) would be dishonest. `now ] $Translate(...)_"Z"` evaluates as `(now ] T)_"Z"`: it compares against the time without "Z", so it also passes when `now` is that very second. The check carries one named allow-list entry, `OcuTalon.Test.Data.PublicSettings:TestNextReset`, and touches no Lane B file. The stale check makes the entry go when the line is fixed.

**For the lead (spec gate).**
- **Route to Lane B (Epic 31; the lead names the story, AD-33).** In `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls:105`, change it to `Do $$$AssertTrue(now ] ($Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T")_"Z"), "without now, the answer is in the future")`. In the same change, remove `OcuTalon.Test.Data.PublicSettings:TestNextReset` from `ALLOW_CONCAT` in `docker/tests/test-class-rules.sh`, or the stale check fails.
- **The warning's wording.** It is event-log (Visual Trace) text, not catalog or UI text, so (inference) it is not a public-text veto item. Classify it if you see it otherwise.
- **The AC's wording** "built from the status's error code, property and limit": on the first check the limit comes from the property's own check, because the import's `#9406` carries none (measured). The intent is unchanged. A Rule 5 tier-1 restatement is optional.

**Integration ACs (Rule 1).** No service, module or shared component is introduced: `RefusalText` is `Judge`'s helper. The consumer of its words is `Conclude`'s warning in `Ens_Util.Log`. That warning is read back in-process (`Test.Bridge.ReplyCheck`, `Test.Watch.Payload`) and from the running production's real Decide (`Test.Watch.Diagnose`, row 14).

**Consumed-by:**
- `Conclude`'s invalid-reply warning (Story 5.12).
- The event log that `Watch.Reader`'s evidence read may pass to a later model request (U-193).
- Story 30.1, if it builds DW-483's retry: its spec gate rules what check text that retry may carry.

**Consumes:**
- `Decide.CheckReply`, `Unfenced`, `Interpret` and `Conclude` (Stories 1.3, 5.12, 7.1).
- `%SYSTEM.Status.DecomposeStatus`, `%Dictionary.CompiledProperty` and the reply classes' generated `<Property>IsValid`.
- `Test.Core.Observe` (read only), and `ProbeReplyCheck` and `ProbeFilter`.

**Extend, don't copy (Rule 2).**
- **Decide.** `CheckReply` is extended with an output, not copied. `Unfenced` is reused. `Conclude`'s warning line is reused as it is.
- **The check.** The new scanner extends `unchecked_prepares`' machinery: the joined text and `lineof`, the class and member tracking, comment blanking, the Class:Method allow-list with `STALE`, and `name_stale`. Share that machinery between both rules, with the unchanged unchecked-prepare samples still passing, rather than copying it. Its own `parse_args` treats `[` as nesting, so the operator tokenizer is new.
- **The tests.** They extend `Test.Bridge.ReplyCheck`'s helpers and use `Test.Watch.Payload`'s fixtures.

**Ledger inbox (Rule 17).**
- DW-498: addressed (rows 1-16; the Decide task; the ReplyCheck, Payload and Diagnose tasks).
- DW-505: addressed (row 17, KeyScan; row 18, `assert-concat`). Its Lane B instance is routed above.

**Contended edits:** none.

**Files outside "Ours"** (`footprint_extensions`): `docker/tests/test-class-rules.sh`, which is not contended and is named by DW-505.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s6i` and the warm tag `e30s6iw`.

How to run:
- One command per tool call, in the foreground, with `timeout: 600000`. Never two IRIS test runs in one message.
- The harness moves a call to the background after about 180 s. Poll it in loops of under 170 s, and never start a second copy.

Where to run:
- **Throwaway stacks only.**
- **Warm** for the in-process classes.
- **Fresh** for `Test.Watch.Diagnose`: Decide is code of the running production, and a warm stack's job keeps its old code.
- **Slot B** for load and compile only.
- Tear down only your own tags, after a failure too.

**Commands:**
- (loop) `bash docker/tests/test-class-rules.sh`. Expected: `PASS assert-concat: …` and "all rules passed".
- (loop) `<lane> OCUTALON_RUN_TAG=e30s6iw ci/warm.sh up`, once. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s6iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Bridge.ReplyCheck`
  - `OcuTalon.Test.Watch.Payload`
  - `OcuTalon.Test.Agent.KeyScan`
  - `OcuTalon.Test.Bridge.Decide`
  - `OcuTalon.Test.Fix.Kind`
  - `OcuTalon.Test.Fix.Validation`
- (loop) `<lane> OCUTALON_RUN_TAG=e30s6i ci/iris.sh class OcuTalon.Test.Watch.Diagnose`, fresh (about 45 s plus the stack). Expected: passed.
- (once) `bash ci/checks.sh`. Expected: every script passes.
- (once) `<lane> OCUTALON_RUN_TAG=e30s6i ci/iris.sh shard lane-a --part k/6` for k = 1 to 6, fresh, one call each. Expected: passed, with each part's time recorded.
- (once) `<lane> OCUTALON_RUN_TAG=e30s6i ci/iris.sh shard lane-b --part k/3` for k = 1 to 3, fresh, one call each. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e30s6iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s6i ci/iris.sh teardown`, also after a failure.

**Shared surfaces:**
- **The invalid-reply warning's text:**
  - `Test.Watch.Payload.TestRefusalTrace` (re-pinned);
  - `Test.Watch.Diagnose.TestDiagnosisVariants` (its old assertion still holds, and one is added);
  - `TestOtherFallbacksLogNothing` (count 0, unaffected).
  - A search found no other test pinning IRIS's error texts.
- **`CheckReply`'s signature** (+1 trailing output): its four 3-argument callers are unchanged.
- **`test-class-rules.sh`'s rule list** (+1 PASS line): no script counts its lines.
- **CI time:** no new unit. The added methods run in `shards-2` (Bridge, Agent) and `shards` (Watch). Expect +5 s or less (inference).
- Every test added or changed passes on a fresh environment, in either order. Each test removes its Decision rows and its REFUSED warnings, and kills `^||ZzProbeFilter` and `^||ZzProbeReplyCheck`, also after a failure.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, and revert byte for byte (`git status --short` and `git diff --stat` unchanged). Record each as `mutation: … → …` here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1, AC 3, rows 8, 9 | Judge path 1 keeps `GetErrorText(checked)` | ReplyCheck rows 8 and 9 (M appears); Payload row 9 ([redacted]); Diagnose row 14 (fresh) |
| AC 2, rows 5, 6 | Judge path 2 keeps `GetErrorText(checked)` | ReplyCheck rows 5 and 6 (M appears: `#7201` quotes the value) |
| AC 1, row 5 | The length part prints parameter 1 instead of its `$Length` | ReplyCheck row 5 (M appears) |
| AC 1, rows 1-3 | The `#9406` lookup dropped (always "ERROR #9406 on <Property>") | ReplyCheck rows 1, 2 and 3; Payload row 4 |
| Rows 2, 6, 15a | The element position dropped | ReplyCheck rows 2, 6 and 15a |
| Row 15d | The compiled-property check dropped | ReplyCheck row 15d |
| Row 6, 15h | The cap removed | ReplyCheck rows 6 and 15h |
| AC 3, row 10 | The IsValid code ignored (always 9406) | ReplyCheck row 10 (Confidence) |
| Row 16 | `CheckReply`'s wrapper text changed | `Test.Fix.Kind`, `Payload.AssertRefused` |
| AC 5, row 17 | KeyScan's expected id made wrong (`stepId + 1`) | KeyScan TestKeyIsStoredNowhere |
| AC 5, row 18 | KeyScan:123 put back as it was; the allow-list entry removed; a stale entry added | `assert-concat` FAIL naming each file:line, or the stale entry |

Mutation results (Rule 19; each applied, observed red, reverted byte for byte; the warm class was green again after each revert):
- mutation: Judge path 1 keeps `GetErrorText(checked)` -> `Test.Bridge.ReplyCheck` TestOtherRefusalsNameTheCode rows 7-11 and TestRefusalNamesTheLimitNotTheReply rows 1-3 (the marker appears in rows 8 and 9); `Test.Watch.Payload` TestRefusalTrace over-the-limit and key-in-a-refused-value (the key case now holds "[redacted]"); `Test.Watch.Diagnose` (fresh) TestDiagnosisVariants "it ends with what the check refused".
- mutation: Judge path 2 keeps `GetErrorText(checked)` (first 400 characters) -> `Test.Bridge.ReplyCheck` TestRefusalNamesTheLimitNotTheReply rows 5 and 6 (the marker appears).
- mutation: the length part prints parameter 1 instead of its `$Length` -> `Test.Bridge.ReplyCheck` TestRefusalNamesTheLimitNotTheReply rows 1, 2, 5 and 6 (the marker appears).
- mutation: the `#9406` lookup dropped (`If 0 && ...` in RefusalImport) -> `Test.Bridge.ReplyCheck` TestRefusalNamesTheLimitNotTheReply rows 1, 2 and 3 and TestOtherRefusalsNameTheCode row 10 (Confidence); `Test.Watch.Payload` TestRefusalTrace over-the-limit.
- mutation: the element position dropped -> `Test.Bridge.ReplyCheck` TestRefusalNamesTheLimitNotTheReply rows 2 and 6 and TestRefusalTextForms a.
- mutation: the compiled-property check dropped -> `Test.Bridge.ReplyCheck` TestRefusalTextForms d.
- mutation: the cap removed (MAXREFUSALPARTS 999) -> `Test.Bridge.ReplyCheck` TestRefusalNamesTheLimitNotTheReply row 6 and TestRefusalTextForms h.
- mutation: the IsValid code ignored (RefusalCheck always adds nothing, so "ERROR #9406 on <Property>") -> `Test.Bridge.ReplyCheck` TestRefusalNamesTheLimitNotTheReply rows 1, 2 and 3 and TestOtherRefusalsNameTheCode row 10 (Confidence).
- mutation: `CheckReply`'s wrapper text changed ("The reply check failed" to "The reply check fails") -> `Test.Fix.Kind` TestReplyCheckRows and `Test.Watch.Payload` TestPayloadRefused (a change of only the colon after "failed" is not pinned by any test: the pins match "The reply check failed").
- mutation: KeyScan's expected id made wrong (`stepId + 1`) -> `Test.Agent.KeyScan` TestKeyIsStoredNowhere ("Find sees an agent step").
- mutation: KeyScan:123 put back as `text [ "agent steps "_stepId` -> `assert-concat` FAIL at `src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls:123`; the allow-list entry removed -> FAIL at `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls:105`; a stale entry added -> FAIL "stale allow-list entry" at the entry's line in `docker/tests/test-class-rules.sh`.
- mutation: `RefusalImport` reads the reply text without `Unfenced` (a fenced reply) -> `Test.Bridge.ReplyCheck` TestRefusalNamesTheLimitNotTheReply "row 1: a text over its limit in a Markdown code fence".
- mutation: the object-or-array list element line of `RefusalImport` dropped -> `Test.Bridge.ReplyCheck` TestOtherRefusalsNameTheCode "row 10: an object for a list element".

## Auto Run Result

Status: done
Blocking condition: none

- Summary: an invalid decide or diagnose reply now gets a trace warning built by the new `Decide.RefusalText` from the error code, the reply class's own property, the element position, the numeric limit and a computed length; no value, IRIS message text or reply field name. `CheckReply` gained a trailing `Output cause`; its returned status and text are unchanged, and its wrapper words are now one Parameter (`CHECKFAILED`) shared with `Judge`. DW-505: `Test.Agent.KeyScan:123` parenthesised, and the `assert-concat` class-rules check added with one allow-listed Lane B line (`Test.Data.PublicSettings:TestNextReset`; routing in Design Notes).
- Files changed:
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `CheckReply` cause output, `RefusalText` and helpers, `Judge` on both paths, docs.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/ReplyCheck.cls`: three new tests, helpers, a fenced-reply case and an object-element case.
  - `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls`: exact warning text per case.
  - `src/ocutalon/cls/OcuTalon/Test/Watch/Diagnose.cls`: the live warning's ending.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls`: line 123.
  - `docker/tests/test-class-rules.sh`: `assert-concat` (footprint extension, not contended).
- Review: 4 layers; patches applied 4 (2 medium: the quadratic part de-duplication, the unpinned `Unfenced` call; 2 low: the shared wrapper Parameter, the object list element case); deferred 0; rejected 16 low as by-design, defensive or not worth the added state (reasons in the Review Triage Log).
- Follow-up review recommended: false (the two patched mediums are covered by a recorded mutation each and by the green full shards).
- Verification: `test-class-rules.sh` green; slot B load and compile 0 errors; warm `Test.Bridge.ReplyCheck`, `Test.Watch.Payload`, `Test.Agent.KeyScan`, `Test.Bridge.Decide`, `Test.Fix.Kind`, `Test.Fix.Validation` passed; fresh `Test.Watch.Diagnose` passed; `bash ci/checks.sh` passed; fresh `shard lane-a` parts 1-6 and `shard lane-b` parts 1-3 passed (lane-a: 514, 230, 248, 577, 401, 482 s; lane-b: 888, 228, 465 s). Both throwaway tags torn down.
- Residual risks: `assert-concat` ran on macOS awk only; the Lane B line stays allow-listed until Epic 31 fixes it and removes the entry in the same change.
