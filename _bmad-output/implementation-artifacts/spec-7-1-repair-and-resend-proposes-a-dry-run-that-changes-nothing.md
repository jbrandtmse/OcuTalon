---
title: 'Repair and resend proposes a dry run that changes nothing'
type: 'feature'
created: '2026-10-27'
status: 'done'
baseline_revision: '2deb933f7a65815240340252db1854b82bd5cf63'
baseline_commit: '2deb933f7a65815240340252db1854b82bd5cf63'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      A dry run reads only each group's Seen set (the newest 1000 keys), so for an incident with more than 1000 failures the dry run's affected and resend counts are lower than the incident's Count, with nothing in the result saying so.
    evidence: |-
      Settle.SEENMAX caps FailureGroup.Seen at 1000 and the spec makes Seen the only source of targets. Only 50 orders are exercised; Story 7.4 measures 500.
    location: >-
      src/ocutalon/cls/OcuTalon/Fix/Kind/RepairResend.cls (DryRun)
    severity: medium
---

<intent-contract>

## Intent

**Problem:** Epic 5 stores a usable data-format diagnosis with `fixKind: repair_resend` and model-written `fixParameters` (field, source format, target format). Nothing checks those parameters against a fixed set, no fix kind exists, and `OcuTalon.Fix.Executor` is a stub, so nobody can work out what a repair would do. Story 7.2 needs the fixed targets and the `DryRun` JSON before it can raise the approval request.

**Approach:** Add the fix-kind contract `OcuTalon.Fix.Kind` and its one release-1 kind, `OcuTalon.Fix.Kind.RepairResend`, with reformatters registered in code (`OcuTalon.Fix.Reformat`). The kind's parameter check runs inside the bridge's validation of `OcuTalon.Watch.Msg.DiagnosisPayload`. It checks the field against the sample body of the evidence pack the diagnosis was given. Decide exposes that pack to the reply class through a new bridge API, `OcuTalon.Bridge.ReplyCheck`. `FixExecutor` answers a new area-internal request, `OcuTalon.Fix.Msg.DryRun`, with `OcuTalon.Fix.Msg.DryRunResult`: the target header ids and the `DryRun` JSON. The Fix area's new install step declares `%Ens_MessageResend:U` for the service role.

## Boundaries & Constraints

