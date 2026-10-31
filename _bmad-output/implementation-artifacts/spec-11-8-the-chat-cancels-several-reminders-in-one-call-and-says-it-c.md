---
title: 'Story 11.8: The chat cancels several reminders in one call and says it can set them'
type: 'feature'
created: '2026-10-31'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-11-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `cancel_reminder` takes one ref per call. A "cancel all my reminders" turn with three pending reminders needs list, cancel, cancel, cancel and a reply: five model requests, over Chat's ceiling of 4 (AD-20), so the turn ends unusable after the cancels ran (DW-140). Chat's instructions also name no reminder ability, and their first rule tells the model to answer "a command" with "I can't run commands", so a live model may refuse to set a reminder (DW-142). The tests that check a turn's Visual Trace steps hold three copies of one checker (DW-316).

**Approach:** `cancel_reminder` takes `reminderRefs`, one or more refs, and submits one `CancelReminder` per ref inside the one tool call. Each command gets its own `IdempotencyKey` at the next command position (U-118, owner). AD-20 is not changed. Chat's instructions gain a reminder block ahead of the no-commands rule, and the rule itself is unchanged. One public step checker in `Test.Agent.RunnerFixture` serves the three step-checking tests. Everything is pinned on the CI mock. The live check on Claude Haiku 5.5 is Story 38.1's.

## Boundaries & Constraints

**Always:**
- **Thin tools (Story 1.10, decision 5).** The tool passes each ref to the owner as given, in order. It does not dedupe and does not stop at a refusal. `ReminderOps` decides each ref, and the tool reads and writes no table (AD-1, AD-33).
- **One command per ref.** Each ref goes through `CommandCall.Run`, so each command carries origin `tool`, the session, and the key `<ItemId>:<n>`, where n is the next command position (`Bridge.Context.CommandCount`).
- **Session check first.** `CommandCall.Session` runs before the refs are read. A call that is not a session's turn answers `NOSESSION`, whatever its arguments, and submits nothing.
- **Private helpers.** Every helper in `ReminderTools` is `[ Private ]`. A public method of a `%AI.Tool` class becomes a tool, and `TestDeclarations` pins three.
- **Text rules.** Model-facing texts are ASCII sentences. Comments state the contract (Rule 14).
- **Mock scenarios.** New ones go under `ci/mock/scenarios/A/`.

**Never:**
- Change AD-20's ceiling (`Chat.MaxIterations` stays 4) or any AD text.
- Change `CommandCall`'s key rule, or `src/bridge/cls/OcuTalon/Bridge/Context.cls` (Epic 30's file).
- Change the catalog key `agent.noCommands`, or the instruction line that quotes it.
- Change the step label "Cancelling a reminder".
- Change `ci/mock/mock.mjs` or `ci/mock/scenarios.mjs` (AD-22, U-194).
- Edit a file of Epics 15, 30, 12 or 13. Among them are `Test/Bridge/Gate.cls`, `Test/Bridge/CodeRules.cls` and `Bridge/Context.cls`.
- Add a browser spec, or change `ci/units.sh`.
- Use a real model key, or run any test on slot A.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| several refs (DW-140) | session turn; `reminderRefs` [R1,R2,R3]; next position p | three `CancelReminder` commands in order, keys `:p`, `:p+1`, `:p+2`; answer `{"ok": true, "results": [Answer(R1), Answer(R2), Answer(R3)]}`, each entry with its `ref` | none |
| one refused | as above, owner refuses R2 | R1 and R3 still submitted; R2's entry is `{"ok": false, "message": <owner's>, "ref": R2}`; top `ok` false | refusal stays in its entry |
| one ref | `["R"]` or the JSON string `"R"` | one command; flat answer exactly as today (`{"ok","message","ref","due","dueLocal"}` or the owner's refusal) | unchanged |
| failed submit | double in fail mode, [R1,R2] | both recorded; two entries `{"ok": false, "message": NOTSENT, "ref": Ri}`; one warning each | NOTSENT per entry |
| bad shape | left out, `[]`, `{}`, an entry that is not a string (`5`, `{}`, `null`) | `{"ok": false, "message": BADREFS}` | nothing submitted |
| no session's turn | no context, any arguments | `{"ok": false, "message": NOSESSION}` | nothing submitted |
| cancel all, real owner (DW-140, AD-20) | session A has three pending reminders, B has one; "Cancel all my reminders." | Chat makes 3 requests (list, one cancel call, reply), under the ceiling of 4; A's three rows cancelled with keys `:2`, `:3`, `:4`, waiters ended, rail empty; B untouched | no fallback |

</intent-contract>

## Code Map

**The tool**
- `src/ocutalon/cls/OcuTalon/Tools/ReminderTools.cls`:
  - :1-14 is the class doc;
  - :18-19 is `BADDELAY`, the pattern for `BADREFS`;
  - :25 is `STEPLABELCANCELREMINDER`, unchanged;
  - :71-80 is `CancelReminder(reminderRef)`, which this story changes. Its doc comment is the description the model reads. The argument's `DESCRIPTION` is what the model reads about it.
- `src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls`, read only:
  - :36-62 `Run`: the key is `ItemId:(CommandCount+1)`, written back;
  - :66-73 `Session(.context)`: public, "" or the NOSESSION object;
  - :77-90 `Answer`;
  - :132 `Refusal` is private, so the tool builds its own `{"ok": false, "message": ...}`.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls:4-5, 50-55`, read only (Epic 30): `CommandCount` is "the number of commands that the tools of the call have submitted".
