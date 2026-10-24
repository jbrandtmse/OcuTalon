# Epic 13 Context: Any production can use the bridge

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Prove the bridge is a reusable product and not an OcuTalon internal. A production developer with no OcuTalon installed loads the bridge's classes without IPM, runs its installer, configures it purely through production settings, and runs an example production. That production's own agent, tools, decisions, agent steps and approvals show up in Visual Trace. A developer guide documents the install, every setting, the message types and the governance rules, and CI runs it verbatim on a clean instance. This is 1.0.0 kit work, and it is the evidence that the bridge works in another production.

## Stories

- Story 13.1: The example production makes its own decision through the bridge
- Story 13.2: The example's own tools wait for approval when they are risky
- Story 13.3: The bridge developer guide, proved on a clean instance

## Requirements & Constraints

- **Standalone.** The example runs in an Interoperability namespace that holds no other OcuTalon class, with none of OcuTalon's channels, web app or packages. To install: load `src/bridge/` with `$SYSTEM.OBJ.LoadDir`, then run `OcuTalon.Bridge.Installer`, which sets up the Workflow role and user, audit events, default settings and prices. IPM is not involved.
- **Settings only.** The bridge is configured entirely through production settings: the agent class, the runner's agent allow-list, toolsets, the model per runner, the provider config, the token budget per decision, the timeout (at most 110 s), the fallback route, the approval role, the tool classifications and the three extension classes. A change to the model, budget or timeout applies to the next decision with no code change.
- **One decision per item.** The decision message carries an outcome (`ignore`, `digest`, `tellnow` or `act`), plain-English reasons, a confidence between 0 and 1, four token counts (input, output, cache read, cache write) and a USD cost from the bridge price table. Other components can route on it.
- **Trace.** Visual Trace shows the item, the decision message and each agent step in order, with its name, a summary of inputs and result, its duration, and a request size labelled as an estimate. Tokens and cost are recorded per turn and per decision, never per step.
- **Fallback.** A timeout, refusal, exceeded budget or missing key makes the decision `tellnow`, flagged with its reason and routed on the fallback route. No tool runs, and the production keeps running.
- **Governance.**
  - A developer classifies their own tools as read-only or risky in the bridge's settings, and an unclassified tool counts as risky.
  - In a `user` item, a risky or unclassified call runs nothing. It becomes one `tool_call` approval request in IRIS Workflow, holding the exact call.
  - In an `untrusted` item, only read-only tools run. Any other call is denied with a plain sentence, and no request is raised.
  - An approved call is replayed once, with no model request.
  - Only holders of the approval-role setting may answer. A second answer returns `already_answered`, and a user without the role gets `not_allowed`.
  - A rejected or expired request (24-hour expiry) never runs. Every outcome is audited with the time, IRIS user and channel.
- **No extension class named.** Cost and audit still happen through the do-nothing defaults.
- **Secrets.** The model key comes only from `ANTHROPIC_API_KEY` through `@{env:...}` and is never stored. The test's dummy key must not appear in any step, decision message, event-log entry or audit entry. No request may set `temperature`, `top_p` or `top_k`; the CI mock rejects any that does.
- **CI.** The standalone-bridge job in `.github/workflows/lane-a.yml` runs on the IRIS runner, in a clean build 154 container.
  - The image is built on the runner and never cached, pushed or stored as an artifact.
  - The job fails unless the sent item's decision message and agent step appear in the example namespace.
  - It runs one test per tool classification.
  - From Story 13.3, it runs the guide's commands exactly as the guide writes them.
- **Guide.** The guide lives in `docs/`.
  - It is plain English, with no keys, local paths, instance names or private infrastructure details.
  - Its stated requirements are AI Hub build 154 on IRIS for Health or IRIS.
  - It says that OcuTalon installs the same bridge in its one package, and that a separate bridge package is a follow-on.
  - It marks `StreamRenderer` subclassing and the policy setters as experimental.
  - The release checklist confirms that it matches the release.

## Technical Decisions

- **Package and footprint.** The example is the package `OcuTalon.BridgeExample` in `src/bridge/cls/OcuTalon/BridgeExample/`, in Lane A's files.
  - The boundary check fails if an example class references any OcuTalon package other than `OcuTalon.Bridge`.
  - `%AI` and `EnsLib.AI` references are allowed in this package.
  - OcuTalon's one IPM package installs it, but never starts the example production in OCUTALON.
