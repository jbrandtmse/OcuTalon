---
title: 'Story 1.7: Timeouts and rate limits end every decision on time'
type: 'feature'
created: '2026-10-22'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-5, AD-6, AD-7, AD-8, AD-9, AD-19, AD-20, AD-22, AD-23, AD-26, AD-30, AD-31 and AD-33, the S2 and S18 rows of Spikes, and the Redaction, Logging and errors and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:**
- **Nothing is derived from the timer.** `OcuTalon.Bridge.Timeouts.Derive` is Epic 0's stub (it answers `{}`). The runners' session config has no `timeout_ms`, and the Config Store entries that the Provider step writes have no `request_timeout_secs` and no retry block, so AI Hub waits up to 30 s on a `Retry-After` (S18) and nothing the bridge set bounds a held request.
- **The timer is an error.** When `Decide`'s timer fires, `OnResponse` ends with an error status and records no decision (Story 1.3), so the caller gets no fallback.
- **A rate limit falls back at once.** Story 1.6 classifies `rate_limited` and falls back at once (its decision 1). Nothing re-sends.
- **`ToolsRun` is never set (DW-56).** The runner's `Answer` never sets `Reply.ToolsRun`, and the re-send rule depends on it.

**Approach:**
- **One timeout API.** `Timeouts.Derive(timer)` gives `timeout_ms` and the `http_config` block (the request timeout and the full retry block). `Timeouts.Check` is the one timer check (12 to 110 s). `Timeouts.Apply(timer)` is the one run-time timer change: it writes `Decide`'s setting, merges the block into each runner's entry, and restarts `Decide` and the runners.
- **The values reach AI Hub.** The adapter adds `timeout_ms` to every session config. The Provider step writes the block into every entry at every start.
- **The timer records a fallback:** `timeout`, or `rate_limited` once `Decide` has re-sent.
- **The re-send.** After a `rate_limited` failure whose `Reply` says no tool ran, `Decide` re-sends with back-off (1, 2, 4, then 8 s, the last one shortened to fit) until its timer fires. It prechecks every re-send.
- **`ToolsRun`.** The runner sets it from AI Hub's tool-call counter and the step records.

## Boundaries & Constraints

**Always:**
- **`Derive` (AD-8).**
  - **The signature** is Epic 0's: `Timeouts.Derive(timer As %Integer) As %DynamicObject` (pinned by `Test.Contract.Ac:322`). It is pure.
  - **For a timer that `Check` accepts,** it gives exactly `{"timeout_ms": (timer - 5) * 1000, "http_config": {"request_timeout_secs": A, "retry": {"max_retries": 1, "attempt_timeout_secs": A, "initial_backoff_ms": 500, "max_backoff_ms": 2000}}}`, where A = (timer - 10) \ 2.
  - **For 60** that is 55000 and 25. The worst case of one `Chat` request is (1 + 1) x A + 1 x 2 = 52 s, and for every accepted timer it is at most timer - 8.
  - **For any other value,** it gives `{}`.
- **`Check`.**
  - **The bounds.** `Timeouts.Check(timer) As %Status` is OK for a whole number (digits only) from `Decide.#MINTIMER` (new, 12) to `Decide.#MAXTIMER` (110).
  - **The error,** for any other value, is `The setting TimerSeconds of Decide is '<value>'; it must be a whole number of seconds from 12 to 110`. The value is cut to 40 characters and redacted.
  - **Its callers.** `Decide.CheckSettings` uses it for the timer, so a refused timer stays an error status before anything is sent.
- **`Apply` (AD-5, AD-8, AD-19).**
  - **The signature.** `Timeouts.Apply(timer As %Integer, production As %String = "") As %Status` is the bridge's one run-time timer change. An empty `production` means the active production.
  - **The order of a call:**
    1. `Check(timer)`.
    2. Every runner item of `Decide.#RUNNERS` that the production has must have a `ProviderConfig` of the form `@{config:<name>}` whose entry exists (`ConfigStore.Details`). All runners are checked before anything is written.
    3. It writes the System Default Settings row of `Decide`'s `TimerSeconds` (item `Decide`, host class `*`) through the bridge's writer, `Ext.Accessor.WriteDefault`. If the timer that `Ext.Accessor.ValueFor` then reads is not the one given, because the production definition sets it, Apply puts the row back and fails, naming that setting.
    4. It merges `Derive(timer).http_config` into each runner's entry (`ConfigStore.Merge`), so `api_key`, `base_url`, `custom_headers` and `tls` stay.
    5. When the production runs, it restarts `Decide` and each runner item (`Ens.Director.TempStopConfigItem` off, then on), and returns once they run again: within 60 s, or with an error that names the item that did not start (the writes stay, and the next restart applies them).
  - **A refusal changes nothing** and names the setting or the runner.
  - **No details leave it.** It never logs or returns an entry's details.
- **The session config (AD-6, AD-7).**
  - **`Compose`.** `Adapter.Agent.Compose` gains a trailing `timeoutMs As %Integer = ""`, which sets `timeout_ms` when it is not empty. Without it the config is exactly what it is today.
  - **`SessionConfigFor`** passes `Derive(T).timeout_ms`. T is `Decide`'s `TimerSeconds` as `Ext.Accessor.ValueFor("TimerSeconds")` reads it (the active production, item `Decide`) when the config is composed.
  - **No usable timer.** A timer that cannot be read, or that `Check` refuses, composes no `timeout_ms`; `Decide` refuses every request in that state.
- **The Provider step (AD-19, AD-23).**
  - **The timer it reads.** `Install.Step.Provider.Apply` reads `Decide`'s `TimerSeconds` of `OcuTalon.Production` (`ValueFor("TimerSeconds", production, "Decide")`) and checks it with `Timeouts.Check` together with the overrides. A refusal fails the step, naming `TimerSeconds`, and writes no entry and no row.
  - **What it writes.** `Details(agentClass, baseUrl, caFile, mockKeyFlag, timer = 60)` stays pure and puts `request_timeout_secs` and the whole `retry` block of `Derive(timer).http_config` into every entry's `http_config`, after `custom_headers` and `tls`, in the judges' install too.
  - **Structural.** Every value is still rewritten whole at every start.
- **The timer (AD-6, AD-8, AD-30).**
  - **The fallback.** `OnResponse` for the key `timer` records a fallback (`RecordFallback`) for the stored `DecisionRef` and answers the caller: a `DecisionResponse`, or a fallback `Reply` for a turn. The reason is what `Classify` gives for the facts `timedOut` (true) and `resends` (the number of re-sends so far).
  - **The late reply.** The timer keeps `SetTimer`'s default controlled keys (`*`), so the runner request in flight leaves the pending list and Ens discards its late reply (`Ens/BusinessProcess.cls:294-297`, :375-399). The runner still writes its `Usage` row (Story 1.4).
  - **What the row holds.** No step is sent for the call that was in flight. The row's totals are those of the ref's `Usage` rows when the timer fired.
