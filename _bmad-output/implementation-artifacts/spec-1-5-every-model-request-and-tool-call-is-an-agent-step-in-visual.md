---
title: 'Story 1.5: Every model request and tool call is an agent step in Visual Trace'
type: 'feature'
created: '2026-10-22'
status: 'done'
baseline_revision: 'b5d8096b3bf5dfe15d355dca2ac0a19b5423a9ea'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-5, AD-6, AD-9, AD-20, AD-22, AD-26, AD-30, AD-31 and AD-33, and the Redaction, Logging, Messages and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred:
  - summary: >-
      Shipped tool classes declare no STEPLABEL, and nothing fails a tool class that has none, so every real tool step reads
      "Running a tool" in Visual Trace.
    evidence: |-
      AD-9: each tool declares its readable step label. Tools.WatchFixture (the methods of the Tools.Watch toolset) carries none; the spec's
      decision 10 leaves them out because Diagnosis cannot run through Decide yet and Story 5.4 replaces the class.
      Test.Bridge.CodeRules.TestCallbackRule is the place for a scan once the first real tool class exists (Stories 1.10, 5.4).
    location: >-
      src/ocutalon/cls/OcuTalon/Tools/
    severity: low
---

<intent-contract>

## Intent

**Problem:** No agent step reaches Visual Trace today. The runner passes no renderer to `Chat` and adds no audit policy, so nothing records a model request or a tool call. `AgentSteps` is a stub that answers "not implemented", and `Decide` sends it nothing. There is no `OcuTalon.Bridge.Redact`. A judge cannot follow what the agent did, and nothing keeps a key or an identity out of a step. Story 1.4 also left one gap (DW-77): the `Usage` row's largest request is the last request's measured size only, so a call that threw records none.

**Approach:**
- **Recording.** The runner's adapter passes a new step renderer to `Chat` and adds a new audit policy in `OnAfterAgentInit`. Both write into a step buffer in the runner's job.
- **Returning.** After `Chat`, the adapter turns the buffer into redacted step records and returns them with the reply in a new `Reply.Steps` field.
- **Sending.** `Decide` sends each record as an `AgentStep` message to `AgentSteps`, in order, in the caller's trace session. `AgentSteps` becomes a real operation.
- **The largest request (DW-77).** The step estimates also feed the `Usage` row's `LargestRequestTokens`.

## Boundaries & Constraints

