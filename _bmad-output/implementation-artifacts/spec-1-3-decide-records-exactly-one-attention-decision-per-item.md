---
title: 'Story 1.3: Decide records exactly one attention decision per item'
type: 'feature'
created: '2026-10-21'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-5, AD-6, AD-7, AD-8, AD-14, AD-18, AD-19, AD-20, AD-22, AD-26, AD-30, AD-31 and AD-33)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `Decide`, the business process that every model use passes through, is a stub that answers "not implemented", and `OcuTalon.Agent.Input.Render` returns "". So no item can get an attention decision, nothing is recorded in `OcuTalon.Bridge.Data.Decision`, and the standalone-bridge job in `lane-a.yml` is empty.

**Approach:**
- `Decide` admits a `Request` and returns the recorded decision for a repeated item. Otherwise it allocates the `DecisionRef` and sends the request asynchronously under `SetTimer` to the runner for its kind.
- When the reply comes, `Decide` checks it against the runner's new `ReplyClass` setting and filters the model-written text. For a user's item it turns an `ignore` or `digest` into `tellnow`. It then records one `Decision` row with its `TraceSessionId`, fires `decision.recorded` after the commit, and answers only its caller.
- `Agent.Input.Render` renders an Item as the model's user message: a local-time preamble from `OcuTalon.Data.Time`, then the user's own text, or quoted, labelled data for anything else.
- A minimal `OcuTalon.BridgeExample.Production` and a Lane A script prove the same path with the bridge alone in a clean namespace. `lane-a.yml`'s `standalone-bridge` job runs that script.
- Failures that Stories 1.6 and 1.7 will turn into fallbacks (a runner error, an unusable reply, the timer) end with an error status for now, and no row is recorded.

## Boundaries & Constraints

**Always:**
- **The pipeline (AD-6, AD-30).**
  - `Decide` sends only two kinds of message: the request to the runner for the kind (`decide` to `TriageAgent`, `diagnose` to `DiagnosisAgent`, `turn` to `ChatAgent`), and the `SetTimer` request to `Ens.Alarm`.
  - It answers only its caller, through the business-process framework.
  - It runs no `%AI` call, and only runners call `Chat`. `Test.Bridge.CodeRules` already enforces this.
- **The timer.**
  - The timer is a new `Decide` host setting, `TimerSeconds`, an integer with default 60.
  - A value outside 1 to 110 refuses the request before anything is sent (AD-5, AD-8).
- **The reply check (AD-7).**
  - A `decide` or `diagnose` request needs its runner's `ReplyClass`: a compiled `%JSON.Adaptor` class, read with `Ens.Director.GetHostSettingValue` from the active production.
  - The reply text is checked as one JSON object: `%JSONImport` with exceptions caught, then `%ValidateObject()`. Only surrounding white space, or one surrounding Markdown code fence, is removed first.
  - `DecisionPayload.%OnValidateObject` requires three things:
    - an `Outcome` in `Bridge.Msg.Enum` `OUTCOME`;
    - at least one non-blank reason;
    - a `Confidence` (import already refuses values outside 0 to 1, measured).
  - A `turn` needs no `ReplyClass`: its reply is the text. An empty text is not an answer.
- **The confidence (FR-1).** It is recorded rounded to two decimals and never changes the outcome.
- **The user rule (AD-6, FR-1).**
  - It applies to kind `decide` with provenance `user` when the outcome is `ignore` or `digest`.
  - The recorded and answered outcome becomes `tellnow`.
  - The first reason line becomes the code-written sentence "The outcome was changed because a message the user writes is always answered."
- **The filter (AD-28, AD-31).**
  - `ReplyFilterClass.Filter` runs exactly once on every model-written text, before anything is recorded or returned: each reason, and a turn's reply text.
  - It never runs on code-written text.
  - The class is checked with `Ext.Accessor.Check` before sending, and a bad class refuses the request (fail closed).
- **The row (AD-20).**
  - One row per recorded decision, holding:
    - `Ref` = the `DecisionRef`;
    - `Kind`, `ItemId`, `OwnerRef` and `Summary` from the request;
    - `Outcome`, `Reasons` (one per line), `Confidence`, `Fallback` 0 and `FallbackReason` "";
    - `Payload`, the checked payload exported as JSON, with the filtered reasons and the model's own outcome;
    - `TraceSessionId` = the process's `%SessionId`, which is the session of its decision message;
    - `RecordedAt` from the new `OcuTalon.Bridge.Time.NowUtc()`.
  - A turn row has outcome `tellnow` and no reasons, confidence or payload.
- **The host event (AD-31).**
  - The event comes after the row's `%Save` has returned OK. It is `OnEvent("decision.recorded", <OwnerRef>, HostSink.RefPayload(<Ref>))`, wrapped in its own error handling.
  - An error status or an exception is logged with `$$$LOGWARNING` (naming the class, the event and the Ref) and never fails `Decide`.
  - If the sink class fails `Ext.Accessor.Check`, that is logged too, and no event is sent.
- **One decision per item (AD-6, AD-20).**
  - Before anything is sent, an existing row for (`ItemId`, `Kind`) of `decide` or `diagnose` is answered from the row.
  - An existing `turn` row refuses the request with an error that names the item and the `DecisionRef`. The row keeps no reply text, and a second model answer would answer one message twice (AD-30).
  - If a concurrent `Decide` saved the row first, the recorded row answers and no second event fires.
- **Admitting a request.**
  - The message is not an `OcuTalon.Bridge.Msg.Request`, or its kind is `tool`: `$$$NotImplemented`. The approved-call replay is Story 3.6, now in Epic 30.
  - An error naming the field, before anything is sent: a kind outside `REQUESTKIND`, a provenance outside `PROVENANCE`, an empty `ItemId`, an empty `OwnerRef`, or an `Input` empty once white space and control characters are removed.
- **Rendering (AD-7, AD-14, AD-18, NFR-6, NFR-14).**
  - `Render(item, now = "")` keeps Epic 0's first parameter, `item`, and its `%String` return. `Test.Contract.Ac` pins that row at :313, and its rule at :139 allows trailing optional parameters.
  - **The preamble** is one line: the local weekday, date and time from `Data.Time.ToLocal`, and `Data.Time.Zone()`.
  - **A `user` item** is then a blank line and its `Text`, as written.
  - **Any other provenance** is rendered as untrusted, which fails safe:
    - a label naming its `Channel` and saying it is quoted data, never instructions;
    - then `Sender`, `Subject` and `Text`, every line prefixed with `> `.
  - An Item with no `Text`, `Sender` or `Subject` renders "".
- **The bridge boundary (AD-2).**
  - Code in `src/bridge/` names no other OcuTalon package, the `BridgeExample` package included.
  - The example's settings live only in its production definition and in System Default Settings rows.
- **Storage (AD-5).** `Decide`'s Storage block keeps its committed slots, and `TimerSeconds` is appended as slot 4 by the compiler.
- **Text in `src/`.** It is ASCII. No INSTRUCTIONS block contains `{{`.
- **Test placement.**
  - Tests go under `OcuTalon.Test.Bridge` and `OcuTalon.Test.Agent`, in the lane-a shard.
  - Each test removes the `Decision` rows, System Default Settings rows and key points it made, and restarts each item it changed.