- **`Classify` (AD-8).** One rule is added after the prechecks and before the failure text: `timedOut` gives `rate_limited` when `resends` is above 0, else `timeout`. Every other rule is Story 1.6's, and a missing fact counts as false or 0.
- **The re-send (AD-8, FR-4, NFR-23).**
  - **When it is weighed.** In `OnResponse` for the key `reply`, after the steps are sent, when the runner answered with a `Reply` and no error status (`RunnerError` is OK). The `Reply`'s `FailureText` gives the reason (`Classify`), and `ResendDelay(reason, toolsRun, resends, remainingMs)` decides.
  - **`ResendDelay` is pure.** It gives a whole number of seconds when:
    - the reason is `rate_limited`;
    - `toolsRun` is false;
    - `remainingMs` (`TimerSeconds` x 1000, minus the milliseconds since `Decide` began) is at least 2000.

    The delay is the least of `RESENDFIRST` (1 s) x 2^resends, `RESENDMAX` (8 s) and (remainingMs - 1000) \ 1000, so the last re-send still has at least 1 s before the timer. Otherwise it gives 0.
  - **A delay above 0.** `Decide` adds the reply's `AgentStepCount` to `StepCount`, sets a timer of that many seconds with the key `resend` and controlled keys "" (it cancels nothing), and answers nothing yet.
  - **A delay of 0.** The reply goes to `Conclude` as in Story 1.6. So a tool that ran, an error status (no `Reply`), `error`, `timeout` and every other reason fall back at once.
  - **For the key `resend`:**
    1. `Decide` prechecks the request again (`Precheck`, with the same token budget as `OnRequest`). A reason is recorded with `RecordFallback`, so `daily_cap` marks the day.
    2. It sends a clone of the request, with the stored `DecisionRef`, to the same runner (key `reply`) and adds 1 to `Resends`.
    3. It sets the timer `timer` for the whole seconds left of `TimerSeconds` since it began. With less than 1 s left, it records `rate_limited` at once.
- **State (AD-5).** `Decide` gains four stored properties, which the compiler appends as Storage slots 9 to 12. None is a setting.
  - `DecisionRef` (`%String(MAXLEN = 22)`): set in `OnRequest` before the send.
  - `Resends` (`%Integer`, 0).
  - `StepCount` (`%Integer`, 0): the `AgentStepCount` of the attempts before the last.
  - `StepsSent` (`%Integer`, 0): the step records sent so far.
- **Totals and steps across attempts (AD-9, AD-20).**
  - **Steps.** The row's and the answer's `AgentStepCount` is the sum over the attempts: `StepCount` plus the last reply's.
  - **Tokens and cost** come from `Usage.Totals(ref)`, which sums every attempt's row.
  - **Duration.** `DurationMs` runs from when `Decide` began.
  - **Positions.** `EmitSteps` numbers a decision's steps 1 to n across its attempts: `StepMessages` gains a trailing `offset = 0`, and the Positions start at offset + 1.
- **`ToolsRun` (AD-6, DW-56).**
  - **Where it is set.** `Answer` sets it on every `Reply` it builds, the failure `Reply` included, from the pure `Adapter.Agent.ToolsRan(before, after, records)`.
  - **When it is 1:**
    - the `total_tool_calls` delta of the two readings is above 0;
    - a step record is of kind `tool`;
    - or either reading is not an object.

    An unknown counts as ran, so `Decide` never re-sends an attempt in which a tool may have run. Otherwise it is 0, and `Reply.ToolsRun`'s doc says so.
  - **What `Decide`'s answers carry.**
    - A usable answer keeps the runner's value, because it is a clone.
    - A fallback `Reply` carries the runner's `ToolsRun`, as it carries `Tainted`.
    - A fallback with no runner reply (a precheck or the timer) sets neither.
- **The bridge boundary (AD-2).** `Timeouts`, `Decide` and the adapter name no other OcuTalon package. `OcuTalon.Install.Step.Production.WriteDefault` delegates to the new `Ext.Accessor.WriteDefault(production, item, setting, value, description)`, so there is one writer of System Default Settings rows.
- **Logs and text.**
  - **No warning for a re-send.** A re-send is not a fault, so `Decide` logs none for it; the runner's warning for each failed `Chat` stays (Story 1.6). Every new warning is Type 3 and passes `Redact.Text`.
  - **ASCII.** All text in `src/`, `ci/` and `release/` is ASCII.
- **Tests.**
  - **Where they go:** `OcuTalon.Test.Bridge`, `.Agent` and `.Install`, all in the `lane-a` shard. The new class `OcuTalon.Test.Bridge.Timeouts` joins an existing area, so `ci/units.sh` does not change.
  - **Every test puts back what it changed:**
    - a changed timer, through `Apply` with the earlier timer and then `RunnerFixture.RestoreDefaults`;
    - every countdown it armed (`Test.Contract.Mock.Arm(marker, "")`);
    - its `Decision`, `Usage` and `AgentStep` rows and its System Default Settings rows.

**Never:**
- **Story 1.8:** no conversation link and no `SessionBroken`.
- **Story 1.9:** no `too_large` and no tool-result cap.
- **Step 2:** no second-model retry, no settings page and no `SettingsOps`.
- **Lane B's files:**
  - no change to `OcuTalon.Msg.Catalog*`, `Conversation`, `docker/**`, `ci/**` outside `ci/mock/scenarios/A/`, the mock's code or its tests, or `Test/{Contract,Core,Data,Demo,Live,Msg,Web}/**`;
  - `Test.Contract.Mock`'s `Arm`, `LogMark` and `LogSince` are only called.
- **The mock's existing scenarios:** none changes except the delay of `decide-late.json`. Lane B's mock tests read `held-past-timer`, `overloaded`, `rate-limited` and `long-retry-after`.
- **No new structures:**
  - no new production item, table, index or event type;
  - no change to `Production.cls` or `BridgeExample.Production`;
  - no property change in `src/bridge/` beyond `Decide`'s four and the doc of `Reply.ToolsRun`.
- **Re-sends:**
  - only for `rate_limited` with `ToolsRun` false;
  - never after the timer fired;
  - never for an error status;
  - and `Decide` never reads `Retry-After`: AI Hub's retry block caps it.
