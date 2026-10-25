---
title: 'Story 4.1: Switch demo mode from the terminal'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: 'e8e2ea9470589265f16dbeb70df95ab1c9524c14'
baseline_commit: 'e8e2ea9470589265f16dbeb70df95ab1c9524c14'
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
- [x] `src/ocutalon/cls/OcuTalon/Msg/Command/SetDemoMode.cls` -- add `Property ActingUser As %String(MAXLEN = 160)` ("the IRIS user who asked; set by the submitting code from its authenticated context"), with its storage value -- so that the audit entry names the person (AD-17; V3).
- [x] `src/ocutalon/cls/OcuTalon/Data/Setting.cls` -- add `ClassMethod Set(key, value) As %Status`:
  - it upserts the row with `UpdatedAt` from `Data.Time.NowUtc()` and kills this process's cache entry;
  - it refuses an empty key or a public key exactly as `Seed` does, sharing one private check.
  - Its doc comment says that `SettingsOps` is its only caller -- the run-time writer API (AD-19).
- [x] `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls` -- remove `STUB` and implement `OnMessage` as the Boundaries describe:
  - `Parameter ALLOWLIST = "demo.mode"`;
  - a private guarded write `Apply(key, value)`, which refuses keys off the list;
  - a private `WriteAudit(data)` seam (`Bridge.Audit.Write("Settings", <redacted data>, "Demo mode set to on|off")`);
  - a private `RunStep(Output kept, Output warnings)` seam (`Install.Step.Demo.Run()`, `TakeWarnings()`, and `StatusMark.Get("demoKept")`'s `how` when the mark is set);
  - the texts T1 to T5, and the outcomes `on`, `off`, `off_kept`, `step_failed`, `not_audited`, `unknown_command` and `failed`;
  - an error thrown inside is logged once (`$$$LOGERROR`) and answers `failed` with `MESSAGEFAILED`.
- [x] `src/ocutalon/cls/OcuTalon/Core/Admin.cls` (new) -- the admin terminal entry point:
  - `ClassMethod SetDemoMode(mode As %String = "") As OcuTalon.Msg.CommandResult` validates `mode`, checks `..Allowed($ROLES)`, builds the command with `ActingUser = $USERNAME` and calls `Commands.Submit(cmd, "system", .result)`;
  - it writes the result's `Message` on a line of its own and returns the result;
  - its local answers (`invalid`, `not_allowed`, `not_running`, `failed`) are unsaved `CommandResult`s;
  - `ClassMethod Allowed(roles As %String) As %Boolean` is pure: 1 when the comma list holds `OcuTalonAdmin`, by whole name (`%All` alone gives 0: V1 ruling).
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOpsProbe.cls` (new) -- a subclass of `SettingsOps` that overrides `WriteAudit` and `RunStep`:
  - it records each call in `^OcuTalonTest("SettingsOpsProbe", ...)` (the data object as JSON, and the value `Setting.Get(MODEKEY)` reads inside `RunStep`);
  - it answers from that global (OK, an error, or a `demoKept` note it records through `StatusMark.Record`, saved and restored by the test).
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls` (new, lane-b shard) -- drives a shadow instance of the probe. It saves and restores the `demo.mode` row with `Test.Demo.Step`, the probe global and the `demoKept` mark. Tests:
  - TestSwitch: with `DemoMode` 0 and 1, `Ok 1`, `off` or `on`, T2 or T1. The row value and `UpdatedAt` are written. The audit call came first and the step ran after the write (the probe saw the new value). The event data has `user`, `sessionRef`, `channel` `system`, `origin` `system`, `setting` `demo.mode` and `value`.
  - TestKept: `off_kept`, with T3 built from the note's `how`.
  - TestStepFails: `step_failed`, T4 carries the error sentence, and the row keeps the new value.
  - TestAuditFails: `not_audited`, T5, the row is unchanged, and the step did not run.
  - TestOtherCommand: `unknown_command`, and nothing is written.
  - TestAllowList: `ALLOWLIST` is exactly `demo.mode`, and `Apply("digest.time", "x")` is refused with no row.
  - TestOnlyRunTimeWriter: a scan with `Test.Bridge.Source` over every compiled `OcuTalon.*` class outside `OcuTalon.Test`, and outside `OcuTalon.Data.Setting` itself.
    - Writers of `OcuTalon.Data.Setting` (`Set(`, `%New(`, `%OpenId(`, `%Open(`, `KeyIndexOpen(`, `%DeleteId(`, `%Delete(`, or `^OcuTalonP.Setting`) appear only in `OcuTalon.Core.SettingsOps`, and `Seed(` only under `OcuTalon.Install`.
    - The scanner is first shown to flag synthetic violators and to pass a comment-only mention.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/Admin.cls` (new, lane-b shard):
  - TestAllowed: `OcuTalonAdmin`, `%All,OcuTalonAdmin` and `%Developer,OcuTalonAdmin` give 1; `%All`, `OcuTalonUser,OcuTalonTraceViewer`, `""` and `OcuTalonAdmins` give 0.
  - TestInvalidArgument: `2`, `"on"`, `""` and `"01"` give `invalid` with T6, no header to `SettingsOps` (count before and after) and an unchanged row.
- [x] `src/ocutalon/cls/OcuTalon/Test/Data/Setting.cls` -- add TestSet:
  - it writes an absent key and overwrites a present one, with `UpdatedAt`;
  - `Get` in this process sees the new value at once over a fresh cache entry;
  - it refuses an empty key and a public key, and writes nothing then.
- [x] `src/ocutalon/cls/OcuTalon/Test/Msg/Contracts.cls` -- add `"ActingUser": "%String(MAXLEN=160)"` to the `SetDemoMode` oracle.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls:32` -- set `SettingsOps` to `"stub": 0`.
- [x] `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` -- take `SettingsOps` out of the stub table and give it its own assertion:
  - `SetDemoMode` from `system`, with the mode the stack already has, answers status OK with `Ok 1`, outcome `on` or `off` and T1 or T2;
  - it reaches `SettingsOps` once, and the answer is one response header that is not an error;
  - update the class header.
- [x] `docker/tests/test-demo-switch.sh` (new; unit `live:demo-switch`) -- one fresh Docker throwaway, using only lib-live's helpers plus a local curl sign-in. A copy of test-bundle-folder's two lines, because `lib-live.sh` is contended (Rule 2 reason). In order:
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
- [x] `web/e2e/demo-switch/badge.spec.ts` (new) -- signs in as the README account and loads `/ocutalon/`:
  - with `OCUTALON_E2E_DEMO_MODE=1`, `.context-badge` reads "Demo mode";
  - with `0`, there is no `.context-badge` and the chat region is shown;
  - without the variable it fails at once, naming the variable.
- [x] `web/playwright.config.ts` and `web/package.json` -- add a project `demo-switch` (`testDir: './e2e/demo-switch'`, Desktop Chrome), add `**/e2e/demo-switch/**` to the `chromium` project's `testIgnore`, update the header comment, and add the script `"e2e:demo-switch": "playwright test --project=demo-switch"`.
- [x] `ci/units.sh` -- add `live:demo-switch` to one group, and `demo-switch` to `BROWSER_UNITS`.
  - The group is the one whose job was shortest in the latest green `ci` run of `feature/OCT_OcuTalon_MVP` (read with `gh run view`, read-only).
  - Record the job times and the unit's local duration under `## Verification`.
  - `live:demo-switch` checks the web bundle, so it stays out of `NO_WEB_BUNDLE_UNITS`.
- [x] Task 0 (measure, on the first fresh `live:demo-switch` run, once `SettingsOps` and the unit exist) -- confirm that `Install.Step.Demo.Run()` succeeds inside the real `SettingsOps` job, both off and on. The plan measured it only from a process registered as the CommandsIn host (Design Notes, M5).
  - If it fails only inside the job, wrap the call in `New %Ensemble`.
  - If that also fails, run the step in a JOBbed process that returns its status and warnings, and wait for it inside `CommandsIn`'s 120 s timeout.
  - Record which form held, with the off and on durations, under `## Verification`.

- [x] [CI] `ci` workflow, job `web`, step "Unit tests" (`npm --prefix web test`): `web/scripts/playwright-projects.test.mjs` case "chromium (the e2e script) lists exactly the spec files outside demo-path/ and floor/" fails on c8b4354, because this story put `**/e2e/demo-switch/**` in the `chromium` project's `testIgnore` while the test still expects chromium to list `demo-switch/badge.spec.ts` -- https://github.com/jbrandtmse/OcuTalon/actions/runs/40209803845/job/121218409733 -- make the test's rule match the config (chromium lists every spec outside `demo-path/`, `floor/` and `demo-switch/`, and the `demo-switch` project lists exactly `demo-switch/`), keeping its ability to fail on a spec that no project lists; add `npm --prefix web test` as a `(loop)` line under `## Verification`, and run it green.

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

### Review Findings

Code review 2026-10-25 (`bmad-code-review`, full mode, 4 layers on the full-opus tier: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor). 33 layer findings plus 1 of the reviewer's own; after grouping, 17 entries (high 0, med 4, low 13); 12 findings rejected (appendix). Each entry: severity, fix-risk, footprint, disposition.

- [x] [Review][Defer] An on switch with an OCUORDERS that OcuTalon did not create keeps `demo.mode` "1" after the Demo step refuses (`Plan` answers `error`, AD-3), so every later start stops at `STEP Demo FAILED` before Production and Ready, and the documented command then answers `not_running` [src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:61] -- deferred: med, fix-risk med (any fix changes the matrix row "Step fails" and needs a new terminal text, V2), in-story; `decision-pending owner=burndown` DW-207 for the decision sheet, recommended: refuse the on switch before the audit and the write when `Plan` says `error`. Right after the failed switch the production still runs, so `SetDemoMode(0)` recovers it before a restart. The class comment's "which the next start repairs" was corrected in this pass to "the next start runs the step again".
- [x] [Review][Patch] `TestSettingsOpsSwitches` switched on a `demo.mode` row it did not create (a missing row would have sent a real off switch) and did not put the row back (Shared surfaces) [src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls:64] -- med, fix-risk low, in-story: `Saved`, fail with no row, `Put` with a dated-back time, `PutBack` right after the submit.
- [x] [Review][Patch] `TestKept` set no row, so "the row holds 0" could fail only after an earlier test left "1" [src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls:99] -- med, fix-risk low, in-story: it puts "1" first.
- [x] [Review][Patch] QA's `TestAuditRedacted` held a literal `sk-ant-` key shape, which fails `test-boundaries.sh` ("keys: nothing key-like"), so `ci/checks.sh` and the hosted `checks` job go red [src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls:192] -- med, fix-risk low, in-story (reviewer's own): built by concatenation, as `Test.Bridge.Redact` does.
- [x] [Review][Patch] `TestSettingsOpsSwitches`' "the row holds the mode" could not fail (the same mode is sent) [src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls:64] -- low, fix-risk low: the job must move the dated-back `UpdatedAt`.
- [x] [Review][Patch] `Admin.ErrorText` left an Interoperability code (`ERROR <Ens>Err...:`) at the head of T4 and T8 [src/ocutalon/cls/OcuTalon/Core/Admin.cls:66] -- low, fix-risk low: any `ERROR ` prefix is dropped; TestErrorText.
- [x] [Review][Patch] `TestOnlyRunTimeWriter`'s pattern missed `%KillExtent`, `%DeleteExtent`, `KeyIndexDelete` and an extended global reference [src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls:277] -- low, fix-risk low: added, with synthetic violators.
- [x] [Review][Patch] `poll_state` stopped 12 s after the 61st second even with fewer than 3 late answers, a spurious red on a slow runner [docker/tests/test-demo-switch.sh:172] -- low, fix-risk low: it polls on until 3 late answers or the deadline.
- [x] [Review][Patch] `not_audited` logged nothing to the Event Log [src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls:57] -- low, fix-risk low: `$$$LOGERROR` with the status text.
- [x] [Review][Patch] No test read the Event Log errors of `SettingsOps` [src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls:313] -- low, fix-risk low: `Logged(text, type)`; TestStepFails, TestAuditFails, TestApplyFails and TestThrown count one error row each.
- [x] [Review][Defer] Rule 2: `Admin.Result` and `SettingsOps.Result` are near-copies of the private `CommandsIn.Result` [src/ocutalon/cls/OcuTalon/Core/Admin.cls:75] -- deferred: low, fix-risk med, in-story, not a two-way door (the sibling is private in a contended class; unifying needs a public factory on the cross-lane `Msg.CommandResult` contract); `wontfix-accepted` DW-208, reopen_if a fourth builder appears outside `OcuTalon.Test` or `CommandResult` gains a field every answer must set.
- [x] [Review][Patch] Live step 3's "the audit log is unchanged" was read seconds after the refusals, before any entry can be readable (M6: about 57 s) [docker/tests/test-demo-switch.sh:279] -- low, fix-risk low: the claim moved to step 7, which polls.
- [x] [Review][Patch] Live step 6 did not check that the row is "1" (matrix row "On") [docker/tests/test-demo-switch.sh:338] -- low, fix-risk low: added.
- [x] [Review][Patch] The origin of the real `Admin.Send` was pinned only through the probe; live step 7 matched user and value, so a `web_admin` origin passed [docker/tests/test-demo-switch.sh:105] -- low, fix-risk low: step 7 also requires `"channel":"system"`.
- [x] [Review][Patch] `TestSet` read the object it still held open, so an update that never saved passed, and "the same row" was 1 by construction [src/ocutalon/cls/OcuTalon/Test/Data/Setting.cls:113] -- low, fix-risk low: the object is dropped before the overwrite, and the ids are compared.
- [x] [Review][Patch] `TestInvalidArgument`'s "no header" and "row unchanged" checks could not fail on their own (the test session holds `%All` without `OcuTalonAdmin`, so the role check refused anyway) [src/ocutalon/cls/OcuTalon/Test/Core/Admin.cls:55] -- low, fix-risk low: an `OcuTalonAdmin` probe loop asserts nothing is submitted.
- [x] [Review][Patch] AC 1's seed guard (`Seed` now writes through `Upsert`, so its `KeyIndexExists` guard alone keeps a later write) had no `mutation:` line [src/ocutalon/cls/OcuTalon/Data/Setting.cls:49] -- low, closed in this pass: mutation applied, red observed, line recorded under Verification.

