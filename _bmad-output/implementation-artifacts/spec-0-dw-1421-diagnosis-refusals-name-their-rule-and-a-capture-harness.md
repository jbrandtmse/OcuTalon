---
title: 'DW-1421 C0 + C1: diagnosis refusals name their rule, and a capture harness for the fallback replies of an eval run'
type: 'feature'
created: '2026-11-16'
status: 'done'
baseline_revision: '165547dd1193c68d8a845abed1e248a14806e0fb'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-23-3-name-the-setting-change-behind-an-incident-and-offer-its-rol.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-12-a-correct-diagnosis-is-never-refused-for-an-over-long-eviden.md'
warnings:
  - oversized
deferred: []
---

<intent-contract>

## Intent

**Problem (DW-1421, MED; Contest Planner rulings "DW-1421 rulings" ~09:30Z and "DW-1421 C0: option (b) CONFIRMED" ~10:00Z, 2026-11-16, BINDING):**
- The 23.3 incidents `orders-target-to-review` and `orders-target-renamed` end in the fallback `invalid` in real-model runs (to-review 6/10, renamed 3/10 over the DW-1389 A/B). The diagnosis found that `Watch.Msg.DiagnosisPayload`'s `%OnValidateObject` refuses the Diagnosis agent's reply (`Decide.Judge`, `Decide.cls:1653`).
- Which rule refuses it is unknown:
  - `Decide.RefusalText` (`Decide.cls:1050-1089`) turns every `%OnValidateObject` rule into the same "ERROR #5001" (`RefusalPart`, L1142-1150), because the rule's message holds reply values, so it is never shown;
  - no raw reply is kept anywhere the Planner can read after the eval stack is torn down.
- The Planner rules on C2 and C3 (code-side tolerance) only from measured per-rule numbers, not from the leading inference.

**Approach:**
- **C1, rule tags (product, not model-facing, no A/B):**
  - each `%OnValidateObject` rule of `DiagnosisPayload` gets a fixed tag name, and so do the three rules it inherits from `Bridge.Msg.DecisionPayload` (Veto item 6);
  - the rule's error carries the tag as the status's second parameter;
  - `RefusalText` shows `ERROR #5001 rule <tag>`, but only for a tag that the reply class lists in its new `REFUSALRULES` parameter. The tag is the rule's name only: no model text and no field value.
- **C0, the capture harness (eval tooling, no model, no key):**
  - `eval/capture-fallbacks.sh` plus the ObjectScript entry `OcuTalon.Test.Eval.CaptureTool` read, on the running eval stack and before its teardown, the raw `Reply.Text` of every reply that a fallback decision got (Ens message store);
  - each reply is re-checked with a new public `Decide.Recheck`, which is Conclude's own check and records and logs nothing;
  - the harness writes one file per reply (raw text, rule, field) into an evidence folder outside the checkout, and prints counts and rule names only.
  - The Planner's key-holder turns it on by setting `OCUTALON_EVAL_CAPTURE_DIR` for `eval/run.sh --release-candidate`, because the run's exit trap is its teardown (Design Notes).

## Boundaries & Constraints

**Always:**
- **Footprint.** All files are Lane A (Veto item 2). Lane C makes the edits under the Planner's DW-1421 C0/C1 ruling:
  - `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`: the three tags, `REFUSALRULES`, class doc.
  - `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
    - the tags and `REFUSALRULES`;
    - the time-of-day rule split into one rule for the cause and one for the fixSummary;
    - the fix kind's check wrapped in a tagged error;
    - the class doc.
  - `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
    - `RefusalText` and its doc, plus a private `RefusalTag`;
    - a new public `Recheck`;
    - the `Interpret` doc sentence naming `Recheck`.
  - New: `src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls` (the entry, not a TestCase) and `src/ocutalon/cls/OcuTalon/Test/Eval/Capture.cls` (its TestCase).
  - `eval/capture-fallbacks.sh` (new) and `eval/run.sh` (the opt-in step and the header's Variables and release-candidate text).
  - Tests:
    - `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls`;
    - `src/ocutalon/cls/OcuTalon/Test/Bridge/ReplyCheck.cls`;
    - `src/ocutalon/cls/OcuTalon/Test/Agent/RememberDecision.cls` (`DEMOTAIL`);
    - `docker/tests/test-eval-set.sh` (a new rule `capture`, its header line, its bad samples).
  - This spec.
- A tag is a fixed ASCII literal matching `?1L.(1L,1N,1"-")`, written in the rule's `$$$ERROR($$$GeneralError, <message>, "<tag>")`. The message (the status's first parameter) is unchanged, so `GetErrorText` of every refusal is byte-identical to the baseline, except for the fix-kind rule, whose text gains the outer sentence before the kind's own (Task 0 item 1).
- `RefusalText` shows a second parameter only when it is a tag that `REFUSALRULES` of the reply class lists. Anything else, a value included, gives the bare "ERROR #5001" as today. `RefusalText`'s contract stands: it never shows a reply value, an IRIS message text or a field name taken from the reply.
- Every refused reply still falls back with reason `invalid`, exactly as before (AD-8 unchanged). The order of the rules is unchanged.
- The harness and the re-check never read `.env` or any key variable, never call the model or any runner, and send no Ens message. They write no event-log row, no Decision, Usage or trace row and no audit record.
- The harness prints counts and rule names only. Raw reply text goes only into the files of the evidence folder.
- It refuses an evidence folder inside the checkout. It changes neither the run's verdict nor its exit code.
- `eval/run.sh` sources `eval/capture-fallbacks.sh` only when `OCUTALON_EVAL_CAPTURE_DIR` is set, so every existing stub test (rc-flow, rc-stack, run-guard, rules-flow), whose copy tree lacks the file, runs unchanged. No workflow, compose file or class default sets the variable.
- ObjectScript and shell stay ASCII. Comments state the contract, not review history. No absolute local path in any file.
- Every existing test passes, with only the pins listed under Tasks changed.

**Never:**
- Change any model-facing text: an INSTRUCTIONS block, a pack, a tool description or Triage/Diagnosis wording (C4 is out of scope).
- Tolerate or drop any field (C2/C3 are not ruled yet), or change which replies are refused.
- Show a tag, a rule or a refusal anywhere a user reads OcuTalon text: a catalog key, a notice, the card, the chat, the README or a Decision row's Reasons.
- Put the tag, or anything of the reply, into a Decision row, an AgentStep or a FailureText.
- Name `.env`, `ANTHROPIC`, `curl`, `wget`, a model URL, `PointKeys` or `LIVE_SESSION_ENV` in a code line of `eval/capture-fallbacks.sh`, or the container tool's name anywhere in it (the eval-scripts rule). It reaches the container only through `iris_script` and `dc exec` of `lib-live.sh`.
- Commit, print or log a raw reply. Write raw replies inside the checkout.
- Delete, skip or weaken a test.

## I/O & Edge-Case Matrix

