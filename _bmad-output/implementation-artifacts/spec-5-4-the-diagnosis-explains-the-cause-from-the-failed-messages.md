---
title: 'The diagnosis explains the cause from the failed messages'
type: 'feature'
created: '2026-10-26'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** When the settle rule ends (Story 5.3), nothing explains the incident. `DiagnosisAgent` has no `ReplyClass`, so `Decide` refuses every `diagnose` request. `OcuTalon.Tools.Watch` is Story 1.1's fixture and reads nothing, and no evidence pack exists. UJ-1 needs the 50 failed orders explained (a changed order-date format) before the notice can say what broke.

**Approach:** At the settle end, `IncidentManager` publishes `watch.progress` `diagnosing`, builds one evidence pack with `OcuTalon.Watch.EvidencePack.Build(source)` (live through `Watch.Reader`, or from a recorded snapshot), and sends it as the `Input` of a `diagnose` request through `Decide`, in the incident's own trace session. `DiagnosisAgent` answers with one JSON object, checked against the new `OcuTalon.Watch.Msg.DiagnosisPayload`, and can use the real read-only watch tools. `IncidentManager` stores the diagnosis, or the bridge's fallback, on the incident row. The item noun comes from the diagnosis, else from `OcuTalon.Watch.ItemNoun`. The notice itself (its variants, `NoticedAt`, the `Notification`s, the `incident` event and its payload fields) belongs to the sibling story of ruling R1.

## Boundaries & Constraints

**Always:**
- **Settle end to diagnosis.** When the waiter fixes `NoticeCount` (Story 5.3), `IncidentManager`:
  - stores the code noun `ItemNoun.For(<the sample's body class>)` on the row;
  - publishes `watch.progress` `diagnosing` (`Live.Payload.WatchProgress`) to each `Session.Recipients` session, after commit;
  - builds the live pack;
  - sends one `OcuTalon.Bridge.Msg.Request` to the `Decide` item, asynchronously, with a response required and completion key `diagnose`. The request carries:
    - `Kind` `diagnose` and `Provenance` `untrusted`;
    - `ItemId` the incident's `Ref`, and `OwnerRef` the incident's owner;
    - `TraceRef` the waiter's `%SuperSession`, and `ThreadSessionId` the waiter's `%SessionId`, which is the incident's `TraceHeaderId`;
    - `Summary` `"<count> failures at <item>"`, code-written, at most 80 characters;
    - `Input` `EvidencePack.Input(pack)`.

  It never goes to `OutcomeRouter` (AD-30). `Decide`'s one decision per (`ItemId`, `Kind`) makes a repeat return the recorded diagnosis.
- **The answer.** A `DecisionResponse` sets `DecisionRef`, `Fallback` and `FallbackReason` on the row.
  - A usable answer (`Fallback` 0) also sets `Cause`, `CauseCategory`, `Element` (from `elementAtFault`) and `FixSummary` from the checked `Payload` JSON, and `ItemNoun` when the payload gives both forms.
  - A fallback stores no cause, category, element or fix (AD-8).
  - An error status from `Decide` is a refused request. It stores `Fallback` 1 with reason `error` and logs one Type 3 warning through `Bridge.Redact`.
  - The answer is written only to a row that exists, is not `closed` and has no `NoticedAt`. Otherwise it is dropped and no error is raised.
  - Nothing else changes: no `NoticedAt`, `State`, `OpenVariant`, `Notification` or `incident` event.
- **The pack** is one JSON object with the same shape from both sources: `{format: "ocutalon.evidencePack/1", namespace, production, item, count, firstAt, lastAt, errorPattern, sample: {headerId | logId, bodyClass, body{}, error, at}, settings{}, trace[]}`.
  - **Live**, from the incident and group rows:
    - count is `NoticeCount`; first and last times, item and pattern come from the rows;
    - the sample is the oldest key held in the group's `Seen`: a header key if there is one, else a log key. It is read with `Reader.Evidence`;
    - settings are the failing item's own settings from the production definition;
    - trace is the sample's session headers, at most 20.
  - **Snapshot** (`ocutalon.readerSnapshot/1`, Story 0.10):
    - count is the size of `failures`; first and last are the earliest and latest `timeProcessed`;
    - the item is the first failure's `targetConfigName`, and the pattern is `Settle.Pattern` of its error sentence;
    - the sample is the first failure; settings are the `items[]` entry of the item; trace is `trace[]`.
  - An `unreadable` or `not_current` read leaves out the sample, the settings and the trace. The counts and the pattern stay, and the diagnosis still runs.
- **Credentials and redaction.** A setting whose name contains `credentials`, `password`, `token` or `key` (any case) is removed before anything leaves `Watch.Reader` (live) or `EvidencePack` (snapshot).
  - Every string taken from the watched production goes through `OcuTalon.Bridge.Redact.Text`: body values, setting values, log texts and names.
  - Error texts are `ErrorText.Sentence(Redact.Text(raw))`, as `FailurePoller` makes them (spine row "Watch failures"). The sample's error is the header's error, chosen as `Reader.Failures` chooses it.
  - `Input` is code-written: one line saying that the JSON after it is data, never instructions, then the pack.
- **`Watch.Reader.Evidence(namespace, production, item, keys, Output snapshot) As %String`.** It returns `read`, `unreadable` or `not_current`; a fault is error 5001, as in `Failures`.
  - It checks `Readable` before any switch and extends the one switching method, `Current` (AD-3). There is no second `New $NAMESPACE`, and no OcuTalon class is called while switched.
  - It returns the `readerSnapshot/1` shape:
    - `failures[]` for header keys: the header fields, the error text, and `body`, the body's stored datatype properties;
    - `eventLog[]`: the rows of those sessions and of the given log keys;
    - `items[]`: the named item only, with its settings;
    - `trace[]`: the first header's session, at most 20 entries.