- `src/ocutalon/cls/OcuTalon/Tools/Reminders.cls`: the toolset `XData`. It needs no change.
- `src/ocutalon/cls/OcuTalon/Schedule/ReminderOps.cls:172-209`, read only: `Cancel`. A key that an earlier cancel used for another ref is refused `reused_key`, which is why each ref needs its own key. A ref that is not one of the session's pending reminders is refused `no_reminder`.
- Measured at plan time on slot A (build 154U):
  - `%AI.Tool.Schema.%ParameterSchema("%Library.DynamicArray", ...)` gives `{"type":"array","items":{"type":"string"}}`;
  - `%AI.ToolMgr.ExecuteTool` checks neither required nor unknown arguments nor their types: `cancel_reminder` with `{}`, an unknown key, or an array for a string all reached the method, which answered NOSESSION;
  - `%AI.Tool.Generator.GenerateInvoke` passes a dynamic-class argument through as `args.<name>`.
  - Whether the XData toolset compiler passes the argument the same way is Task 0's to confirm (inference until then).

**The agent**
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls`:
  - :1-6 is the class doc;
  - :21 is `MaxIterations` = 4, unchanged;
  - :37-39 is "What you do:" and its no-commands line, unchanged. The reminder block goes between them.

**The tests and fixtures**
- `src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls` (Lane A; area Tools, shard lane-a@rest, CI group `shards-2`):
  - :1-57 is the header;
  - :159-245 is `TestDeclarations`: :168 is `want("cancel_reminder")`, and :180 is the type pin of delaySeconds, the pattern for the new type pin;
  - :329-386 are `TestCancel` and `TestCancelRefused`;
  - :816-847 is `TestBadDelayThroughTheToolManager`, the pattern for a tool-manager test;
  - :849-893 are `Prepare`, `Begin` and `CallTool`;
  - :928-963 is `AssertSteps`, the DW-316 copy;
  - :1103 is `RefOf(tag)`.
- `src/ocutalon/cls/OcuTalon/Test/Tools/CommandsDouble.cls`:
  - :1-25 is the doc of its modes;
  - :50-60 is the `refuse` mode by verb. The new `refuseRef` mode sits beside it.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls` (Lane B's file, changed under AD-29's Epic 11 exception; area Schedule, shard lane-b, CI group `image`):
  - :1-20 is the header;
  - :33-34 is `FIXEDREF`;
  - :92-110 is `OnAfterOneTest`;
  - :115-163 are `Turn` and `AssertChat`;
  - :223-233 is `ListedRefs`;
  - :237-292 are `WaitSteps` and `AssertToolSteps`, the DW-316 copy;
  - :352-398 is `TestCancelThroughChat`, the pattern for the new test.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Turns.cls:264-291`: `AssertSteps(answer, session, label, tool, status)` is the third copy. Its callers (:64, :94, :154) all pass "ok". Area Watch, shard lane-a@Checks,Install,Watch, CI group `shards`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:
  - :1-56 is the header;
  - :323-333 `Headers`, :335-346 `StepsOf` and :415 `CountTo`;
  - :823-861 is `FallbackProblems`, the "; "-joined problem-string pattern that the new checker follows.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls` (area Agent, shard lane-a@rest, CI group `shards-2`):
  - :1-25 is the header;
  - :67-115 is `TestChat`;
  - :171 is the `cancel_reminder` argument in `TestToolsets`.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderOpsFixedRef.cls`, read only: `Next(ref)` gives the next set its Ref, once.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderFixture.cls`, read only: `Remove` :96, `RemoveAll` :143, `WaitEnded` :221.
