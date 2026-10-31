---
title: 'A correct diagnosis is never refused for an over-long evidence reference'
type: 'bugfix'
created: '2026-10-31'
status: 'done'
baseline_revision: '77c9f8f3ff4f6ff6fcad26fead96bfdd5ff2e934'
baseline_commit: '77c9f8f3ff4f6ff6fcad26fead96bfdd5ff2e934'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** On the online demo host, correct diagnoses fell back as `invalid` (1 in 6 in the load run, later 2 in 10) because one model-written evidence reference was longer than the 32 characters `DiagnosisPayload.Evidence` allows. The visitor got the fallback notice with no fix and could not finish the demo path, and the trace did not say why the reply was refused.

**Approach:** Widen each evidence reference to 128 characters and make the diagnosis prompt state the same limit. Prove it by replaying both recorded host replies through Decide. When Decide records an `invalid` fallback for a decide or diagnose reply, it also logs the check's own error text, through the redactor, as one warning in that decision's trace session. Nothing a user, a notice or the model reads carries that text.

## Boundaries & Constraints

**Always:**
- Touch only the payload class, the diagnosis prompt, Decide's invalid-path lines, their tests and the fixtures.
- In `Decide.cls`, change only the lines this spec names: no refactor, no reformat, no moved code. Epic 30 (unmerged) also changes `Decide.cls` and integrates this change later. Its hunks are the insertion after L747, `RecordFallback`'s doc L877-879, its signature L887 and L895, and parameters after L123. Leave all of these alone.
- The trace text passes through `OcuTalon.Bridge.Redact.Text`, and the bridge code names only `OcuTalon.Bridge.*` classes (AD-2).
- Copy each fixture byte for byte from `epics.md`. The bytes check below must print `exact` for both.
- Tests are self-contained: they remove the Decision rows and warnings they make.