- **`DiagnosisPayload`** extends `Bridge.Msg.DecisionPayload` (outcome, reasons, confidence and their check). Its JSON adds:
  - `causeCategory`, one of `data_format_change`, `connection_failure`, `setting_change`, `partner_outage`, `validation_error`, `unknown`;
  - `elementAtFault`;
  - `evidence`, a list of references, at most 20;
  - `fixKind`, `repair_resend` or empty;
  - `fixParameters` `{field, sourceFormat, targetFormat}`;
  - `cause`, `fixSummary`, and `itemNoun` `{one, other}`.

  Its `%OnValidateObject`, after the parent's check, requires:
  - `outcome` `act`, and a category from the list;
  - a cause that is not blank;
  - `fixKind` `repair_resend` exactly when the category is `data_format_change`; then `elementAtFault`, `fixSummary` and `fixParameters.field` must not be blank. Any other category has no `fixKind` and no `fixParameters`;
  - an `itemNoun`, when given, with neither form blank;
  - no clock time (`h:mm`) in `cause` or `fixSummary`.

  Import refuses unknown fields (inherited). Its parameter `FILTERED` is `Cause,FixSummary`.
- **`Decide`** (bridge, generic) filters the reasons, then filters once, with `ReplyFilterClass`, each string property that the reply class names in a `FILTERED` parameter. It then validates the payload again, and a reply that fails is `invalid` (AD-31). A reply class without `FILTERED` behaves as today.
- **The agent.** `DiagnosisAgent`'s `ReplyClass` is `OcuTalon.Watch.Msg.DiagnosisPayload` (`Production.cls`, Lane A region). `Agent.Diagnosis`'s `INSTRUCTIONS` describe the pack, the tools and the reply object, with no `{{`. `MODEL`, `MOCKKEY`, `EFFORT` and `TOOLSETS` are unchanged.
- **The tools.** `OcuTalon.Tools.Watch` keeps its name, its tool names (`Tools.Names`) and `ReadOnly`. Its methods move to `OcuTalon.Tools.WatchReads`, which replaces `WatchFixture`, with the same step labels and classification: safe, read-only, not trusted output.
  - The methods take no arguments. Each reads the incident whose `Ref` is the bridge context's `ItemId` and whose `OwnerRef` is the context's `OwnerRef`, and returns through `Return`:
    - `read_failed_messages`: `{count, items[≤5]: {headerId | logId, item, at, bodyClass, body, error}}`;
    - `read_event_log`: `{items[≤20]: {logId, at, type, item, text}}`;
    - `read_item_settings`: `{item, settings}`.
  - With no such incident, or no context, each returns `{"items": []}`.
  - They write nothing, make no `%AI` or Python call, and call only classes in CodeRules' `CALLBACKHELPERS` and `READERCLASSES`.
- **`ItemNoun.For(bodyClass)`** gives `{"one":"order","other":"orders"}` for `OcuTalon.Demo.Orders.PartnerOrder`, else `{"one":"message","other":"messages"}`, as JSON text, the form `Incident.ItemNoun` stores.
- **Unchanged.** `IncidentManager` keeps `STUB`, `PoolSize` 1 and its 5003 answer to anything else. It stays the only writer of `Incident` and `FailureGroup` and the only publisher of `watch.progress` and `incident`.

**Never:**
- No notice of any variant: no `NoticedAt`, no `Notification`, no catalog key or `Slots`, no `State` or `OpenVariant` change, no `incident` event, and no change to `Live/Payload/*`. These are the sibling story's (R1); the with-fix notice follows R2.
- No schema change: `Incident` already holds every field this story writes. No edit to a contended path.
- No change to `Msg/*`, `Core/*`, `Data/Session.cls`, `Data/Ownership.cls`, `Data/Setting.cls`, `Live/*`, `ci/units.sh`, the CI workflows, `eval/` (its codes are adopted as they are) or `Test/Demo/*`.
- No embedded SQL and no unchecked prepare. No write from a tool, and no namespace switch outside `Watch.Reader`. The model never chooses the namespace, production or message read.
- No real model call (the CI mock only), and no NFR-7 time assertion: the 20-second diagnosis is measured in the rehearsal.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Demo (real poller, default scenario) | Session A watches Orders; 50 failing orders tagged with A; mock scenario `diagnosis` | A's stream gets `noticed`, `settling`, `diagnosing` in that order. One `Decision` of kind `diagnose`: `ItemId` the incident's `Ref`, `TraceSessionId` the incident's `TraceHeaderId`. The row has `CauseCategory` `data_format_change`, `Element` `OrderDate`, the scenario's `Cause` and `FixSummary`, `ItemNoun` order/orders, `Fallback` 0, that `DecisionRef`, and `NoticedAt` still empty. No `Notification` and no `incident` event | none |
| What the model saw | Same run, the mock's log | The first request's user text holds the pack: count 50, item `OrdersFromPartner`, the measured sentence, a body with `OrderDate` `10/16/2026`. The second request holds `read_failed_messages`' result: the header ids of real failed orders and the sentence | none |
| Snapshot | `eval/orders-date-format/snapshot.json`; a `diagnose` request with its `Input` sent to `Decide` | The pack has count 50, `firstAt` and `lastAt` `2026-10-20T10:37:45Z`, item `OrdersFromPartner`, a sample body (`OrderDate` `10/16/2026`) with its sentence, that item's settings and the trace excerpt. The decision is usable: `causeCategory` `data_format_change`, `elementAtFault` `OrderDate`, `fixKind` `repair_resend`, `itemNoun` order/orders | none |
| No fix | Synthetic failure whose text holds `[[mock:diagnosis-nofix]]` | `CauseCategory` `partner_outage`, `Cause` set, `FixSummary` empty. The scenario gives no noun, so `ItemNoun` is message/messages | none |
| Unknown | Text holds `[[mock:diagnosis-unknown]]` | `CauseCategory` `unknown`, no fix | none |
| Invalid / refusal | Text holds `[[mock:invalid-reply]]`, or `[[mock:refusal]]` | `Fallback` 1 with `invalid` or `refusal`; `Cause`, `CauseCategory`, `Element` and `FixSummary` empty; `ItemNoun` the code noun; `DecisionRef` the fallback decision's | Decide classifies; nothing raised |
| Refused request | `Decide` answers with an error status | `Fallback` 1, `FallbackReason` `error`, one Type 3 warning | warning, row stands |
| Gone before the answer | `[[mock:diagnosis-late]]` (delayed reply); the incident deleted after `diagnosing` | The answer writes nothing: no row comes back and no error is logged | dropped |
| Unreadable / not current | The incident's namespace unreadable, or another production | The pack has counts and pattern but no sample, settings or trace; the diagnosis runs | none |
| Credentials | A snapshot item with settings `Credentials`, `SMTPPassword`, `BotToken`, `ApiKey`, `TargetConfigName`; and `Reader`'s name rule over the same names | Only `TargetConfigName` reaches the pack, and the rule keeps only that name | none |
| Tools in scope | Bridge context `ItemId` = a fixture incident's `Ref` over real failed orders, with the matching owner | `read_failed_messages`: at most 5 items, with header ids, sentence and body. `read_event_log`: the sessions' rows. `read_item_settings`: `OrdersFromPartner`'s settings | none |
| Tools out of scope | No context; an unknown `ItemId`; another owner | Each tool returns `{"items": []}` | none |
| Payload check | Rows: usable data-format; usable `partner_outage`; `unknown`; refused: outcome `tellnow`, an unlisted category, `fixKind` on `partner_outage`, data-format without `fixKind`/`fixSummary`/`fixParameters.field`/`elementAtFault`, blank cause, a noun with a blank form, an unknown field, confidence 2, no reasons, `cause` holding "since 14:12" | Accepted or refused as listed (`Decide.CheckReply`) | none |
| Filtered texts | A filter that changes or blanks text; reply class `DiagnosisPayload` | The stored `Payload` holds the filtered `cause` and `fixSummary`; a cause filtered to blank is `invalid` | none |
| Item noun | `OcuTalon.Demo.Orders.PartnerOrder`; `Ens.StringRequest`; `""` | order/orders; message/messages; message/messages | none |

