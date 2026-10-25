# Epic 3 Context: Nothing risky happens without a yes, and everything is audited

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 3 (Lane A) builds OcuTalon's governance core in the bridge and the installer. One fail-closed gate classifies every tool call as safe or risky by fixed rules that neither the model nor arriving content can change, and content that didn't come from the user can only look, notify and save. Each risky action becomes one IRIS Workflow approval request, fixed to exact targets, answered once (the first answer wins), expiring after 24 hours and surviving restarts. Every action and governance event goes to the IRIS audit log through one writer, and the roles and the service user decide who may do what. The epic also lands the online demo's public settings, password guard and $20 daily cap early, so the online-demo epics can make November 1. The approved tool-call replay is not in this epic (it moved to Epic 30): here a risky tool call is held and runs nothing.

## Stories

- Story 3.1: Roles and the service user grant only what the architecture lists (done)
- Story 3.2: One gate decides every tool call (done)
- Story 3.3: Content that didn't come from the user can only look, notify and save (done)
- Story 3.4: Each risky action becomes one approval request held in IRIS Workflow
- Story 3.5: The first answer wins, and unanswered requests expire
- Story 3.6: A risky tool call waits for approval and runs nothing
- Story 3.7: Every action and governance event is in the IRIS audit log
- Story 3.8: The online demo's settings, password guard and spending cap are ready

## Requirements & Constraints

- **No risky action runs without an approved request**, in every configuration.
  - Safe: read-only checks and tools; setting, listing or cancelling reminders; saving for the digest; messages to the user; starting or stopping a background check the user asked for.
  - Risky: any change to a production, its items, settings or messages; anything sent to someone other than the user; any risky or unclassified tool. Unclassified counts as risky.
- **Untrusted content** (emails, webhook payloads, failed-message bodies, tool results that aren't trusted output) leads only to read-only checks, notifying the user and saving for the digest. Anything else is offered to the user in plain words, and an offer never becomes an approval request. No built-in tool can answer an approval, classify a tool, change a setting, add an MCP server or pair a chat.
- **One test per risky built-in tool** shows it doesn't run when a user's turn calls it; the suite fails if one is missing. A rejected or expired request runs nothing.
- **Approval requests:** targets and the exact change are fixed when raised, and carrying one out calls no model. The first answer wins, and the loser learns which channel won and when. A request expires 24 hours after it is raised. Pending requests survive restarts and in-place upgrades. On a local install the required role defaults to `OcuTalonUser`.
- **Audit entries** carry time, IRIS user and session for: an action run (target, result), an approval answered (who, channel, outcome), a pairing, a settings change, an MCP server added or removed, a tool classified. No entry holds a key, token, password, or Telegram chat id or display name. If instance-wide auditing is off, say so plainly (log warning plus a recorded status); never change that setting.
- **Privileges:** roles and the service user hold only what the architecture lists. The public accounts can change nothing, including their own passwords.
- **Online-demo budget:** the daily cost cap defaults to $20, and the gateway's spend counts toward today. At the cap, a decision falls back with `daily_cap` before any request is sent.
- **Routed open items:** DW-10 (3.7), the warning when instance-wide auditing is off; DW-160 (3.8), see the `Public` step below.

## Technical Decisions

**The gate**, `OcuTalon.Bridge.Policy.Gate` (built in 3.2, extended in 3.3), an AI Hub Authorization policy:
- The runner adapter adds it beside the step audit policy in `OnAfterAgentInit`; it runs for every tool call, including tools that don't require authorization. It **fails closed**: a missing context, an exception or a lock timeout means deny, always as a caught `ToolAccessDenied` status (an escaping exception skips the audit policies and leaks a source line to the model).
- **`Decision`'s order:** call checks (`FAILED`), classification, permissions (`NOPRIVILEGE`), provenance and taint (`UNTRUSTED`), then the result: a `safe` call is allowed and every other call is denied with `NEEDSAPPROVAL`, a placeholder that 3.6 replaces with the hold. The rules apply to every request kind (`decide`, `diagnose`, `turn`, `tool`). The gate takes no lock yet; `Approval.Raise` is the first lock on its path, so 3.6 tests the lock timeout.
- **Classification by (source, name).** An `mcp:` toolref is recognised first; otherwise the source is `metadata.origin_class`.
  - A built-in tool declares class parameters `CLASSIFICATION` (`safe`/`risky`), `READONLY` and `TRUSTEDOUTPUT` (1/0), suffixed `<NAME>` (tool name in upper case) for one tool of a class that holds several. A class may instead classify in code with an `[ Internal ]` class method `Classify<NAME>(arguments)`, else `Classify(arguments)`; the flags stay parameters.
  - Only the exact values `safe` and `risky` classify, and a flag is 1 only when exactly 1. A bad value leaves the tool unclassified; an empty parameter declares nothing.
  - For a class source the order is code, then Decide's `ToolClassification` setting (a JSON array of `{class, tool, classification}`, each optionally with `readOnly` and `trustedOutput`, for a developer's own tools), then `ClassificationClass`. Neither can change what code gives, so a setting never downgrades a built-in tool. An `mcp:` source is classified by `ClassificationClass` alone.
  - A call's metadata, its arguments (except through a code `Classify`) and its context never classify it, and a same-named tool in another class never takes a built-in's classification.
