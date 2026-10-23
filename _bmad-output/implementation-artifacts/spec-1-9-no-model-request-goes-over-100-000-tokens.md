---
title: 'Story 1.9: No model request goes over 100,000 tokens'
type: 'feature'
created: '2026-10-23'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-6, AD-7, AD-8, AD-9, AD-10, AD-19 (the Bridge values bullet), AD-20, AD-22, AD-26, AD-31 and AD-33, and the Tool results, Settings, Redaction and Tests rows of Consistency Conventions)'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:**
- **Nothing stops an oversized request.** `Decide`'s precheck knows `no_key`, `daily_cap` and `budget` only; `too_large` exists in `Msg.Enum` and the catalog but is never given.
- **The estimate is too small.** `Decide.EstimateTokens` counts `Input`, `SeedText` and `SystemNote` (`Decide.cls:556`). It leaves out the system prompt, the tool schemas and, since Story 1.8, a linked conversation's stored history, and it counts a seed that only a linked `fresh` turn sends.
- **Nothing flags a long conversation** for the compaction that Story 30.1 builds (AD-20).
- **Tool results are not bounded.** `OcuTalon.Tools.Result` does not exist, and the one built-in tool class (`WatchFixture`) returns pre-encoded JSON strings, which AI Hub encodes again (Conventions, "Tool results").
- **No test names the tools each agent offers.** `Test.Agent.Runners` only counts them.

**Approach:**
- **The size check.** `Decide` estimates every request's first model request: the runner's agent's system prompt and tool schemas, the linked history, and the input that `Chat` gets. A request above the request-size limit takes `too_large` and is never sent. The limit is a host setting whose default and ceiling are 100,000.
- **The flag.** A turn above 40,000 tokens is flagged with a new `Request.Compact`. The runner ignores the flag until Story 30.1, so the turn is sent as it is.
- **The tool-result cap.** `OcuTalon.Tools.Result` is the shared base of the built-in tools. It cuts and marks each result against the current model step's 10,000 tokens. The total is kept in the bridge context and reset at every `OnMessage`. The watch fixture returns dynamic objects through it.
- **The tools of each agent.** A live test names each agent's offered tools exactly.

## Boundaries & Constraints

**Always:**
- **The estimate (AD-6, AD-20).** `Decide.EstimateTokens(request, runner, agentClass As %String = "", Output sc As %Status) As %Integer` is `StepBuffer.Tokens` of the sum of three parts. An empty `agentClass` means the runner item's `AgentClass` setting (`Ext.Accessor.ValueFor`).
  1. **The agent part:** `RequestSize.AgentChars(agentClass)`.
  2. **The history:** `RequestSize.HistoryChars(ConversationLink.SessionOf(OwnerRef, runner))`, but only for a linked turn (`Adapter.Agent.IsLinked`) whose `SessionMode` is not `fresh`. It is 0 otherwise, and 0 when the turn has no link.
  3. **The input:** `$Length(Adapter.Agent.ChatInput(request, seeded))`, with `seeded` 1 only for a linked `fresh` turn. This is what the runner sends, so a seed on any other request no longer counts.

  `sc` is an error when the agent part could not be read; that part then counts 0.
- **`OcuTalon.Bridge.RequestSize` (new).** Its methods only read: they build no AI Hub agent, make no `$ZF` call and name no other OcuTalon package.
  - **`AgentChars(agentClass, Output sc) As %Integer`** adds up two parts:
    - **The system prompt:** the length of the class's compiled `INSTRUCTIONS`, read the way AI Hub loads it: `%Dictionary.CompiledXData`, lines joined by `$Char(10)`, the last line break dropped (`%AI/Agent.cls:364-401`).
    - **The tool schemas:** for each class that its `TOOLSETS` parameter names (comma-separated and trimmed), the length of `$ClassMethod(<toolset>, "%New").%Discover().%Get("tools").%ToJSON()`.

    A part that cannot be read counts 0 and sets `sc`. A toolset named by a URI (its name holds `:`) counts 0.
  - **`HistoryChars(sessionId) As %Integer`:** the length of the saved AI session's stored history (`%AI.Agent.Session`, `ContextData`). It is read from the stored value, never by opening or attaching the session (Task 0 (b) picks the reader). It is 0 for "" and for an id that has no stored history.
- **The request-size limit (AD-8, AD-19, NFR-3).**
  - **The setting:** a new `Decide` host setting, `Property RequestTokenLimit As %Integer [ InitialExpression = 100000 ]`, listed as `RequestTokenLimit:Bridge` in `SETTINGS`, with `Parameter MAXREQUESTTOKENS = 100000`.
  - **The limit:**
    - a whole number from 1 to 100,000 is the limit;
    - an empty value counts as 100,000, with no warning;
    - any other value (0, a value that is not a whole number, or one above 100,000) counts as 100,000 and logs one Type 3 warning that names `RequestTokenLimit` and passes `Redact.Text`.

    So the limit is never off and never above 100,000.
  - **Assignment:** `AssignOneSetting` treats it as it treats `DecisionTokenBudget`: a value that is not made of digits is held as "". The precheck gets the text as written, through one reader for both settings, generalised from today's `TokenBudget()`.
- **The precheck (AD-8, AD-20).** `Precheck(request, runner, tokenBudget, requestLimit As %String = "", Output estimate As %Integer)`:
  - **The estimate:** works it out once (`EstimateTokens`), and logs one warning naming the runner when its agent part could not be read;
  - **The new fact:** gives `Classify` the fact `tooLarge` (the estimate is above the limit). `Classify`'s rule 1 becomes noKey, capped, overBudget, tooLarge, so `too_large` comes after `budget` and before the timer's `timeout`;
  - **When it runs:** before the first send (`OnRequest`) and before every re-send (`Resend`), for every kind;
  - **A `too_large` request:**
    - `RecordFallback` records it, with the outcome `tellnow` and `Fallback` 1, and fires one `decision.recorded`;
    - its answer is the fallback `Reply` of a turn, or the `DecisionResponse` of a decide or diagnose;
    - nothing is sent to a runner: no timer, no steps and no `Usage` row.
- **The flag (AD-20).** `OcuTalon.Bridge.Msg.Request` gains `Property Compact As %Boolean [ InitialExpression = 0 ]`, appended as storage slot 14. `Decide` gains `Parameter COMPACTTOKENS = 40000`.
  - **One method builds what is sent:** every request that `Decide` sends to a runner, the first send and every re-send, comes from one method. It clones the request and sets the clone's `DecisionRef`.
  - **Its `Compact`** is 1 exactly when the request is a `turn` (any provenance, any `SessionMode`) and the precheck's `estimate` is above 40,000; otherwise it is 0, whatever the caller set.
  - **The runner ignores `Compact`.** A flagged request under the limit is sent as it is.
