---
title: 'Story 9.6: Incident cases are diagnosed through IncidentManager and reach nobody'
type: 'feature'
created: '2026-10-29'
status: 'done'
baseline_revision: '7aacb9ff5e3c1932105cd7db8bd2e952a8fd0b9e'
baseline_commit: '7aacb9ff5e3c1932105cd7db8bd2e952a8fd0b9e'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** EvalIn still skips the ten recorded incident cases (kind `incident`, reported as `notRunYet`). So no cause score has ever measured the product's diagnosis, and Story 9.5's demo-incident gate has no path to run through. The live `IncidentManager` path, as Epic 7 left it, also asks for a dry run, raises an approval request and delivers a notice after every diagnosis. An evaluation incident must reach none of those.

**Approach:**
- EvalIn sends each incident case to `IncidentManager` as a new Lane A message, `OcuTalon.Eval.Msg.IncidentCase`, carrying a fresh Ref, the case name and the recorded snapshot.
- A separate evaluation branch of `IncidentManager` then:
  - builds the pack with `EvidencePack.Build(snapshot)`;
  - calls `Decide` (`diagnose`, owner `eval`), with that Ref as `ItemId`;
  - sends `EvalSink` one `ItemDecision`;
  - writes no row, starts no waiter, and sends or publishes nothing else.
- The Diagnosis agent's read tools answer from the same recorded snapshot for owner `eval`, so the measured diagnosis is the product's.
- Two ledger entries are folded in:
  - DW-353: the row is opened with the Ref EvalIn minted.
  - DW-385: the Orders-definition fixture becomes one shared test helper.

## Boundaries & Constraints

**Always:**
- **The eval branch has a single output.** It is reached only by an `IncidentCase`. Its only sends are:
  - one `OcuTalon.Bridge.Msg.Request` to `Decide`;
  - one `OcuTalon.Msg.ItemDecision` to `EvalSink`.
- **The request to Decide** is built exactly as `Diagnose` builds one, by the shared builder:
  - Kind `diagnose`, Provenance `untrusted`;
  - `ItemId` = the case's `IncidentRef`, `OwnerRef` = `OcuTalon.Data.Ownership.#EVAL`;
  - `TraceRef` = `..%SuperSession` (the run Ref), `ThreadSessionId` = `..%SessionId`;
  - `Summary` = `<pack.count> failures at <pack.item>`, cut to `SUMMARYMAX`;
  - `Input` = `EvidencePack.Input(pack)`.
