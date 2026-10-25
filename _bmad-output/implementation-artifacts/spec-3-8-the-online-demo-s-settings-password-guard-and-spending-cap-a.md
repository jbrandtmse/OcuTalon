---
title: 'Story 3.8: The online demo''s settings, password guard and spending cap are ready'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: '5f98fa227825bcedb40973e1e05b7cab55935533'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-19 "Online-demo start values" and "Public settings", AD-13 "Password changes", AD-24 "Page size" and the password sentence of its accounts bullet, AD-23 the after-start steps 3 to 6, AD-20 "The online demo", and AD-3 "Only these classes switch namespace")'
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      The password guard matches the lower-cased name exactly, so on an instance with multiple domains enabled the name IRIS passes carries the domain and a public account's password change would pass.
    evidence: |-
      Security.System documents that the name passed to the validation routine "will contain the domain name if multiple domains are enabled". OcuTalon's image does not enable multiple domains; whether any deployment can is not settled. Would be settled by checking that the demo host's instance (docker/**, Story 29.3) keeps multiple domains off, or by matching the name before the domain too.
    location: >-
      src/ocutalon/cls/OcuTalon/Install/Step/Users.cls WriteGuard
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** The online demo cannot start as itself.
- `Install.Step.Public.Run()` writes only the flag, so the published accounts, the reset values, the proxy address, the connection cap, the reserve and the message allowance never reach the public settings.
- Nothing writes `Decide`'s three budget settings, so the $20 daily cap and the gateway's spend never reach `Budget.State()`.
- Nothing stops a visitor from changing a public account's password with a sign-in request (AD-13, S17).
- On a fresh flag-on volume, the public accounts' Visual Trace page size is never pinned in OCUORDERS (DW-160).

Lane B's Epic 16 and Epic 29 build on all four.

**Approach:**
- `Public.Run()` reads AD-19's start values from the environment on every start. It writes each public key through `OcuTalon.Data.Public.Settings`. With the flag on, it also writes `Decide`'s three budget settings; on a local install it seeds the cap at 0.
- With the flag on, the Users step writes a password-guard routine into `%SYS` and points the instance's password-validation routine at it, before it writes the public accounts' passwords. With the flag off, no guard exists.
- `Public.Ready()` pins both public accounts' page size, then sets readiness.

## Boundaries & Constraints

**Always:**
- **The start values (AD-19).** `$SYSTEM.Util.GetEnviron` reads them. A variable that is set but empty counts as unset.

  | Variable | Goes to | Default (flag on) | Accepted |
  | --- | --- | --- | --- |
  | `OCUTALON_ONLINE_DEMO` | `onlineDemo` | -- | exactly `1` is on; anything else is off |
  | `OCUTALON_DEMO_USER`, `OCUTALON_DEMO_PASSWORD`, `OCUTALON_READONLY_USER`, `OCUTALON_READONLY_PASSWORD` | `demoUser`, `demoPassword`, `readonlyUser`, `readonlyPassword` | none | not checked here (the Users step refuses empty or clashing accounts) |
  | `OCUTALON_RESET_INTERVAL_HOURS` | `resetIntervalHours` | 4 | a number above 0 |
  | `OCUTALON_RESET_ANCHOR`, `OCUTALON_LAST_RESET` | `resetAnchor`, `lastReset` | none | empty, or `YYYY-MM-DDThh:mm:ssZ` naming a real time |
  | `OCUTALON_LAST_RESET_KIND` | `lastResetKind` | none | empty, `scheduled` or `unscheduled` |
  | `OCUTALON_PROXY_ADDRESS` | `proxyAddress` | none | not checked |
  | `OCUTALON_CONNECTION_CAP`, `OCUTALON_CONNECTION_RESERVE`, `OCUTALON_MESSAGE_ALLOWANCE` | `connectionCap`, `connectionReserve`, `messageAllowance` | 8, 2, 50 | whole numbers; the cap and the allowance are 1 or more; the reserve is 0 or more and below the cap |
  | `OCUTALON_DAILY_COST_CAP_USD` | `Decide` `DailyCostCapUSD` | 20 | a number of 0 or more; 0 means off |
  | `OCUTALON_GATEWAY_SPEND_USD` | `Decide` `GatewaySpendUSD` | empty | empty, or a number of 0 or more |
  | `OCUTALON_GATEWAY_SPEND_DATE` | `Decide` `GatewaySpendDate` | empty | empty, or an existing date `YYYY-MM-DD` (the instance-zone date it counts) |

- **`Public.Run()`.**
  1. It first clears readiness (`Settings.ClearReady()`). Readiness then stays cleared on both entry points (the after-start script and `Registry.Run("ipm")`) until `Ready()`.
  2. **Flag on:**
     - It checks every value in the table before it writes anything. A value it does not accept refuses the step with an error that names the variable and the rule, never the value, and nothing else is written.
     - It then writes `onlineDemo` 1 and the twelve other keys through `Settings.Set`: the value, the default, or "" (which removes the key). Every key is rewritten on every start (structural).
     - It then writes the three `Decide` rows (`OcuTalon.Production`, `Decide`, any class) through `Install.Step.Production.WriteDefault`, with descriptions saying that the Public step writes them at every start from the named variable. An empty gateway value is written as an empty row.
  3. **Flag off:**
     - It writes `onlineDemo` 0 and no other public key.
     - It writes no gateway row.
     - It writes the `DailyCostCapUSD` row with 0 (the seed) only when no System Default Settings row of any specificity resolves `Decide`'s host setting `DailyCostCapUSD`. An existing row is kept: `SettingsOps` owns it from step 2.
- **`Public.Ready()`.** It reads `onlineDemo` through the accessor (an error status fails it).
  - With the flag on, it calls `Users.PinTrace(name)` for the non-empty `demoUser` and `readonlyUser`. A pin's error fails `Ready()`, and readiness is not set.
  - It then calls `SetReady()` (DW-160, AD-23, AD-24).
- **The password guard (Users step, flag on; AD-13, AD-24).**
  - `Accounts(readmeUser)` runs in this order:
    1. the flag;
    2. `PublicAccounts` validated;
    3. the guard check: the instance's `PasswordValidationRoutine` must be "" or `Check^OcuTalonPasswordGuard`. Any other value refuses the step, naming the routine, with nothing changed;
    4. `EnsureService`;
    5. `Guard(accounts)`;
    6. each account's `EnsurePublic` and `PinTrace`;
    7. `DisableReadme`.
  - `Guard`, in `%SYS`:
    1. It generates the routine `OcuTalonPasswordGuard` with `%Routine`. For each public account, the routine holds the account's lower-cased name, a fresh random salt and the Base64 SHA-512 of salt plus the published password. No password is in clear.
    2. Its `Check(user, password)` lower-cases `user`. For a public account's name it returns 1 only when the hash matches; otherwise it returns an error status. For every other name it returns 1. It calls nothing outside `$SYSTEM`, `$ZConvert` and `$SYSTEM.Status`.
    3. `Guard` saves the routine and compiles it with `-d`. The compile adds no line to the start log: measured, `-d` still prints one empty line, which the step keeps off the log.
    4. It self-checks: `$$Check^OcuTalonPasswordGuard` returns 1 for each account's name in upper case with its published password, and refuses that name with a different password (the published one with a character added).
    5. Only then does it set `PasswordValidationRoutine` to `Check^OcuTalonPasswordGuard`, if it is not already. A failed save, compile or self-check refuses the step and leaves the setting as it was.
- **Flag off (local or IPM install).** `Accounts` runs `EnsureService`, then `Unguard`, then `DisablePublic`, then `Ensure`.
  - `Unguard` clears `PasswordValidationRoutine` only when it is `Check^OcuTalonPasswordGuard`.
  - It then deletes the routine (`%Routine.Delete`, flag 0) when it exists.
  - It warns once, and only when it removed something.
  - A foreign routine is never touched.
- **Who reads what.** The public keys are read only through `OcuTalon.Data.Public.Settings`. The bridge is not changed: `Budget.State()` and `Decide`'s precheck already read the three rows through `Ext.Accessor.ValueFor` (AD-2, AD-20).
- **Where tests run.** Tests run on throwaways only (`ci/iris.sh`, `ci/warm.sh`). A test that changes a start variable, a public key, readiness, a `Decide` row, the `PasswordValidationRoutine` setting, the guard routine, a page-size pin, today's day mark, the runners' key entries or `Decide`'s host sink puts it back, also after a failure. A test that signs in signs out again.

**Never:**
- No edit to Lane B's `OcuTalon.Data.Public.Settings` or its test `Test.Data.PublicSettings`. No edit to `Install/Step/Demo.cls`, `Core/**`, `docker/**`, `ci/compose.ci.yml`, `.github/**`, `docs/**` or the bridge.
- No `ci/units.sh` change unless the shard rule in Design Notes applies.
- No namespace switch in the guard routine.
- No published password in clear in any routine.
- No reference to `^OcuTalonPublic` outside the accessor.
- No change to the `Decide` rows of any production but `OcuTalon.Production`.
- No guard, no `PasswordValidationRoutine` change and no gateway row on a local install.
- No security change on `ocutalon-slot-a`.
- Out of scope, Lane B's Story 16.1: the other password-change forms of S17 (legacy names, query string, encoded, multipart, chunked, GET), the splash, and the busy check.

## I/O & Edge-Case Matrix

The environment is set in the test process (`Test.Agent.KeyScan.SetEnv` and `UnsetEnv`), and the steps run in process, as the after-start script runs them. The fixture accounts are `ZzPublic<n>Demo` and `ZzPublic<n>Ro` (`Test.Install.Public`), or the fixture accounts of `Test.Install.Users`.

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Every start value (AC 1) | The flag 1 and all twelve other public variables set; readiness 1 | `Run()` OK. Each key reads back through `Settings.Get` as given, `onlineDemo` is 1, and readiness is "" | -- |
| 2 | Defaults | The flag and the four account variables only; stale `resetAnchor`, `lastReset`, `lastResetKind` and `proxyAddress` | `resetIntervalHours` 4, `connectionCap` 8, `connectionReserve` 2, `messageAllowance` 50; the four stale keys read "" | -- |
| 3 | A bad value | One at a time: interval `0` and `x`; cap `0` and `1.5`; reserve `-1`, and reserve equal to the cap; allowance `0`; anchor `2026-10-25 00:00`; last reset `2026-10-25T00:00:00+01:00`; kind `manual`; daily cap `-1`; gateway spend `x`; gateway date `2026-13-01` | `Run()` returns an error naming the variable. Every public key and the three rows are unchanged, and readiness is "" | Refused before any key or row is written |
| 4 | Flag off (AC 1, AC 3) | The flag unset, every other variable set; stale keys; no cap row, then a cap row of 7 | Among the public keys, only `onlineDemo` changes (to 0); readiness is "". No gateway row. The cap row is 0 when it was absent, and 7 is kept | -- |
| 5 | The budget rows (AC 3) | Flag on: the cap unset; then `0`; then `12.5`; spend `3.2` with today's date; then no gateway variables, over rows of 9 and `2001-02-03` | `DailyCostCapUSD` 20, then 0, then 12.5. The spend and date as given, then both rows empty (rewritten). The cap is read back through `Ext.Accessor.ValueFor` | -- |
| 6 | The chain (AC 2, AC 4) | Flag on with the fixture accounts; `Public.Run()`, then `Users.Accounts(<fixture README>)` | Both accounts hold their published passwords, and the guard is set. A sign-in request with `IRISOldPassword` and a new `IRISPassword` is refused for each account, whose password stays the published one | -- |
| 7 | The cap (AC 3, AC 4) | Flag on; the cap unset (20). Control: spend 0, today (`Bridge.Time.LocalDate` of now). Then spend 20, today | Control: an untrusted decide reaches the mock once. At the cap: `Budget.State()` is cap 20 and capped; the decide is answered with a tellnow fallback `daily_cap` (answer, XML and row); no request with its reference reaches the mock; the probe sink gets `budget.capped` once | -- |
| 8 | The last phase (DW-160) | Flag on, with the fixture names published; their pins killed in OCUTALON and OCUORDERS (which exists on every throwaway); readiness "". Then the flag 0 with other names | `Ready()` OK. Both names are pinned to 100 in both namespaces, and readiness is 1. Flag 0: readiness 1, and no pin written for the names | A pin error fails `Ready()`, and readiness stays "" |
| 9 | The guard (AC 2) | Flag on, `Accounts` with the fixture accounts | The setting is the literal `Check^OcuTalonPasswordGuard`. The routine's source holds neither password. For each account: `Security.Users.Modify` to another password is refused, and the password is unchanged; a sign-in change with the name in capitals is refused. A non-public fixture user changes its password with the same request (the control) | -- |
| 10 | The installer's write | After row 9, the published passwords changed in the settings, and `Accounts` run again | OK. Each account holds the new password, and the guard now refuses the old one | -- |
| 11 | No guard locally (AC 2) | Flag off, `Accounts`; then flag on, `Accounts`; then flag off, `Accounts` twice | The first: the setting "" and no routine. After the flag-on run, the first flag-off run clears the setting, deletes the routine and warns once; the second warns nothing | -- |
| 12 | A foreign routine | `PasswordValidationRoutine` = `ZzOther^ZzForeign`. Flag on, `Accounts`; then flag off, `Accounts` | Flag on: refused naming it; no public account made; the setting unchanged. Flag off: the setting unchanged, and no warning | Refused before any change |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls` -- the change. `Run` (:7-11) writes only the flag; `Ready` (:14-17) only calls `SetReady`; the class comment (:1-2).
- `src/ocutalon/cls/OcuTalon/Data/Public/Settings.cls` -- Lane B's, read only.
  - `KEYS` (:9) already lists every key.
  - `Get` (:19), `Set` (:31; "" removes the key), `ClearReady` (:43), `SetReady` (:50).
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls` -- the guard.
  - The class comment (:1-16) and the parameters (:20-48).
  - `Accounts` (:67-93): add the guard check, `Guard` and `Unguard` in the Boundaries' order.
  - `EnsurePublic` (:135-153) writes the password through `Security.Users.Modify` or `Create`.
  - `PinTrace` (:158-172) is public and idempotent; `PublicAccounts` (:179-213) builds `accounts(n)`.
  - The patterns: `Disable` (:262-274, warn only on a change), `Refuse` (:277) and `Fail` (:283).
- `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls` -- read only.
  - `PRODUCTION` (:26).
  - `WriteDefault` (:268-271) is the writer to reuse.
  - `HasRow` (:228-231) is the `%GetSetting` pattern for the seed check: there it uses target `Adapter`; here use `Host` and the class `OcuTalon.Bridge.Process.Decide`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls` -- read only: `ValueFor` (:19-35) reads the item definition, then System Default Settings, then the property's initial value; `WriteDefault` (:40-56).
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls` -- read only. `State` (:41-92) already adds `GatewaySpendUSD` when `GatewaySpendDate` is today, and names bad values as faults.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- read only.
  - `SETTINGS` (:92) and the three properties (:160-167).
  - `Precheck` (:587) gives `daily_cap` from `State().capped`.
  - `OcuTalon.Production` (:18-21) sets no budget setting on `Decide`, so System Default Settings rows decide.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls` -- read only: `Order` (:12-15) already runs `Public` second and `Ready` last; `RunStep` (:126-140).
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` -- extend it.
  - The header (:1-6) and `KEYS` (:13).
  - `OnBeforeOneTest` (:67-80) and `OnAfterOneTest` (:82-97) gain the guard's save and restore.
  - The model test is `TestPublicAccountsWithFlagOn` (:284).
  - The helpers: `SetPublic` (:643), `PasswordOk` (:664), `ClearAccounts` (:751), `ClearPins` (:762) and `Clean` (:818).
  - The `Svc` fixture user in `ClearAccounts` is the model for the control user.
- `src/ocutalon/cls/OcuTalon/Test/Install/ProviderEnv.cls` -- the pattern for environment tests: save and restore (:170-215), and `RunWith` (:241-262).
  - `Test.Agent.KeyScan` `SetEnv`, `UnsetEnv` and `HasEnv` (:279-297).
- `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` -- public helpers, called and not edited:
  - `ReadyReason` (:306), `NewRequest` (:276), `Run` (:378), `DecisionOf` (:315), `FallbackProblems` (:823);
  - `Drain` (:802) and `FindRequests` (:918);
  - `PointKeys` and `RestoreKeys` (:456-467);
  - `UseItemSetting` and `RestoreItemSetting` (:617-635);
  - `RememberDefault` (:715), `RestoreDefaults` (:727) and `SinkCalls` (:781).
- `src/ocutalon/cls/OcuTalon/Test/Agent/Decide.cls` -- read only. It is Epic 1's sibling of row 7:
  - `TestDailyCapBothPaths` (:1337-1393);
  - the private `Prepare` (kills today's mark, `PointKeys` once), `SwapSink` (:1571) and `AssertNotSent` (:1596).
- `src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls` -- read only: `LogMark` (:365) and `LogSince` (:378). `OcuTalon.Test.Bridge.ProbeSink` is the probe sink.
- `src/ocutalon/cls/OcuTalon/Test/Data/PublicSettings.cls` -- Lane B's, read only. `TestPublicStep` (:127-139) calls `Run()` with the flag off and expects `onlineDemo` 0 and readiness "". It must stay green.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:129` -- pins that `Public.Ready` exists.
- `irissys/Security/System.cls:349-380` -- `PasswordValidationRoutine`: a routine that must exist in `%SYS`, called with the user name lower-cased; it returns a `%Status`.
- `irislib/%CSP/PasswordChange.cls:95-110` -- the form fields: `IRISUsername`, `IRISOldPassword`, `IRISPassword` and `IRISLogin`.
- `irislib/%Library/Routine.cls` -- `Compile(qspec)` (:662); `Delete(name, flag)` (:732; flag 0 deletes the MAC, INT and OBJ); `Exists` (:787).

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls`:
  - one parameter maps each variable to its key or setting;
  - the defaults and the checks of the Boundaries table;
  - `Run` as the Boundaries say (clear readiness; flag on: check, keys, rows; flag off: the flag and the seed);
  - `Ready` with the DW-160 pins;
  - the class comment states the contract.
  - Why: rows 1 to 5 and 8; AC 1, AC 3; DW-160.
- [ ] `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls`:
  - the parameters `GUARDROUTINE` (`OcuTalonPasswordGuard`) and `GUARDENTRY` (`Check^OcuTalonPasswordGuard`);
  - the guard check in the validation phase;
  - `Guard(accounts)` (generate, save, compile `-d`, self-check, set) and `Unguard()`, both in `%SYS`;
  - `Accounts` in the Boundaries' order;
  - the class comment.
  - Why: rows 9 to 12; AC 2.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/PasswordGuard.cls` (new, no `Test` method):
  - `State()` returns the `PasswordValidationRoutine` setting and whether the guard routine exists; `Restore(state)` puts both back;
  - `Source()` returns the routine's source text;
  - `SignInChange(user, old, new)` POSTs `IRISUsername`, `IRISOldPassword`, `IRISPassword` and `IRISLogin` to `127.0.0.1:52773/ocutalon/` with `%Net.HttpRequest`. It then signs out with `/ocutalon/?IRISLogout=end`, sending the session cookie the sign-in returned, and returns the sign-in's HTTP status.
  - Why: Rule 2, so `Test.Install.Users` and `Test.Install.Public` share one copy.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls`:
  - `TestGuardWithFlagOn` (row 9; it reads the setting by its literal value);
  - `TestInstallerWritesAChangedPassword` (row 10);
  - `TestNoGuardWithFlagOff` (row 11);
  - `TestForeignGuardIsRefused` (row 12).
  - `OnBeforeOneTest` and `OnAfterOneTest` save and restore through `PasswordGuard.State` and `Restore`. `ClearAccounts` also removes the control user `ZzUsers<n>Ctl`.
  - The header lists the new tests.
  - Every existing flag-on test that now installs the guard stays green.
  - Why: AC 2.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Install/Public.cls` (new test class; its header says it runs on throwaways and in CI only):
  - `TestEveryStartValue` (row 1), `TestDefaults` (row 2), `TestBadStartValues` (row 3), `TestFlagOffWritesOnlyTheFlag` (row 4), `TestBudgetRows` (row 5), `TestStartValuesReachTheUsersStep` (row 6), `TestDecisionAtTheCap` (row 7) and `TestReadyPinsThePublicAccounts` (row 8).
  - It saves and restores the 16 variables (present and value), the 13 keys and readiness, the three `Decide` rows (`RunnerFixture.RememberDefault` and `RestoreDefaults`), the guard (`PasswordGuard`), and the fixture accounts and their pins.
  - `TestDecisionAtTheCap` also:
    - kills today's day mark before and after;
    - points the runners' keys and restores them (`PointKeys`, `RestoreKeys`);
    - swaps `Decide`'s `HostSinkClass` to `OcuTalon.Test.Bridge.ProbeSink` in its shared mode, as `SwapSink` sets it (`^OcuTalonTest("ProbeSink","shared")` = 1), and back (`UseItemSetting`, `RestoreItemSetting`);
    - drains `TriageAgent` before it reads the mock's log;
    - deletes the `Usage` rows of its decisions.
  - The fixture counter is `^OcuTalonTest("Public","n")`, never reset.
  - Why: AC 1, AC 3, AC 4; DW-160.

**Acceptance Criteria:**
- Given AD-19's online-demo start values in the environment, when the `Public` step runs (right after `OcuTalon.Bridge.Installer`, before the role, user and web steps), then it writes each public key through `OcuTalon.Data.Public.Settings.Set` on every start while readiness stays cleared, with the defaults 4, 8, 2 and 50 an hour; without `OCUTALON_ONLINE_DEMO` it writes only the flag (off); and after `Production` and `Reconcile` its `Ready()` sets readiness last. Rows 1 to 4 hold (FR-14, FR-59, AD-19, AD-23).
- Given the online-demo flag set, when the user step runs, then it reads the flag and the published accounts through the accessor and installs the password-validation routine, which allows each public account only its published password, compares the user name case-insensitively, and never blocks the installer's own write of that value; on a local install no routine is installed and an earlier one of OcuTalon's is removed. Rows 9 to 12 hold (FR-59, AD-13, AD-24).
- Given the flag set, with `OCUTALON_DAILY_COST_CAP_USD` (default 20), `OCUTALON_GATEWAY_SPEND_USD` and `OCUTALON_GATEWAY_SPEND_DATE`, when the `Public` step runs before `Production`, then `Decide`'s System Default Settings `DailyCostCapUSD` (0 means off), `GatewaySpendUSD` and `GatewaySpendDate` hold them, and `Budget.State()` and the precheck read them through the bridge's accessor. On a local install `DailyCostCapUSD` is a seed of 0 and the gateway values are not written. Rows 4, 5 and 7 hold (FR-40, AD-8, AD-19, AD-20).
- Given a test stack with the online-demo start values, when the three are exercised, then the public keys read back through `OcuTalon.Data.Public.Settings`, a password change for either public account is refused while the installer's write succeeds, and a decision at the cap falls back with `daily_cap` without a request being sent. Rows 1, 6, 7 and 10 hold (FR-40, FR-59).
- DW-160: given a fresh flag-on volume, where OCUORDERS does not exist when the Users step runs, when the start reaches its last phase, then `Public.Ready()` calls `Users.PinTrace` for both public accounts before `SetReady`, so the page size is pinned in both namespaces (ledger; routed by spec_gate 2026-10-24). Addressed by row 8 and the `Public.cls` task.
- Given the fresh `shard lane-a`, `shard lane-b`, `live install-start` and `live install-upgrade`, when they run, then every class and check passes.

## Spec Change Log

- 2026-10-25, lead spec gate: AD-13 and AD-19 are not amended. The plan's Rule 20 points went into a new Consistency Conventions row "Online-demo start" (light path): the Public step's order, keys and defaults, the malformed-value refusal, the last phase (PinTrace, then readiness), and the password guard's shape and order. Kept as one story despite the `multiple-goals` warning: the three ACs share the Public step and one test stack, and the AC asks for them together. The flag-on proof sets the start values in the test process on a throwaway, as `Test.Install.ProviderEnv` does; a real flag-on start is Lane B's Stories 16.1 and 16.2 (no contended compose or live script is edited). Ruled in the veto window and kept as planned: the instance-wide password guard (a generated `%SYS` routine with salted hashes of the published passwords), a malformed start value failing the start, and the new admin texts.

## Review Triage Log

### 2026-10-25 — Review pass
- verdicts: 37 findings — high 0, medium 9, low 24, false 3, maybe-false 1 (the 9 medium rows group into 4 entries: sign-in status, start-value tests, failed guard, seed specificity)
- findings:
  - Blind hunter:
    - `[maybe-false]` `[defer]` The guard compares the lower-cased name exactly, so on an instance with multiple domains enabled (the name then carries the domain) a public account's password change would pass — evidence: Security.System documents the domain suffix; OcuTalon's image does not enable multiple domains, whether any deployment can is not settled here (deferred, medium unverified).
    - `[medium]` `[patch]` Two sign-in refusal assertions discard the request's status, so they pass when no request is made — `SignInChange`'s status is now asserted > 0 for each public account in `Test.Install.Users.TestGuardWithFlagOn` and `Test.Install.Public.TestStartValuesReachTheUsersStep`.
    - `[medium]` `[patch]` Bad-value tests leave stated rules unchecked (empty means unset, an unreal time, a near-miss flag) — added `TestEmptyCountsAsUnset`, `TestOnlyOneIsOn` and two unreal-time cases in `TestBadStartValues`; the reserve-equal-to-cap case was already there (reserve 8 over the default cap 8), and the `$Length(bad) > 3` limit stays (a short value such as `0` appears in the rule text).
    - `[low]` `[reject]` Numeric rules accept `1E2`, `+5`, `.5`, `007` and set no upper bound — the spec asks for "a number" and "a whole number"; the readers parse numerically, and no product bound exists to enforce; not worth guards (wontfix-accepted, reopen_if a reader of a public key compares the text).
    - `[low]` `[reject]` The write phase is not atomic after validation — the spec promises "nothing written" only for a refused value; a write error is an internal fault (wontfix-theoretical).
    - `[low]` `[reject]` A flag-on to flag-off start leaves the gateway rows and the cap — by design: Design Notes "Flag off: no clean-up of rows an earlier flag-on start wrote".
    - `[medium]` `[patch]` No test shows that a guard that cannot be written leaves the setting as it was — added `Test.Install.Users.TestFailedGuardLeavesTheSetting` (a line feed in the demo account's name breaks the routine's compile); special-character passwords stay untested (low, reject: passwords only enter the hash).
    - `[low]` `[patch]` `CheckGuardRoutine` says it runs in %SYS but does not switch — it now switches like its siblings.
  - Edge case hunter:
    - `[low]` `[reject]` A second start replaces the live routine before the new one is checked, so a failed compile or check leaves the setting naming a changed routine — the setting is as it was (the spec's wording), the failure refuses the step, and password changes are refused (fail-closed); wontfix-accepted, reopen_if a start with valid accounts fails the compile.
    - `[low]` `[reject]` A control character in an account name breaks or injects into the routine — quotes are doubled, so a name cannot leave its literal; a line feed fails the compile and the step (pinned by `TestFailedGuardLeavesTheSetting`).
    - `[low]` `[reject]` Numeric values stored verbatim — same as the blind hunter's numeric row.
    - `[low]` `[reject]` The write loop can fail midway — same as the blind hunter's atomicity row.
    - `[low]` `[reject]` `PasswordGuard.Restore` could set a setting naming a missing routine — it restores a state `State` just read, where the routine existed (wontfix-theoretical).
    - `[low]` `[reject]` `SignInChange` ignores the sign-out's status — best effort; a left session is not an assertion (wontfix-accepted, reopen_if licence use grows during the suite).
    - `[medium]` `[patch]` Empty-means-unset has no test — same as the blind hunter's bad-value row (`TestEmptyCountsAsUnset`).
    - `[false]` `[reject]` The self-check does not try the lower-cased name — `Check` lower-cases its argument, so the upper-case call runs the same path.
    - `[low]` `[reject]` Claim: "leaves the setting as it was" while the routine was already replaced — the claim is about the setting and holds; see the first row.
    - `[low]` `[reject]` Claim: only the first bad variable is named, and readiness is cleared first — both are the spec's wording (AD-23, "refuses the step with an error that names the variable").
  - Verification gap:
    - `[medium]` `[patch]` Sign-in assertions can pass vacuously — the blind hunter's sign-in row.
    - `[medium]` `[patch]` No test for a failed guard leaving the setting — the blind hunter's failed-guard row.
    - `[medium]` `[patch]` The real-time half of the time rule is unpinned — two unreal times added to `TestBadStartValues`, mutation recorded.
    - `[medium]` `[patch]` The flag's exactness is unpinned — `TestOnlyOneIsOn`; the claim that the old code took `01` as on is false (the old `= 1` compared strings too), and the recorded mutation uses a numeric comparison.
    - `[medium]` `[patch]` The seed's any-specificity check is unpinned — `TestFlagOffKeepsARowOfAnotherSpecificity` with a row on the item `*`, mutation recorded.
    - `[low]` `[patch]` `TestEveryStartValue` has no recorded mutation — recorded (skip `messageAllowance`).
    - `[low]` `[patch]` `TestBadStartValues` has only the reserve mutation — the time-clause mutation recorded.
    - `[low]` `[reject]` `TestGuardWithFlagOn`'s second named mutation (`Check` returns 1 for all) is not demonstrated — one demonstrated mutation per AC is the bar.
    - `[low]` `[patch]` `TestForeignGuardIsRefused` has no mutation line — recorded (`CheckGuard` accepts any routine).
    - `[low]` `[reject]` `TestNoGuardWithFlagOff` has only the setting mutation — one per AC is the bar.
    - `[low]` `[reject]` A run across midnight can flake `today` — a seconds-wide window shared with Epic 1's tests (wontfix-theoretical).
    - `[low]` `[reject]` The seed assertion relies on no other-specificity row existing — it fails loudly, never falsely green (wontfix-accepted).
    - `[low]` `[reject]` Teardown ignores the statuses of `Restore` — a later test fails loudly on a bad state (wontfix-accepted).
  - Intent alignment (descriptive; no divergence from the spec's own Where-tests-run and Lane B boundaries):
    - `[low]` `[reject]` No test runs the Registry order or the after-start script with the flag on — the contract fixes in-process proofs; the real flag-on start is Lane B's Stories 16.1 and 16.2.
    - `[low]` `[reject]` The start log's emptiness after the compile is not asserted — the null-device redirect is in the spec's own measured plan; wontfix-accepted, reopen_if the flag-on start log shows an empty line.
    - `[low]` `[reject]` The guard-before-passwords order is proved only through row 10 — that test goes red when the order flips.
    - `[low]` `[reject]` The sign-in test hard-codes port 52773 and row 6 has no control — the request runs inside the container, where the port is measured; the status assertion now shows the request was answered.
    - `[false]` `[reject]` Validation details looser than the contract — the contract says "a number" and "whole numbers"; same as the numeric rows above.
    - `[false]` `[reject]` The shard rule — measured: the fresh `lane-a` took 412 s in the shard, under the 460 s line.

## Design Notes

**Architecture decisions:**
- **AD-19** governs the start values, the keys' one accessor, structural against seed, and the three `Decide` rows.
- **AD-23:** `Public` runs second and `Ready` last; a step's warning never changes its result.
- **AD-13 and AD-24:** the password-validation routine (case-insensitive, never blocking the installer), and the page size pinned in both namespaces.
- **AD-20 and AD-8:** `Budget.State()` adds the gateway's spend, and `daily_cap` is a before-sending fallback. Both are already built (Epic 1).
- **AD-2:** no bridge change, and the bridge never reads public settings.
- **AD-3:** the Users step switches to `%SYS` (allowed for `OcuTalon.Install.*`); the generated routine switches nothing.
- **AD-22:** throwaways only. **AD-29:** the Public step and the Users step are Lane A's; the accessor is Lane B's.
- No AC contradicts an AD's Rule.

**Measured at planning** (warm throwaway `e3s8pw`, build 154, torn down afterwards):
- **The hook.**
  - `Security.Users.Create` and `Modify` (with a password) call the routine, with the name lower-cased, in `%SYS`. A refusal makes `Modify` return the routine's status.
  - A sign-in request to `/ocutalon/` with `IRISOldPassword` and `IRISPassword` calls it too, in `%SYS`, as the signing-in user with `$Roles` `%All`. It changed a password when allowed and kept it when refused; HTTP 200 both times. The name in capitals was still matched.
- **Fail-closed.** A routine that throws, or a setting that names a missing routine, refuses every password change on the instance. Hence: compile and self-check first, set the setting last; on removal, clear the setting first.
- **Generating it.** `%Routine.%New("X.mac")`, `WriteLine`, `Save` and `Compile("-d")` in `%SYS` worked, writing to IRISSYS (`/durable/iris/mgr/`). The compile printed one empty line.
  - The whole flow passed: a salted SHA-512 guard, the self-check, then the setting.
    - The installer's `Modify` to the published value: OK.
    - `Modify` to another value: refused with the routine's error.
    - The sign-in change: refused.
  - `%Routine.Delete(name)` then left no MAC and no OBJ. The setting was restored to "".
- **The defaults on a throwaway.** `PasswordValidationRoutine` is "", `PasswordPattern` is `3.255ANP`, the web port inside the container is 52773, and OCUORDERS exists (demo mode is seeded on in OcuTalon's image).

**Decided in-stage:**
- **The guard is generated, not a reader.** The routine must live in `%SYS`. A reader would have to switch to OCUTALON for the accessor, which AD-3 does not list, or reference the global, which the CI check forbids.
  - So the Users step writes it from the accessor's values at every flag-on start, as it writes the passwords into `Security.Users`.
  - `^OcuTalonPublic` stays the only home (AD-19). The routine holds derived hashes, never a password.
- **Order.** The guard is written before the public accounts' passwords, so the installer's write of a changed published value passes it (row 10).
- **A foreign routine.** With the flag on it is refused with nothing changed, like a foreign account (`EnsurePublic`). With the flag off it is never touched.
- **Flag off removes OcuTalon's guard,** so "no routine on a local install" holds even on a volume that was once flag-on.
- **`Run` clears readiness first,** so readiness is cleared on the IPM path too, and a failed `Public` step leaves the instance not ready.
- **Bad start values refuse the step** (fail-closed), naming the variable. A malformed cap would otherwise count as off in `Budget.State`.
- **Empty means unset.** Unset keys with no default are removed (structural). Unset gateway values are written as empty rows.
- **Flag off: no clean-up of rows an earlier flag-on start wrote.** A kept cap is a safe failure, and `SettingsOps` owns the row from step 2.
- **`Ready` fails on a pin error,** as the Users step does.
- **In-process proofs.** No compose file passes the online-demo variables, and a flag-on live unit would need a new `docker/tests` script (contended), so AC 4 runs the steps in process with the variables set in the test process, as `Test.Install.ProviderEnv` does. Lane B's online-demo runs (Stories 16.1 and 16.2) cover the real start and the other S17 forms.
- **One sign-in form.** `TestGuardWithFlagOn` uses the current field names by POST. The other S17 forms are Story 16.1's.
- **Sign out after every sign-in.** (inference, AD-13 S13) A signed-in CSP session holds a licence connection.
- **Implement stage (3.8):**
  - `PasswordGuard.ROUTINE` is the literal `OcuTalonPasswordGuard`: `State`, `Restore` and `Source` run in `%SYS`, which holds no OcuTalon class to ask for the step's parameter. `State()` also returns the routine's source (third element), so `Restore` can write back a routine that existed before the test.
  - The sign-in change on build 154 answers HTTP 303, not 200 (planning measured 200 for another request shape). The tests do not pin the status. `TestGuardWithFlagOn`'s control user, whose password the same request changes, proves that the request reaches the password path, and the `Guard not called` mutation shows the public accounts' password changing without the guard.
  - `TestForeignGuardIsRefused` creates a real foreign routine `ZzForeign` (entry `ZzOther`, allows every password) in `%SYS` and deletes it afterwards: a setting that names a missing routine refuses every password change, including the README account's create in the flag-off run.
  - The reserve-against-cap refusal names `OCUTALON_CONNECTION_RESERVE`. The reserve is checked against the effective cap, so an unset reserve (2) with a cap of 2 is refused.
  - `Users.CompileQuietly` opens the null device around `Compile("-d")` so the empty line it prints stays off the start log. Its effect is not asserted by a test; the flag-on start is not run by the live units.
  - The step's start variables map in one parameter, `Public.VARIABLES` (`public:<key>` or `decide:<setting>`); defaults and rules are in `Default` and `Rule`.

**For the lead:**
- **The veto window.** No item is owner-only.
  - Security posture: on the online demo the installer sets the instance-wide `PasswordValidationRoutine` and writes a generated routine into `%SYS` (IRISSYS) holding the public accounts' lower-cased names and salted SHA-512 hashes of their published passwords. AC 2 and AD-13 mandate the routine; the storage is this plan's.
  - A start can now fail on a malformed online-demo start value (the error names the variable).
  - New admin-facing texts: the guard's refusal, the Public step's refusals, and `Unguard`'s warning. None is UX text.
- **Rule 20.** Two candidates:
  - AD-13's "Tested fallback" bullet, or a Conventions row: the routine `Check^OcuTalonPasswordGuard`, generated by the Users step at every flag-on start before the accounts' passwords, removed with the flag off, a foreign routine refused.
  - A sentence in AD-19's start-values paragraph: a malformed value fails the `Public` step, naming the variable. Story 29.3's deployment and Story 16.1 plan from the spine.

**Integration ACs:**
- `Budget.State()` and `Decide`'s precheck consume the rows `Public.Run()` writes: the decision falls back with `daily_cap` and nothing reaches the mock (row 7).
- The Users step consumes the keys `Public.Run()` writes: the accounts hold the published passwords, and the guard refuses a sign-in change (row 6).
- `Public.Ready()` consumes `Users.PinTrace` (row 8).
- IRIS's password paths consume the guard (rows 9 and 10).

**Consumes:**
- From Epic 0: `Public.Settings`, the registry and `Production.WriteDefault`.
- From Story 3.1: `Users.Accounts`, `EnsurePublic` and `PinTrace`.
- From Epic 1: `Budget.State`, `Decide.Precheck`, `RunnerFixture` and the mock.

**Consumed-by:**
- **Story 16.1:** every public key; the guard against the S17 forms; a local install with no routine and a seed cap.
- **Story 16.2:** the splash's accounts and allowance.
- **Story 16.5:** the cap and the reserve.
- **Story 16.6:** the probe restores the published passwords, which the guard allows.
- **Story 16.8:** the reset keys and `NextReset`.
- **Story 16.9:** the cost cap's banner and message, through `BridgeSink`.
- **Story 29.3:** the deployment sets the variables, the gateway's spend among them.
- **Story 14.2:** the overview lists the guard.

**Cross-epic:**
- **Epic 13:** none. The rows are scoped to `OcuTalon.Production`, and neither `Budget` nor the bridge's settings change.
- **Lane B:** `Test.Data.PublicSettings.TestPublicStep` is unaffected (flag off, readiness cleared).

**Rule 2 (extend, don't copy):**
- Extended: `Public`, `Users` (`Accounts`, in the `Disable` and `Refuse` style) and `Test.Install.Users`.
- Reused: `Production.WriteDefault`, `RunnerFixture`, `KeyScan` and `Mock`.
- **A copy, with its reason.** Row 7's glue repeats the shape of `Test.Agent.Decide`'s private `Prepare`, `SwapSink` and `AssertNotSent` in a few lines. They are private methods of another epic's test class, and the public `RunnerFixture` calls do the work.
- `PasswordGuard` holds the one copy of the guard's save, restore and sign-in helpers.

**Footprint:**
- Every edit is in `src/ocutalon/cls/OcuTalon/Install/**` and `Test/Install/**`.
- No footprint extension, and no contended path is edited.

**Ledger inbox:** DW-160 is addressed by row 8, the `Public.cls` task and the DW-160 acceptance bullet.

**Shard time (inference):**
- **The new tests add about 20 to 35 s.** Row 7 dominates: `PointKeys`, `RestoreKeys` and the sink swap restart items. The guard compiles and the sign-ins take a second or two.
- **Expected fresh `lane-a`:** about 415 to 435 s, against 395 s after Story 3.7 and the 460 s line.
- **If the measured fresh `lane-a` passes 460 s,** the implement stage stops with a clarification and does not edit `ci/units.sh`. It reports the per-class times and proposes a third Lane A shard holding the Install area. That is a `ci/units.sh`-only change; `ci.yml` names only the groups:
  - `SHARDS="lane-a lane-a2 lane-b"`;
  - `shard_areas`: `lane-a)` "Agent Bridge Tools Digest" and `lane-a2)` "Install";
  - `group_units`' `shards)` line: `shard:lane-a shard:lane-a2 shard:lane-b`.

## Verification

**Targets:**
- `ocutalon-slot-a` (namespace `OCUTALON`) is for `iris_doc_load` compiles only, after `iris_server_info` shows build 154, with no security change there. Pass `server` and `namespace` on every MCP call.
- Everything else runs through `ci/iris.sh` and `ci/warm.sh`. Never `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, slot B or slot C. No push, and never read `.env`.
- Run each command from the worktree root, in the foreground with `timeout: 600000`, one per call.
- The tags: fresh `e3s8i` and warm `e3s8iw` (implement); `e3s8q` and `e3s8qw` (QA); `e3s8r` and `e3s8rw` (review). Each stage puts its own tags and stage name on the line.
- Warm runs reload classes only. The start (the after-start `Public` and `Users` with the flag off) is proved by the fresh `live` units.

**Commands:**
- (loop) `bash ci/checks.sh` -- expected: every block passes. About 20 s.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s8iw bash ci/warm.sh up` -- expected: a ready warm stack (about 60 s). Run it once at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e3s8iw bash ci/iris.sh class <Class>`, one call per class -- expected: `CLASS ... passed` after a `WARM reloaded` line. The classes: `OcuTalon.Test.Install.Public`, `OcuTalon.Test.Install.Users`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Data.PublicSettings` and `OcuTalon.Test.Bridge.Budget`.
- (loop) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s8iw bash ci/warm.sh down` -- at the stage's end, and after a failure.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s8i bash ci/iris.sh shard lane-a` -- expected: every class passes, in about 415 to 435 s. Run it alone in its call. Record the time and the times of `Install.Public` and `Install.Users`.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s8i bash ci/iris.sh shard lane-b` -- expected: every class passes (`Data.PublicSettings` included). About 75 s.
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s8i bash ci/iris.sh live install-start` -- expected: PASS (`onlineDemo` 0, ready 1, `STEP Public OK`).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s8i bash ci/iris.sh live install-upgrade` -- expected: PASS (row 7's failed start still leaves readiness empty).
- (once) `OCUTALON_LOCK_DIR="$(cd ../.coordination/locks/lane-a && pwd)" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=3 stage=implement' OCUTALON_RUN_TAG=e3s8i bash ci/iris.sh teardown` -- expected: nothing tagged `e3s8i` is left.

**Shared surfaces:**
- **The cap row.** Every flag-off start now leaves the System Default Settings row (`OcuTalon.Production`, `Decide`, `*`, `DailyCostCapUSD`) = 0. Search the test trees for tests that assert no such row or count the rows. `Test.Bridge.Budget`, `Test.Bridge.Decide`, `Test.Agent.Decide` and `WebStatus` snapshot and restore their rows.
- **`Public.Run()`** now clears readiness, and with the flag on writes every key and the three rows. `Test.Data.PublicSettings.TestPublicStep` (flag off) stays green.
- **The password-validation setting and the routine.** The instance-wide `PasswordValidationRoutine` and the `%SYS` routine `OcuTalonPasswordGuard` are set by every flag-on `Accounts` call. `Test.Install.Users` and `Test.Install.Public` restore both after every test.
- **The public keys, readiness and the fixture names' `^EnsPortal.Settings` pins in both namespaces.**
- **During row 7:** `Decide`'s `HostSinkClass`, the runners' Config Store keys, today's day mark, and the test's `Usage` rows.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to record** (Rule 19; record each as `mutation: ... -> ...` here):

| AC | Pinning test | Mutation that must turn it red |
| --- | --- | --- |
| AC 1 | `Test.Install.Public.TestEveryStartValue`, `TestDefaults` | `Run` skips `messageAllowance`; or the `connectionCap` default is dropped |
| AC 1 | `TestFlagOffWritesOnlyTheFlag` | `Run` writes the other keys with the flag off |
| AC 1 | `TestBadStartValues` | the reserve-below-cap check is removed |
| AC 2 | `Test.Install.Users.TestGuardWithFlagOn` | the guard stores the name as published and compares it exactly; or `Check` returns 1 for every password |
| AC 2 | `TestInstallerWritesAChangedPassword` | `Accounts` writes the accounts before it regenerates the guard |
| AC 2 | `TestNoGuardWithFlagOff` | `Unguard` leaves the setting |
| AC 3 | `Test.Install.Public.TestBudgetRows`, `TestFlagOffWritesOnlyTheFlag` | the cap's default is 0; or the seed overwrites an existing row |
| AC 4 | `TestDecisionAtTheCap` | `Run` does not write `GatewaySpendUSD` (the decide reaches the mock) |
| AC 4 | `TestStartValuesReachTheUsersStep` | `Guard` is not called |
| DW-160 | `TestReadyPinsThePublicAccounts` | `Ready` does not call `PinTrace` |

Mutations demonstrated (implement stage, warm stack `e3s8iw`; each applied, observed red, reverted byte-identical with `cmp`, and the class green again on the same stack):
- mutation: `Public.Default` drops the `connectionCap` default (8) -> `Test.Install.Public.TestDefaults` red (the run is refused for the unset cap, so `TestStartValuesReachTheUsersStep` goes red too)
- mutation: `Public.RunLocal` also writes `messageAllowance` with the flag off -> `Test.Install.Public.TestFlagOffWritesOnlyTheFlag` red
- mutation: the reserve-below-cap check in `Public.StartValues` removed -> `Test.Install.Public.TestBadStartValues` red (reserve equal to the cap is accepted and written)
- mutation: `Users.WriteGuard` stores the account name as published, not lower-cased -> `Test.Install.Users.TestGuardWithFlagOn` and `TestInstallerWritesAChangedPassword` red (the self-check refuses the routine)
- mutation: `Users.Accounts` calls `Guard` after the accounts are written -> `Test.Install.Users.TestInstallerWritesAChangedPassword` red (the old guard refuses the new published password)
- mutation: `Users.Unguard` returns before clearing the setting -> `Test.Install.Users.TestNoGuardWithFlagOff` red
- mutation: `Public.DEFAULTCAP` is 0 -> `Test.Install.Public.TestBudgetRows` red
- mutation: the seed in `Public.RunLocal` always writes (the `%GetSetting` check removed) -> `Test.Install.Public.TestFlagOffWritesOnlyTheFlag` red (an existing cap row of 7 is overwritten)
- mutation: `Public.Run` skips the `GatewaySpendUSD` row -> `Test.Install.Public.TestDecisionAtTheCap` red (not capped, the decide reaches the mock)
- mutation: `Users.Accounts` does not call `Guard` -> `Test.Install.Public.TestStartValuesReachTheUsersStep` red (the sign-in change succeeds)
- mutation: `Public.Ready` does not call `PinTrace` -> `Test.Install.Public.TestReadyPinsThePublicAccounts` red
- mutation: `Public.Run` skips the `messageAllowance` key -> `Test.Install.Public.TestEveryStartValue` red (`TestDefaults` and `TestEmptyCountsAsUnset` too)
- mutation: the real-time clause (`$ZDateTimeH`) removed from the `time` rule of `Public.Accepts` -> `Test.Install.Public.TestBadStartValues` red (`2026-02-30T00:00:00Z` and `2026-10-25T25:00:00Z` are accepted)
- mutation: the flag compared as a number (`+GetEnviron(...) '= 1`) in `Public.Run` -> `Test.Install.Public.TestOnlyOneIsOn` red (`01` and `1.0` turn the demo on)
- mutation: a variable that is set but empty counts as set (`Public.StartValues` applies the default only for an unset one) -> `Test.Install.Public.TestEmptyCountsAsUnset` red
- mutation: the seed check in `Public.RunLocal` looks only at the exact row (`%ExistsId`, not `%GetSetting`) -> `Test.Install.Public.TestFlagOffKeepsARowOfAnotherSpecificity` red
- mutation: `Users.Guard` sets the instance's validation routine before it writes the guard -> `Test.Install.Users.TestFailedGuardLeavesTheSetting` red
- mutation: `Users.CheckGuard` accepts any routine -> `Test.Install.Users.TestForeignGuardIsRefused` red

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The `Public` step reads AD-19's start values, checks them before it writes, and writes the twelve keys and, with the flag on, the three `Decide` rows (the cap's seed of 0 with the flag off); `Ready()` pins both public accounts' page size before readiness (DW-160). The Users step writes a salted-hash password guard into `%SYS` at every flag-on start, sets it as the instance's validation routine last, refuses a foreign routine, and removes its own guard with the flag off.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Install/Step/Public.cls` -- start values, checks, keys, rows, seed, `Ready()` pins.
- `src/ocutalon/cls/OcuTalon/Install/Step/Users.cls` -- `GUARDROUTINE`, `GUARDENTRY`, `CheckGuard`, `Guard`, `Unguard` and the new `Accounts` order.
- `src/ocutalon/cls/OcuTalon/Test/Install/PasswordGuard.cls` (new) -- the shared helpers for the guard's tests.
- `src/ocutalon/cls/OcuTalon/Test/Install/Public.cls` (new) -- 11 tests (rows 1 to 8, plus `TestOnlyOneIsOn`, `TestEmptyCountsAsUnset`, `TestFlagOffKeepsARowOfAnotherSpecificity`).
- `src/ocutalon/cls/OcuTalon/Test/Install/Users.cls` -- `TestGuardWithFlagOn`, `TestInstallerWritesAChangedPassword`, `TestNoGuardWithFlagOff`, `TestForeignGuardIsRefused`, `TestFailedGuardLeavesTheSetting`, and the guard's save and restore.

**Review.** 37 findings from four layers: 13 rows patched (sign-in status asserted; empty-as-unset, unreal-time and near-miss-flag tests; the failed-guard test; the wider-specificity seed test; `CheckGuardRoutine`'s namespace switch; three mutation lines), 1 deferred (domain-qualified names, medium unverified), 23 rejected with the reasons in the triage log. No high. Patched at entry verdict: medium 4, so a follow-up review is recommended; the unverified risk is that the new tests and the failed-guard patch were verified by mutation and by the fresh runs but not read by a second reviewer.

**Verification performed.**
- `bash ci/checks.sh`: all scripts passed.
- Warm stack `e3s8iw` (torn down): `Test.Install.Public`, `Test.Install.Users`, `Test.Install.Registry`, `Test.Data.PublicSettings` and `Test.Bridge.Budget` passed after every mutation was reverted; 18 mutations went red on the named tests (the table above).
- Fresh stack `e3s8i` (torn down, nothing left): `shard lane-a` passed (47 classes) in 412 s inside the tool, 419 s measured by the stage (line 460 s; `Install.Public` 8.9 s, `Install.Users` 0.6 s); `shard lane-b` passed (24 classes, 75 s); `live install-start` and `live install-upgrade` passed.
- Slot A: one `Users.cls` compile by the handoff subagent; no security change there.

**Residual risks.**
- The flag-on start itself (real environment variables, the Registry order, the start log after the guard's compile) is not run anywhere in this story; Lane B's Stories 16.1 and 16.2 run it. `CompileQuietly`'s null-device redirect is unasserted.
- The sign-in password change answers 303 on build 154; the tests assert only that the request is answered and that the password stays.
- The guard replaces the live routine before the new one is verified: a failed compile on a later start leaves the setting naming a routine that may refuse every change (fail-closed).
- Multiple-domain instances (the deferred item).
- Shard time is 412 s of the 460 s line; the next Lane A story that adds tests should measure it.