- **The tool-result cap (AD-10, NFR-3).** New `OcuTalon.Tools.Result Extends %AI.Tool [ Abstract ]`, with `Parameter STEPTOKENS = 10000`. The room of one model step is `STEPTOKENS` times `StepBuffer.CHARSPERTOKEN`: 40,000 characters.
  - **`ClassMethod Return(value)`** takes a dynamic object or a string. Its text is `value.%ToJSON()`, or the string itself. There are three outcomes:
    - **Whole:** when the step's running total plus the text's length is at most the room, it returns `value` unchanged (a dynamic object stays one) and adds the length to the total.
    - **Cut:** otherwise, with k = room − total − 1 − the note's length, and k at least 1, it returns as a string the first k characters of the text, then a line break and the note. The total becomes the room.
    - **Left out:** when k would be below 1, it returns the note alone, with 0 characters shown, and adds the note's length. Only when less room than the note's length remains does this pass 40,000 characters, by one note for each such result; that is the only way a step's results pass the room.
  - **The note** is `Parameter CUTNOTE`, filled in as `[cut by OcuTalon: <shown> of <total> characters shown]`, in ASCII.
  - **A value whose text cannot be built whole** (it is longer than the longest string) is left out. Its note gives `unknown` as the total.
  - **The running total** is a new field of the bridge context, `ToolResultChars`:
    - it is in `Context` `FIELDS`, and `Begin` sets it to 0;
    - it is read through `Context.Current()` and written through `Context.Put`;
    - `StepRenderer.OnMessage` sets it to 0 at every model response, so the results of one model step share one room;
    - with no active context, `Return` measures against a fresh room and keeps nothing.
  - **The callback rule (AD-6).** `Result` and every class that extends it name `%AI` only on their Class line and run no Python. `Context` joins `CodeRules`' `CALLBACKHELPERS`.
  - **`Return` is not itself a tool** of a class that extends `Result`, because AI Hub exposes only the concrete class's own methods (Task 0 (d) confirms it).
- **The built-in tools (Conventions, "Tool results").**
  - **The watch fixture:** `OcuTalon.Tools.WatchFixture` extends `OcuTalon.Tools.Result`, and its three methods return `..Return({"items": []})`, declared `As %DynamicObject`.
  - **The rule for every tool provider:** a product tool provider of `OcuTalon.Tools` is a class that extends `%AI.Tool`, is not a toolset and is not `Result`. Every such class extends `Result` and returns only through `..Return(`, and a static scan enforces it.
- **The tools of each agent (AD-7).** They do not change: Triage has none, Diagnosis has the Watch toolset, and Chat has its `TOOLSETS` (none until Story 1.10). The test derives each agent's expected tool names from its `TOOLSETS` (the names in each toolset's `%Discover()`), and it also pins today's lists as literals.
- **The bridge boundary (AD-2).** Nothing in `src/bridge/` names another OcuTalon package. The agent class comes from the runner's setting.
- **The link (AD-6, AD-33).** `Decide` may call `ConversationLink.SessionOf`, which only reads, as well as `Lock` and `Unlock`. It never calls `Point`. The link class's doc and the scan say so.
- **Logs and text.** Every new warning is Type 3 and passes `Redact.Text`. All text in `src/`, `ci/` and `release/` is ASCII (Rule 14).
- **Tests.**
  - **The new area:** `OcuTalon.Test.Tools` joins the shard `lane-a`, through Lane A's entry of `shard_areas` in `ci/units.sh`.
  - **Every test puts back what it changed:**
    - `Decide`'s `RequestTokenLimit` row, with a restart of `Decide`;
    - the AI sessions and links that its user turns saved (`SessionMark`, `DropSince`);
    - its `Decision`, `Usage` and `AgentStep` rows;
    - the context and the step buffer of an in-process call.
  - **One owner per conversation:** every user-turn test has an owner of its own (Story 1.8).

**Never:**
- **Story 30.1:**
  - no compaction, `ForkAndSummarize` or `Summarize`;
  - no 20 seconds added to the timer;
  - no code that reads `Compact` in the runner.
- **Nothing aborts a request inside AI Hub's tool loop** (AD-20, S4), and the step estimate (`BaseChars`, `StepBuffer`) does not change.
- **No MCP proxy** (`call_mcp_tool`, Epic 22) **and no reminder tools** (Story 1.10).
- **Lane B's files:** no change to:
  - `OcuTalon.Core.*` or `OcuTalon.Msg.*`; the catalog's `fallbackReason.tooLarge` already exists and is only read;
  - `Test/{Contract,Core,Data,Demo,Live,Msg,Web}/**` or `docker/**`;
  - the mock's code or its tests;
  - `ci/**` outside `ci/mock/scenarios/A/` and the `lane-a` entry of `ci/units.sh`.
- **The mock's existing scenarios** do not change.
- **No new structures:**
  - no new production item, table, index, global, event type or mapping;
  - no change to `Production.cls`, `BridgeExample` or `release/standalone-bridge.sh`.
