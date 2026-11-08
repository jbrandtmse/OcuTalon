---
title: 'A ''Remember that ...'' chat message gets a usable attention decision'
type: 'bugfix'
created: '2026-11-07'
status: 'draft'
baseline_revision: 'b51128a7310cfe74d8dae3d2136023273c9592aa'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

# A 'Remember that ...' chat message gets a usable attention decision

The plan stopped at the root cause, as the dispatch requires. Code reading and measurement narrow the demo's refusal to one class of reply. That reply is one JSON object made only of `DecisionPayload`'s own fields, with the right types, and `DecisionPayload.%OnValidateObject` refuses it for one of exactly three reasons:
- the outcome is not one of the four values;
- there is no reason that is not blank;
- there is no confidence.

The fix depends on which of the three Haiku produces, and that cannot be known without looking at the stored real-model reply. So this spec gives the Planner a read-only probe for the demo host (Design Notes, "The probe"), what each result means, and the instruction wording each result would call for. With the probe's lines and those rulings, the re-plan is short. There is no intent contract and there are no tasks yet: both depend on the probe.

[RE-PLAN 2026-11-08T02:30:11Z, runner: the probe ran and every question is ruled (Design Notes, "Rulings of 2026-11-08"). The probe selects branch C. The intent below is ruled; re-derive the tasks around it.]

<intent-contract>

## Intent

