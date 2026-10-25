---
title: 'Story 3.4: Each risky action becomes one approval request held in IRIS Workflow'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: '1eac10ddb527aae84c45a2be81fb0d4d5c19b09d'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-11, AD-5, the after-start and "Who owns the steps" bullets of AD-23, the Workflow and public-account lines of AD-24, the first and "Commands and notices" bullets of AD-26, the HostSink contract of AD-31, and the namespace-switch line of AD-3)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The approval API is still Epic 0's stub: `Approval.Raise` answers "not implemented", `ApprovalStartIn` and `ApprovalHold` are stubs, and the bridge installer sets up no Workflow role or user. So nothing can hold a risky action for a yes, and Story 3.5 (answers, expiry) and Story 3.6 (the gate's hold) have nothing to build on.

**Approach:**
- `Bridge.Installer` sets up the Workflow role `OcuTalonApprovals` with exactly one member, the technical, login-disabled user `OcuTalonWorkflow`.
- `Raise` validates the unsaved row, fixes its role, times and `Ref`, and starts the hold synchronously through `ApprovalStartIn` in the caller's trace session.
- `ApprovalHold` sends the Workflow task and sets the 24-hour timer. It keeps one stored property, `Ref`, and its logic lives in `Approval`.
- A Lane A `Reconcile()` declaration re-arms holds whose process is gone and cancels orphaned tasks.
- Answering, expiring and cancelling stay Story 3.5's.

## Boundaries & Constraints

**Always:**
- **The Workflow setup** (`Bridge.Installer.Run()`, at every start and on its own, AD-2):
  - the Workflow role `OcuTalonApprovals` exists;
  - the Workflow user `OcuTalonWorkflow` exists and is active (only active members get tasks: `irislib/EnsLib/Workflow/RoleDefinition.cls` `ActiveUsersForRole`);
  - it is a member of the role, and every other member is removed from it;
  - the IRIS user `OcuTalonWorkflow` exists with login disabled, no roles, no escalation roles and a random password nobody reads. An existing one gets Enabled 0, no roles and no escalation roles, and keeps its password.
  - The installer creates no other Workflow user and deletes none that it did not make.
  - The `%SYS` part stays in the class's one `%SYS` method (AD-3, AD-17), which the audit events already use.
- **Approval constants** are parameters of `OcuTalon.Bridge.Approval`:
  - `WORKFLOWROLE = "OcuTalonApprovals"`, `WORKFLOWUSER = "OcuTalonWorkflow"`;
  - `STARTITEM = "ApprovalStartIn"`, `HOLDITEM = "ApprovalHold"`;
  - `ACTIONS = "Approve,Reject"`, `TASKSUBJECT = "OcuTalon approval request "`;
  - `EXPIRYSECONDS = 86400`, `LOCKSECONDS = 2`, `STARTSECONDS = 10`.
- **The approval-role setting** is `Decide`'s host setting `ApprovalRole` (category `Bridge`, `InitialExpression = "OcuTalonUser"`), read through `Ext.Accessor.ValueFor`. It mirrors `ServiceUser`.
- **`Raise(request, Output ref, sinkClass = "", sessionId = "", superSession = "")`.** The Epic 0 parameters keep their names and order; the three new ones are optional and come after them.
  1. **Validate** before anything is written. Each refusal is an error status that names the field.
     - `request` is an unsaved `ApprovalRequest`.
     - `Kind` is one of `Msg.Enum` `APPROVALKIND`.
     - `OwnerRef` is a 22-character reference, `instance` or `eval` (AD-2).
     - `tool_call`: `ToolName` is set, `ToolArguments` parses as a JSON object, and `DryRun` is empty.
     - `fix`: `DryRun` parses as a JSON object, `ResultTarget` is set, and `ToolName` and `ToolArguments` are empty.
     - `IncidentRef` and `TraceRef` are empty or 22-character references.
     - `Ref`, `State`, `RequiredRole`, `RaisedAt`, `ExpiresAt`, the four `Answered*` fields, `Result` and `FinishedAt` are empty, because Raise and the later state methods own them.
     - The `ApprovalRole` setting reads without error and is not empty.
  2. **Under `LOCK +^OcuTalon.Bridge.Approval(<new ref>):LOCKSECONDS`**:
     - set `Ref` from `Ids.NewRef()`, `State` `pending`, `RequiredRole` from the setting, `RaisedAt` from `Time.NowUtc()`, and `ExpiresAt` exactly `EXPIRYSECONDS` later;
     - save the row;
     - start the hold.
     - A lock timeout is an error that names the lock.
  3. **The start:** `Ens.Director.CreateBusinessService(STARTITEM)` and `ProcessInput` of an `OcuTalon.Bridge.Msg.ApprovalStart` (`Ref`, `SessionId`, `SuperSession`).
     - The session comes from the arguments, else from an active bridge context (`ThreadSessionId`, `SuperSession`), else it is new.
     - `SuperSession` falls back to the row's `TraceRef`.
  4. **A failure after the save** (start error, timeout or refusal): Raise deletes the row it saved and returns the error. A failed Raise leaves no row, no hold and no event.
  5. **After the unlock**, Raise fires `approval.raised` once through `Decide.FireEvent`, with the row's `OwnerRef` and `HostSink.RefPayload(ref)`. The sink is `sinkClass`, else `Accessor.ValueFor("HostSinkClass")`.
- **`ApprovalStartIn`** (`Service.ApprovalStart`, adapterless):
  - It refuses an input that is not an `ApprovalStart` with a `Ref`.
  - After the service base has cleared them (AD-26, S6), it sets `..%SessionId` (only when the message carries one above 0) and `..%SuperSession`.
  - It sends the message with `SendRequestSync(HOLDITEM, ..., STARTSECONDS)` and returns the hold's answer or error.
- **`ApprovalHold`** has exactly one stored property of its own, `Ref`. `OnRequest` stores `Ref` and calls `Approval.Hold($this, request)`. `OnResponse` calls `Approval.HoldResponse(...)`. Each is one line (AD-5).
- **`Approval.Hold`** ([ Internal ]):
  1. Open the row by `Ref`. A missing or non-pending row is an error that names the Ref and the state.
  2. Send an `EnsLib.Workflow.TaskRequest` asynchronously to `WORKFLOWROLE` with completion key `task`. It has `%Actions` = `ACTIONS` and `%Subject` = `TASKSUBJECT` plus the Ref. `%Message`, `%UserName`, `%Title` and `%Command` stay empty. A `%UserName` would assign the task to that Workflow user, member or not (`Engine.AssignTask`).
  3. `SetTimer` the whole seconds until the row's `ExpiresAt`, at least 1, with key `expiry` and the default controlled keys. Pass seconds, never a timestamp: `Ens.Util.Time.SecondsUntil` reads a `Z` time as local.
  4. `Reply` an `Ens.Response`, so ApprovalStartIn's call returns while the hold keeps waiting.
- **`Approval.HoldResponse`** changes no row in this story. Story 3.5 acts on the answer and the timer.
- **A live hold** is an `ApprovalHold` instance with the row's `Ref` that is not completed, not terminated, and still waits for at least one response.
- **`Approval.Reconcile()`** returns one status that combines the failures, each naming its Ref. Every row is tried, and it is idempotent.
  1. It first cancels, with `EnsLib.Workflow.Engine.%CancelRequest`, every incomplete task of role `WORKFLOWROLE` that is not the task of a live hold of a pending row. The sending hold is the `BusinessProcessId` of the TaskRequest's header.
  2. It then starts, through ApprovalStartIn, a new hold for every pending row that has no live hold: in a new session, `SuperSession` the row's `TraceRef`, its timer from the row's `ExpiresAt`.
  3. It fires no event.
- **The Lane A declaration** `OcuTalon.Install.Step.Approvals.Reconcile()` calls `Approval.Reconcile()`. The Reconcile step calls it after `Production` at every start (AD-23).
- Approval, ApprovalStart and ApprovalHold make no `%AI` call and run no Python (AD-6), because Story 3.6 calls `Raise` from the gate's callback.
- **Tests run on throwaway stacks only, through `ci/iris.sh`.**
  - Each test removes the rows, holds and open Workflow tasks that it created, also those a failed earlier run left. It ends a hold by completing its task, and waits for a hold to end before removing it, so that no late response reaches a removed hold.
  - It restores every setting, item state and Workflow object that it changed.
  - It creates no IRIS user or role.

