# Epic 3 Context: Nothing risky happens without a yes, and everything is audited

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 3 (Lane A) builds OcuTalon's governance core in the bridge and the installer. One fail-closed gate classifies every tool call as safe or risky by fixed rules that neither the model nor arriving content can change, and content that didn't come from the user can only look, notify and save. Each risky action becomes one IRIS Workflow approval request, fixed to exact targets, answered once (the first answer wins), expiring after 24 hours and surviving restarts. Every action and governance event goes to the IRIS audit log through one writer, and the roles and the service user decide who may do what. The epic also lands the online demo's public settings, password guard and $20 daily cap early, so the online-demo epics can make November 1. The approved tool-call replay is not in this epic (it moved to Epic 30). Here a risky tool call is held and runs nothing.

## Stories

- Story 3.1: Roles and the service user grant only what the architecture lists
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
- **One test per risky built-in tool** shows it doesn't run without approval. The suite fails if such a test is missing.
- **Approval requests:**
  - Targets and the exact change are fixed when the request is raised, and carrying it out calls no model.
  - The first answer wins. The losing answer learns which channel won and when.
  - A request expires 24 hours after it is raised.
  - Pending requests survive restarts and in-place upgrades.
  - On a local install, the required role defaults to `OcuTalonUser`.
- **Audit entries** carry time, IRIS user and session for each of these: an action run (target and result), an approval answered (who, channel, outcome), a pairing, a settings change, an MCP server added or removed, and a tool classified.
  - No entry ever holds a key, token, password, or Telegram chat id or display name.
  - If instance-wide auditing is off, say so plainly with a log warning and a recorded status. Never change that setting.
- **Privileges:** roles and the service user hold only what the architecture lists. The public accounts can change nothing, including their own passwords.
- **Online-demo budget:** the daily cost cap defaults to $20, and the gateway's spend counts toward today. At the cap, a decision falls back with `daily_cap` before any request is sent.
- **Routed open items:**
  - DW-143 (3.2): the watch fixture's tools declare no classification, so they would be held as risky.
  - DW-136 and DW-139 (3.3): should set and cancel reminder output be trusted output? Can list output that carries model-written reminder text stay trusted?
  - DW-10 (3.7): the warning when instance-wide auditing is off.

## Technical Decisions

**The gate**, `OcuTalon.Bridge.Policy.Gate`, an AI Hub Authorization policy:
- The runner adapter adds the gate beside the step audit policy in `OnAfterAgentInit`. AI Hub chains policies, so every authorization policy must allow. The gate runs for every tool call, including tools that don't require authorization.
- **It fails closed.** A missing context, an exception or a lock timeout means deny. The gate catches every exception itself and returns a `ToolAccessDenied` status, because an escaping exception skips the audit policies and leaks a source line to the model.
- **Classification** is by (source, name):
  - A toolset tool's source is `metadata.origin_class`.
  - A built-in tool declares class parameters `CLASSIFICATION` (`safe` or `risky`), `READONLY` and `TRUSTEDOUTPUT`. A class holding several tools suffixes each with the tool's name in upper case. A tool whose class depends on its arguments uses a `Classify(arguments)` method instead.
  - A developer's own tools are classified by a bridge setting. Anything else goes through `ClassificationClass`, whose default does nothing.
  - A tool of the same name in another class never takes a built-in's classification.
- **Permissions:** the gate calls `$SYSTEM.Security.CheckUserPermission` with the service user and the tool's declared `RESOURCES`. If a privilege is missing, it denies with a plain sentence.
- **Taint:**
  - Every tool result taints the turn unless its tool is `TrustedOutput`, meaning code built the output from OcuTalon's own records.
  - In an untrusted or tainted turn, only read-only tools run.
  - `Reply.Tainted` is set, and the next turn runs with `SessionMode` `fresh` and a code-written `SeedText` recap.
  - A tainted turn is never saved to the linked AI session. An untrusted turn uses a throwaway session and never changes the user's conversation link.
- **An allowed call** reports `turn.step` through `HostSinkClass` with `{decisionRef, label}`, and the session as `ownerRef`.
- **A risky or unclassified call in a user's turn:**
  1. The gate calls `Approval.Raise` with kind `tool_call` and the exact call. It reaches `ApprovalStartIn` through a synchronous round trip from inside `%CanExecute`.
  2. Then it denies the call with "held for your approval; nothing was run". The sentence is written to read well after AI Hub's "Access denied: … Tool access denied:" prefix.