- Read only and unchanged, but they read what changes:
  - `Test/Bridge/Gate.cls:1764` passes `{"reminderRef":"x"}`. The gate denies the call before the method runs, and ExecuteTool checks no argument (measured), so the test is unaffected. Epic 30's file.
  - `Test/Bridge/CodeRules.cls:585-586` and `ToolCodeClean` scan ReminderTools: no SQL, table or global, and only the three command classes.
  - `Test/Install/Tools.cls:89` pins the label.
  - `Test/Agent/Runners.cls:305`: Chat's system block is already cache-marked, and it only grows.

**The mock**
- `ci/mock/scenarios/A/reminder-cancel.json:19` and `ci/mock/scenarios/B/reminder-cancel-chat.json:19` send `"reminderRef"`.
- The B file is also read by `web/e2e/reminder/chat.spec.ts:142` (live:sign-in, CI group `browser`).
- `ci/mock/scenarios/B/reminder-thursday.json` (marker `reminder-thursday`) sets "load the new certificate" at the local time 2030-11-07T10:00:00. It is read only.

## Tasks & Acceptance

**Execution:**
- `ci/mock/scenarios/A/reminder-cancel-all.json` -- new, marker `reminder-cancel-all`. Three replies:
  - `list_reminders`;
  - `cancel_reminder` with `{"reminderRefs": ["zzReminderChatCancel02","zzReminderChatCancel03","zzReminderChatCancel04"]}`;
  - the text "The CI mock cancelled the reminders.".
- `ci/mock/scenarios/A/reminder-cancel.json`, `ci/mock/scenarios/B/reminder-cancel-chat.json` -- the input becomes `{"reminderRefs": ["<the same Ref>"]}`. The B edit is a key rename under AD-29's Epic 11 exception, with no behaviour change.
- `src/ocutalon/cls/OcuTalon/Tools/ReminderTools.cls` -- the tool change (DW-140):
  - `CancelReminder(reminderRefs As %DynamicArray(DESCRIPTION = "The refs of the reminders to cancel, each exactly as list_reminders gave it: one or more."))`. The argument stays required in the schema.
  - Add `Parameter BADREFS = "reminderRefs must hold one or more refs, each as list_reminders gave it, so nothing was cancelled."`.
  - The steps, in order:
    1. `CommandCall.Session` (NOSESSION).
    2. Read the refs: a non-empty `%DynamicArray` whose entries are all JSON strings, or a non-empty scalar (one ref). Anything else answers BADREFS.
    3. One ref: return the flat answer of today's code.
    4. Several refs: one `Run` per ref; each entry is `Answer` (or the `Run` refusal), with `ref` set to the given ref when the entry has none. The answer is `{"ok": <boolean: every entry ok>, "results": [...]}`, returned once through `Return`.
  - Replace the method's doc comment with: "Cancels pending reminders of the user in this conversation. Give in reminderRefs the ref of every reminder to cancel, exactly as list_reminders gave it, all in this one call: one ref, or several, such as every pending one when the user asks to cancel all of them. With one ref, the answer says whether that reminder was cancelled. With several, ok is true only when every one was cancelled, and results holds one answer for each ref, in the order given, each with its ref. When a reminder was not cancelled, its message says why, in plain English, so tell the user."
  - Update the class doc.
