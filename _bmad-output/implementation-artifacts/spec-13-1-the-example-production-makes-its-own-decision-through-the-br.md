---
title: 'Story 13.1: The example production makes its own decision through the bridge'
type: 'feature'
created: '2026-10-24'
status: 'done'
baseline_revision: 'fb66ec90ca1a8e54b71b6276b0bad345bc869e17'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: [oversized]
deferred:
  - summary: >-
      The spine lint reports ok:false on the base tree: four low placeholder findings that are template text of the spine's own examples, so the wording "ok: true" of AC 9 cannot hold.
    evidence: |-
      Linting the spine at the baseline commit gives the same four findings ('{time}' line 393, '{day}' line 831, '{what happened}' and '{reason}' line 844). The two new Lane A rows add none (same four before and after); no ad_id, ad_fields or placeholder finding comes from them.
    location: >-
      _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:393
    severity: low
---

<intent-contract>

## Intent

**Problem:** Epic 1's bridge example is only the three bridge items (`Decide`, `TriageAgent`, `AgentSteps`), and a decide request reaches it through Ens's testing service. No production of its own sends an item, routes on the decision or takes a fallback. So nothing yet shows a developer the bridge working, configured only by settings, in a production that has none of OcuTalon.

**Approach:**
- Grow `OcuTalon.BridgeExample.Production` into a small production of its own, beside the three bridge items: an adapterless service, a process that renders the item and calls `Decide`, a routing engine whose rule routes on the decision, and three operations it routes to.
- Extend `release/standalone-bridge.sh`, the script of the standalone-bridge job, so that in its throwaway namespace it sends items through the example's service and checks the decision, the trace, the routing, three settings changes, four fallbacks and the dummy key.
- Add the example's items to the spine's ownership table.

## Boundaries & Constraints

**Always:**
- Example classes name no OcuTalon package other than `OcuTalon.Bridge` and their own (AD-2). The example agent `OcuTalon.BridgeExample.Agent` stays unchanged (AD-7).
- The production definition holds structure (items, classes, pool sizes, enabled flags) plus the settings that wire it: the runner's three existing settings and the router's `BusinessRuleName`. `Model`, `ProviderConfig`, `TimerSeconds` and `DecisionTokenBudget` are never in the definition. They are System Default Settings rows that a developer writes (AD-5, AD-19). The definition comes before those rows when a setting is read (`Ext.Accessor.ValueFor`), so a value in the definition would hide them.
- The process sends `Decide` one `OcuTalon.Bridge.Msg.Request` per item with these fields:
  - `Kind` `decide`, `OwnerRef` `instance` and `Channel` `system`;
  - `Provenance` taken from the item (default `untrusted`);
  - the item's `ItemId`, from `OcuTalon.Bridge.Ids.NewRef()`;
  - a code-written one-line `Summary` of at most 80 characters;
  - the rendered text as `Input`, never the item object (AD-6).
- The rule routes on the named properties `Fallback` and `Outcome` only.
- No extension class is named on `Decide` (AD-31).
- The model key reaches the runner only as `@{env:ANTHROPIC_API_KEY}` in its `ProviderConfig` row.
  - The throwaway's dummy value is generated at run time inside the run's temporary folder. It is never committed and never printed.
  - `x-ocutalon-mockkey` is added only after the script checks `OCUTALON_MOCK_KEY_HEADER=1` (owner-fixed value 11).
- The standalone checks run only in a throwaway stack, in the namespace `OCUBRIDGE` that the script creates. CI builds the image on the runner and never caches, pushes or uploads it (AD-22).
- Every live wait is a poll with a deadline. The audit read-back polls, because entries can arrive about a minute late (AD-17).