</intent-contract>

## Code Map

Every `OcuTalon/...` path is under `src/ocutalon/cls/` unless it starts with `Bridge/`, which is under `src/bridge/cls/OcuTalon/`.

- `OcuTalon/Watch/IncidentManager.cls` (5.3, 265 lines):
  - `Check` L221 ends the settle rule (`NoticeCount`). The diagnosis starts there.
  - `OnResponse` L55 ignores `pCompletionKey`: dispatch on `settle` (`ALARMKEY`) and `diagnose`.
  - `Tell` L242 publishes to `Recipients`. `Waiting` L233.
  - Precedent for the Decide call: `Core/Intake.cls` `Send` L250, the call L83, `RequestFor` L151-164, `OnError` L99 (keeps the error by key) and `OnResponse` L108 (`$Case(pCompletionKey, ...)`).
- `Bridge/Process/Decide.cls`:
  - `RUNNERS` L95 (`diagnose:DiagnosisAgent`); `CheckSettings` L524 (today's refusal, L531); `CheckReply` L543 (`%JSONImport` then `%ValidateObject`, public); `Conclude` L735; `Interpret` L800 (filters `Reasons` only at L810, re-exports the payload JSON).
  - `TimerSeconds` 60 (L158). A timeout answers a normal fallback `DecisionResponse`; only an `Admit` or settings refusal is an error status.
  - `Data.Decision` `(ItemId, Kind)` is unique; `TraceSessionId` is Decide's `%SessionId`.
- `Bridge/Msg/DecisionPayload.cls`: the sibling to extend (`Outcome`, `Reasons`, `Confidence`, `%OnValidateObject`; import refuses undeclared fields). `Bridge/Msg/Request.cls`: no correlation ref, so `ItemId` carries the incident `Ref`. `Bridge/Msg/DecisionResponse.cls`: `Payload` holds the checked JSON.
- `Bridge/Context.cls` `FIELDS` L13 and `Current()` L90: `.ItemId` and `.OwnerRef` are how tools read the request (e.g. `Tools/CommandCall.cls:70`).
- `OcuTalon/Production.cls` L28-30: the `DiagnosisAgent` item, in Lane A's region L15-41. `TriageAgent` L26 shows the `ReplyClass` setting line. `Test/Install/Production.cls:619` is the oracle row (lane A, not Epic 13's lines).
- `OcuTalon/Agent/Diagnosis.cls`: `INSTRUCTIONS`, `MOCKKEY` `diagnosis`, `TOOLSETS`.
- `OcuTalon/Tools/Watch.cls` (toolset, `DependsOn` the provider) and `Tools/WatchFixture.cls` (labels and classification parameters to keep; `{"items": []}` answers). `Tools/Names.cls` L22-29 (tool names). `Tools/Result.cls` `Return` (a 40,000-character step room; never pre-encoded JSON).
- `OcuTalon/Watch/Reader.cls`:
  - `Failures` L149 (`Readable` check, `ServiceUser` through `Bridge.Ext.Accessor`, fault 5001).
  - `Current` L169-266, the one switch, with no "what" argument today. It does not select `MessageBodyId`; the header SELECT is L194.
  - `Readable` L135. The failure rows' keys are documented at L25.
