---
title: 'Story 4.1: Switch demo mode from the terminal'
type: 'feature'
created: '2026-10-25'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Demo mode is only a seed value today: `SettingsOps` is a stub, `OcuTalon.Core.Admin` does not exist, and nothing at run time can switch demo mode, audit the switch and add or remove OCUORDERS. An admin has no documented way to turn the demo on (IPM install) or off (Docker install).

**Approach:** Add `OcuTalon.Core.Admin.SetDemoMode(mode)`, which checks the caller's role and submits `SetDemoMode` through `Commands.Submit` with origin `system`. Build `SettingsOps` as the only run-time settings writer: an allow-list of one key (`demo.mode`), an audit entry through `Bridge.Audit`, the value through a new `Setting.Set`, then a rerun of `Install.Step.Demo`. It answers a plain-English `CommandResult`, which the terminal prints. The page, `/state` and `Notify` already read the setting.

## Boundaries & Constraints

**Always:**
- The command goes `Admin` → `Commands.Submit(cmd, "system")` → `CommandsIn` (routes `SetDemoMode` to `SettingsOps` for `web_admin,system` only and refuses `tool`; already built) → `SettingsOps`.
- `Admin` checks the role before anything is submitted. Allowed: `$ROLES` holds `OcuTalonAdmin` (strict, as AD-19's Rule reads; a `%All` holder without `OcuTalonAdmin` is refused: lead ruling on V1, veto, see Design Notes). A refusal prints `CommandsIn`'s `MESSAGEADMINONLY`, submits nothing and changes nothing.
- `Admin` sets `ActingUser` from `$USERNAME`, never from an argument.
- `SettingsOps` is the only run-time writer of `OcuTalon.Data.Setting`, and it writes only keys on its `ALLOWLIST` parameter (`demo.mode` in release 1).
- For every accepted `SetDemoMode`, `SettingsOps`:
  - writes the `Settings` audit entry first;
  - then writes the value (`"1"` or `"0"`);
  - then runs `Install.Step.Demo.Run()`, takes its warnings with `Install.Step.TakeWarnings()`, and answers.
- It never answers an error status. Every answer is a `CommandResult` with `Ok`, `Outcome` and `Message`.
- The audit event data is `{"user", "sessionRef", "channel", "origin", "setting", "value"}`, passed through `Bridge.Redact.Text`:
  - `user` is the command's `ActingUser`;
  - `channel` is `system` for origin `system` and `web` for `web_admin`.
  - The key is `user`, never `username`, because the redactor treats `username` as sensitive.
- Product values apply by `Setting.Get`'s 60-second cache. `Setting.Set` drops its own process's cache entry.
- Destructive checks (the switch adds or removes OCUORDERS) run only on lane-B throwaways (`ci/iris.sh`), never on slot B.

**Never:**
- Edit a contended path. That includes `Core/Commands*.cls`, `Install/**` other than `Install/Step/Demo.cls`, `Data/{StatusMark,Time,Reminder}.cls`, `Data/Public/**`, `src/bridge/**`, `docker/**` other than a new `docker/tests/` script, `web/src/app/api/**`, `Test/Contract/Ac.cls` and `.github/**`. A need to edit one stops the story with `## Clarification Needed`.
- No change to `Install.Step.Demo` (the seed, the grants and the keep path are Story 0.10/0.12's and already meet AC 1), to `Web.Api` (the demo routes stay Story 0.5's 501 and `/state` already reads `demo.mode`) or to the page.
- No new live event, no role or grant change, no `%Development` for any OcuTalon role (AD-24).
- No terminal text other than the texts listed under Design Notes (V2).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Off, `OcuTalonAdmin` holder | Docker throwaway with demo on. The admin fixture of the next row runs `do ##class(OcuTalon.Core.Admin).SetDemoMode(0)` | It prints T2. The `demo.mode` row is `"0"`. An `OcuTalon/Settings` audit entry has `user` set to the admin fixture and `value` `"0"`. OCUORDERS, its databases, the mappings, `/ocutalon/trace/ocuorders/`, the trace role's OCUORDERS grants and its SQL privilege are gone, and the Orders production is stopped. | none |
| On, `OcuTalonAdmin` holder | A user with `OcuTalonAdmin,%Developer,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,OcuTalonUser` (no `%All`), demo off | It prints T1. The row is `"1"`. OCUORDERS, the trace app and the grants exist, and the Orders production runs with `OrdersFromPartner` and `OrdersToWarehouse` alive. The audit `user` is that user. | none |
| Refused | A user with `%Developer,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,OcuTalonUser` and no `OcuTalonAdmin`; also `irisowner` (`%All`, no `OcuTalonAdmin`; V1 ruling) | It prints `MESSAGEADMINONLY`. No header goes to `SettingsOps`. The row, OCUORDERS and the audit log are unchanged. | Outcome `not_allowed` |
| Bad argument | `SetDemoMode(2)`, `("on")`, `()` | It prints T6, and nothing is submitted. Only `0` and `1` (number or string) are accepted. | Outcome `invalid` |
| No production | `Submit` returns an error status | It prints T7, and nothing changes. | Outcome `not_running` |
| Submit throws | for example `<PROTECT>` for a user without write access to OCUTALON_DATA | It prints T8 with the error, and nothing changes. | Outcome `failed` |
| Same mode again | `SetDemoMode(1)` with demo on | Audited, written and the step rerun (idempotent). It prints T1. | none |
| Off, foreign OCUORDERS | The step's keep path, which records `demoKept` | `Ok 1`, `off_kept`. It prints T3 with the `demoKept` note's `how` sentence. | none |
| Step fails | `Install.Step.Demo.Run()` returns an error | `Ok 0`, `step_failed`, T4 with the error sentence. The row keeps the new value, so the next start converges. | answered, never thrown |
| Audit fails | `Bridge.Audit.Write` is not OK | `Ok 0`, `not_audited`, T5. Nothing is written and the step does not run. | answered |
| Other command | Any class other than `OcuTalon.Msg.Command.SetDemoMode` reaches `SettingsOps` | `Ok 0`, `unknown_command`, `CommandsIn.#MESSAGEUNKNOWN`. Nothing is written. | answered |
| Key off the list | The guarded write is given `digest.time` | It is refused with an error status, and no row is written. | status |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:1-14` -- the stub (`STUB` 1, `NotImplemented`). It becomes the real business operation. Production item `SettingsOps`, pool 1, already in `Production.cls:66`.
- `src/ocutalon/cls/OcuTalon/Core/CommandsIn.cls` (read-only, contended):
  - `:38` `MESSAGEADMINONLY`, `:46` `MESSAGEUNKNOWN`, `:50` `MESSAGEFAILED`: reuse these texts;
  - `:92-95` the private `Send` seam that a test subclass overrides: the pattern for `SettingsOps`'s seams;
  - `:172` the route of `SetDemoMode`: `SettingsOps`, `web_admin,system`.
- `src/ocutalon/cls/OcuTalon/Core/Commands.cls:18` (read-only, contended) -- `Submit(command, origin, Output result)`: it sends to `CommandsIn` in the caller's process. An error status means it never reached `CommandsIn`.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetDemoMode.cls:6,8-18` -- `DemoMode` %Boolean. `ActingUser` is added here (V3).
- `src/ocutalon/cls/OcuTalon/Msg/CommandResult.cls` -- `Ok`, `Message`, `Outcome`.
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- `Get` (`:26`, 60-second per-process cache `^||OcuTalon.Setting`), `Seed` (`:44`) and `IsPublic` (`:58`). `Set` is added beside `Seed` and shares its key checks (Rule 2).
- `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` (unchanged):
  - `MODEKEY` (`:36`) and `KEPTMARK` (`:51`);
  - `Run()` (`:70`) reads the mode through `Mode()` (`:130`, seed then get) and records the `demoKept` mark;
  - `DefaultMode()` (`:137`) seeds `"1"` where `/opt/ocutalon/version` exists;
  - the keep note's `how` sentence (`:363`).
- `src/ocutalon/cls/OcuTalon/Install/Step.cls:52,58` -- `Warn` and `TakeWarnings` ("code that runs a step on its own takes them").
- `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls:39` (read-only, contended) -- `Get("demoKept")`: the JSON note with `how`.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls:31` (read-only) -- `Write(type, data As %DynamicObject, description)`. Types include `Settings`.
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls` (read-only) -- `Text(text)`. `SENSITIVEKEYS` (`:32`) includes `username` and `userid`.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Functions.cls:19` and `Core/Rule/Notify.cls:42-47` -- `DemoOn()` reads `Setting.Get(MODEKEY)`, so `Notify` adds `SimPhoneOut` only while demo mode is on. On/off is already tested in `Test/Core/Routing.cls` (TestNotifyTargets).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls:280` (`/state` `demoMode` from `Setting.Get`) and `:60-63` (the demo routes are `NotBuilt` 501). Both unchanged.
- `web/src/app/header/header.ts:358-364` -- the badge reads "Demo mode" when `snapshot.demoMode` is true. `web/src/app/live/live-state.ts:32` -- the snapshot loads once per page load (and again on a Seq skip or a new epoch).
- `src/ocutalon/cls/OcuTalon/Test/Demo/Step.cls:125-165` -- `Saved`, `Put`, `Remove` and `PutBack`: the shared save and restore of the `demo.mode` row. Reuse them.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Source.cls` (read-only reuse) -- `Text`, `Lines` and `Matches` over compiled class source, with comment lines dropped.
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProbe.cls`, `CommandsOwner.cls` -- driving a host through `##class(Ens.Host).GetShadowInstance("class||<Class>", .sc)` and calling `OnMessage`.
- Shared rows that this story rewrites:
  - `Test/Core/CommandsInProduction.cls:24-56`, the `SettingsOps` row of the stub table ("each owner's story rewrites its row");
  - `Test/Core/ProductionItems.cls:32` (`stub` 1);
  - `Test/Msg/Contracts.cls:309-317`, the `SetDemoMode` oracle.
  - `Test/Contract/Ac.cls:219` (contended) checks only that the named properties exist, so a superset passes.
- `docker/tests/lib-live.sh` (read-only, contended) -- `iris_script` (`:307`), `live_fixture_user` (`:320`), `demo_surfaces` (`:711`), `compare_surfaces --drop-orders` (`:736`), `check_orders_jobs` (`:767`), `check_demo_on` (`:791`) and `check_demo_off` (`:853`).
- `docker/tests/test-bundle-folder.sh:151-152` -- the curl sign-in with a cookie jar (README account). `docker/tests/test-sign-in.sh:200-230` -- running a Playwright npm script from a live unit.
- `ci/units.sh:28-41` -- `group_units` and `BROWSER_UNITS`. `docker/tests/test-ci-config.sh` pins that every `docker/tests/test-*.sh` belongs to exactly one group, and that a script that runs Playwright is in `BROWSER_UNITS`. No `ci.yml` change is needed for a unit added to an existing group.
- `web/playwright.config.ts` -- the projects. `chromium` runs everything except `e2e/demo-path/` and `e2e/floor/`.

## Tasks & Acceptance

**Execution:**
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Command/SetDemoMode.cls` -- add `Property ActingUser As %String(MAXLEN = 160)` ("the IRIS user who asked; set by the submitting code from its authenticated context"), with its storage value -- so that the audit entry names the person (AD-17; V3).
- [ ] `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- add `ClassMethod Set(key, value) As %Status`:
  - it upserts the row with `UpdatedAt` from `Data.Time.NowUtc()` and kills this process's cache entry;
  - it refuses an empty key or a public key exactly as `Seed` does, sharing one private check.
  - Its doc comment says that `SettingsOps` is its only caller -- the run-time writer API (AD-19).
- [ ] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- remove `STUB` and implement `OnMessage` as the Boundaries describe:
  - `Parameter ALLOWLIST = "demo.mode"`;
  - a private guarded write `Apply(key, value)`, which refuses keys off the list;
  - a private `WriteAudit(data)` seam (`Bridge.Audit.Write("Settings", <redacted data>, "Demo mode set to on|off")`);
  - a private `RunStep(Output kept, Output warnings)` seam (`Install.Step.Demo.Run()`, `TakeWarnings()`, and `StatusMark.Get("demoKept")`'s `how` when the mark is set);
  - the texts T1 to T5, and the outcomes `on`, `off`, `off_kept`, `step_failed`, `not_audited`, `unknown_command` and `failed`;
  - an error thrown inside is logged once (`$$$LOGERROR`) and answers `failed` with `MESSAGEFAILED`.
- [ ] `src/ocutalon/cls/OcuTalon/Core/Admin.cls` (new) -- the admin terminal entry point:
  - `ClassMethod SetDemoMode(mode As %String = "") As OcuTalon.Msg.CommandResult` validates `mode`, checks `..Allowed($ROLES)`, builds the command with `ActingUser = $USERNAME` and calls `Commands.Submit(cmd, "system", .result)`;
  - it writes the result's `Message` on a line of its own and returns the result;
  - its local answers (`invalid`, `not_allowed`, `not_running`, `failed`) are unsaved `CommandResult`s;
  - `ClassMethod Allowed(roles As %String) As %Boolean` is pure: 1 when the comma list holds `OcuTalonAdmin`, by whole name (`%All` alone gives 0: V1 ruling).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls` (new) -- a subclass of `SettingsOps` that overrides `WriteAudit` and `RunStep`:
  - it records each call in `^OcuTalonTest("SettingsOpsProbe", ...)` (the data object as JSON, and the value `Setting.Get(MODEKEY)` reads inside `RunStep`);
  - it answers from that global (OK, an error, or a `demoKept` note it records through `StatusMark.Record`, saved and restored by the test).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls` (new, lane-b shard) -- drives a shadow instance of the probe. It saves and restores the `demo.mode` row with `Test.Demo.Step`, the probe global and the `demoKept` mark. Tests:
  - TestSwitch: with `DemoMode` 0 and 1, `Ok 1`, `off` or `on`, T2 or T1. The row value and `UpdatedAt` are written. The audit call came first and the step ran after the write (the probe saw the new value). The event data has `user`, `sessionRef`, `channel` `system`, `origin` `system`, `setting` `demo.mode` and `value`.
  - TestKept: `off_kept`, with T3 built from the note's `how`.
  - TestStepFails: `step_failed`, T4 carries the error sentence, and the row keeps the new value.
  - TestAuditFails: `not_audited`, T5, the row is unchanged, and the step did not run.
  - TestOtherCommand: `unknown_command`, and nothing is written.
  - TestAllowList: `ALLOWLIST` is exactly `demo.mode`, and `Apply("digest.time", "x")` is refused with no row.
  - TestOnlyRunTimeWriter: a scan with `Test.Bridge.Source` over every compiled `OcuTalon.*` class outside `OcuTalon.Test`, and outside `OcuTalon.Data.Setting` itself.
    - Writers of `OcuTalon.Data.Setting` (`Set(`, `%New(`, `%OpenId(`, `%Open(`, `KeyIndexOpen(`, `%DeleteId(`, `%Delete(`, or `^OcuTalonP.Setting`) appear only in `OcuTalon.Core.SettingsOps`, and `Seed(` only under `OcuTalon.Install`.
    - The scanner is first shown to flag synthetic violators and to pass a comment-only mention.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/Admin.cls` (new, lane-b shard):
  - TestAllowed: `OcuTalonAdmin`, `%All,OcuTalonAdmin` and `%Developer,OcuTalonAdmin` give 1; `%All`, `OcuTalonUser,OcuTalonTraceViewer`, `""` and `OcuTalonAdmins` give 0.
  - TestInvalidArgument: `2`, `"on"`, `""` and `"01"` give `invalid` with T6, no header to `SettingsOps` (count before and after) and an unchanged row.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Setting.cls` -- add TestSet:
  - it writes an absent key and overwrites a present one, with `UpdatedAt`;
  - `Get` in this process sees the new value at once over a fresh cache entry;
  - it refuses an empty key and a public key, and writes nothing then.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` -- add `"ActingUser": "%String(MAXLEN=160)"` to the `SetDemoMode` oracle.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:32` -- set `SettingsOps` to `"stub": 0`.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` -- take `SettingsOps` out of the stub table and give it its own assertion:
  - `SetDemoMode` from `system`, with the mode the stack already has, answers status OK with `Ok 1`, outcome `on` or `off` and T1 or T2;
  - it reaches `SettingsOps` once, and the answer is one response header that is not an error;
  - update the class header.
- [ ] `docker/tests/test-demo-switch.sh` (new; unit `live:demo-switch`) -- one fresh Docker throwaway, using only lib-live's helpers plus a local curl sign-in. A copy of test-bundle-folder's two lines, because `lib-live.sh` is contended (Rule 2 reason). In order:
  1. First start (demo on). Sign in as the README account. Post one chat message and wait for its reply. Record `/state`'s `chat` and `rail` (S0) and `demoMode` true. Record `demo_surfaces` (F0) and the audit mark.
  2. Control: a tell-now Notification sent into `Notify` from a host made with `CreateBusinessService` (as `Test.Core.RoutingProduction` does) leaves a header to `SimPhoneOut`.
  3. Create two fixtures with `live_fixture_user` (the Refused and On rows of the matrix; passwords through the environment). The non-admin logs in with `$SYSTEM.Security.Login` and runs the command, and so does `irisowner` (the session's OS login, `%All` without `OcuTalonAdmin`; V1 ruling): the exact refusal line is printed; the row, the `SettingsOps` header count and the surfaces are unchanged.
  4. As the admin fixture, run `SetDemoMode(0)`: T2 is printed. The row is `"0"`. `compare_surfaces --drop-orders` against F0 passes, and `check_demo_off` passes.
  5. Every `/state` answer from 61 s after step 4 returned reports `demoMode` false (polled every 2 s from the start), and `chat` and `rail` equal S0. `POST /v1/demo/break-feed` still answers 501 `not_built`. A new tell-now Notification leaves no header to `SimPhoneOut`. `npm --prefix web run e2e:demo-switch` with `OCUTALON_E2E_DEMO_MODE=0` passes.
  6. As the admin fixture, run `SetDemoMode(1)`: T1 is printed. `check_demo_on` and `check_orders_jobs` pass, and `compare_surfaces` against F0 passes.
  7. Poll `%SYS.Audit` from the mark, up to 180 s, for `OcuTalon/Settings/Settings` entries:
     - one with the admin fixture and `value` `"0"`;
     - one with the admin fixture and `"1"`;
     - none naming the non-admin or `irisowner`.
  8. From 61 s after step 6, `/state` reports `demoMode` true and `chat` and `rail` equal S0. The e2e script with `OCUTALON_E2E_DEMO_MODE=1` passes.
  - It prints PASS or FAIL lines and keeps a local deadline, like the other live units.
- [ ] `web/e2e/demo-switch/badge.spec.ts` (new) -- signs in as the README account and loads `/ocutalon/`:
  - with `OCUTALON_E2E_DEMO_MODE=1`, `.context-badge` reads "Demo mode";
  - with `0`, there is no `.context-badge` and the chat region is shown;
  - without the variable it fails at once, naming the variable.
- [ ] `web/playwright.config.ts` and `web/package.json` -- add a project `demo-switch` (`testDir: './e2e/demo-switch'`, Desktop Chrome), add `**/e2e/demo-switch/**` to the `chromium` project's `testIgnore`, update the header comment, and add the script `"e2e:demo-switch": "playwright test --project=demo-switch"`.
- [ ] `ci/units.sh` -- add `live:demo-switch` to one group, and `demo-switch` to `BROWSER_UNITS`.
  - The group is the one whose job was shortest in the latest green `ci` run of `feature/OCT_OcuTalon_MVP` (read with `gh run view`, read-only).
  - Record the job times and the unit's local duration under `## Verification`.
  - `live:demo-switch` checks the web bundle, so it stays out of `NO_WEB_BUNDLE_UNITS`.
- [ ] Task 0 (measure, on the first fresh `live:demo-switch` run, once `SettingsOps` and the unit exist) -- confirm that `Install.Step.Demo.Run()` succeeds inside the real `SettingsOps` job, both off and on. The plan measured it only from a process registered as the CommandsIn host (Design Notes, M5).
  - If it fails only inside the job, wrap the call in `New %Ensemble`.
  - If that also fails, run the step in a JOBbed process that returns its status and warnings, and wait for it inside `CommandsIn`'s 120 s timeout.
  - Record which form held, with the off and on durations, under `## Verification`.

**Acceptance Criteria:**
- Given a fresh install, when it first starts, then demo mode is `"1"` on the Docker install and `"0"` without the image's version file (IPM), written as a seed that a later write survives at restarts and upgrades.
  - No code changes for this. It is already pinned by `Test.Demo.Step` (TestDefaultMode, TestMode) and `live:install-start` row 6.
  - The implement stage records the mutation `DefaultMode()` returns 1 unconditionally → TestDefaultMode red.
- Given an `OcuTalonAdmin` holder in a terminal in OCUTALON, when they run `do ##class(OcuTalon.Core.Admin).SetDemoMode(0|1)`, then `live:demo-switch` steps 4, 6 and 7 hold: the printed line, the row, the audit entry naming them, and OCUORDERS removed or created with the Orders production stopped or running.
- Given a terminal user without `OcuTalonAdmin` (a `%All` holder included: V1 ruling), when they run it, then it prints `MESSAGEADMINONLY`, nothing reaches `SettingsOps` and nothing changes (`live:demo-switch` step 3).
- Given a switch, when 61 s have passed, then (integration: consumers read what `SettingsOps` wrote):
  - `/state` (consumer `Web.Api`) reports the new value;
  - the page (consumer `header.ts`) shows or drops the badge at its next load;
  - the real `Notify` router stops or resumes routing to `SimPhoneOut`;
  - the conversation and rail are unchanged, and the demo routes still answer 501 (`live:demo-switch` steps 2, 5 and 8).
- Given `SettingsOps`, when any command reaches it, then it is the only run-time writer of settings, writes only `demo.mode`, and a value applies within 60 s by cache expiry: TestOnlyRunTimeWriter, TestAllowList and TestOtherCommand, plus `Test.Data.Setting`'s existing cache-expiry test.

## Spec Change Log

- 2026-10-25, spec gate (runner): V1 ruled strict (`OcuTalonAdmin` only; `%All` alone refused) per AD-19 as written (U7 step 1); V2 and V3 kept as veto items; rows, tasks and criteria updated to match.

## Review Triage Log

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- AD-1: Submit only, origin from the authenticated context, `tool` refused, role checks at the admin entry point.
- AD-3: only `Install.Step.Demo` switches namespace, and it runs whenever the setting changes.
- AD-12: snapshot plus polling; no event type for settings.
- AD-14: `Notify` sends to `SimPhoneOut` only in demo mode.
- AD-17: one audit writer; the event data names the user, the SessionRef and the channel and passes the redactor; tests read back by polling.
- AD-19: `SettingsOps` is the only run-time writer, with an allow-list, seed values, a 60 s cache and this terminal command.
- AD-22: destructive work only on throwaways.
- AD-23: a switch reruns only the Demo step, and the grants come back after the Roles step.
- AD-24: no role or grant changes.
- AD-29 and AD-33: Lane B owns `SettingsOps`, `Setting`, `SetDemoMode` and `Admin`.

**Dependency edge.** `SettingsOps` (Core) calls `Install.Step.Demo.Run()`. The AC and AD-23 ("a demo-mode switch reruns only this step") require it. The spine's dependency diagram has no Core → Install arrow, though `Core.Rule.Functions` and `Web.Api` already read `Install.Step.Demo.#MODEKEY`. For the lead: add the arrow under Rule 20 (conv).

**Measured on the lane-B throwaway `e4s1pw` (2026-10-25, ARM, the Docker image; torn down):**
- M1: `iris session IRIS -U OCUTALON` logs in as `irisowner` with `$ROLES` `%All` (OS auth; `%Service_Terminal` AutheEnabled 48, public `U`).
- M2: the README account (`OcuTalonAdmin,OcuTalonTraceViewer,OcuTalonUser`) gets "Access Denied" at its first programmer-mode command after `$SYSTEM.Security.Login`. No OcuTalon role holds `%Development` (AD-24), and `OcuTalonAdmin` holds no resource.
- M3: a user with `%Developer,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,OcuTalonUser` submits `SetDemoMode` through `Commands.Submit` (the stub answered `not_built`). Write access to OCUTALON_DATA is enough; the private database is not needed.
- M4: that user's `Set $ROLES="OcuTalonAdmin"` throws `<PROTECT>`, so a `$ROLES` check can't be self-escalated.
- M5: `Install.Step.Demo.Run()` from a process registered as the CommandsIn host (`%Ensemble("ConfigName")` set): off 2.8 s, on 2.3 s, both OK, the Orders production Running. Not measured: the real job, which runs as the Interoperability user (Task 0).
- M6: a `Bridge.Audit.Write("Settings", ...)` entry became readable in `%SYS.Audit` after 57.3 s. Its `Username` column is the writing process's user, so the acting user must be in the event data.

**Veto-window items (for the lead; the spec is written with the recommended option):**
- **V1 (privileges, close to `%All`). A `%All` holder counts as holding `OcuTalonAdmin`. Recommended.**
  - Every default terminal session (M1: Docker `irisowner`; CI; an IPM install's superuser) holds `%All` and not `OcuTalonAdmin`. The README account can't type a command (M2).
  - Under a strict check, the documented command fails on every default install. Stories 10.2 (README), 11.2 (upgrade harness) and 15.2 (FR-57 job), which run it from such terminals, would first have to grant `OcuTalonAdmin`.
  - `%All` already holds every privilege, so accepting it grants nothing new. Alternative: a strict `OcuTalonAdmin` check.
  - If ruled, add "(a process holding `%All` counts as holding it)" to AD-19's Rule (Rule 20).
  - If vetoed: `Allowed` drops `%All`. `live:demo-switch` step 4 then runs as the admin fixture, and an `irisowner` attempt joins step 3 as a refusal. TestAllowed expects 0 for `%All`.
- **V2 (public text not in the UX or PRD). The terminal texts.** `{v}` is `on` or `off`. The refusal reuses `MESSAGEADMINONLY` ("Only an OcuTalon admin can change settings. Nothing was changed."), so it adds no text.
  - T1: "Demo mode is on. The Orders production runs in namespace OCUORDERS. Reload the OcuTalon page in a minute to see the change."
  - T2: "Demo mode is off. The Orders production is stopped and namespace OCUORDERS is removed. Reload the OcuTalon page in a minute to see the change."
  - T3: "Demo mode is off. " + the `demoKept` `how` sentence (Story 0.12's) + " Reload the OcuTalon page in a minute to see the change."
  - T4: "Demo mode is set to {v}, but the Demo step failed: {the error's text, without its ERROR #n: prefix}. OcuTalon runs the step again at its next start."
  - T5: "OcuTalon couldn't write the audit entry, so demo mode was not changed."
  - T6: "SetDemoMode takes 1 (on) or 0 (off). Nothing was changed."
  - T7: "OcuTalon isn't taking commands now: its production isn't running or CommandsIn is disabled. Nothing was changed."
  - T8: "OcuTalon couldn't submit the change: {error}. Nothing was changed."
- **V3 (schema). `SetDemoMode` gains `ActingUser`,** an additive property on a Lane B message. No in-footprint alternative exists: `Commands`/`CommandsIn` are contended, and `Ens.MessageHeader` carries no user.

**Lead rulings at the spec gate (runner, 2026-10-25; policy 9e90866):**
- **V1 -- strict check (veto).** AD-19's Rule reads "requires the OcuTalon admin role", and AD-19 is cited by other in-flight epics' specs (Epic 3's 3.1 and 3.2, Epic 10's 10.1, Epic 13's 13.1), so accepting `%All` would be an AD amendment the run may not make on its own (doctrine U7(c), U14). U7 step 1 (comply) applies: `Allowed` is 1 only when `$ROLES` holds `OcuTalonAdmin`; a `%All` holder without it (the default `irisowner` terminal) is refused with `MESSAGEADMINONLY`. The rows, tasks and criteria above are written for the strict check. Reversal (owner): accept `%All` too, which needs AD-19's Rule to say "(a process holding `%All` counts as holding it)" (owner decision, re-architecture across epics), then a one-line change to `Admin.Allowed`, TestAllowed and `live:demo-switch` steps 3, 4 and 7. Inbox item recorded by the runner.
- **V2 -- the terminal texts T1-T8 and "the page follows it at its next load" (veto, kept).** Public-facing text not in the UX or PRD, and AC 4's "the page follows it" read as the next snapshot load (no settings event exists under release 1's polling contract). Reversal: change a text; a periodic `/state` refresh in a later story.
- **V3 -- `SetDemoMode.ActingUser` (veto, kept).** An additive property on a Lane B message (stored message schema). Reversal: drop the property and take the user from the session in Story 18.1.
- **Dependency edge.** Added to the spine's dependency diagram under Rule 20 (`Core --> Install.Step.Demo.Run()`, AD-23); not an AD change.
- **CI placement.** `live:demo-switch` goes into the group with the most headroom by Rule 21's balance rule (the task's "shortest job" reading); record the reasoning under `## Verification`.

**Decided in-stage:**
1. Audit before write: no change is ever unaudited (AD-17, AD-19). If the save then fails, the entry records an attempt, and the answer is `failed` ("may not have finished").
2. Every accepted command audits, writes and reruns the step, even when the mode is unchanged. The step is idempotent and repairs a half-done switch.
3. "The page follows it" means that the page renders from `/state`, which it loads once per page load. An open page shows the change at its next snapshot load, and T1 and T2 say to reload.
   - A live push would need a new event type (a spine change under AD-33), a payload class and generated types in contended `web/src/app/api/**`.
   - Release 1's polling contract (owner-fixed value 3) has none.
4. A step failure keeps the new value. The Demo step runs at every start and reads the mode, so it converges.
5. The step runs in the `SettingsOps` job (M5); the fallback is in Task 0.
6. `Admin.Allowed` reads `$ROLES` (M4). The DB permissions of IRIS stay the boundary: the role check is the admin gate and the audit's subject, not a sandbox.
7. One new live unit, rather than a block appended to an existing script: the switch is destructive and needs its own stack. Estimated (inference): about 4 to 5 minutes on ARM, two fixed 61 s waits included, and about 8 to 10 minutes on the runner.
8. Arguments: only `0` and `1`, as a number or a string.

**Rule 2 (extend, don't copy):**
- `Setting.Set` extends `Seed`'s key checks.
- `SettingsOps`'s seams follow `CommandsIn.Send`.
- The texts reuse `CommandsIn`'s parameters.
- The row save and restore reuses `Test.Demo.Step`, and the scan reuses `Test.Bridge.Source`.
- The live unit reuses lib-live's demo helpers. The only copy is the two-line curl sign-in, because `lib-live.sh` is contended.

**Consumed-by:**
- Stories 4.2, 4.3 and 4.6: the demo-off 404 reads the `demo.mode` that `SettingsOps` writes.
- 10.2: the README quotes `SetDemoMode`.
- 11.2: the upgrade harness switches off with `SetDemoMode(0)`.
- 15.2: the FR-57 job switches on and off.
- 18.1: the settings page sends `SetDemoMode` from `web_admin` through the same `SettingsOps`, with `ActingUser` from the session's `IrisUser`.

**Consumes:**
- `CommandsIn` routing (Stories 0.6 and 2.3);
- `Bridge.Audit` and `Bridge.Redact` (0.4 and 1.x);
- `Install.Step.Demo` (0.10 and 0.12);
- `Setting.Get` (0.4);
- `/state` `demoMode` and the header badge (2.1);
- `Notify`'s `DemoOn` (2.7).

The integration checks run against a real throwaway, not a mock.

**Ledger:** no entries are owned by this story.

**For the lead -- footprint:**
- `Msg/Command/SetDemoMode.cls`, `Data/Setting.cls` (Lane B per AD-33), `Test/Msg/Contracts.cls` and `Test/Data/Setting.cls` are Lane B areas.
- `web/playwright.config.ts` and `web/package.json` are Lane B's web.
- `ci/units.sh`: the group entry and the `BROWSER_UNITS` line.
- New: `docker/tests/test-demo-switch.sh` and `web/e2e/demo-switch/`.

## Verification

`<lane B vars>` = Rule 21's `OCUTALON_LOCK_DIR` (the main checkout's `.worktrees/.coordination/locks/lane-b`), `OCUTALON_TEST_WEB_PORT=52802` and `OCUTALON_LOCK_OWNER='epic=4 stage=implement'`. The warm stack is started once with `<lane B vars> OCUTALON_RUN_TAG=e4s1iw ci/warm.sh up`, and ended with `ci/warm.sh down` (also after a failure). Fresh runs use tag `e4s1i`, then `ci/iris.sh teardown`. One command per foreground call (`timeout: 600000`).

**Commands:**
- `<lane B vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s1iw ci/iris.sh class OcuTalon.Test.Core.SettingsOps` (loop) -- expected: `CLASS ... passed`.
- `<lane B vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s1iw ci/iris.sh class OcuTalon.Test.Core.Admin` (loop) -- expected: passed.
- `<lane B vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s1iw ci/iris.sh class OcuTalon.Test.Data.Setting` (loop) -- expected: passed.
- `<lane B vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s1iw ci/iris.sh class OcuTalon.Test.Msg.Contracts` (loop) -- expected: passed.
- `<lane B vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s1iw ci/iris.sh class OcuTalon.Test.Core.ProductionItems` (loop) -- expected: passed.
- `<lane B vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e4s1iw ci/iris.sh class OcuTalon.Test.Core.CommandsInProduction` (loop) -- expected: passed.
- `<lane B vars> OCUTALON_RUN_TAG=e4s1i ci/iris.sh live demo-switch` (loop; fresh, destructive; also Task 0) -- expected: every line PASS, exit 0.
- `npm --prefix web run lint` (loop) -- expected: exit 0.
- `bash docker/tests/test-ci-config.sh` (loop) -- expected: all rules pass.
- `<lane B vars> OCUTALON_RUN_TAG=e4s1i ci/iris.sh shard lane-b` (once) -- expected: every class passed.
- `<lane B vars> OCUTALON_RUN_TAG=e4s1i ci/iris.sh shard lane-a` (once) -- expected: every class passed.
- `<lane B vars> OCUTALON_RUN_TAG=e4s1i ci/iris.sh live sign-in` (once; the `chromium` project after the config change) -- expected: PASS.
- `bash ci/checks.sh` (once) -- expected: every block passes.

**Planned mutations** (the implement stage applies each one, observes red, reverts, confirms `git status --short`/`git diff --stat` unchanged, and rewrites each as `mutation: ... → ...`):
- AC 1: `DefaultMode()` returns 1 → `Test.Demo.Step` TestDefaultMode.
- AC 2: `SettingsOps` skips `RunStep` → `live:demo-switch` step 4 (OCUORDERS still there), and TestSwitch.
- AC 2: the step runs before the write → TestSwitch.
- AC 2 (audit): drop the `WriteAudit` call → `live:demo-switch` step 7, and TestSwitch.
- AC 3: `Allowed` returns 1 → `live:demo-switch` step 3, and TestAllowed.
- AC 4: `SettingsOps` writes nothing → step 5's `/state`; `DemoOn` returns 1 → step 5's `Notify` check.
- AC 5: a `Setting.Set` call added to `Web.Api` → TestOnlyRunTimeWriter; `ALLOWLIST` gains `digest.time` → TestAllowList.

**Shared surfaces:**
- the `SettingsOps` rows of `Test.Core.ProductionItems` and `Test.Core.CommandsInProduction`;
- the `SetDemoMode` contract in `Test.Msg.Contracts`;
- the `demo.mode` row (every test that changes it saves and restores it through `Test.Demo.Step`);
- the `demoKept` mark;
- `ci/units.sh` groups and `BROWSER_UNITS` (`test-ci-config.sh`);
- the Playwright projects (the `chromium` project's ignore list);
- the IRIS audit log (append-only; readers count from a mark).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
