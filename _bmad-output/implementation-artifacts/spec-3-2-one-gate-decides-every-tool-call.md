---
title: 'Story 3.2: One gate decides every tool call'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: '18b26cfe8ee630cceed4cf68dd18c1ffb533ef17'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-6, AD-9, AD-10, AD-19, AD-24 and AD-31, and the Agent step labels, Tool classification, Tool resources and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred:
  - summary: >-
      A zero from CheckUserPermission for the ServiceUser reads as a missing privilege with no log, so a runner job without %Admin_Secure:USE would deny every tool that declares RESOURCES.
    evidence: |-
      CheckUserPermission returns 0 on error, and for a user other than $USERNAME it needs %Admin_Secure:USE (irislib/%SYSTEM/Security.cls). The gate cannot tell the cases apart, and row 13 pins NOPRIVILEGE for a user that does not exist. The tests ran as irisowner; the job of the production's runners was not measured, and no built-in tool declares RESOURCES yet.
      Settled by one gate call, with a tool that declares RESOURCES, from the production's runner job on a throwaway (the first story that adds such a built-in tool).
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls (MissingPrivilege)
    severity: medium (unverified)
  - summary: >-
      Whether AI Hub gives an MCP tool a toolref that starts mcp: is unmeasured; another form would take metadata.origin_class as the source.
    evidence: |-
      %AI.Tool.Resolver documents mcp:stdio:<command> and mcp:remote:<url> (both start mcp:) and also a JSON configuration form. Task 0 measured toolset tools only, and rows 8 and 9 build the toolref by hand. An MCP tool with another toolref that shadows a built-in name would carry the built-in's class (Story 1.5 measurement), and take its classification.
      Settled by measuring the toolref and metadata of a real MCP tool (stdio, remote and JSON configuration) in %CanExecute, in step 4 (MCP).
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls (Source, IsMcp)
    severity: medium (unverified)
  - summary: >-
      Two tools of one class whose names differ only in underscores, hyphens or case share their CLASSIFICATION, RESOURCES and STEPLABEL parameters.
    evidence: |-
      StepBuffer.ToolParameter derives NAME by upper-casing the tool name and removing _ and - (the one naming rule of Stories 1.5 and 3.1). send_mail and sendmail in one class read the same CLASSIFICATIONSENDMAIL, so a safe declaration for one covers the other. Pre-existing convention; the gate is the first reader whose result is a decision.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls (ToolParameter)
    severity: low
  - summary: >-
      A tool that is REQUIRESAUTH in AI Hub and declares safe is not held, because the gate never reads metadata's requirements (security posture; the lead rules).
    evidence: |-
      The spec's Boundaries (the gate never reads metadata's requirements) and Decided in-stage (the class parameters are the one declaration) fix this. Reading requires_auth as risky could only tighten the result; a governance-test check that no built-in tool is both safe and REQUIRESAUTH would be the smallest form.
    location: >-
      src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls (Decision)
    severity: low
  - summary: >-
      The classes that BridgeSink calls once Story 2.6 makes it publish are not in CodeRules.CALLBACKHELPERS, so the callback rule does not scan them.
    evidence: |-
      The gate fires turn.step to the HostSinkClass from inside AI Hub's authorization callback, and CALLBACKHELPERS lists OcuTalon.Core.BridgeSink only. A session call or Python in a class that it calls would deadlock or crash the job (AD-6).
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls (CALLBACKHELPERS)
    severity: low
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
- [x] Task 0 -- measure these on the stage's warm throwaway, never on the slot, and record each under Design Notes. Use a temporary authorization policy that records what it gets (deleted afterwards), or the gate once it is written.
  - (a) In `%CanExecute`, for a toolset tool, both through `ToolMgr.ExecuteTool` and through `Chat`: the value of `toolref`, the type of `call.arguments` (object or JSON string), and the keys of `metadata`.
  - (b) For a `ToolAccessDenied` denial:
    - the status that `%LogDenial` gets;
    - what `ExecuteTool` raises (its name and code), which row 18's helper catches;
    - the exact tool-result text that the model gets, from the mock's log (AI Hub's prefix before the sentence).
  - (c) Whether a denial with code 5001 instead also reaches `%LogDenial`.
  - Adjust the sentences' wording to read well after the measured prefix (keep their meaning).
- [x] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - Add `ServiceUser As %String(MAXLEN = 160) [ InitialExpression = "OcuTalonService" ]` and `ToolClassification As %String(MAXLEN = "")`: a JSON array of `{"class","tool","classification"[,"readOnly"][,"trustedOutput"]}`, where an empty value is none.
  - Add both to `SETTINGS` as `:Bridge`, and append them to the storage block.
  - Why: the bridge cannot read `Install` (AD-2), and AD-19 puts bridge values in host settings.