**Never:**
- No change to `src/bridge/cls/OcuTalon/Bridge/**` (Epic 3's). No change to any other contended file except the lines that Task 9 names, once the orchestrator has ruled on them.
- No tool, toolset, `ApprovalHold`, Workflow operation or approval role in the example (Story 13.2). No developer guide (Story 13.3). No new mock behaviour: only scenario files `ci/mock/scenarios/A/bridge-example-*.json`.
- The example is never started in OCUTALON, and `EnsLib.Testing.Service` is no longer used: the script stops writing its `TestingEnabled` row.
- No sampling parameter, and no new third-party dependency.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | `ItemIn.Send(subject, body)` with no marker; the mock picks `bridge-example` by `MOCKKEY` | One `DecisionResponse` back to `ExampleTriage`: outcome `tellnow`, reasons, confidence 0.7, the four token counts, model `claude-haiku-5-5`, `CostUSD` from `Price`. Routed to `ExampleNotifyOut` only | No error expected |
| Digest | body holds `[[mock:bridge-example-digest]]` | Outcome `digest`, routed to `ExampleDigestOut` only | No error expected |
| Ignore | body holds `[[mock:bridge-example-ignore]]` | Outcome `ignore`. The router completes and sends to no operation | No error expected |
| Model changed | `TriageAgent` `Model` row = `claude-sonnet-5-5`, applied | The next decision's `Model`, its `Usage` row and the mock's request name `claude-sonnet-5-5`, and its cost is at the Sonnet price | Row removed and applied again afterwards |
| Budget | `Decide` `DecisionTokenBudget` row = 1, applied | Fallback `budget`: no runner request and no `Usage` row. Routed to `ExampleFallbackOut` | Row removed afterwards |
| No key | `ProviderConfig` row's `api_key` = `@{env:OCUTALON_EXAMPLE_UNSET_KEY}`, a variable the stack never sets | Fallback `no_key`, no runner request, routed to `ExampleFallbackOut` | Row restored afterwards |
| Refusal | body holds `[[mock:bridge-example-refusal]]` | Fallback `refusal`, routed to `ExampleFallbackOut` | No error expected |
| Timeout | `Decide` `TimerSeconds` row = 12, applied; body holds `[[mock:bridge-example-late]]` (reply held 25 s) | Fallback `timeout`, with `DurationMs` from 12000 to 17999 | Row removed afterwards |
| Every fallback | any of the four rows above | `tellnow`, `Fallback` 1 and the reason on the row and on the `DecisionResponse` in the trace. No reasons are kept and no tool step is recorded | Production keeps running |
| Keeps running | after the fallbacks | Every item's job is alive, and a plain item gets a usable `tellnow` routed to `ExampleNotifyOut` | Polls up to 90 s: the runner may still hold the late call |
| Blank item | subject and body both empty once white space and control characters are removed | `Send` returns an error status that names Subject and Body. No message is sent | Error status, no header |
| Summary | subject over 80 characters, holding a line break | One line of at most 80 characters, with control characters and line breaks turned to spaces. With an empty subject, the first non-blank line of the body is used | No error expected |
| Dummy key | the run's dummy `ANTHROPIC_API_KEY` | Found in no `AgentStep`, `DecisionResponse`, `Decision` row, `Decided` message or `OCUBRIDGE` event-log row, and in no IRIS audit entry since the run began | A hit fails the check without printing the value |

</intent-contract>

## Code Map

- `src/bridge/cls/OcuTalon/BridgeExample/Production.cls` -- Epic 1's three-item production (doc lines 1-9, XData lines 13-25). This story grows it. Keep `TriageAgent`'s three settings exactly as they are: `AgentClass`, `AgentAllowList` (the example agent) and `ReplyClass` `OcuTalon.Bridge.Msg.DecisionPayload`.
- `src/bridge/cls/OcuTalon/BridgeExample/Agent.cls` -- read-only. `MODEL` `claude-haiku-5-5`, `MOCKKEY` `bridge-example`, `TOOLSETS` "", and INSTRUCTIONS with no `{{`. The first AC holds here already, and `OcuTalon.Test.Bridge.Example:TestAgent` pins it.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- read-only.
  - `RUNNERS` fixes the decide runner's item name as `TriageAgent`.
  - `Admit` (line 462) needs `Kind`, `Provenance`, `ItemId`, `OwnerRef` and a non-blank `Input`.
  - `TimerSeconds` must be from `MINTIMER` 12 to 110. `DecisionTokenBudget` 0 means off.
  - Both settings are host properties that the job takes when it starts, so a change needs the item restarted.
  - `RecordFallback` keeps no reasons. `OnRequest` (line 216) records the precheck fallbacks with no runner request.
- `src/bridge/cls/OcuTalon/Bridge/Keys.cls:61` -- `Absent` reads the runner's `ProviderConfig` setting live (`GetAdapterSettingValue`), so a changed row gives `no_key` with no restart.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:53-75` -- `AgentAllowList`. The runner refuses to start when `AgentClass` is not on the list. `Model` is a setting of AI Hub's adapter (`irislib/EnsLib/AI/Agent/OutboundAdapter.cls:61`), so its row uses target Adapter or host class `*`.
- `src/bridge/cls/OcuTalon/Bridge/Ext/Accessor.cls:19` -- `ValueFor` reads the production definition, then System Default Settings, then the property's initial value.
- `src/bridge/cls/OcuTalon/Bridge/Msg/Request.cls`, `Msg/Result.cls`, `Msg/DecisionResponse.cls`, `Msg/AgentStep.cls` -- the contract.
  - The decision fields are on `Result`.
  - `AgentStep` holds `Label`, `Summary`, `DurationMs`, `Status` and `EstimatedTokens`, and has no token or cost property.
  - `Msg/Enum.cls` lists `CHANNEL`, which includes `system`.
- `src/bridge/cls/OcuTalon/Bridge/Data/Price.cls:58` `CostFor(model, prompt, cacheRead, cacheWrite, completion, ...)`; `Data/Usage.cls:144` `Totals`; `Data/Decision.cls` (`ItemIdKindIndex`, `TraceSessionId`); `Ids.cls` `NewRef`.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls` `Write(type, data, description)` and `Installer.cls:100` `CheckAudit()` -- the audit path of AC 5.
- `src/bridge/cls/OcuTalon/Bridge/Service/ApprovalStart.cls`, `Operation/Steps.cls` -- the adapterless-service and answer-OK-with-no-response operation patterns that `ItemIn` and `Outcome` follow.
- `release/standalone-bridge.sh` -- the job's script.
  - Check 3 (lines 94-111) writes the `ProviderConfig` row with `api_key` `@{env:OCUTALON_MOCK_KEY_HEADER}` and the `TestingEnabled` row.
  - Check 4 (lines 113-182) starts the production (3 jobs), sends through `EnsLib.Testing.Service` (line 141), and checks the price and the steps.
  - The diagnosis block is at line 184; checks 5 and 6 follow.
- `docker/tests/lib-live.sh` -- read-only.
  - `live_add_file` (line 147) adds a compose file after the overrides.
  - The decoy and env reset (lines 78-81) mean no key reaches a throwaway unless a compose file sets one.
  - `check_session` (line 465) and `settle_scheduler` (line 662).
- `ci/compose.ci.yml` -- read-only. It sets no key variable, sets `OCUTALON_MODEL_BASE_URL` and `OCUTALON_MOCK_KEY_HEADER=1`, and mounts the mock's log at `/opt/ocutalon/mock-log/requests.jsonl`. Each log line carries `scenario`, `marker`, `model` and `rejected`.
- `ci/mock/scenarios/A/bridge-example.json` -- the default script, matched by `mockkey` (`tellnow`, 0.7). `refusal.json`, `decide-late.json` and `decide-ignore.json` show the shapes of a refusal, a held reply and a marker scenario. Read them only: they are contended. A file's `name` must equal its file name.
- `docker/tests/lib-scan.sh:59` `bridge_refs`, run by `docker/tests/test-class-rules.sh:196-202` over every file of `src/bridge/cls`, the example included -- read-only, contended. It already fails on an example class that names another OcuTalon package.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls:55-90` (`TestProduction`) and `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:442-458` (`TestExampleInstalledNotStarted`) -- existing Epic 3-contended files that pin the three-item shape. See Task 9.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Timeouts.cls:179` and `Ext.cls:71` -- read-only. They rely on the example's `TriageAgent` having no `@{config:}` `ProviderConfig` and on no row naming the example in OCUTALON. Keep `ProviderConfig` out of the definition.
- `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md:1039-1060` -- the Production items ownership table (AD-33).
- `irislib/Ens/Config/DefaultSettings.cls:265,336` -- saving a row raises the production's modification counter, so `Ens.Director.UpdateProduction()` (`irislib/Ens/Director.cls:159`) sees a change (inference; Task 7 measures it). `TempStopConfigItem` is at `Director.cls:2467`.

## Tasks & Acceptance

**Execution:**
- `src/bridge/cls/OcuTalon/BridgeExample/Msg/Item.cls` (new) -- an `Ens.Request` with these properties, and its compiler-generated `Storage` block (no `DEFAULTGLOBAL`):
  - `ItemId` (22);
  - `Subject` (200);
  - `Body` (no limit);
  - `Provenance` (`user` or `untrusted`, initial `untrusted`).

  Rationale: the example's own item.
- `src/bridge/cls/OcuTalon/BridgeExample/Msg/Decided.cls` (new) -- an `Ens.Request` with `ItemId`, `Summary`, `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason`, and its `Storage` block. Rationale: the message the rule routes; the example's counterpart of `OcuTalon.Msg.ItemDecision`.
- `src/bridge/cls/OcuTalon/BridgeExample/ItemIn.cls` (new) -- the adapterless `Ens.BusinessService` that items enter by.
  - Setting `TargetConfigName`, default `ExampleTriage`.
  - `OnProcessInput` refuses anything but an `Item`, and an item whose `Check` fails. It sets an empty `ItemId` from `NewRef`, then sends the item asynchronously to the target.
  - `ClassMethod Check(item) As %Status` gives an error naming Subject and Body when both are blank.
  - `ClassMethod Send(subject, body, provenance = "untrusted", Output itemId) As %Status` builds the item, calls `Ens.Director.CreateBusinessService("ExampleItemIn")` and `ProcessInput`. A developer, the script and Story 13.3's guide send an item with this one line.
- `src/bridge/cls/OcuTalon/BridgeExample/Triage.cls` (new) -- the `Ens.BusinessProcess`, with setting `RouterName` (default `ExampleRouter`) and its `Storage` block.
  - `OnRequest` sends `RequestFor(item)` to `Decide` (asynchronous, response wanted).
  - `OnResponse` sends `DecidedFor(item, response)` to `RouterName` and wants no response.
  - Class methods: `RequestFor`, `Render` ("Subject: <subject>", a blank line, then the body), `SummaryOf` (the Summary rule of the matrix) and `DecidedFor`.
  - An error status from `Decide` ends the process with that status, and nothing is routed.
- `src/bridge/cls/OcuTalon/BridgeExample/Rule.cls` (new) -- an `Ens.Rule.Definition` with `RuleAssistClass` `EnsLib.MsgRouter.RuleAssist`, context `EnsLib.MsgRouter.RoutingEngine` and production `OcuTalon.BridgeExample.Production`. Each rule is constrained to `Decided` and ends with a return. The rules, in order:
  1. `Document.Fallback=1` sends to `ExampleFallbackOut`;
  2. outcome `tellnow` or `act` sends to `ExampleNotifyOut`;
  3. `digest` sends to `ExampleDigestOut`;
  4. `ignore` returns and sends nothing.

  No concrete rule exists in the repo yet (`OcuTalon.Core.Rule.Outcome` is a stub), so check the XML grammar by compiling on the slot or in the throwaway.
- `src/bridge/cls/OcuTalon/BridgeExample/Outcome.cls` (new) -- the adapterless `Ens.BusinessOperation` behind the three operation items.
  - For a `Decided` it logs one `$$$LOGINFO` line: its item name, the outcome, `DecisionRef`, `ItemId` and, for a fallback, the reason. No model text.
  - It answers OK with no response. Any other message class gets "not implemented".
- `src/bridge/cls/OcuTalon/BridgeExample/Production.cls` -- the definition becomes nine items in this order, with `TestingEnabled` false and `ActorPoolSize` 2:
  1. `ExampleItemIn` (pool 0);
  2. `ExampleTriage`;
  3. `Decide` (no setting);
  4. `TriageAgent` (its three settings unchanged);
  5. `AgentSteps`;
  6. `ExampleRouter` (`EnsLib.MsgRouter.RoutingEngine`, setting `BusinessRuleName` `OcuTalon.BridgeExample.Rule`);
  7. `ExampleNotifyOut`;
  8. `ExampleDigestOut`;
  9. `ExampleFallbackOut`.

  Every item but the service has pool 1, and the last three are of class `OcuTalon.BridgeExample.Outcome`. Rewrite the doc comment to the new contract.
- `ci/mock/scenarios/A/bridge-example-digest.json`, `bridge-example-ignore.json`, `bridge-example-refusal.json`, `bridge-example-late.json` (new) -- marker scenarios: a valid `digest` and a valid `ignore` JSON reply with reasons and confidence; `stopReason` `refusal`; and a valid `tellnow` reply with `delayMs` 25000.
- `release/standalone-bridge.sh` -- before writing the new checks, measure one thing in the throwaway: does a saved System Default Settings row followed by `Ens.Director.UpdateProduction()` restart the item whose effective setting changed? If not, which call does (`TempStopConfigItem(item,1)` then `(item,0)`)? Use that as the script's one `apply` helper, and record it in the header and under `## Design Notes`. Then:
  - Generate the run's dummy key (`ocutalon-example-dummy-` plus 16 random hex digits). Write `services: iris: environment: ANTHROPIC_API_KEY: <dummy>` to `$tmp/key.yml` and call `live_add_file` before `dc up`.
  - Check 2 adds `Installer.CheckAudit()` OK in `OCUBRIDGE`.
  - Check 3 writes the `ProviderConfig` row with `api_key` `@{env:ANTHROPIC_API_KEY}`, keeps the base URL and the mock-key header, checks inside IRIS that the container's variable equals the dummy (it prints only 1 or 0), and drops the `TestingEnabled` row.
  - Check 4 waits for the eight job items to be Alive, checks that `ExampleItemIn` is enabled and that the runner resolves the example agent as `AgentClass` and `AgentAllowList` and `DecisionPayload` as `ReplyClass`, keeps the extension-settings check, and writes one `Action` entry through `OcuTalon.Bridge.Audit.Write` carrying a run-unique marker.
  - Then the matrix rows, each through `ItemIn.Send` and polled to its routed header:
    - the happy path, with the trace order and fields of AC 3 and AC 4;
    - digest and ignore;
    - the model, budget, no-key, refusal and timeout rows, each change applied and undone;
    - keeps-running.
  - Then the mock-log check (AC 4), the dummy-key search (in `OCUBRIDGE`, and in `%SYS` for the audit log) and the audit read-back of check 4's entry, polling up to 180 s.
  - Keep the web-application and stop checks.
  - Rewrite the header's check list. One PASS or FAIL line per check, exit 1 on any failure, and the event-log diagnosis on failure.
- `.github/workflows/lane-a.yml` -- update the header comment to the full example. If the developer-machine run takes over 4.5 minutes, raise `OCUTALON_LIVE_DEADLINE` to 1200 and `timeout-minutes` to 25. Nothing else changes: no cache, artifact or registry step.
- Task 9, only as the orchestrator rules -- `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls` and `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:
  - In `TestProduction`, change only the lines that pin three items: the header's `TestProduction` bullet, the method comment, `Items.Count()` 3, the per-item pool `1|1` (the service has 0), the name list and the settings total 3. They become the nine items above, in order, with the four settings, and with `Decide`'s and `TriageAgent`'s existing assertions kept.
  - In `TestExampleInstalledNotStarted`, change only the count line 3 to 9 and the "three items" words of its comment and message.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ExampleTriage.cls` (new; the lane-a shard's Bridge area already holds it) -- unit tests that start nothing:
  - `RequestFor`: every field, and `Decide.Admit` accepts the request;
  - `SummaryOf`: the matrix's Summary row;
  - `Render`: it keeps a marker in the body;
  - `ItemIn.Check`: the blank-item row, while subject-only and body-only items are accepted;
  - `DecidedFor`: it copies the six fields.
- `ARCHITECTURE-SPINE.md` (Production items table, after `OcuTalonApprovals`) -- two Lane A rows. Then run the spine lint.
  - Row 1: `ExampleItemIn`, `ExampleTriage`, `ExampleNotifyOut`, `ExampleDigestOut`, `ExampleFallbackOut`, which exist only in `OcuTalon.BridgeExample.Production`, beside its `Decide`, `TriageAgent` and `AgentSteps`, and are never started in OCUTALON. Classes: `OcuTalon.BridgeExample.ItemIn` (adapterless), `.Triage` and `.Outcome`.
  - Row 2: `ExampleRouter`, class `EnsLib.MsgRouter.RoutingEngine` with rule `OcuTalon.BridgeExample.Rule`.
  - Rows only: no AD text changes and no new AD (AD-33).

**Acceptance Criteria:**
1. Given the package `OcuTalon.BridgeExample`, when `docker/tests/test-class-rules.sh` runs, then `bridge-refs` passes on the tree and fails when an example class names another OcuTalon package. The example agent keeps static INSTRUCTIONS with no `{{`, `MOCKKEY` and `MODEL` `claude-haiku-5-5`, and the runner checks its reply against `DecisionPayload` (`ReplyClass`).
2. Given `OCUBRIDGE` in a throwaway, holding only `src/bridge/` loaded with `LoadDir` and `OcuTalon.Bridge.Installer` run, when `OcuTalon.BridgeExample.Production` starts, then all nine items run: eight jobs are Alive and `ExampleItemIn` is enabled. The runner started with the example agent as `AgentClass` and on its allow-list, and `Decide` names no extension class.
3. Given the example running against the mock, when an item is sent through `ExampleItemIn`, then:
   - `ExampleTriage` sends `Decide` a `Request` with `Kind` `decide`, `OwnerRef` `instance`, the item's `ItemId` and `Provenance`, `Channel` `system`, the code-written `Summary` and a non-empty `Input`;
   - exactly one `DecisionResponse` comes back in the item's session, with outcome, reasons, a confidence from 0 to 1, the four token counts (input above 0) and `CostUSD` equal to `Price.CostFor` for its model and tokens and to its one `Usage` row.
4. Given that decision, when the session's headers are read in id order, then they show: the item; the request; the runner's request and reply; each `AgentStep` from `Decide` to `AgentSteps` in `Position` order, each with a label, a summary, a duration and `EstimatedTokens` above 0; the `DecisionResponse`; the `Decided` message to `ExampleRouter`; and the router's send to the outcome's operation only (`ignore`: none).
   - `AgentStep` has no token or cost property.
   - The mock's log holds no request rejected for sampling or `max_tokens`, and a line not rejected for each marker item.
5. Given no extension class named, when the example decides, then each decision that reached the model has its `Usage` row and cost. `Installer.CheckAudit()` is OK in `OCUBRIDGE`, and an `Action` entry written there through `OcuTalon.Bridge.Audit` is read back from the IRIS audit log within 180 s.
6. Given the runner's `Model`, `Decide`'s `DecisionTokenBudget` or `Decide`'s `TimerSeconds` changed as a System Default Settings row and applied, when the next item is sent, then its decision shows the new value (matrix rows Model, Budget and Timeout), with no code change.
7. Given each fallback row of the matrix, when its item is sent, then the decision is `tellnow` with `Fallback` 1 and its reason in the row and in the trace's `DecisionResponse`, routed to `ExampleFallbackOut`, with no tool step. The production keeps running, and the dummy key appears in no step, decision message, event-log row or audit entry.
8. Given a push, when lane-a's standalone-bridge job runs `release/standalone-bridge.sh` on the IRIS runner, then the job fails unless every check above passes, and it builds its image on the runner with no cache, push or artifact.
9. Given the spine, when the change lands, then the Production items table holds the two Lane A rows, and the spine lint reports `"ok": true`.

## Spec Change Log

- 2026-10-24, lead (Epic 13 runner), after the plan's blocked round 1: both escalated questions ruled (Design Notes, Clarification Needed items 1 and 2: the orchestrator's option (a) for Task 9's lines; the runner's decide on the audit clause). The spec already assumed both answers, so nothing else changed; status set to ready-for-dev without a re-plan.

## Review Triage Log

### 2026-10-24 -- Review pass
- verdicts: 31 findings -- high 0, medium 5, low 21, false 4, maybe-false 1
- findings:
  - `[low]` `[reject]` TestProduction pins counts only, not each item's class or settings (blind) -- the standalone script pins them (AC 2's recorded mutation went red there); Task 9 bounds the lines that may change in that file.
  - `[low]` `[reject]` no unit tests for Rule, Outcome, Msg.Decided or ItemIn.OnProcessInput (blind) -- the script drives all of them against a real production; the one untested rule clause (act) is patched below.
  - `[low]` `[reject]` Check and Send do not validate Provenance (blind) -- the item class's VALUELIST refuses it at save with an error status and nothing is sent; no caller of this example passes anything else.
  - `[low]` `[reject]` Send returns an ItemId when ProcessInput fails (blind) -- the status is the signal and every caller checks it; the Ref points to no message, which the status already says.
  - `[low]` `[reject]` item_check builds its send line without escaping quotes (blind) -- every string it is given is a fixed literal of this script; a developer-facing helper does not exist.
  - `[maybe-false]` `[reject]` iris_script retry could send a second item (blind) -- it needs a session that prints no CHK line; each check then reads the session of its own new ItemId; would be low if true.
  - `[low]` `[reject]` timeout upper bound 17999 is tight (blind) -- the bound is the matrix row's own wording (by-design); the run passed in each of five runs.
  - `[low]` `[reject]` audit scan uses the host clock and covers enabled events only (blind) -- the key is random per run and exists only after the stack starts, minutes after the window opens; see the patched audit order for the late-entry part.
  - `[low]` `[reject]` key scan omits Usage, Item and message-header tables (blind) -- the scanned set is the matrix row's own list (AgentStep, DecisionResponse, Decision, Decided, event log); spec-bound.
  - `[false]` `[reject]` runtime near the job limit (blind) -- the measured run is 2 min 40 s to about 6 min on a loaded machine against timeout-minutes 20, and every wait has its own deadline.
  - `[low]` `[reject]` spine does not list the new messages or scenarios (blind) -- AD-33's table lists production items only, and the spec says rows only.
  - `[false]` `[reject]` blank summary when the first 400 characters of a subject are blank (edge) -- Subject has a limit of 200 characters, and a blank subject takes the body path.
  - `[low]` `[reject]` Body over the string limit makes Check throw (edge) -- needs about 3.6 million characters in one item; theoretical.
  - `[false]` `[reject]` F_AWAIT can read routing before the Decided header completes (edge) -- the target poll runs only after the Decided header is Completed (`If done,target'=""`).
  - `[medium]` `[patch]` the audit key search runs once, before the audit read-back (edge) -- moved after the read-back in release/standalone-bridge.sh.
  - `[low]` `[reject]` host-clock `since` against the container's audit timestamps (edge) -- as for the blind finding above.
  - `[low]` `[reject]` a partial last line of the mock log makes %FromJSON throw (edge) -- the mock writes whole lines and the read happens after the matrix; theoretical.
  - `[low]` `[reject]` the marker row could be counted twice (edge) -- the marker is run-unique and written once.
  - `[low]` `[reject]` in-session waits are not checked against the script's deadline (edge) -- each wait has its own deadline, and the job's timeout-minutes bounds the worst case.
  - `[low]` `[patch]` diagnose could print the dummy key if it leaked into the event log (edge) -- its output passes through `sed` that replaces the dummy with a label.
  - `[low]` `[patch]` the old check that the first step is of kind model was dropped (edge) -- F_HAPPY's step check now also requires StepKind model at Position 1.
  - `[low]` `[patch]` the lane-a.yml header said "every record and audit entry" (edge) -- reworded to the records the script searches.
  - `[medium]` `[patch]` the audit-key claim is unpolled (edge) -- same root cause and fix as the audit-order row above.
  - `[medium]` `[patch]` act routing has no test and no scenario (verification-gap) -- scenario bridge-example-act.json, one item_check row, and a mutation line.
  - `[medium]` `[patch]` the blank-item assertion on Send passes without Check, because no production runs (verification-gap) -- TestCheck now asserts that Send's error text names Subject and Body; mutation recorded.
  - `[low]` `[patch]` the dummy-key search has no recorded mutation (verification-gap) -- mutation: a leak into the event log by Outcome; red recorded.
  - `[medium]` `[patch]` the audit key search runs before late rows are awaited (verification-gap) -- the same entry as the audit-order row.
  - `[low]` `[patch]` AC 8 has no mutation line (verification-gap) -- the script's exit 1 on a failed check is recorded under the act and key mutations; AC 9 stays a review check; AC 4's log sub-claims and AC 6's Model and Budget rows sit under their ACs' one recorded mutation each.
  - `[low]` `[reject]` log-sonnet is compared to exactly 1 (verification-gap) -- one item sends one Sonnet request; the check passed in five runs.
  - `[false]` `[reject]` TestProduction names no BusinessRuleName value (verification-gap) -- the script's routing checks cover the value (the Rule mutations went red).
  - `[low]` `[reject]` Alive is the only readiness signal before a send (verification-gap) -- each item_check polls up to 60 s, which absorbs the runner's start.