Rejected:
- `low` Edge: the Demo step could outlast `CommandsIn`'s 120 s timeout -- Task 0 measured 1 to 3 s; the answer would be `MESSAGEFAILED` ("may not have finished"), which is true (`wontfix-theoretical`: a Demo step run over 120 s would make it real).
- `false` Edge: the audit data lacks the actor's role -- AD-17 asks for the role "from step 6"; the spec's six fields are release 1's.
- `false` Edge: a repeated `IdempotencyKey` is carried out again -- the owner's dedup is for tool commands (AD-1, AD-8); `SetDemoMode` is refused from `tool`, `Admin` sets no key, and the matrix row "Same mode again" reruns by design.
- `false` Edge: `check_demo_off`/`check_demo_on`'s "STEP Demo OK" reads the first start's log -- the same helpers' namespace, database, grant and production checks fail when the switch's step does not run (recorded mutation "skips `RunStep`", step 4 red).
- `low` Blind: `run_admin` runs the command after a failed login -- under the strict check the fallback `irisowner` is refused and step 3 and 4 check `login` and `$USERNAME` (`wontfix-theoretical`: a V1 reversal that accepts `%All` would make it real; the reversal already lists steps 3, 4 and 7).
- `false` VG: TestAllowList's "an empty key is refused" cannot fail -- it fails when both guards stop refusing; an assertion over defence in depth is still falsifiable.
- `low` VG: AC 4's "the conversation and rail are unchanged" has no mutation line -- one mutation per AC is the bar, and AC 4 has three.
- `low` VG: AC 4's badge and 501 route have no mutation line -- the same bar; rejected in the implement review too.
- `low` VG: AC 5's cache expiry has no mutation line -- AC 5 has four.
- `low` Acceptance: the printed line is not preceded by `Write:$X !` -- after a typed command `$X` is 0 in a terminal; the piped session's prefix is its own prompt, which `live:demo-switch` strips, and the effect of the fix in a piped session is unmeasured.
- `low` Acceptance: step 5 starts polling after step 4's checks -- every answer from the 61st second is polled and compared, and a lasting change of chat or rail cannot hide in the few seconds before the first poll.
- Acceptance: `MESSAGEFAILED` and `MESSAGEUNKNOWN` can reach the terminal although the Never line names only V2's texts -- the Tasks and the matrix specify those reused texts; the fix would edit the spec.