- **Pipeline.** The example's own process sends `OcuTalon.Bridge.Process.Decide` an `OcuTalon.Bridge.Msg.Request`.
  - The request has kind `decide` and `OwnerRef` `instance`. Its `Input` is rendered text, never an Item, and its `Summary` is one line written by code.
  - `Decide` sends to an `OcuTalon.Bridge.Operation.AgentRunner` item and gets a `DecisionResponse` back. Steps go to `AgentSteps`.
  - Grow `OcuTalon.BridgeExample.Production` from the minimal production that Epic 1 built.
- **Agent.** The example agent is a `%AI.Agent` subclass with static `XData INSTRUCTIONS` that contains no `{{`, a `MOCKKEY` parameter and `MODEL` `claude-haiku-5-5`.
  - It replies with one JSON object, validated against `OcuTalon.Bridge.Msg.DecisionPayload` through the runner's `ReplyClass`.
  - Its class must be on the runner's allow-list. The runner refuses to start if any policy, tool, skill, system-prompt or session-config setting is set on it.
- **Tools.** The example's tools are a `%AI.ToolSet`.
  - Each tool declares its step label as a class parameter (`STEPLABEL<NAME>` or `STEPLABEL`).
  - A developer tool's classification comes from the bridge setting: not a table, and not the class parameters that built-in tools use.
  - A tool's identity is its source (`metadata.origin_class`) plus its name.
  - Tools must not make `%AI` calls or run embedded Python, and they return a dynamic object or plain text, never a pre-encoded JSON string.
- **Approvals.** The always-installed, fail-closed gate is `OcuTalon.Bridge.Policy.Gate`.
  - The approval path is `OcuTalon.Bridge.Approval.Raise` → `ApprovalStartIn` → `ApprovalHold` → an `EnsLib.Workflow.TaskRequest` to `OcuTalonApprovals` (`EnsLib.Workflow.Operation`).
  - The Workflow role's only member is the login-disabled `OcuTalonWorkflow`, so no person is a Workflow user. Answers come only through `OcuTalon.Bridge.Approval.Answer`, and the request row changes state only through the Approval API, under its lock.
  - A replay is a `tool` request through `Decide` with a one-shot grant.
- **Extension classes.** `HostSinkClass`, `ReplyFilterClass` and `ClassificationClass` are settings on `Decide`, read through `OcuTalon.Bridge.Ext.Accessor.ClassFor`. The example leaves them unset.
- **Audit and redaction.** Audit is written only through `OcuTalon.Bridge.Audit`, and redaction goes through `OcuTalon.Bridge.Redact`. Tests poll the IRIS audit log with a timeout, because entries can arrive minutes late.
- **Mock.** Scenario files go only under `ci/mock/scenarios/A/`. A request picks its scenario by a `[[mock:<name>]]` marker or by the agent's `MOCKKEY`. There is no default reply: a request that matches nothing gets a 500. New mock behaviour is Lane B's to build.
- **Naming.** Items are PascalCase, and service names end `In`. Enumerations come from `OcuTalon.Bridge.Msg.Enum`. Decision fields use the plain names (`Outcome`, `Reasons`, `Confidence`, `Fallback`, `FallbackReason`, the four token fields, `CostUSD`, `Model`, `AgentStepCount`, `DurationMs`).
- **Ownership tables.** The example's items go into the spine's ownership tables as Lane A's, in the same change that adds them.

## Cross-Story Dependencies

- **Builds on Epic 1 (done):** the bridge pipeline, the minimal example production and the standalone-bridge job.
- **13.1 → 13.2 → 13.3.** Story 13.1 may start early. Story 13.2 needs Epic 30 merged, for its approved tool-call replay (Story 30.3). Story 13.3 needs Epic 11 merged, for its release checklist item (Story 11.4), and documents the example from 13.1 and 13.2.
- **Lane B's Story 31.3** adds the About dialog's bridge-guide link and the finish-state link "Use the same bridge in your own production ↗". Story 13.3 supplies the guide's stable path for both.
- **Later epics:** Epic 15's IPM install checks that the example is installed but not started in OCUTALON. Later bridge extensions, such as the step 3 turn-tools class, must keep the standalone job passing.
- **Runner and files:** the epic runs on a pool runner but stays in Lane A's files.