**Never:**
- No `Answer`, `Expire`, `Cancel`, `StartExecution` or `FinishExecution` body: they stay Epic 0's stubs. Raise is not audited (Story 3.7 lists the state changes).
- No call of `Raise` from the gate (Story 3.6), `IncidentManager` (Epic 5) or anything else outside the tests.
- No new `ApprovalRequest` column, and no edit to `Test/Data/**` (a contended path that pins the row's contract).
- No edit to `Production.cls`: the three items already exist.
- No edit to a contended path: `Core/**`, `Channel/**`, `Data/{Delivery,Session}.cls`, `Web/**`, `Live/**`, `Schedule/**`, `Test/{Core,Web,Data,Live,Schedule}/**`, `docker/**`, `docs/**`, `web/**`, `.github/**`, `src/bridge/cls/OcuTalon/BridgeExample/**`.
- No setting of `%UserName` on the TaskRequest. No `AutoCreateRole`. No reference from the bridge to another OcuTalon package (AD-2).
- No test run, security change or Workflow change on `ocutalon-slot-a`. No absolute local path in a tracked file.

## I/O & Edge-Case Matrix

Terms used in the table:
- **A tool_call row:** an `ApprovalRequest` with `Kind` `tool_call`, `OwnerRef` a new Ref, `ToolName` `zz_gate_held`, `ToolArguments` `{"value":1}` and `TraceRef` a new Ref.
- **A fix row:** `Kind` `fix`, `OwnerRef`, `IncidentRef` and `TraceRef` new Refs, `ResultTarget` `IncidentManager`, and `DryRun` `{"affected":3,"resend":3,"leftOut":0,"field":"OrderDate","before":"10/24/2026","after":"2026-10-24","itemNoun":"orders"}`.
- **The sink:** `OcuTalon.Test.Bridge.ProbeSink`, passed as Raise's `sinkClass`.
- **The hold's messages:** the headers of `ApprovalStart` (ApprovalStartIn to ApprovalHold), the `TaskRequest` (to OcuTalonApprovals) and the `AlarmRequest` (to Ens.Alarm).
- **Completing a task:** `AssignTask("OcuTalonWorkflow")`, then `CompleteTask("Approve")`, on its `TaskResponse`.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Installed Workflow | After the start, then `Bridge.Installer.Run()` twice | The role `OcuTalonApprovals` has exactly one member, the active Workflow user `OcuTalonWorkflow`. The IRIS user `OcuTalonWorkflow` has Enabled 0, no roles and no escalation roles. The only Workflow user in OCUTALON is `OcuTalonWorkflow`, and the README account has `WorkflowRows` 0. The production's item named `WORKFLOWROLE` is an `EnsLib.Workflow.Operation`. Both runs return OK and leave this state. | -- |
| 2 | Workflow repaired | (a) The role and the Workflow user deleted. (b) Fixture Workflow users `ZzRegistry<n>Person` and `ZzRegistry<n>Demo` added as members, `OcuTalonWorkflow` removed from the role and set inactive, and the IRIS user enabled with role `OcuTalonUser`. Each is followed by `Bridge.Installer.Run()`. | After each run, row 1's state holds again. The fixture Workflow users still exist and are no members. | The installer deletes no Workflow user that it did not make. |
| 3 | Raise a tool_call row | No bridge context | OK, and `ref` is 22 base64url characters and the row's `Ref`. The one row: <br>- the given fields are unchanged; <br>- `State` is `pending` and `RequiredRole` is `OcuTalonUser`; <br>- `RaisedAt` is within 5 s of now (`YYYY-MM-DDThh:mm:ssZ`), and `ExpiresAt` is exactly 24 h later; <br>- `DryRun`, `IncidentRef`, `ResultTarget`, the answer fields and the result fields are empty. <br>The hold's messages share one new session whose SuperSession is the `TraceRef`. The sink got exactly one call: `approval.raised`, with the `OwnerRef`, `{"ref":<ref>}`, `$TLevel` 0 and the row existing. | -- |
| 4 | Raise a fix row | No context | As row 3, with `DryRun`, `IncidentRef` and `ResultTarget` kept and `ToolName` and `ToolArguments` empty. Rows 3 and 4 have different Refs. | -- |
| 5 | The hold | After row 3's Raise returns | The TaskRequest has `%Actions` `Approve,Reject`, `%Subject` `TASKSUBJECT` plus the Ref, and an empty `%UserName` and `%Title`. Within 10 s its task is in role `OcuTalonApprovals`, unassigned, with exactly one worklist item, for `OcuTalonWorkflow`. The AlarmRequest asks 86,395 to 86,400 s, and `^Ens.Alarm` holds its entry. One ApprovalHold instance has the Ref and waits for the keys `task` and `expiry`. | -- |
| 6 | Caller's session | (a) A bridge context with `ThreadSessionId` S (row 3's session) and `SuperSession` T. (b) No context, with Raise's `sessionId` S and `superSession` T. | In both cases, the hold's messages are in session S with SuperSession T. | -- |
| 7 | Approval-role setting | A System Default Setting `Decide` `ApprovalRole` of `ZzApprover<n>`, then of "" (restored afterwards) | `RequiredRole` is `ZzApprover<n>`. With "", Raise fails naming `ApprovalRole` and creates nothing. | -- |
| 8 | Refused | Each alone: <br>- not an `ApprovalRequest`, or a saved row; <br>- `Kind` "" or `other`; `OwnerRef` "" or `x`; <br>- a tool_call row without `ToolName`, with `ToolArguments` `[1]` or `x`, or with a `DryRun`; <br>- a fix row without `DryRun`, with `DryRun` `x`, with a `ToolName`, or without `ResultTarget`; <br>- `IncidentRef` or `TraceRef` `x`; <br>- any one of `Ref`, `State`, `RequiredRole`, `RaisedAt`, `ExpiresAt`, `AnsweredAction`, `AnsweredChannel`, `AnsweredBy`, `AnsweredAt`, `Result` and `FinishedAt` set | An error status that names the field. `ref` is "", and there is no row, no hold and no sink call. | -- |
| 9 | Lock held | Another job of the test holds `LOCK ^OcuTalon.Bridge.Approval` | After about `LOCKSECONDS`, an error that names the lock. Nothing is created. | -- |
| 10 | Start fails | `ApprovalStartIn` disabled through `Ens.Director.EnableConfigItem`, and enabled again afterwards | Raise returns the director's error. There is no row, no hold and no sink call. | -- |
| 11 | Production restart | Row 3's request held (task open), then `Install.Step.Production.Start()`, then `Install.Step.Reconcile.Run()` | The same ApprovalHold instance is still the only one with the Ref. Its task is the same open task, and its `^Ens.Alarm` entry and wake time are unchanged. Completing the task delivers the TaskResponse to that hold: its pending key `task` is gone. | -- |
| 12 | Process gone | Row 3's request, with `RaisedAt` 23 h ago and `ExpiresAt` 1 h ahead, and its ApprovalHold instance deleted. Then `Install.Step.Reconcile.Run()` twice. | The orphaned task is discarded: it is complete and has no worklist item. One new ApprovalHold has the Ref, in a new session whose SuperSession is the `TraceRef`. It has one open task, with a worklist item for `OcuTalonWorkflow`, and an AlarmRequest of 3,595 to 3,600 s. Completing the new task delivers its response to the new hold. The second Reconcile starts no hold and cancels no task. | -- |
| 13 | Gone past expiry | As row 12, with `ExpiresAt` 1 minute ago | The new hold's AlarmRequest asks 1 s. Once it fires, the hold has ended and its task is no longer open. | The row's state is Story 3.5's. |
| 14 | Frozen hold | The compiled `ApprovalHold` | Its own stored properties are exactly `Ref`. Its own methods are exactly `OnRequest` and `OnResponse`, each one line that calls `OcuTalon.Bridge.Approval`. | -- |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- Epic 0's stub (:1-50).
  - `Raise` (:9-13) is the method to build.
  - `Answer` (:19-23), `Expire`, `Cancel`, `StartExecution` and `FinishExecution` (:26-48) stay stubs.
  - The class comment (:1-4) changes.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- the row, read only.
  - `RefIndex` is unique (:68), and `DRYRUNKEYS` is at :9.
  - Its columns are the Epic 0 contract that `Test.Data.Tables` pins exactly (`src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls:183-212`, contended).