- **Permissions (Tool resources convention):** a tool declares `RESOURCES` (or `RESOURCES<NAME>`) as `resource:permission[,…]`, permission from `R`, `W`, `U`; a defined parameter wins even when empty. The installer's `Tools` area composes them into `OcuTalonServiceRole`. The gate checks Decide's `ServiceUser` (default `OcuTalonService`) with `$SYSTEM.Security.CheckUserPermission`, one permission letter per call, before provenance and before any hold. Never declare a `%Service_` resource.
- **Provenance and taint (built in 3.3):** a turn is untrusted when the context's `Provenance` isn't exactly `user`, and tainted when `Tainted` isn't 0. There a call runs only when it is `safe` and read-only. Every other call is denied with `UNTRUSTED`, fires no `turn.step` and never reaches the result branch, so steered content can never raise an approval: a safe tool that changes something, a risky or unclassified tool (even one declaring read-only), any `mcp:` tool.
  - Right before allowing a call, after `turn.step`, the gate sets `Tainted` to 1 through `Context.Put` unless the tool's `trustedOutput` is 1. A denied call never taints.
  - AI Hub authorizes and runs one response's calls one at a time in listed order, and a denial doesn't stop the later calls (measured), so the next call in the same response sees the taint.
- **Trusted output** is built by code from OcuTalon's own records and holds no text from outside a user's untainted turn. `set_reminder` and `cancel_reminder` are safe, not read-only, trusted output; `list_reminders` is safe, read-only, trusted output (trusted only because setting a reminder never runs in an untrusted or tainted turn). The watch tools are read-only and never trusted. An extension's classification and every `mcp:` source carry neither flag. The `TRUSTEDTOOLS` and `READONLYTOOLS` lists in `Test.Bridge.Gate` fail the suite when a built-in tool declares either flag without being listed.
- **Quarantine (runner):** the context's taint reaches `Reply.Tainted`, and a tainted turn is never saved to the linked AI session. An untrusted turn uses a throwaway session and never changes the user's link. `Context.Begin` starts every turn untainted, untrusted ones included. Lane B's Conversation sends the next turn with `SessionMode` `fresh` and a code-written `SeedText` recap.
- **Tool code scan:** `Test.Bridge.CodeRules.ToolCodeClean` flags any tool reference to governance (the Approval API, its globals and hosts, `AnswersIn`, `EnsLib.Workflow`, the classification setting or extension, settings writers, production-changing `Ens.Director` methods, `Ens.Config` creation or deletion, MCP and pairing classes) and any command class outside `TOOLVERBS`; `Test.Agent.Runners` applies it to every live provider. Approval code stays in the bridge, never in a tool.
- **An allowed call** fires `turn.step` through `HostSinkClass` with `{decisionRef, label}` and the session as `ownerRef`.
- **The hold (3.6):** only in the result branch of a user's turn, a risky or unclassified call calls `Approval.Raise` (kind `tool_call`, the exact call), which reaches `ApprovalStartIn` by a synchronous round trip from inside `%CanExecute`, then denies with "held for your approval; nothing was run".
- **Callbacks** (gate, tools, renderer, the host sink) never call AI Hub's native `%AI` agent, session, tool-manager or provider methods: that deadlocks the job, and a CI check flags it.
- **Governance tests:** built-in tools go through a real `%AI.ToolMgr` with no model; developer test tools run end to end through a shadow runner of `ZzGateAgent` (toolsets `ZzGateTools` and `ZzGateInjection`) and the mock. The suite also fails if a built-in tool is marked as requiring authorization while classified safe or by its arguments. The approval-row counts in 3.3's untrusted-turn and suspicious-email tests can't fail until 3.6 raises approvals; 3.6 makes them live.