- **Callbacks** (the gate, tools, the renderer) never call AI Hub's native `%AI` agent, session, tool-manager or provider methods: doing so deadlocks the job.

**Approvals:** `OcuTalon.Bridge.Approval`, where the row is the truth.
- **Raise** creates the `ApprovalRequest` row. The row holds:
  - the kind (`fix` or `tool_call`) and `IncidentRef`;
  - the fixed targets, the exact change, and `DryRun` or the exact call;
  - `OwnerRef`, and the required role from the approval-role setting;
  - the raised time, an expiry 24 hours later, and `ResultTarget`;
  - `Ref`, from `Ids.NewRef()`.
- **The hold:**
  1. Raise sends to `ApprovalStartIn` (adapterless, `OcuTalon.Bridge.Service.ApprovalStart`). That service starts `ApprovalHold` with the caller's trace session and `SuperSession`, which come from the context's `ThreadSessionId`.
  2. `ApprovalHold` sends an `EnsLib.Workflow.TaskRequest` (`%Actions="Approve,Reject"`) to the Workflow operation `OcuTalonApprovals`, and sets the expiry timer.
- **Workflow membership:** the Workflow role `OcuTalonApprovals` has exactly one member, the login-disabled `OcuTalonWorkflow`. No person or public account is a Workflow user or role member.
- **State changes** happen only through `Answer`, `Expire`, `Cancel`, `StartExecution` and `FinishExecution`, each under `LOCK ^OcuTalon.Bridge.Approval(Ref)`.
  - The allowed paths: `pending` to `approved`, `rejected`, `expired` or `cancelled`; `approved` to `executing` to `done` or `failed`; and `approved` straight to `failed` when an approved run can't start.
  - `StartExecution` succeeds only on a row that is approved, unexpired and not already executing, checked and set atomically.
- **`Answer(Ref, Action, Channel, IrisUser, SessionRef)`**:
  - It refuses an answer past the expiry even before the timer fires.
  - It records the action, channel, user and time, then completes the task as `OcuTalonWorkflow`.
  - It returns `done`, `already_answered` (with the winning channel and time), `expired`, `not_found` or `not_allowed`.
  - Lane B's `AnswersIn` checks visibility and ownership before it calls `Answer`.
- **Outcomes:**
  - `ApprovalHold` acts on a `TaskResponse` only if the row already shows that answer.
  - On approval, rejection or expiry it sends `ApprovalOutcome` to `ResultTarget`. Until Story 30.3 merges, an approved `tool_call` gets neither and runs nothing.
  - The HostSink gets `approval.raised`, `approval.answered`, `approval.expired` and `approval.cancelled`, each carrying the `Ref`.
- **Restarts:** `ApprovalHold`'s persistent properties are frozen: append-only, with its logic in other classes. Lane A's `Reconcile()` declaration does two things. For each pending row whose process is gone, it starts a new hold through `ApprovalStartIn` and re-arms the timer from the row's times. It also cancels orphaned Workflow tasks.

**Audit:** `OcuTalon.Bridge.Audit` is the only writer.
- Entries use source `OcuTalon` and types `Action`, `Approval`, `Pairing`, `Settings`, `MCP` or `Tool`, with one fixed data shape per type, written through `$SYSTEM.Security.Audit`.
- `Bridge.Installer` registers the events on every start.
- Production jobs run as the Interoperability system user, so each entry's event data names the acting IRIS user, the `SessionRef` and the channel.
- Every entry passes `OcuTalon.Bridge.Redact`, and every Approval API change is audited.
- OcuTalon keeps no audit table of its own. Tests read the IRIS audit log back, polling with a timeout, because rows can land minutes late.

**Roles and users:**
- **`OcuTalonService`** has login disabled, no services and a random password. The role step composes its grants from every area's `Grants()` entries (`{"role","resource","permission"}`), taken from each tool's and fix kind's `RESOURCES`. It is a privilege profile that the gate checks: IRIS does not enforce it on running code.
- **`OcuTalonTraceViewer`** holds only:
  - `%Ens_Portal`, `%Ens_MessageTrace`, `%Ens_MessageHeader` and `%Ens_MessageContent` (Use);
  - read access to the OCUTALON data and code databases, never the private ones;
  - SQL `SELECT` on `Ens.MessageHeader`.

  The role step rebuilds the role without OCUORDERS grants on every start. Lane B's `Demo` step adds them afterwards, only with demo mode on.
