---
title: 'Story 0.6: Every release-1 production item runs as a stub, beside the Orders production'
type: 'feature'
created: '2026-10-19'
status: 'done'
baseline_revision: 'd127fb0a57fb2b4b1e7cd8d07e5477dcac09fac4'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** OCUTALON has no production. The `Production` installer step is a stub that starts nothing. No production item class exists, and neither do the bridge's extension bases. The cross-lane APIs of AD-29 are missing, and so are `Commands.Submit` and the constants that the CI mock keys on. So neither lane can replace a stub with a real item without editing the other lane's files. Also, `test-storage.sh` misses the storage blocks of business processes and other message bodies (DW-13).

**Scope (Rule 22 split, October 19).** The demo-mode group of this story's acceptance criteria moved to Story 0.10: the `Demo` step, OCUORDERS, the Orders production, its transform and `eval/`. The title still names the Orders production; that work is 0.10's.

**Approach:**
- **The production.** Add `OcuTalon.Production` with all 38 release-1 items in two lane regions. 35 items are enabled; `TelegramIn`, `TelegramOut` and `EvalIn` are disabled. Every unbuilt item is a stub class that answers "not implemented" and carries a stub marker.
- **The `Production` step.** Build the step. It starts, recovers or restarts the production, then waits until every enabled item runs and every runner resolves a model.
- **The bridge's extension points.** Add the extension bases and their accessor, fix the HostSink payloads, and add the two stubs that `Decide`'s settings name.
- **Cross-lane contracts.** Add the cross-lane APIs as signatures with stub bodies. Implement `Commands.Submit` fully, together with the part of `Bridge.Context` it needs.
- **Constants.** Add the agent classes with their `MOCKKEY`, the built-in tool names and the compaction prompt.
- **DW-13.** Widen `test-storage.sh`.

## Boundaries & Constraints

**Always:**
- **Lanes (AD-29, AD-33).**
  - The production has exactly one `ProductionDefinition` XData block.
  - Each item sits between its lane's markers, `<!-- lane A: begin -->` … `<!-- lane A: end -->` (then the same for lane B), as the ownership table in Design Notes says.
  - Every class goes in its owning lane's package.
- **The bridge (AD-2, AD-31).**
  - No class under `src/bridge/` references another `OcuTalon` package, not even through a setting's default.
  - `src/bridge/` still loads and installs alone (`test-install-start.sh` row 5, `other-classes` 0).
- **Structure only in the production class (AD-5).** The XData holds items, classes, pool sizes, enabled flags and these structural settings only:
  - the runners' `AgentClass`;
  - the routers' `BusinessRuleName`;
  - `Decide`'s `HostSinkClass` and `ReplyFilterClass`.

  Changeable values, such as `EvalIn`'s switch and every model, live in System Default Settings.
- **Stubs.** An unbuilt item class has `Parameter STUB = 1` and declares its one handler as `Quit $$$ERROR($$$NotImplemented)`. Its job never dies on a request. A cross-lane API stub follows 0.4's `Data.Delivery` pattern:
  - a `%Status` method returns `$SYSTEM.Status.Error(5001, "<Class>.<Method> is not implemented yet (Story <id>)")`, where `<id>` is the story the Design Notes signature table names in parentheses (for example "OcuTalon.Bridge.Approval.Raise is not implemented yet (Story 3.4)");
  - any other method returns the neutral empty value listed in Design Notes.
- **Persistent classes (AD-5).**
  - Every business-process stub commits its compiler-generated `Storage Default` block verbatim.
  - Business processes and message bodies set no `DEFAULTGLOBAL` (DW-13).
- **No model key (FR-38, AD-6).**
  - The production starts and every enabled item runs with no `ANTHROPIC_API_KEY`.
  - No item calls AI Hub's native library at start.
  - No test sends a model request.
- **Runtime targets (Rules 13, 21).**
  - **Slot A.** Every MCP call names `server: ocutalon-slot-a` and `namespace: OCUTALON`. Slot A tests:
    - only compile `OcuTalon.Production` and read its definition; they never start, stop or update it;
    - create only per-run `Zz`/`zz` fixtures (from `$Increment(^OcuTalonTest(<area>,"n"))`, never reset);
    - restore the one System Default Setting row they touch;
    - remove what they create.
  - **Throwaways.** Starting, stopping, recovering, killing and recompiling run only in throwaway projects through `docker/tests/lib-live.sh`, one IRIS stack at a time.
- **Source text.** ASCII only. Comments state contracts, never history (Rule 14).

**Never:**
- **Owned by later stories:**
  - the real behaviour of any item or API;
  - the adapter's start refusals and its build on first use (1.2);
  - seeding the runners' `Model` setting, the Config Store entries, and the agents' INSTRUCTIONS and TOOLSETS (1.1);
  - the OnEvent wrapper and the reply-filter call inside `Decide` (1.3 and 1.4);
  - the Workflow role (Epic 3);
  - marking the production autostart on an IPM install (15.2);
  - the Telegram switch (12.1);
  - everything in 0.10.
- **Autostart.** Never make `OcuTalon.Production` autostart on the Docker path (AD-3).
- **No save to the class.** Never enable or disable an item through `Ens.Director.EnableConfigItem` or a production save. Those change the stored definition, which the next compile overwrites.
- **No wrong production.** Never stop or replace a production other than `OcuTalon.Production`.
- **References and secrets.** Never load anything from `irislib/` or `irissys/`, and never read `.env`.
- **No new dependencies.** No new Python or npm package.

## I/O & Edge-Case Matrix

Where each row runs:
- Rows 1–11: slot A `%UnitTest` classes.
- Row 12: `test-storage.sh`.
- Rows 13–18 and 21: `test-production.sh`.
- Rows 19–20: `test-production-restart.sh`.
- Row 22: the existing live scripts.
- Row 23: the slot A round trip.

| # | Scenario | Input / State | Expected | Error Handling |
|---|---|---|---|---|
| 1 | Definition | compiled `OcuTalon.Production`'s XData | exactly the 38 items of the Design Notes table (name, class, pool size, enabled, settings); each between its lane's markers; the four markers once each, in the order A-begin, A-end, B-begin, B-end; no item outside a region; `TestingEnabled` false | none |
| 2 | Accessor, from another job | a `Job`'d process calls `Ext.Accessor.ClassFor(setting, "OcuTalon.Production")` | `HostSinkClass` gives `OcuTalon.Core.BridgeSink`, `ReplyFilterClass` gives `OcuTalon.Checks.ReplyGuard`, `ClassificationClass` gives `OcuTalon.Bridge.Ext.Classification`. Each of these gives `""` with an error status: setting `ZzClass`; item `Zz<n>`; production `Zz<n>.Production`; `Check("HostSinkClass", "%Library.String")` | error status |
| 3 | Stubs answer | every item whose class has `STUB` = 1: a shadow instance (`%New("")`) and its handler, given an `Ens.StringRequest` | status code 5003, no response, and no new `Ens.Util.Log` row. The two rule classes have `STUB` = 1 and a rule set with no rule. Every item class is compiled | code 5003 |
| 4 | Runner models | `AgentRunner.ResolveModel(item, "OcuTalon.Production")` | `claude-haiku-5-5` for the three runner items; `""` for `Zz<n>`. `Step.Production.UnresolvedRunners("OcuTalon.Production")` is `""` | none |
| 5 | Step helpers | `EvalEnabled(v)`; `SetEval(1)`, then `SetEval(0)`; `NotRunning()` with no production running | `EvalEnabled` is 1 only for `"1"` (not for `""`, `"0"`, `"true"` or `" 1"`). The System Default Setting row (`OcuTalon.Production`, `EvalIn`, `*`, `Enabled`) holds 1, then 0, and the test then restores the row it found. `NotRunning()` says `OcuTalon.Production is not running` | none |
| 6 | Extension bases | the three bases; the stubs `Core.BridgeSink` and `Checks.ReplyGuard` | `HostSink.OnEvent` returns OK for each of the 8 types, and its `EVENTS` parameter lists exactly those 8. The payload builders give exactly `{"ref"}`, `{"decisionRef","label"}` and `{"day"}`. `BridgeSink` extends `HostSink`, returns OK and writes no `Live.Event` row. `Filter(text)` returns the text unchanged (`ReplyGuard` too, for "Everything I checked passed."). `Classify` returns `""` | none |
| 7 | Context | no context; then `Begin(request, "zzss<n>")`; then a `Job`'d probe; then `Put("Tainted", 1)` and `End()` | `Active()` is 0 and `Current()` is `""` before `Begin`. After `Begin`, `Active()` is 1, and `Current()` carries the request's fields and the SuperSession. The other job sees `Active()` = 0. After `Put`, `Current().Tainted` is 1. After `End()`, `Active()` is 0 | none |
| 8 | Submit's origin | a `Command.ListReminders` whose payload `Origin` is `web_admin` | origin `web_user`, outside a context: `Origin` becomes `web_user`. Inside a context with `web_admin`: it becomes `tool`. Origin `zz` or `""`, or a non-command object: an error naming the problem, and `Origin` keeps its value. The send fails on slot A (no production is running there), so the test doesn't assert the send's status | error status |
| 9 | API stubs | each stub of the Design Notes signature table | each `%Status` stub's error text contains "is not implemented yet". `Answer` returns `not_found` with `winner` `{}`. `Budget.State()` is `{"spent":0,"cap":0,"capped":false,"resetsAt":""}`. `Keys.Status` is 0. `Timeouts.Derive(60)` is `{}`. `Input.Render` gives `""`. `Checks.Render.Render([])` gives `""` with `rows` `[]`. `Recipients` gives `""`. `TurnCost` and `RunCost` give `{}` | none |
| 10 | Signatures | `Test.Contract.Ac` `Signatures` with the 31 new rows | every row keeps its parameter names in order (an Output parameter is written with its `*`) and its return type; the count is at least 43 | none |
| 11 | Constants | the agent, tool and compaction classes | `MOCKKEY` is `triage`, `diagnosis` and `chat`, one per agent. Each agent extends `%AI.Agent`, has `MODEL` `claude-haiku-5-5`, and has no `{{` in INSTRUCTIONS. `Tools.Names` has 11 distinct snake_case values, and `RELEASE1` lists exactly them. `Compaction.Prompt()` is ASCII, its first line starts `OCUTALON-COMPACTION-V1`, and it names `user_goals`, `constraints`, `decisions`, `facts_learned`, `tool_actions`, `open_questions` and `next_steps` | none |
| 12 | DW-13 | synthetic trees; the real tree | three samples without a storage block are each flagged by `storage`: one extends `Ens.BusinessProcess`, one `Ens.MessageBody`, one `Ens.StreamContainer`. A process with a storage block and no `DEFAULTGLOBAL` is not flagged by `registry-param`. The real tree passes every rule | exit 1 on a flag |
| 13 | First start, no key | `test-production.sh`, Health image | the log has `STEP Production OK`, then `RESULT OK`; the container is healthy; the production state is Running, named `OcuTalon.Production`; `^Ens.AutoStart` is not `OcuTalon.Production` | FAIL names the check |
| 14 | Items run | the running production | each of the 25 items with a pool has at least one `Alive` job whose status isn't `error`, `halted` or `terminated`. The 10 adapterless services are enabled, have no job, and `CreateBusinessService` succeeds for each. `TelegramIn`, `TelegramOut` and `EvalIn` have no job, and `CreateBusinessService("EvalIn")` is refused as disabled | FAIL names the item |
| 15 | Accessor outside Decide | a terminal session, default production | the three classes of row 2 | none |
| 16 | Stub over the production | a created `CommandsIn` service sends `SendRequestSync` to `SessionOps`, `Conversation`, `TriageAgent` and `OutcomeRouter` | `SessionOps`, `Conversation` and `TriageAgent` answer code 5003. `OutcomeRouter` answers OK and routes nothing. Every target keeps the job ids it had before | none |
| 17 | Submit, live | `Submit(ListReminders, "web_user")`; then the same inside `Context.Begin`; then origin `zz` | the first two return `CommandsIn`'s 5003, with `Origin` `web_user` and then `tool`. Origin `zz` is refused naming `zz` | error status |
| 18 | Running branch | `Step.Production.Start(30)` while the production runs | OK; every item with a pool has new job ids; `NotRunning()` is `""` | none |
| 19 | EvalIn switch | `test-production-restart.sh`: recreate with `OCUTALON_EVAL=1`, then without it | with the variable: `STEP Production OK`, `CreateBusinessService("EvalIn")` succeeds, and the System Default Setting row is 1. Without it: refused as disabled, and the row is 0 | none |
| 20 | Unclean stop | `docker kill -s KILL`, then `dc start iris` | the step recovers if it finds the production Troubled (Task 0 records the state found); `STEP Production OK`; the production runs; row 14's job check passes | none |
| 21 | An item can't start | in the stack, a fixture `OcuTalon.Watch.Ops` whose `OnInit` returns an error is compiled; `Start(15)` runs; the original is compiled back; `Start(30)` runs again | the first `Start` is an error naming `WatchOps`. After the restore, `Start` is OK and `WatchOps` runs | error status |
| 22 | Existing installs | `test-install-start.sh`, `test-install-upgrade.sh`, `test-sign-in.sh`, `test-audit.sh` | still pass with the production running. The STEP list is unchanged. Row 5 still loads the bridge alone, with `other-classes` 0 | as before |
| 23 | Storage round trip | load, compile and export on slot A | every business-process stub's file is byte-identical | none |