**Approvals:** `OcuTalon.Bridge.Approval`; the row is the truth.
- **Raise** creates the `ApprovalRequest` row: kind (`fix`/`tool_call`), `IncidentRef`, fixed targets, exact change, `DryRun` or the exact call, `OwnerRef`, the required role (approval-role setting), raised time, expiry +24 h, `ResultTarget`, and `Ref` from `Ids.NewRef()`.
- **The hold:** Raise sends to `ApprovalStartIn` (adapterless `OcuTalon.Bridge.Service.ApprovalStart`), which starts `ApprovalHold` with the caller's trace session and `SuperSession`. `ApprovalHold` sends an `EnsLib.Workflow.TaskRequest` (`%Actions="Approve,Reject"`) to the Workflow operation `OcuTalonApprovals` and sets the expiry timer.
- **Workflow membership:** the role `OcuTalonApprovals` has exactly one member, the login-disabled `OcuTalonWorkflow`. No person or public account is a Workflow user or role member (the inbox page has no resource check); 3.4 owns enforcing that exact membership.
- **State changes** only through `Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`, each under `LOCK ^OcuTalon.Bridge.Approval(Ref)`. Paths: `pending` → `approved`/`rejected`/`expired`/`cancelled`; `approved` → `executing` → `done`/`failed`; `approved` → `failed` when a run can't start. `StartExecution` succeeds only on an approved, unexpired, not-executing row, checked and set atomically.
- **`Answer(Ref, Action, Channel, IrisUser, SessionRef)`** refuses past the expiry even before the timer fires; records action, channel, user and time; completes the task as `OcuTalonWorkflow`; returns `done`, `already_answered` (winning channel and time), `expired`, `not_found` or `not_allowed`. Lane B's `AnswersIn` checks visibility and ownership first.
- **Outcomes:** `ApprovalHold` acts on a `TaskResponse` only if the row already shows that answer, then sends `ApprovalOutcome` to `ResultTarget`. Until Story 30.3 merges, an approved `tool_call` gets neither outcome nor replay and runs nothing. The HostSink gets `approval.raised`, `approval.answered`, `approval.expired`, `approval.cancelled`, each with the `Ref`.
- **Restarts:** `ApprovalHold`'s persistent properties are append-only, with its logic elsewhere. Lane A's `Reconcile()` declaration starts a new hold through `ApprovalStartIn` for each pending row whose process is gone, re-arming from the row's times, and cancels orphaned Workflow tasks.

**Audit (3.7):** `OcuTalon.Bridge.Audit` is the only writer, through `$SYSTEM.Security.Audit`, source `OcuTalon`, types `Action`, `Approval`, `Pairing`, `Settings`, `MCP`, `Tool`, one fixed data shape per type. `Bridge.Installer` registers the events on every start. Production jobs run as the Interoperability system user (the runner job is `_Ensemble`), so event data names the acting IRIS user, `SessionRef` and channel. Every entry passes `OcuTalon.Bridge.Redact`, and every Approval API change is audited. There is no OcuTalon audit table: tests read the IRIS audit log back, polling with a timeout (rows can land minutes late), through a reusable helper in `OcuTalon.Test.Bridge`.

**Roles and accounts (built in 3.1):** `OcuTalonService` is login-disabled, has no services, and holds exactly `OcuTalonServiceRole`; it is a privilege profile the gate checks, not something IRIS enforces on running code. The Roles step refuses forbidden resources (`%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun`, `%Ens_ProductionConfig`, `%Ens_WorkflowConfig`, the Workflow inbox). The Users step reads the online-demo flag and accounts only through `OcuTalon.Data.Public.Settings`, and `Users.PinTrace` pins a public account's Visual Trace page size to 100.

