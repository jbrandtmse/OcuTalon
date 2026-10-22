---
title: 'Story 1.6: An unusable reply takes the fallback route, and OcuTalon starts with no key'
type: 'feature'
created: '2026-10-22'
status: 'done'
baseline_revision: '1b4e5f4b955dc65266d5ff90b027d946963a2082'
baseline_commit: '1b4e5f4b955dc65266d5ff90b027d946963a2082'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-5, AD-6, AD-8, AD-9, AD-19, AD-20, AD-22, AD-26, AD-28, AD-30, AD-31 and AD-33, and the Redaction, Logging and errors and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred:
  - summary: >-
      The matrix row "A cut-off tool call" says the result is never a usable answer, but AI Hub runs a tool call that the provider cut at
      max_tokens and goes on, so Chat returns the later reply with end_turn and the turn is answered with no fallback.
    evidence: |-
      Measured in Task 0 (e) on build 154 (Verification, "Measured in implementation"): the scenario cut-off-tool gives three steps (model, tool,
      model) and the finish reason end_turn. The bridge sees only the stop reason of the last response: StepRenderer.OnMessage gets the content
      value and nothing else. TestCutOffToolCall pins the measured behaviour. The row needs the lead's amendment, or AI Hub needs a per-response
      stop reason. Whether the arguments of a cut-off tool call can be truncated on the real Anthropic API is not measured (inference).
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Agent/Steps.cls (TestCutOffToolCall); src/bridge/cls/OcuTalon/Bridge/Adapter/StepRenderer.cls (OnMessage)
    severity: medium
  - summary: >-
      Decide.Precheck calls Budget.State on every decision, and State scans the Usage table by RecordedAt, which has no index.
    evidence: |-
      Usage indexes DecisionRef and OwnerRef only; UsageSpent selects by RecordedAt, and with a cap above 0 UnpricedModels scans again. The cost
      grows with the number of Usage rows. What would settle it: the time of Decide.Precheck with about 100,000 Usage rows.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Budget.cls (UsageSpent, UnpricedModels); src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls (Precheck)
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:**
- **Failures are errors today.** `Decide` ends every unusable reply with an error status and records no decision (Story 1.3's decision 1): a refusal, a reply cut off at the output cap, an empty reply, a provider error, a reply that fails its `ReplyClass` check and the agent's maximum-iterations error.
- **Nothing is checked before sending.** `Decide` checks no model key, no daily cost cap and no token budget. `OcuTalon.Bridge.Keys.Status` is a stub that answers 0, and nothing calls `OcuTalon.Bridge.Budget.MarkCapped`.
- **The steps of a failed call are lost (DW-83).** A `Chat` that throws returns only an error status, so the steps its runner buffered never reach Visual Trace.
- **The daily cap can fail open silently (DW-76).** A `Usage` row with no price counts nothing toward the day's spend, and an unreadable budget setting leaves the cap off, with no log line in either case.

**Approach:**
- **One classification method.** `Decide.Classify` picks the `FallbackReason` from the facts of one request, in AD-8's order.
- **Prechecks.** Before sending, `Decide` checks `no_key` (`Keys.Status`), `daily_cap` (`Budget.State`) and `budget` (a new token-budget setting). A request that fails one is recorded as a fallback decision and never sent.
- **Fallbacks after sending.** A reply, or a runner failure, that is not usable is recorded as a fallback decision: outcome `tellnow`, `Fallback` 1 and its reason. A turn gets a fallback `Reply` with no text.
- **The failed call's steps (DW-83).** The runner answers a `Chat` that threw with a failure `Reply`. It carries the redacted failure text, the buffered steps and the usage, so `Decide` sends the steps to `AgentSteps` as it does for any reply.
- **The daily cap.** Both `daily_cap` paths call `MarkCapped` once the fallback is recorded. `Budget.State` names the configuration faults that make a set cap count less, and the precheck logs them (DW-76).

## Boundaries & Constraints

**Always:**
- **The one classification method (AD-8).** `OcuTalon.Bridge.Process.Decide.Classify(facts As %DynamicObject) As %String` is pure. It returns "" when the request or reply is usable, else exactly one value of `Msg.Enum` `FALLBACKREASON`. A missing fact counts as false or empty.
  - **The facts:**
    - `noKey`, `capped` and `overBudget` are booleans from the precheck;
    - `failure` is the redacted text of a runner failure;
    - `finishReason` and `text` come from the runner's `Reply`;
    - `invalid` is a boolean: the reply failed its `ReplyClass` check, or nothing was left of it once the `ReplyFilterClass` filtered it.
  - **The order** (the first rule that holds wins):
    1. `noKey` gives `no_key`, then `capped` gives `daily_cap`, then `overBudget` gives `budget`. Story 1.9 adds `too_large` after these, and Story 1.7 the timer's `timeout`.
    2. A non-empty `failure` is matched by its text, case-insensitively:
       - it holds `daily cost cap reached` (the gateway's 403, AD-8): `daily_cap`;
       - it holds an `@{env:` placeholder and `has no value` (the missing-key provider error, measured in Story 1.2): `no_key`;
       - it holds `operation timed out`: `timeout`;
       - it holds `Rate limit exceeded`: `rate_limited`. The fallback is taken at once; Story 1.7 adds the re-send;
       - it holds one of `ITERATIONCODES` (Task 0 (a): `<%AICore>MaxIterationsReached`, plus `<%AICore>LoopDetected` if a loop raises that): `unusable`;
       - anything else, `Invalid input` included until Story 1.8 adds `SessionBroken`: `error`.
    3. `finishReason` `refusal` gives `refusal`, and `max_tokens` gives `cut_off`. Every cut-off reply is unusable (NFR-5).
    4. A `text` that is blank once white space and control characters are removed gives:
       - `empty` when `finishReason` is not empty;
       - `unusable` when it is empty, because a provider that reports no stop reason cannot tell an empty reply from a refusal or a cut-off.
    5. `invalid` gives `invalid`.
  - **The literals** live in class parameters: `DAILYCAPTEXT`, `NOKEYTEXT`, `TIMEOUTTEXT`, `RATELIMITTEXT` and `ITERATIONCODES`. The class doc records each one's source: Task 0, an earlier story's measurement, or AD-8.
- **The prechecks (AD-8, AD-20).**
  - **When they run.** In `OnRequest`, after `Admit`, the recorded-row answer, `ReplyClassOf` and `CheckSettings`. A misconfigured `Decide` stays an error status. Then the `DecisionRef` is allocated, and `Precheck(request, runner, tokenBudget)` runs:
    - `noKey` is `'Keys.Status(runner)`;
    - `capped` is `Budget.State(, .faults).capped`, and each line of `faults` is logged as one warning (DW-76);
    - `overBudget` is true when `tokenBudget` is above 0 and `EstimateTokens(request)` is above `tokenBudget`;
    - then `Classify` runs on these facts.
  - **A precheck fallback is never sent.** `Decide` records it (`RecordFallback`) and answers from `OnRequest`. It sends no runner request and sets no timer.
- **The token budget (AD-19, AD-20, FR-40).**
  - **The setting.** `Decide` gains `Property DecisionTokenBudget As %Integer [ InitialExpression = 0 ]` and the setting `DecisionTokenBudget:Bridge`. 0 means off, and 0 is the default.
  - **A bad value.** A value that is not a whole number of 0 or more counts as 0, and the precheck logs it as a configuration fault.
  - **Storage.** The compiler appends the property to `Decide`'s Storage block as slot 8.
  - **The estimate.** `Decide.EstimateTokens(request)` is `StepBuffer.Tokens` of the lengths of `Input` + `SeedText` + `SystemNote` added together. Story 1.9 adds the system prompt, the tool schemas and the history.
- **Daily-cap faults (DW-76): the cap fails open, never silently.** `Budget.State(now = "", Output faults As %DynamicArray)` keeps its JSON, with the same keys in the same order. `faults` gets one plain line, passed through `Redact.Text`, for each of these:
  - `DailyCostCapUSD` cannot be read, or is not empty and not a number of 0 or more. It counts as 0, which is off.
  - `GatewaySpendUSD` cannot be read, or is not empty and not a number of 0 or more. The gateway's spend is not counted.
  - `GatewaySpendDate` cannot be read, or is not empty and not a YYYY-MM-DD date. The gateway's spend is not counted.
  - The cap is above 0, and Usage rows of the day (owner not `eval`) have no cost. There is one line per model, naming it. Their spend is not counted.

  The spend that can be read is still counted and compared with the cap.
- **After sending (AD-6, AD-8, AD-9).**
  - **`OnError`.** For the completion key `reply`, it keeps the runner's error status in the transient property `RunnerError` (not stored) and returns OK. Ens then calls `OnResponse` (`Ens/BusinessProcess.cls:331-420`; Task 0 (d) confirms this). Other keys keep their status.
  - **`OnResponse`.** The timer still ends with an error (Story 1.7). For `reply`, it sends the steps first (`EmitSteps`), before it reads the `ReplyClass`, then calls `Conclude`. The `failure` it passes is the text of `RunnerError`, cut by `StepBuffer.Part` to `Reply.#MAXFAILURE` (2,000), or else the reply's `FailureText`.
  - **`Conclude`.** It gains the trailing parameter `failure As %String = ""`. It checks the filter class, which stays an error. Then it works out every fact:
    - `failure`: the runner's failure text; with none, a reply that is not a `Reply` counts as the failure `The runner gave no Reply`;
    - `finishReason` and `text`;
    - `invalid`, from `CheckReply` or from the filter.

    It calls `Classify` once. A reason goes to `RecordFallback`, and "" goes to the usable path, as today. `CheckReplyShape` is removed.
- **`RecordFallback(request, decisionRef, reason, reply, sinkClass, traceSessionId, Output response, durationMs = "")` (AD-8, AD-20, AD-26, AD-31).**
  - **The row.** It is built by `NewRow`, which `Conclude` shares:
    - `Ref`, `Kind`, `ItemId`, `OwnerRef`, `Summary`, `TraceSessionId` and `RecordedAt`;
    - the totals from `Usage.Totals`;
    - `AgentStepCount` from the reply, else 0, and `DurationMs`.
    - It holds `Outcome` `tellnow`, `Fallback` 1 and the reason. `Reasons`, `Confidence` and `Payload` are empty, so no model text is kept.
  - **Recording.** It is saved through `Record`, with the unique-index race handled as today.
  - **Events.** When this call saved the row, `FireEvent` sends `decision.recorded`. Then, for `daily_cap` only, `Budget.MarkCapped("", sinkClass)` runs, outside any transaction.
  - **The answer.**
    - For `decide` and `diagnose`: `ResponseFromRow`.
    - For a `turn`, a new `Reply`, not a clone. It holds `DecisionRef`, `Outcome` `tellnow`, `Fallback` 1, the reason, the totals (`CarryTotals`) and `Tainted` from the runner's reply when there is one. `Text`, `HostData`, `Steps`, `FailureText` and `FinishReason` are empty. A fallback therefore never carries check rows (AD-28) or model text.
  - **Nothing else is sent.** The fallback triggers no tool, fix or approval: `Decide` sends nothing besides its runner request, its timer, the steps and its answer (AD-30).
- **The runner's failure reply (AD-6, AD-9, DW-83).** When `Chat` throws, `Adapter.Agent.Answer` no longer re-throws. It returns OK with a `Reply` holding:
  - `FailureText`: `StepBuffer.Part` (redact, then cut to `Reply.#MAXFAILURE`) of `GetErrorText(%AI.System.HandleError(thrown, 1))`;
  - `Steps` from `StepsJson()`;
  - `HostData` and `Tainted` from the context;
  - the usage (`CarryUsage`, with the `Usage` row written as before);
  - an empty `Text` and `FinishReason`.

  It logs one warning that names the runner item, the `DecisionRef` and the `FailureText`. A failure before `Chat` (a refused request, `BuildAgent`, `NewSession` or `Context.Begin`) keeps its error status. The context and the step buffer end on every path.
- **`Reply.FailureText` (AD-5, AD-9).** `Property FailureText As %String(MAXLEN = 2000)`, appended by the compiler as slot 10, and `Parameter MAXFAILURE = 2000`, the one limit that the runner and `Decide` cut to. The runner fills it only on a failure reply, and every `Decide` answer leaves it empty.
- **`Keys.Status(agent)` (AD-6, AD-19, AD-20, FR-38).**
  - **What it reads.** `agent` is the runner item's name (`TriageAgent`, `DiagnosisAgent`, `ChatAgent`). It reads that item's `ProviderConfig` adapter setting in the active production (`Ens.Director.GetAdapterSettingValue`, as `AgentRunner.ResolveModel` does), and `Present(providerConfig)` decides.
  - **0 (no key)** when:
    - there is no production or no item;
    - the config is empty;
    - an `@{config:<name>}` entry does not exist;
    - the `api_key` is missing or empty;
    - the `api_key` is exactly one `@{env:NAME}` (`ConfigStore.KEYPATTERN`) and `$SYSTEM.Util.GetEnviron(NAME)` is empty.
  - **1** otherwise. That covers a set variable, a value that is not a placeholder, an entry that cannot be read, and a config that is neither `@{config:<name>}` nor a JSON object. Then the runner's own failure is classified.
  - **The entry** is read without its secrets resolved, through a new `ConfigStore.Details(entry, Output details)`, which `Merge` shares.
  - **No value ever leaves it.** It returns only 0 or 1. It never logs, stores or returns a value, and never throws.
- **Steps (AD-9, DW-83).** `EmitSteps` sends the `Steps` of every `Reply` that reaches `OnResponse`, the failure reply included. A runner error status carries no steps.
- **The bridge boundary (AD-2).** Nothing new in `src/bridge/` names another OcuTalon package. The bridge renders no user text: a fallback's `Reasons` are empty, and Lane B's catalog renders the reason (`OcuTalon.Msg.Catalog` `REASONKEYS`).
- **Logs (Conventions: Logging, Redaction).** Every new warning passes `Redact.Text`, directly or through `Part`. The new rows are Type 3 only, never `$$$LOGERROR`, so `check_clean_start` stays clean.
- **Text.** All text in `src/`, `ci/` and `release/` is ASCII. No committed file holds a key-like string that `docker/tests/test-boundaries.sh` flags.
- **Tests.**
  - **Where they go:** `OcuTalon.Test.Bridge` and `OcuTalon.Test.Agent`, in the lane-a shard.
  - **Cleanup on every path:** each test removes the `Decision`, `Usage` and `AgentStep` rows it made. It also puts back every System Default Settings row it wrote, every stored-configuration setting it swapped, today's `^OcuTalonBP.UsageCapped` mark, and `^OcuTalonTest("ProbeSink")`.

**Never:**
- **Story 1.7:** no timer `timeout`, no `Derive`, no re-send and no `ToolsRun`.
- **Story 1.8:** no `SessionBroken` and no conversation link.
- **Story 1.9:** no `too_large`, no estimate of the system prompt, tools or history, and no tool-result cap.
- **Lane B:** no change to `OcuTalon.Msg.Catalog*`, `Conversation`, `OutcomeRouter`, `StatusMonitor`, a banner, `docker/**`, `ci/**` outside `ci/mock/scenarios/A/`, or `Test/{Contract,Core,Data,Demo,Live,Msg,Web}/**`.
- **Step 2:** no second-model retry and no settings page.
- **No new structures:**
  - no new production item, table, index or event type;
  - no change to `Production.cls` or `BridgeExample.Production`;
  - no property change in `src/bridge/` beyond `Reply.FailureText`, `Decide.DecisionTokenBudget` and `Decide`'s transient `RunnerError`, so `Request`, `Result`, `DecisionResponse`, `AgentStep`, `Decision`, `Usage` and `Price` stay as they are.
- **Settings:** no System Default Settings row is seeded.
- **Keys:** no literal key, no `@{env:...:-fallback}`, and never a key value in a return, a log, a message or a row.
- **No commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reply fallbacks (live) | Untrusted `decide`s with the markers `refusal`, `max-tokens`, `empty`, `provider-error` and `invalid-reply` | 1. **The answer** is a `DecisionResponse`: `tellnow`, `Fallback` 1 and, in turn, `refusal`, `cut_off`, `empty`, `error`, `invalid`. Its `Reasons`, `Confidence` and `Payload` are empty.<br>2. **The row** holds the same values, with `Ref` = the runner request's `DecisionRef` and the totals of its Usage row.<br>3. **The trace:** the answer's XML holds `<Fallback>true</Fallback>` and `<FallbackReason>` with the reason. Decide's targets are only `TriageAgent`, `Ens.Alarm`, `AgentSteps` (when the reply had steps) and `ApprovalStartIn`.<br>4. **`provider-error`:** the `TriageAgent` header is Completed, and its `Reply` holds `FailureText` with `CI mock: the provider failed.` | Status OK |
| Maximum iterations (live) | User `turn`, marker `tool-loop` | 1. **The answer:** a `Reply` with `Text` "", `tellnow`, `Fallback` 1 and `unusable`, and a turn row the same.<br>2. **Usage:** Story 1.4's `Usage` row, unchanged.<br>3. **The steps (DW-83):** the call's model steps are `AgentStep`s of the ref, in the decision's session. | OK |
| A turn's fallback is a reply only (live) | User `turn`, marker `refusal` | `Text`, `HostData`, `Steps`, `FailureText` and `FinishReason` are empty; `Fallback` 1, `refusal`. The refused text is in no field of the answer. | OK |
| A runner error status (live, Task 0 (d)) | `ChatAgent`'s `Model` row is `zz-no-such-model`, `ChatAgent` restarted; a user turn | 1. **The answer** comes through `OnError`: an `error` fallback `Reply` and row.<br>2. **Nothing reached the mock.**<br>3. **On time:** the answer comes in under 10 s, not after the timer. | OK; the row is put back and the item restarted |
| A failed turn's steps (live, DW-83) | `ChatAgent` swapped to `StepsAgent`, marker `steps-loop` | 1. **The answer:** an `unusable` fallback `Reply`.<br>2. **The steps:** the `AgentStep`s of the ref alternate model and tool:<br>- Positions 1 to n;<br>- tool labels `Reading the test note`, status `ok`;<br>- each Completed, in the decision's session, after `ChatAgent`'s reply and before `Decide`'s answer.<br>3. **The count:** the row's `AgentStepCount` is at least n. | OK |
| A cut-off tool call (live, Task 0 (e)) | `StepsAgent`, marker `cut-off-tool` | As measured on build 154: AI Hub runs the cut-off tool call and goes on, `Chat` returns the later reply with `end_turn`, and that final reply is the turn's answer (three steps: model, tool, model). A final reply cut at the cap is never an answer (`cut_off`, AC1). [AMENDED 2026-10-22, lead, unattended ruling U-29; the row said "A fallback ... Never a usable answer", which AI Hub does not allow] | OK |
| Prechecks (live) | 1. `DecisionTokenBudget` 1, `Decide` restarted.<br>2. `DailyCostCapUSD` 1, `GatewaySpendUSD` 1, `GatewaySpendDate` today. | 1. `budget`.<br>2. `daily_cap`, plus one `budget.capped` event: owner `instance`, payload `{"day": <today>}`.<br>For each: the mock's log holds no request with the ref, and `Decide` sends nothing but its answer (no runner request, no `Ens.Alarm`). | OK |
| Both daily-cap paths (live, U-16) | The cap is off, today is unmarked, and `Decide`'s `HostSinkClass` is swapped to `ProbeSink` in shared mode. Then, in order:<br>1. a decide with `[[mock:daily-cap]]` (HTTP 403);<br>2. a decide on Triage's default script;<br>3. a user turn. | 1. **The 403:** `daily_cap`; the runner was called once and today is marked.<br>2. **The precheck:** `daily_cap`, nothing sent.<br>3. **The turn:** a `daily_cap` fallback `Reply`, nothing sent.<br>**The events:** exactly one `budget.capped` (owner `instance`, `{day}` today), fired after the first row exists, and three `decision.recorded`. | OK; the mark and the swap are removed |
| No key (live, a CI start) | `ANTHROPIC_API_KEY` unset; the entries at its placeholder | 1. **Keys:** `Keys.Status` is 0 for `TriageAgent`, `DiagnosisAgent` and `ChatAgent`.<br>2. **Fallbacks:** a decide and a turn through `Decide` each record a `no_key` fallback.<br>3. **Nothing sent:** the mock's log has nothing since the mark.<br>4. **Nothing fails:** every item runs before and after, and there is no event-log row of Type 2 or 6 since the mark taken before the `Decide` sends. | OK |
| Keys (pure) | `Present` of `""`, `{}`, `{"api_key":""}`, `{"api_key":"@{env:PATH}"}`, `{"api_key":"@{env:ZZOCUTALONNOSUCHVAR}"}`, `{"api_key":"literal-value"}`, `@{config:ZzNoSuchEntry}` and `not json`; `Status("ZzNoSuchItem")` | `Present` gives 0, 0, 0, 1, 0, 1, 0 and 1, and `Status` gives 0. Each result is exactly 0 or 1, and no event-log row since the mark holds the value of `PATH`. | Never throws |
| Classify (pure) | 1. Each fact alone.<br>2. Pairs: `noKey` + `failure`; `failure` + `refusal`; `refusal` + an empty text; `max_tokens` + `invalid`.<br>3. The measured failure texts: Task 0 (a) and (b), Story 1.2's missing key, Story 0.11's 400, 500 and 529, and AD-8's `operation timed out`.<br>4. An empty text with `finishReason` "" and with `end_turn`. | 1. Each fact gives its own reason, and no facts give "".<br>2. The earlier rule wins.<br>3. The 403 gives `daily_cap`, the missing key `no_key`, the 529 `rate_limited`, timed out `timeout`, maximum iterations `unusable`, and the 400 and 500 `error`.<br>4. `empty` with `end_turn`, `unusable` with "". A `finishReason` of "" never gives `refusal` or `cut_off`. | n/a |
| The catalog map (pure, Lane B's renderer) | Each of the 12 `FALLBACKREASON` values through `OcuTalon.Msg.Catalog.Render("conversation.turnFallback", <slots>, "web", .sc)`, where the slots are the JSON text `{"fallbackReason": "<v>"}` | 1. **One each:** each text holds exactly one of the 11 `fallbackReason.*` texts (`Catalog.Entry`).<br>2. **Generic:** `invalid` and `unusable` give the generic one.<br>3. **Own:** `refusal` and `cut_off` give their own.<br>4. **All reached:** every one of the 11 is reached. | `sc` OK |
| Conclude and OnError (pure) | 1. `Conclude` of a refusal, a `max_tokens`, an empty turn, a reply that fails its check, a filter that leaves nothing and a failure text.<br>2. `OnError`, then `OnResponse`, with an error status.<br>3. A fallback for an item that already has a row. | 1. Status OK. One row with `Fallback` 1 and the reason, and empty `Reasons`, `Confidence` and `Payload`. One `decision.recorded`, after the save. A turn gets a fresh `Reply`.<br>2. An `error` fallback.<br>3. The existing row's answer, and no event. | n/a |
| The MarkCapped wiring (pure) | `ProbeSink`. `RecordFallback` with `daily_cap`; again for another item; then with `error` | 1. `decision.recorded`, then `budget.capped`, at `$TLevel` 0, with the row and the mark in place.<br>2. `decision.recorded` only.<br>3. No `budget.capped`. | A failing sink is a warning |
| Budget faults (pure, DW-76) | 1. `DailyCostCapUSD` `abc`.<br>2. `GatewaySpendUSD` `x`.<br>3. `GatewaySpendDate` `2001-13-45`.<br>4. Cap 1 and a Usage row of the day with no cost (model `zz-unpriced`).<br>5. Cap 0 with that row.<br>6. All valid. | 1 to 3. One fault line each, naming the setting.<br>4. One line naming `zz-unpriced`; `capped` is false and `spent` leaves the row out, so the cap fails open.<br>5 and 6. No fault.<br>The JSON of `State` is unchanged. | Never throws |
| The precheck logs (pure) | 1. `Decide.Precheck` with the `zz-unpriced` row and cap 1.<br>2. `DecisionTokenBudget` -1. | 1. One warning per fault, from `Precheck`, naming it, redacted.<br>2. The token budget counts as 0, with a warning. | n/a |
| The runner's failure reply (in process) | `ZzRunner` with `provider-error`, `provider-error-secret` and `tool-loop` | 1. **Status** OK.<br>2. **`FailureText`** holds the provider's text, or the maximum-iterations code. For `provider-error-secret`, the fake bearer token shows as `[redacted]`, and it is in no `FailureText`, `Steps`, log row or `KeyScan.Find` store.<br>3. **The rest of the reply:** `Steps` holds the buffered records.<br>4. **Usage:** one row for `tool-loop`, none for `provider-error`.<br>5. **The log:** one warning, naming the `DecisionRef`.<br>6. **Cleanup:** the context and the buffer have ended, and the next call is OK. | n/a |
| The bridge alone | `release/standalone-bridge.sh` | The example decision is not a fallback: `Keys.Status` reads its inline `ProviderConfig` placeholder as present, the cap is off and the budget is 0. The script's checks pass unchanged. | The script fails, naming the check |
| The timer and a late reply | `TestTimer` | Unchanged: an error status that names the timer (Story 1.7). | As in Story 1.3 |

</intent-contract>

## Code Map

- **AI Hub and Ens (read only, `irislib/`, `irissys/`):**
  - **Codes.** `%AI/Errors.inc`: `MaxIterationsReached` (:34), `LoopDetected` (:32), `ProviderError` (:45), `ProviderConfigError` (:43) and `InternalError` (:23). The texts are native, so Task 0 measures them.
  - **`Chat` throws** (`%AI/Agent.cls:754-762`, contract at :971-973). `%AI/System.cls:87-127` `HandleError(ex, 1)` keeps the `<%AICore>` code and text.
  - **A missing key** fails the agent build, so nothing is sent: `EnsLib/AI/Agent/OutboundAdapter.cls:250-252` and :288-290. The measured text (`spec-1-2…md:554`) is `ERROR <%AICore>ProviderCreateFailed: Failed to create provider 'anthropic' > ERROR <%AICore>InternalError: Internal AI-Core error: @{env:ANTHROPIC_API_KEY} has no value and no :-fallback was given`.
  - **Provider texts** (`spec-0-11…md:870-877`, measured):
    - 400: `… error: Invalid input: <msg>`;
    - 401: `… API error: Authentication failed: <msg>`;
    - 500: `… API error: [api_error] <msg>`;
    - 529: `… error: Rate limit exceeded: <msg>`.

    403 has never been measured (Task 0 (b)).
  - **Config Store.** `irissys/%SYS/ConfigStore/Configuration.cls:413-436` `GetDetails(fqn, .d, 0, 0)` gives `@{env:NAME}` as literal text. `@{config:X}` means `AI.LLM.X` (`irislib/%AI/Utils/ConfigStore.cls:13-17`).
  - **Ens.** `Ens/BusinessProcess.cls:331-347`: an errored response calls `OnError`. When that returns OK, `OnResponse` is called next (:414-420). The default `OnError` is at :875-878.
- **The bridge (Lane A, `src/bridge/cls/OcuTalon/Bridge/`):**
  - **`Process/Decide.cls`:**
    - the class doc (:3-31) and `SETTINGS` (:35);
    - `OnRequest` (:73-95), with `CheckSettings` at :88, the send at :92 and the timer at :94;
    - `OnResponse` (:98-113), with `ReplyClassOf` at :106-110 and `EmitSteps` at :111;
    - `CheckReplyShape` (:279-291), which is removed;
    - `Conclude` (:309-388), with the row at :352-374, `Record` at :375, `FireEvent` at :377 and the turn clone at :378-385;
    - `Record` (:393), `FireEvent` (:415), `ResponseFromRow` (:449) and `CarryTotals` (:469);
    - Storage (:476-504), where slot 7 is the last.
  - **`Adapter/Agent.cls`:**
    - `Answer` (:210-263), with `Chat` at :232, the rethrow at :244, the catch at :254-257 and the ends at :259-260;
    - `StepsJson` (:284), `RecordUsage` (:315) and `CarryUsage` (:335).
  - **`Budget.cls`:** `State` (:24-40), `MarkCapped` (:52-79, which already lists Story 1.6 as its caller), `UsageSpent` (:84), `Setting` (:99) and `Amount` (:105).
  - **`Keys.cls`:** the stub that answers 0.
  - **`ConfigStore.cls`:** `KEYPATTERN` (:19), `Merge` (:33-57, which runs `Exists` and `GetDetails` at :46-50) and `FullName` (:61).
  - **`Msg/Reply.cls`:** the properties (:5-34) and Storage slots 1 to 9.
  - **`Msg/Enum.cls`:** `FALLBACKREASON` (:15).
  - **`Operation/AgentRunner.cls`:** `OnMessage` (:18-31), and the `GetAdapterSettingValue` pattern in `ResolveModel` (:39-51).
  - **`Adapter/StepBuffer.cls`:** `CHARSPERTOKEN` (:19), `Tokens` (:146) and `Part` (:172, redact, then cut).
  - **Others:** `Redact.Text` (:43), `Ext/Accessor.ValueFor` (:13), `Data/Usage.Totals` (:144), and `Time.LocalDate` (:31) and `DayStartUtc` (:37).
- **The catalog (Lane B, read only):**
  - `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls:44`: `REASONKEYS` maps all 12 values, with `invalid` and `unusable` to `generic`, and the slot type at :185-190 uses it.
  - `Msg/Catalog/Core.cls`: `conversation.turnFallback` (:157) and the 11 `fallbackReason.*` keys (:181-235).
  - `Test/Msg/Catalog.cls:255-280` pins the map.
- **The mock (Lane B's code; Lane A adds files to `ci/mock/scenarios/A/` only):**
  - **The scenario rules** (`ci/mock/scenarios.mjs`):
    - a reply is `status` plus one of `text`, `toolUse` or `body` (:26-27, :106-113);
    - `stopReason` is refused with a `body` or with a status of 400 or more (:134-140), and a `toolUse` needs a status below 400 (:141);
    - `toolUse` together with `max_tokens` is legal;
    - the name is kebab-case and equals the file name and the marker (:156-167);
    - new `A/` scenarios are marker scenarios (`constants.test.mjs:70-80`).
  - **The answers** (`mock.mjs`):
    - an error status with no `body` is answered `{"type":"error","error":{"type":<403 permission_error, 500 api_error, ...>,"message":<text>}}` (:60-73, :302);
    - a request with no key gets 401 (:397-400).
  - **The log** is read from IRIS through `Test.Contract.Mock.LogMark`/`LogSince` (:365, :378), and `RunnerFixture.FindRequests(entries, ref)` (:524) filters it by the ref.
  - **Existing scenarios:** `refusal`, `max-tokens`, `empty`, `provider-error` (500), `invalid-reply` and `tool-loop` (always `list_productions`) serve AC1. `overloaded` and `rate-limited` are left to Story 1.7. No scenario serves a 403.
- **Tests (Lane A, `src/ocutalon/cls/OcuTalon/Test/`):**
  - **`Agent/Decide.cls`:**
    - `TestUnusableEndsWithError` (:344-374): its invalid-reply half (:351-354, and the message at :362) and its provider-error half (:368-373) flip to fallbacks;
    - `TestCostOfFailedTurn` (:509-539) flips to an `unusable` fallback, and its "no AgentStep" assertions (:530, :535) become "its model steps";
    - `TestTimer` (:378-412) stays;
    - `Prepare` (:594), `OnAfterOneTest` (:82-101, which deletes the TimerSeconds row and restarts Decide) and `ItemIds`;
    - the doc (:20-23, :36-37, :43-44).
  - **`Agent/RunnerFixture.cls`:**
    - `NewRequest` (:200), `Run` (:299), `Targets` (:308), `HeaderTo` (:325) and `CountTo` (:336);
    - `Restart` (:77), `ReadyReason` (:230), `DecisionOf` (:239), `Headers` (:247), `StepsOf` (:259), `DeleteSteps` (:273) and `SessionSince` (:364);
    - `PointKeys`/`RestoreKeys` (:373/:380: `@{env:OCUTALON_MOCK_KEY_HEADER}` = "1", against the unset `@{env:ANTHROPIC_API_KEY}`);
    - `UseAgent`/`RestoreAgent`, with the private `ChangeAgent`, `ReadSetting` and `PutSetting` (:441-515, Adapter target only);
    - `EventMark` (:108), `EventRows` (:175), `Warnings` (:565), `UsageIds` (:582) and `AddUsage` (:594).
  - **`Agent/Runners.cls`:** `TestStartsWithNoKey` (:92-123) and `EnsureKeysAtPlaceholder` (:333).
  - **`Agent/Steps.cls`:** the swap of `ChatAgent` to `StepsAgent` (`OnBeforeAllTests` :60, `OnAfterAllTests` :93), `WaitStepsDone` (:387) and `HeadersOf` (:364).
  - **`Bridge/Decide.cls`:**
    - `TestReplyCheck`'s `Conclude` part (:205-217) and `TestFilterBlanks` (:455-467) flip to fallbacks;
    - `TestOnRequestUsesItsSettings` (:576-594) stays, because the settings check comes before the precheck;
    - the helpers `NewReply` (:1010), `Conclude` (:1020), `ConcludeWith` (:1027), `Rows` (:1054) and `NewProcess` (:978).
  - **`Bridge/Runner.cls`:**
    - `TestChatErrorIsStatus` (:172-195), `TestUsageRows` (:398-440) and `TestStepBufferEndsOnEveryPath` (:635-665) flip to the failure reply;
    - `TestBuildRetried` (:135-167) and `TestFinishReason` (:252-264) stay;
    - `NewRunner` (:746) and `ProviderConfig` (:760).
  - **`Bridge/Budget.cls`:**
    - the JSON pin at :109 stays;
    - `Prepare` (:495), `SettingId`, `Snapshot`, `Put` (:537-552) and `RestoreSetting` (:555-560), all instance methods and private;
    - `TestMarkSeveralAtOnce` (:350-399).
  - **`Bridge/ProbeSink.cls`:** it records into the process-private `^||ZzProbeSink`, which a production job's calls cannot reach.
  - **The rest:**
    - `Bridge/Contracts.cls`: the `Reply` block (:158-184, exact) and `TestNewBusy` (:16-34);
    - `Bridge/Api.cls:36`: `Keys.Status("TriageAgent")` is 0;
    - `Bridge/Example.cls:95-108` `TestDecideDefaults`;
    - `Bridge/StepsAgent.cls`, which has no `MaxIterations`; Chat's is `Property MaxIterations … = 4` (`Agent/Chat.cls:13`).
- **Lane B, read only:**
  - `Test/Contract/Ac.cls`: the signature check (:140-163) is a prefix; `Budget.State` is pinned at :320 and `Keys.Status` at :321. The `Named` check of the `Reply` properties is a superset check (:225-226).
  - `docker/tests/lib-live.sh` `check_clean_start` (:644-653) allows no Type 2 or 6 row.
  - `test-storage-roundtrip.sh` compares the Storage blocks.
- **CI (Lane A):** `release/standalone-bridge.sh` writes an inline `ProviderConfig` with `@{env:OCUTALON_MOCK_KEY_HEADER}` (:107-108), and its decide check expects `fallback 0` (:130-147).

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **Targets.** Use the slot for process-local facts and a throwaway of tag `e1s6a` for the rest.
- **(a) Maximum iterations.**
  - **What to record:** the code and the full `GetErrorText(HandleError(thrown, 1))` of the exception that `Chat` throws, verbatim, for `tool-loop` on `ChatAgent` (a missing tool) and for `steps-loop` on `StepsAgent` (a real tool), with `MaxIterations` 4. Record whether a loop raises `LoopDetected` instead.
  - **What it sets:** `Decide.ITERATIONCODES`.
- **(b) The gateway's 403.**
  - **First try:** the failure text of the new `daily-cap` scenario (Anthropic's error shape) through `ZzRunner`. It must hold `daily cost cap reached`.
  - **Second try:** if it does not, try the same reply with a plain-text `body`.
  - **Stop:** if neither text holds the phrase, stop with status `blocked` and the condition `intent gap: AD-8 (the gateway's 403 is daily_cap), measured <text>`.
- **(c) The reply shapes.** `FinishReason` and `Text` for `refusal`, `max-tokens` and `empty`. An empty reply must carry a non-empty `FinishReason` on the Anthropic path. If it does not, stop with status `blocked` and the condition `intent gap: AC1 (empty), measured <fact>`.
- **(d) `OnError`.** A runner error status through `Decide` (`ChatAgent`'s `Model` row set to `zz-no-such-model`). Record:
  - that Ens calls `OnResponse` with the key `reply` after `OnError` returned OK, and what `callresponse` holds;
  - that the business process completes with the answer, and what becomes of the pending timer;
  - whether the build or `NewSession` fails.

  If `OnResponse` is not called, `OnError` itself classifies and records the fallback. Write down which of the two was implemented.
- **(e) A cut-off tool call.** For `cut-off-tool` (a `toolUse` with `stopReason` `max_tokens`) through `StepsAgent`, record whether `Chat` returns `max_tokens`, runs the tool, or throws, and the steps that result.
- **(f) The environment in production jobs.** In a throwaway, in the `Decide` job and in a runner job, `$SYSTEM.Util.GetEnviron`:
  - gives `OCUTALON_MOCK_KEY_HEADER` (record its length only);
  - gives "" for `ANTHROPIC_API_KEY`;
  - and `Keys.Status` agrees with the test process.

  Also confirm that `PATH` is set in the test process, for the "Keys" row.
- **(g) Redaction.** `Redact.Text` of each measured failure text (a, b, Story 1.2's missing key, Story 0.11's 529) keeps the words that `Classify` matches.
- **(h) The XML** of a fallback `DecisionResponse` and of a fallback `Reply`.
- **Other facts.** If a fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`.** Rationale: AD-6, AD-8, AD-9, AD-20, AD-26, AD-30, AD-31; DW-76, DW-83, U-16.
  - **New:** `DecisionTokenBudget` and its setting; `Classify` and the five literal parameters; `Precheck`; `EstimateTokens`; `RecordFallback`; `NewRow` (shared with `Conclude`); `OnError`, with the transient `RunnerError`.
  - **`OnRequest`:** the precheck after `CheckSettings`, and a fallback answered without a send.
  - **`OnResponse`:** `EmitSteps` before `ReplyClassOf`, then the failure text passed to `Conclude`.
  - **`Conclude`:** the facts, one `Classify`, and the fallback branch.
  - **Removed:** `CheckReplyShape`.
  - **The class doc:** rewrite its failure paragraph.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:** the failure reply when `Chat` threw, cut to `Reply.#MAXFAILURE` through `StepBuffer.Part`, and its warning. Update the class doc and `Answer`'s doc. Rationale: AD-6, AD-9, DW-83.
- **`src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`:** add `FailureText` and `MAXFAILURE`; the compiler appends slot 10. Rationale: AD-5, AD-9.
- **`src/bridge/cls/OcuTalon/Bridge/Keys.cls`:** `Status` and `Present`, as in Boundaries, and the doc. Rationale: AD-6, AD-19, AD-20, FR-38.
- **`src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`:** add `Details(entry, Output details)` (`Exists`, then `GetDetails(fqn, .d, 0, 0)`). `Merge` calls it. Rationale: AD-19, Rule 2.
- **`src/bridge/cls/OcuTalon/Bridge/Budget.cls`:** the `faults` output of `State`; `Setting` returns its status; update the doc. Rationale: AD-20, DW-76.
- **`src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`:** the doc only (a failed `Chat` is answered with a failure reply). Rationale: AD-6.

**The mock (Lane A's folder).** Four new marker scenarios. Rationale: AD-22.
- **`ci/mock/scenarios/A/daily-cap.json`:** status 403, with the body `{"type":"error","error":{"type":"permission_error","message":"daily cost cap reached"}}`.
- **`ci/mock/scenarios/A/steps-loop.json`:** always the `toolUse` `zz_steps_note` with `{"topic": "status"}`.
- **`ci/mock/scenarios/A/cut-off-tool.json`:** the `toolUse` `zz_steps_note` with `{"topic": "status"}` and `stopReason` `max_tokens`, then the text `The CI mock answered after the cut.`
- **`ci/mock/scenarios/A/provider-error-secret.json`:** status 500, text `CI mock: the provider failed. Authorization: Bearer zzocutalonfakebearer0123456789`. That is not key-like for `test-boundaries.sh`.

**Tests.**
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Fallback.cls`** (new, pure): the "Classify" and "The catalog map" rows. It reads the catalog through `Catalog.Render` and `Catalog.Entry` only.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Keys.cls`** (new, pure): the "Keys" row.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`:**
  - flip `TestReplyCheck`'s `Conclude` part and `TestFilterBlanks`;
  - add `TestConcludeFallbacks`, `TestOnErrorFallback`, `TestFallbackRace`, `TestMarkCappedWiring`, `TestPrecheckLogs` and `TestEstimateTokens` (the pure rows);
  - update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Budget.cls`:** add `TestFaults` (the DW-76 row). Its settings helpers move to `RunnerFixture` (below), and the private methods become one-line delegates.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`:**
  - `TestChatErrorIsStatus` becomes `TestChatErrorIsFailureReply`;
  - flip `TestUsageRows` and `TestStepBufferEndsOnEveryPath`;
  - add `TestFailureTextRedacted` (`provider-error-secret`);
  - update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls`:** add `"FailureText": "%String(MAXLEN=2000)"` to `Reply`, and `FailureText` to `TestNewBusy`'s empty fields.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`:** `TestNeutralValues` checks `Keys.Status("ZzNoSuchItem")` is 0, and the doc follows.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls`:** `TestDecideDefaults` checks that `DecisionTokenBudget` defaults to 0 and is `DecisionTokenBudget:Bridge`.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls`:** add the shared mode. While `^OcuTalonTest("ProbeSink","shared")` is 1, each call also appends `$ListBuild(type, ownerRef, payloadJSON, rowExists, markExists)` under `^OcuTalonTest("ProbeSink","calls")`. Update the doc.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/StepsAgent.cls`:** `Property MaxIterations As %Integer [ InitialExpression = 4 ]`, as on Chat, and the doc names the new scenarios.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:**
  - **Item settings.** `UseItemSetting(item, target, name, value, Output saved)` and `RestoreItemSetting(item, saved)`, built on `ChangeAgent`'s helpers with a `target` parameter. `UseAgent` and `RestoreAgent` keep their behaviour.
  - **Default settings.** `SnapshotDefault(item, setting)`, `PutDefault(item, setting, value)` and `RestoreDefault(saved)`, moved from `Test.Bridge.Budget`.
  - **Readers.** `ErrorRows(mark)` gives the event-log rows of Type 2 or 6. `SinkCalls(type)` reads the shared probe.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`:**
  - `TestUnusableEndsWithError` becomes `TestReplyFallbacks`: the five markers, with the "Reply fallbacks" row;
  - flip `TestCostOfFailedTurn` (the "Maximum iterations" row);
  - add `TestTurnFallbackIsReplyOnly`, `TestRunnerErrorIsFallback`, `TestPrechecks` and `TestDailyCapBothPaths`;
  - `OnAfterOneTest` puts back every default-settings row and item setting it saved, kills today's mark and `^OcuTalonTest("ProbeSink")`, and restarts what it changed;
  - update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Steps.cls`:** add `TestFailedTurnSteps` (the DW-83 row) and `TestCutOffToolCall` (the Task 0 (e) row).
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`:** `TestStartsWithNoKey` gains the "No key" row's `Decide` part. `OnAfterOneTest` deletes the rows it made.
- **Coverage.** Prove every matrix row with these tests and the script.

**Acceptance Criteria:**
- **AC1, every unusable reply is classified, never answered.**
  - **Given** the mock's refusal (`finish_reason` `refusal`), cut-off (`max_tokens`), empty, provider-error (500) and invalid-JSON scenarios, and the agent's maximum-iterations error (`tool-loop`), served on the Anthropic provider path that ships,
  - **when** `Decide` handles each,
  - **then** it records `refusal`, `cut_off`, `empty`, `error`, `invalid` or `unusable` in turn, through the one method `Decide.Classify` in AD-8's order, and no reply text becomes an answer. The maximum-iterations text measured on build 154 is the `ITERATIONCODES` parameter of that method.

  (`Test.Agent.Decide.TestReplyFallbacks`, `TestCostOfFailedTurn`; `Test.Bridge.Fallback`; `Test.Bridge.Decide.TestConcludeFallbacks`)
- **AC2, prechecks are never sent.**
  - **Given** a request over the token budget per decision, a daily cost cap that has been reached, or no model key,
  - **when** `Decide` prechecks it,
  - **then** the result is `budget`, `daily_cap` or `no_key`, the mock's log holds no request with its ref, and `Decide` sends no runner request and sets no timer. The gateway's HTTP 403 "daily cost cap reached" is classified `daily_cap` and sent once only.

  (`Test.Agent.Decide.TestPrechecks`, `TestDailyCapBothPaths`; `Test.Agent.Runners.TestStartsWithNoKey`)
- **AC3, the day is capped once (Integration AC; U-16).**
  - **Given** both `daily_cap` paths,
  - **when** a test forces the gateway's 403 through the mock and then the precheck,
  - **then** each path calls `Budget.MarkCapped` once its fallback decision is recorded, the day is marked once, and the host sink receives exactly one `budget.capped` (owner `instance`, `{day}`).

  The consumer is `Budget.State()`: after the 403 it reports the cap reached, so the next decision falls back before sending.

  (`Test.Agent.Decide.TestDailyCapBothPaths`; `Test.Bridge.Decide.TestMarkCappedWiring`)
- **AC4, any fallback.**
  - **Given** any fallback,
  - **when** `Decide` records it,
  - **then:**
    - the row and the answer have outcome `tellnow`, `Fallback` true and its `FallbackReason`, and the message XML shows both;
    - `Decide` sends nothing but its runner request, its timer, the steps and its answer, so no tool, fix or approval request follows;
    - a `turn` is answered with a fallback `Reply` only: no text, no host data, the reason;
    - an item's fallback is a `DecisionResponse` for its caller to notify.

  (`Test.Agent.Decide.TestReplyFallbacks`, `TestTurnFallbackIsReplyOnly`, `TestRunnerErrorIsFallback`; `Test.Bridge.Decide.TestConcludeFallbacks`)
- **AC5, each reason maps to one UX reason (Integration AC).**
  - **Given** the bridge's 12 `FallbackReason` values,
  - **when** a test renders each through Lane B's catalog renderer,
  - **then:**
    - each gives exactly one of the UX's 11 fallback reasons, and all 11 are reached;
    - `invalid`, `unusable` and any reply from a provider that reports no stop reason give the generic "the model's reply couldn't be used";
    - `cut_off` and `refusal` arise only from a reported `finish_reason`.

  (`Test.Bridge.Fallback`)
- **AC6, OcuTalon starts with no key.**
  - **Given** no model key in the environment,
  - **when** a CI test runs on the started production,
  - **then:**
    - every production item runs and no event-log error or alert row appears;
    - a decide and a turn take the fallback route with `no_key` and are never sent;
    - `Keys.Status(agent)` reports each runner's key as absent, returning only 0 or 1 and never a value.

  (`Test.Agent.Runners.TestStartsWithNoKey`, `Test.Bridge.Keys`)
- **AC7, a failed call's steps reach Visual Trace (DW-83; Integration AC).**
  - **Given** a turn whose `Chat` throws after model requests and tool calls,
  - **when** the runner answers,
  - **then** its failure `Reply` carries the redacted failure text and the buffered steps, and `Decide` sends them to `AgentSteps`, in order, in the decision's session, like a completed turn's.

  (`Test.Agent.Steps.TestFailedTurnSteps`, `Test.Bridge.Runner.TestChatErrorIsFailureReply`, `TestFailureTextRedacted`)
- **AC8, a set cap never fails open silently (DW-76).**
  - **Given** an unpriced model's usage today, or a budget setting that cannot be read or is not valid,
  - **when** the `daily_cap` precheck runs,
  - **then** `Budget.State` names each fault, the precheck logs each one as a warning, and the cap counts the spend it can read (it fails open, with the fault logged).

  (`Test.Bridge.Budget.TestFaults`, `Test.Bridge.Decide.TestPrecheckLogs`)

## Spec Change Log

- 2026-10-22, lead (Epic 1 runner), at dev complete: the I/O matrix row "A cut-off tool call" is restated to the behaviour Task 0 (e) measured (veto U-29; the platform report is ledgered as decision-pending for the owner). The intent is unchanged: a reply cut at the output cap is never treated as an answer.

## Review Triage Log

### 2026-10-22 — Review pass
- verdicts: 48 findings — high 0, medium 8, low 36, false 3, maybe-false 1
- findings:
  - Blind Hunter:
    - `[medium]` `[patch]` `ConfigStore.Merge` does not read through `Details` although the spec, the class doc and the test header say it does — `Merge` repeated the `Exists` and `GetDetails` block (Rule 2). Fixed: `Merge` calls `Details`; the missing-entry text names the class and the entry; `Test.Bridge.ConfigStore` is green.
    - `[low]` `[patch]` `Details` doc says the api_key is "never the value", which holds only for placeholders — fixed: the doc says it returns the entry as stored and that a caller never logs, stores or returns it.
    - `[low]` `[patch]` `Keys.Present` finds an absent entry by matching "does not exist" in the error text — fixed: a failed `Details` is absent only when `%ConfigStore.Configuration.Exists` says so (decision 23).
    - `[low]` `[reject]` `Keys` judges "no key" from `ProviderConfig` alone, not from `ProviderName` or the agent class's `APIKEY` and `PROVIDERCONFIG` parameters — spec-bound (Boundaries: an empty config is 0), and OcuTalon's runners always carry a `ProviderConfig` from the Provider step; reopen_if a runner may take its key from those other sources.
    - `[maybe-false]` `[defer]` `Precheck` calls `Budget.State` on every decision, and `State` scans `Usage` by the unindexed `RecordedAt` — medium if true; what would settle it: the time of `Precheck` with about 100,000 `Usage` rows (deferred item 2).
    - `[low]` `[patch]` `UnpricedModels` logs its failure without `Redact.Text` — fixed. The scan failure is a warning, not silent, and the four faults of `State` are the spec's list.
    - `[low]` `[reject]` `daily_cap` is found by an unanchored substring and has a day-wide effect — AD-8 and the spec define the match as "holds `daily cost cap reached`", and the text is the provider's own error, which does not echo request text (Task 0 (b)); reopen_if a provider error is seen echoing prompt text.
    - `[medium]` `[defer]` `TestCutOffToolCall` pins "no fallback" where the matrix row says "never a usable answer" — AI Hub runs a tool call that the provider cut at max_tokens and goes on (Task 0 (e), decision 22), and the bridge cannot see an intermediate stop reason (`StepRenderer.OnMessage` gets the text only). The platform behaviour is pre-existing; the row needs the lead's amendment (deferred item 1).
    - `[low]` `[reject]` the restores in three `OnAfterOneTest` methods ignore their status — a failed restore makes later tests fail visibly, not pass; unlikely, and the fix touches three teardown methods.
    - `[low]` `[patch]` `TestPresentEntry` has `$$$AssertTrue(1, ...)` for the entry that cannot be created — fixed: `$$$LogMessage`, so no assertion that cannot fail stays.
    - `[low]` `[reject]` untested branches (the `Catch` of `FailureText`, the failed scan in `UnpricedModels`, a `Keys.Status` read error that is not "item not found", `Classify` of a non-object) — each is by inspection, needs a seam that the product does not have, and `Classify` takes a `%DynamicObject` by contract.
  - Edge Case Hunter:
    - `[low]` `[reject]` an empty `ProviderConfig` while `ProviderName` or the class parameters supply the key — same root as the Blind Hunter's fourth finding.
    - `[low]` `[reject]` a keyless provider (vertex, bedrock, a local `base_url`) has no api_key and counts as absent — spec-bound (a missing api_key is 0) and release 1 runs key-based providers; reopen_if a keyless provider is supported.
    - `[low]` `[patch]` `Details` errors read as absent by their text — same root as the Blind Hunter's third finding; fixed.
    - `[low]` `[reject]` a missing or renamed runner item is hidden as `no_key` — spec-bound (Keys.Status Boundaries: no item gives 0), and `CheckSettings` already refuses a runner that the kind does not name.
    - `[low]` `[reject]` one warning per fault per decision, unthrottled — decision 4 states exactly that, and decisions are rare events; reopen_if the event log fills with these warnings.
    - `[low]` `[reject]` `daily_cap` does not mark the day when another call already saved the item's row — spec-bound (the mark follows the call that saved the row), it needs two answers for one item, and the next `daily_cap` fallback of any other item marks the day.
    - `[low]` `[reject]` a non-AI-Hub exception inside `Chat` becomes an `error` fallback row — spec-bound (Boundaries: when `Chat` throws, `Answer` no longer re-throws; ruled U-25); a job that is halted does not return to this code.
    - `[low]` `[reject]` a reply of only non-ASCII white space (NBSP, U+200B) is not blank — spec-bound (blank once white space and control characters are removed, as Story 1.3 checked); reopen_if a provider returns such replies.
    - `[low]` `[patch]` `TestCostOfFailedTurn` reads `row.AgentStepCount` when `row` may not be an object — fixed: a guard.
    - `[low]` `[reject]` a failed `Chat` no longer raises an error-level event-log row or alert — spec-bound (Boundaries: one warning, Type 3 only, so `check_clean_start` stays clean; ruled U-25).
    - `[medium]` `[patch]` the removed assertion that `Decide` sends the runner exactly one request — fixed: `CountTo(headers, runner) = 1` in `TestReplyFallbacks` (each marker), `TestCostOfFailedTurn`, `TestTurnFallbackIsReplyOnly`, `TestRunnerErrorIsFallback` and `TestFailedTurnSteps`; mutation recorded.
    - `[medium]` `[patch]` claim: "`Merge` calls `Details`" — same root as the Blind Hunter's first finding; fixed.
    - `[low]` `[reject]` claim: `steps-loop.json` holds six topics, not one — a measured fact, recorded as decision 13; the fix would edit the spec's Tasks text.
  - Verification Gap:
    - `[medium]` `[patch]` the dropped one-request assertion — same root as the Edge Case Hunter's eleventh finding; fixed.
    - `[low]` `[patch]` `TestOnRequestPrecheck` could not tell the settings check from the precheck — fixed: the bad-setting case is a turn that also fails the no-key and budget prechecks. `TestOnRequestUsesItsSettings` already pinned the order; mutation recorded.
    - `[low]` `[reject]` the three "cannot be read" branches of `State` have no test — a read fails only with no active production or no Decide item, and then `Precheck` does not run; a test needs a production argument on `State`, which is new public surface.
    - `[medium]` `[patch]` a failure Reply's host data and taint were checked only at their defaults — fixed: the scenario `context-probe-fail` and `TestFailureKeepsContext`; mutation recorded.
    - `[low]` `[reject]` the fail-open branches of `Keys` are never exercised — no seam provokes a director or Config Store error; the branches follow decision 7 and read right by inspection.
    - `[low]` `[patch]` no `mutation:` line names `TestRunnerErrorIsFallback` — recorded (`OnError` returns the status).
    - `[low]` `[patch]` AC5's pinning test `TestCatalogMap` had no demonstrated red — recorded (a `FALLBACKREASON` value the catalog does not know).
    - `[low]` `[reject]` sub-clauses with no mutation line of their own (the 403, "sends nothing but", AC6's `ErrorRows`, AC8's invalid settings) — Rule 19 asks for one demonstrated mutation per AC, and each AC has at least one.
    - `[low]` `[reject]` the pre-story stub (`Status` always 0) leaves `TestStartsWithNoKey` green — the AC6 mutation (`Present` always 1) is red there, and the stub's case is red in every test that points the keys.
    - `[low]` `[patch]` `$$$AssertTrue(1, ...)` in `TestPresentEntry` — same root as the Blind Hunter's tenth finding; fixed.
    - `[low]` `[reject]` `(x = 0) || (x = 1)` after an equality to 0 or 1 adds nothing — redundant, not misleading.
    - `[low]` `[patch]` `RunnerFixture.ErrorRows` ignores a failed statement, so the "no error row" assertion could pass without a query — fixed: a failed statement gives one row that says so.
    - `[low]` `[reject]` `TestPrecheckLogs` asserts absolute warning counts, which an unpriced row left by another test would change — it holds on a fresh environment in either order (the standing criterion), and a leftover would fail loudly.
    - `[low]` `[reject]` `Keys.TestStatus` reads the installed `ProviderConfig` rows — it reads and writes nothing of its own.
    - `[low]` `[reject]` `OnAfterOneTest` ignores the restore statuses — same root as the Blind Hunter's ninth finding.
    - `[low]` `[patch]` stale `Saved` comment in `Test.Bridge.Budget` — fixed.
  - Intent Alignment:
    - `[medium]` `[defer]` the cut-off tool call: the diff pins the opposite of the row's last sentence — same root as the Blind Hunter's eighth finding (deferred item 1).
    - `[medium]` `[patch]` `Details` is a sibling reader and `Merge` does not share it — same root as the first finding; fixed.
    - `[low]` `[reject]` `Classify` with a missing `text` fact gives "" (decision 16) — a documented choice between two statements of the contract.
    - `[false]` `[reject]` "The bridge alone" has no test — `release/standalone-bridge.sh` is a `## Verification` command, unchanged, and passes; the example's `ProviderConfig` reads as present.
    - `[false]` `[reject]` the catalog map pins Lane B's existing state — that is AC5's Integration AC by design.
    - `[low]` `[reject]` the live `OnError` test shows only the default reason `error` — `TestOnErrorFallback` covers the texts of the other reasons through `OnError` then `OnResponse`.
    - `[low]` `[reject]` only the `BuildAgent` failure before `Chat` is tested in `TestFailureTextRedacted` — a refused request and an unbuilt kind keep their status in `TestUnbuiltKinds`, and `NewSession` and `Context.Begin` precede the `Try` that catches `Chat`.
    - `[false]` `[reject]` the timer path is not re-pinned — `TestTimer` is unchanged as the spec says, and the timer branch of `OnResponse` still comes first.

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** `Keys`, `Budget`, `Decide` and the adapter name no other package. The bridge alone still records its decision.
- **AD-5:** the Storage blocks only grow: `Reply` gains slot 10 and `Decide` slot 8.
- **AD-6:** the pipeline, the runner's answer, a start with no key, and `Keys.Status`.
- **AD-8:** the whole classification.
- **AD-9:** the steps of a failed call.
- **AD-19:** keys come from the environment only; the budget host settings.
- **AD-20:** the prechecks, the daily cap, `MarkCapped`, and a fallback's totals.
- **AD-22:** the mock scenarios under `A/`; CI forces every fallback reason; the start with no key.
- **AD-26:** `Fallback` and `FallbackReason` in the trace.
- **AD-28:** a fallback carries no host data.
- **AD-30:** `Decide` answers only its caller.
- **AD-31:** `FireEvent`, and `budget.capped` through the host sink.
- **AD-33:** no new item, table or event type.

No acceptance criterion contradicts an AD's Rule.

**Decided in-stage:**
1. **AD-8's branches that later stories own.**
   - **Built here.** `Classify` holds AD-8's whole text mapping. A rate-limit failure is `rate_limited`, which falls back at once, as AD-8 says; Story 1.7 adds the re-send. The provider's `operation timed out` is `timeout`.
   - **Not built here.**
     - The bridge timer stays an error until Story 1.7 makes it `timeout`, because that is Story 1.7's AC.
     - `Invalid input` stays `error` until Story 1.8 sets `SessionBroken`.
   - **The cost.** Until Story 1.7, a 529 says "the model was busy and retries ran out" although AI Hub never retries a 529. This is honest for a 429, which AI Hub retries three times (S2). It ends within this epic, before any release.
2. **The token budget per decision** means the estimated size of the request. The estimate is the request's own texts at 4 characters a token. A request whose estimate is above the setting falls back with `budget`. The setting is new, defaults to 0 (off, like the daily cap on a local install; FR-40's admin page is step 2), and is read as `Decide`'s own property, like `TimerSeconds`, so a change applies when `Decide` restarts. Story 1.9 adds the system prompt, the tool schemas and the history. Story 1.7's re-sends and step 2's second-model retry may count the decision's earlier attempts.
3. **The precheck runs after the settings check.** A misconfigured `Decide` stays an error and is never hidden behind `no_key`. So a `diagnose`, which `DiagnosisAgent` cannot answer until Epic 5 gives it a `ReplyClass`, stays a configuration error with no key too (`TestDiagnoseNeedsReplyClass`). The no-key test sends a decide and a turn.
4. **DW-76: the cap fails open, with each fault logged.**
   - **Why not fail closed.** The only reasons a fail-closed cap could show are `daily_cap` ("today's cost limit has been reached") or `error`, and both would be false. The online demo's gateway enforces the cap on its own (AD-25). A local install's cap is off by default.
   - **What the precheck logs.** One warning per fault per decision while the fault lasts. The faults about the gateway and about unpriced rows matter only when they can change whether the day is capped.
5. **A failed `Chat` becomes a failure `Reply`** with `FailureText`, because Ens passes no body with an errored response (1.5's decision 6). A failure before `Chat` keeps its error status, which `OnError` classifies; it has no steps.
6. **A fallback row keeps no reasons, confidence or payload.** The reason is the `FallbackReason`, and the catalog words it. The bridge writes no user text. A fallback `Reply` is new, not a clone, so no model text or check row can ride on it. `Tainted` is kept, because session rotation after untrusted content is the safe direction.
7. **`Keys.Status`'s `agent` is the runner item's name**, as `Test.Bridge.Api` already calls it and `Decide` knows it (`RUNNERS`). It reports 0 only when it can tell the key is missing. A form the bridge does not read counts as present, so the precheck never blocks a configuration it cannot judge; the runner's failure text is classified then (`no_key` included).
8. **`empty` against `unusable`.** An empty text is `empty` only when the provider reported a stop reason. With none, the reason is `unusable`, so a provider without stop reasons always shows the generic reason. Task 0 (c) confirms that the Anthropic path reports one.
9. **Every `max_tokens` reply is `cut_off`** (NFR-5: a cut-off reply is never treated as an answer), as Story 1.3's check already did.
10. **A filter that leaves nothing is `invalid`**: the reply is not one that can be used, and the generic reason is true.
11. **`EmitSteps` moves before `ReplyClassOf` in `OnResponse`.** This closes 1.5's occurrence on DW-83, a reply whose `ReplyClass` lookup fails.
12. **The live fallback tests extend `Test.Agent.Decide`**, which holds `Prepare`, the row clean-up and the restart of `Decide`, rather than copying them into a new class. The DW-83 and cut-off tests extend `Test.Agent.Steps`, which already swaps `ChatAgent` to `StepsAgent`.
13. **`steps-loop.json` holds six replies with six topics, not one repeated topic (Task 0 (a); Rule: decide small).** Measured on build 154: a loop of identical, successful tool calls does not end in an error. After two identical tool results AI Hub appends the user message "You appear to be repeating tool calls without gaining new information" (it holds no marker), the mock answers that request from `ChatAgent`'s default script, and the turn ends with the text "The CI mock looked at the productions." and `end_turn`. With a new topic in each reply the results bring new evidence, no nudge comes, and `Chat` throws `<%AICore>MaxIterationsReached` after the 4 iterations, with four model steps and four tool steps. The scenario keeps its name, its marker and the tool `zz_steps_note`; only the topic changes from reply to reply (status, uptime, queues, errors, alerts, journal).
14. **`ITERATIONCODES` holds two codes (Task 0 (a)).** The `tool-loop` scenario on `ChatAgent` raises `<%AICore>LoopDetected` ("Agentic loop stalled: no new evidence from tool results after 4 assessment(s)"), not `MaxIterationsReached`, and both end a turn in AI Hub's loop. The parameter is `<%AICore>MaxIterationsReached,<%AICore>LoopDetected`, and AC1's `tool-loop` row is `unusable` through `LoopDetected`.
15. **A runner error status needs the default model family out of the way (Task 0 (d)).** A `Model` row of `zz-no-such-model` alone fails nothing: the `default` row of `ModelFamily` has the empty prefix and matches every model, and the mock accepts any model. `TestRunnerErrorIsFallback` therefore also takes the `default` row out for its run and `OnAfterOneTest` writes it back. With no matching family `NewSession` fails with "No ModelFamily row matches the model", the runner answers an error status, `OnError` keeps it and `OnResponse` records the `error` fallback in 0.3 s.
16. **`Classify` applies the empty-text rule only when a `text` fact is there.** "A missing fact counts as false or empty" and "no facts give ''" together mean that a request with no reply to judge is not an empty reply. `Conclude` always sets `text` for a `Reply`, and a reply that is not a `Reply` is a failure.
17. **`Conclude`'s check is a private method, `Interpret`.** It holds the decide-and-diagnose half (`CheckReply`, the filter on each reason, the user rule, the payload), so that `Conclude` stays one flow: facts, `Classify`, fallback or usable. It runs on any non-blank text, also a refused one, and its result is only `invalid`, never stored.
18. **Budget faults: which are unconditional.** The unreadable or invalid `DailyCostCapUSD`, `GatewaySpendUSD` and `GatewaySpendDate` each give a line whatever the cap (the Boundaries list them without a condition); only the unpriced-model lines need a cap above 0 (the row "Budget faults" 5). An empty value is no fault. The models are listed as written (`%EXACT`), because a query collates them to capitals.
19. **`DecisionTokenBudget`: an empty value counts as 0 without a warning;** a value that is not made of digits only (`-1`, `abc`, `1.5`, `5e1`, `1,000`, a leading space) counts as 0 and is one warning from `Precheck`.
20. **`Keys.Status` answers 0 for an unreadable setting only when the item or the production is missing** (`Ens.Director` returns the error `<Ens>ErrConfigItemNotFound`, or there is no active production). Any other error counts as present, like every form it cannot judge (decision 7).
21. **`RunnerFixture.PutDefault` writes the row with SQL when the validated save refuses it.** The save of a provider configuration expands it, so a configuration that names an unset variable, a missing entry or text that is not JSON cannot be saved, and the `Keys` tests need exactly those. It is test code only.
22. **`TestCutOffToolCall` pins what was measured (Task 0 (e)), not "never a usable answer".** AI Hub runs a tool call that the provider cut at the output cap and goes on: the second request carries the tool's result and `Chat` returns that later reply with `end_turn`. The turn is answered with the later text and no fallback, and the bridge cannot tell, because it sees the stop reason of the last response only (`StepRenderer.OnMessage` gets the text and nothing else). This does not meet the row's "never a usable answer" in the wording of the specification and is reported for the lead's ruling; the cut-off reply itself is never an answer, as a tool use has no text.
23. **`Keys.Present` judges an entry that cannot be read by `Exists`, not by the error text.** A failed `ConfigStore.Details` is absent only when `%ConfigStore.Configuration.Exists` says the entry is not there; any other failure counts as present (decision 7).
24. **`ConfigStore.Merge` reads through `Details`** (Rule 2). The text of a missing entry names the class and the entry; `Merge`'s tests only pin that it names the entry.

**Integration ACs (Rule 1):**
- **AC3:** `Budget.State` reads the day's mark that the 403's fallback set, and the next decision falls back before sending, through the running production and the mock.
- **AC5:** Lane B's real catalog renderer reads each bridge reason.
- **AC7:** `Decide` reads the failure `Reply`'s `Steps` and produces the `AgentStep` messages.
- **The bridge alone:** its `Decide` reads `Keys.Status` of an inline `ProviderConfig` and records the example decision.

**Consumed-by:**
- **Story 1.7:** `Classify` gains the timer's `timeout`; the re-send reads `ToolsRun` before falling back on `rate_limited`.
- **Story 1.8:** the `Invalid input` branch sets `SessionBroken`.
- **Story 1.9:** `too_large` after `budget`, and `EstimateTokens` gains the system prompt, the tools and the history.
- **Story 2.4 (Lane B):** `Conversation` renders a fallback `Reply`'s reason.
- **Story 2.6 (Lane B):** `BridgeSink` gets `budget.capped` and the first `daily_cap` in `decision.recorded`.
- **Story 2.10 (Lane B):** `StatusMonitor`'s `noModelKey` comes from `Keys.Status` of the three runner items.
- **Epic 5:** `IncidentManager` takes a fallback diagnosis as `tellnow`.
- **Story 13.1:** the example's `budget`, `no_key` and `timeout` fallbacks.
- **Story 17.4:** the admin's token budget and cap, through the bridge.
- **Story 29.3 (the gateway):** its 403 body keeps the measured form.

**Consumes:**
- **Story 1.3:** `Decide` and its helpers.
- **Story 1.4:** `Budget.State`, `MarkCapped`, `Usage.Totals` and `RecordUsage`.
- **Story 1.5:** `StepBuffer`, `EmitSteps`, `Redact` and `Test.Agent.Steps`' swap.
- **Story 1.1:** the Provider step's placeholder and `ConfigStore`.
- **Story 1.2:** the runner and `RunnerFixture`'s keys.
- **Lane B, read only:** `OcuTalon.Msg.Catalog.Render` and `Entry`, and the mock.

**Extend, don't copy (Rule 2):**
- **The row.** `NewRow` serves both `Conclude` and `RecordFallback`, and `Record` and `FireEvent` are reused.
- **The config read.** `ConfigStore.Details` serves `Merge` and `Keys`.
- **Cutting and estimating.** `StepBuffer.Part` and `Tokens` are reused for the failure text and the estimate.
- **`Budget.State`** gains an output rather than a second method.
- **The fixture.** `RunnerFixture`'s item-setting swap generalizes `ChangeAgent`, and `Test.Bridge.Budget`'s settings snapshot moves there rather than being copied.
- **The probes.** `ProbeSink` gains a mode, and `StepsAgent` gains `MaxIterations` as `Chat` has it.

**Ledger:**
- **DW-76** is addressed by AC8: the `Budget.cls` and `Decide.cls` tasks and the rows "Budget faults" and "The precheck logs".
- **DW-83** is addressed by AC7: the `Adapter/Agent.cls` and `Reply.cls` tasks and the rows "A failed turn's steps" and "The runner's failure reply".
- **U-16's bullet** is addressed by AC3: the row "Both daily-cap paths".

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles and process-local facts only. No test class runs there.
- **Throwaways.**
  - Everything else goes through `ci/iris.sh` or the script, with `OCUTALON_RUN_TAG=e1s6a OCUTALON_LOCK_OWNER='epic=1 stage=implement'`. QA uses `e1s6q` and review `e1s6r`.
  - One stack at a time, one command per call, each with `timeout: 600000`.
  - Run `ci/iris.sh teardown` with the same tag at the end.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or `ocutalon-slot-b`. No push and no `gh workflow run`. Never read `.env`.

**Commands** (each prefixed with the tag and lock owner where it starts a stack):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, including the storage check, the bridge-references check and the boundaries check (ASCII, no key-like string). About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Bridge.Fallback`, `.Bridge.Keys`, `.Bridge.Decide`, `.Bridge.Budget`, `.Bridge.Runner`, `.Bridge.Contracts`, `.Bridge.Api`, `.Bridge.Example` and `.Bridge.CodeRules`;
  - `.Agent.Decide`, `.Agent.Steps` and `.Agent.Runners`.

  Expected: `CLASS ... passed`.
- **(loop)** `bash release/standalone-bridge.sh`. Expected: every check `PASS`, the decide check with `fallback 0`, and exit 0.
- **(loop)** `bash ci/iris.sh shard lane-a`. Expected: every class passed, and the only SKIP is the existing `TestStepHelpers` one.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s6a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass with the four new scenarios.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passed, `Test.Contract.Ac` (the `Reply` superset, the `Keys` and `Budget` signatures) and `Test.Msg.Catalog` included.
- **(once)** `bash ci/iris.sh live storage-roundtrip`. Expected: PASS, with the `Reply` slot 10 and `Decide` slot 8 blocks equal to the compiled ones.
- **(once)** `bash ci/iris.sh live production`, then `live production-restart`, one per call. Expected: PASS, with a clean start: no Type 2 or 6 row, and every item runs.
- **(once)** `bash ci/iris.sh live install-upgrade`. Expected: PASS, with the appended slots over an earlier install.
- **(once)** `bash ci/iris.sh live compose-start`, then `live demo-path`, one per call. Expected: PASS: no key, the `@floor` test passes.
- **(once)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s6a`'s projects.

**Shared surfaces:**
- **What `Decide` answers to an unusable reply:**
  - `Test.Agent.Decide` (`TestUnusableEndsWithError`, `TestCostOfFailedTurn`'s steps) and `Test.Bridge.Decide` (`TestReplyCheck`, `TestFilterBlanks`).
  - Search the test trees for `AssertStatusNotOK` around `Decide`, `Conclude` or `OnResponse`.
  - A pure test that calls `OnRequest` with valid settings now meets the precheck (`Keys.Status` of the runner). Search `Test.Bridge` for `OnRequest`.
  - Lane B's `Conversation` tests use a test double.
- **The runner's answer to a `Chat` that threw:** `Test.Bridge.Runner`'s three tests. `TestBuildRetried` and `Test.Agent.Runners`' direct runner sends keep their error status.
- **`Reply`'s contract and Storage:** `Test.Bridge.Contracts`, `TestNewBusy`, `storage-roundtrip`, and Lane B's `Test.Contract.Ac` (a superset check).
- **`Decide`'s settings and Storage:** `Test.Bridge.Example.TestDecideDefaults`, `storage-roundtrip`.
- **`Keys.Status`:** `Test.Bridge.Api.TestNeutralValues`.
- **`Budget.State`:** its signature, which the oracle pins as a prefix, and its JSON, which `Test.Bridge.Budget:109` pins and which does not change.
- **Today's `^OcuTalonBP.UsageCapped` mark.** A test that leaves it makes every later decision of the shard fall back. Clean it in every test that can set it.
- **Production state while a test runs:**
  - `Decide`'s `HostSinkClass`, in the stored configuration, during `TestDailyCapBothPaths`;
  - `ChatAgent`'s `Model` row during `TestRunnerErrorIsFallback`;
  - the `Decide` rows `TimerSeconds`, `DecisionTokenBudget`, `DailyCostCapUSD`, `GatewaySpendUSD` and `GatewaySpendDate`.
- **The mock's scenario set:** four new files.
- **`ProbeSink`'s shared mode** and `^OcuTalonTest("ProbeSink")`.
- **The event log:** new Type 3 warnings only.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19)**, one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `Classify` drops the `finishReason` rules | `Agent.Decide.TestReplyFallbacks` (refusal, cut_off), `Bridge.Fallback` |
| AC1 | `ITERATIONCODES` is empty | `Agent.Decide.TestCostOfFailedTurn` (gives `error`), `Bridge.Fallback` |
| AC1 | `invalid` is checked before `empty` | `Bridge.Fallback` (the empty decide) |
| AC2 | `Precheck` returns "" | `Agent.Decide.TestPrechecks`, `Agent.Runners.TestStartsWithNoKey` |
| AC2 | The precheck fallback still sends the request | `Agent.Decide.TestPrechecks` (a mock request with the ref) |
| AC3 | `RecordFallback` does not call `MarkCapped` | `Agent.Decide.TestDailyCapBothPaths`, `Bridge.Decide.TestMarkCappedWiring` |
| AC3 | `MarkCapped` is called before the row is saved | `Bridge.Decide.TestMarkCappedWiring` (no row when the event fires) |
| AC4 | The turn fallback is a clone of the runner's reply | `Agent.Decide.TestTurnFallbackIsReplyOnly` |
| AC4 | `Fallback` is not set on the row | `Agent.Decide.TestReplyFallbacks` (the XML), `Bridge.Decide.TestConcludeFallbacks` |
| AC5 | Empty text with no `finishReason` gives `empty` | `Bridge.Fallback` (the generic reason) |
| AC6 | `Keys.Present` ignores the environment (always 1) | `Bridge.Keys`, `Agent.Runners.TestStartsWithNoKey` |
| AC7 | `Answer` re-throws as before | `Agent.Steps.TestFailedTurnSteps`, `Bridge.Runner.TestChatErrorIsFailureReply` |
| AC7 | `FailureText` is not redacted (`Cut` instead of `Part`) | `Bridge.Runner.TestFailureTextRedacted` |
| AC8 | `State` reports no fault for unpriced rows | `Bridge.Budget.TestFaults`, `Bridge.Decide.TestPrecheckLogs` |

**Measured in implementation** (Task 0; build 154; the slot `ocutalon-slot-a` for the process-local facts and the throwaway `e1s6a` for the rest; 2026-10-22). The failure texts are the `FailureText` of the runner's `Reply` (the status text of the same call before this story's change).
- **(a) Maximum iterations.**
  - `tool-loop` on `ChatAgent`: `Chat` throws `ERROR <%AICore>LoopDetected: Agentic loop stalled: no new evidence from tool results after 4 assessment(s)`. The code is `<%AICore>LoopDetected`. The mock saw three requests (two by the marker, one by `ChatAgent`'s default script after AI Hub's nudge "You appear to be repeating tool calls without gaining new information"); 3 buffered model steps (calls to a missing tool are not audited), `AgentStepCount` 6.
  - `steps-loop` as first specified (always `{"topic":"status"}`) on `StepsAgent`: `Chat` returns, with `end_turn` and the text "The CI mock looked at the productions." after the nudge (4 requests, 7 steps). Neither code is raised.
  - `steps-loop` with six topics (decision 13): `ERROR <%AICore>MaxIterationsReached: Max iterations (4) reached without a final response`; 8 steps (model, tool, four times), the tool steps labelled `Reading the test note` with the status `ok`; `AgentStepCount` 8.
  - `Decide.ITERATIONCODES` is `<%AICore>MaxIterationsReached,<%AICore>LoopDetected` (decision 14).
- **(b) The gateway's 403** (scenario `daily-cap`, Anthropic's error shape, `permission_error`): `ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: Authentication failed: daily cost cap reached`. It holds `daily cost cap reached`, so the plain-text body was not tried. One request reached the mock: AI Hub does not send a 403 again.
- **(c) The reply shapes** (`ChatAgent` turns; Triage the same for `empty`): `refusal` gives `FinishReason` `refusal` with the text "The CI mock refuses this request."; `max-tokens` gives `max_tokens` with a text of 50 characters; `empty` gives `FinishReason` `end_turn` (not empty) and a `Text` of length 0. An empty reply therefore carries a stop reason on the Anthropic path.
- **(d) `OnError`.**
  - **Setup:** the `default` family row was taken out (decision 15). `NewSession` fails ("No ModelFamily row matches the model 'zz-no-such-model'"), the build does not, and nothing reached the mock.
  - **Ens:** the header `ChatAgent` to `Decide` has `IsError` 1 and no body class. Ens calls `OnError`, and when it returns OK it calls `OnResponse` with the key `reply`, and with `callresponse` empty (not an object). `OnResponse` read `callrequest.DecisionRef` as usual.
  - **Timing:** the process completed with the answer after 0.3 s. The header `Decide` to `Ens.Alarm` stayed Delivered until the timer's 6 s were over, and then completed with a discarded `AlarmResponse` (read in a normal run with `TimerSeconds` 6; the error run was read for 0.3 s only).
  - **Implemented:** `OnError` keeps the status and `OnResponse` classifies and records it.
- **(e) `cut-off-tool`** (`StepsAgent`): `Chat` runs the tool and goes on. The mock got two requests; `Chat` returned `end_turn` with "The CI mock answered after the cut."; 3 steps (model, tool `Reading the test note` with `ok`, model); `AgentStepCount` 3. Decision 22.
- **(f) The environment in the jobs.** `/proc/<pid>/environ` of the jobs of `Decide`, `TriageAgent`, `DiagnosisAgent` and `ChatAgent` holds `OCUTALON_MOCK_KEY_HEADER` (length 1), `PATH` (length 54) and no `ANTHROPIC_API_KEY`; the test process gives lengths 1, 80 and 0 for the three through `GetEnviron`. `Keys.Status` of the three runners is 0, 0, 0 in the test process with the entries at the placeholder and 1, 1, 1 after `PointKeys`; `Decide`'s own job agrees: it records `no_key` in `TestStartsWithNoKey` and passes the precheck in every test that points the keys. (The jobs' variables were read from `/proc`, which is the environment that `GetEnviron` reads.)
- **(g) `Redact.Text`** leaves the 403 text, the missing-key text (with `@{env:ANTHROPIC_API_KEY} has no value`), the 529 text and the `LoopDetected` text as they are; the secret scenario's text becomes `... [api_error] CI mock: the provider failed. Authorization: [redacted]`.
- **(h) The XML** of a `refusal` fallback `DecisionResponse`: `<DecisionResponse><DecisionRef>..</DecisionRef><Outcome>tellnow</Outcome><Reasons></Reasons><Fallback>true</Fallback><FallbackReason>refusal</FallbackReason><InputTokens>376</InputTokens>..<DurationMs>118</DurationMs><CostUSD>.000045</CostUSD><Model>claude-haiku-5-5</Model><Payload></Payload></DecisionResponse>`. Of a `refusal` fallback `Reply`: `<Reply>..<Fallback>true</Fallback><FallbackReason>refusal</FallbackReason>..<Text></Text><Tainted>false</Tainted><SessionRotated>false</SessionRotated><ToolsRun>false</ToolsRun><SessionBroken>false</SessionBroken><Busy>false</Busy><HostData></HostData><FinishReason></FinishReason><Steps></Steps><FailureText></FailureText></Reply>`.
- **Other facts.** The two `intent gap` conditions of Task 0 (the 403 text, an empty `FinishReason`) did not occur. Decisions 13, 15 and 22 are the places where a premise of the specification did not hold.

**Verified** (all from the worktree, in throwaways of the tag `e1s6a`, one command per call):
- `bash ci/checks.sh`: every block passes. `bash docker/tests/test-mock.sh`: 94 pass.
- `ci/iris.sh shard lane-a`: 31 classes passed, forward and with `--reverse`, the only SKIP being `TestStepHelpers`. `ci/iris.sh shard lane-b`: 24 classes passed.
- `release/standalone-bridge.sh`, `live storage-roundtrip` (57 classes, with `Reply` slot 10 and `Decide` slot 8), `live production`, `live production-restart`, `live install-upgrade`, `live compose-start` and `live demo-path`: all pass.
- **After the review patches** (the same tag, one command per call): `bash ci/checks.sh` and `ci/iris.sh build` pass; each of the 12 classes of the (loop) list passes alone; `release/standalone-bridge.sh` passes; `shard lane-a` passes (31 classes, the only SKIP being `TestStepHelpers`); then, once, `docker/tests/test-mock.sh` (94 pass), `shard lane-b` (24 classes), `live storage-roundtrip` (57 classes), `live production`, `live production-restart`, `live install-upgrade`, `live compose-start` and `live demo-path` all pass, and `ci/iris.sh teardown` left nothing of the tag.

**Mutations demonstrated (Rule 19).** Each was applied to the worktree and the test run in a throwaway; the files were then put back, and `git status --short`, `git diff --stat` and a checksum of the diff and of the untracked files were identical to what they were before. Mutations 1, 2, 3 and 10 were applied together, and so were 7, 8, 9 and 14 and 11 and 12, each attributed by the text of the failed assertion.
- mutation: `Classify` drops the `finishReason` rules -> red: `Test.Bridge.Fallback.TestEachFactAlone` (refusal, cut_off), `Test.Agent.Decide.TestReplyFallbacks` (refusal and max-tokens)
- mutation: `ITERATIONCODES` is empty -> red: `Test.Bridge.Fallback.TestMeasuredTexts`, `Test.Agent.Decide.TestCostOfFailedTurn` (gives `error`)
- mutation: `invalid` is checked before `empty` -> red: `Test.Bridge.Fallback.TestOrder` ("an empty text before invalid")
- mutation: `Precheck` returns "" -> red: `Test.Agent.Decide.TestPrechecks`, `Test.Agent.Runners.TestStartsWithNoKey`, `Test.Bridge.Decide.TestOnRequestPrecheck`
- mutation: the precheck fallback still sends the request -> red: `Test.Agent.Decide.TestPrechecks` (a mock request with the ref), `Test.Bridge.Decide.TestOnRequestPrecheck`
- mutation: `RecordFallback` does not call `MarkCapped` -> red: `Test.Agent.Decide.TestDailyCapBothPaths`, `Test.Bridge.Decide.TestMarkCappedWiring`
- mutation: `MarkCapped` is called before the row is saved -> red: `Test.Bridge.Decide.TestMarkCappedWiring` (budget.capped comes before decision.recorded)
- mutation: the turn fallback is a clone of the runner's reply -> red: `Test.Agent.Decide.TestTurnFallbackIsReplyOnly`, `Test.Bridge.Decide.TestConcludeFallbacks`
- mutation: `Fallback` is not set on the row -> red: `Test.Agent.Decide.TestReplyFallbacks` (the XML), `Test.Bridge.Decide.TestReplyCheck`
- mutation: empty text with no `finishReason` gives `empty` -> red: `Test.Bridge.Fallback.TestEachFactAlone`, `TestEmptyText`
- mutation: `Keys.Present` ignores the environment (always 1) -> red: `Test.Bridge.Keys.TestPresent`, `Test.Agent.Runners.TestStartsWithNoKey`
- mutation: `Answer` re-throws as before -> red: `Test.Agent.Steps.TestFailedTurnSteps`, `Test.Bridge.Runner.TestChatErrorIsFailureReply`
- mutation: `FailureText` is not redacted (`Cut` instead of `Part`) -> red: `Test.Bridge.Runner.TestFailureTextRedacted`
- mutation: `State` reports no fault for unpriced rows -> red: `Test.Bridge.Budget.TestFaults`, `Test.Bridge.Decide.TestPrecheckLogs`
- mutation: `OnError` returns the runner's error status instead of OK -> red: `Test.Agent.Decide.TestRunnerErrorIsFallback` (AC4)
- mutation: `OnRequest` sends the runner request twice -> red: `Test.Agent.Decide.TestReplyFallbacks` (every marker: "sends the runner one request, never a second") (AC4)
- mutation: `Answer` drops the taint and the host data of a failure Reply -> red: `Test.Bridge.Runner.TestFailureKeepsContext` (AC7)
- mutation: `OnRequest` runs the precheck before the settings check -> red: `Test.Bridge.Decide.TestOnRequestPrecheck`, `TestOnRequestUsesItsSettings`, `TestOnRequestAnswersRecorded`
- mutation: a `FALLBACKREASON` value that the catalog does not know (`cut_off` written `cutoff`) -> red: `Test.Bridge.Fallback.TestCatalogMap` (AC5), `TestPure`

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **`Reply.FailureText`:** a new stored message property, slot 10, appended (a schema append). It holds a redacted failure text of at most 2,000 characters in the runner's reply (decision 5).
- **`Decide.DecisionTokenBudget`:** a new host setting and stored business-process property, slot 8, default 0, off (decision 2).
- **DW-76 (a money posture):** a set daily cap fails open on an unpriced model or an unreadable budget setting, and the precheck logs each fault (decision 4).
- **`Keys.Status`' reading of the environment (secret handling):** it tests for presence with `$SYSTEM.Util.GetEnviron` in the production job, and never returns, logs or stores the value. A form it cannot read counts as present (decision 7).
- **How failures show:** a `Chat` that throws now leaves the runner's message Completed, with a warning, instead of Errored (decision 5).

**For the lead (ruling recommended, not blocking):**
- **Decision 1.** AD-8's `rate_limited` and the provider's `timeout` texts are classified here; the timer stays Story 1.7's, and `SessionBroken` Story 1.8's.
- **Decision 3.** The precheck comes after the settings check, so a diagnose with no `ReplyClass` stays a configuration error even with no key.
- **Decision 6.** A fallback row has empty `Reasons`.
- **Decision 7.** `Keys.Status`' `agent` is the runner item's name. Lane B's Story 2.10 (`StatusMonitor`) calls it that way.
- **Story 29.3.** The gateway's 403 body follows the form that Task 0 (b) measures. That story is outside this repository, and the dependency is recorded here only.

**Ruled at spec validation** (Epic 1 runner, 2026-10-22, unattended; the owner may reverse a veto ruling through the inbox):
- **`Reply.FailureText`, `Decide.DecisionTokenBudget`, and a thrown `Chat` showing Completed with a warning:** `category=veto`, kept as planned (inbox U-25).
- **DW-76, the cap fails open with each fault logged:** `category=veto`, kept as planned (inbox U-26).
- **`Keys.Status` tests presence only and never returns, logs or stores the value:** `category=decide`, kept; the criterion requires "without revealing any value".
- **Decision 1 (`rate_limited` and the provider's `timeout` text classified here):** `category=decide`, kept. Until Story 1.7 adds the re-send, the `rate_limited` reason's text overstates what ran, but Epic 1 merges to the feature branch as a whole, after Story 1.7, so no build anyone runs shows that interim state.
- **Decisions 3, 6 and 7, and the Story 29.3 dependency:** `category=decide`, kept as planned. A diagnose without a `ReplyClass` is a configuration error before any precheck (Story 1.3's ruling); a fallback's reasons are rendered by Lane B's catalog, not stored; `Keys.Status` takes the runner item name, as Story 2.10 calls it; the 403's text is the one AD-8 and the criterion fix, measured in Task 0 (b).

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** An unusable reply, a runner failure and a failed precheck now take the fallback route in `OcuTalon.Bridge.Process.Decide`. `Classify` picks the one `FallbackReason` in AD-8's order. `Precheck` runs after the settings check and before any send (`no_key` through `Keys.Status`, `daily_cap` through `Budget.State`, and `budget` through the new `DecisionTokenBudget` setting). `RecordFallback` records `tellnow` with `Fallback` 1 and the reason, answers a turn with a text-free `Reply`, and marks the day capped once for `daily_cap`. A `Chat` that threw is answered by the runner with a failure `Reply` (`FailureText`, the steps, the usage), so its steps reach Visual Trace (DW-83). `Budget.State` names the faults of a set cap, and `Precheck` logs them (DW-76).

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `Classify`, `Precheck`, `EstimateTokens`, `RecordFallback`, `NewRow`, `Interpret`, `OnError`, the reworked `OnRequest`, `OnResponse` and `Conclude`, the five literal parameters, `DecisionTokenBudget` (slot 8); `CheckReplyShape` removed.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: the failure `Reply` of a thrown `Chat`, with one warning.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`: `FailureText` (slot 10) and `MAXFAILURE`.
- `src/bridge/cls/OcuTalon/Bridge/Keys.cls`: `Status` and `Present` (presence only, never a value).
- `src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`: `Details`, which `Merge` and `Keys` share.
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls`: the `faults` output of `State`, `Setting` returns its status, `UnpricedModels`.
- `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`: doc only.
- `ci/mock/scenarios/A/`: `daily-cap`, `steps-loop`, `cut-off-tool`, `provider-error-secret` and `context-probe-fail`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/`: new `Fallback` and `Keys`; changed `Decide`, `Budget`, `Runner`, `Contracts`, `Api`, `Example`, `ConfigStore`, `ProbeSink`, `StepsAgent` and `ZzStatsAdapter`.
- `src/ocutalon/cls/OcuTalon/Test/Agent/`: changed `Decide`, `Steps`, `Runners` and `RunnerFixture`.

**Review.** 48 findings: high 0, medium 8, low 36, false 3, maybe-false 1 (see the Review Triage Log). Patches applied: 18 findings in 13 groups. In short:
- `ConfigStore.Merge` reads through `Details`, and the `Details` doc is corrected;
- `Keys.Present` finds an absent entry by `Exists`, not by an error text;
- the `UnpricedModels` warning is redacted;
- the one-request assertions are back in the five fallback tests;
- `TestFailureKeepsContext` and the scenario `context-probe-fail` pin the taint and host data of a failure `Reply`;
- the bad-setting case of `TestOnRequestPrecheck` also fails the prechecks, so it pins the order;
- `ErrorRows` cannot pass on a failed statement;
- a vacuous assertion, a missing guard and a stale comment are fixed;
- five `mutation:` lines were added.

Deferred: 2 items, in the frontmatter (the cut-off tool call that AI Hub continues, and the `Usage` scan in every `Precheck`). Rejected: 27, each with its reason in the log.

**Follow-up review recommended: true.** Three medium entries were patched after the review layers had read the diff (the `Merge` and `Details` refactor, the restored one-request assertions, and the failure-reply taint test), together with the `Keys.Present` rewrite, and no second layer has read those patches. Patched counts by verdict: medium 3 entries (6 findings), low 12 findings.

**Verification.** See `## Verification`, "Verified": every (loop) command and every (once) command passed on the patched tree; 14 recorded mutations from the first pass and 5 more after the review were each applied, seen red, reverted, and the tree checked byte-identical.

**Needs the lead's ruling (not blocking).**
- The matrix row "A cut-off tool call" ends "Never a usable answer", and AI Hub does not allow it: it runs a tool call that the provider cut at `max_tokens` and goes on, and `Chat` returns the later reply with `end_turn` (decision 22, Task 0 (e)). `TestCutOffToolCall` pins what was measured. The row needs an amendment (a wording that says the cut-off reply is never an answer, and that a cut-off tool call is run by AI Hub), or an AI Hub change that reports each response's stop reason. Deferred item 1.
- Decision 13: `steps-loop.json` holds six replies with six topics, because AI Hub's loop detector ends a loop of identical tool results with a usable text and no error.

**Residual risks.**
- The `Usage` table is scanned on every decision (deferred item 2).
- `Keys.Status` reads a runner's `ProviderConfig` only: a runner that takes its key from `ProviderName` or an agent class parameter, or a keyless provider, counts as having no key (spec-bound; reopen_if either is supported).
- The pending timer after an error-status fallback was measured for 0.3 s only (Task 0 (d)); the normal path shows it completing after its seconds with a discarded response.
