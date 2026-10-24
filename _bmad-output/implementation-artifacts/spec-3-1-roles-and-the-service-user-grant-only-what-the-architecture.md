---
title: 'Story 3.1: Roles and the service user grant only what the architecture lists'
type: 'feature'
created: '2026-10-24'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
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
- [ ] Task 0 -- on the stage's own warm throwaway (an `iris session` in its container, with a fixture user created and deleted there; never on the slot), measure two things and record each result under Design Notes:
  - whether `##class(Security.Users).CheckPassword(.userObject, password)` returns 1 for the current password and 0 for a wrong one, without changing the user's `InvalidLogins` count;
  - whether `Security.Roles.Create` and `Modify` refuse a resource that does not exist.

  The check for a restored password takes the first of these that works:
  - (a) `CheckPassword`;
  - (b) `$SYSTEM.Security.ChangePassword(user, published, published, .sc)` returning 1;
  - (c) `PasswordChangedDateTime` advancing (labelled weaker).
- [ ] `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls`:
  - Add `ClassMethod ToolParameter(toolClass, name, base) As %String`. It returns the tool's own parameter `base_<NAME>` when the compiled class defines it, even if the value is empty; else `base` when defined; else "". "Defined" is tested with `%Dictionary.CompiledParameter`.
  - `LabelFor` calls it. Its result is unchanged for every class today. It references only `%Dictionary`.
  - Why: one suffix-rule reader that the installer and Story 3.2's gate share (Rule 2).
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Roles.cls`:
  - Add `Parameter FORBIDDEN = "%All,%Development,%Ens_MessageEditResend,%Ens_MessageDiscard,%Ens_ProductionRun,%Ens_ProductionConfig,%Ens_WorkflowConfig"`. In `Add`, refuse a listed resource, matched case-insensitively, with an error naming the area, role and resource.
  - In `Apply`, every role is created or modified with `GrantedRoles` "".
  - Why: AD-24's list becomes a fail-closed refusal at install, not only a test.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Tools.cls` (new; it declares and does not run):
  - `Toolsets()`: the compiled, non-abstract `OcuTalon.Tools.*` classes that extend `%AI.ToolSet`, sorted.
  - `Parse(value, where) As %DynamicArray`: `resource:permission[,resource:permission...]`, where the permission is one or more of R, W and U. An empty value gives `[]`. A malformed pair throws a status naming `where`.
  - `GrantsOf(toolsets As %List) As %DynamicArray`: for each toolset, `%New().%Discover().tools`. For each `{provider, name}`, `Parse(StepBuffer.ToolParameter(provider, name, "RESOURCES"), provider_" "_name)`, giving one `{"role", "resource", "permission"}` per pair, with duplicates removed, plus the entry that declares the role alone. The role is `##class(OcuTalon.Install.Step.Users).#SERVICEROLE`.
  - `Grants()` is `GrantsOf(..Toolsets())`.
  - Why: AC 1. The service user's grants come from each tool's `RESOURCES`.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls`:
  - Add the parameters `SERVICEUSER="OcuTalonService"`, `SERVICEROLE="OcuTalonServiceRole"`, `DEMOROLES="OcuTalonUser,OcuTalonTraceViewer"`, `READONLYROLES="OcuTalonTraceViewer"` and `TRACEPAGESIZE=100`.
  - `Run()` becomes `Quit ..Accounts(..#USER)`.
  - `Accounts(readmeUser)`, in this order, so that a refusal changes nothing:
    1. Read `onlineDemo` through `Settings.Get`; an error status fails the step.
    2. Flag on: read the four account keys and validate them all (matrix row 10).
    3. `EnsureService()`: create the service user once with `$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(32),1)`, `Enabled` 0, the service role and the flags of matrix row 1. When the user exists, `Modify` sets `Enabled` 0 and the roles.
    4. Flag off: `Ensure(readmeUser, PASSWORD, ROLES)`.
    5. Flag on: `EnsurePublic(name, password, roles)` creates or modifies each account with the password, exact roles, `FullName` set to the marker `OcuTalon online-demo account`, `Enabled` 1, `ChangePassword` 0, `PasswordNeverExpires` 1 and `AccountNeverExpires` 1. `PinTrace(name)` sets `^|ns|EnsPortal.Settings(name,"VisualTrace","ItemsPerPage")=..#TRACEPAGESIZE` for `OCUTALON`, and for `OCUORDERS` when `%SYS.Namespace.Exists` is true. If the README account exists, set its `Enabled` to 0 (roles and password unchanged) and `Warn` names it.
  - Why: AC 1 and AC 4.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/ZzGrantTools.cls` (extends `OcuTalon.Tools.Result`; methods `Alpha`, `Beta` and `Gamma` return `..Return({})`; parameters as in matrix row 3, with `STEPLABEL` set) and `src/ocutalon/cls/OcuTalon/Test/Install/ZzGrantToolset.cls` (an `%AI.ToolSet` whose XData names `alpha`, `beta` and `gamma`) -- new committed fixtures. They refer to `%AI` only on the Class line (CodeRules).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Tools.cls` (new) -- tests:
  - `Parse`: valid input, several pairs, empty, and each malformed form;
  - `GrantsOf` of the fixture toolset: the per-tool value wins, the class value is the fallback, and a defined empty value gives nothing;
  - `ToolParameter`, and `LabelFor` unchanged for `ReminderTools`;
  - the real `Grants()`: no throw; every entry names `OcuTalonServiceRole`; the role-alone entry is there; `Toolsets()` holds `OcuTalon.Tools.Reminders` and `.Watch` and no `OcuTalon.Test.*` class.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`:
  - Fixture changes: switch both fixtures to `%Ens_Portal:U`. `OnBeforeAllTests` saves the trace role's resources and creates the resource `ZzOcuTalonGrantProbe` (public permission 0); `OnAfterAllTests` re-runs `Roles.Run()`, restores the saved trace-role resources and deletes the probe resource. `TestRolesStep` expects `%DB_USER:RW,%Ens_Portal:U`.
  - New tests for matrix rows 3, 5, 6 and 7.
  - `TestTraceRoleSql`: the trace role's rows in `Security.SQLPrivileges` are exactly SELECT (`s`) on `1,Ens.MessageHeader` in OCUTALON (after `Web.GrantTraceSql()`), and in OCUORDERS once a missing one is fixture-granted there. The test removes only what it added.
  - `TestEveryRole`: every `OcuTalon*` role holds no `FORBIDDEN` resource and no granted roles, and the trace role holds no `%DB_OCUTALON_PRIVATE` or `%DB_OCUTALON_PUBLIC`. The README account, the service user and the fixture public accounts appear in neither `EnsLib_Workflow.UserDefinition` nor `EnsLib_Workflow.RoleMembership`, in OCUTALON or OCUORDERS. No account's roles hold `%Ens_WorkflowConfig`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` -- extend it with tests for matrix rows 1, 2 and 8 to 10:
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

## Spec Change Log

- 2026-10-24, lead spec gate (unattended ruling, veto window: security posture): with the flag on, an existing README account is disabled (roles and password unchanged) and the step warns, instead of being left as it is (matrix row 9, Boundaries, Users task, Users test row 9, mutation table). The first-start OCUORDERS page-size pin is routed to Story 3.8's `Public` step (DW-160, routed by spec_gate). The `RESOURCES` grammar and the service role's name are recorded as the spine's Consistency Conventions row "Tool resources" (Rule 20).

## Review Triage Log

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

Status: ready-for-dev
Blocking condition: none
