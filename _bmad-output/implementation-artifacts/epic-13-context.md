# Epic 13 Context: Any production can use the bridge

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Prove the bridge is a reusable product, not an OcuTalon internal. A production developer with no OcuTalon installed loads the bridge's classes without IPM, runs its installer, configures it purely through production settings and runs an example production whose own agent, tools, decisions, agent steps and approvals show up in Visual Trace. A developer guide documents the install, every setting, the message types and the governance rules, and CI runs it verbatim on a clean instance. This is 1.0.0 kit work (Must, never cut) and sits on the critical path to the 1.0.0 release candidate.

## Stories

- Story 13.1: The example production makes its own decision through the bridge
- Story 13.2: The example's own tools wait for approval when they are risky
- Story 13.3: The bridge developer guide, proved on a clean instance

## Requirements & Constraints

- **Standalone.** The example runs in an Interoperability namespace with no other OcuTalon class, channel, web app or package. Install = load `src/bridge/` with `$SYSTEM.OBJ.LoadDir`, then run `OcuTalon.Bridge.Installer` (Workflow role and user, audit events, default settings, prices). No IPM.
- **Settings only.** Agent class, runner agent allow-list (seeded with OcuTalon's three agents; the developer adds their own), toolsets, model per runner, provider config, token budget per decision, timeout (110 s ceiling), fallback route, approval role, tool classifications and the three extension classes. A change to model, budget or timeout applies to the next decision with no code change.
- **One decision per item:** outcome (`ignore`, `digest`, `tellnow`, `act`), plain-English reasons, confidence 0..1, four token counts (input, output, cache read, cache write), USD cost from `OcuTalon.Bridge.Data.Price`. Routable by other components.
- **Trace.** Visual Trace shows the item, the decision message and each agent step in order (name, inputs/result summary, duration, request size labelled as an estimate). Tokens and cost are per turn and per decision, never per step.
- **Fallback.** Timeout, refusal, budget exceeded or missing key → `tellnow`, flagged with reason (`timeout`, `refusal`, `budget`, `no_key`), routed on the fallback route; no tool runs; the production keeps running.
- **Governance.**
  - Unclassified tools count as risky.
  - `user` item: a risky or unclassified call runs nothing. It becomes one `tool_call` approval request in IRIS Workflow, holding the exact call.
  - `untrusted` item: only read-only tools run; other calls are denied with a plain sentence and no request is raised.
  - An approved call replays once, with no model request. Only holders of the approval role may answer; a second answer gets `already_answered`, a user without the role gets `not_allowed`.
  - Rejected or expired (24 h) requests never run. Every outcome is audited with time, IRIS user and channel.
- **No extension class named.** Cost and audit still happen through the do-nothing defaults.
- **Secrets.** The key comes only from `ANTHROPIC_API_KEY` via `@{env:...}` and is never stored. The test's dummy key must appear in no step, decision, event-log or audit entry. No request sets `temperature`, `top_p` or `top_k` (the CI mock rejects it).
- **CI.** The `standalone-bridge` job in `.github/workflows/lane-a.yml` runs on the IRIS runner in a clean build 154 container, with an image built there and never cached, pushed or stored as an artifact. It fails unless the sent item's decision message and agent step appear in the example namespace. One test per tool classification. From 13.3 it runs the guide's commands exactly as written.
- **Guide** (in `docs/`): plain English; no keys, local paths, instance names or private infrastructure. Requirements: AI Hub build 154 on IRIS for Health or IRIS. It states that OcuTalon installs the same bridge in its one package, and that a separate bridge package and listing are a follow-on. It marks `StreamRenderer` subclassing and the policy setters as experimental. It tells developers to put `Timeouts.Derive(timer).http_config` into an inline `ProviderConfig`, or to use `@{config:}` with `Timeouts.Apply`, because otherwise AI Hub's 30 s Retry-After cap and default request timeout apply under the bridge timer; 13.1's timer test must keep working. The release checklist confirms the guide matches the release.
- **README.** With 13.3, the README's "What you can use it for" list gains a third item, "An AI decision step you can audit, in your own production.", linking the guide's real path.

## Technical Decisions

- **Package and footprint.** `OcuTalon.BridgeExample` in `src/bridge/cls/OcuTalon/BridgeExample/` (Lane A).
  - The boundary check fails if an example class references any OcuTalon package other than `OcuTalon.Bridge`. `%AI` and `EnsLib.AI` are allowed here.
  - OcuTalon's IPM package installs the example but never starts it in OCUTALON.
- **Production.** Grow `OcuTalon.BridgeExample.Production` from Epic 1's minimal one (items `ExampleItemIn`, `ExampleTriage`, `ExampleRouter` with rule `OcuTalon.BridgeExample.Rule`, `Example*Out`, `Decide`, `TriageAgent`, `AgentSteps`). 13.2 adds `ApprovalHold` and `OcuTalonApprovals`. New items enter the spine's ownership tables as Lane A's in the same change.
- **Pipeline.** The example process sends `OcuTalon.Bridge.Process.Decide` an `OcuTalon.Bridge.Msg.Request`:
  - kind `decide`, `OwnerRef` `instance`;
  - `Input` is rendered text, never an Item; `Summary` is one line written by code.
  - `Decide` → `OcuTalon.Bridge.Operation.AgentRunner` → `DecisionResponse`. Steps go to `AgentSteps`.
- **Agent.** A `%AI.Agent` subclass with static `XData INSTRUCTIONS` (no `{{`), a `MOCKKEY` parameter and `MODEL` `claude-haiku-5-5`.
  - It replies with one JSON object, validated against `OcuTalon.Bridge.Msg.DecisionPayload` through the runner's `ReplyClass`.
  - It must be on the runner's allow-list. The runner refuses to start if a policy, tool, skill, system-prompt or session-config setting is set on it.
- **Tools.** The example's tools are a `%AI.ToolSet`. Each tool declares a step label parameter (`STEPLABEL<NAME>` or `STEPLABEL`).
  - A developer's classification goes in `Decide`'s `ToolClassification` setting: a JSON array of `{class, tool, classification}` (`safe`/`risky`), optionally with `readOnly` and `trustedOutput`. It is a setting, not a table.
  - The gate's order is code-declared classification (built-ins), then this setting, then `ClassificationClass`. A code-given value is never overridden.
  - A tool's identity is its source (`metadata.origin_class`) plus its name.
  - No `%AI` calls and no embedded Python inside tools. Return a dynamic object or plain text, never pre-encoded JSON.
- **Approvals.** `OcuTalon.Bridge.Policy.Gate` is the always-installed, fail-closed gate.
  - The path is `Approval.Raise` → `ApprovalStartIn` → `ApprovalHold` → `EnsLib.Workflow.TaskRequest` to `OcuTalonApprovals`. `Raise` is synchronous: OK means held, and a failed `Raise` leaves no row, hold or event.
  - The approval role is `Decide`'s `ApprovalRole` setting (category Bridge, default `OcuTalonUser`), read via `Ext.Accessor.ValueFor`. An empty value refuses `Raise`.
  - The Workflow role's only member is the login-disabled `OcuTalonWorkflow`, so answers come only through `OcuTalon.Bridge.Approval.Answer`. Request rows change state only through the Approval API, under its lock.
  - A replay is a `tool` request through `Decide` with a one-shot grant.
- **Extension classes.** `HostSinkClass`, `ReplyFilterClass` and `ClassificationClass` are `Decide` settings read through `OcuTalon.Bridge.Ext.Accessor.ClassFor`. The example leaves them unset.
- **Audit and redaction.** Audit only via `OcuTalon.Bridge.Audit.Record(type, data)`; redaction via `OcuTalon.Bridge.Redact`. Tests poll the IRIS audit log with a timeout, because entries can land minutes late.
- **Mock.** Scenarios go only under `ci/mock/scenarios/A/` and are picked by a `[[mock:<name>]]` marker or the agent's `MOCKKEY`. There is no default reply: an unmatched request gets a 500. New mock behaviour is Lane B's to build.
- **Naming.** Items are PascalCase and services end `In`. Enumerations come from `OcuTalon.Bridge.Msg.Enum`. Decision fields: `Outcome`, `Reasons`, `Confidence`, `Fallback`, `FallbackReason`, `InputTokens`, `OutputTokens`, `CacheReadTokens`, `CacheWriteTokens`, `CostUSD`, `Model`, `AgentStepCount`, `DurationMs`.

## Cross-Story Dependencies

- **Builds on Epic 1 (merged):** the bridge pipeline, the minimal example production and the standalone-bridge job.
- **13.1 → 13.2 → 13.3.**
  - 13.2 needs Epic 30 merged, for Story 30.3's approved tool-call replay.
  - 13.3 needs Epic 11 merged, for the release checklist item from Story 11.4. It documents what 13.1 and 13.2 built.
- **Lane B's Story 31.3** adds the About dialog's bridge-guide link and the finish-state link "Use the same bridge in your own production ↗". 13.3 supplies the guide's stable path.
- **Later epics:** Epic 15's IPM install checks that the example is installed but not started in OCUTALON. Later bridge extensions (such as step 3's `TurnToolsClass`) must keep the standalone job passing.
- **Runner and files:** the epic runs on a pool runner but stays in Lane A's files.