"Warning" means the Type 3 event-log row that `Decide.Conclude` writes (L1472): "The reply check refused the reply of the decision <ref>: <problem>".

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Diagnosis rule | A diagnose reply that breaks one `DiagnosisPayload` rule, e.g. a fixSummary on a setting_change with no fix kind | Fallback `invalid` as today. Warning "...DiagnosisPayload accepts: ERROR #5001 rule fix-summary-not-for-category" | none |
| 2 Inherited rule | A decide or diagnose reply with no confidence | Warning "...accepts: ERROR #5001 rule confidence-missing" (triage too: DecisionPayload) | none |
| 3 After the filter | A reply valid until the filter blanks its cause | "After the reply filter ran: ... refused the filtered payload: ERROR #5001 rule cause-blank" | none |
| 4 Fix kind's check | data_format_change whose fixParameters fail the kind's check, or no pack | "ERROR #5001 rule fix-parameters-check" (the kind's inner reason is embedded, not shown) | none |
| 5 Untagged #5001 | A 5001 with no second parameter, or one that `REFUSALRULES` of the reply class does not list (another class's tag, a value, a probe) | "ERROR #5001", never the parameter | none |
| 6 Import and length errors | #9404, #9406, #5035, #7201 to #7204 | Unchanged words ("ERROR #9406 on Reasons", "Evidence element 2: 129 > 128") | none |
| 7 Capture, fallbacks present | `OCUTALON_EVAL_CAPTURE_DIR=<folder outside the checkout>`, rc run that recorded fallbacks | After the result and before REPORT (stack still up), one IRIS session; each reply of each fallback decision is one file in the folder; stdout `CAPTURE` lines (Design Notes) | capture failure is one `CAPTURE failed` line; verdict and exit unchanged |
| 8 Capture, none | No fallback decision on the stack | "CAPTURE 0 fallback decision(s) ..." and no file | none |
| 9 Folder inside the checkout | The resolved folder is the checkout or below it | "CAPTURE refused: ..." and no IRIS session, no file; the run is otherwise unchanged | none |
| 10 Variable unset | Every existing invocation | Nothing sourced, no session, no line: byte-identical behaviour | none |
| 11 Decision with no reply | Fallback before any runner reply (precheck, timer) | Counted; 0 replies; rule `no reply` | none |
| 12 Blank reply text | A failure reply (FailureText set, Text empty) | One file (text empty, failureText kept in the file only); rule `no reply text` | none |
| 13 Reply passes now | A fallback whose reason is not `invalid`, or a reply that passes the re-check | Rule `passes the check`, with the fallback reason counted | none |
| 14 Second attempt | First runner and retry runner each answered | One file per reply, attempt 1 and 2, runner named | none |
| 15 Unsafe CHK field | A CHK field holding a character outside `[A-Za-z0-9 #:;<>.,()_-]` | Printed as "(withheld)" | none |
| 16 Script run directly | `bash eval/capture-fallbacks.sh ...` | Usage line, exit 2, no call | none |

</intent-contract>

## Code Map

Line numbers are at the baseline `1de31e808`.

- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - class doc L1-17;
  - parameters L21-35;
  - `%OnValidateObject` L62-97: `##super()` L64, the rules L66-92, the setting-kind exit L94, `CheckFix` L95;
  - `Listed` L101, `CheckFix` L114 (returns `Fix.Kind.Check`'s status), `Blank` L134.
- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`: `%OnValidateObject` L19-32 (outcome L22-24, reasons L29, confidence L30). `Test.Bridge.ProbeReplyCheck` extends it and calls `##super()`.
- `src/ocutalon/cls/OcuTalon/Fix/Kind.cls`: `Check` L180-185 and `CheckParameters` L189-205 (their #5001 texts quote reply keys). Not changed.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `ReplyClassOf` L976 (public; reads the runner's `ReplyClass` through `Ext.Accessor.ValueFor`);
  - `CheckReply` L1017-1034 (its own error text holds `GetErrorText`, unlogged);
  - `RefusalText` doc L1036-1049 and body L1050-1089 (the #5001 call at L1075 passes param 2 as `limit`);
  - `RefusalAdd` L1098, `RefusalPart` L1134-1151, `RefusalImport` L1154, `RefusalCheck` L1207;
  - `Conclude` L1435: the warning L1472, the only place a problem is written;
  - `Accept`'s `ClassFor("ContentClass", "", "Decide", .sc)` L1520 is the model for reading `ReplyFilterClass`;
  - `Interpret` L1624-1641 (Private; begins and ends `ReplyCheck`) and `Judge` L1645-1704 (problems L1655, L1666, L1691; no log, no row);
  - `RecordFallback` L1719 (Fallback 1, no reasons, no payload), `NewRow` L1756.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls` (`Text` L9, `FinishReason`, `FailureText` L66), `Msg/Request.cls` (`DecisionRef`, `Input` SqlFieldName `InputText`, `RetryOf`), `Data/Decision.cls` (`Ref`, `Kind`, `Fallback`, `FallbackReason`, `RecordedAt`; `RefIndex`), `ReplyCheck.cls` (process-private, so a re-check in the harness's session is isolated).
- The runner's Reply carries no DecisionRef (`Adapter/Agent.cls` `Converse` L1171-1178). The link is `Ens.MessageHeader`:
  - the request header (body `OcuTalon.Bridge.Msg.Request`, the `SentRequest`/`RetryRequest` clone that carries the DecisionRef, Decide L510-535, target the runner);
  - then the response header whose `CorrespondingMessageId` is that header's ID (body `OcuTalon.Bridge.Msg.Reply`).
  - Task 0 item 2 confirms it.
- `src/ocutalon/cls/OcuTalon/Production.cls`:
  - `Decide` L20 with `ReplyFilterClass` `OcuTalon.Checks.ReplyGuard` L22;
  - `TriageAgent` `ReplyClass` DecisionPayload L32;
  - `DiagnosisAgent` L34 and `DiagnosisAgentRetry` L45, both DiagnosisPayload.
- `src/ocutalon/cls/OcuTalon/Eval/Data/CaseResult.cls`: `RunRef`, `CaseName`, `DecisionRef` (an incident's diagnose Ref). This gives the harness the case of a decision.
- `eval/run.sh`:
  - header Variables L19-34;
  - `. ci/iris.sh` / `setup_tag` L295-297;
  - `eval_run` L319-349 (the `iris_script OCUTALON` pattern, early `CHK|started|`), `fetch` L443-451 (`dc exec -T iris cat`);
  - stack start L637-651;
  - rc branch L1012-1116: attempts L1016-1035, held-out L1038-1042, smoke L1044-1056, verdict L1058-1073, fetch L1074, the result text L1076-1087, `REPORT` L1088, then the exits.
  - The exit trap (`lib-live.sh` `live_start` L88) is the teardown.
- `docker/tests/lib-live.sh`: `dc` L319, `iris_script` L487 (keeps only `CHK|` lines; no `-e` unless `LIVE_SESSION_ENV`).
- `docker/tests/test-eval-set.sh`:
  - eval-scripts L126-128 and `check_eval_scripts` L2875 (no `docker` in a code line of `eval/*.sh`);
  - key-like `check_key_like` L4038;
  - rc-flow stubs `rcf_stub` L3535 and `rcf_session` L3685 (the copy tree copies a fixed file list, so not the new script);
  - rule list L4410-4434.
- Tests that pin the old words:
  - `Test/Watch/Payload.cls` `TestRefusalTrace` L309: "ERROR #5001" at L337 ("key in a refused value", causeCategory = a key) and L341 ("invalid after the filter", cause blanked); doc L14-19. Also `TestPayloadRefused` L150, `TestRollbackFix` L233 (the pack with settingChanges), `Usable`/`Outage`/`Rollback`/`Pack`.
  - `Test/Bridge/ReplyCheck.cls`: row 9 L338 ("ERROR #5001" for the probe's outcome); `TestRefusalTextForms` L375 (row g, a repeated untagged 5001); doc L10-18.
  - `Test/Agent/RememberDecision.cls` `DEMOTAIL` L32 (a triage reply with no confidence).
- Guards that must stay green: `Test/Fix/Validation.cls` `TestKindCheckIsLast` (its `CheckReply` error text must still hold "is not a field of the sample message"), `Test/Fix/Kind.cls`, `Test/Watch/Diagnose.cls` (its warning still ends "ERROR #9406 on Reasons"), `Test/Bridge/CodeRules.cls`.
- `ci/units.sh` L142: area `Eval` runs in `shard:lane-a@Install,Digest,Eval`. `Test.Eval.Capture` joins it with no edit.
- IPM: `module.xml` ships `OcuTalon.PKG` from `src/ocutalon/cls` whole, `OcuTalon.Test.*` included (`release/ipm-install.sh` calls Test fixtures on an installed package). No unshipped package exists, so the entry lives in `OcuTalon.Test.Eval` beside `ThinkingSmoke`, which `eval/run.sh` already calls.
- Visibility of the warning: Type 3 in `Ens_Util.Log` of OCUTALON, in the decision's trace session. It shows in the Management Portal Event Log and in Visual Trace (`Core/Trace.cls` L1-16). The model's readers take Type 2 and 6 of watched namespaces only (`Watch/Reader.cls` L758, L765).

## Tasks & Acceptance

**Task 0 (measure first, no model and no key, on a lane-C throwaway, never a slot (Rule 21); record each result under `## Verification`):**
- Put the probes in one scratch class (`ZzScratch.Dw1421`) in your scratchpad. Load it into the throwaway only, never commit it, and remove every row, header and file a probe made.
1. **The status mechanics (before any product edit, warm stack).** Record:
   - for `$$$ERROR($$$GeneralError, "t", "zz-tag")`, `DecomposeStatus`'s `errors(1,"param")` and `errors(1,"param",2)`, and that `GetErrorText` is "ERROR #5001: t";
   - for a scratch `%JSON.Adaptor` class whose `%OnValidateObject` returns that error, whether `Decide.CheckReply`'s `cause` still carries param 2 after `%ValidateObject`;
   - for `$SYSTEM.Status.EmbedStatus(outer, inner)` with two 5001s, the top-level count of `DecomposeStatus` (expect 1, the outer), and whether `GetErrorText` holds the inner text within its first 400 characters;
   - **Rule:** if param 2 is lost, stop with `## Clarification Needed`. If the embedded text is not kept, use `AppendStatus` and record that `RefusalText` then shows the bare inner part after the tag.
2. **A real fallback's store (mock, no key).** On the warm throwaway (runners pointed at the mock, as `Test.Watch.Diagnose` runs), send one failure whose text holds `[[mock:invalid-reply]]` through IncidentManager, following `Test.Watch.Diagnose` `SendBatch`, and wait for its diagnose Decision row (Fallback 1, `invalid`). Record:
   - the Request bodies whose `DecisionRef` is the Ref, and their headers (`TargetConfigName`, `SourceConfigName`, `SessionId` against the row's `TraceSessionId`);
   - the response headers found by `CorrespondingMessageId`, with `MessageBodyClassName` `OcuTalon.Bridge.Msg.Reply`;
   - that `Reply.Text` equals the reply of `ci/mock/scenarios/A/invalid-reply.json`;
   - whether `DiagnosisAgentRetry` answered too;
   - the SQL that finds them.
   - **Rule:** if no reply is found this way, stop with `## Clarification Needed`.
3. **Settings outside a production job.** In an `iris session` in OCUTALON, record `Decide.ReplyClassOf` for `DiagnosisAgent`, `DiagnosisAgentRetry` and `TriageAgent`, and `Ext.Accessor.ClassFor("ReplyFilterClass", "", "Decide", .sc)`.
4. **No side effects of a re-check.** Around `CheckReply` and `ReplyGuard.Filter` on item 2's text (and, after the Execution tasks, around `CaptureTool.Run` with that Ref), record:
   - the `Ens_Util.Log` max ID, the counts of `OcuTalon_Bridge_Data.Decision` and `Usage`, and the `Ens.MessageHeader` max ID: all unchanged;
   - after `Run`: one file with the scenario's text, and the rule `ERROR #9406 on Reasons` with field `reasons`.
5. **End to end (after the Execution tasks; background run, `run_in_background`).** Run `OCUTALON_EVAL_CAPTURE_DIR=<scratchpad>/capture-e2e OCUTALON_RUN_TAG=<tag> bash eval/run.sh --release-candidate --on-mock` with the lane-C variables, and record:
   - the `CAPTURE` lines, the number of files and the number of replies the summary gives;
   - that no file's text (its first 40 characters, for each file) is in the run's output;
   - the exit code and verdict;
   - the elapsed time.
   - The mock's one diagnosis is a repair_resend of OrderDate, so an incident whose sample lacks that field is expected to show `fix-parameters-check`. Record what was measured, whatever it is.

**Execution:**
- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`:
  - add `Parameter REFUSALRULES = "outcome-unlisted:outcome,reasons-blank:reasons,confidence-missing:confidence";`, documented as "the fixed name of each rule of %OnValidateObject and the JSON field it reads, as tag:field, comma-separated; a subclass lists these first, then its own";
  - pass each rule's tag as the third argument of its `$$$ERROR`;
  - one class-doc sentence.
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`:
  - `REFUSALRULES`: the parent's three, then the 19 own pairs of the table in Design Notes, in rule order;
  - each own rule's `$$$ERROR` carries its tag;
  - L91-93 become two rules (`time-of-day-in-cause`, then `time-of-day-in-fix-summary`), with the same message;
  - L95 becomes: `Set sc = ..CheckFix()`, and when it errs, `Quit $SYSTEM.Status.EmbedStatus($$$ERROR($$$GeneralError, "The fix kind's check of the fixParameters failed", "fix-parameters-check"), sc)` (or `AppendStatus`, per Task 0 item 1);
  - the class doc names the tags and `REFUSALRULES`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - add private `RefusalTag(replyClass, value) As %String`: the value when it is a tag of `$Parameter(replyClass, "REFUSALRULES")`, else "";
  - in `RefusalText`, a #5001 whose param 2 gives a tag adds the part "ERROR #5001 rule <tag>" in place of `RefusalPart`'s "ERROR #5001";
  - update `RefusalText`'s doc (a new bullet for the tag form);
  - add public `Recheck(request As OcuTalon.Bridge.Msg.Request, text As %String, replyClass As %String, filterClass As %String, Output problem As %String) As %Boolean`, which calls `Interpret` and documents "the reply check that Conclude makes, for a tool that re-checks a stored reply: 1 when the reply passes; no row, no event, no warning; problem as Interpret's";
  - one sentence in `Interpret`'s doc.
- `src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls` (new, `%RegisteredObject`, Lane A):
  - `Run(folder As %String, refs As %String = "", Output summary As %DynamicObject) As %Status`:
    - for every Decision row with Fallback 1 and Kind decide or diagnose (only the comma-separated `refs` when given), it finds the decision's replies by item 2's SQL, in header-ID order (attempt 1, 2);
    - per reply it reads the case (`CaseResult` by `DecisionRef`, else none), the runner, `Decide.ReplyClassOf(runner)` and the filter class (`ClassFor`);
    - it calls `Decide.Recheck` with the stored Request body and derives the rule and the field (Design Notes);
    - it writes one JSON file per reply, `<n>-<decisionRef>-<attempt>.json`, into `folder` (UTF-8), after deleting only the files of its own name pattern there; plus `summary.json`.
  - `Lines(summary) As %String`: the `CHK|` lines; `Print(summary)` writes them.
  - No `$$$LOG*`, no `Ens.Util.Log`, no Ens send, no `%AI`, no runner, no `Conclude`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Capture.cls` (new TestCase) -- the harness tests below.
- `eval/capture-fallbacks.sh` (new):
  - sourced by `eval/run.sh`, it defines `capture_fallbacks <folder>`;
  - run directly, it prints `usage: OCUTALON_EVAL_CAPTURE_DIR=<evidence folder outside the checkout> bash eval/run.sh --release-candidate [--on-mock]` and exits 2;
  - the function resolves the folder (`mkdir -p`, `pwd -P`), refuses one inside `$(pwd -P)` of `$root`, and runs one `iris_script OCUTALON` session (`CHK|started|`, `CaptureTool.Run("/tmp/ocutalon-capture/", "", .s)`, `Print`, `CHK|run|`, error codes only);
  - it copies each `CHK|file|<name>` whose name matches `^[A-Za-z0-9._-]+$` with `dc exec -T iris cat`, prints the `CAPTURE` lines through the safe-character filter, and removes the container folder.
- `eval/run.sh`:
  - in the rc branch, just before `echo "REPORT $report_dir"` (L1088), whatever `fails` is: when `OCUTALON_EVAL_CAPTURE_DIR` is set and not empty, source `"$root/eval/capture-fallbacks.sh"` and call `capture_fallbacks "$OCUTALON_EVAL_CAPTURE_DIR"`. On a non-zero return, print "CAPTURE failed: the fallback replies were not captured" and go on;
  - the header's Variables gain `OCUTALON_EVAL_CAPTURE_DIR` (rc runs only, Planner's tooling, never set by a workflow);
  - the release-candidate text gains the step.
- Tests -- the changed pins and new tests listed in the acceptance criteria below; `docker/tests/test-eval-set.sh` gains the rule `capture` (header line, bad samples, `rule capture ...`).

**Acceptance Criteria:**
- **AC 1 (C1, tags carried).** Given a diagnose reply that breaks exactly one rule, when `CheckReply` refuses it, then `RefusalText(cause, DiagnosisPayload, text)` is exactly "ERROR #5001 rule <tag>", for each of the 22 rules of the table.
  - Pinning test: new `Test.Watch.Payload` `TestRuleTags`, one row per rule, using the pack of `TestRollbackFix`. Its rows also check that the tag's field in `REFUSALRULES` is the table's.
  - Changed pins in `TestRefusalTrace`: "...accepts: ERROR #5001 rule cause-category-unlisted" (the key-in-value row: neither the key nor `[redacted]`) and "...refused the filtered payload: ERROR #5001 rule cause-blank".
  - Pinned rules with their own mutations: `fix-summary-not-for-category`, `rollback-fix-summary`, `time-of-day-in-cause`, `time-of-day-in-fix-summary`, `confidence-missing`, `fix-parameters-check`.
- **AC 2 (only listed tags).** Given a #5001 whose second parameter is a marker, or a tag the reply class does not list, when `RefusalText` runs, then the part is the bare "ERROR #5001" and holds nothing of the parameter.
  - Pinning test: `Test.Bridge.ReplyCheck` `TestRefusalTextForms`:
    - new row k: the probe class with "confidence-missing" gives "ERROR #5001 rule confidence-missing";
    - new row l: a marker gives "ERROR #5001", without the marker;
    - new row m: "cause-blank" with the probe class gives "ERROR #5001".
  - Row 9 becomes "ERROR #5001 rule outcome-unlisted". `RememberDecision` `DEMOTAIL` ends "ERROR #5001 rule confidence-missing".
- **AC 3 (every rule has one fixed tag).** Given the two classes, then:
  - each `REFUSALRULES` lists distinct `tag:field` pairs whose tags match the pattern;
  - DiagnosisPayload's list starts with DecisionPayload's;
  - each class's own `%OnValidateObject` implementation has exactly one listed own tag literal per `$$$ERROR(`, and each own tag occurs once.
  - Pinning test: new `Test.Watch.Payload` `TestEveryRuleTagged` (reads `%Dictionary.CompiledMethod` implementations; `Test.Bridge.CodeRules`' source helper if it fits).
- **AC 4 (Recheck is Conclude's check, silent).** Given each `TestRefusalTrace` reply, when `Decide.Recheck` runs with the same request, class and filter, then it returns 0, and REFUSED_ref ": " problem equals Conclude's warning. A usable reply returns 1 with an empty problem.
  - Pinning test: `TestRefusalTrace`, extended.
- **AC 5 (harness: one reply per rule, counts and fields).** Given seeded fallback decisions (Decision row, Request body, Reply body and the two linked headers, made as Task 0 item 2 found them), with:
  - one diagnose reply per rule of the table,
  - one triage reply with no confidence,
  - one reply that passes, one blank-text failure reply, and a second attempt on `DiagnosisAgentRetry`,
  - when `CaptureTool.Run(folder, refs)` runs, then the summary counts each rule once with its field, the files are one per reply, and each file's text equals the seeded text with its attempt and runner.
  - Pinning test: new `Test.Eval.Capture` `TestOneReplyPerRule`.
- **AC 6 (no reply text on stdout).** Given those seeds, each carrying a distinct marker in a field, when `Lines(summary)` is built, then it holds no marker and no 10-character part of one, while the files hold each.
  - Pinning tests:
    - `Test.Eval.Capture` `TestLinesHoldNoReplyText`;
    - shell rule `capture`: the rc-flow copy tree plus the script, a stub that answers the capture session with CHK lines and the files' `cat` with a marker, and a stub CHK field holding the marker. Expected: the run's output holds the `CAPTURE` lines and no marker (the planted field prints "(withheld)"), and the folder holds the marker files.
- **AC 7 (records and logs nothing, calls no model).** Given `Run`, then the `Ens_Util.Log` max ID, the Decision and Usage counts and the `Ens.MessageHeader` max ID are unchanged, and the CaptureTool source names no `$$$LOG`, `Ens.Util.Log`, `%AI`, `Chat`, `SendRequest`, `Conclude` or runner item.
  - Pinning test: `Test.Eval.Capture` `TestRecordsAndLogsNothing`.
- **AC 8 (the script's guarantees).** Given `eval/capture-fallbacks.sh`, then:
  - no code line names `.env`, `ANTHROPIC`, `curl`, `wget`, `/v1/`, `api.`, `PointKeys` or `LIVE_SESSION_ENV`;
  - it passes eval-scripts and key-like;
  - run directly, it exits 2 with the usage line and no stub call;
  - a folder inside the copy tree is refused, with no capture session and no file.
  - Pinning test: rule `capture`; each bad sample (one per forbidden name, one unguarded folder) must be flagged.
- **AC 9 (opt-in, before teardown).** Given `OCUTALON_EVAL_CAPTURE_DIR` unset, then rc-flow, rc-stack, run-guard and rules-flow are unchanged. Given it set, then exactly one capture session runs, after the `Gate.Result` session and before the `REPORT` line, with verdict and exit code unchanged, also when the stub's capture session prints nothing (the `CAPTURE failed` line).
  - Pinning test: rule `capture`.
- Standing criterion (Rule 19): every test added or changed passes on a fresh environment, in either order.

### Review Findings

Code review (lane C, 2026-11-16, tags e0dw1421c*; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; diff `165547dd1`..`64b72d142` without the bookkeeping files). 30 entries after grouping: high 0, medium 3, low 25, false 2, plus a note. Every patch is applied (unattended option 1); nothing is deferred and no ledger entry is made. AD-8 is unchanged: the same replies are refused, in the same rule order, with the same `invalid` fallback (acceptance auditor and triage).

- [x] [Review][Patch] (medium) The silence tests compared counts of the whole instance while the production runs: `TestNothingIsWrittenAnywhere` (row counts of every product table, non-OcuTalon headers, all OcuTalon audit entries) and `Snap` (Decision, Usage, bridge headers) can go red from another job's work. Patched: `Writes` calls Run or Recheck up to three times and fails only on a count that changed in every try (`Moved`, `Counts`; `Snap` in the same `name=count;` form), and the audit count is of this process's user [src/ocutalon/cls/OcuTalon/Test/Eval/Capture.cls]
- [x] [Review][Patch] (medium) "A second run replaces the files of the first" could not fail (same refs, same names; its status unasserted), so `Clear` and "only its own names" were unpinned. Patched: a file of another name is put into the folder, the second run covers one decision, its status is asserted, and the folder must hold 3 files with the foreign one kept [Capture.cls TestOneReplyPerRule]
- [x] [Review][Patch] (medium) I/O row 8 (no fallback decision, no file, summary.json included) had no test. Patched: new `TestNoFallbackWritesNoFile` [Capture.cls]
- [x] [Review][Patch] (low) `Run("")` wrote into the IRIS process's directory: `NormalizeDirectory("")` is the current directory (`$$$FileNormalizeDirectoryFull`), so the "empty folder" check after it never fired (the earlier review's Blind 9 patch). Patched: the raw argument is checked first; pinned in `TestNoFallbackWritesNoFile` [src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls:Run]
- [x] [Review][Patch] (low) The fixed rule `no check` had no test. Patched: new `TestUncheckableReplyIsCounted` (a reply to an item with no reply class is `no check`, the other reply of the run is still judged and written) [Capture.cls]
- [x] [Review][Patch] (low) The shell's unsafe-file-name filter had no sample, though it is the one guard on the copy's write path. Patched: stub `RCF_CAP=unsafe` (`CHK|file|../zz-escape.json`) and bad sample `bad-no-name-filter` in rule `capture` [docker/tests/test-eval-set.sh]
- [x] [Review][Patch] (low) The folder guard refused only this checkout: a folder in the main checkout or a sibling worktree was accepted (QA note; Planner focus). Patched: `capture_inside` also refuses each checkout that `git worktree list --porcelain` names, and below it (no git, or not a repository: as before); samples with a stub git (the main checkout, a folder in it, a folder in a sibling worktree refused; a folder beside them gets its session) and bad sample `bad-one-checkout` [eval/capture-fallbacks.sh:capture_inside]
- [x] [Review][Patch] (low) A failed or empty copy left its partial or empty file in the evidence folder, looking like a capture file. Patched: `rm -f` of that file; the copy-fail samples assert an empty folder; bad sample `bad-failed-copy-kept` [eval/capture-fallbacks.sh]
- [x] [Review][Patch] (low) `cd "$given"` with an exported CDPATH and a relative folder could print a path into `resolved`. Patched: `CDPATH= cd --` (and in the worktree loop); `bad-logical-path` follows the new text [eval/capture-fallbacks.sh]
- [x] [Review][Patch] (low) The rc stub runs other than rc-flow inherit the caller's `OCUTALON_EVAL_CAPTURE_DIR` (rule hermeticity). Patched: `test-eval-set.sh` unsets it at its start; the rule's own samples set it per session [docker/tests/test-eval-set.sh]
- [x] [Review][Patch] (low) The rule's copy check passed when either file held the text (`grep -qF` over two files). Patched: each file is checked [docker/tests/test-eval-set.sh check_capture]
- [x] [Review][Patch] (low) AC 7's source scan did not name the runner items. Patched: TriageAgent, DiagnosisAgent and ChatAgent added [Capture.cls TestRecordsAndLogsNothing]
- [x] [Review][Patch] (low) `TestEveryRuleTagged` counted only `$$$ERROR(`: a rule written with `$SYSTEM.Status.Error(` shipped untagged unseen. Patched: both forms are counted. A status returned from a helper (the `CheckFix` shape) is still not counted; such a rule fails safe as the bare "ERROR #5001" [src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls]
- [x] [Review][Patch] (low) The field half of `REFUSALRULES` was only compared with a hand copy, so one typo in both passed. Patched: each pair's field (its first part) must be the `%JSONFIELDNAME` of a compiled property of the class (`JsonField`) [Payload.cls TestEveryRuleTagged]
- [x] [Review][Patch] (low) Row l of `TestRefusalTextForms` was not deterministic: about 29% of `NewRef` values hold "_", so that sample failed the form check, not the allowlist. Patched: "_" becomes "-" (the fixed `zzmarkerprobe` row already pinned the allowlist) [src/ocutalon/cls/OcuTalon/Test/Bridge/ReplyCheck.cls]
- [x] [Review][Patch] (low) Doc comments narrated review history ("(QA, DW-1421)", "(QA, attempt 2)", "// n (QA)"), against Rule 14. Patched [Capture.cls, ReplyCheck.cls]
- [x] [Review][Patch] (low) CaptureTool's doc said the attempts are "1, 2" (first and retry runner), but a rate_limited re-send to the same runner (AD-20) is an attempt too, and a cut-off first attempt of an invalid decision is re-checked like the others. Patched: the doc states both and that each file keeps its finishReason; `TestNothingIsWrittenAnywhere`'s doc says "add or remove no row" (it counts rows) [CaptureTool.cls, Capture.cls]

**Rejected**
- (false) The capture session can run 3 times (`iris_script` retries): it retries only a session that printed no CHK line, and the script prints `CHK|started|1` before Run, so a retry follows only a session that never ran Run.
- (false) A tagged error with an embedded 5802 reads "ERROR #5001 on <P> rule <tag>": CheckFix's inner status comes from `Fix.Kind.Check`/`CheckParameters` (#5001 only) or `%JSONExportToString`; no fix kind returns a 5802 (grep of `Fix/`), and TestRuleTags pins the exact form.
- (low, wontfix-accepted) A reused evidence folder mixes two runs' files: the key-holder makes a new run folder per run (Design Notes); refusing a non-empty folder would be a refusal the Planner's ruling (b) does not list. reopen_if=a capture folder holding files of two runs.
- (low, wontfix-accepted) A folder named in another case than the disk's (case-insensitive macOS) passes the guard: the key-holder passes `$E/<run folder>/capture`; a case fold would add branches. reopen_if=a capture command that names the folder in a case other than the disk's.
- (low, wontfix-theoretical) A symlink already named like a capture file in the evidence folder redirects the write: it needs a planted link in the key-holder's own new folder.
- (low, wontfix-theoretical) The capture session has no time limit: every `iris_script` session of eval/run.sh has the same property.
- (low, wontfix-accepted) eval/key-proof.sh's inner eval/run.sh inherits an exported `OCUTALON_EVAL_CAPTURE_DIR` (out of footprint). reopen_if=a key-holder sequence that exports the variable around eval/key-proof.sh.
- (low, wontfix-accepted) A cut-off first attempt of an invalid decision is counted under the rule its text fails now (its file keeps finishReason; doc patched above). reopen_if=a key-holder capture whose file with a finishReason other than end_turn is counted under a check rule.
- (low, wontfix-accepted) The row counts cannot see an update in place: Recheck is Interpret, which records nothing by contract; the doc now says so. reopen_if=Interpret or Judge gains a save.
- (low, by-design) The summary does not split runs or uncased decisions: the stdout form is the spec's (Design Notes); each file carries runRef and case.
- (low, reject) The Auto Run Result's "4 medium entries patched" against the triage log's 9: the fix edits the spec under review.
- (low, by-design) The name filter runs without `LC_ALL=C` and lets `.`/`..` through: a name never holds "/", and `.`/`..` fail on the redirect and are counted.
- (low, by-design) AC 8's "passes key-like" is vacuous for the new script (the rule is about sourcing lib-keys); `check_capture`'s own needle grep covers it.
- (note) `OcuTalon.Test.Eval.CaptureTool` ships in the IPM (Veto 6(v)) and is reachable from no web, REST, CSP, `SqlProc` or `WebMethod` entry: only a terminal user with ObjectScript rights can call it. The Capture tests rely on the production's runner items, as the class doc says.

## Design Notes

**The tags (C1).** Each tag is followed by its field; source lines are at the baseline.

DecisionPayload (inherited; L22, L29, L30):
- `outcome-unlisted`: outcome
- `reasons-blank`: reasons
- `confidence-missing`: confidence

DiagnosisPayload:
- L66 `outcome-not-act`: outcome
- L67 `cause-category-unlisted`: causeCategory
- L70 `evidence-over-max`: evidence
- L71 `cause-blank`: cause
- L73 `format-no-fix-element-blank`: elementAtFault
- L75 `format-fix-kind-unlisted`: fixKind
- L76 `format-fix-element-blank`: elementAtFault
- L77 `format-fix-summary-blank`: fixSummary
- L78 `format-fix-field-blank`: fixParameters.field
- L80 `rollback-fix-parameters`: fixParameters
- L81 `rollback-fix-summary`: fixSummary
- L82 `rollback-element-unlisted`: elementAtFault
- L84 `fix-kind-not-for-category`: fixKind
- L85 `fix-parameters-not-for-category`: fixParameters
- L86 `fix-summary-not-for-category`: fixSummary
- L89 `item-noun-blank`: itemNoun
- L91 `time-of-day-in-cause`: cause
- L91 `time-of-day-in-fix-summary`: fixSummary
- L95 `fix-parameters-check`: fixParameters

Notes on the tags:
- The `rollback-*` rules are the branch where the category's fix kind is one that `DiagnosedFor` lists, which today is only setting_change's rollback_setting.
- A fixKind such as "none" on a setting_change hits `fix-kind-not-for-category`. The C2 example "fixSummary on a setting_change that should carry no fix" is `fix-summary-not-for-category`.
- Why param 2 plus a list:
  - The message (param 1) holds reply values, so it can never be shown. A second parameter is kept by `$$$ERROR` and read by `DecomposeStatus` (Decide already reads it as `limit` at L1075).
  - Checking it against the reply class's own compiled list means a value can never pass as a tag, even if some other code puts one there.
  - The same list gives the harness the field. A subclass repeats its parent's pairs first, and AC 3 pins this, rather than walking the class tree.
- Format: "ERROR #5001 rule <tag>" keeps the "ERROR #5001" prefix, so a `[ "ERROR #5001"` check anywhere stays true.

**Where the tag is visible.** It is visible in:
- the Type 3 event-log warning of the decision's trace session in OCUTALON (Management Portal Event Log; Visual Trace, which admins and trace-role users open from a decision);
- the harness's stdout and files.

It is visible nowhere else:
- not in the catalog, a notice, the card, the chat, the README or a Decision row;
- not in the model's input: the readers take Type 2 and 6 rows of watched namespaces.

It is an internal diagnostic name, not public text (Veto item 1).

**The harness (C0).** Shape and guarantees:
- **Why inside `eval/run.sh`.** The ruling says the harness runs after each eval run and before teardown.
  - `eval/run.sh`'s teardown is its own exit trap (`live_start`), so there is no moment between the run and the teardown for a separate command.
  - The eval-scripts rule lets `eval/*.sh` reach the container only through `lib-live.sh`'s `dc`, which needs that run's project and files.
  - So the key-holder runs the same command with one more variable, and the capture is the run's last step before teardown: `OCUTALON_EVAL_CAPTURE_DIR="$E/<run folder>/capture"`, added inside the subshell of `release-evidence/ab-1389/sequence.sh`'s form, before `bash eval/run.sh --release-candidate`.
  - The harness reads no key and passes none. Compose interpolation on its `dc` calls is the same as on every other call of the run.
- **Rule and field per reply.** `problem` from `Recheck`:
  - the stage is `check` (it starts with `CHECKFAILED`), `after the filter`, or `no reason left after the filter`;
  - the parts are what follows "accepts: " or "payload: ", split on "; ";
  - rule = the first part: the tag for "ERROR #5001 rule <tag>", else the part verbatim (fixed words, a compiled property name, positions, limits and computed lengths: RefusalText's contract);
  - field = the tag's field, else the `%JSONFIELDNAME` of a named compiled property, else empty (a #9404's field name came from the reply and appears only in the file's raw text);
  - fixed rule names: `no reply`, `no reply text`, `passes the check`, `no reason left after the filter`.
- **stdout** (the run's log, counts and rule names only; case names are eval folder names):
  ```
  CAPTURE 7 fallback decision(s) (decide 1, diagnose 6), 9 reply(s), 9 file(s)
  CAPTURE reason invalid: 7
  CAPTURE rule fix-summary-not-for-category field fixSummary: 5
  CAPTURE rule confidence-missing field confidence: 2
  CAPTURE rule passes the check field -: 2
  CAPTURE case orders-target-to-review rule fix-summary-not-for-category: 3
  CAPTURE folder <the folder given>
  ```
- **A file** `<n>-<ref>-<attempt>.json`: {decisionRef, kind, case, runRef, fallbackReason, runner, replyClass, attempt, finishReason, stage, rule, rules, field, problem, failureText, text}. `text` is the raw `Reply.Text`. `summary.json` holds the counts.
- **What it cannot see:** a reply that never reached the store (a timer fallback has none; a late reply arrives after the Decision row and is still stored and found); text that a purge removed (none runs on a throwaway); more than 5 parts (RefusalText's cap).

**Decisions taken at implementation (small ambiguities, lane C):**
- A missing evidence folder is refused ("CAPTURE refused: ...", no session, return 0), as the Planner's condition (b) rules, so the spec's `mkdir -p` is not done; the key-holder makes the folder first (`mkdir -p "$E/<run folder>/capture"` before the command). The refusal of a folder inside the checkout also returns 0, so only a session that prints nothing gives the "CAPTURE failed" line.
- `CaptureTool.Run` makes the container folder itself; the shell removes it after the copy. summary.json is written only when at least one decision was found (scenario 8: no file), and counts itself (files = replies + 1).
- Review fixes: `CaptureTool.Parse` skips an empty part (and a part with an empty rule name), so a problem with no part keeps the rule `no check` and `Count` never gets an empty rule; `Run` returns an error status for a folder that normalises to "". `eval/capture-fallbacks.sh` counts the files named by `CHK|file|` and not copied (a failed `cat`, an empty copy, an unsafe name) and prints `CAPTURE copy failed: <n> file(s) were not copied` before the folder line, still returning 0. `TestOneReplyPerRule` seeds five more replies (an over-long evidence element, a mistyped reasons, the after-the-filter stage, no reason left after the filter, a cut_off fallback) and asserts `stage`, `rule` and `field` of each; `Test.Eval.Capture` removes its temp file. Rule `capture` pins the copy-failed line (stub variants RCF_CAPCAT fail and empty) and the session script's `CaptureTool).Print(` and `CHK|run|1`.
- One more fixed rule name, `no check`, for a reply that the tool could not judge (no request body, no reply class or filter class, or Recheck threw). It does not occur in the measured run.
- `TestRecordsAndLogsNothing` and `TestRecheckIsSilent` count the event-log rows of the test's own job and the headers of the bridge's messages and of no body, not the global max IDs: the production's background work writes rows in other jobs, and the first draft was seen to flake after a warm reload. The mutations above each change one of the counted things.
- The code-rule pin for Recheck lives in `Test.Eval.Capture` (a footprint file) and scans the web, channel, core, tool, agent and MCP packages for any code line naming Recheck, and every non-test class but Decide for a line naming `Process.Decide` and Recheck together.
- The direct-run usage line goes to stderr. The test rcf_session gained RCF_CAPTURE, RCF_CAPDIR, RCF_CAPMAKE and RCF_CAPEMPTY, and the stub gained a `CaptureTool` session branch (RCF_CAP, RCF_CAPMARK) and a cat of the capture folder (RCF_CAPTEXT).

**AD:** no AD text changes (Veto item 4). AD-8's rule (spine "AD-8: The bridge alone decides when a reply is unusable") classifies a reply and does not specify the words of the reply-check warning. Every refused reply still falls back with `invalid`. If the Planner wants a record, the sentence to add after "Content that doesn't validate is unusable (AD-8)." (spine L271) would be: "The reply check's warning names each refused rule of a reply class's %OnValidateObject by a fixed tag that the class lists in REFUSALRULES, never by a value of the reply (DW-1421)."

**Ledger inbox:** DW-1421 (C0, C1). Its status line is recorded per the run's DW process at merge, through `ledger.sh append`.

## Veto items

| # | Gate item | What | Recommendation |
|---|-----------|------|----------------|
| 1 | (a) New public text | None. The 22 tags and the "ERROR #5001 rule <tag>" form are internal diagnostic names. They appear only in the Type 3 event-log warning of the decision's trace session (Management Portal Event Log and Visual Trace, for admins and trace-role users) and in the capture harness's stdout and evidence files. No catalog key, notice, card, chat text, README line, Decision row or model input changes. | Approve as internal. |
| 2 | (b) Cross-lane edits | `Bridge/Process/Decide.cls`, `Bridge/Msg/DecisionPayload.cls`, `Watch/Msg/DiagnosisPayload.cls`, the new `Test/Eval/CaptureTool.cls` and `Test/Eval/Capture.cls`, `Test/Watch/Payload.cls`, `Test/Bridge/ReplyCheck.cls`, `Test/Agent/RememberDecision.cls`, `eval/run.sh`, the new `eval/capture-fallbacks.sh` and `docker/tests/test-eval-set.sh` are Lane A. Lane C makes the edits under the Planner's DW-1421 C0/C1 ruling. At plan time no unmerged `OCT-*` branch touches these files. | Grant. |
| 3 | (c) Stored data or schema | None. No persistent class or storage changes (DecisionPayload and DiagnosisPayload are not persistent; only parameters and error arguments change). The harness reads Decision, CaseResult, Ens headers and bodies. It writes only files in the container's `/tmp/ocutalon-capture/` (removed after the copy) and in the evidence folder outside the checkout. | Approve, with no migration. |
| 4 | (d) Architecture change | None. AD-8's text is unchanged: it does not specify the warning's words, and every refused reply still falls back `invalid`. An optional record sentence is in Design Notes, verbatim. | Approve with no AD change. |
| 5 | (e) Product behaviour change | Refusal diagnostics name the rule. The reply-check warning reads "ERROR #5001 rule <tag>" instead of "ERROR #5001" for each `%OnValidateObject` rule of DiagnosisPayload and the three of DecisionPayload (so triage refusals too). The time-of-day rule is two rules with the same message. A fix kind's parameter refusal is wrapped in the tagged error, its own reason embedded. Nothing else: the same replies are refused, with the same fallback. `eval/run.sh --release-candidate` gains the opt-in capture (`OCUTALON_EVAL_CAPTURE_DIR`), which no workflow sets. | Approve. |
| 6 | Design beyond the ruling | (i) Tagging the three inherited DecisionPayload rules, which a diagnose reply can break first (confidence missing is the demo's known Haiku shape); it changes the `DEMOTAIL` and row 9 pins. (ii) The harness runs inside `eval/run.sh`, through an opt-in variable, as its last step before the exit-trap teardown, rather than as a separate command: no separate moment exists, and eval-scripts allows container access only through the run's `dc`. (iii) A public `Decide.Recheck`. (iv) Decide (triage) fallbacks are captured too, against their own reply class. (v) The entry lives in `OcuTalon.Test.Eval`, which ships in the IPM like every OcuTalon class, because no unshipped package exists. | Approve. |

## Public text

None new. The tags and `CAPTURE` lines are internal diagnostics (Veto item 1). No catalog key, sentence or UI string is added or changed.

## Spec gate rulings (Contest Planner, ~10:30Z Nov 16, BINDING): C0 + C1 APPROVED, both deviations included

- C1: `REFUSALRULES` is an ALLOWLIST. PIN, with a mutation, that a reply value can NEVER appear after "rule" in the refusal text.
- Deviation 1 (the harness inside `eval/run.sh`): opt-in through `OCUTALON_EVAL_CAPTURE_DIR` ONLY; no workflow sets it. It runs after the report numbers are final. PIN that `run.sh` without the variable gives a byte-identical report. Refuse a folder inside the checkout AND a missing folder.
- `Decide.Recheck`: unreachable from any REST, Telegram or chat path. PIN that it saves nothing, fires nothing and logs nothing.
- Deviation 2 (the three inherited DecisionPayload rules tagged): APPROVED, no A/B; keep the two updated pins (`Test.Bridge.ReplyCheck` row 9, `Test.Agent.RememberDecision` DEMOTAIL).
- When pushed, the lead sends the sha and the EXACT key-holder command.

## Verification

Use a lane C throwaway only (Rule 21), never a dev slot. Set these on every `ci/iris.sh`, `ci/warm.sh` and `eval/run.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=0 stage=<stage>'`.
- Warm runs add `OCUTALON_WARM=1 OCUTALON_RUN_TAG=<warm tag>`.
- Fresh runs leave `OCUTALON_WARM` unset.
- Run one test class (or `Class:Method`) per foreground call, `timeout: 600000`, each under about 3 minutes, never two test calls in one message. Task 0 item 5 runs in the background.
- No model and no key anywhere: `--on-mock` unsets any key.

**Commands:**
- (once) `ci/warm.sh up` with the warm tag, then Task 0 items 1 to 4 (item 4's second half after the edits).
- (loop) Warm, each expected to pass:
  - `ci/iris.sh class OcuTalon.Test.Watch.Payload`;
  - `OcuTalon.Test.Bridge.ReplyCheck`;
  - `OcuTalon.Test.Eval.Capture`;
  - `OcuTalon.Test.Fix.Validation`;
  - `OcuTalon.Test.Fix.Kind`;
  - `OcuTalon.Test.Bridge.CodeRules`.
- (loop) `EVAL_SET_ONLY="capture eval-scripts key-like" bash docker/tests/test-eval-set.sh`, then `EVAL_SET_ONLY="rc-flow"` and `EVAL_SET_ONLY="rc-stack run-guard rc-guard rules-flow"` (each call under 10 minutes; split further if needed).
- (once) Fresh, each expected to pass:
  - `OcuTalon.Test.Agent.RememberDecision`;
  - `OcuTalon.Test.Watch.Diagnose:TestDiagnosisVariants`;
  - `ci/iris.sh shard lane-a@Eval` (or the class list of the Eval area, split).
- (once) Task 0 item 5, in the background.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call: each exits 0.
- (once) `git diff --name-only 1de31e808` lists only the footprint files. No added line holds a non-ASCII character or an absolute local path. No capture file is inside the checkout (`git status --short` shows only the footprint).
- (once, at the end, also after a failure) `ci/warm.sh down` with the warm tag; `ci/iris.sh teardown` for the fresh and end-to-end tags.

**Mutations (Rule 19):**
- Write one `mutation:` line per mutation, as `mutation: <change> -> <test that went red>`.
- Revert each byte for byte (`cmp` against a copy taken before it), and check that `git status --short` and `git diff --stat` are as before.
- The planned mutations:
  - AC 1: `RefusalText`'s tag branch removed -> `TestRuleTags`, `TestRefusalTrace` red.
  - AC 1, one per pinned rule:
    - the tags of L81 and L86 swapped;
    - `time-of-day-in-fix-summary` given the cause's tag;
    - `confidence-missing` removed from L30;
    - the L95 wrap removed;
    - each -> `TestRuleTags` red (and `RememberDecision` for `confidence-missing`).
  - AC 2: `RefusalTag` returns the value unchecked -> `TestRefusalTextForms` row l red.
  - AC 3: the tag argument dropped from L85 -> `TestEveryRuleTagged` red.
  - AC 4: `Recheck` made to call `CheckReply` alone -> `TestRefusalTrace` (the "no reason left" row) red.
  - AC 5: `CaptureTool`'s field lookup returns "" -> `TestOneReplyPerRule` red.
  - AC 6:
    - `Lines` given each file's first 20 characters -> `TestLinesHoldNoReplyText` red;
    - the shell's safe-character filter removed -> rule `capture` red.
  - AC 7: a `$$$LOGINFO` added to `Run` -> `TestRecordsAndLogsNothing` red.
  - AC 8: the in-checkout guard removed -> rule `capture` red.
  - AC 9: the `-n "$OCUTALON_EVAL_CAPTURE_DIR"` test inverted -> rule `capture` and rc-flow red.

**Shared surfaces:** the reply-check warning text (pinned in `Test.Watch.Payload`, `Test.Bridge.ReplyCheck`, `Test.Agent.RememberDecision` and `Test.Watch.Diagnose`), `eval/run.sh`'s rc sequence (pinned by rc-flow and rc-stack), and the eval-scripts and key-like rules over `eval/*.sh`.

### Implementation record (lane C, 2026-11-16; Planner conditions (a) to (h) applied)

**Task 0 (lane-C throwaway, mock only, no key):**
1. Status mechanics, measured before any product edit (warm stack): `$$$ERROR($$$GeneralError, "t", "zz-tag")` gives `errors(1,"param")` 2, `errors(1,"param",1)` "t", `errors(1,"param",2)` "zz-tag", and `GetErrorText` "ERROR #5001: t". For a scratch `%JSON.Adaptor` class whose `%OnValidateObject` returns that error, `%ValidateObject` and `Decide.CheckReply` (its `cause`) keep param 2. `EmbedStatus(outer, inner)` of two 5001s: `DecomposeStatus` top-level count 1 (the outer, with its tag as param 2 and an `embeddedstatus`), and the inner text (60 parts, 1370 characters in all) is within the first 400 characters of `GetErrorText`. `AppendStatus` gives count 2. So param 2 survives and the embedded text is kept: `EmbedStatus` is used (no stop).
2. A real fallback's store (mock `[[mock:invalid-reply]]` through `Test.Watch.Diagnose`'s `SendBatch` path, scratch subclass): the diagnose Decision row is Fallback 1, `invalid`. One `OcuTalon.Bridge.Msg.Request` body carries its DecisionRef; its header is Decide -> DiagnosisAgent with SessionId equal to the row's TraceSessionId; the response header found by `CorrespondingMessageId` has `MessageBodyClassName` `OcuTalon.Bridge.Msg.Reply`; `Reply.Text` is exactly the reply of `ci/mock/scenarios/A/invalid-reply.json` (`{"outcome":"maybe","reasons":"none","confidence":2}`, FinishReason end_turn). `DiagnosisAgentRetry` did not answer (one request only). The SQL is the one in `CaptureTool.Attempts` (request headers joined to `OcuTalon_Bridge_Msg.Request` by body id and DecisionRef, then the response header by `CorrespondingMessageId`).
3. `Decide.ReplyClassOf` in an `iris session` in OCUTALON: DiagnosisAgent and DiagnosisAgentRetry `OcuTalon.Watch.Msg.DiagnosisPayload`, TriageAgent `OcuTalon.Bridge.Msg.DecisionPayload`; `Ext.Accessor.ClassFor("ReplyFilterClass", "", "Decide", .sc)` `OcuTalon.Checks.ReplyGuard` with sc OK.
4. No side effects: around `CheckReply` + `ReplyGuard.Filter` the event-log max ID, the Decision and Usage counts and the Ens header max ID were unchanged (`log=125 dec=0 usage=0 hdr=11 hdrN=8` before and after), and so around `CaptureTool.Run` with item 2's Ref (`log=190 dec=1 usage=1 hdr=735 hdrN=98` before and after). `Run` wrote one reply file (text equals the scenario's) and summary.json, the rule `ERROR #9406 on Reasons`, field `reasons`, stage `check`, runner DiagnosisAgent, attempt 1.
5. End to end, `OCUTALON_EVAL_CAPTURE_DIR=<folder outside the checkout> OCUTALON_RUN_TAG=e0dw1421ie bash eval/run.sh --release-candidate --on-mock` (lane C, run in the background with bounded polls): exit 0, `VERDICT blocked` ("the verdict is blocked (0 of 3 attempt(s) met every target)"), 236 s (a first run before a small summary fix: 285 s, same lines). The CAPTURE lines, before the REPORT line: `CAPTURE 43 fallback decision(s) (decide 12, diagnose 31), 43 reply(s), 44 file(s)`; `CAPTURE reason invalid: 43`; `CAPTURE rule fix-parameters-check field fixParameters: 31`; `CAPTURE rule ERROR #5035 field -: 12`; 17 `CAPTURE case <case> rule <rule>: <n>` lines (13 cases with fix-parameters-check, 1 to 3 each, and the four user-turn-* cases with `ERROR #5035`, 3 each); `CAPTURE folder <folder>`. 44 files in the folder (43 replies plus summary.json, which says files 44, replies 43). No file's text (its first 40 characters, for each of the 43) is in the run's output. As the spec expects, the mock's one diagnosis (repair_resend of OrderDate) fails the fix kind's check for the incidents whose sample lacks that field: all 31 diagnose fallbacks are `fix-parameters-check`; the 12 decide fallbacks are replies that are not JSON (the mock's default text), `ERROR #5035`. No fallback of this run is a `DiagnosisPayload` tolerance case: the real-model measurement is the key-holder's.

**Tests and scripts (final tree):** warm: `Test.Watch.Payload` (TestRuleTags, TestEveryRuleTagged and the changed TestRefusalTrace included), `Test.Bridge.ReplyCheck` (row 9 and rows k, l, m), `Test.Agent.RememberDecision` (DEMOTAIL), `Test.Eval.Capture` (5 tests), `Test.Bridge.Decide`, `Test.Fix.Validation`, `Test.Fix.Kind`, `Test.Bridge.CodeRules` all pass. Fresh: `Test.Watch.Diagnose:TestDiagnosisVariants` passes (its warning still ends "ERROR #9406 on Reasons"); `ci/iris.sh shard lane-a@Eval` passes (24 classes, `Test.Eval.Capture` among them). `docker/tests/test-eval-set.sh` passes all rules (the new `capture` rule, `rc-flow`, `rc-stack run-guard rc-guard rules-flow`, `eval-scripts`, `key-like` and the rest, in four calls). `test-class-rules.sh` and `test-boundaries.sh` exit 0. The spine lint (`lint_spine.py`) still gives 12 findings, all low (the baseline). No workflow, compose file or class sets `OCUTALON_EVAL_CAPTURE_DIR` (grep of `.github/`, `ci/`, `docker/` finds it only in the rule `capture`'s own text). The footprint is the files of the intent contract; no added line holds a non-ASCII character or an absolute local path.

**Pins for the Planner's conditions:** (a) `TestRefusalTextForms` rows k, l, m (a marker, a lower-case value with the form of a tag, a tag of another class, a class that does not exist and a `tag:field` pair as the second parameter all give the bare "ERROR #5001"). (b) rule `capture`: with the variable unset or empty, the output, the calls and the report folder are the same byte for byte (epoch, pid, durations and the random work folder masked) with and without `eval/capture-fallbacks.sh` in the tree; set, the report folder and the rest of the output are the same as unset, so the capture runs after the numbers are final; the folder inside the tree and a missing folder are each refused with no session and no file. (c) `Test.Eval.Capture` `TestRecheckIsSilent` (log rows of the job, Decision, Usage and bridge-header counts, four replies and a usable one) and `TestRecheckIsUnreachable` (no web, channel, core, tool, agent or MCP class names Recheck; no class but Decide names Recheck of Decide).

**Mutations (Rule 19; each reverted with `cp` from a copy taken before it and checked with `cmp`, and `git status --short` and `git diff --stat` were the same as before each):**
- mutation: RefusalText's tag branch removed (`Set part = part_" rule "_tag` -> `Set part = part`) -> Test.Watch.Payload TestRuleTags (all 22 rows) and TestRefusalTrace (key in a refused value, invalid after the filter) red.
- mutation: the tags of `rollback-fix-summary` and `fix-summary-not-for-category` swapped -> Test.Watch.Payload TestRuleTags (both rows) red.
- mutation: `time-of-day-in-fix-summary` given the cause's tag -> Test.Watch.Payload TestRuleTags and TestEveryRuleTagged red.
- mutation: `confidence-missing` removed from DecisionPayload's rule -> Test.Watch.Payload TestRuleTags and TestEveryRuleTagged, and Test.Agent.RememberDecision TestProbeShapeIsTheDemoWarning (DEMOTAIL) red.
- mutation: the fix-kind wrap removed (`Quit sc`) -> Test.Watch.Payload TestRuleTags and TestEveryRuleTagged red.
- mutation: RefusalTag without the allowlist (`Quit value` after the form check) -> Test.Bridge.ReplyCheck TestRefusalTextForms rows l (a value that has the form of a tag, a lower-case value with a hyphen) and m (a tag of another class) red.
- mutation: RefusalTag returns the value unchecked (form check and allowlist both gone) -> Test.Bridge.ReplyCheck TestRefusalTextForms rows l (the marker, the form of a tag), m red.
- mutation: the tag argument dropped from `fix-parameters-not-for-category` -> Test.Watch.Payload TestEveryRuleTagged and TestRuleTags red.
- mutation: Recheck made to call CheckReply alone -> Test.Watch.Payload TestRefusalTrace (no reason left after the filter, invalid after the filter, a usable reply) red.
- mutation: CaptureTool's field lookup returns "" -> Test.Eval.Capture TestOneReplyPerRule (the field of each rule) red.
- mutation: each file name in the summary given the first 20 characters of its text (`Lines` then holds them) -> Test.Eval.Capture TestLinesHoldNoReplyText red ("nor any 10 characters of it").
- mutation: `$$$LOGINFO` added to CaptureTool.Run -> Test.Eval.Capture TestRecordsAndLogsNothing (the log count and the source scan) red.
- mutation: `$$$LOGINFO` added to Decide.Recheck -> Test.Eval.Capture TestRecheckIsSilent red (the warning row cleaned up).
- mutation: a Decision row saved in Decide.Recheck -> Test.Eval.Capture TestRecheckIsSilent red (row removed).
- mutation: a Usage row saved in Decide.Recheck -> Test.Eval.Capture TestRecheckIsSilent red (row removed).
- mutation: an Ens message header saved in Decide.Recheck -> Test.Eval.Capture TestRecheckIsSilent red (header removed).
- mutation: a call of Decide.Recheck added to OcuTalon.Web.BodyLimit -> Test.Eval.Capture TestRecheckIsUnreachable red.
- mutation: the shell's safe-character filter removed (`case "" in` in capture_value) -> rule capture red (the planted field is shown, not "(withheld)").
- mutation: the in-checkout guard removed (capture_inside returns 1) -> rule capture red (a folder inside the checkout is not refused).
- mutation: the `-n "$OCUTALON_EVAL_CAPTURE_DIR"` test inverted in eval/run.sh (the original line kept as a comment so that the bad samples still apply) -> rule capture red and rule rc-flow red (exit 1 for the unset variable).
- mutation: CaptureTool's `FieldOf` given `Quit ""` after the tag branch (so the import-type refusals lose their field) -> Test.Eval.Capture TestOneReplyPerRule (the evidence element and the mistyped reasons rows, field `evidence` and `reasons`) red.
- mutation: the `Parse` literal " refused the filtered payload: " changed -> Test.Eval.Capture TestOneReplyPerRule (cause-blank counted 2, the after-the-filter row's stage and rule) red.
- mutation: the `reason '= "invalid"` branch of CaptureTool's `Reply` deleted -> Test.Eval.Capture TestOneReplyPerRule (the cut_off fallback's rule `passes the check`, counted 2) red.
- mutation: the status of the capture `cat` ignored in eval/capture-fallbacks.sh (the emptiness check kept) -> rule capture red (the copy that fails after some text gives no `CAPTURE copy failed` line).
- mutation: the emptiness check (`[ ! -s ... ]`) removed in eval/capture-fallbacks.sh (the status check kept) -> rule capture red (the empty copy gives no `CAPTURE copy failed` line).
- mutation: the `Print(summary)` line deleted from the printf list of eval/capture-fallbacks.sh -> rule capture red (the capture session does not print the summary).
- The rule's own bad samples are each the real script with one edit and each is flagged for its reason: no script, no run.sh, one code line naming `.env`, the key variable, curl, wget, /v1/, api., PointKeys, LIVE_SESSION_ENV or the container tool, no usage exit, unguarded folder, a missing folder made, no filter, no copy, a copy that prints the text, always capturing, inverted test, never capturing, a failed capture that fails the run, the capture before the result, the capture after the REPORT line, a capture that writes into the report folder.

### Code review record (lane C, 2026-11-16; tags e0dw1421c*)

Runs, every stack command through the lane-C wrapper, no model and no key: warm `Test.Eval.Capture` (10 tests), `Test.Watch.Payload`, `Test.Bridge.ReplyCheck` and `Test.Bridge.Decide` pass before and after the patches; fresh `ci/iris.sh shard lane-a@Eval` passes (24 classes, 320 s); `docker/tests/test-eval-set.sh` passes in three calls (`capture eval-scripts key-like`, `rc-flow`, `rc-stack run-guard rc-guard rules-flow`) with the new samples `bad-one-checkout`, `bad-no-name-filter` and `bad-failed-copy-kept` each flagged for its reason; `test-class-rules.sh` and `test-boundaries.sh` exit 0.

Mutations (each applied to one copy, run warm, reverted with `cp` and checked with `cmp`; `git status --short` and `git diff --stat` were the same before and after):
- mutation: `Do ..Clear(folder)` deleted from CaptureTool.Run -> Test.Eval.Capture TestOneReplyPerRule red (the second run leaves the first run's files).
- mutation: `If summary.decisions {` -> `If 1 {` in CaptureTool.Run -> Test.Eval.Capture TestNoFallbackWritesNoFile red (a file and its count with no decision).
- mutation: the raw empty-folder check of CaptureTool.Run disabled (`If 0 {`, the old place after NormalizeDirectory) -> Test.Eval.Capture TestNoFallbackWritesNoFile red ("an empty folder is an error").
- mutation: the no-check branch of CaptureTool.Reply gives `..#PASSES` -> Test.Eval.Capture TestUncheckableReplyIsCounted red.
- mutation: an empty Ens.MessageHeader saved in Decide.Recheck on every call -> Test.Eval.Capture TestNothingIsWrittenAnywhere (Run and the four Recheck rows) and TestRecheckIsSilent red; the same header saved on the second Recheck call of the process only (one try) -> TestRecheckIsSilent stays green (background work in one try does not fail it).
- mutation: the field of `cause-blank` changed to `causes` in DiagnosisPayload's REFUSALRULES and in Test.Watch.Payload RuleTags together -> Test.Watch.Payload TestEveryRuleTagged red (the field is not a JSON name of the class); TestRuleTags stayed green.
- mutation: an untagged `$SYSTEM.Status.Error(5001, "zz")` rule added to DiagnosisPayload's %OnValidateObject -> Test.Watch.Payload TestEveryRuleTagged red.
- mutation: a code line naming TriageAgent added to CaptureTool.Run -> Test.Eval.Capture TestRecordsAndLogsNothing red.
- The shell pins are the rule's bad samples: `bad-one-checkout` (a checkout that git lists is not refused), `bad-no-name-filter` (an unsafe name is copied), `bad-failed-copy-kept` (a failed or empty copy leaves its file), each flagged; `bad-logical-path` follows the new `CDPATH= cd --` line.

## Review Triage Log

### 2026-11-16 - Review pass
- verdicts: 30 findings - high 0, medium 9, low 19, false 2, maybe-false 0
- findings:
  - `[medium]` `[patch]` Blind 1: Parse can push an empty rule and Count then raises a null subscript, aborting the capture - patched: empty parts skipped, no usable part keeps `no check`.
  - `[false]` `[reject]` Blind 2: a fallback that is not `invalid` is counted as `passes the check` - spec I/O row 13 says exactly this; the reason is counted separately in the summary.
  - `[low]` `[reject]` Blind 3: the `fix-parameters-check` wrapper hides the inner reason - spec-bound (Design Notes: the kind's inner reason is embedded, not shown); the raw text is in each file for a re-check; closed by-design.
  - `[medium]` `[patch]` Blind 4: Parse and the stage branches have no test - patched with five seeds and stage assertions in TestOneReplyPerRule, three mutations.
  - `[low]` `[reject]` Blind 5: Snap counts global tables - the counts were scoped after one observed flake and the class was green repeatedly; wontfix-accepted, reopen_if=Test.Eval.Capture flakes on a stack with a running production.
  - `[medium]` `[patch]` Blind 6: a failed copy in capture-fallbacks.sh is silent - patched: `CAPTURE copy failed: <n> file(s) were not copied`, pinned by rule capture with two mutations.
  - `[low]` `[reject]` Blind 7: the evidence folder is not scanned for key-like text - no key exists in a lane or on a mock stack, and the folder is outside the checkout; wontfix-theoretical for the lane, the key-holder's own run keeps its existing scan of the report pair.
  - `[low]` `[reject]` Blind 8: REFUSALRULES is repeated by hand in three places - the spec orders the repetition and AC 3 (TestEveryRuleTagged, TestRuleTags) pins both lists; no divergence is reachable without a test going red.
  - `[low]` `[patch]` Blind 9: Run returns OK with no output for an empty folder - patched with the Parse fix (an error status).
  - `[low]` `[reject]` Blind 10: attempt 2 (retry) is seeded only - recorded as a residual risk; the pairing uses the same SQL as attempt 1 and is exercised by the seeded second attempt.
  - `[low]` `[reject]` Edge 1: the SQL status in Run, Attempts and CaseOf is not checked - the tables are the product's own; wontfix-theoretical.
  - `[low]` `[reject]` Edge 2: an exception mid-loop aborts the run - needs a corrupt store row; wontfix-theoretical, the empty-rule trigger that was reachable is patched (Edge 7).
  - `[low]` `[reject]` Edge 3: a failed Put counts the reply but writes no file - the shell's file count and copy-failed line expose a gap; wontfix-theoretical (a disk error).
  - `[medium]` `[patch]` Edge 4: the shell copy loop ignores a failed cat - same root cause as Blind 6, patched.
  - `[low]` `[reject]` Edge 5: the session's CHK|error code is discarded - the line only says "CAPTURE failed"; the key-holder can re-run; wontfix-accepted, reopen_if=a capture failure with no known cause.
  - `[false]` `[reject]` Edge 6: a tagged error with an embedded 5802 gives "ERROR #5001 on X rule <tag>" - DecomposeStatus gives one top-level error for the EmbedStatus outer (Task 0 item 1), so RefusalPart has no property; TestRuleTags pins "ERROR #5001 rule fix-parameters-check" exactly.
  - `[medium]` `[patch]` Edge 7: Parse with an empty part or no "accepts" segment gives an empty rule - same root cause as Blind 1, patched.
  - `[low]` `[reject]` Edge 8: Recheck drops Interpret's sc - sc is an error only when a payload that passed cannot be exported, which a valid object does not do; wontfix-theoretical.
  - `[low]` `[reject]` Edge 9: the Recheck-unreachable scan covers six packages plus a same-line pattern - the scope the Planner's condition (c) asks for (REST, Telegram, chat paths); by-design.
  - `[low]` `[reject]` Edge 10: Snap counts only bridge and empty bodies - the bodies that Recheck and Run could send; accepted with Blind 5.
  - `[low]` `[reject]` Edge 11: the CheckFix inner reason is not shown - same as Blind 3, by-design.
  - `[low]` `[reject]` Edge 12: AC 7 says max IDs, the test counts the job's rows - recorded decision (a global max flaked after a warm reload); accepted with Blind 5.
  - `[low]` `[reject]` Edge 13: a failed Put leaves replies counted without a file - same as Edge 3.
  - `[medium]` `[patch]` Gap 1: FieldOf's property branch has no test - patched: evidence and mistyped-reasons seeds, mutation recorded.
  - `[medium]` `[patch]` Gap 2: the filter-stage and non-invalid branches have no test - patched with the seeds of Blind 4, two mutations.
  - `[medium]` `[patch]` Gap 3: the capture session text is not pinned - patched: rule capture requires `CaptureTool).Print(` then `CHK|run|1`, mutation recorded.
  - `[medium]` `[patch]` Gap 4: a silent partial copy - same as Blind 6, patched.
  - `[low]` `[reject]` Gap 5: global counts in the silence tests - same as Blind 5.
  - `[low]` `[patch]` Gap 6: OnBeforeOneTest leaves a temp file - patched (removed in OnAfterOneTest); the class's documented dependence on the production's runner items stays, by the spec's own Task 0 item 3.
  - `[low]` `[reject]` Gap 7: source-text tests (TestEveryRuleTagged, the Recheck scan) - AC 3 and the Planner's condition (c) ask for a code-rule test, and TestRuleTags pins the same tags by behaviour; by-design.
  - Intent alignment audit: descriptive, no findings; it names the real-model measurement as the key-holder's.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** C1: the 22 `%OnValidateObject` rules (3 inherited, 19 own) carry a fixed tag as the status's second parameter, listed per reply class in the allowlist `REFUSALRULES`; `Decide.RefusalText` shows "ERROR #5001 rule <tag>" only for a listed tag, so a reply value never follows "rule". The time-of-day rule is two rules and the fix kind's check is wrapped in the tagged `fix-parameters-check`. C0: `OcuTalon.Test.Eval.CaptureTool`, `eval/capture-fallbacks.sh` and an opt-in step in `eval/run.sh` (only when `OCUTALON_EVAL_CAPTURE_DIR` is set, after the result and before the REPORT line) write one file per fallback reply and print counts and rule names only. `Decide.Recheck` is the public, silent form of Conclude's check.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`, `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls`: tags and `REFUSALRULES`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `RefusalText`, private `RefusalTag`, public `Recheck`.
- `src/ocutalon/cls/OcuTalon/Test/Eval/CaptureTool.cls`, `Test/Eval/Capture.cls` (new): the entry and its tests.
- `eval/capture-fallbacks.sh` (new), `eval/run.sh`: the opt-in capture step.
- `docker/tests/test-eval-set.sh`: the rule `capture`.
- `Test/Watch/Payload.cls`, `Test/Bridge/ReplyCheck.cls`, `Test/Agent/RememberDecision.cls`: the tag pins and updated pins (row 9, DEMOTAIL).

**Review.** 30 findings: high 0, medium 9, low 19, false 2. Patched (one bounded iteration): the empty-rule abort in `Parse` and an error status for an empty folder; the silent failed copy (`CAPTURE copy failed: <n> file(s) were not copied`); test seeds and assertions for the import-type field, the after-the-filter stage, `no reason left after the filter` and a non-invalid fallback; the pin of the session text; the temp file of the Capture test. Nothing deferred. Rejected with their reasons are in the Review Triage Log.

**Follow-up review recommended:** false (no high was patched; 4 medium entries patched, 0 high).

**Verification performed.** See `## Verification` (Task 0 results, 26 mutation lines, class runs, eval-set rules, class-rules, boundaries, spine lint at its 12 low baseline). After the review patches: `Test.Eval.Capture` warm, eval-set rules `capture`, `rc-flow`, `eval-scripts`, `key-like`, and `test-class-rules.sh` passed on the patched tree; `test-boundaries.sh` and the `capture` rule were re-run by the lead and passed. No stack is up, no `.env` was read, no model was called.

**Residual risks.** The retry (attempt 2) pairing was measured only on seeded data (the mock's retry runner did not answer). A real-model run is the key-holder's measurement; the mock's 31 diagnose fallbacks are all `fix-parameters-check` because the mock's repair_resend names a field absent from most samples.

## QA Record (lane C, 2026-11-16; stage qa, tags e0dw1421q*)

No model, no key: the runs used the CI mock, `ANTHROPIC_API_KEY` unset, and no `.env` was read. Product code is unchanged; only test files and this record changed.

**The four Planner conditions**
1. A reply value never follows "rule". Proved by `TestRefusalTextForms` rows k, l, m, with a gap closed: the old rows used values that share nothing with the list, so a loose allowlist test (the colon or the leading comma of the match dropped, or a plain substring test) passed all of them. New row n in `Test.Bridge.ReplyCheck`: a field name, the start and the end of a tag are the bare "ERROR #5001", a whole tag from the middle of the list is shown.
   - mutation: RefusalTag's match without the closing colon (`rules [ (","_value)`) -> Test.Bridge.ReplyCheck TestRefusalTextForms row n (confidence, outcome, reasons, confidence-miss) red; the old rows stayed green.
   - mutation: RefusalTag's match without the leading comma (`rules [ (value_":")`) -> Test.Bridge.ReplyCheck TestRefusalTextForms row n (missing, unlisted, blank) red.
   - mutation: RefusalTag's match as a plain substring (`rules [ value`) -> Test.Bridge.ReplyCheck TestRefusalTextForms row n (all seven values) red.
2. `eval/run.sh` without the variable is byte-identical. The existing rule `capture` pin is a real byte comparison (output, calls and report folder of two stub runs, with and without the script in the tree, also with the variable empty), but the report files there are the stub's text. A real check was added, run by hand on lane C (not a repeatable test: two runs of about 5 minutes each): `eval/run.sh --release-candidate --on-mock` twice on the same tree, A without the variable, B with `OCUTALON_EVAL_CAPTURE_DIR` set to an empty folder outside the checkout, each with its own report folder.
   - Both ended `VERDICT blocked`, exit 0. The stdout of B without its 22 `CAPTURE` lines equals A's after masking numbers and the tags. The 16 report files of each run have the same structure; every leaf that differs is a clock or a random reference (`durationMs`, `runRef`, `ref`, `maxMs`, `meanMs`, `since`, `builtAt`, `run`, `createdAt`, and the run reference in the first line of `set-n.md`), and after masking those the 16 files are equal.
   - B printed 43 fallback decisions (22 CAPTURE lines), 43 replies, 44 files (31 `fix-parameters-check`, 12 `ERROR #5035`), the folder line, then `REPORT`. No file's text (first 40 characters of each of 43) is in B's output. No stack of either run remained.
3. A folder inside the checkout and a missing folder are both refused. The existing pins used one folder of each kind. Gap closed in rule `capture` (`check_capture`, helper `cap_guard`): capture_fallbacks is sourced under stubs whose root is a link to the copy tree, and eight paths that lead into the tree (the tree, with a trailing slash, a subfolder, `..` inside and out, a link from outside, a link plus a subfolder, a relative `.`) must give "CAPTURE refused: ... inside the checkout" and no call; a file, a missing folder and an empty name must give "does not exist" and no call; a sibling whose name starts with the tree's, a folder outside, and a link inside the tree to a folder outside must get exactly one session.
   - mutation: the folder resolved with `pwd` instead of `pwd -P` (eval/capture-fallbacks.sh) -> rule capture sample bad-logical-path red ("that leads into the checkout is not refused as inside it").
   - mutation: the inside test as a prefix match without the slash (`case $1 in "$here"*`) -> rule capture sample bad-prefix-match red (the folder t-evidence is refused).
   - mutation: the checkout not resolved (`here=$root`, tested with a link as root) -> rule capture sample bad-no-root-resolve red.
4. `Decide.Recheck` unreachable and silent. The unreachability pin (`TestRecheckIsUnreachable`) is a source scan of the web, channel, core, tool, agent and MCP packages and stays; a grep of every `$ClassMethod(` with a method name in a variable (Install.Registry, Policy.Gate hooks) found none that takes a name from a request or a model. The silence pin counted only the job's event-log rows, Decision, Usage and the bridge's headers, so a save to any other table, an alert header or an audit entry passed. Gap closed with `TestNothingIsWrittenAnywhere`: the row count of every persistent table of the product (160, outside OcuTalon.Test), the headers whose body is not an OcuTalon class, and the OcuTalon entries of the IRIS audit log (with a control entry, so that zero means something), around `Run` and four `Recheck` calls. Measured idle on the warm stack: no table changed in 20 seconds.
   - mutation: an audit entry written in Recheck (`OcuTalon.Bridge.Audit.Write`) -> Test.Eval.Capture TestNothingIsWrittenAnywhere (Run and the four Recheck rows) red; TestRecheckIsSilent stayed green.
   - mutation: a HeartbeatBeat row saved in Recheck -> TestNothingIsWrittenAnywhere red; TestRecheckIsSilent stayed green.
   - mutation: an Ens.MessageHeader of body class Ens.AlertRequest saved in Recheck -> TestNothingIsWrittenAnywhere red; TestRecheckIsSilent stayed green.

**Harness stdout, hostile replies.** New `TestHostileRepliesStayOffStdout`: seven replies in diagnose and decide (a non-JSON text, an unknown key, a category, a cause, a reason, a fix summary, a fix field and an outcome, each holding a line end, a carriage return, a tab, quotes, a back slash, a bar, a line "CHK|file|../../evil.json", characters outside ASCII including one outside the basic plane, and the text "ERROR #5001 rule cause-blank"), a reply that is exactly a tag name, a failure reply with such a failure text, and a case name and a fallback reason that carry a line end and a bar. Results: the lines are ASCII, each is one CHK line of the shape of its kind (7, 4, 5, 5 and 3 fields), the file lines equal the files of the folder (no injected line), the rule counts are exactly the seeded ones, no fragment of a reply (evil, quoted, single, first line, pipe, back, cause-blank, "../") is in the lines, the case name and the reason come out cleaned, every file name is safe to copy, and each file holds its reply byte for byte (with the non-BMP character).
   - mutation: `Plain` returns the value -> TestHostileRepliesStayOffStdout red (an injected file line).
   - mutation: `Plain` translates the bar only -> TestHostileRepliesStayOffStdout red (the line shapes of the reason and the case).
   - mutation: `Put` without its UTF8 translate table -> TestHostileRepliesStayOffStdout red (six files hold other than the seeded text); every pre-existing test stayed green.

**The retry attempt (attempt 2).** Still only seeded (the mock's retry runner did not answer), but the seeded gap is closed: the old seed had both attempts answered in order. `TestAttemptsAreNumberedByRequest` seeds an unanswered first request with an answered retry (file `-2`, the retry runner), an answered first attempt with an unanswered retry (one reply), two unanswered requests (a decision with no reply), and a first answer stored after the retry's (still attempt 1). Request and answer seeding were split (`SeedRequest`, `SeedAnswer`; `SeedReply` calls both).
   - mutation: the attempt counter incremented after the unanswered `Continue` -> TestAttemptsAreNumberedByRequest red (the retry's reply became attempt 1); every pre-existing test stayed green.
   - mutation: `answered` counted for requests with no reply -> TestAttemptsAreNumberedByRequest red; every pre-existing test stayed green.

**Runs (final tree).** Warm lane C: Test.Eval.Capture (8 tests), Test.Watch.Payload and Test.Bridge.ReplyCheck passed. `docker/tests/test-eval-set.sh` passed all rules in four calls (capture, eval-scripts, key-like; rc-flow; rc-stack, run-guard, rc-guard, rules-flow; every other rule). `test-boundaries.sh` and `test-class-rules.sh` exit 0. Each mutation was reverted with `cp` from a copy and `cmp`; `git status` held only the test files before and after. No added line holds a non-ASCII character or an absolute local path.

**Findings for the lead (no product change made)**
- The inside-the-checkout guard compares with this checkout's root only. A folder in another checkout of the repository (the main checkout, or a sibling worktree) is not refused. Low: the key-holder's folder is outside every checkout in the sequence.
- The harness prints a tool-owned value (a case name, a reason) cleaned of bars and control characters, and the shell prints it as (withheld) when it holds a character outside its safe set, so a non-ASCII case name is withheld, not shown. By design.
- The real retry runner's reply (attempt 2) was never measured; only the seeded pairing is pinned.
- One `ci/iris.sh class` call of this stage ran without the lane-C variables because a shell chain stopped before the variables were set. It started and tore down a fresh throwaway of its own (project `ocutalon-class-local-*`, no lock folder, no published port, 128 s) and touched no other container. A wrapper that sets the variables was used afterwards.