**Always:**
- The model picks only the kind and its parameters, and the kind validates them (AD-16). The reformatters are a fixed set in code: dates `YYYY-MM-DD`, `MM/DD/YYYY`, `DD/MM/YYYY`, `DD.MM.YYYY` and `YYYYMMDD`; numbers `1234.56`, `1234,56`, `1,234.56` and `1.234,56` (names written exactly, case-sensitive).
  - A value must match its source format exactly, with ASCII digits only (`[0-9]`, never `\d`, which matches other scripts' digits), at most 40 characters, and a date must be a real calendar date. Anything else is refused.
  - A number is converted as digit strings: no arithmetic and no rounding.
  - Input is never evaluated: no `Xecute`/`$Xecute`, indirection (`@`), `$ClassMethod`/`$Method`/`$Property` on names derived from the input, `$ZF` or SQL built from the input.
- The kind's check is the last check in `DiagnosisPayload.%OnValidateObject`, so every earlier refusal keeps its own reason. It fails closed: when no `ReplyCheck` is active, or its `Input` is not an evidence pack with a sample body, every `repair_resend` reply is refused.
- The dry run reads the failed messages only through `OcuTalon.Watch.Reader.Evidence`, the one namespace-switching reader (AD-3). It writes nothing: no row, no message other than its own response, no setting and no queue. It calls no model.
- A target is a header key (`h<id>`) from the `Seen` of the incident's groups whose message is still in status `Error`. Its scope (`OcuTalon.Watch.FailurePoller.Scope(superSession)`) must equal the incident's `OwnerRef`, and its field must read in the source format. Targets are listed in ascending header-id order. The example is the first target.
- The `DryRun` JSON has exactly the keys of `OcuTalon.Bridge.Data.ApprovalRequest.DRYRUNKEYS`. Code reads that parameter and never copies the list.
- `src/bridge/**`, comments included, names no OcuTalon package outside `OcuTalon.Bridge` (AD-2).
- The service role's grants come only from `Install.Step.Fix.Grants()`, built from each registered kind's `RESOURCES` in the tool form `resource:permission[,...]` and parsed by `Install.Step.Tools.Parse`. No role holds `%Ens_MessageEditResend`.
- `Fix.Msg.Execute` and `Fix.Msg.FixResult` keep their properties. `FixExecutor` keeps `Parameter STUB = 1` and answers every request but a `DryRun` with error 5003, writing nothing. Execute belongs to Story 7.3.
- Tests are `%UnitTest` classes under `OcuTalon.Test.Fix`, in the `lane-a` shard. Tests that touch the production or OCUORDERS run only on a throwaway stack, never on a slot. Each new message class commits its `Storage` block. Rule 14 applies: ASCII escapes, and comments that state the contract.

**Never:**
- No change to `IncidentManager`: Story 7.2 sends the `DryRun` at the with-fix notice and calls `Raise`.
- No new or changed property on `Incident`, `FailureGroup`, `FixRun`, `ApprovalRequest` or any other stored class.
- No `Recheck` or `Execute` implementation (7.3), `Reconcile`/`Sweep` (7.5), catalog key or mock scenario.
- No edit to an existing `Install/**` file, and no change to `OcuTalon.Bridge.Context`.
- No `[Language = python]`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Valid repair | `ReplyCheck` Input is a pack whose sample body has `OrderDate`; reply `repair_resend` `{OrderDate, MM/DD/YYYY, YYYY-MM-DD}` | `CheckReply` accepts; `Conclude` records a usable diagnosis | none |
| Unknown field | as above, `field` `ShipDate` (not a key of the sample body; matched exactly) | refused, naming the reply check; `Conclude` gives fallback `invalid` with no payload | the bridge's fallback |
| Bad format | `sourceFormat` `MM-DD-YY`; or source `MM/DD/YYYY` with target `1234.56` (different families); or source equal to target | refused / fallback `invalid` | same |
| Extra parameter | `fixParameters` holds `rounding` | refused at import (#9404, measured) / `invalid`; the kind's schema check also refuses an extra key in a parameters object | same |
| No pack | no `ReplyCheck` active, or its Input is not a pack, or the sample has no body | every `repair_resend` reply is refused; a no-fix diagnosis is still accepted | same |
| Fallback route (consumer) | a kind-invalid reply concluded for a fixture incident, then IncidentManager's answer handler | the incident stores `Fallback` 1, reason `invalid`, no cause or fix, and gets Epic 5's fallback notice (`incident.fallback`, `fallbackReason` `invalid`) | Epic 5's route |
| 50 orders | 50 in-scope failed orders, `OrderDate` `10/16/2026` | `Targets` holds the 50 ids ascending; DryRun `{affected 50, resend 50, leftOut 0, field "order date", before "10/16/2026", after "2026-10-16", itemNoun {"one":"order","other":"orders"}}`; snapshot unchanged; no mock request | none |
| Left out | 6 in-scope failed orders, two of whose bodies hold `2026/10/16` and `""` | affected 6, resend 4, leftOut 2; the example is the lowest target | none |
| Not counted | `Seen` also holds a failed order of another scope and a delivered (status 3) header | neither counted, nor a target, nor left out | none |
| Nothing readable | in-scope failed messages exist, none reads in the source format | OK; resend 0, `Targets` "", `before` and `after` "" | none (7.2 raises nothing) |
| Refused dry run | unknown or closed incident; unknown `FixKind`; `Parameters` not a JSON object or failing `CheckParameters` against the read messages' body; unreadable or not-current production; no in-scope failed header | `DryRunResult.Reason` holds a plain sentence (through `Bridge.Redact.Text`), `Targets` and `DryRun` empty | FixExecutor answers OK and changes nothing |
| Grants | a start on a fresh throwaway | `CheckUserPermission(OcuTalonService, %Ens_MessageResend, U)` = 1, W = 0, and `%Ens_MessageEditResend` U = 0 | the Roles step refuses forbidden resources |
| Other request | an `Ens.StringRequest` sent to `FixExecutor` | error 5003, no response, no log row (the stub oracle) | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `src/bridge/` or `ci/`.

- `Fix/Executor.cls`: a 14-line stub (`STUB = 1`; `OnMessage` returns `$$$NotImplemented`). The production item `FixExecutor` (`Production.cls` L44, PoolSize 1). The stub oracle is in `Test/Install/Production.cls` L628 (stub 1) and L149-169: a STUB class's `OnMessage(Ens.StringRequest)` answers code 5003, gives no response and writes no log row.
- `Fix/Msg/Execute.cls`, `Fix/Msg/FixResult.cls`: Story 5.5's messages, which stay fixed. `Test/Watch/Lifecycle.cls` `TestFixMessages` L737 names only these two. For a new message class, follow their pattern: `Extends Ens.Request`/`Ens.Response`, no `SessionRef`, a committed `Storage Default`.
- `Watch/Msg/DiagnosisPayload.cls`: `%OnValidateObject` L59 holds the existing pure checks and the `FIXKINDS` parameter, which only this class reads. `Watch/Msg/FixParameters.cls` imports `field`/`sourceFormat`/`targetFormat`. Measured on slot A: an unknown key fails import with #9404, and `%JSONExportToString` omits an empty property.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: `CheckReply` L545 (`%JSONImport` then `%ValidateObject`, exceptions caught). `Conclude` L739 calls `Interpret` L807, which calls `CheckReply` at L814 and validates again after the filter at L842, only when the class has `FILTERED`. Both checks run in Decide's job, where no `Bridge.Context` exists: the runner job begins it (`Adapter/Agent.cls` L318). The class doc lines L42-47 describe the check.
- `src/bridge/cls/OcuTalon/Bridge/Context.cls`: the sibling of the new `ReplyCheck`: `Begin`, `End`, `Active`, `Current`, `Put`, kept in the process-private `^||OcuTalonBP.Context`. Read by the gate, the tools, `Core.Commands.Submit` (origin `tool` when active) and `Test/Bridge/ProbeTool.cls`, which snapshots `FIELDS`.
- `Watch/EvidencePack.cls`: `FORMAT`, `INPUTLINE`, `Scope` L37, `Read` L49 and `Input(pack)` L232 (`INPUTLINE _ $C(10) _ pack.%ToJSON()`). The pack's `sample.body` holds the stored datatype properties of the sample's message class, as `Reader` reads them, with keys kept and sensitive values redacted. It is in `Test/Bridge/CodeRules.cls` WATCHREADS, so it may call only listed callback classes.
- `Watch/IncidentManager.cls` `Diagnose` L367 stores `SampleHeaderId` and the code noun, then sends Decide `Input = EvidencePack.Input(pack)`. `Answered` L406 stores a usable diagnosis or a fallback, then the notice step. This story only reads it.
- `Watch/Reader.cls` `Evidence(ns, production, item, keys, .snapshot)` L190. Each `snapshot.failures[]` holds `headerId`, `superSession`, `targetConfigName`, `bodyClass`, `status` (display text: `Error` for 8), `isError` and `body{}` (datatype properties, each value cut at `VALUEMAX` 1000). Outcomes are `read`, `unreadable` or `not_current`.
- `Watch/FailurePoller.cls` `Scope(superSession)` L132 returns the session whose `TraceRef` it is, else `instance`. `Checks.Process` calls it already. `Watch/ItemNoun.cls` `For(bodyClass)` gives the code noun.
- `Data/Incident.cls`: `Ref`, `OwnerRef`, `Namespace`, `Production`, `State`, `ItemNoun` (JSON `{one, other}`). `Data/FailureGroup.cls`: `OfIncident(ref)`, `ItemName`, `Seen` (comma-separated `h<id>`/`l<id>`, the newest 1000). In product code only `IncidentManager` writes them (a CodeRules scan); tests may.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` L9 `DRYRUNKEYS = "affected,resend,leftOut,field,before,after,itemNoun"`.
- `Msg/Catalog/Watch.cls` L78 `incident.withFix` renders the `field` slot as is: the fixtures use `"field": "order date"` (`Test/Msg/Catalog.cls` L1232). So the dry run's `field` is the property name in lower-case words.
- `Install/Step.cls` (`Grants()` entries `{role, resource, permission}`). `Install/Registry.cls` `Areas` discovers every non-abstract `OcuTalon.Install.Step.<Name>`, and `Declared` collects them, so a new area needs no registry edit. `Install/Step/Tools.cls` `GrantsOf`/`Parse` is the sibling. `Install/Step/Roles.cls` `FORBIDDEN` L13 and `Add` refuse forbidden or unknown resources. `Install/Step/Users.cls` `#SERVICEROLE` = `OcuTalonServiceRole`. Measured on slot A: `%Ens_MessageResend` exists.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` `Resources(value, where)` L200 is the shared parser. `MissingPrivilege` L228 is Story 7.3's model for the executor's check.
- `Agent/Diagnosis.cls` INSTRUCTIONS L35 and L41-42 name `fixParameters` but no registered format. `Test/Agent/Instructions.cls` `TestDiagnosis` checks substrings only.
- `Demo/Orders/Partner.cls` `Send(count, dateFormat, traceRef, orderDate)` L83 (formats `YYYY-MM-DD`, `MM/DD/YYYY`). `Demo/Orders/PartnerOrder.cls` holds `OrderNumber`, `OrderDate`, `Sku` and `Quantity`.
- Test helpers to reuse:
  - `Test/Watch/Case.cls`: `Ready`, `Session`, `Fail(count, traceRef)` L545, `WaitFailed` L578, `HeaderIds` L591, `FixtureHeader` L644, `Top` L534, `RowCount` L450 (BackgroundCheck rows), and clean-up of OCUORDERS headers, bodies and incident rows. `SendTick` L475 shows `Ens.Director.CreateBusinessService` with `SendRequestSync`; `SendBatch` L970 sends from `SimMailboxIn` with `%SuperSession` set.
  - `Test/Watch/Evidence.cls` `Fixture(owner, ids, ...)` L148: the live fixture incident and group, to lift into `Case`.
  - `Test/Watch/IncidentProbe.cls`: `Answer(ref, response)` L94; `Sent` records Notifications. Usage pattern: `Test/Watch/Diagnose.cls` `TestRefusedRequest` L222.
  - `Test/Contract/Mock.cls`: `LogMark()` L365, `LogSince(mark, .entries)` L378, `LOGFILE` `/opt/ocutalon/mock-log/requests.jsonl`.
  - `Test/Bridge/Source.cls`: `Text`, `CodeLines` and `Matches`, the static-scan helper.
  - `Test/Bridge/Decide.cls`: `NewRequest`/`NewReply`, the `Conclude` helper L2905, `RowOf`.
- Tests that this story's shared-surface change touches:
  - `Test/Watch/Payload.cls` `Check`/`Usable` L19-35: `CheckReply` with no context.
  - `Test/Bridge/Decide.cls` `TestFilterDiagnosis` L611-645: formats "a"/"b" and a request with no pack.
  - `Test/Agent/Decide.cls` `TestSnapshotDiagnosis` L439 already sends `Input(pack)` built from the recorded snapshot, whose sample body has `OrderDate`.
  - `Test/Watch/Diagnose.cls` `TestDemoDiagnosis` uses a live pack of real orders.
- `ci/units.sh` L17 lists the `lane-a` shard: `Agent Bridge Checks Install Tools Digest Watch`.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure, then record the results in this spec's `## Verification`):
  - On the stage's first fresh throwaway, list the `SourceConfigName` of each new OCUTALON session header over a 70-second idle window. Expected (inference): only `HeartbeatIn` sessions. Any other source joins `Snapshot`'s allowance with a named reason.
  - Time `Snapshot.Take` on a stack after the `lane-a` shard. Expected (inference): seconds.
- `Fix/Reformat.cls` (new) -- Holds the fixed registry above (its `Names()` and `Family(name)`, which is `date`, `number` or "") and `Convert(value, source, target, .result) As %Status`. Every rule is in the Always list:
  - dates are parsed by fixed positions and checked with `$ZDATEH(yyyy-mm-dd, 3, , , , , , , -1)`;
  - numbers are split into sign, integer digits and fraction digits, then rendered with the target's group and decimal separators.
  -- Why: AD-16's registered reformatters.
- `Fix/Kind.cls` (new, abstract) -- Defines the contract:
  - parameters `NAME`, `PARAMETERS` (the parameter schema: its names, comma-separated, each a required non-blank string), `RESOURCES` (tool form) and `KINDS = "OcuTalon.Fix.Kind.RepairResend"` (the fixed set);
  - `Classes() As %List` (each listed class that is compiled and extends `Fix.Kind`), `Names()` and `ForName(name)`;
  - `Check(name, parameters As %DynamicObject, fields As %DynamicArray) As %Status`: an unknown kind is an error, else the kind's `CheckParameters`;
  - `CheckParameters`: the base checks the schema (exactly the `PARAMETERS` keys);
  - `DryRun(incident As OcuTalon.Data.Incident, parameters, Output targets As %String, Output dryRun As %DynamicObject)`, `Recheck(incident, parameters, targets, Output passed As %String, Output skipped As %DynamicArray)` and `Execute(incident, parameters, targets, Output result As %DynamicObject)`: each returns `$$$ERROR($$$NotImplemented)` in the base.
  -- Why: AD-16's contract. Story 7.3 implements `Recheck` and `Execute` and keeps their first three arguments.
- `Fix/Kind/RepairResend.cls` (new) -- Sets `NAME = "repair_resend"`, `PARAMETERS = "field,sourceFormat,targetFormat"` and `RESOURCES = "%Ens_MessageResend:U"`.
  - `CheckParameters`: the schema (`##super`), then the field is a member of `fields` (exact match), both formats are registered, they share a family and they differ.
  - `FieldWords(name)`: the words of a property name, lower-cased, split at case changes, with `_`, `-` and `.` as spaces (`OrderDate` gives `order date`, `PONumber` gives `po number`).
  - `DryRun`, as the Always list and the matrix say:
    - the header keys come from each group's `Seen` (`FailureGroup.OfIncident`), with one `Reader.Evidence` call per group's `ItemName`;
    - it calls `CheckParameters` against the body keys of the first in-scope failed message;
    - `itemNoun` comes from `Incident.ItemNoun`, else `Watch.ItemNoun.For` of the first in-scope failed message's `bodyClass`;
    - an outcome other than `read`, or no in-scope failed header, is an error status.
  -- Why: AC 1, AC 3, AC 4.
- `src/bridge/cls/OcuTalon/Bridge/ReplyCheck.cls` (new) -- Holds the request whose reply Decide is checking: `FIELDS = "Kind,ItemId,OwnerRef,Input"`, `Begin(request As OcuTalon.Bridge.Msg.Request) As %Status` (refuses anything else), `End()`, `Active()` and `Value(name)` ("" for no check or an unknown name), kept in a process-private global. `Begin` first clears every earlier value, so nothing of an earlier request survives it. Its comments name no OcuTalon package outside the bridge. -- Why: the validation seam (Design Notes V1, U-125's condition).
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `Interpret` begins `ReplyCheck` from `request` before `CheckReply`. It ends it on every exit after the check run again, an exception included (wrap the body). Update the class doc and `CheckReply`'s doc: a reply class's `%OnValidateObject` may read the request through `ReplyCheck`. -- Why: AC 2.
- `Watch/EvidencePack.cls` -- `FromInput(text) As %DynamicObject` is the inverse of `Input`: the pack when the first line is `INPUTLINE` and the rest is a JSON object of `FORMAT`, else "". It calls no unlisted class (WATCHREADS). -- Why: the field check reads the pack the diagnosis was given.
- `Watch/Msg/DiagnosisPayload.cls` -- Removes `FIXKINDS`; a `data_format_change`'s fix kind must satisfy `##class(OcuTalon.Fix.Kind).ForName(..FixKind) '= ""`, and the error names `Fix.Kind.Names()`.
  - Last in `%OnValidateObject`, with a `FixKind`: the fields are the keys of `EvidencePack.FromInput(##class(OcuTalon.Bridge.ReplyCheck).Value("Input")).sample.body`, or `[]`. The parameters are `FixParameters` exported to a `%DynamicObject`. Then `Fix.Kind.Check(..FixKind, parameters, fields)`, and its error is the payload's.
  - Update the class doc.
  -- Why: AC 2, AD-7, AD-8.
- `Agent/Diagnosis.cls` -- Adds one INSTRUCTIONS bullet: for `repair_resend`, `field` is a property of the sample's body, written exactly as the pack names it; `sourceFormat` and `targetFormat` are two different names from one list, written exactly (the dates and the numbers); any other value makes the reply invalid. It holds no `{{`. -- Why: the model's choice is limited to the registered set (AC 2; Story 9.5's gate).
- `Fix/Msg/DryRun.cls` (new, `Ens.Request`) -- Properties `IncidentRef` (`MAXLEN` 22), `FixKind` (32) and `Parameters` (`MAXLEN` "", a JSON object). Commit its storage. -- Why: Execute stays fixed (7.3's AC).
- `Fix/Msg/DryRunResult.cls` (new, `Ens.Response`) -- Properties `IncidentRef` (22), `Targets` (`MAXLEN` "", comma-separated ascending header ids), `DryRun` (`MAXLEN` "", JSON) and `Reason` (`MAXLEN` 1000, "" when worked out). Commit its storage.
- `Fix/Executor.cls` -- `OnMessage` hands a `Fix.Msg.DryRun` to `DryRun(request, .response)`, which builds the matrix's result: it opens the incident by `Ref`, resolves the kind, parses `Parameters` and calls the kind's `DryRun`. Any other request gets 5003 as now. Keep `STUB = 1` and update its doc lines. -- Why: AC 3, the Integration AC.
- `Install/Step/Fix.cls` (new; not in `Registry.Order`, so it only declares) -- `Grants()` returns `GrantsOf(##class(OcuTalon.Fix.Kind).Classes())`. `GrantsOf(kinds As %List)` gives one `{role: Users.#SERVICEROLE, resource, permission}` per pair of each kind's `RESOURCES`, parsed by `Install.Step.Tools.Parse(value, kind)`, each pair once. -- Why: AC 1, AD-23, AD-24.
- `ci/units.sh` -- Adds `Fix` to the `lane-a` areas (the lane's own entry). -- Why: Rule 21: a new `Test.<Area>` must join a shard.
- `Test/Watch/Case.cls`, `Test/Watch/Evidence.cls` -- Move `Fixture` from `Evidence` to `Case` unchanged, adding a trailing optional `fields As %DynamicObject = ""` whose members are set on the incident before its save. `Evidence` uses the inherited one.
- `Test/Watch/Payload.cls` -- `OnBeforeOneTest` begins `ReplyCheck` with a fixture request whose Input is `EvidencePack.Input` of a pack with sample `bodyClass` `OcuTalon.Demo.Orders.PartnerOrder` and body `{OrderNumber, OrderDate "10/16/2026", Sku, Quantity}`. `OnAfterOneTest` ends it. Update the class doc. Every existing case keeps its own reason.
- `Test/Bridge/Decide.cls` `TestFilterDiagnosis` -- Its request carries the same pack Input, and its fix parameters are `OrderDate`/`MM/DD/YYYY`/`YYYY-MM-DD`. It still asserts the ten filter calls in `FILTERED` order. The probe's `[f] ` prefix now fails the re-check, so assert fallback `invalid` and no payload. Move the assertions on the stored, filtered payload to a `partner_outage` reply (cause, element, evidence, noun, reason).
- `Test/Bridge/ReplyCheck.cls` and `Test/Bridge/ProbeReplyCheck.cls` (new) -- The probe extends `Bridge.Msg.DecisionPayload` with one `FILTERED` property, so Decide checks it twice. It records `ReplyCheck.Active()` and its four values at each validation, and throws on request.
  - `Begin` refuses a non-Request; `Value` of an unknown name is "".
  - `Decide.Conclude` with the probe: both checks see the request's values, and `Active()` is 0 after it returns, also for an invalid reply and a throwing check.
  - U-125's condition, in one job: (1) the error path: a check that throws inside `Interpret` leaves `Active()` 0 and every `Value` "" afterwards; (2) a second decision after the first: `Conclude` for request A, then `Conclude` for request B (different `ItemId`, `OwnerRef` and `Input`) in the same process, and B's checks see only B's values, never A's; and `Begin` for B after a `Begin` for A with no `End` between holds only B's values.
- `Test/Fix/Reformat.cls` (new, pure) -- Every registered format:
  - converts a table of valid inputs exactly (all pairs within a family, sign, grouping, fractions, leap day);
  - refuses wrong separators, padding, length > 40, `2026-02-30`, `T`, Arabic-Indic digits and empty values;
  - refuses injection-shaped inputs (`@^OcuTalonTest("FixSentinel")`, `$$TOUCH^ZzFix`, `"_$Increment(^OcuTalonTest("FixSentinel"))_"`, `##class(...)`, `$ZF(-100,...)`), with `^OcuTalonTest("FixSentinel")` left undefined;
  - and a static scan (`Test.Bridge.Source.CodeLines`) of `Fix.Reformat` and `RepairResend` finds no `Xecute`, `$Xecute`, `@`, `$ZF(`, `$ClassMethod(`, `$Method(` or `$Property(`.
- `Test/Fix/Kind.cls` (new, pure) and `Test/Fix/ZzKind.cls` (a fixture kind, not in `KINDS`) --
  - The contract: the members and parameters, `Classes()` exactly `RepairResend`, `ForName`, `Names`, and `ZzKind` unknown.
  - `RepairResend`'s parameters; the `CheckParameters` matrix; `FieldWords`.
  - `Install.Step.Fix.Grants()` is exactly the one service-role pair, and `GrantsOf(ZzKind)` gives its pairs.
  - No registered kind declares a `Roles` `FORBIDDEN` resource.
  - Each `Reformat.Names()` entry appears quoted in `Agent.Diagnosis`'s INSTRUCTIONS.
  - The validation rows of the matrix through `Decide.CheckReply` with `ReplyCheck` begun, and through `Decide.Conclude` (fallback `invalid`, no payload). The test removes the Decision rows it made.
- `Test/Fix/Snapshot.cls` (new helper, no Test methods; 7.3 and 7.4 reuse it) -- `Take(namespaces As %List, Output snapshot)` first waits up to 10 s for every queue to be empty, then reads, in each namespace:
  - every `Ens.MessageHeader` row (all columns);
  - the stored properties of each of those headers' bodies;
  - each production definition (`Ens.Config.Production` XML, items and settings), its state, and the `Ens_Config.DefaultSettings` rows;
  - the queue counts (`Ens.Queue_Enumerate()`).
  `Diff(before, after, allowedSessions)` gives one line per changed or missing item, and per new header outside OCUTALON's allowed sessions and `HeartbeatIn` sessions.
- `Test/Fix/DryRun.cls` (new; extends `Test.Watch.Case`, throwaway only) --
  - `TestFiftyOrdersChangeNothing`. Set-up:
    - assert that no BackgroundCheck row watches Orders;
    - session S: `Fail(50, S.TraceRef)` and `WaitFailed(50)`;
    - `Fixture(S, ids, , , , {"ItemNoun": "{\"one\":\"order\",\"other\":\"orders\"}"})`;
    - assert the mock log file exists;
    - `LogMark` and `Take` over OCUTALON and OCUORDERS.
    Then send the `DryRun` from `SimMailboxIn` (with `%SuperSession` = S's TraceRef) with `SendRequestSync("FixExecutor", ..., 60)`, take the snapshot again, and assert: `Diff` empty except for the request's own session, `LogSince` empty, and the matrix's targets and values with the key set equal to `DRYRUNKEYS`.
  - `TestLeftOutAndScope`: the two matrix rows. The test edits only its own orders' bodies.
  - `TestRefusals`: each refused row.
  - `TestServiceUserMayResend`: the grants row.
  - `TestInvalidRepairTakesTheFallbackRoute`: for a fixture incident, `Conclude` (`DiagnosisPayload`, a pack Input) with a bad format, then `IncidentProbe.Answer` gives the fallback row and one `incident.fallback` Notification with `fallbackReason` `invalid`. A valid repair on a second incident is stored with no notice.

**Acceptance Criteria:**
- AC 1: Given the package is compiled, when `OcuTalon.Test.Fix.Kind` runs, then:
  - `OcuTalon.Fix.Kind` declares `DryRun`, `Recheck`, `Execute` and `CheckParameters` against fixed targets, plus `NAME`, `PARAMETERS` and `RESOURCES`;
  - its registered kinds are exactly `RepairResend` (`repair_resend`, `field,sourceFormat,targetFormat`, `%Ens_MessageResend:U`);
  - `Install.Step.Fix.Grants()` is generated from those `RESOURCES`;
  - and on a fresh throwaway the started service user may use `%Ens_MessageResend` and not `%Ens_MessageEditResend`.
- AC 2: Given a reply proposing `repair_resend`, when the bridge validates it against `DiagnosisPayload` (`Decide.Conclude`), then only a field of the pack's sample body and two different registered formats of one family pass. Any other value, an extra parameter, or no pack makes it `invalid`, and IncidentManager handles it by Epic 5's fallback route.
- AC 3: Given a validated repair for an incident's failure group, when a `DryRun` message reaches the item `FixExecutor` by name (as IncidentManager will send it), then `DryRunResult` carries the ascending in-scope target ids and the `DryRun` JSON with exactly `DRYRUNKEYS`, and left-out messages are counted in `leftOut`.
- AC 4: Given 50 failed orders made through `Partner.Send` on a throwaway, when the dry run runs, then no header, body, production or item setting, or queue in OCUTALON or OCUORDERS changed (apart from the dry run's own request and response, and any scheduled `HeartbeatIn` session that Task 0 confirms), the mock logged no request, and the values are those of the matrix's 50-orders row.
- AC 5: Given the registered reformatters, when `OcuTalon.Test.Fix.Reformat` runs, then every format converts its valid inputs exactly, refuses every non-matching value, and never evaluates input.
- AC 6 (owner U-125's condition): Given `OcuTalon.Bridge.ReplyCheck`, when `Decide.Interpret` validates replies in one production job, then `Begin` clears any earlier value, `End` runs on every exit of `Interpret`, errors included, and so a context left by one decision can never validate another decision's reply. `OcuTalon.Test.Bridge.ReplyCheck` pins both cases: the error path, and a second decision after the first in the same job.

## Spec Change Log

- 2026-10-27, spec gate (lead): owner decision U-125 (through the Contest Planner, answer_ref 2026-10-27T22:08:24Z#378) chose (a) for both spine questions; AD-16 and the dependency diagram's "Bridge shared" node are amended in the spine, and the Diagnosis Conventions row names the kind check. U-125's condition on `ReplyCheck` added as AC 6, with its task lines (`Begin` clears earlier values; the error-path and second-decision tests).

## Review Triage Log

### 2026-10-27 - Review pass
- verdicts: 30 findings - high 0, medium 4, low 24, false 2, maybe-false 0
- findings:
  - `[medium]` `[defer]` Blind: a dry run reads only each group's Seen (newest 1000 keys), so an incident with more than 1000 failures is under-counted - the spec names Seen as the source; recorded in `deferred:`; Story 7.4 measures the large dry run.
  - `[low]` `[reject]` Blind: fields are checked against the first in-scope message only - messages without the field are counted as left out, so no false all-clear; a mixed-class incident is not a reachable demo case.
  - `[low]` `[patch]` Blind: a missing or non-object `failure.body` ends in a thrown dry run - `RepairResend.DryRun` now takes `{}` for such a body.
  - `[low]` `[patch]` Blind: exception text (code, location) reaches `Reason` - the catch path now sets one fixed sentence.
  - `[low]` `[reject]` Blind: the INSTRUCTIONS have no way out for a field format outside the list - the same text names "use repair_resend only when ..." and the other categories exist; the reply is then `invalid` and falls back safely.
  - `[low]` `[reject]` Blind: MM/DD/YYYY and DD/MM/YYYY both read values with day and month up to 12 - inherent to the formats; the approval shows the first target's before and after.
  - `[low]` `[reject]` Blind: `Kind.Classes` drops a bad KINDS entry silently - `Kind.TestContract` pins `Classes()` to exactly RepairResend, so a typo is red.
  - `[low]` `[patch]` Blind: `Test.Fix.Kind` names a method that does not exist, and nothing ran `Registry.Declared("Grants")` - the header is corrected and `TestGrants` asserts that the Fix area's grant is among the declared grants.
  - `[low]` `[reject]` Blind: an exception in the post-filter check escapes `Conclude` - that structure is the prior behaviour of `Interpret`; `ReplyCheck` is ended and the exception thrown on (U-125); `CheckFix` has no throwing input.
  - `[low]` `[patch]` Blind: `Case.SampleOrder` does not assert its save - it now asserts and does not record an empty id.
  - `[low]` `[patch]` Edge: `Reason` carries raw error text on the catch path - same root cause and fix as the Blind row.
  - `[low]` `[patch]` Edge: an `ItemNoun` that is valid JSON but not an object aborts the dry run - the noun test now requires a dynamic object.
  - `[low]` `[reject]` Edge: header id 0 could become a target - header keys come from real headers, and `Reader.Evidence` answers only existing ids.
  - `[low]` `[reject]` Edge: a redacted or cut field value is left out with no hint - it is counted as left out, which is the contract.
  - `[low]` `[reject]` Edge: an incident in a state other than open or closed still gets a dry run - the dry run is read-only; the states are Story 7.2's.
  - `[low]` `[reject]` Edge: the output filter may alter the fix parameters before the second check - the repair is then refused as `invalid`, which is the safe failure.
  - `[false]` `[reject]` Edge: a nested `Interpret` clears an outer ReplyCheck - Decide never nests `Interpret`, and U-125 requires `Begin` to clear.
  - `[low]` `[reject]` Edge: `TestFilterDiagnosis` lost its assertions on the stored filtered fix texts - the spec's task directs the move to a partner_outage reply; the filter-call order is still pinned.
  - `[low]` `[patch]` Edge: the claim "Reason is one plain sentence" fails on the catch path - same fix as above.
  - `[medium]` `[patch]` Verification gap: the incident-noun versus body-class choice of `itemNoun` is not pinned - `TestNothingReadable` now gives the incident a different noun; mutation recorded.
  - `[medium]` `[patch]` Verification gap: ascending order and the merge of groups are not pinned (every fixture is ascending and single-group) - new `TestTargetsAscendAcrossGroups`; mutation recorded.
  - `[medium]` `[patch]` Verification gap: `Snapshot.Diff` is exercised for the headers category only - new pure `Test.Fix.SnapshotDiff` (every category, the allowed sessions, the heartbeat rule) with two mutations, and the 50-orders test asserts that the request's session holds exactly two headers; reading `OcuTalon.Data` tables in `Take` is not in the spec and is not added.
  - `[low]` `[patch]` Verification gap: three DryRun tests pass silently without a response - each asserts the response first.
  - `[low]` `[reject]` Verification gap: the 50-orders test relies on no BackgroundCheck row watching Orders - the spec's set-up asserts it, so the dependency is a visible check.
  - `[low]` `[reject]` Verification gap: `Snapshot.Take` goes on after 10 s of non-empty queues - a leftover would show as a diff line (a flake, not a vacuous pass).
  - `[low]` `[patch]` Verification gap: the stale method name in `Test.Fix.Kind` - same fix as the Blind row.
  - `[low]` `[reject]` Verification gap: the dropped `TestFilterDiagnosis` fix-text assertions - same as the Edge row.
  - `[low]` `[reject]` Verification gap: the static scan covers only `Reformat` and `RepairResend` - the spec lists them; the other classes call `$ClassMethod` only on names from the fixed KINDS list.
  - `[low]` `[reject]` Verification gap: `Interpret` ignores the status of `ReplyCheck.Begin` - the argument is a Request by type, so Begin cannot refuse there.
  - `[false]` `[reject]` Intent: nothing shows that the live runner's Input starts with the pack line - `Agent.Decide.TestSnapshotDiagnosis` (through the runner) and `Watch.Diagnose.TestDemoDiagnosis` (a live pack) pass with a valid repair.

## Design Notes

**V1. The validation seam.** `CheckReply` validates with `%ValidateObject()` in Decide's job, which has no bridge context. The check needs the message class's fields.
- Rejected: beginning `Bridge.Context` in Decide. Its `Active()` means "inside a model call" to the gate, the tools and `Commands.Submit`, and adding `Input` to its `FIELDS` ripples into every probe that snapshots them.
- Rejected: reading the incident's sample header live from the validation. That is a namespace read in Decide's job, it would fail recorded-snapshot (eval) incidents and pure tests, and it needs the incident.
- Chosen: `ReplyCheck` exposes the request. The fields are the keys of the pack's sample body, which are exactly what the model saw, whether the pack is live or recorded.
- Cost: `Test.Watch.Payload` and `Test.Bridge.Decide.TestFilterDiagnosis` change (shared surface). `Test.Agent.Decide` and `Test.Watch.Diagnose` stay green.
- The rule fails closed.

This is a veto item for the spec gate, because it adds a bridge API.

**U-125 (owner decision, 2026-10-27, through the Contest Planner; answer_ref 2026-10-27T22:08:24Z#378).** The owner chose (a) for both spec-gate questions:
- Q1: AD-16's "The Fix area's messages" bullet now also names `OcuTalon.Fix.Msg.DryRun` (`IncidentRef`, `FixKind`, `Parameters`) and `OcuTalon.Fix.Msg.DryRunResult` (`IncidentRef`, `Targets`, `DryRun`, `Reason`) as the dry-run ask from `IncidentManager` to `FixExecutor`. The two new message tables are accepted.
- Q2: `ReplyCheck` is added to the "Bridge shared" node of the dependency diagram.
- **Condition (binding on implement):** `Begin` clears any earlier value; `End` runs on every exit of `Decide.Interpret`, errors included; so a context left by one decision can never validate another decision's reply in the same production job. A test pins both cases: the error path, and a second decision after the first in the same job (AC 6).
- The spine edits carry `[AMENDED 2026-10-27, Story 7.1, Epic 7 runner, orchestrator, owner U-125]`. The Diagnosis Conventions row also names the kind check (light path).

**Spec-gate rulings (lead, decide):** V1's design as planned (the spine listing is U-125's); V2's registered set as planned; V3 `STUB = 1` until 7.3.

**V2. The registered set and the names the model sees** (Always, first bullet). This is decided in-stage: the AC says "a fixed set". Number names are written as examples because a comma list cannot hold them. The ruling may change members. The tests read `Reformat.Names()`.

**V3. `FixExecutor` keeps `STUB = 1`** until Story 7.3 builds Execute, so Test.Install.Production's oracle stays unchanged.

**Decided in-stage (implement):**
- `Targets` (the `DryRunResult` field and the kind's `targets` output) are the plain header ids, comma-separated and ascending (`101,102`), not `h<id>` keys; the `h<id>` keys are only what `Seen` holds.
- `EvidencePack.FromInput` ignores text after the pack's first JSON object (found by a string-aware brace scan). `Test.Agent.Decide`'s fixture appends ` (test <ref>)` to every input, and a strict parse would have made `TestSnapshotDiagnosis` refuse its repair. The fields still come from a genuine pack: no pack, another first line, another format or an unclosed object still gives "" and refuses every repair.
- The date range is that of `$ZDATEH` (1840-12-31 to 9999-12-31); `0001-01-01` is refused. A number has an optional minus sign, whole digits (grouped in threes where the format groups, no leading zero but a lone 0) and an optional fraction of one or more digits after the decimal separator; a `+`, an exponent and a trailing separator are refused. Two equal formats are refused by `Convert` as well as by the kind.
- `Reformat` has `DATES` and `NUMBERS` parameters (vertical-bar lists) and no `NAMES`, because a comma list cannot hold `1234,56`. `Names()` returns a list.
- `Install.Step.Fix.Grants()` has no role-only entry (the Tools step declares the role): it is exactly the one `%Ens_MessageResend:U` pair.
- `Decide.Interpret` is a wrapper (`ReplyCheck.Begin`, `Try`, `End` on both exits, the exception thrown on) around the previous body, now the private `Judge`.
- `Snapshot.Diff` allows a new header whose session is in `allowedSessions` or whose session a new `HeartbeatIn` header started (the answer of `Checks` has another source in the same session).

**Schema changes:** none to existing classes. There are two new message classes, which the lead's brief authorizes. `ReplyCheck` is not persistent.

**Governing ADs:**
- AD-1: the item is reached by name.
- AD-2: bridge boundary.
- AD-3: only `Reader` switches namespace; `Executor` switches only to resend (7.3).
- AD-4: scope.
- AD-7: `ReplyClass`; static INSTRUCTIONS with no `{{`.
- AD-8: the bridge alone decides `invalid`.
- AD-11 and AD-16: `DryRun` keys, kinds and `RESOURCES`.
- AD-15 and AD-33: only `IncidentManager` writes incident rows.
- AD-22: tests, the mock log, throwaways.
- AD-23 and AD-24: `Grants()` composed by Roles; the forbidden list.
- AD-29: Lane A; `ci/units.sh` by region.
- AD-31: the bridge reaches the host only through extensions (`ReplyCheck` is read by the host).

Conventions: "Tool resources" (the tool form; one permission letter per check), "Diagnosis", "Approval requests" (`DryRun` is the fix row's contract column), "Messages", "Redaction".

**Integration ACs, Consumes, Consumed-by:**
- In-story consumers, each observed from outside the module:
  - Decide's validation consumes `ReplyCheck` and `Fix.Kind`, and IncidentManager produces Epic 5's fallback notice (`TestInvalidRepairTakesTheFallbackRoute`);
  - the item `FixExecutor` consumes `RepairResend.DryRun` (`TestFiftyOrdersChangeNothing`);
  - the Roles step consumes `Install.Step.Fix.Grants` (`TestServiceUserMayResend`).
- Consumes:
  - 5.4: `DiagnosisPayload`, `EvidencePack.Input`, the stored pack Input;
  - 5.3: the incident and group rows, `Seen`, `FailurePoller.Scope`;
  - 5.1: `Reader.Evidence`;
  - 3.1: `Tools.Parse`/`Gate.Resources`, `Roles`, `Users.SERVICEROLE`;
  - 0.4: `DRYRUNKEYS`;
  - 0.10: `Partner.Send`;
  - 0.11: the mock log.
- Consumed-by:
  - 7.2: IncidentManager sends `DryRun` at the with-fix notice, calls `Raise` with `Targets`/`DryRun`, and stores the kind and parameters on the row (its storage decision). A later request excludes earlier targets.
  - 7.3: `RepairResend.Recheck`/`Execute`; the resource check; `Snapshot` for "originals unchanged". The dry run does not look for earlier resends: "not resent" is 7.3's re-check.
  - 7.4: the 500-message dry run.
  - 9.5: "parameters that pass the kind's validation" through `Fix.Kind.Check`.
  - 14.1: `Fix.Kind.Classes()` and `RESOURCES` rows.
  - Step 5's rollback kind joins `KINDS`.

**Extend, don't copy (Rule 2):**
- `Install.Step.Fix.GrantsOf` follows `Tools.GrantsOf` and reuses `Tools.Parse`. The discovery differs (the registered kinds against the toolsets).
- `ReplyCheck` is separate from its sibling `Bridge.Context` (V1).
- The test fixture moves `Evidence.Fixture` to `Case`.
- Reused as they are: `FailurePoller.Scope` (as `Checks.Process` does), `Reader.Evidence` (no new reader mode), `Watch.ItemNoun.For`, `Mock.LogMark`/`LogSince`, and `Case.Fail`/`WaitFailed`/`HeaderIds`.
- `DiagnosisPayload` reads kind names from `Fix.Kind` (one list).

**Ledger inbox:** none.

**Measured on `ocutalon-slot-a` (build 154, read-only, 2026-10-27):**
- the nested unknown key → #9404;
- empty properties are left out of the export;
- `$ZDATEH("2026-02-30",3,,,,,,,-1)` and `"T"` give -1;
- `%Ens_MessageResend` and `%Ens_MessageEditResend` exist;
- `Ens.Queue_Enumerate()` runs.

**(inference):** the idle OCUTALON traffic and the snapshot time are Task 0. Running `Reader.Evidence` over 500 keys at an acceptable speed is 7.4's measurement.

**Footprint extensions** (none contended; Rule 11(b)):
- `Watch/Msg/DiagnosisPayload.cls`, `Watch/EvidencePack.cls`;
- `Agent/Diagnosis.cls`;
- `Test/Watch/{Case,Evidence,Payload,Incidents}.cls`, `Test/Bridge/{Decide,ReplyCheck,ProbeReplyCheck}.cls`;
- `ci/units.sh` (`shared_by_region`, the `lane-a` entry);
- `Install/Step/Fix.cls`, a new file inside Epic 15's `Install/**`, as the brief allows. No existing `Install/**` file changes: `Registry` discovers areas.

**Spine notes for the lead (Rule 20; candidates only):**
- AD-16's list of Fix messages gains `DryRun` and `DryRunResult`.
- The invariant's domain arrows gain Fix → `Watch.Reader` (AD-3 forces it, and the AC names it) and Fix → `FailurePoller.Scope` (as Checks already has).
- The "Bridge shared" list gains `ReplyCheck`.
- The "Diagnosis" row: the kind checks the fix parameters against the pack's sample body.

**Size:** one story is planned (`multiple-goals`, `oversized`). If the lead prefers to split it, the seam is 7.1a (kind, reformatters and validation: AC 1, AC 2, AC 5) and 7.1b (`FixExecutor`'s dry run and the snapshot: AC 3, AC 4).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=7 stage=implement'`, run from the worktree root. Run one command per call, each with `timeout: 600000`. Never put two IRIS test runs in one message. Only throwaways: never `ocutalon-slot-a` for tests.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e7s1iw ci/warm.sh up` -- once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e7s1iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Fix.Reformat`, `OcuTalon.Test.Fix.Kind`, `OcuTalon.Test.Bridge.ReplyCheck`, `OcuTalon.Test.Watch.Payload`, `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Watch.Evidence`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Agent.Instructions`, `OcuTalon.Test.Install.Production`. Expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e7s1i ci/iris.sh class <Class>`, fresh, one call per class, because running jobs keep old code and the start's Roles step changed: `OcuTalon.Test.Fix.DryRun`, `OcuTalon.Test.Agent.Decide`, `OcuTalon.Test.Watch.Diagnose`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e7s1i ci/iris.sh shard lane-a --part 1/3`, then `--part 2/3` and `--part 3/3`, each in its own call. Record each part's time. If a part runs past 480 s, use `k/4`.
- (once) `<lane> OCUTALON_RUN_TAG=e7s1i ci/iris.sh shard lane-b`. Expected: passed.
- (once) `bash ci/checks.sh`. Expected: all pass (boundaries, storage blocks, class rules, ci-config).
- (once) `<lane> OCUTALON_RUN_TAG=e7s1iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e7s1i ci/iris.sh teardown`.

**Throwaway recipe for AC 4:** `ci/iris.sh class OcuTalon.Test.Fix.DryRun` with tag `e7s1i`. This is a fresh `docker/tests/lib-live.sh` project with `ci/compose.ci.yml`: demo mode on, OCUORDERS and its Orders production started, and the mock writing `/opt/ocutalon/mock-log/requests.jsonl`.

**Shared surfaces:**
- **What a valid data-format diagnosis is.** It now needs a `ReplyCheck` pack and registered formats.
  - Changed: `Test.Watch.Payload` and `Test.Bridge.Decide.TestFilterDiagnosis`.
  - Unchanged but run: `Test.Agent.Decide.TestSnapshotDiagnosis` and `Test.Watch.Diagnose.TestDemoDiagnosis`.
- **The service role's resources** gain `%Ens_MessageResend:U`. `Test.Install.Registry` saves and restores them; `Test.Watch.Grant` asserts only OCUORDERS.
- **The installer areas** gain `Install.Step.Fix`. `Test.Install.Registry.TestAreas` checks membership.
- **The Diagnosis INSTRUCTIONS text.** `Test.Agent.Instructions` checks substrings.
- **`Test.Watch.Case.Fixture`** moves from `Evidence`.
- **The `lane-a` area list** gains `Fix` (`ci/units.sh`, `test-ci-config.sh`).
- **`FixExecutor` stays a stub** for every request but a `DryRun` (the `Test.Install.Production` oracle).
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19). The implement stage applies each one, observes red, reverts byte-identically, and records the result here as `mutation: … → …`.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 contract | delete `Recheck` from `Fix.Kind` | `Kind.TestContract` |
| AC 1 grants | `RepairResend.RESOURCES` "" | `Kind` (Grants), `DryRun.TestServiceUserMayResend` (fresh) |
| AC 2 field | `CheckParameters` skips the field check | `Kind` (validation rows) |
| AC 2 format | `Reformat.Family` accepts any name | `Kind` (validation rows) |
| AC 2 schema | the base check ignores extra keys | `Kind.TestCheckParameters` |
| AC 2 seam | `Interpret` skips `ReplyCheck.Begin` | `Bridge.ReplyCheck`, `Agent.Decide.TestSnapshotDiagnosis` (fresh) |
| AC 2 end | `Interpret` skips `End` | `Bridge.ReplyCheck` (`Active` after `Conclude`) |
| AC 2 route | `DiagnosisPayload` skips the kind check | `DryRun.TestInvalidRepairTakesTheFallbackRoute` |
| AC 3 scope | `DryRun` drops the scope test | `DryRun.TestLeftOutAndScope` |
| AC 3 left out | an unreadable value becomes a target | `DryRun.TestLeftOutAndScope` |
| AC 4 nothing changed | `DryRun` saves the repaired value into the original body | `DryRun.TestFiftyOrdersChangeNothing` |
| AC 4 no model | `DryRun` sends one POST to the mock's `/v1/messages` | `TestFiftyOrdersChangeNothing` (mock log) |
| AC 4 field | `FieldWords` returns the name as is | `TestFiftyOrdersChangeNothing` |
| AC 5 digits | the patterns use `\d` | `Reformat.TestRefuses` (Arabic-Indic digits) |
| AC 5 never evaluates | `Convert` runs `Xecute "Set x="_value` | `Reformat.TestNeverEvaluates` |
| stub | `FixExecutor` answers OK to other requests | `Install.Production` |
| AC 6 clear | `ReplyCheck.Begin` keeps earlier values it is not given | `Bridge.ReplyCheck` (second decision in one job) |
| AC 6 error path | `Interpret` ends `ReplyCheck` only on its normal exit | `Bridge.ReplyCheck` (error path) |

**Task 0 results (implement, warm stack `e7s1iw`, 2026-10-27):**
- Idle window: 70 s on a started warm stack, after the stack had been up for more than a minute: no new `Ens.MessageHeader` row at all in OCUTALON (2 headers before and after) and none in OCUORDERS (1 header). So `HeartbeatIn` did not tick in the window (its cadence is longer than 70 s on a throwaway), and `Snapshot` needs no allowance beyond `HeartbeatIn` sessions. `Snapshot.Diff` allows the sessions that a new `HeartbeatIn` header starts, which covers a tick that does fall in a test.
- `Snapshot.Take` over OCUTALON and OCUORDERS: 0.02 s on a fresh stack (3 headers); 0.37 s on a warm stack after the Fix, Evidence and Decide test classes (340 headers in OCUTALON), a second take 0.36 s. About 1 ms per header, so the full `lane-a` shard (a few thousand headers) is a few seconds. It was not timed after the whole shard, because each shard part runs on its own throwaway that is gone when it ends.

**Test results (implement):**
- Slot A (pure classes): `Test.Fix.Reformat` 6/6, `Test.Fix.Kind` 9/9, `Test.Bridge.ReplyCheck` 4/4, `Test.Watch.Payload` 4/4, `Test.Bridge.Decide:TestFilterDiagnosis`.
- Warm `e7s1iw`: `Fix.Reformat`, `Fix.Kind`, `Bridge.ReplyCheck`, `Watch.Payload`, `Bridge.Decide`, `Watch.Evidence`, `Bridge.CodeRules`, `Agent.Instructions`, `Install.Production` passed.
- Fresh `e7s1i`: `Fix.DryRun` passed; `Agent.Decide` passed (after the `FromInput` decision above; it failed before it); `Watch.Diagnose` passed.
- `lane-a` shard, final run after the last code change (fresh `e7s1i`): part 1/3 passed (378 s), part 2/3 passed (125 s), part 3/3 passed (417 s); the first run of part 3/3 had failed in `Test.Watch.Incidents` (`TestInstanceShared`, `TestTwoSessions`), closed as decided below. `lane-b` passed (228 s, before the `Test.Watch` fixture change, which `lane-b` does not run). `bash ci/checks.sh` passed after the last change.
- `Test.Watch.Incidents` (decided in-stage, a shared surface the plan did not list): its two tests delivered synthetic failures whose evidence pack had no sample body (a namespace that does not exist, or header ids that do not exist), and relied on the mock's default `repair_resend` staying unnoticed until Story 7.2. With the kind check failing closed that diagnosis is the fallback `invalid`, which is noticed. `TestInstanceShared` and `TestTwoSessions` now give the first failure of each incident the id of a failed fixture order of OCUORDERS (`Case.SampleOrder`: Status 8, an hour old so the poller never reads it, a `PartnerOrder` body dated `10/16/2026`, removed with the test), and `TestTwoSessions` delivers to OCUORDERS' Orders production, because only a namespace's own current production can be read. The assertions are unchanged. The file is in Lane A's `Test/Watch/**`: a footprint extension.

**Pinning mutations (Rule 19)**, each applied, observed red and reverted (the tree is byte-identical to before; the one test edit after the baseline is `Test/Bridge/ReplyCheck.cls`, which gained a refused-Begin assertion in `TestSecondDecision`):
- mutation: delete `Recheck` from `Fix.Kind` -> red: `Kind.TestContract` (slot A).
- mutation: `RepairResend.RESOURCES` "" -> red: `Kind.TestContract`, `Kind.TestGrants` (slot A); `DryRun.TestServiceUserMayResend` (fresh `e7s1i`).
- mutation: `CheckParameters` skips the field check -> red: `Kind.TestCheckParameters`, `TestConcludeRows`, `TestReplyCheckRows` (slot A).
- mutation: `Reformat.Family` accepts any name (gives "date") -> red: `Kind.TestCheckParameters`, `TestConcludeRows`, `TestReplyCheckRows` (slot A).
- mutation: the base `CheckParameters` ignores extra keys -> red: `Kind.TestCheckParameters`, `Kind.TestSchemaCheck` (slot A).
- mutation: `Interpret` skips `ReplyCheck.Begin` -> red: `Bridge.ReplyCheck` (`TestBothChecksSeeTheRequest`, `TestErrorPath`, `TestSecondDecision`) (slot A). `Agent.Decide.TestSnapshotDiagnosis` (fresh) was not run with this mutation.
- mutation: `Interpret` skips `End` on its normal exit -> red: `Bridge.ReplyCheck.TestBothChecksSeeTheRequest` (`Active` after `Conclude`) (slot A).
- mutation: `DiagnosisPayload` skips the kind check -> red: `DryRun.TestInvalidRepairTakesTheFallbackRoute` (warm; the test calls `Conclude` in its own process).
- mutation: `DryRun` drops the scope test -> red: `DryRun.TestLeftOutAndScope`, `TestRefusals` (warm).
- mutation: an unreadable value becomes a target -> red: `DryRun.TestLeftOutAndScope`, `TestNothingReadable` (warm).
- mutation: `DryRun` saves the repaired value into the original body -> red: `DryRun.TestFiftyOrdersChangeNothing` (the snapshot diff names 50 changed headers) (warm).
- mutation: `DryRun` sends one POST to the mock's `/v1/messages` -> red: `DryRun.TestFiftyOrdersChangeNothing` (the mock log) (warm).
- mutation: `FieldWords` returns the name as is -> red: `DryRun.TestFiftyOrdersChangeNothing`, `TestNothingReadable` (warm).
- mutation: the patterns use `\d` -> red: `Reformat.TestRefuses` (Arabic-Indic digits in a fraction; the date patterns still refuse them through the calendar check) (slot A).
- mutation: `Convert` runs `Xecute "Set x="_value` -> red: `Reformat.TestNeverEvaluates` (sentinel defined), `TestStaticScan` (slot A).
- mutation: `FixExecutor` answers OK to other requests -> red: `Install.Production.TestStubsAnswer` (warm).
- mutation: `ReplyCheck.Begin` keeps earlier values (no `Kill`) -> red: `Bridge.ReplyCheck.TestBegin` (the planted stale value, and a refused Begin), `TestSecondDecision` (a refused Begin after A leaves nothing of A) (slot A). A second decision whose request has an empty `Input` overwrites it, so the clear is pinned by the stale value and the refused Begin.
- mutation: `Interpret` ends `ReplyCheck` only on its normal exit -> red: `Bridge.ReplyCheck.TestErrorPath` (slot A).
- mutation: `Snapshot.Diff` drops the queues category -> red: `SnapshotDiff.TestEachCategoryIsCompared` (slot A).
- mutation: `Snapshot.Diff` ignores the allowed sessions -> red: `SnapshotDiff.TestNewHeaders` (slot A).
- mutation: `Install.Step.Fix` made Abstract (the registry skips it) -> red: `Kind.TestGrants` (the declared grants lack the Fix area's) (slot A).
- mutation: `RepairResend.DryRun` lists the targets in the order the groups held them -> red: `DryRun.TestTargetsAscendAcrossGroups` (fresh `e7s1i`).
- mutation: `RepairResend.DryRun` ignores `Incident.ItemNoun` -> red: `DryRun.TestNothingReadable` (fresh `e7s1i`).
- Not run: none of the 18 rows is without a line; two rows name a second test that was not run with their mutation (`Agent.Decide.TestSnapshotDiagnosis` for the seam, as said above).

## Auto Run Result

Status: done
Blocking condition: none

**Change.** The fix-kind contract `OcuTalon.Fix.Kind` with its one kind `RepairResend` (parameter check, field words, a read-only dry run that reads through `Watch.Reader.Evidence` and returns ascending in-scope targets and the `DRYRUNKEYS` JSON); the registered reformatters `OcuTalon.Fix.Reformat`; the bridge API `OcuTalon.Bridge.ReplyCheck` and `Decide.Interpret` beginning it and ending it on every exit (owner decision U-125); the kind check as the last check of `DiagnosisPayload` against the sample body of the evidence pack (`EvidencePack.FromInput`); `Fix.Msg.DryRun`/`DryRunResult` answered by `FixExecutor` (`STUB = 1` kept, every other request still error 5003); `Install.Step.Fix.Grants()` giving the service role `%Ens_MessageResend:U`; one INSTRUCTIONS bullet naming the formats.

**Files changed.**
- New: `src/ocutalon/cls/OcuTalon/Fix/{Kind,Reformat}.cls`, `Fix/Kind/RepairResend.cls`, `Fix/Msg/{DryRun,DryRunResult}.cls`, `Install/Step/Fix.cls`, `src/bridge/cls/OcuTalon/Bridge/ReplyCheck.cls`; tests `Test/Fix/{Reformat,Kind,ZzKind,Snapshot,SnapshotDiff,DryRun}.cls`, `Test/Bridge/{ReplyCheck,ProbeReplyCheck}.cls`.
- Changed: `Fix/Executor.cls`, `src/bridge/.../Bridge/Process/Decide.cls`, `Watch/EvidencePack.cls`, `Watch/Msg/DiagnosisPayload.cls`, `Agent/Diagnosis.cls`, `ci/units.sh` (the `lane-a` areas), `Test/Watch/{Case,Evidence,Payload,Incidents}.cls`, `Test/Bridge/Decide.cls`.

**Review.** 30 findings: high 0, medium 4, low 24, false 2. Patches applied: 3 medium (itemNoun source, ascending across groups, Snapshot.Diff oracle) and 8 low. Deferred: 1 medium (the 1000-key `Seen` cap, in `deferred:`). Every rejected finding has its reason in the triage log above. Follow-up review recommended: true, because three medium patches (new tests `TestTargetsAscendAcrossGroups`, the `SnapshotDiff` class, the `itemNoun` assertion) were made after the review layers ran; each was run green and each has a recorded red mutation, but none was reviewed again.

**Verification.** `lane-a` shard parts 1/3 and 3/3 passed after the `Test.Watch` fixture change and part 2/3 passed after the last patch; `lane-b` passed (before the last test-only patches); `Test.Fix.DryRun` passed fresh after the last product change; `Test.Watch.Incidents` passed fresh; `bash ci/checks.sh` passed after the last change. Both throwaway tags (`e7s1i`, `e7s1iw`) are torn down.

**Residual risks.** The `Seen` cap (deferred). The dry run's reading of 500 messages inside a 60 s synchronous call is Story 7.4's measurement. `Test.Watch.Incidents` now seeds its two tests with a fixture order; other Epic 5 tests that deliver synthetic failures do not assert on a stored diagnosis and stayed green.