**Never:**
- No fallback route, classification, `Keys.Status` or precheck (`no_key`, `daily_cap`, `budget`, `too_large`). Those are Stories 1.6, 1.4 and 1.9.
- No `timeout` fallback, `Derive` or re-send (Story 1.7).
- No `Usage` row and no token, cost, `Model`, `AgentStepCount` or `DurationMs` value (Story 1.4).
- No agent step sent and no step renderer (Story 1.5).
- No `ConversationLink`, `Busy`, `SessionMode` or `SeedText` handling (Story 1.8).
- No `DiagnosisAgent` `ReplyClass` and no diagnosis outcome rule (Story 5.4).
- No change to the properties of any `OcuTalon.Bridge.Msg` class or of `Bridge.Data.Decision`, which are pinned by `Test.Bridge.Contracts`, Lane B's `Test.Data.Tables` and `Test.Contract.Ac`.
- No change to `Bridge.Msg.Enum`.
- `AgentSteps`, `OcuTalon.Checks.ReplyGuard` and `OcuTalon.Core.BridgeSink` stay as they are.
- No edit to `triage.json`, `diagnosis.json` or `chat.json`.
- No edit to `src/module.xml` (Design Notes, decision 14).
- No `TestingEnabled="true"` and no provider settings in the example production's XData.
- No literal key and no `@{env:...:-fallback}` form.
- No edit to any contended Lane B path, including `docker/**`, `ci/**` (except `ci/mock/scenarios/A/`), `.github/workflows/ci.yml`, `OcuTalon.Core`, `.Msg`, `.Data.Time` and the Lane B test packages. No copy of a private Lane B helper. No new `ci/units.sh` entry.
- No commit and no push.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Untrusted decide (default script) | A `decide` Request, provenance `untrusted`, fresh `ItemId`, `OwnerRef` `instance`; `triage.json` answers `digest`, 0.5 | 1. **The answer:** a `DecisionResponse` with a new 22-character `DecisionRef`, `digest`, the mock's reason, 0.5, `Fallback` 0 and `Payload` = the reply's JSON.<br>2. **The row:** one row with the same values and `Kind` `decide`, whose `TraceSessionId` is the session id of the response header.<br>3. **The runner's request:** it carries that `DecisionRef`.<br>4. **The timer:** the `Ens.AlarmRequest` from `Decide` has `Timeout` 60.<br>5. **Sends:** `Decide`'s only headers in the session are to `TriageAgent`, `Ens.Alarm` and the caller. | No error expected |
| Low confidence | Marker `decide-act-low-confidence` (`act`, 0.12), untrusted | Row and response: `act`, 0.12 | No error expected |
| User, digest | Provenance `user`, default script (`digest`) | `tellnow`. Reasons: line 1 is "The outcome was changed because a message the user writes is always answered.", then the mock's reason. `Payload` keeps `"outcome":"digest"`. | No error expected |
| User, ignore | Provenance `user`, marker `decide-ignore` | `tellnow`, with the code-written line first | No error expected |
| User, act | Provenance `user`, marker `decide-act-low-confidence` | `act`, 0.12, unchanged | No error expected |
| Untrusted, ignore | Provenance `untrusted`, marker `decide-ignore` | `ignore` | No error expected |
| Repeat | The same `ItemId` sent again as `decide` | The first row's `DecisionRef`, outcome, reasons and confidence. No new mock request, no header to `TriageAgent` in the second session, and no second row. | No error expected |
| Turn | Kind `turn`, provenance `user`, `Input` = `Render(item)`; `chat.json` makes two requests, a tool call fed back, then text | 1. **The answer:** a `Reply` whose `Text` is the mock's final text, with `Outcome` `tellnow` and its `DecisionRef`.<br>2. **The row:** `Kind` `turn` and `tellnow`.<br>3. **The log:** in every logged request, the rendered `Input` is the text of a user-role message, and no `tool_result` block holds the item's text. | No error expected |
| Repeat turn | The same `ItemId` sent again as `turn` | Nothing sent and no new row | An error naming the item and the recorded `DecisionRef` |
| Diagnose | Kind `diagnose` (`DiagnosisAgent` names no `ReplyClass` until Story 5.4) | Nothing sent, no row | An error naming `DiagnosisAgent` and `ReplyClass` |
| Invalid reply | Marker `invalid-reply` | No row; the caller gets no response | An error status that names the reply check (Story 1.6 makes it `invalid`) |
| Runner error | Marker `provider-error` | No row | The runner's error status with AI Hub's text (Story 1.6 classifies it) |
| Timer | `TimerSeconds` row = 2, `Decide` restarted, marker `decide-late` (answers after 6 s) | No row, before or after the late reply arrives. The late reply's header is marked discarded. | An error naming the timer and `TriageAgent` (Story 1.7 makes it `timeout`) |
| Refused requests | Kind `tool`; an `Ens.StringRequest`; kind `zz`; provenance `zz`; empty `ItemId`; empty `OwnerRef`; `Input` of white space only | Nothing sent | `tool` and the foreign class get 5003. The others get an error naming the field. |
| Bad settings (pure) | `TimerSeconds` 0, 111 or `x`; a `ReplyFilterClass` that is missing or does not extend its base | Nothing sent | An error naming the setting |
| Reply check (pure) | Valid JSON; JSON inside a `json` code fence; outcome `maybe`; `"reasons":[]`; a blank reason; no confidence; confidence 1.5; an extra field; not JSON; a JSON array | The first two pass. Every other input fails. | An error status naming the check |
| Filter (in-process) | `Conclude` with the probe filter (prefixes `[f] `) for a decide reply and a turn reply | Each model reason is filtered once on the row, in `Payload` and in the response, and so is the turn's `Text`. The code-written user line is not filtered. | No error expected |
| Sink (in-process) | `Conclude` with the probe sink in record, error and throw modes | **Record:** one call of `decision.recorded` with the request's `OwnerRef` and payload exactly `{"ref":<Ref>}`; during the call, `$TLevel` is 0 and the row exists.<br>**Error and throw:** the row is recorded and the response is OK. | A warning row in `Ens_Util.Log` names the sink class and the Ref |
| Concurrent save (in-process) | `Conclude` for an (`ItemId`, `Kind`) whose row another call saved first | The existing row's response. No second row and no event. | No error expected |
| Render, user | `Item` provenance `user`, `Text` "Is the Orders feed fine?", `now` = `2025-03-04T15:06:07Z` | The preamble from `Data.Time.ToLocal(now)` and `Zone()`, a blank line, then the text, unchanged | No error expected |
| Render, untrusted | Provenance `untrusted` (and `""`), channel `mailbox`, sender, subject, two-line text holding `[[mock:x]]` | The preamble, a label naming `mailbox` as quoted data and never instructions, then the sender, subject and every text line, each prefixed `> ` | No error expected |
| Render, empty | `##class(OcuTalon.Msg.Item).%New()` | "" | No error expected |
| The bridge alone | `src/bridge/cls` loaded into a fresh namespace with Interoperability and no Foundation (CI or throwaway); `Installer.Run()`; the example production with its runner's `ProviderConfig` and `$Production` `TestingEnabled` as System Default Settings rows | 1. **The response:** a `decide` request through `EnsLib.Testing.Service.SendTestRequest("Decide", ...)` gets a `DecisionResponse` with `tellnow` (scenario `bridge-example`).<br>2. **The row:** a `Decision` row for its `ItemId` whose `TraceSessionId` is that session.<br>3. **The extensions:** `Ext.Accessor.ClassFor` gives the three base classes.<br>4. **The namespace:** no `OcuTalon.*` class outside `OcuTalon.Bridge` and `OcuTalon.BridgeExample`, and no web application of the namespace that names an OcuTalon class or `/ocutalon`. | The script fails, naming the failed check |

</intent-contract>

## Code Map