**The `Public` step and the budget (3.8):**
- Runs right after `Bridge.Installer`, before roles, users and web applications. On every start it writes the fixed public keys from the online-demo environment variables, only through `OcuTalon.Data.Public.Settings` (Lane B owns it; a CI check fails any other reference to its global), with readiness cleared. Without `OCUTALON_ONLINE_DEMO` it writes only the flag (off) and readiness.
- Online demo only, before `Production`: writes `Decide`'s System Default Settings `DailyCostCapUSD` (default 20; 0 = off), `GatewaySpendUSD` and `GatewaySpendDate` (instance-zone date). On a local install `DailyCostCapUSD` is a seed value 0 and the gateway values aren't written. The bridge never reads public settings; `Budget.State()` and `Decide`'s precheck read the three through the bridge's settings accessor.
- Its last phase, after `Production` and `Reconcile` and before `SetReady`, calls `Users.PinTrace` for both public accounts, because on a fresh flag-on volume OCUORDERS doesn't exist yet when Users runs (DW-160).
- **Password guard** (online demo only): a password-validation routine allows each public account only its published password, with the user name compared case-insensitively, without blocking the installer's own write.

**Conventions:**
- The bridge references no other OcuTalon package (CI-enforced); it reaches its host only through the extension classes and settings on `Decide`. A failed `OnEvent` is logged and never fails the caller.
- Storage is append-only, with committed storage blocks.
- Governance tests are `%UnitTest` classes in `OcuTalon.Test.Bridge`, run in the `lane-a` shard, which takes about 375 to 400 s fresh after 3.3 against a 10-minute job cap; keep tests lean.
- Role, user and security changes and test runs happen only on throwaway stacks through `ci/iris.sh`; the developer slot is load-and-compile only. Tests restore every security object, setting and public key they change.
- Lane A extends the CI model mock only by adding files under `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- **Denials are plain sentences the model relays.** The model sees AI Hub's prefix ending "Tool access denied: " before each sentence, so sentences start in lower case and read well after it; each is a gate class parameter, and the sentences stay distinct. A held call: "held for your approval; nothing was run". An untrusted or tainted turn (`UNTRUSTED`): only read-only tools can run, and the model describes the action to the user as an offer they can ask for in their own turn.
- **The suspicious-request sample email triggers nothing:** no resend, no setting change, no approval. Triage's instructions treat item content as data and ask for the reason that an email can't approve requests or change a production.
- **Answer statuses:** `Answer`'s results feed channel statuses such as "Approved from Telegram at 14:15" and "Already answered: …". The bridge never renders user-facing text.
- **The turn indicator** shows the tool's readable label from `turn.step`; a label never holds arguments or model text.

## Cross-Story Dependencies

- **Inside the epic:** 3.6 (the hold) replaces `NEEDSAPPROVAL` in the gate's result branch, which 3.3's provenance step keeps untrusted and tainted turns from reaching. 3.4 (Raise, hold, Workflow) comes before 3.5 and 3.6. 3.7 audits every Approval API change that 3.5 makes. 3.8 owns the `Public` step, including the last phase that pins the public accounts' trace page size.
- **Builds on:** Epic 0's contracts and stubs (Approval signatures, `ApprovalStartIn`, `ApprovalRequest`, extension bases, `Public.Settings`, `Ids`, `Redact`, audit registration) and Epic 1's runner adapter, step audit policy, `Context`, `Budget` and reminder tools.
- **Lane B's side:** OCUORDERS trace grants (fixture grants until Story 4.1 merges), `AnswersIn` and the approval cards (Epic 6), `BridgeSink` publishing `turn.step` (Story 2.6), Conversation's fresh turn after a `Tainted` reply (Story 2.4), Intake's untrusted `act` turn (Story 2.7), and `SessionOps.End` calling `Approval.Cancel`.
- **Downstream:** Epic 5 follows in lane order; Story 5.7's `check_status` declares trusted output and joins both flag lists. Epic 7 runs fix approvals on this API. Epic 13's example production builds its agent through the same adapter, so its own tools are held unless classified (by code, its `ToolClassification` setting or `ClassificationClass`). Stories 19.3, 19.4 and 22.3 keep memory, document and MCP results untrusted. Story 30.3 replays approved tool calls through `StartExecution`, `FinishExecution` and a live grant. Story 14.1 lists the classifications and resources. Epic 15 needs the installer core, and Epics 16 and 29 need Story 3.8.