- `(Task 0, measure)` -- once the `ReminderTools` change compiles on slot A, read `cancel_reminder`'s discovered `parameters` through a fresh `%AI.ToolMgr` with no bridge context (it answers NOSESSION and submits nothing). Record the schema under Verification. On the first warm run of `TestCancelThroughTheToolManager`, record what a JSON array and a JSON string reach the method as. If the toolset path decodes the array as anything other than a `%DynamicArray`, read that form into the same list of refs, and record it.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- DW-142. Insert as the first bullet of "What you do:", before the unchanged no-commands line, exactly:
  ```
  - You can set, list and cancel the user's reminders in this conversation. A request about a reminder is never a request to run a command:
    - If the user asks you to remind them of something, call set_reminder, then say what you set and when it is due, from the answer.
    - If the user asks which reminders they have, call list_reminders and name each one with its due time.
    - If the user asks you to cancel one or more reminders, call list_reminders first when you do not have their refs. Then call cancel_reminder once, with the refs of every reminder to cancel. Then say which reminders you cancelled and, for any that was not cancelled, why, from its message in the answer.
  ```
  The class doc says that the reminder block comes before the no-commands rule, and that a test pins both.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- add `ClassMethod StepProblems(decisionRef As %String, sessionId As %Integer, labels As %List, tools As %List, runner As %String = "", seconds As %Integer = 10) As %String` (DW-316). It polls `StepsOf` every 0.25 s, for at most `seconds`, until it has 1 + 2n steps. It then names, joined by "; ", or answers "" when there is nothing to name:
  - kinds other than `model` followed by n pairs of `,tool,model`;
  - a tool step i with a label other than labels(i), a summary that lacks tools(i), or a status other than `ok`;
  - a step with a header outside `sessionId`;
  - a step with no header in it;
  - when `runner` is not empty, a count of the runner's replies to Decide in the session other than 1.
  - Add it to the header.
- `src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls`, `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls`, `src/ocutalon/cls/OcuTalon/Test/Watch/Turns.cls` -- each step checker becomes one `$$$AssertEquals(StepProblems(...), "", ...)` call:
  - Reminders: `AssertSteps` passes runner `ChatAgent`;
  - ReminderChat: `AssertToolSteps` opens `row.TraceHeaderId`, asserts that it exists, and passes its `SessionId`. `WaitSteps` goes;
  - Turns: `AssertSteps` passes `ChatAgent`, and its `status` argument goes.