- **The ItemDecision** carries:
  - `ItemId` = `IncidentRef` (the incident's Ref, AD-30) and the case's `SourceItemId`;
  - `OwnerRef` `eval`, the request's `Summary`, and an empty `Channel`;
  - `DecisionRef`, `Outcome`, `Fallback` and `FallbackReason` as Decide answered.
- **Every failure ends the case as a fallback.** These all send a fallback `ItemDecision` (`Fallback` 1, `FallbackReason` `error`, `Outcome` `tellnow`, no `DecisionRef`) with one Type 3 warning (redacted):
  - a snapshot that does not parse or builds no pack;
  - a send to Decide that fails;
  - an error answer;
  - an answer that is not a `DecisionResponse`.

  So a case row never stays `sent` silently. A failed send to EvalSink logs one Type 3 warning.
- **EvalIn mints the case's `IncidentRef`** with `OcuTalon.Bridge.Ids.NewRef()`, the same way it mints every case's fresh id (AD-22).
  - `SourceItemId` is the case's folder name, as for turn cases.
  - The case's `CaseResult` row is opened with `ItemId` = `IncidentRef` before the send.
  - A failed send removes the row again.
- **The read tools' eval branch (AD-6) has strict limits:**
  - It is reached only when `EvidencePack.Scope()` finds no incident, the context's `OwnerRef` is exactly `eval`, and the newest `IncidentCase` whose `IncidentRef` is the context's `ItemId` holds a snapshot of `SNAPSHOTFORMAT`.
  - It reads that table with SQL only, so no `OcuTalon.Eval` class is named in callback code.
  - It never throws, and writes nothing.
  - Its answers have the live answers' shape, at most `MAXMESSAGES` failures and `MAXLOG` log rows, and the item's settings without credential names.
- **These stay as they are:**
  - every other path through IncidentManager, which keeps its existing tests green;
  - every other tool answer and every other owner's answer;
  - every cross-lane signature.

**Never:**
- **Never in the eval branch:**
  - write an `Incident` or `FailureGroup` row;
  - start a `Settle` waiter, or call `Tell`, `Notice`, `Propose`, `Ask`, `SendDryRun`, `RaiseRequest`, `Deliver`, `SendNotice` or `SendExecute`;
  - publish `incident` or `watch.progress`;
  - reach `OutcomeRouter`, `Notify`, `FixExecutor`, `ApprovalHold` or any `*Out` item.
- Never diagnose outside `IncidentManager` (U-130). Never use `EnsLib.Testing.Service` or the testing switch.
- **Never edit these:**
  - a contended path: `Data/**`, `Core/**`, `Msg/**`, `Test/{Web,Data,Msg}/**`, `Install/**`, `docs/**`, `src/module.xml`;
  - Lane B's mock behaviour, or `ARCHITECTURE-SPINE.md` (the lead writes the spine).
- Never put a `[[mock:` marker in `eval/` outside `eval/mock-wrong/`. Never commit a local absolute path.
- Never make `eval/run.sh` fail on a score.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Demo incident through the product (AC1, AC2) | A run names `orders-date-format` on a stack with EvalIn on and the CI mock | EvalIn>IncidentManager, IncidentManager>Decide (DiagnosisAgent), IncidentManager>EvalSink. The row ends `decided` with `DecisionRef` (a `diagnose` Decision, owner `eval`), `CauseCategory`, `ElementAtFault`, `FixKind`, `FixParameters`, `CostUSD` and `LargestRequestTokens`. No `Incident`, `FailureGroup`, `Notification`, `Delivery`, live event, `DryRun`, `ApprovalRequest` or `FixRun`. | No error expected |
| Usable diagnosis with a fix | `DecisionResponse` with `act`, `Fallback` 0 and `repair_resend` | Exactly one `ItemDecision` to EvalSink (Outcome `act`). No dry run, raise, notice, waiter or alarm. | No error expected |
| Usable diagnosis, no fix or `unknown` | `DecisionResponse` with `act` and an empty `fixKind` | The same single `ItemDecision`. No no-fix notice. | No error expected |
| Fallback answer | `DecisionResponse` with `Fallback` 1 and `tellnow` | `ItemDecision` with Fallback 1, its reason and its `DecisionRef` | No error expected |
| Decide refuses | `OnError` for an `IncidentCase` | `ItemDecision` with fallback `error` and no `DecisionRef` | One Type 3 warning; `OnError` answers OK |
| Bad snapshot at IncidentManager | `Snapshot` not JSON, not `SNAPSHOTFORMAT`, or with no failure | No request to Decide; fallback `error` `ItemDecision` | One Type 3 warning |
| Send to Decide fails | `SendDiagnose` errors | fallback `error` `ItemDecision` | One Type 3 warning |
| Empty `IncidentRef` | An `IncidentCase` with no `IncidentRef` | `OnRequest` answers an error status that names the missing Ref. Nothing is sent. | Framework logs it |
| Incident case cannot be sent (EvalIn) | No `snapshot`, a name with `/`, `\` or `..`, a missing file, or not a reader snapshot (`EvidencePack.Load`) | Skipped with `REASONNOSNAPSHOT` or `REASONSNAPSHOT`; no row, nothing sent | Warning `LOGSKIPPED` |
| Dispatch fails (EvalIn) | `DispatchIncident` errors or throws | The row is removed; the case is skipped with the error text | Warning `LOGSKIPPED` |
| Read tool, eval incident | Context: owner `eval`, `ItemId` = a saved `IncidentCase`'s `IncidentRef` | The three tools answer from its snapshot. `read_failed_messages` gives `{count: failures size, items: first ≤5}`; `read_event_log` gives ≤20 rows; `read_item_settings` gives `{item, settings}` without credentials. | Never throws |
| Read tool, anything else | Another owner, no `IncidentCase` for the ItemId, no context, or a live incident in `Scope` | Unchanged: `{"items": []}`, or the live answer | Unchanged |
| EvalSink receives the incident decision (DW-353) | `ItemDecision.ItemId` = the `IncidentRef` the row was opened with | `CaseResult.Pending(ItemId)` finds the row and completes it as today | Unchanged |

</intent-contract>

## Code Map

All class paths are under `src/ocutalon/cls/OcuTalon/` unless they say otherwise.

**Product**
- `Watch/IncidentManager.cls`. Lane A, Epic 7's as-built (a footprint extension).
  - `OnRequest` :209-220 dispatches by class; any other class is a 5001 error at :219.
  - `OnResponse` :226-243 and `OnError` :248-262 return early unless the request is a `Settle` (:228, :250). The eval route must come before that check.
  - `Diagnose` :610-644 builds the request inline at :632-641 and sends it at :641 with `SendRequestAsync(..#DECIDE, request, 1, ..#DIAGNOSEKEY)`. A shadow instance cannot `SendRequestAsync`, so the seam matters for tests.
  - `Tell` :1305 is the only publisher. Session.Recipients gives nothing for owner `eval`, but the eval branch must not call it at all.
  - The BP's storage persists `%SuperSession` (irislib `Ens/BusinessProcess.cls`:260, :1394), so `OnResponse` still has the run Ref.
- `Watch/EvidencePack.cls`. Lane A (a footprint extension). It is scanned by the callback rule (`Test/Bridge/CodeRules.cls` `WATCHREADS` :79, `CALLBACKHELPERS` :72, which includes `OcuTalon.Bridge.Context` and `OcuTalon.Data.Ownership`).
  - `Scope` :37-45.
  - `Build(source)` :84-101, which already accepts an Incident or a snapshot: the pattern to mirror.
  - `Recorded` :119-136, which requires the format and at least one failure.
  - Shaping helpers: `Message` :163, `LogMessage` :176, `Settings` :188.
  - `Load(file)` :287.
  - The tool reads take an Incident only: `FailedMessages` :305, `EventLog` :329, `ItemSettings` :347. Their only caller is `Tools/WatchReads.cls`.
- `Tools/WatchReads.cls` :39-58. Each tool calls `Scope()` and otherwise answers `{"items": []}`. A footprint extension. The mock's default `diagnosis` script calls `read_failed_messages` first (`ci/mock/scenarios/A/diagnosis.json`).
- `Tools/WatchAnswers.cls` `EvalCheckResults` :218-240. The sibling eval branch (Story 9.7): owner exactly `eval`, SQL read of an Eval message by `ItemId`, never throws.
- `Eval/In.cls`
  - `KINDS` :53, `REASONKIND` :85.
  - `Send` :257-312: the item path, `Open` :293, `%SuperSession` :296, `Dispatch` :297.
  - `Dispatch` seam :346-349.
  - `SendTurn` :355-386: the precedent of `SourceItemId` = the case name (:368, :372).
  - `SendOrder` :207: incidents go with "the others".
  - `Scalar` :503.
- `Eval/Msg/TurnResult.cls`: the precedent for a Lane A eval message (`Ens.Request`, no `DEFAULTGLOBAL`, no `short-names.tsv` row; its storage is the generated block).
- `Eval/Data/CaseResult.cls`
  - `Open` requires `itemId`; `Pending(itemId)` is how Sink finds the row.
  - No storage change; doc comment only.
- `Eval/Sink.cls`
  - `Complete` finds the row by `Pending(request.ItemId)` and reads the cause fields from the Decision when `Kind` is `diagnose` (already tested on synthetic rows: `Test/Eval/Sink.cls` `TestIncident` :127).
  - Doc comment only.
- `Eval/Report.cls`
  - Doc :42-45 and `NOTRUNYET` :151-152.
  - `AddSkipped` :815-828: `notRunYet` = in `CASEKINDS` (:58) and not in `In.#KINDS`, so it turns 0 once `incident` is in `KINDS`.
  - `Problems` :179-209.
  - `Complete` :303-330 already requires a `DecisionRef`, a cost and a size on every row.
  - Case entries carry `kind` (:402).
- `eval/run.sh`
  - `eval_run` :77-100 prints `CHK|case|name|right|got|fallback`, with an object `got` printed empty (:89), and `CHK|incidents|` (:90), which nothing checks.
  - Run 1's checks are at :150-207. Run 2 parses `$5`/`$6` (:220).
- Unchanged:
  - `.github/workflows/lane-a.yml` `evaluation` job :44-63 (30-minute timeout, existing push triggers);
  - `docker/tests/test-eval-set.sh`: the `markers` rule allows only `item` cases in `mock-wrong/`;
  - `src/ocutalon/cls/OcuTalon/Production.cls`: `IncidentManager`, `DiagnosisAgent`, `EvalSink` and `FixExecutor` already exist at :28, :40, :43 and :44.
- Bridge, read-only (`src/bridge/cls/OcuTalon/Bridge/`):
  - `Msg/Request.cls`, which has no `HostData`.
  - `Msg/DecisionResponse.cls`, extending `Msg/Result.cls` (`Outcome`, `Fallback`, `FallbackReason`, `DecisionRef`) with `Payload`.
  - `Process/Decide.cls`: `Admit` :481-495 refuses an empty ItemId, OwnerRef or Input; `RecordFallback` :887-907 answers `tellnow`; one row per (ItemId, Kind).
  - `Context.cls` `Begin(request, superSession)` :59, `End` :78, `Current` :90.
  - `Budget.cls`:141 excludes `eval` from the daily cap. `Data/Ownership.cls` `Rows` :637-642 refuses owner `eval` for session totals.

**Tests**
- `Test/Eval/Run.cls`. The in-production isolation test: real production, with EvalIn switched on by `Prepare` :198-256 and restored in `OnAfterAllTests` :364.
  - Cases and allow-list: `RUN1CASES` :73 already names `orders-date-format`; `ITEMPATH` :100.
  - Tests to update: `TestItemPath` :483 (:486, :490), `TestRefusals` :571 (:575, :582, :596), `TestIsolation` :627-661 (the deny list :637 names IncidentManager; the Incident filter :648), `TestHops` :666-701 (:699), `TestUsage` :706-735 (`decisions = 14` :729), `TestReport` :738 (:757-760).
  - Helpers: cleanup :386-401, `Leftovers` :438, `RowsOf` :1090, `Refs` :1101, `MaxId` :1146, `CountAbove` :1154.
- `Test/Eval/In.cls`
  - `TestRefuses` :152-183: case `zz-incident` → `KindReason("incident")`.
  - `TestEarlyRefusalsSetUpNoWatch` :323-353: `zz-w-kind`, kind incident.
  - `TestSendOrder` :599-617: stays valid.
  - `KindReason` :743-748.
- `Test/Eval/ZzIn.cls`: the `Dispatch` override at :20 records an Item under `^OcuTalonTest("EvalIn","seen",n)`, with the `fail` and `throw` globals.
- `Test/Eval/Cases.cls` `TestRecordedCases` :106-160: the incident else-branch :147-148 expects a skip.
- `Test/Eval/Report.cls`: `TestSkipped` :931-958 (:943, :949, :953-955) and `TestText` :1013 (:1035).
- `Test/Watch/IncidentProbe.cls` :19. The shadow-instance subclass of IncidentManager whose send seams record into `Sent`, `DryRuns`, `Raised`, `Executed`, `Started`, `Alarms` and `Cancelled`. It is made with `Ens.Host.GetShadowInstance("class||<class>")` (`Test/Watch/Lifecycle.cls` :1010-1015). `Test/Watch/Lifecycle.cls` `TestUnknownRequest` :998-1006 must stay green.
- `Test/Eval/Checks.cls`: the pattern for a callback-branch test. `Begin(owner, itemId)` :185 starts a bridge context from a Request, `Record` :198 saves a message body, and cleanup is by a SourceItemId prefix.
- `Test/Contract/Mock.cls` `LogMark` :471, `LogSince` :484. These read `/opt/ocutalon/mock-log/requests.jsonl`, whose entries keep `messages` in full, with key-like text redacted (`ci/mock/mock.mjs` :40-46, :176-179).
- DW-385 pair:
  - `Test/Watch/Evidence.cls` `FixtureSettings` :60-87 and `DefinedSettings` :90-111 (all five names get `FIXTUREVALUE`; asserted at :362; callers :53, :350-372).
  - `Test/Eval/Record.cls` `FixtureSettings` :973-1005 and `DefinedSettings` :1008-1030 (the credentials get `SECRET`, the note gets `NOTEVALUE`; asserted at :775, :785; callers :153, :540-554, :743-792).
  - Both target `OCUORDERS` / `OcuTalon.Demo.Orders.Production` / `OrdersFromPartner`, with the names `Credentials,SMTPPassword,BotToken,ApiKey,ZzFixtureNote`.
  - Public ClassMethods not named `Test*` are not run as tests (irislib `%UnitTest/Manager.cls` :1333-1351).
- CI: `ci/units.sh`:17 puts the area `Eval` in `lane-a`, run by `shards-2` (`shard:lane-a@rest`). New `Test.Eval.*` TestCases are found by area, and non-TestCase helpers are ignored (`ci/iris.sh` :141-149).

## Tasks & Acceptance

**Execution:**

**Product**
- `src/ocutalon/cls/OcuTalon/Eval/Msg/IncidentCase.cls` (new) -- An `Ens.Request` with:
  - `IncidentRef` (`%String`, MAXLEN 22);
  - `SourceItemId` (MAXLEN 128);
  - `Snapshot` (`%String`, MAXLEN "", the recorded reader snapshot's JSON text).

  Its doc comment names its one writer (EvalIn) and its readers (`IncidentManager`'s eval branch, `EvidencePack.EvalSnapshot`). Commit the generated `Storage Default` block. -- This is the message the spine leaves unnamed. It carries the text, so IncidentManager reads no file.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` --
  - Add `Parameter EVALSINK = "EvalSink"` and a `LOGEVAL` warning prefix.
  - `OnRequest`: dispatch `OcuTalon.Eval.Msg.IncidentCase` to a new private `EvalCase`.
  - `OnResponse` and `OnError`: route an `IncidentCase` request to the eval handler before the `Settle` check.
  - Extract the request build of `Diagnose` (:632-640) into a private `DiagnoseRequest(itemId, owner, count, pack)`. Extract the send into a private seam `SendDiagnose(request)`, which is `SendRequestAsync(..#DECIDE, request, 1, ..#DIAGNOSEKEY)`. `Diagnose` uses both, with its behaviour unchanged.
  - Add a private seam `SendEval(decision)`, which is `SendRequestAsync(..#EVALSINK, decision, 0)`.
  - `EvalCase`, `EvalAnswered` and `EvalRefused` implement the Always and Never rules and the matrix rows.
  - Add one class-doc bullet for the evaluation incident (the contract, not the history). -- AC1, AC2; extend, don't copy.
- `src/ocutalon/cls/OcuTalon/Eval/In.cls` --
  - `KINDS` gains `incident`. Add the parameters `INCIDENTKIND`, `INCIDENTTARGET = "IncidentManager"`, `REASONNOSNAPSHOT` and `REASONSNAPSHOT` (with `{why}`).
  - `Send` routes the kind to a private `SendIncident(case, folder, name)`, which:
    - validates the `snapshot` member and loads it with `EvidencePack.Load`;
    - builds the `IncidentCase` (fresh `IncidentRef`; `SourceItemId` = name; `Snapshot` = `snapshot.%ToJSON()`);
    - opens the row with `ItemId` = `IncidentRef`, sets `%SuperSession` = `RunRef` and calls a private seam `DispatchIncident(case)`, which is `SendRequestAsync(..#INCIDENTTARGET, case)`;
    - removes the row on an error.
  - Update the class doc. -- AC1, AC3, DW-353.
- `src/ocutalon/cls/OcuTalon/Watch/EvidencePack.cls` --
  - Add `ClassMethod EvalSnapshot() As %DynamicObject`, the eval read under the Always limits. It is an SQL `SELECT Snapshot FROM OcuTalon_Eval_Msg.IncidentCase WHERE IncidentRef = ? ORDER BY ID DESC`, parsed and format-checked, returning "" otherwise.
  - Make `FailedMessages`, `EventLog` and `ItemSettings` accept, like `Build`, either an Incident (live, unchanged) or a recorded snapshot. The answer shaping is shared, so both sources give one shape. A recorded snapshot answers:
    - `count` = the size of `failures`, with `items` = the first `MAXMESSAGES` failures (or event-log rows when it has none);
    - the first `MAXLOG` event-log rows;
    - `item` = `Clean(failures[0].targetConfigName)` with `Settings(snapshot, item)`.

  Name only classes that `CodeRules` allows. -- The Diagnosis agent's tools read the recorded failures (AD-22 Prevents).
- `src/ocutalon/cls/OcuTalon/Tools/WatchReads.cls` -- Each of the three tools uses `Scope()`, then, when that finds no incident, `EvidencePack.EvalSnapshot()`. Otherwise it answers `{"items": []}` as today. Update the class doc. -- Same as above.
- `src/ocutalon/cls/OcuTalon/Eval/Data/CaseResult.cls`, `Eval/Sink.cls` and `Eval/Report.cls` -- Doc comments only:
  - an incident row is opened by EvalIn with the `IncidentRef` and completed from IncidentManager's `ItemDecision`;
  - an incident's `SourceItemId` is the case name;
  - `notRunYet` marks a kind of `CASEKINDS` that EvalIn does not send, which is now none.

  There is no storage or behaviour change. -- Contract accuracy.
- `eval/run.sh` --
  - In `eval_run`, print an object `got` as `causeCategory/elementAtFault/fixKind`, and append the case's `kind` as a seventh field of `CHK|case|`.
  - Run 1 must check that:
    - the number of `incident` case lines equals the number of top-level `eval/*/case.json` of kind `incident`, and is greater than 0;
    - every incident line has `fallback` 0 and a `got` with a non-empty cause category and element.
  - Update the header comment. There is no score check. -- AC3.

**DW-385**
- `src/ocutalon/cls/OcuTalon/Test/Watch/OrdersDefinition.cls` (new, not a TestCase) -- It holds:
  - `Parameter CREDENTIALS = "Credentials,SMTPPassword,BotToken,ApiKey"` and `Parameter NOTE = "ZzFixtureNote"`;
  - `ClassMethod Put(on As %Boolean, credentialValue As %String, noteValue As %String) As %Status`, the one open/remove/insert/save loop on `OCUORDERS`'s Orders production definition (item `OrdersFromPartner`; namespace and production from `OcuTalon.Install.Step.Demo`'s parameters, as Evidence reads them);
  - `ClassMethod Defined() As %String`. -- DW-385.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls` and `src/ocutalon/cls/OcuTalon/Test/Eval/Record.cls` -- Delete the private `FixtureSettings` and `DefinedSettings` and call the helper:
  - Evidence passes `FIXTUREVALUE` for both values;
  - Record passes `SECRET` and `NOTEVALUE`;
  - their name parameters reference the helper's.

  Assertions and values are unchanged. -- DW-385; no drift.

**Tests**
- `src/ocutalon/cls/OcuTalon/Test/Eval/ZzIncident.cls` (new) -- Extends `OcuTalon.Test.Watch.IncidentProbe`, overriding:
  - `SendDiagnose`, which records the Request's fields in `Asked` and answers OK, or an error when `FailDiagnose` is set;
  - `SendEval`, which records the ItemDecision's fields in `Delivered` and answers OK, or an error when `FailEval` is set.

  The inherited seams record any forbidden send. -- A shadow-instance double; extends the sibling.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Incident.cls` (new TestCase, warm-safe, no production) -- Shadow-instance tests of every IncidentManager matrix row. The inputs are the demo snapshot from `/opt/ocutalon/eval/orders-date-format/snapshot.json`, and synthetic `DecisionResponse`s and errors.
  - Each test asserts that `Sent`, `DryRuns`, `Raised`, `Executed`, `Started`, `Alarms` and `Cancelled` stay empty. It also asserts that the counts of the `Incident`, `FailureGroup`, `ApprovalRequest`, `FixRun` and `Live.Event` tables are unchanged.
  - `TestRequest` pins the request's fields, with `Input` equal to `EvidencePack.Input` of `Build` of the same snapshot.
  - Read-tool tests (the `Test.Eval.Checks` pattern) cover the eval branch and every non-eval row of the matrix, comparing each answer with `EvidencePack`'s answer for the snapshot.
  - It deletes its `IncidentCase` bodies (SourceItemId prefix `zz-incident-`) and ends the context. -- AC1, AC2, tools.
- `src/ocutalon/cls/OcuTalon/Test/Eval/ZzIn.cls` and `src/ocutalon/cls/OcuTalon/Test/Eval/In.cls`:
  - ZzIn: add a `DispatchIncident` override that records `IncidentRef`, `SourceItemId`, the snapshot's format and failure count, whether the row was open, and the SuperSession, under `^OcuTalonTest("EvalIn","incident",n)`, with the same `fail` and `throw`.
  - In: move the refused-kind cases to an unknown kind such as `zz-kind`.
  - In: add tests that an incident case is sent once, with a 22-character fresh `IncidentRef`, `SourceItemId` = folder, and the row open with that ItemId.
  - In: add tests for each EvalIn matrix row (skips and dispatch failure leave no row). -- AC1, DW-353.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` -- In `TestRecordedCases`, every recorded incident case is sent through `ZzIn`, with a snapshot of the format and at least one failure, and none is skipped. -- AC3.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` --
  - `TestSkipped` and `TestText`: an incident skip is now a problem, and `notRunYet` is 0 for every kind.
  - Add `TestEveryKindSent`: `Eval.In.#KINDS` covers every kind of `Report.#CASEKINDS`. -- AC3.
- `src/ocutalon/cls/OcuTalon/Test/Eval/Run.cls` --
  - `Prepare` also takes `Mock.LogMark()` and marks for `FixRun` and `FailureGroup`.
  - `TestIsolation`:
    - the deny list drops `IncidentManager` and adds `FixExecutor`;
    - no header has a body of `OcuTalon.Fix.Msg.DryRun`, `.Execute` or `OcuTalon.Watch.Msg.Settle`;
    - no `Incident` or `FailureGroup` row of any owner and no `FixRun` above its mark.
  - `TestHops`: `ITEMPATH` adds `IncidentManager` and `DiagnosisAgent`. The control requires the hops `EvalIn>IncidentManager`, `IncidentManager>Decide` and `IncidentManager>EvalSink`. EvalIn's requests are exactly ` EvalIn>Decide EvalIn>EvalSink EvalIn>IncidentManager EvalIn>Intake`, and IncidentManager's exactly ` IncidentManager>Decide IncidentManager>EvalSink`.
  - `TestUsage`: 15 decisions (six decide, one diagnose, eight turn).
  - `TestItemPath`: run 1 sends 2 rows.
  - `TestRefusals`: only `zz-missing`; four warnings.
  - `TestReport`: incidents `1 of 1`; one skip; `notRunYet` 0.
  - New `TestIncidentPath` covers the demo row's fields (first matrix row). In `LogSince`, a diagnose request has a `tool_result` that holds the snapshot's first failure's `bodyClass`, and no `tool_result` is `{"items":[]}`.
  - Cleanup and `Leftovers` include the runs' `IncidentCase` bodies. Update the header. -- AC1, AC2, Integration.

**U-162 (the owner's condition on the veto ruling, 2026-10-30)** -- mirror 9.7's `check_status` guard tests (`Test/Eval/Checks.cls` `TestNotEvalBranch`, `TestSessionOwner`), each with a demonstrated mutation and its `mutation:` line:
- [x] [U-162] (1) The three read tools (`read_failed_messages`, `read_event_log`, `read_item_settings`) never take the eval branch for any owner but `eval`: a test where an `IncidentCase` of the call's `ItemId` exists and the context's owner is a session's Ref as a chat turn sets it, and one where the context comes from a tool call (the bridge context a tool-originated request begins), plus the owner `instance` and an owner only like `eval` (for example `eval ` or `EVAL`); each gets the live answer, never the recorded snapshot. Mutation: the branch's owner check dropped or widened.
- [x] [U-162] (2) With a live incident in scope, the tools answer live even for owner `eval`: a test that makes `EvidencePack.Scope()` find a live incident (its own throwaway rows, removed after) while an `IncidentCase` of the call's `ItemId` exists, and asserts the three answers are the live ones. Mutation: `WatchReads` tries `EvalSnapshot()` before `Scope()`.
- [x] [U-162] (3) The branch writes nothing: around eval-branch calls of all three tools, no new row in the message tables (`Ens.MessageHeader`, `Ens.MessageBody`, the `IncidentCase` table), the session tables (`Session`, `Turn`, `Live.Event`) or the watch tables (`Incident`, `FailureGroup`, `BackgroundCheck`), and no change to the `^OcuTalon*` globals the branch could touch (counts or a checksum taken before and after). Mutation: the branch saves a row or sets a global.

**Acceptance Criteria:**
- **AC1.** Given the recorded incident `orders-date-format`, when a run sends it, then:
  - `IncidentManager` builds the pack with `EvidencePack.Build` from the snapshot and calls `Decide` (`diagnose`) with owner `eval`;
  - it sends `EvalSink` one `ItemDecision` with `IncidentRef` as `ItemId`, the diagnosis's `DecisionRef` and `SourceItemId` `orders-date-format`;
  - nothing goes to `FixExecutor`, `ApprovalHold` or `Notify` (`Test.Eval.Run` `TestIncidentPath`, `TestHops`; `Test.Eval.Incident`).
- **AC2.** Given a completed run that includes an incident case, when the isolation test checks what it wrote, then:
  - there is no `Notification`, `Delivery`, live event holding a run Ref, `DryRun` or `Execute`, `ApprovalRequest`, `FixRun`, `Incident` or `FailureGroup`;
  - every `Usage` row of the run's ItemIds has owner `eval`, and the daily spend is unchanged (`Test.Eval.Run` `TestIsolation`, `TestUsage`).
- **AC3.** Given the evaluation job's command `eval/run.sh` on the CI mock, when run 1 sends the set, then:
  - all ten incident cases run through `IncidentManager` with the item and turn cases, and each ends with a completed result row: a recorded diagnosis (its `DecisionRef`), a cost and a request size in the report (the epic's AC3);
  - the demo incident (`Report.DEMOCASE`, `orders-date-format`) ends `decided`, with no fallback, a cause category and an element;
  - each of the other nine ends `decided` or as a fallback the product's own validation chose (on the CI mock the one `diagnosis` scenario answers `repair_resend` on `OrderDate`, which `RepairResend.CheckParameters` refuses where the sample body has no such field), and `eval/run.sh` reports their fallbacks without failing on them;
  - the run exits 0 with `eval/run: all checks passed` and no problem. [AMENDED 2026-10-30, implement-stage intent gap, lead ruling (decide): it read "each ends `decided`, with no fallback, a cause category and element, a cost and a request size", which the CI mock cannot reach; the epic's AC3 and the product promise are unchanged]
- **Integration (Rule 1).** Given the eval branch's `ItemDecision`, when the real `EvalSink` and `Report` consume it in the running production, then:
  - the case row is completed by its `ItemId` (DW-353);
  - the report scores the incident;
  - the Diagnosis agent's real `read_failed_messages`, called by the mock's default script, gives the model the recorded failures (the mock log).
- **U-162.** Given the read tools' eval branch, when the tests of the three U-162 items run, then: no owner but `eval` (a chat turn's session, a tool call's context, `instance`, a near-`eval` string) reaches it; owner `eval` with a live incident in scope gets the live answers; and the branch adds no row and changes no global (`Test.Eval.Incident`, with mutation lines).
- **DW-385.** Given the two Orders-definition fixtures, when `Test.Watch.Evidence` and `Test.Eval.Record` run, then:
  - both call `OcuTalon.Test.Watch.OrdersDefinition`, with no private copy left (`rg -n 'Method (FixtureSettings|DefinedSettings)' src` finds none);
  - both classes pass unchanged in what they assert.

### Review Findings

Code review 2026-10-30 (full mode, four layers, full-opus tier). 24 layer rows grouped into 12 entries (high 0, medium 5, low 7), 6 rows rejected. Every patch is applied; each line gives severity, fix-risk, footprint and disposition (Rule 15).

- [x] [Review][Patch] An error answer of Decide ended the evaluation case twice: OnError's EvalRefused, then the OnResponse call that Ens.BusinessProcess makes after an error OnError handled (no body), which EvalAnswered refused again, so two ItemDecisions and two warnings (the second a LOGNOROW at EvalSink) [src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:1410] — med, fix-risk low (one guard on the framework's %CurrentResponseHeader.IsError), in-story, spec-clear (Always: one ItemDecision; matrix "Decide refuses": one warning). Fixed; ZzIncident.CaseRefuse now makes the framework's OnError-then-OnResponse sequence, and the mutation line is under Verification.
- [x] [Review][Patch] TestHops no longer caught another item's request to IncidentManager once IncidentManager left TestIsolation's deny list [src/ocutalon/cls/OcuTalon/Test/Eval/Run.cls:834] — med, fix-risk low, in-story. Fixed: the requests addressed to IncidentManager must be exactly ` EvalIn>IncidentManager` (fresh `Test.Eval.Run` green).
- [x] [Review][Patch] Hermeticity: TestToolsWriteNothing's footprint and the host tests' Counts() compared namespace-wide state that the running production's own jobs change (the heartbeat's Tick header and StatusMark each minute, status and check events), the DW-349 shape [src/ocutalon/cls/OcuTalon/Test/Eval/Incident.cls:427] — med, fix-risk low, in-story. Fixed: up to ATTEMPTS (3) windows, since a background write lands in one window and a write of the branch in every one; Counts() counts only incident and watch.progress events.
- [x] [Review][Patch] The Ens.MessageBody term of the U-162 (3) footprint was always 0: %CLASSNAME names the queried table's class (measured on the warm stack: 0 with %CLASSNAME, 1 with x__classname; a sample row gave `Ens.MessageBody` against `~Ens.Request~OcuTalon.Core.Msg.RunTurns~`) [src/ocutalon/cls/OcuTalon/Test/Eval/Incident.cls:571] — med (a clause of U-162 (3) structurally unfalsifiable), fix-risk low, in-story. Fixed with `x__classname [ '~OcuTalon.'` and a control that the term counts the test's own IncidentCase body; mutation line under Verification.
- [x] [Review][Patch] The U-162 (3) footprint left out the bridge's tables: ^OcuTalonBP* (Decision, Usage, ApprovalRequest, ConversationLink rows) was excluded as "caches" [src/ocutalon/cls/OcuTalon/Test/Eval/Incident.cls:572] — low, two-way door, in-story. Fixed: the four tables are counted by rows; the doc is corrected.
- [x] [Review][Patch] The incident-count pass line said "each with a completed result row (the run has no problem)" whatever the problems check printed [eval/run.sh:173] — low, mechanical. Fixed: "all N incident case(s) were run".
- [x] [Review][Patch] The INFO line gave a count and a fixed explanation, not the fallbacks' reasons [eval/run.sh:187] — low, mechanical. Fixed: eval_run prints `CHK|fallback|<case>|<reason>` and the INFO line names each incident fallback with its reason (this review's run: the nine, each `invalid`).
- [x] [Review][Patch] A model-written `|` or line break in a cause field would shift the `CHK|case|` fields [eval/run.sh:96] — low, mechanical. Fixed: `$Translate` of `|`, CR and LF, as the problem lines do.
- [x] [Review][Patch] TestNotDecisionResponse's empty-answer half checked only that one ItemDecision went out [src/ocutalon/cls/OcuTalon/Test/Eval/Incident.cls:222] — low, mechanical. Fixed: a fresh case and log mark, AssertFallback and AssertNothingElse.
- [x] [Review][Patch] The class doc said every test asserts the forbidden sends and the row counts [src/ocutalon/cls/OcuTalon/Test/Eval/Incident.cls:5] — low, mechanical (Rule 14). Fixed: the shadow-instance tests do; the tool tests assert on answers.
- [x] [Review][Defer] Test.Live.GuideRefresh.TestHeldLockCallerWait has DW-349's exposure, as TestHeldLock had: it seeds Fixture.Check with no NextDueAt and asserts `seq = 1` [src/ocutalon/cls/OcuTalon/Test/Live/GuideRefresh.cls:217] — deferred: med, out-of-footprint (only the lead's TestHeldLock line is in this story); occurrence appended to DW-349 (routed owner=11-1-the-web-demo-path-passes-end-to-end-in-the-rel-2-test). The lead's TestHeldLock change itself is hermetic: `Ahead()` is pure, the row is the test's own and cleaned as before, and nothing else changed.
- [x] [Review][Defer] Test.Eval.Incident.Begin is the fourth private copy of the bridge-context Begin helper (Test.Eval.Checks, Test.Tools.Reminders, Test.Watch.Case) [src/ocutalon/cls/OcuTalon/Test/Eval/Incident.cls:521] — deferred: low (Rule 2, weak reason), not a two-way door (the shared home Test.Data.Fixture is contended); closed DW-430 wontfix-accepted with reopen_if.

Rejected:
- `false` — the live read_failed_messages answer is capped at five event-log rows now (blind-hunter): Read passes at most MAXMESSAGES log keys, and Reader.Evidence's eventLog holds only those rows when there is no header key, so a live answer never had more than five.
- `low` — EvalSnapshot scans the shared ^Ens.MessageBodyD extent with no index (blind-hunter, edge-case-hunter): it is reached only for owner eval, on throwaway, CI and release-candidate stacks, at a few ms per tool call; an index changes a stored message class's storage (a veto-window item).
- `low` — the eval branch takes an IncidentCase from any sender (blind-hunter): only EvalIn sends one, EvalIn is off in the product, and no product host holds an IncidentCase to resend (U-131).
- `low` — the footprint does not see an update of an existing row (blind-hunter): U-162 (3) asks for no new row and no global change, EvalSnapshot only selects, and a checksum of ^Ens.MessageBodyD would count the engine's own traffic.
- `low` — no clause-level mutation lines for run.sh's demo check, TestIsolation's body and row terms or TestHops' exact list (verification-gap): Rule 19 asks one per AC, and AC1, AC2 and AC3 each have demonstrated ones; the demo check's fields were confirmed on this review's run, where the same `$6` test picked out the nine fallbacks.
- `low` — the run.sh task bullet still reads as before the AC3 restatement (acceptance-auditor): its fix is an edit of the spec under review.

## Spec Change Log

- 2026-10-30, implement-stage intent gap (AC3 unreachable on the CI mock), lead ruling (decide): AC3 restated as the epic's AC3 (every incident case completes with a recorded diagnosis, cost and request size; the demo incident decided with no fallback, a cause and an element; the other nine decided or a validated fallback, reported); design note 7 corrected. The owner's U-162 condition added as three open `[U-162]` tasks and the U-162 acceptance criterion. Status reset to `in-review` (the implementation is in the tree, uncommitted; re-dispatch resumes at review).

- 2026-10-30, lead spec gate: Design Notes gained "Lead gate rulings" (DW-353 by construction accepted; U-162 veto for IncidentCase and the read-tool eval branch; spine row and diagram edge written by the lead). No intent change.

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 36 findings - high 0, medium 0, low 32, false 4, maybe-false 0
- findings:
  - Blind Hunter
    - `[low]` `[reject]` `EvalSnapshot` queries `IncidentCase` by `IncidentRef` with no index - evals are tens of rows between purges; an index changes the message class's storage (a veto-window item) for a path used by one test-only owner.
    - `[low]` `[reject]` `EvalDecision` rebuilds the pack for the Summary - once per case, a few ms; the fix means a new field on the message or a second code path.
    - `[false]` `[reject]` `ItemSettings` item from `failures[0]` differs from the pack's item - `Recorded` takes the pack's item from the same `failures[0].targetConfigName`; a snapshot with no failure builds no pack, so no tool is called for it.
    - `[low]` `[reject]` `run.sh` counts incident cases by a text grep - the 10 `case.json` files are repository content that `test-eval-set.sh` pins; a stray match needs a hand-made file and the check would still fail loudly.
    - `[low]` `[patch]` the `run.sh` pass message says "each decided" while the nine may be fallbacks - the message now says "each with a completed result row (the run has no problem)".
    - `[low]` `[reject]` nine of ten cases are fallbacks on the mock - by design (AC3 as restated; the spec change log of 2026-10-30).
    - `[low]` `[patch]` `TestEveryKindSent` hard-codes five kinds - the expected string is built from the kinds' count.
    - `[low]` `[reject]` `notRunYet` is dead code - kept on purpose (Decided in-stage 8); `TestEveryKindSent` pins it at 0.
    - `[false]` `[reject]` `OnError` swallows other keys - IncidentManager sends an `IncidentCase`'s Decide request with `DIAGNOSEKEY` only, so no other key reaches it.
    - `[low]` `[reject]` the demo snapshot path is repeated across test classes - the repeats existed (`Test.Agent.Decide`, `Test.Watch.Evidence`); a shared constant is a refactor of seven test classes.
    - `[low]` `[reject]` `SendIncident`'s `..` check over-rejects - the name rule is the one the other kinds use for files in a case folder; no recorded case names such a file.
    - `[low]` `[patch]` the footprint of `TestToolsWriteNothing` could fail on a background write - narrowed: `^OcuTalonBP*` (Decide's caches) is left out, and eight consecutive warm runs plus all shard parts were green.
  - Edge Case Hunter
    - `[low]` `[reject]` a failed send to EvalSink leaves the row `sent` - the spec's rule is one warning, nothing else ("A failed send to EvalSink logs one Type 3 warning").
    - `[low]` `[reject]` a snapshot with no `failures` is sent and ends as a fallback - the matrix row "Bad snapshot at IncidentManager" says exactly that.
    - `[low]` `[reject]` an incident case with a `watch` member ignores it - no recorded incident case has one, and the item path's watch belongs to injection cases.
    - `[false]` `[reject]` a symlinked or escaping snapshot name - the case folders are repository content, not input; the name check is the existing one.
    - `[low]` `[patch]` `TestEveryKindSent` hard-coded count - same root cause as the Blind Hunter row.
    - `[false]` `[reject]` removing `IncidentManager` from the deny list lets live messages through - `TestHops` requires every source and target in `ITEMPATH`, IncidentManager's requests to be exactly ` IncidentManager>Decide IncidentManager>EvalSink`, and `TestIsolation` forbids `Settle`, `DryRun` and `Execute` bodies and any `Incident` row.
    - `[low]` `[reject]` `TestIncidentPath` indexes `failures[0]` of a snapshot with none - the snapshot is the repository's demo file.
  - Verification Gap Reviewer
    - `[low]` `[patch]` AC2's `TestIsolation` had no demonstrated red for the `instance`-owned Incident row - `TestIsolation` can fail on it (`CountAbove` of `Incident` above the mark); demonstrated on a fresh stack: `TestIsolation` and `TestIncidentPath` red, reverted. Line written.
    - `[low]` `[reject]` `TestHops` control and exact-request strings have no mutation of their own - Rule 19 asks one demonstrated mutation per AC; AC1 has three.
    - `[low]` `[reject]` `Test.Eval.Cases` `TestRecordedCases` has none - AC3 has the `KINDS` mutation, red in `eval/run.sh` and `TestEveryKindSent`.
    - `[low]` `[reject]` the `eval/run.sh` demo-incident check has none - same AC3 row.
    - `[low]` `[patch]` the EvalIn tests (row opened with the `IncidentRef`; a failed send removes the row) had no mutation - both demonstrated on `Test.Eval.In` (warm) and written.
    - `[low]` `[reject]` the matrix rows of `Test.Eval.Incident` have no mutation of their own - covered by the AC1 rows.
    - `[low]` `[reject]` mutations were applied to one of the three tools - `TestToolsLiveWins`, `TestToolsOwnerGuard` and `TestToolsWriteNothing` loop over all three; the mutated code is identical in each.
    - `[low]` `[reject]` `DeleteIncidentCases` and the `Leftovers` term have no mutation - Rule 19's hermeticity row is the `Test.Eval.Incident` sweep; `Test.Eval.Run` runs on a fresh stack.
    - `[low]` `[reject]` the `empty = 0` assertion is not shown red - `holds >= 1` is the pin (shown red); `empty` only adds.
    - `[low]` `[patch]` hermeticity of the footprint (background writes) - the same root cause as the Blind Hunter row.
    - `[low]` `[reject]` `OnError` for other keys has no test - unreachable (see above).
  - Intent Alignment Auditor (descriptive; each divergence logged)
    - `[low]` `[reject]` an empty `IncidentRef` gives an error status and no `ItemDecision` - the matrix row says so.
    - `[low]` `[reject]` a failed delivery to EvalSink gives no decision - the matrix says one warning.
    - `[low]` `[reject]` `run.sh` checks the demo line and the count, and relies on `Report.Problems` for the others' completeness - the epic's AC3 as restated; `Problems` requires a `DecisionRef`, a cost and a size per row.
    - `[low]` `[reject]` an incident skip is now a problem - intended (AC3, `TestSkipped`).
    - `[low]` `[reject]` `Diagnose` and the three live reads were refactored onto shared helpers - Rule 2 asks for it; the live tests (`Test.Watch.Evidence`, `Diagnose`, `Lifecycle`) are green and unchanged in what they assert.
    - `[low]` `[reject]` `OrdersDefinition` reads the namespace and production from `Install.Step.Demo` - as `Test.Watch.Evidence` already did; `Test.Eval.Record` passes on it.

## Design Notes

**Architecture decisions (Rule 6).**

| AD | What it binds here |
|---|---|
| AD-15 | The only writer is IncidentManager, and the eval branch writes no row. The pack goes in the first request. |
| AD-16 | No dry run or Execute without approval: the eval branch asks for none. |
| AD-20 | Usage owner `eval`, which no session total or cap counts. The filters are owner-only and so kind-agnostic: `Budget.cls`:141, `Ownership.Rows`. |
| AD-22 | EvalIn, the product path and `EvidencePack.Build`. Its Prevents line, "a different path from the product", is why the read tools answer from the recording. |
| AD-26 | Each case is its own trace session, and the run Ref is the SuperSession. |
| AD-30 | IncidentManager sends EvalSink an `ItemDecision` with the incident's Ref as `ItemId`. |
| AD-6, AD-10 | The tool methods write nothing and make no AI Hub or Python call. Answers are bounded and read-only, and a read tool's output taints, as it does today. |
| AD-29, AD-33 | Every touched class is Lane A. |

No AC contradicts an AD's Rule.

**Decided in-stage:**
1. **The message.** `OcuTalon.Eval.Msg.IncidentCase` is in Eval, beside `TurnResult`, and carries the snapshot text, not a path: IncidentManager reads no file named by a message, and the trace shows what was diagnosed. The demo snapshot is 71 KB, which fits a `%String(MAXLEN="")` as `TurnResult`'s fields do.
2. **DW-353 is addressed by construction.** EvalIn mints the case's Ref, as AD-22 has it mint every case's fresh id, and IncidentManager uses it as the incident's Ref. So EvalIn knows the `ItemId` the `ItemDecision` will carry, and the existing `ItemId` match of `CaseResult.Pending` completes the row.
   - The entry's proposed `RunRef` + `SourceItemId` match and index would add a second match path, a storage change and an index for a case that no longer arises.
   - The entry's root cause, an incident row EvalSink cannot complete, is closed and tested (Integration AC). Flagged for the lead's gate, since the bullet named a mechanism.
3. **`SourceItemId` = the case's folder name**, as for turn cases (`In.cls`:368, the `CaseResult` doc).
4. **No `Incident` or `FailureGroup` row, settle wait or `watch.progress`** for an evaluation incident. A recorded batch has already settled. This is stricter than AC2's "owned by a session or instance", and the tests pin "none of any owner".
5. **The read tools' eval branch.** It mirrors 9.7's `EvalCheckResults`. Without it the mock's own script, and Haiku in 9.5's gate, would get `{"items": []}` against a pack showing 50 failures, which is a different path from the product. It is reachable only for owner `eval`, which only EvalIn and this branch set, and is read-only.
6. **Every failure ends the case as a fallback `ItemDecision`.** So `Report.Complete` lists it (no `DecisionRef`) and a mock run fails on it instead of waiting out `Wait`.
7. **No `mock-wrong` incident case.** The mock's default diagnosis already answers `data_format_change`/`OrderDate` for every incident, so on every push the other 9 of 10 score wrong or end as a fallback (measured at implement: the nine end as fallback `invalid`, because `RepairResend.CheckParameters` refuses `OrderDate` where their sample bodies lack it), which proves the scoring can say "wrong" [AMENDED 2026-10-30, lead ruling with the AC3 amendment]. The `markers` rule would also need a kind change.
8. **`Report` keeps the `notRunYet` field.** It is in the shape that 9.5 and 11.4 will read, and it now reads 0; `TestEveryKindSent` pins that it stays 0.
9. **`lane-a.yml` is unchanged.** Its existing push triggers stand (decided in 9.1 and 9.2), and `run.sh` carries AC3's checks.
10. **The ItemDecision's `Channel` is empty**, as the live diagnose request sets none.
11. **The send seams.** `DispatchIncident` is a sibling of `Dispatch`, not a generalised one, because `ZzIn` records typed fields per message.

**Siblings (extend, don't copy):**
- `DiagnoseRequest` and `SendDiagnose` are extracted from `Diagnose`.
- `ZzIncident` extends `Test.Watch.IncidentProbe`.
- `EvalSnapshot` follows `WatchAnswers.EvalCheckResults`.
- The tool reads take a source, like `EvidencePack.Build`.
- `Test.Eval.Incident`'s context tests follow `Test.Eval.Checks`.
- `OrdersDefinition` replaces two copies (DW-385).

**Integration and linkage (Rules 1 and 2).**
- **Consumes:**
  - `EvidencePack.Build`, `Load` and `Input` (Stories 0.10 and 5.4);
  - Decide (`diagnose`) and DiagnosisAgent (Epics 1 and 5);
  - `OcuTalon.Msg.ItemDecision` (Lane B, Story 0.4);
  - `EvalSink` and `CaseResult` (9.1), `Report` (9.2);
  - the ten recorded incidents (9.4, 9.9);
  - `Test.Watch.IncidentProbe` (Stories 5.3 to 7.6) and `Test.Contract.Mock.LogMark`/`LogSince` (Story 0.11).

  The integration AC exercises the real production, not a mock of these.
- **Consumed-by:**
  - Story 9.5: the demo-incident gate runs `Report.DEMOCASE` ten times on Haiku through this path, and reads `CaseResult`'s cause fields and `FixParameters` for `RepairResend.CheckParameters`.
  - Story 17.7: setting-change incidents recorded through `Eval.Record.Capture` run as incident cases.
  - Story 11.4: indirectly, through 9.5's result file.

**Ledger inbox:**
- DW-353 is addressed: Decided in-stage 2, and the tasks for `Eval/In.cls` and `Test/Eval/In.cls`, and the Integration AC.
- DW-385 is addressed: the `OrdersDefinition` tasks and the DW-385 AC.

**Footprint extensions:** none of these is a contended path.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`
- `src/ocutalon/cls/OcuTalon/Watch/EvidencePack.cls`
- `src/ocutalon/cls/OcuTalon/Tools/WatchReads.cls`
- `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls`
- `src/ocutalon/cls/OcuTalon/Test/Watch/OrdersDefinition.cls` (new)

**Veto-window items, for the lead's classification:**
- the new stored message class `IncidentCase` (a new message body; compare U-144);
- the read tools' eval branch (a new answer path for owner `eval`; read-only, no grant).

**Proposed spine text (for the lead).** No AD's Rule, Binds or Prevents changes.
- AD-33's ownership tables, "Cross-area classes and APIs", after the `TurnResult` row:
  `| \`OcuTalon.Eval.Msg.IncidentCase\` (AD-22): \`IncidentRef\`, \`SourceItemId\`, \`Snapshot\`, from \`EvalIn\` to \`IncidentManager\`; the Diagnosis agent's read tools read its \`Snapshot\` for owner \`eval\` | A | Story 9.6 |`
- Optional, in the Production diagram after `EVI["EvalIn (disabled)"] -->|"eval Item"| INT` (spine line 1049): `  EVI -->|"incident case"| INC`

**Lead gate rulings (2026-10-30, spec gate).**
- DW-353 by construction (Decided in-stage 2): accepted (decide). The entry's root cause, an incident row EvalSink cannot complete, is closed by EvalIn minting the `IncidentRef` and opening the row with it as `ItemId`; the bullet's `RunRef` + `SourceItemId` match and index are not built. The epics.md bullet carries the amendment.
- `OcuTalon.Eval.Msg.IncidentCase` (a new stored message body) and the read tools' eval branch: kept as planned, a veto-window ruling (inbox U-162), consistent with U-143 and U-144. Reversal is a fix story.
- **The owner's U-162 condition (answer 2026-10-30T07:39:17Z#494, applied by the lead):** keep the `IncidentCase` message and the read tools' eval branch, with tests proving that (1) the three read tools never take the eval branch for any owner but `eval`, including an owner set from chat or a tool call, (2) with a live incident in scope they answer live even for owner `eval`, and (3) the branch writes nothing: the same guard as 9.7's `check_status` (U-143). Folded in as the three `[U-162]` tasks and the U-162 acceptance criterion (tier-1, inside the story's intent).
- AC3 (implement-stage intent gap, 2026-10-30): restated as the epic's own AC3, decided by the lead; see the Spec Change Log.
- The proposed spine text is written by the lead: the `IncidentCase` row in the Structural Seed's cross-area table and the `EVI -->|"incident case"| INC` diagram edge (no AD block changed). Do not edit the spine.

**CI time (inference).**
- `shards-2` gains about 10 to 20 s: one more diagnosis in `Test.Eval.Run`, and the shadow-instance and context tests at under 2 s.
- The `evaluation` job (lane-a workflow) gains about 30 to 60 s: ten diagnoses of two mock requests each on DiagnosisAgent's one job. That is inside `Wait`'s 180 s and the job's 30 minutes. `shards` is unchanged.

## Verification

`<B>` stands for:
```
OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=implement'
```

**Run discipline.**
- Tags: fresh `e9s6i`, warm `e9s6iw`. QA and review use their own stage names and tags.
- Run every command from the epic-9 worktree root, in the foreground of its own call with `timeout: 600000`.
- Make one `iris_execute_tests` call per message, and pass `server` and `namespace` on every IRIS MCP call.

**Runtime targets.**
- Slot B: `server` `ocutalon-slot-b`, namespace `OCUTALON`, for `iris_server_info` and compile checks only. Never run a test, `EvalIn` or a fixture there.
- Every test runs on throwaways through `ci/iris.sh` with `<B>`.
- Tear down only `e9s6i` and `e9s6iw`.
- `Test.Eval.Run` asserts "no incident", so it runs on fresh stacks only.

**Shared surfaces:**
- `Eval.In.#KINDS`, read by `Report.AddSkipped` and `Test.Eval.In` `KindReason`.
- `Test.Eval.Run`'s counts, hops, deny list and `ITEMPATH`.
- `eval/run.sh`'s `CHK|case|` line (a seventh field) and its run-1 checks.
- The run's headers, the DiagnosisAgent queue and the mock log during a run.
- `EvidencePack`'s tool reads, read by `Test.Watch.Evidence` and `Test.Watch.Diagnose`, with live answers unchanged.
- The Orders definition's fixture settings, used by `Test.Watch.Evidence` and `Test.Eval.Record`.
- `IncidentManager.OnRequest`'s handled classes, pinned by `Test.Watch.Lifecycle` `TestUnknownRequest`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once, first) `iris_server_info` on `ocutalon-slot-b`, then load and compile every new or changed class on slot B, namespace `OCUTALON`. Copy `IncidentCase`'s generated `Storage Default` into its file. -- expected: build 154, port 1991, every class compiles.
- (once) `<B> OCUTALON_RUN_TAG=e9s6iw ci/warm.sh up` -- expected: ready, `LOCK acquired warm-iris`.
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s6iw ci/iris.sh class OcuTalon.Test.Eval.Incident`, and then, each in its own call, `OcuTalon.Test.Eval.In`, `.Test.Eval.Cases`, `.Test.Eval.Report`, `.Test.Eval.Record`, `.Test.Watch.Evidence`, `.Test.Watch.Diagnose`, `.Test.Watch.Lifecycle` and `.Test.Bridge.CodeRules` -- expected: each passed.
- (loop) `<B> OCUTALON_RUN_TAG=e9s6i ci/iris.sh class OcuTalon.Test.Eval.Run` -- expected: passed on a fresh stack, about 2 to 4 min. Measured: 98 to 103 s per call; the demo diagnosis's `DurationMs` is 342 on the CI mock (cost 0.000424 USD, largest request 1830 tokens).
- (loop) `bash docker/tests/test-eval-set.sh` -- expected: every rule passes.
- (once) `<B> OCUTALON_RUN_TAG=e9s6i bash eval/run.sh` -- expected: `eval/run: all checks passed`; ten incident lines, the demo's with fallback 0 and `data_format_change/OrderDate/repair_resend`, the other nine's fallbacks reported (INFO). Wall time 99 s (measured, ARM, fresh throwaway).
- (once) Fresh shard parts, each in its own call. Use `ci/iris.sh classes lane-a@rest` and `ci/iris.sh classes lane-a@Watch` to find the parts of `--part k/8` that hold the changed classes. Run `<B> OCUTALON_RUN_TAG=e9s6i ci/iris.sh shard lane-a@rest --part k/8` for each such part, then `--reverse`, and the same for `lane-a@Watch`. -- expected: every class passes, each call under about 8 min. Record the times.
- (once) `bash ci/checks.sh` -- expected: every block passes, including `storage`, `boundaries`, `eval-set`, `class-rules` and `ci-config`.
- (once, last; also after a failure) `<B> OCUTALON_RUN_TAG=e9s6iw ci/warm.sh down`, then `<B> OCUTALON_RUN_TAG=e9s6i ci/iris.sh teardown` -- expected: no lock of this stage is left in the lane-b folder.

**Planned mutations (Rule 19).** Apply each, observe the red, revert, confirm `git status --short` and `git diff --stat` are as before, then write the `mutation:` line.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 | `EvalAnswered` calls `..Propose(...)` with the fix | `Test.Eval.Incident` (`DryRuns` not empty) |
| AC1 | The eval request's `Input` is the raw snapshot text | `Test.Eval.Incident` `TestRequest` |
| AC1 | The ItemDecision's `ItemId` is the `SourceItemId` | `Test.Eval.Run` `TestIncidentPath` (the row stays sent) |
| AC2 | `EvalCase` saves an `Incident` row with owner `instance` | `TestIsolation`, and the `Test.Eval.Incident` counts |
| AC2 | The request's `OwnerRef` is `instance` | `TestUsage` (`others` > 0) |
| AC3 | `KINDS` without `incident` | `eval/run.sh` (the incident count check) and `TestEveryKindSent` |
| Tools | `EvalSnapshot` drops its owner check | `Test.Eval.Incident`, the non-eval read-tool test |
| Integration | `WatchReads` skips `EvalSnapshot` | `TestIncidentPath` (the `tool_result` is `{"items":[]}`) |
| DW-385 | `OrdersDefinition.Put` writes `credentialValue` to the note | `Test.Eval.Record` (the note value) |
| Hermeticity | `Test.Eval.Incident` keeps its `IncidentCase` bodies | its leftover check |

**Demonstrated mutations (implement stage; each applied, red observed, reverted with the tree byte-identical).**
- mutation: `EvalAnswered` also calls `SendDryRun` (the Propose seam) -> `Test.Eval.Incident` `TestUsableAnswers`, `TestFallbackAnswer`, `TestEvalSendFails` (DryRuns not empty).
- mutation: the eval request's `Input` is `case.Snapshot` -> `Test.Eval.Incident` `TestRequest` (Input and not-raw-text asserts).
- mutation: the ItemDecision's `ItemId` is the `SourceItemId` -> `Test.Eval.Run` `TestIncidentPath` (the row stays sent; also `TestItemPath`, `TestReport`, `TestUsage`).
- mutation: `EvalCase` saves an `Incident` row with owner `instance` -> `Test.Eval.Incident` row counts in every test (`TestIsolation` not run for this one).
- mutation: the eval request's `OwnerRef` is `instance` -> `Test.Eval.Run` `TestUsage` (Usage rows not owned by eval) and `TestIncidentPath`.
- mutation: `In.KINDS` without `incident` -> `Test.Eval.Report` `TestEveryKindSent`, `TestSkipped`, `TestText`, and `eval/run.sh` ("0 incident case(s) were run, but eval/ holds 10").
- mutation: `EvalSnapshot` drops its owner check -> `Test.Eval.Incident` `TestToolsNotEval`.
- mutation: `WatchReads.ReadFailedMessages` skips `EvalSnapshot` -> `Test.Eval.Run` `TestIncidentPath` (no tool result holds the body class).
- mutation: `OrdersDefinition.Put` writes `credentialValue` to the note -> `Test.Eval.Record` `TestCaptureDropsCredentialSettings`.
- mutation: `Test.Eval.Incident.Sweep` does nothing -> its leftover asserts in `TestToolsEval` and `TestToolsNotEval`.

- mutation: `EvalCase` saves an `Incident` row with owner `instance` (re-run on a fresh stack in the review pass) -> `Test.Eval.Run` `TestIsolation` ("no Incident row of any owner was written") and `TestIncidentPath` (the zero-rows assertion). AC2.
- mutation: `In.SendIncident` does not remove the row after a failed dispatch (`If opened` becomes `If 0`) -> `Test.Eval.In` `TestIncidentSendFails` and `TestSendFails` ("and the row is deleted").
- mutation: `In.SendIncident` opens the row with the case's name as `ItemId` instead of the `IncidentRef` -> `Test.Eval.In` `TestSendsIncident` ("found by the IncidentRef") and `TestIncidentSendFails`.

**U-162 mutations (re-dispatch implement; each applied, red observed, reverted with the tree byte-identical).**
- mutation: `EvalSnapshot` drops its owner check (the `OwnerRef = eval` term) -> `Test.Eval.Incident` `TestToolsOwnerGuard` (every case but owner eval: session Ref in a chat turn and in a tool call, `instance`, `Eval`, `EVAL`, `eval `, ` eval`, `evaluation`, empty owner) and `TestToolsNotEval`. U-162 (1).
- mutation: the owner check is widened to `$ZConvert(context.OwnerRef, "U") = "EVAL"` -> `TestToolsOwnerGuard` (the `Eval` and `EVAL` cases) and `TestToolsNotEval`. U-162 (1).
- mutation: `WatchReads.ReadFailedMessages` tries `EvalSnapshot()` before `Scope()` -> `TestToolsLiveWins` (the answer is the snapshot's, count 50 against the live incident's 3). U-162 (2).
- mutation: `EvalSnapshot` saves an `IncidentCase` row -> `TestToolsWriteNothing` (the row counts). U-162 (3).
- mutation: `EvalSnapshot` sets `^OcuTalonZzMutation = $Increment(^OcuTalonZzMutation)` -> `TestToolsWriteNothing` (the `^OcuTalon*` footprint). U-162 (3).

**QA stage (tags `e9s6qw` warm, `e9s6q` fresh; every mutation applied from a backup, red observed, reverted; `git status --short` and `git diff --stat` compared before and after each one and identical).**
- (QA) New file: `src/ocutalon/cls/OcuTalon/Test/Eval/SharedFixture.cls` (warm-safe TestCase; found by area `Eval`). It pins the DW-385 half that no test pinned: `TestNoPrivateCopy` (neither `Test.Watch.Evidence` nor `Test.Eval.Record` defines `FixtureSettings` or `DefinedSettings`, nor builds an `Ens.Config.Setting` in a method of its own), `TestHelperIsNotATest`, `TestNamesAreTheHelpers`.
- mutation (DW-385, no private copy): a `FixtureSettings` method added to `Test.Watch.Evidence` -> `Test.Eval.SharedFixture` `TestNoPrivateCopy`; a differently named method that builds an `Ens.Config.Setting` -> the same test.
- mutation (DW-385, values): `OrdersDefinition.Put` writes `credentialValue` to the note -> `Test.Eval.Record` `TestCaptureDropsCredentialSettings` (re-observed in QA).
- mutation (U-162 (1), owner dropped): `EvalSnapshot` without its `OwnerRef = eval` term -> `Test.Eval.Incident` `TestToolsOwnerGuard` (all ten owner cases, the chat-turn session Ref and the tool-call session Ref each red on their own) and `TestToolsNotEval`.
- mutation (U-162 (1), owner widened): `$ZConvert(OwnerRef, "U") = "EVAL"` -> `TestToolsOwnerGuard` (`Eval`, `EVAL`) and `TestToolsNotEval`.
- mutation (U-162 (1), turn and tool contexts): the owner check widened with `|| Kind = "turn" || Kind = "tool"` -> `TestToolsOwnerGuard` (the chat-turn and tool-call cases, session Ref and `instance`, red by name).
- mutation (U-162 (2)): `WatchReads` tries `EvalSnapshot()` before `Scope()`, applied to each of the three tools in turn -> `TestToolsLiveWins` red for `ReadFailedMessages`, `ReadEventLog` and `ReadItemSettings` each (the first also on the count 50 against 3).
- mutation (U-162 (3), row): `EvalSnapshot` saves an `IncidentCase` row -> `TestToolsWriteNothing`.
- mutation (U-162 (3), global in the helper): `EvalSnapshot` increments `^OcuTalonZzMutation` -> `TestToolsWriteNothing`.
- mutation (U-162 (3), global in the tool): `WatchReads.ReadEventLog` increments `^OcuTalonZzMutation6` -> `TestToolsWriteNothing`.
- mutation (AC1, request): the shared `DiagnoseRequest` sets `Input` to `pack.%ToJSON()` -> `Test.Eval.Incident` `TestRequest`.
- mutation (AC1, decision): the `ItemDecision`'s `ItemId` is the `SourceItemId` -> `Test.Eval.Run` `TestIncidentPath` (fresh stack).
- mutation (AC2, rows): `EvalCase` saves an `Incident` row of owner `instance` (`Test.Data.Fixture.Incident`) -> `Test.Eval.Run` `TestIsolation` ("no Incident row of any owner was written") and `TestIncidentPath`.
- mutation (AC2, usage): the request's `OwnerRef` is `instance` -> `Test.Eval.Run` `TestUsage` ("every one is owned by eval", "each has a Usage row of the owner eval") and `TestIncidentPath`.
- mutation (Integration): `WatchReads.ReadFailedMessages` skips `EvalSnapshot` -> `Test.Eval.Run` `TestIncidentPath` (the mock log's `tool_result` is `{"items":[]}`).
- mutation (AC3): `In.KINDS` without `incident` -> `Test.Eval.Report` `TestEveryKindSent`, `TestSkipped`, and `eval/run.sh` ("FAIL set: 0 incident case(s) were run, but eval/ holds 10"; exit 1).
- QA baselines after the mutations (tree clean apart from the new file): warm `Test.Eval.Incident` (2.5 s), `SharedFixture`, `Report`, `In`, `Record` (42 s) passed; fresh `Test.Eval.Run` passed (121 s); `eval/run.sh` exit 0 with `eval/run: all checks passed`.

**Code review (tags `e9s6rw` warm, `e9s6r` fresh; every mutation applied from a backup, red observed, reverted; `git status --short` and `git diff --stat` identical before and after each one; both tags torn down, the lane-b lock folder empty).**
- mutation (matrix "Decide refuses", AC1's one ItemDecision): `EvalAnswered` without its error-header guard (`If '$IsObject(answer) && ... %CurrentResponseHeader.IsError Quit $$$OK`) -> `Test.Eval.Incident` `TestRefused` ("one ItemDecision goes to EvalSink", "and one Type 3 warning names the case": two of each).
- mutation (U-162 (3), after the footprint's rework into up to three windows): `EvalSnapshot` increments `^OcuTalonZzMutation` -> `TestToolsWriteNothing` (red in window 3 of 3).
- mutation (U-162 (3), the `Ens.MessageBody` term, now `x__classname`): `EvalSnapshot` saves an `OcuTalon.Eval.Msg.TurnResult` body (no header, no counted table) -> `TestToolsWriteNothing` (window 3 of 3).
- Measured on the warm stack: `SELECT COUNT(*) FROM Ens.MessageBody WHERE %CLASSNAME %STARTSWITH 'OcuTalon.'` gave 0 where `x__classname [ '~OcuTalon.'` gave 1 (`%CLASSNAME` names the queried table's class).
- Baselines after the patches: slot B compile of `IncidentManager`, `ZzIncident`, `Test.Eval.Incident`, `Test.Eval.Run`; warm `Test.Eval.Incident` passed (2.79 s; 2.31 s after the reverts); fresh `Test.Eval.Run` passed (class 8.46 s, call 116 s, with TestHops' new "no item but EvalIn sends IncidentManager a request"); fresh `eval/run.sh` exit 0, `eval/run: all checks passed`, the INFO line naming the nine fallbacks, each `invalid`; `docker/tests/test-eval-set.sh` passed.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Incident cases are diagnosed through `IncidentManager`'s evaluation branch and reach nobody: EvalIn sends an `OcuTalon.Eval.Msg.IncidentCase` (a fresh Ref, the case name and the recorded snapshot), the branch builds the pack, asks Decide for a `diagnose` with owner `eval` and sends EvalSink one `ItemDecision`; the Diagnosis agent's read tools answer from the recorded snapshot for owner `eval` only. DW-353 (row opened with the minted Ref) and DW-385 (one shared Orders-definition helper) are folded in. This re-dispatch closed the review: AC3 as restated, the three `[U-162]` guard tests (in `Test.Eval.Incident`: `TestToolsOwnerGuard`, `TestToolsLiveWins`, `TestToolsWriteNothing`, each with demonstrated mutations), and the demo diagnosis's measurement (`DurationMs` 342 on the CI mock, cost 0.000424 USD, largest request 1830 tokens).

**Files changed** (all under `src/ocutalon/cls/OcuTalon/` unless stated)
- `Eval/Msg/IncidentCase.cls` (new): the message. `Eval/In.cls`: `incident` kind, `SendIncident`, `DispatchIncident` seam. `Eval/Data/CaseResult.cls`, `Eval/Sink.cls`, `Eval/Report.cls`: doc comments and the `notRunYet` text.
- `Watch/IncidentManager.cls`: `EvalCase`, `EvalAnswered`, `EvalRefused`, `EvalDecision`, `EvalDeliver`, the `DiagnoseRequest`/`SendDiagnose`/`SendEval` seams. `Watch/EvidencePack.cls`: `EvalSnapshot` and source-agnostic tool reads. `Tools/WatchReads.cls`: the eval fallback after `Scope()`.
- `eval/run.sh`: the incident checks (count, demo line, INFO count of the other fallbacks).
- Tests: `Test/Eval/Incident.cls` (new; the matrix, the read tools and the U-162 guards), `Test/Eval/ZzIncident.cls` (new), `Test/Eval/In.cls`, `ZzIn.cls`, `Cases.cls`, `Report.cls`, `Run.cls`, `Record.cls`; `Test/Watch/OrdersDefinition.cls` (new), `Test/Watch/Evidence.cls`.

**Review.** 36 findings (high 0, medium 0, low 32, false 4): 7 rows patched (5 root causes), 29 rejected with their reasons in the triage log. Patches: `TestEveryKindSent` derives its expected string; the `TestToolsWriteNothing` footprint leaves out `^OcuTalonBP*`; the `run.sh` pass message no longer says "decided"; three mutation lines (the `instance`-owned Incident row red in `TestIsolation` on a fresh stack; both EvalIn row mutations). Follow-up review recommendation: false (no high, no medium patched).

**Verification performed** (slot B compile check; throwaways on lane B, tags `e9s6i` and `e9s6iw`, both torn down; the lane-b lock folder is empty)
- Slot B: build 154; every changed class compiled.
- Warm, each green: `Test.Eval.Incident` (also eight consecutive runs), `In`, `Cases`, `Report`, `Record`, `Test.Watch.Evidence`, `Diagnose`, `Lifecycle`, `Test.Bridge.CodeRules`.
- Fresh: `Test.Eval.Run` passed (98 to 103 s per call); `docker/tests/test-eval-set.sh` passed; `eval/run.sh` exit 0 with `eval/run: all checks passed` (99 s; ten incident lines, the demo `data_format_change/OrderDate/repair_resend` with fallback 0, the other nine reported as fallbacks, INFO); shard parts `lane-a@rest` 5/8 (161 s), 6/8 (178 s), 2/8 (146 s) and reversed 3/8 (154 s), 4/8 (163 s), 7/8 (171 s), and `lane-a@Watch` 1/8 (162 s) and reversed 7/8 (86 s), all passed; `bash ci/checks.sh` passed (201 s).
- Mutations: all in `## Verification` (the `[U-162]` items by the lines under "U-162 mutations").

**Residual risks.**
- On the CI mock, nine of ten incident cases end as fallback `invalid` (the AC3 restatement); only the real-model gate of Story 9.5 measures their cause scores.
- `TestToolsWriteNothing` reads the `^OcuTalon*` globals (except `^OcuTalonTest` and `^OcuTalonBP*`) before and after; a background writer to another product global during the two reads would fail it (not seen in eight warm runs and the shard parts).
- The 342 ms `DurationMs` is the mock's, not a model's.