- **Bridge (Lane A):**
  - **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:**
    - The `STUB` parameter (:9) and the stub `OnRequest` (:22-25) go away.
    - `SETTINGS` (:11) gains `TimerSeconds`.
    - Keep the three extension properties (:14-20) and the committed Storage block (:27-43), which has slots 1 to 3. Lane B's `docker/tests/test-storage-roundtrip.sh:103-136` uses this file as its control: it removes slot 3 and expects the compiler to give it back, and expects the original to export unchanged. So the committed block must stay exactly what the compiler generates.
  - `src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`: `OnMessage` (:13-27) is unchanged. `ResolveModel` (:34) is pinned by `Ac.cls:336`. Add the host setting `ReplyClass` here; the class has no `SETTINGS` parameter yet.
  - `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: `Answer` (:185) already refuses an empty `Input` and kind `tool`. `Decide` refuses them first, so nothing reaches the runner.
  - **Messages, unchanged:**
    - `Msg/Request.cls` (13 properties);
    - `Msg/Result.cls`: `DecisionRef`, `Outcome`, `Reasons`, `Confidence`, `Fallback`, `FallbackReason` and the totals;
    - `Msg/DecisionResponse.cls` (`Payload`);
    - `Msg/Reply.cls`;
    - `Msg/DecisionPayload.cls` (`Outcome`, `Reasons` as a list, `Confidence` with MINVAL 0, MAXVAL 1 and SCALE 2), which gains only `%OnValidateObject`.
  - `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls`: the properties are pinned exactly by Lane B's `Test/Data/Tables.cls:157-187`. `ItemIdKindIndex` (:73) is unique, and so is `RefIndex` (:71).
  - **The extension classes:**
    - `Ext/Accessor.cls`: `Check(setting, class)` (:37) and `ClassFor` (:16);
    - `Ext/HostSink.cls`: `OnEvent` (:32), `DECISIONRECORDED` (:13) and `RefPayload` (:38);
    - `Ext/ReplyFilter.cls`: `Filter` (:9).
  - `Ids.cls:7` `NewRef()`. `Msg/Enum.cls`: `OUTCOME`, `PROVENANCE` and `REQUESTKIND`.
  - `Operation/Steps.cls` (`AgentSteps`) stays a stub: Story 1.5.
- **Product (Lane A):**
  - `src/ocutalon/cls/OcuTalon/Agent/Input.cls:7-10`: the stub `Render`.
  - `src/ocutalon/cls/OcuTalon/Agent/Triage.cls`: the shape the example agent mirrors (`MODEL`, `MOCKKEY` on one line, `TOOLSETS = ""`, INSTRUCTIONS asking for one JSON object of `DecisionPayload`'s shape).
  - `src/ocutalon/cls/OcuTalon/Production.cls`: Decide is at :18-21. TriageAgent is at :24-26, inside Lane A's region (:15-43).
- **Lane B, read and call only:**
  - `src/ocutalon/cls/OcuTalon/Data/Time.cls`: `NowUtc` (:15), `ToLocal` (:22), `Zone` (:52) and the `WEEKDAYS` parameter (:8).
  - `src/ocutalon/cls/OcuTalon/Msg/Item.cls`: `ItemId`, `SessionRef`, `Channel`, `Provenance`, `Text`, `Sender`, `Subject`, `CatalogKey` and `Slots`.
  - `Test/Contract/Mock.cls`: `LogMark` (:365), `LogSince` (:378) and `MissingReason` (:291).
  - `Test/Contract/Ac.cls:313` (the `Render` row) and `:224-227` (the named properties).
  - **`docker/tests/test-production.sh`:**
    - The row 16 sweep (:155-181) targets only `"stub": 1` items of the oracle, so Decide leaves it.
    - `check_items_run` and `check_clean_start` (`lib-live.sh:616` and `:646`) need Decide to run with no error row at start.
  - `docker/tests/test-pinned-sources.sh:62-66`: `bridge_first` pins the first two `<Resource>` lines.
- **Ens and AI Hub, read only** (BP = `irislib/Ens/BusinessProcess.cls`):
  - **The callbacks.** `OnRequest` (BP:839) returns `response` as `%response`. `OnResponse(request, .response, callrequest, callresponse, pCompletionKey)` (BP:846) runs per reply. The reply goes to the caller when nothing is pending (BP:478-480). A leftover timer does not block completion (BP:401-416).
  - **The timer.**
    - `SetTimer(timeout, key)` (BP:189-197) sends an `Ens.AlarmRequest` to `Ens.Alarm` in the process's session.
    - When it fires, `OnTimeout` runs, the pending entries it controls are removed, and `OnResponse` runs with `callresponse` an `Ens.AlarmResponse` and the timer's key (BP:357-435).
    - A late runner reply is marked discarded and never reaches `OnResponse` (BP:294-297, 323-326).
  - **A runner error** goes to `OnError` (BP:332-339, 875-878). Its default returns the status, which the caller gets.
  - **The session.** `%SessionId` and `%SuperSession` are the primary request's (BP:259-260). The reply to the caller is in that session (`Ens/MessageHeader.cls:105`).
  - **Persistence.** Stored properties survive between callbacks. The framework opens no transaction, so a `%Save` is committed when it returns (no TSTART in BP, Actor or Host).
  - **Settings.** An item `<Setting>` wins over a System Default Settings row, which wins over `InitialExpression` (`irislib/Ens/Config/Item.cls:315-331`).
  - **Testing.** A `$Production` `TestingEnabled` row enables the testing service, overriding the definition (`irislib/Ens/Director.cls` about :869-873). `EnsLib.Testing.Service.SendTestRequest(target, request, .response, .sessionId, getReply)` is at `irislib/EnsLib/Testing/Service.cls:35`. Row lookup is in `irislib/Ens/Config/DefaultSettings.cls:198-221`.
  - `irislib/Ens/Util/MessageBodyMethods.cls:55-69`: Visual Trace's contents pane shows an XML-enabled body's XML.
- **Tests and fixtures (Lane A):**
  - **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:**
    - `Send` (:114) goes through `ApprovalStartIn` with a 240 s wait.
    - `Ask` (:126) builds a `Request` with only `Kind`, `Provenance` and `Input`.
    - Also: `PointKeys` (:142), `RestoreKeys` (:149), `FindRequests` (:212), `Restart` (:62), `WaitAllRun` (:71), `EventMark` (:93) and `EventRows` (:102).
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`: the private `Ready` (:321) and `Point` (:345), and the `OnAfterOneTest` pattern (:71-90).
  - **`src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:**
    - The `Items` oracle: Decide at :591 with `"stub": 1`, TriageAgent at :594.
    - `TestStubsAnswer` (:136-169) asserts `STUB` = the `stub` flag.
    - `TestDefinition` (:74-131) compares the settings with their target.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls:30-37`: `TestNeutralValues` asserts that `Render` of an empty Item is "". That stays true, but the comment at :6 and :31 still calls it a stub value.
  - `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls:37-45`: `TestDecisionPayloadJson` imports a valid payload. That stays valid.
