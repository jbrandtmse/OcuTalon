# Epic 3 Context: Nothing risky happens without a yes, and everything is audited

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 3 (Lane A) builds OcuTalon's governance core in the bridge and the installer. One fail-closed gate classifies every tool call as safe or risky by fixed rules that neither the model nor arriving content can change, and content that didn't come from the user can only look, notify and save. Each risky action becomes one IRIS Workflow approval request, fixed to exact targets, answered once (the first answer wins), expiring after 24 hours and surviving restarts. Every action and governance event goes to the IRIS audit log through one writer, and the roles and the service user decide who may do what. The epic also lands the online demo's public settings, password guard and $20 daily cap early, so the online-demo epics can make November 1. The approved tool-call replay is not in this epic (it moved to Epic 30): here a risky tool call is held and runs nothing.

## Stories

- Story 3.1: Roles and the service user grant only what the architecture lists (done)
- Story 3.2: One gate decides every tool call
- Story 3.3: Content that didn't come from the user can only look, notify and save
- Story 3.4: Each risky action becomes one approval request held in IRIS Workflow
- Story 3.5: The first answer wins, and unanswered requests expire
- Story 3.6: A risky tool call waits for approval and runs nothing
- Story 3.7: Every action and governance event is in the IRIS audit log
- Story 3.8: The online demo's settings, password guard and spending cap are ready

## Requirements & Constraints

- **No risky action runs without an approved request**, in every configuration.
  - Safe: read-only checks and tools; setting, listing or cancelling reminders; saving for the digest; messages to the user; starting or stopping a background check the user asked for.
  - Risky: any change to a production, its items, settings or messages; anything sent to someone other than the user; any risky or unclassified tool. Unclassified counts as risky.
- **Untrusted content** (emails, webhook payloads, failed-message bodies, tool results) can lead only to read-only checks, notifying the user and saving for the digest. Anything else is offered to the user in plain words, and an offer never becomes an approval request by itself. No built-in tool can answer an approval, classify a tool, change a setting, add an MCP server or pair a chat.
- **One test per risky built-in tool** shows it doesn't run without approval; the suite fails if one is missing.
- **Approval requests:** targets and the exact change are fixed when raised, and carrying one out calls no model. The first answer wins, and the loser learns which channel won and when. A request expires 24 hours after it is raised. Pending requests survive restarts and in-place upgrades. On a local install the required role defaults to `OcuTalonUser`.
- **Audit entries** carry time, IRIS user and session for: an action run (target, result), an approval answered (who, channel, outcome), a pairing, a settings change, an MCP server added or removed, a tool classified. No entry holds a key, token, password, or Telegram chat id or display name. If instance-wide auditing is off, say so plainly (log warning plus a recorded status); never change that setting.
- **Privileges:** roles and the service user hold only what the architecture lists. The public accounts can change nothing, including their own passwords.
- **Online-demo budget:** the daily cost cap defaults to $20, and the gateway's spend counts toward today. At the cap, a decision falls back with `daily_cap` before any request is sent.
- **Routed open items:**
  - DW-143 (3.2): the watch fixture's tools declare no classification, so they would be held as risky.
  - DW-136 and DW-139 (3.3): should set and cancel reminder output be trusted output? Can list output that carries model-written reminder text stay trusted?
  - DW-10 (3.7): the warning when instance-wide auditing is off.
  - DW-160 (3.8): see the `Public` step below.

## Technical Decisions

