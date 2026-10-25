---
title: 'Ask OcuTalon to watch a production, and to stop'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: 'ec4cc15a75aa85dbcbf6b873dc85da0e53ba7952'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      WatchOps' failure answers (session lock timeout, a failed save or delete) and the lock's serialisation of one session's commands have no test.
    evidence: |-
      Watch/Ops.cls OnStart and OnStop answer `failed` with Ok 0 when `Lock +^OcuTalon.Watch(session):5` times out or %Save/%DeleteId fails.
      Test.Watch.Ops asserts started, already_watching, stopped, not_watching, unknown_production, only_orders and no_session only. A lock in the
      same process is re-entrant, so the test needs a second job that holds the lock for more than 5 s; deleting the lock line leaves every test green.
    location: >-
      src/ocutalon/cls/OcuTalon/Watch/Ops.cls:OnStart, OnStop, Lock
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The Chat agent has no watch tools and `WatchOps` is a stub, so "Watch the Orders production" (UJ-1's second step) can't start a background check, and "Stop watching Orders" can't end one.

**Approach:** Add the start_watch, stop_watch and list_productions tools to the Chat agent. The production lookup goes through a new `OcuTalon.Watch.Reader`, which is the only place that switches namespace and checks the service user's read access. The start and stop tools submit `StartWatch` and `StopWatch` through `Commands.Submit`, and a real `WatchOps` writes or removes the session's `BackgroundCheck` row. The Chat instructions carry the UX's exact sentences.

## Boundaries & Constraints

**Always:**
- Tools submit only through `OcuTalon.Tools.CommandCall.Run` (origin `tool`, `IdempotencyKey` = turn `ItemId:position`) and never read or write a domain table. `WatchOps` alone writes `BackgroundCheck` (AD-1, AD-33).
- Matching is by display name over each readable Interoperability namespace's own current production (the name that `Ens.Director.GetProductionStatus` gives). "Readable" means `$SYSTEM.Security.CheckUserPermission(<Decide's ServiceUser setting>, <namespace's default global database resource>, "R")`. On the online demo the list holds only the Orders demo production (`OCUORDERS` / `OcuTalon.Demo.Orders.Production`) (AD-3, AD-4).
- With demo mode on, the service user can read OCUORDERS's data database, so "Orders" finds the Orders production on a real install, not only in tests.
- `WatchOps` admits a `StartWatch` only for a production that the reader lists, whatever the origin. A repeat for a production the session already watches creates nothing. The asking IRIS user comes from the `Session` row, never from the message.
- Tool code is callback-safe: no `%AI` call, no Python, no session call (AD-6).

**Never:**
- No catalog rendering in tools or `WatchOps` (AD-32). The UX sentences live in the Chat instructions, as `agent.noCommands` does.
- No `check` live event, check runs, poller or incident work. Those belong to Stories 5.2, 5.6 and 5.7.
- No change to the Lane B message contracts (`StartWatch`, `StopWatch`, `CommandResult`) and no new `BackgroundCheck` column.
- No edit to `Core/Commands.cls`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Start, known name | user turn, `start_watch(name "Orders")`, demo on or off | One row: `SessionRef`, `Kind` `production`, `OCUORDERS`, `OcuTalon.Demo.Orders.Production`, `DisplayName` `Orders`, `AskedBy` = the session's `IrisUser`, `NextDueAt` = now (UTC). The answer is `{ok:true, outcome:"started", production:"Orders", ref}` | none |
| Repeat | the same command again (same key), or a new ask for a production the session already watches | No second row. Answer `ok:true`, outcome `already_watching`, the existing `ref` | none |
| Unknown name, not the demo | `start_watch("Billing")` | Nothing is submitted and no row is written. Answer `{ok:false, outcome:"unknown_production", name:"Billing", list:"Orders", productions:[{name, namespace}]}`. The list is joined with ", " and with " and " before the last name | none |
| Online demo, another name | `onlineDemo` 1, any name that isn't the Orders demo production | Nothing is submitted. Answer `{ok:false, outcome:"only_orders", readmeLink:"https://github.com/jbrandtmse/OcuTalon#readme"}` | none |
| Ambiguous | two listed productions match | Nothing is submitted. Answer outcome `ambiguous` with each match's name and namespace. An optional `namespace` argument picks one | none |
| Stop | `stop_watch("Orders")` while sessions A and B both watch Orders | A's row is removed and B's stays. Answer outcome `stopped` | none |
| Stop, not watching | `stop_watch("Orders")` with no watch | Nothing is removed. Answer `ok:false`, outcome `not_watching` | none |
| No session | no context, an owner that isn't a session `Ref` (`instance`, `eval`, empty), or no `ItemId` | Nothing is submitted | CommandCall `NOSESSION` |
| Submit fails | `Submit` returns an error or a result that isn't a `CommandResult` | Nothing changes | `NOTSENT` plus one redacted warning. The job's `$$$JobSessionId` is unchanged (DW-74) |
| Owner check | `StartWatch` from any origin for a production the reader doesn't list (an unreadable namespace, another production on the demo), or for an unknown `SessionRef` | `Ok` 0 and no row. Outcome `unknown_production` (or `only_orders` on the demo), or `no_session` | none |
| Unreadable namespace | the service user can't read the namespace's data database (OCUTALON in a throwaway) | The reader leaves the namespace out | none |
| DW-38 | OCUTALON holds a compiled `OcuTalon.Demo.Orders.Production` row with description "Orders", and OCUTALON is made readable for the test | The only match for "Orders" is in OCUORDERS. OCUTALON offers only its current production (`OcuTalon.Production`) | none |
| Untrusted or tainted turn | provenance `untrusted`, or an earlier tool result tainted the turn | start_watch and stop_watch are denied with the gate's `UNTRUSTED` sentence and nothing is submitted. list_productions runs | gate denial |

</intent-contract>

## Code Map

All `OcuTalon/...` paths are under `src/ocutalon/cls/`.

- `OcuTalon/Watch/Ops.cls` -- `WatchOps`, a stub (`STUB` 1, answers `NotImplemented`). Build it. Only `CommandsIn` calls it today.
- `OcuTalon/Watch/Reader.cls` -- new file.
- `OcuTalon/Tools/CommandCall.cls` -- `Run`:
  - fills `SessionRef` and `IdempotencyKey` (`ItemId:position`, L41);
  - saves and restores `$$$JobSessionId` around `Submit` (L43, L49);
  - its `NOSESSION`, `NOTSENT` and warning texts (L19–25, L52) still say "reminder".
  - `Answer` builds `{ok, message, ref, due…}`.
- `OcuTalon/Tools/ReminderTools.cls` and `OcuTalon/Tools/Reminders.cls` -- the sibling pattern: parameters named by tool, `Return`, a `DependsOn` toolset with no Requirement element.
- `OcuTalon/Tools/Watch.cls` and `OcuTalon/Tools/WatchFixture.cls` -- name clash. These are Diagnosis's read-only toolset `OcuTalon.Tools.Watch`, which Story 5.4 replaces in place. Leave them alone.
- `OcuTalon/Tools/Names.cls` -- `STARTWATCH`, `STOPWATCH` and `LISTPRODUCTIONS` already exist.
- `OcuTalon/Agent/Chat.cls` -- `TOOLSETS` (L14) and `XData INSTRUCTIONS` (L22–38). Precedent: the `agent.noCommands` sentence is in the instructions, and a test compares the two.
- `OcuTalon/Msg/Command/StartWatch.cls` (`Namespace`, `Production`, `DisplayName`), `StopWatch.cls` (`Namespace`, `Production`) and `Msg/CommandResult.cls` (`Ok`, `Message`, `Outcome`, `Ref`, `Data`) -- Lane B contracts, read-only.
- `OcuTalon/Core/CommandsIn.cls` -- read-only.
  - L163–177 route `StartWatch` and `StopWatch` to "WatchOps"; every origin, `tool` included, is accepted.
  - `Send` is `SendRequestSync(…, 120)` (L92–95).
  - A stub owner (5003) maps to `not_built` (L83).
- `OcuTalon/Data/BackgroundCheck.cls` -- `Ref`, `SessionRef`, `Kind`, `Namespace`, `Production`, `DisplayName`, `AskedBy`, `NextDueAt`, `LastRunAt`, `Result`, `Finding` and `LastRunHeaderId`.
  - Indices: `RefIndex`, `SessionRefIndex` and `NamespaceProductionIndex`. There is no idempotency column.
  - `Kind` must be exactly `production`, because `Ownership.cls` L42, L327, L518 and L522 filter on it.
- `OcuTalon/Data/Session.cls` -- `IrisUser` (L18) and `RefIndexOpen` (L34). `src/bridge/cls/OcuTalon/Bridge/Ids.cls` `NewRef()` makes a `Ref`. `OcuTalon/Data/Time.cls` `NowUtc()` gives the time.
- `OcuTalon/Data/Ownership.cls:213` `Checks(sessionRef)` -- read-only consumer (Epic 16 contended).
  - Its SQL (L480–482) selects the session's rows.
  - It feeds `/state` through `Web/Api.cls` `RailBody` (L351–367) and `CheckView` (L372–388).
  - The page builds "{name} production" and "Live, plus a check every minute" from `Kind` and `DisplayName` (`web/src/app/rail/rail-view.ts:43-44,176-179`).
- `OcuTalon/Data/Setting.cls:26` -- `Get("onlineDemo")`. Tests flip the flag with `OcuTalon.Data.Public.Settings.Set("onlineDemo", …)` and restore it (`Test/Core/CommandsRouting.cls:43-53`).
- `OcuTalon/Msg/Catalog/Watch.cls` L29–43 -- `watch.unknownProduction` and `watch.onlyOrders`. The confirmation is not a catalog key; it is UX text (`ux-designs/…/EXPERIENCE.md:169`).
- `OcuTalon/Demo/Orders/Production.cls:12` -- `<Description>Orders</Description>`.
- `OcuTalon/Install/Step/Demo.cls` (Lane B; Epic 4 contended) -- `NAMESPACE` L39, `PRODUCTION` L42, `DATADB` L48.
  - `WithOrders(resources, on)` (L145) is pure.
  - `System(1)` grants the trace role Read on the OCUORDERS databases (L278–292). The off and keep paths remove that grant (L318–330).
- `OcuTalon/Install/Registry.cls:12` -- order: `Roles`, …, `Demo`, …. `Install/Step/Roles.cls:60` refuses a resource that doesn't exist.
  - `OcuTalonServiceRole` holds only the tool `RESOURCES` (`Install/Step/Tools.cls`), and no tool declares any today.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`:
  - `ClassificationOf` L176–195;
  - `MissingPrivilege` L228–247, which reads the service user with `Ext.Accessor.ValueFor("ServiceUser")`;
  - `Decision` L119–131, with the `UNTRUSTED` sentence at L69.
- `OcuTalon/Production.cls:38` -- the `WatchOps` item in Lane A's region (L15–44). Unchanged.
- Tests to extend:
  - `Test/Tools/CommandsDouble.cls` answers by verb and gives `not_handled` otherwise.
  - `Test/Tools/Reminders.cls` templates: `Begin` 874, `CallTool` 887, `Turn` 896, `AssertCall` 965, `TestSetRelative` 247, `TestKeys` 514, `TestSubmitKeepsTheJobSession` 654, `TestDeclarations` 164.
  - `Test/Bridge/Gate.cls`: `TestWatchToolsAreClassified` 207, `TestEveryBuiltInToolIsClassified` 223, `AssertSafeReadOnlyOnly`'s cases (~1572) and runs (~1592), `RunDenied` 1871, `TestSuspiciousRequestActsOnNothing` 1275.
  - `Test/Bridge/CodeRules.cls`: `CALLBACKHELPERS` L62 and `TestCallbackRule` 137–176 (its `raiseClass` loop is the template).
- `ci/units.sh:17` -- `lane-a` areas. `docker/tests/test-ci-config.sh:636-648` requires every `Test/<Area>` to be in a shard.
- `ci/warm.sh` `warm_up` (L120–151) calls `stack_ready`. `stack_ready` (`ci/iris.sh` L249–260) prints `READY` right after `dc up --wait`, and `warm_up` never reads the after-start log. The log is available through `docker/tests/lib-live.sh:345` `start_log`. `docker/tests/test-ci-warm.sh` is hermetic with stubs.
- `ci/mock/scenarios/A/reminder-set-relative.json` -- the scenario shape (`name`, `match.marker`, `replies[]` with `toolUse` or `text`). `ci/mock/scenarios.mjs:26` lists the allowed fields.
- Platform measured in Task 0 (slot A, read-only, build 154):
  - `%SYS.Namespace.ListAll` with `GetNSInfo(ns,.i)` gives `i("Resource")` (for example `%DB_OCUTALON_DATA`) with no switch to `%SYS`.
  - `%Library.EnsembleMgr.IsEnsembleNamespace` flags Interoperability namespaces.
  - `Ens.Director.GetProductionStatus(.name,.state,timeout,skipLockIfRunning)` (`irislib/Ens/Director.cls:531`) gives "" when nothing ever ran.
  - OCUTALON's `Ens_Config.Production` holds six rows, `OcuTalon.Demo.Orders.Production=Orders` among them (DW-38 confirmed).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- new class with:
  - `Productions()`, which returns `[{namespace, production, displayName}]` under the matching rule in Always. The display name is the `Ens.Config.Production` `Description`, or the class name when it is empty. The namespace switch happens in one method with `New $NAMESPACE`, and `GetProductionStatus` gets a short lock timeout with `skipLockIfRunning` set.
  - `Find(name, namespace="")`. It trims the name, drops a trailing " production", and compares case-insensitively with the display name or the class name.
  - `Admits(namespace, production)` for `WatchOps`.
  - The Orders identity comes from `OcuTalon.Install.Step.Demo`'s `NAMESPACE` and `PRODUCTION` parameters, which are read, not copied.
- `src/ocutalon/cls/OcuTalon/Watch/Ops.cls` -- remove `STUB`. Add a `MessageMap` for `StartWatch` and `StopWatch` that answers a `CommandResult` as in the matrix rows "Start", "Repeat", "Stop", "Stop, not watching" and "Owner check". Repeat detection uses the natural key (`SessionRef`, `production`, `Namespace`, `Production`).
- `src/ocutalon/cls/OcuTalon/Tools/WatchTools.cls` -- new class extending `OcuTalon.Tools.Result`:
  - `StartWatch(name, namespace)`, `StopWatch(name, namespace)` and `ListProductions()`, each returning through `Return`;
  - parameters by the naming rule: `STEPLABEL*` ("Starting a watch", "Stopping a watch", "Listing the productions"), `CLASSIFICATION*` `safe` for all three, `READONLY*` 0, 0, 1, and `TRUSTEDOUTPUT*` 1 for all three (see Design Notes);
  - `READMELINK`;
  - start and stop resolve the name through `Reader.Find`, then submit through `CommandCall.Run` and add `outcome` and `production` to `CommandCall.Answer`.
- `src/ocutalon/cls/OcuTalon/Tools/Watching.cls` -- new `%AI.ToolSet` with `DependsOn` `WatchTools`. Its three tools use the `Names` constants.
- `src/ocutalon/cls/OcuTalon/Tools/CommandCall.cls` -- make the `NOSESSION`, `NOTSENT` and warning texts neutral rather than reminder-specific, so both toolsets share it (Rule 2: extend, don't copy).
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- `TOOLSETS` becomes `OcuTalon.Tools.Reminders,OcuTalon.Tools.Watching`. Add these to the instructions:
  - call start_watch directly with the name the user gave;
  - on `started`, confirm with exactly "I'll watch the {production} production and stay quiet unless something needs you.";
  - on `unknown_production`, reply with exactly the `watch.unknownProduction` text, filling `{name}` and `{list}`;
  - on `only_orders`, reply with exactly the `watch.onlyOrders` text with `{readmeLink}`;
  - on `ambiguous`, ask which production was meant;
  - on `stopped`, say so in one short sentence.
  - Update the class doc comment.
- `src/ocutalon/cls/OcuTalon/Test/Tools/CommandsDouble.cls` -- answer `StartWatch` and `StopWatch`, honouring the `refuse/<Verb>` switch.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Reader.cls`, `Test/Watch/Ops.cls`, `Test/Watch/Tools.cls` and `Test/Watch/Turns.cls` -- new tests covering every matrix row and the acceptance criteria below.
  - They run in throwaways only, and fail with the reason when the production or OCUORDERS is missing.
  - `Ops` sends commands directly to a shadow instance (`Ens.Host.GetShadowInstance`, as in `Test/Digest/Store.cls:195`).
  - `Tools` runs against `CommandsDouble`.
  - `Turns` uses the real `CommandsIn` and `WatchOps`.
  - Role changes in a test, such as making OCUTALON readable for the DW-38 row, are restored in teardown.
- `ci/mock/scenarios/A/` -- add `watch-start-orders`, `watch-start-unknown`, `watch-stop-orders` and `watch-injected-stop` (stop_watch called in an untrusted turn).
- `ci/units.sh` -- add `Watch` to the `lane-a` areas (L17), only that entry.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` -- extend `TestWatchToolsAreClassified` with the three exact flag sets. In `AssertSafeReadOnlyOnly`'s cases and runs, start_watch and stop_watch are denied and list_productions runs.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- add these to `CALLBACKHELPERS`:
  - `OcuTalon.Watch.Reader` and the OcuTalon classes it calls inside the callback (`Data.Setting`, `Data.Public.Settings`, `Install.Step.Demo` for its parameters);
  - for DW-177, `OcuTalon.Core.BridgeSink`'s callees: `Live.Publish`, `Live.Event`, `Data.Ownership`, `Data.Session`, `Data.Turn`, `Data.Incident`, `Live.Payload.Approval`, `.Decision`, `.TurnStep`, `.Part.ItemNoun` and `.Part.DryRun`. Re-read `BridgeSink` when implementing, in case its callees changed.
  - Add an assertion loop like the `raiseClass` loop for both groups.
- Shared-surface tests:
  - `src/ocutalon/cls/OcuTalon/Test/Agent/Instructions.cls`: `TestChat` compares the three sentences, `TestToolsets` covers six tools, and the no-context run expects `NOSESSION` from start and stop.
  - `Test/Agent/Runners.cls`: `REMINDERTOOLS` and the inventory's expected list, with a per-tool provider in `TestToolInventory`.
  - `Test/Tools/Reminders.cls`: `TestDeclarations`, and the offered names in `TestSetRelative`.
  - `Test/Bridge/Decide.cls`: the sizes in `TestEstimateTokens` (L1536, L1798).
  - `Test/Install/Production.cls:625`: `WatchOps` `"stub": 0`.
- `ci/warm.sh`, plus one optional check argument on `ci/iris.sh` `stack_ready` that runs before its `READY` line (fresh calls pass none) -- for DW-164, `warm up` prints `READY` only when the after-start log's last `RESULT` line is `RESULT OK`. Otherwise it prints `FAIL` naming that line, exits 1 and tears the project down.
- `docker/tests/test-ci-warm.sh` -- append one self-contained block at the end that stubs the after-start log for both cases (`RESULT FAILED` and `RESULT OK`).
- [Epic 4's file; one-time footprint extension by orchestrator ruling, veto U-79] `src/ocutalon/cls/OcuTalon/Install/Step/Demo.cls` -- a minimal, self-contained addition beside the trace role's OCUORDERS grants, reusing `WithOrders`' pattern (for example a pure sibling helper that adds or removes `%DB_OCUORDERS_DATA:R` alone): with demo mode on, `System(1)` gives `OcuTalonServiceRole` Read on `%DB_OCUORDERS_DATA` only (no code database, no SQL grant, no write); the off and keep paths remove it. Do not reshape existing methods beyond what the addition needs. The service role exists at that point (the Roles step composes it from the tool `RESOURCES` before `Demo`); a missing role fails the step with a plain sentence, like the trace role's.
- [Epic 4's file; footprint extension by orchestrator ruling (decide)] `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls` -- remove the `StartWatch|WatchOps|web_user` row from `TestStubOwnersAnswerPlainEnglish`'s table and take WatchOps out of the stub-owners header comments. Change nothing else.
- Pin the grant (orchestrator ruling) in Lane A's own test classes, never under `Test/Demo/**` (Epic 4's): (a) the pure helper: add, idempotent add, remove, remove when absent, the code database never added; (b) on a throwaway started with demo mode on, `OcuTalonServiceRole` holds `%DB_OCUORDERS_DATA:R` and no `%DB_OCUORDERS_CODE`; (c) `Watch.Reader` finds Orders with the grant, and not without it (the test takes the grant away and puts it back); (d) the off path removes it: either a test that reruns `Install.Step.Demo.Run()` with demo mode off and then on again (restoring OCUORDERS and its production before it returns; throwaway only), or a self-contained block appended at the end of an existing live script; the keep path shares the off path's role edit, and where a live script already ends in the keep state (`docker/tests/test-install-start.sh`), one appended block there asserts the service role holds no OCUORDERS resource. Changing no existing line of a `docker/tests` script.

**Acceptance Criteria:**
- Given a user turn "Watch the Orders production and only tell me if something needs me." with `[[mock:watch-start-orders]]`, through the real ChatAgent, `CommandsIn` and `WatchOps` in a throwaway with demo mode on:
  - when the turn runs, then there is exactly one row as in the matrix row "Start", `ToolsRun` is 1, and the turn has the step "Starting a watch";
  - and `OcuTalon.Data.Ownership.Checks(<session>)`, the source of `/state`'s background-check rows, lists it with `Kind` `production` and `DisplayName` `Orders` (Integration AC).
- Given that watch and another session's Orders watch, when "Stop watching Orders" runs with `[[mock:watch-stop-orders]]`, then `Ownership.Checks` no longer lists the first session's watch and the other session's row is unchanged.
- Given an untrusted turn with `[[mock:watch-injected-stop]]` while the session watches Orders, when it runs, then the stop_watch step is denied with `UNTRUSTED`, no command reaches `WatchOps`, and the row remains (NFR-14).
- Given the Chat agent, when its instructions and toolsets are read, then:
  - they hold the confirmation sentence, which equals the UX text once `{production}` is "Orders";
  - they hold the catalog's exact `watch.unknownProduction` and `watch.onlyOrders` texts;
  - and `TOOLSETS` names both toolsets.
- Given a start_watch or stop_watch call with the job's `%Ensemble("SessionId")` set, when it returns (a failed submit included), then the id is unchanged and a warning logged afterwards is in that session (DW-74).
- Given `ci/warm.sh up` whose after-start log ends `RESULT FAILED`, when it runs, then it prints no `READY` line and no `WARM up … ready` line, prints `FAIL`, exits 1 and leaves no project of the tag. With `RESULT OK`, its output is unchanged (DW-164).
- Given `CALLBACKHELPERS`, when `TestCallbackRule` runs, then every listed class, BridgeSink's callees included, is compiled, scanned and clean (DW-177).
- Given a throwaway with demo mode on, when the Demo step has run, then `OcuTalonServiceRole` holds `%DB_OCUORDERS_DATA:R` and no other OCUORDERS resource, and `Watch.Reader` finds Orders only while it does; given demo mode off (or kept), then the role holds no OCUORDERS resource (U-79).

## Spec Change Log

- 2026-10-25, spec gate (Epic 5 runner): the plan's intent gap was ruled by the orchestrator (option (a)); the two Epic 4 paths became footprint extensions, the grant gained its pinning tests and an acceptance criterion, the TRUSTEDOUTPUT classification was ruled veto U-80; status set to `ready-for-dev`. Rulings under Design Notes.

## Review Triage Log

### 2026-10-25 - Review pass
- verdicts: 34 findings - high 0, medium 5, low 27, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: stop_watch cannot stop a watch whose production the reader no longer lists - the spec's own rule (stop resolves through `Reader.Find`; `OnStop` itself would delete); needs a table-reading fallback in a tool or a new command shape, for a rare state (a revoked grant or a production gone); Story 16.4's `SessionOps.End` goes through WatchOps.
  - `[low]` `[reject]` Blind: Description is free text under TRUSTEDOUTPUT - an instance admin writes it (no outside content), and the classification is the spec-gate ruling U-80; the length and line-break part is the patched Label row below.
  - `[low]` `[reject]` Blind: name matching is only the display name or the class name - the matching rule is the spec's (Decided in-stage); an empty Description matches by class name as specified.
  - `[low]` `[reject]` Blind: `Reader.Productions` runs several times per request - no wrong outcome; `skipLockIfRunning` and a 1 s lock bound it, and the lists are short.
  - `[low]` `[reject]` Blind: `Productions` can throw before the Try in `OnStart` - it throws only on an unreadable ServiceUser setting or a failed ListAll, a configuration error that fails loudly; CommandsIn answers `failed` for it.
  - `[low]` `[reject]` Blind: Chat instructions name no sentence for stop's `failed`, `no_session` - the model says why from the message; unlikely to be met, and the fix adds instruction text (and moves token-size tests).
  - `[low]` `[reject]` Blind: `warm_start_result` passes an empty log - the real log always holds a RESULT line once the health-gated start is up; an unreadable log is unlikely, and telling it from a stub's empty log means changing existing lines of `test-ci-warm.sh`, which the spec forbids.
  - `[medium]` `[defer]` Blind: test gaps in `Test.Watch.Ops` (lock timeout, failed save) - same root cause as the verification-gap row on the failure answers; deferred. The Demo step's off path and the missing-role sentence are covered by the shared-edit keep block and `ServiceRole`'s one branch; low, not worth a test.
  - `[low]` `[reject]` Blind: the spec's status and Auto Run Result lines are out of step during the run - the finalize step writes them.
  - `[low]` `[reject]` Blind: the old summary line prints before the appended block of `test-ci-warm.sh` and `test-install-start.sh` - the spec forbids changing existing lines; the exit code and the block's own summary are final.
  - `[low]` `[reject]` Edge: `Productions` throws on an unreadable ServiceUser or ListAll - as the blind row above: a loud configuration error.
  - `[medium]` `[patch]` Edge: a Description longer than 128 characters (or with line breaks) overflows `DisplayName` (MAXLEN 128) on the command and the row, so the start fails - verified: `Reader.Current` took the whole Description. Fix: `Reader.Label` collapses white space and cuts to 128; `Test.Watch.Reader` `TestLabel` pins it (mutation line written).
  - `[low]` `[reject]` Edge: `Submitted` has no name or list when the owner refuses after the tool's own read listed the production - needs a state change between the two reads; the answer still carries the outcome and the message.
  - `[low]` `[reject]` Edge: a namespace argument that matches nothing answers unknown_production while naming the production elsewhere - the argument is only for a follow-up to `ambiguous`; the list answer is still correct.
  - `[low]` `[reject]` Edge: on the online demo with Orders unreadable the answer is only_orders - the Demo step grants the read whenever demo mode is on; edge of a broken install.
  - `[low]` `[reject]` Edge: `Readable` with an empty ServiceUser setting - an empty setting is a configuration error, and CheckUserPermission then denies.
  - `[low]` `[reject]` Edge: stop for a production that dropped out of the reader - same as the blind row.
  - `[false]` `[reject]` Edge: `Admits` is case-sensitive where `Find` is not - the tool passes the entry's own namespace from the reader, so the cases agree; a forged command in another case is refused, the safe direction.
  - `[medium]` `[patch]` Edge: `TestUsageTurn`'s `first '= ""` cannot fail (the `+` makes it numeric) - verified. Fix: `first > 0`; `Test.Agent.Decide` runs green.
  - `[low]` `[reject]` Edge: `warm_start_result` empty-log pass - as the blind row.
  - `[low]` `[reject]` Edge: the WatchTools class comment claims no outside content - as the Description row above.
  - `[medium]` `[patch]` Gap: `Tools.WatchAnswers` runs in the callback but is not in `CALLBACKHELPERS`, so the AD-6 scan never reads it - verified. Fix: listed in `CALLBACKHELPERS` and in `READERCLASSES` (a loop pins it); the mutation line is written.
  - `[medium]` `[defer]` Gap: WatchOps' `failed` paths and the session lock have no test - needs a second job that holds the lock over 5 s; recorded in `deferred:`.
  - `[low]` `[patch]` Gap (Rule 19): AC 1, 2, 3, 4, 7 and 8 had no `mutation:` line - each mutation applied, red observed, reverted (tree byte-identical); lines written under Verification.
  - `[low]` `[reject]` Gap: `TestChat` compares the constant with a literal - the literal is the UX sentence and the next assertion compares the instructions text; the constant check is a second pin and the AC4 mutation turned `TestChat` red.
  - `[low]` `[reject]` Gap: the `READERCLASSES` and `SINKCLASSES` loops repeat the list - they pin that the listed callees stay in `CALLBACKHELPERS` (the DW-177 mutation turned the test red); the callees are read from BridgeSink by hand as the spec says.
  - `[low]` `[reject]` Gap: `TestListProductions`'s disjunct is weak - it can fail (no " and " in the list) and pins the joined list; order is not the AC's claim.
  - `[low]` `[reject]` Gap: `TestUsageTurn` derives its expectation from the estimate - the largest-request rule is pinned in `Test.Bridge.Usage`; this test only joins the two.
  - `[false]` `[reject]` Gap: `TestInjectedStop` has no positive control that the helper sees WatchOps traffic - the AC3 mutation (READONLYSTOPWATCH 1) turned its "no command reached WatchOps" assertion red, so it can fail.
  - `[low]` `[reject]` Gap: the Watch classes rely on the Demo grant and demo mode - by design: `Case.Ready` fails with the reason, and `Test.Install.Registry` restores the role.
  - `[low]` `[reject]` Gap: assertions assume the throwaway's namespace set - the throwaway's set is fixed (OCUORDERS and OCUTALON); each fails with its reason if it changes.
  - `[low]` `[reject]` Gap (other): stop for an unlisted production - as the blind row.
  - `[low]` `[reject]` Gap (other): `warm_start_result` passes an empty log - as the blind row.
  - `[low]` `[reject]` Intent audit: the headline expectations sit at the chat and install surfaces and the tests exercise class-level surfaces and the scripted mock - `Test.Watch.Turns` runs the real Decide, tool, `CommandsIn`, WatchOps and `Ownership.Checks` in a throwaway; the model's choice of tool and wording is scripted by design (AD-22).

## Design Notes

**Governing ADs:**
- AD-1: commands, `IdempotencyKey`, tools never write tables.
- AD-3: the reader is the only namespace switcher, and readability is judged for the service user.
- AD-4: `SessionRef`, Orders only on the online demo, scope.
- AD-6: callback safety.
- AD-10: classification, untrusted and taint rules.
- AD-18: `BackgroundCheck` written by `WatchOps`.
- AD-22: tests and mock scenarios under `A/`.
- AD-23: the Demo step owns the OCUORDERS grants, and a demo-mode switch reruns only it.
- AD-24: the service user's privileges.
- AD-26: job session and thread (DW-74).
- AD-29 and AD-33: lanes and owners.
- AD-32: producers never render.

**Integration ACs, Consumes, Consumed-by:**
- The new services are `Watch.Reader` and the real `WatchOps`. Their in-story consumers are the watch tools, and `Data.Ownership.Checks` (the `/state` rail), which the first acceptance criterion covers.
- Consumes:
  - `Commands.Submit` and `CommandsIn` (Epic 0 / 2.3);
  - `Session` (Epic 0);
  - the gate (3.2, 3.3);
  - `Ownership.Checks` (Epic 2);
  - `Install.Step.Demo` parameters (0.10).
- Consumed-by:
  - Story 5.2 (`FailurePoller` reads watches and reads through `Reader`);
  - Story 5.6 (`Checks` runs each watch's check, and publishes its `check` event when a watch starts or stops);
  - Story 5.7 (`check_status`);
  - Story 9.x (`WatchOps` in evaluation runs);
  - Story 16.4 and Story 31.3 (`SessionOps.End` stops a session's watches through `WatchOps`; 31.3 turns on the real path);
  - Stories 23.x and 24.x (more `BackgroundCheck` kinds).

**Extend, don't copy:**
- `WatchTools` follows `ReminderTools`, and its submits go through `CommandCall`, generalised rather than copied.
- `Reader` reads the service user as the gate's `MissingPrivilege` does, and takes the Orders identity from `Install.Step.Demo`'s parameters.
- The contended grant reuses `Demo.WithOrders` for the data database.
- New class `Tools.Watching`, and not `Tools.Watch`, because that name is Diagnosis's toolset.

**Decided in-stage:**
- Idempotency uses the natural key (`SessionRef`, `production`, `Namespace`, `Production`) instead of a key column, so there is no schema change. A repeat answers `already_watching` with the same `Ref`.
- `NextDueAt` is the creation time, so the first heartbeat runs the check. `Result` starts empty.
- A name matches after trimming, dropping a trailing " production", and comparing case-insensitively with the display name or the class name.
- A namespace with no current production is skipped.
- The list is joined with ", " and with " and " before the last name.
- `ambiguous` is a new outcome, with an optional `namespace` argument to pick one.
- The UX sentences live in the instructions, compared by a test against the catalog and the UX text, as the `agent.noCommands` precedent does. The tools return the outcome plus the slot values, so there is no rendering in a callback (AD-32).
- `READMELINK` is a parameter of `WatchTools`. No server constant exists yet, and Lane B may later move it to the catalog.
- Step labels follow Story 1.10's form. The stop confirmation is the model's own short sentence, because the UX fixes none.
- DW-74 is addressed without touching `Commands.cls`. `CommandCall.Run` already restores the job session (Story 1.10), and `Test.Watch.Tools` and `Turns` prove it for the watch tools in a throwaway.
- Classification: start_watch, stop_watch and list_productions are all `TRUSTEDOUTPUT` 1.
  - Their answers are built by code from the owner's `CommandResult` and IRIS's production registry. No content arrives from outside the instance; these are the same names that `check_status`'s trusted rows carry.
  - If list_productions tainted the turn, the gate would deny a start_watch that followed it in the same turn, which breaks UJ-1.
  - This is a veto-window item, raised in Auto Run Result.

- Implement stage, tool side: `Tools.WatchTools` returns only through `Return` (the code-rules scan flags any other `Quit` value in a tool provider), so the shaping of the answers is `Tools.WatchAnswers` (`Resolve`, the pure `Decide`, `Submitted`, `Listed`, `Joined`). `CommandCall` gained `Session()` (the NOSESSION check, which `Run` also uses), so a watch tool answers NOSESSION before it looks anything up. An empty list reads "no productions". `READMELINK` stays a `WatchTools` parameter and `WatchAnswers` reads it.
- Implement stage, owner side: `WatchOps` answers `failed` (Ok 0) when a lock or a save fails, takes a lock on the session for each command (`^OcuTalon.Watch(sessionRef)`), and takes the display name from the reader, never from the command. `stop_watch` resolves the name through the reader like `start_watch`, so a watch whose production the reader no longer lists (an unreadable namespace) cannot be stopped by the tool: it answers `unknown_production`.
- Implement stage, Demo step: `ServiceRole(on)` is a sibling of `System` that `System` calls after it switches back to the home namespace (`Demo` classes do not resolve in `%SYS`); `WithOrdersData` is the pure helper. The off and keep paths call it before they branch, so both remove the grant.
- Implement stage, tests: `Test.Watch.Case` (abstract) and `Test.Watch.Grant` are new beside the four named classes. `Test.Install.Registry` now saves and restores the service role's resources as it does the trace role's: its `OnAfterAllTests` runs the Roles step, which drops the Demo step's grant and left every later Watch class with an empty list in a fresh shard. Chat's request is now above `min_tokens_for_cache` and above Test.Agent.Decide's measured usage, so `Test.Agent.Runners` expects Chat's system block marked (`systemMarked`) and `Test.Agent.Decide` `TestUsageTurn` expects the larger of the measured last request and the first request's estimate; both are consequences of the six tools and the longer instructions, with no change of product code. `Test.Tools.Reminders` follows the six tool names. The service role's off and keep removal is pinned by one block appended to `docker/tests/test-install-start.sh` (seed the grant, rerun the step in the keep state, expect no OCUORDERS resource).
- Implement stage, DW-164: `stack_ready` takes the optional check, `warm_start_result` fails the up when the after-start log's last `RESULT` line is not `RESULT OK ...` or there is none. A log with no content at all (only a stub gives one: the start is health-gated) passes, so the existing hermetic checks keep their stubs unchanged.
- `Reader.Label` makes the display name of a production description: white-space runs become one space and the text is cut to 128 characters (the length of `DisplayName` in the command and the row), so a long or multi-line Description never fails a start. Review pass, 2026-10-25.

**Declined:** none. DW-38 (the reader's own-production rule and its matrix row), DW-74, DW-164 and DW-177 are all addressed above.

**Footprint extensions** (not contended): `Agent/Chat.cls`, `Test/Agent/{Instructions,Runners}.cls`, `Test/Bridge/{Gate,CodeRules,Decide}.cls`, `Test/Install/Production.cls` (the `WatchOps` row only), `ci/warm.sh`, `ci/iris.sh` (`stack_ready` hook), and `docker/tests/test-ci-warm.sh` (one block appended). By orchestrator ruling also Epic 4's `Install/Step/Demo.cls` and `Test/Core/CommandsInProduction.cls` (below), and, if used, one block appended at the end of `docker/tests/test-install-start.sh`.

**Orchestrator rulings (2026-10-25, on the plan's intent gap):**
- `Install/Step/Demo.cls`: allowed as a one-time footprint extension. The minimal addition grants `OcuTalonServiceRole` `%DB_OCUORDERS_DATA:R` only with demo mode on; off and keep remove it. A privilege grant: veto, inbox item U-79 (recorded by the orchestrator). Recorded in the spine as the Consistency Conventions row "Service role, OCUORDERS read" (Rule 20 light path; no AD text changed). Pinned by tests (Tasks). DW-213 routes the security overview's demo-mode-only listing to Story 14.1. If Epic 4 later edits the file, the second integrate-forward is a plain union.
- `Test/Core/CommandsInProduction.cls`: allowed (decide), per the test's own header. Remove only the WatchOps row and its header mention; the one-line conflict with Epic 4's SettingsOps removal resolves as a plain union (both removals).
- The other out-of-footprint edits listed above are accepted as reported. DW-74 needs no `Core/Commands.cls` change.

**Spec-gate ruling (Epic 5 runner, 2026-10-25):** the three watch tools are `TRUSTEDOUTPUT` 1, as planned: veto, inbox item U-80 (precedent U-60). The spine's "Tool classification" row now names them.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`. Run one command per call with `timeout: 600000`, and never two IRIS test runs in one message.

**Commands:**
- (loop) `bash docker/tests/test-ci-warm.sh` -- expected: every check PASS.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s1iw ci/warm.sh up` -- once per stage, and again after any `ci/mock` change (`down` then `up`). Expected: READY. Until DW-164 is fixed, also confirm that the after-start `RESULT OK` line is present.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s1iw ci/iris.sh class <Class>`, one call per class, for `OcuTalon.Test.Watch.Reader`, `.Watch.Ops`, `.Watch.Tools`, `.Watch.Turns`, `OcuTalon.Test.Bridge.Gate`, `.Bridge.CodeRules`, `.Bridge.Decide`, `OcuTalon.Test.Agent.Instructions`, `.Agent.Runners`, `OcuTalon.Test.Tools.Reminders` and `OcuTalon.Test.Install.Production` -- expected: `CLASS … passed`.
- (once) `<lane> OCUTALON_RUN_TAG=e5s1i ci/iris.sh shard lane-a` -- expected: passed. Split it into per-class calls if it nears 8 minutes; Epic 3's last run took about 410 s.
- (once) `<lane> OCUTALON_RUN_TAG=e5s1i ci/iris.sh shard lane-b` -- expected: passed. It holds `Test.Core.CommandsInProduction`.
- (once) `bash ci/checks.sh` and `bash docker/tests/test-mock.sh` -- expected: all pass.
- (once, only if a block is appended to `docker/tests/test-install-start.sh`) `<lane> OCUTALON_RUN_TAG=e5s1i ci/iris.sh live install-start` -- expected: passed (fresh only; never warm).
- (once) `<lane> OCUTALON_RUN_TAG=e5s1iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s1i ci/iris.sh teardown`.

**Shared surfaces:**
- Chat `TOOLSETS` and the ChatAgent tool inventory: `Agent.Instructions`, `Agent.Runners`, `Tools.Reminders` and `Bridge.Decide`'s size.
- The `CommandCall` refusal texts.
- `CommandsDouble`'s verbs.
- The production stub table (`Install.Production`).
- `CommandsInProduction`'s stub-owner rows (contended).
- `CALLBACKHELPERS`.
- The `lane-a` shard areas.
- The gate's built-in tool scan.
- The `ci/mock/scenarios/A` set.
- Every test added or changed passes on a fresh environment, in either order.

**Planned pinning mutations** (Rule 19; the implement stage records the observed red):
- Drop the `CheckUserPermission` filter → `Test.Watch.Reader` lists OCUTALON.
- List every `Ens.Config.Production` row instead of the current one → the DW-38 row matches twice.
- Skip the natural-key check → `Test.Watch.Ops` finds two rows.
- Delete by `Namespace` and `Production` only → the other session's row goes.
- Set start_watch `READONLY` to 1 → `Gate`'s untrusted run is no longer denied.
- Drop the restore in `CommandCall` → the job-session test fails.
- Remove the `RESULT` check → the `test-ci-warm.sh` block fails.

**Observed pinning mutations** (Rule 19; each applied, run, observed red, reverted; the tree was byte-identical afterwards):
- mutation: drop the `CheckUserPermission` filter (`Reader.Readable` quits 1) -> `Test.Watch.Reader` `TestUnreadableNamespaceIsLeftOut` fails (OCUTALON is listed and admitted).
- mutation: read a production row by description instead of the current production (`Reader.Current` takes the `Ens_Config.Production` row described Orders) -> `Test.Watch.Reader` `TestReadableNamespaceOffersItsOwnProduction` fails (the DW-38 row matches twice).
- mutation: skip the natural-key check (`Ops.OnStart` sets `ref` to "") -> `Test.Watch.Ops` `TestRepeat` fails (two rows).
- mutation: delete by `Namespace` and `Production` only (`Ops.OnStop`) -> `Test.Watch.Ops` `TestStop` fails (the other session's row goes).
- mutation: `READONLYSTARTWATCH` 1 -> `Test.Bridge.Gate` `TestUntrustedTurnRunsOnlySafeReadOnly` and `TestWatchToolsAreClassified` fail (start_watch is no longer denied).
- mutation: drop the job-session restore in `CommandCall.Run` -> `Test.Watch.Tools` `TestSubmitKeepsTheJobSession` fails (five assertions).
- mutation: drop the `RESULT` check (`warm_up` passes no check to `stack_ready`) -> the appended block of `docker/tests/test-ci-warm.sh` fails (4 checks).
- mutation: drop the keep and off path's `ServiceRole(0)` in `Demo.System` -> the appended block of `docker/tests/test-install-start.sh` fails (`CHK|role|1`, wanted 0).
- mutation: `Ops.OnStart` writes `Kind` "other" (fresh stack) -> `Test.Watch.Turns` `TestStartThroughTheAgent` fails (the row's Kind and `Ownership.Checks`' Kind) (AC 1).
- mutation: `Ops.OnStop` deletes by `Namespace` and `Production` only, with SQL (fresh stack) -> `Test.Watch.Turns` `TestStopLeavesTheOtherSession` fails (the other session's row is gone and `Ownership.Checks` no longer lists it) (AC 2).
- mutation: `WatchTools` `READONLYSTOPWATCH` 1 (fresh stack) -> `Test.Watch.Turns` `TestInjectedStop` fails (the stop_watch step is not denied, the row is deleted, WatchOps and CommandsIn see the command) (AC 3).
- mutation: the started sentence of `Agent.Chat` says "stay silent" -> `Test.Agent.Instructions` `TestChat` fails; `TOOLSETS` without `OcuTalon.Tools.Watching` -> `TestToolsets` fails (AC 4).
- mutation: `OcuTalon.Live.Event` removed from `CALLBACKHELPERS` -> `Test.Bridge.CodeRules` `TestCallbackRule` fails (BridgeSink's callee, DW-177); `OcuTalon.Tools.WatchAnswers` removed from it -> the same test fails (AC 7).
- mutation: `Demo.WithOrdersData` also adds `%DB_OCUORDERS_CODE:R` -> `Test.Watch.Grant` `TestHelper` fails (five assertions); `Demo.System` skips `ServiceRole(1)` on the on path (fresh stack) -> `Test.Watch.Grant` `TestReaderNeedsTheGrant` and `TestRoleHoldsTheDataDatabaseOnly` fail (AC 8).
- mutation: `Reader.Label` without the 128-character cut -> `Test.Watch.Reader` `TestLabel` fails (a 299-character label).
- Note: a warm stack reloads classes, but a running production job keeps its old code, so a mutation of `WatchOps` is seen by `Test.Watch.Ops` (shadow instance) on a warm stack and by `Test.Watch.Turns` (the production's item) only on a fresh one.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The Chat agent now has start_watch, stop_watch and list_productions (`Tools.Watching`, `Tools.WatchTools`, `Tools.WatchAnswers`). `Watch.Reader` is the one namespace switcher and read-access check; `WatchOps` is real (natural-key repeat, own-row stop, owner check on every start, asking user from the `Session` row). The Chat instructions carry the UX sentences. `Install.Step.Demo` gives `OcuTalonServiceRole` Read on `%DB_OCUORDERS_DATA` only with demo mode on, and the off and keep paths remove it (U-79). DW-164 (`warm up` reads the after-start log's last `RESULT` line), DW-177 (`CALLBACKHELPERS` covers BridgeSink's callees) and DW-74 (job session kept) are closed.

**Files changed** (paths under `src/ocutalon/cls/OcuTalon/` unless noted):
- New: `Watch/Reader.cls`; `Tools/{WatchTools,WatchAnswers,Watching}.cls`; `Test/Watch/{Case,Reader,Grant,Ops,Tools,Turns}.cls`; `ci/mock/scenarios/A/watch-{start-orders,start-unknown,stop-orders,injected-stop}.json`.
- Changed: `Watch/Ops.cls` (real WatchOps), `Tools/CommandCall.cls` (neutral texts, `Session()`), `Agent/Chat.cls`, `Install/Step/Demo.cls` (service-role grant), `ci/{iris,warm,units}.sh`, one appended block each in `docker/tests/test-ci-warm.sh` and `docker/tests/test-install-start.sh`.
- Tests changed: `Test/Bridge/{Gate,CodeRules,Decide}.cls`, `Test/Agent/{Instructions,Runners,Decide}.cls`, `Test/Tools/{CommandsDouble,Reminders}.cls`, `Test/Install/{Production,Registry}.cls`, `Test/Core/CommandsInProduction.cls` (WatchOps row only).

**Review.** 34 findings: high 0, medium 5, low 27, false 2. Patched (4 entries): `Reader.Label` (a description over 128 characters or with line breaks overflowed `DisplayName`), `TestUsageTurn`'s unfailable `first > 0` assertion, `Tools.WatchAnswers` added to `CALLBACKHELPERS` and `READERCLASSES`, and the missing Rule 19 mutation lines for AC 1, 2, 3, 4, 7, 8 (each mutation observed red and reverted). Deferred: 1 (WatchOps' `failed` paths and session lock untested; in `deferred:`). Rejected: the rest, each with its reason in the Review Triage Log. Patched by verdict: medium 3, low 1.

**Follow-up review recommended: true** (three medium entries were patched on this first pass). The unverified risk: `Reader.Label` is pinned by a pure test and by the Orders description "Orders" through the real path, but no real production with a long or multi-line Description has gone through `Reader.Current`, `WatchOps` and the rail.

**Verification** (after the last patch): `bash docker/tests/test-ci-warm.sh` all PASS; warm up READY (the `RESULT OK` check ran); warm class runs passed for `Watch.Reader`, `.Ops`, `.Tools`, `.Turns`, `.Grant`, `Bridge.Gate`, `.CodeRules`, `.Decide`, `Agent.Instructions`, `.Runners`, `.Decide`, `Tools.Reminders`, `Install.Production`; fresh `shard lane-a` passed (52 classes, 422 s); fresh `shard lane-b` passed (42 classes, 138 s); `bash ci/checks.sh` all pass; `bash docker/tests/test-mock.sh` 94 of 94; fresh `ci/iris.sh live install-start` passed (with the U-79 block). Warm stack `e5s1iw` and fresh `e5s1i` torn down, no leftover container or lock. The mutation runs are under Verification (observed list); the tree was byte-identical after them.

**Veto-window items for the lead** (both ruled before this stage): U-79 (the service role's Read on `%DB_OCUORDERS_DATA`, `Install/Step/Demo.cls`) and U-80 (`TRUSTEDOUTPUT` 1 on all three watch tools).

**Residual risks.**
- A watch cannot be stopped through the tool once the reader stops listing its production (the spec's rule; `WatchOps` itself would delete the row; Story 16.4's `SessionOps.End` goes through WatchOps).
- `warm_start_result` passes a log with no content at all, because the existing hermetic stubs return none; a real start's log always holds a RESULT line.
- A warm stack reloads classes but a running production job keeps its old code: a change to WatchOps is proved by `Test.Watch.Turns` only on a fresh stack (noted for Rule 21's warm-mode note).
- `Test.Install.Registry` now restores the service role (its Roles step otherwise drops the Demo step's grant); a later test that reruns the Roles step without restoring would blank every Watch class.
