# Epic 13 Context: Any production can use the bridge

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Prove the bridge is a reusable product, not an OcuTalon internal. A production developer with no OcuTalon installed loads the bridge's classes without IPM, runs its installer, configures it purely through production settings and runs an example production whose own agent, tools, decisions, agent steps and approvals show up in Visual Trace. A developer guide documents the install, every setting, the message types and the governance rules, and CI runs it verbatim on a clean instance. This is 1.0.0 kit work (Must, never cut) on the critical path to the 1.0.0 release candidate. Stories 13.1 and 13.2 are done; 13.3 (the guide) remains.

## Stories

- Story 13.1: The example production makes its own decision through the bridge (done)
- Story 13.2: The example's own tools wait for approval when they are risky (done)
- Story 13.3: The bridge developer guide, proved on a clean instance

## Requirements & Constraints

- **Standalone install.** An Interoperability namespace with no other OcuTalon class, channel, web app or package. Load `src/bridge/` with `$SYSTEM.OBJ.LoadDir`, then run `OcuTalon.Bridge.Installer` (Workflow role `OcuTalonApprovals` and its login-disabled member `OcuTalonWorkflow`, audit events, default settings, prices). No IPM. The key comes only from `ANTHROPIC_API_KEY` via `@{env:...}` and is never stored.
- **Settings only.** Agent class, runner agent allow-list (seeded with OcuTalon's three agents; developer adds their own), toolsets, model per runner, provider config, token budget per decision, timeout (110 s ceiling), fallback route, approval role, tool classifications, and the three extension classes with do-nothing defaults. Changes apply to the next decision with no code change. The runner refuses policy, tool, skill, system-prompt or session-config settings on the agent.
- **Decision:** one per item: `Outcome` (`ignore`/`digest`/`tellnow`/`act`), `Reasons`, `Confidence` 0..1, `Fallback`, `FallbackReason`, four token counts, `CostUSD`, `Model`, `AgentStepCount`, `DurationMs`. Tokens and cost are per turn and per decision, never per step. Fallback (`timeout`, `refusal`, `budget`, `no_key`) → `tellnow` on the fallback route, with no tool run.
- **Governance.** Unclassified counts as risky. On a `user` item, a risky or unclassified call runs nothing and becomes one `tool_call` approval request in IRIS Workflow. On an `untrusted` item only safe read-only tools run; others are denied with a plain sentence and no request is raised. Approved calls replay once with no model request. Answers come only through `OcuTalon.Bridge.Approval.Answer`, because no person is a Workflow user. Results are `done`, `already_answered`, `not_allowed`, `expired` and `not_found`. Rejected or expired (24 h) requests never run, and every outcome is audited with time, IRIS user and channel.
- **Guide (13.3)**, in `docs/`:
  - Plain English, with no keys, local paths, instance names or private infrastructure; it must pass the public-text check.
  - Install section in order: requirements (AI Hub build 154 on IRIS for Health or IRIS, Interoperability namespace), LoadDir, installer and what it sets up, the env key, starting `OcuTalon.BridgeExample.Production`, sending an item, opening the decision in Visual Trace.
  - Reference sections: every setting, the policy settings the runner refuses, the message types (`Msg.Request` kinds, provenance and owner; the decision fields; `Msg.AgentStep`; `Msg.Enum`), tool classification (identity = source class + tool name), the fallback route, Workflow approvals, and developer tool rules: no `%AI` call or embedded Python in a tool, and results as a dynamic object or plain text.
  - Say that OcuTalon installs the same bridge in its one package, and that a separate bridge package and listing are a follow-on.
  - Mark `StreamRenderer` subclassing and the policy setters as experimental.
  - Timeout advice: put `Timeouts.Derive(timer).http_config` in an inline `ProviderConfig`, or use `@{config:}` with `Timeouts.Apply`. Otherwise AI Hub's 30 s Retry-After cap and default request timeout apply under the bridge timer. 13.1's timer row must keep working.
  - U-229 condition: one sentence saying that changing the bridge's tool-classification setting writes no OcuTalon audit entry, while each tool call is still audited, with no promise of a future release. Add the same sentence to `docs/security-overview.md`'s approval-and-audit section, near its classification-setting paragraph.
  - The release checklist confirms the guide matches the release. Any "this release" statement in `docs/security-overview.md` that this epic makes untrue must be fixed in this epic's own merge.
- **README.** With 13.3, the "What you can use it for" list gains a third item, "An AI decision step you can audit, in your own production.", linking the guide's real path.
- **CI.** From 13.3, the `standalone-bridge` job in `.github/workflows/lane-a.yml` runs the guide's install and run commands exactly as written, on the IRIS runner in a clean build 154 container. The image is built there and never cached, pushed or stored. The job fails if a command fails or if no decision message and agent step for the sent item appear in the example namespace. The one-test-per-classification cases from 13.2 must keep passing. No request sets `temperature`, `top_p` or `top_k`. The test's dummy key appears in no step, decision, event-log or audit entry.

## Technical Decisions

- **Package and footprint:**
  - `OcuTalon.BridgeExample` lives in `src/bridge/cls/OcuTalon/BridgeExample/` (Lane A).
  - The boundary check fails if any example class references an OcuTalon package other than `OcuTalon.Bridge`.
  - The IPM package installs the example but never starts it in OCUTALON.
  - No existing `OcuTalon.Bridge.*` file needs to change for the example.
- **Production (as built):** `ExampleItemIn`, `ExampleTriage`, `ExampleRouter` (rule `OcuTalon.BridgeExample.Rule`), `ExampleNotifyOut`/`DigestOut`/`FallbackOut`, `Decide`, `TriageAgent`, `AgentSteps`, then `ApprovalStartIn`, `ApprovalHold`, `OcuTalonApprovals` (12 items). `Approval.Raise` needs all three approval items running. `ExampleTriage` sets the request's `ThreadSessionId` to its own session, so holds, Workflow tasks and replays land in the item's trace session.
- **Pipeline:** the example process sends `Decide` an `OcuTalon.Bridge.Msg.Request` with kind `decide` and `OwnerRef` `instance`. `Input` is rendered text and `Summary` is one line. `Decide` → `AgentRunner` → `DecisionResponse`, and steps go to `AgentSteps`. The agent is a `%AI.Agent` subclass with static `XData INSTRUCTIONS` (no `{{`), `MOCKKEY` and `MODEL` `claude-haiku-5-5`. Its reply is validated against `Msg.DecisionPayload`.
- **Tools (as built):**
  - `OcuTalon.BridgeExample.ToolSet`/`.Tools`: `example_count_items` (safe, `readOnly` 1), `example_forward_item` (risky) and `example_archive_item` (unclassified).
  - Each tool declares `STEPLABEL<NAME>` and holds no classification or `RESOURCES` of its own. `RESOURCES` would need `Decide`'s `ServiceUser`, which a standalone namespace lacks.
  - A safe tool's result taints the turn unless `trustedOutput` is set. A later risky call is then denied as untrusted instead of held.
- **Classification and role are System Default Settings rows, not definition settings.** `ToolClassification` (JSON array of `{class, tool, classification[, readOnly][, trustedOutput]}`) and `ApprovalRole` (category Bridge, default `OcuTalonUser`) are read live via `Ext.Accessor.ValueFor`, so no restart is needed. A value in the production definition would hide the row. Gate order: code-declared classification, then this setting, then `ClassificationClass`.
- **Example role:** the approval role is `ExampleApprovers`; IRIS refuses a role and a user with the same name. User `ExampleApprover` holds it and `ExampleViewer` does not, and both are login-disabled. The guide takes role names from `release/standalone-bridge.sh`. `Answer` checks roles through `GetUserRecursedRoleSet`, which needs `%Admin_Secure:USE`, so call it from a privileged session. The example answers with channel `system`.
- **Proof script:** `release/standalone-bridge.sh` drives every case in a throwaway namespace `OCUBRIDGE`, polling with deadlines; audit read-backs poll up to 180 s. A full run takes about 6 min against job deadline 1200 s and `timeout-minutes` 25. 13.3 makes it run the guide's commands verbatim.
- **Mock:** scenarios go only under `ci/mock/scenarios/A/`, picked by a `[[mock:<name>]]` marker or `MOCKKEY`. An unmatched request gets a 500. New mock behaviour is Lane B's.
- **Audit and redaction:** only via `OcuTalon.Bridge.Audit.Record(type, data)` and `OcuTalon.Bridge.Redact`.

## Cross-Story Dependencies

- 13.3 documents what 13.1 and 13.2 built and needs Epic 11 merged (part 1 merged; the release checklist from Story 11.4 is done).
- Lane B's Story 31.3 adds the About dialog's bridge-guide link and the finish-state link "Use the same bridge in your own production ↗". 13.3 supplies the guide's stable path.
- Epic 14 (merged) owns `docs/security-overview.md`. 13.3 adds the U-229 sentence there and must leave its statements true.
- Later bridge extensions must keep the standalone job passing. The epic runs on a pool runner but stays in Lane A's files.