- `src/ocutalon/cls/OcuTalon/Test/Tools/CommandsDouble.cls` -- add the mode `^OcuTalonTest("CommandsDouble","refuseRef",<ReminderRef>) = <message>`: a `CancelReminder` of that ref is refused with that message. Document it with the other modes.
- `src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls` -- `TestDeclarations`: the input is `reminderRefs`, required, of type `array` with items of type `string`. Add two tests and update the header:
  - `TestCancelSeveral` (in process): the matrix rows "several refs", "one refused" (`refuseRef` on R2), "one ref" (`["R1"]`, and the string "R1") and "failed submit". Each checks the double's records (class, origin, session, key, `ReminderRef`) and the whole answer (`AssertObject` per entry).
  - `TestCancelThroughTheToolManager` (in process, a fresh `%AI.ToolMgr`, as `TestBadDelayThroughTheToolManager` does): `{"reminderRefs": [R1,R2]}` gives two commands and the several-ref answer; `{"reminderRefs": "R3"}` gives one command and the flat answer; each bad shape of the matrix gives BADREFS and records nothing.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/ReminderChat.cls` -- add `TestCancelAllThroughChat`:
  - A sets three reminders with the marker `reminder-thursday`, each after `ReminderOpsFixedRef.Next(zzReminderChatCancel0<k>)` for k = 2, 3, 4. B sets one the same way, with no fixed Ref.
  - A sends "Cancel all my reminders. [[mock:reminder-cancel-all]]".
  - It asserts the last matrix row, and also:
    - `AssertChat(chat, 3, "marker")`;
    - the last tool result of request 2 lists exactly A's three Refs, in any order;
    - the last tool result of request 3 is `{"ok": true, "results": [...]}`, with each entry ok, in the scenario's order;
    - each row's `CancelKey` is `<ItemId>:2`, `:3` and `:4`, and `WaitEnded`;
    - A's events read `pending,pending,pending,cancelled,cancelled,cancelled`;
    - `##class(OcuTalon.Agent.Chat).%New().MaxIterations` = 4;
    - the steps are list, then cancel.
  - Add the three Refs to the clean-up, before and after the test, and to the header.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls` -- `TestChat` pins the reminder block (AC5). `TestToolsets`' `cancel_reminder` argument becomes `{"reminderRefs": ["zzReminderStretch00001"]}`. Update the header.

**Acceptance Criteria:**
- **AC1 (DW-140, U-118).** Given a session's turn, when `cancel_reminder` gets several refs, then the "several refs", "one refused" and "failed submit" rows hold (`TestCancelSeveral`). Each command has its own key at the next position, in the order of the refs.
- **AC2.** Given one ref, as a one-element list or a JSON string, when the tool runs, then it submits one command, and its answer is byte-for-byte today's flat answer. `TestCancel`, `TestCancelRefused`, `TestToolsPassOnWhatTheModelGave`, `TestRefusalsAreUnchanged` and the `TestSubmit*` tests pass with their assertions unchanged.
- **AC3.** Given AI Hub's tool manager, when `cancel_reminder` is discovered and run, then:
  - its input is `reminderRefs`, required, an array of strings;
  - the bad shapes answer BADREFS and submit nothing;
  - a call outside a session's turn answers NOSESSION first (`TestDeclarations`, `TestCancelThroughTheToolManager`, `TestNoSession`, `Instructions.TestToolsets`).
- **AC4 (integration: consumer `ReminderOps`, real; AD-20).** Given three pending reminders in session A and one in B, when A sends "Cancel all my reminders." on the CI mock, then the turn finishes in 3 model requests with no fallback and Chat's ceiling still 4. A's three reminders are cancelled with keys `:2`, `:3` and `:4`, their waiters end, their cancelled events arrive, and A's rail is empty. B's reminder, waiter, events and rail are unchanged (`TestCancelAllThroughChat`).
- **AC5 (DW-142).** Given Chat's compiled INSTRUCTIONS, when `TestChat` reads them, then they hold:
  - "You can set, list and cancel the user's reminders in this conversation.";
  - "A request about a reminder is never a request to run a command";
  - "call set_reminder";
  - "call list_reminders and name each one with its due time";
  - "Then call cancel_reminder once, with the refs of every reminder to cancel.";
  - all before the unchanged line "If the user asks you to run a command, reply with exactly this sentence and nothing else, and do not call a tool: " followed by the rendered `agent.noCommands`.
- **AC6 (DW-316).** Given the three step-checking tests, when they check a turn's steps, then each calls `RunnerFixture.StepProblems` and holds no copy of its loops. `Tools.Reminders`, `ReminderChat` and `Watch.Turns` pass.
- **AC7.** Given the renamed input in `A/reminder-cancel.json` and `B/reminder-cancel-chat.json`, when `TestCancel`, `TestCancelThroughChat` and `web/e2e/reminder/chat.spec.ts` C2 run, then they pass with their assertions unchanged.

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions.**

| AD | What it governs here |
| --- | --- |
| AD-1 | A tool's state change is a `CancelReminder` through `CommandsIn`, with its own `IdempotencyKey`. |
| AD-4 | `ReminderOps` cancels only the session's own reminders. |
| AD-6 | Tool code makes no AI Hub or Python call. |
| AD-7 | Chat's static INSTRUCTIONS, with no `{{`, and its TOOLSETS. |
| AD-8 | A turn that reaches the ceiling is unusable. |
| AD-9 | One tool step per call, with its label. |
| AD-10 | One gate decision per tool call; the classification is unchanged: safe, not read-only, trusted output. |
| AD-18 | Reminders. |
| AD-20 | The ceiling of 4 is unchanged (U-118). |
| AD-22 | The CI mock; new scenarios under `A/`; `mock.mjs` unchanged. |
| AD-26 | The steps are in the turn's trace session. |
| AD-29 | The Epic 11 exception covers the B files `Test/Schedule/ReminderChat.cls` and `B/reminder-cancel-chat.json`. |

**AD-1 compliance (U7 step 1).** AD-1's key is "the turn's ItemId plus the tool call's position". The merged build counts the commands (`Bridge.Context.CommandCount`, "the number of commands that the tools of the call have submitted"). A call that submits nothing, such as `list_productions` or `check_status`, takes no position, so the merged code already reads that position as the command's. The several-ref cancel follows that reading, and each ref takes the next position, as U-118 requires. The literal one-key-per-call reading would make `ReminderOps` refuse the second ref as `reused_key`. No AD changes. Whether to reword AD-1's parenthetical is for the lead to decide; this story does not need it.

**Extend, don't copy (Rule 2).**
- `StepProblems` replaces three copies:
  - `Test.Tools.Reminders.AssertSteps`;
  - `Test.Schedule.ReminderChat.AssertToolSteps` with its `WaitSteps`;
  - `Test.Watch.Turns.AssertSteps`.
  - It follows `RunnerFixture.FallbackProblems`' problem string. The strictest check of the three, that every step has a header in the session, now holds for all three callers.
- `BADREFS` follows `BADDELAY`.
- `refuseRef` sits beside the double's `refuse` mode.
- `A/reminder-cancel-all.json` follows `A/reminder-cancel.json`'s three replies.

**Integration ACs and links (Rule 1/2).** AC4 is the consumer `ReminderOps` against the real production. AC6 is the consumers of the shared checker.

| Link | Who |
| --- | --- |
| Consumes | `CommandCall` (`Session`, `Run`, `Answer`), `ReminderOps` through `CommandsIn`, the CI mock, `RunnerFixture`, `ReminderOpsFixedRef`, `ReminderFixture` |
| Consumed-by | the Chat agent: the model reads the description, the schema and the instruction lines |
| Consumed-by | Story 38.1: DW-358's live "cancel all my reminders" with three or more pending, and DW-142's live phrasings, on Haiku 5.5 |
| Consumed-by | `RunnerFixture.StepProblems`: the three tests above, and any later tool test |

**Ledger (Rule 17).**
- Addressed:
  - DW-140 (AC1 to AC4, AC7);
  - DW-142's instruction half (AC5);
  - DW-316 (AC6).
- Declined DW-142 (live-check half): the real-key check belongs to Story 38.1's pass

**Decided in-stage.**
- **One argument, plural.** `reminderRefs`, an array of strings, replaces `reminderRef`. A plural name and an array schema push the model to cancel in one call. The two existing cancel scenarios move to one-element arrays with their Refs unchanged.
- **A JSON string counts as one ref.** A live model may send one. Existing callers in process, `CallTool` and `CancelReminder("no such reminder")`, keep working.
- **Two answer shapes.** One ref keeps today's flat answer, the contract of Stories 1.10 and 8.6. Several refs answer `{"ok", "results"}`, and each entry names its ref, so a refusal maps to its reminder.
- **No dedupe and no cap** (thin tools). A ref given twice is cancelled once, and its second entry is the owner's `no_reminder`. A session has few pending reminders, and `Return` cuts an oversized answer (inference).
- **The label stays "Cancelling a reminder".** There is still one tool step per call, and four test classes pin the label.
- **Two texts stay byte-identical:** the catalog sentence `agent.noCommands` and its instruction line (user-facing catalog text). The reminder block makes reminders an explicit exception ahead of it. The block claims only what the tools do.
- **The cancel-all test sets its reminders with the Thursday marker** (due in 2030), so none fires during the test. The guide prompt's 60-second reminders could.
- **`Test/Bridge/Gate.cls:1764`'s stale `reminderRef` stays.** It is harmless (measured), and the file is Epic 30's.

**Contended paths (U14).**
- No file planned here appears in `git diff origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic<N>` for N = 15, 30, 12 or 13. The diffs were re-checked at plan time.
- The new file sits in `ci/mock/scenarios/A/`.

**CI budget (REL-4).**
- No browser spec is added.
- `TestCancelAllThroughChat` adds five mock turns to shard lane-b, about 10 to 15 s on ARM and about 30 to 45 s in CI group `image`, which runs about 1,660 s (inference).
- The in-process tests add about 2 s to `shards-2`. `Watch.Turns` is unchanged in time.

## Verification

`<A>` stands for `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=11 stage=implement'`. QA uses `stage=qa` with the tags `e11s8q`/`e11s8qw`, and review uses `stage=review` with `e11s8c`/`e11s8cw`. `<scratch>` is the stage's own scratch folder, never a repository path.

**Run discipline:**
- Run everything from the epic-11 worktree root.
- Each command runs in the foreground of its own call, with `timeout: 600000`. `ANTHROPIC_API_KEY` stays unset.
- One test call per message. Never re-submit after a client-side timeout.
- Every IRIS MCP call passes `server` `ocutalon-slot-a` and namespace `OCUTALON`.

**Shared surfaces:**
- `cancel_reminder`'s input schema and answer, read by `TestDeclarations`, `Instructions.TestToolsets`, `Bridge.Gate` (read only), `A/reminder-cancel.json`, `B/reminder-cancel-chat.json` and `web/e2e/reminder/chat.spec.ts`.
- Chat's INSTRUCTIONS, read by `TestChat` and `Runners`' system-block cache mark.
- `ci/mock/scenarios/A/` gains one scenario.
- `^OcuTalonTest("CommandsDouble")` gains `refuseRef`, which the class's existing kill of that node clears.
- ReminderChat's fixed Refs 02 to 04.
- `RunnerFixture`'s step checker, used by three classes.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead's lane-a and lane-b shards, forward and `--reverse`, are the order check.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-a` -- expected: build 154U.
  - Then load and compile there: `Tools/ReminderTools.cls`, `Tools/Reminders.cls`, `Agent/Chat.cls`, and the test classes `Agent/RunnerFixture`, `Tools/CommandsDouble`, `Tools/Reminders`, `Schedule/ReminderChat`, `Watch/Turns` and `Agent/Instructions`. Then run Task 0's schema read -- expected: they compile, and `reminderRefs` is `{"type":"array","items":{"type":"string"}}` and required. No test runs on the slot.
- (once) `<A> OCUTALON_RUN_TAG=e11s8i ci/iris.sh build` -- expected: the image and the bundle build.
- (once, after the three scenario files are written) `<A> OCUTALON_RUN_TAG=e11s8iw ci/warm.sh up` -- expected: `LOCK acquired warm-iris`. Any later change under `ci/mock/` needs `ci/warm.sh down` and then `up`.
- (loop) `<A> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e11s8iw ci/iris.sh class <C>`, one call for each C of `OcuTalon.Test.Tools.Reminders`, `OcuTalon.Test.Schedule.ReminderChat`, `OcuTalon.Test.Agent.Instructions` and `OcuTalon.Test.Watch.Turns` -- expected: `CLASS <C> passed`.
- (once) the same warm call for each of `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Agent.Runners`, `OcuTalon.Test.Install.Tools` and `OcuTalon.Test.Contract.Ac` -- expected: passed.
- (once) `<A> OCUTALON_RUN_TAG=e11s8i ci/iris.sh class <C>` for the four changed classes, one per call -- expected: passed on a fresh stack.
- (once) `bash docker/tests/test-mock.sh` -- expected: passes, and the new scenario loads.
- (once) `bash docker/tests/test-boundaries.sh`, then `bash docker/tests/test-class-rules.sh`, one per call -- expected: every PASS. These are the parts of `ci/checks.sh` that this story touches.
- (once) the browser check of AC7:
  - Write `npm --silent --prefix web run e2e -- --list --reporter=json` to `<scratch>/listing.json`.
  - Run `node web/scripts/e2e-part.mjs k/3 <scratch>/listing.json` for k = 1, 2 and 3, to find the part that names `reminder/chat.spec.ts`.
  - Run `<A> OCUTALON_RUN_TAG=e11s8i ci/iris.sh live sign-in --part k/3` for that k -- expected: the part passes.
- (once, last; also after a failure) `<A> OCUTALON_RUN_TAG=e11s8iw ci/warm.sh down`, then `<A> OCUTALON_RUN_TAG=e11s8i ci/iris.sh teardown` -- expected: no lock of this stage is left in the lane-a folder.

**Planned mutations (Rule 19).** For each one: apply it, see red, revert, check that `git status --short` and `git diff --stat` are unchanged, then see green again. A red that a leftover on the warm stack could explain counts only when the class is green again on the same stack. The AC4 mutation changes `ci/mock/`, so it runs on a fresh class run.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `CancelReminder` submits only the first ref of a list | `TestCancelSeveral` (one command recorded) |
| AC1 | every ref of the call gets the call's first position (`CommandCount` put back before each `Run`) | `TestCancelSeveral` keys; `TestCancelAllThroughChat` (`reused_key`, rows still pending) |
| AC2 | a one-element list answers the several-ref shape | `TestCancel` on the flat answer |
| AC3 | an empty list answers `{"ok": true, "results": []}` | `TestCancelThroughTheToolManager` |
| AC4 | `A/reminder-cancel-all.json` cancels one ref per call (three cancel replies) | `TestCancelAllThroughChat`: over the ceiling, a fallback reply |
| AC5 | the reminder block removed from INSTRUCTIONS | `TestChat` |
| AC6 | `StepProblems` compares each label with the label plus "x" | `TestCancel`, `TestCancelThroughChat` and `Watch.Turns` |
| AC7 | `B/reminder-cancel-chat.json` keeps `"reminderRef"` | `TestCancelThroughChat` (refused BADREFS) |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned and verified against the READY FOR DEVELOPMENT standard on 2026-10-31; halted after planning as the dispatch asked. Nothing is implemented, and the spec is uncommitted.
