---
title: 'Story 3.1: Roles and the service user grant only what the architecture lists'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: 'f14712cab091e4f6409d1087e89ec2fd75916017'
baseline_commit: 'f14712cab091e4f6409d1087e89ec2fd75916017'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-2, AD-10, AD-11, AD-19, AD-23, AD-24, AD-26 and AD-29, and the Agent step labels, Tool classification and Tests rows of Consistency Conventions)'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon's roles are composed from the areas' `Grants()`, but nothing creates the service user `OcuTalonService`, no tool's `RESOURCES` reaches any role, nothing stops a declaration from granting a forbidden privilege, and the Users step always creates the README admin account and never the online demo's public accounts or their pinned Visual Trace page size.

**Approach:** Extend the Lane A installer in three places. The Roles step refuses AD-24's forbidden resources and clears granted roles, and a new declaring area, `OcuTalon.Install.Step.Tools`, turns each built-in tool's `RESOURCES` into grants for the service user's role. The Users step creates the login-disabled service user on every start, then reads the online-demo flag and the published accounts through `OcuTalon.Data.Public.Settings`: with the flag off it creates the README account, and with it on the two public accounts, with AD-24's roles and their page size pinned to 100.

## Boundaries & Constraints

**Always:**
- The steps are idempotent and run on every start, install and upgrade.
- Structural values, rewritten on every start:
  - the roles: their resources exactly the declared union, and no granted roles;
  - the service user: login disabled, holding exactly `OcuTalonServiceRole`;
  - the two public accounts: their published password, exact roles and flags, and the page-size pin.
- Seed values, created when absent and never changed afterwards:
  - the README account (unchanged behaviour on a local install; with the flag on it is never created, and an existing one is disabled, see matrix row 9);
  - the service user's random password.
- Every failure is a `%Status` that names the area, role, key or class at fault. Each check runs before anything is applied, so a refusal changes nothing.
- The user step reads the flag and the accounts only through `OcuTalon.Data.Public.Settings.Get`.
- Destructive tests (roles, users, resources) run only on throwaway stacks through `ci/iris.sh`. Every test restores the security objects and public keys it changed: the trace role's resources, the public keys, and the fixture users, roles, resource, areas and `^EnsPortal.Settings` nodes.