**Always:**
- **The step buffer (AD-9).** `OcuTalon.Bridge.Adapter.StepBuffer` lives in the process-private global `^||OcuTalonBP.Steps`, in the pattern of `OcuTalon.Bridge.Context`. Its methods:
  - `Start(baseChars)` empties the buffer and sets the clock mark. `Answer` calls it right before `Chat`. `baseChars` is the length of the agent's `SystemPrompt`, plus the JSON of `..Agent.ToolManager.%Discover()`, plus the request's `Input`. It is read in the adapter, outside every callback, and a `%Discover()` that fails counts 0.
  - `Model(textLength)` appends one model step:
    - its duration is the clock time since the mark, in whole milliseconds;
    - its estimate in characters is `baseChars` plus the text lengths of the earlier model steps plus the argument and result lengths of the earlier tool steps.

    Then it moves the mark.
  - `Tool(name, toolClass, arguments, result, durationMs, status, detail)` appends one tool step with the raw strings and moves the mark. `status` is `ok`, `error` or `denied`, and `detail` is the error or denial text.
  - `Estimates()` gives the model steps' estimated tokens, in order. `Records()` gives the step records (below). `End()` empties the buffer.
  - With no `Start`, every append does nothing.
  - **Tokens.** A count in tokens is the count in characters ÷ 4, rounded up (`CHARSPERTOKEN` 4, the same rate as AD-20's compaction estimate).
- **The renderer (AD-6, AD-9).** `OcuTalon.Bridge.Adapter.StepRenderer` extends `%AI.Shell.StreamRenderer`:
  - `OnBegin` returns "" and moves the mark;
  - `OnMessage(content)` calls `StepBuffer.Model` with the length of `content.value` (0 when it is not readable);
  - `OnEnd`, `OnFeedback` and `OnChunk` do nothing.

  It catches every exception. It makes no `%AI` call beyond its base class and runs no Python (`Test.Bridge.CodeRules.TestCallbackRule` covers it by superclass).
- **The audit policy (AD-6, AD-9).** `OcuTalon.Bridge.Policy.StepAudit` extends `%AI.Policy.Audit`:
  - `%LogExecution` calls `StepBuffer.Tool` with these values:
    - `call.name` and `metadata.origin_class`;
    - `call.arguments` (a JSON string, or an object turned into JSON);
    - `result.result_json`, "" when `result` is null;
    - `duration`;
    - status `ok` or `error`, with the error's own text, without its code, as `detail`.
  - `%LogDenial` records status `denied` with the denial's text.
  - Both return OK always, catch every exception and follow the same callback rule.
  - The adapter adds it in `OnAfterAgentInit` through `agent.ToolManager.SetAuditPolicy`. AI Hub chains code-added policies after any named in settings (S4). `AuditPolicy` stays a refused setting.
- **The step records (AD-9, FR-3).** `Records()` is called after `Chat`, outside every callback. It gives an array of `{"kind", "label", "summary", "durationMs", "status", "estimatedTokens"}` in buffer order, where `kind` is `model` or `tool`.
  - **A model step:**
    - label: `Model request <n>`;
    - summary: `About <t> tokens sent (an estimate). Reply: <c> characters of text, <k> tool calls.`, where `<k>` counts the tool steps that follow it before the next model step;
    - status: `ok`;
    - `estimatedTokens`: the request estimate in tokens.
  - **A tool step:**
    - **label:** the class parameter `STEPLABEL<NAME>` of `toolClass` (`<NAME>` is the tool's name, upper-cased, with `_` and `-` removed), else its `STEPLABEL`, else `Running a tool`. It never holds an argument or model text.
    - **summary:** `<name>. Inputs: <arguments>. Result: <result>.` (or `Error: <detail>.` / `Denied: <detail>.`), then `About <t> tokens added to the next request (an estimate).`
    - **`estimatedTokens`:** (arguments + result or detail) in tokens.
  - **Redact, then cut.** Every label and every part of a summary passes `OcuTalon.Bridge.Redact.Text` first and is cut after, so a cut can never split a secret out of its pattern. A cut part ends in `...`. The name is cut to at most 64 characters, the inputs to 300, the result or detail to 400 and the label to 200, and a summary is never over 1,000 characters (`AgentStep`'s `MAXLEN`).
- **The redactor (AD-31, Conventions: Redaction).** `OcuTalon.Bridge.Redact.Text(text) As %String` returns the text with every sensitive value replaced by `[redacted]`.
  - **JSON.** When the text is a JSON object or array, it replaces every value, at any depth, of a key whose name is in `SENSITIVEKEYS`, compared in lower case with `_` and `-` removed. It then serializes the result.
  - **`SENSITIVEKEYS`:** password, passwd, pwd, passphrase, secret, clientsecret, token, accesstoken, refreshtoken, idtoken, bottoken, apikey, xapikey, authorization, cookie, privatekey, chatid, firstname, lastname, username and displayname.
  - **Patterns.** Then, anywhere in the text:
    - `sk-ant-` keys, and other `sk-` keys of 20 or more characters;
    - Telegram bot tokens (`<6-12 digits>:<30+ of [A-Za-z0-9_-]>`);
    - `Bearer <token>`;
    - JWT-shaped tokens;
    - `ghp_`/`github_pat_` tokens and `AKIA` keys;
    - `<sensitive key>` followed by `=` or `:` and a value, in text that is not JSON.
  - **Guarantees.** It is idempotent and never throws: when it fails, it returns `[redacted: the text could not be checked]` (it fails closed). It never logs or stores its input.
  - **Logs.** Every warning that the new step code writes passes it too.
- **The reply (AD-9, AD-5).** `OcuTalon.Bridge.Msg.Reply` gains `Property Steps As %String(MAXLEN = "")`, the JSON array of the records. The compiler appends it to the Storage block as slot 9.
  - **The runner** fills it after every `Chat` that returns. A `Chat` that throws still ends with an error status and no reply (Design Notes, decision 6). The buffer ends with the context on every path.
  - **`Decide`** empties it on its own answer for a turn.
- **Sending (AD-9, AD-26, AD-30).** `Decide.OnResponse`, for completion key `reply` and before `Conclude`, sends each record as an `OcuTalon.Bridge.Msg.AgentStep` to the `STEPSITEM` (`AgentSteps`) with `SendRequestAsync(..., 0)`.
  - **The message.** It carries `DecisionRef` (the runner request's), `Position` (1 to n, in array order), `StepKind`, `Label`, `Summary`, `DurationMs`, `Status` and `EstimatedTokens`.
  - **The session.** The sends inherit `Decide`'s session and `SuperSession`, so the steps sit in the caller's trace session, after the runner's reply and before `Decide`'s answer.
  - **Building.** A pure class method, `StepMessages(decisionRef, reply)`, builds the messages, and the instance method `EmitSteps` sends them.
  - **Problems.** Steps JSON that does not parse, or a send that fails, is a warning naming the `DecisionRef`, never the content. It never changes the answer.
  - **No steps** are sent for an answer from a recorded row, for a timer that fired, or for a late reply.
- **`AgentSteps` (AD-33).** `OcuTalon.Bridge.Operation.Steps` loses `Parameter STUB`. It answers an `AgentStep` with OK and no response: the message in Visual Trace is the record. Any other class gets "not implemented".
- **The largest request (DW-77, AD-20, NFR-3).** `Usage.FromStats` gains the trailing optional parameter `estimates` (the `%List` from `StepBuffer.Estimates()`). `LargestRequestTokens` becomes the largest of two values:
  - the last request's measured input (`Response.Usage`);
  - the estimates of the other model requests (all of them when nothing was measured, as after a `Chat` that threw).

  It is "" when there is neither. `Price.CostFor` keeps reading it, and `RecordUsage` passes the estimates.
- **The bridge boundary (AD-2).** Nothing new in `src/bridge/` names another OcuTalon package. The test agent and its tools live under `OcuTalon.Test.Bridge`.
- **Text.** All text in `src/`, `ci/` and `release/` is ASCII, and no file holds a key-like string that `docker/tests/test-boundaries.sh` flags.
- **Tests.** They go under `OcuTalon.Test.Bridge` and `OcuTalon.Test.Agent` (the lane-a shard).
  - **Cleanup.** Each test removes the `Usage` and `Decision` rows it made.
  - **The swap.** `Test.Agent.Steps` points `ChatAgent` at the test agent through the production's stored configuration for its own run only, and restores it in `OnAfterAllTests` on every path.

**Never:**
- **Story 1.6's route.** No fallback, no classification, no precheck.
- **Other stories.**
  - No `ToolsRun` and no re-send (Story 1.7, DW-56).
  - No conversation link or history in the base estimate (Story 1.8).
  - No size check, no `too_large` and no tool-result cap (Story 1.9).
  - No gate, no `turn.step` event and no MCP (Story 3.2, step 4).
- **Tokens and cost.** No token or cost value on a step: the totals stay per turn and per decision (AD-9, FR-2).
- **No new structures.** No new production item, table or event type, and no change to `Production.cls` or `BridgeExample.Production`. No property change to `Request`, `Result`, `DecisionResponse`, `AgentStep`, `Usage`, `Price` or `Decision`: `Reply.Steps` is the only new property.
- **Settings.** No System Default Settings row is seeded.
- **Errors.** No `$$$LOGERROR`.
- **No contended edit.** Nothing in `docker/**`, `ci/**` outside `ci/mock/scenarios/A/`, `.github/workflows/ci.yml`, `src/ocutalon/cls/OcuTalon/Test/{Contract,Core,Data}/**` or any Lane B class.
- **No literal key** and no `@{env:...:-fallback}`.
- **No commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Two tool calls through Decide (live) | User `turn` to `Decide` with the marker `steps-two-tools`, while `ChatAgent` runs `Test.Bridge.StepsAgent` (`zz_steps_note` `{"topic":"status"}`, then `zz_steps_card` `{"owner":"ops"}`, then text; the first reply waits 1 s) | 1. **The messages:** five `AgentStep` messages for the `DecisionRef`, Positions 1 to 5, kinds model, tool, model, tool, model.<br>2. **The tool steps:** labels `Reading the test note` and `Reading the test card`. Their summaries hold `zz_steps_note`, `status`, `ops` and the tools' result values. Status `ok`, `EstimatedTokens` above 0.<br>3. **The model steps:** `EstimatedTokens` above 0 and strictly increasing, and step 1's `DurationMs` is at least 1000.<br>4. **The trace:** every header is from `Decide` to `AgentSteps`, body class `OcuTalon.Bridge.Msg.AgentStep`. All are in the Decision row's `TraceSessionId`, the session of the answer's header, after `ChatAgent`'s reply and before `Decide`'s answer, ids in Position order, each `Completed`.<br>5. **The totals:** `AgentStepCount` 5 on the row and the answer, and the answer's `Steps` is "". | No error expected |
| Two tool calls in process | The same marker through the shadow runner `ZzRunner` (`Test.Bridge.Runner`) | 1. **The reply:** `Reply.Steps` holds the five records as above, and `AgentStepCount` is 5.<br>2. **The note step:** its `durationMs` is at least 200, because the tool hangs 0.25 s (Task 0 (b)).<br>3. **The policy:** the built agent's `ToolManager.AuditPolicy` is a `StepAudit`. | No error expected |
| A decide (live) | Untrusted `decide` with Triage's default script | One `AgentStep` (model, Position 1) in the decision's session. `TestDecision`'s targets are `AgentSteps,ApprovalStartIn,Ens.Alarm,TriageAgent`. | No error expected |
| Secrets (live and in process) | User `turn` with the marker `steps-secrets`. The arguments and the tool results each hold a model key, an access token, a password, a Telegram chat id and a display name. The card call fails, naming the password and the key. | 1. **Nowhere in the trace:** none of the ten values is in any `AgentStep` of the ref, in the runner's `Reply` (`Steps` and XML), in an `Ens_Util.Log` row since the mark, or in what `KeyScan.Find` names.<br>2. **The failed call:** the card step has status `error`, and its summary holds `is locked` and `[redacted]`.<br>3. **The markers:** each of the five keys shows `[redacted]` in a summary. | The card call's error |
| Renderer (pure) | `Start(400)`. `OnMessage({"value": <20 chars>})`, then `%LogExecution` with arguments of 40 and a result of 60, then `OnMessage` | 1. **`OnBegin`:** returns "".<br>2. **Model step 1:** estimate 100.<br>3. **Model step 2:** estimate `ceil(520/4)` = 130.<br>4. **Durations:** from the clock (a 250 ms `Hang` reads at least 200).<br>5. **No `Start`:** nothing is recorded. | No error expected |
| Audit (pure) | `%LogExecution` for a class with `STEPLABELZZX`, one with only `STEPLABEL`, and one with neither. Arguments as a string and as an object, an error status, and `%LogDenial`. A `result` and a `call` that are not objects. | 1. **The labels:** in that precedence; the third is `Running a tool`.<br>2. **The values:** the arguments' JSON either way, `error` with its text, `denied`.<br>3. **Not objects:** returns OK, raises nothing, and still records the step, with "" for what it could not read. | Nothing raised |
| Redact, then cut (pure) | A result of 2,000 characters with a `sk-ant-` key that crosses the cut at 400 | No part of the key is in the summary, and the summary is at most 1,000 characters. | No error expected |
| Redact (pure) | The five kinds as JSON keys (snake, camel and upper case, nested in an object and an array), as free text (`password=x`, `Bearer x`, a bot token, `sk-ant-...`, a JWT), plain text, and a text the redaction cannot finish (free text near the string limit, full of `pwd=x`, whose redacted form would pass the limit) | 1. **Sensitive values:** all are `[redacted]`.<br>2. **Other text:** plain text and non-sensitive keys are unchanged, and `Text(Text(x))` = `Text(x)`.<br>3. **Failure:** the text it cannot finish gives `[redacted: the text could not be checked]`. | Fails closed |
| Largest request (pure, DW-77) | 1. Last request measured at 3,000, estimates [5,000, 2,000, 2,500].<br>2. Measured 3,000, estimates [1,000, 2,000, 4,000].<br>3. Nothing measured, estimates [1,000, 4,000].<br>4. Neither. | 1. 5,000: an earlier request beats the measurement.<br>2. 3,000: the last estimate is dropped when a measurement exists.<br>3. 4,000.<br>4. "". | No error expected |
| Steps on the answer (pure) | `Decide.StepMessages` with two records; with `Steps` "" or `{`; and `Conclude` of a turn whose reply has `Steps` | 1. **Two records:** two `AgentStep`s with Positions 1 and 2 and the `DecisionRef`.<br>2. **No records:** none, and a warning for `{`.<br>3. **The turn:** the answer's `Steps` is "". | A warning names the ref |
| Late and repeated | `TestTimer`'s late reply; `TestRepeat`'s second request | No `AgentStep` for the late reply's ref, and none for the repeated request. | As in Story 1.3 |
| Failed turn with spend | `tool-loop` on `ChatAgent` (Story 1.4) | No `Decision` row and no `AgentStep`. The `Usage` row's `LargestRequestTokens` is above 0: the largest estimate, because nothing was measured. | The runner's error status |
| The bridge alone | `release/standalone-bridge.sh` | One `AgentStep` for the example decision's Ref: `StepKind` model, `EstimatedTokens` above 0, in the row's `TraceSessionId`. No error row of `AgentSteps`. | The script fails, naming the check |

</intent-contract>

## Code Map

- **AI Hub (read only, `irislib/`):**
  - **`%AI/Agent.cls`:**
    - `Chat(session, input, feedback)` (:728-766): `feedback` must extend `%AI.Shell.StreamRenderer`. `OnMessage` fires once per model response, and `OnChunk` never fires for `Chat`.
    - `SystemPrompt` (:56).
  - **`%AI/Shell/StreamRenderer.cls`:**
    - `OnBegin` returns the feedback interval (:78-83).
    - `OnMessage(content)` holds the turn's text in `content.value`; a long one throws `<MAXSTRING>`, which the doc at :105-118 shows how to handle.
  - **`%AI/Policy/Audit.cls`:** `%LogExecution(call, metadata, result, duration, status)` (:40) and `%LogDenial(call, metadata, status)` (:53).
  - **`%AI/ToolMgr.cls`:** `SetAuditPolicy` (:219) goes through the native add, which chains the policy. `%Discover()` (:460) lists the tools.
  - **`EnsLib/AI/Agent/OutboundAdapter.cls`:** `AfterAgentInit` ends with the private hook `OnAfterAgentInit(ByRef agent)`, around :229-238.
  - **S4 (build 154, `ARCHITECTURE-NOTES.md` S4; inference until Task 0 (a)):**
    - `OnMessage(n)` fired before the tools that response n asked for;
    - a tool-calling response's text was empty;
    - `call.arguments` arrived as a JSON string;
    - `metadata` held the Requirements, `origin_class` and `requires_auth`;
    - `result` held `tool_name`, `result_json` (a tool's string result is JSON-encoded once more) and `display_text`;
    - `duration` was 0 for a fast tool.
- **Ens (read only):**
  - `Ens/BusinessProcess.cls` `SendRequestAsync(target, request, responseRequired = 1, ...)` (:160).
  - An errored async response goes to `OnError`, which gets no body (:331-339). So a runner error carries no reply (decision 6).
  - **The stored configuration.** `Ens/Director.cls` `UpdateProduction` (:159) applies the stored `Ens.Config.Production` (`findProductionDifferences` opens it at :743), not the class.
  - **Precedence.** An item setting in the XData beats a System Default Settings row, so `ChatAgent`'s `AgentClass` can only change in the stored configuration (decision 3).
- **The bridge (Lane A):**
  - **`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:**
    - `REFUSED` (:28) and `BuildAgent` (:83-99). There is no `OnAfterAgentInit` today.
    - `Answer` (:193-243): the `Chat` call is at :214, between `ReadStats` (:209, :219), and the context `End` is at :240.
    - `RecordUsage` (:263-278) and `CarryUsage` (:283-295).
  - `src/bridge/cls/OcuTalon/Bridge/Context.cls`: the process-private pattern (`^||OcuTalonBP.Context`, `Begin`/`End`) that `StepBuffer` follows.
  - **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:**
    - the class doc (:3-26) says "These are the only two messages Decide sends";
    - `OnResponse` (:90-104) calls `Conclude` at :103;
    - `Conclude`'s turn clone is at :307-313;
    - Storage is at :404-432 (no change).
  - `src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`: the properties (:5-27), `NewBusy` (:31-36) and Storage slots 1 to 8 (:38-69).
  - `src/bridge/cls/OcuTalon/Bridge/Msg/AgentStep.cls`: eight properties, pinned and unchanged.
  - `src/bridge/cls/OcuTalon/Bridge/Operation/Steps.cls`: the stub, with `STUB` at :8.
  - `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`: `Delta` (:66) and `FromStats` (:83-119), with the largest request at :100.
  - The `BridgeExample` production already holds `AgentSteps`.
- **The mock (Lane B's code; Lane A adds files to `ci/mock/scenarios/A/` only):**
  - **Format.** `ci/mock/scenarios.mjs:11-28`. A reply has exactly one of `text`, `toolUse` or `body` (:110-111), and `toolUse` may be a list (:82-95).
  - **Which reply.** Reply k is `replies[min(k, last)]`, where k counts the assistant messages after the newest user text (`mock.mjs:18-22`). So three replies serve a sequence of two tool calls.
  - **Rules.** A marker scenario needs no `MOCKKEY` and no `OcuTalon.Tools.Names` tool name (`constants.test.mjs:69-94`). The name equals the file name, in kebab-case.
  - **Usage.** The mock's default usage is `ceil(raw body / 4)` (`mock.mjs:325`).
  - **Key-like strings.** `docker/tests/test-boundaries.sh:39-40` (`key_like`) fails a committed `sk-ant-…` of 8 or more characters, or a bot token (decision 9).
- **Tests and fixtures (Lane A):**
  - **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:**
    - `Restart` (:69), `WaitAllRun` (:78) and `EventMark` (:100);
    - `Send` (:121) and `NewRequest` (:132);
    - `Headers(sessionId, source)` (:178-186), which today returns target, body class and body id, but no header id;
    - `SessionOf` (:189), `HeaderMark` (:198) and `SessionSince` (:206);
    - `PointKeys` and `RestoreKeys` (:215-222), `Warnings` (:326) and `UsageIds` (:343).
  - **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`:**
    - `TestDecision` (:105), with the targets assertion at :140 and the doc at :10-11;
    - `TestRepeat` (:206) and `TestTimer` (:350);
    - `TestUsageTurn` (:440), with `USAGETURNSTEPS` at :61;
    - `TestCostOfFailedTurn` (:478), whose largest request is "" at :495;
    - the private helpers `Run`, `Targets`, `HeaderTo`, `CountTo` and `WaitForStatus` (:571-670).
  - **`src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`:** `NewRunner` (:518), `ProviderConfig` (:532), `Guard` (:558), the template `TestContext` (:179-231) and the cleanup `OnAfterOneTest` (:35).
  - **Fixture precedent.** `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeAgent.cls`, `ProbeTools.cls` and `ProbeTool.cls`: a test agent, a toolset of `<Tool Name Class Method>` and a tool class.
  - **`src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls`:** `Reply` (:158-182), `AgentStep` (:197-209) and `TestNewBusy` (:16-34). Its `Compare` (`Test/Contract.cls:79-147`) is exact: every property must be in the contract.
  - **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`:**
    - `TestOnResponseUsesItsSettings` (:530) runs on an unstarted process, with a reply that has no `Steps`;
    - `TestTurnKeepsReply` (:628).
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Usage.cls`: the largest-request assertions at :119, :128, :149 and :156.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`: `TestCallbackRule` (:55) finds callback classes by `CALLBACKBASES` (:24), and only the `Class` line may name `%AI`. Also `TestOnlyRunnersChat` (:88).
  - `src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls`: `Find(value)` (:125-135) scans the entries, settings, item settings, event log and sessions.
  - `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: the `AgentSteps` row `"stub": 1` (:619), `TestStubsAnswer` (:139-172) and the doc (:11-13).
- **Lane B, read only:**
  - `Test.Contract.Ac` checks that the named `Reply` properties exist, a superset check (:204-226).
  - `docker/tests/test-storage-roundtrip.sh` compares every committed Storage block with the compiled one.
  - `lib-live.sh:644-652` `check_clean_start`.
  - `test-production.sh:155-180` (row 16) sweeps the oracle's stub items.
- **CI (Lane A):** `release/standalone-bridge.sh`: the decide check (:128-144), the cost check (:146-162) and the diagnosis dump (:164-171).

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **Targets.** Use the slot for process-local facts and a throwaway of tag `e1s5a` for the rest.
- **(a) The callback order.** Through `ZzRunner` with `steps-two-tools`, record OnBegin, each OnMessage (its text length) and each `%LogExecution` (`call`, `metadata`, `result`, `duration`, `status`), in order. Expected: OnMessage(n), then the tool of response n.
- **(b) `duration`** of a tool that hangs 0.25 s. Expected: about 250. If it is 0, the tool step uses the clock time since the mark, and the spec's ≥ 200 check moves to that.
- **(c) A missing tool.** Does a call of a tool the agent does not have (`usage-turn` on Chat) reach `%LogExecution`, and with which status and `origin_class`? This sets whether `AgentStepCount` (Story 1.4's stats delta, unchanged) equals the steps for such a turn (decision 5).
- **(d) A tool that throws.** What `status`, `result` and model input does it give?
- **(e) The estimates.** For `StepsAgent` and the three agents: `baseChars`, and each model step's estimate against the mock's measured `prompt_tokens` of the last request. Record the ratio. No test pins a ratio.
- **(f) The configuration swap.** Changing `ChatAgent`'s `AgentClass` and `AgentAllowList` (target Adapter) in the stored `Ens.Config.Production` and then calling `UpdateProduction`:
  - restarts `ChatAgent` with `StepsAgent`;
  - is undone the same way, giving back `OcuTalon.Agent.Chat`;
  - leaves the class XData unchanged, and `Test.Install.Production` stays green afterwards.

  If the swap cannot be applied and undone in a running production, stop with status `blocked` and the condition `intent gap: AC3 (a test agent behind Decide), measured <fact>`.
- **(g)** The XML export of an `AgentStep`.
- **(h)** The step headers' `SessionId`, `SuperSession` and ids, relative to the runner's reply and to `Decide`'s answer.
- **(i)** The JSON escapes of `steps-secrets` reach the tools as the intended values.
- **Other facts.** If a fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/Redact.cls`** (new): `Text(text)` and `SENSITIVEKEYS`, as in Boundaries. Rationale: AD-31, Conventions (Redaction), NFR-11.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls`** (new): `Start`, `Model`, `Tool`, `Estimates`, `Records`, `End`, the label lookup and `CHARSPERTOKEN`. Rationale: AD-9.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/StepRenderer.cls`** (new): as in Boundaries. Rationale: AD-6, AD-9.
- **`src/bridge/cls/OcuTalon/Bridge/Policy/StepAudit.cls`** (new): as in Boundaries. Rationale: AD-6, AD-9.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:**
  - add `OnAfterAgentInit`, which adds `StepAudit`;
  - in `Answer`, call `StepBuffer.Start(<base>)` right before `Chat` and pass a new `StepRenderer` to `Chat`;
  - after `Chat`, pass `StepBuffer.Estimates()` to `RecordUsage` (new trailing parameter), and on a returned call set `reply.Steps` = `Records().%ToJSON()`;
  - call `StepBuffer.End()` on every path, beside the context's `End`;
  - update the class doc.

  Rationale: AD-6, AD-9, AD-20.
- **`src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls`:** add `Largest(last, estimates)` and the `estimates` parameter of `FromStats`, which uses it, and update the doc. No property or index change. Rationale: DW-77, AD-20, NFR-3.
- **`src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`:** add `Steps` (Boundaries). The compiler appends slot 9. Rationale: AD-9, AD-5.
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:** Rationale: AD-9, AD-26, AD-30.
  - add `Parameter STEPSITEM = "AgentSteps"`, `StepMessages` and `EmitSteps`;
  - call `EmitSteps` in `OnResponse` before `Conclude`;
  - set `Steps` "" on the turn clone in `Conclude`;
  - update the class doc: it sends the runner request, the timer and the steps.
- **`src/bridge/cls/OcuTalon/Bridge/Operation/Steps.cls`:** implement it (Boundaries), drop `STUB` and rewrite the doc. Rationale: AD-9, AD-33.

**The mock (Lane A's folder).** Two new marker scenarios. Rationale: AD-22.
- **`ci/mock/scenarios/A/steps-two-tools.json`:** three replies:
  1. `toolUse` `zz_steps_note` with `{"topic": "status"}` and `delayMs` 1000;
  2. `toolUse` `zz_steps_card` with `{"owner": "ops"}`;
  3. the text `The CI mock read the note and the card.`
- **`ci/mock/scenarios/A/steps-secrets.json`:** three replies:
  1. `zz_steps_note` with `{"topic": "keys", "apiKey", "accessToken", "password", "chatId", "displayName"}`;
  2. `zz_steps_card` with `{"owner": "locked", "password", "chatId", "displayName", "apiKey", "accessToken"}`;
  3. the text `The CI mock read the secret note.`

  Each argument value is `StepsNote.Secret(<kind>, "arg")` (below). The fake model key (`sk-ant-` form) and the fake access token (a Telegram bot token) are written with one JSON `\u` escape, so the committed file holds no key-like string (decision 9).

**CI (Lane A).**
- **`release/standalone-bridge.sh`:** add one `check_session` after the cost check for "The bridge alone" step row, and update the header. Rationale: AD-2, FR-5.

**Tests.**
- **Fixtures** (`src/ocutalon/cls/OcuTalon/Test/Bridge/`, new; never part of a production), on the Probe pattern:
  - **`StepsAgent.cls`:** `MODEL` `claude-haiku-5-5`, `TOOLSETS` `StepsTools` and static `INSTRUCTIONS`.
  - **`StepsTools.cls`:** `zz_steps_note` (class `StepsNote`, method `Read`) and `zz_steps_card` (class `StepsCard`, method `Read`), each with `<Requirement Name="ReadOnly" Value="1"/>`.
  - **`StepsNote.cls`:**
    - `STEPLABEL` `Reading the test note`;
    - `Read(topic, apiKey, accessToken, password, chatId, displayName)` hangs 0.25 s and returns a dynamic object;
    - for topic `keys` the object holds the five kinds with their `"result"` values; otherwise it is `{"topic", "note": "All systems normal."}`;
    - **the fake values.** `Secret(kind, where)` gives the ten fake values, built at run time from fragments: the five kinds `apiKey`, `accessToken`, `password`, `chatId` and `displayName`, each `"arg"` or `"result"`. They are ten distinct strings, and the tests and the scenario use only these.
  - **`StepsCard.cls`:**
    - `STEPLABELZZSTEPSCARD` `Reading the test card`;
    - `Read(owner, password, chatId, displayName, apiKey, accessToken)` returns `{"owner", "card": "On call: <owner>"}`;
    - for owner `locked` it throws an error whose text names the password and the key: `The card of locked is locked: ...`.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Redact.cls`** (new, pure): the "Redact (pure)" row.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Steps.cls`** (new, pure): the "Renderer", "Audit" and "Redact, then cut" rows. It also covers the record shapes and wording of Boundaries (a model step counts the tool steps after it).
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Usage.cls`:** add `TestLargest` (the DW-77 row) and a `FromStats` case with estimates.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`:** add `TestSteps` and `TestStepsRedacted` (the in-process rows), and update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`:** add `TestStepMessages`, change `TestTurnKeepsReply` (the answer's `Steps` is ""), and update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls`:** add `"Steps": "%String(MAXLEN=)"` to `Reply`, and `Steps` to `TestNewBusy`'s empty fields.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Steps.cls`** (new, live; THROWAWAY STACKS AND CI ONLY):
  - **Setup.** `OnBeforeAllTests` checks `ReadyReason`, points the keys and swaps `ChatAgent` to `StepsAgent` (`RunnerFixture.UseAgent`). When the readiness check or the swap fails, every test fails with the reason and sends nothing.
  - **`TestTwoTools`:** the "Two tool calls through Decide" row (AC3, AC5). The note step's summary holds `zz_steps_note`, `status` and `All systems normal.`; the card step's holds `zz_steps_card`, `ops` and `On call: ops`.
  - **`TestRedacted`:** the "Secrets" row (AC4), with the ten values from `StepsNote.Secret`. The runner's reply is the body of the `ChatAgent` header in the session.
  - **`TestDecideStep`:** the "A decide" row, through `TriageAgent`, which the swap does not touch.
  - **Teardown.** `OnAfterAllTests` restores the agent and the keys.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`:**
  - `TestDecision`'s targets and one step;
  - `TestTimer` and `TestRepeat`: no step;
  - `TestCostOfFailedTurn`: the largest request above 0;
  - update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:**
  - add `UseAgent(item, agentClass, Output saved)` and `RestoreAgent(item, saved)`, the Task 0 (f) swap;
  - add `StepsOf(decisionRef)`: the `AgentStep` rows, by Position;
  - add `id` to `Headers`' objects;
  - move to it any helper of `Test.Agent.Decide` that `Test.Agent.Steps` needs (Rule 2).
- **`src/ocutalon/cls/OcuTalon/Test/Agent/KeyScan.cls`:**
  - `Find` also scans the agent steps (`FindSteps`, the store named `agent steps`: the `Label` and `Summary` of every `AgentStep`);
  - `TestKeyIsStoredNowhere`'s positive control saves one `AgentStep` with a fresh value, finds that store named, and deletes it.
- **`src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:** the `AgentSteps` row is `"stub": 0`, and the doc names it.
- **Coverage.** Prove every matrix row with these tests and the script.

**Acceptance Criteria:**
- **AC1, a step per model request.**
  - **Given** the runner passes `OcuTalon.Bridge.Adapter.StepRenderer` (whose `OnBegin` returns "") to `Chat`,
  - **when** the agent makes model requests,
  - **then** each `OnMessage` records one model-request step, with its duration from the clock and an estimated request size. The estimate is built only from callback data (the texts and tool calls that the callbacks received before it) and the base the runner measured before `Chat` (decision 2).

  (`Test.Bridge.Steps`, `Test.Bridge.Runner.TestSteps`, `Test.Bridge.CodeRules`)
- **AC2, a step per tool call.**
  - **Given** `OcuTalon.Bridge.Policy.StepAudit`, which the adapter always adds in `OnAfterAgentInit`,
  - **when** a tool runs or is denied,
  - **then** `%LogExecution` (or `%LogDenial`) records a step with:
    - the tool's label from its class parameter, never its arguments or model text;
    - a redacted summary of its inputs and its result or error;
    - its duration and its status.

  (`Test.Bridge.Steps`, `Test.Bridge.Runner.TestSteps`)
- **AC3, the steps in the trace (Integration AC).**
  - **Given** a user's turn whose test agent makes two read-only tool calls, through the running production and the mock,
  - **when** the turn completes,
  - **then:**
    - `Decide` sends five `AgentStep` messages to `AgentSteps`, in order, in the caller's trace session: every model request and both tool calls;
    - each has its label, summary, duration and an estimate labelled as an estimate;
    - the decision and the answer carry `AgentStepCount` 5;
    - no step carries tokens or cost.

  The consumer is `Decide`: it reads the runner's `Reply.Steps` and produces the messages that Visual Trace shows. The bridge alone does the same for its example decision.

  (`Test.Agent.Steps.TestTwoTools`, `TestDecideStep`; `Test.Bridge.Decide.TestStepMessages`; `release/standalone-bridge.sh`)
- **AC4, no secret in a step.**
  - **Given** steps buffered in the runner's job,
  - **when** they are returned with the reply,
  - **then:**
    - every label and summary has passed through `OcuTalon.Bridge.Redact`;
    - a test that puts a model key, an access token, a password and a Telegram chat id and display name into tool arguments, results and a tool's error finds none of them in any agent step, the runner's reply, the event log or `KeyScan.Find`, and finds `[redacted]` in their place.

  (`Test.Agent.Steps.TestRedacted`, `Test.Bridge.Runner.TestStepsRedacted`, `Test.Bridge.Redact`)
- **AC5, readable names in the turn's thread.**
  - **Given** a turn in Visual Trace,
  - **when** a reviewer reads it,
  - **then:**
    - the steps are `OcuTalon.Bridge.Msg.AgentStep` messages from `Decide` to `AgentSteps`, with plain-English labels and summaries;
    - they sit in the session of its decision and reply, after the runner's reply and before `Decide`'s answer.

  The read-only account reads them as it reads the decision message (decision 7).

  (`Test.Agent.Steps.TestTwoTools`)
- **AC6, the largest request (DW-77).**
  - **Given** a `Chat` call with step estimates,
  - **when** the runner writes its `Usage` row,
  - **then** `LargestRequestTokens` is the largest of the measured last request and the estimates of the other requests, or of all the estimates when nothing was measured.

  (`Test.Bridge.Usage.TestLargest`, `Test.Agent.Decide.TestCostOfFailedTurn`)

## Spec Change Log

## Review Triage Log

### 2026-10-22 — Review pass
- verdicts: 42 findings — high 0, medium 9, low 29, false 2, maybe-false 2
- findings:
  - `[low]` `[patch]` Blind: StepBuffer appends raise the counter before the slot is written, so a raise leaves a hole that Estimates() reads outside RecordUsage's Try — Verified in `Tool`/`Model`: `$Increment` came first, `Estimates()` and `Records()` read every slot up to the counter. Reachable only with strings over the 3.6 M-character limit (the next model request would fail then anyway). Fixed: the slot, the running total and the counter are written in that order, so an append is whole or absent; `Test.Bridge.Steps.TestAppendRaises` pins it (mutation recorded).
  - `[low]` `[reject]` Blind: Redact key names and free-text values (compound names such as authToken keep their value in JSON; an unquoted value stops at a space) — `SENSITIVEKEYS` is the list of the intent contract (veto U-22) and the patterns are the backstop to the structural rules; the unquoted-value limit is recorded under Residual risks with its trade-off (over-redacting the rest of an error sentence). reopen_if=a real tool puts a secret under a name outside the list, or a passphrase with spaces in an error text.
  - `[medium]` `[patch]` Blind: nothing pins the AgentSteps operation after STUB left it out of TestStubsAnswer — Verified: no test calls `Operation.Steps.OnMessage`; an unconditional `Quit $$$OK` kept every test green. Fixed: `Test.Bridge.Steps.TestAgentStepsOperation` (AgentStep gets OK and no response, another class gets 5003, no STUB); mutation recorded.
  - `[low]` `[reject]` Blind: KeyScan.Find does not scan Reply.Steps — The spec names the `agent steps` store as the one to add; `Reply.Steps` holds the same redacted JSON and is checked directly in `TestRedacted` and `TestStepsRedacted` (Steps and XML). reopen_if=a later story relies on `Find` alone for the runner's reply.
  - `[low]` `[defer]` Blind: shipped tool classes carry no STEPLABEL and nothing enforces the convention — Pre-existing tools (`Tools.WatchFixture`); the spec's decision 10 leaves them unlabelled and Stories 1.10 and 5.4 declare labels. An enforcement scan belongs with the first real tool story: deferred, severity low.
  - `[low]` `[reject]` Blind: Redact.Text rebuilds and compiles its patterns on every call — Real but small: about a hundred calls and a thousand compiles for a 30-step loop, once per turn, in the runner job after Chat; the fix (a process cache) adds state. reopen_if=a turn's reply is measured slower by the redaction.
  - `[low]` `[reject]` Blind: the steps of a failed turn are discarded — The spec's decision 6, already routed as DW-83 to Story 1.6.
  - `[low]` `[reject]` Blind: "1 tool calls" and "About 1 tokens" read badly — The intent contract fixes the wording (veto U-23); changing it is the lead's call.
  - `[low]` `[patch]` Blind: Test.Agent.Steps.OnAfterAllTests skips the restore when the production is not running — Verified: the agent restore was guarded by `Running()`. Fixed: the stored settings of ChatAgent are put back whenever they were swapped (the update of the running production then fails with a status); the entries of the runners keep the guard.
  - `[medium]` `[patch]` Blind: LogRowsHolding is copied into three test classes — Verified (Test.Bridge.Decide, Test.Bridge.Runner, Test.Agent.Steps), no reason given: Rule 2. Fixed: one `RunnerFixture.LogRowsHolding`; each class keeps a one-line delegate, as `Test.Agent.Decide` does for the moved helpers.
  - `[low]` `[patch]` Edge: Tool and Model raise the counter before writing the slot (same root as the Blind finding) — Same defect and fix as the first Blind row.
  - `[low]` `[reject]` Edge: EmitSteps sends before Conclude, so a refused reply or a concurrent duplicate leaves AgentSteps under a DecisionRef with no row — The intent contract says before `Conclude`; the steps then show what the agent did for a reply that was refused, and orphans are purged like any message. Recorded under Residual risks.
  - `[low]` `[reject]` Edge: an unquoted sensitive value with a space, comma or semicolon leaves its tail (displayName=Ada Lovelace; a second cookie) — The same limit as the Blind redaction row; recorded under Residual risks.
  - `[medium]` `[patch]` Edge: escaped JSON in text is invisible to the key rule — Measured on the slot: the result of a tool that returns text (the product tools return %String) reaches the policy as a JSON string, and `"{\"password\":\"hunter2\",\"chatId\":777001}"` came back unchanged. Fixed: a text that is exactly one JSON string is redacted by its content (`Redact.Literal`, also when encoded twice; a string that needs no change is returned as it is); `Test.Bridge.Redact.TestJsonString` pins it (mutation recorded). Escaped JSON inside other free text is rare and stays a residual risk.
  - `[low]` `[patch]` Edge: Part turns only TAB to CR into spaces, though its doc says control characters — Verified. Fixed: the C0 controls, DEL, NEL and the line and paragraph separators become spaces; pinned in `TestRedactThenCut` (mutation recorded).
  - `[maybe-false]` `[reject]` Edge: a cut inside a surrogate pair may make %ToJSON throw — Not measured; if true it is low (one call's steps lost, with a warning) and the trigger is a non-BMP character exactly at a cut point.
  - `[medium]` `[patch]` Edge: TestTwoTools reads the step headers right after Decide answers, without waiting for AgentSteps to complete them — Verified: the five sends are asynchronous and the test asserted status Completed once. Fixed: a poll with a 60 s ceiling (`WaitStepsDone`) before the headers are read.
  - `[medium]` `[patch]` Edge: the standalone step check counts the header and the AgentSteps errors without waiting — Same defect in `release/standalone-bridge.sh`. Fixed: the check polls (up to 60 s) for the step header with Status 9 before it counts the errors.
  - `[maybe-false]` `[reject]` Edge: StepAudit records call.name and the original arguments when a policy redirects a call — No policy in this product redirects a call, and the intent contract names `call.name`; if true it is low.
  - `[low]` `[reject]` Edge: LargestRequestTokens ignores the request that was in flight when Chat threw — By design: estimates come from the model responses that arrived (`OnMessage`), and a call that threw before any request writes no row at all (the intent contract's matrix).
  - `[low]` `[patch]` Gap: no test fails if Tool stops moving the clock mark — Verified: model step 2 followed the tool step with no pause, so it read about 0 either way. Fixed: `TestRenderer` pauses 0.25 s before the tool step and asserts that the next model step is under 200 ms (mutation recorded). Not added: an upper bound in the live tests (a slow runner could exceed it) and a test of the mark that OnBegin sets (the adapter calls Start right before Chat, so the two marks coincide).
  - `[medium]` `[patch]` Gap: nothing tests the AgentSteps operation — Same finding and fix as the third Blind row.
  - `[low]` `[reject]` Gap: EmitSteps' failed-send branch has no test — Measured while trying to fix it: a Decide instance that is not started does not fail the send, it sent two real AgentStep messages into the running production, so the cheap test is unsafe; a safe one needs a Decide subclass with a missing STEPSITEM or a disabled AgentSteps in the running production. The branch is twelve lines (ISERR to a warning, Catch to a warning). reopen_if=a send to AgentSteps fails in a live run and the answer changes.
  - `[medium]` `[patch]` Gap: TestTwoTools asserts Completed without waiting (flaky) — Same finding and fix as the Edge row on TestTwoTools.
  - `[medium]` `[patch]` Gap: the standalone check has no wait and no header status — Same finding and fix as the Edge row on the standalone check.
  - `[low]` `[reject]` Gap: Runner.TestSteps' `LargestRequestTokens >= first estimate` cannot catch ignored estimates — True, and not AC6's pinning test (`Bridge.Usage.TestLargest` and `Agent.Decide.TestCostOfFailedTurn` pin AC6, both with recorded mutations); the assertion can fail if the field is empty.
  - `[low]` `[patch]` Gap: the `durationMs >= 0` half of the TestRenderer assertion cannot fail — Removed while the line was changed for the clock-mark finding.
  - `[low]` `[reject]` Gap: TestRedacted has no positive control that the note tool returned its secrets — The tool returns them for topic keys by construction, `TestStepsRedacted` shows the arguments arrive, and the unredacted mutation turned `TestRedacted` red.
  - `[low]` `[reject]` Gap: Test.Agent.Steps.OnBeforeAllTests saves whatever ChatAgent has, even a leftover swap — Each class runs in its own fresh throwaway; a leftover swap needs an aborted run in the same stack.
  - `[low]` `[reject]` Gap: AgentStep rows are not deleted after the tests — The intent contract's cleanup names the Usage and Decision rows; the AgentStep rows carry fresh DecisionRefs and nothing counts them across tests.
  - `[low]` `[reject]` Gap: Test.Bridge.CodeRules, %LogDenial and the order of the step headers have no mutation line of their own — Each of AC1, AC2 and AC5 has the mutation lines the spec asked for (one per AC); the order is pinned by the reverse-order mutation of AC3.
  - `[low]` `[reject]` Gap: %LogDenial is never driven through AI Hub — Story 3.2's gate produces the first denials (Consumed-by); the pure test covers the signature and the record.
  - `[false]` `[reject]` Gap: Test.Contract.Ac does not list Reply.Steps — Lane B, read only, and a superset check by design; `Test.Bridge.Contracts` is the exhaustive pin and lists `Steps`.
  - `[low]` `[reject]` Intent: the failed-send branch is untested (gap 1) — Same as the Gap row on EmitSteps.
  - `[medium]` `[patch]` Intent: Completed is read once, without a wait (gap 2, reading B5) — Same as the TestTwoTools and standalone rows.
  - `[low]` `[reject]` Intent: "nowhere in the trace" is scanned over AgentStep only, not Reply (gap 3) — Same as the KeyScan row.
  - `[low]` `[reject]` Intent: the shape-only patterns are tested only in the pure class (gap 4) — The matrix row for the patterns is a pure row; the live and in-process rows use the key rule.
  - `[low]` `[reject]` Intent: AgentStepCount and the step messages are two counters, compared only in the two-tool scenarios (gap 5) — Task 0 (c) measured the missing-tool difference; it is recorded under Residual risks.
  - `[low]` `[reject]` Intent: an ordinary call can now take an earlier request's estimate as its largest request (gap 6) — That is AC6; `TestFromStats` pins the tier effect with a synthetic estimate.
  - `[low]` `[reject]` Intent: the chaining of audit policies is shown only by the in-process test (gap 7, reading B6) — `TestStepsRedacted` chains a second policy and counts both calls; `TestSteps` and the live tests record the steps.
  - `[low]` `[patch]` Intent: the restore path is skipped when the production has stopped (gap 8, reading B8) — Same as the OnAfterAllTests row.
  - `[false]` `[reject]` Intent: readings B1 to B4 and B7 (estimates are not tokens of a step; the key rule inside JSON strings; Position is the array index; the prefix counts toward 20; all calls take the larger value) — Descriptive: the diff takes the readings the intent contract states or the Decided in-stage notes record; no divergence beyond the rows above.

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** `Redact`, the buffer, the renderer, the policy and `AgentSteps` stay in the bridge and name no other package. The standalone path records its step too.
- **AD-5:** `Reply`'s Storage block only grows (slot 9, appended by the compiler).
- **AD-6:** the callback rule, `OnAfterAgentInit`, the refused `AuditPolicy` setting, and that only the adapter calls `Chat`.
- **AD-9:** the whole step design.
- **AD-20:** tokens per turn, never per step, and `LargestRequestTokens` (DW-77).
- **AD-22:** the mock scenarios under `A/`.
- **AD-26:** the caller's session and readable names.
- **AD-30:** `Decide` sends nothing else but the steps.
- **AD-31:** the redactor is the bridge's.
- **AD-33:** no new item, table or event type.

No acceptance criterion contradicts an AD's Rule.

**Decided in-stage:**
1. **Steps travel on `Reply.Steps`** (JSON), because AD-9 says "returned with the reply". The rejected alternatives:
   - **A global keyed by `DecisionRef`:** a late reply would leave entries behind with no purge.
   - **Persistent `AgentStep` bodies saved by the runner:** they would leave orphans with no header.
   - **The answer.** `Decide` empties the field on its answer, so no cross-lane field is added (AD-33). The runner's reply in the trace shows the redacted JSON.
2. **"Built only from callback data"** (AC1, AD-9) is read as S4 built it: in-callback data only, so no session or `%AI` call inside a callback, plus a base the adapter measures before `Chat`.
   - Without the base, the first request's estimate would be 0.
   - The base counts no history until Story 1.8's conversations.
3. **The live AC3 test swaps `ChatAgent`'s agent in the stored configuration.** It is the only way to put a test agent behind `Decide`:
   - `Decide.RUNNERS` is fixed;
   - the XData's `AgentClass` beats System Default Settings;
   - the Diagnosis path has no `ReplyClass`.

   The swap is runtime only, in throwaways, for one class's run, and Task 0 (f) gates it. The rejected alternative is a ChatAgent turn calling tools Chat lacks, which leaves only error steps and no labels.
4. **The label convention:** `STEPLABEL<NAME>` per tool, else `STEPLABEL` per class, else `Running a tool`. It allows one label per tool when a class holds several tools (Story 1.10's reminders, Story 5.4's watch tools) and stays a class parameter, as AD-9 says. The spine is silent on the form (see the lead's items).
5. **`AgentStepCount` stays Story 1.4's stats delta.** It equals the emitted steps when every tool call reaches the policy. Task 0 (c) records whether a call of a missing tool does; if not, the difference goes under Residual risks, and no test changes.
6. **Failed calls.** A `Chat` that throws keeps Story 1.3's error status with no reply. Ens passes no body with an errored response, so its steps are not sent in this story; its estimates still feed `LargestRequestTokens`. Story 1.6, which turns failures into fallback decisions, decides how a failed call's reply reaches `Decide`, and the steps travel on it. No acceptance criterion of this story moves.
7. **AC5's reviewer.** The steps are ordinary messages in the `Ens.MessageBody` extent and in the decision message's session, which Lane B's trace role already reads. This story adds no grant. Story 2.9's links and the browser check of the read-only account are the outer surface.
8. **Tool steps carry an estimate too.** It is what the call adds to the next request, labelled as an estimate, so "each with … an estimated request size" (AC3) holds without a token or cost claim.
9. **Fake secrets in the scenario.** The model key and the bot token are written with one `\u` escape, so `test-boundaries.sh`'s key scan stays meaningful. The tools build their values from fragments at run time.
10. **`WatchFixture` gets no labels.** Diagnosis cannot run through `Decide` yet (no `ReplyClass`), and Story 5.4 replaces the class.
11. **Redaction runs in the runner,** before the reply is a message, so neither the runner's reply nor a step holds a secret. It fails closed.

**Decided in-stage (implementation, unattended):** small ambiguities, each inside the spec's intent and reversible in this story.
12. **`sk-` keys of "20 or more characters"** count the prefix: `sk-` followed by 17 or more of `A-Z a-z 0-9 _ -`, with no letter or digit before the `sk-`. `sk-ant-` keys have no minimum and no boundary.
13. **The key rule (`<sensitive key>` then `=` or `:` and a value)** also checks the string values inside JSON, because a tool's result can hold `password=...` in a string; a key follows `[_-]?` between its letters, so `api_key` and `apiKey` match; a quoted value is replaced whole and keeps its quotes (so a JSON fragment in a text stays well formed); an authentication scheme (`Bearer`, `Basic`, `Digest`, `Negotiate`) before the value belongs to it. The structural JSON rule still takes the whole value of a sensitive key, whatever its type.
14. **A tool step adds its arguments and its result, or its error or denial text when there is no result, to the later estimates**, the same count as its own `estimatedTokens`, so that an error that the model reads counts as it should. For a step with a result the count is the spec's.
15. **The error detail is the full error text without its code.** `GetOneStatusText` drops the cause of a tool failure (Task 0 (d)), so `StepAudit` takes `GetErrorText`, removes the leading `ERROR <code>:` of each error, turns control characters into spaces and the long dash into a hyphen, and keeps 2,000 characters.
16. **Redaction runs on each part** (name, inputs, result or error text, label) and the parts are cut; the composed summary is cut only. A second redaction of the composed text would let the key rule take the full stop after a value.
17. **`UseAgent` leaves `saved` empty when it could not read the item's settings**, and `RestoreAgent` of an empty `saved` is an error that changes nothing, so a failed swap can never remove the item's `AgentClass`. `Send` and `Run` of `RunnerFixture` take an optional super session, as a channel service sets one (AD-26).
18. **Added tests and fixtures:** `Test.Bridge.StepsSeen` (a second audit policy that records what the tools were called with, for Task 0 (i)); `Test.Agent.Steps.TestSwapKeepsDefinition` (the Task 0 (f) gate as a test); `Test.Bridge.Usage.TestLargest` also runs the four DW-77 cases through `FromStats`; `Test.Bridge.Runner.TestUsageRows` now expects a largest request above 0 for the stalled tool loop (AC6) and still expects no row for a failure before any request.
19. **`Decide`'s helpers moved.** `Run`, `Targets`, `HeaderTo` and `CountTo` live in `RunnerFixture`; `Test.Agent.Decide` keeps one-line private methods of the same names that call them, so its test bodies did not change.
20. **A text that is exactly one JSON string** is redacted by its content. AI Hub encodes the string result of a tool as a JSON string, and the product's own tools return `%String`; the key rule cannot see `\"password\"` inside such a string. `Redact.Literal` parses the string, redacts its content as a text of its own (JSON inside it too, also when encoded twice) and encodes it again; a string that needs no change is returned as it is.
21. **A step is added to the buffer whole or not at all.** The slot, the running total and the counter are written in that order, so an append that raises leaves nothing behind for `Estimates()` and `Records()`.

**Integration ACs (Rule 1):**
- **AC3, live.** `Decide` reads the runner's `Reply.Steps` and produces the messages in `AgentSteps`, through the running production and the mock.
- **The bridge alone.** The example's decision step reaches `AgentSteps`.
- **AC4.** The redactor's consumer here is the step records, observed in the trace and the event log.

**Consumed-by:**
- **Story 1.6:** the steps of a failed call (decision 6), and the step records of a fallback reply.
- **Story 1.7:** the tool steps beside `ToolsRun` (DW-56).
- **Story 1.8:** the base estimate gains the conversation's history.
- **Story 1.9:** the chars÷4 estimator, the renderer's `OnMessage` as the reset of the tool-result total, and `LargestRequestTokens`.
- **Story 1.10:** reminder tools declare `STEPLABEL…`.
- **Story 2.9:** trace links open a turn at its steps.
- **Story 3.2:** the gate's denials become `%LogDenial` steps.
- **Story 3.7:** the audit writer uses `Redact`.
- **Story 5.4:** watch-tool labels.
- **Story 9.4:** recorded files pass `Redact`.
- **Story 12.6:** Telegram identities are absent from steps.
- **Story 13.1:** the example's steps in order.

**Consumes:**
- **Story 1.2:** `Answer` and the refusals.
- **Story 1.3:** `OnResponse`, `Conclude`, `RunnerFixture` and the Probe pattern.
- **Story 1.4:** `FromStats`, `RecordUsage` and `AgentStepCount`.
- **Story 1.1:** `KeyScan.Find`.
- **Epic 0:** `AgentStep`, the `AgentSteps` stub and `Reply`.
- **Lane B, read only:** the mock's `toolUse` lists and `Test.Contract.Compare`.

**Extend, don't copy (Rule 2):**
- **The buffer.** `StepBuffer` follows `Context`'s process-private pattern in its own global. Its lifecycle (a base before `Chat`, read after it) and its API differ, and `Context`'s Epic 0 fields, which the gate and the tools read, stay as they are.
- **The fixture.** `RunnerFixture` gains the swap and the step reader, and `Test.Agent.Decide`'s helpers move there rather than being copied.
- **The usage row.** `FromStats` gains a trailing parameter.
- **The key scan.** `KeyScan.Find` gains a store.
- **The tests.** The in-process tests extend `Test.Bridge.Runner`.

**Ledger:** DW-77 is addressed by AC6 (the `Usage.cls` task, the "Largest request" row).

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles and process-local facts only. No test class runs there.
- **Throwaways.**
  - Everything else goes through `ci/iris.sh` or the script, with `OCUTALON_RUN_TAG=e1s5a OCUTALON_LOCK_OWNER='epic=1 stage=implement'`. QA uses `e1s5q` and review `e1s5r`.
  - One stack at a time, one command per call, each with `timeout: 600000`.
  - Run `ci/iris.sh teardown` with the same tag at the end.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or `ocutalon-slot-b`. No push and no `gh workflow run`. Never read `.env`.

**Commands** (each prefixed with the tag and lock owner where it starts a stack):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, including the storage check (`Reply` slot 9 appended), class rules (bridge refs) and boundaries (ASCII, no key-like string). About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Bridge.Redact`, `.Bridge.Steps`, `.Bridge.Usage`, `.Bridge.Runner`, `.Bridge.Decide`, `.Bridge.Contracts` and `.Bridge.CodeRules`;
  - `.Agent.Steps`, `.Agent.Decide`, `.Agent.KeyScan`, `.Agent.Runners` and `.Install.Production`.

  Expected: `CLASS ... passed`.
- **(loop)** `bash release/standalone-bridge.sh`. Expected: every check `PASS`, the step check included, and exit 0.
- **(loop)** `bash ci/iris.sh shard lane-a`. Expected: every class passed, and the only SKIP is the existing `TestStepHelpers` one.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s5a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass with the two new scenarios.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passed (`Test.Contract.Ac` with `Reply`'s named properties and `AgentStep` pinned).
- **(once)** `bash ci/iris.sh live storage-roundtrip`. Expected: PASS (`Reply`'s committed block equals the compiled one).
- **(once)** `bash ci/iris.sh live production`, then `live production-restart`, one per call. Expected: PASS. `AgentSteps` runs, has left the stub sweep, and the start is clean.
- **(once)** `bash ci/iris.sh live install-upgrade`. Expected: PASS (the appended `Reply` slot over an earlier install).
- **(once)** `bash ci/iris.sh live compose-start`, then `live demo-path`, one per call. Expected: PASS (`@floor`, no key).
- **(once)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s5a`'s projects.

**Shared surfaces:**
- **`Decide`'s sends.** Every model call now adds `AgentStep` headers: `Test.Agent.Decide.TestDecision`'s targets list changes. Search the test trees for other target or header counts of `Decide`'s session.
- **`Reply`:** its contract (`Test.Bridge.Contracts`), its Storage block (storage-roundtrip), and the turn answer's fields (`Test.Bridge.Decide.TestTurnKeepsReply`).
- **The `AgentSteps` oracle row:** `Test.Install.Production`, `test-production.sh` row 16 and `check_items_run`.
- **`LargestRequestTokens` after a throw:** `Test.Agent.Decide.TestCostOfFailedTurn`. `Test.Bridge.Runner.TestUsageRows` keeps "" for a throw before any request.
- **`KeyScan.Find`'s store list** and its positive control.
- **`RunnerFixture.Headers`'** objects gain `id`.
- **The mock's scenario set:** two new files.
- **`ChatAgent`'s stored configuration** during `Test.Agent.Steps` only, restored after.
- **`release/standalone-bridge.sh`**.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19)**, one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `OnMessage` records nothing | `Bridge.Steps`, `Bridge.Runner.TestSteps`, `Agent.Steps.TestTwoTools` |
| AC1 | The estimate is the base only (no accumulation) | `Bridge.Steps` (130), `Agent.Steps.TestTwoTools` (increasing) |
| AC1 | The model step's duration is a fixed 0 | `Bridge.Runner.TestSteps` (at least 1000) |
| AC2 | The label is taken from `call.name` | `Bridge.Steps`, `Agent.Steps.TestTwoTools` |
| AC2 | `OnAfterAgentInit` adds no policy | `Bridge.Runner.TestSteps` (no tool step, no `StepAudit`) |
| AC2 | The status is always `ok` | `Agent.Steps.TestRedacted` (the card step) |
| AC3 | `EmitSteps` is not called | `Agent.Steps.TestTwoTools`, `TestDecideStep` |
| AC3 | The steps are sent in reverse order | `Agent.Steps.TestTwoTools` (the ids against Position) |
| AC3 | The turn clone keeps `Steps` | `Bridge.Decide.TestTurnKeepsReply` |
| AC4 | `Redact.Text` returns its input | `Bridge.Redact`, `Bridge.Runner.TestStepsRedacted`, `Agent.Steps.TestRedacted` |
| AC4 | The text is cut before it is redacted | `Bridge.Steps` (redact, then cut) |
| AC5 | Each step is sent from a fresh session (`..%SessionId` cleared) | `Agent.Steps.TestTwoTools` |
| AC6 | `FromStats` ignores the estimates | `Bridge.Usage.TestLargest` (case 1), `Agent.Decide.TestCostOfFailedTurn` |
| AC6 | The last estimate is kept beside the measurement | `Bridge.Usage.TestLargest` (case 2: 4,000, not 3,000) |

**Mutations demonstrated (Rule 19).** Each change was applied alone to a clean tree, the named classes ran in a throwaway, and the tree was put back and compared (`git status --short`, `git diff --stat` and the file's checksum identical to before).
- mutation: `StepRenderer.OnMessage` records nothing -> `Bridge.Steps` (`TestRenderer`), `Bridge.Runner` (`TestSteps`, `TestStepsRedacted`, `TestUsageRows`), `Agent.Steps` (`TestTwoTools`, `TestRedacted`, `TestDecideStep`) went red
- mutation: the estimate is the base only (`Model` without the accumulated texts) -> `Bridge.Steps` (`TestRenderer` 130, `TestRecords`), `Bridge.Runner.TestSteps`, `Agent.Steps.TestTwoTools` (increasing) went red
- mutation: the model step's duration is a fixed 0 -> `Bridge.Runner.TestSteps` (at least 1000), `Agent.Steps.TestTwoTools`, `Bridge.Steps.TestRenderer` went red
- mutation: the label is taken from `call.name` (`Records` uses the name, not `LabelFor`) -> `Bridge.Steps` (`TestRecords`, `TestAudit`), `Agent.Steps.TestTwoTools` went red
- mutation: `OnAfterAgentInit` adds no policy -> `Bridge.Runner.TestSteps` (no `StepAudit`, no tool step), `TestStepsRedacted` went red
- mutation: the status is always `ok` -> `Agent.Steps.TestRedacted` (the card step), `Bridge.Runner.TestStepsRedacted` went red
- mutation: `EmitSteps` is not called -> `Agent.Steps` (`TestTwoTools`, `TestRedacted`, `TestDecideStep`), `Agent.Decide` (`TestDecision`, `TestRepeat`) and the step check of `release/standalone-bridge.sh` ("wanted CHK|steps|1, got 0") went red
- mutation: the steps are sent in reverse order (`For i = messages.Count():-1:1`) -> `Agent.Steps.TestTwoTools` (the ids against Position) went red
- mutation: the turn clone keeps `Steps` -> `Bridge.Decide.TestTurnKeepsReply` (and `TestStepMessages`) went red
- mutation: `Redact.Text` returns its input -> `Bridge.Redact` (all three families), `Bridge.Runner.TestStepsRedacted`, `Agent.Steps.TestRedacted`, `Bridge.Steps.TestRedactThenCut` went red
- mutation: the text is cut before it is redacted (`Part`) -> `Bridge.Steps.TestRedactThenCut` ("sk-a" left in the summary) went red
- mutation: each step is sent from a fresh session (`..%SessionId` cleared before the send) -> `Agent.Steps` (`TestTwoTools`, `TestDecideStep`) went red
- mutation: `FromStats` ignores the estimates (`Largest(last)`) -> `Bridge.Usage` (`TestLargest` cases 1 and 3 through the row, `TestFromStats`), `Agent.Decide.TestCostOfFailedTurn` went red
- mutation: the last estimate is kept beside the measurement (no `- 1` in `Largest`) -> `Bridge.Usage.TestLargest` (case 2: 4,000, not 3,000) went red
- mutation: `StepBuffer.Tool` does not move the clock mark -> `Bridge.Steps.TestRenderer` (the model step after the tool step reads 252 ms) went red
- mutation: `Redact.Redacted` does not treat a text that is one JSON string by its content -> `Bridge.Redact.TestJsonString` went red
- mutation: `StepBuffer.Tool` raises the counter before it writes the slot -> `Bridge.Steps.TestAppendRaises` (`<UNDEFINED>` in `Estimates`) went red
- mutation: `Operation.Steps.OnMessage` answers OK to every message -> `Bridge.Steps.TestAgentStepsOperation` (5003 for another class) went red
- mutation: `StepBuffer.Part` turns only TAB to CR into spaces -> `Bridge.Steps.TestRedactThenCut` went red

The five mutations of the review pass were applied together in two batches (four in `StepBuffer`, `Operation.Steps` and `Part`, then one in `Redact`), each named test went red, and the tree was put back and compared as above.

**Measured in implementation (Task 0).** The slot (build 154) ran the process-local facts; a throwaway of tag `e1s5a` ran the rest, through a temporary measurement class and a temporary renderer and audit policy (all deleted). Times are from the start of the call.
- **(a) The callback order.** `steps-two-tools` through a shadow runner: `OnBegin` (1 ms), `OnMessage` 1 (1,016 ms, `value` ""), `%LogExecution` of `zz_steps_note` (1,281 ms), `OnMessage` 2 (1,284 ms, ""), `%LogExecution` of `zz_steps_card` (1,285 ms), `OnMessage` 3 (1,285 ms, the 39 characters of the final text). So `OnMessage(n)` comes before the tool calls of response n, and a tool-calling response has an empty text. `call` is `{"id","name","arguments"}` with `arguments` a JSON string (keys sorted); `metadata` is `{"ReadOnly":"1","origin_class":"<the tool class>","requires_auth":false}`; `result` is `{"tool_name","result_json","display_text":null}`, where `result_json` is a JSON string with sorted keys (`{"note":"All systems normal.","topic":"status"}`) and a tool's string result is encoded once more (`"\"{\\\"items\\\":[]}\""`). The status is OK on success.
- **(b) `duration`** of the tool that hangs 0.25 s: 252 to 256. A fast tool reports 0. So the tool step uses `duration`, and no clock fallback is needed.
- **(c) A missing tool.** `usage-turn` on `ChatAgent` (the call of `list_productions`, which Chat's catalog, `[]` in this story, does not hold): neither `%LogExecution` nor `%LogDenial` is called. The events are `OnBegin`, `OnMessage` (empty), `OnMessage` (46 characters). `total_tool_calls` still counts the call, so `AgentStepCount` is 3 and the steps are 2 (Residual risks). No test changes.
- **(d) A tool that throws** (`zz_steps_card`, owner `locked`): `%LogExecution` gets `result` `{}` (an object with no members, not null), `duration` 0, and a status of one error, `<%AICore>ToolExecutionFailed`. `GetOneStatusText` gives only "Tool execution failed: IRIS error"; the cause is embedded, and only `GetErrorText` shows it: `ERROR <%AICore>ToolExecutionFailed: Tool execution failed: IRIS error [%Status]: 5001 (code: 5001) <long dash> p$C(1)The card of locked is locked: password=... apiKey=...$C(1) x 8 at Read+2^OcuTalon.Test.Bridge.StepsCard.1`. The model's next request holds a `tool_result` block of `{"error": "<that text>"}`, and the turn goes on to the final reply. `StepAudit` therefore takes the full error text, drops the leading `ERROR <code>:`, turns the control characters into spaces and the long dash into a hyphen.
- **(e) The estimates** (`baseChars` = system prompt + tool catalog JSON + input; tokens; the measured value is `Response.Usage.prompt_tokens` of the last request, from the mock's `ceil(body / 4)`): `StepsAgent` two tools 1,457 (172 + 1,203 + 82), estimates 365, 381, 394, measured 418, ratio 0.94; `StepsAgent` secrets 1,449, estimates 363, 480, 546, measured 639, ratio 0.85; Triage 1,332 (1,245 + 2 + 85), estimate 333, measured 373, ratio 0.89; Diagnosis 2,172 (758 + 1,358 + 56), estimates 543, 548, measured 461, ratio 1.19; Chat 968 (901 + 2 + 65), estimates 242, 242, measured 347, ratio 0.70. The ratio of the last estimate to the last measured request lies between 0.70 and 1.19. No test pins a ratio.
- **(f) The configuration swap works and is undone.** Changing `AgentClass` and adding `AgentAllowList` (target Adapter) on `ChatAgent` in the stored `Ens.Config.Production` and calling `UpdateProduction(60)` took about 1 s, restarted `ChatAgent` (a new job) and ran `StepsAgent` behind `Decide` (five steps). `RestoreAgent` removed the allow-list setting, gave back `OcuTalon.Agent.Chat` and restarted the job again. The text of the class XData (4,722 characters) was identical after `%Save`, after `UpdateProduction`, after `UseAgent` and after `RestoreAgent`. (A first comparison by hash reported a difference; that was a reading artifact: `%OpenId` gave back the open object whose XData stream was at its end. The comparison of the whole text, with a rewind, is the one that counts and the one `Test.Agent.Steps.TestSwapKeepsDefinition` makes.) `Test.Install.Production` passes after the swap in the `lane-a` shard, forward and reversed.
- **(g) The XML of an `AgentStep`:** `<AgentStep><DecisionRef>...</DecisionRef><Position>1</Position><StepKind>model</StepKind><Label>Model request 1</Label><Summary>...</Summary><DurationMs>1001</DurationMs><Status>ok</Status><EstimatedTokens>365</EstimatedTokens></AgentStep>`. The runner's `Reply` XML holds `<Steps>` with the JSON array as text.
- **(h) The headers** of one turn through `Decide`, in id order, all with one `SessionId`: `ApprovalStartIn` to `Decide` (3), `Decide` to `ChatAgent` (4), `Decide` to `Ens.Alarm` (5), `ChatAgent` to `Decide` with the `Reply` (6), five `Decide` to `AgentSteps` with the `AgentStep` bodies (7 to 11, in Position order, each Completed), and `Decide` to `ApprovalStartIn` with the answer (12). The steps come after the runner's reply and before the answer. When the sending service has a `SuperSession`, every header, the steps included, carries it. The `Decision` row's `TraceSessionId` is that session.
- **(i) The JSON escapes of `steps-secrets`** reach the tools as the intended values: a test-only second audit policy (`Test.Bridge.StepsSeen`, chained after `StepAudit`) saw the `call.arguments` of both calls, and `Test.Bridge.Runner.TestStepsRedacted` compares all five against `StepsNote.Secret(kind, "arg")`; the card's error text names the intended password and key.

**Residual risks:**
- A summary's inputs are JSON. They are readable to a reviewer, but not prose.
- Free-text identities (a display name in prose) are beyond the redactor: the structural rules come first (Conventions). The key rule takes a value up to the next space, so `displayName=Ada Lovelace` in free text leaves `Lovelace`; in JSON the whole value goes.
- A call of a missing tool does not reach the policy (Task 0 (c), measured): `AgentStepCount` (the stats delta, which counts the call) is then one more than the steps that `Decide` sends, and the model step that asked for it says "0 tool calls". `Test.Agent.Decide.TestUsageTurn` keeps the stats count of 3 and pins no step count.
- `Decide` sends the steps before `Conclude`, as the spec says, so a reply that `Conclude` then refuses (the reply check) has sent its steps for a decision that is never recorded. The steps of a turn whose `Chat` threw are not sent at all (decision 6; Story 1.6, DW-83).
- The failed-send branch of `EmitSteps` has no test: a Decide instance that is not started does not fail the send (it sent real messages in a trial), so a safe test needs a Decide subclass with a missing `STEPSITEM` or a disabled `AgentSteps`.
- Escaped JSON inside free text (not a text that is one JSON string) is not seen by the key rule, and nor is a name outside `SENSITIVEKEYS`.

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **`Reply.Steps`:** a new stored property of a message class (slot 9, appended): a schema append (decision 1).
- **What the steps store:** the redacted, cut summaries of tool inputs, results and errors in `AgentStep` messages, which are kept by Ens's purge like any message.
- **The redactor's rules** (security posture): `SENSITIVEKEYS`, the patterns, `[redacted]`, and fail closed.
- **Public-facing text that is not in the UX:** the step labels and summaries (`Model request <n>`, `About <t> tokens sent (an estimate)…`, `Running a tool`, the inputs and results form) and the test tools' labels.
- **`LargestRequestTokens`'s meaning** (DW-77): now the largest of measured and estimated sizes, and set after a throw.

**For the lead (ruling recommended, not blocking):**
- **Decision 3.** The live test swaps `ChatAgent`'s agent class in the throwaway's stored configuration. This is new to the repository.
- **Decision 4.** The label convention independent builders would follow. The recommendation is a Consistency Conventions row by Rule 20's light path.
- **Decision 6.** A failed call's steps wait for Story 1.6. Said plainly: no acceptance criterion moves, and Story 1.6 receives the dependency.
- **Decision 9.** The escaped fake keys in `steps-secrets.json`.

**Ruled at spec validation** (Epic 1 runner, 2026-10-22, unattended; the owner may reverse a veto ruling through the inbox):
- **Decision 3 (the live test swaps `ChatAgent`'s agent class in the throwaway's stored configuration, then restores it):** `category=decide`, kept. Throwaways only (Rule 21), measured first in Task 0, restored by the test; the allow-list row it needs is the throwaway's too.
- **Decision 4 (the step-label convention):** `category=decide`, kept, and written into the spine by Rule 20's light path as the Consistency Conventions row "Agent step labels" (`lint_spine.py`: no new finding). The wording of the labels is veto U-23.
- **Decision 6 (a failed call's steps wait for Story 1.6):** `category=decide`, kept; no criterion moves. The dependency is ledgered as DW-83, routed to Story 1.6 with a `DW-83:` bullet in its acceptance criteria.
- **The stored data (`Reply.Steps`, the `AgentStep` contents, `LargestRequestTokens`'s meaning):** `category=veto`, kept as planned (inbox U-21).
- **The redactor's rules and decision 9 (the escaped fake secrets):** `category=veto`, kept as planned (inbox U-22).
- **The step labels and summaries:** `category=veto`, kept as planned (inbox U-23).

## Auto Run Result

Status: done
Blocking condition: none

**Summary of the implemented change.**
- **Recording.** The runner's adapter starts a step buffer (`StepBuffer`, in `^||OcuTalonBP.Steps`) right before `Chat`, passes a `StepRenderer` to it and adds a `StepAudit` policy in `OnAfterAgentInit`. One model step is recorded per model response and one tool step per tool call or denial.
- **Returning and sending.** After `Chat`, the redacted and cut records go back in the new `Reply.Steps` (Storage slot 9). `Decide.EmitSteps` sends each one as an `AgentStep` to `AgentSteps`, in order, in the caller's session, before `Conclude`; `AgentSteps` answers an `AgentStep` with OK. The answer to a turn has no `Steps`.
- **Redaction.** `OcuTalon.Bridge.Redact.Text` replaces the values of sensitive keys at any depth, the key, token and bearer patterns, and the content of a text that is one JSON string; it fails closed.
- **The largest request (DW-77).** `Usage.Largest` and the `estimates` parameter of `FromStats` give `LargestRequestTokens` the larger of the measured last request and the estimates of the others.
- **Task 0.** All nine measurements are under `## Verification`. The configuration swap of the live test works and is undone; a tool's `duration` is accurate; a call of a missing tool never reaches the policy.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/`: `Redact.cls`, `Adapter/StepBuffer.cls`, `Adapter/StepRenderer.cls` and `Policy/StepAudit.cls` (new); `Adapter/Agent.cls`, `Data/Usage.cls`, `Msg/Reply.cls`, `Operation/Steps.cls` and `Process/Decide.cls` (changed).
- `ci/mock/scenarios/A/steps-two-tools.json` and `steps-secrets.json` (new); `release/standalone-bridge.sh` (the step check).
- `src/ocutalon/cls/OcuTalon/Test/`: `Bridge/Redact`, `Bridge/Steps`, `Bridge/StepsAgent`, `StepsTools`, `StepsNote`, `StepsCard`, `StepsSeen` and `Agent/Steps` (new); `Bridge/Contracts`, `Decide`, `Runner`, `Usage`, `Agent/Decide`, `KeyScan`, `RunnerFixture` and `Install/Production` (changed).

**Review findings.** 42 findings from the four layers (medium 9, low 29, false 2, maybe-false 2, high 0), all in `## Review Triage Log`.
- **Patched (16 findings, 8 root causes, medium 9 and low 7):** the step buffer's append is whole or absent; a text that is one JSON string is redacted by its content; `Part` turns every control character into a space; a test of the `AgentSteps` operation; `LogRowsHolding` moved into `RunnerFixture` (Rule 2); `TestTwoTools` and the standalone step check wait for the step headers to be Completed; `TestRenderer` pins the clock mark that a tool step moves; the swap of `ChatAgent` is restored when the production has stopped. Five new mutation lines are under `## Verification`.
- **Deferred (1):** a scan that fails a shipped tool class with no `STEPLABEL`, for Stories 1.10 and 5.4.
- **Rejected (25), each with its reason in the log:** the redactor's key list and unquoted-value limit (intent contract, Residual risks), `Reply.Steps` outside `KeyScan.Find`, redaction cost, the steps of a failed turn (DW-83), the wording of "1 tool calls", steps sent before `Conclude`, the failed-send test of `EmitSteps` (a trial showed that a Decide instance that is not started sends real messages, so no safe cheap test exists), and the descriptive gaps of the intent-alignment layer.

**Follow-up review recommendation: true.** Nine medium findings were patched in this first pass (two or more). The unverified risk is the new JSON-string branch of `Redact` (a recursion and a re-encoding path in a security backstop) and the two polls, which have each run green but have not been reviewed.

**Verification performed.**
- **Loop lines, first pass, before the review:** `bash ci/checks.sh` (all scripts passed), `ci/iris.sh build` (exit 0), the twelve classes one per call (all passed), `release/standalone-bridge.sh` (every check PASS), `shard lane-a` (29 classes passed, one SKIP `TestStepHelpers`), `teardown`.
- **After the patches:** `ci/checks.sh` (364 PASS), `ci/iris.sh build`, `Test.Bridge.Steps`, `Redact`, `Decide`, `Runner` and `Test.Agent.Steps` one per call (passed), `release/standalone-bridge.sh` (12 PASS, the step check included), `shard lane-a` (29 classes passed; it also covers the classes not run alone again), then the five mutations (red as named, tree put back byte-identical).
- **Once lines, after the last patch:** `docker/tests/test-mock.sh` (94 of 94), `shard lane-b` (24 classes passed), `live storage-roundtrip`, `live production`, `live production-restart`, `live install-upgrade`, `live compose-start` and `live demo-path` (all PASS), and `ci/iris.sh teardown` for tag `e1s5a` (nothing left).
- **Not run:** `shard lane-a` and `shard lane-b` with `--reverse` (the lead's fresh-environment check).

**Residual risks.** See `## Verification`: free-text identities and names outside `SENSITIVEKEYS`, escaped JSON inside free text, a call of a missing tool (`AgentStepCount` one more than the steps), steps sent for a reply that `Conclude` then refuses, the steps of a failed `Chat` (DW-83, Story 1.6) and the untested failed-send branch of `EmitSteps`.