- **No key, no commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| The agent part (in process) | `RequestSize.AgentChars` of `OcuTalon.Agent.Triage`, `.Diagnosis` and `.Chat`, and of a class that does not exist | 1. **Triage and Chat:** the length of their `INSTRUCTIONS`.<br>2. **Diagnosis:** its `INSTRUCTIONS` plus the JSON of the Watch toolset's three tools.<br>3. **The missing class:** 0, with an error status. | n/a |
| The estimate (in process) | `EstimateTokens` for a decide (`TriageAgent`), a diagnose (`DiagnosisAgent`), an untrusted turn, a user turn with no link, a user `fresh` turn with a seed and a note, and a decide that carries a seed | 1. **Each:** `Tokens(AgentChars + len(ChatInput))`, with no history.<br>2. **The seed** counts only for the user `fresh` turn. | n/a |
| The history (in process, `ZzRunner`) | Turn 1 of an owner, with 4,000 characters of input. Then turn 2, an untrusted turn and a `fresh` turn of the same owner. | 1. **The stored history:** `HistoryChars` of the link is above 4,000.<br>2. **Turn 2:** `EstimateTokens(turn 2, "ZzRunner", "OcuTalon.Agent.Chat")` equals `Tokens(AgentChars + HistoryChars + len(ChatInput))`. It is within 10% of the runner's own first-step estimate of turn 2.<br>3. **The untrusted and the fresh turn** count no history. | n/a |
| The precheck's order (in process) | `Precheck` with the limit equal to the estimate, and one below it. Every combination of a missing key, a capped day, a budget that is over and a size that is over. | 1. **At the estimate:** "".<br>2. **One below:** `too_large`.<br>3. **The order:** no_key, daily_cap, budget, too_large.<br>4. **`Classify`:** `{"tooLarge":1,"timedOut":1,"failure":"x"}` gives `too_large`. | n/a |
| Too large, first send and re-send (in process, `ZzDecide`) | A decide and a user turn whose estimate is above `RequestTokenLimit`. `OnResponse` with the key `resend` for one of them. | 1. **The first send:** a `too_large` fallback is recorded and answered from `OnRequest`: a `DecisionResponse`, or a `Reply` with no text and no flags. One `decision.recorded`, no send and no timer.<br>2. **The re-send** records `too_large` and sends nothing. | n/a |
| The limit setting (in process) | `RequestTokenLimit` "", "5000", "100000", "0", "-1", "abc" and "100001", through `AssignOneSetting` and `Precheck` | 1. **The limits:** 100000 (no warning), 5000, 100000.<br>2. **The last four:** 100000, each with one warning that names `RequestTokenLimit`.<br>3. **The setting:** `RequestTokenLimit:Bridge`, with the initial value 100000. | n/a |
| The flag (in process, `ZzDecide`) | User turns estimated at 40,000 and at 40,001. A decide, a diagnose and an untrusted turn at 50,000. A user turn of 10 tokens whose caller set `Compact` to 1. The re-send of the 40,001 turn. | The sent request's `Compact`, in that order: 0, 1, 0, 0, 1 and 0. The re-send carries 1. | n/a |
| Too large (live) | Turn 1 of owner A has 8,000 characters of input and is answered. `Decide`'s `RequestTokenLimit` row is then set between the estimate of A's turn 2 without its history (the same input for a new owner B) and with it, and `Decide` is restarted. | 1. **Owner A's turn 2:**<br>- a `too_large` fallback `Reply` (`FallbackProblems` reports nothing) and a `Decision` row with `too_large`;<br>- no header to `ChatAgent`, nothing at the mock and no `Usage` row;<br>- the link and the saved session's data unchanged.<br>2. **Owner B's turn:** answered. | OK; restored |
| A flagged turn (live) | A user turn with about 170,000 characters of input (an estimate between 40,000 and 100,000), and a short user turn | 1. **The flag:** the request to `ChatAgent` has `Compact` 1; the short turn's has 0.<br>2. **Sent as it is:** the long turn is answered with the chat script's text, and the mock logged one request that carries the whole input.<br>3. **Recorded:** its `Usage` row's `LargestRequestTokens` is above 40,000 and under 100,000. | OK |
| `Result` (pure) | A context begun. Texts and objects of several sizes, returned in a row. A renderer `OnMessage`. No context. A room smaller than the note. | 1. **Whole values** come back unchanged (an object stays an object).<br>2. **The result that crosses the room** is cut to fit, with the note (`shown` and `total` right), and the total equals the room.<br>3. **A later result** is the note alone.<br>4. **After `OnMessage`:** a full room again.<br>5. **With no context:** a fresh room, and nothing is kept. `Begin` starts the total at 0. | n/a |
| One step's results (in process, `ZzRunner`, `result-cap`) | `ZzResultAgent`. Step 1 calls `zz_result_text` (30,000 characters) and `zz_result_object` (30,000) in one response. Step 2 calls `zz_result_text` (1,000). | 1. **Request 2** carries the text whole and the object's JSON cut, ending with the note. Their lengths add up to at most 40,000.<br>2. **Request 3** carries the 1,000 characters whole.<br>3. **The reply** is the scenario's text. | OK |
| The watch tools (live; and in process) | Diagnosis's request to its runner. A fresh `%AI.ToolMgr` that runs each watch tool. | 1. **The model:** Diagnosis's second request carries the tool's result as the JSON object `{"items":[]}`, not as a JSON string.<br>2. **`ExecuteTool`** gives that object. | OK |
| The tools of each agent (live) | Triage, Diagnosis and Chat requests to their runners | The first logged request offers exactly these tools:<br>- **Triage:** none;<br>- **Diagnosis:** `read_event_log`, `read_failed_messages` and `read_item_settings`;<br>- **Chat:** the tools of its `TOOLSETS` (none).<br>Any other tool fails the test. | OK |
| The scans | The product classes of `src/` | 1. **Tool providers:** every one in `OcuTalon.Tools` extends `Result` and returns only through `Return`. A sample that returns a literal, and one that does not extend `Result`, are flagged first.<br>2. **The link:** `Decide` calls `Lock`, `Unlock` and `SessionOf` of the link class, and nothing else.<br>3. **The callback rule:** `Result` and `Context` pass it. | n/a |

</intent-contract>

## Code Map