**Never:**
- No edit to a contended path: `Install/Step/Demo.cls`, `Install/Step/Schedule.cls`, `Test/Web/**`, `Test/Demo/**`, `docker/**` (including `docker/tests/**`), `ci/compose.ci.yml`, `.github/**`, `README.md`.
- No new step in `Registry.Order()`. The 15-step order and `lib-live.sh`'s `expected_run` stay as they are.
- No OcuTalon role holds `%All`, `%Development`, `%Ens_MessageEditResend`, `%Ens_MessageDiscard`, `%Ens_ProductionRun`, `%Ens_ProductionConfig` or `%Ens_WorkflowConfig`.
- No account this story creates is a Workflow user or a Workflow role member.
- No README account is created with the flag on.
- No grant goes to the public accounts beyond AD-24's roles.
- No role, user, resource or security change, and no test run, on `ocutalon-slot-a`. Loading and compiling code there is fine.
- No `GetEnviron` in the Users step.
- No absolute local path in a tracked file.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1 Service user created | `OcuTalonService` absent | The Users step creates it: `Enabled` 0, `ChangePassword` 0, `PasswordNeverExpires` 1, `AccountNeverExpires` 1, roles exactly `OcuTalonServiceRole`, and a random 44-character password (non-empty hash). | The status of `Security.Users.Create` is returned. |
| 2 Service user drifted | Enabled by hand and given an extra role | The next run sets `Enabled` 0 and roles exactly `OcuTalonServiceRole`. The password hash is unchanged. | The status of `Modify` is returned. |
| 3 Tool resources reach the service user (Integration) | A fixture area returns `Tools.GrantsOf` of the fixture toolset: per-tool `RESOURCESALPHA="ZzOcuTalonGrantProbe:U"`, class-level `RESOURCES="ZzOcuTalonGrantProbe:R"` for `beta`, and `RESOURCESGAMMA=""` | After `Roles.Run()`, the service role holds `ZzOcuTalonGrantProbe:RU`. `$SYSTEM.Security.CheckUserPermission("OcuTalonService","ZzOcuTalonGrantProbe",p)` is 1 for `"U"` and for `"R"` (one letter per call) and 0 for `"W"`. After the fixture area is deleted and `Roles.Run()` runs again, `"U"` gives 0. | No error expected |
| 4 Malformed `RESOURCES` | A value without `:`, with an empty resource name, or with a permission not made of R, W and U | `GrantsOf` and `Parse` throw a status that names the class and the tool. `Roles.Run()` then fails naming the area, and no role changes. | The step fails, so the start fails closed. |
| 5 Forbidden grant | An area's `Grants()` names `%Ens_MessageDiscard:U` for an `OcuTalon*` role | `Roles.Run()` fails with a status naming the area, the role and the resource. No role is created or changed. | Step error |
| 6 Hand-added privilege | A fixture role is given `GrantedRoles="%Developer"` and an extra resource | The next `Roles.Run()` leaves it with exactly its declared resources and `GrantedRoles` empty. | No error expected |
| 7 Trace role, demo off and on | The trace role holds the OCUORDERS database grants | `Roles.Run()` leaves exactly the six OCUTALON grants (Use on the four `%Ens_` resources, Read on `%DB_OCUTALON_DATA` and `%DB_OCUTALON_CODE`). The Demo step's own composition, `Demo.WithOrders(r,1)` (fixture grants until Story 4.1), gives exactly those plus `%DB_OCUORDERS_CODE:R` and `%DB_OCUORDERS_DATA:R`. `WithOrders(r,0)` gives no OCUORDERS grant. | No error expected |
| 8 Flag off | `onlineDemo` is 0 | `Accounts(readme)` creates the README account (seed) with the three roles and creates no public account. | The status of `Ensure` is returned. |
| 9 Flag on | `onlineDemo` 1, with the demo and read-only names and passwords set through `Settings.Set` | The demo account holds exactly `OcuTalonTraceViewer,OcuTalonUser`, and the read-only account exactly `OcuTalonTraceViewer`. A hand-added `OcuTalonAdmin`, a changed password and changed flags are restored on the next run. `^EnsPortal.Settings(name,"VisualTrace","ItemsPerPage")` is 100 in OCUTALON and in OCUORDERS (where that namespace exists). No README account is created; an existing one is disabled (`Enabled` 0; its roles and password unchanged) and the step warns, so the README's published password never signs in on a flag-on instance. | No error expected |
| 10 Flag on, bad accounts | A name or password is empty; the two names are equal (ignoring case); a name equals `OcuTalonService`; or a name is an existing account that the step did not create (its `FullName` is not the step's marker `OcuTalon online-demo account`, for example `_SYSTEM`) | The step fails with a status naming the key or the clash. No account is created or changed. | Step error |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls` -- `Add` (:35-54) validates the role prefix, the resource and the permission, and gains the forbidden check after the name check. `Apply` (:57-83) uses `Create(role,desc,resources)` and `Modify` with `Resources` only, and gains `GrantedRoles` "" on both paths. `Modify` replaces the whole list (measured, `irissys/Security/Roles.cls:256`).
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls` -- holds `USER`, `PASSWORD`, `ROLES`, `Grants()` (two entries, kept) and `Ensure` (seed, kept). `Run()` (:18-21) changes.
- `src/ocutalon/cls/OcuTalon/Install/Step.cls` -- the area contract (`Grants()`, `Warn`).
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls` -- `Areas()` (:20) discovers any `OcuTalon.Install.Step.<Name>`. `Declared` (:97) turns an exception in `Grants()` into an error naming the area. The order (:14) is unchanged.
- `src/ocutalon/cls/OcuTalon/Install/Step/Web.cls` -- read only. `Grants()` (:78-81) is the trace role's six entries, and `GrantTraceSql` (:274) grants SELECT on `Ens.MessageHeader`. AD-23 gives the Web step to Lane B, so it is not edited.
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` -- read only, contended. `WithOrders(resources,on)` (:145) is pure. The step re-adds the OCUORDERS database grants (:279-290) and the OCUORDERS SQL SELECT (:476) after Roles on every start with demo mode on, and removes them with it off (:318-355).
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- read only (Lane B). `Get(key,.sc)` and `Set`. Keys: `onlineDemo`, `demoUser`, `demoPassword`, `readonlyUser`, `readonlyPassword`.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` -- `LabelFor` (:154-166) applies the suffix rule (`$ZConvert($Translate(name,"_-"),"U")`). It is the sibling that the new `ToolParameter` extends.
- `src/ocutalon/cls/OcuTalon/Tools/` -- the toolsets are `Reminders` (ReminderTools: set, list and cancel reminder) and `Watch` (WatchFixture). Neither declares `RESOURCES` today. `ReminderTools.cls:24-40` is the per-tool parameter pattern.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls:659-672` -- `ToolClasses` is the test's own, independent scan of `OcuTalon.Tools.`; it is not reused (see Design Notes). `:106` is the callback rule (a fixture tool refers to `%AI` only on its Class line). `OcuTalon.Test.Bridge.Source.Text(class,.text)` reads class source.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`
  - It has the fixture-area machinery: `Create(xdata,class,n,...)`, `RolesBefore`/`RemoveNewRoles` (:402-424), and the XData `FixtureArea` and `FixtureBad` (:487, :582).
  - Both fixtures grant `%Development:U`, which becomes forbidden, so they change to `%Ens_Portal:U`.
  - `TestRolesStep` (:102) strips the Demo step's OCUORDERS grants from the trace role and never restores them.
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` -- its fixture users are `ZzUsers<n>`, and `Clean` deletes users and roles by the prefix. `TestDeclarations` (:98) pins `Grants()` at size 2.
- Shared assertions that must stay green without edits:
  - `Test/Web/Install.cls:99-137` (lane-b): exactly 6 trace-role declarations, exactly 2 for User and Admin, and none forbidden;
  - `docker/tests/lib-live.sh:486-524` `check_security` (the three roles and user `ocutalon`), `:575-581` `expected_run`, and `:683-717` `demo_surfaces`, compared across restarts in `test-install-start.sh`;
  - `test-install-upgrade.sh:145-170`, the README account's fingerprint.
- `ci/units.sh:17` -- `Install` is already in the `lane-a` shard, so new `Test/Install/*` classes join it with no edit.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 -- on the stage's own warm throwaway (an `iris session` in its container, with a fixture user created and deleted there; never on the slot), measure two things and record each result under Design Notes:
  - whether `##class(Security.Users).CheckPassword(.userObject, password)` returns 1 for the current password and 0 for a wrong one, without changing the user's `InvalidLogins` count;
  - whether `Security.Roles.Create` and `Modify` refuse a resource that does not exist.

  The check for a restored password takes the first of these that works:
  - (a) `CheckPassword`;
  - (b) `$SYSTEM.Security.ChangePassword(user, published, published, .sc)` returning 1;
  - (c) `PasswordChangedDateTime` advancing (labelled weaker).
- [x] `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls`:
  - Add `ClassMethod ToolParameter(toolClass, name, base) As %String`. It returns the tool's own parameter `base_<NAME>` when the compiled class defines it, even if the value is empty; else `base` when defined; else "". "Defined" is tested with `%Dictionary.CompiledParameter`.
  - `LabelFor` calls it. Its result is unchanged for every class today. It references only `%Dictionary`.
  - Why: one suffix-rule reader that the installer and Story 3.2's gate share (Rule 2).
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls`:
  - Add `Parameter FORBIDDEN = "%All,%Development,%Ens_MessageEditResend,%Ens_MessageDiscard,%Ens_ProductionRun,%Ens_ProductionConfig,%Ens_WorkflowConfig"`. In `Add`, refuse a listed resource, matched case-insensitively, with an error naming the area, role and resource.
  - In `Apply`, every role is created or modified with `GrantedRoles` "".
  - Why: AD-24's list becomes a fail-closed refusal at install, not only a test.
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Tools.cls` (new; it declares and does not run):
  - `Toolsets()`: the compiled, non-abstract `OcuTalon.Tools.*` classes that extend `%AI.ToolSet`, sorted.
  - `Parse(value, where) As %DynamicArray`: `resource:permission[,resource:permission...]`, where the permission is one or more of R, W and U. An empty value gives `[]`. A malformed pair throws a status naming `where`.
  - `GrantsOf(toolsets As %List) As %DynamicArray`: for each toolset, `%New().%Discover().tools`. For each `{provider, name}`, `Parse(StepBuffer.ToolParameter(provider, name, "RESOURCES"), provider_" "_name)`, giving one `{"role", "resource", "permission"}` per pair, with duplicates removed, plus the entry that declares the role alone. The role is `##class(OcuTalon.Install.Step.Users).#SERVICEROLE`.
  - `Grants()` is `GrantsOf(..Toolsets())`.
  - Why: AC 1. The service user's grants come from each tool's `RESOURCES`.
- [x] `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls`:
  - Add the parameters `SERVICEUSER="OcuTalonService"`, `SERVICEROLE="OcuTalonServiceRole"`, `DEMOROLES="OcuTalonUser,OcuTalonTraceViewer"`, `READONLYROLES="OcuTalonTraceViewer"` and `TRACEPAGESIZE=100`.
  - `Run()` becomes `Quit ..Accounts(..#USER)`.
  - `Accounts(readmeUser)`, in this order, so that a refusal changes nothing:
    1. Read `onlineDemo` through `Settings.Get`; an error status fails the step.
    2. Flag on: read the four account keys and validate them all (matrix row 10).
    3. `EnsureService()`: create the service user once with `$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(32),1)`, `Enabled` 0, the service role and the flags of matrix row 1. When the user exists, `Modify` sets `Enabled` 0 and the roles.
    4. Flag off: `Ensure(readmeUser, PASSWORD, ROLES)`.
    5. Flag on: `EnsurePublic(name, password, roles)` creates or modifies each account with the password, exact roles, `FullName` set to the marker `OcuTalon online-demo account`, `Enabled` 1, `ChangePassword` 0, `PasswordNeverExpires` 1 and `AccountNeverExpires` 1. `PinTrace(name)` sets `^|ns|EnsPortal.Settings(name,"VisualTrace","ItemsPerPage")=..#TRACEPAGESIZE` for `OCUTALON`, and for `OCUORDERS` when `%SYS.Namespace.Exists` is true. If the README account exists, set its `Enabled` to 0 (roles and password unchanged) and `Warn` names it.
  - Why: AC 1 and AC 4.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/ZzGrantTools.cls` (extends `OcuTalon.Tools.Result`; methods `Alpha`, `Beta` and `Gamma` return `..Return({})`; parameters as in matrix row 3, with `STEPLABEL` set) and `src/ocutalon/cls/OcuTalon/Test/Install/ZzGrantToolset.cls` (an `%AI.ToolSet` whose XData names `alpha`, `beta` and `gamma`) -- new committed fixtures. They refer to `%AI` only on the Class line (CodeRules).
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Tools.cls` (new) -- tests:
  - `Parse`: valid input, several pairs, empty, and each malformed form;
  - `GrantsOf` of the fixture toolset: the per-tool value wins, the class value is the fallback, and a defined empty value gives nothing;
  - `ToolParameter`, and `LabelFor` unchanged for `ReminderTools`;
  - the real `Grants()`: no throw; every entry names `OcuTalonServiceRole`; the role-alone entry is there; `Toolsets()` holds `OcuTalon.Tools.Reminders` and `.Watch` and no `OcuTalon.Test.*` class.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`:
  - Fixture changes: switch both fixtures to `%Ens_Portal:U`. `OnBeforeAllTests` saves the trace role's resources and creates the resource `ZzOcuTalonGrantProbe` (public permission 0); `OnAfterAllTests` re-runs `Roles.Run()`, restores the saved trace-role resources and deletes the probe resource. `TestRolesStep` expects `%DB_USER:RW,%Ens_Portal:U`.
  - New tests for matrix rows 3, 5, 6 and 7.
  - `TestTraceRoleSql`: the trace role's rows in `Security.SQLPrivileges` are exactly SELECT (`s`) on `1,Ens.MessageHeader` in OCUTALON (after `Web.GrantTraceSql()`), and in OCUORDERS once a missing one is fixture-granted there. The test removes only what it added.
  - `TestEveryRole`: every `OcuTalon*` role holds no `FORBIDDEN` resource and no granted roles, and the trace role holds no `%DB_OCUTALON_PRIVATE` or `%DB_OCUTALON_PUBLIC`. The README account, the service user and the fixture public accounts appear in neither `EnsLib_Workflow.UserDefinition` nor `EnsLib_Workflow.RoleMembership`, in OCUTALON or OCUORDERS. No account's roles hold `%Ens_WorkflowConfig`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` -- extend it with tests for matrix rows 1, 2 and 8 to 10:
  - The fixture README name is `ZzUsers<n>Readme`, the public names are `ZzUsers<n>Demo` and `ZzUsers<n>Ro`, and the passwords are like `Zz-demo-pw-1`.
  - The five public keys are saved before each test and restored after it.
  - `Clean` also kills the `^EnsPortal.Settings("ZzUsers*")` nodes in OCUTALON and OCUORDERS.
  - Row 9 also creates the fixture README account first (flag off), then turns the flag on and asserts that the account is disabled with its roles unchanged; and it asserts that OCUORDERS exists on the stack, and that for each public account `CheckUserPermission(account, <resource of the database that GetGlobalDest gives for EnsPortal.Settings in each namespace>, "W")` is 0.
  - `TestNoEnvironment`: `Source.Text("OcuTalon.Install.Step.Users")` holds no `GetEnviron`.
  - `TestDeclarations` also pins the new parameters.

**Acceptance Criteria:**
- Given a fresh throwaway stack, when it starts (`ci/iris.sh shard lane-a`), then the after-start's `STEP Roles OK` and `STEP Users OK` lines show that the new Tools area and service user install at first start, and every lane-a class passes. `ci/iris.sh live install-upgrade` passes too, with the README account's fingerprint and `check_security` unchanged (AC 1, AD-23).
- Given the trace role after `Roles.Run()`, `Web.GrantTraceSql()` and the Demo step's fixture grants, when its grants are listed, then it holds exactly AD-24's resources and exactly SELECT on `Ens.MessageHeader` in OCUTALON and OCUORDERS, and nothing in a private database. Without the fixture grants it holds no OCUORDERS grant (AC 2). Lane B's existing `install-start` live script still checks the demo-off removal end to end.
- Given every `OcuTalon*` role and every account this story creates, when `TestEveryRole` inspects them, then none holds a forbidden resource or granted role, and none is a Workflow user or Workflow role member (AC 3, AD-11, AD-24).
- Given the flag and the accounts set through `Settings.Set` on the test stack, when `Users.Accounts` runs, then matrix rows 8 to 10 hold, and the Users step's source holds no `GetEnviron` (AC 4, AD-19, AD-24).
- Given lane-b's `Test.Web.Install` and Lane B's live scripts, when the fresh `shard lane-b`, `live install-start` and `live sign-in` runs pass with no edit to those files, then the shared Grants and security surfaces are intact.

### Review Findings

Code review of 2026-10-24 (bmad-code-review; layers blind-hunter, edge-case-hunter, verification-gap and acceptance-auditor, all on the session's model; plus the lead's L1 to L3 and the reviewer's own Rule 2 check). 32 rows, grouped into 16 entries: high 0, medium 3, low 13. 11 patched, 5 closed in the ledger, 10 rows rejected.

- [x] [Review][Patch] (medium, lead ruling L1, security posture) With the flag turned from 1 to 0 on a kept volume, the two public accounts stayed enabled with their published passwords -- the flag-off path of `Accounts` now runs `DisablePublic`: every account whose `FullName` is `MARKER` and that is enabled gets `Enabled` 0, nothing else changed, never deleted, and `Warn` names it; `DisableReadme` and `DisablePublic` share one `Disable` [src/ocutalon/cls/OcuTalon/Install/Step/Users.cls:79]; `TestFlagOffDisablesThePublicAccounts`; mutation recorded. fix-risk low: one query and a loop over the marked accounts.
- [x] [Review][Patch] (medium, L2 + edge-case-hunter + verification-gap + acceptance-auditor) A resource the instance lacks failed the Roles step with IRIS's own `#892`, naming neither the area nor the role, and only after the roles that sort before it had been rewritten -- `Roles.Add` checks that the resource exists, so the refusal names the area, role and resource before any role is touched [src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls:59]; `TestUnknownResourceFailsTheStep` now asserts the three names and that a role sorting first keeps a grant added by hand; mutation recorded. fix-risk low: every resource that a `Grants()` declares exists before Roles runs (the CPF merge and IRIS's own).
- [x] [Review][Patch] (medium, blind-hunter + verification-gap, Rule 19) Row 1's "random password" assertion compared hash and salt of two users, which differ for any password (the salt is random per `Create`), so `EnsureService` with a constant password stayed green -- the assertion is replaced by a known-`NewPassword` fixture step (`ZzUsersPins.NewPassword`) and `PasswordOk`, and `TestNewPassword` keeps pinning the generator [src/ocutalon/cls/OcuTalon/Test/Install/Users.cls:216]; mutation recorded. fix-risk low.
- [x] [Review][Patch] (low, blind-hunter + edge-case-hunter + acceptance-auditor) An escalation role added by hand to a public account or the service user survived every start (measured: a `Modify` of `Roles` alone keeps `EscalationRoles`, and `%Service_EscalateLogin` is public Use) -- both `Modify` branches clear `EscalationRoles` [src/ocutalon/cls/OcuTalon/Install/Step/Users.cls:117]; drift cases in `TestPublicAccountsWithFlagOn` and `TestServiceUserDriftIsRepaired`; mutations recorded.
- [x] [Review][Patch] (low, blind-hunter + verification-gap) `TestDeclarations` did not pin the persisted `MARKER` literal or `TRACENAMESPACES`, so a reworded marker (which turns a kept volume's public accounts into foreign ones) stayed green [src/ocutalon/cls/OcuTalon/Test/Install/Users.cls:181]; mutation recorded.
- [x] [Review][Patch] (low, blind-hunter + edge-case-hunter) A published password that the instance refuses was reported under the name key only (`demoUser`) -- the error names both keys of the account [src/ocutalon/cls/OcuTalon/Install/Step/Users.cls:91]; `TestApplyFailuresNameTheUserAndTheKey` asserts `demoPassword`; mutation recorded.
- [x] [Review][Patch] (low, blind-hunter + verification-gap, hermeticity) Four Users tests change the real `OcuTalonService` by hand and put it right only with their own last call -- `OnAfterOneTest` runs `EnsureService` when the user exists [src/ocutalon/cls/OcuTalon/Test/Install/Users.cls:91].
- [x] [Review][Patch] (low, verification-gap) `AssertPublic` read a just-created account without the class's own wait for the hash before `CheckPassword` -- it waits (`Account(name, 1)`) [src/ocutalon/cls/OcuTalon/Test/Install/Users.cls:626]. (DW-9's flake was the `|` split, so the delay itself is unmeasured.)
- [x] [Review][Patch] (low, verification-gap) The OCUORDERS half of AC 3's Workflow check had no control -- `TestWorkflowCheckCountsAWorkflowUser` saves and counts a Workflow user in OCUTALON and in OCUORDERS [src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:654]; mutation recorded.
- [x] [Review][Patch] (low, acceptance-auditor) `TestEveryRole` checked the accounts' resources for `%Ens_WorkflowConfig` only, while AC 3 names all seven -- it checks the seven [src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:582].
- [x] [Review][Patch] (low, edge-case-hunter) `ToolParameter`'s comment wrote the per-tool name as `base_<NAME>`, which reads as an underscore -- it says "base followed by NAME, with no separator" with an example [src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls:163].
- [x] [Review][Defer] (low, reviewer's Rule 2 check) DW-8's `reopen_if` is met: `Test.Install.Registry.Clean` now deletes `ZzRegistry` users by prefix, a fourth copy of the %SYS fixture helper [src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:767] -- deferred: occurrence on DW-8, re-closed wontfix-accepted (the one fixture class spans Lane B's `Test/Web`), reopen_if a fifth test class repeats it. The Design Notes line "DW-8's reopen_if stays unmet" is superseded by that trailer.
- [x] [Review][Defer] (low, L3) `Security.Users.Create` and `Modify` accept a role that does not exist (measured), and `EnsureService`'s "the role must exist" is not checked [src/ocutalon/cls/OcuTalon/Install/Step/Users.cls:109] -- deferred: DW-165, wontfix-theoretical (Roles runs before Users and makes the role; a missing role grants nothing).
- [x] [Review][Defer] (low, acceptance-auditor) AD-24's "no services" is not enforced against a later `%Service_` declaration -- deferred: DW-166, wontfix-theoretical (login disabled closes every service; no tool declares `RESOURCES` yet).
- [x] [Review][Defer] (low, acceptance-auditor) A Workflow user or membership added by hand for a public account is never taken away by a start -- deferred: DW-167, wontfix-theoretical (fresh online-demo volume; Story 3.4 owns `OcuTalonApprovals`' exact membership).
- [x] [Review][Defer] (low, edge-case-hunter) An `OcuTalon*` role that no area declares is left as it is [src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls:76] -- deferred: DW-168, wontfix-theoretical (no release has shipped, so no volume holds a dropped role).

Rejected:
- `false` (verification-gap, acceptance-auditor) `ZzUsersPins.cls` is untracked -- QA's and the review's files are uncommitted by protocol; the lead's commit carries them (it is listed under Files Modified).
- `false` (acceptance-auditor) the `TestEveryRole` mutation's reason ("`Install/Step/Web.cls` is a contended path") is inaccurate -- the epic's footprint gives `Install/Step/Web.cls` to Lane B (AD-23), so it is contended for this story.
- `by-design` (acceptance-auditor) a password that the instance's policy refuses fails after the service user is applied, against "each check runs before anything is applied" -- recorded under Decided in-stage at implement (the step does not call `ValidatePassword` ahead); the fix would edit the spec.
- `low` (verification-gap) `TestTraceRoleGrants`' private-database assertion cannot fail unless the exact-six equality does -- redundant, not vacuous: the equality is row 7's pin, with its mutation.
- `low` (verification-gap) `$ListLength(roles) >= 4` in `TestEveryRole` is a weak control -- the recorded mutation (a forbidden grant for the service role) shows the scan reaches the service role.
- `low` (edge-case-hunter) two tools that spell one resource in different case give two entries -- IRIS folds the case of resource names (measured), declarations are committed code, and the worst case is a lost permission, which the gate denies.
- `low` (edge-case-hunter) the page size is pinned under the setting's spelling of the name -- the step makes the account from the same setting, and the online demo is a fresh volume.
- `low` (edge-case-hunter) `CheckPrivilege` answering an error status would make `TestTraceRoleSql` grant and revoke the real grant -- no such answer was shown; the fix adds a guard.
- `low` (blind-hunter) SQL privileges granted by hand straight to a public account are not cleared -- nothing grants SQL to a user, and the fix is a revoke pass with branches.
- `low` (edge-case-hunter) an `ExpirationDate` set by hand on a public account is not cleared -- it only stops that account's sign-in (fails closed) and grants nothing.

## Spec Change Log

- 2026-10-24, lead spec gate (unattended ruling, veto window: security posture): with the flag on, an existing README account is disabled (roles and password unchanged) and the step warns, instead of being left as it is (matrix row 9, Boundaries, Users task, Users test row 9, mutation table). The first-start OCUORDERS page-size pin is routed to Story 3.8's `Public` step (DW-160, routed by spec_gate). The `RESOURCES` grammar and the service role's name are recorded as the spine's Consistency Conventions row "Tool resources" (Rule 20).
- 2026-10-24, lead ruling at review (unattended, veto window: security posture; product default 3, keep the safe behaviour): the implement stage's wontfix-accepted "the public accounts are not retired when the flag goes back to 0" is replaced. With the flag off, the Users step disables (`Enabled` 0, nothing else changed) every account that carries the step's online-demo marker `FullName`, and warns naming it; no account is ever deleted (matrix row 8's flag-off path; `Users.DisablePublic`, `TestFlagOffDisablesThePublicAccounts`).

## Review Triage Log

### 2026-10-24 -- Review pass
- verdicts: 31 findings -- high 0, medium 4, low 19, false 7, maybe-false 1 (a finding that two or more layers reported is one row; layers: B = blind-hunter, E = edge-case-hunter, V = verification-gap, I = intent-alignment)
- findings:
  - `[low]` `[patch]` (B, E, V, I) `LabelFor` sent a defined-but-empty `STEPLABEL<NAME>` to the generic label, where it used to fall back to the class's `STEPLABEL`, and no test pinned either -- `LabelFor` keeps the class fallback (`ToolParameter` keeps "defined wins" for the other bases); `ZzGrantTools` gains an empty `STEPLABELGAMMA`; `TestLabelForIsUnchanged` pins it; mutation recorded.
  - `[low]` `[reject]` (B, V) `ToolParameter` answers "" for any read failure, so an unreadable class "declares nothing" -- the class comes from the toolset's own discovery, so it has compiled; the spine row says an undeclared parameter declares nothing; wontfix-theoretical, and Story 3.2 owns the gate's handling of an unreadable class.
  - `[low]` `[reject]` (B) the README account is disabled last, so a failure earlier in `Accounts` leaves it enabled -- a failed step fails the start (the instance is not ready), the online demo's fresh volume holds no README account (AD-25), and the order is the spec's step 5 (by-design).
  - `[low]` `[reject]` (B, E, I) the public accounts are not retired when the flag goes back to 0 or a name changes -- outside the matrix and the Boundaries; the online demo is a fresh flag-on volume that is never flipped (AD-25). wontfix-accepted, reopen_if: a deployment turns `onlineDemo` from 1 to 0 on a kept volume. Named under residual risks for the lead (security posture).
  - `[low]` `[patch]` (B, E, V, I) "every check runs before anything is applied" was overstated: a public name equal to a role (measured error #942) and a policy-rejected password fail at the call, after the service user is applied -- `PublicAccounts` now refuses a name that is a role (`TestPublicAccountsRefused`, case "names the role"), the class comment states the limit, and `TestApplyFailuresNameTheUserAndTheKey` pins that a refusal by the instance names the user or the key; the password-policy case stays at the call (S17's routine would apply to a pre-check as well).
  - `[medium]` `[patch]` (B, V, I) the "password is random" assertion compared hash and salt of two users, which differ for the same password, and nothing checked the 44 characters -- `Users.NewPassword()` is the generator; `TestNewPassword` pins 44 characters and a different value per call; `TestServiceUserIsCreated` asserts the README's published password is not the service user's; mutations recorded.
  - `[low]` `[reject]` (B) the Tools area can grant any resource outside AD-24's seven -- AD-24's Rule is the deny-list and tool declarations are committed code (Story 3.2's gate checks them); by-design.
  - `[false]` `[reject]` (B, E, V) the tests fail where OCUORDERS does not exist -- the spec requires asserting it, every stack since Story 0.10 creates it (the lane-a and lane-b shards and the live scripts passed), and a missing one fails the precondition assertion first.
  - `[low]` `[patch]` (B) the `PinTrace` comment promised a caller in Story 4.1 -- reworded to say the method is idempotent and can be called again.
  - `[low]` `[patch]` (B) the `SERVICEUSER` comment said "no services", which the code neither sets nor checks -- the comment now says what the step makes structural.
  - `[low]` `[reject]` (E) a toolset whose `%New` gives no object throws `<INVALID OREF>` naming only the Tools area -- a guard for a state not shown; the failure is loud and fails the start closed.
  - `[low]` `[reject]` (E, V) `Toolsets()` answers "" when `GetAllDerivedClasses` fails -- `%AI.ToolSet` exists on every supported image, and the result would remove grants, not add them.
  - `[maybe-false]` `[reject]` (E) a resource with leading or trailing white space passes the `FORBIDDEN` compare -- it would need IRIS to trim a name it refuses as nonexistent (Task 0, error #892) and a committed `Grants()` to carry it (`Parse` refuses white space); at worst low, so rejected.
  - `[false]` `[reject]` (E) the hash is read without the wait after a `Modify` -- `Modify` leaves the hash in place; the wait serves the first read after a `Create`, as in the existing tests; the class ran green in every pass.
  - `[low]` `[reject]` (E) the README warning fires only on the start that disables the account -- later starts have nothing to warn about; the spec says the step warns.
  - `[medium]` `[patch]` (V, I) nothing tested the real `Users.Run()` or the `Accounts` to `EnsureService` wiring, and "the service user is made" could not tell creation from pre-existence -- the flag-off and flag-on tests now enable the real service user by hand with other roles before the second run and expect it put right; `TestRunIsTheStep` runs `Run()`; mutations recorded.
  - `[medium]` `[patch]` (V, I) the path `Tools.Grants()` to `Toolsets()` never met a tool that declares `RESOURCES` (a mutation to `GrantsOf("")` stayed green) -- `Registry.TestToolsAreaFindsABuiltInToolset` compiles a tool and a toolset under `OcuTalon.Tools.ZzProbe<n>`, checks `Toolsets`, `Grants` and the Roles step, and deletes them; mutation recorded.
  - `[low]` `[patch]` (V) the `OcuTalon.Tools.Result` assertion in `TestRealDeclarations` cannot fail -- removed.
  - `[low]` `[reject]` (V) the abstract and uncompiled filters of `Toolsets()` are unpinned -- no abstract toolset exists and the failure would be loud at install; wontfix-accepted, reopen_if: a toolset under `OcuTalon.Tools` is abstract.
  - `[medium]` `[patch]` (V) the apply-phase failures of `Accounts` (`EnsureService`, a public account's `Create` or `Modify`) had no test -- `TestApplyFailuresNameTheUserAndTheKey` (a user named like a role; a two-character password); mutations recorded. The `PinTrace` catch needs a database that rejects writes and stays untested (wontfix-theoretical).
  - `[low]` `[patch]` (V) the control of `TestNoEnvironment` exercised another predicate than the assertion -- replaced by a control that the source was read; mutation re-demonstrated.
  - `[low]` `[patch]` (V) `UserResources` in `TestEveryRole` had no non-empty control -- a control on the demo account's resources added.
  - `[low]` `[reject]` (V) the `""` granted-roles argument of `Create` in `Roles.Apply` has no observable effect (a new role has none) -- the `Modify` path is pinned by row 6.
  - `[low]` `[patch]` (V) pinning tests without a `mutation:` line (row 4, the SQL half of AC 2, row 5's case folding, row 2's unchanged password, row 9's drift and warning, row 10's branches, `ToolParameter`) -- Rule 19 closes it in the pass: each mutation applied, red, reverted, green again; lines written under Verification.
  - `[low]` `[reject]` (V) AC 3's granted-role and Workflow clauses have no mutation of their own -- one demonstrated mutation per AC is the bar and `TestEveryRole` has its line.
  - `[low]` `[reject]` (V) the Users tests need the product start's roles, `TestTraceRoleGrants` reads the trace role before the Roles step, `_SYSTEM` stands for the foreign account, and an exception (not an assertion failure) between create and delete leaves a throwing area for the later tests -- the start's roles are the suite's standing precondition, `_SYSTEM` is the spec's example, and `OnAfterAllTests` cleans by class prefix.
  - `[false]` `[reject]` (I) no production writer exists for the four account keys, and no shipped tool declares `RESOURCES` -- Story 3.8 writes the keys and Stories 7.x declare tools; a flag-on start fails closed at the empty key (row 10) until then.
  - `[false]` `[reject]` (I) `tool.provider` and `tool.name` of an XML toolset and `CheckUserPermission` for a disabled user could not be read from the exports -- settled at runtime: `TestGrantsOf` and row 3 pass on the build 154 stack.
  - `[false]` `[reject]` (I) the refusal of the README account's name as a public name goes beyond row 10 -- recorded under Decided in-stage; it keeps a flag-on start from making an account and disabling it.
  - `[false]` `[reject]` (I) on a first flag-on start the OCUORDERS pin cannot be written by the Users step (Demo runs after Users) -- spec-bound (DW-160, Story 3.8).
  - `[false]` `[reject]` (I) `Registry.OnAfterAllTests` leaves the real roles at their declared composition, not at their earlier state -- the Boundaries list the trace role's resources, the keys and the fixtures; the Roles step rebuilds the rest.

## Design Notes

**Architecture decisions:**
- **AD-23:** the step order, `Grants()` composition, and structural versus seed values (with AD-19).
- **AD-24:** the roles, the service user, the trace role's exact grants, the forbidden list, the public accounts, the page-size pin, and that public accounts are never Workflow members.
- **AD-19:** the flag and the accounts come only through `Data.Public.Settings`.
- **AD-26:** the page size is the viewer's own setting, default 40; 100 for the public accounts.
- **AD-10:** the gate's permission check is this story's consumer.
- **AD-11:** the Workflow role's only member is `OcuTalonWorkflow`, from Story 3.4.
- **AD-2:** the bridge references no other package. The new helper lives in the bridge, and Install calls the bridge.
- **AD-29 and AD-33:** Install is Lane A's; Demo, Web and `Data.Public` are Lane B's, and are read but not edited.
- **AD-22:** destructive tests run on throwaways.

No AC contradicts an AD's Rule.

**Measured at planning** (read-only on `ocutalon-slot-a`, build 154, port 52790, and in `irissys/`):
- **Role and user names.** A role and a user can't share a name: `Users.cls:18`, and `RoleExists` returns error #942, case-insensitively. So the service user's role is `OcuTalonServiceRole`.
- **`CheckUserPermission`:**
  - it ignores `Enabled` (the disabled user `IAM` still returns 1);
  - it follows granted roles and adds public permissions;
  - for an unknown user it returns 0;
  - asking about another user needs `%Admin_Secure:U`;
  - a multi-letter permission is unreliable (`"RW"` returned 1 for a user holding only R), so callers pass one letter per call.
- **Visual Trace page size.** It is `^EnsPortal.Settings($username,"VisualTrace","ItemsPerPage")`, default `MSGPERPAGE` 40 (`EnsPortal/VisualTrace.cls:1149-1159`). In OCUTALON it resolves to `ocutalon_data`, and no mapping exists. `%DB_OCUTALON_DATA` has public permission 0, and the public accounts hold only R on it through the trace role. So the page cannot save a change: a ZEN write without W fails with `<PROTECT>` (inference; tested as no W).
- **Passwords.** The pattern is `3.255ANP` and no validation routine is set. A 44-character `Base64Encode(GenCryptRand(32),1)` passes `ValidatePassword`.
- **"The Workflow inbox".** No resource gates the inbox; it is entered by being a Workflow user (`EnsLib/Workflow/Engine.cls:304-310`). `%Ens_WorkflowConfig` gates the Workflow configuration pages, and every forbidden resource exists on the slot.

**Decided in-stage** (small, reversible, inside AD-24's Rule):
- **Service role name.** The service user's role is `OcuTalonServiceRole`, the measured consequence of AD-24's "the service user's role".
- **`RESOURCES` grammar.**
  - The value is IRIS's own role-resource form, `resource:permission[,...]`. It is found by the suffix rule of the step labels and of tool classification: `RESOURCES<NAME>`, else `RESOURCES`.
  - A defined parameter wins even when it is empty.
  - An undeclared `RESOURCES` declares nothing.
  - Story 7.1's `%Ens_MessageResend` is written `%Ens_MessageResend:U`.
- **Tool inventory.** It is every compiled `OcuTalon.Tools.*` toolset, the agents' only tool source today. Developer and MCP tools get their resources elsewhere (AD-10).
- **The Workflow inbox** is read as `%Ens_WorkflowConfig` in `FORBIDDEN`, plus no Workflow user or membership for these accounts.
- **Fail closed in the Roles step.** It refuses forbidden resources. Step 5's rollback exception (`%Ens_ProductionConfig` W for the service role) will amend `FORBIDDEN` in its own story.
- **SQL privileges stay with the steps that grant them** (Web for OCUTALON, Demo for OCUORDERS), whose own on and off paths keep them exact. Roles rebuilds resources and granted roles only, because a SQL grant is per namespace and not a role property.
- **Public accounts are structural.** They are rebuilt from the public keys, which AD-19 makes structural, and Story 3.8's guard spares the installer's write.
- **The step manages only public accounts it created.** A public name that matches an existing account without the `FullName` marker is refused. So a deployment value can never rewrite the password or roles of `_SYSTEM` or any other user. The online demo's fresh volume holds no such account, so the refusal costs it nothing.
- **The README account stays seed and only for a local install.** On a flag-on instance it is never created, and an existing one is disabled and the step warns (lead ruling at the spec gate, veto window: security posture; the planner's "left as it is" was replaced, because the README publishes its password). The online demo is a fresh flag-on volume (AD-25), so none exists there.
- **The OCUORDERS pin.** It is written where OCUORDERS exists. AD-23 runs Demo after Users, so on a fresh volume's first start the Users step cannot pin OCUORDERS yet; the lead routed the first-start pin to Story 3.8's `Public` step, whose last phase runs after `Production` and `Reconcile` and before `SetReady` (DW-160, routed by spec_gate), so both namespaces are pinned before the instance reports ready. On the online demo every visitor-facing start comes from a golden copy that already holds OCUORDERS, and `TraceLink` reads the stored value (default 40), so no link points at the wrong page (AD-26's Prevents holds). Story 4.1 may call `Users.PinTrace(name)` after it creates OCUORDERS.
- **Copy, by design.** `Tools.Toolsets()` does not reuse `CodeRules.ToolClasses`, because a rule test must scan independently of the product code it checks. The tests extend the existing `Test.Install.Users` and `Registry` classes, and `Test.Install.Tools` repeats no role helper, so DW-8's `reopen_if` stays unmet.

**Task 0, measured at implement** (warm throwaway `e3s1iw`, build 154, in an `iris session` in its container, with a fixture user and role created and deleted there; nothing on the slot):
- **`CheckPassword`.** `Security.Users.CheckPassword(.object, password)`, with the handle from `Exists`, returned 1 for the current password and 0 for a wrong one (twice), and `InvalidLoginAttempts` stayed 0. So check (a) is the restored-password check. The Users test uses it on the public accounts.
- **`ChangePassword`.** `$SYSTEM.Security.ChangePassword(user, published, published, .sc)` returned 1 for the right password and 0 (error #952) for a wrong one. It would also have served as check (b), and (c) is not needed: `Security.Users.Get` returned no `PasswordChangedDateTime` property to compare.
- **Missing resource.** `Security.Roles.Create` and `Modify` both refuse a resource that does not exist, with error #892 "Resource ... does not exist", and a refused `Modify` leaves the role's resources as they were. A tool that declares an unknown resource therefore fails the Roles step with IRIS's own message, and the step needs no existence check of its own.

**Decided in-stage at implement** (small, reversible, inside AD-24's Rule):
- **`EnsureService(user, role)`** takes its two names as optional arguments that default to `SERVICEUSER` and `SERVICEROLE`, and `Accounts` calls it with the defaults. The tests for rows 1 and 2 pass fixture names, so no test deletes or recreates the real service user, whose seed password could not be restored.
- **The README account's name is refused as a public name** (row 10's family). Otherwise a flag-on start with `demoUser=ocutalon` would make the account and then disable it as the README account.
- **Name comparisons are case-insensitive** for the two public names, the service user and the README account, as IRIS user names are.
- **A password the instance refuses** fails at `Create` or `Modify` with a status that names the public key, and not in the validation phase: the step does not call `ValidatePassword` ahead (S17's password-validation routine would apply there too). The service user has been applied by then and no public account has.
- **`Parse` is strict:** upper-case R, W and U only, no white space in a resource name, and an empty pair (`a:R,`) is malformed.
- **The README warning** is written when the step disables the account, and not again on a later start where it is already disabled.
- **`GrantsOf`** lists the role-alone entry first, then each tool's pairs in discovery order, each (resource, permission) pair once.
- **The forbidden check** sits after the role-name check and the comma-and-colon check, before the permission check.
- **Tests read AD-24's list as a literal,** not from `Roles.FORBIDDEN` or `Users.DEMOROLES`, so that emptying or changing the parameter turns them red.
- **Two tests beyond the spec's list:** `Registry.TestMalformedResourcesFailTheStep` (row 4's step failure, with a tool, toolset and area compiled at test time and deleted again) and `Users.TestNoReadmeAccountWithFlagOn` (the pin for row 8's "never created with the flag on").

**Decided in-stage at review** (patches; the reasons are in the Review Triage Log):
- **Compile order.** `Test.Install.Registry` reads three parameters from `Install.Step.Users` and `Install.Step.Web` when it compiles. The first fresh start compiled it before them (`<CLASS DOES NOT EXIST>`, `STEP package FAILED`), which no warm stack shows, because the steps are already compiled there. The class now declares `DependsOn = (OcuTalon.Install.Step.Users, OcuTalon.Install.Step.Web)`.
- **`LabelFor`** keeps its class fallback for an empty per-tool label, so its results are unchanged for every class, an empty one included. `ToolParameter` keeps "a defined parameter wins even when empty" for every other base (`RESOURCES`).
- **`Users.NewPassword()`** is public: the generator of the service user's password, so a test can pin its length and its variation.
- **A public name that is a role** is refused in `PublicAccounts` (a role and a user cannot share a name, measured error #942), before anything is applied.
- **The Registry test's `GrantSelect`** makes the SELECT in OCUORDERS with the system call that `Web.GrantTraceSql` makes, because the Web step's class is not mapped there; OCUTALON keeps the Web step's own call.
- **Tests added at review:** `Users.TestNewPassword`, `TestApplyFailuresNameTheUserAndTheKey` and `TestRunIsTheStep`; `Registry.TestToolsAreaFindsABuiltInToolset` (a fixture tool and toolset under `OcuTalon.Tools.ZzProbe<n>`, removed again and by `Clean`); extra cases in `TestLabelForIsUnchanged`, `TestPublicAccountsRefused`, `TestReadmeAccountWithFlagOff`, `TestPublicAccountsWithFlagOn` and `TestEveryRole`.
- **`TestEveryRole`'s mutation** is applied to `Tools.Grants()`, not `Web.Grants()`, because `Install/Step/Web.cls` is a contended path that this story does not edit; the shape is the same (a declared forbidden grant with `FORBIDDEN` emptied).

**For the lead (Rule 20; the plan does not write the spine):**
- Consider a Consistency Conventions row for the `RESOURCES` grammar (Stories 3.2, 7.1 and 14.1 rely on it).
- Consider noting in AD-24 the role name `OcuTalonServiceRole`, the `%Ens_WorkflowConfig` reading, and the OCUORDERS-pin timing.

**Integration ACs:**
- Matrix row 3 exercises the composed service role through `$SYSTEM.Security.CheckUserPermission`, the exact call that Story 3.2's gate makes.
- Row 7 exercises Lane B's Demo step composition (`WithOrders`) on top of the rebuilt trace role.
- The first OcuTalon code consumer is Story 3.2.

**Consumed-by:**
- **Story 3.2:** the gate checks `OcuTalonService` against `ToolParameter(...,"RESOURCES")`, one letter per call. It needs its own service-user setting, because the bridge can't read `Install`.
- **Stories 7.1 and 7.3:** fix kinds declare `RESOURCES` and an `Install.Step.Fix` area composes them the same way. The executor checks the service user.
- **Story 14.1:** the overview is generated from the same declarations and compared with the installed roles.
- **Story 3.8:** the Public step writes the keys that this step reads. Its password guard must allow the installer's writes and the service user's random password.
- **Story 2.9:** `TraceLink` reads the pinned page size.
- **Story 4.1:** the Demo step adds the OCUORDERS grants after Roles.
- **Epics 16 and 29:** the public accounts.

**Consumes:**
- `Data.Public.Settings.Get` (Epic 0);
- `Registry.Declared` and `Areas`;
- `Web.Grants` and `GrantTraceSql`;
- `Demo.WithOrders` (test fixture);
- `StepBuffer.LabelFor` (extended);
- `Security.Users`, `Roles`, `Resources` and `SQLPrivileges`.

**Ledger inbox** (`LEDGER slice 3-1-roles-and-the-service-user-grant-only-what-the-architecture`): none, so no `DW-n` is addressed or declined.

**Footprint:** every file is in Epic 3's footprint (`Install/**`, `Test/Install/**`, `src/bridge/**`). There is no extension and no contended edit.

## Verification

**Targets:**
- `ocutalon-slot-a` (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154) is used only for `iris_doc_load` compiles. No step, test or security change runs there.
- Everything else runs through `ci/iris.sh` with `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a`, `OCUTALON_TEST_WEB_PORT=52801` and `OCUTALON_LOCK_OWNER='epic=3 stage=implement'`. The fresh tag is `e3s1i` and the warm tag `e3s1iw`; QA uses `e3s1q`/`e3s1qw` and review `e3s1r`/`e3s1rw`.
- One command per call, each with `timeout: 600000`.
- Never `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, slot B or slot C. No push, and never read `.env`.

**Commands** (each with the variables above):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes (`boundaries`, `class-rules`, `ci-config`, `storage`). About 20 s.
- **(loop)** `OCUTALON_RUN_TAG=e3s1i bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `OCUTALON_RUN_TAG=e3s1iw bash ci/warm.sh up`, once before the first warm run. Expected: a ready warm stack.
- **(loop)** `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e3s1iw bash ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Install.Tools`, `OcuTalon.Test.Install.Users`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Bridge.Steps`, `OcuTalon.Test.Bridge.CodeRules` and `OcuTalon.Test.Tools.Reminders`. Expected: `CLASS ... passed` each time, after a `WARM reloaded` line.
- **(loop)** `OCUTALON_RUN_TAG=e3s1iw bash ci/warm.sh down`, at the stage's end and after a failure.
- **(once)** `OCUTALON_RUN_TAG=e3s1i bash ci/iris.sh shard lane-a`. Expected: a fresh start with `STEP Roles OK` and `STEP Users OK`, and every class passed. About 1 minute.
- **(once)** `OCUTALON_RUN_TAG=e3s1i bash ci/iris.sh shard lane-b`. Expected: every class passed, `Test.Web.Install` and `Test.Demo.Step` included.
- **(once)** `OCUTALON_RUN_TAG=e3s1i bash ci/iris.sh live install-start`. Expected: PASS, with the surfaces equal across restarts (the new role and user are stable) and the demo-on and demo-off trace grants. About 3 minutes.
- **(once)** `OCUTALON_RUN_TAG=e3s1i bash ci/iris.sh live install-upgrade`. Expected: PASS (the README fingerprint and `check_security`).
- **(once)** `OCUTALON_RUN_TAG=e3s1i bash ci/iris.sh live sign-in`. Expected: PASS.
- **(once)** `OCUTALON_RUN_TAG=e3s1i bash ci/iris.sh teardown`. Expected: nothing tagged `e3s1i` is left.

**Pinning tests and the mutations to record** (Rule 19; record each as `mutation: ... -> ...` here):

| Pinning test | Mutation that must turn it red |
| --- | --- |
| row 3 (Registry, integration) | `GrantsOf` returns only the role-alone entry |
| row 5 | `FORBIDDEN` emptied |
| row 6 | the `GrantedRoles` reset removed |
| row 7 | the Roles step merges with the role's existing resources |
| rows 1 and 2 | `Enabled` 1 |
| row 9 | `DEMOROLES` gains `OcuTalonAdmin`, or the pin is skipped for OCUORDERS, or the README account is left enabled |
| row 8 | the README account is created with the flag on |
| row 10 | the duplicate-name check removed |
| `TestEveryRole` | `Web.Grants()` temporarily gains `%Ens_MessageDiscard:U` with `FORBIDDEN` emptied |
| `TestNoEnvironment` | a `GetEnviron` call added |

**Mutations recorded at implement** (Rule 19; each applied on the warm stack `e3s1iw`, observed red, reverted so that `git status --short`, the `git diff` hash and the new files' hashes were unchanged, and the class run green again on the same stack):

mutation: `Tools.GrantsOf` returns only the role-alone entry -> Registry `TestToolResourcesReachTheServiceUser` (row 3; `TestMalformedResourcesFailTheStep` also)
mutation: `Roles.FORBIDDEN` emptied -> Registry `TestForbiddenGrantRefused` (row 5)
mutation: the `GrantedRoles` reset removed from `Roles.Apply` -> Registry `TestHandAddedPrivilegeIsRemoved` (row 6)
mutation: `Roles.Apply` merges the role's existing resources into the composed set -> Registry `TestTraceRoleGrants` (row 7; `TestRolesStep`, `TestHandAddedPrivilegeIsRemoved`, `TestForbiddenGrantRefused` and `TestToolResourcesReachTheServiceUser` also)
mutation: `Users.EnsureService` creates and modifies the service user with `Enabled` 1 -> Users `TestServiceUserIsCreated` and `TestServiceUserDriftIsRepaired` (rows 1 and 2; `TestReadmeAccountWithFlagOff` also)
mutation: `Users.DEMOROLES` gains `OcuTalonAdmin` -> Users `TestPublicAccountsWithFlagOn` (row 9; `TestDeclarations` also)
mutation: `Users.TRACENAMESPACES` reduced to OCUTALON, so the pin is skipped for OCUORDERS -> Users `TestPublicAccountsWithFlagOn` (row 9)
mutation: `Users.DisableReadme` leaves an enabled README account enabled -> Users `TestPublicAccountsWithFlagOn` (row 9)
mutation: `Users.Accounts` makes the README account on the flag-on path too -> Users `TestNoReadmeAccountWithFlagOn` (row 8)
mutation: the duplicate-name check removed from `Users.PublicAccounts` -> Users `TestPublicAccountsRefused` (row 10)
mutation: `Roles.FORBIDDEN` emptied and `Tools.Grants()` gains `%Ens_MessageDiscard:U` for the service role (`Web.Grants()` is a contended path, so it is not the one mutated) -> Registry `TestEveryRole` (`TestForbiddenGrantRefused` also)
mutation: a `GetEnviron` call added to `Users.Accounts` -> Users `TestNoEnvironment`

**Mutations recorded at review** (Rule 19; each applied on the warm stack `e3s1iw`, observed red, reverted so that the file's hash was unchanged, and the class run green again on the same stack; the two lines of `TestNoEnvironment` and `TestEveryRole` above were demonstrated again after their tests changed):

mutation: `StepBuffer.LabelFor` drops the class fallback for an empty per-tool label -> Tools `TestLabelForIsUnchanged` (the empty `STEPLABELGAMMA` case)
mutation: `StepBuffer.ToolParameter` lets a non-empty value win instead of a defined one -> Tools `TestToolParameter` (gamma's empty value)
mutation: `Tools.Parse` drops the check of the number of colons in a pair -> Tools `TestParseMalformed` (`ZzRes:R:W`; row 4)
mutation: `Tools.GrantsOf` swallows a malformed value -> Registry `TestMalformedResourcesFailTheStep` (row 4)
mutation: `Tools.Grants()` ignores the toolsets -> Registry `TestToolsAreaFindsABuiltInToolset` (row 3, as the installer finds the area)
mutation: `Roles.Apply` deletes and creates an existing role again before it modifies it -> Registry `TestTraceRoleSql` (AC 2, the SQL half)
mutation: `Roles.Add` compares the resource without folding its case -> Registry `TestForbiddenGrantRefused` (row 5)
mutation: `Users.EnsureService` sets a new password in its `Modify` branch -> Users `TestServiceUserDriftIsRepaired`, `TestReadmeAccountWithFlagOff`, `TestPublicAccountsWithFlagOn` and `TestRunIsTheStep` (row 2, the password stays)
mutation: `Users.EnsureService` creates the service user with `Enabled` 1 -> Users `TestServiceUserIsCreated` (row 1)
mutation: `Users.NewPassword` returns a constant -> Users `TestNewPassword` (row 1, random password)
mutation: `Users.EnsureService` creates the service user with the README's published password -> Users `TestServiceUserIsCreated` (row 1, random password)
mutation: `Users.Run` is the README account's `Ensure` again -> Users `TestRunIsTheStep` (AC 1)
mutation: `Users.Accounts` skips `EnsureService` -> Users `TestReadmeAccountWithFlagOff` and `TestPublicAccountsWithFlagOn` (AC 1)
mutation: `Users.Accounts` returns a public account's status without the key and account -> Users `TestApplyFailuresNameTheUserAndTheKey` (row 9)
mutation: `Users.EnsureService` returns the status of `Create` without the user and role -> Users `TestApplyFailuresNameTheUserAndTheKey` (row 1)
mutation: `Users.EnsurePublic` leaves the password out of its `Modify` branch -> Users `TestPublicAccountsWithFlagOn` (row 9, a changed password is restored)
mutation: `Users.DisableReadme` does not warn -> Users `TestPublicAccountsWithFlagOn` (row 9, the warning)
mutation: `Users.PublicAccounts` drops the check of a name that is a role, of the service user, of the README account or of a foreign account (each alone) -> Users `TestPublicAccountsRefused` (row 10)

**Mutations recorded at QA** (Rule 19; found by mutating the product code against the shipped tests. Two survivors were observed before any new test existed: the order swap in `Users.Accounts` and the flag read as `flag '= 0`; the other new tests pin behaviour that no shipped assertion read. Each mutation below was applied on the warm stack `e3s1qw`, observed red, reverted from a byte copy so that `git status --short` and the hash of `git diff` on `src/ocutalon/cls/OcuTalon/Install` were as before, and the class run green again on the same stack):

mutation: `Users.Accounts` applies the service user before it validates the public settings -> Users `TestRefusalLeavesADriftedServiceUserAlone` (row 10, a refusal changes nothing; the only test that went red)
mutation: `Users.Accounts` reads any flag but 0 as on (`flag '= 0`) -> Users `TestOnlyOneTurnsTheFlagOn` (rows 8 and 9: an unset flag, 0, "yes", "true" and 2 are off)
mutation: `Users.Disable` (which `DisableReadme` calls since the review) drops its exit for an account that is already disabled -> Users `TestADisabledReadmeAccountIsNotWarnedAboutAgain` (row 9, one warning per disabling; demonstrated again at code review, `TestFlagOffDisablesThePublicAccounts` also)
mutation: `Users.EnsurePublic` drops the marker check -> Users `TestEnsurePublicRefusesAForeignAccount` (row 10, at the write)
mutation: `Users.PinTrace` drops the namespace-exists check -> Users `TestPinSkipsANamespaceThatDoesNotExist` (row 9, "where it exists")
mutation: `Users.PublicAccounts` compares the README name with its case -> Users `TestPublicAccountsRefused` (the upper-case README case, row 10)
mutation: `Users.Accounts` drops the status of the README account's `Ensure` -> Users `TestFailureOfEnsureIsReturned` (row 8, the error column)
mutation: `Roles.Add` widens the forbidden match to the first 15 characters of a resource -> Registry `TestNearMissesAreNotForbidden` (row 5, the exact seven; every other test stayed green)
mutation: `Roles.Apply` ignores a refusal by the instance -> Registry `TestUnknownResourceFailsTheStep` (Task 0: an unknown resource fails the step). Superseded at code review: `Roles.Add` now refuses an unknown resource before `Apply` runs, so this test's pin is the code-review line "`Roles.Add` drops the check that the resource exists".
mutation: `Tools.Toolsets` drops the abstract filter -> Registry `TestToolsetsSkipAnAbstractToolset` (Task: "non-abstract")
mutation: `Registry.WorkflowRows` (the test's own query) reads the wrong column -> Registry `TestWorkflowCheckCountsAWorkflowUser` (AC 3, the Workflow clause; `TestEveryRole` stayed green, which is why the control exists)
mutation: `Users.EnsurePublic` also makes the account a Workflow user -> Registry `TestEveryRole` (AC 3, the Workflow clause)
mutation: `Users.Grants()` gives `OcuTalonUser` a resource -> `OcuTalon.Test.Web.Install` `TestGrants`, "OcuTalonUser holds no resource" (AC 5, lane-b's shared surface; the class was run warm and not edited)
mutation: `Tools.GrantsOf` removes duplicates by resource alone -> Tools `TestGrantsOf` and Registry `TestToolResourcesReachTheServiceUser` (row 3, the pairs; no line existed for it)

**Mutations recorded at code review** (Rule 19; each applied on the review's warm stack `e3s1rw`, observed red, reverted from a byte copy so that `git status --short`, the hash of `git diff` and the untracked fixture's hash were as before, and the class run green again on the same stack):

mutation: `Users.Accounts` skips `DisablePublic` on the flag-off path -> Users `TestFlagOffDisablesThePublicAccounts` (lead ruling at review: the public accounts disabled with the flag off)
mutation: `Users.EnsureService` creates the service user with a constant password instead of `NewPassword()` -> Users `TestServiceUserIsCreated` (row 1, the password is the one `NewPassword` makes; the hash-and-salt comparison it replaces stayed green under this mutation)
mutation: `Users.MARKER` reworded -> Users `TestDeclarations` (row 10, the persisted marker)
mutation: `Users.EnsurePublic` drops the `EscalationRoles` reset -> Users `TestPublicAccountsWithFlagOn` (row 9, exact roles)
mutation: `Users.EnsureService` drops the `EscalationRoles` reset -> Users `TestServiceUserDriftIsRepaired` (row 2, exactly the role)
mutation: `Users.Accounts` names only the name key of a refused account -> Users `TestApplyFailuresNameTheUserAndTheKey` (row 9, the password key named)
mutation: `Roles.Add` drops the check that the resource exists -> Registry `TestUnknownResourceFailsTheStep` (the area and the role named, and a role sorting first left as it was)
mutation: `Registry.WorkflowRows` (the test's own query) skips OCUORDERS -> Registry `TestWorkflowCheckCountsAWorkflowUser` (AC 3, the OCUORDERS half of the Workflow clause)

**Files added or changed at QA (QA):**
- `src/ocutalon/cls/OcuTalon/Test/Install/ZzUsersPins.cls` (QA, new): the Users step with a pin list that names a missing namespace; a fixture, not a test case.
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` (QA): `TestRefusalLeavesADriftedServiceUserAlone`, `TestOnlyOneTurnsTheFlagOn`, `TestADisabledReadmeAccountIsNotWarnedAboutAgain`, `TestEnsurePublicRefusesAForeignAccount`, `TestPinSkipsANamespaceThatDoesNotExist`, `TestFailureOfEnsureIsReturned`, an upper-case README case in `TestPublicAccountsRefused`, and `Parameter PINS`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls` (QA): `TestNearMissesAreNotForbidden`, `TestUnknownResourceFailsTheStep`, `TestToolsetsSkipAnAbstractToolset`, `TestWorkflowCheckCountsAWorkflowUser`, the XData `FixtureAbstractToolset`, the helpers `ResourceExists` and `ClearWorkflow` (called by `Clean`).

**QA runs** (tags `e3s1q` fresh, `e3s1qw` warm): the warm stack's after-start log held `STEP Roles OK`, `STEP Users OK` and `RESULT OK`; the Install classes Users, Tools and Registry passed in both orders; `Test.Bridge.CodeRules`, `Test.Bridge.Steps` and `Test.Web.Install` passed; `bash ci/checks.sh` passed; `OCUTALON_RUN_TAG=e3s1q bash ci/iris.sh shard lane-a` passed (42 classes) from a fresh start; `ci/warm.sh down` and `ci/iris.sh teardown` left nothing tagged `e3s1q`.

**Shared surfaces:**
- **The OcuTalon roles:**
  - the trace role's resources, which every test that runs `Roles.Run()` saves and restores;
  - the new `OcuTalonServiceRole`;
  - `GrantedRoles` cleared on every role.
- **`Security.Users`:** gains `OcuTalonService` (seen by `demo_surfaces`; stable across starts).
- **`Registry.Areas()` and `Declared("Grants")`:** gain `OcuTalon.Install.Step.Tools`. `Test.Web.Install`'s counts of trace, User and Admin entries are unchanged, and `TestAreas` has no count.
- **The Registry fixtures' resource:** changes from `%Development` to `%Ens_Portal`.
- **The public keys:** `onlineDemo`, `demoUser`, `demoPassword`, `readonlyUser` and `readonlyPassword`, set and restored by the Users test.
- **`^EnsPortal.Settings`:** fixture nodes, removed by `Clean`.
- **`StepBuffer.LabelFor`:** results unchanged.
- **The search:** search the test trees and `docker/tests` for `Security.Roles`, `Security.Users`, `TraceViewer`, `Grants`, `%Development`, `LabelFor`, `onlineDemo` and `ItemsPerPage`.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The installer now makes the service user `OcuTalonService` (login disabled, exactly `OcuTalonServiceRole`, a random 44-character seed password) on every start. A new declaring area, `OcuTalon.Install.Step.Tools`, turns each built-in toolset's `RESOURCES` parameters into grants of that role, read through the shared `StepBuffer.ToolParameter`. The Roles step refuses AD-24's seven forbidden resources and clears granted roles. The Users step reads the flag and the four account keys through `Settings.Get`: with the flag off it makes the README account as before, and with it on the two public accounts (exact roles and flags, published password, marker `FullName`, page size pinned to 100 in OCUTALON and in OCUORDERS where it exists), no README account, and an existing one disabled with a warning. No tool declares `RESOURCES` yet, so on a real start the service role is created empty.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls`: `ToolParameter` (the one suffix-rule reader); `LabelFor` calls it and keeps its fallbacks.
- `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls`: `FORBIDDEN` refusal; `GrantedRoles` cleared on create and modify.
- `src/ocutalon/cls/OcuTalon/Install/Step/Tools.cls` (new): `Toolsets`, `Parse`, `GrantsOf`, `Grants`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls`: `Accounts`, `EnsureService`, `NewPassword`, `EnsurePublic`, `PinTrace`, `PublicAccounts`, `DisableReadme`; `Run` calls `Accounts`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Tools.cls`, `ZzGrantTools.cls`, `ZzGrantToolset.cls` (new): grammar, grants of a toolset, `ToolParameter`, the real declarations.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`: rows 3 to 7, `TestTraceRoleSql`, `TestEveryRole`, `TestToolsAreaFindsABuiltInToolset`, role save and restore, `DependsOn`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls`: rows 1, 2 and 8 to 10, apply failures, `Run`, `NewPassword`, `TestNoEnvironment`.
- `_bmad-output/implementation-artifacts/spec-3-1-roles-and-the-service-user-grant-only-what-the-architecture.md`: Task 0 results, Design Notes, 30 `mutation:` lines, the triage log.

**Review findings.** 31 findings (high 0, medium 4, low 19, false 7, maybe-false 1). Patched 12 (4 medium, 8 low); deferred 0; rejected 19, each with its reason in the Review Triage Log.
- Patched, medium: the "random password" assertion could not fail (now `NewPassword`, `TestNewPassword` and a README-password check); the real `Users.Run()` and `Accounts` to `EnsureService` wiring was untested (`TestRunIsTheStep` and a hand-damaged service user in the flag tests); `Tools.Grants()` to `Toolsets()` never met a declaring tool (`TestToolsAreaFindsABuiltInToolset`); apply-phase failures were untested (`TestApplyFailuresNameTheUserAndTheKey`).
- Patched, low: `LabelFor`'s class fallback for an empty per-tool label; a public name that is a role is refused; two comments; the `Result` assertion that could not fail; the `TestNoEnvironment` control; a non-empty control in `TestEveryRole`; the missing `mutation:` lines (Rule 19).
- Rejected: `ToolParameter` and `Toolsets()` swallowing read failures (theoretical); README disabled last (spec order, a failed step fails the start); the public accounts not retired when the flag goes off (wontfix-accepted, below); a deny-list only (AD-24's Rule); OCUORDERS assumed by the tests (the spec requires the assertion); the abstract-toolset filter unpinned (reopen_if: an abstract toolset under `OcuTalon.Tools`); the intent auditor's descriptive items (Story 3.8 writes the keys, DW-160 owns the first-start pin).

**Follow-up review recommended: true.** First pass, four medium entries patched. The unverified risk: the patches added code after the review layers read it (`NewPassword`, the role-name refusal, three Users tests, one Registry test and its fixture XData), and no independent layer has read it or run it in reverse order (Rule 19's fresh-environment check is the lead's). Patched entries by verdict: medium 4, low 8.

**Verification performed.**
- `bash ci/checks.sh`: all scripts passed (after the last edit). `ci/iris.sh build`: exit 0.
- Warm `class` runs after the last code change: Install.Tools, Install.Users, Install.Registry, Bridge.Steps, Bridge.CodeRules and Tools.Reminders all passed.
- Once, after the last patch: `shard lane-a` (42 classes) and `shard lane-b` (24 classes) passed; `live install-start` (94 PASS), `live install-upgrade` (34 PASS) and `live sign-in` passed; `ci/iris.sh teardown` left nothing tagged `e3s1`. `ci/warm.sh down` ran after each warm stack.
- 30 mutations applied, each red, reverted byte-identically and green again on the same stack. Slot A took compile-only loads of the changed product classes; no test or security change ran there.
- Matrix Test Audit: rows 1 to 10 each have a covering test that ran and passed (row 4: `TestParseMalformed` and `TestMalformedResourcesFailTheStep`).

**Residual risks and observations.**
- The online-demo flag turned from 1 to 0 on a kept volume leaves the two public accounts enabled with their published passwords, and a README account disabled by the flag-on path stays disabled (seed). The online demo never flips the flag (AD-25). wontfix-accepted, reopen_if: a deployment turns `onlineDemo` from 1 to 0 on a kept volume. This is a security-posture item for the lead's veto window.
- A refusal by the instance itself (a policy-rejected password) fails at the call, after the service user and possibly the first public account are applied; the status names the key and the account, and the next start rewrites both.
- The first-start OCUORDERS page-size pin is Story 3.8's (DW-160). Until Story 3.8 writes the four account keys, a flag-on start fails closed at the empty key (row 10).
- Tooling observation (outside this story's footprint, `ci/`): while `Test.Install.Registry` failed to compile on the first start, `ci/warm.sh up` still printed `READY warm 543s`, although the stack's after-start log said `RESULT FAILED` and `not ready`; only the first `class` run showed the failure. A fresh `shard` or the live scripts would have shown it too.
- Compile order found at review: see Decided in-stage at review (`DependsOn` on `Test.Install.Registry`).