</intent-contract>

## Code Map

- **Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`), by line:
  - AD-1 L96–106 (Submit and Origin, L104); AD-2 L108–119; AD-3 L139 (not autostart); AD-5 L174–183; AD-6 L185–216 (runners and adapter L192–200, Context L213); AD-7 L218–236 (model resolution L225); AD-8 timeouts L260–263; AD-11 L309–323.
  - AD-20 L518–542 (compaction prompt L535); AD-22 L574–594 (mock keys L582–587, `EvalIn` L591); AD-23 L596–639 (the `Production` step L615); AD-28 L745–753; AD-29 L755–769 (regions L764, release-cut rule L768); AD-31 L793–808 (payloads L804); AD-33 L821–829.
  - Conventions L865–887; production seed L913–1000; item ownership table L1004–1027; cross-area classes L1031–1048; event table L1050–1065.
- **Epics** (`_bmad-output/planning-artifacts/epics.md`):
  - this story L909–939;
  - consumers: 0.7 L941–982 (lane-region check L965, `OCUTALON_EVAL` pass-through L960); 0.10 L1019–1032; 1.1 L1040–1069 (agents L1048, model check L1060–1062); 1.2 L1072–1098 (adapter L1079–1082); 2.3 L1480–1500 (Submit's caller); 11.5 L3379 (refuses "not implemented"); 15.2 L3873 (IPM autostart).
- **Existing code:**
  - `src/ocutalon/cls/OcuTalon/Install/Step/Production.cls`: the stub, to replace in place.
  - `Install/Registry.cls`: `Order()` L12–15 (unchanged); `RunStep` L117–131 calls `Run()` with no argument.
  - `Install/Step.cls`: the `Run()` contract.
  - `Channel/Telegram/In.cls`: 0.4's disabled stub with `Ens.InboundAdapter`. It is used as is, and its class is not changed.
  - `Msg/Command.cls` L8–9 (`Origin`); `Msg/Enum.cls` L39 (`ORIGIN`); `Msg/Command/ListReminders.cls` (the fixture verb); `Msg/CommandResult.cls`.
  - `Data/Delivery.cls` L25–38: the API-stub pattern to follow. `Data/Session.cls` gains `Recipients`, with no storage change.
  - `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`: the fields `Context.Begin` copies. `Bridge/Data/ApprovalRequest.cls`: `Raise`'s argument.
- **Tests to extend:**
  - `src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls`: `TestCrossLaneSignatures` L138–161 (floor `>= 12` at L160; `ParameterNames` L191–199 keeps an Output parameter's `*`); `XData Signatures` L286–305.
  - `Test/Data/Tables.cls` `TestDeliveryStubs` L80–86 (the stub-test pattern); `TestSqlNames` covers the new persistent processes. Their table names are not reserved words: Process, Decide, ApprovalHold, Conversation, Intake, ReminderTimer and IncidentManager all measure 0.
  - `Test/Data/Session.cls` L1–22: the fixture-counter pattern.
- **Shell tests:**
  - `docker/tests/test-storage.sh`:
    - `roots` L54, `message()` L41–50, `registry-param` L143;
    - `make_tree` L162–171, the bad samples L200–218, the rules L256–264;
    - the header L2–18, which says what a storage-bearing class is.
  - `docker/tests/lib-live.sh`:
    - `live_start` L20, `live_add_file` L44, `live_pop_file` L442;
    - `dc` L136, `iris_script` L190, `check_session` L317, `session_value` L325;
    - `wait_started_log` L235, `wait_started_ready` L245, `log_steps` L416, `expected_run` L421–425 (the STEP list, unchanged);
    - `marker` L214, `health_status` L204.
  - `docker/tests/test-install-start.sh` row 5 L194–232 (the bridge alone). `docker/tests/test-install-upgrade.sh` L27–66 shows the recreate pattern.
- **IRIS reference** (read only):
  - `irislib/Ens/Director.cls`:
    - `StartProduction` L15 (refuses Running and Troubled; resumes Suspended), `UpdateProduction` L159, `RestartProduction` L323 (stops, then starts), `GetProductionStatus` L531, `IsProductionRunning` L601, `RecoverProduction` L688 (Troubled to Suspended);
    - `CreateBusinessService` L1450 (refuses a disabled item);
    - `EnableConfigItem` L1561 (saves the definition; not used);
    - `GetItemSettingValue` L1755 (reads the definition tables; works with no production running).
  - `irislib/Ens/Config/Item.cls`:
    - `PoolSize` L38–41 (0 for adapterless services);
    - `Enabled` L43–47: "This value can be overridden using System Default Settings … even if this value is defined in the production definition";
    - `getModifiedSettingValue` L306–341: the item's setting, then a System Default Setting, then the class's initial expression.
  - `irislib/Ens/Config/DefaultSettings.cls` L17 (IdKey: production, item, class, setting) and L20–38.
  - `irislib/Ens/Job.cls` L837 (`Enumerate`: Job, ConfigName, Status, State); `irislib/Ens/Util/Statistics.cls` L100.
  - `irislib/EnsConstants.inc` (production states L8–14, job statuses L26–34); `irislib/Ensemble.inc` (`$$$ConfigIsEnabled` L144, `$$$ConfigPoolSize` L151).
  - `irislib/Ens/Host.cls` L471–524: `%New("")` makes a shadow instance and runs no `OnInit`.
  - `irislib/Ens/BusinessService.cls` L132; `BusinessProcess.cls` L839 (logs through `$$$EnsError`; the stubs override it), storage `^Ens.BusinessProcessD` L1403; `BusinessOperation.cls` L707.
  - `irislib/EnsLib/AI/Agent/OutboundAdapter.cls`: `AgentClass` L15, `Model` L61, `SETTINGS` L123, `OnInit` L129–144 (builds the agent at start).
  - `irislib/%AI/Agent.cls`: `MODEL` L18, `%Init` L197–232.
  - `irislib/EnsLib/Workflow/Operation.cls`: `AutoCreateRole` L16 defaults to 0; `OnInit` L54 starts without a role.
  - `irislib/Ens/Rule/Definition.cls` L10–13 (projection); `irislib/Ens/Rule/Model/ruleDefinition.cls` L99 (`XMLNamespace "http://www.intersystems.com/rule"`).
- **Measured on slot A, October 19** (build 154 Health ARM64, profile `ocutalon-slot-a`, `OCUTALON`, read-only calls):
  - `$$$ERROR($$$NotImplemented)` reads "ERROR #5003: Not implemented". `<Ens>ErrNotImplemented` reads "Method X.Y() not implemented".
  - Slot A has `ANTHROPIC_API_KEY` set, so no-key behaviour is measured only on throwaways.
  - Slot A's `^Ens.Configuration("csp","LastProduction")` is `OCUTALONPKG.FoundationProduction` (stopped), and the namespace's production state is Stopped. So no test may rely on the "active" production on slot A; tests pass `OcuTalon.Production` explicitly.
  - `^Ens.AutoStart` is empty.

## Tasks & Acceptance

**Execution:**

**Task 0, measure.** These run after the IRIS classes below compile, on one throwaway built from the tree with no key (Health image). Record each result under Verification; anything left unmeasured is labelled `(inference)`.
- Right after `StartProduction`:
  - what `Ens.Job:Enumerate` shows for each kind of item (process, operation, runner with the stub adapter, router, Workflow operation): `ConfigName`, `Status` and `State`;
  - how many seconds pass until every item with a pool has an `Alive` job;
  - whether `StartProduction` writes lines to the session device.
  
  This settles the predicate `NotRunning()` uses. If a status other than `error`, `halted` or `terminated` means "not running", tighten the predicate and note it.
- Does a System Default Setting `Enabled` row for `EvalIn` (value 1, then 0) decide `$$$ConfigIsEnabled("EvalIn")` and `CreateBusinessService("EvalIn")` at the next start?
- What production state does the after-start `Production` step find after `dc restart iris`, and after `docker kill -s KILL` followed by `dc start iris`? Does IRIS's own start recover it first?
- Does an error from an adapterless service's `OnProcessInput`, reached through `CreateBusinessService` and `ProcessInput`, write an `Ens_Util.Log` row for `CommandsIn`? (If it does, row 17 also checks that row.)
- What does a router whose rule set is empty answer to a `SendRequestSync`: OK with no response, or an error? Row 16 asserts what is measured, and the job must stay alive either way.
- For Story 1.2, informational only: with no key and no provider in a terminal session, what do `##class(OcuTalon.Agent.Triage).%New()` and `%Init()` return?
- On slot A:
  - does compiling `OcuTalon.Production` change `^Ens.Configuration("csp","LastProduction")`?
  - does a shadow instance's stub handler add any `Ens.Util.Log` row?

IRIS, Lane A (`src/bridge/cls/OcuTalon/Bridge/`, unless a path says otherwise):
- `Ext/HostSink.cls`, `Ext/ReplyFilter.cls`, `Ext/Classification.cls`: the bases with do-nothing defaults. `HostSink` has the event-type parameters, `EVENTS`, and the three payload builders. AD-31.
- `Ext/Accessor.cls`:
  - `Parameter BASES` maps each setting to its base.
  - `ClassFor(setting, production = "", item = "Decide", Output sc)` reads the setting through `Ens.Director.GetHostSettingValue(production_"||"_item, …)`. An empty production means `Ens.Director.GetActiveProductionName()`.
  - It returns the class only when `Check(setting, class)` passes (compiled, and extends the base). Otherwise it returns `""` with the error, and never silently falls back to a base. AD-31.
- `Process/Decide.cls`: a `STUB` process.
  - Settings properties `HostSinkClass`, `ReplyFilterClass` and `ClassificationClass`, whose initial values are the three bases (`SETTINGS` category `Extensions`).
  - Then compile and copy its storage block in.
- `Process/ApprovalHold.cls`: a `STUB` process, with its storage block. `Service/ApprovalStart.cls` and `Operation/Steps.cls`: `STUB` hosts.
- `Adapter/Agent.cls`: extends `EnsLib.AI.Agent.OutboundAdapter`, with `OnInit()` returning OK. So nothing calls AI Hub at start, and the item runs with no key. Story 1.2 builds the rest. AD-6.
- `Operation/AgentRunner.cls`: a `STUB` operation with `ADAPTER = "OcuTalon.Bridge.Adapter.Agent"`.
  - `ResolveModel(item, production = "")`: the adapter's `Model` setting (item, then System Default Setting); if that is empty, the `MODEL` parameter of the adapter's `AgentClass` when that class extends `%AI.Agent`; otherwise `""`. AD-7, AD-23.
- `Approval.cls`, `Budget.cls`, `Keys.cls`, `Timeouts.cls`, `ConfigStore.cls`: the signatures and stub bodies of the Design Notes table. AD-8, AD-11, AD-19, AD-20.
- `Context.cls`, a `%RegisteredObject`:
  - properties `Kind`, `Provenance`, `ItemId`, `DecisionRef`, `OwnerRef`, `TraceRef`, `Channel`, `ThreadSessionId`, `SuperSession`, `Tainted` (`%Boolean`, initial 0) and `HostData`;
  - class methods `Begin`, `End`, `Active`, `Current` and `Put`, implemented over the process-private global `^||OcuTalonBP.Context`. AD-6.