- intent-alignment (descriptive, no findings counted): it reads the diff as the running-production surface, with the class surface as support; the divergences it names (the unpolled audit search, the SQL-written no-key row, class-level coverage of the blank item) repeat rows above or Design Notes 8.

## Design Notes

**Governing ADs (Rule 6):**
- AD-2: bridge-only references, and the standalone `LoadDir` plus `Installer` path.
- AD-5: the production class is structure; values live in rows.
- AD-6: the `Decide` pipeline, the `Request` fields, one decision per item, and the allow-list.
- AD-7: the agent, `ReplyClass` and `Model`.
- AD-8: the fallback reasons and the timer range.
- AD-9: steps, and tokens per turn.
- AD-17: the one audit writer, and late rows.
- AD-19: settings as System Default Settings rows, and the key only through `@{env:}`.
- AD-20: `Usage`, `Price` and the budget precheck.
- AD-22: mock scenarios under `ci/mock/scenarios/A/`, no image in a cache or registry, and the throwaway.
- AD-26: decision messages in the trace session.
- AD-29: Lane A's files, and lane-a's job.
- AD-30: the example mirrors its routing shape.
- AD-31: do-nothing extension defaults.
- AD-33: ownership rows in the same change.

No AC contradicts an AD's Rule.

**Integration AC (Rule 1):** AC 8. The consumer is lane-a's standalone-bridge job: it runs the example through `release/standalone-bridge.sh` and fails the build unless the decision message is found.

