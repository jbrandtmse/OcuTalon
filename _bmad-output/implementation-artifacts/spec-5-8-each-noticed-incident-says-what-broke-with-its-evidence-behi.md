---
title: 'Each noticed incident says what broke, with its evidence behind Show details'
type: 'feature'
created: '2026-10-26'
status: 'done'
baseline_revision: '86cc5bf1453806047c5687ba0aa052f8032e3823'
baseline_commit: '86cc5bf1453806047c5687ba0aa052f8032e3823'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 5.4 every settled incident holds its diagnosis or the bridge's fallback, but nobody is told. No `Notification` goes out, `NoticedAt` stays empty (so the page and `/state` never show the incident), and `Live.Payload.Incident.FromRow` leaves out `Groups`, `Evidence`, `TraceTargets` and `Requests`, so Show details has nothing to show. No row stores a group's count, times or error summary, the sample, or the first failure.

**Approach:** As soon as an incident's diagnosis outcome is stored, `IncidentManager` sends its notice (rulings R2 and R3 in Design Notes are pending; this spec is written to their recommended answers). A no-fix, unknown-cause or fallback outcome gets one kind-`incident` `Notification` per `Session.Recipients` session, with catalog key and slots built by code in the new pure class `OcuTalon.Watch.Notice`. The incident is set `NoticedAt`, `open` and its open variant, and the `incident` event goes to each watcher's stream. A usable data-format diagnosis stays stored and unnoticed: Story 7.2 sends its with-fix notice with the dry run and `Raise`, through the delivery and the with-fix slot builder that this story builds and unit-tests. `FromRow` fills the Show-details fields from rows only, so the event and `/state` carry the same view. DW-261 and DW-264 are settled on the way.

## Boundaries & Constraints

**Always:**
- **When the notice goes out.** Right after `Answered` or `Refused` (Story 5.4) saves an outcome, `IncidentManager` runs its notice step on the row. It acts only on a row that exists, is not `closed` and has no `NoticedAt` (`Open`):
  - `Fallback` 1 (any reason, `error` included): key `incident.fallback`, open variant `fallback`;
  - usable, `CauseCategory` `unknown`: key `incident.noFixUnknown`, open variant `no_fix`;
  - usable, any other category except `data_format_change`: key `incident.noFix`, open variant `no_fix`;
  - usable `data_format_change` (with a fix): no notice and no row change (R2 (a)). The row stays `open` with `NoticedAt` empty, for Story 7.2.