- `OcuTalon/Watch/Msg/Failure.cls` `BodyClass` L21, which `FailurePoller` sets at L111 and `IncidentManager` does not keep. `FailurePoller.cls:112` makes the redact-then-`Sentence` error text. `Watch/ErrorText.cls` `Sentence` L33; `Watch/Settle.cls` `Pattern`; `Watch/Mark.cls` `KeyOf` L67.
- `eval/orders-date-format/snapshot.json` (71 KB; `format`, `source`, `failures[50]`, `eventLog[50]`, `items[3]`, `trace[1]`) and `case.json` (`expectation`: `data_format_change`, `OrderDate`, `repair_resend`). Mounted read-only at `/opt/ocutalon/eval/` in throwaways (`docker/tests/compose.throwaway.yml:3`). Its builder `Test/Demo/Production.cls` `Snapshot` L445-507 (Epic 4's, contended, read only) is the model for the body, settings, trace and log reads.
- Orders: `OcuTalon.Demo.Orders.PartnerOrder` (`OrderNumber`, `OrderDate` MAXLEN 20, `Sku`, `Quantity`; `%XML.Adaptor` through `Ens.MessageBody`). The failing item is `OrdersFromPartner`, and the sentence is `Test/Watch/Case.cls:50` `ORDERDATETEXT`.
- Item settings: `Ens.Config.Production` items, with `item.Settings` as `Ens.Config.Setting` Name/Value (production definition, as the snapshot does). `irislib/Ens/Config/Item.cls` `PopulateVirtualSettings` L642 is not used (see Decided in-stage).
- `OcuTalon/Data/Incident.cls`: every field written here already exists (`ItemNoun`, `Cause`, `CauseCategory` 32, `Element` 128, `FixSummary`, `Fallback`, `FallbackReason`, `DecisionRef`). `Data/FailureGroup.cls`: `ItemName`, `ErrorPattern`, and `Seen` (newest last).
- `OcuTalon/Live/Payload/Part/ItemNoun.cls` (`One`/`Other`, JSON `one`/`other`; already in `CALLBACKHELPERS`) is reused as the payload's noun type. `Live/Payload/WatchProgress.cls` `STAGES` includes `diagnosing`.
- `ci/mock/`:
  - `mock.mjs` `select` L249: a marker in the newest user text wins over the `mockkey` header. Replies are indexed by the assistant messages since that text.
  - `scenarios/A/diagnosis.json` is today's shape, with no `outcome`. `refusal.json` and `invalid-reply.json` are marker scenarios to reuse.
  - `test/scenarios.test.mjs:109` `STORY_SCENARIOS` holds names only; `test/constants.test.mjs:70-96` requires one `mockkey` scenario per agent, and that tool names in `mockkey` scenarios are `Tools/Names.cls` values.
- Tests that pin the fixture or the refusal, and that this story updates:
  - `Test/Agent/Decide.cls:433` `TestDiagnoseNeedsReplyClass`;
  - `Test/Agent/Runners.cls:288-298` (`RunnerFixture.DIAGNOSISTEXT` L83, tool result `{"items":[]}`) and `:319` (provider);
  - `Test/Agent/Instructions.cls:119-135` (tools run with `{"production":...}`);
  - `Test/Tools/Result.cls:211`;
  - `Test/Bridge/Gate.cls:70,93` (`WATCH`, `READONLYTOOLS`);
  - `Test/Bridge/CodeRules.cls:434,451,473-477,684`, and the lists `CALLBACKHELPERS` L67 and `READERCLASSES` L70;
  - `Test/Bridge/Decide.cls:1546-1549` (the toolset's tool JSON is over 500 characters).
- Test helpers:
  - `Test/Watch/Case.cls`: `Fail` L455, `Failed` L475, `SendBatch` L880 (synthetic ids from 900000000; text into the pattern), `Begin` L379 (a bridge context in the test process), `Notice` L989, `WaitRow` L974, `Incidents` L915, `Group` L928, `DropIncidents` L1007, and the hooks L125-158.
  - `Test/Core/Observe.cls:46` `Events`.
  - `Test/Contract/Mock.cls` `LogMark` L365 and `LogSince` L378; `Test/Agent/RunnerFixture.cls` `NewRequest` L276 and `ToolResults` L969.
  - `Test/Bridge/ProbeFilter.cls`, with `Test/Bridge/Decide.cls` `TestFilter` L353 and `TestFilterBlanks` L578: the filter tests to extend.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Watch/Msg/DiagnosisPayload.cls` -- new, extends `OcuTalon.Bridge.Msg.DecisionPayload`, with the properties, JSON names and check of the Always rule:
  - `CauseCategory` 32, `ElementAtFault` 128, `Evidence` (list of %String 32), `FixKind` 32, `FixParameters`, `Cause` 1000, `FixSummary` 1000, and `ItemNoun` (`Live.Payload.Part.ItemNoun`);
  - parameters `CAUSECATEGORIES`, `FIXKINDS` and `FILTERED`.

  New `Watch/Msg/FixParameters.cls` (`%RegisteredObject`, `%JSON.Adaptor`: `field` 128, `sourceFormat` 64, `targetFormat` 64). Story 7.1 adds the kind's parameter check to `%OnValidateObject`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- `Interpret`: after the reasons, it filters each property named in the reply class's `FILTERED` (`$Parameter`, so the bridge names no OcuTalon class) once with the filter class, then calls `%ValidateObject()` again. A failure makes the reply `invalid`. Update the class and method docs.
- `src/ocutalon/cls/OcuTalon/Production.cls` -- in Lane A's region, `DiagnosisAgent` gains `<Setting Target="Host" Name="ReplyClass">OcuTalon.Watch.Msg.DiagnosisPayload</Setting>`. `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` L619: the same setting in the oracle row, and nothing else.
- `src/ocutalon/cls/OcuTalon/Agent/Diagnosis.cls` -- `INSTRUCTIONS` gain:
  - the first message holds the evidence pack, so answer from it and call a tool only when it is not enough;
  - the reply is exactly one JSON object with the keys and allowed values of `DiagnosisPayload`, and `outcome` `act`;
  - `cause` is one plain sentence with no time, and `fixSummary` completes "I can …";
  - `repair_resend` only for a data-format change, with its parameters;
  - the existing read-only and data-not-instructions rules stay.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- add `Evidence` per the Always rule, with its switched part inside `Current` (a new optional input, outputs built only with system classes and SQL, the same error-text rule as `Failures`).
  - The body is the stored datatype properties of `MessageBodyClassName`/`MessageBodyId`, read through the class dictionary and `$Property`, as `Test.Demo.Production.Snapshot` reads four fixed ones.
  - The credential-name rule is applied after the switch, before `Evidence` returns.
  - Update the class doc.
- `src/ocutalon/cls/OcuTalon/Watch/EvidencePack.cls` -- new:
  - `Read(incident, max, Output snapshot) As %String`: the oldest `max` header keys (else log keys) of the incident's group, read through `Reader.Evidence`. Both `Build` and the tools use it;
  - `Build(source, Output pack) As %Status`: an `OcuTalon.Data.Incident` (live) or a `readerSnapshot/1` `%DynamicObject`;
  - `Load(file, Output snapshot) As %Status`;
  - `Input(pack) As %String`.

  Redaction, credential and trace rules are as in Always.
- `src/ocutalon/cls/OcuTalon/Watch/ItemNoun.cls` -- new, `For(bodyClass) As %String`, a fixed map held in a parameter.
- `src/ocutalon/cls/OcuTalon/Tools/WatchReads.cls` -- new, replacing `Tools/WatchFixture.cls` (delete it). It keeps the three methods' names and their `STEPLABEL*`, `CLASSIFICATION*`, `READONLY*` and `TRUSTEDOUTPUT*` parameters. The methods take no arguments and follow the tool rule in Always, reading through `EvidencePack.Read`. `src/ocutalon/cls/OcuTalon/Tools/Watch.cls`: `Class=` and `DependsOn` name `WatchReads`, and the doc drops "fixture". Fix the comment in `Tools/Watching.cls:4`.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- in `Check`, at the settle end, add the steps of the Always rule. Add `OnResponse` dispatch by key and a `diagnose` answer handler, plus `OnError` for the `diagnose` key (fallback `error` and one warning). Add parameters for the target (`Decide`), the key and the warning texts, and update the class doc. `STUB` stays.
- `ci/mock/scenarios/A/diagnosis.json` -- the final reply becomes a `DiagnosisPayload` object:
  - `outcome` `act`, `data_format_change`, `OrderDate`, `repair_resend`;
  - `fixParameters` `{field: "OrderDate", sourceFormat: "MM/DD/YYYY", targetFormat: "YYYY-MM-DD"}`;
  - a `cause` and a `fixSummary` sentence, `itemNoun` order/orders, `evidence`, reasons and confidence.

  The tool call stays. New marker scenarios:
  - `diagnosis-nofix.json`: `partner_outage`, no fix, no `itemNoun`, no tool call;
  - `diagnosis-unknown.json`: `unknown`;
  - `diagnosis-late.json`: a valid reply with `delayMs` 6000.

  `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls` `DIAGNOSISTEXT`: the new final text.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- add every class the tools now reach to `READERCLASSES` and `CALLBACKHELPERS`: `Watch.EvidencePack`, `Data.FailureGroup`, `Watch.ErrorText`, `Watch.Settle`, and any other the implementation calls. Rename the provider in L434, L451, L473-477 and L684.
- Existing tests, for the new toolset and agent:
  - `Test/Agent/Decide.cls`: replace `TestDiagnoseNeedsReplyClass` with `TestSnapshotDiagnosis` (the Snapshot row through `Decide`, using `EvidencePack.Load`/`Build`/`Input` and `RunnerFixture.NewRequest`; also `[[mock:invalid-reply]]` gives fallback `invalid`);
  - `Test/Agent/Runners.cls` (provider name; the no-incident result stays `{"items":[]}`);
  - `Test/Agent/Instructions.cls` (no arguments, `{"items":[]}` with no context);
  - `Test/Tools/Result.cls:211`;
  - `Test/Bridge/Gate.cls:70,93`;
  - `Test/Bridge/Decide.cls:1546` (keep the estimate assertion true, or restate its bound from the new tool JSON);
  - `Test/Bridge/Decide.cls`: add `TestFilterDiagnosis` (the Filtered texts row, with `ProbeFilter`).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls`:
  - the cleanup also deletes the `diagnose` `Decision` rows of the incidents it deletes;
  - add `WaitDiagnosed(ref, seconds)` (waits until `DecisionRef` is set or `Fallback` is 1; reopens the row each poll, as `WaitRow` does);
  - `Notice(ref)` callers first wait for the diagnosis, so a whole-row save by `IncidentManager` cannot write over the fixture.
- `src/ocutalon/cls/OcuTalon/Test/Watch/IncidentProbe.cls` -- add a public method that calls `IncidentManager`'s `diagnose` error handler and nothing else, as `Say` calls `Tell`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Incidents.cls` -- update the assertions that count `watch.progress` events after the settle end (`diagnosing` now follows `settling`), and the tests that call `Notice`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Payload.cls` -- new, pure (warm): the Payload check rows through `Decide.CheckReply`, and the Item noun rows.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls` -- new (needs OCUORDERS and demo mode; warm-capable, since it calls no production item). Tests:
  - `TestSnapshotPack` (Snapshot pack fields);
  - `TestLivePack`: a fixture incident and group over `Case.Fail` headers, with no watch, so the poller makes nothing. It checks the sample, sentence, settings, trace and counts, and `Reader.Evidence`'s shape;
  - `TestUnreadable` (Unreadable / not current);
  - `TestCredentialsLeftOut` (the snapshot path, and `Reader`'s name rule as a pure class method, which `Evidence` applies after the switch);
  - `TestToolsReadTheIncident` (Tools in scope and out of scope, through `Case.Begin`).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Diagnose.cls` -- new, over the running production (fresh only; it fails with the reason where OCUORDERS or demo mode is missing). Tests:
  - `TestDemoDiagnosis` (Demo and What the model saw rows, through `Case.Fail(50, A)`);
  - `TestDiagnosisVariants`: one `SendBatch` with four marker texts (no fix, unknown, invalid, refusal) gives four incidents that settle together;
  - `TestGoneBeforeTheAnswer`;
  - `TestRefusedRequest` (Refused request row): through `Test.Watch.IncidentProbe`, which gains a public wrapper of the `diagnose` error handler, as `Say` wraps `Tell`. It runs on a shadow instance in the test process, with a fixture incident row, and asserts fallback `error`, one Type 3 warning, and that the row stands.

  Keep the class under about 100 s on the developer machine.

**Acceptance Criteria:**
- Given a throwaway with demo mode on and session A watching Orders, when 50 failing orders tagged with A settle, then A's stream gets `noticed`, `settling`, `diagnosing` in that order. `Decide` records one `diagnose` decision for the incident in the incident's own trace session, and the row holds the Demo row's diagnosis with `NoticedAt` empty and no `Notification` (Integration AC: consumer `IncidentManager` of the `DiagnosisAgent` answer through `Decide`, against the real runner and mock).
- Given that run, when the mock's log is read, then the model's first request holds the evidence pack, and its second request holds `read_failed_messages`' result built from the incident's real failed orders (Integration AC: consumer `DiagnosisAgent` of the real `OcuTalon.Tools.Watch`, through the gate).
- Given the recorded snapshot and the `diagnosis` scenario, when `EvidencePack.Build` makes the pack and a `diagnose` request carrying `Input(pack)` goes through `Decide`, then the decision is usable with `data_format_change`, `OrderDate`, `repair_resend` and order/orders, and its `Payload` is the checked `DiagnosisPayload` JSON (Integration AC: consumer `Decide` of `DiagnosisPayload` as `ReplyClass`).
- Given replies that fail the check or are refused, when `IncidentManager` stores the answer, then the incident holds the bridge's fallback, no cause and no fix, and the code noun.
- Given a filter class, when `Decide` records a diagnosis, then `cause` and `fixSummary` were filtered once before recording, and a blanked cause is `invalid` (AD-31).
- Given the product source, when `Test.Bridge.CodeRules` runs, then the watch tools are clean, return through `Return`, keep distinct step labels, and call only listed callback classes. When `Test.Install.Production` runs, then `DiagnosisAgent`'s `ReplyClass` is `OcuTalon.Watch.Msg.DiagnosisPayload` and `IncidentManager` still has pool 1 and `STUB`.

## Spec Change Log

- 2026-10-26, spec gate (Epic 5 runner): R1 ruled (decide, split; Story 5.8 inserted in epics.md); R2 and R3 belong to Story 5.8; the spine candidates written as the Consistency Conventions row "Diagnosis"; status set to `ready-for-dev`.

## Review Triage Log

## Design Notes

**Rulings this plan halts on (R1 to R3).** The spec above is written as if each is ruled as recommended. Under R1 (a), the spec stands as written.

- **R1. Split** [RULED 2026-10-26 by the epic lead: (a), decide (a split into siblings planned next, within limits.split_children); the sibling is Story 5.8 `5-8-each-noticed-incident-says-what-broke-with-its-evidence-behi`, run after 5.4 and before 5.5; epics.md amended] **(the lead asked for one when the story does not fit; product default 6).** Story 5.4's block holds three units, each the size of a story: the diagnosis (pack, real toolset, payload, the `Decide` call), the three-variant notice with its delivery, and the incident payload's evidence fields. Planned whole, it would be well over Story 5.3's size, which already carried `oversized`. Recommended (a), two siblings:
  - **5.4 (this spec): "The diagnosis explains the cause from the failed messages".** From epics.md's 5.4 block:
    - AC 1, whole: the pack, `diagnosing`, `diagnose` through `Decide`;
    - AC 2, whole: `Tools.Watch`, `DiagnosisPayload`, `invalid`;
    - AC 5's second paragraph: the `ItemNoun` map and its unit test;
    - AC 7's diagnosis part: the snapshot and scenario give a data-format change at the order date, and CI sees `noticed`, `settling`, `diagnosing` in that order.

    It adds the hand-over: the diagnosis or fallback is stored on the incident row.
  - **New sibling, planned next and run before 5.5:** for example "The incident notice says what broke, without a fix or as a fallback". It takes:
    - AC 3 per R2, and AC 3's second paragraph: one notice per watcher session of an `instance` incident (U-86);
    - AC 4: the no-fix notice and its render test;
    - AC 5's first paragraph: the fallback notice;
    - AC 6: `Evidence`, `TraceTargets`, `Groups`, and `Requests` per R3;
    - AC 7's notice part, per R2.

    Its plan meets these facts:
    - `Live.Payload.Incident.FromRow` (Lane A) is what `/state` calls (`Web/Api.cls:317`, contended). The evidence fields therefore belong in `FromRow`, so the event and the snapshot do not drift, and `Test.Live.Payloads.TestFromRow` (:233, which asserts them absent) changes.
    - The `groups` slot needs a count, a first time and an error summary per group, and the payload needs sample and first-failure header ids. No row stores these today, so a `FailureGroup` schema veto is likely.
    - `Notify` already routes kind `incident` (no rule row is needed), and `WebChatOut` only records a `Delivery` for that kind.

  Alternative (b): one story as written. It is rejected under product default 6. Alternative (c): three children, splitting the toolset out of this one. The toolset and the pack share `Reader.Evidence` and `EvidencePack.Read`, so the third child would be thin, and the 5.4 title would no longer fit its first child.
- **R2. The with-fix notice contradicts AD-15 (Rule 6).** [For Story 5.8; this spec sends no notice. The lead puts R2 to the orchestrator (it moves an AC to Epic 7's Story 7.2) before 5.8's plan.] Epics AC 3 asks 5.4 to send, for a usable data-format diagnosis, a kind-`incident` notice with the with-fix catalog key and slots count, time, item noun, cause and fix summary, set `NoticedAt`, and publish state `open`, with "Story 7.2 adds the dry run and the approval request". That contradicts three things:
  - **AD-15's Rule.** The with-fix variant is "a usable data-format diagnosis and a valid dry run; it carries the first request's `ApprovalRef`", and the transition table moves `open, not noticed` to `awaiting_approval` only on "notice with a fix and a valid dry run (`Raise`)"; every other move is refused.
  - **AD-32.** The first request's `ApprovalRef` travels on every incident notice.
  - **The catalog.** `incident.withFix` (`Msg/Catalog/Watch.cls:78`) declares `field`, `before`, `after` and `resendCount` and asks "Approve?". `Catalog.Render` refuses a missing slot (`Catalog.cls:250`), so that notice cannot render before 7.2, and its text would ask for an approval that does not exist.

  Recommended (a): a usable data-format diagnosis is stored, and its notice is sent by Story 7.2 with the dry run and `Raise`, as AD-15 states. Epic 5 leaves such an incident unnoticed. The sibling builds the delivery that 7.2 calls, plus a unit-tested with-fix slot builder (count, time, noun, cause, fix summary). AC 7's "the notification's slots give 50 orders and the first failure's time … then the notice" moves to 7.2. That is a veto item: an AC moved to another epic's not-yet-planned story in the same release, where only the end-to-end demo gate depends on it, and that gate needs 7.2 anyway. UJ-1 has no notice today, so nothing regresses.

  Alternative (b): amend AD-15 (a veto under U7) to allow an interim with-fix notice. This needs a new catalog text, which is public text not in the UX. Alternative (c): send the AC as written. It contradicts AD-15's table and AD-32, cannot be rendered, and says "Approve?" with nothing to approve. Not recommended.
- **R3. The `Requests` result has no storage before Epic 7 (for the sibling's plan).** [For Story 5.8; ruled at 5.8's spec gate.] `Part.IncidentRequestResult` needs `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted` and `Reason`. No table stores them: `FixRun` has only `ApprovalRef`, `IncidentRef` and `StartedAt`, and `ApprovalRequest.Result` is a word. No incident has a request in Epic 5.

  Recommended: the sibling lists each request's `Ref` and `State` from `ApprovalRequest` rows by `IncidentRef`, pinned with a fixture row. `Result` is filled by the story that stores a fix run's counts (7.4). That is a veto item: part of an AC moved to a not-yet-planned story.

**Governing ADs:**
- AD-2: the product extends the bridge's `DecisionPayload`, and the bridge reads `FILTERED` by name.
- AD-3: `Reader` is the one switch, it checks readable before switching, and `Evidence` extends `Current`.
- AD-5: the waiter persists across the `Decide` round trip, and the row is the state.
- AD-6: `Decide`, `diagnose`, the throwaway AI session, and `Input` from `EvidencePack`.
- AD-7: `ReplyClass`, `INSTRUCTIONS` without `{{`, and reasons and confidence.
- AD-8: only the bridge classifies fallbacks, and a fallback has no fix.
- AD-9: the step labels stay.
- AD-10: the tools are governed by classification, and `Return` cuts results.
- AD-12: `watch.progress` after commit.
- AD-15: the pack at settle, the one-request typical diagnosis, and the transitions (R2).
- AD-22: the mock in CI, throwaways only.
- AD-26: the diagnosis runs in the incident's session.
- AD-29 and AD-33: Lane A files; `IncidentManager` is the only writer and publisher.
- AD-30: the diagnosis never reaches `OutcomeRouter`.
- AD-31: every stored model text is filtered (the `FILTERED` hook).

Spine conventions: "Watch failures", "Redaction", "Tool classification", "Text OcuTalon sends" (nothing is rendered here), "HostData" (the watch read tools set no `HostData`), "Identifiers", "Times".

**Integration ACs, Consumes, Consumed-by:**
- New: `EvidencePack`, `DiagnosisPayload`, `FixParameters`, `ItemNoun`, `Reader.Evidence`, `Tools.WatchReads`, `Decide`'s `FILTERED` hook, and `IncidentManager`'s diagnosis step.
- In-story consumers:
  - `IncidentManager`, of the `DiagnosisAgent` answer through `Decide` (AC 1);
  - `DiagnosisAgent`, of the real toolset (AC 2);
  - `Decide`, of `DiagnosisPayload` (AC 3).
- Consumes:
  - Story 5.3's waiter, rows and `Tell`;
  - 5.2's `Reader` and `ErrorText`;
  - Epic 1's `Decide`, runner, gate and mock;
  - Epic 2's `Session.Recipients` and `Live.Publish`;
  - Epic 0's snapshot and `Live.Payload.Part.ItemNoun`.
- Consumed-by:
  - The R1 sibling: the notice reads `NoticeCount`, the stored diagnosis or fallback, `ItemNoun`, `DecisionRef` and `TraceHeaderId`, and fills `Evidence` and `TraceTargets`.
  - 7.1: `DiagnosisPayload.%OnValidateObject` gains the fix kind's parameter check over `FixParameters`.
  - 7.2: with R2 (a), the with-fix notice and `Raise` read the decision's `Payload`.
  - 6.x: the cards show the cause and the element.
  - 9.x: evaluation runs drive `EvidencePack.Build` with snapshots, owner `eval`, through `EvalSink` (AD-30).

**Extend, don't copy:**
- `DiagnosisPayload` extends `DecisionPayload`.
- The noun type reuses `Live.Payload.Part.ItemNoun`.
- `Reader.Evidence` extends `Current` (AD-3; spec 5.2's "no second switcher").
- The tools and `Build` share `EvidencePack.Read`.
- The error text reuses `FailurePoller`'s `Sentence(Redact.Text(...))`. If a second call site appears, it moves into one `ErrorText` helper that both use.
- The live reads follow `Test.Demo.Production.Snapshot`. That class is Epic 4's test helper, so it is followed, not shared.
- `TestFilterDiagnosis` extends `ProbeFilter`'s tests.
- `Case.WaitDiagnosed` calls `WaitRow`'s polling.

**Decided in-stage:**
- **The `diagnose` request.** `ItemId` is the incident `Ref`: one decision per incident, and the tools find their incident through it. `Provenance` is `untrusted`, because the failed messages did not come from the user (AD-10 rule 3).
- **`DiagnosisPayload`'s values.** It adopts the evaluation case's codes and keys unchanged (`causeCategory`, `elementAtFault`, `fixKind`; spec 0-10 L718). `outcome` must be `act` (AD-30: a usable diagnosis is `act`). A cause is required for every category. A fix for a cause outside data format is invalid, not ignored. A clock time in `cause` or `fixSummary` is invalid (AD-32: model slots carry no times).
- **The pack.** It holds one sample, the oldest held header failure, so the evidence and the later payload point at the same message. It holds the failing item's own settings from the production definition, as the recorded snapshot does: one rule for both sources, and no reliance on `PopulateVirtualSettings`, which has not been measured here. The trace excerpt is the sample's session, at most 20 headers. The event log is left out of the pack; a tool offers it.
- **The credential rule** is the recorded snapshot's name rule (credentials, password, token, key). It is applied inside `Reader` after the switch, before anything leaves it, so no caller holds such a value, and the redactor is the backstop.
- **The tools** take no arguments, so the model chooses nothing. They are scoped to the context's incident and owner, and give `{"items": []}` otherwise (so `Test.Agent.Runners`' assertion holds). The limits are 5 failed messages and 20 log rows.
- **The provider class** is renamed `WatchReads`, because a class named "Fixture" that holds real readers would mislead.
- **The code noun** is stored at the settle end, so a fallback always has a noun. A usable diagnosis's noun replaces it.
- **A refused `diagnose`** (an error status) is stored as fallback `error`, with one warning. That is the reason the bridge gives a failure it cannot classify, so the sibling's notice never leaves the incident silent.
- **The answer handler** writes only to an unclosed, unnoticed row that still exists. The incident remains unnoticed until the sibling's notice.
- **Scenario selection.** Tests choose a mock scenario with a `[[mock:<name>]]` marker in a synthetic failure's error text. The marker flows into the pack's `errorPattern`, because it holds no digits. `diagnosis.json` stays the default for real Orders failures.

**(inference), pinned by the tests and recorded by the implement stage:**
- `Decide`'s `TraceSessionId` for a request from the waiter is the waiter's session, the incident's `TraceHeaderId` (`TestDemoDiagnosis`).
- A marker inside the pack's JSON text survives `Redact.Text` and reaches the mock (`TestDiagnosisVariants`).
- The body's datatype properties read through the class dictionary while switched (`TestLivePack`).
- An `Ens.BusinessProcess` waiter that sends a request and gets its response keeps its `%SessionId` across the round trip (`TestDemoDiagnosis`).

**Ledger inbox:** none was routed to this story. No `DW-n` entry is addressed or declined.

**Footprint extensions** (none contended):
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`: the bridge's extension point, Lane A.
- `Production.cls`: Lane A's region.
- `Test/Install/Production.cls`: one lane-A oracle row, not Epic 13's lines.
- `Test/Agent/*`, `Test/Bridge/*` and `Test/Tools/Result.cls`: Lane A's own tests.

**Spine candidates (Rule 20, for the lead at the spec gate):**
- AD-15 or the "Watch failures" row could add:
  - a `diagnose` request's `ItemId` is the incident `Ref`, and its provenance is `untrusted`;
  - the watch read tools are scoped to the context's incident and owner, and take no arguments;
  - the pack's shape and its one-sample rule.
- AD-31 could add: `Decide` filters the reply class's `FILTERED` properties and validates again.
- Under R2 (a), AD-15 is unchanged. Under (b), AD-15 is amended.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`. Run one command per call, each with `timeout: 600000`. Never put two IRIS test runs in one message, and chain nothing after a shard.

**Commands:**
- (loop) `bash docker/tests/test-mock.sh` -- expected: every mock test passes. The scenario files load, there is one `mockkey` scenario per agent, and the tool names come from `Tools/Names.cls`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s4iw ci/warm.sh up` -- once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s4iw ci/iris.sh class <Class>`, one call per class, for `OcuTalon.Test.Watch.Payload`, `OcuTalon.Test.Watch.Evidence`, `OcuTalon.Test.Watch.Reader`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Bridge.Gate` and `OcuTalon.Test.Tools.Result` -- expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s4i ci/iris.sh class <Class>`, fresh, one call per class, because production items changed (`IncidentManager`, `Decide`, the runner's toolset). For `OcuTalon.Test.Watch.Diagnose`, `OcuTalon.Test.Agent.Decide`, `OcuTalon.Test.Agent.Runners`, `OcuTalon.Test.Agent.Instructions`, `OcuTalon.Test.Bridge.Decide`, `OcuTalon.Test.Watch.Incidents` and `OcuTalon.Test.Install.Production` -- expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e5s4i ci/iris.sh shard lane-a --part 1/2`, then in its own call `... --part 2/2` -- each alone in its call. Expected: passed. Record each part's time here. If a part takes more than 480 s, use `--part k/3` (three calls) and record those times.
- (once) `<lane> OCUTALON_RUN_TAG=e5s4i ci/iris.sh shard lane-b` -- `diagnose` decisions and their `decision` events now appear for watched incidents. Expected: passed.
- (once) `bash ci/checks.sh` -- expected: all pass (storage blocks, class rules).
- (once) `<lane> OCUTALON_RUN_TAG=e5s4iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s4i ci/iris.sh teardown`.

**Shared surfaces:**
- **Every settled incident** now publishes `watch.progress` `diagnosing` and gets one `diagnose` `Decision`, with its `decision` event through `BridgeSink`.
  - `Test.Watch.Incidents` counts progress events. The `Case` cleanup removes those `Decision` rows; a row that `Decide` records after the cleanup is harmless, being unique per `ItemId`.
  - `Notice` fixtures must wait for the diagnosis.
- **The incident row's** `ItemNoun`, `Cause`, `CauseCategory`, `Element`, `FixSummary`, `Fallback`, `FallbackReason` and `DecisionRef` are now written after the settle.
- **`DiagnosisAgent`'s `ReplyClass`:** `Test.Install.Production`'s oracle row, and `Test.Agent.Decide`'s former refusal test.
- **The Diagnosis toolset:** the provider class name, the methods' signatures and their results. These are pinned by `Test.Agent.Instructions`, `Test.Agent.Runners` (`DIAGNOSISTEXT`), `Test.Tools.Result`, `Test.Bridge.Gate`, `Test.Bridge.CodeRules` and `Test.Bridge.Decide` (the size estimate).
- **The mock scenario set:** `diagnosis.json`'s content, and three new marker files. `STORY_SCENARIOS` is unchanged.
- **CodeRules' callback lists** (`CALLBACKHELPERS`, `READERCLASSES`).
- **`Reader`'s switching method.**
- **The `lane-a` class list:** three new classes (`Test.Watch.Payload`, `Test.Watch.Evidence`, `Test.Watch.Diagnose`), run as parts.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19). The implement stage applies each one, observes red, reverts byte-identically and records it here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | the waiter publishes no `diagnosing` | `TestDemoDiagnosis` (the progress order) |
| AC 1, trace | the `diagnose` request is sent with `%SessionId` cleared | `TestDemoDiagnosis` (`TraceSessionId` is not `TraceHeaderId`) |
| AC 1, row | a usable answer is not stored (`CauseCategory` left empty) | `TestDemoDiagnosis` |
| AC 2 | `read_failed_messages` always returns `{"items": []}` | `TestDemoDiagnosis` (the tool result), `TestToolsReadTheIncident` |
| AC 2, pack | `Input` without the pack | `TestDemoDiagnosis` (the first request) |
| AC 3 | `Build` drops the snapshot's sample | `TestSnapshotPack`, `Test.Agent.Decide` `TestSnapshotDiagnosis` |
| AC 4 | the handler treats every answer as usable | `TestDiagnosisVariants` (invalid and refusal rows) |
| AC 4, noun | no code noun at the settle end | `TestDiagnosisVariants` (the fallback rows' noun) |
| AC 5 | `Decide` skips `FILTERED` | `Test.Bridge.Decide` `TestFilterDiagnosis` |
| AC 6 | `ReplyClass` removed from `Production.cls` | `Test.Install.Production` `TestDefinition` |
| Payload check | `fixKind` accepted on `partner_outage`; and separately, outcome `tellnow` accepted | `Test.Watch.Payload` |
| Item noun | the map gives message for `PartnerOrder` | `Test.Watch.Payload` |
| Credentials | the name rule checks only "password" | `TestCredentialsLeftOut` |
| Tools in scope | the tools ignore `OwnerRef` | `TestToolsReadTheIncident` |
| Gone before the answer | the handler saves a row it could not open as a new one | `TestGoneBeforeTheAnswer` |
| Refused request | the error handler stores no fallback | `TestRefusedRequest` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Plan stage, 2026-10-26: the plan halted `blocked` on R1 (split), R2 and R3; the epic runner ruled R1 (split; Story 5.8 takes the notice) and left R2 and R3 to Story 5.8, which this spec does not depend on (it sends no notice). Status set to `ready-for-dev` at the spec gate.