## Spec Change Log

- 2026-10-25, rework iteration 1 (trigger: CI red on c8b4354, the hosted `web` job's unit tests): one `[CI]` item under Tasks & Acceptance.

- 2026-10-25, spec gate (runner): V1 ruled strict (`OcuTalonAdmin` only; `%All` alone refused) per AD-19 as written (U7 step 1); V2 and V3 kept as veto items; rows, tasks and criteria updated to match.

## Review Triage Log

### 2026-10-25 — Review pass
- verdicts: 19 rows for the 26 findings of the blind, edge-case and verification-gap layers (findings with one root cause share a row; the intent-alignment audit was descriptive and filed none) — high 0, medium 3, low 16, false 0, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: CI placement contradicts its figures (image 476 s plus the unit vs shards 786 s) — the task says the group with the shortest job; the resulting `image` job (about 16 to 18 minutes, inference) is still the lowest maximum of the six placements and far under REL-4's 35 minutes.
  - `[low]` `[patch]` Blind and VG: the writer scanner misses SQL and `$ClassMethod` writes — patterns and synthetic violators added, mutation line recorded.
  - `[medium]` `[patch]` Blind, Edge and VG: `TestSubmits`' origin assertion read a constant the probe wrote — `Send` now takes the origin as an argument and the probe records it; mutation line recorded.
  - `[low]` `[reject]` Blind: every submit error prints the not-running text — the matrix row "No production" fixes it ("Submit returns an error status", T7), and an error status means the command never reached CommandsIn (Code Map).
  - `[low]` `[reject]` Blind and Edge: empty `ActingUser` audited as is — `Admin` is the only submitter now and sets it from `$USERNAME` (TestSubmits, live step 7); Story 18.1 sets it from the session; a guard would add an outcome the spec does not define.
  - `[low]` `[reject]` Blind and Edge: malformed `demoKept` note makes `Kept` throw — only `Install.Step.Demo` writes the mark, as JSON with `how`; no reachable path (wontfix-theoretical; a hand-edited mark would make it real).
  - `[low]` `[reject]` Blind and Edge: audit first leaves an entry when the write fails and no entry for `step_failed` — Decided in-stage 1 (audit before write, so no change is unaudited); the answer text says "may not have finished".
  - `[low]` `[reject]` Blind: `ErrorText` handles one error line — the texts it shapes come from one `Status.Error` or the step's single status; no multi-error status is produced on this path.
  - `[low]` `[reject]` Blind: Design Notes out of order — a finding whose fix edits the spec; the stage reordered its own notes 16 and 17 anyway.
  - `[low]` `[reject]` Edge: `Redact.Text` fail-closed result is not JSON — the six short fields cannot pass the redactor's limit (`ActingUser` is MAXLEN 160); answered `failed` if it ever did, with nothing changed.
  - `[low]` `[patch]` Edge: a step failure is not in the Event Log — `step_failed` now logs `$$$LOGERROR`.
  - `[low]` `[reject]` Edge: unknown origin gives an empty channel — `CommandsIn` routes `SetDemoMode` to `SettingsOps` for `web_admin,system` only, both mapped.
  - `[medium]` `[patch]` Edge and VG: the probe replaced the whole `RunStep`, so its Try/Catch and kept path had no test — a finer seam `RunDemo`; TestStepThrows and TestKept now run the real `RunStep`; mutation lines recorded. TestThrown throws from the audit write.
  - `[medium]` `[patch]` VG: Notify resuming after the switch on was not checked — step 8 repeats the Notify control; mutation (`DemoOn` always 0) red at steps 2 and 8.
  - `[low]` `[patch]` VG other: audit-before-write, `ActingUser = $USERNAME` and the SQL pattern had no mutation line — TestSwitch reads the old value in the audit call; the mutations are recorded.
  - `[low]` `[reject]` VG: no mutation line for the 501 route, the badge appearing, `Admin.ErrorText` or `Setting.Set`'s public key — one mutation per AC is the bar; those are existing consumers (AC 4 has three) and `Setting.Set`'s refusal has TestSet's "without its key check" line.
  - `[low]` `[reject]` VG: `notify_probe`'s fixed `Hang 3` could flake step 2 red — it can only turn a green red, never the reverse, and ran green in four fresh runs; a 3 s margin on a router that answers in under a second.
  - `[low]` `[reject]` Intent: no documentation change, and `Admin.ErrorText` is a Core to Core dependency — documenting is Story 10.2's (README is contended); the shared helper is Decided in-stage 10 (Rule 2).

### 2026-10-25 — Review pass (rework iteration 1, the `[CI]` item only; diff since 2bb605c)
- verdicts: 6 findings — high 0, medium 0, low 5, false 1, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind: the "every spec on disk is listed" case adds almost no coverage -- it fails when a directory is in `OWN_PROJECT_DIRS` and ignored by chromium with no project listing it, a case the chromium case misses (its expected set drops the directory too); demonstrated by the mutation line.
  - `[low]` `[reject]` Blind: `OWN_PROJECT_DIRS` is a second hand-kept copy of the config -- by design, the test pins the config against an independent statement of it; deriving it from the config would make the test agree with any config; the header says to add a directory with its project.
  - `[low]` `[reject]` Blind: the `demo-switch` project's engine and `testDir` are not pinned -- the exact listing case pins its `testDir`, the engine is covered by the project's own run; unlikely in everyday use.
  - `[low]` `[reject]` Edge: the script list of the union case is hand-kept -- same reason; a new project without a script is also a new `package.json` line the lint reviews.
  - `[low]` `[reject]` Edge: the spec records no result for `npm --prefix web test` -- recorded in this pass's `## Auto Run Result`.
  - `[low]` `[patch]` Verification-gap: the union case and the `e2e:demo-switch` case have no `mutation:` line -- both mutations demonstrated (union red alone among the target cases; demo-switch case red), both lines written under `## Verification`, both files restored byte-identical.
- intent-alignment: no divergence between the readings and the diff that needs work; reading C (derive the rule from the config) is rejected above.

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
9. `Admin.SetDemoMode` validates the argument before it checks the role, so a bad argument prints T6 whoever types it.
10. `Admin.ErrorText(sc)` (public) is the one place that strips `ERROR #n:` and the closing full stop from a status text. `SettingsOps` calls it for T4, so the two classes share it (Rule 2).
11. `SettingsOps.RunStep` turns an error thrown by the step into the step's error status, so `step_failed` (T4) answers it. Only an error thrown elsewhere in `OnMessage` answers `failed`. The step's warnings are logged with `$$$LOGWARNING`.
12. The audit data goes through `Bridge.Redact.Text` in `SettingsOps.AuditData`, and the `WriteAudit` seam receives the redacted `%DynamicObject`. The seam's second argument is the description.
13. `Setting.Seed` and `Setting.Set` share a private `Refusal(key, verb)` and a private `Upsert(key, value)` (Rule 2); `Seed`'s refusal text is unchanged.
14. `live:demo-switch` creates its two fixture users in step 1, before F0, so that F0 holds their roles and the later surface comparisons are exact. Step 3's refusals run against the same F0.
15. `SettingsOpsProbe.Guarded` is a public wrapper of the private `Apply` for TestAllowList; the probe, not the test, is the subclass that can call it.
16. Warm-stack caveat for mutations: a recompiled class is not picked up by a running production job. A mutation that must reach the `SettingsOps` job toggles the item (`Ens.Director.EnableConfigItem` 0 then 1) after the reload, or runs on a fresh stack.
17. Stage-agent addition after the handoff (Matrix Test Audit: rows "No production" T7 and "Submit throws" T8 had no covering test): `Admin` gets two private seams, `Roles()` (`$ROLES`) and `Send(command, origin, Output result)` (`Commands.Submit(command, origin, .result)`), overridden by `Test.Core.AdminProbe`, which records the origin it is given. `Test.Core.Admin` gains TestSubmits, TestRefused, TestNotRunning and TestSubmitThrows. `SetDemoMode` reads `$Get(result)`, so a submit that answers OK with no CommandResult is `failed`.
18. Review patches: `SettingsOps.RunStep` calls a new private seam `RunDemo()` (the one `Install.Step.Demo.Run()` call) and the probe overrides that, not `RunStep`, so the real Try/Catch, warnings loop and kept sentence run in the unit tests (TestStepThrows, TestKept). A thrown step error is `step_failed`; TestThrown now throws from the audit write. `step_failed` is also logged with `$$$LOGERROR`. TestSwitch pins audit-before-write by the probe's audit call reading the old value. `TestOnlyRunTimeWriter` also flags the SQL table `OcuTalon_Data.Setting` and `$ClassMethod("OcuTalon.Data.Setting"`. `live:demo-switch` step 8 repeats the Notify control (a header to `SimPhoneOut` again).

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
- `npm --prefix web test` (loop) -- expected: all tests pass.
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

**Measured and recorded (implement stage, 2026-10-25):**
- Task 0: `Install.Step.Demo.Run()` succeeds inside the real `SettingsOps` job with no wrapper: the plain call held (no `New %Ensemble`, no JOB). `SetDemoMode(0)` took 3 s and `SetDemoMode(1)` 1 s end to end (whole seconds, session start included), both outcome `off` and `on`, Ok 1, with the Orders production Running and both jobs alive after the on switch (`check_demo_on`, `check_orders_jobs`).
- `live:demo-switch`, ARM, lane B, fresh: 244 s and 35 PASS lines (also 244 s on the first run); the mutated runs took 235 to 243 s, and 374 s where the audit entries never appeared (the 180 s poll). The runner estimate of Design Notes 7 (8 to 10 minutes) stays an inference.
- CI placement: the latest green `ci` run of `feature/OCT_OcuTalon_MVP` with every iris job executed (run 40093157003; the newer runs ran only a few seconds, because changes.sh skipped their jobs) had these job times: image 476 s, production 560 s, install-fresh 605 s, install-upgrade 696 s, browser 755 s, shards 786 s. `live:demo-switch` is in the `image` group (shortest job, most headroom; ahead of `shard:lane-b`, which stays last), and `demo-switch` is in `BROWSER_UNITS`. Not in `NO_WEB_BUNDLE_UNITS`.
- Verification runs (all green): the six `(loop)` class runs on the warm stack (`OcuTalon.Test.Core.ProductionItems` is an oracle, not a test class: it is run through `OcuTalon.Test.Install.Production`, which reads it, and that passes); `live demo-switch`; `npm --prefix web run lint`; `test-ci-config.sh`; `shard lane-b` (44 classes, 102 s); `shard lane-a` (41 classes, 379 s); `live sign-in` (192 passed, chromium project); `ci/checks.sh`.

- After the stage agent's Admin seams (Decided in-stage 17) and the review patches (18), the `(loop)` classes (warm) and `live demo-switch` (all PASS, the last one 4 minutes), lint, `test-ci-config.sh`, `shard lane-b` (44 classes, 103 s), `shard lane-a` (41 classes, 388 s) and `ci/checks.sh` ran on the final tree, all green. `live sign-in` ran green (192 passed) after the Admin seams and was not run again after the review patches, which touch no web file.

**Mutations** (each applied, observed red, reverted; `git status --short` and the file's md5 unchanged after each):
- mutation: AC 1, `Install.Step.Demo.DefaultMode()` returns 1 unconditionally -> `Test.Demo.Step` TestDefaultMode red ("a version file that is absent gives 0").
- mutation: AC 2, `SettingsOps` skips `RunStep` -> TestSwitch red (two seams, the step second, the step seeing the new value); `live:demo-switch` step 4 red (278 surface lines still name OCUORDERS, 15 of 15 off values differ).
- mutation: AC 2, the step runs before the write -> TestSwitch red ("the step saw the new value").
- mutation: AC 2 (audit), the `WriteAudit` call dropped -> TestSwitch and TestAuditFails red; `live:demo-switch` step 7 red (no Settings entry for the admin within 180 s).
- mutation: AC 2, `Apply` writes nothing -> TestSwitch, TestKept and TestOnlyRunTimeWriter red; `live:demo-switch` step 4 (row stays 1), step 5 (`/state` still true, the Notification still reaches SimPhoneOut, and the page spec for mode 0) red.
- mutation: AC 3, `Admin.SetDemoMode` submits with the origin `web_admin` -> `Test.Core.Admin` TestSubmits red ("from the origin system").
- mutation: `Admin.SetDemoMode` sets `ActingUser` to "" -> `Test.Core.Admin` TestSubmits red ("ActingUser from $USERNAME").
- mutation: Matrix row "Step fails", `RunStep`'s Catch rethrows -> `Test.Core.SettingsOps` TestStepThrows red.
- mutation: Matrix row "Off, foreign OCUORDERS", `RunStep` never reads the kept sentence -> TestKept red.
- mutation: AC 2, `Apply` runs before `WriteAudit` -> TestSwitch ("the audit saw the old value") and TestAuditFails red.
- mutation: AC 5, the SQL-table alternative removed from the scanner's pattern -> TestOnlyRunTimeWriter red ("the scanner flags an SQL write").
- mutation: AC 4, `Functions.DemoOn()` always 0 -> `live:demo-switch` step 2's control red and step 8's Notify check red (a header to `SimPhoneOut` never comes back).
- mutation: Matrix row "No production", `Admin` answers the outcome `failed` for an error status from the submit -> `Test.Core.Admin` TestNotRunning red.
- mutation: AC 3, the role check in `Admin.SetDemoMode` removed (`ElseIf 0`) -> `Test.Core.Admin` TestRefused red (the submit goes out for `%All` and for a user without OcuTalonAdmin).
- mutation: AC 3, `Admin.Allowed` returns 1 -> TestAllowed red; `live:demo-switch` step 3 red (both users switch demo off; the row, the headers and the audit change).
- mutation: AC 4, `Functions.DemoOn()` returns 1 -> `live:demo-switch` step 5's Notify check red (a header still goes to SimPhoneOut with demo mode off).
- mutation: AC 5, a `Setting.Set` call added to `Web.Api` -> TestOnlyRunTimeWriter red ("OcuTalon.Web.Api does not write the Setting rows").
- mutation: AC 5, `ALLOWLIST` gains `digest.time` -> TestAllowList red.
- mutation: AC 5, `SettingsOps` accepts any command class -> TestOtherCommand red.
- mutation: `Admin.SetDemoMode` accepts 2 -> TestInvalidArgument red.
- mutation: `**/e2e/demo-switch/**` dropped from the chromium `testIgnore` in `web/playwright.config.ts` -> `web/scripts/playwright-projects.test.mjs` case "chromium (the e2e script) lists exactly the spec files outside demo-path/, demo-switch/ and floor/" red (chromium lists demo-switch/badge.spec.ts); config restored from backup.
- mutation: `'**/e2e/api/**'` added to the chromium `testIgnore` and `'api'` added to `OWN_PROJECT_DIRS` in the test, with no `api` project -> `web/scripts/playwright-projects.test.mjs` case "every spec file on disk is listed by at least one of the chromium, demo-path, demo-switch and floor scripts" red (the chromium case stays green because its expected set drops `api/` too; the sign-in API case also went red because `api/` specs no longer list); both files restored from backup.
- mutation: the `demo-switch` project's `testDir` changed from `./e2e/demo-switch` to `./e2e` -> `web/scripts/playwright-projects.test.mjs` case "demo-switch (the e2e:demo-switch script) lists exactly the spec files inside demo-switch/" red; config restored from backup.
- mutation: `Setting.Set` does not drop the cache entry -> TestSet red ("Get in this process sees the new value at once"); `Setting.Set` without its key check -> TestSet red (a subscript error on the empty key).
- mutation: `SetDemoMode.ActingUser` MAXLEN 160 -> 100 -> `Test.Msg.Contracts` TestContracts red.
- mutation: `SettingsOps` answers `Ok 0 not_built` after a switch -> `Test.Core.CommandsInProduction` TestSettingsOpsSwitches red (run after the `SettingsOps` item was toggled, Decided in-stage 16).

**QA stage (2026-10-25)**: no new test file; (QA) tests added to existing classes, no new live run (no live unit or web file changed).
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/Admin.cls`: TestPrinted (the one printed line, through `AdminProbe.Capture`), TestArgumentBeforeRole. `Test/Core/AdminProbe.cls` gains `Capture`.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/SettingsOps.cls`: TestSameMode, TestApplyFails, TestKeptOnlyForOff, TestWarningsTaken, TestAuditRedacted. `Test/Core/SettingsOpsProbe.cls` gains the `apply` and `warn` answers and an `Apply` override that is the real one unless told to fail.
- mutation: Matrix row "printed line", the `Write result.Message, !` of `Admin.SetDemoMode` removed -> `Test.Core.Admin` TestPrinted red (three assertions).
- mutation: Design Notes 9, the argument check after the role check -> `Test.Core.Admin` TestArgumentBeforeRole red (and TestInvalidArgument).
- mutation: AC 2 (audit before write, write failure), `SettingsOps.Carry` ignores the status of `Apply` -> TestApplyFails red.
- mutation: Matrix row "Same mode again", `Carry` returns early when the row already holds the value -> TestSameMode red.
- mutation: Matrix row "Off, foreign OCUORDERS", the `word = "off"` guard of the `off_kept` answer removed -> TestKeptOnlyForOff red.
- mutation: Boundaries (the step's warnings taken), `RunStep` no longer calls `TakeWarnings()` -> TestWarningsTaken red.
- mutation: Boundaries (audit data through `Bridge.Redact.Text`), `AuditData` returns the data unredacted -> TestAuditRedacted red.
- Each applied from a backup, run on the warm stack, restored; md5 of `Admin.cls` and `SettingsOps.cls` and `git status --short`/`git diff --stat` identical after each. Without `OCUTALON_E2E_DEMO_MODE` the badge spec fails at once naming the variable (run with `npm --prefix web exec playwright test --project=demo-switch`, no stack needed).

**Code review (2026-10-25)**: warm stack `e4s1rw` for the class runs and mutations, fresh throwaways `e4s1r` for `CommandsInProduction`'s mutation and the live runs; all torn down. After the patches: `Test.Core.SettingsOps`, `Test.Core.Admin`, `Test.Data.Setting` and `Test.Core.CommandsInProduction` passed (warm), `shard lane-b` passed (44 classes, warm, after every revert), `live:demo-switch` passed (fresh, 265 s, 37 PASS lines) and `bash ci/checks.sh` passed. Each mutation was applied from a backup and restored; md5 of the three product files, `git status --short` and `git diff --stat` identical after each.
- mutation: Matrix row "Off, foreign OCUORDERS" (TestKept on its own row), `SettingsOps.Apply` writes nothing -> TestKept red ("kept: the row holds 0").
- mutation: Tasks (the failures are logged with `$$$LOGERROR`), the `step_failed` and `not_audited` log lines removed -> TestStepFails and TestAuditFails red; the thrown-error and failed-write log lines removed -> TestThrown and TestApplyFails red.
- mutation: AC 5, `%KillExtent` and the extended global reference dropped from the scanner's pattern -> TestOnlyRunTimeWriter red ("the scanner flags a %KillExtent", "... by an extended reference").
- mutation: Matrix row "Step fails" (T4 without the code prefix), `Admin.ErrorText` strips only `ERROR #` -> `Test.Core.Admin` TestErrorText red ("an Interoperability code is dropped too").
- mutation: `Setting.Upsert` does not save a row that exists -> `Test.Data.Setting` TestSet red ("the stored row holds the new value"); green before the patch, which read the open object.
- mutation: AC 1 (a seed that a later write survives), `Setting.Seed` without its `KeyIndexExists` guard -> `Test.Data.Setting` TestSeedOnlyWritesAnAbsentKey red ("the second Seed changed nothing").
- mutation: AC 2 (the real job writes the row), `SettingsOps.Apply` writes nothing -> `Test.Core.CommandsInProduction` TestSettingsOpsSwitches red ("the SettingsOps job wrote the row with the same mode"; fresh stack, 69 s).
- mutation: AC 2 (origin `system` at the real seam), `Admin.Send` submits with `web_admin` -> `live:demo-switch` step 7 red (0 and 0 entries from the channel system, 1 and 1 from any channel; 368 s); green before the patch.

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

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Core.Admin.SetDemoMode(0|1)` checks that the caller's roles hold `OcuTalonAdmin` (strict: `%All` alone is refused), submits `SetDemoMode` through `Commands.Submit` with origin `system` and `ActingUser` from `$USERNAME`, and prints the plain-English answer. `SettingsOps` is the real business operation: allow-list `demo.mode`, audit entry first (`Bridge.Audit`, redacted), then `Setting.Set`, then `Install.Step.Demo.Run()` (Task 0: it succeeds inside the real job with no wrapper, off 3 s, on 1 s), with T1 to T5 and the outcomes `on`, `off`, `off_kept`, `step_failed`, `not_audited`, `unknown_command` and `failed`.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Core/Admin.cls` (new): the terminal entry point, `Allowed`, `ErrorText`, and the `Roles`/`Send` test seams.
- `src/ocutalon/cls/OcuTalon/Core/SettingsOps.cls`: the real operation (`Carry`, `AuditData`, `WriteAudit`, `Apply`, `RunStep`, `RunDemo`, `Kept`).
- `src/ocutalon/cls/OcuTalon/Data/Setting.cls`: `Set`, with `Seed` sharing `Refusal` and `Upsert`.
- `src/ocutalon/cls/OcuTalon/Msg/Command/SetDemoMode.cls`: `ActingUser`.
- Tests: `Test/Core/{SettingsOps,SettingsOpsProbe,Admin,AdminProbe}.cls` (new), `Test/Data/Setting.cls` (TestSet), `Test/Msg/Contracts.cls`, `Test/Core/ProductionItems.cls`, `Test/Core/CommandsInProduction.cls`.
- `docker/tests/test-demo-switch.sh` (new live unit), `web/e2e/demo-switch/badge.spec.ts` (new), `web/playwright.config.ts` and `web/package.json` (the `demo-switch` project and script), `ci/units.sh` (`live:demo-switch` in `image`, `demo-switch` in `BROWSER_UNITS`).
- No path outside Epic 4's footprint was left edited (mutation runs touched `Install/Step/Demo.cls`, `Core/Rule/Functions.cls` and `Web/Api.cls` temporarily and restored them).

**Review.** 4 layers, 26 findings reported in 19 triage rows. Patched: 3 medium (origin assertion read a constant; real `RunStep` untested; Notify resume unchecked) and 3 low (SQL and `$ClassMethod` scanner patterns; step failure logged; missing mutation lines). Deferred: none. Rejected (12 rows, each with its reason in the Review Triage Log): CI placement, every submit error as not-running, empty `ActingUser`, malformed `demoKept` note, audit-first leaving an entry, `ErrorText` single line, Design Notes order, `Redact` fail-closed, unknown origin, extra mutation lines, `Hang 3` flake, documentation and the `Admin.ErrorText` dependency.

**Follow-up review recommended: true.** Three medium findings were patched on this first pass. The named risk: the `Admin.Send`/`Roles` and `SettingsOps.RunDemo` seams were reshaped after the first full verification pass; the full loop and once set ran green again on the final tree, but `live sign-in` was not rerun after the review patches (they touch no web file).

**Verification.** Warm class runs of `Test.Core.SettingsOps`, `Core.Admin`, `Data.Setting`, `Msg.Contracts`, `Install.Production` (reads ProductionItems) and `Core.CommandsInProduction` passed; `live demo-switch` passed (35 PASS plus step 8's Notify check, the mutated run red at steps 2 and 8); `npm --prefix web run lint`, `test-ci-config.sh`, `shard lane-b` (44 classes), `shard lane-a` (41 classes) and `ci/checks.sh` passed. The mutations listed under `## Verification` were each applied, seen red and reverted. No stack with the `e4s1` tags is left.

**Residual risks.** The runner duration of `live:demo-switch` is an inference (8 to 10 minutes; 244 s on ARM). A switch reaches an open page only at its next snapshot load (T1 and T2 say to reload). Cross-epic notes for the lead: the dependency edge `Core -> Install.Step.Demo.Run()` (AD-23) goes into the spine under Rule 20, and the V1 reversal is the owner's (`Admin.Allowed`, TestAllowed, `live:demo-switch` steps 3, 4 and 7).

**Rework iteration 1 (the `[CI]` item only).** `web/scripts/playwright-projects.test.mjs` now states the chromium rule against `OWN_PROJECT_DIRS` (`demo-path`, `demo-switch`, `floor`), has a case that `e2e:demo-switch` lists exactly `demo-switch/`, and a case that every spec on disk is listed by one of the four scripts. `web/playwright.config.ts` is unchanged. Review: 6 findings, 1 patched (two missing `mutation:` lines, written after demonstrating both reds), 5 rejected with their reasons in the Review Triage Log. Follow-up review recommended: false (no high patched). Verification: `npm --prefix web test` 567 of 567 passed, `npm --prefix web run lint` exit 0, `bash ci/checks.sh` all scripts passed. Residual risk: the hosted `web` job itself runs on the next push.