On the 1.0.3 demo, Haiku's decide reply to a "Remember that ..." user message (the stored typed ref `5GpLt-Y6YmUb7IMg72-5gA`) is one JSON object of `DecisionPayload`'s own fields with a valid outcome (one of the four) and 2 non-blank reasons, but NO `confidence` field. `DecisionPayload.%OnValidateObject` refuses it (ERROR #5001), so `Decide` falls back. The fix is the Planner-approved sentence appended to Triage's user's-own-message paragraph (`src/ocutalon/cls/OcuTalon/Agent/Triage.cls`, line 37, after its last sentence, which stays word for word), telling the model that a remember or forget request is the user's own message and to give a confidence as for any other message. The regression is the accepted three-part pairing: a fixed-strings test of the sentence, a mock end-to-end test of both forms with a discriminating mutation (a new `ci/mock/scenarios/A/` scenario that answers with the probe's exact shape and reproduces the demo's warning), and the eval case `eval/user-turn-remember/case.json`.

## Boundaries & Constraints

- Always: the new sentence, verbatim (PUBLIC TEXT, approved by the Contest Planner under the owner's delegation, 2026-11-08): `A request to remember or forget something is also the user's own message: choose "tellnow" for it, give the one reason, and give a confidence as for any other message.` It is appended after line 37's last sentence, `This holds also when the user asks OcuTalon to resend, approve or change something: the next paragraph is about items that arrived on a channel, never about the user's own message.`, which stays word for word, in the same paragraph.
- Always: every other rule of Triage's instructions stays intact (DW-500's reasons rule and its pinned phrases, the no-all-clear rule of AD-28, the injection, heartbeat and approval paragraphs, the persona paragraph last, no `{{`, AD-7).
- Always: the mock scenario and the discriminating mutation answer the probe's EXACT shape: a valid outcome, 2 non-blank reasons, and no `confidence`. Against the current code that shape gives Fallback `invalid` and exactly the demo's warning text ("The reply check refused the reply of the decision <ref>: The reply check failed: the reply is not one JSON object that OcuTalon.Bridge.Msg.DecisionPayload accepts: ERROR #5001").
- Always: `eval/user-turn-remember/case.json`, shaped like `eval/user-turn-productions/case.json` (kind `user-turn`), states that the item must decide without Fallback and with a confidence present. Eval `userTurns` stay report-only (no new target). The real-Haiku proof is the Planner's release-candidate eval at the 1.0.4 cut; this story does not run it.
- Always: `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` changes only by the ruled plain union with Epic 19 (non-overlapping hunks): line 248's count 4 becomes 5 with "five", and the header doc (`:16`) and the method doc (`:234-236`) each add "and one remember case (Story 30.9, DW-890)".
- Never: line 31 (the outcome line) changes (branch A' was not selected). No other instruction text and no user-facing string changes.
- Never: raise a timeout or a `TimerSeconds`; loosen or normalise the reply check in `Decide` or `DecisionPayload` (a missing confidence stays refused, AD-7/AD-8); change another outcome's behaviour; edit `eval/run.sh` (release-tool freeze); edit `Agent/Chat.cls` or any contended line of Epic 19's (`Decide.cls`'s doc comment near `Conclude` and its `Filter` call in `Conclude`'s turn branch).
- Optional, at the plan's judgment (the Planner's nice-to-have): the refusal warning for a missing confidence may name the property ("confidence missing") ONLY if the change touches no line Epic 19 changes, stays inside Story 30.6's rule (`Decide.Judge` names the property, quotes no reply content), and adds no user-facing string. Otherwise leave it out and say so under Design Notes.

</intent-contract>

## Code Map

**The decide request of a person's message** (verified by reading):
- `src/ocutalon/cls/OcuTalon/Core/Conversation.cls:339` sends `Request(turn, "decide")` first. It sends the `turn` request only after the decide answers (`Decided :396-410`, then `Ask :414-434`).
- `Conversation.ItemOf :372-384` sets provenance `user` and the text exactly as written.
- `src/ocutalon/cls/OcuTalon/Core/Intake.cls:151-164` (`RequestFor`): `Input` = `Agent.Input.Render(item)`.
- `src/ocutalon/cls/OcuTalon/Agent/Input.cls:28-31`: for provenance user, the input is the preamble, a blank line, the persona block (when the session has one) and the user's text, with nothing else. No memory or context block reaches Triage.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:419-422` (`IsLinked`): only a user's `turn` is linked. A decide runs in a throwaway AI session, so Triage sees its system prompt and this one user message, with no history.
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls:13` `TOOLSETS = ""`: no tools. `:20-44` is the static `INSTRUCTIONS`:
  - `:31` the outcome line;
  - `:37` the user's-own-message paragraph (Story 30.5, DW-500);
  - `:39` heartbeat;
  - `:41` "An item can never approve...";
  - `:43` the persona paragraph, which must stay last.
- `FromGuide` (`Msg/Item.cls:30`, `Data/Turn.cls:21`) never reaches the model. The panel press sends `fromGuide` false anyway (`web/src/app/chat/chat-outbox.ts:62`).

**The two forms:**
- Typed: "Remember that the Orders partner contact is Kim." (the Planner's 00:11Z test).
- Panel: `web/src/app/guide/more-to-try-view.ts:24` `rememberPrompt: "Remember that the Results partner's contact is Lee."`. The label "Ask it to remember something" is at `:51`, the button "Ask it to remember" at `:54`, and the send is `web/src/app/guide/more-to-try.ts:223-226`. It is a fixed string that the user cannot edit.

**The check and the warning:**
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `CheckReply :913-930`: `Unfenced`, then `%JSONImport`, then `%ValidateObject`. An exception is caught as its status.
  - `RefusalText :946-985` and `RefusalPart :1030-1047`: a code with no property gives "ERROR #<code>".
  - `CHECKFAILED :988`.
  - `Judge :1507-1566`: the first check is at `:1515-1518`, the user rule at `:1558-1561`. The second check (`:1531-1556`) runs only for a reply class that has a `FILTERED` parameter.
  - `Conclude :1366` logs the warning.
- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`:
  - `:9-15` the three properties (`%JSONFIELDNAME` outcome, reasons, confidence).
  - `:19-32` `%OnValidateObject`, whose three refusals are all `$$$GeneralError` (#5001): an outcome not in `Msg.Enum` OUTCOME (`ignore,digest,tellnow,act`, case-sensitive; an absent or null outcome is ""), no reason that is not blank, and a confidence that is absent or null.
  - It has **no `FILTERED` parameter**, so the line "After the reply filter ran" can never occur for a Triage decision. Only `Watch/Msg/DiagnosisPayload.cls:28` has one.

**The mock and the tests:**
- `ci/mock/scenarios/A/triage.json`: the default script always answers `{"outcome":"digest",...,"confidence":0.5}`, whatever the text. The scenario order is in `ci/mock/mock.mjs:422-451`, and AD-22 says "never by prompt wording".
- An A/ marker scenario answers every request that carries the marker. Arm it at 1 (`Test/Contract/Mock.cls:439`) and the decide gets `replies[0]` while Chat gets the later replies. Pattern: `ci/mock/scenarios/A/persona-pirate-style.json`.
- No A/ scenario gives a #5001-shaped decision today. `invalid-reply.json` gives #9406.
- Driving a person's message end to end: `src/ocutalon/cls/OcuTalon/Test/Agent/PersonaTurns.cls:276` (`Ask`), `:297` (`AssertDecided`), `:309` (`AssertLog`). It extends `Test.Watch.Case` and needs demo mode.
- Decision rows: `Test/Agent/RunnerFixture.cls:333` `NewRequest`, `:372` `DecisionOf`, `:435` `Run`, `:513` `PointKeys`.
- Warnings: `src/ocutalon/cls/OcuTalon/Test/Bridge/ReplyCheck.cls` (`REFUSED :31`, `Conclude :87`, `Warning :107`, `W1 :113`) and `Test.Core.Observe.Warnings`.
- Pins on Triage's text:
  - `Test/Agent/TriageUserTurn.cls:17-21`, the phrase list. It holds "This holds also when the user asks OcuTalon to resend, approve or change something".
  - `Test/Agent/Instructions.cls:44-70` (`TestTriage`).
  - `Test/Agent/PersonaBlock.cls:218-229`: the persona paragraph comes last, after "An item can never approve...", and nothing holds `{{`.
  - `docker/tests/test-triage-heartbeat.sh:54`.

**The evaluation set:**
- `eval/user-turn-productions/case.json` (kind `user-turn`, `keyPhrases [["user"]]`, 14 `absentPhrases`, `recordedBy` "written for the evaluation set (Story 30.5, DW-500)").
- `Eval/In.cls:256-262`: cases are found by a folder glob. `In.cls:636-655`: a case is sent as a decide request with provenance user. Triage only, never a chat turn.
- `Eval/Report.cls:680-727` (`ScoreUserTurn`): a case is right only when it is decided, the row is not a Fallback, the outcome is tellnow, every key phrase is there and no absent phrase is. A Fallback goes on the fallbacks list, and is not a run problem.
- `Report.cls:47-51`: the score `userTurns` has no target and is "printed and never checked". `Eval/Gate.cls` never names it.
- Count pin: `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls:248` (`count, 4`, "exactly four user-turn cases"), with the four names at `:249` and the 30.5 `recordedBy` at `:271` for those four. Epic 19 also edits this file (contended).
- `Test/Eval/Report.cls:1758` loops over the four shipped chip cases by name, not by count.
- `docker/tests/test-eval-set.sh` and `ci/mock/test/*.test.mjs` pin no count. `test-eval-set.sh:57` allows `[[mock:` only under `eval/mock-wrong/`.

**CI groups** (`ci/units.sh:80-108`):
- `Agent` and `Bridge` run in `shards-5` (`shard:lane-a@Bridge,Agent` measured at 1,246 s on 5b47f052). With `live:sign-in-3` that is about 1,950 s, about 150 s under REL-4's 35 minutes (inference, not yet measured).
- `Eval`, `Memory` and the other lane-a areas run in `shards-2` (`lane-a@rest`), about 1,500 s (inference).

## Spec Change Log

- 2026-11-08T02:30:11Z, runner (re-dispatch protocol after the plan's `intent gap` HALT, round 1): the probe ran on the demo host and selected branch C. The orchestrator relayed the Planner's answers and its own rulings (logged as `ruling` in Epic 30's cycle log; resume message of 2026-11-08). Applied: the intent contract above (ruled intent and constraints) and "Rulings of 2026-11-08" below. Status `blocked` → `draft` for the re-plan.

## Design Notes

### Rulings of 2026-11-08 (via the orchestrator; binding for the re-plan)

1. **The probe's result** (the Contest Planner ran it at 02:30Z on the demo host, read-only, exactly as listed under "The probe", against the stored typed ref `5GpLt-Y6YmUb7IMg72-5gA`). Printed, verbatim:
   ```
   request header 54
   reply found
   output tokens 86, steps 1, finish end_turn, persona block 0
   check: ERROR #5001; fenced 0
   one JSON object: 1
   types: outcome string, reasons array, confidence unassigned; other fields 0
   outcome: empty 0, one of the four 1, one of the four once case, spaces and punctuation are folded 1, a word of the user's message 0
   reasons: 2, blank or not a string 0
   confidence: unassigned
   ```
   **Branch C:** the outcome is valid and the reasons are fine; the confidence is missing. The panel and control refs were not run; the stored ref settled it. (The stored reply has 86 output tokens; the strip showed 66 for the 21:50Z walk.)
2. **PUBLIC TEXT, approved** (the Contest Planner under the owner's delegation): the combined sentence WITH "or forget", appended after line 37's last sentence, which stays word for word: `A request to remember or forget something is also the user's own message: choose "tellnow" for it, give the one reason, and give a confidence as for any other message.` NOT branch A': line 31 stays as it is. No other text changes.
3. **The Planner's conditions:** the regression's mutation and the new mock scenario answer the probe's exact shape (a valid outcome, 2 reasons, no confidence) and reproduce the demo's warning. The eval case `eval/user-turn-remember/` must show no Fallback and a confidence present on real Haiku in the Planner's release-candidate eval at the 1.0.4 cut (the Planner reports that; this story does not run it). Optional nice-to-have: see the last line of the intent contract's constraints.
4. **Ruled by the orchestrator (decide):** the three-part regression pairing ("Questions for the Planner", 3) is accepted; eval `userTurns` stay report-only (no new target); the `Test/Eval/Cases.cls` count 4 → 5 plus the two doc lines is a plain union with Epic 19 (non-overlapping hunks).

### Root cause (DW-890)

**The demo's evidence** (the Contest Planner, read-only, fresh session 00:11:00Z Sun 2026-11-08, typed "Remember that the Orders partner contact is Kim."). Ens_Util.Log held exactly one Type 3 warning from 00:10:30Z on:
`ID 254 | 2026-11-08 00:11:01.987 | Decide | Conclude | "The reply check refused the reply of the decision 5GpLt-Y6YmUb7IMg72-5gA: The reply check failed: the reply is not one JSON object that OcuTalon.Bridge.Msg.DecisionPayload accepts: ERROR #5001"`. The demo showed 1 agent step, 66 output tokens and 0.9 s. The code on the demo is this tree's: `v1.0.3` is an ancestor of HEAD, and `Triage.cls`, `DecisionPayload.cls`, `Decide.cls` and `Agent/Input.cls` are unchanged since it.

**Verified by code and measurement.** Planning measurements:
- `CheckReply` and `RefusalText` were probed on slot D (read-only).
- `Decide.Conclude` ran on the lane-D warm throwaway `e30s9pw`, which reproduced the demo's warning word for word.

Each reply shape gives these words after "accepts: ":

| Reply text (shape) | Refusal |
|---|---|
| A valid object, alone or in one Markdown fence | passes |
| Outcome not one of the four ("remember", "tell_now", "TellNow") | ERROR #5001 |
| `"reasons": []` | ERROR #5001 |
| No `confidence`, or `"confidence": null` | ERROR #5001 |
| `{}` | ERROR #5001 |
| Prose before or after the object; a fenced object with prose before it; two objects; a text "tool call" (`<function_calls>...`); plain prose | ERROR #5035 |
| An array of the object | ERROR #9406 on Outcome |
| An extra field (`"memory": ...`, or a `{"type":"tool_use",...}` object) | ERROR #9404: an unexpected property |
| `"confidence": "0.95"` (a string) / `"reasons": "x"` (a string) | ERROR #9406 on Confidence / on Reasons |
| `"confidence": 95` | Confidence: value > 1 |

**What this verifies:**
- Haiku's reply to a "Remember that ..." message passed `%JSONImport`. So it was one JSON object (bare or in one fence) whose fields are all among outcome, reasons and confidence, with acceptable types.
- `%OnValidateObject` then refused it for exactly one of these: (A) an outcome that is not exactly `ignore`, `digest`, `tellnow` or `act` (absent, null, another word, or another spelling); (B) no reason that is not blank; (C) no confidence.
- An attempted real tool call is excluded too:
  - Triage has no tools.
  - 1 step means one model request and no tool call.
  - A text imitation of a tool call gives #5035.

**Three readings of the evidence are corrected:**
1. The Planner inferred prose around the object, a second object or an attempted tool call. All of these give #5035, not #5001, so the inference is refuted.
2. "No 'After the reply filter ran' line, so not a length, datatype or enum failure" does not hold:
   - the second check never runs for `DecisionPayload`, which has no `FILTERED`;
   - length and datatype failures are first-check refusals with their own words (#7201 forms, #9406, "value > 1");
   - #5001 is precisely the enum check, or the blank-reasons or missing-confidence check.
3. The ledger guessed that "the output schema rejects the reply". There is no API-side schema: the runner sends no output format (`Adapter/Agent.cls`, `ReplyClass` is read only by Decide). The refusal is the bridge's own check (AD-8).

**Nothing in the code treats "Remember that ..." differently from the chips:**
- the same request shape;
- no tools and no history;
- the same persona rule;
- `FromGuide` is unused.

The only variable is the text, so the trigger is Haiku's answer to that text under the current `INSTRUCTIONS`.

**On the mock, the symptom does not appear without a scenario.** Measured on `e30s9pw`: a user decide of "Remember that the Orders partner contact is Kim." decided `tellnow`, Fallback 0, through the default `digest` and the user rule. A marker scenario can reproduce the shape (the `Conclude` runs above). By AD-22, the mock never answers by prompt wording, so no mock test can show whether a change to `INSTRUCTIONS` changes Haiku's answer.

**Inference (unverified):**
- Which of A, B or C it is.
- 66 output tokens is about twice a minimal valid reply such as `{"outcome":"tellnow","reasons":["A request from the user; the user is answered directly."],"confidence":0.95}`, which is about 30 tokens (inference). That is a substantial text, which argues against B and suggests A, because a model rarely drops a field.
- The instructions name "resend, approve or change" as user requests that are still tellnow, but not "remember". A plausible failure is an outcome taken from the request ("remember" or similar).
- This is not evidence. The three branches need different instruction wording. And no wording can be proved on the mock, so a fix chosen now would be invented. Hence the HALT.

### The probe (read-only, for the Planner on the demo host)

**What it reads and prints.** It reads the stored real-model reply that `TriageAgent` sent back for the decision, the `OcuTalon.Bridge.Msg.Reply` body in the trace. It prints:
- the check's own words (`RefusalText`, which by Story 30.6 quotes nothing of the reply);
- JSON types, counts and 0/1 flags.

It prints no character of the reply. It writes nothing and makes no model call. It was tested on slot D (the SQL and the shape lines, with synthetic replies, for all three branches and #5035) and end to end on the throwaway `e30s9pw` (a real decide through `Decide` → `TriageAgent` → the mock: "request header 12", "reply found", "check: passes").

**Step 1, the decision.**
- **Preferred.** Use `ref` = `5GpLt-Y6YmUb7IMg72-5gA` (warning ID 254), if its reply body is still in the trace: step 3 then prints "reply found".
- **Otherwise** (purged or reset), in a fresh demo session:
  - type "Remember that the Orders partner contact is Kim.";
  - then press More to try → "Ask it to remember";
  - then, as the control, press the first chip "Which productions are running?";
  - optionally type the remember message once more, to see whether the shape repeats.

  Each costs under $0.0001. Then list the refs, in namespace OCUTALON. The text filter keeps other visitors' messages out:

  `SELECT ID, Ref, Summary, Fallback, FallbackReason, OutputTokens, AgentStepCount, RecordedAt FROM OcuTalon_Bridge_Data.Decision WHERE Kind = 'decide' AND RecordedAt >= '<UTC start, YYYY-MM-DDThh:mm:ssZ>' AND Summary IN ('Remember that the Orders partner contact is Kim.', 'Remember that the Results partner''s contact is Lee.', 'Which productions are running?') ORDER BY ID`

  The warnings are `SELECT ID, TimeLogged, Text FROM Ens_Util.Log WHERE Type = 3 AND SourceMethod = 'Conclude' AND TimeLogged >= '<UTC start>' ORDER BY ID`. A warning quotes nothing of a reply.

**Step 2, run the lines.** For each ref, run these lines in the demo's IRIS (`iris session IRIS -U OCUTALON` in its IRIS container, or the same read-only access as the 00:11Z reading). Each line is complete on its own, so they can be pasted one by one. Run S1 to S6 only after L5 printed "reply found".

```
 Set ref="5GpLt-Y6YmUb7IMg72-5gA"
 Set hid="",rid="",bid="",st=##class(%SQL.Statement).%ExecDirect(,"SELECT h.ID AS hid, r.ID AS rid FROM Ens.MessageHeader h, OcuTalon_Bridge_Msg.Request r WHERE r.DecisionRef = ? AND r.Kind = 'decide' AND h.MessageBodyClassName = 'OcuTalon.Bridge.Msg.Request' AND h.MessageBodyId = r.ID AND h.TargetConfigName = 'TriageAgent' ORDER BY h.ID",ref) If st.%SQLCODE<0 { Write "SQL ",st.%SQLCODE," ",st.%Message,! } If st.%Next() { Set hid=st.hid,rid=st.rid }
 Write $Select(hid="":"no TriageAgent request for "_ref,1:"request header "_hid),!
 Set st=##class(%SQL.Statement).%ExecDirect(,"SELECT MessageBodyId FROM Ens.MessageHeader WHERE CorrespondingMessageId = ? AND MessageBodyClassName = 'OcuTalon.Bridge.Msg.Reply' ORDER BY ID",hid) If st.%SQLCODE<0 { Write "SQL ",st.%SQLCODE," ",st.%Message,! } If st.%Next() { Set bid=st.MessageBodyId }
 Set reply=##class(OcuTalon.Bridge.Msg.Reply).%OpenId(bid),req=##class(OcuTalon.Bridge.Msg.Request).%OpenId(rid) Write $Select($IsObject(reply):"reply found",1:"no reply body"),!
 If $IsObject(reply) { Set t=reply.Text,in=req.Input Write "output tokens ",reply.OutputTokens,", steps ",reply.AgentStepCount,", finish ",reply.FinishReason,", persona block ",(in [ ##class(OcuTalon.Agent.Persona).#OPENING),! }
 Set D="OcuTalon.Bridge.Process.Decide",P="OcuTalon.Bridge.Msg.DecisionPayload",u=$ClassMethod(D,"Unfenced",t),sc=$ClassMethod(D,"CheckReply",t,P,.p,.c) Write "check: ",$Select($System.Status.IsOK(sc):"passes",1:$ClassMethod(D,"RefusalText",c,P,t)),"; fenced ",(u'=$ZStrip(t,"<>WC")),!
 Set o="" Try { Set o=##class(%DynamicAbstractObject).%FromJSON(u) } Catch { } Set obj=$IsObject(o)&&o.%IsA("%DynamicObject") Write "one JSON object: ",obj,!
 Set other=0 If obj { Set it=o.%GetIterator() While it.%GetNext(.k,.v) { If '$ListFind($ListBuild("outcome","reasons","confidence"),k) { Set other=other+1 } } Write "types: outcome ",o.%GetTypeOf("outcome"),", reasons ",o.%GetTypeOf("reasons"),", confidence ",o.%GetTypeOf("confidence"),"; other fields ",other,! }
 Set W=$ListBuild("ignore","digest","tellnow","act"),x="" If obj && (o.%GetTypeOf("outcome")="string") { Set x=o.outcome } Write "outcome: empty ",(x=""),", one of the four ",''$ListFind(W,x),", one of the four once case, spaces and punctuation are folded ",''$ListFind(W,$ZConvert($ZStrip(x,"*WP"),"L")),", a word of the user's message ",((x'="")&&($ZConvert(in,"L")[$ZConvert(x,"L"))),!
 Set n=0,b=0 If obj && (o.%GetTypeOf("reasons")="array") { For i=0:1:o.reasons.%Size()-1 { Set n=n+1 If (o.reasons.%GetTypeOf(i)'="string") || ($ZStrip(o.reasons.%Get(i),"*WC")="") { Set b=b+1 } } } Write "reasons: ",n,", blank or not a string ",b,!
 Set ct=$Select(obj:o.%GetTypeOf("confidence"),1:"-") Write "confidence: ",$Select(ct'="number":ct,(o.confidence>=0)&&(o.confidence<=1):"a number from 0 to 1",1:"a number outside 0 to 1"),!
```

(The first line is L0, the next five are L1 to L5, and the last six are S1 to S6.)

**Step 3, send back** the printed lines of each ref, labelled typed, panel or control. They hold no reply content.

### What each result means, and the branch it selects

| Printed (remember decision) | Meaning | Branch |
|---|---|---|
| `check: ERROR #5001` and `outcome: ... one of the four 0, ... folded 1` | a spelling variant (capitals, a space, an underscore) | A' |
| `check: ERROR #5001`, `one of the four 0`, `folded 0` (any value of "a word of the user's message"; 1 means it reused a word of the message, such as its verb) | an outcome that is not one of the four | A |
| `check: ERROR #5001`, `outcome: empty 1` (types: outcome `unassigned` or `null`) | no outcome | A |
| `check: ERROR #5001`, outcome one of the four, `reasons: 0`, or blank equal to the count | no usable reason | B |
| `check: ERROR #5001`, outcome one of the four, reasons fine, `confidence: unassigned` or `null` | no confidence | C |
| `check: passes` or another refusal (#5035, #9404, #9406) | not the shape of the 00:11Z warning: a wrong ref, or the reply varies | report; re-plan from the new evidence |
| Control chip: `check: passes`, one of the four 1 | expected; its output tokens are the size of a valid reply | -- |
| `persona block 1` | the session has a persona block. Note it: the chips decided fine with the same block | -- |
| `no reply body` | purged; use step 1's typed messages | -- |

### Public Text (for the Planner's ruling, together with the probe)

None is decided in this stage. The instruction text of Triage counts as Public Text (dispatch). The candidates, in `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`:

**Branches A, B and C (recommended default: one sentence that covers all three).** Line 37 keeps every word it has, so the DW-500 phrases pinned by `TriageUserTurn` stay. One sentence is appended at its end:
- OLD (`:37`, its last sentence, unchanged): `This holds also when the user asks OcuTalon to resend, approve or change something: the next paragraph is about items that arrived on a channel, never about the user's own message.`
- NEW (appended after it): `A request to remember or forget something is also the user's own message: choose "tellnow" for it, give the one reason, and give a confidence as for any other message.`
- The Planner's choice: with or without "or forget". Chat also handles forget requests (`Chat.cls:70`), but no forget failure has been observed.

**Branch A' (added to the above when the probe shows a spelling variant).**
- OLD (`:31`): `- "outcome": one of the quoted values "ignore", "digest", "tellnow" or "act".`
- NEW (`:31`): `- "outcome": exactly one of the quoted values "ignore", "digest", "tellnow" or "act", written as quoted and never another word.`

**No other string changes.** No user-facing string changes in any branch. The strip's fallback text and the Story 30.6 warning stay as they are.

### Questions for the Planner (via the runner)

1. Run the probe (step 1, 2 or 3) and send back the lines.
2. Rule the wording for the branch the probe selects. Or rule, without the probe, that the re-plan plans the combined sentence blind. The rc eval case on Claude Haiku 5.5 would then be its only proof.
3. **The regression on the mock.** The fix is a sentence in `INSTRUCTIONS`, and the mock never answers by prompt wording (AD-22), so no mock test can be made red by restoring the cause. The re-plan would pin it with three tests:
   - (a) a fixed-strings test of the new sentence. Its mutation, dropping the sentence, turns it red.
   - (b) a mock test that drives both forms through WebChatIn → Conversation → Decide and asserts a decide row with outcome tellnow, Fallback 0 and no refusal warning. Its discriminating mutation is a new A/ scenario that answers the decide with the probe's shape: it gives Fallback `invalid` and exactly the demo's warning text, and turns the assertion red.
   - (c) the new eval case, which runs on real Haiku at each release candidate.

   Accept this pairing, or rule otherwise.
4. **Gating.** `userTurns` has no target (`Report.cls:47-51`), so a remember case that falls back on the rc run is listed (not right, and on the fallbacks list) but fails nothing. The case "states" the rule, but does not enforce it. A target, or a per-case gate in `Eval/Gate.cls`, is a new product target, which belongs to the owner or the Planner. The default is to keep it report-only.
5. **The contended edit.** `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls:248` pins exactly four user-turn cases, and Epic 19 (runner C) edits this file. A fifth case needs the runner to clear that line (below).

### Plan after the probe (for the re-plan; not frozen)

- **Fix site.** `Triage.cls` `INSTRUCTIONS` only, as ruled.
  - The new sentence goes in the user's-own-message paragraph, so the persona paragraph stays last (`PersonaBlock.cls:218-229`).
  - The DW-500 rule, the no-all-clear rule (AD-28), the injection, heartbeat and approval paragraphs, and the absence of `{{` (AD-7) are untouched.
  - Never in `Decide.cls` or `DecisionPayload.cls`. Accepting or normalising a refused outcome, or refused reasons or confidence, would loosen the reply check for every other reply and contradict AD-7 ("content that doesn't validate is unusable") and AD-8. So the fix needs neither of the two contended `Decide.cls` lines.
- **Tests.**
  - `Test/Agent/TriageUserTurn.cls`: add the ruled sentence to the phrase list. A string test, about 0.4 s, in `shards-5`.
  - A new class drives both forms end to end on the mock. It extends `PersonaTurns.Ask` / `AssertDecided` (the sibling it extends, Rule 2) and reads the warning through `Test.Core.Observe.Warnings`, as `Test.Bridge.ReplyCheck.Warning` does. It also uses a new `ci/mock/scenarios/A/remember-<shape>.json` with the probe's shape at replies[0] and a Chat text at replies[1], armed at 1.
  - Place it by time: `Test.Agent.*` lands in `shards-5`, which has about 150 s of room (inference). If the class costs more than about 60 s, place it in an area of `shards-2` instead.
- **Eval case.** `eval/user-turn-remember/case.json`, shaped like `user-turn-productions`:
  - kind `user-turn`, `heldOut` false;
  - turn text = the panel's "Remember that the Results partner's contact is Lee.";
  - the same `keyPhrases` and the 14 `absentPhrases`;
  - `recordedBy` "written for the evaluation set (Story 30.9, DW-890)".
  - The name stays distinct from Epic 41's planned email and webhook remember cases.
  - On the mock it scores right (the default `digest` plus the user rule: the reasons hold "user" and no absent phrase; inference from `ScoreUserTurn`). `eval/run.sh` is not touched.
- **Contended edit (proposed plain union).** In `Test/Eval/Cases.cls`:
  - `:248` `Do $$$AssertEquals(count, 4, "eval/ holds exactly four user-turn cases")` becomes `5` and "five".
  - The class header at `:16` ("exactly four user-turn cases") and the method doc at `:234-236` each add "and one remember case (Story 30.9, DW-890)".
  - The new case's own field checks go in the story's own new test, so the four-name loop at `:249-272` stays as it is.

### Architecture decisions (Rule 6)

- **AD-6:** a person's message makes two requests, and the decide goes through Decide.
- **AD-7:**
  - Triage: static `INSTRUCTIONS`, no `{{`, no tools.
  - One JSON object, checked against `ReplyClass`; content that doesn't validate is unusable.
  - The persona arrives only as data.
  - Haiku 5.5 with effort low and no sampling parameters.
- **AD-8:** the bridge alone decides that a reply is unusable, and `invalid` is a fallback.
- **AD-14:** provenance user; the text is rendered as written.
- **AD-22:** the mock picks by marker, then guide prompt, then the MOCKKEY default, never by prompt wording; the evaluation set.
- **AD-26:** the warning goes in the decision's trace session.
- **AD-28:** no all-clear.
- **AD-29 and AD-33:** Lane A's files; new A/ scenario files only.
- **AD-21:** memory saving stays in Chat's turn, unchanged.
- No AC contradicts an AD's Rule. A code-side loosening would contradict AD-7 and AD-8, and is excluded.

### Ledger inbox (Rule 17)

- **DW-890: addressed in part.** Its root cause is narrowed to one verified class (A, B or C above), and the ledger's two guesses are refuted with measurements. The fix, the regression test and the eval case wait for the probe. No entry is declined.

### Integration and reuse (Rules 1 and 2)

- **Integration.** No service or module is introduced, and no consumers are added.
- **Consumes** (unchanged):
  - `Decide.CheckReply` / `RefusalText`;
  - `Conversation`'s two requests;
  - `Eval.Report.ScoreUserTurn`;
  - the mock's marker rule.
- **Consumed-by:** the decision strip (via `Conversation.Decided` → `TriageDecisionRef`) and the evaluation report.
- **Extend, don't copy:** the end-to-end test extends `PersonaTurns.Ask` / `AssertDecided`; the warning read reuses `Test.Core.Observe.Warnings`; the eval case copies the shape of `user-turn-productions`.

### Decided in-stage

- **The spec's file name** is the sprint key, which is cut at 64 characters ("...decisio"), like the earlier truncated keys (`spec-0-6-...-or.md`).
- **The probe** prints only check words, types, counts and flags. It was tested on slot D and on `e30s9pw` before it went into the spec.
- **No fix is planned before the probe** (the dispatch's rule). The branch table and the candidate wording let one Planner round settle both.

## Verification

**Measured at planning:**
- **Slot D** (`ocutalon-slot-d`, port 52793, build 154U, OCUTALON; read-only):
  - `CheckReply` / `RefusalText` on 21 synthetic replies (the table above);
  - the probe's lookup SQL with an absent ref ("no TriageAgent request ..."), and its shape lines on 7 synthetic replies;
  - the decide request listing: no rows on the slot.
- **Lane-D warm throwaway** `e30s9pw` (`<lock-dir>/lane-d`, `OCUTALON_TEST_WEB_PORT=52804`, up in 146 s, then `ci/warm.sh down`: 1 project removed, nothing left over). Scripts under `<scratchpad>/e30s9plan/`, run with `docker exec -i <iris container> iris session IRIS -U OCUTALON`:
  - `RunnerFixture.PointKeys`, then a user decide of the typed remember text: tellnow, Fallback 0, 33 output tokens (mock count), 1 step, finish end_turn. The probe found its request and reply ("check: passes").
  - `Decide.Conclude` with replies of shapes A, B and C gave Fallback `invalid` and the warning "The reply check refused the reply of the decision <ref>: The reply check failed: the reply is not one JSON object that OcuTalon.Bridge.Msg.DecisionPayload accepts: ERROR #5001" (`Conclude`, Type 3), word for word the demo's.
  - With a valid control: no warning, Fallback 0.
  - With prose before the object, two objects and a text tool call: the same warning ending in "ERROR #5035".
- The working tree was clean before and after (`git status --short` empty).

**For the re-plan:**
- **Shared surfaces:** Triage's `INSTRUCTIONS` text (pinned by `TriageUserTurn`, `Instructions.TestTriage`, `PersonaBlock.TestParagraphs` and `test-triage-heartbeat.sh`) and the eval set's user-turn count (`Test/Eval/Cases.cls:248`).
- The standing criterion: every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: blocked (round 1; superseded by the re-plan of 2026-11-08, see Spec Change Log)
Blocking condition: intent gap: root cause needs a real-model probe (answered: branch C)

- The plan halted before any intent contract or task, because the fix depends on which of the three `%OnValidateObject` refusals (A outcome, B reasons, C confidence) Haiku's stored reply hits.
- Verified: the reply was one JSON object of `DecisionPayload`'s own fields that passed import. Prose, a second object or a tool call give #5035, not #5001, and the after-filter check never runs for `DecisionPayload`.
- The read-only probe, what each result means, the candidate Triage wording for each branch (Public Text) and five questions for the Planner are under Design Notes.
- No source file was changed. Runtime use: slot D read-only probes; the lane-D warm throwaway `e30s9pw`, started and torn down by this stage.