- **AI Hub (read only, `irislib/`):**
  - **`%AI/Agent.cls`:**
    - `%LoadInstructions` (:364-401) reads `INSTRUCTIONS` from `%Dictionary.CompiledXData`: lines are joined by LF and the last LF is dropped;
    - `%LoadToolSets` (:404-421) uses the `TOOLSETS` parameter;
    - `CreateSession` (:649) takes `ToolManager.%Discover()`, a native catalog.
  - **`%AI/ToolSet.cls`:** `%Discover()` (:119) is generated ObjectScript that returns `{"tools":[...],"mcp":[...]}`; `%OnNew` (:17) only sets `Connections`.
  - **`%AI/Tool.cls`:**
    - `DISCOVERYLIMIT` (top of the class): only methods that originate in the concrete class are tools;
    - `%Encode` (:414-441): a dynamic object passes as it is, and a string is passed on and encoded again (S4; Story 1.5's decision 20).
  - **`%AI/Agent/Session.cls`:** `ContextData` is a `%Stream.GlobalCharacter` (:63) that `%OnAddToSaveSet` fills with the exported history (:80-98). `GetContext` (:284) needs the session attached.
  - **`%AI/ToolMgr.cls`:** `%Discover` (:460) is a `$ZF` call, so it is not usable in `Decide`'s job.
- **The bridge (Lane A, `src/bridge/cls/OcuTalon/Bridge/`):**
  - **`Process/Decide.cls`:**
    - the class doc (:3-76), `SETTINGS` (:80) and `RUNNERS` (:83);
    - `DecisionTokenBudget` (:150-153) and `AssignOneSetting` (:176-184);
    - `OnRequest` (:191-223): `Held` at :208, the `DecisionRef` at :212, `Precheck` at :214-217, and the clone and send at :218-222;
    - `Resend` (:309-325): `Precheck` at :313, the clone at :319-321;
    - `TokenBudget()` (:329-334), `Admit` (:430) and `RunnerFor` (:447);
    - `Precheck` (:532-552), `EstimateTokens` (:556-559), `Classify` (:580-607, rule 1 at :583-585) and `RecordFallback` (:754-785).
  - **`Msg/Request.cls`:** the properties, with `SystemNote` as storage slot 13.
  - **`Context.cls`:** `FIELDS` (:10), `Begin` (:45), `Current` (:74) and `Put` (:86).
  - **`Adapter/StepRenderer.cls`:** `OnMessage` (:24).
  - **`Adapter/StepBuffer.cls`:** `CHARSPERTOKEN` (:19) and `Tokens` (:146).
  - **`Adapter/Agent.cls`:**
    - `IsLinked` (:302) and `ChatInput` (:437);
    - `BaseChars` (:451-469), the live sibling of `AgentChars`;
    - `Converse` (:361), which passes the renderer to `Chat` at :372.
  - **`Data/ConversationLink.cls`:** the doc (:1-16) and `SessionOf` (:35).
  - **`Ext/Accessor.cls`:** `ValueFor` (:17).
  - **`Msg/Enum.cls`:** `FALLBACKREASON` (:15), which holds `too_large`.
- **OcuTalon (Lane A):**
  - **`Tools/WatchFixture.cls`:** three methods that return the pre-encoded `"{""items"":[]}"`.
  - **`Tools/Watch.cls`:** the toolset, which names the methods by `Class=`.
  - **`Tools/Names.cls`:** the watch tool names.
  - **The agents' `TOOLSETS`:** `Agent/Triage.cls` "", `Agent/Diagnosis.cls` "OcuTalon.Tools.Watch", and none in `Agent/Chat.cls`.
  - **Story 1.5's live sizes (Task 0 (e)), the system prompt plus the tool catalog:** Triage 1,245 + 2, Diagnosis 758 + 1,358, Chat 901 + 2.
- **Lane B (read only):**
  - `Msg/Catalog.cls:44`: `REASONKEYS` maps `too_large` to `tooLarge`;
  - `Msg/Catalog/Core.cls:216`: `fallbackReason.tooLarge`;
  - `Test/Core/CommandsContext.cls:124`: it snapshots `Context` `FIELDS` and compares the snapshots with each other.
- **The mock (Lane B's code; Lane A adds files under `ci/mock/scenarios/A/` only):**
  - `summarizeTools` (`mock.mjs:127`) logs tool names;
  - a reply's `toolUse` may be an array (:305-306);
  - `input_tokens` is `ceil(raw body / 4)` (:325);
  - `messages` are logged whole;
  - the pattern of a scenario with tools is `steps-two-tools.json`.
- **CI:** `ci/units.sh:17` (`lane-a` is "Agent Bridge Install").
- **Tests (Lane A, `src/ocutalon/cls/OcuTalon/Test/`):**
  - **`Agent/RunnerFixture.cls`:**
    - `Restart` (:98), `DecisionOf` (:262), `Headers` (:270) and `NewRequest` (:223);
    - `Run` (:325), `HeaderTo` (:351), `SessionOf` (:375), `HeaderMark` (:384) and `SessionSince` (:394);
    - `PointKeys` and `RestoreKeys` (:403, :410);
    - `PutDefault`, `RememberDefault` and `RestoreDefaults` (:605, :638, :650);
    - `FallbackProblems` (:746), `SessionMark` and `DropSince` (:786, :793), `SessionExport` (:809) and `WaitForAnswer` (:824);
    - `FindRequests` (:841), `Messages` (:853) and `UsageIds` (:932).
  - **`Agent/Runners.cls`:** `TestRequestsUnderTheModelRules` (:244-272), `TestToolInventory` (:277-315) and `AssertRequests` (:443-462).
  - **`Agent/Instructions.cls`:** `TestToolsets` (:83-110), with `result.value` at :103.
  - **`Agent/Conversation.cls`:** `Prepare` (:428) and the `OnBefore`/`OnAfter` methods (:80-135), the pattern of a live class.
  - **`Bridge/Decide.cls`:**
    - `TestPrecheckOrder` (:1423), `TestEstimateTokens` (:1464) and `TestOnRequestPrecheck` (:1499);
    - `TestResendPrecheck` (:1643) and `TestResendWiring` (:1703);
    - `NewRecorder` (:2216), `NewProcess` (:2266), `NewRequest` (:2284), `Put` (:2510), `PutKey` (:2519) and `PrecheckWarnings` (:2532).
  - **`Bridge/ZzDecide.cls`:** the send record, `$ListBuild(name, DecisionRef, response required, key, ItemId)`.
  - **`Bridge/Conversation.cls`:** `TestFirstStepCountsHistory` (:387), `NewHost` (:655), `NewTurn` (:663), `Send` (:683), `FirstEstimate` (:693), `HistoryChars` (:699, through `GetContext`), `LinkOf` (:732) and `Guard` (:805).
  - **`Bridge/Runner.cls`:** `NewRunner(agentClass, effort, providerConfig, configName, runnerClass)` (:968).
  - **`Bridge/CodeRules.cls`:** `CALLBACKHELPERS` (:34), the link parameters (:63-77), `TestCallbackRule` (:80), `TestOnlyTheRunnerWritesLinks` (:177), `Offenders` (:447) and `IsCallbackClass` (:469).
  - **The pattern of a fixture agent, toolset and tool:** `Bridge/StepsAgent.cls`, `StepsTools.cls` and `StepsNote.cls`.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **Targets.**
  - **The throwaway:** tag `e1s9a` with the CI mock, for everything that needs the mock.
  - **The slot:** `ocutalon-slot-a` (namespace `OCUTALON`, after `iris_server_info` shows build 154), only for facts that need no mock.
- **(a) The agent part.**
  - **What to measure:** for `OcuTalon.Agent.Triage`, `.Diagnosis`, `.Chat` and `OcuTalon.BridgeExample.Agent`, the two parts of `AgentChars` against the live agent's `SystemPrompt` length and the length of `ToolManager.%Discover().%ToJSON()`.
  - **The generated code:** `OcuTalon.Tools.Watch`'s generated `%Discover` makes no `$ZF` call and no `%AI.Utils` call (`iris_routine_intermediate`).
  - **The setting:** `Ens.Director.GetHostSettingValue("<production>||<runner>", "AgentClass")` gives the agent class of the three runners and of the example's runner.
  - **Stop:** if the setting cannot be read, stop with status `blocked` and the condition `intent gap: AD-20 (estimate of the system prompt and tools), measured <fact>`.
- **(b) The stored history.**
  - **The turns:** two linked turns through `ZzRunner`, the first with 4,000 characters of input.
  - **What to measure:** the length of the saved session's stored `ContextData`, read without opening the session (for example the generated `ContextDataGetStored` and the stream's `Size`). Compare it with the length of `GetContext().%ToJSON()` and the length of the `messages` JSON of turn 2's logged request, and say whether it holds the system prompt.
  - **Stop:** if the stored history cannot be read without attaching the session, stop with status `blocked` and the condition `intent gap: AD-20 (history estimate), measured <fact>`.
- **(c) The agreement.** Compare `Decide`'s estimate with the mock's `input_tokens` of the first request for a decide, a diagnose and the linked turn of (b), and with the runner's first-step estimate of that turn. Record the ratios. If the gap to the runner's own estimate is above 10%, the `Bridge.Conversation` band becomes the measured gap plus 5 points, and it is recorded.
- **(d) Tool results as the model sees them.**
  - **The returns:** through `ZzRunner`, with fixture tools that return (i) a pre-encoded JSON string, (ii) a dynamic object, and (iii) plain text. Record the `tool_result` content of each as the mock logs it. Expected: (i) a JSON string literal of the escaped text, (ii) the object's JSON, and (iii) the text.
  - **The base class:** a class that extends `Result` discovers only its own methods.
  - **`ExecuteTool`:** what a fresh `%AI.ToolMgr` gives as `result.value` for a tool that returns an object.
  - **Stop:** if a dynamic object does not reach the model as its JSON, stop with status `blocked` and the condition `intent gap: Consistency Conventions "Tool results", measured <fact>`.
  - **If (i) and (ii) are logged the same,** record it: the pin of AC5 is then the scan alone.
- **(e) Two tools in one response** (`result-cap`): the order of the `OnMessage` calls and the tool calls. Expected: `OnMessage` 1, tool a, tool b, `OnMessage` 2. **Stop:** if a tool of response n runs after `OnMessage` n+1, stop with status `blocked` and the condition `intent gap: AD-10 (reset at each OnMessage), measured <order>`.
- **(f) The time.** The time of `EstimateTokens` in `Decide`'s job, 10 runs of each kind. If the median is above 20 ms, `AgentChars` is cached per process, keyed by the agent class and its compile time, and the choice is recorded.
- **Other facts.** If any fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/RequestSize.cls`** (new): `AgentChars` and `HistoryChars`, as in Boundaries, and the class doc. Rationale: AD-2, AD-6, AD-20.
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`.** Rationale: AD-6, AD-8, AD-19, AD-20.
  - **The setting:** `RequestTokenLimit` (`SETTINGS`, `AssignOneSetting`), `MAXREQUESTTOKENS` and `COMPACTTOKENS`;
  - **One setting reader** for `DecisionTokenBudget` and `RequestTokenLimit`, generalised from `TokenBudget()`;
  - **The estimate and the precheck:** `EstimateTokens(request, runner, agentClass, .sc)`; `Precheck` with `tooLarge`, the limit, `estimate` and the warnings; `Classify`'s rule 1;
  - **What is sent:** one method that builds the clone (`DecisionRef`, `Compact`), used by `OnRequest` and `Resend`;
  - **The class doc:** the precheck, the estimate and the flag.
- **`src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`:** `Compact` (storage slot 14) and its doc: `Decide` sets it, the runner ignores it until Story 30.1, and a caller's value is ignored. Rationale: AD-6, AD-20.
- **`src/bridge/cls/OcuTalon/Bridge/Context.cls`:** `ToolResultChars` (the property and `FIELDS`), 0 at `Begin`, and the doc. Rationale: AD-10.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/StepRenderer.cls`:** `OnMessage` resets `ToolResultChars`, inside its `Try`, and the doc. Rationale: AD-9, AD-10.
- **`src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls`:** the doc only: `Decide` also calls `SessionOf`, to read. Rationale: AD-6, AD-33.

**OcuTalon.**
- **`src/ocutalon/cls/OcuTalon/Tools/Result.cls`** (new): as in Boundaries. Rationale: AD-10, Conventions "Tool results".
- **`src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls`:** it extends `Result` and returns dynamic objects; the doc. Rationale: AD-7, AD-10.

**CI.**
- **`ci/units.sh`:** `lane-a` becomes "Agent Bridge Install Tools". Rationale: AD-22.
- **`ci/mock/scenarios/A/result-cap.json`** (new), with three replies:
  1. a `toolUse` array: `zz_result_text` with `{"chars":30000}`, and `zz_result_object` with `{"chars":30000}`;
  2. `zz_result_text` with `{"chars":1000}`;
  3. the text `The CI mock read the results.`

  Rationale: AD-22.

**Tests.**
- **`src/ocutalon/cls/OcuTalon/Test/Tools/Result.cls`** (new): the `Result` (pure) row, and `TestStepCap` (the row "One step's results": `Test.Bridge.Runner.NewRunner` with `ZzResultAgent`, guarded by `RunnerFixture.GuardReason`).
- **`Test/Tools/ZzResultAgent.cls`, `ZzResultTools.cls` and `ZzResultTool.cls`** (new fixtures, with no `Test` method), following `StepsAgent`, `StepsTools` and `StepsNote`. `ZzResultTool` extends `Result`, and its two methods give deterministic content of the asked length.
- **`Test/Bridge/Decide.cls`:**
  - **rewritten:** `TestEstimateTokens` (the agent part, the estimate);
  - **extended:** `TestPrecheckOrder` (four facts and the `Classify` order), `TestOnRequestPrecheck` and `TestResendPrecheck` (`too_large`);
  - **new:** `TestRequestLimitSetting` and `TestCompactFlag`;
  - **and the header.**
- **`Test/Bridge/ZzDecide.cls`:** the send record gains the sent request's `Compact` as its seventh member. The six members before it keep their places.
- **`Test/Bridge/Conversation.cls`:** new `TestPrecheckCountsHistory` (the history row), with the class's own helpers.
- **`Test/Bridge/CodeRules.cls`:** `Context` joins `CALLBACKHELPERS`; `TestOnlyTheRunnerWritesLinks` allows `Decide`'s `SessionOf`; new `TestToolsReturnThroughResult`; and the header.
- **`Test/Agent/RequestSize.cls`** (new, live): `TestTooLarge` and `TestCompactFlag`, with `Test.Agent.Conversation`'s `Prepare` pattern (`ReadyReason`, `PointKeys`, then `RestoreKeys`).
- **`Test/Agent/Runners.cls`:** `AssertRequests` names the offered tools exactly (expected from `TOOLSETS` and from today's literal lists); Diagnosis's second request carries `{"items":[]}` as an object; the header.
- **`Test/Agent/Instructions.cls`:** `TestToolsets` expects the object from `ExecuteTool`.
- **Coverage.** These tests prove every matrix row.

**Acceptance Criteria:**
- **AC1, `too_large` (Integration AC: `Decide`'s caller reads the fallback).**
  - **Given** a request whose estimated first model request is above the request-size limit (`Decide`'s `RequestTokenLimit`: 100,000 by default and at most),
  - **when** `Decide` prechecks it, before the first send or a re-send,
  - **then:**
    - it records a `too_large` fallback, which comes after `no_key`, `daily_cap` and `budget`;
    - it answers its caller with it;
    - it sends nothing to a runner or the model.

  (`Test.Agent.RequestSize.TestTooLarge`; `Test.Bridge.Decide` `TestPrecheckOrder`, `TestOnRequestPrecheck` and `TestResendPrecheck`)
- **AC2, what the estimate counts.**
  - **Given** a request of any kind,
  - **when** `Decide` estimates it,
  - **then** the estimate counts, at 4 characters a token:
    - the runner's agent's system prompt and tool schemas;
    - the stored history of a linked turn that continues;
    - the input that `Chat` gets, with the seed only on a linked `fresh` turn.

  (`Test.Bridge.Decide.TestEstimateTokens`; `Test.Bridge.Conversation.TestPrecheckCountsHistory`; `Test.Agent.RequestSize.TestTooLarge`)
- **AC3, the flag (no consumer in this story; the first is Story 30.1).**
  - **Given** a `turn` whose estimate is above 40,000 tokens and within the limit,
  - **when** `Decide` sends it, or sends it again,
  - **then:**
    - the request carries `Compact` 1, and every other request carries 0;
    - the runner sends the turn as it is.

  (`Test.Bridge.Decide.TestCompactFlag`; `Test.Agent.RequestSize.TestCompactFlag`)
- **AC4, the tool-result cap (Integration AC: the model API, through AI Hub, reads the cut results).**
  - **Given** built-in tools that return through `OcuTalon.Tools.Result`,
  - **when** their results come back within one model step,
  - **then:**
    - each result is passed whole while it fits, and cut to fit and marked with the note when it does not;
    - together they pass at most 10,000 tokens (40,000 characters), the notes included. The one exception is a result that arrives when less room than its note remains: it is the note alone;
    - the running total is the bridge context's, and it starts again at every `OnMessage`.

  (`Test.Tools.Result`: the pure tests and `TestStepCap`)
- **AC5, a dynamic object or plain text.**
  - **Given** the built-in tools,
  - **when** they return,
  - **then:**
    - each returns a dynamic object or plain text through `Result`, never a pre-encoded JSON string;
    - so the model reads the watch tools' result as a JSON object.

  (`Test.Agent.Runners.TestRequestsUnderTheModelRules`, Diagnosis's second request; `Test.Agent.Instructions.TestToolsets`; `Test.Bridge.CodeRules.TestToolsReturnThroughResult`)
- **AC6, the tools of each agent.**
  - **Given** a request for each agent,
  - **when** the mock records its first model request,
  - **then:**
    - it offers only that agent's own tools: none for Triage, the three watch tools for Diagnosis, and the tools of Chat's toolsets for Chat (none until Story 1.10);
    - the test fails on any other tool.

  (`Test.Agent.Runners.TestRequestsUnderTheModelRules`)
- **AC7, the limit cannot be turned off or raised.**
  - **Given** `Decide`'s `RequestTokenLimit` setting,
  - **when** it is empty, 0, not a whole number, or above 100,000,
  - **then:**
    - the limit is 100,000;
    - any of these values except an empty one logs one warning that names the setting;
    - a whole number from 1 to 100,000 is the limit.

  (`Test.Bridge.Decide.TestRequestLimitSetting`)

## Spec Change Log

## Review Triage Log

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** `RequestSize`, `Decide`, `Context` and `StepRenderer` name no OcuTalon package. `OcuTalon.Tools.Result` may use the bridge, which is the allowed direction.
- **AD-6:** `Decide` does the size precheck. The runner is the only caller of `Chat`. The callback rule binds `Result`, `Context` and the renderer. The request carries the flag.
- **AD-7:** each agent's static `INSTRUCTIONS` and `TOOLSETS`: Triage none, Diagnosis the watch tools, Chat its own toolsets.
- **AD-8:** `too_large` is a precheck reason, never sent, after `budget`.
- **AD-9:** `OnMessage` is one model step, and the renderer adds no `%AI` call.
- **AD-10:** one shared base cuts and marks every result against the step's 10,000 tokens. The total lives in the bridge context and is reset at each `OnMessage`.
- **AD-19:** the request-size limit is a host setting of a bridge item.
- **AD-20:** the first request is estimated from the system prompt, the tool schemas, the history and the input. Above 40,000 tokens the turn is flagged. The arithmetic gives 94,000 at most. The `Usage` row keeps `LargestRequestTokens`.
- **AD-22:** the scenario goes under `A/`, and the tests are in shard `lane-a`.
- **AD-26:** `Compact` is a named property in the request's trace message, and `FallbackReason` shows in the decision message.
- **AD-31:** a `too_large` fallback fires `decision.recorded`, as every fallback does.
- **AD-33:** Lane A owns `Decide`, `Request`, `Context` and `OcuTalon.Tools`.

No acceptance criterion contradicts an AD's Rule. AD-20 also says that `Decide` adds 20 seconds to the timer of a flagged turn. That belongs to Story 30.1 (the owner's amendment of 2026-10-20), because nothing compacts until then.

**Decided in-stage:**
1. **The size check covers every kind, and the flag every `turn`.**
   - **Every kind:** NFR-3 binds every model request, and `Precheck` serves every kind.
   - **Every turn:** the flag follows the AC ("Given a `turn`") and AD-20 ("`Decide` flags a `turn`") as written, with no narrowing. Story 30.1's own AC leaves a turn with no older history uncompacted, so the flag on an untrusted or `fresh` turn is harmless. Nothing reads the flag in this story, so the choice can be reversed.
2. **The limit can never be off or above 100,000.** It fails safe, unlike `DecisionTokenBudget`, where 0 means off, because NFR-3 is a ceiling and the price tier changes above 100,000 (`Installer.cls:65`).
3. **The estimate's input is `ChatInput`.** It counts what the runner sends, so the seed counts only on a linked `fresh` turn. This settles the Story 1.8 review row that was rejected as "Story 1.9 owns the estimate".
4. **The agent part is read from the class, not from the runner's live agent.**
   - **Why:** `Decide`'s job has no agent. Building one there would call AI Hub's native library outside a runner, and it would need the key.
   - **What it leaves out:** later steps' MCP and knowledge-base tools (AD-21), which only the live catalog holds. The step estimate (`BaseChars`) keeps the live values.
5. **The history is the stored value of the linked session**, read without attaching it (Task 0 (b)), because `GetContext` needs an attached session.
6. **`Compact` is a new `Request` property**, because the flag must reach the runner's job (AD-6: "when `Decide` asks it to compact"). One method builds every sent clone, and `Decide` always sets the flag itself.
7. **The note, and the edge of the cap.** AD-10's "together at most 10,000" and the AC's "each says it was cut" cannot both hold for a result that arrives after the room is used up. That result is the note alone, of 56 characters (14 tokens) at most. This keeps "says it was cut", and AD-20's margin of 6,000 tokens absorbs it. The flag goes to the veto window (Clarification Record).
8. **The running total is kept in characters** in the context, which `StepRenderer.OnMessage` resets. `Context` joins `CALLBACKHELPERS`, because tool and renderer callbacks now call it.
9. **A whole result keeps its type**, so the model reads an object as JSON. A cut result is text, because cut JSON is no longer an object.
10. **`OcuTalon.Test.Tools` is created now:** `Result` lives in `OcuTalon.Tools`, and Story 1.10's tests (the `CommandsIn` test double) belong there.
11. **A `too_large` turn leaves its conversation as it was.** Until Story 30.1 compacts, a conversation whose history alone passes the limit gets `too_large` on every turn that continues it, and a `fresh` turn starts it again. That needs about 400,000 characters of history. Recorded for the lead.
12. **The live tests take their sizes from `EstimateTokens` at run time.** The limit is set between the estimate with the history and the estimate without it, so no constant hides a change in the agent's prompt.
13. **The wording of the note** is code-written text for the model, never user-facing, and it is a class parameter.

**Integration ACs (Rule 1):**
- **AC1:** `Decide`'s caller (the test, through the production's service) reads the `too_large` `Reply`. Lane B's catalog already renders it as `fallbackReason.tooLarge`.
- **AC4 and AC5:** the model API, through AI Hub, reads the cut results and the object results (the mock's log). `DiagnosisAgent`'s watch tools are the product consumer of `Result`.
- **AC3:** no consumers in this story; the first consumer will be Story 30.1.

**Consumed-by:**
- **Story 1.10:**
  - its reminder tools return through `Result`, and the scan holds them;
  - their tests join `Test.Tools`;
  - Chat's `TOOLSETS` gains them, and `Test.Agent.Runners` expects them (from `TOOLSETS`); `Test.Agent.Instructions`' "Chat has no toolset" changes.
- **Story 5.4:** the real watch readers replace `WatchFixture`, still through `Result`.
- **Story 22.x:** `call_mcp_tool` cuts through `Result` (AD-21).
- **Story 30.1:** reads `Request.Compact` in the runner before `Chat`, and adds 20 seconds to a flagged turn's timer.
- **Story 2.4 (Lane B):** `Conversation` gets a `too_large` fallback like any other (decision 11).
- **Stories 9.1 to 9.3:** the evaluation reads `LargestRequestTokens` (NFR-3).

**Consumes:**
- **Story 1.1:** the agents' `TOOLSETS`, `WatchFixture` and `Test.Agent.Instructions`.
- **Story 1.2:** `Test.Agent.Runners`.
- **Story 1.3:** `Decide`.
- **Story 1.4:** `LargestRequestTokens`.
- **Story 1.5:** `StepRenderer.OnMessage`, `StepBuffer.Tokens` and `CHARSPERTOKEN`.
- **Story 1.6:** `Precheck`, `Classify`, `RecordFallback` and `FallbackProblems`.
- **Story 1.7:** the precheck of `Resend`, and `ZzDecide`.
- **Story 1.8:** `IsLinked`, `ChatInput`, `ConversationLink.SessionOf`, the `Test.Bridge.Conversation` helpers, `SessionMark` and `DropSince`.
- **Epic 0:** `too_large` in `Msg.Enum`, `Context`, the catalog's `tooLarge`, and the mock's `toolUse` arrays.

**Extend, don't copy (Rule 2):**
- **Parameters, not copies:**
  - `Precheck` gains `requestLimit` and `estimate`;
  - `EstimateTokens` gains `runner` and `agentClass`;
  - `ZzDecide`'s send record gains a member;
  - `Test.Agent.Runners.AssertRequests` gains the expected tool names.
- **One setting reader** serves `DecisionTokenBudget` and `RequestTokenLimit`. **One clone method** serves `OnRequest` and `Resend`.
- **Reused:** `ChatInput`, `IsLinked`, `SessionOf`, `StepBuffer.Tokens` and `CHARSPERTOKEN`, `Context.Current` and `Put`, and the `Test.Bridge.Conversation` and `RunnerFixture` helpers.
- **The fixtures** follow `StepsAgent`, `StepsTools` and `StepsNote`.
- **Copies, with their reasons:**
  - `RequestSize.AgentChars` beside `Adapter.Agent.BaseChars` (decision 4);
  - its `INSTRUCTIONS` read beside AI Hub's `%LoadInstructions`, which needs an agent instance.

**Ledger:** the inbox for this story is empty, so no entry is addressed or declined.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles and for facts that need no mock. No test class runs there.
- **Throwaways.**
  - Everything else runs through `ci/iris.sh` or the scripts, with `OCUTALON_RUN_TAG=e1s9a OCUTALON_LOCK_OWNER='epic=1 stage=implement' OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801`.
  - QA uses the tag `e1s9q` (`stage=qa`), and review uses `e1s9r` (`stage=code-review`).
  - One stack at a time, one command per call, each with `timeout: 600000`.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, `ocutalon-slot-b` or `ocutalon-slot-c`. No push, no `gh workflow run`, and never read `.env`.

**Commands** (each with the variables above):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, including the storage check (`Request` and `Decide` each append one slot), the class rules and the CI config (the `Tools` area is in `lane-a`). About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Tools.Result`;
  - `.Bridge.Decide`, `.Bridge.Conversation` and `.Bridge.CodeRules`;
  - `.Agent.RequestSize`, `.Agent.Runners` and `.Agent.Instructions`.

  Expected: `CLASS ... passed` for each, about 1 to 2 minutes a call.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s9a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass, the new `result-cap` included.
- **(once)** `bash ci/iris.sh shard lane-a`. Expected: every class passes, `Tools` included, and the only SKIP is the existing `TestStepHelpers`.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passes, `Test.Contract.Ac` and `Test.Core.CommandsContext` included.
- **(once)** `bash release/standalone-bridge.sh`. Expected: every check `PASS`. The example's `Decide` now reads its runner's agent class.
- **(once)** `bash ci/iris.sh live storage-roundtrip`, then `live demo-path`, one per call. Expected: PASS, with `@floor` passed.
- **(once)** `bash ci/iris.sh teardown`. Expected: nothing of `e1s9a` is left.

**Shared surfaces:**
- **`Decide.EstimateTokens` and `Precheck`.**
  - **What changes:** a new signature, the agent part and the history.
  - **The tests that assert them:** `Test.Bridge.Decide`'s `TestEstimateTokens`, the "5 tokens" control of `TestPrecheckOrder`, `TestOnRequestPrecheck` and `TestResendPrecheck`.
  - **What stays:** `Test.Agent.Decide`'s budget test (a budget of 1 is still over) and `Test.Bridge.Fallback` (a fact that is missing counts as false).
  - **Search the test trees** for `EstimateTokens`, `Precheck(` and `DecisionTokenBudget`.
- **`Classify`'s rule 1** gains `tooLarge`.
- **Stored classes.**
  - **`Decide`:** a new setting and storage slot (`Test.Bridge.Example`'s setting checks, the storage check, `storage-roundtrip`).
  - **`Request`:** a new property and storage slot (`Test.Contract.Ac` checks only that the named properties exist).
- **`Context` `FIELDS`** gains `ToolResultChars`. `Test.Core.CommandsContext` (Lane B) compares its snapshots with each other, and `Test.Bridge.ProbeTool` iterates the fields.
- **`WatchFixture`'s results:**
  - `Test.Agent.Instructions.TestToolsets`;
  - Diagnosis's second request in `Test.Agent.Runners`;
  - any test that reads the summary of a watch tool's step. Search the test trees for `items`.
- **The scans:** `TestOnlyTheRunnerWritesLinks` (`Decide`'s `SessionOf`) and `CALLBACKHELPERS`.
- **The shard `lane-a`** gains the `Tools` area: `ci/units.sh`, `ci/iris.sh classes lane-a` and `test-ci-config.sh`'s units rule.
- **`ZzDecide`'s send record:** the tests that read `CallOf("send", n)` by position keep the first six members.
- **Production state while a test runs:**
  - `Decide`'s `RequestTokenLimit` row, and the restart of `Decide`;
  - the saved AI sessions and links, including one with about 170 KB of history;
  - the mock's new `result-cap`.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19),** one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `Classify` ignores `tooLarge` | `Agent.RequestSize.TestTooLarge`, `Bridge.Decide.TestPrecheckOrder` |
| AC1 | `too_large` comes before `budget` | `Bridge.Decide.TestPrecheckOrder` |
| AC1 | `Resend` skips the size check | `Bridge.Decide.TestResendPrecheck` |
| AC2 | `EstimateTokens` leaves out the history | `Agent.RequestSize.TestTooLarge`, `Bridge.Conversation.TestPrecheckCountsHistory` |
| AC2 | `AgentChars` leaves out the toolsets | `Bridge.Decide.TestEstimateTokens` (Diagnosis) |
| AC2 | the seed counts on a turn that continues | `Bridge.Decide.TestEstimateTokens` |
| AC3 | the threshold is "at least 40,000" | `Bridge.Decide.TestCompactFlag` |
| AC3 | a decide is flagged too | `Bridge.Decide.TestCompactFlag` |
| AC3 | the re-send clone carries no flag | `Bridge.Decide.TestCompactFlag` |
| AC3 | a flagged turn is not sent | `Agent.RequestSize.TestCompactFlag` |
| AC4 | `Return` never cuts | `Tools.Result` (pure), `Tools.Result.TestStepCap` |
| AC4 | the renderer does not reset the total | `Tools.Result.TestStepCap` (step 2's result is cut) |
| AC4 | a cut result has no note | `Tools.Result` (pure) |
| AC5 | `WatchFixture` returns the JSON string | `Agent.Runners` (Diagnosis's second request), `Bridge.CodeRules.TestToolsReturnThroughResult` |
| AC6 | Chat's runner also registers the Watch toolset (`UseToolSet` in `OnAfterAgentInit`) | `Agent.Runners.TestRequestsUnderTheModelRules` |
| AC7 | a value above 100,000 is used as written | `Bridge.Decide.TestRequestLimitSetting` |

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **Stored-data additions** (category 3). The AC and AD-20 call for both, and both only append a slot:
  - `Request.Compact`: a message property, storage slot 14;
  - `Decide.RequestTokenLimit`: a process property and host setting.
- **The edge of the cap** (decision 7). A result that arrives after a step's room is used up is the note alone. So the step can pass 10,000 tokens by 14 tokens for each such result, and the model is still told that it was cut.

**For the lead (rulings recommended, not blocking):**
- **Spine lines (Rule 20):**
  - AD-6's request fields gain `Compact`: `Decide` sets it on a `turn` estimated above 40,000 tokens, and Story 30.1's runner reads it;
  - AD-19's "request-size limit" is `Decide`'s `RequestTokenLimit` (default and ceiling 100,000, never off);
  - AD-10 gains the note and its edge;
  - AD-22's as-built line: `lane-a` gains `Tools`.
- **Decision 1:** every `turn` above 40,000 tokens is flagged, untrusted and `fresh` ones included. Story 30.1 leaves those uncompacted (they have no older history), and should add its 20 seconds only to a turn that it can compact.
- **Decision 11:** until Story 30.1, a conversation whose history alone passes the limit answers `too_large` on every turn that continues it. Lane B's `Conversation` sends `fresh` only after `Tainted` or `SessionBroken`.

**Lead's rulings at the spec gate (2026-10-23, Epic 1 runner, unattended):**
- **One story, not a split:** the three parts serve NFR-3 and share `Decide`, the context and the runner tests.
- **No spine change:** the four lines listed above are details inside existing Rules (AD-20 flags a turn for compaction; AD-19 names the request-size limit a bridge host setting; AD-10 cuts and marks results; `ci/units.sh` holds the shard entries).
- **Veto window, kept as planned:** `Request.Compact` and `Decide.RequestTokenLimit` (inbox U-42); the note-only result at the cap's edge (U-43).
- **Decided:** the `Compact` flag on every turn kind above 40,000 stands.
- **Until Story 30.1:** a conversation whose history alone passes the limit answers `too_large` on every turn; ledgered as DW-125, routed to Story 30.1 (with its "only flagged turns it can compact" note).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-23, halted after planning as the dispatch asked).**
- **Sources.** The cached `epic-1-context.md`, Story 1.8's spec (done) for continuity, Story 1.9's block in `epics.md`, NFR-3, and the spine's AD-6 to AD-10, AD-19, AD-20 and AD-22 with the Conventions.
- **The standard.** The spec meets the READY FOR DEVELOPMENT standard.
- **No runtime.** Nothing was measured or run against a runtime in this stage. Task 0 holds the measurements, with their stop conditions.
- **Warnings.** `multiple-goals`: the size check, the tool-result cap and the per-agent tools can ship apart, and they are kept together because NFR-3 binds all three. `oversized`.
- **The ledger inbox** is empty.
- **The Clarification Record** lists two items for the veto window and three for the lead. None blocks implementation.
- **Footprint.** Every file the plan edits is in Epic 1's footprint: `src/bridge/**`, `src/ocutalon/cls/OcuTalon/Tools/**`, `Test/{Agent,Bridge,Tools}/**`, `ci/mock/scenarios/A/**`, and Lane A's `lane-a` entry of `ci/units.sh`. No contended path is touched.