- **The mock (Lane A's folder `ci/mock/scenarios/A/`, plus read-only facts):**
  - `triage.json` (mockkey `triage`): `digest`, 0.5.
  - `chat.json`: a tool call, then text.
  - `invalid-reply.json`: outcome `maybe`, reasons a string, confidence 2.
  - `provider-error.json` also exists.
  - `held-past-timer.json` waits 120 s, which is too long for a test.
  - **The scenario loader** (`ci/mock/scenarios.mjs:145-275`):
    - `name` is kebab-case and equals the file name, and a marker equals its name;
    - each reply holds exactly one of `text`, `toolUse` or `body`;
    - the files sit directly in `A/`, with no subfolder.
  - `ci/mock/test/constants.test.mjs:41-47, 70-80`: every `MOCKKEY` under `src/bridge/cls/OcuTalon/BridgeExample/` needs exactly one `mockkey` scenario.
  - `ci/mock/mock.mjs:152-161` logs messages whole. Content is a string or blocks of `text`, `tool_use` and `tool_result`, so a tool result arrives as a user-role message of `tool_result` blocks.
- **The CI recipe (Lane B, sourced and called read-only):**
  - **`ci/iris.sh`:**
    - Sourcing it runs nothing (:413-414). It also `cd`s to the root and sources `ci/units.sh` and `docker/tests/lib-live.sh`.
    - `setup_tag` (:38), `preflight` (:77) and `cmd_build`.
    - `teardown` removes `ocutalon-<label>-<tag>-...`.
  - **`docker/tests/lib-live.sh`:**
    - `live_start <label>` (:53-84) sets `P`, `tmp` and `deadline`, takes the lock, sets the EXIT trap that tears down, and builds the web bundle.
    - Also: `dc` (:239-243), `live_track_image` (:247), `iris_script` (:303-313), `check_session` (:465-470), `pass`/`fail`/`die` (:269-278) and `settle_scheduler` (:662).
  - `docker/tests/test-install-start.sh:707-735`: row 5's recipe, copying a CPF in, `iris merge`, then `LoadDir("/opt/ocutalon/src/bridge/cls","ck-d",.errors,1)` and `Installer.Run()` in the new namespace.
  - `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls:275`: `EnableNamespace(ns, 0, , 1)` enables Interoperability with no Foundation installer (measured in Story 0.10).
  - `ci/compose.ci.yml`: the IRIS container gets `OCUTALON_MODEL_BASE_URL=http://mock:8080/v1/`, `OCUTALON_MOCK_KEY_HEADER=1`, no key and no `TZ`.
  - **`.github/workflows/lane-a.yml:21-27`:** the empty job.
  - **The rules of `docker/tests/test-ci-config.sh`:**
    - the top-level permissions are exactly `contents: read`;
    - the fork guard is exactly the current `if:`;
    - the runner is `[self-hosted, ocutalon]`;
    - actions are pinned by sha with `# vX.Y.Z`, and every checkout sets `persist-credentials: false`;
    - no `secrets`, no cache, and no artifact upload on a self-hosted job;
    - a job that runs `ci/iris.sh` has a later `if: always()` `ci/iris.sh teardown` step;
    - no `strategy.matrix.group`;
    - no timeout pin.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- Use the slot for process-local facts and a throwaway of tag `e1s3a` for running-production facts.
- **(a)** After the compile, `%ValidateObject()` calls `DecisionPayload.%OnValidateObject` for each row of the "Reply check" matrix.
- **(b)** On the first throwaway run, confirm the BP facts of the Code Map:
  - the `Ens.AlarmRequest` header and its `Timeout` in `Decide`'s session;
  - the response header's `SessionId` = `Decide`'s `%SessionId`;
  - the late reply's header status;
  - the error text the caller gets when the runner fails.
- **(c)** In the standalone run, the exact System Default Settings rows that enable the testing service and set the runner's `ProviderConfig` for `OcuTalon.BridgeExample.Production`, and that no production runs in the new namespace before the example starts.
- **(d)** The logged shape of `chat.json`'s second request: where the `tool_result` block sits and what it holds.
- **(e)** Where an in-process `$$$LOGWARNING` lands in `Ens_Util.Log` (`Type`, `SourceClass`, `ConfigName`).
- If a fact contradicts this spec in a way that changes an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The bridge.**
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`**: build the process. Rationale: AD-6, AD-7, AD-20, AD-26, AD-30, AD-31; FR-1.
  - **Remove** `STUB` and the stub handler.
  - **Settings.** Add the setting `TimerSeconds` (`%Integer`, `InitialExpression` 60, category `Bridge`). Add the parameters `RUNNERS` (`decide:TriageAgent,diagnose:DiagnosisAgent,turn:ChatAgent`), `MAXTIMER` (110) and `USERANSWERED` (the sentence).
  - **`OnRequest`:**
    1. Admit the request (Boundaries, "Admitting a request").
    2. For a recorded (`ItemId`, `Kind`), answer from the row, or refuse a turn.
    3. Resolve the runner, its `ReplyClass` (decide and diagnose), the filter class and the timer, and refuse on any problem.
    4. Send a clone of the request, with a new `DecisionRef`, through `SendRequestAsync(runner, clone, 1, "reply")` and `SetTimer(..TimerSeconds, "timer")`.
  - **`OnResponse`:**
    - The `timer` key answers with an error naming the timer and the runner.
    - The `reply` key calls `Conclude`.
  - **`Conclude(request, decisionRef, reply, replyClass, filterClass, sinkClass, traceSessionId, Output response) As %Status`** is a class method: the in-process tests drive the BP's own logic through it. It does, in order:
    1. Interpret the reply (decide and diagnose), or check that its text is non-empty (turn).
    2. Filter.
    3. Apply the user rule.
    4. Check for a concurrent row.
    5. Save the row.
    6. Fire the event.
    7. Build the `DecisionResponse`, or a clone of the runner's `Reply` with `Text` filtered, `DecisionRef` and `Outcome` `tellnow`.
  - Keep these as separate class methods that the tests call:
    - the admission of a request;
    - the settings check (the timer range, the filter class, and the runner's `ReplyClass` given its value);
    - the reply check;
    - the event firing;
    - the row-to-response method.

    `OnRequest` and `OnResponse` only call them.
- **`src/bridge/cls/OcuTalon/Bridge/Msg/DecisionPayload.cls`**: add `%OnValidateObject()`, which checks the outcome, at least one non-blank reason and the confidence. No property change. Rationale: AD-7.
- **`src/bridge/cls/OcuTalon/Bridge/Operation/AgentRunner.cls`**: add `Parameter SETTINGS = "ReplyClass:Basic"` and `Property ReplyClass As %String(MAXLEN = 128)`, documented as the `%JSON.Adaptor` class that `Decide` checks this runner's reply against (empty for a text reply). Update the class comment. Rationale: AD-7.
- **`src/bridge/cls/OcuTalon/Bridge/Time.cls`** (new): `NowUtc()`, `YYYY-MM-DDThh:mm:ssZ`, the same contract as `Data.Time.NowUtc`. Story 1.4 adds the day boundary. Rationale: AD-2, AD-18.
- **`src/bridge/cls/OcuTalon/BridgeExample/Agent.cls`** (new): an `%AI.Agent` with these parameters:
  - `MODEL = "claude-haiku-5-5"`;
  - `MOCKKEY = "bridge-example"`, written on one line;
  - `TOOLSETS = ""`;
  - INSTRUCTIONS with no `{{` that ask for one JSON object of `DecisionPayload`'s shape.

  Rationale: AD-7, FR-5.
- **`src/bridge/cls/OcuTalon/BridgeExample/Production.cls`** (new): `OcuTalon.BridgeExample.Production` with `TestingEnabled="false"`. Rationale: AD-2, AD-31, FR-5. Its items:
  - `Decide` (pool 1, no settings);
  - `TriageAgent` (`AgentRunner`, pool 1), with the adapter's `AgentClass` and `AgentAllowList` = `OcuTalon.BridgeExample.Agent` and the host's `ReplyClass` = `OcuTalon.Bridge.Msg.DecisionPayload`;
  - `AgentSteps` (`Steps`, pool 1).

**The product.**
- **`src/ocutalon/cls/OcuTalon/Agent/Input.cls`**: implement `Render(item, now = "")` (Boundaries, "Rendering") and update the class comment. Rationale: AD-7, AD-14, AD-18, NFR-6, NFR-14.
- **`src/ocutalon/cls/OcuTalon/Production.cls`**, Lane A's region only: add `<Setting Target="Host" Name="ReplyClass">OcuTalon.Bridge.Msg.DecisionPayload</Setting>` to `TriageAgent`. Rationale: AD-5, AD-7.

**The mock (Lane A's folder).** Each file is new under `ci/mock/scenarios/A/`, with one reply of status 200:
- `decide-ignore.json`: marker `decide-ignore`, text `{"outcome":"ignore","reasons":["The CI mock ignores this item."],"confidence":0.9}`.
- `decide-act-low-confidence.json`: marker of the same name, text `{"outcome":"act","reasons":["The CI mock asks for an action."],"confidence":0.12}`.
- `decide-late.json`: marker of the same name, `delayMs` 6000, text `{"outcome":"tellnow","reasons":["The CI mock answers late."],"confidence":0.5}`.
- `bridge-example.json`: mockkey `bridge-example`, text `{"outcome":"tellnow","reasons":["The CI mock tells the example's user now."],"confidence":0.7}`.

**CI (Lane A).**
- **`release/standalone-bridge.sh`** (new; `release/` is Lane A's folder): the "The bridge alone" row. Rationale: FR-5, AD-2, AD-29.
  - **Setup.** It sources `ci/iris.sh`, then runs `setup_tag`, `preflight` and `live_start sbridge`, then `dc up -d --build --wait`, then `live_track_image`.
  - **The namespace.**
    - Copy in and merge a CPF that creates `%DB_OCUBRIDGE`, the database `OCUBRIDGE` and the namespace `OCUBRIDGE` without Interoperability.
    - Then, in `%SYS`, run `EnableNamespace("OCUBRIDGE", 0, , 1)`.
  - **In `OCUBRIDGE`, through `check_session`:**
    1. `LoadDir` of `/opt/ocutalon/src/bridge/cls`, then `Installer.Run()`.
    2. Check that no other OcuTalon class is there.
    3. Fail unless `OCUTALON_MOCK_KEY_HEADER` is `1` and `OCUTALON_MODEL_BASE_URL` is set.
    4. Write the two System Default Settings rows:
       - the runner's inline `ProviderConfig`: `{"model_provider":"anthropic","api_key":"@{env:OCUTALON_MOCK_KEY_HEADER}","base_url":<OCUTALON_MODEL_BASE_URL>,"http_config":{"custom_headers":{"x-ocutalon-mockkey":"bridge-example"}}}`;
       - the `$Production` `TestingEnabled` 1.
    5. `StartProduction`.
    6. Check the three `Ext.Accessor.ClassFor` values.
    7. Send the `decide` request.
    8. Check the response and the row.
    9. Check that no OcuTalon web application points at the namespace.
    10. Settle the scheduler and `StopProduction`.
  - **Output and exit.** It prints `PASS`/`FAIL` lines and exits 1 on any failure. The EXIT trap tears the project down.
- **`.github/workflows/lane-a.yml`**: replace the echo step. Rationale: AD-29, REL-4.
  - Keep the triggers, permissions, concurrency, fork guard and runner exactly as they are.
  - Set `timeout-minutes: 20`, and the job env `IRIS_IMAGE: ocutalon-iris-base:2026.3.0AI.154.0`, `OCUTALON_RUN_TAG: ${{ github.run_id }}-${{ github.run_attempt }}-bridge` and `OCUTALON_LIVE_DEADLINE: "900"`.
  - The steps:
    1. The checkout pinned as in `ci.yml` (`actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`), with `persist-credentials: false`.
    2. `bash ci/iris.sh build`.
    3. `bash release/standalone-bridge.sh`.
    4. `bash ci/iris.sh teardown`, with `if: always()`.
  - Update the header comment.

**Tests.**
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeFilter.cls`** (new fixture): extends `Ext.ReplyFilter`. `Filter` returns `"[f] "_text` and counts its calls in `^||ZzProbeFilter`.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls`** (new fixture): extends `Ext.HostSink`. Its mode comes from `^||ZzProbeSink("mode")`:
  - `record` (the default) keeps each call's type, owner, payload JSON, `$TLevel`, and whether the row exists then;
  - `error` returns an error status;
  - `throw` throws.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Decide.cls`** (new, in process, no mock): the pure and in-process matrix rows:
  - Refused requests;
  - Bad settings;
  - Reply check;
  - Filter;
  - Sink;
  - Concurrent save;
  - the user rule in all four combinations;
  - confidence 0.12 kept and 0.123 rounded to 0.12;
  - the row-to-response method for a recorded decide.

  Each test deletes the rows and the process-private globals it made.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Render.cls`** (new, pure): the three Render rows.
  - The expected preamble is built from `Data.Time.ToLocal(now)` and `Zone()` with a fixed `now` in the past.
  - It also checks that a text line starting `> ` stays inside the quote, and that a provenance of `""` is untrusted.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`**:
  - Add `NewRequest(kind, provenance, input, Output ref)`. It sets `ItemId` = `ref` (from `NewRef`), `OwnerRef` `instance`, `Channel` `system`, `Summary` "Test <ref>", and `Input` = `input` with `" (test <ref>)"` appended.
  - `Ask` uses it.
  - Move `Runners.Ready` here as `ReadyReason()` (it returns "" or the reason), and `Runners` calls it.
  - Add `DecisionOf(itemId, kind)` (the row or "") and `Headers(sessionId, source)` (the target and body class of each header).
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls`** (new; live, throwaway only, the same guards as `Runners`): every other matrix row, through `Decide` with `RunnerFixture.Send`/`Ask`.
  - Points the keys first.
  - `OnAfterOneTest` deletes its rows, deletes the `TimerSeconds` row, restarts `Decide` if the test changed it, restores the keys, and waits until `TriageAgent` has answered the late request.
  - Tests:
    - `TestDecision`, which also checks the `Ens.Alarm` `Timeout`, the sends and the `DecisionRef` on the runner's request;
    - `TestLowConfidence`, `TestUserRule`, `TestRepeat`;
    - `TestTurn`, which covers the `tool_result` check and the repeated turn;
    - `TestDiagnoseNeedsReplyClass`, `TestUnusableEndsWithError` (invalid reply and runner error), `TestTimer`;
    - `TestRefused` (one live refusal, and the foreign class);
    - `TestTraceFields`: the XML of the recorded `DecisionResponse` holds the five names, and the row's `TraceSessionId` is its header's session.
- **`src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`**: in the oracle, set Decide's `"stub": 0` and add TriageAgent's `{"target": "Host", "name": "ReplyClass", "value": "OcuTalon.Bridge.Msg.DecisionPayload"}`. Update the header.
- **`src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls`**: the comments at :6 and :31 say that `Render` of an empty Item is "", and no longer call that a stub value. The assertion stays.
- **`src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls`**: `Ready` calls `RunnerFixture.ReadyReason()`. No behaviour change.
- Prove every matrix row with these tests and the script.

**Acceptance Criteria:**
- **AC1, the decision.**
  - **Given** a `decide` `OcuTalon.Bridge.Msg.Request` (`Input`, `Kind`, `Provenance`, `ItemId`, `OwnerRef`, `TraceRef`, `Channel`, `ThreadSessionId`) sent to the running `Decide` item,
  - **when** `Decide` handles it,
  - **then:**
    - it allocates a `DecisionRef` that its request to `TriageAgent` carries;
    - it sends that request asynchronously under `SetTimer` with `TimerSeconds` (the alarm's `Timeout` is 60 by default);
    - it checks the reply against `TriageAgent`'s `ReplyClass`, `OcuTalon.Bridge.Msg.DecisionPayload`;
    - it records one `Decision` row, unique on (`ItemId`, `Kind`), with outcome `ignore`, `digest`, `tellnow` or `act`, plain-English reasons and a confidence between 0 and 1, and answers its caller with the same in a `DecisionResponse`;
    - a mock reply of `act` with confidence 0.12 is recorded and answered as `act` with 0.12;
    - in the session, `Decide` sends only the runner request and the timer request, and answers only its caller.

  (`Test.Agent.Decide`, `Test.Bridge.Decide`)
- **AC2, one decision per item.**
  - **Given** an `ItemId` that already has a `decide` row,
  - **when** a `decide` request for it arrives again,
  - **then** `Decide` answers with the recorded decision, and the mock's log, the trace and the table show no model request, no runner request and no new row.

  (`Test.Agent.Decide.TestRepeat`)
- **AC3, the user's own message.**
  - **Given** an item with provenance `user`,
  - **when** the mock answers `ignore` or `digest`,
  - **then** `Decide` records and answers `tellnow`, and the first reason line says that the outcome was changed because a message the user writes is always answered. A user's `act`, and every untrusted outcome, stay as the model gave them.

  (`Test.Agent.Decide.TestUserRule`, `Test.Bridge.Decide`)
- **AC4, filter, host event and trace.**
  - **Given** a reply with model-written text,
  - **when** `Decide` records it,
  - **then:**
    - the `ReplyFilterClass` has run once on every model-written text before anything is recorded or returned;
    - after commit, `HostSinkClass.OnEvent` receives `decision.recorded` with the row's `OwnerRef` and the payload `{"ref": <Ref>}` only;
    - an `OnEvent` error or exception is logged and never fails `Decide`;
    - the decision message, as Visual Trace's contents pane shows it, holds `Outcome`, `Reasons`, `Confidence`, `Fallback` and `FallbackReason` under those names;
    - the row's `TraceSessionId` is the session that holds that decision message.

  (`Test.Bridge.Decide`, `Test.Agent.Decide.TestTraceFields`)
- **AC5, rendering.**
  - **Given** one Item with provenance `user` and one with provenance `untrusted`,
  - **when** `OcuTalon.Agent.Input.Render` renders them,
  - **then:**
    - the user's text becomes the model's user message;
    - the untrusted content becomes quoted data labelled with its channel;
    - both start with a preamble that states the local time and zone from `OcuTalon.Data.Time`;
    - for a user turn through `Decide` whose script feeds a tool result back, the mock's log shows the rendered text as a user-role message in every request and never inside a `tool_result` block.

  (`Test.Agent.Render`, `Test.Agent.Decide.TestTurn`)
- **AC6, the bridge alone (Integration AC).**
  - **Given** `src/bridge/` loaded alone into a clean Interoperability namespace and `OcuTalon.Bridge.Installer` run,
  - **when** `OcuTalon.BridgeExample.Production` receives a `decide` request through Ens's testing service; the production holds only `Decide`, a `TriageAgent` runner (the example agent on its allow-list, inline provider settings) and `AgentSteps`, configured only through production settings,
  - **then** a `Decision` row and a `DecisionResponse` are recorded and returned, with every extension class at its do-nothing default and no other OcuTalon package in the namespace. The consumer, Ens's testing service acting as the example's caller, gets the scenario's outcome. `lane-a.yml`'s `standalone-bridge` job runs this on the IRIS runner.

  (`release/standalone-bridge.sh`)

## Spec Change Log

## Review Triage Log

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-2:** the bridge boundary. `BridgeExample` counts as bridge, and the standalone path uses `LoadDir`.
- **AD-5:** structure in the XData (`ReplyClass`), the append-only storage of `Decide`, and the 110-second ceiling of the timer.
- **AD-6:** `Decide`'s role, one decision per item, and the user rule.
- **AD-7:** `ReplyClass`, `Agent.Input` as the one renderer, and checked JSON.
- **AD-8:** the staging below. No fallback is built here.
- **AD-14:** provenance, and untrusted content as quoted data.
- **AD-18:** the preamble from `Data.Time`, and `Bridge.Time` inside the bridge.
- **AD-19:** the example's settings live in System Default Settings rows, and no key is written.
- **AD-20:** the `Decision` row, the allocated `Ref`, and `TraceSessionId`.
- **AD-22:** the mock is extended only by files under `ci/mock/scenarios/A/`.
- **AD-26:** the decision message's field names, and its session as the trace target.
- **AD-30:** `Decide` answers only its caller.
- **AD-31:** the filter runs before recording, and the sink is called after commit and never fails `Decide`.
- **AD-33:** no new item class. The example's items are the three bridge classes that the ownership table already gives Lane A, and Story 13.1 adds the example's own items to the tables.

No acceptance criterion contradicts an AD's Rule.

**Decided in-stage:**
1. **Failures end with an error status until Stories 1.6 and 1.7.** A runner error, a reply that fails the check, an empty turn reply and the timer all end `Decide` with an error status, and no row is recorded. Nothing unusable is ever treated as an answer. Story 1.6's "any fallback is recorded as `tellnow`" and Story 1.7's `timeout` replace these paths. Story 2.4's `Conversation` already treats an error status from `Decide` as a fallback.
2. **Fixed runner names.** The kind-to-runner map is a parameter that holds the spine's three names. The example therefore names its one runner `TriageAgent`. A setting that names the runner per kind is left to Story 13.1, if its full example needs other names.
3. **Where `ReplyClass` lives.** It is a host setting of `AgentRunner`, as AD-7 says, and it is written in the XData as structure, like `AgentClass`. It is not a seed. `Decide` reads it from the active production.
4. **Diagnose without a `ReplyClass`.** `DiagnosisAgent` has none until Story 5.4 builds `OcuTalon.Watch.Msg.DiagnosisPayload`. So a `diagnose` request is refused before sending, with an error naming the runner and the setting. No payload class is guessed.
5. **The turn.** A turn is recorded with outcome `tellnow`, because a reply is told now. Its `Reply` is a clone of the runner's reply with the filtered `Text`, the `DecisionRef` and the outcome. A repeated turn is refused (Boundaries); Story 1.8 has to settle how a `SessionBroken` attempt and its one retry fit the (`ItemId`, `turn`) key (follow-on).
6. **The checked reply.**
   - It is strict: `%JSONImport` also refuses an unknown field, which was measured.
   - A single surrounding code fence is removed, so that Claude Haiku's occasional fence does not end the demo path in an error.
   - `%OnValidateObject` adds the checks that import does not make: the outcome enumeration, at least one non-blank reason, and a confidence that is present. All were measured to pass import otherwise.
7. **Reasons on the row.**
   - The reasons are joined with a line feed. A line break inside a model reason becomes a space, and blank reasons are dropped.
   - The user rule's line comes first, because it explains why the outcome differs from the model's reasons.
   - `Payload` keeps the model's own outcome, for audit.
8. **The confidence** is rounded to two decimals, as the property's `SCALE` says. Import keeps 0.123 as is (measured).
9. **Extension classes.** `Decide` checks its own setting values with `Ext.Accessor.Check`, since the values are already the BP's properties; this is the same accessor, without a production lookup.
   - A bad filter class refuses the request: no unfiltered text, fail closed.
   - A bad sink class is logged and skips the event. The decision stands.
10. **The sink failure** is logged with `$$$LOGWARNING`, not `$$$LOGERROR`: the decision succeeded, and Lane B's `check_clean_start` counts error rows.
11. **A concurrent repeat.** A second `Decide` for the same item that passes the pre-send check in a race is answered from the row that won when it records. The model is called twice, but one decision is recorded. No lock is held across callbacks, because another actor job may run the response.
12. **`OcuTalon.Bridge.Time`** is created now with `NowUtc` only, because `RecordedAt` needs it and AD-2 forbids `Data.Time`. Story 1.4 adds the day boundary.
13. **The preamble and the quoting.**
    - The preamble line holds the weekday, the ISO date and the time to the minute, and the zone. The reminder tool of Story 1.10 needs the weekday to work out "Thursday at 10".
    - Untrusted lines are quoted with `> ` on every line, so content cannot close a delimiter.
    - Any provenance other than `user` is rendered as untrusted (fail safe).
    - An empty Item renders "", so `Decide` refuses it rather than sending a bare preamble, and `Test.Bridge.Api` stays as it is.
14. **The example and `src/module.xml`.**
    - **Why not now.** AD-2 lists `OcuTalon.BridgeExample` among the package's resources, ahead of `src/ocutalon/`. Lane B's `test-pinned-sources.sh` (`bridge_first`) pins the first two resources as `OcuTalon.Bridge.PKG` then `OcuTalon.PKG`. Listing the example in AD-2's position therefore needs that Lane B check changed (contended), and a third position would break AD-2's order.
    - **What this story needs.** Its standalone criterion loads the bridge with `LoadDir`, which needs no manifest. So the listing is left to Story 15.2, whose criterion inspects the installed package for `OcuTalon.BridgeExample`, together with a Lane B change to `bridge_first`.
    - **Consequence.** The judges' install is unchanged, and no OCUTALON test may depend on the example's classes.
15. **How the example is configured and called.**
    - Its XData holds neither the provider settings nor `TestingEnabled`: an XData setting would win over the CI's rows, and the example must not point at the mock or enable testing in a shipped class.
    - The CI script writes both as System Default Settings rows in the throwaway's own namespace, the same settings a developer sets for their own namespace (Story 13.3's guide). Ens's testing service is the only way to reach a production that holds no service of its own, and Story 13.1 adds the example's own service.
16. **Where the script lives.** It is in `release/`, Lane A's folder. The folder does not exist yet, and AD-29 gives it the release sequence and the upgrade-in-place test harness. It is not in `src/bridge/`, which the image copies: AD-22 keeps mock settings out of the judges' install. It sources Lane B's `ci/iris.sh` and `lib-live.sh` read-only, and copies only row 5's few recipe lines, from a Lane B script that cannot be sourced as a library.
17. **The namespace** is created by `iris merge` without Interoperability and enabled with `EnableNamespace(ns, 0, , 1)`. That gives no Foundation production that could hold the namespace (Story 0.10's measured form). It is not `Interop=1`, as row 5 uses.
18. **Why the filter and the sink are pinned in process.**
    - `OcuTalon.Production`'s XData fixes `Decide`'s extension classes (an item setting wins over a System Default Settings row), and the example must run with the defaults. So no running production can be given a probe filter or sink.
    - The in-process tests therefore drive `Conclude`, the same class method that `OnResponse` calls, with the probe classes.
    - The live tests prove that the running BP reaches `Conclude`: rows, filtered pass-through text and the response.
    - The sink and filter calls are the outermost surfaces the AC names.
19. **The job's timeout** is 20 minutes. The job builds the web bundle, the image and a first start, which takes about 3 to 6 minutes on the runner (inference from Rule 21's figures), and it runs in parallel with `ci.yml` on the 12 runner services.

**Integration ACs (Rule 1):**
- AC6: the example's caller (Ens's testing service) sends `Decide` a request in a production that has none of OcuTalon's packages, and gets the scenario's outcome. The `Decision` row carries its session.
- AC5: the runners consume `Agent.Input`'s text through `Decide`, and the mock's log shows it as the user message.
- No product consumer calls `Decide` in this story. The first are Story 2.4 (`Conversation`) and Story 2.7 (`Intake`).

**Consumed-by:**
- **Story 1.4:** the `Usage` totals on the row and on the messages, and `Bridge.Time`'s day.
- **Story 1.5:** `Decide` sends the agent steps to `AgentSteps`.
- **Story 1.6:** the fallback route replaces decision 1's error paths, and adds the prechecks.
- **Story 1.7:** `timeout`, `TimerSeconds` through `Derive`, and the re-send.
- **Story 1.8:** `Busy`, and the turn key of decision 5.
- **Story 1.9:** `too_large`.
- **Story 2.4:** `Conversation`'s decide (user) and turn calls, and `Agent.Input`.
- **Story 2.6:** `BridgeSink` on `decision.recorded`, with `TraceSessionId` as the trace target.
- **Story 2.7:** `Intake`'s decide call and the untrusted turn.
- **Story 5.4:** `DiagnosisAgent`'s `ReplyClass` and the diagnosis outcome.
- **Story 5.7:** `ReplyGuard` as the filter.
- **Story 9.1:** the evaluation runs through `Intake`.
- **Story 13.1:** the example grows.
- **Story 15.2:** the manifest (decision 14).

**Consumes:**
- **Story 1.2:** the runners' `Answer` and `Reply`, `RunnerFixture`, and the mock scenarios.
- **Epic 0:** `Data.Decision`, the `Bridge.Msg` classes, `DecisionPayload`, the extension bases and `Accessor`, `Ids.NewRef`, `Agent.Input`'s signature, `ApprovalStartIn`, and the CI mock with `Test.Contract.Mock`.
- **Lane B:** `Data.Time`, `Msg.Item`, and `ci/iris.sh` with `lib-live.sh`, all read-only.

**Extend, don't copy (Rule 2):**
- **`RunnerFixture`.** `NewRequest` extends `Ask`, and `Ready` moves out of `Runners` into it as `ReadyReason`. `Test.Agent.Decide` uses both, and its key pointing calls `RunnerFixture.PointKeys`/`RestoreKeys`.
- **The bridge.** `Decide` reuses `Ext.Accessor.Check`, `HostSink.RefPayload` and `Ids.NewRef`.
- **Forced copies, with their reasons:**
  - `Bridge.Time.NowUtc` copies `Data.Time.NowUtc`'s one line (AD-2, AD-18).
  - `BridgeExample.Agent` copies the shape of `OcuTalon.Agent.Triage` (AD-2: the example may not name `OcuTalon.Agent`).
  - The script copies row 5's merge and `LoadDir` lines, because Lane B's script runs as a whole and offers no function for them.

**Ledger:** this story's inbox is empty.

**Lane B pieces.** No contended edit is planned. Follow-ons:
- Widen `test-pinned-sources.sh`'s `bridge_first` for `OcuTalon.BridgeExample.PKG`, for Story 15.2.
- Story 2.4 and the stories after it can drop the `Decide` test double once this story merges.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only, with MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call, after `iris_server_info` shows build 154. It is used for `iris_doc_load` compiles and process-local facts only, and no test class runs there.
- **Throwaways.**
  - Everything else goes through `ci/iris.sh` or the script, with `OCUTALON_RUN_TAG=e1s3a OCUTALON_LOCK_OWNER='epic=1 stage=implement'`. QA uses `e1s3q` and review `e1s3r`.
  - One stack at a time, one command per call, each with `timeout: 600000`.
  - Run `ci/iris.sh teardown` with the same tag at the end.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition` or `ocutalon-slot-b`. No push and no `gh workflow run`. Never read `.env`.

**Commands** (each prefixed with `OCUTALON_RUN_TAG=e1s3a OCUTALON_LOCK_OWNER='epic=1 stage=implement'` where it starts a stack):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, including class rules (bridge-refs over `BridgeExample`), storage, boundaries (ASCII in `release/`) and ci-config (`lane-a.yml`). About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for:
  - `OcuTalon.Test.Bridge.Decide`, `.Agent.Decide` and `.Agent.Render`;
  - `.Install.Production`, `.Agent.Runners` and `.Bridge.Api`;
  - `.Bridge.Contracts`, `.Bridge.CodeRules` and `.Bridge.Ext`.

  Expected: `CLASS ... passed`.
- **(loop)** `bash release/standalone-bridge.sh`. Expected: every check `PASS`, and exit 0. About 2 to 3 minutes on ARM (inference).
- **(loop)** `bash ci/iris.sh shard lane-a`. Expected: every class passed, and the only SKIP is the existing `TestStepHelpers` one.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s3a`'s projects.
- **(once)** `bash docker/tests/test-mock.sh`. Expected: all pass with the four new scenario files, and `constants.test.mjs` finds one `mockkey` scenario for `bridge-example`.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passed, among them `Test.Contract.Ac` (the `Render` signature), `Test.Data.Tables` (`Decision`, and `Decide` among the persistent classes) and `Test.Msg.Contracts`.
- **(once)** `bash ci/iris.sh live production`. Expected: PASS, with Decide out of row 16's sweep, every item running and a clean start. About 85 s.
- **(once)** `bash ci/iris.sh live production-restart`. Expected: PASS. About 87 s.
- **(once)** `bash ci/iris.sh live install-start`. Expected: PASS. Row 5 loads `src/bridge/cls` with `BridgeExample` in it, `Run()` gives 1, and there are 0 other classes. About 150 to 200 s.
- **(once)** `bash ci/iris.sh live install-upgrade`. Expected: PASS, with the changed production upgraded in place. About 165 s.
- **(once)** `bash ci/iris.sh live storage-roundtrip`. Expected: PASS. `Decide`'s committed block, with slot 4 `TimerSeconds`, equals the compiler's, and the control still sees a removed slot 3. About 70 s.
- **(once)** `bash ci/iris.sh live compose-start`. Expected: PASS, with no key and every item running. About 80 s.
- **(once)** `bash ci/iris.sh live demo-path`. Expected: PASS, with `@floor`. About 60 s.
- **(once)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s3a`'s projects.

**Shared surfaces:**
- **The `Decide` item.** It has no `STUB`, so the Lane A oracle's stub flag changes, and Lane B's `test-production.sh` row 16 sweep and `check_items_run` read that oracle. Its Storage block is the control sample of `test-storage-roundtrip.sh`.
- **`TriageAgent`'s settings.** It gains `ReplyClass` in the XData (`Test.Install.Production.TestDefinition`), and `AgentRunner` gains a host setting.
- **The mock scenario set.** Four new files under `A/`. `constants.test.mjs` reads the `BridgeExample` `MOCKKEY`, and `scenarios.test.mjs` pins no count.
- **`Decision` rows**, which every test makes and deletes.
- **The `TimerSeconds` System Default Settings row** and `Decide`'s job, which `TestTimer` changes and restores.
- **The Config Store entries' `api_key`**, pointed and restored as in Story 1.2.
- **`Agent.Input.Render`'s output.** `Test.Bridge.Api.TestNeutralValues` reads it for an empty Item.
- **`DecisionPayload`'s validation**, read by `Test.Bridge.Contracts.TestDecisionPayloadJson`.
- **`lane-a.yml`**, against `test-ci-config.sh`'s rules.
- **The `release/` folder**, against `test-boundaries.sh`'s ASCII, local-path and key-like-string scans.
- **The new classes** in `OcuTalon.Bridge` and `OcuTalon.BridgeExample`, for bridge-refs, the `%AI` allow-list, and the `{{` check in INSTRUCTIONS.
- **Tests updated for the new shape:** `Test.Install.Production`, `Test.Bridge.Api` (comments only) and `Test.Agent.Runners` (the moved helper).

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19)**, one or more per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | The `ReplyClass` check skipped (any text recorded) | `Agent.Decide.TestUnusableEndsWithError`, `Bridge.Decide` |
| AC1 | The outcome set to `tellnow` when the confidence is under 0.5 | `Agent.Decide.TestLowConfidence` |
| AC1 | `Decide` also sends the request to `AgentSteps` | `Agent.Decide.TestDecision` (the sends) |
| AC1 | `SetTimer` given 30 instead of `TimerSeconds` | `Agent.Decide.TestDecision` (`Timeout` 60) |
| AC2 | The recorded-row lookup removed | `Agent.Decide.TestRepeat` |
| AC3 | The user rule removed | `Agent.Decide.TestUserRule`, `Bridge.Decide` |
| AC4 | The `Filter` call removed for reasons | `Bridge.Decide` (Filter) |
| AC4 | `OnEvent` called before `%Save` | `Bridge.Decide` (Sink: the row is absent at the call) |
| AC4 | The sink's error returned as `Conclude`'s status | `Bridge.Decide` (Sink, error mode) |
| AC4 | `TraceSessionId` not written | `Agent.Decide.TestTraceFields` |
| AC5 | A `user` item rendered as quoted data | `Agent.Render`, `Agent.Decide.TestTurn` |
| AC5 | The preamble built from `$Horolog` instead of `ToLocal(now)` | `Agent.Render` |
| AC6 | `Decide`'s `HostSinkClass` default changed to `OcuTalon.Core.BridgeSink` | `release/standalone-bridge.sh` (the extension check, or the compile) |

**Measured in planning** (`ocutalon-slot-a`, `OCUTALON`, `iris_server_info` build 154U; process-local, nothing kept). `DecisionPayload.%JSONImport` then `%ValidateObject()`:
- **Pass:** `{"outcome":"act","reasons":["r"],"confidence":0.12}` passes both, with `Confidence` .12, and exports back as `0.12`. Confidence 0, 1 and 0.123 import as they are (.123 is kept).
- **Refused at import:**
  - reasons given as a string (`#9406`);
  - confidence 1.5, -0.1 or `"high"` (`#9406`);
  - a reason that is a number (`#9406`);
  - an extra field (`#9404`);
  - text that is not JSON (`#5035`);
  - a JSON array (`#9406`).
- **Pass both with no class change:** outcome `maybe`, outcome `null` (empty), `"reasons":[]`, a blank reason, and a missing confidence. These are the gaps that `%OnValidateObject` closes.
- **The XML of a `DecisionResponse`**, which Visual Trace's contents pane shows, holds `<DecisionRef>`, `<Outcome>`, `<Reasons>`, `<Confidence>.12</Confidence>`, `<Fallback>false</Fallback>` and `<FallbackReason></FallbackReason>`. So all five names show for a usable decision too, and `<FallbackReason>invalid</FallbackReason>` with `<Fallback>true</Fallback>` shows once they are set.

## Clarification Record

**For the veto window** (not blocking; recommended as planned):
- **Decision 3, `AgentRunner.ReplyClass`.** A new host setting, written in `OcuTalon.Production`'s XData for `TriageAgent`: a production-structure addition.
- **`Decide.TimerSeconds`.** A new stored property of the business process (slot 4, appended by the compiler): a schema append.
- **Decisions 5, 7 and 8, what a `Decision` row holds:**
  - `Payload` is the checked model payload with filtered reasons and the model's own outcome;
  - a turn row has `tellnow` with no reasons, confidence or payload;
  - the reasons are one per line;
  - the confidence is rounded to two decimals.
- **The user rule's reason sentence**, "The outcome was changed because a message the user writes is always answered." Its meaning is fixed by the acceptance criterion, and it is shown in Visual Trace and wherever reasons are shown.
- **Decision 15, the testing service in CI only.** The example production keeps `TestingEnabled` false. The CI script enables Ens's testing service through one System Default Settings row, and only in its own throwaway namespace. This is a security-posture item.
- **Decision 15, the CI key placeholder.** The script's `ProviderConfig` row uses `@{env:OCUTALON_MOCK_KEY_HEADER}` as the key placeholder, which is Story 1.2's ruled decision 12, in throwaways only.

**For the lead** (not blocking): decision 14 leaves `OcuTalon.BridgeExample` out of `src/module.xml`, against AD-2's list of the package's resources, because the AD-2 position conflicts with Lane B's pinned `bridge_first` check. It recommends that Story 15.2 list it, with a cross-lane change to that check.

**Ruled at spec validation** (Epic 1 runner, 2026-10-22, unattended; the owner may reverse a veto ruling through the inbox):
- **Decision 4 (`diagnose` refused until `DiagnosisAgent` names a `ReplyClass`):** `category=decide`, kept. The acceptance criterion checks the reply against the runner's `ReplyClass`; Story 5.4 plans `OcuTalon.Watch.Msg.DiagnosisPayload` and sends `diagnose` through `Decide`. The routing is built and fails closed, and no criterion moves.
- **`Decide.TimerSeconds` and decisions 5, 7 and 8 (what a `Decision` row holds):** `category=veto`, kept as planned (inbox U-12).
- **Decision 15, the testing service in CI only:** `category=veto`, kept as planned (inbox U-13).
- **Decision 3 (`AgentRunner.ReplyClass` in the XData), the user rule's sentence, and decision 15's CI key placeholder:** `category=decide`, kept. AD-7 names the setting; the criterion fixes the sentence's meaning; Story 1.2's ruled decision 12 (U-6) is the placeholder's precedent.
- **Decision 14 (`src/module.xml` and AD-2):** a cross-epic matter (a contended Lane B check, and Story 15.2 in Epic 15), routed to the orchestrator. Its ruling is recorded here when it comes.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