**Consumed-by:**
- Story 13.2: adds the example's toolset, `ApprovalHold` and `OcuTalonApprovals` to this production, and the per-classification tests to this script.
- Story 13.3: the guide documents `ItemIn.Send` and these settings, and the job runs the guide's commands.
- Story 15.2: the IPM install checks that the example is installed and not started in OCUTALON.

**Consumes:** `Decide`, `TriageAgent` and `AgentSteps`, `Installer`, `Audit`, `Price`, `Ids` and the model mock, all exercised against a real throwaway instance, never a mock of IRIS.

**Extend, don't copy (Rule 2):**
- `ItemIn` and `Outcome` follow the five-line patterns of `Bridge.Service.ApprovalStart` and `Bridge.Operation.Steps`. Neither can be extended: they are other items' hosts.
- `Msg.Decided` mirrors `OcuTalon.Msg.ItemDecision`, which the example cannot reference (AD-2).
- The four scenario files copy the shapes of `decide-ignore`, `refusal` and `decide-late` so that the example's scenarios stay its own: the standalone job and the guide never depend on OcuTalon's fixtures, which other epics edit.
- The script's new checks extend the existing `check_session` blocks. No new helper copies a `lib-live.sh` one.

**Decided in-stage:**
1. The example keeps `AgentAllowList` = `OcuTalon.BridgeExample.Agent` only.
   - OcuTalon's three agents are seeded by OcuTalon's own install step (`Install.Step.Production`), never by the bridge, and they do not exist in a namespace with no OcuTalon class.
   - Naming them would also put OcuTalon package names into an example class, which `bridge-refs` flags.
   - So "exactly as a developer adds their own agent" is the example naming its own class in that setting.