- `src/bridge/cls/OcuTalon/Bridge/Service/ApprovalStart.cls` (:1-15) and `Process/ApprovalHold.cls` (:1-20) -- stubs.
  - Delete `STUB` (:8) and the stub handlers.
  - ApprovalHold's `Storage Default` (:15-18) becomes the compiler's block for `Ref`.
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls`:
  - `Run` (:11-21) gains the Workflow setup;
  - `AuditEvents` (:106-128) is "the class's only method that switches to %SYS", so extend it rather than adding a second `New $Namespace` method;
  - `CheckAudit` (:100) must keep checking the audit events only, because `Install.Step.Audit` calls it.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`:
  - `SETTINGS` (:92);
  - `ServiceUser` (:174-177) is the sibling of `ApprovalRole`;
  - `FireEvent` (:922) delivers every bridge event;
  - the storage block (:983) ends at slot 15 (`ToolClassification`), so append slot 16.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls:19` -- `ValueFor` reads the definition, then System Default Settings, then the property's initial value. `Ext/HostSink.cls:18` has `APPROVALRAISED`, and `:41` has `RefPayload`.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls` -- `ThreadSessionId` (:35), `SuperSession` (:38), `Active` (:84) and `Current` (:90). `Ids.cls:7` has `NewRef`, and `Msg/Enum.cls:18-21` has `APPROVALSTATE` and `APPROVALKIND`.
- `src/bridge/cls/OcuTalon/Bridge/Time.cls` -- `NowUtc` (:15). Add `PlusSeconds(utc, seconds)` and `SecondsUntil(utc)`, each "" for an unreadable time.
- `src/bridge/cls/OcuTalon/Bridge/Msg/ToolInventory.cls` -- the shape of a bridge `Ens.Request` message, for `Msg/ApprovalStart.cls` (new).
- `src/ocutalon/cls/OcuTalon/Production.cls:22-23,35` -- `ApprovalHold` (pool 1), `ApprovalStartIn` (pool 0) and `OcuTalonApprovals` (`EnsLib.Workflow.Operation`, pool 1) exist already. No edit.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls` -- `Order` (:12-15) runs `Reconcile` after `Production`, and `CallAreas` (:78) calls every area's `Reconcile()`. `Install/Step/Reconcile.cls:5-8` is the step.
- `src/ocutalon/cls/OcuTalon/Install/Step/Digest.cls` -- the declare-only area pattern for `Install/Step/Approvals.cls` (new).
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls:109-125` -- `EnsureService`, the login-disabled user that the Workflow login mirrors.
- Patterns from other lanes (read only):
  - `src/ocutalon/cls/OcuTalon/Core/Commands.cls:30-32` -- `CreateBusinessService` and `ProcessInput` from any job.
  - `src/ocutalon/cls/OcuTalon/Demo/Orders/Partner.cls:66-76` -- setting `..%SessionId` and `..%SuperSession` inside `OnProcessInput`.
- IRIS Workflow (`irislib/EnsLib/Workflow/`):
  - `Operation.cls:29-52` -- the role is the item's config name;
  - `Engine.cls:502-602` (`%DistributeTask`) and `TaskResponse.cls:89-123` (`OnNewTask`) -- sent to every active member, an error with none, and assigned directly when `%UserName` is set;
  - `Engine.cls:735-784` -- `%CancelRequest`;
  - `Engine.cls:201-248` -- `CompleteTask` sends the deferred response;
  - `RoleDefinition.cls:92,145,183` -- `CreateRole`, `AddUserToRole` and `RemoveUserFromRole`;
  - `UserDefinition.cls:47` -- `CreateUser`, and `IsActive`.
- The business-process framework (`irislib/Ens/`):
  - `BusinessProcess.cls:189-197` -- `SetTimer` with controlled keys `*`;
  - `BusinessProcess.cls:360-404` -- a timer that fires times out the controlled requests, and `TaskRequest.%OnTimeout` cancels the task;
  - `BusinessProcess.cls:405-420` -- the timer is cleared when it is all that is left;
  - `BusinessProcess.cls:1003-1027` -- `Reply`;
  - `BusinessProcess.cls:199-240` -- the header's `BusinessProcessId` is the sender's `%Id()`.
  - `Alarm.cls:181-225` -- alarms persist in `^Ens.Alarm` and are restored at `OnInit`.
  - `Util/Time.cls:32-60` -- `SecondsUntil` drops a `Z`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls` -- extend it:
  - `TestEveryRole` (:547) already checks that the README, service and public accounts are no Workflow users;
  - `WorkflowRows` (:912) and `ClearWorkflow` (:686) deletes `ZzRegistry%` Workflow users;
  - `OnBeforeAllTests` (:54), `OnAfterAllTests` (:75) and `Clean` (:754).
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:614-615` -- the `stub` of `ApprovalHold` and `ApprovalStartIn` becomes 0. The class comment (:11-13) lists the built items.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls:17-30` -- `TestApprovalStubs` (Raise leaves it). Class comment :1-10.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls:94-213` -- the message oracle. The `ToolInventory` entry is at :188.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls:23` -- `rowExists` checks Decision rows only.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Time.cls` -- the clock's tests.
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- reuse it, without editing it:
  - `ReadyReason` (:306), `Headers` (:323), `SessionOf` (:428) and `HeaderMark` (:437);
  - `SnapshotDefault`, `PutDefault` and `RestoreDefault` (:670-713).
  - `Send` (:262) uses ApprovalStartIn's service object for `SendRequestSync`, not `ProcessInput`, so it keeps working.
- `src/ocutalon/cls/OcuTalon/Test/Agent/Conversation.cls:158` -- a lane-a test that restarts the production with `Install.Step.Production.Start()`. `Test/Bridge/Budget.cls:426` is the lock-holding `Job` pattern.
- `ci/units.sh:17` -- `lane-a` runs the Bridge and Install areas, so the new test class needs no edit there.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 -- measure on the stage's warm throwaway `e3s4iw` (never the slot), and record the results under Design Notes:
  - (a) how to find an `ApprovalHold` instance by `Ref`, and to tell that it is live, through `%IsCompleted`, `%IsTerminated` and its pending responses;
  - (b) that `Reply` in `OnRequest` answers ApprovalStartIn's `SendRequestSync` while `task` and `expiry` stay pending;
  - (c) that the TaskRequest's header `BusinessProcessId` is the hold's `%Id()`;
  - (d) how long `Install.Step.Production.Start()` takes.
- [x] `src/bridge/cls/OcuTalon/Bridge/Time.cls` -- add `PlusSeconds` and `SecondsUntil`, and the class comment. Why: the expiry and the re-armed timer.
- [x] `src/bridge/cls/OcuTalon/Bridge/Msg/ApprovalStart.cls` (new) -- an `Ens.Request` with `Ref` (`%String(MAXLEN = 22)`), `SessionId` (`%Integer`) and `SuperSession` (`%String(MAXLEN = 64)`). Commit the compiler's storage block: compile it on slot A with `iris_doc_load`. Why: AD-11, AD-26, AD-5.
- [x] `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- add `ApprovalRole` to `SETTINGS` as `:Bridge`, with the property, its comment and storage slot 16. Why: AD-11.
- [x] `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- add the parameters, `Raise`, `Hold`, `HoldResponse`, the live-hold check and `Reconcile`, as in Boundaries, and the class comment. Why: AC 2 to 4.
- [x] `src/bridge/cls/OcuTalon/Bridge/Service/ApprovalStart.cls` -- add `OnProcessInput` as in Boundaries, delete `STUB`, and update the class comment. Why: AC 3.
- [x] `src/bridge/cls/OcuTalon/Bridge/Process/ApprovalHold.cls` -- add `Ref`, and the one-line `OnRequest` and `OnResponse`. Delete `STUB`, and commit the compiler's storage block (slot A). Why: AC 3, AC 5.
- [x] `src/bridge/cls/OcuTalon/Bridge/Installer.cls` -- add the Workflow setup to `Run`, and move the login part into the one `%SYS` method. Update the comments of the class and of that method. Why: AC 1.
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Approvals.cls` (new) -- the declare-only area: `Reconcile()` returns `Approval.Reconcile()`. Why: AC 4, AD-23.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`:
  - `TestApprovalsWorkflow` (row 1) and `TestApprovalsWorkflowRepaired` (row 2) reuse `WorkflowRows`, and their fixtures are `ZzRegistry<n>...`;
  - `OnAfterAllTests` and `Clean` run `Bridge.Installer.Run()` again before `ClearWorkflow`, so that the fixture members leave the role before their Workflow users are deleted, and the Workflow setup is whole after any failure;
  - update the class comment.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls` (new):
  - the tests `TestRaiseToolCall` (3, 5), `TestRaiseFix` (4), `TestCallerSession` (6), `TestApprovalRole` (7), `TestRefused` (8), `TestLockHeld` (9), `TestStartFails` (10), `TestRestartKeepsTheHold` (11), `TestReconcileReArms` (12), `TestReconcilePastExpiry` (13) and `TestHoldIsFrozen` (14);
  - each live test is guarded by `RunnerFixture.ReadyReason()`;
  - the helpers: the hold of a Ref, its task, its worklist users, its alarm, completing a task, and waiting with a deadline;
  - the cleanup: every Ref is tracked under `^OcuTalonTest("Approval")`;
  - a class comment that names what each test pins.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/Api.cls` -- `TestApprovalStubs` drops `Raise` and keeps the other five, and the class comment changes. `src/ocutalon/cls/OcuTalon/Test/Bridge/Contracts.cls` -- the oracle gains `Msg.ApprovalStart`, and the class comment changes. Why: shared surfaces.
