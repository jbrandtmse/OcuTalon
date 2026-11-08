---
title: 'A ''Remember that ...'' chat message gets a usable attention decision'
type: 'bugfix'
created: '2026-11-07'
status: 'ready-for-dev'
baseline_revision: 'b51128a7310cfe74d8dae3d2136023273c9592aa'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

# A 'Remember that ...' chat message gets a usable attention decision

Re-planned on 2026-11-08 from the probe's result (branch C: Haiku's decide reply to a "Remember that ..." message has no `confidence`) and the rulings below. The fix is one Planner-approved sentence in Triage's instructions. The regression is a string test of the sentence, a mock end-to-end test of both forms with a scenario that answers the probe's exact shape, and an evaluation case for the release-candidate run on Claude Haiku 5.5.

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

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Typed form | "Remember that the Orders partner contact is Kim." through WebChatIn; the mock's default `triage` and `chat` scripts (no marker) | The turn is done with Chat's reply. Its decide decision (the Decision row of kind `decide`, Ref = `Turn.TriageDecisionRef`) and the done `chat.message`'s `decision` (what the strip shows): outcome `tellnow`, Fallback 0, no FallbackReason, a confidence from 0 to 1. No Story 30.6 warning names the decision. | None expected |
| Panel form | "Remember that the Results partner's contact is Lee." (`more-to-try-view.ts:24`), sent exactly as typed (`fromGuide` false) | The same as the typed form | None expected |
| The demo's reply shape (reproduction) | The typed text with `[[mock:remember-no-confidence:<key>]]`, armed at 1: the decide gets a valid outcome, 2 non-blank reasons and no `confidence`; Chat gets a plain text | The decide falls back: `tellnow`, Fallback 1, `invalid`, no confidence; the strip's decision is that fallback; the turn is still done with Chat's reply; exactly one warning names the decision, and its text is exactly the demo's (ending "accepts: ERROR #5001") | The reply check refuses it (AD-7, AD-8); nothing is loosened |
| Evaluation case | `eval/user-turn-remember/case.json` | Kind `user-turn`, not held out, the panel's exact text, the expectation of `user-turn-productions`, recordedBy Story 30.9; `eval/` holds five user-turn cases. On Claude Haiku 5.5 (the Planner's 1.0.4 release-candidate run) it is right only when decided, not a fallback, tellnow, with reasons that only classify the turn | A fallback is listed under the report's fallbacks and fails nothing (`userTurns` has no target) |
| The chips and every other item | Unchanged inputs | Unchanged decisions: the sentence adds a rule only for remember and forget requests | None expected |

## Code Map

