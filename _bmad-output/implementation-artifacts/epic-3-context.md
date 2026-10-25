# Epic 3 Context: Nothing risky happens without a yes, and everything is audited

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 3 (Lane A) builds OcuTalon's governance core in the bridge and the installer. One fail-closed gate classifies every tool call as safe or risky by fixed rules that neither the model nor arriving content can change, and content that didn't come from the user can only look, notify and save. Each risky action becomes one IRIS Workflow approval request, fixed to exact targets, answered once (the first answer wins), expiring after 24 hours and surviving restarts. Every action and governance event goes to the IRIS audit log through one writer, and the roles and the service user decide who may do what. The epic also lands the online demo's public settings, password guard and $20 daily cap early, so the online-demo epics (Lane A's 29, Lane B's 16) can make November 1. The approved tool-call replay is not in this epic (it moved to Epic 30): here a risky tool call is held and runs nothing.

## Stories

- Story 3.1: Roles and the service user grant only what the architecture lists (done)
- Story 3.2: One gate decides every tool call (done)
- Story 3.3: Content that didn't come from the user can only look, notify and save (done)
- Story 3.4: Each risky action becomes one approval request held in IRIS Workflow (done)
- Story 3.5: The first answer wins, and unanswered requests expire (done)
- Story 3.6: A risky tool call waits for approval and runs nothing (done)
- Story 3.7: Every action and governance event is in the IRIS audit log (done)
- Story 3.8: The online demo's settings, password guard and spending cap are ready

## Requirements & Constraints

- **No risky action runs without an approved request**, in every configuration.
  - Safe: read-only checks and tools, reminders, saving for the digest, messages to the user, a background check the user asked for.
  - Risky: any change to a production, its items, settings or messages; anything sent to someone other than the user; any unclassified tool.
  - Untrusted content leads only to read-only checks, a notice and a digest save; an offer never becomes an approval request.
- **Approval requests:** targets and change fixed when raised; the first answer wins and the loser learns which channel won and when; expiry 24 hours after raising; pending requests survive restarts and upgrades; a rejected or expired request runs nothing.
- **Audit:** every action and governance event is an IRIS audit entry carrying time, IRIS user, session and channel, never a key, token, password, Telegram chat id or display name. OcuTalon never changes instance-wide auditing; when it is off, the install says so plainly.
- **Privileges:** roles and the service user hold only what the architecture lists. The public accounts can change nothing, including their own passwords.
- **Online-demo start values (3.8):** read from fixed environment variables on every start; the public keys are written only through their accessor, readiness stays cleared until the start's last phase, and without `OCUTALON_ONLINE_DEMO` only the flag (off) and readiness are written.
- **Password guard (3.8):** with the flag set, each public account accepts only its published password, while the installer can still write that value; a local install has no guard.
- **Budget (3.8):** the online demo's daily cost cap defaults to $20 (0 = off), the gateway's spend counts toward today, and at the cap a decision falls back with `daily_cap` before any request is sent. On a local install the cap is a seed value of 0 and the gateway values aren't written.
- **3.8's proof on a test stack:** the public keys read back through the accessor, a password change for either public account is refused while the installer's write succeeds, and a decision at the cap falls back with `daily_cap` with no request sent.
- **Open items:** DW-160 (3.8, below). DW-10 and DW-201 are resolved by 3.7. Routed elsewhere: DW-194 (Story 30.3), and a hold whose start times out after `STARTSECONDS` can still create its task and timer after Raise deleted the row (deferred, medium, unverified).

## Technical Decisions

**Built in 3.1 to 3.6 (orientation only):**
- **The gate**, `OcuTalon.Bridge.Policy.Gate`, an AI Hub Authorization policy added by the runner adapter, runs for every tool call and fails closed (any error is a caught `ToolAccessDenied`).
  - Order: call checks (`FAILED`), classification by (source, name) from code, Decide's `ToolClassification` or `ClassificationClass`, never from arguments; the service user's `RESOURCES` permissions (`NOPRIVILEGE`); provenance and taint (`UNTRUSTED`); then `safe` runs and anything else is held (`HELD`) through `Approval.Raise`.
  - Callbacks never call AI Hub's native agent, session, tool-manager or provider methods.
- **Approvals**, `OcuTalon.Bridge.Approval`: the row is the truth.
  - `Raise` refuses at `$TLevel` > 0, saves the pending row and starts the `ApprovalHold` synchronously (Workflow task in `OcuTalonApprovals`, expiry timer); `Reconcile()` re-arms pending rows at every start.
  - The five state methods (`Answer`, `Expire`, `Cancel`, `StartExecution`, `FinishExecution`) change state under the row's lock and fire HostSink events after the unlock; `Answer` returns `not_found`, `not_allowed`, `expired`, `already_answered` (with `winner`) or `done`. The required role is Decide's `ApprovalRole` (default `OcuTalonUser`).