- [x] `src/ocutalon/cls/OcuTalon/Test/Bridge/ProbeSink.cls` -- `rowExists` also counts an `ApprovalRequest` with the Ref, and the comment changes. `src/ocutalon/cls/OcuTalon/Test/Bridge/Time.cls` -- pins for the two new helpers: a day, a month end and a year end, the past, and unreadable input.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- `"stub": 0` for `ApprovalHold` and `ApprovalStartIn`, and the class comment.

**Acceptance Criteria:**
- Given `OcuTalon.Bridge.Installer` runs (first at every start, or on its own), when it sets up approvals, then:
  - the Workflow role `OcuTalonApprovals` has exactly one member, the active, technical Workflow user `OcuTalonWorkflow`, whose IRIS user has login disabled and no roles;
  - the production item `OcuTalonApprovals` is an `EnsLib.Workflow.Operation` named after the role;
  - the installer makes no other Workflow user, so after a start no person and no public account is a Workflow user or role member, and the Workflow inbox can't answer for anyone;
  - a run repairs a missing role or user, an inactive user, and an enabled or role-holding login, and it removes every other member from the role.
  - Rows 1 and 2 hold (FR-8, AD-11, AD-24, AD-2).
- Given a risky action's unsaved row, when `OcuTalon.Bridge.Approval.Raise` is called, then:
  - it creates one pending row with the kind, the `IncidentRef` when there is one, the fixed targets and exact change (the exact call, or the dry run with its incident), the `OwnerRef`, the required role from `ApprovalRole` (`OcuTalonUser` by default), the raised time, an expiry exactly 24 hours later, the `ResultTarget` and an unguessable `Ref`;
  - a refused request, a held lock or a failed start creates nothing.
  - Rows 3, 4 and 7 to 10 hold (FR-8, FR-5, AD-11, UX-DR52, UX-DR148, UX-DR153).
- Given the new row, when Raise starts `ApprovalHold` through `ApprovalStartIn`, then:
  - ApprovalHold sends an `EnsLib.Workflow.TaskRequest` with `%Actions` "Approve,Reject" to `OcuTalonApprovals`, where only `OcuTalonWorkflow` receives it, and sets its timer to the row's expiry;
  - the request's messages are in the caller's trace session with its SuperSession;
  - `HostSinkClass` receives `approval.raised` with the `Ref`, once, after the row is saved and the hold has started.
  - Rows 3, 5 and 6 hold (FR-8, NFR-20, AD-11, AD-26, AD-31).
- Given pending approval requests, when the production restarts and the Reconcile step runs, as every start runs it after `Production`, then:
  - a hold that survived keeps its task and timer, and nothing new starts;
  - a pending row whose hold is gone gets a new `ApprovalHold`, through `ApprovalStartIn`, with its timer re-armed from the row's times;
  - its orphaned Workflow task is cancelled;
  - the new task's answer reaches the new hold, so the request can still be answered.
  - Rows 11 to 13 hold (FR-8, AD-5, AD-23).
- Given `ApprovalHold`, when the class is inspected and the storage checks run, then its persistent properties are append-only, with exactly `Ref` and the committed compiler block, and its logic is in `OcuTalon.Bridge.Approval`. Row 14, `bash ci/checks.sh` (storage) and `live storage-roundtrip` hold (AD-5).
- Given the stubs that Stories 3.5 and 3.6 build, when `Test.Bridge.Api` runs, then `Answer` still answers `not_found`, and `Expire`, `Cancel`, `StartExecution` and `FinishExecution` still say they are not implemented.
- Given the fresh `shard lane-a`, `shard lane-b`, `live install-start`, `live install-upgrade`, `live audit`, `live production`, `live production-restart`, `live storage-roundtrip` and `live demo-path`, when they run, then every class and unit passes.

## Spec Change Log

- 2026-10-25, lead spec gate: AD-11 is not amended. The plan's five points went into a new Consistency Conventions row "Approval requests" (Rule 20 light path): the `ApprovalRole` setting, the synchronous start and the failed Raise that leaves nothing, the caller's and the re-armed hold's sessions, the frozen hold, the installer's membership rule and the Workflow login's name hold, and where a request's targets and change live. The last one is the reading of AD-11's "fixed targets; exact change" against Epic 0's row contract (AD-33) and AD-16 ("FixExecutor loads kind, targets and change from the row ... the message list comes from the failure group"): no column is added in this story, and the first fix kind (Epic 7) writes its keys into `DryRun`. Ruled in the veto window: the IRIS user `OcuTalonWorkflow` (login disabled, no roles) and the membership-only rule (privileges and roles), and the stored-data additions (`Decide`'s `ApprovalRole` value 16, `ApprovalHold`'s `Ref`, the new `Msg.ApprovalStart`). All kept as planned.

## Review Triage Log