- `Compaction.cls`: `Parameter PREFIX = "OCUTALON-COMPACTION-V1"`, `XData Prompt` (the text in Design Notes), and `Prompt() As %String`, whose lines are joined by `$Char(10)`. AD-20.

IRIS, Lane A (`src/ocutalon/cls/OcuTalon/`):
- `Agent/Triage.cls`, `Agent/Diagnosis.cls`, `Agent/Chat.cls`: extend `%AI.Agent`, with `MODEL = "claude-haiku-5-5"` and `MOCKKEY` `triage`, `diagnosis` and `chat`. No INSTRUCTIONS or TOOLSETS (1.1). AD-7, AD-22.
- `Agent/Input.cls`: `Render(item)`, a stub. `Checks/Render.cls`: `Render(results, .rows)`, a stub.
- `Checks/ReplyGuard.cls`: extends `Ext.ReplyFilter`, with no members of its own.
- `Tools/Names.cls`: the 11 parameters and `RELEASE1`. AD-22.
- `STUB` item classes:
  - `Channel/Telegram/Out.cls`;
  - `Watch/FailurePoller.cls` (an adapterless service), `Watch/IncidentManager.cls` (a process, with its storage block), `Watch/Ops.cls`;
  - `Eval/In.cls` (adapterless), `Eval/Sink.cls`;
  - `Fix/Executor.cls`;
  - `Checks/Process.cls` (a process, with its storage block);
  - `Digest/Store.cls`.
- `Install/Step/Production.cls`, filled in place (`Include Ensemble`):
  - **Parameters:** `PRODUCTION = "OcuTalon.Production"`, `EVALITEM = "EvalIn"`, `WAITSECONDS = 60`, `STOPSECONDS = 30`.
  - **`Run()`:** calls `SetEval(EvalEnabled($SYSTEM.Util.GetEnviron("OCUTALON_EVAL")))`, then `Start(..#WAITSECONDS)`.
  - **`Start(wait)`:** reads `GetProductionStatus`, then:
    - this production running: `RestartProduction(..#STOPSECONDS)`;
    - another production running: an error naming it;
    - Troubled: `RecoverProduction()`, then `StartProduction`;
    - Stopped or Suspended: `StartProduction`.
    
    It then polls each second, up to `wait`, until `NotRunning()` is `""`. It fails naming those items, or naming `UnresolvedRunners(..#PRODUCTION)` when that isn't empty.
  - **`NotRunning()`:** the comma list of enabled items (`$$$ConfigIsEnabled`) with a pool (`$$$ConfigPoolSize > 0`) and no `Alive` job whose status is outside `error`, `halted` and `terminated` (from `Ens.Job:Enumerate`). It returns "OcuTalon.Production is not running" when the production isn't running under that name.
  - **`UnresolvedRunners(production)`:** the enabled `AgentRunner` items whose `ResolveModel` is `""`.
  - **`EvalEnabled(value)`:** 1 only for `"1"`.
  - **`SetEval(enabled)`:** writes the System Default Setting row (`PRODUCTION`, `EVALITEM`, `*`, `Enabled`), with 1 or 0, at every start (structural). The description says the step writes it.
  - **Class doc:** never marks autostart. AD-3, AD-5, AD-22, AD-23.

IRIS, Lane B (`src/ocutalon/cls/OcuTalon/`):
- `STUB` item classes:
  - `Channel/WebChat/In.cls` (adapterless), `Channel/WebChat/Out.cls`;
  - `Channel/SimMailbox/In.cls` (adapterless), `Channel/SimMailbox/Out.cls`, `Channel/SimPhone/Out.cls`;
  - `Core/AnswersIn.cls`, `Core/CommandsIn.cls`, `Core/NoticesIn.cls` and `Core/StatusMonitor.cls` (all four adapterless);
  - `Core/Conversation.cls` and `Core/Intake.cls` (processes, with storage blocks);
  - `Core/SessionOps.cls`, `Core/SettingsOps.cls`;
  - `Schedule/HeartbeatIn.cls` (adapterless), `Schedule/ReminderOps.cls`, `Schedule/ReminderTimer.cls` (a process, with its storage block);
  - `Demo/BreakFeedIn.cls` (adapterless), `Demo/PartnerTrigger.cls`.
- `Core/Rule/Outcome.cls` and `Core/Rule/Notify.cls`: extend `Ens.Rule.Definition`, with `RuleAssistClass = "EnsLib.MsgRouter.RuleAssist"`, `STUB = 1`, and `XData RuleDefinition` holding one empty rule set (golden example in Design Notes).
- `Core/BridgeSink.cls`: extends `OcuTalon.Bridge.Ext.HostSink`, with no members of its own. Story 2.6 replaces it.
- `Core/Commands.cls`: `Submit(command, origin, Output result)` as in Design Notes. AD-1.
- `Data/Ownership.cls`: `TurnCost`, `RunCost`. `Data/Session.cls`: append `Recipients(ownerRef, incidentRef = "") As %List`.

The production:
- `src/ocutalon/cls/OcuTalon/Production.cls`: `Extends Ens.Production`, holding the one XData block of the Design Notes table, in the table's order, with each lane's region. Pool sizes: 0 for adapterless services, 1 for every other item. AD-3, AD-29, AD-33.

Tests:
- New slot A test classes:
  - `Test/Install/Production.cls` (A): rows 1 and 3–5. Its oracle is `XData Items`, a copy of the Design Notes table. The run's number is `^OcuTalonTest("Production","n")`.
  - `Test/Bridge/Ext.cls` (A): rows 2, 6 and 7. The child jobs report through `^OcuTalonTest("BridgeExt",n,…)`, which is deleted afterwards.
  - `Test/Bridge/Api.cls` (A): row 9 for the bridge's stubs and for `Agent.Input` and `Checks.Render`.
  - `Test/Agent/Constants.cls` (A): row 11.
  - `Test/Core/Commands.cls` (B): row 8, plus row 9 for `Recipients`, `TurnCost` and `RunCost`.
- `Test/Contract/Ac.cls`: append the 31 rows to `XData Signatures` (row 10), and raise the floor to `count >= 43`. Rule 2: this extends the signature pin; it does not copy it.
- `docker/tests/test-storage.sh` (DW-13):
  - roots gain `Ens.BusinessProcess`, `Ens.BusinessProcessBPL`, `Ens.MessageBody` and `Ens.StreamContainer`;
  - the `message()` exemption covers `Ens.MessageBody` and `Ens.StreamContainer`;
  - a new `process()` exemption (`Ens.BusinessProcess`, `Ens.BusinessProcessBPL`) also skips `registry-param`;
  - `make_tree` adds a process with a storage block and no `DEFAULTGLOBAL`, and a message-body and a stream-container class with storage blocks;
  - new bad samples `no-storage-process`, `no-storage-body` and `no-storage-stream` join `rule storage`;
  - the header is updated. Row 12.
- `docker/tests/test-production.sh` (new, label `t06`): rows 13–18 and 21. It uses:
  - `live_start`, then `dc up -d --build` and `wait_started_ready 400`;
  - `iris_script OCUTALON` with `CHK|` lines;
  - a local `item_jobs` helper (job ids per item, from `Ens.Job:Enumerate`);
  - for row 21, a fixture class written by `dc exec` into `/tmp` in the container, loaded with `$SYSTEM.OBJ.Load`, then restored from `/opt/ocutalon/src/ocutalon/cls/OcuTalon/Watch/Ops.cls`.
  
  It finishes inside `lib-live`'s 540 s deadline.
- `docker/tests/test-production-restart.sh` (new, label `t06r`): rows 19–20.
  - `live_add_file` adds a compose file with `environment: {OCUTALON_EVAL: "1"}`, and `live_pop_file` removes it; each change is followed by `dc up -d` and `wait_started_ready`.
  - Then `docker kill -s KILL "$cid"`, `dc start iris` and `wait_started_ready`.
  - Both scripts receive no keys (the throwaway override). Each step can only be checked in a throwaway: it starts the production.

**Acceptance Criteria:**
- Given both trees loaded and compiled on slot A, when `Test.Install.Production`, `Test.Bridge.Ext`, `Test.Bridge.Api`, `Test.Agent.Constants`, `Test.Core.Commands` and `Test.Contract.Ac` run one per call, then rows 1–11 hold, and every existing class in the Verification list still passes.
- Given the tree, when `test-storage.sh` runs, then row 12 holds and every rule passes (DW-13).
- Given a fresh throwaway with no model key, when `test-production.sh` runs, then rows 13–18 and 21 hold. The same holds once on the non-Health image (`IRIS_IMAGE=iris-community:2026.3.0AI.154.0`).
- Given a fresh throwaway, when `test-production-restart.sh` runs, then row 19 (`EvalIn` follows `OCUTALON_EVAL`) and row 20 (a killed instance's next start ends ready with the production running) hold.
- Given the existing live scripts, when they run against the new tree, then row 22 holds: every check passes, the STEP list and `expected_run` are unchanged, and the bridge still loads alone.
- Given the committed storage blocks of the seven business-process stubs, when the trees are loaded, compiled and exported again on slot A, then no tracked file changes (row 23).

## Spec Change Log

Implement stage, October 19. No change to the intent contract. Each ruling below is one the contract could not settle or got wrong; none touches an AD.

- Rule 22 ruling: how does a test build the shadow instance of a stub item class (row 3)? -> `Ens.Host.GetShadowInstance("class||<class>")`, which makes the instance with config name 0 and runs no `OnInit`. (rejected: `%New("")`, which the contract names; it raises `<SUBSCRIPT>` at `initConfig+5^Ens.Host` on `^Ens.Runtime("ConfigItem","")`, measured on slot A for a process, an operation and a service.)
- Rule 22 ruling: what does row 16 expect from the `Conversation` process? -> the measured answer: `<Ens>ErrBPTerminated`, whose text carries `ERROR #5003: Not implemented`; the operations (`SessionOps`, `TriageAgent`) answer code 5003 itself; every job survives. (rejected: code 5003 for the process: a business process wraps the failing handler in `ErrBPTerminated`.)
- Rule 22 ruling: what does row 17 check in the log? -> an Error row (Type 2) for `CommandsIn` whose text holds "Not implemented" exists after the first `Submit`, not a new row per call. An adapterless service logs an error only when its text differs from the last one it reported, so a repeat writes no row (measured across three calls and two sessions). (rejected: a delta of one row per call.)
- Rule 22 ruling: how is AC5 pinned? -> row 5 of `test-install-start.sh` gains a source check: no code line under `src/bridge/cls/` names an `OcuTalon` package, as a class (`OcuTalon.Pkg`) or as a table (`OcuTalon_Pkg`), other than `OcuTalon.Bridge` and `OcuTalon.BridgeExample` (comment lines are skipped). The check first runs on two synthetic classes, which it must flag exactly twice and not at all, and fails when it finds no class to scan. The mutation the contract names (a `Decide` method that calls `##class(OcuTalon.Core.BridgeSink).OnEvent(...)`) left row 5 green: the compiler accepts a call to a class it cannot find, so the load, the install and `other-classes` 0 all pass. (rejected: leaving the pin unfalsifiable; calling `Decide` at run time; a rule in `test-boundaries.sh`, which is not the pin the contract names.)
- Rule 22 ruling: what does `Test.Data.Tables.TestSqlNames` do with the compiler-generated `...MessagesSent` and `...MessagesReceived` classes of a business process? -> it leaves them out (`GeneratedBy` is set; `%OpenId` refuses them as "a stub name"), and checks the process classes themselves. Without this, the first persistent process fails the 0.4 test. (rejected: counting them, which fails 14 assertions.)
- Rule 22 ruling: where do `item_jobs` and the row 14 job check live? -> `docker/tests/lib-live.sh` (`item_jobs`, `check_items_run`), because `test-production.sh` (rows 14 and 18) and `test-production-restart.sh` (row 20 repeats row 14) both read jobs. The item list is `Test.Install.Production.Items()` (public), which the shell reads inside the container, so the ownership table has one copy in the tests. (rejected: a helper local to `test-production.sh`, which row 20 cannot use; a third copy of the table in shell.)
- Rule 22 ruling: does `NotRunning()` count the production's own system items? -> yes, as the contract words it: every enabled item with a pool in the running production, `Ens.Actor` (pool 2), `Ens.Alarm`, `Ens.MonitorService` and `Ens.ScheduleHandler` included. Row 14 counts only the 25 items of the table. (rejected: limiting the step to the 38 definition items, which would let a dead scheduler pass.)
- Rule 22 ruling: what does `Start` do with a Troubled or Suspended production of another name? -> it fails naming it and recovers or starts nothing (Rule 22.4: no other production is touched). The contract's table covers only a running one. (rejected: recovering it, then starting this one.)
- Rule 22 ruling: what does `Context.Begin` do when a context is already set? -> it replaces it, and refuses an argument that is not a `Bridge.Msg.Request`; `Put` refuses a name that is not a field of `FIELDS`. (rejected: refusing a second `Begin`, which would block every later call of a process that an interrupted call left a context in.)

Findings for the lead (no spec change): the contract's Design Notes cite `%New("")` for the shadow instance (see the first ruling). The Rule 20 spine updates the Design Notes list stand; add that `Conversation`-style processes answer `ErrBPTerminated` when a stub handler fails.

Review pass, October 19. No change to the intent contract; no AD touched.

- Rule 22 ruling: do the contract's three wording errors (row 3's `%New("")`, row 16's `Conversation` answer, AC5's load-only pin) stop the story? -> no. Each was measured, decided and logged above, and the code makes the intended behaviour real. The matrix wording is for the lead to correct (Rule 5, apply and report: a wrong API and a wrong expected value that the AC cites). (rejected: an `intent gap` HALT, because the product promise is unchanged and Rule 22.1 says to decide and keep going.)
- Rule 22 ruling: does the step's "runs" check cover adapterless services? -> no, as the Tasks word it: `NotRunning()` checks the enabled items that have a pool; an adapterless service runs when it is enabled in the running production, and row 14's live check calls `CreateBusinessService` for each. (rejected: calling it inside the step, which the Tasks do not ask for.)
- Rule 22 ruling: does `Context.Put` guard identity fields or the taint? -> no: it is a plain setter over `FIELDS`, as the Context ruling says; the gate that owns taint is Story 1.2's. Reopen if 1.2 finds a tool path that clears `Tainted`. (rejected: a one-way taint ratchet now, which would fix a rule that 1.2 owns.)
- Patches made at review, all inside the story and each pinned (mutations below): the source check of row 5 (negative control, a floor of scanned classes, table names); row 20 confirms that the container started again after the kill; `test-production.sh` checks that the step fails naming another running production and leaves it running; `Submit` answers an error status, not `<UNDEFINED>`, when the origin or the command is left out; `Test.Install.Production` derives its stub count from the oracle, skips its not-running assertion where the production runs, and names a runner whose agent class does not exist; `Test.Bridge.Ext` covers an empty and a missing class in `Accessor.Check` and a second `Context.Begin`; `Test.Bridge.Api` pins the stub adapter's own `OnInit`; `Test.Agent.Constants` shows its `{{` detector flags a text that holds one; `Test.Data.Tables` shows the seven business processes are SQL-name checked; `test-storage.sh` gains a BPL sample and a subclass of a process; the class comment of the `Production` step lists the other-name cases.