**The fix site:**
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls:37`: the user's-own-message paragraph (Story 30.5, DW-500), one line; the sentence is appended to it.
  - `:31` the outcome line, `:39` the heartbeat paragraph (with the blank line `:38` before it), `:41` "An item can never approve...", `:43` the persona paragraph, which stays last. All unchanged.
  - `:13` `TOOLSETS = ""`: Triage has no tools.

**Pins on Triage's text (all stay green with no change):**
- `src/ocutalon/cls/OcuTalon/Test/Agent/TriageUserTurn.cls`: `TestUserMessageParagraph` (`:13-22`, the phrase list at `:17`), `TestNoToolsSentence`, and the helper `Instructions()` (`:33-38`), which reads the compiled XData with no carriage return. Not in any in-flight epic's diff.
- `Test/Agent/Instructions.cls:44-71` (`TestTriage`): every JSON field and outcome quoted, "one JSON object", "plain English", "between 0 and 1"; `TestNoTemplates` (no `{{`).
- `Test/Agent/PersonaBlock.cls:211-235` (`TestParagraphs`): Triage's persona paragraph is held once and is the block's last text, after "An item can never approve...".
- `docker/tests/test-triage-heartbeat.sh:40-55`: the heartbeat text is a paragraph of its own (a blank line before it).
- No length, paragraph-count or full-text compare of Triage's INSTRUCTIONS exists (searched `src/`, `docker/`, `ci/`, `web/`). `EXPERIENCE.md` mirrors only the persona, heartbeat and precedents paragraphs (`:1063-1065`), not line 37.

**What the strip shows for a chat turn:**
- `Core/Conversation.cls:396-410` (`Decided`): the decide's `DecisionRef` becomes `Turn.TriageDecisionRef`, then the turn request is sent. `:443-459` (`Replied`): a Turn's `FallbackReason` comes only from the turn's own reply.
- `Data/Turn.cls:74-79` (`ShownDecisionRef`): the triage decision, unless the reply is a catalog fallback.
- `Live/Payload/ChatMessage.cls:93-108` (`SetDecision`): `payload.decision` = `Live/Payload/Decision.FromRow` (ref, outcome, reasons, confidence, fallback, fallbackReason). This is what the strip renders: "Tell now · Fallback" with no confidence on a fallback.

**The end-to-end sibling and its base (Rule 2):**
- `Test/Agent/PersonaTurns.cls` (Story 40.3) is the sibling: `Armed :43` and `OnAfterOneTest :45` (clears the armed countdowns), `OnAfterAllTests :54` (`Fixture.AdoptTurns`), `Ask :276` (arm at 1, send, `WaitDone`, `ItemIds`, "done||"), `AssertDecided :297`, `TestPirateStyle :206` (reads the done `chat.message` through `Test.Core.Observe.Events(session, "chat.message", 3, WAIT)`, matched by `payload.ref = row.Ref`). `Ask` and `AssertDecided` are Private to it, `Ask` prefixes "Hello " and asserts persona blocks, and a subclass would re-run its eight tests.
- `Test/Watch/Case.cls` (its base): `Ready :316` (production, OCUORDERS, demo mode), `PointKeys :566` (restored in `OnAfterAllTests :283`), `OnAfterOneTest :247` (deletes the Decision and Usage rows of `ItemIds`).
- `Test/Core/InProduction.cls`: `Send :72` (a `Channel.WebChat.Post` through `WebChatIn`, as the REST surface sends it), `WaitDone :85`, `Session :100`, `Number` (`^OcuTalonTest(<class's last piece>,"n")`).
- `Test/Agent/RunnerFixture.cls` `DecisionOf(itemId, kind)` (`:372` on this branch; the feature branch's Epic 11 merge moved lines, so find it by name).
- Warnings: `Test/Core/Observe.cls` `LastLog :81`, `Warnings :89` (counts Type 3 rows of a method after a mark, with a text start), `RemoveWarnings :102`. `Test/Bridge/ReplyCheck.cls:31` `REFUSED` (reuse as `##class(OcuTalon.Test.Bridge.ReplyCheck).#REFUSED`), and `:42-60` is the pattern for taking a mark and removing the warnings.

**The check (read-only for this story):**
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `CheckReply :913-930` (a new `replyClass` instance for each reply), `RefusalText :946-985` and `RefusalPart :1030-1047` (a #5001 has no property, so it is "ERROR #5001"), `CHECKFAILED :988`, `Judge :1507-1566` (the user rule at `:1558-1561` maps ignore and digest to tellnow and keeps the confidence).
- `src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls:19-32`: `%OnValidateObject`; the missing confidence is `:30`.

**The mock:**
- `ci/mock/scenarios/A/persona-pirate-style.json`: the pattern (marker, `replies[0]` the decide's JSON text, `replies[1]` Chat's text).
- `ci/mock/mock.mjs:453-465` (`pickReply`): armed at 1, the first request with the marker (the decide, which Conversation sends first) gets `replies[0]`, later ones `replies[min(1+k, last)]`. `Test/Contract/Mock.cls:439` `Arm(marker, remaining)` ("" clears).
- The default scripts: `A/triage.json` (digest, 0.5) and `A/chat.json` (`list_productions`, then a text). No `B/` guide prompt matches either remember text (checked), so both forms reach the default scripts.
- `ci/mock/test/scenarios.test.mjs:137-144` loads every committed file and checks named scenarios, never a count. No scenario named `remember-*` exists or is planned in any in-flight branch.

**The evaluation set:**
- `eval/user-turn-productions/case.json`: the shape (kind `user-turn`, `heldOut` false, `turn.text`, `keyPhrases [["user"]]`, 14 `absentPhrases`, `recordedBy`).
- `Eval/In.cls:35-38` (doc), `Converse :538` and `TurnRequest :636`: a user-turn case is sent as a decide request of provenance user, and Decide answers it with a DecisionResponse. `Eval/Report.cls:47-51, 680-727` (`ScoreUserTurn`): right only when decided, not a fallback, tellnow, with every key phrase and no absent phrase; report-only. There is no expectation key for a confidence.
- `Test/Eval/Cases.cls`: `:16`, `:234-236` and `:248` (the ruled edit); `:180` `turns >= 8` (a lower bound that stays true, unchanged); `AssertTurnShape :303-311`; `Read :763` and `Plain :771` are public ClassMethods (reuse them). `Test/Eval/Report.cls:1758` loops the four chip cases by name (unchanged; contended). `docker/tests/test-eval-set.sh` checks every case's shape (unchanged; contended).

**CI and rules:**
- `ci/units.sh:96-109` (`group_units`): `shards-5` runs `shard:lane-a@Bridge,Agent live:sign-in-3`, `shards-2` runs `shard:lane-a@rest` (Eval). Agent and Eval are existing areas, so `ci/units.sh` does not change.
- `docker/tests/test-class-rules.sh` assert-concat: in an assertion, a concatenation right of `[` is wrapped in parentheses.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Agent/Triage.cls` -- on line 37, after `never about the user's own message.`, add one space and the ruled sentence verbatim; change nothing else in the class -- the fix of DW-890 (branch C).
- `src/ocutalon/cls/OcuTalon/Test/Agent/TriageUserTurn.cls` -- add `TestRememberSentence` and its header bullet: the compiled INSTRUCTIONS hold the ruled sentence exactly once; it directly follows `never about the user's own message.` and one space; and the paragraph ends after it (two line feeds, then `An item on the channel heartbeat`). Leave the existing tests as they are -- AC 1, DW-890.
- `ci/mock/scenarios/A/remember-no-confidence.json` (new) -- `name` and `match.marker` `remember-no-confidence`. `replies[0]`: status 200, text `{"outcome":"tellnow","reasons":["A request from the user; the user is answered directly.","The user asks OcuTalon to remember a partner's contact."]}` (a valid outcome, 2 non-blank reasons, no `confidence`). `replies[1]`: status 200, text `Noted.` -- the probe's exact shape for the reproduction and the mutation, DW-890.
- `eval/user-turn-remember/case.json` (new) -- the shape of `user-turn-productions`. Its fields:
  - `name` `user-turn-remember`, `kind` `user-turn`, `heldOut` false;
  - `turn.text` `Remember that the Results partner's contact is Lee.`;
  - `expectation` the same as `user-turn-productions` (`keyPhrases [["user"]]` and its 14 `absentPhrases`, in the same order);
  - `recordedBy` `written for the evaluation set (Story 30.9, DW-890)`;
  - `description`, in plain ASCII: `The user asks OcuTalon to remember a partner's contact, as the guide's Ask it to remember control sends it (Story 30.9, DW-890). The case is right only when Triage decides tell now with no fallback, which needs a reply that gives a confidence, and its reasons only classify the turn as the user's own message: they never describe the state of a production, what Triage can or cannot look up, or whether anything needs the user.`
  - The report has no expectation key for a confidence, so the description states it, and no fallback implies a confidence: `DecisionPayload` refuses a reply without one -- AC 4, DW-890.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RememberDecision.cls` (new) -- extends `OcuTalon.Test.Watch.Case`, as PersonaTurns does. It has a header that states what each test pins (Rule 14), `WAIT` 90 and `SESSIONPREFIX` `zzremember`, and its own session for each test. Its parts:
  - **Clean-up.** An `Armed` list, which `OnAfterOneTest` clears (`Mock.Arm(marker, "")`). A warning mark taken in `OnBeforeOneTest` (`Observe.LastLog`); `OnAfterOneTest` removes the REFUSED warnings after it (`Observe.RemoveWarnings`). `OnAfterAllTests` adopts the run's turns (`Fixture.AdoptTurns`). Each hook calls `##super`.
  - **The helper `Ask(session, text, scenario)`.** It sends `text` through `Send`. Only when a scenario is given, it adds ` [[mock:<scenario>:<run number><tag>]]` to the text and arms that marker at 1 first. It waits for the turn to be done, asserts "done||" as PersonaTurns does, adds the ItemId to `ItemIds`, and gives the Turn and the done `chat.message` payload.
  - **The checks.** `AssertUsable(label, row, payload, mark)` and `AssertDemoFallback(label, row, payload, mark)` hold the I/O Matrix's checks. They read the Decision row (`DecisionOf(row.ItemId, "decide")`), `payload.decision` (its ref = `row.TriageDecisionRef`) and the warnings that name the decision (`Observe.Warnings(mark, .text, "Conclude", REFUSED_ref)`).
  - **The tests.** `TestTypedForm` and `TestPanelForm` (AC 2) send their exact form with no scenario. `TestProbeShapeIsTheDemoWarning` (AC 3) sends the typed form through `remember-no-confidence`. `TestEvalCase` (AC 4) reads the case with `Test.Eval.Cases.Read` and `Plain`.
  - **Its CI place.** It sits in the Agent area, which runs in `shards-5` -- AC 2, AC 3, AC 4, DW-890.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` -- the ruled plain union, exactly the three lines under Design Notes "Contended edits"; nothing else in the class -- AC 4.
- This spec's `## Verification` -- under each planned `mutation:` line, record what was observed (applied, which test went red, reverted, tree byte-identical) -- Rule 19.

**Acceptance Criteria:**
- AC 1: Given the compiled `OcuTalon.Agent.Triage`, when `TriageUserTurn.TestRememberSentence` reads its INSTRUCTIONS, then they hold the ruled sentence exactly once, right after line 37's unchanged last sentence and one space, as the last sentence of that paragraph, and `TestUserMessageParagraph`, `Instructions.TestTriage`, `PersonaBlock.TestParagraphs` and `test-triage-heartbeat.sh` pass unchanged.
- AC 2 (Integration AC, both forms): Given the running production on the CI mock's default scripts, when the typed "Remember that the Orders partner contact is Kim." and the panel's "Remember that the Results partner's contact is Lee." are each sent through WebChatIn, then the consumer, the strip's payload (the done `chat.message` that Conversation publishes), shows the decide decision of `Turn.TriageDecisionRef` as tellnow, not a fallback, with a confidence from 0 to 1. The Decision row says the same. No Story 30.6 refusal warning names the decision.
- AC 3 (the cause, reproduced): Given the `remember-no-confidence` scenario armed at 1, when the typed form is sent with its marker, then the decide decision is tellnow, Fallback 1, `invalid`, with no confidence, and so is the strip's decision. The turn is still done with Chat's reply. Exactly one warning names the decision, and its text equals `The reply check refused the reply of the decision <ref>: The reply check failed: the reply is not one JSON object that OcuTalon.Bridge.Msg.DecisionPayload accepts: ERROR #5001`.
- AC 4: Given `eval/`, when `Test.Eval.Cases` and `RememberDecision.TestEvalCase` run, then:
  - `eval/user-turn-remember/case.json` is a user-turn case, not held out, with the panel's exact text, `user-turn-productions`' expectation, the Story 30.9 recordedBy and a description that names no fallback and a confidence;
  - it holds only the fields of its kind and is plain ASCII;
  - `eval/` holds exactly five user-turn cases;
  - `bash docker/tests/test-eval-set.sh` passes.
- AC 5: Given the story's diff against `baseline_revision`, when it is listed, then it holds only the files of the Execution list and this spec. `Decide.cls`, `DecisionPayload.cls`, `Chat.cls`, `eval/run.sh`, `ci/units.sh`, every timeout and `TimerSeconds`, and every existing mock scenario are unchanged.

## Spec Change Log

- 2026-11-08T02:30:11Z, runner (re-dispatch protocol after the plan's `intent gap` HALT, round 1): the probe ran on the demo host and selected branch C. The orchestrator relayed the Planner's answers and its own rulings (logged as `ruling` in Epic 30's cycle log; resume message of 2026-11-08). Applied: the intent contract above (ruled intent and constraints) and "Rulings of 2026-11-08" below. Status `blocked` → `draft` for the re-plan.
- 2026-11-08T02:43Z, plan stage (re-plan, round 2): kept the intent contract verbatim and re-derived the I/O & Edge-Case Matrix (placed after the intent block), the Code Map, Tasks & Acceptance and Verification around it. Updated "Root cause (DW-890)" to the verified branch C, marked the Public Text as ruled (A' not selected), condensed the probe and the answered questions, and left the optional warning wording out (Decided in-stage). Status `draft` → `ready-for-dev`.

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

### Root cause (DW-890): verified, branch C

**The demo's evidence** (the Contest Planner, read-only, fresh session 00:11:00Z Sun 2026-11-08, typed "Remember that the Orders partner contact is Kim."). Ens_Util.Log held exactly one Type 3 warning from 00:10:30Z on:
`ID 254 | 2026-11-08 00:11:01.987 | Decide | Conclude | "The reply check refused the reply of the decision 5GpLt-Y6YmUb7IMg72-5gA: The reply check failed: the reply is not one JSON object that OcuTalon.Bridge.Msg.DecisionPayload accepts: ERROR #5001"`. The demo showed 1 agent step, 66 output tokens and 0.9 s. The code on the demo is this tree's: `v1.0.3` is an ancestor of HEAD, and `Triage.cls`, `DecisionPayload.cls`, `Decide.cls` and `Agent/Input.cls` are unchanged since it.

**The cause, from the probe's lines** (Ruling 1, on the stored reply of that ref):
- `check: ERROR #5001; fenced 0` and `one JSON object: 1`: a bare JSON object that `%JSONImport` accepted and `%OnValidateObject` refused;
- `types: outcome string, reasons array, confidence unassigned; other fields 0`: only `DecisionPayload`'s own fields, of the right types, with `confidence` absent;
- `outcome: ... one of the four 1`: not branch A or A';
- `reasons: 2, blank or not a string 0`: not branch B;
- `confidence: unassigned`: branch C, the refusal at `DecisionPayload.cls:30` ("The confidence is missing", which `RefusalText` gives as "ERROR #5001").

So Haiku answers a remember request with a valid outcome and reasons but leaves out the confidence. The instructions ask for a confidence for every item, but they name "resend, approve or change" as the user's requests and not "remember". The fix tells the model, in the same paragraph, that a remember or forget request is the user's own message and still gets a confidence. That this wording changes Haiku's answer cannot be shown on the mock (AD-22: never by prompt wording). It is proved by the release-candidate eval case on Claude Haiku 5.5 (Ruling 3).

**How the evidence narrowed it to A, B or C (round 1, kept as evidence).** Planning measurements:
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

**What round 1 verified:**
- Haiku's reply passed `%JSONImport`. So it was one JSON object (bare or in one fence) whose fields are all among outcome, reasons and confidence, with acceptable types.
- `%OnValidateObject` then refused it for exactly one of these: (A) an outcome that is not exactly `ignore`, `digest`, `tellnow` or `act`; (B) no reason that is not blank; (C) no confidence. The probe selected C.
- An attempted real tool call is excluded: Triage has no tools, 1 step means one model request and no tool call, and a text imitation of a tool call gives #5035.

**Three readings of the evidence are corrected:**
1. The Planner inferred prose around the object, a second object or an attempted tool call. All of these give #5035, not #5001, so the inference is refuted.
2. "No 'After the reply filter ran' line, so not a length, datatype or enum failure" does not hold:
   - the second check never runs for `DecisionPayload`, which has no `FILTERED`;
   - length and datatype failures are first-check refusals with their own words (#7201 forms, #9406, "value > 1");
   - #5001 is precisely the enum check, or the blank-reasons or missing-confidence check.
3. The ledger guessed that "the output schema rejects the reply". There is no API-side schema: the runner sends no output format (`Adapter/Agent.cls`, `ReplyClass` is read only by Decide). The refusal is the bridge's own check (AD-8).

**Nothing in the code treats "Remember that ..." differently from the chips:** the same request shape, no tools and no history, the same persona rule, and `FromGuide` is unused. The only variable is the text, so the trigger is Haiku's answer to that text under the current `INSTRUCTIONS`.

**On the mock, the symptom does not appear without a scenario.** Measured on `e30s9pw`: a user decide of "Remember that the Orders partner contact is Kim." decided `tellnow`, Fallback 0, through the default `digest` and the user rule. A marker scenario reproduces the shape (the `Conclude` runs above, and AC 3 through the whole path).

**Round 1's inference, corrected by the probe:** round 1 read the 66 output tokens as a sign of branch A. The probe shows C: the reply was a full text with no confidence field, so that reading was wrong.

### The probe (answered)

A read-only ObjectScript probe for the demo host read the stored `OcuTalon.Bridge.Msg.Reply` of the decision. It printed only the check's own words (`RefusalText`), JSON types, counts and 0/1 flags: no character of the reply, no write and no model call. It was tested on slot D and on `e30s9pw` before it was handed over. Its printed result is Ruling 1. The full probe (its SQL lookup, lines L0 to L5 and S1 to S6) and the table of what each result meant are in this spec as committed at `aa2dafaed507adff8a1e722ceec640dd6148c9ff`. The questions for the Planner (run the probe, rule the wording, accept the three-part pairing, keep `userTurns` report-only, clear the contended count line) are all answered by Rulings 1 to 4.

### Public Text (ruled)

- **RULED (Ruling 2):** appended to `src/ocutalon/cls/OcuTalon/Agent/Triage.cls:37`, after its last sentence `This holds also when the user asks OcuTalon to resend, approve or change something: the next paragraph is about items that arrived on a channel, never about the user's own message.`, which keeps every word, so the DW-500 phrases pinned by `TriageUserTurn` stay: `A request to remember or forget something is also the user's own message: choose "tellnow" for it, give the one reason, and give a confidence as for any other message.` With "or forget": Chat also handles forget requests (`Chat.cls:70`), although no forget failure has been observed.
- **Branch A', NOT SELECTED:** the outcome line `:31` (`- "outcome": one of the quoted values "ignore", "digest", "tellnow" or "act".`) stays as it is.
- **No other string changes.** No user-facing string changes. The strip's fallback text and the Story 30.6 warning stay as they are. The eval case's description and the mock's texts are test data, not product text.

### Contended edits (the ruled plain union with Epic 19, Ruling 4)

`src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls`. Epic 19's hunks (`origin/OCT-epic19`, head `0cb88c2b`), in this branch's numbering, change `:7`, `:123`, `:143` and `:184` and insert 12 lines after `:152`. It leaves these three lines word for word (they sit at its `:16`, `:247-249` and `:261`), so the hunks do not overlap:
- `:16` OLD `///   - TestUserTurnCases (Story 30.5, DW-500): exactly four user-turn cases, one for each "Try it yourself" chip, each with the chip's exact text, the key` → NEW `///   - TestUserTurnCases (Story 30.5, DW-500): exactly four user-turn cases, one for each "Try it yourself" chip, and one remember case (Story 30.9, DW-890), each with the chip's exact text, the key`.
- `:236` OLD `/// limits or an all-clear), and the fields of its kind and nothing else.` → NEW `/// limits or an all-clear), and the fields of its kind and nothing else, and one remember case (Story 30.9, DW-890).`
- `:248` OLD `Do $$$AssertEquals(count, 4, "eval/ holds exactly four user-turn cases")` → NEW `Do $$$AssertEquals(count, 5, "eval/ holds exactly five user-turn cases")`.
- Found and left unchanged: `:180` `turns >= 8` with "(three all-clear, one command and four user-turn)". It is a lower bound, which nine turn cases still meet (eleven or more with Epic 19's documents cases). `Test/Eval/Report.cls:1758` names the four chip cases, not a count (contended; unchanged). No other test, script or document pins the user-turn list or count (searched `src/`, `docker/`, `ci/`, `web/`, `eval/`, `README.md`, `docs/`).

### Optional warning wording: left out (the Planner's nice-to-have)

Naming the property for a missing confidence would need one of two changes, and neither is small:
- **A new status from `DecisionPayload.%OnValidateObject` for `:30`** (for example `$$$PropertyRequired` on `Confidence`, which `RefusalProperty` would name). That changes the demo's "ERROR #5001" words. The intent requires those words exactly, for the reproduction and the mutation. Other tests may pin #5001 too (`Test.Bridge.ReplyCheck`, Epic 19's contended `Test/Bridge/Decide.cls`).
- **A special case in `Decide.RefusalPart` that reads #5001's message.** That message quotes the outcome's value for branch A (`DecisionPayload.cls:23`), which is reply content, so Story 30.6's rule would need a per-message filter.

So it is left out, and Decide and DecisionPayload are untouched.

### Architecture decisions (Rule 6)

- **AD-6:** a person's message makes two requests, and the decide goes through Decide.
- **AD-7:**
  - Triage: static `INSTRUCTIONS`, no `{{`, no tools.
  - One JSON object, checked against `ReplyClass`; content that doesn't validate is unusable.
  - The persona arrives only as data.
  - Haiku 5.5 with effort low and no sampling parameters.
- **AD-8:** the bridge alone decides that a reply is unusable, and `invalid` is a fallback. No `RetryItem` is set by default, so the probe-shape decide is not retried.
- **AD-14:** provenance user; the text is rendered as written.
- **AD-22:** the mock picks by marker, then guide prompt, then the MOCKKEY default, never by prompt wording; the evaluation set runs on the mock on every push and on Claude Haiku 5.5 for each release candidate.
- **AD-26:** the warning goes in the decision's trace session.
- **AD-28:** no all-clear. The new sentence claims no state.
- **AD-29 and AD-33:** Lane A's files; new A/ scenario files only.
- **AD-21:** memory saving stays in Chat's turn, unchanged.
- No AC contradicts an AD's Rule. A code-side loosening would contradict AD-7 and AD-8, and is excluded.

### Ledger inbox (Rule 17)

- **DW-890: addressed by this story's tasks.** It delivers:
  - the cause, verified (branch C) and written above;
  - the fix: the ruled sentence in `Triage.cls:37`;
  - the regression: `TriageUserTurn.TestRememberSentence`, `RememberDecision` (both forms usable, and the demo's reply shape reproduced with the demo's exact warning) and `eval/user-turn-remember/case.json`.

  The entry closes `resolved-by` only on this delivered code plus the Planner's release-candidate eval report at the 1.0.4 cut, which shows the remember case with no Fallback and a confidence on Claude Haiku 5.5. That real-Haiku proof is the Planner's, not this story's.

### Integration and reuse (Rules 1 and 2)

- **Integration.** No service, module or shared component is introduced. AC 2 is the consumer-level check: the strip's payload (Conversation's `chat.message`) reads the decide decision and shows a usable one.
- **Consumes** (unchanged):
  - `Conversation`'s two requests and `Turn.ShownDecisionRef`;
  - `Decide.CheckReply` / `RefusalText`;
  - `Eval.Report.ScoreUserTurn`;
  - the mock's marker rule.
- **Consumed-by:** the decision strip (via `Conversation.Decided` → `TriageDecisionRef` → `ChatMessage.SetDecision`) and the evaluation report.
- **Extend, don't copy:**
  - `RememberDecision` extends `Test.Watch.Case`, PersonaTurns' base. It reuses `Ready`, `PointKeys`, `Session`, `Send`, `WaitDone` and the `ItemIds` clean-up, and PersonaTurns' patterns for arming, adopting the turns and reading the done `chat.message`. Its own `Ask` is a short composition of the base's `Send` and `WaitDone`, not a copy of PersonaTurns' `Ask`, which is Private, prefixes "Hello " and asserts persona blocks.
  - The warning read reuses `Test.Core.Observe.Warnings` / `RemoveWarnings` and `Test.Bridge.ReplyCheck`'s `REFUSED`.
  - `TestEvalCase` reuses `Test.Eval.Cases.Read` and `Plain`.
  - The eval case copies the shape and the expectation of `user-turn-productions`.

### Decided in-stage

- **The spec's file name** is the sprint key, which is cut at 64 characters ("...decisio"), like the earlier truncated keys (`spec-0-6-...-or.md`).
- **The probe** printed only check words, types, counts and flags. It was tested on slot D and on `e30s9pw` before it went into the spec.
- **No fix was planned before the probe** (round 1, the dispatch's rule). The branch table and the candidate wording let one Planner round settle both.
- **The I/O & Edge-Case Matrix sits after the intent block**, not inside it. The skill substitutes the preserved intent contract verbatim, and the dispatch keeps the runner's Intent and Boundaries text unchanged.
- **The optional warning wording is left out** (the subsection above).
- **The scenario** is named `remember-no-confidence`. Its outcome is `tellnow` (the probe printed only "one of the four 1"). Its two reasons are non-blank and quote no user data. Chat's reply is `Noted.`, which claims nothing.
- **The usable forms use the default scripts with no marker**, so each form's own text reaches the decide as written: no `B/` prompt matches either. The probe shape needs a marker, so the reproduction appends one to the typed text.
- **The reproduction is a committed test (AC 3), not only a mutation.** It is the story's "CI-mock reproduction of the reply shape" (epics.md AC 1). It also keeps the check strict: a loosened `DecisionPayload` turns it red.
- **`TestEvalCase` lives in `RememberDecision`.** A new class in `Test/Eval/` would be a folder that Epic 19 edits, and `TriageUserTurn` runs on slots, which do not mount `eval/`.
- **The `Cases.cls` doc lines** take the ruled insertion at `:16` and at the end of `:236` (inside `:234-236`), so each line still describes the four chip cases correctly.
- **`RememberDecision` goes in the Agent area (`shards-5`)**, measured below as about 32 to 34 minutes plus seconds for this class. Epic 19's branch adds `live:documents` to `shards-5` (its own estimate is +300 to 450 s). That would pass 35 minutes with or without this story, so it is Epic 19's rebalance at its integration. This class adds about 10 s to it.

## Verification

**Measured at planning (round 1):**
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

**Measured at planning (round 2, read-only; no runtime started):**
- **The `shards-5` job** (`shard:lane-a@Bridge,Agent live:sign-in-3`):
  - 32 min 9 s on `ci` run 42425689094 (feature `550bf9b8`);
  - 32 min 58 s on run 42419117439 (feature `bed23f1d`);
  - 33 min 37 s on run 42436132783 (`OCT-epic11` `66d7b1c7`).
- **The `shards-2` job:** 26 min 56 s to 27 min 16 s on the same runs.
- **Per class, on run 42425689094:** `Test.Agent.PersonaTurns` 36.33 s for about 35 mock turns, `TriageUserTurn` 0.00 s, `Instructions` 3.51 s, `PersonaBlock` 0.53 s.
- **This story's cost (inference):** `RememberDecision`'s three turns and one file read take about 5 to 15 s, so `shards-5` stays about 32.3 to 33.9 minutes, under REL-4's 35. The `Cases.cls` and `TriageUserTurn` changes add no measurable time, and the remember case adds one case to `lane-a.yml`'s `evaluation` job.
- **In-flight diffs** (`git fetch -q origin`; `git diff --name-only origin/feature/OCT_OcuTalon_MVP...origin/<branch>` over every `OCT-epic*` branch): only `OCT-epic19` touches a file of this story, `Test/Eval/Cases.cls` (ruled). `TriageUserTurn.cls`, `PersonaTurns.cls`, `Test/Watch/Case.cls`, `Test/Core/Observe.cls`, `Triage.cls` and `DecisionPayload.cls` are in no in-flight diff.

**Shared surfaces:**
- Triage's `INSTRUCTIONS` text, pinned by `TriageUserTurn`, `Instructions.TestTriage`, `PersonaBlock.TestParagraphs` and `docker/tests/test-triage-heartbeat.sh`. Each was checked: none holds a length, a paragraph count or a full-text compare that the sentence changes, and all stay green unchanged.
- The eval set's user-turn count, `Test/Eval/Cases.cls:248` (4 → 5, ruled). `Cases.cls:180` (a lower bound) and `Test/Eval/Report.cls:1758` (by name) stay green unchanged.
- The committed A/ scenario set: `scenarios.test.mjs` checks names, never a count.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. Each `RememberDecision` test uses its own session and its own countdown key, clears its countdown, removes its warnings, and its turns and Decision rows are removed after it.

**Commands** (from the root of the Epic 30 worktree, after `git rev-parse --show-toplevel` confirms it; one per call, each about 150 s at most, never two test runs in one message; every `ci/` call carries lane D's variables as written; `<lock-dir>` is the main checkout's `.worktrees/.coordination/locks`):
- (loop) `bash docker/tests/test-triage-heartbeat.sh` -- expected: every line PASS, exit 0.
- (loop) `node --test ci/mock/test/scenarios.test.mjs` -- expected: all pass, so the new scenario file loads with no problem.
- (loop) `bash docker/tests/test-eval-set.sh` -- expected: every rule PASS, so the new case passes the case rules and no `[[mock:` appears outside `eval/mock-wrong/`.
- (loop) `OCUTALON_LOCK_DIR=<lock-dir>/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=30 stage=implement' OCUTALON_RUN_TAG=e30s9iw ci/warm.sh up` -- expected: `WARM up ...` (about 146 s; a wait on the lane lock is normal, since Epic 31's runner shares lane D). Run it only after the scenario file exists, because the mock's files are part of the warm manifest. If the web bundle under `src/ocutalon/csp/` is missing or stale after an integrate-forward, first run `OCUTALON_LOCK_DIR=<lock-dir>/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=30 stage=implement' OCUTALON_RUN_TAG=e30s9i ci/iris.sh build` in its own call (it builds the bundle and starts no stack).
- (loop) `OCUTALON_LOCK_DIR=<lock-dir>/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=30 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s9iw ci/iris.sh class OcuTalon.Test.Agent.TriageUserTurn` -- expected: `CLASS OcuTalon.Test.Agent.TriageUserTurn passed`.
- (loop) the same prefix with `ci/iris.sh class OcuTalon.Test.Agent.RememberDecision` -- expected: `CLASS OcuTalon.Test.Agent.RememberDecision passed` (four tests).
- (loop) the same prefix with `ci/iris.sh class OcuTalon.Test.Agent.Instructions` -- expected: passed.
- (loop) the same prefix with `ci/iris.sh class OcuTalon.Test.Agent.PersonaBlock` -- expected: passed.
- (loop) the same prefix with `ci/iris.sh class OcuTalon.Test.Eval.Cases` -- expected: passed, with `TestUserTurnCases` counting five.
- (loop) `OCUTALON_LOCK_DIR=<lock-dir>/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=30 stage=implement' OCUTALON_RUN_TAG=e30s9iw ci/warm.sh down` -- expected: the warm project removed. Run it at the stage's end, also after a failure. Tear down only this tag.
- (once) `bash ci/checks.sh` -- expected: every block PASS, among them class-rules (assert-concat), ci-config, eval-set and triage-heartbeat (about 20 s).
- (once) `bash docker/tests/test-mock.sh` -- expected: node's report, exit 0 (under 15 s).
- Left to CI and omitted here while CI is available: the IRIS groups `shards-5` (`shard:lane-a@Bridge,Agent`: TriageUserTurn, Instructions, PersonaBlock, RememberDecision), `shards-2` (`shard:lane-a@rest`: Test.Eval.Cases) and `lane-a.yml`'s `evaluation` job (`eval/run.sh` on the mock, now with the remember case, report-only). The fresh-environment forward and reverse shard runs (Rule 19) are left to CI as well: on this harness a fresh stack's start plus a shard does not fit in one call of about 150 s.

**Planned mutations (Rule 19; one per AC; apply, observe red on the warm stack, revert, confirm `git status --short` and `git diff --stat` unchanged, then the class green again on the same stack):**
- AC 1 -- mutation: delete the appended sentence from `Triage.cls:37` → `TriageUserTurn.TestRememberSentence` red.
- AC 2 -- mutation: in `RememberDecision`, pass `remember-no-confidence` as the scenario of `TestTypedForm` and `TestPanelForm` (the probe's exact shape, armed at 1) → both red on Fallback 1 / `invalid`, the missing confidence, the strip's fallback flag and one warning that is exactly the demo's.
- AC 3 -- mutation: delete the missing-confidence refusal (`DecisionPayload.cls:30`) → `TestProbeShapeIsTheDemoWarning` red (Fallback 0, no warning). This relies on an inference: `CheckReply` makes a new instance for each reply, so the warm reload reaches the running Decide job. If no red shows, restart the warm stack's production (`Ens.Director.RestartProduction()`; this stage started the stack), then revert, restart again and re-run green.
- AC 4 -- mutation: change `turn.text` of `eval/user-turn-remember/case.json` (or move the folder away) → `RememberDecision.TestEvalCase` red, and with the folder moved `Test.Eval.Cases.TestUserTurnCases` red (count 4).
- AC 5 -- check: `git diff --name-only <baseline_revision>` lists only the Execution files and this spec.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Re-plan (round 2) of a spec whose round 1 halted for a real-model probe (`blocked`, intent gap; superseded, see Spec Change Log). The probe selected branch C (no `confidence`), and every question is ruled.
- Planned:
  - the ruled sentence on `Triage.cls:37`;
  - `TriageUserTurn.TestRememberSentence`;
  - the new scenario `ci/mock/scenarios/A/remember-no-confidence.json`;
  - the new `Test.Agent.RememberDecision`: both forms usable, the demo's shape and warning reproduced, the eval case's fields;
  - `eval/user-turn-remember/case.json`;
  - the ruled three-line plain union in `Test/Eval/Cases.cls`.
- Decide, DecisionPayload, Chat, `eval/run.sh` and `ci/units.sh` stay untouched. The optional warning wording is left out (Design Notes).
- No source file was changed and no runtime was started in this pass. Read-only: `git fetch` and diffs of the in-flight branches, and `gh run` job timings.