### 2026-10-24 - Review pass
- verdicts: 36 rows (a row may stand for several layer items that share a cause) - high 0, medium 2, low 24, false 10, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1 / Edge 2, 3, 15: a start that times out, or a hold that fails after sending its task, can leave a hold or task with no row - the hold refuses a missing or non-pending row, so a late start holds nothing, and Reconcile's orphan rule cancels a task of a dead hold or a non-pending row at the next start (Design Notes, decided in-stage); a failure after the task is sent needs a failing `Reply` or `SetTimer`, which nothing reaches.
  - `[low]` `[reject]` Blind 2 / Edge 5: no `$TLevel` guard in Raise - a call inside a transaction fails closed with the hold's "no approval request" error and leaves no row; no release-1 caller raises inside one, and the guard adds a branch the spec does not name.
  - `[low]` `[reject]` Blind 3 / Edge 1, 14: Reconcile races a concurrent Raise - the window is the milliseconds between Raise's save and the hold's first send, and Reconcile runs at start, before any agent turn (an LLM call of seconds) can reach a risky tool; `wontfix-theoretical`.
  - `[low]` `[reject]` Blind 4: the timer rounds down, so it can fire up to 1 s before ExpiresAt - the spec says whole seconds until ExpiresAt, and Story 3.5 owns what the timer does.
  - `[false]` `[reject]` Blind 5: the spec text "rewritten at every start" for the password - the intent contract says an existing user keeps its password, which the code does; a fix would edit the spec's Design Notes.
  - `[low]` `[reject]` Blind 6: `LiveHold` scans `ApprovalHold` by Ref - an index changes how stored data is kept (a veto item), and release-1 volumes are a handful of rows; `wontfix-accepted`, reopen_if the `ApprovalHold` row count passes a few thousand.
  - `[low]` `[reject]` Blind 7: Reconcile continues after a failed task query - `%Next` on a failed result returns 0, so pass 1 does nothing and the failure is already combined.
  - `[false]` `[reject]` Blind 8: pass 1 cancels every open task of the role - this is the spec's rule ("every incomplete task of role WORKFLOWROLE that is not the task of a live hold of a pending row"), and the role is the product's own.
  - `[low]` `[reject]` Blind 9: `OnAfterAllTests` and `Clean` both run the installer and drop its status - test teardown has no assertion context.
  - `[false]` `[reject]` Blind 10: the Auto Run Result still said ready-for-dev - it is written at finalize.
  - `[low]` `[reject]` Blind 11: the class comment says Hold "sets the 24-hour timer" - Hold's own comment states the exact rule (the seconds until ExpiresAt).
  - `[low]` `[reject]` Edge 4: an unchecked `%DeleteId` after a failed start - a delete of a row just saved does not fail in a reachable way.
  - `[low]` `[reject]` Edge 6: the caller's object keeps Ref and State after a failed Raise - callers build a new unsaved row per call.
  - `[low]` `[reject]` Edge 7: `LiveHold` reads a failed SQL as no hold - a plain select on a table of the class does not fail in a reachable way.
  - `[false]` `[reject]` Edge 8: a pending row with an unreadable ExpiresAt - only Raise writes rows, and it always sets a readable one.
  - `[low]` `[reject]` Edge 9: a purged message header makes a live hold's task an orphan - the integrity purge keeps the headers of an incomplete session `(inference)`.
  - `[false]` `[reject]` Edge 10: ApprovalHold given a request that is not an ApprovalStart - the production wires only ApprovalStartIn to it.
  - `[false]` `[reject]` Edge 11: an existing IRIS user named OcuTalonWorkflow is disabled - the intent contract says so ("An existing one gets Enabled 0, no roles and no escalation roles").
  - `[low]` `[reject]` Edge 12: an ApprovalRole of whitespace or a name that is no role - the setting is the host's; an empty value is already refused, and a wrong name fails closed (nobody can answer).
  - `[false]` `[reject]` Edge 13: the lock key is the new Ref, so it excludes nothing - by design: Story 3.5's Answer takes the same key, and Reconcile's race is graded above.
  - `[false]` `[reject]` Edge 14 (claim): other Workflow users stay after a start - the spec's Boundaries say the installer deletes none it did not make.
  - `[low]` `[reject]` Edge 15 (claim): a failed Raise leaves nothing - covered by the first row of this log.
  - `[medium]` `[patch]` Gap 1: the given fields were compared with the row that Raise had changed, so clearing a copied field passed - `Snapshot` takes them before the call, and `AssertGiven` and the sink's owner and SuperSession read it; mutation recorded.
  - `[low]` `[reject]` Gap 2: Raise's default `HostSinkClass` path has no test - it is the one line that `Budget` uses and tests the same way; Story 3.6's gate reaches it through the real sink.
  - `[medium]` `[patch]` Gap 3: the caller's session and SuperSession were pinned only for a context alone and for arguments alone - `TestCallerSession` gains (c) an argument that wins over the context's and (d) each value resolved on its own; mutation recorded.
  - `[false]` `[reject]` Gap 4: `TestApprovalsWorkflow` asserts every Workflow user of the namespace - that is the row 1 wording, and the test runs on throwaway stacks, after `Clean` removes the fixtures.
  - `[low]` `[patch]` Gap other 1: `TestReconcilePastExpiry` skipped its timer assertion when no AlarmRequest was found - it now asserts the AlarmRequest is stored.
  - `[low]` `[reject]` Gap other 2: `WaitHoldGone` is true when no hold ever ran - rows 11 and 12 assert the live hold before it, and row 13 the two tasks.
  - `[low]` `[reject]` Gap other 3: `TestHoldIsFrozen` counts non-blank lines - `ci/checks.sh` (storage) pins the stored side, and a two-statement line is visible in review.
  - `[low]` `[reject]` Gap other 4: row 2 (a) does not delete the IRIS user - the spec's row names the role and the Workflow user; the create branch runs on a fresh start (`live install-start`).
  - `[low]` `[reject]` Gap other 5: no failing case for Reconcile's combined status - its failures are SQL errors and cancel errors that nothing reachable produces.
  - `[low]` `[reject]` Gap other 6: the old hold's ^Ens.Alarm entry stays after the test deletes it - throwaway stacks only.
  - `[low]` `[reject]` Intent 1: tests call `Bridge.Installer.Run()` and `Install.Step.Reconcile.Run()` directly, not one start sequence - the order of the steps is Epic 0's and `live install-start`, `install-upgrade` and `production-restart` run every start, Reconcile included.
  - `[low]` `[reject]` Intent 2: Raise's sink is always passed in the tests - same as Gap 2.
  - `[low]` `[reject]` Intent 3: rows 11 and 13 assert the hold ends instead of the key `task` being gone - a finished hold is deleted by the framework (Task 0), so the key cannot be read; the hold ending is the same fact.
  - `[false]` `[reject]` Intent 4: the readings (API contract, running product, installer scope, live predicate, frozen hold) - descriptive; no defect named beyond the rows above.

## Design Notes

**Architecture decisions:**
- **AD-11:** Raise, the row, the hold, the Workflow role and its single member, and the approval-role setting. Prevents: approval state beside Workflow, two answers acting, and the inbox as a second way to answer.
- **AD-5:** the frozen hold, the re-arm from the row's times, and the cancelled orphan tasks.
- **AD-23:** the bridge installer runs first, and the Lane A `Reconcile()` declaration runs after `Production`.
- **AD-24:** public accounts are never Workflow users or members.
- **AD-26:** the caller's trace session, the SuperSession tag, and a re-armed waiter's own session.
- **AD-31:** `approval.raised` goes after the save, in the job that changed state, through `FireEvent`.
- **AD-2:** the bridge installer sets up its own Workflow role and user, and the bridge names no other package.
- **AD-3 and AD-17:** one `%SYS` method in `Bridge.Installer`.
- **AD-6:** no `%AI` call in code that Story 3.6 calls from a callback.
- **AD-16:** `DryRun` holds a fix's change.
- **AD-22:** tests run on throwaways.
- **AD-29 and AD-33:** the three items and the table are Lane A's.

No AC contradicts an AD's Rule.

**Measured at planning:** nothing was run, and no runtime was touched. The facts in Boundaries and the Code Map come from the source tree and `irislib/`. Task 0 measures the four points that the implementation depends on.

**Measured in Task 0** (warm throwaway `e3s4iw`, build 154; a temporary probe test class, deleted afterwards):
- (a) An `ApprovalHold` is found by `SELECT %ID FROM OcuTalon_Bridge_Process.ApprovalHold WHERE Ref = ?` and opened. A live hold has `%IsCompleted` 0, `%IsTerminated` 0, `%RepliedStatus` 3 (sent) and `%MasterPendingResponses.Count()` 2: the key `task` (`IsTimer` 0, no controlled keys) and the key `expiry` (`IsTimer` 1, controlled keys `*`). A hold that ends (its task completed, so that only the timer is left) is deleted by the framework: `%OpenId` of its id answers "" within 3 s. So the tests read "the hold has ended" as "no instance is live", and a live hold is an instance that is not completed, not terminated and has at least one pending response.
- (b) `Reply` in `OnRequest` answers ApprovalStartIn's `SendRequestSync` at once while `task` and `expiry` stay pending: `Raise` took 0.004 s, with `%RepliedStatus` 3 and both keys pending.
- (c) The TaskRequest's header `BusinessProcessId` is the hold's `%Id()` (task 15 had `bp=6`, and the hold had id 6). `TaskStatus_RoleName`, `TaskStatus_Request` and `TaskStatus_IsComplete` are the SQL names that `Reconcile` reads, and `%Subject` is a usable SQL name of `EnsLib_Workflow.TaskResponse`.
- (d) `Install.Step.Production.Start()` on the running warm production took 1.05 s (a restart). The whole `Test.Bridge.Approval` class, with its one restart, its 2-second lock wait and its twelve raises, runs in about 4.6 s warm.
- Also measured: `^Ens.Alarm(<AlarmRequest id>)` holds `$ListBuild(wake time, the AlarmRequest's header id, ...)`, and the hold's `%SessionId` and `%SuperSession` are the ones that ApprovalStartIn set.