- **Roles and accounts (3.1):** `OcuTalonService` is login-disabled with exactly `OcuTalonServiceRole`. No role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun`, `%Ens_ProductionConfig`, `%Ens_WorkflowConfig` or the Workflow inbox. The Users step reads the flag and the published accounts only through `OcuTalon.Data.Public.Settings`; `Users.PinTrace(name)` pins a public account's Visual Trace page size to 100.

**Audit (3.7, built; AD-17 and the "Audit entries" convention):**
- `OcuTalon.Bridge.Audit.Record(type, data)` is product code's only writer (a CodeRules scan enforces it); `Write` stays the pinned raw writer under it. It writes through `$SYSTEM.Security.Audit`, source `OcuTalon`, types `Action`, `Approval`, `Pairing`, `Settings`, `MCP`, `Tool`.
- Every entry's data is `irisUser`, `sessionRef`, `channel` plus one fixed member set per type (`Shape(type)`); `Record` refuses a missing, extra or ill-typed member, an empty identity member, a channel outside `CHANNEL`, a malformed Ref or an out-of-range enumeration, naming the type and member, never the value.
  - The description is derived from the shape; every entry passes `Redact.Text`; a sensitive setting's `from` and `to` are blanked. When IRIS writes nothing (auditing off, event disabled or missing), `Write` returns an error.
- Each Approval state change writes one `Approval` entry after the unlock and before its event, naming the answerer (the approver for a run's start and end), else the job's user with channel `system`; a failed write is warned and the change stands.
  - `Answer` refuses a `sessionRef` that is neither empty nor a 22-character Ref; `Cancel(ref, sinkClass, channel, irisUser, sessionRef)` takes the person who cancels. Raise, the held call and refusals write no entry.
- `Install.Step.Audit` still fails on a missing or disabled event, reads `Bridge.Installer.InstanceAuditing(.enabled)` (read-only), records `on`, `off` or `unknown` in the `StatusMark` `instanceAuditing` only when it changes, warns when off (`WARN Audit`), returns OK, and never changes the setting.
- `OcuTalon.Test.Bridge.AuditLog` (`Now`, `Entries`, `Wait`, `EventState`, `SetEvent`) reads `%SYS.Audit` in `%SYS` by `UTCTimeStamp >= since` only: rows are written at once, but IRIS's indexes lag up to 60 s. Tests find entries by a fresh Ref marker. Run-time settings changes are audited by `SettingsOps` (Story 4.1) with the `Settings` shape.

**The `Public` step and the budget (3.8):**
- **Order (AD-23).** The registry runs `Bridge.Installer`, `Public`, `Roles`, `Users`, `Web`, `SSL`, `Tasks`, `Demo`, `Provider`, `Audit`, `Telegram`, `Production`, `Reconcile`, `PrivateData`, then `Ready` (`Public.Ready()`). The after-start script clears readiness first. Today `Public.Run()` writes only the flag and `Ready()` only calls `SetReady`. An IPM install runs the same steps, `Public` included, with demo mode off.
- **Public keys (AD-19)**, structural, rewritten every start: `OCUTALON_ONLINE_DEMO` (`1` = on); `OCUTALON_DEMO_USER`, `OCUTALON_DEMO_PASSWORD`, `OCUTALON_READONLY_USER`, `OCUTALON_READONLY_PASSWORD` (published on the splash, not secrets); `OCUTALON_RESET_INTERVAL_HOURS` (4); `OCUTALON_RESET_ANCHOR` and `OCUTALON_LAST_RESET` (UTC ISO 8601); `OCUTALON_LAST_RESET_KIND` (`scheduled` or `unscheduled`); `OCUTALON_PROXY_ADDRESS`; `OCUTALON_CONNECTION_CAP`, `OCUTALON_CONNECTION_RESERVE`, `OCUTALON_MESSAGE_ALLOWANCE` (8, 2, 50 an hour).
  - They live only in `^OcuTalonPublic` in `OCUTALON_PUBLIC`; `OcuTalon.Data.Public.Settings` (Lane B's: `Get`, `Set` for the fixed keys only, `ClearReady`, `SetReady`, `NextReset`) is their only reader and writer, and a CI check fails any other reference to the global. `SettingsOps` never writes them.
- **Budget settings (AD-19, AD-20, AD-8).** Online demo only, in `Run` (so before `Production` starts the items): `Decide`'s System Default Settings `DailyCostCapUSD` (from `OCUTALON_DAILY_COST_CAP_USD`, default 20), `GatewaySpendUSD` and `GatewaySpendDate` (instance-zone date), all structural.
  - On a local install `DailyCostCapUSD` is a seed (0, written only when absent; `SettingsOps` owns it from step 2).
  - The bridge never reads public settings. `Budget.State()` and `Decide`'s precheck (Epic 1) read the three through `Ext.Accessor.ValueFor`; `State` adds the gateway spend when its date is today.
  - `daily_cap` is a before-sending fallback (never sent, no tool, fix or approval), and the first one of the day marks the day capped once and fires `budget.capped`.
- **Last phase (DW-160, AD-23, AD-24).** On a fresh flag-on volume OCUORDERS doesn't exist when Users runs (the Demo step creates it later), so `Ready` calls `Users.PinTrace` for both public accounts (page size 100 in both namespaces), then `SetReady`.
- **Password guard (AD-13, AD-24).** With the flag set, the Users step installs a password-validation routine that allows each public account only its published password, the user name compared case-insensitively, without blocking the installer's own write; none on a local install. Why: IRIS accepts a password change through a sign-in request on any password application in almost any form; the proxy's field allow-list comes first, this routine is the tested fallback, and the probe's sign-in check (restoring the published passwords) is the backstop.
- **Accounts (AD-24).** The demo account holds `OcuTalonUser` and `OcuTalonTraceViewer`; the read-only account holds `OcuTalonTraceViewer` alone; public accounts are never Workflow users or role members.

**Conventions:**
- The bridge references no other OcuTalon package (CI-enforced) and reaches its host only through the extension classes and `Decide`'s settings. Storage is append-only with committed storage blocks.
- A step reports a non-fatal condition with `Install.Step.Warn(text)`; the registry prints `WARN <step> <text>`, and a warning never changes a step's result.
- Install-step tests live in `OcuTalon.Test.Install.<Subject>`; seams are compile-time class parameters defaulting to the real classes, with `Zz` fixture subclasses that never run as steps (3.1's `ZzUsersPins`, 3.7's `ZzAudit*`).
- The `lane-a` shard ran 46 classes in 398 s fresh after 3.7, against a 480 s line and a 10-minute job cap; keep tests lean. If a fresh `lane-a` passes 470 s, stop with a clarification and propose a third shard `lane-a2` holding the Install area rather than editing `ci/units.sh`.
- Role, user, security, password and setting changes and test runs happen only on throwaway stacks through `ci/iris.sh` and `ci/warm.sh` (warm reloads classes only; fresh `live install-start` and `live install-upgrade` prove start-time behaviour); the developer slot is load-and-compile only. Tests restore every security object, setting, public key, audit flag and mark they change. Lane A extends the CI model mock only under `ci/mock/scenarios/A/`.

## UX & Interaction Patterns

- **Denials are plain sentences the model relays** after AI Hub's "Tool access denied: " prefix: lower-case start, a period at the end, each a gate class parameter. A held call: "held for your approval; nothing was run.".
- **Answer statuses** (`Answer`'s results and `winner`) feed channel texts such as "Approved from Telegram at 14:15"; the bridge never renders user-facing text.
- **The online demo's surfaces are Lane B's:** the splash shows the published accounts and the message allowance, and `BridgeSink` shows the cap's banner and sends the once-a-day daily-cap message; 3.8 only supplies the values.

## Cross-Story Dependencies

- **Inside the epic:** 3.8 extends Epic 0's `Public` step and 3.1's Users step (the password guard; `PinTrace` from the last phase).
- **Builds on:** Epic 0's contracts (`Public.Settings`, the step registry, `ApprovalRequest`, `Ids`, `Time`, `Redact`, audit registration) and Epic 1's runner adapter, `Budget.State()` and `Decide`'s precheck.
- **Lane B's side:** the `Demo` step creates OCUORDERS after Users (DW-160); `StatusMark`; `AnswersIn` and the approval cards (Stories 6.2, 12.7: pass a 22-character `SessionRef` or "", map the five results and `winner`); `BridgeSink` events (2.6, 2.8); `Allowance.TryConsume` (2.4) uses the message allowance; `SessionOps.End` (16.4) and `McpOps` (22.4) call `Cancel` naming the person.
- **Audit consumers:** Stories 4.1 (`Settings`), 4.3 and 7.4 (`Action`, with `counts`), 10.3 and 12.5 (`Pairing`), 22.1 to 22.4 (`MCP`, `Tool`, `Action`), 30.3 (the replay's `Action`), 11.1 (reads by `UTCTimeStamp` range), 14.2 (lists `Shape()`, points to `instanceAuditing`), 15.2's install docs (the WARN line and the mark).
- **Downstream:** Epics 5 and 7 raise `fix` requests and Stories 7.3 to 7.5 call `StartExecution` and `FinishExecution`; Epic 13's example lacks the approval items, so its risky calls deny with `FAILED`; Story 30.3 replays approved tool calls (DW-194); Story 26.4 replaces the role check; Story 14.1 lists classifications and resources; Epics 16 and 29 need Story 3.8, and Story 29.3 must make November 1.