- **Forbidden:** no OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun`, `%Ens_ProductionConfig` or the Workflow inbox.
- **Accounts:**

  | Account | Roles |
  | --- | --- |
  | Local README account | `OcuTalonUser`, `OcuTalonAdmin`, `OcuTalonTraceViewer` |
  | Online-demo account | `OcuTalonUser`, `OcuTalonTraceViewer` (never admin) |
  | Read-only account | `OcuTalonTraceViewer` only |

  Both public accounts have their Visual Trace page size pinned to 100 in both namespaces.

**The `Public` step and the budget (Story 3.8):**
- **Step order:**
  1. `Bridge.Installer`
  2. `Public`
  3. roles and users
  4. web applications, SSL and tasks
  5. `Demo`
  6. Config Store entries
  7. audit events
  8. Telegram
  9. `Production`
  10. `Reconcile`
  11. `Public` sets readiness last, with `SetReady`
- **Public keys:** on every start, the `Public` step writes the fixed public keys from the online-demo environment variables. It writes only through `OcuTalon.Data.Public.Settings`, which Lane B owns; a CI check fails any other reference to its global. Without `OCUTALON_ONLINE_DEMO`, it writes only the flag (off) and readiness. Every later step, the user step included, reads the flag and the accounts through that accessor, never from the environment.
- **On the online demo,** before `Production` starts, the step writes `Decide`'s System Default Settings:
  - `DailyCostCapUSD`: default 20; 0 means off;
  - `GatewaySpendUSD`;
  - `GatewaySpendDate`: a date in the instance zone.
- **On a local install,** `DailyCostCapUSD` is a seed value of 0, and the gateway values are not written.
- **Readers:** the bridge never reads the public settings. `Budget.State()` and `Decide`'s precheck read the three values through the bridge's settings accessor.
- **Password guard:** on the online demo only, a password-validation routine allows each public account only its published password. It compares the user name case-insensitively and doesn't block the installer's own write.

**Conventions:**
- The bridge references no other OcuTalon package, and a CI check enforces this. It reaches its host only through the extension classes named on `Decide`. When an `OnEvent` call fails, the failure is logged and never fails the caller.
- Storage is append-only, with committed storage blocks.
- Tests are `%UnitTest` classes. Governance tests go in `OcuTalon.Test.Bridge` and run in the `lane-a` shard.
- Lane A extends the CI model mock only by adding files under `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- **Denials are plain sentences the model relays.** A held call: "held for your approval; nothing was run". An untrusted or tainted turn: the action is described as an offer the user can ask for in their own turn.
- **The suspicious-request sample email triggers nothing:** no resend, no setting change, no approval. Its decision reasons say an email can't approve requests or change a production. Triage's instructions treat item content as data.
- **Answer statuses:** `Answer`'s results feed the channels' statuses, such as "Approved from Telegram at 14:15" and "Already answered: …". The bridge never renders user-facing text.
- **The turn indicator** shows the tool's readable label from `turn.step`. A label never holds arguments or model text.

## Cross-Story Dependencies

- **Inside the epic:**
  - Story 3.1's service user and `Grants()` underpin Story 3.2's permission check.
  - Story 3.2's gate comes before Story 3.3 (taint) and Story 3.6 (the hold).
  - Story 3.4 (Raise, the hold, Workflow) comes before Stories 3.5 and 3.6.
  - Story 3.7 audits every Approval API change that Story 3.5 makes.
  - Story 3.1 sets the online-demo flag itself on its test stack, so it doesn't wait for Story 3.8.
- **What this epic builds on:**
  - Epic 0's contracts and stubs: the Approval signatures, `ApprovalStartIn`, `ApprovalRequest`, the extension bases, `Public.Settings`, `Ids`, `Redact` and audit registration.
  - Epic 1's runner adapter, step audit policy, `Context`, `Budget` and reminder tools.
- **Lane B's side:**
  - The OCUORDERS trace grants: until Story 4.1 merges, test them with fixture grants.
  - `AnswersIn` and the approval cards (Epic 6).
  - `BridgeSink`.
  - `SessionOps.End` calls `Approval.Cancel`.
- **Downstream:**
  - Epic 5 follows in lane order, and Epic 7 runs fix approvals on this epic's API.
  - Story 30.3 replays an approved tool call through `StartExecution`, `FinishExecution` and a live grant.
  - Epic 15 needs the installer core.
  - Epics 16 and 29 need Story 3.8.