**Never:**
- A retry on `invalid` (Epic 30's follow-up), or any change to the fallback reasons, `Classify`, `CheckReply` or `RecordFallback`.
- A new property or column on a message, a row or a payload class (no schema change), or a new test unit or `ci/units.sh` entry.
- Editing Lane B's classes (`Live/Payload/Part/ItemNoun.cls` included), `Test/Watch/Case.cls`, `Test/Watch/Reader.cls`, any `Test/Bridge/*` class that Epic 30 changed, `ci/mock/**` or `eval/**`.
- A real model key. Every model call in tests goes to the mock.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Host reply 11:45:50Z | Fixture 1 as the reply text of a diagnose request whose input is the Orders pack; `Decide.Conclude` with `DiagnosisPayload` and the production's filter `OcuTalon.Checks.ReplyGuard` | No fallback. The Decision row has `Fallback` 0. The answer's payload holds the fixture's six evidence references (the 42-character one intact), cause, category, element, fix kind, fix parameters, fix summary and noun | No error expected |
| Host reply 12:01:54Z | Fixture 2, the same way | The same, with five references (the 33-character first one intact) | No error expected |
| Boundary | `Usable()` with one 128-character reference | `CheckReply` OK | No error expected |
| Over the limit | `Usable()` with one 129-character reference | `CheckReply` refused ("The reply check failed"). `Conclude` gives fallback `invalid` | One warning: head + Ref + the check's text, naming the field `evidence` |
| Key in a refused value | `Usable()` with `causeCategory` = `"sk-ant-"` + 17 `x`, built at run time | Fallback `invalid` | The warning holds `[redacted]` and not the fake key |
| Invalid in the production | Mock `invalid-reply` (`Test.Watch.Diagnose`) | Incident fallback `invalid`, with the `incident.fallback` notice as before | One Type 3 warning of `Decide.Conclude` with `SessionId` = the decision's `TraceSessionId`, naming the reply check. The notice's slots hold none of it |
| Other fallbacks | Mock `refusal`, a turn with no text left, `cut_off` | Fallback as before | No warning |

</intent-contract>

## Code Map

Paths are under `src/` unless they start with `_bmad-output/`.

- `ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls` (Lane A):
  - the class doc's evidence bullet, L4;
  - `MAXEVIDENCE` 20, L31-32;
  - **`Evidence` MAXLEN 32, L40-41: the fix**;
  - kept: `CauseCategory` 32 (L35), `ElementAtFault` 128 (L38), `FixKind` 32 (L44), `Cause` and `FixSummary` 1000 (L50, L53);
  - `%OnValidateObject` L59-87.
- `ocutalon/cls/OcuTalon/Agent/Diagnosis.cls`:
  - L33 asks for "at most 20 short references" (keep it);
  - **L41: the lengths sentence, which says 32 for `evidence`**.
- Read-only for the audit:
  - `Watch/Msg/FixParameters.cls`: L7 `Field` 128; L10 and L13 the formats, 64 each.
  - `Live/Payload/Part/ItemNoun.cls`: L6 and L9, 128 each (Lane B).
  - `bridge/.../Msg/DecisionPayload.cls`: L9 `Outcome` 32; L12 `Reasons` 1000 each.
  - `Agent/Triage.cls`: its prompt states no length.
  - `Agent/Chat.cls`: its prompt states no length, and `ChatAgent` has no `ReplyClass` (`OcuTalon.Production` L26, L30).
  - Turn text: `Msg.Reply.Text`, `Data.Turn.ReplyText` and `Eval.Msg.TurnResult.ReplyText` all have MAXLEN "".
  - `Msg/Command/SetReminder.cls`: `Text` 1000.
  - `Msg/Command/CancelReminder.cls` and `Dismiss.cls`: refs, 22 each.
- `bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `CheckReply` L545-560 (read-only): it wraps the error as "The reply check failed: the reply is not one JSON object that <class> accepts: " plus the first 400 characters of the error.
  - `Conclude` doc L716-738 (item 2 is L721) and `Conclude` L739-798:
    - the result variables are set at L750-754;
    - `Interpret` is called at L764;
    - `Classify` and the fallback block are L770-773.
  - `Interpret` doc L800-808, signature L809, start L811-815, `Judge` call L818.
  - `Judge` doc L827, signature L828, start L830-834. Its three `Quit 0` exits are:
    - `CheckReply` failed, L835;
    - no reason is left, L843;
    - re-validation failed, L863.
  - The existing redacted warnings, the pattern to follow: L430, L472, L604.
- Sibling of the warning (Rule 2): `ocutalon/.../Watch/IncidentManager.cls` `Refused` L728-731, "one Type 3 warning with the error (through the redactor)".
- Read-only evidence that the text stays internal:
  - `IncidentManager.cls` L699-722 reads only `Fallback`, `FallbackReason` and the payload's cause, category, element, fix summary, fix kind, fix parameters and noun. It never reads evidence or the event log.
  - `Watch/Reader.cls`:
    - `Failures` reads Type 2 and 6 rows that have no session (L293, L300);
    - `Evidence` reads the event-log rows of the failures' sessions (L424).
  - `Core/Trace.cls` L182 counts a session's log rows and reads no `Text`.
- Tests:
  - `ocutalon/.../Test/Watch/Payload.cls`:
    - doc L1-12; hooks L20-34 (a ReplyCheck is begun for each test);
    - helpers `Pack`, `Usable`, `Outage` and `Check` (= `Decide.CheckReply`), L37-58;
    - `TestPayloadAccepted` L60, `TestPayloadRefused` L76, `AssertRefused` L128.
  - `Test/Watch/Diagnose.cls`:
    - doc L17-22;
    - `TestDiagnosisVariants` L220-285: the fallback branch L262-268, the real order's notice L276-284.
  - `Test/Agent/Instructions.cls`: doc L1-28, `TestDiagnosis` L119-127, `Instructions()` L248.
  - Epic 30 changed none of these three.
- Reuse:
  - `Test/Core/Observe.cls`: `LastLog` L81, `Warnings(mark, .text, method, start)` L89, `RemoveWarnings` L102;
  - `Test/Agent/RunnerFixture.cls`: `DecisionOf(itemId, kind)` L315;
  - the Conclude wrappers `Test/Fix/Kind.cls` L339-344 and `Test/Bridge/ReplyCheck.cls` L62-65, with the `ItemIds` clean-up beside them;
  - the fake-key form at `Test/Tools/Reminders.cls` L639.
- Fixtures: `_bmad-output/planning-artifacts/epics.md` L2842 and L2847. They are the only lines of that file that start with a backtick followed by `{"outcome"`. Both are ASCII, 1014 and 948 characters.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - `Evidence` MAXLEN 32 → 128;
  - the property doc and the class doc's evidence bullet say "each at most 128 characters". Nothing else.
- `src/ocutalon/cls/OcuTalon/Agent/Diagnosis.cls` L41: "each "evidence" reference at most 32 characters" → "at most 128 characters". Nothing else; L33 still asks for short references.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `Judge`:
    - add `Output problem As %String` as the last parameter, set to "" at the start;
    - at L835, keep `CheckReply`'s status and, when it is an error, set `problem` to its `$SYSTEM.Status.GetErrorText`;
    - at L843, `problem` = "No reason is left once the reply filter has run";
    - at L863, `problem` = "After the reply filter ran: " plus the first 400 characters of the re-validation's error text.
  - `Interpret`: add the same last Output parameter, set to "" at the start, and pass it to `Judge`.
  - `Conclude`:
    - add `Set problem = ""` beside `Set json = ""`;
    - pass `.problem` as `Interpret`'s last argument;
    - make the first line inside `If reason '= "" {` (before `RecordFallback`): `If (reason = "invalid") && (problem '= "") $$$LOGWARNING(##class(OcuTalon.Bridge.Redact).Text("The reply check refused the reply of the decision "_decisionRef_": "_problem))`.
  - Docs: one clause in `Conclude`'s item 2 and one in `Interpret`'s doc (what `problem` is, and that only an `invalid` decide or diagnose fallback logs it, as a warning in the decision's session).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls`:
  - **Fixtures.** Two XData blocks, `Reply114550` and `Reply120154` (`MimeType = application/json`). Each holds its fixture as one unindented line. A private reader returns the block's text with only the surrounding white space and line ends removed.
  - **`TestHostReplies`.** Each fixture through `Decide.Conclude` (row 1 or 2 of the matrix) must give:
    - `response.Fallback` 0 and `FallbackReason` "";
    - `DecisionOf(itemId, "diagnose").Fallback` 0;
    - the answer's payload, whose `evidence` array and cause, fix kind, fix parameters and fix summary equal the fixture's.
  - **The boundaries.** `TestPayloadAccepted` gains the 128-character reference; `TestPayloadRefused` gains the 129-character one (through `AssertRefused`).
  - **`TestRefusalTrace`** (rows 4 and 5):
    - take `mark` = `Observe.LastLog()` first;
    - for each reply, assert fallback `invalid`, and empty `Reasons` and `Payload` on both the row and the response;
    - assert `Observe.Warnings(mark, .text, "Conclude", "The reply check refused the reply of the decision "_ref)` is 1, and that `text` holds what the matrix row says: "The reply check failed" and `evidence`, or `[redacted]` and not the fake key;
    - remove the warnings in the test's clean-up.
  - **`Conclude` ends the test's ReplyCheck** (`Interpret` begins and ends its own). So a test that calls `Conclude` calls no `..Check` after it.
  - **Helpers.**
    - `NewRequest`: diagnose, provenance untrusted, a fresh `ItemId` kept in `ItemIds`, input `EvidencePack.Input(..Pack())`.
    - A Conclude wrapper with `DiagnosisPayload`, `OcuTalon.Checks.ReplyGuard` and `OcuTalon.Bridge.Ext.HostSink`, which returns the `decisionRef` it passed.
    - `OnAfterOneTest` deletes the Decision rows of `ItemIds`.
  - **The class doc.** Each new test, and that `Conclude` records rows and warnings which the tests remove.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Diagnose.cls`, in `TestDiagnosisVariants`:
  - for the `invalid-reply` marker, assert one Type 3 warning with `SourceClass` `OcuTalon.Bridge.Process.Decide` and `SourceMethod` `Conclude` in `decision.TraceSessionId`. Its text starts with the head and the decision's Ref and holds "The reply check failed";
  - for `refusal`, assert none;
  - for the real order's notice, assert that its slots JSON holds no "reply check";
  - `DropIncidentRows` already deletes those session rows;
  - update the bullet in the doc.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls`:
  - add `TestDiagnosisLengths`. Diagnosis's prompt holds L41's sentence, built from the compiled MAXLENs: `Evidence`; `ElementAtFault` = `FixParameters.Field` = `ItemNoun.One` = `ItemNoun.Other`; `SourceFormat` = `TargetFormat`; `Cause` = `FixSummary` = `DecisionPayload.Reasons`. Assert each equality. The prompt also holds "at most "_MAXEVIDENCE_" short references";
  - add the method to the doc.

**Acceptance Criteria:**
- **AC1.** Given either recorded host reply, when `Decide.Conclude` checks it against `DiagnosisPayload` with the production's filter, then:
  - it passes and no fallback is recorded;
  - the answer carries the fixture's cause and fix (the members IncidentManager turns into the with-fix notice);
  - `Test.Watch.Diagnose.TestDemoDiagnosis` (with-fix notice, dry run and approval request) stays green, unchanged;
  - `Evidence` accepts 128 characters and refuses 129;
  - the prompt states 128, and the class agrees.
- **AC2.** Given every reply class and prompt the model answers, when the audit (Design Notes) runs, then:
  - every length a prompt states equals its class (`TestDiagnosisLengths`);
  - no model-written free-text property is capped at 32 or fewer outside the fixed value lists.
- **AC3.** Given a decide or diagnose reply that fails its check, when Decide records the `invalid` fallback, then:
  - the decision's trace session holds one redacted Type 3 warning with the check's own error text;
  - the Decision row, the answer and the notice carry none of it.
- **AC4.** Given the change, when it merges, then:
  - CI is green on every workflow;
  - `Test.Eval.Run` passes with no Eval file changed;
  - the diff touches only the files above.

### Review Findings

Code review, 2026-10-31. Full tier: Blind Hunter, Edge Case Hunter, Verification Gap and Acceptance Auditor. 28 rows grouped into 7 entries: high 0, medium 1, low 6. Verdict: done.

Rule checks:
- AD-2, 6, 7, 8, 22, 26 and 31: the implementation matches each Rule.
- Rule 3: `Test.Watch.Diagnose` runs a real production on a throwaway with the mock.
- Rules 1 and 5: not applicable.
- Rule 14: no non-ASCII byte in the source.

Verification of the patches:
- `Test.Watch.Diagnose` passed on a fresh stack (`e5s12r`).
- `Test.Watch.Payload` passed on a warm stack (`e5s12rw`).
- `bash ci/checks.sh` passed all 19 scripts.
- Teardown done; the lane-b lock folder is empty.

- [x] [Review][Patch] `TestDiagnosisVariants` left its `Decide.Conclude` warnings behind, against the Always rule ("they remove the Decision rows and warnings they make") and Rule 19 (medium; fix-risk low: test only, with the existing helper) [src/ocutalon/cls/OcuTalon/Test/Watch/Diagnose.cls:55]
  - `Case.DropIncidentRows` deletes no event-log rows. So the task's line "`DropIncidentRows` already deletes those session rows", and the implement triage's rejection that relied on it, were wrong.
  - Fix: the test now sets `WarningMark` first, and `OnAfterOneTest` removes the `REFUSED` warnings logged after it through `Observe.RemoveWarnings`. That covers both the `invalid-reply` warning and the real order's.
- [x] [Review][Patch] The fixture reader kept the XData line end: `"<>W"` strips neither CR nor LF, against its own doc and the task. Now `"<>WC"` (low) [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls:116]
- [x] [Review][Patch] The test docs misdescribed the new tests (low) [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls:14]
  - Payload's class doc said the tests need "no namespace".
  - The `TestRefusalTrace` bullet named neither filter exit nor its text.
  - Both classes said the warning "starts with the decision's Ref". It starts with REFUSED, and the Ref follows.
- [x] [Review][Patch] `Interpret`'s doc named only two of `problem`'s three forms. It now also names the post-filter form and its 400-character cut. This is a line the story added, outside Epic 30's hunks (low) [src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls:810]
- [x] [Review][Patch] AC1's clause "the answer carries the fixture's cause and fix" had never been seen red. Under the only recorded mutation (MAXLEN 32) the reply falls back, so the field loop is skipped. A mutation was applied and recorded under `## Verification` (low, Rule 19) [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls:202]
- [x] [Review][Defer] AC2's floor has no regression test. A future model-written property at MAXLEN 32 or less, or a whole length group narrowed together with the prompt, would pass CI. AC2's pinning test and its mutations hold for this change; the guard would be about 15 lines of property-path walking, more than this hotfix needs (low) [src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls:133] — deferred: closed `wontfix-accepted`, DW-492 (reopen_if in the ledger)
- [x] [Review][Defer] Rule 2: `Diagnose.DecideWarnings` repeats the loop of `Observe.Warnings`, adding a session filter that `Observe` cannot take. Extending `Observe` (Test/Core) is outside the footprint (low) [src/ocutalon/cls/OcuTalon/Test/Watch/Diagnose.cls:312] — deferred: closed `wontfix-accepted`, DW-493 (reopen_if in the ledger)

Corrections to the record (the sections above are kept as written):
- QA's `TestOtherFallbacksLogNothing` closes the "Residual risks" line and the implement triage's two turn and `cut_off` rejections.
- The implement stage recorded nine mutations, not eleven. The two `(QA)` lines are QA's.
- The lead's `dev_complete` line in `cycle-log-epic-5.md` reads `loc_added=232 13 6 loc_removed= files=`; it should read `loc_added=232 loc_removed=13 files=6`.

**Rejected:**
- `[low]` The cycle log's `dev_complete` fields are malformed. Real, but the line is the lead's and this stage may not write it; handed to the lead.
- `[low]` "Eleven mutations" against nine implement lines; the "Residual risks" line and triage rows went stale after QA; QA's record sits inside the implement blocks; triage row 20's label does not match its text. Each fix edits the spec under review; the facts are corrected above.
- `[by-design]` The warning head says "refused" for "no reason left": the head is the spec's exact line.
- `[by-design]` The warning is logged before `RecordFallback`, so a duplicate item and kind could name a Ref that has no row. The spec puts the line first, before `RecordFallback`, and forbids changing `RecordFallback`.
- `[by-design]` `Redact.Text` wraps the head and the Ref, so the Ref is lost on a fail-closed `UNCHECKED`, or on a base64url Ref that starts with `sk-` (about 1 in 100,000). This is the spec's exact line, and failing closed is the redactor's contract.
- `[by-design]` The 400-character cut runs before redaction. This is the spec's order, the same as `CheckReply`'s own cut. The trace already holds the unfiltered `Reply` body, and a key prefix shorter than the pattern is not a credential.
- `[by-design]` `TestDemoDiagnosis` sends no reference over 32 characters: the lead's spec-gate ruling (AC1's notice is pinned at Decide's answer; no new mock scenario).
- `[false]` A missing fixture makes `%FromJSON("")` throw before the second reply. The test is red either way, and its first assertion names the cause.
- `[false]` `$$$LOGWARNING` writes `$$$JobSessionId`, not `traceSessionId`. In production, Conclude's caller is `OnResponse` with `..%SessionId`, and the fresh Diagnose run finds the warning in `decision.TraceSessionId`. The unit tests filter by mark.
- `[false]` The AC2 audit leaves out `SetReminder.LocalDueAt` (MAXLEN 19). It is a fixed 19-character format, not free text, so AC2 holds; completing the table would be a spec edit.

## Spec Change Log

## Review Triage Log

### 2026-10-31 - Review pass
- verdicts: 23 findings - high 0, medium 0, low 13, false 10, maybe-false 0
- findings:
  - `[low]` `patch` Blind Hunter: `TestHostReplies` skips the field comparison silently when the payload is empty - added an assertion that the answer holds a payload before the `Continue` (patched).
  - `[low]` `patch` Blind Hunter / Verification Gap: `Judge`'s two later `problem` exits (no reason left; invalid after the filter) have no test - `TestRefusalTrace` gained two replies run through `ReplyGuard` (a reason "No issues." and a cause "No problems."), each asserting one warning with its text (patched; mutation recorded).
  - `[false]` `reject` Blind Hunter: the notice check only looks for "reply check" - the spec fixes this assertion (slots hold no "reply check"); the mutation on `Notice.cls` shows it fails when the text leaks.
  - `[false]` `reject` Blind Hunter: prompt/class agreement is pinned only for Diagnosis - the AC2 audit table shows Triage and Chat state no length; `TestDiagnosisLengths` is the spec's test.
  - `[false]` `reject` Blind Hunter: `Diagnose` leaves its warnings - the spec's `DropIncidentRows` already deletes that session's rows.
  - `[false]` `reject` Blind Hunter: "host sink" is mislabelled - the spec names `OcuTalon.Bridge.Ext.HostSink`; the doc says what class is passed.
  - `[low]` `reject` Edge Case Hunter: the error text is cut to 400 characters before redaction, so a key could straddle the cut - the 400 cut is CheckReply's own and the spec's; a partial prefix shorter than the key pattern is not a credential; the fix would reorder the spec's contract.
  - `[false]` `reject` Edge Case Hunter: other fallback reasons (cut_off, refusal) log nothing - this is the spec's decision (Design Notes, "Only an invalid fallback logs") and the matrix row "Other fallbacks".
  - `[low]` `patch` Edge Case Hunter: a missing Decision row passes as "no fallback" - the assertion now reads "no row" when `DecisionOf` returns none (patched).
  - `[low]` `patch` Edge Case Hunter: a duplicate of the empty-payload skip (patched with the first row).
  - `[low]` `patch` Edge Case Hunter: an empty `TraceSessionId` would pass the "no warning" assertion for the refusal vacuously - added an assertion that the decision has a trace session (patched).
  - `[false]` `reject` Edge Case Hunter: `RemoveWarnings` could delete a concurrent shard's warnings - every test run has its own throwaway stack and the mark scopes the removal to rows after it, the same helper the other tests use.
  - `[false]` `reject` Edge Case Hunter: the check text can quote item values (PII) - the trace already holds the runner's unfiltered `Reply` body; the spec's Design Notes decide this.
  - `[low]` `patch` Verification Gap: `Judge`'s later exits are untested - the same entry as the second row (patched).
  - `[low]` `reject` Verification Gap: the guards for a turn and `cut_off` are not pinned - the matrix row "Other fallbacks" is covered by `refusal` (the `reason = "invalid"` half); the `problem` half only avoids an empty-detail line; adding turn and cut_off cases is more than a direct correction for a cosmetic outcome.
  - `[low]` `patch` Verification Gap: AC2 equality assertions have no mutation line - mutation `FixParameters.SourceFormat` 63 recorded (red observed).
  - `[low]` `patch` Verification Gap: AC3 negative clauses (row, answer, notice) have no mutation line - mutations on `RecordFallback`'s `Reasons` and on the notice slot recorded (red observed).
  - `[low]` `patch` Verification Gap: the answer's `Reasons` is not asserted - added `response.Reasons` to `TestRefusalTrace` (patched).
  - `[low]` `reject` Verification Gap: the matrix row "Other fallbacks" has one assertion - see the turn and `cut_off` row above.
  - `[false]` `reject` Verification Gap: `TestHostReplies` silently skips - the same entry as the first row (patched).
  - `[low]` `reject` Verification Gap: `TestHostReplies` sets no Mark, so a failure would leave a Type 3 row - only on a red run, which is a Type 3 row of no consequence and purged by retention; the Decision rows are removed in all cases.
  - `[false]` `reject` Intent Alignment: the production-path test uses a reply that fails for reasons other than evidence length - by the spec's decision the replay at `Decide.Conclude` proves the cure and `TestDemoDiagnosis` the notice; no `ci/mock` file may change.
  - `[false]` `reject` Intent Alignment: the trace is wider than "the check's own text" in two paths - the spec names all three exits and their texts.

## Design Notes

**Governing ADs:**
- AD-6 and AD-8: Decide alone checks the reply and applies the fallback. `invalid` is unchanged.
- AD-7: the static prompt, with no `{{`; Haiku stays the default; the reply is checked by the `ReplyClass`.
- AD-26: the decision's trace target is `Decision.TraceSessionId`, and event-log rows belong to a session's trace. Turns are not traced, so turn threads gain no row.
- AD-2 and AD-31: the bridge names only bridge classes.
- AD-22: tests and the evaluation set on the mock.
- AD-29 and AD-33: Lane A files only. `ItemNoun` is Lane B's and is not edited.
- Conventions: "Redaction" and "Logging and errors" (`$$$LOGWARNING`, nothing secret), and "Watch failures" (Type 2 and 6 rows with no session are failures, so a Type 3 row never is).
- No AC contradicts an AD. No NFR is affected.

**Integration ACs (Rules 1 and 2).** The story introduces no service or shared component.
- Consumes:
  - 5.4: `DiagnosisPayload` and `Agent.Diagnosis`;
  - 1.6: `invalid`;
  - 7.1: `ReplyCheck` and the fix check;
  - 5.7: `ReplyGuard`;
  - 5.8: the fallback notice.
- Consumed-by: Epic 30 integrates `Decide.cls` and may use the trace text when it measures a retry on `invalid`.

**Extend, don't copy:**
- The warning follows `IncidentManager.Refused` and Decide's own redacted warnings. There is no new helper.
- The tests reuse `Observe.LastLog`, `Warnings` and `RemoveWarnings`, `RunnerFixture.DecisionOf` and the existing `Pack` and `Usable`.
- Payload's Conclude wrapper is a three-line copy of the private wrappers in `Test.Fix.Kind` and `Test.Bridge.ReplyCheck`. It is kept as a copy because each wrapper fixes its own reply class and filter, and only this one uses the production's filter `ReplyGuard`.

**Task 0 (plan stage, slot B `ocutalon-slot-b`, build 154, port 52791, `OCUTALON`; read-only, objects in memory only).** Fixture 1's evidence through the compiled class (MAXLEN 32):
- `CheckReply` gives "ERROR #5001: The reply check failed: the reply is not one JSON object that OcuTalon.Watch.Msg.DiagnosisPayload accepts: ERROR #9406: Unexpected format for value of field, evidence, using class base mapping" (205 characters).
- `%JSONImport` itself refuses the over-long list item, with that one error: it names the field, not the limit.
- `%ValidateObject` on the same value gives #7201 "length longer than MAXLEN allowed of 32" with #5802 naming `Evidence(1)` and the value.
- (inference) A 129-character reference under MAXLEN 128 fails the same way.

**AC2 audit:**

| Class.property | Limit | Kind | Prompt states | Decision and reason |
|---|---|---|---|---|
| DiagnosisPayload.Evidence (each) | 32 | model free text | 32 | **Widen to 128**: free text; the story's cause; the prompt now states 128 |
| DiagnosisPayload.ElementAtFault | 128 | free text | 128 | Keep: above 32, matches |
| DiagnosisPayload.Cause, FixSummary | 1000 | free text | 1000 | Keep: matches |
| DiagnosisPayload.CauseCategory | 32 | fixed list (`CAUSECATEGORIES`, longest 18) | the list | Keep: a fixed value list |
| DiagnosisPayload.FixKind | 32 | fixed list (`Fix.Kind` names) | the list | Keep: a fixed value list |
| DiagnosisPayload `MAXEVIDENCE` | 20 entries | a count | 20 | Keep: matches |
| FixParameters.Field | 128 | a field name | 128 | Keep: matches |
| FixParameters.SourceFormat, TargetFormat | 64 | names from the prompt's two lists (longest 10) | 64 | Keep: matches; values come from a list |
| ItemNoun.One, Other (Lane B) | 128 | free text | 128 | Keep: matches, above 32 |
| DecisionPayload.Outcome | 32 | fixed list (`OUTCOME`) | the list | Keep: a fixed value list |
| DecisionPayload.Reasons (each) | 1000 | free text | Diagnosis 1000; Triage none | Keep: matches |
| Chat turn, the command reply (`agent.noCommands`) | no reply class; text MAXLEN "" | free text | none | Keep: no limit |
| Chat tool args: SetReminder.Text | 1000 | free text | none | Keep: above 32 |
| Chat tool args: ReminderRef, IncidentRef | 22 | 22-character refs copied as the tools gave them | none | Keep: identifiers, not free text |

**Decided in-stage:**
- **AC2's reading.** "No property tighter than 32 characters holds free text" is read in the light of the cause. A model-written free-text property capped at 32 or fewer, outside the fixed value lists, is widened. Only `Evidence` qualifies.
- **Where the text goes.** The trace text goes to Decide's event log in the decision's session (`$$$JobSessionId` is `..%SessionId` in `OnResponse`, irislib `Ens/BusinessProcess.cls` L291). It does not go into a field of a message, a row or a payload: that would be a schema change, and the page and IncidentManager read those.
- **Only an `invalid` fallback of decide or diagnose logs.**
  - A turn's only `invalid` is "no text left once filtered", which the reason already says.
  - A reply that fails its check but falls back for an earlier reason (`cut_off`, `refusal`) logs nothing.
- **The text is the check's own.** For an over-long list item, IRIS names the field but not the limit (Task 0), so the trace names `evidence`, and the runner's `Reply` body in the same trace shows the value. Enriching it would change `CheckReply`. The post-filter error text is cut to 400 characters, as `CheckReply` cuts its own.
- **The redactor only, not `ReplyGuard`.** The guard filters results that leave Decide. The trace already holds the runner's unfiltered `Reply` body.
- **A known corner, the same for every existing Decide and IncidentManager warning.** The text can reach a model only on a local install that watches OcuTalon's own production, when a failed header shares the incident's session (`Watch.Reader.Evidence`'s event log). It is never on the online demo, which lists only Orders. Even then the text is redacted and adds nothing beyond what the trace shows. It is a Type 3 row, so it is never a watch failure.
- **On the online demo, visitors can open the shared Visual Trace and see this warning** (AD-24, FR-15). It holds only the session's demo data.
- **AC1's notice.** AC1's notice is pinned at Decide's answer: IncidentManager never reads evidence, and every downstream limit holds the fixture's values (Incident `Cause` and `FixSummary` 1000, `Element` 128; fixture 119, 106 and 9). The existing `TestDemoDiagnosis` pins the with-fix notice for the same shape: same category, kind, parameters and noun. There is no new mock scenario: it would add `ci/mock` files and a production run for a path this change does not touch.
- **The replays use the production's filter `ReplyGuard`.** The fixtures live in XData blocks, so no quote doubling is needed, and the bytes check proves them exact.
- **Test homes.** The tests go in `Test.Watch.Payload` (the `shards` group), `Test.Watch.Diagnose` (`shards`) and `Test.Agent.Instructions` (`shards-2`). Epic 30 changed none of them. They add no unit and no new wait.
- **Triage's and Chat's prompts are unchanged.**

**Ledger inbox:** none.

**Footprint:** within the orchestrator's list. No footprint extension.

**Lead rulings at the spec gate (2026-10-31, unattended, policy 6df0676):**
- The local-install corner (the warning can reach a model only when a local install watches OcuTalon's own production): ruled veto, inbox U-193, choice (a) keep. Reversal: a follow-up story that keeps OcuTalon's own sessions out of `Watch.Reader.Evidence`'s event-log read.
- Visual Trace showing the warning to the online demo's visitor (their own session's demo data, redacted): decide. The AC puts the text in the trace; "the page" is OcuTalon's own web app.
- AC1's notice pinned at Decide's answer plus the unchanged `TestDemoDiagnosis`, with no new mock scenario: decide (smaller is better; the notice path is unchanged).

## Verification

`<lane>` stands for:

```
env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=5 stage=implement'
```

The rules for every run:
- Use one command per call, each with `timeout: 600000`, and never put two IRIS test runs in one message.
- QA and review use their own stage and tags.
- If a run reports a missing or stale web bundle, run `<lane> OCUTALON_RUN_TAG=e5s12i ci/iris.sh build` once.

**Commands:**
- **(loop) Warm stack.** `<lane> OCUTALON_RUN_TAG=e5s12iw ci/warm.sh up`, once. Expected: ready.
- **(loop) Warm class runs.** `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s12iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Watch.Payload`, then `OcuTalon.Test.Agent.Instructions`. Expected: `CLASS … passed`.
- **(loop) Fresh run of the production test.** `<lane> OCUTALON_RUN_TAG=e5s12i ci/iris.sh class OcuTalon.Test.Watch.Diagnose`, about 2 minutes. It must run fresh, because the running Decide job keeps the old code. Expected: passed.
- **(loop) Fixture bytes.** Expected: `exact` twice.

  ```
  grep '^`{"outcome"' _bmad-output/planning-artifacts/epics.md | sed 's/^`//; s/`$//' | while IFS= read -r f; do grep -qxF -- "$f" src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls && echo exact || echo DIFFERS; done
  ```
- **(once) Mutations.** Apply each one, observe red, revert, and confirm that `git status --short` and `git diff --stat` are byte-identical. Record each as `mutation: … → …`.
  - `Evidence` MAXLEN back to 32 → `TestHostReplies` (both replies), the 128 assertion and `TestDiagnosisLengths` go red.
  - MAXLEN 129 → the 129 assertion and `TestRefusalTrace` go red.
  - The `$$$LOGWARNING` line removed → `TestRefusalTrace` and Diagnose's `invalid-reply` assertion go red.
  - `Redact.Text` dropped from that line → the `[redacted]` assertion goes red.
  - The prompt says 32 again → `TestDiagnosisLengths` goes red.
- **Mutations observed (implement stage).** Each was applied, run, reverted from a scratchpad copy, and the tree confirmed unchanged.
  - mutation: `Evidence` MAXLEN 128 → 32 → `TestHostReplies` (both replies: no fallback, Decision row), `TestPayloadAccepted` (the 128 assertion) and `TestDiagnosisLengths` went red.
  - mutation: `Evidence` MAXLEN 128 → 129 → `TestPayloadRefused` (the 129 assertion) and `TestRefusalTrace` (over the limit) went red.
  - mutation: the `$$$LOGWARNING` line removed from `Conclude` → `TestRefusalTrace` (both replies) and `Test.Watch.Diagnose` `TestDiagnosisVariants` (the `invalid-reply` warning assertions) went red.
  - mutation: `Redact.Text` dropped from that line → `TestRefusalTrace` (the `[redacted]` and not-the-key assertion) went red.
  - mutation: the prompt's "at most 128 characters" → 32 → `TestDiagnosisLengths` (the stated-lengths assertion) went red.
  - mutation: the two `Set problem = ...` lines of `Judge` (no reason left; after the filter) removed → `TestRefusalTrace` "no reason left after the filter" and "invalid after the filter" (count and text) went red.
  - mutation: `RecordFallback`'s `Set row.Reasons = ""` → `"x"` → `TestRefusalTrace` (the row's and the answer's empty `Reasons`, all four replies) went red.
  - mutation: `FixParameters.SourceFormat` MAXLEN 64 → 63 → `TestDiagnosisLengths` (sourceFormat = targetFormat, and the stated sentence) went red.
  - mutation: `Notice.cls` L113 slot `fallbackReason` → the text "The reply check failed" → `TestDiagnosisVariants` ("and its slots hold nothing of the reply check") went red (`Test.Watch.Diagnose`, fresh).
  - (QA) mutation: `(reason = "invalid") &&` removed from the `$$$LOGWARNING` guard in `Conclude` → `Test.Watch.Payload` `TestOtherFallbacksLogNothing` (the cut_off and refusal replies, whose text fails the check) went red. Reverted from a scratchpad copy; the tree was byte-identical.
  - (QA) mutation: `&& (problem '= "")` removed from that guard → `TestOtherFallbacksLogNothing` (the turn that the filter empties) went red. Reverted the same way.
  - (code review) mutation: `Set payload.FixSummary = payload.FixSummary_"!"` before `Judge`'s `%JSONExportToString`, so the reply stays usable → `Test.Watch.Payload` `TestHostReplies` ("the answer's fixSummary is the reply's", both replies) went red on the warm stack `e5s12rw` (AC1, the answer's cause and fix). Reverted from a scratchpad copy; the tree was byte-identical, and the class was green again on the same stack.
- **(QA) Files changed.** `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls` (QA): `TestOtherFallbacksLogNothing` (matrix row "Other fallbacks": cut_off, refusal and a turn emptied by the filter log no warning; closes the gap that the implement stage named), `NewRequest` takes an optional kind and provenance, the Conclude wrapper an optional finishReason, and the class doc. The audit of the other rows and ACs found each pinned by an assertion that can fail; nothing else was added.
- **(once) Affected areas, each fresh, one part per call** (about 4-6 minutes each, inference). If a part nears 8 minutes, split it further with a larger n.
  - `<lane> OCUTALON_RUN_TAG=e5s12i ci/iris.sh shard lane-a@Watch --part 1/3`, then `2/3` and `3/3`;
  - `… shard lane-a@Agent`;
  - `… shard lane-a@Bridge --part 1/3`, then `2/3` and `3/3`;
  - `… class OcuTalon.Test.Fix.Kind`;
  - `… class OcuTalon.Test.Fix.DryRun`.

  Expected: every part passed. CI runs the other areas, lane-b and the live units.
- **(once) The mock evaluation set.** `<lane> OCUTALON_RUN_TAG=e5s12i ci/iris.sh class OcuTalon.Test.Eval.Run`, fresh, about 2 minutes. Expected: passed, with no Eval file changed.
- **(once) Checks.** `bash ci/checks.sh`. It includes `eval-set`, `boundaries` and `class-rules`. Expected: all pass.
- **(once) Teardown.** `<lane> OCUTALON_RUN_TAG=e5s12iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s12i ci/iris.sh teardown`, also after a failure. Confirm that the lane-b lock folder holds none of this stage's locks.

**Shared surfaces:**
- **`DiagnosisPayload.Evidence`'s limit.** No test refuses a reference of 33 to 128 characters (searched every evidence array under `ci/mock`, `eval` and `Test/`).
- **The Diagnosis prompt's text.** No test pins L41. The request-size estimates read the live prompt.
- **`Ens_Util.Log`.**
  - Every `invalid` decide or diagnose fallback now adds one Type 3 warning of `Decide.Conclude`: in a unit test it has no session and `ConfigName` "", in a production it is in the decision's session.
  - The tests that count log rows filter by their own mark plus method, text, config or session (`Diagnose` L314 counts IncidentManager's rows; `Fix/DryRun` L135 counts a dry-run session), so none counts these rows.
  - Other tests' invalid replies leave such rows behind, which is harmless: they are not failures (Type 3), and retention purges them.
- No list, menu, roster, schema or count is changed.
- Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-31).** The run was planned only and halted after planning, as asked. Nothing was implemented, committed or pushed.
- **Task 0.** Slot B (`ocutalon-slot-b`, build 154, port 52791, `OCUTALON`) was used read-only, with objects in memory only. It measured `CheckReply`'s error for fixture 1: `%JSONImport`'s #9406 names the field `evidence`, not the limit.
- **Change.**
  - `Evidence` 32 → 128, and the prompt's L41 says the same.
  - `Decide`: an `invalid` decide or diagnose fallback logs the check's own error text, redacted, as one Type 3 warning in the decision's trace session. Only lines that Epic 30 did not change are touched.
  - Tests in `Test.Watch.Payload`, `Test.Watch.Diagnose` and `Test.Agent.Instructions`. Epic 30 changed none of them, and no unit is added.
- **AC2 audit.** Only `Evidence` is widened. Every other limit is kept, with its reason (the table in Design Notes).
- **For the lead.** Two decided in-stage notes to check:
  - the local-install corner, where the warning could reach a model when OcuTalon watches its own production (never on the online demo);
  - AC1's notice, which is pinned at Decide's answer plus the unchanged `TestDemoDiagnosis`, with no new mock scenario.
- **Ledger.** The inbox was empty. No footprint extension.

**Implement stage (2026-10-31).**
- **Summary.** `DiagnosisPayload.Evidence` is 128 characters per reference and the diagnosis prompt says so. `Decide` logs, for an `invalid` decide or diagnose fallback, the check's own error text (through `Redact.Text`) as one warning in the decision's trace session; `Judge` and `Interpret` carry it in a new last `Output problem`. Both recorded host replies now conclude with no fallback.
- **Files changed.**
  - `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`: `Evidence` MAXLEN 128, docs.
  - `src/ocutalon/cls/OcuTalon/Agent/Diagnosis.cls`: the lengths sentence says 128.
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `problem` in `Judge`, `Interpret` and `Conclude`, the warning line, two doc clauses.
  - `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls`: two fixtures, `TestHostReplies`, `TestRefusalTrace`, the 128/129 boundaries, helpers, clean-up.
  - `src/ocutalon/cls/OcuTalon/Test/Watch/Diagnose.cls`: the `invalid-reply` / `refusal` warning assertions and the notice-slots assertion.
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls`: `TestDiagnosisLengths`.
- **Review.** 23 findings: 9 rows patched (seven fixes, all test-side: payload and row assertions, the two later `Judge` exits, the answer's `Reasons`, a trace-session assertion, and the missing mutation lines), 0 deferred, 14 rejected with reasons in the triage log. Patched by verdict: low 9, medium 0, high 0. Follow-up review recommended: false.
- **Verification.** All on lane-b throwaways (tags e5s12i, e5s12iw): fixture bytes `exact` twice; `Test.Watch.Payload` and `Test.Agent.Instructions` passed (warm); `Test.Watch.Diagnose` passed fresh (after the patches); shards `lane-a@Watch` 1/3-3/3, `lane-a@Agent`, `lane-a@Bridge` 1/3-3/3 passed (before the test-only patches; the patched classes were rerun); `Test.Fix.Kind`, `Test.Fix.DryRun` and `Test.Eval.Run` passed; `bash ci/checks.sh` passed. Eleven mutations observed red and reverted (the lines in `## Verification`). Teardown done; the lane-b lock folder is empty.
- **Residual risks.** The turn and `cut_off` "no warning" paths are pinned only through the `refusal` case. The warning can carry the check's quoted item values (already in the trace's `Reply` body; the lead's ruling U-193 covers the local-install corner).