- **The delivery** (`Deliver`, the private method that Story 7.2 calls with `incident.withFix`, its extra slots and the `ApprovalRef`):
  - It sets `NoticedAt` (UTC now), the given state (`open` here) and open variant in one save.
  - After that commit it reads `Session.Recipients(OwnerRef, Ref)` once. To each session it sends one `OcuTalon.Msg.Notification` to the `Notify` item, asynchronously, from the waiter (so the notice is in the incident's trace session, AD-26), then publishes the `incident` event (`FromRow`) on that session's stream.
  - The Notification carries `SessionRef` (the recipient), `Kind` `incident`, `CatalogKey`, `Slots` (JSON), `IncidentRef`, `DecisionRef` (the row's) and `ApprovalRef` (empty here).
  - No recipients (owner `eval`, or `instance` on the online demo) means no Notification, no event and no warning.
  - A failed `Recipients` read logs one Type 3 warning and sends nothing, as `Tell` does. A failed send leaves the other sessions their notice and event, and logs one Type 3 warning per notice (the first error). The row stays noticed either way.
  - `Tell` is extended with an optional Notification, so one `Recipients` read serves both the notice and the event. Each send goes through one private method, `SendNotice`.
- **The slots** (`Watch.Notice`, pure; producers never render):
  - `count` is `NoticeCount`, `time` is `FirstAt` (UTC ISO 8601), and `itemNoun` is the row's `ItemNoun` JSON, else `ItemNoun.For("")`;
  - no fix: also `cause` and `groups`. Unknown: `groups`. Fallback: `fallbackReason` (the row's, `unusable` when empty or not in `Msg.Enum` `FALLBACKREASON`) and `groups`;
  - with fix (the builder 7.2 extends): `count`, `time`, `itemNoun`, `cause` and `fixSummary`.
  - `groups` holds one `{itemName, count, errorSummary, firstAt}` per group that has a `NoticeCount`, in `Seq` order. Its `count` is the group's `NoticeCount`, so the lines add up to the `count` slot even when failures joined during the diagnosis. An empty error summary is written as the fixed value of veto V2.
  - A notice whose slots cannot be built (no group, an empty cause) logs one Type 3 warning and leaves the row unnoticed.
- **What the rows keep** (veto V1). `IncidentManager` writes all of it:
  - `FailureGroup`: `Seq` (1 for an incident's first group), with a unique index on (`IncidentRef`, `Seq`), plus `Count`, `FirstAt`, `LastAt` (kept by `Record` like the incident's), `NoticeCount` (set at the settle end with the incident's, in one transaction) and `ErrorSummary` (`ErrorText.Summary` of the group's first failure text, set when the group is made).
  - `Incident`: `FirstHeaderId` (the header id of the earliest failure, empty when that is a log row; moved with `FirstAt` in `Record`), `SampleHeaderId` and `SampleError` (the live pack's `sample.headerId` and `sample.error`, stored at the settle end with the code noun), and `RequestRefs` (R3: the incident's approval request Refs, comma-separated, in raised order; Story 7.2 appends to it at `Raise`).
- **One reader of an incident's groups:** `OcuTalon.Data.FailureGroup.OfIncident(ref)` opens `SeqIndexOpen(ref, 1)`, then 2, and so on to the first gap, at most a fixed maximum. `IncidentManager.Groups`, `EvidencePack.Group`, `Watch.Notice` and `FromRow` use it.
- **`FromRow` reads rows by object access only**: `OfIncident` and `ApprovalRequest.RefIndexOpen`, with no SQL at all. `/state` calls it as `OcuTalonUser`, who holds no SQL grant (AD-13). It fills:
  - `Groups`: every group, `{itemName, count (live Count), errorSummary, firstAt}`;
  - `Evidence`: `sampleHeaderId` and `sampleError` from the row, and `items`: every group, `{itemName, count, firstAt, lastAt}`;
  - `TraceTargets`: `diagnosis` `{TraceHeaderId, $Namespace}`; `sample` `{SampleHeaderId, Namespace}`; `firstFailure` `{FirstHeaderId, Namespace}`. Each is left out when its id is empty;
  - `Requests`: one `{ref, state}` per `RequestRefs` entry whose row exists and whose `IncidentRef` is the incident's. `result` is left empty (R3: Story 7.4).
- **DW-261.** `OcuTalon.Watch.ErrorText.Text(raw)` is the one composition `Sentence(Bridge.Redact.Text(raw))`. `FailurePoller` and `EvidencePack` use it (`EvidencePack.Sentence` goes), and so does `ErrorText.Summary(raw)`: the first sentence of `Text(raw)` (up to its first ". ", "? " or "! "), at most 80 characters. A longer one is cut at its last space within 79 characters and ends with U+2026, written as an escape. An empty text gives "".
- **DW-264.** No `Ens_Util.Log` row id goes to the model. Where the pack's sample, `read_failed_messages` and `read_event_log` gave `logId`, they give `logRef`: the row's 1-based position in the event log of the read that made the answer. Header ids stay.
- **Unchanged.** `IncidentManager` keeps `STUB`, `PoolSize` 1 and the 5003 answer, and it stays the only writer of `Incident` and `FailureGroup` rows and the only publisher of `incident` and `watch.progress`. A diagnosis never goes to `OutcomeRouter`.

**Never:**
- No with-fix notice, dry run, `Raise`, `ApprovalRef` or `awaiting_approval` (R2 (a), Story 7.2). No state but `open`, and no closing or dismissing (Story 5.5).
- No catalog key or text change, and no payload class property change (the parts exist), so `web/` regenerates nothing.
- No SQL in `Live.Payload.Incident` (AD-13). No `Catalog.Render` call in product code (only `*Out` render, AD-32).
- No edit to a contended path: `Web/Api.cls`, `Data/{Ownership,Session,Setting}.cls`, `Core/*`, `Channel/*`, `Live/Publish.cls`, `Test/Web/*`, `Test/Data/*` (except Tables.cls' `Incident` and `FailureGroup` entries), `Test/Core/*`. No change to `Msg/*`, `ci/units.sh`, `ci/mock/` or `eval/`.
- No real model call and no NFR-7 time assertion.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| No fix | Session A's failure carries `[[mock:diagnosis-nofix]]` | The row has `NoticedAt` set, `open`, `no_fix`. A gets one Notification: kind `incident`, `incident.noFix`, slots count, time, itemNoun, cause, groups[1], the row's `DecisionRef`, no `ApprovalRef`. WebChatOut records one `incident` Delivery row for A. A's stream holds, in `Seq` order, `noticed`, `settling`, `diagnosing`, then one `incident` event (`open`, `no_fix`, groups, evidence items, diagnosis trace target) | none |
| Unknown | `[[mock:diagnosis-unknown]]` | `incident.noFixUnknown`, `no_fix`, no `cause` slot | none |
| Fallback | `[[mock:invalid-reply]]`, `[[mock:refusal]]`; `Refused` with reason `error`; reasons `timeout`, `""` and `zz` (unit) | `incident.fallback`, `fallback`, `fallbackReason` the row's reason (`""` and `zz` give `unusable`). The slots render "I couldn't work out the cause (…)" for each | none |
| With fix (R2 (a)) | Real Orders failures; mock `diagnosis` (data format) | Stored as in 5.4. `NoticedAt` empty, no Notification, no `incident` event. Unit: the with-fix builder's slots plus fixture `field`, `before`, `after`, `resendCount` render the UJ-1 text of `incident.withFix` | none |
| Instance, two watchers (U-86) | Sessions A and B watch Orders, C does not; an untagged no-fix failure | One incident and two Notifications (SessionRef A, B), one `incident` event on each of their streams; C gets none | none |
| Nobody to tell | Owner `eval`; or `instance` with `onlineDemo` on | `NoticedAt`, `open` and the variant are set; no Notification, no event, no warning | none |
| A send fails | Probe: the send to A answers an error | B still gets its Notification and event; one Type 3 warning names the incident | warning, row stays noticed |
| Not to notice | Answer or refusal for a row that is noticed, closed or gone | Nothing is written and nothing is sent | dropped |
| Count moved | `NoticeCount` 50, `Count` 52 at the notice | Slot `count` 50 and the group line 50; the payload's `count` is 52 | none |
| Show details, header sample | No-fix failure of a real failed order of OCUORDERS | `evidence.sampleHeaderId` is that header id, and `sampleError` is `ErrorText.Text` of its real error. `traceTargets.sample` and `firstFailure` are that id in OCUORDERS, and `diagnosis` is `TraceHeaderId` in OCUTALON | none |
| Show details, no sample | Unreadable namespace, or a log-key sample, or a log-row first failure | `sampleHeaderId` and `traceTargets.sample` or `firstFailure` are left out; `items` stay | none |
| Requests (R3) | Fixture: `RequestRefs` naming a fixture `ApprovalRequest` (`pending`), a missing Ref, and one of another incident | `requests` = `[{ref, state: "pending"}]`, with no `result` | skipped refs |
| `/state` | `Web.Api.StateBody(A)` after the no-fix notice | Its chat holds the incident, with the same `groups`, `evidence` and `traceTargets` as the event | none |
| Error summary | Wrapped error with a token; two sentences; a 120-character sentence; `""` | Redacted own sentence; the first sentence; at most 80 characters ending in U+2026; `""` (the group line then uses the V2 value) | none |
| DW-264 | A log-key incident through the pack, `read_failed_messages`, `read_event_log` | Rows carry `logRef` 1..n and no `logId` | none |

</intent-contract>

## Code Map

Every path is under `src/ocutalon/cls/` unless noted.

- `OcuTalon/Watch/IncidentManager.cls` (399 lines): `OnResponse` L84, `OnError` L96, `Batch` L104 (publishes `FromRow` for noticed incidents), `Record` L127 (the per-cause loop with `fresh` keys and `failedAt`; a new group at L169), `Groups` L222 (SQL, to become `OfIncident`), `Check` L263 (the settle end saves `NoticeCount`), `Diagnose` L278 (saves the code noun after `EvidencePack.Build`), `Answered` L310, `Refused` L345, `Open` L361, `Tell` L376. The class doc ends with "NoticedAt, the notice ... are not set here" (L27): rewrite it.
- `OcuTalon/Data/Incident.cls` and `Data/FailureGroup.cls`: schema (Code Map of 5.4). `Count` needs `SqlFieldName = FailureCount`, as `Incident` has it. The `Storage Default` blocks gain the new values as the compiler writes them (export the compiled class; `ci/checks.sh` checks the blocks).
- `OcuTalon/Live/Payload/Incident.cls` `FromRow` L65 (its doc says the four lists are "left absent for the caller": replace). Parts already have every field: `Part/IncidentGroup`, `IncidentEvidence` (`SampleHeaderId`, `SampleError`, `Items`), `IncidentEvidenceItem`, `IncidentTraceTargets`, `TraceTarget` (`TraceHeaderId`, `TraceNamespace`), `IncidentRequest` (`Ref`, `State`, `Result`). Precedent for an object-access read with `$Namespace`: `Live/Payload/Approval.cls` `FromRow` L62-84.
- `/state`: `Web/Api.cls` `ChatItems` L304-318 calls `FromRow` on rows from `Ownership.RecentIncidents`. `StateBody(session)` L258 is public (contended: call only). AD-13 and `docker/tests/test-class-rules.sh` L37-40 allow unchecked prepares only in three methods.
- `OcuTalon/Msg/Catalog/Watch.cls`: `incident.noFix`, `incident.noFixUnknown`, `incident.fallback`, `incident.withFix` (with its `one` form). `Msg/Catalog.cls`: slot types, `GROUPLINE` L50, `REASONKEYS`, and `RenderAt(key, slots, channel, now, onlineDemo, *sc)` for tests. A `text` slot may not be empty.
- `OcuTalon/Msg/Notification.cls` (fields). `Core/Rule/Notify.cls` routes kind `incident` to `WebChatOut` (and `SimPhoneOut` in demo mode, still a stub that answers 5003). `Channel/WebChat/Out.cls` L47-48 records a no-text `Delivery` for kinds other than `tellnow` and `reminder`. Sending precedent: `Core/Conversation.cls` L52, L582.
- `OcuTalon/Data/Session.cls` `Recipients` L93. `Bridge/Data/ApprovalRequest.cls` (`src/bridge/cls/OcuTalon/Bridge/Data/`): `RefIndex` unique, `IncidentRef`, `State`.
- `OcuTalon/Watch/ErrorText.cls` `Sentence` L33 (its doc says it calls nothing outside the class: update it). `Watch/FailurePoller.cls` L112. `Watch/EvidencePack.cls`: `Group` L76 (SQL), `Message` L165, `LogMessage` L177 (`logId`), `Sentence` L206, `FailedMessages` L257, `EventLog` L281 (`logId` at L289). `Tools/WatchReads.cls` L38 and L46 (method docs, which are the tool descriptions).
- `OcuTalon/Bridge` `Redact.Text` is idempotent (its class doc).
- Tests:
  - `Test/Watch/IncidentProbe.cls` (`Say`, `Refuse`, `Answer`). A shadow instance cannot `SendRequestAsync`: `SendRequestAsyncInternal` reads `..%PrimaryRequestHeader.Resent` (`irislib/Ens/BusinessProcess.cls` L204).
  - `Test/Watch/Case.cls`: `SendBatch` L884, `Incidents` L919, `Group` L932, `WaitDiagnosed` L994, `Notice` L1009, `Notifications` L1019, `DropIncidentRows` L1037.
  - `Test/Watch/Diagnose.cls`: `TestDiagnosisVariants` L116 (L147 asserts `NoticedAt` empty), `TestRefusedRequest` L215 (L229), `Row` L267 (no group).
  - `Test/Watch/Incidents.cls`: `TestBurstThroughThePoller` L62, `TestInstanceShared` L273 (the two-watcher pattern: `Case.Watch`; default scenario, so it stays unnoticed).
  - `Test/Watch/Tell.cls` (probe tests with `Test.Data.Fixture` `Session`, `Check`, `Incident`, `Approval`; `Fixture.Clean` drops the sessions' streams and Delivery rows).
  - `Test/Watch/Evidence.cls`: `Fixture` L148 (makes a `FailureGroup` at L161; give it `Seq` 1), `TestLogKeys` L290 (L306, L313), `TestToolsReadTheIncident` L408 (L427).
  - `Test/Live/Payloads.cls`: `TestFromRow` L189 (L233 asserts the four keys absent), `Clean` L617 (ZzPay rows).
  - `Test/Data/Tables.cls`: Contracts L489-532 (index form `"A,B unique"`).
  - `Test/Core/Observe.cls`: `DeliveryRows`, `WaitDeliveries`, `Events`, `LastLog`, `Warnings`, `RemoveWarnings`. `Live.Event.Since(stream, 0, 200, "session")` returns events in `Seq` order.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Data/FailureGroup.cls`, `src/ocutalon/cls/OcuTalon/Data/Incident.cls` -- add the properties and the index of "What the rows keep", and `FailureGroup.OfIncident(ref) As %ListOfObjects`. `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- the `Incident` and `FailureGroup` Contracts entries only.
- `src/ocutalon/cls/OcuTalon/Watch/ErrorText.cls` -- add `Text` and `Summary` (DW-261). `Watch/FailurePoller.cls` L112 uses `Text`. `Watch/EvidencePack.cls`:
  - drop `Sentence` and use `Text`;
  - `logRef` in place of `logId` (DW-264);
  - `Group` becomes the first of `OfIncident`.

  `Tools/WatchReads.cls`: the two method docs say `logRef`.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls` -- new, pure. It gives the key and the open variant of a row, the slots of each variant (the with-fix builder included) and the group lines, per Always. It renders nothing and writes nothing.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`:
  - `Record` keeps the group fields, `Seq` and `FirstHeaderId`;
  - `Groups` calls `OfIncident`;
  - `Check` sets the groups' `NoticeCount` in the incident's transaction;
  - `Diagnose` stores `SampleHeaderId` and `SampleError`;
  - `Answered` and `Refused` call the notice step after their save;
  - add `Notice`, `Deliver`, `SendNotice`, the `Tell` extension, the parameters (`NOTIFY` "Notify", the kind, the warning texts) and the class doc.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Incident.cls` -- `FromRow` fills `Groups`, `Evidence`, `TraceTargets` and `Requests` per Always, with no SQL. Update the class and method docs.
- `src/ocutalon/cls/OcuTalon/Test/Watch/IncidentProbe.cls` -- override `SendNotice`: record each Notification on the instance and answer OK, or an error for a SessionRef that the test names. Doc: why it overrides.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- `Incidents` and `Group` also give the new fields, and `Group` gives the groups as a list. Add a helper that reads a session's stream in `Seq` order (any type), and a helper that returns the Notification bodies of an incident's Ref as objects.
- `src/ocutalon/cls/OcuTalon/Test/Watch/NoticeText.cls` -- new, pure (warm). Tests:
  - keys and variants per row;
  - each variant's slots rendered (`RenderAt`, fixed clock, the expected time from `Data.Time.ForMessage`): the no-fix text exactly as the epics criterion states it, then unknown, fallback (the reasons of the matrix) and with-fix plus fixture dry-run slots (the UJ-1 text);
  - every variant renders on web, phone, mailbox and telegram;
  - the group lines (two groups; a group without `NoticeCount` left out; the V2 value for an empty summary);
  - `count` is `NoticeCount`; the noun fallback;
  - `ErrorText.Text` and `Summary` (the matrix rows), and `Summary(Text(raw))` equals `Summary(raw)`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Tell.cls` -- add two probe tests (warm). `TestNoticeToEachRecipient`: an instance fixture incident with a group, watched by two fixture sessions, a third not watching; `Answer` with a `partner_outage` payload gives two recorded Notifications with the matrix fields, one `incident` event on each watcher's stream, none for the third, and the row noticed `open`, `no_fix`. `TestFailedSendLeavesTheOthersTheirNotice` (the A send fails row). `TestNobodyToNotice` (the Nobody to tell row, with an `eval` incident and an `instance` incident under `onlineDemo` on). Each test deletes the `FailureGroup` rows it made. Update the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Notices.cls` -- new, over the running production (fresh only; it fails with the reason where OCUORDERS or demo mode is missing). Tests:
  - `TestNoticeVariants`: one `SendBatch` for A carrying a real failed order of OCUORDERS (`diagnosis-nofix`, with the header id, as `Diagnose.TestDiagnosisVariants` does) and one carrying three ZZNS failures (`diagnosis-unknown`, `invalid-reply`, `refusal`). A does not watch Orders, so the poller makes no incident of its own. It asserts, for each incident, the No fix, Unknown and Fallback rows; the stream order; the Delivery rows; the Show details header-sample row (the real order); and the `/state` row.
  - `TestInstanceNotice`: the U-86 row, end to end.

  Keep the class under about 100 s on the developer machine.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Diagnose.cls`:
  - `TestDiagnosisVariants`: the no-fix, unknown and fallback rows are now noticed with their open variant (replacing "NoticedAt is empty");
  - `TestDemoDiagnosis` keeps "no notice" (R2 (a)) and adds `SampleHeaderId`/`SampleError`;
  - `Row` makes a `Seq` 1 group with `NoticeCount`;
  - `TestRefusedRequest`: the open fixture is noticed as `fallback` with one recorded notice, and noticed, closed and gone rows get none.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Incidents.cls` -- `TestBurstThroughThePoller` also asserts: one group with `Seq` 1, `Count` 50, the incident's `FirstAt`/`LastAt`, `NoticeCount` 50, `ErrorSummary` "The order date was not in the expected format.", and `FirstHeaderId` the earliest failed header (the lowest id among equal times).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls` -- `logRef` at L306, L313 and L427 (and no `logId` anywhere in the three answers); the fixture group gets `Seq` 1.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- DW-273 (the owner's answer U-91): `CREDENTIALPARTS` also holds `bearer` and `cookie`, still matched case-insensitively as a substring of the setting's name, so the parts are credential, password, passwd, passphrase, secret, token, key, auth, bearer, cookie ("credential" covers credentials). Update the class doc's list (L32) to match. `src/ocutalon/cls/OcuTalon/Test/Watch/Evidence.cls` `TestCredentialsLeftOut`: the snapshot item also gets settings whose names hold only `bearer` or only `cookie`, in mixed case (for example `BearerValue`, `SessionCookie`, `XCOOKIEJAR`); they stay out of the pack, and the name-rule loop also lists them (and still keeps `TargetConfigName` alone). Update the test's class-doc row.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls` (Incident rows only):
  - `TestFromRow`: the row's `TraceHeaderId` now gives `traceTargets.diagnosis`; `groups`, `requests` and `evidence` stay absent for a row without them;
  - add `TestFromRowEvidence` (the Show details rows and the Requests row, from ZzPay fixture rows);
  - add `TestIncidentFromRowReadsNoSql`: the class's method code holds no `%SQL`, `%ExecDirect`, `%Prepare`, `&sql(` or `##sql(`;
  - `Clean` also deletes the ZzPay incidents' groups and fixture approval rows.

**Acceptance Criteria:**
- Given a throwaway with demo mode on and session A, when a no-fix, an unknown and two fallback failures owned by A settle and are diagnosed through the CI mock, then each incident is noticed with its catalog key and open variant. A gets exactly one kind-`incident` Notification per incident, and `WebChatOut` records one `incident` Delivery row for A for each (Integration AC: consumer `WebChatOut`, through `Notify`, of `IncidentManager`'s Notification).
- Given those incidents, when A's stream is read in `Seq` order, then each shows `noticed`, `settling`, `diagnosing`, then its one `incident` event, with `groups`, `evidence` and `traceTargets` filled.
- Given an untagged no-fix failure of Orders that sessions A and B watch, when it is noticed, then each of A and B gets one Notification and one `incident` event, and session C, which does not watch Orders, gets neither (U-86).
- Given the noticed no-fix incident of a real failed order, when `Web.Api.StateBody(A)` builds the snapshot, then its chat incident carries the same `groups`, `evidence` and `traceTargets` as the published event (Integration AC: consumer `/state` of `FromRow`).
- Given each variant's slots from `Watch.Notice`, when `Catalog.RenderAt` renders them, then the no-fix text is exactly "{count} {item noun} failed since {time}. {cause}. None of my fixes applies to this, so I'm not proposing one. Nothing was changed.", then "Failures:", one line per group and "Details and trace: on your OcuTalon page.". The unknown text's first line is "{count} {item noun} failed since {time}. I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed.". Every variant renders on all four channels (Integration AC: consumer `Catalog.Render`).
- Given a usable data-format diagnosis of 50 real failed orders, when it is stored, then the incident stays unnoticed with no Notification and no `incident` event, and the with-fix builder's slots, with fixture dry-run slots, render the UJ-1 notice text (R2 (a); the sent notice is Story 7.2's).
- Given a snapshot item with settings whose names hold `bearer` or `cookie` in any case, when the pack is built and `Reader.CredentialName` judges each name, then none of those values reaches the pack and the rule marks each name as a credential, while `TargetConfigName` stays (DW-273, the owner's answer U-91: a false positive only hides a value; a miss sends one to the model).
- Given the product source, when `Test.Bridge.CodeRules` and `ci/checks.sh` run, then they pass: `IncidentManager` is still the only writer and publisher, the watch tools call only listed classes, and no unchecked prepare or embedded SQL is added.

## Spec Change Log

- 2026-10-26, spec gate (Epic 5 runner): R2 and R3 ruled by the orchestrator (veto U-92; DW-270, DW-271, DW-272 routed to Stories 7.2 and 7.4; Epic 5's blocks amended); V1 and V2 ruled vetoes U-93 and U-94; spine rows written; status set to `ready-for-dev`.
- 2026-10-26, resume after the owner's quota hold (Epic 5 runner, run 20261026T1518Z-1-37): the first implement pass was stopped mid-stage; its tree was saved outside git as evidence and taken out (`stage_dead`), so this pass implements the whole spec from the committed source. The owner's answer U-91 is added as DW-273 (a Tasks & Acceptance item, an acceptance criterion and a pinning mutation); status set to `in-progress`.

## Review Triage Log

### 2026-10-26 - Review pass
- verdicts: 26 entries (the layers' findings grouped by shared root cause; members keep the one row) - high 0, medium 3, low 20, false 3, maybe-false 0
- findings:
  - `[false]` `[reject]` Blind 1 / Edge: a data_format_change diagnosis with an empty fix summary stays unnoticed - `DiagnosisPayload.Validate` refuses a data_format_change with a blank fixSummary, so a usable one always has it.
  - `[low]` `[reject]` Blind 2 / Edge 2: a notice whose slots cannot be built is never retried - the spec says one Type 3 warning and the row stays unnoticed; a retry or a generic notice is a new behavior.
  - `[low]` `[reject]` Blind 3 / Edge 1 / Edge 13: rows saved before this change have no Seq - V1 (ruled, veto U-93): no released install holds incidents, no migration is planned.
  - `[low]` `[reject]` Blind 4 / Edge 5 / Edge 6 / gap "Other 1": OfIncident stops at the first Seq gap or MAXGROUPS, Record always writes Seq 1 - the spec fixes the reader ("to the first gap, at most a fixed maximum") and later groups are Story 7.2's (DW-271 context).
  - `[medium]` `[patch]` Blind 5 / Edge 3: an error thrown after NoticedAt is saved leaves the handler failing and the notice half sent - `IncidentManager.Notice` now runs in Try/Catch and logs one Type 3 warning (Notice step guarded; Edge 3's Deliver case is the same fix).
  - `[low]` `[reject]` Blind 6: logRef is a position within one read - the spec defines it so (R-decided, Design Notes `logRef`); the tool docs say it.
  - `[low]` `[reject]` Blind 7: Summary cuts at ". ", "? ", "! " - the spec's definition.
  - `[low]` `[reject]` Blind 8, gap-coverage bullets: second-batch group accumulation, FirstHeaderId across batches and the Check rollback have no test - beyond the spec's Incidents row; no realistic failure shown.
  - `[low]` `[reject]` Blind 9: Payloads.Clean ignores statement status - existing fixture-cleanup pattern; a wrong name would show as leftover fixture rows in the next run.
  - `[false]` `[reject]` Blind 10: body/trace redaction does not know bearer/cookie - DW-273 (U-91) widens only Reader.CREDENTIALPARTS (settings); the spec's acceptance criterion is the settings.
  - `[low]` `[reject]` Edge 4: NoticedAt is set when nobody is to be told - the spec's "Nobody to tell" row says exactly this.
  - `[low]` `[reject]` Edge 7 / Edge 8: non-numeric or non-positive header ids become trace targets - ids come from header keys the poller built from numeric ids; no reachable path.
  - `[low]` `[reject]` Edge 9: duplicate or padded RequestRefs - Story 7.2 writes them (DW-271); nothing writes them in Epic 5.
  - `[low]` `[reject]` Edge 10: FromRow loads each group's Seen list - up to MAXGROUPS rows, one in practice.
  - `[false]` `[reject]` Edge 11: stale NoticeCount after a rolled-back transaction - Check returns the error status and drops both objects; no later save of them.
  - `[low]` `[reject]` Edge 12: Notice reopens the row instead of taking the saved object - the reopen is the intended fresh read.
  - `[medium]` `[patch]` Gap 1: `TestBurstThroughThePoller`'s "unnoticed" negatives ran before the diagnosis answer - they now wait for the diagnosis and one second for the notice step (mutation recorded on `Incidents`).
  - `[low]` `[reject]` Gap 2: the poll can land between Answered's two saves (about a millisecond) - the mutation went red on TestDemoDiagnosis; the Burst test now waits a second.
  - `[medium]` `[patch]` Gap 3: `Diagnose` variants/fallback counted Notifications right after NoticedAt - `WaitNotices` moved to `Case` and used there.
  - `[low]` `[patch]` Gap 4: no assertion that logRef is 1..n - added to `Evidence.TestEventLogCapped`, mutation recorded.
  - `[low]` `[patch]` Gap 5: the no-SQL scan covered `Live.Payload.Incident` only - it now covers `Data.FailureGroup` too, mutation recorded.
  - `[low]` `[patch]` Gap 6: missing `mutation:` lines (AC 2, AC 3, AC 4 on `Notices`; AC 5 channels; AC 6 with-fix; AC 8; Not to notice; Nobody to tell) - each applied, observed red and recorded in `## Verification`.
  - `[low]` `[patch]` Gap 7: `TestInstanceNotice`'s last label read "and no Notification" - now "and no further Notification".
  - `[low]` `[reject]` Gap: `Tell.TestNobodyToNotice`, `Summary(Text(raw))` equality and `Text` vs `Sentence(Redact.Text)` repeat the definition - the pinning mutations are `Tell` adding the owner (red) and `Text` skipping `Redact` (red); the repeated assertions are secondary.
  - `[low]` `[reject]` Gap: `Notices.TestNoticeVariants` has no `ClearMark` - `Diagnose.TestDiagnosisVariants` runs the same way and passes in either order; unverified claim.
  - `[low]` `[reject]` Gap: `Tell.OnAfterOneTest` mixes session and incident refs in `Refs` - harmless.
  - The intent-alignment auditor reported readings, not findings: it names three readings of the intent (end-to-end behaviour, the producer contract, the data model), finds the diff implements the first with the third underneath, and notes the known surfaces (one group per incident in product code, a probe in place of the send in the shadow tests, the trace session by construction). No row.

## Design Notes

**Rulings (R2 and R3 RULED 2026-10-26 by the orchestrator as recommended, veto U-92; V1 and V2 RULED by the epic lead, vetoes U-93 and U-94; the moved criteria travel as ledger entries DW-270 and DW-271 (owner 7.2) and DW-272 (owner 7.4), and Epic 5's blocks carry `[AMENDED … U-92]` markers; the spine rows were written by the lead).** Originally: rulings pending the orchestrator (R2, R3). This spec is written to the recommended answers, carried from Story 5.4's Design Notes. Both move part of an epics criterion of 5.8 to a not-yet-planned Epic 7 story in the same release (veto item 7). The lead applies the ruling at the spec gate.
- **R2. The with-fix notice** [RULED: as recommended, veto U-92; DW-270 to 7.2]. Epics AC 1 asks 5.8 to send the with-fix notice, set `NoticedAt` and publish `open`. That contradicts AD-15's Rule and transition table (`open, not noticed` leaves only "with a fix and a valid dry run (`Raise`)", to `awaiting_approval`), AD-32 (the first request's `ApprovalRef` travels on every incident notice) and the catalog (`incident.withFix` needs `field`, `before`, `after` and `resendCount`, and asks "Approve?"; `Render` refuses a missing slot).
  - Recommended (a): store, don't notice. Story 7.2 sends the notice with the dry run and `Raise`, calling `Deliver` (state `awaiting_approval`, key `incident.withFix`, `Watch.Notice`'s with-fix slots plus its own four, the `ApprovalRef`). AC 5's UJ-1 check ("50 orders and the first failure's time … then the notice") moves to 7.2. Its ordering part is kept here for the no-fix notice (AC 2).
  - Alternatives: (b) amend AD-15 for an interim with-fix notice (needs new public text); (c) send as written (contradicts AD-15 and AD-32, and cannot render). Not recommended.
- **R3. `Requests`' `Result`** [RULED: as recommended, veto U-92; DW-271 to 7.2 (the `RequestRefs` append), DW-272 to 7.4 (the counts)]. No table stores a request's `Total` … `Reason` before Epic 7.
  - Recommended: list each request's `Ref` and `State` from its `ApprovalRequest` row; `Result` is filled by the story that stores a fix run's counts (7.4).
  - Refinement found while planning: `FromRow` runs in `/state` as `OcuTalonUser`, who holds no SQL grant, and AD-13 allows unchecked prepares only in three named methods. So "by `IncidentRef`" cannot be a query there. The rows are reached by `Ref` through the incident's own `RequestRefs` (veto V1), which Story 7.2 appends to at `Raise`. In Epic 5 nothing writes it, and a fixture pins the read.
  - Alternative (b): the whole `Requests` clause moves to 7.2, which raises the first request. `RequestRefs` is then 7.2's.

**Veto items for the spec gate** (not blocking; the lead rules them):
- **V1. Schema.** [RULED: keep, veto U-93] These change how stored data is kept. No released install holds incidents, so no migration is planned.
  - `FailureGroup.Seq` and unique `SeqIndex (IncidentRef, Seq)`: `FromRow` must reach an incident's groups without SQL (AD-13), and a unique index gives `SeqIndexOpen`.
  - `FailureGroup.Count` (SQL `FailureCount`), `FirstAt`, `LastAt`: per-group counts and times for `Groups` and `Evidence.items`. They equal the incident's while an incident has one group; Story 7.2's later groups need their own.
  - `FailureGroup.NoticeCount`: the group lines add up to the notice's `count` when failures join during the diagnosis.
  - `FailureGroup.ErrorSummary`: the groups slot's code-written summary (UX: first sentence, at most 80 characters, through the redactor).
  - `Incident.FirstHeaderId`: `traceTargets.firstFailure`. `Incident.SampleHeaderId` and `SampleError`: `evidence` and `traceTargets.sample`. They are taken from the pack at the settle end, so no second read of the watched namespace is needed.
  - `Incident.RequestRefs`: R3.
  - Entries: `Test/Data/Tables.cls`, under the standing ruling.
- **V2. Public text.** [RULED: keep "no error text", veto U-94] A failure whose error text is empty (`Reader` gives "" when no log row names the message and the header has no error status, `Test.Watch.Reader` L207) has no summary. The catalog refuses an empty `text` slot, so the notice could not render. Proposed: the code-written value "no error text", giving the line `OrdersFromPartner: 3, 'no error text', first at 14:12`. It is public text not in the UX. The other choice is to leave the line out, which breaks "one line per group".

**Governing ADs:**
- AD-4: `Recipients`; an `instance` incident notifies every watcher session.
- AD-8: a fallback has no cause and no fix, and is grouped by item and pattern.
- AD-11: the request row is the truth, so `Requests` reads its state live.
- AD-12: the `incident` payload's fields, the full view, publishing after commit, and trace targets as header id plus namespace.
- AD-13: `FromRow` has no SQL.
- AD-15: the three variants, `NoticedAt` at the notice, `open` plus the variant, the noun, and the transitions (R2).
- AD-22: the mock, throwaways.
- AD-26: the notice in the incident's trace session; the trace targets.
- AD-29 and AD-33: Lane A; `IncidentManager` is the only writer and publisher.
- AD-30: `IncidentManager` consumes the diagnosis; never `OutcomeRouter`.
- AD-31: `cause` is already filtered.
- AD-32: the Notification contract; producers never render; `ApprovalRef` only with a request.

Conventions: "Diagnosis", "Watch failures" (`ErrorText.Text` is the row's composition), "Text OcuTalon sends", "Notice cards" (kind `incident` gets a Delivery row and no card; the page shows the incident), "Identifiers" (`logRef`; header ids only for traces), "Redaction", "Times".

**Integration ACs, Consumes, Consumed-by:**
- New: `Watch.Notice`, `IncidentManager`'s notice step and `Deliver`, `FailureGroup.OfIncident`, `ErrorText.Text`/`Summary`, and `FromRow`'s fields.
- In-story consumers:
  - `WebChatOut` through `Notify` (AC 1);
  - `/state`'s `StateBody` (AC 4);
  - `Catalog.Render` (AC 5);
  - `FailurePoller`, `EvidencePack`, `Watch.Notice` of `ErrorText`.
- Consumes:
  - 5.4: the stored diagnosis or fallback, `ItemNoun`, `DecisionRef`, `TraceHeaderId`, the live pack;
  - 5.3: `Record`, `Check`, `Tell`, the waiter;
  - Epic 2: `Session.Recipients`, `Live.Publish`, `Notify`/`WebChatOut`, `Web.Api.StateBody`;
  - Epic 0: `Catalog.Render`, `Msg.Notification`, the payload parts;
  - Epic 3: `ApprovalRequest`.
- Consumed-by:
  - 7.2: `Deliver` and the with-fix builder; appends `RequestRefs`; later groups take the next `Seq` and their own counts;
  - 7.4: `Requests`' `result`;
  - 5.5: its transition table takes over the `open`-plus-variant move;
  - Epic 6: Show details reads `evidence`, `traceTargets`, `groups`, `requests`;
  - Epic 4's `SimPhoneOut` and Epic 12's `TelegramOut` render these keys and slots.

**Extend, don't copy:**
- `Tell` gains the Notification instead of a second recipient loop.
- `OfIncident` replaces `IncidentManager.Groups`' and `EvidencePack.Group`'s SQL, so there is one reader of an incident's groups.
- `ErrorText.Text` replaces two copies (DW-261).
- `FromRow` follows `Approval.FromRow`'s object-access read and `$Namespace` trace target.
- `IncidentProbe` gains `SendNotice` beside `Say`, `Refuse` and `Answer`.
- `Notices` follows `Diagnose`'s marker batches, and `TestInstanceNotice` follows `Incidents.TestInstanceShared`.

**Ledger inbox:**
- DW-261 is addressed: Always "DW-261", the `ErrorText` task, the Error summary row and `NoticeText`.
- DW-264 is addressed: Always "DW-264", the `EvidencePack` task and the DW-264 row. `Evidence.cls` asserts `logRef` and no `logId`.
- DW-273 is addressed (added by the lead at the resume, the owner's answer U-91): the `Reader.cls` task, its acceptance criterion and the DW-273 mutation row.

**Decided in-stage:**
- **The notice step follows the stored outcome** in the same waiter job: no new message, alarm or state.
- **`Deliver` makes two saves.** The diagnosis is saved by 5.4's code, then the notice's row change, so 7.2 can call `Deliver` on its own.
- **The notice's `time` is `FirstAt`, and `count` is `NoticeCount`.** The payload keeps its live `count`.
- **Groups.** The payload lists every group; the notice lists the groups settled with it (`NoticeCount` set).
- **A fallback needs no timeout row.** The variant follows `Fallback` whatever the reason. The refusal, invalid and error rows pin it, and `NoticeText` renders the `timeout` reason, so no CI stack waits out Decide's 60-second timer.
- **`logRef`** is the position in the read's own event log. Both tools read with the same keys, so one row has one `logRef` in both answers (inference).
- **The summary's cut** at a word with U+2026 is a format choice; the UX fixes only "at most 80 characters".
- **Object access is not an "unchecked path"** in AD-13's sense: `Web.Api.CurrentSession` and `Approval.FromRow` already read rows by id in REST (spine candidate below).
- **`Diagnosis`' instructions are unchanged.** The tool descriptions name `logRef`.
- **`Watch.Notice` takes the groups as an argument.** `Slots` and `Groups` accept the incident's group list (default: `FailureGroup.OfIncident`), so `NoticeText` renders every variant from unsaved rows and runs warm.
- **Two lenient reads in `Watch.Notice`.** `count` is the `Count` when `NoticeCount` is empty, and a group line takes the incident's `FirstAt` when the group has none, so a legacy row still renders.
- **A failed send does not keep its own session from the event.** `Tell` sends, then publishes, for each session whatever the send answered; the warning is one per notice (the first error).
- **`FirstHeaderId` ties.** At equal times a lower header id replaces the held one; a held log-row first failure (empty id) is never replaced at an equal time.
- **`SampleHeaderId`** is stored only when the pack's sample has a positive whole-number `headerId`; a log-row sample leaves it empty.
- **`Test.Watch.Incidents` points the runners at the CI mock in every test** (`Case.PointKeys`). Without a key the diagnosis is the `no_key` fallback, and a fallback is now noticed at once; with the mock, the default diagnosis is the data-format one, which stays unnoticed (the "nothing noticed" assertions of `TestBurstThroughThePoller`, `TestTwoSessions` and `TestInstanceShared` hold).
- **`/state` targets carry a link.** `Web.TraceLink.Add` (contended, untouched) adds `traceUrl` to each snapshot trace target, so `Notices` compares `groups` and `evidence` as JSON and the targets as `name=id@namespace`.
- **`ci/checks.sh`** fails only the `boundaries` rule "no local machine path" on `cycle-log-epic-5.md` line 121 (the orchestrator's stage log, committed before this stage); the rule passes for everything this story changed.

**(inference), to be pinned by the tests:**
- `OcuTalonUser` cannot run a checked query in `/state` (AD-13 states it; the no-SQL test pins the code).
- `%JSON` leaves out an empty list and an unset object (today's `TestFromRow` relies on it).
- The generated `SeqIndexOpen(ref, n)` reads without SQL.

**Footprint extensions** (none contended): `Live/Payload/Incident.cls` (Lane A home area, AD-33: Lane A publishes `incident`); `Test/Live/Payloads.cls` (its Incident rows); `Test/Data/Tables.cls` (standing ruling: two entries).

**Spine (Rule 20), written by the lead at the spec gate:** the "Watch failures" and "Identifiers" rows were amended and the row "Incident notice" added. The candidates were:
- "Watch failures": name `ErrorText.Text` and `Summary`.
- "Identifiers": the pack and tools carry `logRef`.
- AD-12 or AD-13: a payload builder that `/state` calls reads rows by object access only.
- AD-15: the notice step and its keys; the `Seq` group reader.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`. Run one command per call, each with `timeout: 600000`. Never put two IRIS test runs in one message, and chain nothing after a shard part.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e5s8iw ci/warm.sh up` -- once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s8iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Watch.NoticeText`, `OcuTalon.Test.Watch.Tell`, `OcuTalon.Test.Watch.Evidence`, `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Bridge.Decide` (tool JSON size), `OcuTalon.Test.Web.Api` (fixture incidents through `FromRow`) -- expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s8i ci/iris.sh class <Class>`, fresh, one call per class, because production items changed (`IncidentManager`, `FailurePoller`): `OcuTalon.Test.Watch.Notices`, `OcuTalon.Test.Watch.Diagnose`, `OcuTalon.Test.Watch.Incidents`, `OcuTalon.Test.Watch.Poller` -- expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e5s8i ci/iris.sh shard lane-a --part 1/2`, then in its own call `... --part 2/2`. The shard now has 62 classes. Record each part's time. If a part takes more than 480 s, use `--part k/3` (three calls) and record those times.
- (once) `<lane> OCUTALON_RUN_TAG=e5s8i ci/iris.sh shard lane-b` -- `Test.Live`, `Test.Data` and `Test.Web` are in it. Expected: passed.
- (once) `bash ci/checks.sh` -- expected: all pass (class rules, storage blocks).
- (once) `<lane> OCUTALON_RUN_TAG=e5s8iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s8i ci/iris.sh teardown`.

**Shared surfaces:**
- **Schema** of `Incident` and `FailureGroup` (`Test.Data.Tables`). A `FailureGroup` row needs `Seq` to be found: fixture rows set it (`Test.Watch.Evidence`, `Test.Watch.Diagnose.Row`, the new tests).
- **The `incident` payload** now carries `groups`, `evidence`, `traceTargets` and `requests`: `Test.Live.Payloads.TestFromRow`, and `Test.Web.Api`'s `/state` assertions (contended: run them, change nothing).
- **No-fix and fallback incidents are noticed.** They get Notifications, `incident` Delivery rows and `incident` events: `Test.Watch.Diagnose` (variants and refused), and every test that counts Notifications, Delivery rows or `incident` events of a watch session. Data-format incidents stay unnoticed, so `Test.Watch.Incidents` and `TestDemoDiagnosis` keep their "nothing noticed" assertions.
- **The pack and tool JSON:** `logRef` replaces `logId` (`Test.Watch.Evidence`).
- **`IncidentProbe`** now overrides `SendNotice` (`Test.Watch.Tell`, `Test.Watch.Diagnose`).
- **The `lane-a` class list:** two new classes, run as parts.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19). The implement stage applies each one, observes red, reverts byte-identically and records it here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | the notice step skips `no_fix` | `Notices.TestNoticeVariants` |
| AC 1, Delivery | the Notification's `Kind` is `tellnow` | `TestNoticeVariants` (the `incident` Delivery rows) |
| AC 2 | `Deliver` publishes no `incident` event | `TestNoticeVariants`, `Tell.TestNoticeToEachRecipient` |
| AC 3 (U-86) | `Tell` sends the notice only to the first recipient | `TestNoticeToEachRecipient`, `Notices.TestInstanceNotice` |
| AC 4 | `FromRow` leaves `Evidence` out | `Payloads.TestFromRowEvidence`, `TestNoticeVariants` (the `/state` row) |
| AC 5 | `Watch.Notice` gives `Count` for `count` | `NoticeText` (count is NoticeCount) |
| AC 5, unknown | `unknown` gets `incident.noFix` | `NoticeText`, `TestNoticeVariants` |
| AC 6 (R2 (a)) | the notice step treats `data_format_change` as no-fix | `Diagnose.TestDemoDiagnosis` |
| Fallback | an unknown reason is passed as it is | `NoticeText` (the `zz` reason) |
| A send fails | the first failed send stops the loop | `Tell.TestFailedSendLeavesTheOthersTheirNotice` |
| Show details | `sample` takes `$Namespace` | `TestFromRowEvidence`, `TestNoticeVariants` |
| Requests | `FromRow` skips the `IncidentRef` check | `TestFromRowEvidence` |
| AD-13 | `FromRow` reads groups with `%ExecDirect` | `Payloads.TestIncidentFromRowReadsNoSql` |
| Group fields | `Record` leaves the group `Count` | `Incidents.TestBurstThroughThePoller` |
| Error summary | `Summary` cuts at 100 | `NoticeText` |
| DW-261 | `Text` skips `Redact.Text` | `NoticeText`, `Evidence.TestLogKeys` (its redacted text) |
| DW-264 | `LogMessage` gives `logId` again | `Evidence.TestLogKeys` |
| DW-273 | `CREDENTIALPARTS` loses `cookie` (or `bearer`) | `Evidence.TestCredentialsLeftOut` |

**Results (implement stage, 2026-10-26; re-run after the review patches).** Warm (`e5s8iw`): `NoticeText`, `Tell`, `Evidence`, `Payloads`, `CodeRules` passed after the patches (`Tables`, `Decide` and `Web.Api` passed before them and are in the shards). Fresh (`e5s8i`): `Notices`, `Diagnose`, `Incidents`, `Poller` passed after the patches. `shard lane-a --part 1/2` passed (31 classes, 377 s), `--part 2/2` passed (31 classes, 395 s); `shard lane-b` passed (42 classes, 114 s). `ci/checks.sh`: every script passes but `boundaries`, which fails only on `_bmad-output/implementation-artifacts/cycle-log-epic-5.md:121` (the lead's committed `stage_dead` line holds a local path; it is in the baseline commit and in no file of this diff, so it is the lead's to fix). The warm stack and the throwaway stacks were torn down.

**Pinning mutations applied (Rule 19).** Each was applied, observed red, and reverted with the tree byte-identical (`git status --short` and the file hashes matched the pre-mutation state).
- mutation: the notice step skips `no_fix` (`IncidentManager.Notice` quits for variant no_fix) -> `Notices.TestNoticeVariants` red (no notice, no incident event, no Delivery row for the no-fix and unknown incidents)
- mutation: the Notification's `Kind` is `tellnow` (`IncidentManager` `NOTICEKIND`) -> `Notices.TestNoticeVariants` red (the `incident` Delivery rows and the Notification kind) and `Notices.TestInstanceNotice` red
- mutation: `Deliver` publishes no `incident` event (`Tell` publishes only when it has no notification) -> `Tell.TestNoticeToEachRecipient` red (and `TestFailedSendLeavesTheOthersTheirNotice`)
- mutation: `Tell` sends the notice only to the first recipient -> `Tell.TestNoticeToEachRecipient` red (and `TestFailedSendLeavesTheOthersTheirNotice`)
- mutation: `FromRow` leaves `Evidence` out (`Set payload.Evidence` dropped) -> `Payloads.TestFromRowEvidence` red
- mutation: `Watch.Notice` gives `Count` for `count` -> `NoticeText` red (`TestNoFix`, `TestUnknown`, `TestWithFix`)
- mutation: `unknown` gets `incident.noFix` (`Notice.Key`) -> `NoticeText` red (`TestKeysAndVariants`, `TestUnknown`)
- mutation: the notice step treats `data_format_change` as no-fix (`Notice.Key` gives `incident.noFix`) -> `Diagnose.TestDemoDiagnosis` red (NoticedAt set, a Notification and an `incident` event)
- mutation: an unknown fallback reason is passed as it is (`Notice.Reason`) -> `NoticeText.TestFallback` red (the `zz` reason)
- mutation: the first failed send stops the loop (`Tell` quits after a failed send) -> `Tell.TestFailedSendLeavesTheOthersTheirNotice` red
- mutation: `sample` takes `$Namespace` (`FromRow`) -> `Payloads.TestFromRowEvidence` red
- mutation: `FromRow` skips the `IncidentRef` check of a request -> `Payloads.TestFromRowEvidence` red
- mutation: `FromRow` reads groups with `%ExecDirect` -> `Payloads.TestIncidentFromRowReadsNoSql` red
- mutation: `Record` leaves the group `Count` -> `Incidents.TestBurstThroughThePoller` red
- mutation: `Summary` cuts at 100 (`SUMMARYMAX`) -> `NoticeText.TestSummary` red
- mutation: `Text` skips `Redact.Text` -> `NoticeText` red (`TestErrorText`, `TestSummary`) and `Evidence` red (`TestLogKeys`, `TestRedaction`)
- mutation: `LogMessage` gives `logId` again -> `Evidence.TestLogKeys` red
- mutation: `CREDENTIALPARTS` loses `cookie` -> `Evidence.TestCredentialsLeftOut` red
- mutation: `Tell` sends the notice only to the first recipient -> `Notices.TestInstanceNotice` red (two Notifications, A and B, the event on each stream)
- mutation: `Tell` publishes no event (`Set sc = $$$OK` for the publish) -> `Notices.TestNoticeVariants` red (A's stream in Seq order, four incident events) and `Notices.TestInstanceNotice` red
- mutation: `FromRow` leaves `Evidence` out (`Set payload.Evidence = ""`) -> `Notices.TestNoticeVariants` red (an error on the missing evidence object in the `/state` comparison)
- mutation: `WithFixSlots` leaves `fixSummary` out -> `NoticeText.TestWithFix` red (the UJ-1 text no longer renders) and `NoticeText.TestEveryChannel` red (incident.withFix on web, phone, mailbox and telegram)
- mutation: `Tell` adds the owner to the recipients -> `Tell.TestNobodyToNotice` red (a send and a log line for an `eval` or an online-demo `instance` owner), and `TestNoticeToEachRecipient`, `TestFailedSendLeavesTheOthersTheirNotice` red
- mutation: the `Open` check is dropped from `Refused` and `Notice` (dropping it from `Notice` alone is covered by `Refused`'s own check and stays green) -> `Diagnose.TestRefusedRequest` red (a noticed incident is written, a closed one too)
- mutation: `EvidencePack.EventLog` gives `logRef` 1 for every row -> `Evidence.TestEventLogCapped` red (logRef 1 to n)
- mutation: a second code line in `FailureGroup.OfIncident` runs `%SQL.Statement.%ExecDirect` -> `Payloads.TestIncidentFromRowReadsNoSql` red (the scan now covers `Data.FailureGroup` as well)
- mutation: `Watch.Notice.Key` treats `data_format_change` as no-fix, run against `Incidents` (whose negatives now wait for the diagnosis) -> `Incidents.TestTwoSessions` red (an unnoticed incident is noticed)
- mutation: `Watch.Notice.Key` publishes an `incident` event (a second publisher) -> `Bridge.CodeRules.TestOnlyIncidentManagerWritesIncidents` red (AC 8: `IncidentManager` stays the only publisher)

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** Story 5.8 is implemented in full. As soon as `Answered` or `Refused` stores an outcome, `IncidentManager.Notice` sends the incident notice: a fallback, an unknown cause or a cause with no fix gets one kind-`incident` Notification per `Session.Recipients` session (key and slots from the new pure `Watch.Notice`), `NoticedAt`, `open` and the open variant on the row, and the `incident` event on each watcher's stream. A usable data-format diagnosis stays stored and unnoticed (R2 (a)). `FromRow` fills `groups`, `evidence`, `traceTargets` and `requests` from rows only, with no SQL. The rows keep the new group and incident fields (V1). DW-261 (`ErrorText.Text`/`Summary`), DW-264 (`logRef`) and DW-273 (`bearer`, `cookie` in `Reader.CREDENTIALPARTS`) are settled.

**Files changed** (all under `src/ocutalon/cls/OcuTalon/`):
- `Data/FailureGroup.cls`, `Data/Incident.cls`: the new fields, the unique `SeqIndex`, `FailureGroup.OfIncident`; `Test/Data/Tables.cls`: their Contracts entries.
- `Watch/Notice.cls` (new, pure): key, open variant, slots and group lines of each notice, and the with-fix builder.
- `Watch/IncidentManager.cls`: group fields in `Record`, `NoticeCount` per group in `Check`, the sample in `Diagnose`, `Notice`/`Deliver`/`SendNotice` and the `Tell` extension.
- `Live/Payload/Incident.cls`: `FromRow` fills the Show-details fields by object access.
- `Watch/ErrorText.cls`, `Watch/FailurePoller.cls`, `Watch/EvidencePack.cls`, `Tools/WatchReads.cls`: `Text`/`Summary`, `logRef`, `OfIncident`.
- `Watch/Reader.cls`: DW-273.
- Tests: new `Test/Watch/NoticeText.cls`, `Test/Watch/Notices.cls`; changed `IncidentProbe`, `Case`, `Tell`, `Diagnose`, `Incidents`, `Evidence`, `Test/Live/Payloads.cls`.

**Review.** Four layers (blind hunter, edge-case hunter, verification-gap, intent-alignment). Patches applied: 3 medium (`Notice` runs in Try/Catch; the Burst test's "unnoticed" assertions wait for the diagnosis; the Diagnose tests wait for the Notification, with `WaitNotices` moved to `Case`) and 4 low (a `logRef` 1..n assertion, the no-SQL scan over `Data.FailureGroup`, the label of one assertion, ten missing `mutation:` lines now demonstrated). Nothing deferred. Rejected: 3 false and 17 low entries, each with its reason in the Review Triage Log (mostly spec-fixed behavior: no migration, one group per incident until Story 7.2, notice not retried, row noticed when nobody is told).

**Follow-up review recommended: true.** Three medium entries were patched. The unverified risk: the two test-timing patches (the one-second grace after the diagnosis in `Incidents.TestBurstThroughThePoller`, and `WaitNotices` in `Diagnose`) passed once each on fresh stacks and are not run in reverse order or repeated.

**Verification.** Warm and fresh classes of the `(loop)` lines passed after the patches (`Evidence`, `Payloads`, `NoticeText`, `Tell`, `CodeRules`; `Notices`, `Diagnose`, `Incidents`, `Poller`). `(once)` lines after the last patch: `shard lane-a --part 1/2` 377 s and `--part 2/2` 395 s (31 classes each), `shard lane-b` 114 s (42 classes), all passed; stacks torn down. `ci/checks.sh`: all scripts pass except `boundaries`, which fails only on `_bmad-output/implementation-artifacts/cycle-log-epic-5.md:121`, the lead's `stage_dead` log line (it holds a local path, is in the baseline commit and in no file of this diff). The lead must correct that line before CI. Every pinning mutation of the spec's table, and ten more for the review's gaps, was applied, observed red and reverted (`git status --short` and the file hashes identical).

**Residual risks.** The `boundaries` red above (not this story's file). The real `Notify` route is exercised only in `Notices` (fresh); the shadow-instance tests use the probe's `SendNotice`. `Test.Web.Api` ran in the shards, unchanged.