**The gate**, `OcuTalon.Bridge.Policy.Gate`, an AI Hub Authorization policy:
- The runner adapter adds it beside the step audit policy in `OnAfterAgentInit`. AI Hub chains policies (all must allow), and the gate runs for every tool call, including tools that don't require authorization.
- **Fails closed:** a missing context, an exception or a lock timeout means deny. It catches every exception itself and returns a `ToolAccessDenied` status; an escaping exception skips the audit policies and leaks a source line to the model.
- **Classification by (source, name).** A toolset tool's source is `metadata.origin_class`. A built-in tool declares class parameters `CLASSIFICATION` (`safe`/`risky`), `READONLY` and `TRUSTEDOUTPUT` (1/0), suffixed `<NAME>` (tool name in upper case) when one class holds several tools; an undeclared tool is unclassified. Argument-dependent classes use a `Classify(arguments)` method. A developer's own tools come from a bridge setting; other lookups go through `ClassificationClass` (default does nothing). A same-named tool in another class never takes a built-in's classification.
- **Permissions (Tool resources convention):** a tool declares `RESOURCES` (or `RESOURCES<NAME>`) as `resource:permission[,resource:permission...]`, permission from `R`, `W`, `U`; a defined parameter wins even when empty, an undeclared one declares nothing. The installer's `Tools` area composes them into the role `OcuTalonServiceRole` (IRIS refuses a role and user with the same name). The gate checks the user `OcuTalonService` with `$SYSTEM.Security.CheckUserPermission`, **one permission letter per call** (multi-letter is unreliable on build 154), and denies a missing privilege with a plain sentence. Never declare a `%Service_` resource: the service user has no services. No tool declares `RESOURCES` yet, so the role is empty today.
- **Taint:** every tool result taints the turn unless its tool is `TrustedOutput` (code built the output from OcuTalon's own records). In an untrusted or tainted turn only read-only tools run. `Reply.Tainted` is set; the next turn runs with `SessionMode` `fresh` and a code-written `SeedText` recap. A tainted turn is never saved to the linked AI session; an untrusted turn uses a throwaway session and never changes the user's conversation link.
- **An allowed call** reports `turn.step` through `HostSinkClass` with `{decisionRef, label}` and the session as `ownerRef`.
- **A risky or unclassified call in a user's turn:** the gate calls `Approval.Raise` (kind `tool_call`, the exact call), reaching `ApprovalStartIn` by a synchronous round trip from inside `%CanExecute`, then denies with "held for your approval; nothing was run", written to read well after AI Hub's "Access denied: … Tool access denied:" prefix.
- **Callbacks** (gate, tools, renderer) never call AI Hub's native `%AI` agent, session, tool-manager or provider methods: that deadlocks the job, and a CI check flags it.

**Approvals:** `OcuTalon.Bridge.Approval`; the row is the truth.
- **Raise** creates the `ApprovalRequest` row: kind (`fix`/`tool_call`), `IncidentRef`, fixed targets, exact change, `DryRun` or the exact call, `OwnerRef`, the required role (approval-role setting), raised time, expiry +24 h, `ResultTarget`, and `Ref` from `Ids.NewRef()`.
- **The hold:** Raise sends to `ApprovalStartIn` (adapterless `OcuTalon.Bridge.Service.ApprovalStart`), which starts `ApprovalHold` with the caller's trace session and `SuperSession`. `ApprovalHold` sends an `EnsLib.Workflow.TaskRequest` (`%Actions="Approve,Reject"`) to the Workflow operation `OcuTalonApprovals` and sets the expiry timer.
- **Workflow membership:** the role `OcuTalonApprovals` has exactly one member, the login-disabled `OcuTalonWorkflow`. No person or public account is a Workflow user or role member (the inbox page has no resource check). Story 3.4 owns enforcing that exact membership.
- **State changes** only through `Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`, each under `LOCK ^OcuTalon.Bridge.Approval(Ref)`. Paths: `pending` → `approved`/`rejected`/`expired`/`cancelled`; `approved` → `executing` → `done`/`failed`; `approved` → `failed` when a run can't start. `StartExecution` succeeds only on an approved, unexpired, not-executing row, checked and set atomically.
- **`Answer(Ref, Action, Channel, IrisUser, SessionRef)`** refuses past the expiry even before the timer fires; records action, channel, user and time; completes the task as `OcuTalonWorkflow`; returns `done`, `already_answered` (winning channel and time), `expired`, `not_found` or `not_allowed`. Lane B's `AnswersIn` checks visibility and ownership first.
- **Outcomes:** `ApprovalHold` acts on a `TaskResponse` only if the row already shows that answer, then sends `ApprovalOutcome` to `ResultTarget`. Until Story 30.3 merges, an approved `tool_call` gets neither outcome nor replay and runs nothing. The HostSink gets `approval.raised`, `approval.answered`, `approval.expired`, `approval.cancelled`, each with the `Ref`.
- **Restarts:** `ApprovalHold`'s persistent properties are frozen (append-only, logic elsewhere). Lane A's `Reconcile()` declaration starts a new hold through `ApprovalStartIn` for each pending row whose process is gone, re-arming from the row's times, and cancels orphaned Workflow tasks.

**Audit:** `OcuTalon.Bridge.Audit` is the only writer, through `$SYSTEM.Security.Audit`, source `OcuTalon`, types `Action`, `Approval`, `Pairing`, `Settings`, `MCP`, `Tool`, one fixed data shape per type. `Bridge.Installer` registers the events on every start. Production jobs run as the Interoperability system user, so event data names the acting IRIS user, `SessionRef` and channel. Every entry passes `OcuTalon.Bridge.Redact`; every Approval API change is audited. No OcuTalon audit table: tests read the IRIS audit log back, polling with a timeout (rows can land minutes late), with a reusable helper in `OcuTalon.Test.Bridge`.

**Roles and accounts (as built in Story 3.1):**
- `OcuTalonService`: login disabled, no services, random password, holding exactly `OcuTalonServiceRole`. It is a privilege profile the gate checks; IRIS doesn't enforce it on running code.
- `OcuTalonTraceViewer`: `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader`, `%Ens_MessageContent` (Use), read on the OCUTALON data and code databases (never private), SQL `SELECT` on `Ens.MessageHeader`. The roles step rebuilds it without OCUORDERS grants each start; Lane B's `Demo` step adds them with demo mode on.
- The Roles step refuses forbidden resources (`%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun`, `%Ens_ProductionConfig`, `%Ens_WorkflowConfig`, the Workflow inbox) and clears granted roles.
- Local README account: `OcuTalonUser`, `OcuTalonAdmin`, `OcuTalonTraceViewer`; with the online-demo flag on it is never created and an existing one is disabled. Online-demo account: `OcuTalonUser`, `OcuTalonTraceViewer` (never admin). Read-only account: `OcuTalonTraceViewer` only. With the flag off, accounts carrying the online-demo marker are disabled, never deleted. Public accounts' Visual Trace page size is pinned to 100 in both namespaces.

**The `Public` step and the budget (Story 3.8):**
- Runs right after `Bridge.Installer`, before roles, users and web applications. On every start it writes the fixed public keys from the online-demo environment variables, only through `OcuTalon.Data.Public.Settings` (Lane B owns it; a CI check fails any other reference to its global), with readiness cleared. Without `OCUTALON_ONLINE_DEMO` it writes only the flag (off) and readiness. Every later step reads the flag and accounts through that accessor, never from the environment.
- Online demo only, before `Production`: writes `Decide`'s System Default Settings `DailyCostCapUSD` (default 20; 0 = off), `GatewaySpendUSD`, `GatewaySpendDate` (instance-zone date). Local install: `DailyCostCapUSD` is a seed value 0 and the gateway values aren't written. The bridge never reads public settings; `Budget.State()` and `Decide`'s precheck read the three via the bridge's settings accessor.
- Its last phase, after `Production` and `Reconcile` and before `SetReady`, calls `Users.PinTrace` for both public accounts, because on a fresh flag-on volume OCUORDERS doesn't exist yet when Users runs (DW-160).
- **Password guard** (online demo only): a password-validation routine allows each public account only its published password, user name compared case-insensitively, without blocking the installer's own write.

**Conventions:**
- The bridge references no other OcuTalon package (CI-enforced); it reaches its host only through the extension classes named on `Decide`. A failed `OnEvent` is logged and never fails the caller.
- Storage is append-only, with committed storage blocks.
- Governance tests are `%UnitTest` classes in `OcuTalon.Test.Bridge`, run in the `lane-a` shard, which already takes about 400 s against a 10-minute job cap; keep tests lean.
- Role, user and security changes and test runs happen only on throwaway stacks through `ci/iris.sh`; the developer slot is load-and-compile only. Tests restore every security object and public key they change.
- Lane A extends the CI model mock only by adding files under `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- **Denials are plain sentences the model relays.** A held call: "held for your approval; nothing was run". An untrusted or tainted turn: the action is described as an offer the user can ask for in their own turn.
- **The suspicious-request sample email triggers nothing:** no resend, no setting change, no approval. Its decision reasons say an email can't approve requests or change a production; Triage's instructions treat item content as data.
- **Answer statuses:** `Answer`'s results feed channel statuses such as "Approved from Telegram at 14:15" and "Already answered: …". The bridge never renders user-facing text.
- **The turn indicator** shows the tool's readable label from `turn.step`; a label never holds arguments or model text.

## Cross-Story Dependencies

- **Inside the epic:** Story 3.1's service user and composed role underpin 3.2's permission check (3.2 is its first code consumer). 3.2's gate precedes 3.3 (taint) and 3.6 (the hold). 3.4 (Raise, hold, Workflow) precedes 3.5 and 3.6. 3.7 audits every Approval API change 3.5 makes. 3.8 owns the `Public` step's last phase that pins the public accounts' trace page size.
- **Builds on:** Epic 0's contracts and stubs (Approval signatures, `ApprovalStartIn`, `ApprovalRequest`, extension bases, `Public.Settings`, `Ids`, `Redact`, audit registration) and Epic 1's runner adapter, step audit policy, `Context`, `Budget` and reminder tools.
- **Lane B's side:** OCUORDERS trace grants (fixture grants until Story 4.1 merges), `AnswersIn` and the approval cards (Epic 6), `BridgeSink`, and `SessionOps.End` calling `Approval.Cancel`.
- **Downstream:** Epic 5 follows in lane order; Epic 7 runs fix approvals on this API; Story 30.3 replays approved tool calls through `StartExecution`, `FinishExecution` and a live grant; Epic 15 needs the installer core; Epics 16 and 29 need Story 3.8.