2. "Clean build 154 instance" stays as Epic 1 built it, and as the runner's prompt describes the standalone script today: a throwaway of the product image with a new namespace that holds no OcuTalon class. A consequence: the instance-wide audit events were already registered by OCUTALON's start, so the bridge installer's registration is shown only by `CheckAudit`.
3. The dummy key is set as `ANTHROPIC_API_KEY` in this throwaway only, through a compose file generated at run time. `no_key` is reached by pointing the `ProviderConfig` placeholder at a variable the stack never sets, which is a settings-only change, rather than starting a second stack.
4. The four routes are: fallback to `ExampleFallbackOut`; `tellnow` and `act` to `ExampleNotifyOut`; `digest` to `ExampleDigestOut`; `ignore` to none. This mirrors AD-30, where ignore only records.
5. Example items enter through `ItemIn.Send` (adapterless, pool 0, the product's convention). Items are prefixed `Example` so that the ownership table never pairs them with OcuTalon's own `Notify` or `DigestStore`.
6. The timeout row holds the reply 25 s under a 12 s timer and asserts `DurationMs` of 12000 to 17999. With the default 60 s timer the same item would be answered usably at 25 s, so the row proves that the new value is used.

7. The `apply` helper, measured in a throwaway of build 154 (a Model row on `TriageAgent`; a `TimerSeconds` row on `Decide`):
   - A System Default Settings row saved, then `Ens.Director.UpdateProduction()`, restarts the item whose effective setting changed, and only that item: `TriageAgent`'s job number changed after a `Model` row was saved and again after it was deleted, and `Decide`'s changed the same way for `TimerSeconds`. The decision after each change named the new model, and the one after the delete the default again.
   - So the script's `apply` is `UpdateProduction(30)` followed by a wait (up to 90 s) until the eight job items are Alive. `TempStopConfigItem` is not needed. It is recorded in the script's header.
8. The no-key row is written with `UPDATE %NOCHECK` on the existing `ProviderConfig` row: `Ens.Config.DefaultSettings` validates `ProviderConfig` by expanding its `@{env:}` placeholders on `%Save`, which refuses a variable that is not set ("has no value and no :-fallback was given"). `Keys.Absent` reads the setting live, so no apply follows (and an apply would restart the runner on a placeholder it cannot expand). The restore uses the same path.
9. `ItemIn.Send` reads the `ItemId` back from the item object that `ProcessInput` filled in, so it needs no output parameter from the service. The script's `diagnose` function prints the event log's error rows and the start check stops the script when the eight jobs are not Alive (a run with a runner that refuses to start would otherwise poll every row for 60 s).
10. A fresh run takes about 2 min 40 s on ARM (below the 4.5 min line), so `OCUTALON_LIVE_DEADLINE` (900) and `timeout-minutes` (20) of lane-a stay as they are; only the header comment of `lane-a.yml` changed. The audit entry was readable at once in the throwaway (0 s), and the read-back still polls up to 180 s.
11. The Provider-key row that check 3 writes keeps `x-ocutalon-mockkey` in `custom_headers` after the script checked `OCUTALON_MOCK_KEY_HEADER=1`; the dummy `ANTHROPIC_API_KEY` is set through `$tmp/key.yml` and `live_add_file`, and the script prints only 1 or 0 for it.
12. The review added the scenario `bridge-example-act.json` and one item row for outcome `act` (the rule's second clause had no coverage), moved the audit key search after the audit read-back, and made the first-step check require kind model.

**Ledger inbox:** none (no `DW-n` owned by this story).

**Clarification Needed (escalated with this plan; the spec above assumes the recommended answers):**
1. Contended files.
   - Growing the example production is required by AC 2 and AC 4. It turns two existing Epic 3-contended tests red, and an appended block cannot fix them:
     - `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls` `TestProduction` asserts exactly `Decide,TriageAgent,AgentSteps`, pool 1 for every item and three settings;
     - `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` `TestExampleInstalledNotStarted` asserts three items.
   - Recommended ruling: Epic 13 changes only the pinning lines that Task 9 lists.
   - The alternative: Epic 3, their current editor, makes the same edits.
   - **Ruled 2026-10-24 by the orchestrator (category decide, policy 9e90866): option (a), a one-time footprint extension for these lines only.** In `Test/Bridge/Example.cls` `TestProduction`: the header bullet, the method comment, the item count, the per-item pool check (the service has pool 0), the name list and the settings total become the nine items and their settings; the existing `Decide` and `TriageAgent` assertions stay. In `Test/Install/Production.cls` `TestExampleInstalledNotStarted`: the count 3 to 9 and its words. No other line in either file changes. Both files are reported under the runner's `footprint_extensions:`.
2. The audit clause of the third epic AC, "the bridge ... writes its audit entries for the example", has no entry to observe in 13.1.
   - AD-17 audits actions, approval answers, pairing, settings, MCP and tool classification, never a decision, and this example has no tool and raises no approval.
   - Recommended reading, as planned in AC 5 and AC 7: the bridge's audit path works in the example's namespace with no extension class named, and the dummy key is in no audit entry.
   - The entries for the example's own tool runs and approval answers stay with Story 13.2's existing ACs. No AC moves.
   - **Ruled 2026-10-24 by the Epic 13 runner (unattended, category decide):** the recommended reading stands, as AC 5 and AC 7 plan it. FR-9's list of audited events and AD-17's types (`Action`, `Approval`, `Pairing`, `Settings`, `MCP`, `Tool`) hold no decision event, so the clause asks that the bridge's one audit writer works for the example with no extension class named; nothing is weakened and no AC moves. Rejected: inventing a decision audit type (contradicts AD-17's fixed types); moving the clause to Story 13.2 (an AC move, veto window, with nothing to gain).

## Verification

`<lane variables>` = `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-c OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=13 stage=<stage>'`. `<tag>` = `e13s1` plus the stage's letter (implement `i`, QA `q`, review `r`), and the warm tag is `<tag>w`. Run every command in the foreground of its own call with `timeout: 600000`, one test-runner call per message.

**Commands:**
- `(loop)` `bash docker/tests/test-class-rules.sh` -- expected: every rule PASS (`bridge-refs` scans the example's classes). About 10 s.
- `(loop)` `bash docker/tests/test-storage.sh` -- expected: all PASS. The new message classes and the process carry their `Storage` blocks and no `DEFAULTGLOBAL`.
- `(loop)` `bash docker/tests/test-mock.sh` -- expected: 0 failures. The four new scenario files load.
- `(loop)` Warm, with `<lane variables>` and `OCUTALON_RUN_TAG=<tag>w`: `bash ci/warm.sh up` once. Then, one per call: `OCUTALON_WARM=1 ... bash ci/iris.sh class OcuTalon.Test.Bridge.ExampleTriage`, then `... class OcuTalon.Test.Bridge.Example`, then `... class OcuTalon.Test.Install.Production`. Finish with `bash ci/warm.sh down`, also after a failure. Expected: each `CLASS ... passed`.
- `(loop)` `<lane variables> OCUTALON_RUN_TAG=<tag> bash release/standalone-bridge.sh` -- expected: every check PASS, `standalone-bridge: all checks passed`, exit 0. About 4 to 5 minutes on ARM (inference). Then `<lane variables> OCUTALON_RUN_TAG=<tag> bash ci/iris.sh teardown`, expecting 0 projects removed (the script's trap removed its own).
- `(loop)` `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- expected: `"ok": true` and no `ad_id`, `ad_fields` or `placeholder` finding.
- `(once)` `bash docker/tests/test-ci-config.sh`, then `bash ci/checks.sh` -- expected: all rules and all scripts pass.
- `(once)` Fresh, with `<lane variables>` and `OCUTALON_RUN_TAG=<tag>`: `bash ci/iris.sh shard lane-a`, then `bash ci/iris.sh shard lane-a --reverse`, one per call, then teardown. Expected: every `CLASS ... passed` both times, `STACK ...: project`, no `WARM` line.
- `(once)` `git diff --stat -- src/bridge/cls/OcuTalon/Bridge src/ocutalon/cls/OcuTalon/Install src/ocutalon/cls/OcuTalon/Data docker/tests ci/units.sh ci/mock/mock.mjs ci/mock/server.mjs ci/compose.ci.yml .github/workflows/ci.yml` -- expected: empty. Under existing `src/ocutalon/cls/OcuTalon/Test/{Bridge,Install}` files, `git diff` shows only Task 9's lines.

**Pinning mutations (Rule 19; the implement stage applies each, records `mutation: ... -> ...`, and reverts):**
- AC 1: add a call to `OcuTalon.Core.BridgeSink` in `Triage.cls`. Expected red: `test-class-rules.sh` bridge-refs.
- AC 2: remove `AgentAllowList` from `TriageAgent`. Expected red: the script's start check (the runner refuses to start).
- AC 3: `RequestFor` sets `OwnerRef` "x". Expected red: `ExampleTriage.TestRequestFor`, and the script's request check.
- AC 4: swap the digest and tellnow targets in `Rule.cls`. Expected red: the script's routing checks.
- AC 5: `Write` the audit entry with type "Zz". Expected red: the read-back.
- AC 6: skip the `apply` call after the `TimerSeconds` row. Expected red: the timeout row (usable at 25 s).
- AC 7: `Outcome` ignores `Fallback`, or the rule's fallback rule is removed. Expected red: the fallback routing checks.
- AC 9: remove the rows. Expected red: none of the commands above sees it (no test parses the table), so the lead checks it by review.

**Shared surfaces:** the example production's item list and settings, which `OcuTalon.Test.Bridge.Example:TestProduction` and `OcuTalon.Test.Install.Production:TestExampleInstalledNotStarted` assert (Task 9); the spine's Production items table (no test parses it); and the mock's scenario set (no test counts it, and each `MOCKKEY` keeps its one `mockkey` scenario). Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations observed (Rule 19, implement stage, tree restored byte-identical after each; checked with `shasum` against a backup and `git status`):**
- mutation: add a call to `OcuTalon.Core.BridgeSink` in `Triage.cls` -> `test-class-rules.sh` `FAIL bridge-refs`; restored, all rules PASS.
- mutation: remove the `AgentAllowList` setting from `TriageAgent` in `Production.cls` -> the script's start check (`CHK|jobs` 7 of 8; the event log says the AgentClass is not on the AgentAllowList) and the script aborts.
- mutation: `RequestFor` sets `OwnerRef` "x" -> `OcuTalon.Test.Bridge.ExampleTriage:TestRequestFor` ("its OwnerRef is instance", run on slot C) and the script's happy-path `CHK|request|...` line.
- mutation: swap the digest and tellnow targets in `Rule.cls` -> the script's routing checks for the happy path, the digest item, the model row and the keeps-running item (4 checks red).
- mutation: write the audit entry with type "Zz" -> the script's `audit-write` check and the audit read-back (`not in the IRIS audit log within 180 s`).
- mutation: skip the `apply` call after the `TimerSeconds` row -> the timeout row's apply check and the timeout item (routed to ExampleNotifyOut, `Fallback` 0: usable at 25 s).
- mutation: remove the fallback rule from `Rule.cls` -> the fallback routing checks of budget, no key, refusal and timeout (each routed to ExampleNotifyOut).
- AC 9 (the two spine rows): no command sees them; the lead checks it by review (the spine lint reports the same four pre-existing placeholder findings before and after).
- mutation (review): drop the `act` clause from the TellNow rule in `Rule.cls` -> the script's act row (`CHK|routed` and `CHK|outcome` differ; 2 of 7 values) and exit 1.
- mutation (review): `Outcome` appends the container's `ANTHROPIC_API_KEY` to its event-log line -> the script's dummy-key check on the event log (`CHK|key-Log` 1; 1 of 6 values) and exit 1; the key was not printed.
- mutation (review): delete the `Check` call in `ItemIn.Send` -> `OcuTalon.Test.Bridge.ExampleTriage:TestCheck` ("and the error is Check's, which names Subject and Body"); restored, the class passes.
- AC 8: the two script mutations above end with `exit=1` and a `FAIL` line, and the unmutated script ends with exit 0 and `standalone-bridge: all checks passed`; the image build line of lane-a has no cache, push or artifact step (`test-ci-config.sh` passes).

**Run results of the implement stage:** `test-class-rules.sh`, `test-storage.sh`, `test-mock.sh` (94 tests), `test-ci-config.sh` and `ci/checks.sh` pass; the standalone script ends `standalone-bridge: all checks passed` (about 2 min 40 s); warm `ExampleTriage`, `Example` and `Install.Production` pass; `ci/iris.sh shard lane-a` and `--reverse` pass (42 classes each, `STACK ...: project`, no `WARM` line); the footprint `git diff --stat` over the closed paths is empty, and the two Task 9 files show only their listed lines.


## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.BridgeExample.Production` is now a nine-item production of its own: `ExampleItemIn` (adapterless, `ItemIn.Send`), `ExampleTriage` (renders the item, calls `Decide` with one `Request`), `Decide`, `TriageAgent`, `AgentSteps`, `ExampleRouter` (rule `OcuTalon.BridgeExample.Rule` on `Fallback` and `Outcome`) and three `Outcome` operations. `release/standalone-bridge.sh` sends items through it in the throwaway `OCUBRIDGE` and checks the decision, trace, routing, the model, budget, no-key, refusal and timeout rows, the keeps-running item, the mock log, the dummy key and the audit read-back (34 PASS lines, about 2 min 40 s on ARM when the machine is quiet).

**Files changed.**
- `src/bridge/cls/OcuTalon/BridgeExample/Production.cls` -- nine items, four settings.
- `src/bridge/cls/OcuTalon/BridgeExample/{ItemIn,Triage,Rule,Outcome}.cls` and `Msg/{Item,Decided}.cls` (new) -- the service, process, rule, operation and messages.
- `ci/mock/scenarios/A/bridge-example-{digest,ignore,refusal,late,act}.json` (new) -- marker scenarios.
- `release/standalone-bridge.sh` -- the extended standalone checks, with the one `apply` helper.
- `.github/workflows/lane-a.yml` -- header comment only.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/ExampleTriage.cls` (new) -- unit tests of `RequestFor`, `SummaryOf`, `Render`, `Check`, `DecidedFor`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls` and `Test/Install/Production.cls` -- Task 9's lines only (footprint extension, orchestrator ruling).
- `ARCHITECTURE-SPINE.md` -- the two Lane A rows of the Production items table.

**Review.** 31 findings from the layers (high 0, medium 5, low 21, false 4, maybe-false 1). Patches applied: 3 medium entries (the audit key search moved after the read-back; the `act` route covered by a scenario and a row; the blank-item `Send` assertion made falsifiable) and 4 low (diagnose filters the dummy key, the first-step kind check restored, the lane-a header claim reworded, mutation lines for the key search and AC 8). Deferred: 1 (the spine lint's pre-existing placeholder findings). Rejected with reasons: see the triage log (low theoretical or spec-bound, and the false claims).

**Follow-up review recommended: true.** Two or more medium entries were patched. The unverified risk: the audit key search now runs after the read-back, but no test plants a late audit entry holding the key, so that the order change is shown by a green run, not by a red one.

**Verification performed.** `test-class-rules.sh`, `test-storage.sh`, `test-mock.sh` (94 tests), `test-ci-config.sh`, `ci/checks.sh`: pass. Warm `ExampleTriage`, `Example` and `Install.Production`: pass. `release/standalone-bridge.sh` on lane C: all checks passed after the review patches (34 PASS, dummy key printed 0 times). Fresh `shard lane-a` forward (twice) and `--reverse`: 42 classes passed each, `STACK ...: project`, no `WARM` line. Footprint `git diff --stat` over the closed paths: empty. Spine lint: `ok: false` with the same four pre-existing low placeholder findings as at the baseline. The seven pinning mutations of the implement stage and three of the review pass were observed red and reverted (tree byte-identical by `shasum`). Nothing of this run is left running (`docker ps --filter name=e13s1i` is empty).

**Residual risks.**
- AC 9's wording "the spine lint reports `ok: true`" cannot hold on the base tree: the lint's placeholder heuristic flags template text in the spine's own examples (deferred above). The two rows are in and add no finding. The lead may restate the AC as "no new finding" (Rule 5, apply and report).
- `Ens.Config.DefaultSettings` refuses to save the unset `@{env:}` placeholder, so the no-key row is written by SQL (Design Notes 8).
- Footprint extensions to report: `src/ocutalon/cls/OcuTalon/Test/Bridge/Example.cls` and `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` (Task 9 lines only, ruled).
