---
title: 'Story 3.2: One gate decides every tool call'
type: 'feature'
created: '2026-10-24'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-6, AD-9, AD-10, AD-19, AD-24 and AD-31, and the Agent step labels, Tool classification, Tool resources and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Every tool call runs today with no check at all: the runner adapter adds only the step audit policy, nothing reads the tools' `CLASSIFICATION` and `RESOURCES` parameters, and the watch fixture's three tools declare no classification (DW-143), so they would be held as soon as a gate reads the parameters.

**Approach:** Add `OcuTalon.Bridge.Policy.Gate`, an AI Hub Authorization policy that the adapter adds beside the step audit policy. Its `%CanExecute` fails closed. It classifies each call by (source, name) from code, then from Decide's new `ToolClassification` setting, then from `ClassificationClass`. It checks the service user's privileges for the tool's `RESOURCES`, one letter per call. It denies every risky or unclassified call with a plain sentence, and reports `turn.step` for every call it allows. The watch tools are classified safe and read-only, and one governance test runs every risky built-in tool through the gate.

## Boundaries & Constraints

**Always:**
- **Fail closed.**
  - A missing context, a call that is not an object or has no name, an error status from any step, and any exception all deny the call.
  - The gate catches every exception itself, so none leaves `%CanExecute`, and logs one redacted warning that names the tool and its source.
  - A denial is `$SYSTEM.Status.Error("<%AICore>ToolAccessDenied", <sentence>)`, so `%LogDenial` records it as a step.
  - The model never gets an exception's text, only the sentence.
- **Classification by (source, name), in this order.**
  1. A `toolref` that starts `mcp:` is an MCP call. Its source is the `toolref`, and only `ClassificationClass` can classify it: no class parameter and no setting entry is ever read for it.
  2. Otherwise the source is `metadata.origin_class`. The code of that class decides first: its class method `Classify<NAME>(arguments)`, else `Classify(arguments)`, by the suffix rule of the tool parameters; else its parameter `CLASSIFICATION<NAME>`, else `CLASSIFICATION`, read through `StepBuffer.ToolParameter`.
  3. Then an entry of Decide's `ToolClassification` setting with exactly that class and tool name.
  4. Then `ClassificationClass`.
  5. Anything else is unclassified, which counts as risky.
- **Values.** Only the exact values `safe` and `risky` classify a tool; any other value is unclassified. A classification that code gives is never changed by the setting or the extension. `READONLY` and `TRUSTEDOUTPUT` are 1 only when they are exactly 1, else 0. They are carried in the classification result for Story 3.3 and decide nothing in this story.
- **Permissions.**
  - The gate reads the tool's `RESOURCES` (`StepBuffer.ToolParameter`) and parses it with the one bridge parser (`Gate.Resources`, which the installer's `Tools.Parse` now delegates to).
  - For each pair, it checks `$SYSTEM.Security.CheckUserPermission(<ServiceUser setting>, resource, letter)` for each letter of the permission, one letter per call.
  - The first missing pair denies the call. A tool that declares no resources needs no check.
- **Result.** A `safe` call that passes the permission check is allowed. Every other call is denied: a missing privilege with `NOPRIVILEGE`, a risky or unclassified call with `NEEDSAPPROVAL`.
- **`turn.step`.**
  - Every allowed call, and no denied one, fires `turn.step` through `Decide.FireEvent`, to the class that `HostSinkClass` names.
  - The owner is the context's `OwnerRef`, and the payload is exactly `HostSink.TurnStepPayload(<context DecisionRef>, <label>)`.
  - The label is `StepBuffer.Part(StepBuffer.LabelFor(source, name), StepBuffer.#MAXLABEL)`.
  - A sink that fails is logged and never changes the decision.
- **Denial sentences.** They are model-facing ASCII class parameters of the gate, written to read well after AI Hub's "Tool access denied: " prefix.
- **Tests.** Every test runs on throwaway stacks through `ci/iris.sh`. It restores every System Default Settings row and production setting it writes, and it creates no IRIS user, role or resource.

**Never:**
- No edit to a contended path. That covers `Core/**` (`Core/BridgeSink.cls` is read only), `Web/**`, `Test/{Core,Web,Data,Live,Demo,Schedule}/**`, `docker/**`, `docs/**`, `ci/compose.ci.yml`, `.github/**` and `README.md`.
- No `%AI` agent, session, tool-manager, provider, setting-store or RAG call and no Python in the gate or anything it calls (AD-6). The gate names `%AI` only on its Class line, and has no `Include %AI`.
- No instance property on the gate: AI Hub infers a policy's statefulness from its properties.
- The gate never modifies `call`, never takes a lock, and never reads `metadata`'s requirements (such as `ReadOnly`), a call's arguments (except as the input of a code `Classify` hook), the context's `HostData` or the taint to classify.
- No `Approval.Raise` and no hold (Story 3.6). No provenance or taint rule (Story 3.3). No MCP fingerprints or `OcuTalon_MCP_<server>` resources (step 4).
- No built-in tool declares `RESOURCES` in this story, and no test fixture goes into the `OcuTalon.Tools` package.
- No test run, role, user, resource or security change on `ocutalon-slot-a`. Loading and compiling there is fine.
- No absolute local path in a tracked file.