## Review Triage Log

### 2026-10-19 — Review pass
- verdicts: 50 findings — high 0, medium 9, low 38, false 3, maybe-false 0
- findings:
  - Blind Hunter
    - `[low]` `[patch]` Both lanes edit one test literal (`stubs = 34`) whenever a stub is built — the count is now summed from the oracle's `stub` flags, so the owner edits only the item's own oracle row; the other counts (38, 35, 25, 10, 3) are the spec's published figures.
    - `[low]` `[reject]` `Context.Put` accepts identity fields and lets `Tainted` return to 0 — the Context ruling makes `Put` a plain setter; no caller exists in this story and the gate is Story 1.2's; recorded in the Change Log with a reopen condition; a ratchet adds a branch for a rule 1.2 owns.
    - `[low]` `[patch]` `NotRunning() = "... is not running"` and the log counts assume a stopped namespace — the `NotRunning` assertion is skipped where `OcuTalon.Production` runs (`$$$AssertSkipped`); the log and live-event counts stay, because Row 8/9 state that slot A runs no production.
    - `[medium]` `[patch]` The row 5 source scan had no negative control, no scanned-file floor and a `//`-only comment rule — `test-install-start.sh` now runs the scan on a bad and a clean synthetic class, fails on zero classes, and matches table names; mutation recorded.
    - `[medium]` `[patch]` Row 20 never confirms the kill restarted the container — `docker kill` must succeed and `started_at` must change; mutation (kill replaced by `true`) red.
    - `[medium]` `[patch]` The `Start()` branches for another production had no test — `test-production.sh` stops `OcuTalon.Production`, starts a `ZzOther.Production`, and expects the step to fail naming it with the fixture still running; mutation (fall through to `RestartProduction`) red.
    - `[low]` `[patch]` `Submit` throws `<UNDEFINED>` when the origin is left out — `$Get` guards on `command` and `origin`; `TestOmittedArguments` added; mutation red.
    - `[low]` `[reject]` The step's "runs" for adapterless services is only "enabled" — this is the Tasks' own definition and a Rule 22 ruling (the live row 14 calls `CreateBusinessService` for each); putting it in the step would add a behaviour no AC asks for.
    - `[low]` `[patch]` The step's class comment disagrees with the code on Suspended and Troubled under another name — comment rewritten to list the cases.
    - `[low]` `[patch]` Stale bookkeeping in `## Auto Run Result` — rewritten at finalize.
  - Edge Case Hunter
    - `[medium]` `[patch]` carried: the kill's failure is discarded (`test-production-restart.sh:96`) — same fix as the row 20 entry above.
    - `[medium]` `[patch]` carried: `find` returns no class and the scan passes — same fix as the scan entry above.
    - `[low]` `[patch]` The scan misses the underscore table form `OcuTalon_Pkg` — the pattern is `OcuTalon[._][A-Za-z]+`, with `OcuTalon_Bridge` and `OcuTalon_BridgeExample` allowed; the control flags it.
    - `[low]` `[patch]` carried: `Submit` with the origin or the command left out throws — same fix as above.
    - `[low]` `[reject]` A job `Alive` with status `registered` can precede a failing `OnInit` — real in principle (`Ens.Job` registers before `%New`), but Task 0 saw every pooled job `dequeuing` 0.25 s after the start and row 21 fails reliably; excluding `registered` would fail on `Ens.MonitorService`, which stays `registered`; a second confirming poll adds a branch for no demonstrated case.
    - `[low]` `[reject]` `UnresolvedRunners` compares the class name exactly — the Tasks say "the enabled `AgentRunner` items", and no subclass exists.
    - `[low]` `[patch]` carried: the `NotRunning` assertion fails where the production runs — same guard as above.
    - `[false]` `[reject]` The snake_case pattern `1.L` accepts any letters — `L` is lowercase only; measured on slot A: `set_reminder` matches, `setReminder` and `Set_reminder` do not.
    - `[low]` `[reject]` Process, body and stream classes can set storage locations outside the private prefix — the same exemption already holds for the message classes (Story 0.4), no class does it, and `TestEveryStorageGlobalIsPrivate` passes on the real tree.
    - `[low]` `[patch]` The `GeneratedBy` filter in `TestSqlNames` is wider than the compiler's process tables — `Test.Data.Tables` now asserts that each of the seven business processes is among the checked classes; mutation red.
    - `[low]` `[reject]` `ClassFor` returns the base when the setting is absent from the item — row 2 requires exactly that for `ClassificationClass`, and a removed `HostSinkClass` or `ReplyFilterClass` setting turns `TestDefinition` (row 1) red; a configured class that is wrong is an error.
    - `[false]` `[reject]` A Suspended production of another name fails the step instead of starting — `Ens.Director.StartProduction` itself refuses that case (`EnsErrProductionSuspendedMismatch`); a Stopped state reports an empty name (measured on slot A), so it is not affected; the step names the production.
    - `[low]` `[reject]` `NotRunning` skips pool-0 items — the Tasks' definition; see the Blind Hunter entry above.
  - Verification Gap
    - `[medium]` `[patch]` The step's other-production outcomes have no test — see the `test-production.sh` entry above; the Troubled and Suspended names are refused by the same `Other` call, and a Suspended mismatch is IRIS's own refusal too.
    - `[medium]` `[patch]` The stub adapter's "no AI Hub call at start" has no pin — `Test.Bridge.Api.TestStubAdapter` asserts the adapter extends AI Hub's adapter and owns `OnInit`; mutation (override removed) red.
    - `[low]` `[patch]` The empty and missing class guards of `Accessor.Check` and `ResolveModel` are untested — both cases added to the probe and to `TestRunnerModels` (a fixture runner whose agent class does not exist); two mutations red.
    - `[low]` `[patch]` `Context.Begin` replacing a context and resetting the taint is untested — a second `Begin` added to `TestContext`; mutation red.
    - `[medium]` `[patch]` The AC5 boundary scan has no negative control — same fix as the scan entry above.
    - `[low]` `[reject]` Row 20 does not assert that the Troubled branch ran — the AC4 mutation (Troubled branch replaced by an error) is red and Task 0 measured the kill leaving the production Troubled; a build that stopped leaving it Troubled would make the branch unexercised, and the spec already says how that reads; reopen if the Task 0 measurement changes on a new build.
    - `[low]` `[reject]` AC3 rows 14, 15, 16 and 18 have no mutation line of their own — Rule 19 asks for one demonstrated mutation per AC, and AC3 has three plus the new one; `check_items_run` expects exact counts (25, 10, 3) and cannot pass on an empty scan.
    - `[low]` `[reject]` AC6 / row 23 is a one-off manual export — the contract makes it a manual `(once)` Verification line; a standing export check belongs to Story 0.7's CI.
    - `[medium]` `[patch]` The `{{` assertion on the agents' INSTRUCTIONS cannot fail today (empty text) — the detector is a helper that the test first shows to flag a text with `{{`; mutation red.
    - `[low]` `[reject]` "BridgeSink writes no live event" cannot observe a sink that publishes valid input — the class has no members of its own, `Publish` refuses payloads that are not its own classes, and Story 2.6, which makes the sink publish, owns the assertion that rows appear.
    - `[low]` `[patch]` Tests that rely on a stopped namespace — the `NotRunning` assertion is guarded (above); the remaining count comparisons are stated preconditions of rows 8 and 9 (slot A runs no production).
    - `[low]` `[patch]` `test-storage.sh` has no sample for the BPL root and for a subclass of a process — `no-storage-bpl` and `no-storage-subprocess` added, and `SubProc` sits in the good tree; two mutations red.
    - `[low]` `[patch]` carried: `TestSqlNames` does not show that the seven processes are checked — same assertion as above.
    - `[false]` `[reject]` `test-bundle-folder.sh` runs the after-start script and may break with the production — run once on the patched tree: exit 0, no failing check.
    - `[low]` `[patch]` The accepted-origins loop passes for `web_admin` even if `Submit` sets nothing — the loop now starts each command with an origin different from the one it submits; mutation red.
    - `[low]` `[reject]` `UnresolvedRunners` of an unknown production returns "" — the step passes its own constant, and `StartProduction` fails first for a production that does not exist.
  - Intent Alignment
    - `[low]` `[reject]` D1: row 23 has no repeatable artifact — the contract makes it a manual `(once)` run; re-run and recorded in the review pass results (188 classes, 0 differences).
    - `[low]` `[reject]` D2: row 3 (`%New("")`), row 16 (`Conversation`) and AC5 (load-only pin) differ from the contract's words — each is a measured Rule 22 ruling in the Change Log; the matrix wording is for the lead to correct.
    - `[low]` `[reject]` D3: adapterless services are checked only in the live test — the Tasks' definition of `NotRunning()`; see above.
    - `[low]` `[reject]` D4: a bad origin inside a context is not looked at — the Design Notes' Submit step 2 says so, and `TestOrigin` pins it.
    - `[low]` `[reject]` D5: nothing flags a process that sets `DEFAULTGLOBAL` — the Tasks ask only for the exemption from `registry-param`; `registry-row` already requires a registry row for any class that sets one.
    - `[low]` `[reject]` D6: `TelegramIn` has no `STUB` — the Tasks use Story 0.4's class as it is, and the oracle says `stub` 0.
    - `[low]` `[reject]` D7: "a job never dies on a request" is sampled for four targets — the Matrix row 16 names exactly those four; row 3 covers the status of every stub class.
    - `[low]` `[reject]` D8: the item and signature tables are test-held copies — the Tasks prescribe the oracle as a copy of the Design Notes table.
    - `[low]` `[reject]` D9: the constants are declared but not consumed — the story has no consumer of the mock keys, tool names or prefix; 0.7 and Epic 1 are named in Consumed-by.
    - `[low]` `[reject]` D10: extras beyond the contract (the `GeneratedBy` filter, `Context` validation, other-name refusals) — each is a logged ruling; the filter is now pinned (above), the refusals are now tested.
    - `[low]` `[patch]` carried: D11, slot A tests depend on slot A state — same guard as above.