- [x] `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls` -- `ClassMethod Classify(source As %String, name As %String, arguments As %DynamicObject = "") As %String`. It returns `safe`, `risky` or "" (the default ""). Why: an extension must see the source to keep an MCP tool off a built-in's classification (AD-10, AD-31).
- [x] `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` (new; `Extends %AI.Policy.Authorization`, no properties) -- implement the Boundaries' rules:
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
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls` -- `OnAfterAgentInit` sets the gate as the authorization policy, then the step audit policy, and returns the first error. Why: AC 1 (AD-6).
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Tools.cls` -- `Parse` becomes `Quit ##class(OcuTalon.Bridge.Policy.Gate).Resources(value, where)`. Why: one parser (Rule 2).
- [x] `src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls` -- add `CLASSIFICATION<NAME> = "safe"`, `READONLY<NAME> = 1` and `TRUSTEDOUTPUT<NAME> = 0` for the three tools. Failed messages and event-log text are never trusted output (AD-10), and item settings are not OcuTalon's own records. Why: DW-143.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeTool.cls`, `StepsNote.cls`, `StepsCard.cls` and `StepsText.cls`, and `src/ocutalon/cls/OcuTalon/Test/Tools/ZzResultTool.cls` -- add `Parameter CLASSIFICATION = "safe"`, plus `READONLY = 1` on the three Steps fixtures, whose toolset already says ReadOnly. Why: the tests that run them keep passing with the gate (shared surface).
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateTool.cls` (new; `Extends %AI.Tool`) -- the test tool class:
  - Tool methods: `Risky`, `Safe`, `Held`, `Args`, `Throws`, `PublicRead`, `ReadWrite`, `Admin` and `Shadow`. Each sets `^||ZzGateRan(<tool name>)=1` and returns `{"ran":"<tool name>"}`.
  - Parameters:
    - `STEPLABELZZGATESAFE = "Running the safe gate test tool"`;
    - `CLASSIFICATIONZZGATEHELD = "risky"`;
    - `CLASSIFICATION<NAME> = "safe"` for `zz_gate_public`, `zz_gate_write` and `zz_gate_admin`, with the `RESOURCES<NAME>` values of rows 11 to 13.
  - `[ Internal ]` hooks: `ClassifyZZGATEARGS(arguments)` (row 6) and `ClassifyZZGATETHROW(arguments)`, which reads an undefined variable.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateTools.cls` (new toolset, `DependsOn` the tool class) -- names `zz_gate_risky`, `zz_gate_safe`, `zz_gate_held`, `zz_gate_args`, `zz_gate_throw`, `zz_gate_public`, `zz_gate_write`, `zz_gate_admin` and `set_reminder` (`Shadow`).
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateAgent.cls` (new; `MODEL` `claude-haiku-5-5`, `TOOLSETS` the toolset, a static `INSTRUCTIONS`) and `src/ocutalon/cls/OcuTalon/Test/Bridge/ZzGateClassification.cls` (new; extends `Ext.Classification`; row 9).
- [x] `ci/mock/scenarios/A/gate-risky.json`, `gate-safe.json` and `gate-throw.json` (new) -- the marker is the name. The first reply is a `toolUse` of `zz_gate_risky`, `zz_gate_safe` or `zz_gate_throw` with `{}`, and the second a text reply.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` (new) -- tests for rows 1 to 18, one method per row or close group:
  - Rows 15 to 17 are guarded with `RunnerFixture.GuardReason()`, like `Test.Bridge.Runner`.
  - Row 18 runs each tool through `%AI.ToolMgr` (`RegisterToolSet`, `SetAuthPolicy`, `SetAuditPolicy`, `Context.Begin`, `StepBuffer.Start`, `ExecuteTool`).
  - `Parameter CASES = ""` holds the risky arguments of the `Classify`-hook built-in tools, as `provider:name=<JSON>` entries; there are none today.
  - `TestEveryBuiltInToolIsClassified` checks that every tool of every `OcuTalon.Tools` toolset is classified by code (DW-143's scan).
  - `OnAfterOneTest` ends the context and the buffer, kills `^||ZzGateRan` and `^||ZzProbeSink`, and restores the remembered rows and item settings.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`:
  - Add `OcuTalon.Bridge.Ext.Accessor`, `OcuTalon.Bridge.Process.Decide`, `OcuTalon.Bridge.Ext.HostSink`, `OcuTalon.Bridge.Ext.Classification` and `OcuTalon.Core.BridgeSink` to `CALLBACKHELPERS`: the gate calls them inside the callback.
  - Drop `Private` from `ToolClasses`, so that `Test.Bridge.Gate` reuses the test-side inventory.
  - Update the doc comments.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Ext.cls:204-205` -- call `Classify` with `(source, name, arguments)`.

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

### 2026-10-24 -- Review pass
- verdicts: 52 findings -- high 0, medium 4, low 26, false 17, maybe-false 5
- layers: blind-hunter BH1-BH10, edge-case-hunter EH1-EH12, verification-gap VG1-VG16, intent-alignment IA1-IA13 (a descriptive report: its observations are logged as rows), and the implementation report's IMPL1
- findings:
  - `[low]` `[reject]` BH1: `HookFor` does not require the Classify hook to be `[ Internal ]` -- a toolset registers only the methods its Definition lists, so a public `Classify` is a tool only where a developer lists it, and the gate then denies it (a hook that answers neither `safe` nor `risky` leaves the tool unclassified); enforcing the flag adds a rule and a failure mode for no reachable harm
  - `[false]` `[reject]` BH2: `HookFor` swallows its own exceptions -- its Catch can only meet a <SUBSCRIPT> for an empty class name, which `ClassificationOf` has already turned into an unclassified result; the dictionary reads of a compiled or a missing class raise nothing, and `ToolParameter`'s shared Catch (Story 3.1) leaves CLASSIFICATION empty, which counts as risky
  - `[medium]` `[patch]` BH3: the class-wide `Classify` branch of `HookFor` and the order hook-before-parameter are untested (same root cause as VG3) -- the order is the spec's (methods, then parameters); pinned now by `TestClassWideHook` and the fixture `ZzGateWide`, with two mutations recorded
  - `[low]` `[reject]` BH4: non-object `call.arguments` (array, number, null) becomes `{}` for a code hook, while a JSON string that is not an object is FAILED (same root cause as EH1) -- AI Hub's `call.arguments` is an object (Task 0 and S9), no provider produces another type, and a throw for `null` would deny real calls that carry none; a hook that says `safe` for `{}` is the developer's own
  - `[low]` `[patch]` BH5: `Ext.Classification.Classify` documents `arguments` as the call's but the gate passes none (same root cause as EH11) -- the spec forbids passing them (Never: no call arguments except to a code hook); the class and method comments now say the gate passes none
  - `[low]` `[patch]` BH6: the host-facing contracts do not say that `turn.step` and `Classify` run inside AI Hub's authorization callback -- `HostSink` and `Classification` comments now say so (AD-6); the classes a future `BridgeSink` calls are not scanned by `CALLBACKHELPERS` (deferred to Story 2.6)
  - `[low]` `[patch]` BH7: the `NOPRIVILEGE` sentence names a resource and a letter although the comment said the sentences hold no internal name -- row 12 requires the pair in the sentence; the comment is corrected
  - `[maybe-false]` `[defer]` BH8: a failed or unauthorised `CheckUserPermission` (the caller needs `%Admin_Secure:USE` for a user other than `$USERNAME`) reads as a missing privilege with no log (same root cause as EH3) -- the test process ran as `irisowner`; the production's runner job was not measured, and row 13 pins NOPRIVILEGE for a user that does not exist; settled by one call from the production's job (deferred)
  - `[low]` `[defer]` BH9: `metadata.requires_auth` is never read, so a tool that is `REQUIRESAUTH` and declares `safe` is not held -- spec-bound (Boundaries: the gate never reads `metadata`'s requirements; Decided in-stage: the class parameters are the one declaration); touches the security posture, so the lead rules whether to tighten it (deferred)
  - `[low]` `[patch]` BH10: `ToolClassification` is declared without a length limit but a System Default Settings row holds 2,000 characters -- the property comment now says so and where a longer list goes
  - `[low]` `[reject]` EH1: `ArgumentsOf` treats array, number, boolean and null arguments as none -- same root cause as BH4
  - `[false]` `[reject]` EH2: an unreadable `HostSinkClass` setting denies an allowed call with FAILED -- the spec denies on an error status from any step (Boundaries: Fail closed); only a sink that fails when called is non-fatal, and `FireEvent` keeps that
  - `[maybe-false]` `[defer]` EH3: `CheckUserPermission` returns 0 on error with `%objlasterror` -- same root cause as BH8
  - `[false]` `[reject]` EH4: an empty or blank `ServiceUser` could resolve to the calling job's user -- measured on the warm throwaway as `irisowner`: `CheckUserPermission` returns 0 for "", " " and an unknown user, so the call is denied with NOPRIVILEGE (fail closed)
  - `[low]` `[reject]` EH5: `CheckUserPermission` leaves `%sqlcontext` behind (`%SYS.Ensemble` kills it) -- no disturbance of later SQL was shown, and killing a %-variable of the caller's frames inside a callback is itself a risk
  - `[maybe-false]` `[defer]` EH6: an MCP tool whose toolref is JSON or has another scheme would take `metadata.origin_class` as its source -- AI Hub's `%AI.Tool.Resolver` documents `mcp:stdio:` and `mcp:remote:` (both start `mcp:`) and a JSON config form; Task 0 measured toolset tools only; settled by measuring a real MCP tool's toolref and metadata in step 4 (deferred)
  - `[false]` `[reject]` EH7: metadata without `origin_class` (the method-scan generator) makes code-classified tools denied -- Task 0 measured `origin_class` for toolset tools in both paths, every agent here uses toolsets, and a tool without a source is unclassified and denied (fail closed); the scan's `provider` is the same class for toolset tools (row 18 runs the real `ExecuteTool`)
  - `[false]` `[reject]` EH8: `HookFor` and `ToolParameter` swallow dictionary errors -- same root cause as BH2
  - `[low]` `[defer]` EH9: two tools of one class whose names differ only in `_`, `-` or case share `CLASSIFICATION<NAME>`, `RESOURCES<NAME>` and `STEPLABEL<NAME>` -- the one naming rule of Stories 1.5 and 3.1 (Consistency Conventions), not this story's; a toolset-level check would settle it (deferred)
  - `[false]` `[reject]` EH10: `turn.step` fires for requests that are not turns -- the spec decides it (Decided in-stage: any request kind, the sink decides what to publish), and `TestAnyRequestKindAndProvenance` now pins it
  - `[low]` `[patch]` EH11: the extension is called with source and name only -- same root cause as BH5 (documented)
  - `[low]` `[reject]` EH12: a host override of the old `Classify(tool, arguments)` would see source as tool -- the old default returned "" and no host extension exists before 0.1.0; `Test.Contract.Ac` pins the new signature
  - `[medium]` `[patch]` VG1: every RESOURCES fixture has one pair, so a loop that checks only the first pair passes -- `odd_two_held`, `odd_two_late` and `odd_two_first` added to `ZzGateOdd`, asserted by `TestSeveralPairsAndPrivilegeBeforeApproval`; mutation recorded
  - `[low]` `[patch]` VG2: the label of `turn.step` is redacted and cut by `Part`, and no gate test pins that -- `TestStepLabelIsRedactedAndCut` (StepsCard's Bearer label, and a 250-character label of `odd_long`); mutation recorded
  - `[medium]` `[patch]` VG3: the hook-before-parameter order and the class-wide `Classify` are not exercised -- same root cause as BH3
  - `[low]` `[patch]` VG4: privilege before approval is not pinned (no tool is risky and unprivileged) -- `odd_risky_res` asserts NOPRIVILEGE; mutation recorded
  - `[low]` `[patch]` VG5: no test runs the gate for a request kind other than turn or a provenance other than user -- `TestAnyRequestKindAndProvenance` (decide, diagnose, turn, all untrusted); mutation recorded
  - `[low]` `[reject]` VG6: the error branch of an unreadable `HostSinkClass` is never reached -- the fail-closed rule is pinned by rows 5, 9 and 13, and the branch needs a seam that stops the production's settings from being read
  - `[low]` `[patch]` VG7: row 3's `$Data(^||ZzGateRan) = 0` after `Check` cannot fail (`Check` never runs a tool) -- the assertion is removed; "does not run" is pinned by `TestGovernanceSample` (RunDenied) and rows 15 and 16
  - `[low]` `[reject]` VG8: `TestEveryRiskyBuiltInIsDenied` asserts over an empty population -- the spec's row 18 shape (no built-in tool is risky today and none may be added); the same helper is pinned by `TestGovernanceSample` on the sample (mutation recorded)
  - `[low]` `[reject]` VG9: `TestDeveloperRiskyEndToEnd` passes without the setting being read -- the spec's row 16 names the entry; reading the setting is pinned by `TestDeveloperSetting` and `TestAllowedEndToEnd`
  - `[low]` `[reject]` VG10: `TestOneParser` stays green if the installer keeps its own copy of the parser -- the contract is that both read a value alike, which the test and `Test.Install.Tools` pin
  - `[low]` `[patch]` VG11: the denial sentences are never compared to each other -- `TestSentences` asserts that the three differ; mutation recorded
  - `[medium]` `[patch]` VG12: the tests lean on baseline state they do not set (rows of `ToolClassification`, `ClassificationClass` and `ServiceUser`; the unchecked restores; `TestCanExecute` firing the production's real sink) -- `OnBeforeOneTest` remembers and clears the three rows, `OnAfterOneTest` asserts both restores, `TestCanExecute` sets ProbeSink (CI override only); the stale-guard of the saved sink is fixed
  - `[low]` `[reject]` VG13: ACs and rows without their own `mutation:` line -- Rule 19 asks one demonstrated mutation per AC (recorded: all of the spec's table), AC 8 is a suite-level run with no single pinning test; the tests added in this pass carry their lines
  - `[false]` `[reject]` VG14: AC 7 and AC 8 are not shown by the warm run -- `Test.Agent.Runners` passed on a warm stack built after the change, and the fresh shards and live scripts run once at finalize
  - `[maybe-false]` `[defer]` VG15: `mcp:<server>` as AI Hub's toolref for an MCP tool is an unmeasured assumption -- same root cause as EH6
  - `[low]` `[reject]` VG16: the installer does not read the test tools' RESOURCES, and would grant `%Admin_Secure:U` only if its scan widened beyond `OcuTalon.Tools` -- a scan that `Test.Install.Tools` pins to that package
  - `[false]` `[reject]` IA1: tests call `Check` with a hand-built toolref (the tool's name) -- Task 0 measured a toolset tool's toolref as its name, and the gate reads the toolref only through `IsMcp`
  - `[false]` `[reject]` IA2: direct tests pass an explicit sink class -- `Check`'s optional argument is the spec's; the production's `HostSinkClass` path is pinned by `TestAllowedEndToEnd` and `TestCanExecute`
  - `[false]` `[reject]` IA3: rows 15 to 17 run only for `ZzGateAgent` in a shadow runner under `Guard` -- the spec's design
  - `[false]` `[reject]` IA4: row 18 builds its own `%AI.ToolMgr` and bypasses `OnAfterAgentInit` -- the spec's design (a fresh `%AI.ToolMgr` with the gate and the step audit policy); row 16 pins the adapter's wiring
  - `[false]` `[reject]` IA5: row 2's `{"items":[]}` assertion is in the existing `Test.Agent.Runners` -- the spec names it as the integration check (`Test.Agent.Runners`), and it passed
  - `[maybe-false]` `[defer]` IA6: MCP is synthetic in rows 8 and 9 -- same root cause as EH6
  - `[false]` `[reject]` IA7: `turn.step` is observed only on `ProbeSink`, because `BridgeSink` is read only here and does nothing yet -- Story 2.6 (Lane B) makes it publish
  - `[low]` `[reject]` IA8: an item-level `ToolClassification` setting is never tested, only a System Default Settings row -- both go through `Accessor.ValueFor`, which the Accessor tests pin
  - `[false]` `[reject]` IA9: the watch classification lives on the fixture -- the spec's DW-143 task, kept by Story 5.4 and enforced by `TestEveryBuiltInToolIsClassified`
  - `[false]` `[reject]` IA10: the existing fixture tools are classified `safe` -- the spec's shared-surface update
  - `[false]` `[reject]` IA11: setting entries carry optional `readOnly` and `trustedOutput` and the MCP prefix matches in any case -- the first is the spec's grammar, the second only widens what the extension alone classifies
  - `[false]` `[reject]` IA12: an invalid declared value is final, the privilege check comes before the approval check, and an unreadable sink setting denies -- each is the spec's (Values, Decided in-stage: the order, Fail closed)
  - `[low]` `[patch]` IA13: `ServiceUser`'s default duplicates the installer's `SERVICEUSER` -- the bridge cannot name Install (AD-2); `TestSettings` now asserts that the two agree
  - `[low]` `[patch]` IMPL1: a denied step on the Reply read `Denied: Tool access denied: ERROR <%AICore>ToolAccessDenied: Tool access denied: <sentence>..` (AI Hub's prefix and the code twice, and a double period) -- the spec expected `Tool access denied: <sentence>`; `StepAudit.DenialText` now gives that, pinned by rows 15, 16 and row 18's helper; mutation recorded

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

**Measured at implementation** (Task 0, on the warm throwaway `e3s2iw`, build 154, with a temporary authorization policy and a temporary audit policy that recorded what AI Hub gave them, both deleted afterwards; run through `ToolMgr.ExecuteTool` and through `Chat` in a shadow runner on the mock):
- **(a) What `%CanExecute` gets** for a toolset tool, in both paths:
  - `toolref` is the tool's name (`zz_gate_safe`, `zz_steps_note`);
  - `call.arguments` is a JSON object (type `object`), not a string (the audit policy gets the JSON string); `call` holds `id` (`call_id` through `ExecuteTool`, `toolu_mock_<n>_<n>` through `Chat`), `name` and `arguments`;
  - `metadata` holds `origin_class` and `requires_auth` (0), and the tool's `Requirement` elements when the toolset has them (`ReadOnly` = 1 for the Steps tools).
  - The gate accepts the arguments as an object or as a JSON string.
- **(b) A `ToolAccessDenied` denial** (`$SYSTEM.Status.Error("<%AICore>ToolAccessDenied", <sentence>)`):
  - `%LogDenial` gets a status with the code `<%AICore>ToolAccessDenied` whose text is AI Hub's "Tool access denied: " followed by the gate's whole status text: `ERROR <%AICore>ToolAccessDenied: Tool access denied: <sentence>`. So the step's detail through `StepAudit.StatusText` reads `Tool access denied: ERROR <%AICore>ToolAccessDenied: Tool access denied: <sentence>`;
  - `ExecuteTool` raises an exception whose name and code are both `<%AICore>ToolAccessDenied` (`AsStatus()` has the same code), which the governance helper catches;
  - the tool result that the model gets (from the mock's log) is the JSON object `{"error":"Access denied: Global policy denied: ERROR <%AICore>ToolAccessDenied: Tool access denied: <sentence>"}`.
  - The sentences end that text and already read well after "Tool access denied: ", so their wording is unchanged.
- **(c) A denial with code 5001** also raises `ToolAccessDenied` in `ExecuteTool`, also reaches `%LogDenial` (as the same `ToolAccessDenied`-coded wrapper, text `Tool access denied: ERROR #5001: ...`) and gives the model `Access denied: Global policy denied: ERROR #5001: ...`. AI Hub treats any error status from an authorization policy as a denial; the gate keeps the `ToolAccessDenied` code by the spec.
- **Also seen:** a two-letter permission (`RW`) in one `CheckUserPermission` call was allowed for `%DB_IRISLIB`, which the service user reads but does not write (the row 12 mutation), so the one-letter rule of Story 3.1 stands.

**Measured in the review pass** (the warm throwaway `e3s2iw`, a temporary test class that was deleted afterwards): in a process of the user `irisowner`, `$SYSTEM.Security.CheckUserPermission` returns 0 for the user "" and " " (to `%Admin_Secure:U` and to `%DB_IRISLIB:R`) and for a user that does not exist, with no error in `%objlasterror`. So a blank `ServiceUser` setting denies every tool that declares resources with NOPRIVILEGE (fail closed).

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

- **Code that declares is final, even when it declares badly.** A `Classify` method that returns, or a non-empty `CLASSIFICATION` parameter that holds, anything but exactly `safe` or `risky` leaves the tool unclassified, and neither the setting nor the extension is asked. So a typo in a built-in tool cannot be turned into `safe` by a setting (fail closed). An empty parameter declares nothing.
- **The extension gets no arguments.** The gate gives `Classification.Classify` the source and the name only (`arguments` stays ""), because a call's content classifies nothing except through a code `Classify` method. The `arguments` parameter of the extension's signature stays for a host that calls it itself.
- **Every denial by FAILED logs one warning**, a missing context or a call that is no object included (the spec asks for it for exceptions); they all go through one throw and one catch in `Check`. The `mcp:` prefix is matched in any case, which only widens what the extension alone classifies.
- **A sink class that cannot be read** (the `HostSinkClass` setting) denies the call with FAILED, as any error status from a step does. A sink that fails when called is logged and changes nothing.
- **Setting grammar details.** `readOnly` and `trustedOutput` in a `ToolClassification` entry are the numbers 1 or 0, or a boolean; any other value is malformed. A value of white space only is none.
- **Test additions beyond the spec's list.** `Test.Bridge.ZzGateOdd` (a fixture class in no toolset) holds the odd declarations that rows 6 and 13 need and the toolset of the sample would blur: a hook and a parameter with a value that is not exact, an empty `CLASSIFICATION`, flags that are not exactly 1, and a `RESOURCES` value that is no resources. `Gate.HookFor` is public so that the governance test can ask which tools classify by their arguments. `CASES` entries are separated by a line feed. `Test.Contract.Ac` (the cross-lane signature oracle) names `Classify(source, name, arguments)`; it is outside the footprint list and not contended, and it would fail the lane B shard otherwise.
- **Seen, not changed.** `StepAudit.StatusText` strips only the first "ERROR <code>: ", so a denied step's detail reads "Tool access denied: ERROR <%AICore>ToolAccessDenied: Tool access denied: <sentence>" (see the measurements). It is in the step's summary on the Reply; cleaning it is a follow-up for the step audit policy.

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
- Footprint extension (Rule 11 (b), outside every contended path): `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`, whose signature oracle pins `Ext.Classification.Classify` and now reads `source,name,arguments`. Without it the `lane-b` shard fails.

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

**Mutations recorded at implementation** (Rule 19; each applied alone on the warm throwaway `e3s2iw`, `Test.Bridge.Gate` run, then reverted byte-identical):
- mutation: `OnAfterAgentInit` does not add the gate -> `TestDeveloperRiskyEndToEnd` red (the tool ran; the AuthPolicy is not the gate), also `TestExceptionEndToEnd` and `TestAllowedEndToEnd` (AC 1, row 16)
- mutation: `ClassificationOf` keys the shadowed name `set_reminder` on `ReminderTools` whatever the source -> `TestSameNameAnotherClass` and `TestMcpShadow` red (AC 2, rows 7 and 8)
- mutation: `IsMcp` always 0 (the `mcp:` check removed) -> `TestMcpShadow` and `TestExtension` red (AC 2, rows 8 and 9)
- mutation: the `ToolClassification` entry is read before the code of the class -> `TestDeveloperSetting` red (`zz_gate_held` and `set_reminder` change), also `TestMalformedSettingFailsClosed` and `TestOddValues` (AC 2, row 5)
- mutation: `Check` allows a call whose metadata says `CLASSIFICATION` safe -> `TestCallContentCannotClassify` red (AC 2, row 10)
- mutation: the whole permission string goes to one `CheckUserPermission` call -> `TestOneLetterPerCall` red (AC 3, row 12)
- mutation: `MissingPrivilege` is never asked (the permission check skipped) -> `TestPrivilegeMissing` and `TestOneLetterPerCall` red (AC 3, row 13)
- mutation: `Check`'s Catch rethrows instead of denying and logging -> `TestExceptionEndToEnd` red (the warning is missing), and `TestNoContext`, `TestMalformedCall`, `TestMalformedSettingFailsClosed`, `TestArgumentDependent`, `TestExtension` and `TestPrivilegeMissing` error out (AC 4, row 15)
- mutation: the context check removed from `Decision` -> `TestNoContext` red (a risky tool is no longer denied with FAILED; a safe one still fails on the missing context only by accident, which is why the test also asks for a risky tool) (AC 4, row 14)
- mutation: the owner of `turn.step` is the `DecisionRef` -> `TestAllowedEndToEnd` and `TestSafeBuiltInIsAllowedAndReported` red (AC 5, rows 17 and 1)
- mutation: a denied call fires `turn.step` -> `TestRiskyByCodeAndUnclassified` red, also `TestCallContentCannotClassify`, `TestDeveloperSetting`, `TestArgumentDependent`, `TestExtension` and `TestMcpShadow` (AC 5, row 3)
- mutation: `Check` allows a risky call (`Quit $$$OK` for a call that is not safe) -> `TestGovernanceSample` red (the sample's risky tools are not denied), also `TestCanExecute`, `TestDeveloperRiskyEndToEnd` and others (AC 6, row 18)
- mutation: the `CASES` check dropped from the governance helper -> `TestGovernanceSample` red (`zz_gate_args` and `zz_gate_throw` are no longer flagged) (AC 6, row 18)
- mutation: `CLASSIFICATIONREADFAILEDMESSAGES` removed from `WatchFixture` -> `TestWatchToolsAreClassified` and `TestEveryBuiltInToolIsClassified` red; and `Test.Agent.Runners` `TestRequestsUnderTheModelRules` red ("as the JSON object {"items":[]}"), on a warm stack whose production runners built after the change (DW-143)
- mutation: `Valid` matches the values without regard to case -> `TestOddValues` and `TestMalformedSettingFailsClosed` red (the exact values, beyond the table)

**Mutations recorded in the review pass** (Rule 19; for the tests added or changed there; each applied alone on the warm throwaway `e3s2iw`, `Test.Bridge.Gate` run, red, reverted byte-identical, and the class green again on the same stack):
- mutation: the permission loop of `MissingPrivilege` checks only the first pair (`While` becomes `If`) -> `TestSeveralPairsAndPrivilegeBeforeApproval` red (`odd_two_late` is allowed and reported) (AC 3)
- mutation: `Decision` tests the classification before the privilege (the two `Quit` lines swapped) -> `TestSeveralPairsAndPrivilegeBeforeApproval` red (`odd_risky_res` is denied for an approval) (AC 3, the order)
- mutation: the label of `turn.step` is `LabelFor` without `Part` -> `TestStepLabelIsRedactedAndCut` red (the Bearer token stays, the 250 characters stay) (AC 5)
- mutation: the class-wide `Classify` branch of `HookFor` removed -> `TestClassWideHook` red (`wide_plain` and `wide_param` are no longer risky by code) (AC 2)
- mutation: `HookFor` tries the class-wide `Classify` before the tool's own method -> `TestClassWideHook` red (`wide_own` is risky) (AC 2)
- mutation: `turn.step` fires only when `context.Kind` is turn -> `TestAnyRequestKindAndProvenance` red (AC 5)
- mutation: `StepAudit.%LogDenial` records `StatusText` instead of `DenialText` -> `TestExceptionEndToEnd`, `TestDeveloperRiskyEndToEnd` and `TestGovernanceSample` red (the step keeps AI Hub's repeated prefix) (AC 4, rows 15, 16 and 18)
- mutation: `FAILED` gets the text of `NEEDSAPPROVAL` -> `TestSentences` red (AC 4)

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Bridge.Policy.Gate` is the authorization policy that the adapter adds to every agent it builds, beside the step audit policy. It fails closed, classifies each call by (source, name) from code, then Decide's new `ToolClassification` setting, then `ClassificationClass`, checks the service user's privileges one letter at a time, denies every risky or unclassified call with a plain sentence, and fires `turn.step` for every call it allows. The watch fixture's tools are classified (DW-143), the fixture tools of the existing tests are classified `safe`, and `Test.Bridge.Gate` (rows 1 to 18, with the governance test) pins it.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` (new): the gate.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls`: `OnAfterAgentInit` sets the gate, then the step audit policy.
- `src/bridge/cls/OcuTalon/Bridge/Policy/StepAudit.cls`: a denied step reads `Tool access denied: <sentence>` (`DenialText`).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: the `ServiceUser` and `ToolClassification` settings, storage values 14 and 15 appended.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Classification.cls`, `Ext/HostSink.cls`: `Classify(source, name, arguments)`, and the callback constraint in the comments.
- `src/ocutalon/cls/OcuTalon/Install/Step/Tools.cls`: `Parse` delegates to `Gate.Resources`.
- `src/ocutalon/cls/OcuTalon/Tools/WatchFixture.cls`: classification, read-only and trusted-output parameters (DW-143).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` (new), `ZzGateTool.cls`, `ZzGateTools.cls`, `ZzGateAgent.cls`, `ZzGateClassification.cls`, `ZzGateOdd.cls`, `ZzGateWide.cls` (new): the tests and their fixtures.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`, `Ext.cls`, `ProbeTool.cls`, `StepsNote.cls`, `StepsCard.cls`, `StepsText.cls` and `Test/Tools/ZzResultTool.cls`: the callback helpers, the new signature, and the fixtures classified.
- `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`: the signature oracle reads `source,name,arguments`.
- `ci/mock/scenarios/A/gate-risky.json`, `gate-safe.json`, `gate-throw.json` (new): the end-to-end scenarios.

**Review.** One pass of four layers (blind-hunter, edge-case-hunter, verification-gap, intent-alignment) and the implementation report: 52 findings, high 0, medium 4, low 26, false 17, maybe-false 5 (the Review Triage Log holds every row with its evidence).
- **Patched (16 rows, 14 entries; medium 3 entries, low 11):** multi-pair RESOURCES, hook order and the class-wide hook, privilege before approval, `turn.step` for every request kind, the `turn.step` label, the denial sentences told apart, the cannot-fail "nothing ran" assertion removed, the tests' baseline (rows cleared and restored with checked statuses, the sink of `TestCanExecute`), the denied step's text (and its double period), the `ServiceUser` default agreeing with the installer, and four comments (`Classification`, `HostSink`, the sentences, `ToolClassification`'s 2,000 characters). Each new pinning test has a `mutation:` line.
- **Deferred (5, in the frontmatter):** a zero from `CheckUserPermission` for the service user (the runner job's privilege, medium, unverified), the real toolref of an MCP tool (medium, unverified), tool names that collide under the suffix rule (low), `requires_auth` never read (low, security posture: the lead rules), and the classes `BridgeSink` calls once Story 2.6 makes it publish (low).
- **Rejected (29 rows), each with its reason in the log:** a hook that is not `[ Internal ]` (BH1), swallowed dictionary errors (BH2, EH8), arguments that are not an object (BH4, EH1), an unreadable sink setting (EH2), a blank `ServiceUser` (EH4, measured: denied), `%sqlcontext` (EH5), metadata without `origin_class` (EH7), `turn.step` for non-turn requests (EH10), an old `Classify` override (EH12), the branches and shapes the spec fixes (VG6, VG8, VG9, VG10, VG13, VG14, VG16), and the intent-alignment observations that are the spec's design (IA1 to IA5 and IA7 to IA12).
- **Follow-up review recommended: true.** The unverified risk is `StepAudit.DenialText` (a code change after the layers read the diff: it strips AI Hub's repeated prefix and the closing period; pinned by rows 15, 16 and 18 and a recorded mutation, but no independent layer has read it), and the tests' new baseline step, which deletes three System Default Settings rows before each test and restores them after (restores asserted).

**Verification.**
- `bash ci/checks.sh`: all scripts passed (before and after the review patches). `bash docker/tests/test-mock.sh`: 94 passed.
- Warm throwaway `e3s2iw` (torn down): `Test.Bridge.Gate`, `Steps`, `Runner`, `Ext`, `CodeRules`, `Example`, `Conversation`, `Test.Install.Tools`, `Test.Tools.Result`, `Test.Tools.Reminders` and `Test.Agent.Runners` passed, and the Gate class again after every mutation was reverted.
- Fresh `e3s2i`: `shard lane-a` passed (43 classes, 380 s: 220 s under the 600 s cap), `shard lane-b` passed (24 classes, 69 s), `live production` passed, `live demo-path` passed (floor 1 of 1; 1 of 6 steps run, the rest skipped by their own stories), then `teardown` left nothing tagged `e3s2i` or `e3s2iw`.
- Task 0 and the review measurements are under Design Notes. Nothing ran on `ocutalon-slot-a` but `iris_doc_load` compiles.

**Footprint extension (Rule 11 (b)).** `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`, one line (the signature oracle of `Ext.Classification.Classify`), outside the Epic 3 footprint and every contended path; Lane B should expect the line if it touches that file.

**Residual risks.** The deferred items above; the runner job's user was not measured (the tests ran as `irisowner`); no built-in tool is risky or declares RESOURCES yet, so the governance test shows the helper on the sample only; the model sees AI Hub's own text before the sentence (`Access denied: Global policy denied: ERROR <%AICore>ToolAccessDenied: Tool access denied: <sentence>`), which the gate cannot change.