- **The bridge alone:** `release/standalone-bridge.sh` and the example's inline `ProviderConfig` stay as they are.
- **No key, no commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| `Derive` (pure) | 60, 12, 13, 59 and 110; every timer from 12 to 110 | Exact JSON: 60 gives 55000 and 25; 12 gives 7000 and 1; 13 gives 8000 and 1; 59 gives 54000 and 24; 110 gives 105000 and 50. Each `retry` block has the four keys, with `attempt_timeout_secs` = `request_timeout_secs`. For every timer, 2 x A + 2 is at most timer - 8, and it is 52 for 60. | n/a |
| Refused timers (pure) | 11, 111, 0, -1, "", "x", "60.5", " 60" and "6e1" | `Derive` gives `{}`. `Check` gives an error naming `TimerSeconds` and "12 to 110". `Decide.CheckSettings` refuses each, and accepts 12 and 110. | Never throws |
| `Apply` refuses (in process) | `Apply(111)`, `Apply(11)` and `Apply("x")`; `Apply(30, "OcuTalon.BridgeExample.Production")`, whose `TriageAgent` has no `@{config:}` entry | An error naming `TimerSeconds`, or naming the runner. The System Default Settings row, every entry's JSON and every item's job are as before. | Status error |
| `Apply` (live) | `Apply(20)` on `OcuTalon.Production` | 1. **The row:** `Decide`'s `TimerSeconds` row is 20.<br>2. **The entries:** each runner's entry has `request_timeout_secs` 5 and the retry block with `attempt_timeout_secs` 5, and its `api_key`, `base_url` and `custom_headers` as before.<br>3. **The restarts:** `Decide`, `TriageAgent`, `DiagnosisAgent` and `ChatAgent` run in new jobs (`RunnerFixture.Jobs`).<br>4. **The next decide:** its `Ens.AlarmRequest` has Timeout 20. | OK; restored |
| A held request (live) | After `Apply(20)`, a decide with `held-past-timer` (the reply is held 120 s) | 1. **The answer:** a `timeout` fallback `DecisionResponse`, at least 4 s and less than 20 s after the send (AI Hub's attempts of 5 s each, as Task 0 (c) measures them).<br>2. **The runner's reply:** `TriageAgent`'s `Reply` to `Decide` has a `FailureText` that holds `operation timed out`.<br>3. **No re-send:** `Decide` sent `TriageAgent` one request. | OK |
| The timer fires (live) | `Decide`'s `TimerSeconds` row is 12, written directly, with `Decide` restarted and the runners kept at the 60-s derivation; a decide with `decide-late` (the reply comes after 18 s) | 1. **The answer:** a `timeout` fallback `DecisionResponse` (`FallbackProblems`), 11 to 17 s after the send.<br>2. **The row:** it has the ref of the runner's request, `DurationMs` from 11000 to 17000, and empty token totals.<br>3. **The late reply:** its header is Discarded and no `AgentStep` is sent.<br>4. **Usage:** `TriageAgent` writes one `Usage` row for the ref with tokens above 0, and `Usage.Totals(ref)` counts it. | OK |
| A re-send succeeds (live) | A user turn with `overloaded:<key>` armed 2; another with `rate-limited:<key>` armed 3 | 1. **`overloaded`:** the `Reply` holds "Answered after the overload.", with `Fallback` 0, and the row is not a fallback.<br>2. **What `Decide` sent:** `ChatAgent` got 3 requests, all with the one `DecisionRef`.<br>3. **The log:** 529, 529, 200 for the marker; the second request comes at least 1 s after the first and the third at least 2 s after the second.<br>4. **Steps:** the answer's `AgentStepCount` is the sum of the three runner replies'.<br>5. **`rate-limited`:** the log holds 429, 429, 429, 200, and `Decide` sent 2 requests (AI Hub retries each 429 once). | OK |
| The re-sends run out (live) | `Apply(15)`; a user turn with `overloaded:<key>`, not armed (always 529) | A `rate_limited` fallback `Reply` (`FallbackProblems`), 12 to 15 s after the send: `Decide` kept re-sending until the timer. It sent at least 4 requests, and each is a 529 in the log; the re-sends come at least 1 s, 2 s and then 4 s after the failure before them. | OK; restored |
| A tool ran (live, `StepsAgent`) | A turn with `rate-limited-after-tool` (a `zz_steps_note` tool use, then a 529) | 1. **The answer:** at once, a `rate_limited` fallback `Reply` with `ToolsRun` 1.<br>2. **The runner's reply:** `ToolsRun` 1, and a `FailureText` that holds `Rate limit exceeded`.<br>3. **No re-send:** `Decide` sent one request, and the log holds 2 requests for the ref with no third (read after `Drain`).<br>4. **The steps:** a model step, then `Reading the test note`, reach `AgentSteps`. | OK |
| An error (live) | The `provider-error` marker (500) | One runner request, as `TestReplyFallbacks` already pins: an `error` falls back at once. | OK |
| A long `Retry-After` (live) | A user turn with `long-retry-after:<key>` armed 1 (a 429 with `Retry-After` 30) | The `Reply` holds "Answered after a capped wait.", 1.5 to 10 s after the send. The log holds 429, then 200, and `Decide` sent one request. | OK |
| The session config (in process) | `Compose` with `timeoutMs` "" and 55000; a `ZzRunner`'s `SessionConfigFor` with no `TimerSeconds` row, with a row of 20 and with a row of 111 | 1. **`Compose`:** with "" the JSON is exactly as today; with 55000 it adds `"timeout_ms":55000`.<br>2. **`SessionConfigFor`:** 55000, then 15000, then no `timeout_ms`. | n/a |
| The Provider step | `Details` with the timer 60 and 30; a start; a `TimerSeconds` row of 111 | 1. **`Details`:** every entry's `http_config` holds `request_timeout_secs` 25, or 10, and the full retry block, in the judges' install too.<br>2. **After a start:** each entry holds the block of `Decide`'s timer.<br>3. **A row of 111:** the step fails, naming `TimerSeconds`, and every entry and row stays as it was. | Step error |
| `ToolsRun` (in process) | A `ZzRunner` with `StepsAgent` and `steps-two-tools`; Triage's default script; `provider-error`; `ToolsRan` with readings "", with a delta of 0 and the records `[model]`, with a delta of 0 and `[tool]`, and with a delta of 1 and `[]` | 1 for the two tools, 0 for the default script, 0 for the failure `Reply`; then 1, 0, 1 and 1. | n/a |
| `ToolsRun` (live, DW-56) | `StepsAgent`'s turn with `steps-two-tools` | Both the runner's `Reply` and `Decide`'s answer have `ToolsRun` 1. | OK |
| `Classify` (pure) | `timedOut` alone; `timedOut` with `resends` 1; `noKey`, `capped` and `overBudget` each with `timedOut`; `timedOut` with a failure; `resends` without `timedOut` | `timeout`; `rate_limited`; the precheck reasons win; `timeout` wins over the failure; and `resends` alone gives "". | n/a |
| `ResendDelay` (pure) | `rate_limited`, toolsRun 0, with resends 0, 1, 2, 3, 4 and 9 and 60000 ms left; then resends 0 with 1999, 2000 and 2500 ms left; resends 3 with 5000 ms left; toolsRun 1; the reasons `error`, `timeout` and "" | 1, 2, 4, 8, 8 and 8; then 0, 1 and 1; 4 (cut to fit); and 0 for each of the rest. | n/a |
| `OnResponse` (pure) | A process with `DecisionRef` set: the key `timer` with `Resends` 0 and with 1, for a decide and a turn; the key `resend` with the day marked capped | `timeout`, then `rate_limited`: a row with the process's ref, a `DecisionResponse` or a fallback `Reply`, and one `decision.recorded`. The `resend` key records a `daily_cap` fallback and sends nothing. | n/a |
| The bridge alone | `release/standalone-bridge.sh` | Unchanged: every check passes. The example's runner composes `timeout_ms` 55000 from its `Decide`'s default. | The script names the check |

</intent-contract>

## Code Map

- **AI Hub, Ens and the spikes (read only):**
  - **`Ens/BusinessProcess.cls`:**
    - `SetTimer(timeout, key, controlledKeys = "*")` is at :189;
    - when only timers are pending as a response arrives, Ens clears the pending list before `OnResponse` (:401-416), so a timer that is still running no longer counts and its response is discarded later (:322-326);
    - a timer's response removes the pending entries of its controlled keys (:375-399), so `*` removes the runner request in flight;
    - a response to a completed process is discarded (:294-297);
    - `OnTimeout` (:880) is called before `OnResponse` for a timer, and the default does nothing;
    - `OnResponse` is called at :435.
  - **`Ens/Alarm.cls`:** the wake time is now plus the request's `Timeout` (:28-30), with sub-second waits handled at :150-152.
  - **`Ens/Director.cls`:** `TempStopConfigItem(item, stop)` is at :2467. Its pattern, off then on, is `RunnerFixture.Restart` (:88-95).
  - **S2 and S18 (the spine's Spikes):**
    - `timeout_ms` does not stop a request in flight;
    - AI Hub retries 429, timeouts and connection errors, never 500 or 529;
    - a rate-limit retry waits min(`Retry-After`, `max_backoff_ms`), and 30 s without a full block.

    Lane B's `Test.Contract.Mock.TestCountdownAndRetryAfterCap` (:231) measured the cap through a bare agent with this block.
- **The bridge (Lane A, `src/bridge/cls/OcuTalon/Bridge/`):**
  - **`Timeouts.cls`:** the whole class, the stub (:1-12).
  - **`Process/Decide.cls`:**
    - the class doc (:3-46) and `MAXTIMER` (:56);
    - `TimerSeconds` (:94), `RunnerError` (:111) and Storage (:715-746, slot 8 last);
    - `OnRequest` (:133-162): the budget at :151-152, the send at :157-160 and the timer at :161;
    - `OnResponse` (:180-202): the timer's error at :184-186 and `EmitSteps` at :188;
    - `EmitSteps` (:208), `StepMessages` (:227, Position at :249) and `CheckSettings` (:312-327, the timer branch at :314-316);
    - `Precheck` (:370), `Classify` (:416-442) and `Conclude` (:475-534);
    - `RecordFallback` (:576-602, `Tainted` at :599) and `NewRow` (:607-627, `AgentStepCount` at :624).
  - **`Adapter/Agent.cls`:**
    - `Compose` (:134-160) and `SessionConfigFor` (:175-178);
    - `Answer` (:216-274): the stats readings at :232 and :245, the reply at :253-263 and `StepsJson` at :262;
    - `ReadStats` (:324).
  - **`Msg/Reply.cls`:** `ToolsRun` (:17-18, "True when any tool ran").
  - **`Ext/Accessor.cls`:** `ValueFor(setting, production, item = "Decide", sc)` (:16-27), which reads the production definition, then the System Default Settings, then the initial value.
  - **`ConfigStore.cls`:** `Merge` (:33-54, a deep merge that keeps other keys), `Details` (:60) and `FullName` (:79).
  - **`Keys.cls`:** `Present` matches `@{config:<name>}` and takes the name (:55-56). This is the read that `ConfigStore.EntryOf` takes over (Design Notes).
  - **`Data/Usage.cls`:** `Delta(before, after, key)` (:67), `HasSpend` (:75) and `Totals`.
  - **`Adapter/StepBuffer.cls`:** the record kinds `model` and `tool` (:97-134).
  - **`Time.MsSince`**, as Decide uses it at :155.
- **OcuTalon (Lane A):**
  - **`src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`:** `Run` (:51), `Apply` (:59-73, the override checks at :63-65), `Details` (:83-98, `httpConfig` at :87-96) and `WriteRunner` (:124-143).
  - **`src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`:** `WriteDefault` (:269-285).
  - **`src/ocutalon/cls/OcuTalon/Production.cls:18-21`:** `Decide` sets no `TimerSeconds`, so the System Default Settings row is the one that takes effect.
- **The mock (Lane B's code; Lane A adds and changes files under `ci/mock/scenarios/A/` only):**
  - **The reply rule** (AD-22, "The mock as built"). With k the number of assistant messages after the newest user message with text:
    - a marker that is not armed answers `replies[min(k, last)]`;
    - an armed one answers `replies[0]` while `remaining` is above 0, and takes 1 off;
    - then it answers `replies[min(1 + k, last)]`.

    AI Hub's own retries spend the countdown too. The code is in `mock.mjs:280-292`.
  - **Delays and the log.** A delay holds the whole response (`mock.mjs:451-453`), and each log entry carries `ts` (:363).
  - **The scenarios:**
    - `held-past-timer` (120 s);
    - `overloaded` (529, then 200 "Answered after the overload.");
    - `rate-limited` (429, then 200 "Answered after the rate limit.");
    - `long-retry-after` (429 with `Retry-After` 30, then 200 "Answered after a capped wait.");
    - `decide-late` (6 s, used only by `Test.Agent.Decide.TestTimer`);
    - `cut-off-tool`, whose shape the new `rate-limited-after-tool` follows.
  - **`Test.Contract.Mock`** (Lane B, call only): `Arm(marker, remaining)` (:331), `LogMark` and `LogSince`.
- **The catalog (Lane B, read only):** `Msg/Catalog/Core.cls`: `fallbackReason.timeout` is "the model didn't answer within 60 seconds" (:181-182), and `fallbackReason.rateLimited` is "the model was busy and retries ran out" (:206-207).
- **Tests (Lane A, `src/ocutalon/cls/OcuTalon/Test/`):**
  - **`Agent/Decide.cls`:**
    - the header (:1-80), where `TestTimer` is at :20-21;
    - `OnAfterOneTest` (:128-168), which deletes the `TimerSeconds` row at :158 and restarts `Decide` at :159-162;
    - `TestTimer` (:488-522), `Prepare` (:1007), `Case` (:1033), `HeaderTo`, `CountTo`, `WaitForStatus` and `Put` (:1157).
  - **`Agent/RunnerFixture.cls`:**
    - `Restart` (:88), `Jobs` (:107), `NewRequest` (:211) and `Run` (:313);
    - `RememberDefault` (:626) and `RestoreDefaults` (:638);
    - `Drain` (:688), `FallbackProblems` (:707, the flags at :720), `FindRequests` (:753) and `UsageIds` (:811).
  - **`Agent/Steps.cls`:** the swap of `ChatAgent` to `StepsAgent` (:71-104), `TestTwoTools` (:134) and `TestFailedTurnSteps` (:356).
  - **`Bridge/Decide.cls`:**
    - `TestBadSettings` (:185-199, "a timer of 1 passes" at :190);
    - `TestOnResponseUsesItsSettings` (:606-634, the timer at :628-633) and `TestOnRequestUsesItsSettings` (:660-676);
    - `TestOnErrorFallback` (:1109-1175, the rate-limit text through an error status at :1146-1156);
    - `NewProcess` (:1466) and `NewReply` (:1498).
  - **`Bridge/Fallback.cls`:** the `Classify` tests.
  - **`Bridge/SessionConfig.cls`:** `AssertCompose` (:201) and the exact JSON of each family.
  - **`Bridge/Runner.cls`:** `TestCacheOverThreshold` (:381, `SessionConfigFor`), `NewRunner` (:855) and `ProviderConfig` (:869).
  - **`Bridge/Api.cls:38`:** it pins `Derive(60)` as `{}`.
  - **`Install/Provider.cls`:** `TestDetails` (:32), `TestBadOverrides` (:105), `TestEntries` (:171), `Pure` (:263) and `ForEnv` (:269).
  - **`Install/ProviderEnv.cls`:** `Entry` (:266-278), which writes out the expected entry JSON.
  - **Lane B, read only:** `Contract/Ac.cls:322` pins `Derive`'s signature, and `Ac.cls:226` checks a superset of `Reply`'s properties.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **Targets.** The slot `ocutalon-slot-a` (namespace `OCUTALON`, after `iris_server_info` shows build 154) for process-local facts. A throwaway of tag `e1s7a` for the rest.
- **(a) A rate-limited attempt.**
  - **The run:** a `ZzRunner` (`Test.Bridge.Runner`'s shadow) with `overloaded` armed 1 and `rate-limited` armed 2.
  - **What to record:** the `FailureText`, the deltas of `total_interactions` and `total_tool_calls`, the `Steps`, and whether a `Usage` row is written.
  - **Stop:** if an attempt that ran no tool shows a tool record or a `total_tool_calls` delta above 0, stop with status `blocked` and the condition `intent gap: ToolsRun (AC6), measured <fact>`.
- **(b) A tool before the rate limit.** `rate-limited-after-tool` through `StepsAgent`: the `total_tool_calls` delta, the `Steps` and the `FailureText`.
- **(c) The derived request timeout.**
  - **The run:** a `ProviderConfig` whose `http_config` is `Derive(20)`'s, with a `held-past-timer` request.
  - **What to record:** the time until `Chat` throws, its text, the number of requests in the mock's log, and whether a `Usage` row is written.
  - **Stop:** if the text does not hold `operation timed out`, stop with status `blocked` and the condition `intent gap: AD-8 (timeout text), measured <text>`.
- **(d) The re-send timers.** The times at which `Decide`'s `resend` timers of 1, 2 and 4 s fire (from the trace).
- **(e) `Apply`.** After the restarts, the next decide's timer Timeout, and the attempt timeout that a held request meets.
- **Other facts.** If any fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/Timeouts.cls`:** `Derive`, `Check` and `Apply`, as in Boundaries, and the class doc. Rationale: AD-5, AD-8, AD-19.
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`.** Rationale: AD-5, AD-6, AD-8, AD-9, AD-20, AD-30; FR-4, NFR-23.
  - **New:**
    - `MINTIMER` 12, `RESENDFIRST` 1 and `RESENDMAX` 8;
    - the stored `DecisionRef`, `Resends`, `StepCount` and `StepsSent`;
    - `ResendDelay`, and the handling of the key `resend`.
  - **Changed:**
    - `OnRequest` stores `DecisionRef` before the send;
    - `OnResponse` handles the key `timer` (the fallback) and weighs the re-send after `EmitSteps`;
    - `Classify` adds the `timedOut` rule;
    - `CheckSettings` calls `Timeouts.Check`;
    - `EmitSteps` and `StepMessages` take the offset;
    - `NewRow` adds `StepCount`, and `RecordFallback` copies the runner's `ToolsRun` with `Tainted`.
  - **The class doc:** rewrite the timer and failure paragraphs.
- **`src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`:** the `timeoutMs` of `Compose`; `SessionConfigFor` reads the timer; `ToolsRan`, and `ToolsRun` on every `Reply` of `Answer`; the class doc and `Answer`'s doc. Rationale: AD-6, AD-7, DW-56.
- **`src/bridge/cls/OcuTalon/Bridge/Msg/Reply.cls`:** the doc of `ToolsRun` only, with no storage change. Rationale: DW-56.
- **`src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls`:** `WriteDefault`, the body of `Install.Step.Production.WriteDefault` moved here, and the doc ("reader and writer"). Rationale: AD-2, Rule 2.
- **`src/bridge/cls/OcuTalon/Bridge/ConfigStore.cls`:** `EntryOf(providerConfig) As %String`, the entry name of an `@{config:<name>}` value or "". `Keys.Present` and `Timeouts.Apply` use it. Rationale: Rule 2.
- **`src/bridge/cls/OcuTalon/Bridge/Keys.cls`:** `Present` uses `ConfigStore.EntryOf`, with no change in behaviour.

**OcuTalon (Lane A).**
- **`src/ocutalon/cls/OcuTalon/Install/Step/Provider.cls`:** read and check the timer in `Apply`; the `timer` of `Details` and the block in `http_config`; the class doc. Rationale: AD-8, AD-19, AD-23.
- **`src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`:** `WriteDefault` delegates to `Ext.Accessor.WriteDefault`. Rationale: Rule 2.

**The mock (Lane A's folder).** Rationale: AD-22.
- **`ci/mock/scenarios/A/rate-limited-after-tool.json`** (new): the `toolUse` `zz_steps_note` with `{"topic": "status"}`, then status 529 with the text `CI mock: overloaded after a tool.`
- **`ci/mock/scenarios/A/decide-late.json`:** `delayMs` goes from 6000 to 18000. It stays below the 25-s attempt timeout of the 60-s derivation, and above a timer of 12.

**Tests.**
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Timeouts.cls`** (new): `TestDerive`, `TestRefused` and `TestApplyRefuses` (the rows "`Derive`", "Refused timers" and "`Apply` refuses").
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`:**
  - `TestBadSettings`: 11 and 111 are refused, and 12 and 110 pass;
  - `TestOnRequestUsesItsSettings`: adds 11;
  - `TestOnResponseUsesItsSettings`: the timer's key records `timeout` with the process's `DecisionRef`;
  - `TestStepMessages`: adds the offset;
  - `TestConcludeFallbacks`: the runner's `ToolsRun` is carried;
  - new: `TestTimerFallback`, `TestResendDelay` and `TestResendPrecheck` (the rows "`OnResponse`" and "`ResendDelay`");
  - the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Fallback.cls`:** the `timedOut` rule and its order (the row "`Classify`").
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/SessionConfig.cls`:** `TestTimeoutMs`, the exact JSON with and without `timeoutMs`.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`:** `TestSessionTimeout` and `TestToolsRun` (the rows "The session config" and "`ToolsRun` (in process)"), and the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`:** `TestNeutralValues` pins `Derive(111)` as `{}`, and the doc follows.
- **`src/ocutalon/cls/OcuTalon/Test/Install/Provider.cls`** and **`ProviderEnv.cls`:** the block in every expected entry, `Details` with the timer 30, and a `TimerSeconds` row of 111 that fails the step (the row "The Provider step"). Every row they write is put back.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:**
  - `FallbackProblems` judges `SessionRotated`, `SessionBroken` and `Busy`, and no longer `ToolsRun`, which is the runner's own like `Tainted`;
  - `UseTimer(timer, Output saved)` and `RestoreTimer(saved)`, built on `RememberDefault`, `RestoreDefaults` and `Timeouts.Apply`.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`:**
  - `TestTimer` is rewritten (the row "The timer fires");
  - new: `TestApplyTimer` (the rows "`Apply` (live)" and "A held request"), `TestRateLimitedResent`, `TestRateLimitedUntilTimer` and `TestLongRetryAfterCapped`;
  - `OnAfterOneTest` puts the timer back and clears the countdowns;
  - the header.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Steps.cls`:** `TestToolRanNoResend` (the row "A tool ran"), and `TestTwoTools` asserts `ToolsRun` (the row "`ToolsRun` (live)").
- **Coverage.** These tests and the script prove every matrix row.

**Acceptance Criteria:**
- **AC1, the timer's derived values reach AI Hub (Integration AC).**
  - **Given** the bridge timer (default 60 s),
  - **when** `Timeouts.Derive(timer)` runs,
  - **then:**
    - it gives `timeout_ms` as the timer minus 5 s and `request_timeout_secs` as (timer - 10) / 2 rounded down, with the full retry block `{"max_retries": 1, "attempt_timeout_secs": <request timeout>, "initial_backoff_ms": 500, "max_backoff_ms": 2000}`, so 60 gives 55000, 25 and a worst case of 52 s;
    - every session config that the runner composes carries that `timeout_ms`;
    - the Provider step writes the request timeout and the whole block into each entry's `http_config`, never a part of it.

  The consumer is AI Hub's provider: a request held past its attempt timeout ends as `timeout` before the timer.

  (`Test.Bridge.Timeouts.TestDerive`, `Test.Bridge.SessionConfig.TestTimeoutMs`, `Test.Bridge.Runner.TestSessionTimeout`, `Test.Install.Provider`, `Test.Agent.Decide.TestApplyTimer`)
- **AC2, the timer's bounds, and any change.**
  - **Given** a timer outside 12 to 110 s, or a change of the timer,
  - **when** `Check`, `Decide` or `Apply` meets it,
  - **then:**
    - a timer above 110 (or below 12) is refused, with an error naming `TimerSeconds` and with nothing changed;
    - `Apply` writes the setting, merges `Derive`'s block into every runner's entry and restarts `Decide` and the runners;
    - the next decision uses the new timer.

  (`Test.Bridge.Timeouts.TestRefused`, `TestApplyRefuses`; `Test.Bridge.Decide.TestBadSettings`; `Test.Agent.Decide.TestApplyTimer`)
- **AC3, the timer ends the decision with a fallback.**
  - **Given** a mock scenario that answers after the timer,
  - **when** the timer fires,
  - **then:**
    - `Decide` records `timeout` and answers its caller with the fallback;
    - the late reply is never passed on;
    - the runner still writes its `Usage` row.

  (`Test.Agent.Decide.TestTimer`; `Test.Bridge.Decide.TestTimerFallback`)
- **AC4, rate limits are re-sent only when no tool ran (Integration AC: `Decide` reads the runner's `ToolsRun`).**
  - **Given** mock scenarios that answer HTTP 429 or 529 ("Rate limit exceeded") under the mock's per-test countdown,
  - **when** no tool ran in the failed attempt,
  - **then:**
    - `Decide` re-sends with back-off until its timer fires, returning the reply when an attempt succeeds and `rate_limited` otherwise;
    - when a tool ran, it falls back at once, and an `error` always falls back at once.

  (`Test.Agent.Decide.TestRateLimitedResent`, `TestRateLimitedUntilTimer`, `TestReplyFallbacks`; `Test.Agent.Steps.TestToolRanNoResend`; `Test.Bridge.Decide.TestResendDelay`, `TestResendPrecheck`)
- **AC5, a long `Retry-After` waits only the back-off cap.**
  - **Given** a scenario that sends `Retry-After` 30,
  - **when** it is answered through a runner whose entry the Provider step wrote,
  - **then** the wait is capped at the retry block's `max_backoff_ms`, and the reply comes in 1.5 to 10 s.

  (`Test.Agent.Decide.TestLongRetryAfterCapped`)
- **AC6, `ToolsRun` tells whether a tool ran (DW-56).**
  - **Given** a turn that ran tools, and one that did not,
  - **when** the runner answers,
  - **then:**
    - its `Reply`, and `Decide`'s answer, have `ToolsRun` 1 and 0;
    - a failure `Reply` carries it too;
    - an attempt whose tool counts cannot be read counts as one in which a tool ran.

  (`Test.Bridge.Runner.TestToolsRun`, `Test.Agent.Steps.TestTwoTools`, `TestToolRanNoResend`)

## Spec Change Log

## Review Triage Log

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** `Timeouts`, `Decide` and the adapter name no OcuTalon package. The System Default Settings writer moves into the bridge, and the install step calls it.
- **AD-5:** the timer stays at or under 110 s, and `Decide`'s Storage only grows (slots 9 to 12).
- **AD-6:** the pipeline; a late reply is not passed on, but the runner writes its usage; `ToolsRun` on the `Reply`.
- **AD-7:** the session config is built in code, with `timeout_ms`.
- **AD-8:** `Derive`, the timer, `Classify` and the re-send.
- **AD-9:** the steps across attempts.
- **AD-19:** the Provider step is the only install-time writer of the entries, and `ConfigStore.Merge` is the run-time one. The values are structural.
- **AD-20:** the totals across attempts, and a precheck before every send.
- **AD-22:** the mock scenarios under `A/`, the countdown and `Retry-After`.
- **AD-23:** the Provider step at every start.
- **AD-26:** `Fallback` and `FallbackReason` in the trace.
- **AD-30:** `Decide` sends only runner requests, timers, steps and its answer.
- **AD-31:** `FireEvent`, and `MarkCapped` for a `daily_cap` found at a re-send.
- **AD-33:** no new item, table or event type.

No acceptance criterion contradicts an AD's Rule. One wording of AD-8 is reconciled in decision 7 and offered for a line in the spine (Clarification Record).

**Decided in-stage:**
1. **`Derive`'s shape.** `{"timeout_ms", "http_config": {"request_timeout_secs", "retry"}}`, so that the Provider step and `Apply` use the `http_config` part as it is. A refused timer gives `{}`, the stub's own answer.
2. **The shortest timer is 12 s (it was 1).** (12 - 10) \ 2 = 1 is the least whole attempt timeout. A shorter timer would give AI Hub an attempt timeout of 0 or less, so `Check` refuses it. This is an implementation detail; AD-5 and AD-8 fix only the 110-s ceiling.
3. **`Apply` is the one run-time timer change.**
   - **What it does:** it writes `Decide`'s row, merges the entries and restarts the four items. It refuses a runner whose `ProviderConfig` is not an existing `@{config:}` entry, because a timer that reaches only some runners is not a change "through `Derive`".
   - **Its first consumer** is `SettingsOps` (Story 17.4).
   - **Why it writes the setting itself:** so that no caller can change the timer without the entries.
   - **A change made elsewhere** (the portal) is re-derived by the Provider step at the next start.
4. **The session config reads the timer each time it is composed** (`ValueFor`), so no runner setting holds a second copy. The `http_config` changes only when the runner restarts (S5), which is why `Apply` restarts the runners.
5. **A refused timer fails the Provider step**, as a bad override already does: the start says so. Every decision would be an error status anyway.
6. **`TestTimer` writes `Decide`'s row outside `Apply`, on purpose.**
   - **Why the timer rarely fires:** under the derived values one `Chat` request ends by timer - 8 s. The bridge timer fires only when AI Hub's loop outlasts it (a last request sent just before `timeout_ms`), or after a timer was changed outside `Apply` and before the next start.
   - **What the test uses:** the second case, which is reachable and gives the AC's observables: a reply that comes after the timer, is discarded, and is counted in its `Usage` row.
   - **The loop case** needs a tool that hangs for most of a minute and timings within a few seconds of the bounds, so it is not tested.
7. **The reason when the timer fires after a re-send is `rate_limited`.**
   - **The AC** says "re-sends with back-off until its timer fires, returning ... `rate_limited` otherwise". FR-4 says a rate-limited request is retried with back-off until the timeout before it counts as unusable. The catalog's text, "the model was busy and retries ran out", is then true.
   - **AD-8** lists `timeout` before `rate_limited` among the facts of one reply, and is silent on how the re-sends end.
   - **So** the `timedOut` rule gives `rate_limited` once `resends` is above 0.
8. **The re-send schedule.**
   - **The back-off** is 1, 2, 4, then 8 s. The last one is cut so that its re-send still has at least 1 s, so `Decide` keeps re-sending until its timer fires, as the AC says.
   - **How it ends.** With less than 2 s left, a failed attempt falls back at once with `rate_limited`, from the failure's own text. An attempt still in flight when the timer fires gives `rate_limited` through decision 7.
   - **The timer is set again** for the time left after each re-send, because Ens drops the first timer's pending entry when the reply arrives.
   - **Each re-send is prechecked,** because AD-20 prevents "budgets enforced in some paths and not others".
9. **A re-send needs a `Reply` with `ToolsRun` 0.**
   - **An error status** has no `Reply` to tell what ran, so it falls back at once, even with a rate-limit text (it comes before `Chat`, for example the model lookup of a build).
   - **`TestOnErrorFallback`'s rate-limit text** therefore stays a `rate_limited` fallback at once.
10. **`ToolsRun` means a tool call was made.**
    - **The signal** is AI Hub's counter or a tool step record, so a call to a missing tool or one the gate denied counts, and an unreadable reading counts too. This is the safe direction for the re-send (a denied risky tool can have raised an approval).
    - **It is honest on every `Reply`:** a fallback `Reply` carries the runner's value as it carries `Tainted`. `FallbackProblems` stops treating it as a flag that a fallback never has.
    - **The timer and a precheck** have no runner reply, so their `Reply` sets no runner flag.
11. **A timeout row keeps the totals known when the timer fired.**
    - **The late call's own `Usage` row** is written afterwards with the same `DecisionRef`.
    - **What counts it:** the day's spend, `Usage.Totals(ref)` and any reader that sums rows.
    - **Why it stays this way:** AD-20 says the runner writes the row "even when `Decide` has stopped waiting", and AD-6 says the late cost "is still counted". `Decide` keeps no process alive to rewrite its row (the veto window, below).
12. **The steps across attempts.** Positions run on (`StepsSent`), and `AgentStepCount` is summed (`StepCount`, Story 1.4's Consumed-by). A re-sent attempt normally has no step: its request failed, and no tool ran.
13. **The mock.**
    - **`decide-late`** waits 18 s, and only `TestTimer` uses it.
    - **`rate-limited-after-tool`** is new.
    - **The scenarios that Lane B's mock tests read** do not change. A test arms a marker of its own (`<name>:<NewRef>`) and clears it afterwards.
14. **The old timer is not cancelled.** After a re-send, its alarm still fires and Ens discards the response: one Discarded `Ens.Alarm` response per re-send in the trace.
15. **The bridge alone.**
    - **The example's runner** composes `timeout_ms` from its `Decide`'s default.
    - **Its inline `ProviderConfig`** gets no block from OcuTalon's Provider step, and `Apply` refuses it; its configuration belongs to the example (Story 13.1).
    - **`release/standalone-bridge.sh`** does not change.

**Integration ACs (Rule 1):**
- **AC1:** AI Hub's provider reads the block that the Provider step and `Apply` wrote. A held request ends as `timeout` before the timer (`TestApplyTimer`), and a 30-s `Retry-After` waits 2 s (`TestLongRetryAfterCapped`, AC5).
- **AC4:** `Decide` reads the runner's `Reply.ToolsRun` and does not re-send (`TestToolRanNoResend`).
- **`Apply`:** there is no production consumer in this story; the first will be Story 17.4 (`SettingsOps`). Its tests are its consumer here.

**Consumed-by:**
- **Story 1.8:**
  - a re-sent turn reopens its linked session (a failed `Chat` is never saved, so the history is the same);
  - the late `Chat` of a timed-out turn saves its session, and its taint is not on the fallback `Reply`;
  - Story 1.8 decides both against the conversation lock.
- **Story 1.9:** `too_large` joins `Precheck`, so it also runs before every re-send.
- **Story 2.4 (Lane B):** `Conversation` renders the `timeout` and `rate_limited` fallback `Reply`s and reads `ToolsRun`.
- **Stories 9.1 to 9.3:** `EvalIn`'s `TurnResult` carries a `ToolsRun` that is now set.
- **Story 13.1:** the example's `timeout` fallback and its own `ProviderConfig`.
- **Story 17.2:** the second-model retry stays within the bridge timer next to the re-send.
- **Story 17.4:** `SettingsOps` calls `Timeouts.Check` and `Timeouts.Apply`. The catalog's `fallbackReason.timeout` names 60 seconds, so a timer that can be changed needs that text to follow it (Lane B).

**Consumes:**
- **Story 1.1:** the Provider step and `ConfigStore.Merge`.
- **Story 1.2:** the adapter's `Compose`, and `RunnerFixture`.
- **Story 1.3:** `Decide`.
- **Story 1.4:** `Usage.Delta` and `Totals`, and the late `Usage` row.
- **Story 1.5:** `EmitSteps`, `StepMessages` and the swap in `Test.Agent.Steps`.
- **Story 1.6:** `Classify`, `Precheck`, `RecordFallback` and `FallbackProblems`.
- **Lane B, call only:** `Test.Contract.Mock.Arm`, `LogMark` and `LogSince`, and the mock.

**Extend, don't copy (Rule 2):**
- **The settings writer.** `Ext.Accessor.WriteDefault` is `Install.Step.Production.WriteDefault` moved into the bridge, and the step delegates to it. The bridge cannot call the step (AD-2).
- **The entry name.** `ConfigStore.EntryOf` serves `Keys.Present` and `Apply`.
- **The checks.** `Timeouts.Check` takes over `CheckSettings`' timer branch.
- **Parameters, not copies.** `Compose` gains a parameter, and so do `StepMessages` and `NewRow`.
- **The restart.** `Apply`'s restart is product code and cannot call `RunnerFixture.Restart`. The fixture keeps its own, because it also waits for every item, and `UseTimer` calls `Apply`.
- **The scenario.** `rate-limited-after-tool` follows `cut-off-tool`'s shape.
- **The test class.** `Test.Bridge.Timeouts` is new because no test of `Timeouts` exists.

**Ledger:**
- **DW-56** is addressed by AC6: the `Adapter/Agent.cls` task, the rows "`ToolsRun` (in process)", "`ToolsRun` (live, DW-56)" and "A tool ran", and AC4's use of `ToolsRun`.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles and process-local facts. No test class runs there.
- **Throwaways.**
  - Everything else runs through `ci/iris.sh` or the script, with `OCUTALON_RUN_TAG=e1s7a OCUTALON_LOCK_OWNER='epic=1 stage=implement'`. QA uses `e1s7q` and review `e1s7r`.
  - One stack at a time, one command per call, each with `timeout: 600000`.
  - `ci/iris.sh teardown` runs with the same tag at the end.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, `ocutalon-slot-b` or `ocutalon-slot-c`. No push, no `gh workflow run`, and never read `.env`.

**Commands** (each prefixed with the tag and the lock owner where it starts a stack):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes (the storage check, the bridge-references check and the boundaries check included). About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Bridge.Timeouts`, `.Bridge.Decide`, `.Bridge.Fallback`, `.Bridge.SessionConfig`, `.Bridge.Runner`, `.Bridge.Api`, `.Bridge.Contracts` and `.Bridge.CodeRules`;
  - `.Install.Provider` and `.Install.ProviderEnv`;
  - `.Agent.Decide` and `.Agent.Steps`.

  Expected: `CLASS ... passed`. `.Agent.Decide` waits on real timers and should take about 3 min.
- **(loop)** `bash release/standalone-bridge.sh`. Expected: every check `PASS`, the decide check with `fallback 0`, and exit 0.
- **(loop)** `bash ci/iris.sh shard lane-a`. Expected: every class passed, and the only SKIP is the existing `TestStepHelpers` one.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s7a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass with the new scenario.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passed, `Test.Contract.Ac` (the `Derive` signature) and `Test.Contract.Mock` included.
- **(once)** `bash ci/iris.sh live storage-roundtrip`. Expected: PASS, with `Decide`'s slots 9 to 12 equal to the compiled block.
- **(once)** `bash ci/iris.sh live production`, then `live production-restart`, one per call. Expected: PASS, with a clean start (the Provider step derives the block at start).
- **(once)** `bash ci/iris.sh live install-start`, then `live install-upgrade`, one per call. Expected: PASS, and an upgraded entry gains the block.
- **(once)** `bash ci/iris.sh live compose-start`, then `live demo-path`, one per call. Expected: PASS, and the `@floor` test passes.
- **(once)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s7a`'s projects.

**Shared surfaces:**
- **The timer's range (1 to 110 becomes 12 to 110):**
  - `Test.Bridge.Decide.TestBadSettings` ("a timer of 1 passes"), `TestOnRequestUsesItsSettings` and `TestOnResponseUsesItsSettings` (a timer of 7);
  - `Test.Agent.Decide.TestTimer` (2).
  - Search the test trees for `TimerSeconds`.
- **What the timer key answers** (an error becomes a fallback): `TestTimer` and `TestOnResponseUsesItsSettings`.
- **`Derive`:** `Test.Bridge.Api.TestNeutralValues` (`Derive(60)` is `{}`), and `Test.Contract.Ac`'s signature.
- **The entry JSON:** `Test.Install.Provider` (`TestDetails`, `TestEntries`, `TestRerun`) and `Test.Install.ProviderEnv.Entry`, which now always hold `http_config`. `RunnerFixture.PointKeys` merges only `api_key`.
- **`Compose` and `SessionConfigFor`:**
  - `Test.Bridge.SessionConfig`'s exact JSON stays, with no `timeoutMs` given;
  - `Test.Bridge.Runner.TestCacheOverThreshold` reads only `cache`.
- **`Reply.ToolsRun` is now set:**
  - `RunnerFixture.FallbackProblems` (:720);
  - `Test.Agent.Decide.TestTurnFallbackIsReplyOnly` (:784, a refused turn ran no tool, so it stays 0);
  - Chat's default script calls `list_productions` (missing), so its turns now report 1.
- **`Decide`'s Storage:** slots 9 to 12, which `storage-roundtrip` and the CI storage check compare.
- **Production state while a test runs:**
  - `Decide`'s `TimerSeconds` row;
  - the runners' entries' `http_config`;
  - the jobs of `Decide` and the three runners (`Apply` restarts them);
  - `ChatAgent` swapped to `StepsAgent` in `Test.Agent.Steps`.
- **The mock:** the new `rate-limited-after-tool`, `decide-late`'s delay, and the countdowns, which each test arms on its own key and clears.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19),** one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | `Derive`'s request timeout is timer \ 2 | `Bridge.Timeouts.TestDerive` |
| AC1 | `SessionConfigFor` passes no `timeoutMs` | `Bridge.Runner.TestSessionTimeout` |
| AC1, AC5 | `Details` writes no `retry` block | `Install.Provider.TestDetails`, `Agent.Decide.TestLongRetryAfterCapped` (the wait is about 30 s) |
| AC2 | `Check` accepts 111 | `Bridge.Timeouts.TestRefused`, `Bridge.Decide.TestBadSettings` |
| AC2 | `Apply` restarts nothing | `Agent.Decide.TestApplyTimer` (the same jobs; the held request answers after 20 s) |
| AC3 | The timer key returns its old error | `Agent.Decide.TestTimer`, `Bridge.Decide.TestTimerFallback` |
| AC3 | The timer is set with controlled keys "" | `Agent.Decide.TestTimer` (the answer waits for the late reply) |
| AC4 | `ResendDelay` ignores `toolsRun` | `Agent.Steps.TestToolRanNoResend` (a third request), `Bridge.Decide.TestResendDelay` |
| AC4 | `ResendDelay` always gives 0 | `Agent.Decide.TestRateLimitedResent` |
| AC4 | `error` is re-sent too | `Agent.Decide.TestReplyFallbacks` ("one request, never a second") |
| AC4 | The `resend` key skips the precheck | `Bridge.Decide.TestResendPrecheck` |
| AC4 | `Classify` drops the `resends` part of the `timedOut` rule | `Bridge.Fallback`, `Bridge.Decide.TestTimerFallback` |
| AC6 | `Answer` leaves `ToolsRun` 0 | `Bridge.Runner.TestToolsRun`, `Agent.Steps.TestTwoTools`, `TestToolRanNoResend` |
| AC6 | `ToolsRan` counts an unreadable reading as 0 | `Bridge.Runner.TestToolsRun` |

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **`Decide`'s state (a schema append):** four stored properties, `DecisionRef`, `Resends`, `StepCount` and `StepsSent`, in Storage slots 9 to 12. They hold one process's re-send state.
- **`Timeouts.Apply` writes `Decide`'s `TimerSeconds` row and restarts `Decide` and the runners** (decision 3). AD-19 names `SettingsOps` the only run-time settings writer; `Apply` is the bridge API that `SettingsOps` will call (Story 17.4), so that every timer change goes through `Derive`.
- **A timeout row's totals leave out the late call** (decision 11). Its `Usage` row is written after the row, with the same `DecisionRef`, and the day's spend and `Usage.Totals(ref)` count it.

**For the lead (ruling recommended, not blocking):**
- **Decision 7 (AD-8's order).**
  - **The rule:** a timer that fires after `Decide` re-sent a rate-limited attempt gives `rate_limited`, which is the AC's and FR-4's wording.
  - **A spine line is recommended (Rule 20):** "A timer that fires after `Decide` re-sent a rate-limited attempt gives `rate_limited`: the retries ran out (FR-4)."
- **Decision 2:** the shortest timer is 12 s.
- **Decision 10:** `ToolsRun` means any tool call, and an unknown counts as one.
- **Catalog wording (Lane B, Story 17.4):**
  - `fallbackReason.timeout` says 60 seconds, which becomes inexact once the timer can change;
  - `fallbackReason.rateLimited` ("retries ran out") also shows when a tool ran and `Decide`, by AD-8's rule, did not re-send.

**Lead's rulings at the spec gate (2026-10-23, Epic 1 runner, unattended):**
- **Veto window, kept as planned:** `Decide`'s slots 9 to 12 (inbox U-32); `Timeouts.Apply` writes `Decide`'s `TimerSeconds` row as the bridge method that `SettingsOps` calls (AD-19; U-33); a timed-out row's totals leave out the late call, which its own `Usage` row counts (U-34).
- **Decided:** decision 7 stands with no spine change (AD-8 is silent on how the re-sends end; the AC and FR-4 govern); decision 2 (12 s) and decision 10 (`ToolsRun`) stand.
- **Catalog wording:** ledgered as DW-100, routed to Story 17.4 (Lane B's text; nothing in this story changes it).

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

**Plan stage (2026-10-22, halted after planning as the dispatch asked).** The spec was planned from the cached `epic-1-context.md`, with Story 1.6's spec (done) as the continuity source and the spine's AD-2, 5 to 9, 19, 20, 22, 23, 26, 30, 31 and 33 and the S2 and S18 spikes. It meets the READY FOR DEVELOPMENT standard. Nothing was measured or run against a runtime in this stage; Task 0 holds the measurements. The ledger inbox (DW-56) is addressed by AC6. The Clarification Record lists three items for the veto window and four for the lead, and none of them blocks implementation.