## Design Notes

**ADs:**
- AD-1: `Commands.Submit` and `Origin`.
- AD-2: the bridge's boundary.
- AD-3: not autostart.
- AD-5: structure only in the production class; storage blocks.
- AD-6: runners, adapter, Context, building on first use.
- AD-7: the model; `MODEL` and the runner's `Model`.
- AD-8: `Timeouts.Derive`.
- AD-11: `Approval`.
- AD-19: `ConfigStore.Merge`; settings homes.
- AD-20: `Budget.State`; `budget.capped`; the compaction prompt.
- AD-22: `MOCKKEY`; tool names; `EvalIn`.
- AD-23: the `Production` step.
- AD-28: `ReplyGuard`.
- AD-29: regions; Epic 0's contract list; the release-cut rule.
- AD-31: extension bases, the accessor, payloads.
- AD-33: one owner per item.
- Conventions: item names, messages, `DEFAULTGLOBAL`.

No AC contradicts an AD; no NFR tripwire.

**The production** (in this order in the XData). The kinds are:
- **svc0:** an adapterless service, pool 0, no job;
- **svc:** a service with an adapter, pool 1;
- **proc:** a business process, pool 1, with a storage block;
- **op:** a business operation, pool 1;
- **rt:** a router, `EnsLib.MsgRouter.RoutingEngine`, pool 1.

Every item is enabled unless the table says off.

| Lane | Item | Class | Kind | Notes |
|---|---|---|---|---|
| A | `TelegramIn` | `OcuTalon.Channel.Telegram.In` (0.4) | svc | off |
| A | `TelegramOut` | `OcuTalon.Channel.Telegram.Out` | op | off |
| A | `Decide` | `OcuTalon.Bridge.Process.Decide` | proc | `HostSinkClass` = `OcuTalon.Core.BridgeSink`, `ReplyFilterClass` = `OcuTalon.Checks.ReplyGuard` |
| A | `ApprovalHold` | `OcuTalon.Bridge.Process.ApprovalHold` | proc | |
| A | `ApprovalStartIn` | `OcuTalon.Bridge.Service.ApprovalStart` | svc0 | |
| A | `TriageAgent`, `DiagnosisAgent`, `ChatAgent` | `OcuTalon.Bridge.Operation.AgentRunner` | op | Adapter `AgentClass` = `OcuTalon.Agent.Triage`, `.Diagnosis`, `.Chat` |
| A | `AgentSteps` | `OcuTalon.Bridge.Operation.Steps` | op | |
| A | `OcuTalonApprovals` | `EnsLib.Workflow.Operation` | op | not a stub |
| A | `FailurePoller` | `OcuTalon.Watch.FailurePoller` | svc0 | |
| A | `IncidentManager` | `OcuTalon.Watch.IncidentManager` | proc | |
| A | `WatchOps` | `OcuTalon.Watch.Ops` | op | |
| A | `EvalIn` | `OcuTalon.Eval.In` | svc0 | off; a System Default Setting switches it |
| A | `EvalSink` | `OcuTalon.Eval.Sink` | op | |
| A | `FixExecutor` | `OcuTalon.Fix.Executor` | op | |
| A | `Checks` | `OcuTalon.Checks.Process` | proc | |
| A | `DigestStore` | `OcuTalon.Digest.Store` | op | |
| B | `WebChatIn`, `WebChatOut` | `OcuTalon.Channel.WebChat.In`, `.Out` | svc0, op | |
| B | `SimMailboxIn`, `SimMailboxOut`, `SimPhoneOut` | `OcuTalon.Channel.SimMailbox.In`, `.Out`; `OcuTalon.Channel.SimPhone.Out` | svc0, op, op | |
| B | `AnswersIn`, `CommandsIn`, `NoticesIn`, `StatusMonitor` | `OcuTalon.Core.AnswersIn`, `.CommandsIn`, `.NoticesIn`, `.StatusMonitor` | svc0 | |
| B | `Conversation`, `Intake` | `OcuTalon.Core.Conversation`, `.Intake` | proc | |
| B | `OutcomeRouter`, `Notify` | `EnsLib.MsgRouter.RoutingEngine` | rt | `BusinessRuleName` = `OcuTalon.Core.Rule.Outcome`, `.Notify` |
| B | `SessionOps`, `SettingsOps` | `OcuTalon.Core.SessionOps`, `.SettingsOps` | op | |
| B | `HeartbeatIn` | `OcuTalon.Schedule.HeartbeatIn` | svc0 | |
| B | `ReminderOps`, `ReminderTimer` | `OcuTalon.Schedule.ReminderOps`, `.ReminderTimer` | op, proc | |
| B | `BreakFeedIn`, `PartnerTrigger` | `OcuTalon.Demo.BreakFeedIn`, `.PartnerTrigger` | svc0, op | |

That is 38 items: 18 in Lane A and 20 in Lane B. 25 have a pool, 10 are enabled adapterless services, and 3 are off. Step 2's `Digest` and step 4's `EmailIn`, `EmailOut` and `WebhookIn` are not release 1, and are left out.

Golden shapes:

```xml
<Production Name="OcuTalon.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>2</ActorPoolSize>
  <!-- lane A: begin -->
  <Item Name="TriageAgent" ClassName="OcuTalon.Bridge.Operation.AgentRunner" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="AgentClass">OcuTalon.Agent.Triage</Setting>
  </Item>
  <!-- lane A: end -->
  <!-- lane B: begin --> ... <!-- lane B: end -->
</Production>
```

```xml
<ruleDefinition alias="" context="EnsLib.MsgRouter.RoutingEngine" production="OcuTalon.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
</ruleSet>
</ruleDefinition>
```

**Cross-lane signatures** (all class methods; the lane and the story that builds each are in parentheses):

| Class | Signature | Stub body |
|---|---|---|
| `OcuTalon.Bridge.Approval` (A, 3.4–3.6, 7.3) | `Raise(request As OcuTalon.Bridge.Data.ApprovalRequest, Output ref As %String) As %Status`; `Expire(ref) As %Status`; `Cancel(ref) As %Status`; `StartExecution(ref) As %Status`; `FinishExecution(ref, result) As %Status` | error |
| `OcuTalon.Bridge.Approval` | `Answer(ref, action, channel, irisUser, sessionRef, Output winner As %DynamicObject) As %String`, whose result is one of `done`, `already_answered`, `expired`, `not_found` and `not_allowed` | `not_found`, with `winner` `{}` |
| `OcuTalon.Agent.Input` (A, 1.3) | `Render(item As OcuTalon.Msg.Item) As %String` | `""` |
| `OcuTalon.Checks.Render` (A, 5.7) | `Render(results As %DynamicArray, Output rows As %DynamicArray) As %String`: returns the catalog key | `""`, with `rows` `[]` |
| `OcuTalon.Bridge.Context` (A, 1.2) | `Begin(request As OcuTalon.Bridge.Msg.Request, superSession As %String = "") As %Status`; `End()`; `Active() As %Boolean`; `Current() As OcuTalon.Bridge.Context`; `Put(name As %String, value As %String) As %Status` | implemented |
| `OcuTalon.Bridge.Budget` (A, 1.4) | `State() As %DynamicObject` (`spent`, `cap`, `capped`, `resetsAt`) | 0, 0, false, `""` |
| `OcuTalon.Bridge.Keys` (A, 1.6) | `Status(agent As %String) As %Boolean` (1 when a key is present) | 0 |
| `OcuTalon.Bridge.Timeouts` (A, 1.7) | `Derive(timer As %Integer) As %DynamicObject` | `{}` |
| `OcuTalon.Bridge.ConfigStore` (A, 1.1) | `Merge(entry As %String, fields As %DynamicObject) As %Status` | error |
| `OcuTalon.Data.Session` (B, 2.2) | `Recipients(ownerRef As %String, incidentRef As %String = "") As %List` of `SessionRef`s | `""` |
| `OcuTalon.Data.Ownership` (B, 2.2 and 2.6) | `TurnCost(turnRef) As %DynamicObject`; `RunCost(sessionRef, since) As %DynamicObject` | `{}` |
| `OcuTalon.Core.Commands` (B) | `Submit(command As OcuTalon.Msg.Command, origin As %String, Output result As OcuTalon.Msg.CommandResult) As %Status` | implemented |
| `OcuTalon.Bridge.Ext.Accessor` (A) | `ClassFor(setting, production = "", item = "Decide", Output sc As %Status) As %String`; `Check(setting, class) As %Status` | implemented |
| `OcuTalon.Bridge.Ext.HostSink` (A) | `OnEvent(type, ownerRef, payload As %DynamicObject) As %Status`; `RefPayload(ref)`; `TurnStepPayload(decisionRef, label)`; `BudgetCappedPayload(day)`, each `As %DynamicObject` | OK; the builders are implemented |
| `OcuTalon.Bridge.Ext.ReplyFilter`, `.Classification` (A) | `Filter(text As %String) As %String`; `Classify(tool As %String, arguments As %DynamicObject = "") As %String` | text; `""` |
| `OcuTalon.Bridge.Operation.AgentRunner` (A) | `ResolveModel(item As %String, production As %String = "") As %String` | implemented |
| `OcuTalon.Bridge.Compaction` (A, 1.9) | `Prompt() As %String` | implemented |

The `Signatures` rows write an Output parameter with its `*` (for example `request,*ref`), as the FormalSpec does.

**HostSink.** Its parameters are:
- `TURNSTEP` "turn.step";
- `DECISIONRECORDED` "decision.recorded";
- `APPROVALRAISED`, `APPROVALANSWERED`, `APPROVALEXPIRED`, `APPROVALCANCELLED` and `APPROVALRESULT` ("approval.raised" and so on);
- `BUDGETCAPPED` "budget.capped";
- `EVENTS`, the 8 values in that order.

The payloads (AD-31 L804):
- `decision.*` and `approval.*`: `{"ref": <public Ref>}`;
- `turn.step`: `{"decisionRef", "label"}`, with the session as `ownerRef`;
- `budget.capped`: `{"day": "YYYY-MM-DD"}` (the instance-zone date), with `ownerRef` `instance`.

**Submit** (AD-1):
1. Refuse a non-command, with an error status.
2. The effective origin is `tool` when `##class(OcuTalon.Bridge.Context).Active()`. Otherwise it is the `origin` argument, which must be in `Msg.Enum.ORIGIN`; any other value is refused naming it, and nothing is sent.
3. Set `command.Origin` to the effective origin, overwriting the payload's value.
4. Call `Ens.Director.CreateBusinessService("CommandsIn", .service)`, then `service.ProcessInput(command, .result)`, and return that status.

2.3 adds joining the turn's thread and routing by verb.

**Tool names** (`OcuTalon.Tools.Names`, release 1; `RELEASE1` lists the values comma-separated):
- `SETREMINDER` set_reminder, `LISTREMINDERS` list_reminders, `CANCELREMINDER` cancel_reminder;
- `STARTWATCH` start_watch, `STOPWATCH` stop_watch, `LISTPRODUCTIONS` list_productions;
- `DISMISSINCIDENT` dismiss_incident, `CHECKSTATUS` check_status;
- `READFAILEDMESSAGES` read_failed_messages, `READEVENTLOG` read_event_log, `READITEMSETTINGS` read_item_settings.

**The compaction prompt** (`XData Prompt`, ASCII). This is S18's confirmed schema-conformant text. The source is `../spikes/batch2/s18/src/OcuSpike/S18/Probe.cls`, the v2 variant without the probe marker:

```text
OCUTALON-COMPACTION-V1 You are a compression engine for an IRIS operations assistant's conversation.
Given the full transcript, including tool calls and tool outputs, return ONLY one valid JSON object, with no code fences and exactly these keys:
"user_goals": a string with the user's active goals;
"constraints": an array of strings;
"decisions": an array of strings: answers and decisions already given;
"facts_learned": an array of strings, one per tool result, each naming the tool, its tool call id, its arguments and every value it returned, e.g. "GetX (toolu_123) itemName=A returned count 5, id 77";
"tool_actions": an array of objects {"tool": the tool name (required), "input_summary": string, "result_summary": string, "state_change": string}, one per tool call;
"open_questions": an array of strings;
"next_steps": an array of strings.
Never drop a tool result: copy every number, name, id, date and error text a tool returned verbatim.
```

**Rule 22 rulings** (each as: Rule 22 ruling: question → choice (rejected: …)):
- Rule 22 ruling: what is a stub's answer, and how does Story 11.5 detect one? → every unbuilt item class declares its one handler (`OnProcessInput`, `OnRequest` or `OnMessage`) as `Quit $$$ERROR($$$NotImplemented)` (measured: "ERROR #5003: Not implemented"), and carries `Parameter STUB = 1`. 11.5 refuses an enabled item whose class, or whose router's rule class, has `STUB`. The owner deletes both lines when it builds the item. (rejected: a shared stub base, because the bridge can't share an OcuTalon class (AD-2) and an owner would have to change the superclass; relying on the inherited defaults, because the process default logs through `$$$EnsError` and the operation default answers "not handled"; answering OK.)
- Rule 22 ruling: are the two routers' classes `OcuTalon.Core.Rule.Outcome` and `.Notify`, or are those their rule classes? → the items are `EnsLib.MsgRouter.RoutingEngine` with `BusinessRuleName` set to the rule classes the AC names. A stub rule has an empty rule set, so it accepts and routes nothing; its stub-ness is `STUB` on the rule class. (rejected: a routing-engine subclass named after the rule, since the AC calls them "routing-rule classes"; a rule that targets a missing item, which would be an error on purpose.)
- Rule 22 ruling: how does `EvalIn` follow `OCUTALON_EVAL`? → the `Production` step writes a System Default Setting row `Enabled` for `EvalIn` at every start: 1 when the variable is `"1"`, else 0. A System Default Setting overrides the definition's `Enabled` (Item.cls L43–47). Story 12.1's Telegram switch can use the same mechanism. (rejected: `EnableConfigItem`, which saves the stored definition, so the next compile overwrites it, and a class save drops the lane markers; editing the XData at start.)
- Rule 22 ruling: which production states does the `Production` step handle? → this production running → `RestartProduction` (AD-23: "restart every item"); another production running → fail naming it; Troubled → `RecoverProduction`, then start; Stopped or Suspended → start. Then it waits at most 60 s. (rejected: `UpdateProduction`, which restarts only changed items; stopping another production, which Rule 22.4 forbids.)
- Rule 22 ruling: what does "every enabled item runs" mean? → an enabled item with a pool has an `Alive` job that is not in error; an adapterless service, which never has a job, runs when it is enabled in the running production. Task 0 confirms the statuses. (rejected: the host-monitor status, which lists only hosts that have started.)
- Rule 22 ruling: what does "every runner resolves a model" read? → the adapter's `Model` setting (item, then System Default Setting), else the `AgentClass`'s `MODEL`. The agent stubs carry `MODEL` `claude-haiku-5-5` now, so the check passes before 1.1 seeds the setting; 1.1 adds seeding and its `Test.Agent` check on the same method. (rejected: leaving the check to 1.1, since AD-23 defines the step with it.)
- Rule 22 ruling: how do the runners start with no key? → the runner stub uses the final adapter class `OcuTalon.Bridge.Adapter.Agent`, with `OnInit` returning OK, so the settings already sit where 1.1 and 1.2 expect them (`Target="Adapter"`) and nothing calls AI Hub at start. (rejected: no adapter with host settings, which 1.2 would have to move; the stock adapter, which builds the agent in `OnInit` (OutboundAdapter.cls L129–144; S4: build on first use).)
- Rule 22 ruling: what are the agents' `MOCKKEY` values? → `triage`, `diagnosis` and `chat`; INSTRUCTIONS and TOOLSETS stay 1.1's. (rejected: the class names, which a scenario file would have to repeat in full.)
- Rule 22 ruling: how are the built-in tool names spelled, and which are fixed? → snake_case, matching the two names the docs spell (`check_status`, `call_mcp_tool`), for release-1 tools only; step 3 and step 4 tools are fixed by their own stories (AD-29: Epic 0 freezes no guessed contract for later steps). (rejected: camelCase; fixing step 3 and 4 names now.)
- Rule 22 ruling: where does the compaction prompt live? → in the bridge, `OcuTalon.Bridge.Compaction`, because the runner does compaction (AD-20). (rejected: `OcuTalon.Agent`, which the standalone bridge doesn't have.)
- Rule 22 ruling: what is the extension accessor called, and what does it do with a bad class? → `OcuTalon.Bridge.Ext.Accessor.ClassFor`. It reads the production definition, so it works in any job, and needs no running production when the production is named. A class that doesn't extend its base gives `""` and an error, never the do-nothing base, so a misconfigured guard can't silently disable AD-28. (rejected: silently falling back to the base class.)
- Rule 22 ruling: how is `Context` held? → in a process-private global, because AI Hub's callbacks might `New` local variables, and the context dies with the process. `Begin`, `End`, `Active`, `Current` and `Put` are implemented, because `Submit` must really detect a context; everything else in it is a plain field. (rejected: a `%`-variable holding the object.)
- Rule 22 ruling: what does `Submit` trust? → the caller's origin, which `Submit` validates against the enumeration and overrides to `tool` under a context; it doesn't re-check roles, because the admin-checked endpoints and 2.3's `CommandsIn` own those checks. VETO WINDOW. (rejected: `Submit` reading `$Roles` for `web_admin`, which is unspecified and could refuse legitimate calls.)
- Rule 22 ruling: what are the cross-lane API signatures? → the table above, from the AD texts; `Answer`'s argument order is AD-11's, and return shapes the docs leave open use `%DynamicObject` with camelCase keys, or `%List`. (rejected: deferring the shapes to the owners, which would leave callers nothing to compile against.)
- Rule 22 ruling: what pool sizes do the items get? → 0 for adapterless services, 1 for everything else. The future pollers (`HeartbeatIn`, `StatusMonitor`, `FailurePoller`) are adapterless stubs; their owners add the adapter and the pool in their own region. (rejected: stub polling adapters, which would wake jobs that do nothing.)
- Rule 22 ruling: where do the tests go? → one test class per area and lane, as listed; the production's own test is in `Test.Install`, because the step and the definition are Lane A's core. (rejected: one shared test class, which both lanes would edit.)

**Integration ACs (Rule 1):**
- The after-start registry (consumer) runs the `Production` step, and the production runs (rows 13–14).
- A script acting as the web layer and as a tool (consumer of `Submit`) reaches `CommandsIn` (row 17).
- A job outside `Decide` (consumer of the accessor) reads the extension classes (rows 2 and 15).
- The step (consumer of `ResolveModel` and of the agents' `MODEL`) resolves every runner (rows 4 and 13).
- A created service (consumer of the stubs) gets "not implemented" from three kinds of item, without killing their jobs (row 16).
- The stub APIs and `BridgeSink` have no consumer in this story. Their first consumers are 1.2, 1.3, 2.2, 2.3 and 2.6 (below).

**Consumes:**
- 0.2: the registry, `lib-live.sh`, the after-start script.
- 0.4:
  - `Msg.Command` and its verbs, `CommandResult`, `Msg.Enum.ORIGIN`;
  - `Bridge.Msg.Request`, `Bridge.Data.ApprovalRequest`, `Data.Session`;
  - `Channel.Telegram.In`;
  - the `Data.Delivery` stub pattern, and `Test.Contract.Ac`.
- 0.5: `Live.Event` (row 6's no-row check).

**Consumed-by:**
- 0.7:
  - the CI lane-region check over this XData (lane by item name for the `EnsLib` classes);
  - the storage check;
  - the `OCUTALON_EVAL` pass-through;
  - the mock, which keys on `MOCKKEY`, the tool names and the prefix.
- 0.8, 0.9 (DW-12, the production jobs) and 0.10.
- Epic 1:
  - 1.1: agents, `ConfigStore.Merge`, `Model` seeding;
  - 1.2: the adapter and runner;
  - 1.3: `Decide`, `Agent.Input`, the reply filter;
  - 1.4: `Budget.State`, `budget.capped`;
  - 1.5: `AgentSteps`;
  - 1.6: `Keys.Status`;
  - 1.7: `Timeouts.Derive`;
  - 1.9: `Compaction`;
  - 1.10: the tools, `Submit`.
- Epic 2:
  - 2.2: `Recipients`, `Ownership`;
  - 2.3: `CommandsIn`, `Submit`;
  - 2.4–2.10: the Lane B items;
  - 2.6: `BridgeSink`, `TurnCost`, `RunCost`.
- Epic 3: `Approval`, `ApprovalHold`, `ApprovalStartIn`, `OcuTalonApprovals` (3.4–3.6).
- 4.1: `SettingsOps`.
- Epic 5: the watch items and `Checks`; 5.7: `ReplyGuard`, `Checks.Render`.
- Epic 7: `FixExecutor`.
- Epic 9: `EvalIn`, `EvalSink`.
- 11.5: `STUB`.
- 12.1: the Telegram items, by the same System Default Setting mechanism.
- 15.2: IPM autostart.

**Reuse (Rule 2):**
- API stubs follow `Data.Delivery`'s pattern.
- The signature pin extends `Test.Contract.Ac`.
- `test-storage.sh` is extended, not copied.
- The live scripts use `lib-live.sh`. `item_jobs` is local, because no sibling reads jobs.
- The item stubs each carry their one-line handler; the stub-answer ruling gives the reason for the copy.
- `Accessor`, `Context`, `Submit` and the step's helpers have no sibling.

**Ledger inbox:** DW-13 is addressed in row 12, the `test-storage.sh` task and AC2. No entry is declined.

**VETO WINDOW items (Rule 22.3), for the lead's FYI:**
- `Submit` trusts the caller's origin outside a bridge context (security posture).
- The `Production` step recovers a Troubled production, which keeps its queued messages as Suspended (data handling).

**Spine updates for the lead (Rule 20):**
- AD-29: the `STUB` marker that 11.5 reads.
- AD-29: the routers are `EnsLib.MsgRouter.RoutingEngine` with `BusinessRuleName`.
- AD-29: pool sizes 0 and 1.
- AD-23 (the `Production` step):
  - the states it handles;
  - the "runs" predicate;
  - `EvalIn` through a System Default Setting (AD-22 too);
  - model resolution.
- AD-6: the stub adapter that starts with no AI Hub call.
- AD-6: `Context` held in `^||OcuTalonBP.Context`.
- AD-31: `OcuTalon.Bridge.Ext.Accessor.ClassFor`, which never falls back silently.
- AD-31: the payload keys and the event-type parameters.
- AD-22: the `MOCKKEY` values, the 11 tool names in `OcuTalon.Tools.Names`, and `OcuTalon.Bridge.Compaction`.
- AD-1: `Submit`'s signature and its origin rule.
- AD-29: the API signature table above.

**Size, and where to split it (for the lead):** the story has several goals and is oversized. Most of it is 5–20-line stub classes and one live harness. The clean line:
- **0.6:** the production and every item stub, the `Production` step, the extension bases, the accessor, the payloads, the agents with `MOCKKEY`, and DW-13 (rows 1–6, 11 (agents only), 12–16 and 18–23).
- **0.11:** the cross-lane API signatures, `Context`, `Submit`, `Tools.Names` and `Compaction` (rows 7–10, 11 (tools and prompt) and 17). It follows 0.6, because `Submit` needs `CommandsIn`.

## Verification

Runtime targets:
- Slot A: `ocutalon-slot-a`, MCP profile `ocutalon-slot-a`, namespace `OCUTALON`.
- Throwaway projects: `ocutalon-t06-*` and `ocutalon-t06r-*`, through `lib-live.sh`, one at a time, torn down by their own trap.

Every command below finishes in one foreground call (`timeout: 600000` where noted).

**Commands:**
- `(loop)` `iris_server_info` (`server: ocutalon-slot-a`). Expected: build 154.
- `(loop)` `iris_doc_load` with `server: ocutalon-slot-a`, `namespace: OCUTALON`, `compile: true`, `flags: "ck"`, as two calls: `src/bridge/cls/**/*.cls`, then `src/ocutalon/cls/**/*.cls`. Expected: 0 errors.
- `(loop)` `iris_execute_tests`, one class per call, each waiting for the last:
  - new: `OcuTalon.Test.Install.Production`, `.Test.Bridge.Ext`, `.Test.Bridge.Api`, `.Test.Agent.Constants`, `.Test.Core.Commands`;
  - updated or kept green: `.Test.Contract.Ac`, `.Test.Contract.Checker`, `.Test.Install.Registry`, `.Test.Install.PrivateData`, `.Test.Data.Tables`, `.Test.Msg.Contracts`, `.Test.Bridge.Contracts`, `.Test.Live.Payloads`, `.Test.Data.Session`.
  
  Expected: 0 failed. No `Zz` fixture, `^OcuTalonTest("BridgeExt")` child entry, Context global or extra System Default Setting row is left behind; the `EvalIn` row is as found.
- `(loop)` One call each: `bash docker/tests/test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-build-inputs.sh`. Expected: exit 0.
- `(loop)` `bash docker/tests/test-production.sh` (`timeout: 600000`). Expected: exit 0, and no `ocutalon-t06-*` project left.
- `(loop)` `bash docker/tests/test-production-restart.sh` (`timeout: 600000`). Expected: exit 0, and no `ocutalon-t06r-*` project left.
- `(loop)` `bash docker/tests/test-install-start.sh` (`timeout: 600000`). Expected: exit 0 (row 5 included).
- `(once)` `bash docker/tests/test-install-upgrade.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` `bash docker/tests/test-sign-in.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` `bash docker/tests/test-audit.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` `bash docker/tests/test-bundle-folder.sh` (`timeout: 600000`). Expected: exit 0. It runs the after-start script with the production, and restarts the container.
- `(once)` `IRIS_IMAGE=iris-community:2026.3.0AI.154.0 bash docker/tests/test-production.sh` (`timeout: 600000`). Expected: exit 0.
- `(once)` On slot A, load and compile the trees, then export them (`iris_doc_export`, prefix `OcuTalon`) into a scratch folder. Expected: every file equals the tree byte for byte, the seven process storage blocks included.

**Shared surfaces:**
- the production-item list: `OcuTalon.Production`'s XData, the ownership table, and `Test.Install.Production`'s `Items` oracle. 0.7's lane check reads the same list;
- the STEP list: `Registry.Order()` and `expected_run` are unchanged, but the `Production` step now starts 25 jobs in every throwaway the live tests start;
- the storage roots, and the samples and rules of `test-storage.sh`;
- `Test.Contract.Ac`'s `Signatures` and its count floor;
- the `Ens_Config` definition rows and rule metadata of `OcuTalon.Production` on slot A (written by compiling);
- the System Default Setting row (`OcuTalon.Production`, `EvalIn`, `*`, `Enabled`): restored on slot A, and written at every throwaway start;
- `^Ens.AutoStart` (read only);
- the counters `^OcuTalonTest("Production","n")`, `("BridgeExt","n")` and `("Commands","n")`;
- the throwaway event log.

Every test added or changed passes on a fresh environment, in either order.

**Mutations to demonstrate** (Rule 19: apply, see red, revert, `git status --short` unchanged):
- AC1:
  - `WebChatIn` moved into lane A's region → row 1 red;
  - `ClassFor` ignoring the item's setting → row 2 red;
  - `SessionOps.OnMessage` answering OK → row 3 red;
  - `MODEL` removed from `Agent.Triage` → row 4 red;
  - `EvalEnabled` accepting `"true"` → row 5 red;
  - the `turn.step` builder writing `decisionref` → row 6 red;
  - `Context.Active` ignoring the stored context → row 7 red;
  - `Submit` not overriding the origin under a context → row 8 red;
  - `Budget.State` without `resetsAt` → row 9 red;
  - `Answer` with `channel` and `action` swapped → row 10 red;
  - Chat's `MOCKKEY` set to `triage` → row 11 red.
- AC2: `Ens.BusinessProcess` dropped from the roots → `rule storage` FAIL (sample `no-storage-process`).
- AC3:
  - `Start` without the wait loop, while row 21's fixture is loaded → row 21 red;
  - `Start` that never calls `StartProduction` → rows 13–14 red;
  - `Submit` targeting `CommandIn` → row 17 red.
- AC4:
  - `SetEval` skipped → row 19 red;
  - the Troubled branch removed → row 20 red. This holds when Task 0 finds the production Troubled after the kill. If Task 0 finds that IRIS's own start leaves it Stopped, row 20 still pins the outcome (ready, with the production running); the branch is then unexercised, and Verification records that, with Task 0's evidence, as `(inference)`.
- AC5: a method of `Bridge.Process.Decide` that calls `##class(OcuTalon.Core.BridgeSink).OnEvent(...)` → `test-install-start.sh` row 5 red, because the bridge no longer loads alone.
- AC6: one slot removed by hand from `Decide`'s storage block → the export differs.

### Task 0 results

Measured October 19 on one throwaway built from the tree (Health image, no key; project `ocutalon-t06x-*`, torn down), and on slot A where noted.

- **`Ens.Job:Enumerate` right after `StartProduction`** (30 rows): every process (`Decide`, `Conversation`, `Intake`, `ApprovalHold`, `IncidentManager`, `Checks`, `ReminderTimer`), operation, runner (`TriageAgent`, `DiagnosisAgent`, `ChatAgent` with the stub adapter), router (`OutcomeRouter`, `Notify`) and the Workflow operation (`OcuTalonApprovals`) shows `Mode` Background, `Status` `dequeuing`, `State` `Alive`. `Ens.MonitorService` shows `registered` and `Ens.ScheduleHandler` `running`. One item (`WebChatOut`) was still `starting` / `Starting` with no pid. No Alive row with a status other than these was seen. The predicate stays: an item with a pool runs when it has an Alive job whose status is not `error`, `halted` or `terminated` (a `Starting` row is not Alive).
- **Time to every item with a job:** `StartProduction` returned in 0.055 s; the second poll, 0.25 s later, found every pooled item with an Alive job. The step took 1.1 s as a whole. Measured on the Health image; the non-Health image was not timed (inference: the same, the `test-production.sh` run passed there).
- **`StartProduction` and the session device:** it writes two lines, `<time>:Ens.Director: Production 'OcuTalon.Production' starting...` and `... started.`. They land in the after-start transcript; `log_steps` keeps only `STEP` and `RESULT` lines, so they change nothing.
- **System Default Setting `Enabled` for `EvalIn`:** with the row at 1, the next start (`Start` on the running production) gave `$$$ConfigIsEnabled("EvalIn")` 1 and `CreateBusinessService("EvalIn")` succeeded; with the row at 0 it gave 0 and `<Ens>ErrConfigDisabled: Configuration item 'EvalIn' is disabled`. The row decides at the next start, as the contract says.
- **State the after-start step finds:** after `dc restart iris` (a graceful stop) it is Stopped: IRIS stops the production itself ("StopProduction initiated (Force flag: 1)") and does not start it, so the step starts it. After `docker kill -s KILL` and `dc start iris` it is Troubled (state 4, name `OcuTalon.Production`); IRIS's own start does not recover it, and the step recovered it and started it (`STEP Production OK`). The Troubled branch is exercised by row 20.
- **`OnProcessInput` error through `CreateBusinessService` and `ProcessInput`:** it writes one Error row for `CommandsIn` (`ERROR #5003: Not implemented`), and only when the text differs from the last one the service reported: three calls in two sessions wrote one row. Row 17 checks that the row exists.
- **Router with an empty rule set:** `SendRequestSync` to `OutcomeRouter` and to `Notify` answers OK with no response; the job id is unchanged.
- **Stubs over the production:** `SessionOps` and `TriageAgent` answer code 5003 with no response; `Conversation` answers `<Ens>ErrBPTerminated` whose text carries `ERROR #5003: Not implemented`; each job id is unchanged one second later.
- **For Story 1.2 (informational):** in a terminal session of the throwaway, with no key and no provider, `##class(OcuTalon.Agent.Triage).%New()` returns an object and `%Init()` returns OK.
- **Slot A:** compiling `OcuTalon.Production` leaves `^Ens.Configuration("csp","LastProduction")` at `OCUTALONPKG.FoundationProduction` and `^Ens.AutoStart` empty. A shadow instance's stub handler (six classes tried) adds no `Ens_Util.Log` row (6 rows of `OcuTalon.*` classes before and after).
- **An item that cannot start (row 21):** with a `WatchOps` whose `OnInit` fails, its job ends `last was: terminated` / `Dead`; `Start(15)` waits 15.2 s and fails with `these items do not run: WatchOps`; with the original compiled back, `Start(30)` takes 1.1 s and succeeds.

### Results (implement stage, October 19)

- Slot A: build 154 (`iris_server_info`, profile `ocutalon-slot-a`). Both trees load and compile with 0 errors (33 bridge classes, 155 classes of `ocutalon`).
- `%UnitTest`, one class per call, all 0 failed: `Test.Install.Production` 4, `Test.Bridge.Ext` 3, `Test.Bridge.Api` 3, `Test.Agent.Constants` 3, `Test.Core.Commands` 3, `Test.Contract.Ac` 6 (43 signature rows), and the kept classes `Test.Contract.Checker` 5, `Test.Install.Registry` 11, `Test.Install.PrivateData` 5, `Test.Data.Tables` 5 (after the `TestSqlNames` change), `Test.Msg.Contracts` 6, `Test.Bridge.Contracts` 5, `Test.Live.Payloads` 4, `Test.Data.Session` 3. Once, `Test.Contract.Checker` and `Test.Install.Production` were sent in the same message, which the run rules forbid; both were green and independent.
- Left behind on slot A: no `Zz` class or fixture production, no `^OcuTalonTest("BridgeExt",...)` child (only the counter), no extra System Default Setting row (`sdsrows` 0, no `EvalIn` row), `LastProduction` and `^Ens.AutoStart` as found.
- Shell: `test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-build-inputs.sh`, `test-lib-live.sh` exit 0.
- Live, each in its own throwaway, torn down by its trap (none left): `test-production.sh` 14 checks passed in 69 s (Health) and passed once on `iris-community:2026.3.0AI.154.0` (53 s); `test-production-restart.sh` 11 checks passed in 74 s; `test-install-start.sh` (row 5 included, `other-classes` 0) passed; `test-install-upgrade.sh`, `test-sign-in.sh` (29 specs) and `test-audit.sh` passed. The STEP list and `expected_run` are unchanged.
- Row 23: after the final load, the export of all 188 classes of `OcuTalon` into a scratch folder equals the tree byte for byte, the seven business-process stubs (`Decide`, `ApprovalHold`, `IncidentManager`, `Checks`, `Conversation`, `Intake`, `ReminderTimer`) included.

### Mutations (Rule 19), demonstrated October 19

Each was applied to the tree, loaded on slot A or built into a throwaway, run, and reverted from a saved copy; `git status --short` plus a hash of `src/` and `docker/` was identical before and after.

- mutation: `WebChatIn` moved into lane A's region -> `Test.Install.Production.TestDefinition` red ("WebChatIn sits in the region of lane B") (AC1, row 1).
- mutation: `ClassFor` returns the setting's base class instead of reading the item's setting -> `Test.Bridge.Ext.TestAccessorInAnotherJob` red (HostSinkClass, ReplyFilterClass, item and production cases) (row 2).
- mutation: `SessionOps.OnMessage` answers OK -> `TestStubsAnswer` red ("SessionOps answers code 5003") (row 3).
- mutation: `MODEL` removed from `Agent.Triage` -> `TestRunnerModels` red (row 4).
- mutation: `EvalEnabled` accepts "true" -> `TestStepHelpers` red ("'true' does not enable") (row 5).
- mutation: the `turn.step` builder writes `decisionref` -> `Test.Bridge.Ext.TestExtensionBases` red (row 6).
- mutation: `Context.Active` returns 0 -> `TestContext` red (row 7).
- mutation: `Submit` leaves the origin alone under a context -> `Test.Core.Commands.TestOrigin` red (row 8).
- mutation: `Budget.State` without `resetsAt` -> `Test.Bridge.Api.TestNeutralValues` red (row 9).
- mutation: `Answer` with `channel` and `action` swapped -> `Test.Contract.Ac.TestCrossLaneSignatures` red (row 10).
- mutation: Chat's `MOCKKEY` set to `triage` -> `Test.Agent.Constants.TestAgents` red (row 11).
- mutation: `Ens.BusinessProcess` dropped from the roots -> `test-storage.sh` `FAIL storage: the checker does not flag the sample no-storage-process`, exit 1 (AC2, row 12).
- mutation: `Start` without the wait loop and the check, with row 21's fixture loaded -> `test-production.sh` row 21 red (`start-fails` 0), the other rows green (AC3).
- mutation: `Start` that never calls `StartProduction` -> the first start ends `STEP Production FAILED ... is not running` and `test-production.sh` stops red at row 13 (AC3).
- mutation: `Submit` targeting `CommandIn` -> `test-production.sh` row 17 red (3 of 4 values) (AC3).
- mutation: `SetEval` not called -> `test-production-restart.sh` red at the first start and at both row 19 checks (AC4).
- mutation: the Troubled branch replaced by an error -> `test-production-restart.sh` row 20 red: the start after the kill ends `STEP Production FAILED ... Troubled production not handled`. The kill does leave the production Troubled (Task 0), so the branch is exercised (AC4).
- mutation: a `Decide` method that calls `##class(OcuTalon.Core.BridgeSink).OnEvent(...)` -> with the load check alone, `test-install-start.sh` stayed green (the compiler accepts the call); with the source check added to row 5, row 5 is red and names `Decide.cls:24` (AC5). Review pass: the scan function of the script, run on a copy of `Decide` that holds that method, names `Decide.cls:29`; it flags a synthetic class that names `OcuTalon.Core` as a class and `OcuTalon_Data` as a table exactly twice, passes a clean one, and sees the 33 classes of the tree.
- mutation: the third slot removed from `Decide`'s storage block -> after load and compile on slot A the export of `Decide` differs from the mutated file (the compiler adds the slot back: lines 37-39) and equals the committed one (AC6, row 23).

### Results (review pass, October 19)

- After the patches: both trees load and compile with 0 errors (33 and 155 classes); the 14 `%UnitTest` classes pass, one class per call: `Test.Install.Production` 4, `Test.Bridge.Ext` 3, `Test.Bridge.Api` 4, `Test.Agent.Constants` 3, `Test.Core.Commands` 4, `Test.Contract.Ac` 6, `Test.Contract.Checker` 5, `Test.Install.Registry` 11, `Test.Install.PrivateData` 5, `Test.Data.Tables` 5, `Test.Msg.Contracts` 6, `Test.Bridge.Contracts` 5, `Test.Live.Payloads` 4, `Test.Data.Session` 3. Slot A is left as found: no `Zz` class, no `BridgeExt` child (only the counter), no System Default Setting row, `LastProduction` and `^Ens.AutoStart` unchanged.
- Shell, exit 0: `test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-build-inputs.sh`, `test-lib-live.sh`.
- Live, one throwaway each, none left, exit 0: `test-production.sh` (Health, and once on `iris-community:2026.3.0AI.154.0`), `test-production-restart.sh`, `test-install-start.sh` (row 5: the control, 33 classes scanned, the bridge alone), `test-install-upgrade.sh`, `test-sign-in.sh` (29 specs), `test-audit.sh`, `test-bundle-folder.sh`. The STEP list is unchanged.
- Row 23 again: the export of all 188 classes equals the tree byte for byte.

### Mutations (Rule 19), review pass, October 19

Each was applied, loaded on slot A or built into a throwaway, run, and reverted from a saved copy; the hash of `src/` and `docker/` and `git status --short` were identical before and after, apart from one intended fix to the `Write` order in `test-production.sh` made between two live runs (the seven slot A mutations were applied together and run one class per call).

- mutation: `Submit` leaves a payload origin of `web_admin` alone -> `Test.Core.Commands.TestOrigin` red ("the origin web_admin is accepted and replaces the payload's") (row 8).
- mutation: `Submit` without its `$Get` guards -> `TestOmittedArguments` red (`<UNDEFINED>` on `origin`) (row 8).
- mutation: `Context.Begin` returns OK when a context is active -> `Test.Bridge.Ext.TestContext` red ("Current carries only the second request's fields") (row 7).
- mutation: the "not compiled" line removed from `Accessor.Check` -> `TestAccessorInAnotherJob` red (the `checkMissing` case) (row 2).
- mutation: the "agent class not compiled" line removed from `AgentRunner.ResolveModel` -> `Test.Install.Production.TestRunnerModels` red (`<CLASS DOES NOT EXIST>` for the runner whose agent class is missing) (row 4).
- mutation: `Adapter.Agent` without its `OnInit` -> `Test.Bridge.Api.TestStubAdapter` red ("OnInit is the adapter's own") (AC3, the no-key start).
- mutation: `HasTemplateToken` returns 0 -> `Test.Agent.Constants.TestAgents` red ("the detector flags a text with a {{ token") (row 11).
- mutation: the reserved-word query leaves out `OcuTalon.Core.Intake` -> `Test.Data.Tables.TestSqlNames` red ("OcuTalon.Core.Intake is among the checked classes") (AC1, the persistent processes).
- mutation: the `Ens.BusinessProcessBPL` root dropped -> `test-storage.sh` `FAIL storage: the checker does not flag the sample no-storage-bpl` (AC2, row 12).
- mutation: the recursion of `process()` removed -> `test-storage.sh` `FAIL controls`, with `registry-param` naming `Core/SubProc.cls` (AC2, row 12).
- mutation: `Start` falls through to `RestartProduction` when another production runs -> `test-production.sh` red at "another production: the step fails naming it and leaves it running" (`start-refused` 1|0), every other check green (AC3).
- mutation: the `docker kill` of row 20 replaced by `true` -> `test-production-restart.sh` `FAIL row 20: the container did not start again after the kill` (AC4).

## Auto Run Result

Status: done
Blocking condition: none

**Planning summary (October 19).**
- **Sources.** The spec was planned against the committed `epic-0-context.md`, Story 0.5's spec, the spine (AD-1, 2, 3, 5, 6, 7, 8, 11, 19, 20, 22, 23, 28, 29, 31 and 33, the Conventions and the Structural Seed's tables, by line range) and `epics.md` (0.6, 0.7, 0.10, 1.1, 1.2, 2.3, 11.5 and 15.2).
- **Checks.** No intent gap; no AC contradicts an AD; no NFR tripwire.

**Implemented change.**
- The production `OcuTalon.Production` holds the 38 release-1 items in two lane regions; 35 are enabled and `TelegramIn`, `TelegramOut` and `EvalIn` are off. Every unbuilt item is a `STUB` class that answers "not implemented" (5003), and the two routers' rule classes are stubs with an empty rule set.
- The `Production` install step starts, recovers or restarts the production and waits until every enabled item with a pool has an alive job and every runner resolves a model. It writes the `EvalIn` System Default Setting row from `OCUTALON_EVAL` at every start, and never marks autostart.
- The bridge gained its extension bases and `Ext.Accessor`, the no-AI-Hub-call adapter, `AgentRunner.ResolveModel`, `Context` (over `^||OcuTalonBP.Context`), `Compaction`, and the stub signatures of `Approval`, `Budget`, `Keys`, `Timeouts` and `ConfigStore`. `Core.Commands.Submit` is implemented; the other cross-lane APIs, the agents with `MOCKKEY`, `Tools.Names` and `BridgeSink` and `ReplyGuard` are signatures and constants.
- DW-13: `test-storage.sh` also covers business processes, message bodies and stream containers.

**Files changed.**
- `src/bridge/cls/OcuTalon/Bridge/`: 17 new classes (`Adapter/Agent`, `Approval`, `Budget`, `Compaction`, `ConfigStore`, `Context`, `Keys`, `Timeouts`, `Ext/*` (4), `Operation/AgentRunner` and `Steps`, `Process/Decide` and `ApprovalHold`, `Service/ApprovalStart`).
- `src/ocutalon/cls/OcuTalon/`: 40 new classes (`Production`, 31 item stub classes under `Channel`, `Core`, `Schedule`, `Demo`, `Watch`, `Eval`, `Fix`, `Checks`, `Digest`, the two `Core/Rule` classes, `Core/BridgeSink`, `Core/Commands`, `Checks/ReplyGuard`, `Agent/*` (4), `Tools/Names`, `Data/Ownership`), plus `Data/Session` (`Recipients`) and `Install/Step/Production` (filled in place).
- Tests: five new classes (`Test/Install/Production`, `Test/Bridge/Ext`, `Test/Bridge/Api`, `Test/Agent/Constants`, `Test/Core/Commands`); `Test/Contract/Ac` (31 signature rows, floor 43); `Test/Data/Tables` (`TestSqlNames`).
- `docker/tests/`: new `test-production.sh` and `test-production-restart.sh`; `lib-live.sh` (`item_jobs`, `check_items_run`); `test-storage.sh` (DW-13 and its samples); `test-install-start.sh` (row 5's source check).

**Review findings breakdown.**
- 50 findings from four layers: high 0, medium 9, low 38, false 3. 25 were patched, 25 rejected, none deferred or routed (`deferred:` stays empty); no `intent_gap` or `bad_spec`.
- Patched (grouped by root cause; medium unless marked low): the row 5 scan lacked a control, a floor and table names (3 findings); row 20 did not confirm the kill; no test for the step with another production running; no pin for the stub adapter; the `{{` assertion could not fail; `Submit` threw on a left-out origin (low); the tests' stub count, not-running assertion, class-guard cases, second `Begin`, BPL and subclass samples, SQL-name coverage and origin loop (low); the step's class comment (low).
- Rejected with their reasons are in the Review Triage Log. The ones the lead should know: the three false findings (the snake_case pattern, a Suspended other-name production, `test-bundle-folder.sh`); `Context.Put` stays a plain setter (Change Log, reopen if Story 1.2 finds a path that clears `Tainted`); the adapterless services' check stays in the live row 14 (the Tasks' definition); row 23 stays a manual `(once)` run.
- Follow-up review recommended: true. Five medium entries were patched. The named risk: the patches are test and harness code that no independent layer has read (the source check and its control in `test-install-start.sh`, the other-production block in `test-production.sh`, the kill confirmation in `test-production-restart.sh`, and the new unit cases). Each was mutation-checked and the whole Verification list was re-run green.

**Verification performed.** Slot A (build 154, profile `ocutalon-slot-a`): both trees load with 0 errors; 14 `%UnitTest` classes pass, one per call; the slot is left as found. Shell: `test-storage.sh`, `test-boundaries.sh`, `test-compose-file.sh`, `test-build-inputs.sh`, `test-lib-live.sh` exit 0. Live, one throwaway at a time and none left: `test-production.sh` (Health and community images), `test-production-restart.sh`, `test-install-start.sh`, `test-install-upgrade.sh`, `test-sign-in.sh`, `test-audit.sh` and `test-bundle-folder.sh` exit 0. Row 23: 188 exported classes equal the tree. Twelve review-pass mutations and the earlier 17 were applied, seen red and reverted (Verification). Task 0's measurements are recorded under Verification.

**Residual risks and items for the lead.**
- The matrix wording to correct (Rule 5, apply and report): row 3 names `%New("")` and should say `Ens.Host.GetShadowInstance("class||<class>")`; row 16 should say that `Conversation` answers `<Ens>ErrBPTerminated` carrying 5003; AC5's pin is the row 5 source check plus the load.
- Rule 20 spine updates listed under Design Notes stand, with one addition: a business process whose stub handler fails answers `ErrBPTerminated`. The two VETO WINDOW items (`Submit` trusts the caller's origin; the step recovers a Troubled production) are still to be sent.
- `test-bundle-folder.sh` also runs the after-start script; it is now on the Verification list as a `(once)` line.
- An item whose `OnInit` fails after its job registers could pass one poll (Task 0 never saw it; the step re-checks nothing). Reopen if a real item shows it.