**Decided in-stage** (small and reversible; inside AD-11 and the AC):
- **Targets and change use the contract's columns.** For `tool_call`, the exact call (`ToolName`, `ToolArguments`) is both the target and the change. For `fix`, the dry run (`field`, `before`, `after`, the counts) and its incident are: the failure group, which `IncidentRef` names, holds the target operation and the messages (AD-16). Epic 0 fixed these columns as the cross-lane contract (AD-33), and a new column would edit `Test/Data/Tables.cls`, a contended path. A later fix kind adds keys to `DryRun` (`DRYRUNKEYS`).
- **The start is synchronous.** The hold replies once it has sent its task and set its timer, so Raise says OK only when the request is really held. A failed start leaves nothing behind.
- **A failed Raise deletes its own row.** That row was never announced. The hold refuses a missing or non-pending row, so a late start after a timeout holds nothing. Reconcile's orphan rule also cancels a task whose row is not pending.
- **The caller's session:** explicit arguments win (Epic 5's `IncidentManager` will pass its own), then the bridge context (Story 3.6's gate), then a new session tagged with `TraceRef`. A re-armed hold takes its own session with the tag, which is AD-26's waiter rule. The row stores no header id, and its first session may be purged.
- **Membership is what the installer enforces.** Only members of `OcuTalonApprovals` get its tasks, and the hold never names a `%UserName`. So the installer removes every other member, but never deletes a Workflow user it did not make: in a developer's own namespace, other Workflow users may serve another production. A fresh install has no other Workflow user (row 1), and `Test.Install.Registry` `TestEveryRole` keeps checking the accounts.
- **The Workflow login is an IRIS user with login disabled.** It holds the name, so that no account created later under that name can sign in to the Workflow inbox (`UserDefinition`: a Workflow user with no system user cannot sign in there). Every start rewrites it like `OcuTalonService`.
- **`ApprovalRole` defaults to `OcuTalonUser` in the bridge**, as `ServiceUser` defaults to `OcuTalonService`. An empty value refuses Raise, which fails closed.
- **The timer gets whole seconds, at least 1**, because `Ens.Util.Time.SecondsUntil` reads a `Z` timestamp as local time. A past expiry fires at once, and Story 3.5's handler expires the row. Until then, such a row stays pending and is re-armed at each start. No release-1 caller raises before Story 3.6.
- **An IRIS restart needs no live script.** A hold survives it the way it survives the production restart of row 11: its instance and its `^Ens.Alarm` entry are on the durable volume, and `Ens.Alarm` restores alarms at start. The after-start then runs the same Reconcile step. Changing a live restart script would mean editing `docker/tests/**`, which is contended. `live production-restart` still proves that every start, Reconcile included, ends OK.
- **The tests complete Workflow tasks themselves** (assign, then complete with `Approve`), exactly what Story 3.5's `Answer` will do inside the lock. They never change a row's `State`. Rows 12 and 13 move a fixture row's `RaisedAt` and `ExpiresAt` directly, which only a test does.
- **Raise reads each of the caller's two session values on its own:** `sessionId` is the argument, else the context's `ThreadSessionId`, else new; `superSession` is the argument, else the context's `SuperSession`, else the row's `TraceRef`. A caller that passes only one of them still gets the context's other value.
- **`Approval.LiveHold(ref)` is public** (not [ Internal ]) because `Reconcile` and the tests both use it; its helper `IsLive`, `Validate`, `Refuse`, `IsRef`, `IsJsonObject`, `SaveAndStart`, `OwnedByLiveHold` and `Combine` are private. `StartHold(ref, sessionId, superSession)` is [ Internal ] and is the one way that `Raise` and `Reconcile` start a hold.
- **`Bridge.Installer`:** the one private `%SYS` method is now `InSystem(action)` (action `audit`, `check` or `login`), which replaces `AuditEvents(create)`; `RegisterAudit` and `CheckAudit` keep their signatures. `SetUpApprovals()` is public, so that it can run on its own. It runs after `RegisterAudit` and before the model families.
- **Row 1 asserts "the only Workflow user" by listing the namespace's Workflow users**, and row 2 (a) deletes the role and the Workflow user, not the IRIS user (which `InSystem` repairs by Modify).
- **A refusal checks in a fixed order** (request, Kind, OwnerRef, the kind's fields, IncidentRef, TraceRef, the fields that Raise owns, then the `ApprovalRole` setting) and reports the first. The error text reads `...Raise refuses the request: <field> <reason>`, which the tests match.
- **`Time.PlusSeconds` answers "" for a result before the calendar's start** (a negative total of seconds), as it does for any unreadable input.
- **Row 11 proves "the answer reaches that hold" as "the hold ends"**, because the framework deletes a completed hold, so its pending key `task` cannot be read afterwards; the keys are read before the restart and after the Reconcile step.
- **`Test.Install.Registry` `OnAfterAllTests` runs `Bridge.Installer.Run()` itself, and so does `Clean`** (which `OnAfterAllTests` also calls), so the fixture members leave the role before `ClearWorkflow` deletes their Workflow users.

- **Alarm entries are polled in the tests.** `Ens.Alarm` stores a hold's `^Ens.Alarm` entry when it handles the AlarmRequest, so on a loaded fresh shard the entry can come after the task: `Test.Bridge.Approval` polls for it for up to 10 s (found by the first fresh `shard lane-a`, where two assertions failed).

**For the lead (veto window; Rule 20, the plan does not write the spine):**
- **Security posture and privileges:** the IRIS user `OcuTalonWorkflow` (login disabled, no roles, a random password, rewritten at every start), and membership-only enforcement (no deletion of a Workflow user that the installer did not make).
- **Stored data:** `Decide` gains the stored setting `ApprovalRole` (slot 16), `ApprovalHold` its first stored property `Ref`, and the new message class `Msg.ApprovalStart` is added. No `ApprovalRequest` column changes.
- **Spine, Rule 20:** consider recording these in AD-11.
  - The approval-role setting is `Decide`'s host setting `ApprovalRole`, default `OcuTalonUser`.
  - The start through ApprovalStartIn is synchronous, and a failed Raise creates nothing.
  - A re-armed hold runs in its own session tagged with the row's `TraceRef`.
  - The installer enforces the membership of `OcuTalonApprovals`.
  - The targets and the change of a request live in `DryRun` or in `ToolName` and `ToolArguments`.

**Cross-epic (Epic 13):**
- From this story, `Bridge.Installer` also creates the Workflow role `OcuTalonApprovals`, the Workflow user `OcuTalonWorkflow` and the IRIS user `OcuTalonWorkflow` (login disabled), in whatever namespace it runs in.
- `Decide` gains `ApprovalRole`, with a default.
- The bridge example's production has no `ApprovalStartIn`, `ApprovalHold` or `OcuTalonApprovals` item. So from Story 3.6, a risky call of its agent is denied with `FAILED` instead of being held, unless Epic 13 adds the three items.
- No example file changes, and the example's current agent has no tools.

**Rule 2 (extend, don't copy):**
- Approval, ApprovalStart and ApprovalHold extend Epic 0's stubs.
- The start follows `Core.Commands.Submit`, and the session join follows `Demo.Orders.Partner.OnProcessInput`.
- `ApprovalHold` uses `Decide`'s timer and response keys. `Msg.ApprovalStart` follows `Msg.ToolInventory`.
- `Install.Step.Approvals` follows `Install.Step.Digest`. `ApprovalRole` follows `ServiceUser`. `Time` gains two helpers.
- The tests extend `Test.Install.Registry` (`WorkflowRows`, `ClearWorkflow`, `Clean`), `Test.Bridge.Api`, `Test.Bridge.Contracts`, `Test.Bridge.Time` and `ProbeSink`, and reuse `RunnerFixture`'s helpers.
- **One copy, with its reason:** the Workflow login repeats the eight lines of `Install.Step.Users.EnsureService` with no role. The bridge cannot call `OcuTalon.Install` (AD-2). `Users` could call the bridge, but only through a public `%SYS` method, and `Bridge.Installer` keeps one private `%SYS` method (AD-3, AD-17).

**Integration ACs:**
- The Workflow operation `OcuTalonApprovals`, a real production item, reads the hold's TaskRequest and gives exactly one worklist item, to `OcuTalonWorkflow` (row 5).
- The Reconcile step, through the registry's area discovery, reads the pending rows and gives a running hold with a new task (row 12).
- The after-start registry runs `Bridge.Installer` first, and every start ends `RESULT OK` (`live install-start`, `live install-upgrade`, `live production-restart`).
- The host sink receives `approval.raised` (rows 3 and 4). OcuTalon's own `BridgeSink` is Lane B's stub until Story 2.6.

**Consumed-by:**
- **Story 3.5:**
  - `Answer` assigns and completes the hold's task (found by `TASKSUBJECT` plus the Ref) under the lock;
  - `HoldResponse` acts on `task` and `expiry`;
  - `Expire` and `Cancel` act on the row.
  - Its tests should include a re-armed request, and an answer that arrives before the task exists.
- **Story 3.6:** the gate calls `Raise` (kind `tool_call`) from `%CanExecute` in a bridge context, adds `Approval` to `CodeRules`' `CALLBACKHELPERS`, and tests the lock timeout through it. It should also check the runner's own session after the call.
- **Story 3.7:** audits the state methods.
- **Story 2.6 (Lane B):** `BridgeSink` publishes `approval.raised`.
- **Epic 6:** `AnswersIn` and the cards read the rows.
- **Epic 5 and Epic 7:** `IncidentManager` raises `fix` requests and passes its session.
- **Story 30.3:** the replay.
- **Epic 15:** the IPM path runs the `Reconcile()` declarations at production start.

**Consumes:**
- `Ids.NewRef` and the extension bases (Epic 0);
- `Accessor.ValueFor` and `Decide.FireEvent` (Stories 0.6 and 1.3);
- `Context` (Story 1.2);
- the step registry and its areas (Story 0.2), and `Install.Step.Production.Start` (Story 0.6);
- `RunnerFixture` and `ProbeSink` (Epic 1).

**Footprint:**
- All edits are in the Epic 3 footprint: `src/bridge/**` (not `BridgeExample`), `Install/**` and `Test/{Bridge,Install}/**`.
- No footprint extension. No contended path is edited.

**Ledger inbox:** none.

**Shard time:** the new tests add about 30 to 45 s to `lane-a`: about twelve raises with their holds, one production restart of about 10 to 15 s (Story 1.12 measured a stop of 1 to 2 s and a start of 6 to 13 s), two production updates for row 10, a 1-second timer and a 2-second lock wait (inference). That puts the fresh shard at about 410 to 445 s, inside the 600 s cap.

## Verification

**Targets:**
- `ocutalon-slot-a` is for `iris_doc_load` compiles only, which give the compiler's storage blocks. Pass MCP `server: ocutalon-slot-a` and `namespace: OCUTALON` on every call, after `iris_server_info` shows build 154.
- Everything else runs through `ci/iris.sh` and `ci/warm.sh`. Never `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, slot B or slot C. No push, and never read `.env`.
- Run every command from the worktree root, in the foreground with `timeout: 600000`, one per call, with these variables on the same line:
  - `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)"`;
  - `OCUTALON_TEST_WEB_PORT=52801`;
  - `OCUTALON_LOCK_OWNER='epic=3 stage=implement'`.
- The tags: fresh `e3s4i` and warm `e3s4iw` (implement); `e3s4q` and `e3s4qw` (QA); `e3s4r` and `e3s4rw` (review). Each stage uses its own tags and stage name.

**Commands:**
- (loop) `bash ci/checks.sh` -- expected: every block passes, `boundaries` (AD-2), `class-rules` and `storage` included. About 20 s.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4iw bash ci/warm.sh up` -- expected: a ready warm stack.
  - Run it once `Bridge.Installer` is changed: a warm run reloads classes but does not run the start again, so the Workflow setup comes from `up`.
  - A later installer change needs `down`, then `up`.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e3s4iw bash ci/iris.sh class <Class>`, one call per class -- expected: `CLASS ... passed` after a `WARM reloaded` line. The classes:
  - `OcuTalon.Test.Bridge.Approval`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Install.Production` and `OcuTalon.Test.Bridge.Api`;
  - `OcuTalon.Test.Bridge.Contracts` and `OcuTalon.Test.Bridge.Time`;
  - `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Bridge.Budget` and `OcuTalon.Test.Bridge.Example` (Decide's settings and `ProbeSink`).
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4iw bash ci/warm.sh down` -- run it at the stage's end, and after a failure.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh shard lane-a` -- expected: every class passes, `Test.Bridge.Approval` and `Test.Install.Registry` included. About 410 to 445 s; run it alone in its call.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh shard lane-b` -- expected: every class passes, `Test.Data.Tables` and `Test.Contract.Ac` included (the row's contract and Raise's signature prefix). About 70 s.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh live install-start` -- expected: PASS. This includes row 5, where the bridge installs alone in OCUBRIDGET and `Bridge.Installer.Run()` returns 1.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh live install-upgrade` -- expected: PASS.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh live audit` -- expected: PASS (`Bridge.Installer.Run()` with an event disabled and with instance auditing off).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh live production` -- expected: PASS.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh live production-restart` -- expected: PASS (every start, the Reconcile step included, ends OK).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh live storage-roundtrip` -- expected: PASS (the compiled blocks of `Decide`, `ApprovalHold` and `Msg.ApprovalStart` equal the committed ones).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh live demo-path` -- expected: PASS (UJ-1 is unchanged).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s4i bash ci/iris.sh teardown` -- expected: nothing tagged `e3s4i` is left.

**Shared surfaces:**
- **Raise is no stub:** `Test.Bridge.Api` `TestApprovalStubs`.
- **The stub flags** of `ApprovalHold` and `ApprovalStartIn`: the oracle of `Test.Install.Production` and its `TestStubsAnswer`.
- **The bridge message oracle** gains `Msg.ApprovalStart`: `Test.Bridge.Contracts`.
- **`ProbeSink`'s `rowExists`** now also counts approval rows: `Test.Bridge.Decide`, `Test.Bridge.Budget` and `Test.Bridge.Gate` read it.
- **`Decide`'s `SETTINGS` and storage** (`ApprovalRole`): `Test.Bridge.Gate`, `Test.Bridge.Decide` and `Test.Bridge.Example` read the settings by entry.
- **The Reconcile step now calls the `Approvals` area:** `Test.Install.Registry` `TestReconcileStep`, and every start (`live install-start`, `install-upgrade`, `production-restart`).
- **The Workflow role, user and login** `OcuTalonWorkflow`: `Test.Install.Registry` `TestEveryRole` checks other accounts through `WorkflowRows`.
- **ApprovalStartIn:**
  - `RunnerFixture.Send` sends through its service object;
  - row 10 disables it for a moment and restores it.
- **The production** is restarted once by `Test.Bridge.Approval`, as `Test.Agent.Conversation` does.
- Search the test trees for `ApprovalStartIn`, `ApprovalHold`, `Approval).Raise`, `STUB`, `Bridge.Installer).Run` and `ProbeSink`.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order. Tests that change Workflow objects or the IRIS user `OcuTalonWorkflow` run on throwaways only, restore them, and delete the fixture Workflow users they made.

**Pinning tests and the mutations to record** (Rule 19; record each as `mutation: ... -> ...` here):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `TestApprovalsWorkflowRepaired` (a) | the installer does not create the Workflow user, or the role |
| AC 1 | `TestApprovalsWorkflowRepaired` (b) | the installer does not remove other members; or does not set `IsActive`; or leaves the login enabled or holding a role |
| AC 1 | `TestApprovalsWorkflow` | `WORKFLOWROLE` differs from the production item's name |
| AC 2 | `TestRaiseToolCall` | `ExpiresAt` is 23 h after `RaisedAt`; or `Ref` is a counter (it is not 22 base64url characters) |
| AC 2 | `TestApprovalRole` | `RequiredRole` is the constant `OcuTalonUser` instead of the setting |
| AC 2 | `TestRefused` | the `Kind` check is removed; or a caller's `RequiredRole` is kept |
| AC 2 | `TestLockHeld` | Raise takes no lock |
| AC 2 | `TestStartFails` | Raise keeps its row when the start fails |
| AC 3 | `TestRaiseToolCall` (row 5) | `%Actions` is `Approve`; or the timer is 3,600 s; or `%UserName` is set to a fixture Workflow user |
| AC 3 | `TestCallerSession` | ApprovalStartIn does not set `..%SessionId` from the message |
| AC 3 | `TestRaiseToolCall` | `approval.raised` is fired before the save, or not at all |
| AC 4 | `TestRestartKeepsTheHold` | Reconcile treats every hold as gone (a second hold starts) |
| AC 4 | `TestReconcileReArms` | the re-arm uses `EXPIRYSECONDS` instead of the row's `ExpiresAt`; or the orphan cancel is skipped; or `Install.Step.Approvals.Reconcile` does nothing |
| AC 4 | `TestReconcilePastExpiry` | the timer is the raw seconds left (0 or less) instead of at least 1 |
| AC 5 | `TestHoldIsFrozen` | a second stored property is added to `ApprovalHold`; or `OnRequest` holds the logic |
| AC 6 | `Test.Bridge.Api` `TestApprovalStubs` | `Answer` answers `done` |

Mutations recorded by the implement stage (Rule 19), each applied alone to the warm stack `e3s4iw`, the named class observed red, then the file restored byte for byte (`cmp` against a backup) and the class green again on the same stack:
- mutation: `Bridge.Installer.SetUpApprovals` does not create the Workflow user (`CreateUser` replaced by OK) -> `Test.Install.Registry` `TestApprovalsWorkflowRepaired` (a) red.
- mutation: `SetUpApprovals` does not create the Workflow role (`CreateRole` replaced by OK) -> `TestApprovalsWorkflowRepaired` (a) and (b) red.
- mutation: `SetUpApprovals` does not remove the other members (`RemoveUserFromRole` replaced by OK) -> `TestApprovalsWorkflowRepaired` (b) red.
- mutation: `SetUpApprovals` leaves `IsActive` 0 -> `TestApprovalsWorkflowRepaired` (b) red.
- mutation: `InSystem("login")` sets the roles to `x`, or sets Enabled 1 -> `TestApprovalsWorkflow` and `TestApprovalsWorkflowRepaired` red (two runs).
- mutation: `Approval.WORKFLOWROLE` is `OcuTalonApprovalz` -> `TestApprovalsWorkflow` red.
- mutation: `EXPIRYSECONDS` is 82800 -> `Test.Bridge.Approval` `TestRaiseToolCall` and `TestRaiseFix` red.
- mutation: `Raise` uses a counter for the Ref -> `TestRaiseToolCall` and `TestRaiseFix` red.
- mutation: `Raise` sets `RequiredRole` to the constant `OcuTalonUser` -> `TestApprovalRole` red.
- mutation: `Validate` skips the `Kind` check -> `TestRefused` red.
- mutation: `Validate` leaves `RequiredRole` out of the fields that Raise owns -> `TestRefused` red.
- mutation: `Raise` takes no lock -> `TestLockHeld` red.
- mutation: `SaveAndStart` keeps the row when the start fails -> `TestStartFails` red.
- mutation: `ACTIONS` is `Approve` -> `TestRaiseToolCall` red; `Hold` sets `%UserName` to a fixture Workflow user -> `TestRaiseToolCall` red; the timer is a fixed 3,600 s -> `TestRaiseToolCall` red.
- mutation: `ApprovalStartIn` does not set `..%SessionId` from the message -> `TestCallerSession` red.
- mutation: `approval.raised` is fired before the save -> `TestRaiseToolCall` and `TestRaiseFix` red; not fired at all -> the same two red.
- mutation: `Reconcile` treats every hold as gone -> `TestRestartKeepsTheHold` and `TestReconcileReArms` red.
- mutation: `Hold` uses `EXPIRYSECONDS` instead of the row's `ExpiresAt` -> `TestReconcileReArms` red; `Reconcile` skips the orphan cancel -> `TestReconcileReArms` red; `Install.Step.Approvals.Reconcile` does nothing -> `TestReconcileReArms` red.
- mutation: `Hold` passes the raw seconds (no minimum of 1) -> `TestReconcilePastExpiry` red.
- mutation: a second stored property on `ApprovalHold` -> `TestHoldIsFrozen` red; `OnRequest` holds logic (two lines) -> `TestHoldIsFrozen` red.
- mutation: `Approval.Answer` answers `done` -> `Test.Bridge.Api` `TestApprovalStubs` red.
- mutation: `Time.PlusSeconds` adds a day to the result, or `SecondsUntil` reverses its sign -> `Test.Bridge.Time` `TestPlusSeconds` and `TestSecondsUntil` red.
- mutation: `SaveAndStart` clears `request.OwnerRef` after the checks (the given fields are compared with a snapshot taken before Raise) -> `TestRaiseToolCall` and `TestRaiseFix` red (the given OwnerRef and the sink call).
- mutation: `SaveAndStart` always takes the context's `ThreadSessionId` over Raise's `sessionId` argument -> `TestCallerSession` (c) and (d) red.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 3.4 builds the approval hold. `Bridge.Installer` sets up the Workflow role `OcuTalonApprovals` with the one member `OcuTalonWorkflow` and the login-disabled IRIS user of that name. `Approval.Raise` validates the unsaved row, saves it as pending under a lock, starts the hold synchronously through `ApprovalStartIn` and fires `approval.raised` after the unlock; a failed Raise leaves no row. `ApprovalHold` (one stored property, `Ref`) sends the Workflow task and sets the expiry timer through `Approval.Hold`. `Install.Step.Approvals.Reconcile` re-arms holds whose process is gone and cancels orphaned tasks. Answer, Expire, Cancel, StartExecution and FinishExecution stay stubs.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`: constants, `Raise`, `Hold`, `HoldResponse`, `LiveHold`, `Reconcile`.
- `src/bridge/cls/OcuTalon/Bridge/Installer.cls`: `SetUpApprovals`, and the one `%SYS` method `InSystem` (audit, check, login).
- `src/bridge/cls/OcuTalon/Bridge/Service/ApprovalStart.cls`, `Process/ApprovalHold.cls`: the handlers; `STUB` removed.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: the `ApprovalRole` setting (storage slot 16).
- `src/bridge/cls/OcuTalon/Bridge/Time.cls`: `PlusSeconds`, `SecondsUntil`.
- `src/bridge/cls/OcuTalon/Bridge/Msg/ApprovalStart.cls` (new): the start message.
- `src/ocutalon/cls/OcuTalon/Install/Step/Approvals.cls` (new): the Reconcile declaration.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Approval.cls` (new): eleven tests; `Test/Install/Registry.cls`, `Test/Install/Production.cls`, `Test/Bridge/Api.cls`, `Contracts.cls`, `ProbeSink.cls`, `Time.cls`: the shared surfaces.

**Review.** 36 triage rows from four layers. Patches applied: 3 (two medium, one low), all test-only: the given fields are compared with a snapshot taken before Raise, `TestCallerSession` gains the context-plus-arguments cases (c) and (d), and `TestReconcilePastExpiry` asserts its AlarmRequest. Deferred: none. Rejected: 33, each with its reason in the Review Triage Log. One finding of the first fresh `shard lane-a` (an `^Ens.Alarm` entry read before `Ens.Alarm` stored it) was fixed in the test before review (Decided in-stage).

**Follow-up review recommended:** false (no high patched, two medium patched, both in tests).

**Verification.**
- `bash ci/checks.sh`: all scripts passed (after the last patch).
- Warm `e3s4iw`: the ten classes of the Verification list passed in the handoff; after the review patches `Test.Bridge.Approval` passed, with the two new mutations red and green again after the revert (tree byte-identical, `git diff --stat` unchanged).
- Fresh `e3s4i`: `shard lane-a` passed (44 classes, 396 s, after the last patch; the first run failed on the alarm race above and was fixed); `shard lane-b` passed (24 classes); `live install-start`, `install-upgrade`, `audit`, `production`, `production-restart`, `storage-roundtrip` and `demo-path` passed (run before the three test-only review patches; none of them runs `Test.Bridge.Approval`). Teardown left nothing tagged `e3s4i` or `e3s4iw`.
- Matrix Test Audit: rows 1 and 2 are `TestApprovalsWorkflow` and `TestApprovalsWorkflowRepaired`, rows 3 to 14 are the tests of `Test.Bridge.Approval` named in Tasks; all ran and passed.

**Residual risks.**
- The timer is whole seconds rounded down, so it can fire up to 1 s before `ExpiresAt`; Story 3.5's handler must not depend on the clock being past `ExpiresAt`.
- `LiveHold` scans `ApprovalHold` by Ref (no index; `wontfix-accepted`, reopen_if the row count passes a few thousand).
- Reconcile and a concurrent Raise are not serialized (a window of milliseconds at start).
- Raise inside an open transaction fails closed with the hold's "no approval request" error.
- Epic 13: the bridge example's production has none of the three approval items.