## I/O & Edge-Case Matrix

Unless a row says otherwise, each call is made in a user's turn: a context with `Kind` turn, `Provenance` user, an `OwnerRef` and a `DecisionRef`. `ZzGateTool` is the new test tool class.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Safe built-in | `Check` for `set_reminder` of `OcuTalon.Tools.ReminderTools`, sink `ProbeSink` | OK. The sink gets one call: `turn.step`, the owner is the `OwnerRef`, and the payload is exactly `{"decisionRef":<DecisionRef>,"label":"Setting a reminder"}`. | A sink in error or throw mode: still OK, with one warning. |
| 2 | Watch tools (DW-143) | `ClassificationOf(OcuTalon.Tools.WatchFixture, <each of the three tools>)` | `{"classification":"safe","readOnly":1,"trustedOutput":0,"by":"code"}`. In the production, Diagnosis's second model request carries `{"items":[]}` as its tool result (the integration check, through `Test.Agent.Runners`). | -- |
| 3 | Risky by code | `zz_gate_held` (`CLASSIFICATIONZZGATEHELD="risky"`) | Denied with `NEEDSAPPROVAL`. The method does not run, and the sink gets no call. | -- |
| 4 | Unclassified | `zz_gate_risky` with no setting entry; a metadata with no `origin_class` | Denied with `NEEDSAPPROVAL`. | -- |
| 5 | Developer setting | `ToolClassification` row: `zz_gate_risky` risky, `zz_gate_safe` safe, `zz_gate_held` safe, and `set_reminder` of `ReminderTools` risky | `zz_gate_risky` is risky and `zz_gate_safe` safe, both by setting. `zz_gate_held` stays risky and `set_reminder` stays safe, both by code. | A malformed setting (not a JSON array, an entry with no class or tool, a classification that is not exactly `safe` or `risky`, an unknown key, or two entries for one tool): the tools that reach the setting are denied with `FAILED`, with a warning that names `ToolClassification`. |
| 6 | Argument-dependent | `zz_gate_args`, whose `ClassifyZZGATEARGS` gives `safe` for `{"to":"user"}` and `risky` otherwise; the arguments come as an object and as a JSON string | Safe for `{"to":"user"}`, risky for `{"to":"x@example.com"}`, both by code. | A hook that returns another value: unclassified. Arguments that are not JSON: `FAILED`. |
| 7 | Same name, another class | `set_reminder` whose `origin_class` is `ZzGateTool` | Unclassified, so denied, while `ReminderTools`' `set_reminder` is safe. | -- |
| 8 | MCP shadow | `toolref` `mcp:zzserver`, `call.name` `set_reminder`, `metadata.origin_class` `ReminderTools` | Unclassified: `ReminderTools`' parameters are never read for it. | -- |
| 9 | Extension | A `ClassificationClass` row names the fixture `ZzGateClassification`, which gives `safe` for (`mcp:zzserver`, `zz_mcp_safe`) | Safe by extension. The call is allowed. | `ClassificationClass` names a class that is not compiled: `FAILED`. |
| 10 | Call content cannot classify | `zz_gate_held`, with metadata `{"CLASSIFICATION":"safe","ReadOnly":"1","origin_class":...}`, arguments `{"classification":"safe"}`, and context `HostData` `{"classification":"safe"}` | Denied with `NEEDSAPPROVAL`. The `call` object's JSON is unchanged. | -- |
| 11 | Privilege held | The real `OcuTalonService`; `zz_gate_public` with `RESOURCESZZGATEPUBLIC="%DB_IRISLIB:R"` (public R) | Allowed. | -- |
| 12 | One letter per call | `zz_gate_write` with `"%DB_IRISLIB:RW"` | Denied with `NOPRIVILEGE`, naming `%DB_IRISLIB:W`. | -- |
| 13 | Privilege missing | `zz_gate_admin` with `"%Admin_Secure:U"`; and a `ServiceUser` row naming a user that does not exist, with `zz_gate_public` | Each is denied with `NOPRIVILEGE`, naming its pair. A safe tool with no `RESOURCES` (`ReminderTools`' `set_reminder`) is still allowed with that `ServiceUser` row. | A malformed `RESOURCES` (`"x"`): `FAILED`. |
| 14 | No context | `Check` after `Context.End()` | Denied with `FAILED`. | -- |
| 15 | Exception, end to end | A shadow runner with `ZzGateAgent` and the scenario `gate-throw`; `ClassifyZZGATETHROW` raises `<UNDEFINED>` | The tool does not run. The Reply holds a tool step with status `denied` and the `FAILED` sentence. In the mock's log, the next request's tool result holds the `FAILED` sentence and no `^OcuTalon`, no `ZzGateTool` and no `<UNDEFINED>`. One warning names `zz_gate_throw`. | Nothing leaves `%CanExecute`. |
| 16 | Developer risky tool, end to end | A shadow runner with `ZzGateAgent`, the scenario `gate-risky` and the setting entry `zz_gate_risky` risky | `^\|\|ZzGateRan("zz_gate_risky")` is undefined. The step is `denied` with `NEEDSAPPROVAL`, and the next request's tool result carries the sentence. The built agent's `AuthPolicy` is a `Gate` and its `AuditPolicy` a `StepAudit`. | -- |
| 17 | Allowed, end to end | The scenario `gate-safe`, the setting entry `zz_gate_safe` safe, and Decide's `HostSinkClass` set to `ProbeSink` (`RunnerFixture.UseItemSetting`) | The tool ran and its step is `ok`. The sink got exactly one call, `turn.step`, with the request's `OwnerRef`, `{"decisionRef":<the request's DecisionRef>,"label":"Running the safe gate test tool"}`. | The setting is restored, also after a failure. |
| 18 | Every risky built-in (governance) | Every tool of every `OcuTalon.Tools` toolset, and the sample toolset `ZzGateTools` | Each tool whose classification with the arguments `{}` is not `safe`, or throws, goes through a fresh `%AI.ToolMgr` with the gate and the step audit policy, in a user's turn. It is denied, its method does not run, and its only step is `denied`. Every tool whose class has a `Classify` hook has an entry in the test's `CASES`. On the sample, `zz_gate_held` and `zz_gate_risky` are run and denied, and `zz_gate_args` and `zz_gate_throw` are flagged for having no case. | -- |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:164-169` -- `OnAfterAgentInit` adds only `StepAudit` today; it gains `SetAuthPolicy(Gate.%New())` first. `CheckSettings` (:113) already refuses the `AuthPolicy` setting. Update the class comment (:17-18).
- `src/bridge/cls/OcuTalon/Bridge/Policy/StepAudit.cls` -- the thin-policy pattern: callbacks delegate to class methods, catch everything and name `%AI` only on the Class line. `%LogDenial` (:29) records `denied` with `StatusText` (:41), which strips "ERROR <code>: ".
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- `ToolParameter` (:167) is the one suffix-rule reader (3.1), `LabelFor` (:155), `Part` (:189) and `MAXLABEL` (:31).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`
  - `SETTINGS` (:92) and the extension properties (:148-154): add `ServiceUser` and `ToolClassification` here.
  - `FireEvent(sinkClass, ownerRef, ref, type, payload)` (:909) is the one sink caller; it never fails its caller, and `Budget.MarkCapped` (`Budget.cls:118-130`) calls it the same way.
  - The storage block ends at `<Value name="13">` (:1011): append, never renumber (AD-5).
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls` -- `ValueFor(setting)` reads Decide's setting from the production definition, then the System Default Settings, then the initial value. `ClassFor(setting, ..., .sc)` returns an error for a missing class.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls:9-12` -- `Classify(tool, arguments)` returns "". Its signature changes to `(source, name, arguments)`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/HostSink.cls` -- `TURNSTEP` and `TurnStepPayload(decisionRef, label)`.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `Active()` and `Current()`, with `OwnerRef`, `DecisionRef`, `Kind` and `Provenance`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Tools.cls:69-87` -- the body of `Parse(value, where)` moves to the bridge, and `Parse` keeps its signature and errors. `Test.Install.Tools` pins it unchanged.
- `src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls:11-15` -- only the `STEPLABEL<NAME>` parameters today (DW-143). `ReminderTools.cls:24-40` is the triple pattern. `Watch.cls` keeps its `Requirement` elements, which the gate never reads.
- Fixture tools that tests run today, all unclassified: `Test/Bridge/ProbeTool.cls`, `StepsNote.cls`, `StepsCard.cls`, `StepsText.cls` (all `Extends %AI.Tool`) and `Test/Tools/ZzResultTool.cls`. Their mock scenarios are `context-probe*`, `steps-*`, `cut-off-tool`, `tool-loop`, `rate-limited-after-tool` and `result-cap*`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Runner.cls`
  - `NewRunner(agentClass, ...)` (:987) and `ProviderConfig` (:1001): shadow runners on the mock.
  - `TestContext` (:317) is the end-to-end pattern.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- the shared test helpers:
  - `GuardReason` (:100) and `EventMark` (:182);
  - `PutDefault`, `RememberDefault` and `RestoreDefaults` (:682-735);
  - `UseItemSetting` and `RestoreItemSetting` (:617-632);
  - `FindRequests` (:918) and `ToolResults(logged)` (:969);
  - `Warnings` (:1037).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls:365-378` -- `LogMark` and `LogSince`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls` -- in-process mode `^||ZzProbeSink(n)` = `$ListBuild(type, owner, payload JSON, ...)`, with modes record, error and throw.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- `CALLBACKHELPERS` (:51) and `ToolClasses(toolsets)` (:659, Private), the test-side scan of `OcuTalon.Tools.`. `TestCallbackRule` (:107) scans every `%AI.Policy.Authorization` subclass.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls:204-205` -- calls `Classify` with the old signature.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Runners.cls:285-293` -- Diagnosis's second request carries `{"items":[]}`. Without DW-143's fix, the gate would turn it into a denial.
- `ci/mock/scenarios/A/steps-two-tools.json` -- the scenario shape: the marker equals the name, and the file is `{name, match:{marker}, replies:[{status, toolUse:{name,input}}, {status, text}]}`.
- `ci/units.sh:17` -- the `lane-a` shard runs the `Bridge` area, so `OcuTalon.Test.Bridge.Gate` joins it with no edit.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 -- measure these on the stage's warm throwaway, never on the slot, and record each under Design Notes. Use a temporary authorization policy that records what it gets (deleted afterwards), or the gate once it is written.
  - (a) In `%CanExecute`, for a toolset tool, both through `ToolMgr.ExecuteTool` and through `Chat`: the value of `toolref`, the type of `call.arguments` (object or JSON string), and the keys of `metadata`.
  - (b) For a `ToolAccessDenied` denial:
    - the status that `%LogDenial` gets;
    - what `ExecuteTool` raises (its name and code), which row 18's helper catches;
    - the exact tool-result text that the model gets, from the mock's log (AI Hub's prefix before the sentence).
  - (c) Whether a denial with code 5001 instead also reaches `%LogDenial`.
  - Adjust the sentences' wording to read well after the measured prefix (keep their meaning).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - Add `ServiceUser As %String(MAXLEN = 160) [ InitialExpression = "OcuTalonService" ]` and `ToolClassification As %String(MAXLEN = "")`: a JSON array of `{"class","tool","classification"[,"readOnly"][,"trustedOutput"]}`, where an empty value is none.
  - Add both to `SETTINGS` as `:Bridge`, and append them to the storage block.
  - Why: the bridge cannot read `Install` (AD-2), and AD-19 puts bridge values in host settings.
- [ ] `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls` -- `ClassMethod Classify(source As %String, name As %String, arguments As %DynamicObject = "") As %String`. It returns `safe`, `risky` or "" (the default ""). Why: an extension must see the source to keep an MCP tool off a built-in's classification (AD-10, AD-31).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` (new; `Extends %AI.Policy.Authorization`, no properties) -- implement the Boundaries' rules:
  - `%CanExecute(toolref, call, metadata)`: `Quit ..Check(toolref, call, metadata)` inside its own Try, which denies with `FAILED`.
  - `ClassMethod Check(toolref, call, metadata, sinkClass = "") As %Status`: the decision. An empty `sinkClass` means `ValueFor("HostSinkClass")`.
  - `ClassMethod ClassificationOf(source, name, arguments) As %DynamicObject`: `{classification, readOnly, trustedOutput, by}`, where `by` is `code`, `setting`, `extension` or "". It throws on a malformed setting.
  - `ClassMethod Source(toolref, metadata) As %String`.
  - `ClassMethod Resources(value, where) As %DynamicArray`: the parser moved from `Install.Step.Tools.Parse`, unchanged.
  - `ClassMethod Denial(sentence) As %Status`.
  - Parameters: `DENIEDCODE = "<%AICore>ToolAccessDenied"` and the sentences:
    - `NEEDSAPPROVAL`: "this tool is risky or not classified, so it needs an approval, and nothing was run."
    - `NOPRIVILEGE`: "the service user lacks the privilege {privilege} that this tool needs, so nothing was run."
    - `FAILED`: "the check of this tool call failed, so nothing was run."
  - Why: AC 2 to 5 (AD-10, AD-9, AD-31).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- `OnAfterAgentInit` sets the gate as the authorization policy, then the step audit policy, and returns the first error. Why: AC 1 (AD-6).
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Tools.cls` -- `Parse` becomes `Quit ##class(OcuTalon.Bridge.Policy.Gate).Resources(value, where)`. Why: one parser (Rule 2).
- [ ] `src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls` -- add `CLASSIFICATION<NAME> = "safe"`, `READONLY<NAME> = 1` and `TRUSTEDOUTPUT<NAME> = 0` for the three tools. Failed messages and event-log text are never trusted output (AD-10), and item settings are not OcuTalon's own records. Why: DW-143.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeTool.cls`, `StepsNote.cls`, `StepsCard.cls` and `StepsText.cls`, and `src/ocutalon/cls/OcuTalon/Test/Tools/ZzResultTool.cls` -- add `Parameter CLASSIFICATION = "safe"`, plus `READONLY = 1` on the three Steps fixtures, whose toolset already says ReadOnly. Why: the tests that run them keep passing with the gate (shared surface).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateTool.cls` (new; `Extends %AI.Tool`) -- the test tool class:
  - Tool methods: `Risky`, `Safe`, `Held`, `Args`, `Throws`, `PublicRead`, `ReadWrite`, `Admin` and `Shadow`. Each sets `^||ZzGateRan(<tool name>)=1` and returns `{"ran":"<tool name>"}`.
  - Parameters:
    - `STEPLABELZZGATESAFE = "Running the safe gate test tool"`;
    - `CLASSIFICATIONZZGATEHELD = "risky"`;
    - `CLASSIFICATION<NAME> = "safe"` for `zz_gate_public`, `zz_gate_write` and `zz_gate_admin`, with the `RESOURCES<NAME>` values of rows 11 to 13.
  - `[ Internal ]` hooks: `ClassifyZZGATEARGS(arguments)` (row 6) and `ClassifyZZGATETHROW(arguments)`, which reads an undefined variable.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateTools.cls` (new toolset, `DependsOn` the tool class) -- names `zz_gate_risky`, `zz_gate_safe`, `zz_gate_held`, `zz_gate_args`, `zz_gate_throw`, `zz_gate_public`, `zz_gate_write`, `zz_gate_admin` and `set_reminder` (`Shadow`).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateAgent.cls` (new; `MODEL` `claude-haiku-5-5`, `TOOLSETS` the toolset, a static `INSTRUCTIONS`) and `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateClassification.cls` (new; extends `Ext.Classification`; row 9).
- [ ] `ci/mock/scenarios/A/gate-risky.json`, `gate-safe.json` and `gate-throw.json` (new) -- the marker is the name. The first reply is a `toolUse` of `zz_gate_risky`, `zz_gate_safe` or `zz_gate_throw` with `{}`, and the second a text reply.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` (new) -- tests for rows 1 to 18, one method per row or close group:
  - Rows 15 to 17 are guarded with `RunnerFixture.GuardReason()`, like `Test.Bridge.Runner`.
  - Row 18 runs each tool through `%AI.ToolMgr` (`RegisterToolSet`, `SetAuthPolicy`, `SetAuditPolicy`, `Context.Begin`, `StepBuffer.Start`, `ExecuteTool`).
  - `Parameter CASES = ""` holds the risky arguments of the `Classify`-hook built-in tools, as `provider:name=<JSON>` entries; there are none today.
  - `TestEveryBuiltInToolIsClassified` checks that every tool of every `OcuTalon.Tools` toolset is classified by code (DW-143's scan).
  - `OnAfterOneTest` ends the context and the buffer, kills `^||ZzGateRan` and `^||ZzProbeSink`, and restores the remembered rows and item settings.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`:
  - Add `OcuTalon.Bridge.Ext.Accessor`, `OcuTalon.Bridge.Process.Decide`, `OcuTalon.Bridge.Ext.HostSink`, `OcuTalon.Bridge.Ext.Classification` and `OcuTalon.Core.BridgeSink` to `CALLBACKHELPERS`: the gate calls them inside the callback.
  - Drop `Private` from `ToolClasses`, so that `Test.Bridge.Gate` reuses the test-side inventory.
  - Update the doc comments.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls:204-205` -- call `Classify` with `(source, name, arguments)`.

**Acceptance Criteria:**
- Given any runner, when its adapter builds the agent, then the agent's `AuthPolicy` is an `OcuTalon.Bridge.Policy.Gate` beside the `StepAudit` audit policy, and the gate decides calls of tools whose `requires_auth` is false (rows 16 and 17; AC 1, AD-6, AD-10).
- Given a tool call, when the gate classifies it, then rows 1 to 10 hold: (source, name) from `origin_class` or the `mcp:` `toolref`; code, then the setting, then `ClassificationClass`; unclassified counts as risky; and nothing in the call, an item or a tool result changes a classification (AC 2, AD-10, AD-31).
- Given a tool's `RESOURCES`, when the gate checks the service user, then rows 11 to 13 hold, one permission letter per `CheckUserPermission` call, and a denied call does not run (AC 3, AD-10, AD-24).
- Given a missing context, an error status from any step (a lock timeout included, see Decided in-stage) or an exception inside the gate, when a call arrives, then it is denied with a `ToolAccessDenied` status, `%LogDenial` records the step, and the model gets no source line (rows 5, 9, 13 to 15; AC 4, AD-9, AD-10).
- Given an allowed call, when the tool is about to run, then `HostSinkClass` gets exactly one `turn.step` with `{decisionRef, label}` and the session as owner, and nothing for a denied call (rows 1, 3 and 17; AC 5, AD-9, AD-31).
- Given every built-in tool and the developer test tool classified risky in the setting, when `OcuTalon.Test.Bridge.Gate` runs, then each risky or unclassified one is shown not to run in a user's turn, and the suite fails for a risky argument-dependent built-in that has no case (rows 16 and 18; AC 6, NFR-13).
- Given the production's `DiagnosisAgent` built with the gate, when `Test.Agent.Runners` sends its diagnose request, then its watch tool runs and the second request carries `{"items":[]}` (row 2; DW-143, the integration check).
- Given the fresh `shard lane-a` and `shard lane-b`, `live production` and `live demo-path`, when they run, then every class and unit passes. This covers the existing tool-running tests of `Test.Bridge`, `Test.Agent` and `Test.Tools`, with their fixtures classified.

## Spec Change Log

- 2026-10-24, lead spec gate: the spine's Consistency Conventions row "Tool classification" now records the `Classify<NAME>` hook, the exact values and the gate's order (Rule 20, as the plan suggested); AD-31 and AD-10 are unchanged (neither fixes `Classify`'s signature, and the `ServiceUser` setting is an implementation detail of AD-24's check). The three denial sentences are ruled in the veto window (model-facing text the model may relay to the user).

## Review Triage Log

## Design Notes

**Architecture decisions:**
- **AD-10:** the gate, failing closed, classification by (source, name) with the MCP prefix first, the permission check, and unclassified counting as risky.
- **AD-6:** the adapter adds the gate in `OnAfterAgentInit`, and callbacks never call `%AI`.
- **AD-9:** a denial is a step through `%LogDenial`, and the gate reports `turn.step`.
- **AD-31:** the `HostSink` contract and the `ClassificationClass` extension.
- **AD-24:** the service user is a privilege profile that the gate checks.
- **AD-2:** the bridge names no other package, so it gets its own `ServiceUser` setting, and the installer calls the bridge's parser.
- **AD-19:** bridge values are host settings.
- **AD-5:** Decide's storage is append-only.
- **AD-22:** tests run on throwaways.
- **AD-29 and AD-33:** the footprint.

No AC contradicts an AD's Rule.

**Measured at planning** (read-only and process-local on `ocutalon-slot-a`: build 154, profile port 52790, namespace OCUTALON; and the `irislib/` sources):
- **The denial status.** `$SYSTEM.Status.Error("<%AICore>ToolAccessDenied", "x")` has the code `<%AICore>ToolAccessDenied`, the text "ERROR <%AICore>ToolAccessDenied: Tool access denied: x", and `GetOneStatusText` "Tool access denied: x". So no `Include %AI` is needed, and `StepAudit.StatusText` shows "Tool access denied: <sentence>". AD-10's outer "Access denied: ..." prefix is unmeasured: Task 0 (b).
- **Public permissions** (bit mask R=1, W=2, U=4): `%DB_IRISLIB` 1, `%Admin_Secure` 0 and `%DB_IRISTEMP` 3. For a user that does not exist, `CheckUserPermission` returns 0 even for a public R. Rows 11 to 13 use these with the real `OcuTalonService`, which holds only its empty role. So no test creates a user, role or resource, and DW-8's fifth copy is avoided.
- **The policy chain** (`%AI/ToolMgr.cls:23-36` and `:509-525`): `AuthPolicySet` adds the policy to the native chain, and `ExecuteTool` runs authorization, then the tool, then the audit. `%AI/Tool/Generator.cls:31-36` skips private, internal and `%` methods, so an `[ Internal ]` `Classify` hook is never a tool.
- **Earlier measurements** (S4, S9, Story 1.5 Task 0):
  - the gate runs for tools whose `requires_auth` is false;
  - a toolset tool's `toolref` is its name and its class is `metadata.origin_class`;
  - an exception escaping `%CanExecute` skips the audit and shows a source line to the model;
  - an MCP tool that shadows a built-in name carries the built-in's class;
  - the audit gets `call.arguments` as a JSON string (sorted keys), so the gate parses a string.

**Decided in-stage** (small and reversible; inside AD-10's Rule):
- **One class.** `Gate` holds `%CanExecute` and the class methods, which tests call directly. `Check`'s optional `sinkClass` follows `Budget.MarkCapped`'s pattern.
- **The order.** Classification, then permissions, then the result. A call that the service user could not make is denied before any hold (Story 3.6 adds the hold in the result branch). Until Story 3.6, a risky or unclassified call is denied with `NEEDSAPPROVAL` in every turn. Provenance is Story 3.3's.
- **Precedence.** For a class source: code first (the hook, then the parameter), then the setting, then the extension. For an `mcp:` source: the extension only, since MCP tools are classified by an admin (FR-48). A declared code classification is never changed by the setting, so a setting can never downgrade a built-in tool. A defined but empty `CLASSIFICATION` counts as undeclared (`ToolParameter` cannot tell them apart).
- **The hook.** `Classify<NAME>(arguments)`, else `Classify(arguments)`, by the suffix rule. It is a compiled class method, marked `[ Internal ]` so that it is never a tool. It returns the classification only; `READONLY` and `TRUSTEDOUTPUT` stay parameters.
- **Values.** Exact lower-case `safe` and `risky`. Flags are 1 only when exactly 1. They are carried for Story 3.3 and unused here.
- **Ignored inputs.** `metadata`'s requirements and MCP annotations are never read, so the class parameters are the one declaration.
- **The two settings.** `ToolClassification`'s JSON grammar is strict, and a malformed value is an error (`FAILED`). The `ServiceUser` setting defaults to `OcuTalonService`, and is read only when a tool declares resources.
- **One parser.** It moves to the bridge, and the installer delegates (Rule 2).
- **The sentences.** They are model-facing class parameters (the precedent of Story 1.10's `BADDELAY`), and start in lower case to follow "Tool access denied: ". Story 3.6 replaces `NEEDSAPPROVAL` with its specified "held for your approval; nothing was run".
- **Lock timeout.** The gate takes no lock in this story. A step that times out on a lock reports it as an error status or an exception, which the gate's one rule denies (rows 9, 13 and 15). The first locks on its path are `Approval.Raise` (Story 3.6) and the replay grant (Story 30.3), and their stories test them.
- **`turn.step`.** It fires for every allowed call of any request kind, and the sink decides what to publish. The label is redacted and cut, as `StepBuffer.Records` does.
- **Exceptions.** Each one is logged as one warning, redacted with `Redact.Text`, that names the tool and its source.
- **DW-143.** The watch tools are `safe`, read-only and not trusted output. `Watch.cls`'s `Requirement` elements stay, for information. `TestEveryBuiltInToolIsClassified` is DW-143's "scans for it".
- **The governance test's surface.** Built-in tools run through a real `%AI.ToolMgr`: the same native chain (`can_execute`, execute, log) with no model, because a mock scenario per future tool is impractical. The developer test tool runs end to end through a runner and the mock (row 16).
- **Fixtures.** Classifying the existing fixture tools `safe` is the shared-surface update; their toolsets already call them read-only.

**Rule 2 (extend, don't copy):**
- `Gate.Resources` is `Install.Step.Tools.Parse`, moved; the installer delegates.
- The gate reads parameters through `StepBuffer.ToolParameter`, labels through `LabelFor` and `Part`, settings through `Ext.Accessor`, and fires through `Decide.FireEvent`.
- The tests reuse `Test.Bridge.Runner.NewRunner` and `ProviderConfig`, `RunnerFixture` (rows, item settings, the mock's log, `ToolResults`, warnings), `ProbeSink`, and `CodeRules.ToolClasses`, made callable.
- `ZzGateTool` is a new fixture, not an extension of `StepsNote` or `ProbeTool`: its tools need classifications, resources and hooks that would change those fixtures' own tests.

**For the lead (Rule 20; the plan does not write the spine):**
- Consider amending the "Tool classification" row with: the `Classify<NAME>` hook; the precedence (code, then Decide's `ToolClassification`, then `ClassificationClass`, with `mcp:` sources through the extension only); exact values; ignored metadata requirements; and the setting's grammar.
- Consider noting `Ext.Classification.Classify(source, name, arguments)` and Decide's `ServiceUser` setting in AD-31 or AD-10.

**Integration ACs:**
- `DiagnosisAgent`, the production runner, builds its agent with the gate, and its read-only watch tool runs: Diagnosis's second model request carries `{"items":[]}` (`Test.Agent.Runners`; row 2).
- The `HostSinkClass` that Decide's setting names (`ProbeSink`) receives `turn.step` from a runner's allowed call (row 17).
- `StepAudit` records the gate's denial as a `denied` step on the Reply (rows 15 and 16).

**Consumed-by:**
- **Story 3.3:** adds the provenance and taint rule before the result, and reads `readOnly` and `trustedOutput` from `ClassificationOf`.
- **Story 3.6:** calls `Approval.Raise` in the risky branch of a user's turn, and replaces `NEEDSAPPROVAL`.
- **Story 30.3:** checks the replay grant before the result.
- **Story 2.6 (Lane B):** `BridgeSink` publishes `turn.step` to the session's stream (UX-DR66).
- **Story 14.1:** the security overview lists the classifications and the resources.
- **Step 4 (MCP):** `ClassificationClass` with the source, and the `OcuTalon_MCP_<server>` resources.
- **Story 5.4:** replaces `WatchFixture` and keeps its classification (the scan enforces it).

**Consumes:**
- `Context` (Stories 0.6 and 1.2);
- `StepBuffer.ToolParameter`, `LabelFor` and `Part` (Stories 1.5 and 3.1);
- `Decide.FireEvent` (Story 1.3);
- `Ext.Accessor.ValueFor` and `ClassFor` (Stories 0.6 and 1.4);
- the `HostSink` payloads (Story 0.6);
- the service user `OcuTalonService` and its role (Story 3.1);
- `$SYSTEM.Security.CheckUserPermission`;
- AI Hub's authorization chain.

**Ledger inbox** (`LEDGER slice 3-2-one-gate-decides-every-tool-call`): DW-143 is addressed by the `WatchFixture` task, matrix row 2, `TestEveryBuiltInToolIsClassified` and the integration AC.

**Footprint:**
- Every file is in Epic 3's footprint (`src/bridge/**`, `Install/**`, `Test/Bridge/**`, `ci/mock/scenarios/A/**`, and the `OcuTalon.Tools` tool classes) except the footprint extension `src/ocutalon/cls/OcuTalon/Test/Tools/ZzResultTool.cls`, which is Lane A's and not contended.
- `Core/BridgeSink.cls` is only read: it is named in `CodeRules.CALLBACKHELPERS`.

**Shard time:** the new class adds about 20 to 40 s (inference: mostly shadow-runner calls of about 1 to 2 s each, and two production updates for row 17). That puts the fresh `lane-a` shard at about 430 to 450 s, inside 8 minutes.

## Verification

**Targets:**
- `ocutalon-slot-a` is for `iris_doc_load` compiles only. Pass MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call, after `iris_server_info` shows build 154.
- Everything else runs through `ci/iris.sh` and `ci/warm.sh`. Never `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, slot B or slot C. No push, and never read `.env`.
- Run every command from the worktree root, in the foreground with `timeout: 600000`, with these variables on the same line:
  - `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)"`;
  - `OCUTALON_TEST_WEB_PORT=52801`;
  - `OCUTALON_LOCK_OWNER='epic=3 stage=implement'`.
- The tags: fresh `e3s2i` and warm `e3s2iw`; QA `e3s2q`/`e3s2qw`; review `e3s2r`/`e3s2rw`.

**Commands:**
- (loop) `bash ci/checks.sh` -- expected: every block passes, `boundaries` (AD-2), `class-rules` and `storage` (Decide's appended values) included. About 20 s.
- (loop) `bash docker/tests/test-mock.sh` -- expected: the mock's node tests pass, so the three new scenario files keep the grammar. Under 15 s.
- (loop) `OCUTALON_RUN_TAG=e3s2iw bash ci/warm.sh up` -- run it once the adapter change and the three scenario files are in the tree, because a change under `ci/mock` refuses a warm run and needs `down` and `up` again. Expected: a ready warm stack.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e3s2iw bash ci/iris.sh class <Class>`, one call per class -- expected: `CLASS ... passed` after a `WARM reloaded` line. The classes:
  - `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Bridge.Steps`, `OcuTalon.Test.Bridge.Runner`, `OcuTalon.Test.Bridge.Ext`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Bridge.Example` and `OcuTalon.Test.Bridge.Conversation`;
  - `OcuTalon.Test.Install.Tools`;
  - `OcuTalon.Test.Tools.Result` and `OcuTalon.Test.Tools.Reminders`.

  A production runner on a warm stack keeps the agent it built before a reload, so `Test.Agent.*` evidence about the gate counts only from a stack whose runners built after the change: the fresh shard below, or the warm stack after `down` and `up`.
- (loop) `OCUTALON_RUN_TAG=e3s2iw bash ci/warm.sh down` -- run it at the stage's end and after a failure.
- (once) `OCUTALON_RUN_TAG=e3s2i bash ci/iris.sh shard lane-a` -- expected: every class passes, `Test.Bridge.Gate` and `Test.Agent.Runners` included. About 430 to 450 s.
- (once) `OCUTALON_RUN_TAG=e3s2i bash ci/iris.sh shard lane-b` -- expected: every class passes.
- (once) `OCUTALON_RUN_TAG=e3s2i bash ci/iris.sh live production` -- expected: PASS (the runners build their agents with the gate).
- (once) `OCUTALON_RUN_TAG=e3s2i bash ci/iris.sh live demo-path` -- expected: PASS (UJ-1's chat turns run their tools through the gate).
- (once) `OCUTALON_RUN_TAG=e3s2i bash ci/iris.sh teardown` -- expected: nothing tagged `e3s2i` is left.

**Shared surfaces:**
- Every tool call of every runner now passes the gate. Tests that run fixture tools need the fixtures classified: search the test trees and `ci/mock/scenarios` for `toolUse`, `TOOLSETS` and `Extends %AI.Tool`.
- The host sink's calls gain `turn.step` for each allowed call. Search `SinkCalls`, `EventTypes` and `ZzProbeSink`, and update any assertion on a path where a tool runs.
- Decide gains `SETTINGS` entries and storage values, and the gate reads its `ToolClassification`, `ServiceUser` and `ClassificationClass` rows.
- `Ext.Classification.Classify`'s signature changes.
- `CodeRules.CALLBACKHELPERS`'s count and `ToolClasses`' visibility change.
- `ci/mock/scenarios/A` gains three files.
- `Install.Step.Tools.Parse` now delegates, and `WatchFixture` gains classification parameters.
- Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19; record each as `mutation: ... -> ...` here):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | row 16 | `OnAfterAgentInit` does not add the gate |
| AC 2 | rows 7 and 8 | `ClassificationOf` keys on the name alone, or the `mcp:` check is removed |
| AC 2 | row 5 | the setting is read before code |
| AC 2 | row 10 | `metadata.CLASSIFICATION` is read |
| AC 3 | row 12 | the whole permission string goes to one `CheckUserPermission` call |
| AC 3 | row 13 | the permission check is skipped |
| AC 4 | row 15 | `Check`'s Catch rethrows |
| AC 4 | row 14 | the context check is removed |
| AC 5 | row 17 | the payload gains a key, or the owner is the `DecisionRef` |
| AC 5 | row 3 | a denied call fires `turn.step` |
| AC 6 | row 18 | `Check` allows a risky call, or the `CASES` check is dropped |
| DW-143 | row 2 and `TestEveryBuiltInToolIsClassified` | `CLASSIFICATIONREADFAILEDMESSAGES` is removed from `WatchFixture` (on a fresh stack for `Test.Agent.Runners`) |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
