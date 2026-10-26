---
title: 'New failures are picked up within seconds'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: 'c8bedd4468f71aaef38c21a1345cb152f1b3bbcf'
baseline_commit: 'c8bedd4468f71aaef38c21a1345cb152f1b3bbcf'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `FailurePoller` and `IncidentManager` are stubs and `WatchMark` holds no mark, so a watched production's failures never reach anything: UJ-1's Break the feed would fail 50 orders and OcuTalon would not notice. Separately (DW-222), the reader drops a cleanly stopped production, so it cannot be watched and a watch on it cannot be stopped from chat.

**Approach:** Build `FailurePoller` as an `Ens.InboundAdapter` service (every 3 s) that, for each watched production, reads new failures through `Watch.Reader`'s one namespace-switching method above the production's `WatchMark`, scopes each to the session whose `TraceRef` is its `SuperSession` (else `instance`), and sends `IncidentManager` one `FailureBatch` per scope per poll only when something is new. `IncidentManager` accepts the batch (Story 5.3 groups it). The reader also lists a namespace's last-started production, and `stop_watch` resolves from the session's own watches first.

## Boundaries & Constraints

**Always:**
- A **failure** is (a) a message header in `Status` 8 (Error), whatever its `IsError`, or (b) an event-log row of `Type` 2 (Error) or 6 (Alert) that has no `SessionId`. A log row with a session is never a failure on its own: it is the error text of its session's errored header (DW-35, measured below). A response header with only `IsError` 1 is not a failure.
- Only `Watch.Reader` switches namespace, still in exactly one method with `New $NAMESPACE` that calls no OcuTalon class while switched (5.1's rule). Readability (`CheckUserPermission` for Decide's `ServiceUser` on the namespace's data-database resource) is checked before any switch; an unreadable namespace is never entered (AD-3, NFR-12).
- A watched production is read only while it is the namespace's own production: the running one, else the last started (`Ens.Director.GetActiveProductionName()`), never any other `Ens.Config.Production` row (DW-38, DW-222).
- `WatchMark` is the one store of the high-water mark, written only by `FailurePoller`. It survives restarts (AD-5): nothing that decides "new" lives in memory.
- A failure tagged with a session's `TraceRef` is scoped to that session, on any install, whether or not that session watches the production (AD-4). Every batch is its own trace session, with `SuperSession` = the scope session's `TraceRef` (empty for `instance`) (AD-26).
- `FailurePoller` logs only Type 3 warnings (never an error row) and its `OnProcessInput` always returns OK.
- The production is never changed and its alerts are never relied on (AD-15).

**Never:**
- No `Incident`, `FailureGroup`, `watch.progress`, `incident` event, notice or settle logic (Story 5.3), no evidence pack (5.4), no check runs or `check` event (5.6).
- No change to `OcuTalon.Msg.*` contracts, `Core/*`, `Data/Session.cls`, `Data/Ownership.cls`, or any contended path except the two Contracts entries of `Test/Data/Tables.cls` ruled in Design Notes.
- No embedded SQL and no unchecked prepare (`ci/checks.sh` class rules); no `%AI`, Python or session call in any class the watch tools call (AD-6).
- No pickup-time assertion in CI: NFR-7's 15 s / typical 3 s is measured in the clean-machine rehearsal.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Session-tagged | Session A watches Orders; 3 failing orders tagged with A's `TraceRef` | `FailureBatch`(es) to `IncidentManager`: `Namespace` OCUORDERS, `Production` `OcuTalon.Demo.Orders.Production`, `OwnerRef` A, the 3 failed header ids once each, `Kind` header, `ItemName` OrdersFromPartner, `ErrorText` "The order date was not in the expected format. Expected YYYY-MM-DD, got '10/16/2026'.", `FailedAt` UTC to the second. Each batch header: `SuperSession` = A's `TraceRef`, its own `SessionId`, `Completed` at IncidentManager | none |
| Untagged | 2 failing orders with no `TraceRef` | One batch scope `instance`, empty `SuperSession` | none |
| Scopes in one poll | A-tagged, B-tagged (B watches nothing) and untagged failures | At most one batch per (production, `OwnerRef`) per poll (`PolledAt`); B's failures scoped to B | none |
| Nothing new | watched, no new failure | No batch and no `WatchMark` write | none |
| Again / restart | poller temp-stopped, 2 failures, poller started | The 2 arrive once after the start; earlier failures never again | none |
| Late error | a header created earlier enters `Status` 8 after a later header was batched | Batched in a later poll, once | none |
| Watch after failures | failures, then the production's first watch | Failures before the earliest watch row's `CreatedAt` are not batched; later ones are | none |
| Unreadable | Read on `%DB_OCUORDERS_DATA` removed from the service role | Nothing read (no switch), no batch, mark unchanged; grant back: those failures batched once | none |
| Not the own production | watch row for OCUTALON / `OcuTalon.Demo.Orders.Production`, OCUTALON made readable | Reader answers `not_current`; nothing read | none |
| Headerless log row | Type 2 or 6 row with no session | One failure, `Kind` error or alert, `ItemName` = the row's `ConfigName`, scope `instance`. The Orders failures give 3 failures, not 6 | none |
| Flood | more than 500 new failures | At most 500 per production per poll; the rest next poll; none twice | none |
| Read or send error | the read step throws (a test probe overrides the poller's private read seam), or a send fails | One Type 3 warning naming the production, mark unchanged, `OnProcessInput` OK | warning |
| Stopped production (DW-222) | Orders cleanly stopped | `Productions` lists Orders; start_watch admits it; its tail failures are still read | none |
| Stop from own rows (DW-222) | A watches Orders, grant removed (reader no longer lists it) | stop_watch("Orders") resolves from A's own watches, submits StopWatch, the row goes, outcome `stopped`. Own matches ambiguous: `ambiguous`; no own match: the reader path, unchanged | none |
| Fix copy | any failed header | Batched by scope with its `HeaderId` (no copy registry exists until Story 7.3) | none |

</intent-contract>

## Code Map

All `OcuTalon/...` paths are under `src/ocutalon/cls/`.

- `OcuTalon/Watch/FailurePoller.cls` -- stub (`STUB` 1, no adapter). Build it. Pattern (read-only, Lane B): `Core/StatusMonitor.cls` (`ADAPTER` `Ens.InboundAdapter`, warnings, always OK); `Demo/Orders/Partner.cls:72` sets `..%SuperSession` in a service.
- `OcuTalon/Watch/IncidentManager.cls` -- stub BP. `Test/Install/Production.cls` `TestStubsAnswer` (L139-171) sends an `Ens.StringRequest` to every `STUB` class and expects 5003; `Test/Core/CommandsInProduction.cls` (Epic 4, contended) expects a `Dismiss` to answer `not_built`; `Test/Bridge/Approval.cls` sends `ApprovalOutcome` to it. All three stay true if only `FailureBatch` is accepted and `STUB` stays.
- `OcuTalon/Data/WatchMark.cls` -- only `Namespace`, `Production`, unique index. Needs the mark.
- `OcuTalon/Data/BackgroundCheck.cls` -- no creation time (`NextDueAt` is moved by Story 5.6).
- `OcuTalon/Watch/Reader.cls` -- `Current` L131-150 is the one switching method (`GetProductionStatus` with `LOCKSECONDS`, `skipLockIfRunning`); `Productions` L32-56; `Find` L60-73; private `Normalize` L106-114 and `Readable` L118-126.
- `OcuTalon/Watch/Ops.cls` -- `OnStart` L49-89 writes the row (`NextDueAt` L74); `OnStop` L92-118 already deletes the session's row without asking the reader.
- `OcuTalon/Tools/WatchTools.cls` `StopWatch` and `OcuTalon/Tools/WatchAnswers.cls` `Resolve` L18-24, `Decide` L29-44, `Names` -- stop resolves through the reader only today. `Tools/CommandCall.cls` `Session(.context)` gives the context (`OwnerRef` = session Ref).
- `OcuTalon/Data/Ownership.cls:212` `Checks(sessionRef)` -- Lane B (Epic 16), call-only: the session's `BackgroundCheck` objects; in `CALLBACKHELPERS` already.
- `OcuTalon/Data/Session.cls:36` -- `TraceRefIndex` (unique): `TraceRefIndexOpen(superSession)` gives the scope. Call-only.
- `OcuTalon/Production.cls` L36-37 -- Lane A region: `FailurePoller` `PoolSize="0"`, `IncidentManager`.
- `OcuTalon/Test/Install/Production.cls` L623-624 -- oracle rows of both items.
- `OcuTalon/Test/Bridge/CodeRules.cls` L62 `CALLBACKHELPERS`, L65 `READERCLASSES`.
- `OcuTalon/Test/Data/Tables.cls` L454-483 (Epic 16, CONTENDED) -- the Contracts XData pins `BackgroundCheck` and `WatchMark` property sets exactly (`TestContracts`).
- `OcuTalon/Test/Watch/Case.cls` -- the watch tests' base: `Reason`, `GrantRole`/`RevokeRole` (restored in `OnAfterOneTest`), `Watch`, `Rows`; extends `Test/Core/InProduction.cls` (`Session(name)` L100: a fixture session whose `TraceRef` is a run SuperSession; cleanup removes OCUTALON messages of the run's SuperSessions).
- `OcuTalon/Test/Demo/Production.cls` (Epic 4, read-only) -- `Send` L342-348 (private: switch to OCUORDERS, `OcuTalon.Demo.Orders.Partner.Send(count, dateFormat, traceRef, orderDate)`), `WaitCount` L322; `Test/Data/Fixture.cls` `RemoveMessages(refs, namespace)` (Epic 16, call-only).
- `eval/orders-date-format/snapshot.json` -- the recorded shape of an Orders failure.
- IRIS source (reference): `irislib/Ens/Actor.cls:482-483` (`$$$LOGSTATUS` before `SetStatus(Error)`); `irislib/Ens/BusinessOperation.cls:404` (an operation logs a repeated error text once, so headers, not log rows, count failures); `irislib/Ens/Util/Log.cls:88-89` (`MessageId` is the job's current header, else the newest header id of the namespace, so trust it only with a matching `SessionId`); `irislib/Ens/Director.cls:1664` `GetActiveProductionName()`, `:2467` `TempStopConfigItem(name, stop, doUpdate)`; `irislib/Ens/Queue.cls:152` (`EnQueue` commits any open transaction, so a send and a mark save cannot be one transaction); `irislib/Ens/MessageHeader.cls` `SetStatus` (sets `TimeProcessed` with the status; `TimeProcessed` and `Status` are indexed).
- Platform measured in Task 0 (2026-10-25, lane-A warm throwaway `e5s2pw`, build 154, torn down):
  - 3 failing orders: each one request header (`Type` 1) `Status` 8, `IsError` 0, `SuperSession` = the tag, `TimeProcessed` set at the failure (`2026-10-25 22:46:48.801`, IRIS UTC with ms), no response header.
  - Each has one log row `Type` 2, `ConfigName` OrdersFromPartner, `SessionId` = the header's session, `MessageId` = the header id, `TimeLogged` about 10 ms before `TimeProcessed`. Text: `ERROR <Ens>ErrBPTerminated: Terminating BP OrdersFromPartner # due to error: ERROR #5001: <sentence>` then a line break and `  > ERROR #5001: <sentence>`.
  - After `StopProduction` in OCUORDERS: `GetProductionStatus` name "" (state 2), `GetActiveProductionName()` = `OcuTalon.Demo.Orders.Production` (`^Ens.Configuration("csp","LastProduction")`), `Description` still "Orders". HSCUSTOM, HSLIB, HSSYS and USER give "" from both. `StartProduction` restores it in about 10 ms.

## Tasks & Acceptance

**Execution:**
- Task 0 is done (Code Map, "Platform measured"). The implement stage re-measures only where a test contradicts it, and records the difference under Design Notes.
- `src/ocutalon/cls/OcuTalon/Data/WatchMark.cls` -- add `MarkAt` (`%String(MAXLEN = 23)`: the newest failure time read, as IRIS stores it, UTC `YYYY-MM-DD HH:MM:SS.sss`) and `Seen` (`%String(MAXLEN = "")`: the failures already batched whose time is within the overlap before `MarkAt`, `h<header id>` / `l<log id>`, comma-separated). Storage appended by the compiler, committed (AD-5).
- `src/ocutalon/cls/OcuTalon/Data/BackgroundCheck.cls` -- add `CreatedAt` (`%String(MAXLEN = 20)`, UTC to the second).
- `src/ocutalon/cls/OcuTalon/Watch/Ops.cls` -- `OnStart` writes `CreatedAt` with the same `NowUtc()` value as `NextDueAt`; doc comment.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` --
  - `Current`: when `GetProductionStatus` gives "", take `Ens.Director.GetActiveProductionName()` (DW-222).
  - `Failures(namespace, production, from, limit, Output rows)` returning an outcome (`read`, `unreadable`, `not_current`): checks readability first (no switch when unreadable); in the reader's one switching method (today `Current`, which then serves both reads), confirms the namespace's own production equals `production`, then reads errored headers (`Status` 8, `TimeProcessed` >= `from`) with their raw error text (the `Type` 2 row whose `MessageId` is the header and whose `SessionId` matches; else the session's `Type` 2 row at the header's target; else the header's `ErrorStatus` text when `IsError`; else "") and headerless `Type` 2/6 rows (`SessionId` null, `TimeLogged` >= `from`), in (time, id) order, at most `limit`. Each row: `kind`, `headerId`, `sessionId`, `superSession`, `item`, `source`, `bodyClass`, `at` (IRIS UTC), `logId`, `errorText`. SQL through `%SQL.Statement` (checked).
  - Extract the pure name matcher from `Find` (for example `Matches(entries, name, namespace)`), so the stop resolver uses the same rule.
- `src/ocutalon/cls/OcuTalon/Watch/ErrorText.cls` -- new pure class: `Sentence(text)` gives the error's own sentence: after the first " due to error: " when the text holds "Terminating BP", up to the first line break or "  > ", without a leading `ERROR #<n>: ` or `ERROR <Ens>Name: `, trimmed, at most 1000 characters (DW-35).
- `src/ocutalon/cls/OcuTalon/Watch/Mark.cls` -- new pure class: the start (`max(MarkAt, earliest CreatedAt as IRIS UTC)`, or the earliest `CreatedAt`, or the poll time when no row has one), dropping `Seen` failures, capping at `MAXFAILURES` 500, and the next `MarkAt`/`Seen` with `OVERLAP` 2 seconds; `FailedAt` formatting (IRIS UTC to `YYYY-MM-DDTHH:MM:SSZ`).
- `src/ocutalon/cls/OcuTalon/Watch/Msg/FailureBatch.cls` (extends `Ens.Request`: `Namespace`, `Production`, `OwnerRef`, `PolledAt` UTC to the second, `Failures` list of the serial below) and `src/ocutalon/cls/OcuTalon/Watch/Msg/Failure.cls` (`%SerialObject`: `Kind`, `HeaderId`, `SessionId`, `ItemName`, `SourceName`, `BodyClass`, `ErrorText` 1000, `FailedAt`, `LogId`) -- new; storage blocks committed; no SQL reserved words (`Test.Data.Tables` `TestSqlNames`).
- `src/ocutalon/cls/OcuTalon/Watch/FailurePoller.cls` -- remove `STUB`; `ADAPTER` `Ens.InboundAdapter`. Each call: the distinct watched (`Namespace`, `Production`) of `Kind` production rows with their earliest `CreatedAt`; per production: `Mark` start, `Reader.Failures`, drop `Seen`, cap, scope (`Session.TraceRefIndexOpen(superSession)` → Ref, else `instance`), one `FailureBatch` per scope sent async to `IncidentManager` after clearing `..%SessionId` and setting `..%SuperSession`, then save the `WatchMark` (create on first sight). Nothing new: no send, no save. Any error: one warning, that production's mark unsaved, OK returned. The `Reader.Failures` call sits in one private method, the seam that `Test.Watch.PollerProbe` overrides.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- `OnRequest` completes a `FailureBatch` with no response and writes nothing; anything else still answers 5003; `STUB` stays (5.3 and 5.5 build it). Doc comment.
- `src/ocutalon/cls/OcuTalon/Production.cls` -- Lane A region only: `FailurePoller` `PoolSize="1"` with `<Setting Target="Adapter" Name="CallInterval">3</Setting>`.
- `src/ocutalon/cls/OcuTalon/Tools/WatchAnswers.cls` -- `ResolveStop(name, namespace, sessionRef, .match)`: the session's own `Kind` production rows from `Ownership.Checks` as entries, matched with the reader's matcher; one match: it; several: `ambiguous`; none: `Resolve` as today.
- `src/ocutalon/cls/OcuTalon/Tools/WatchTools.cls` -- `StopWatch` calls `ResolveStop` with the context's `OwnerRef`; class and method docs say stop reads the session's own watches through the ownership API.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- add `OcuTalon.Data.BackgroundCheck` to `CALLBACKHELPERS` and `READERCLASSES`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` -- oracle row `FailurePoller`: `pool` 1, `stub` 0, `settings` `[{"target": "Adapter", "name": "CallInterval", "value": "3"}]`; header comment.
- [Epic 16's file; one-time footprint extension by orchestrator ruling (decide)] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- in the Contracts XData only: `OcuTalon.Data.WatchMark` gains `"MarkAt": "%String(MAXLEN=23)"`, `"Seen": "%String(MAXLEN=)"`; `OcuTalon.Data.BackgroundCheck` gains `"CreatedAt": "%String(MAXLEN=20)"`. Nothing else.
- Tests (throwaway-only ones fail with the reason without OCUORDERS, as 5.1's do):
  - `Test/Watch/Mark.cls` (new, pure): `ErrorText.Sentence` on the measured text, a plain `ERROR #5001:` text, a text with no prefix, a long text; `Mark` start rule (no mark, mark later than `CreatedAt`, `CreatedAt` later than mark, no `CreatedAt`), `Seen` filtering, the cap, the overlap window, `FailedAt`.
  - `Test/Watch/Poller.cls` (new, throwaway, over the running production): matrix rows Session-tagged, Untagged, Scopes in one poll, Nothing new, Again / restart (`TempStopConfigItem("FailurePoller", 1, 1)` then `(…, 0, 1)`, which leave the definition unchanged), Late error (a fixture header saved in OCUORDERS with `Status` 3 and the run's `TraceRef`, later moved to 8 with `SetStatus`, which sets `TimeProcessed`), Watch after failures, Unreadable, Headerless log row (fixture `Ens_Util.Log` rows of `Type` 2 and 6 in OCUORDERS with no session and a `ConfigName` of the test's own). Waits poll every 0.5 s up to 30 s, a test bound and not NFR-7; "no further batch" waits 7 s (two polls). Keep the class under about 60 s on the developer machine.
  - `Test/Watch/PollerProbe.cls` (new, test-only, extends `FailurePoller`): overrides the private read seam to throw; a `Test.Watch.Poller` test calls its shadow instance's `OnProcessInput` and expects OK, one Type 3 warning naming the production, and the mark unchanged (matrix row Read or send error).
  - `Test/Watch/Reader.cls`: `Failures` outcomes (`read` with the measured fields, `unreadable` without a switch, `not_current` for the DW-38 row); Stopped production (stop Orders in the test; `Productions` and `Find("Orders")` list it, `Failures` answers `read`, and WatchOps' shadow admits a start; `OnAfterOneTest` starts Orders again, and the test asserts it runs).
  - `Test/Watch/Ops.cls`: `CreatedAt` equals `NextDueAt` on a new row.
  - `Test/Watch/Tools.cls`: `ResolveStop` rows with the double (own row the reader does not list, two own matches, no own match); one real-path test (no double): A watches Orders, grant revoked, stop_watch("Orders") → `stopped`, row gone.
  - `Test/Watch/Case.cls`: helpers `Fail(count, traceRef)` (switches to OCUORDERS, `Partner.Send`; a copy of the Demo test's private 3-line `Send`, which is Epic 4's), `Batches(since)`, poller stop/start, Orders stop/start, and cleanup of the OCUORDERS messages the run made (`RemoveMessages(refs, "OCUORDERS")`, plus untagged ones and fixture headers and log rows by id) and of the run's `instance` batches by header id.

**Acceptance Criteria:**
- Given a throwaway with demo mode on and session A watching Orders, when 3 failing orders tagged with A's `TraceRef` and 2 untagged ones arrive, then within 30 s (a test bound, not NFR-7) `IncidentManager` holds `FailureBatch` messages, each `Completed` (Status 9) at `IncidentManager`, A's with `SuperSession` = A's `TraceRef`, that cover exactly those 5 failures once, by scope, with the measured `ErrorText`; and no batch follows within the next two polls (Integration AC: consumer `IncidentManager`).
- Given that watch, when the poller is temp-stopped, 2 more failures arrive and it is started again, then exactly those 2 are batched once and none of the earlier ones again.
- Given the service role without Read on `%DB_OCUORDERS_DATA`, when failures arrive, then no batch is sent and A's `WatchMark` is unchanged; when the grant returns, those failures are batched once.
- Given Orders cleanly stopped, when the reader lists productions and a `StartWatch` for Orders reaches `WatchOps`, then Orders is listed and the watch is started (DW-222).
- Given A watching Orders and the reader no longer listing it, when stop_watch("Orders") runs through the real `CommandsIn` and `WatchOps`, then A's row is gone and the outcome is `stopped` (DW-222; Integration AC: consumer stop_watch of `Ownership.Checks`).
- Given `OcuTalon.Production`, when its definition is read, then `FailurePoller` has pool size 1, `CallInterval` 3 and no `STUB`, and `IncidentManager` still carries `STUB` and answers 5003 to anything but a `FailureBatch`.

### Review Findings

Code review 2026-10-26 (bmad-code-review, unattended; layers blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor, full tier): 35 rows, 31 entries after grouping (1 high, 7 medium, 21 low, 2 false). Every patch applied by the reviewer; no decision-needed, no Fix Pack. Paths under `src/ocutalon/cls/OcuTalon/`.

- [x] [Review][Patch] HIGH (Rule 6, Consistency Conventions: Redaction) -- a failure's `ErrorText` was copied unredacted from the watched production's log into OcuTalon's messages; it is now `Sentence(Redact.Text(raw))`, pinned by the new `TestErrorTextIsRedacted` [Watch/FailurePoller.cls:112, Test/Watch/Poller.cls:434]
- [x] [Review][Patch] MED (Rule 19, readiness) -- AC 1's "Completed (Status 9)" was asserted on the snapshot `WaitBatched` returned, before IncidentManager could have taken the second batch; now asserted after the two-poll settle [Test/Watch/Poller.cls:96]
- [x] [Review][Patch] MED (Rule 19, hermeticity) -- the probe's rows mode fed every watched production of the instance, so TestFlood/TestNothingNew/TestSendErrorWarns relied on no other watch row existing; it now answers `not_current` except for the production `Feed` names, and TestReadErrorWarns' warning filter names the namespace [Test/Watch/PollerProbe.cls:24, Test/Watch/Poller.cls:297]
- [x] [Review][Patch] MED (Rule 19, falsifiability) -- the batch's and the reader's `SessionId`, `SourceName`, `BodyClass`, `FailedAt`/`at` were checked only for being non-empty; now equal to the header's (`Case.Failed` returns them) [Test/Watch/Poller.cls:86, Test/Watch/Reader.cls:166, Test/Watch/Case.cls:454]
- [x] [Review][Patch] MED (Rule 19, unfalsifiable) -- "unreadable without a switch" rested on `$Namespace = here`, which `New $NAMESPACE` makes always true; replaced by a nonexistent namespace that must answer `unreadable` without throwing [Test/Watch/Reader.cls:242]
- [x] [Review][Patch] MED (Rule 19) -- the first error-text rule (the log row whose `MessageId` is the header) had no test; fixture added, an earlier at-target row must lose to it [Test/Watch/Reader.cls:204]
- [x] [Review][Patch] MED (Rule 19) -- a failure whose `SuperSession` is no session's `TraceRef` (a production that sets its own SuperSession) had no test of the `instance` fallback; new `TestUnknownSuperSession` [Test/Watch/Poller.cls:417]
- [x] [Review][Patch] LOW -- the at-target condition could be dropped with no test failing (target row written first); fixture order swapped [Test/Watch/Reader.cls:205]
- [x] [Review][Patch] LOW -- "earliest CreatedAt" untested (both flood watches had one time); the first watch row is now made later than the second and than the first failures [Test/Watch/Poller.cls:391]
- [x] [Review][Patch] LOW -- a poll warning after another production's send carried that batch's `$$$JobSessionId` into its trace; cleared before the warning (Ens's own idiom) [Watch/FailurePoller.cls:43]
- [x] [Review][Patch] LOW -- `Sentence` kept an inner wrapper of nested "Terminating BP" texts, a host's retry grace period words and a system error's varying " -- logged as" tail (splitting same-cause groups); all three dropped, four asserts added [Watch/ErrorText.cls:37, Test/Watch/Mark.cls:35]
- [x] [Review][Patch] LOW -- IncidentManager's doc told Story 5.3 to dedupe by header id, which an event-log failure (empty `HeaderId`) does not carry; it now names the failure key (`Mark.Key`) [Watch/IncidentManager.cls:4]
- [x] [Review][Patch] LOW -- "the last one started" overstated `GetActiveProductionName` (also the auto-start production when none started); doc corrected [Watch/Reader.cls:5, :162]
- [x] [Review][Patch] LOW -- TestNotOwnProduction's negatives would pass with no poller running; the session now also watches Orders and its batch is the control [Test/Watch/Poller.cls:245]
- [x] [Review][Patch] LOW -- three "no further failure is batched" asserts run with no settle (by design, for time) and claimed more than they check; relabelled "no other failure is in the batches by then" [Test/Watch/Poller.cls:177, :224, :281]
- [x] [Review][Patch] LOW (Rule 19) -- TestLateError asserted `late < failed id`, true by construction, and wrapped its expected value in a dead `$Select`; removed [Test/Watch/Poller.cls:176]
- [x] [Review][Patch] LOW -- CodeRules: `READERCLASSES` doc and its assertion message ("through Watch.Reader") were stale; doc names the ownership API and `BackgroundCheck`, `Data.Ownership` is listed [Test/Bridge/CodeRules.cls:65, :182]
- [x] [Review][Patch] LOW -- `Case.RestoreDouble` put the real service back; renamed `UseReal`; Poller header's repeated phrase removed [Test/Watch/Case.cls:327, Test/Watch/Tools.cls:433]
- [x] [Review][Patch] LOW (Rule 19, stale line) -- AC 1's ErrorText clause was never observed red at the poller level; mutation applied fresh and the line under Verification corrected
- [x] [Review][Closed] MED, by-design (DW-228) -- a `not_current` production keeps its mark (spec Design Notes, spine row "Watch failures"), so if another production ran in the namespace meanwhile, its failures since the mark are batched as the watched one's when it is current again; reopens only by amendment (advance a not_current mark to the poll time; unreadable keeps it)
- [x] [Review][Closed] LOW, wontfix-accepted (DW-229) -- a fault inside `Reader.Current` reaches the poller only through `Failures`' fault check, which no test drives (no cheap trigger without a new seam)
- [x] [Review][Closed] LOW, wontfix-accepted (DW-230) -- no test that one production's failing poll still lets the others be polled in the same run
- [x] [Review][Closed] LOW, wontfix-theoretical -- the `LOGWATCHES` warning path is untested; real only if the SQL over OcuTalon's own `BackgroundCheck` table fails
- [x] [Review][Closed] LOW, wontfix-theoretical -- `GenerateSuperSessionID` set on `FailurePoller` would tag instance batches; real only if an admin or a System Default Setting enables it for OcuTalon's item
- [x] [Review][Closed] LOW, wontfix-theoretical (QA's flag) -- `TimeProcessed >= from` compares IRIS's trailing-zero-stripped stamp (`Ens.DataType.UTC.Normalize`) with a three-digit `from`, so only a row at exactly `from` to the millisecond sorts below it: at `MarkAt` less 2 s such a row is already in `Seen`, and at a whole-second `CreatedAt` it is not after the watch; real only if a failure that commits more than the overlap late lands on exactly that millisecond
- [x] [Review][Closed] LOW, by-design -- the `stop_watch` description mentions "the ownership API" (the spec's Task asks the method doc to say so); a stopped production's listed state is Story 5.6's

Rejected (false): the acceptance auditor's "Nothing new is tested through the probe" (the matrix row is pinned by TestNothingNew and the live two-poll settle; informational) and "the diff carries bookkeeping files" (the lead's harvest, not story code).

## Spec Change Log

- 2026-10-25, spec gate (Epic 5 runner): the plan's intent gap (contended `Test/Data/Tables.cls`) was ruled by the orchestrator, option (a); the schema change was ruled veto U-83; the spine candidates were written as the Consistency Conventions row "Watch failures" (no AD text changed); status set to `ready-for-dev`. Rulings under Design Notes.

## Review Triage Log

### 2026-10-25 -- Review pass
- verdicts: 31 findings -- high 0, medium 2, low 22, false 6, maybe-false 1
- findings:
  - `[false]` `[reject]` Blind 1 / Edge 8: a header read before its log row is committed batches an empty ErrorText that is never refreshed -- Task 0 measured the log row `TimeLogged` about 10 ms BEFORE `TimeProcessed` (the BP logs, then sets Status 8), so the row exists when the header enters Status 8; the `IsError` fallback covers the rest
  - `[low]` `[reject]` Blind 2 / Edge 4: a failed send after another scope's send re-sends the earlier scopes at the next poll -- recorded residual risk in Design Notes (send then save; Story 5.3 dedupes by header id); spec-bound, a per-scope save would change the specified one-mark write
  - `[low]` `[patch]` Blind 3: `Test.Watch.Poller` leaves the Orders/OCUTALON `WatchMark` rows behind (the product keeps marks by design) -- `Poller.OnAfterOneTest` now clears both marks after the base clean-up
  - `[low]` `[reject]` Blind 4 / Edge 1: a watch row with an empty `CreatedAt` and no mark starts each poll at its own time -- the spec states that start ("the poll time when no row has one") and `WatchOps` always writes `CreatedAt` now; only pre-5.2 rows of an unreleased build lack it; spec-bound
  - `[low]` `[patch]` Blind 5: `Watched()` grouping (one read per production however many sessions watch it) had no test -- TestFlood now has two sessions watching the probe-only production and asserts one read and one batch per poll; mutation recorded
  - `[low]` `[reject]` Blind 6: `CreatedAt` is whole seconds, so a failure up to 999 ms before the watch in the same second counts as after it -- `CreatedAt` UTC to the second is the specified shape (same as `NextDueAt`); the test waits 1.2 s for it
  - `[low]` `[reject]` Blind 7: `Reader.Current` does a lot inside the one switching method and a text lookup per failed header -- the spec requires the read inside that one method (AD-3), at most 500 headers per poll; the inner `Quit` only ends the innermost loop and the outer loops then quit at once
  - `[low]` `[reject]` Blind 8: `TraceRefIndexOpen` once per failure -- at most 500 indexed opens per 3 s poll; a per-poll cache adds a branch for no reachable harm
  - `[low]` `[reject]` Blind 9 / Edge 6 / Edge 7: `Mark.Normal` accepts an out-of-range date and a non-stamp `at` -- every value comes from IRIS's own stored times or `NowUtc()`, never user text; no reachable input
  - `[low]` `[reject]` Blind 10: `Productions` lists a `GetActiveProductionName()` whose definition class was deleted -- the spec says the last started production; a stale LastProduction of a deleted class is not a user-reachable state
  - `[false]` `[reject]` Blind 11: non-batch request to `IncidentManager` untested; `Msg.Failure`/`FailureBatch` not in the Tables contracts -- `TestStubsAnswer` sends an `Ens.StringRequest` to every STUB item and expects 5003 (mutation "accepts every request" is red there); `Test.Data.Tables` lists only the classes the spec names and passed on lane-b
  - `[low]` `[reject]` Edge 2 / Edge 3: unreadable and not_current outcomes log nothing -- the spec's matrix says nothing is read and the mark is unchanged, and a warning every 3 s for a revoked grant would flood the log; the class description claimed otherwise, so its wording is corrected (see the next row)
  - `[low]` `[patch]` Edge 3 (claim): the `FailurePoller` description said a warning per production "that could not be read" -- reworded to one warning per poll whose read or send threw; unreadable logs nothing
  - `[low]` `[reject]` Edge 5: a production that fails every poll logs a warning every 3 s -- the specified Read or send error row (one Type 3 warning per failing poll, same pattern as StatusMonitor); throttling would add state
  - `[low]` `[reject]` Edge 9: a `TimeProcessed` set more than 2 s before its Status 8 commit falls below the window -- the 2-second overlap is the decided value (IRIS assigns the time just before the write commits); no measurement shows more
  - `[low]` `[reject]` Edge 10: `Sentence` of a text that begins with a line break or `  > ` -- not a shape the BP wrapper produces; the measured and plain forms are tested
  - `[low]` `[reject]` Edge 11: rows tie-ordered headers before log rows at one time rather than (time, id) -- the Reader's own description states the tie rule; capped rows beyond a tie are re-read next poll (not in Seen), so none is lost
  - `[false]` `[reject]` Edge 12: batches stay in IncidentManager when a test never calls `Since` -- every Poller test that waits for a batch calls `Since()` first, which fixes the floor `DropBatches` uses
  - `[medium]` `[patch]` Vgap 1: the reader limit `MAXFAILURES` + Seen count was never asserted -- TestFlood asserts the limits 500 then 503 through the probe; mutation (limit = MAXFAILURES only) red
  - `[low]` `[patch]` Vgap 2: the error-text fallbacks (session's log row at the target, header ErrorStatus, empty) and the IsError-only negative had no test -- `Test.Watch.Reader.TestFailureDefinition` added with fixture headers and log rows; three mutations red
  - `[medium]` `[patch]` Vgap 3: TestNotOwnProduction could not fail from the defect it names (no failed header in OCUTALON) -- a Status 8 header is made in OCUTALON after the watch's CreatedAt; mutation (drop the not_current check) red at the poller level
  - `[low]` `[patch]` Vgap 4 (Rule 19): AC 6 had no mutation line -- three recorded (pool 0, CallInterval removed, IncidentManager accepts every request), each red in `Test.Install.Production`
  - `[low]` `[reject]` Vgap: matrix rows Headerless log row and Read error have no mutation line (not ACs; informational) -- both are asserted by exact-value tests whose subjects are constructed
  - `[low]` `[reject]` Vgap: `limit` 0 assertion cannot detect removing the `limit > 0` guard -- the guard is a short-circuit, not a behavior; the control reads fail first
  - `[low]` `[reject]` Vgap other: inner `Quit` in the merge loop is redundant -- same as Blind 7; output unaffected
  - `[false]` `[reject]` Intent: 50 failing orders (UJ-1 volume) are not run through the live poller -- AC 1 is specified with 3 + 2 orders; the cap is pinned by TestFlood; the demo-path test of Story 5.7 owns the 50
  - `[low]` `[reject]` Intent: `stop_watch` against a cleanly stopped production and the live poller against one are not tested -- the matrix rows pin the reader (list, find, failures read, start admitted) and the stop from own rows; reading uses the same `Current`
  - `[false]` `[reject]` Intent: `Ownership` is not in `READERCLASSES` -- it is in `CALLBACKHELPERS` already (spec Code Map); `BackgroundCheck` was added to both
  - `[low]` `[patch]` Intent: the negative of the failure definition (a response header with only IsError) had no test -- covered by TestFailureDefinition (same patch as Vgap 2)
  - `[false]` `[reject]` Intent: no scan proves only `Current` switches namespace -- 5.1's existing rule/test for the one switching method stands, and the diff adds no second `New $NAMESPACE` in `Reader`; `Failures` calls `Current`
  - `[maybe-false]` `[reject]` Intent: a real session-less log row may not match `SessionId IS NULL` -- IRIS SQL maps the empty string to NULL and Ens writes the row through `Ens.Util.Log` `%New`/`%Save` as the fixture does; a maybe-false at low severity

## Design Notes

**Governing ADs:**
- AD-1: tools never write tables; `CreatedAt` is written by `WatchOps`.
- AD-3: the reader is the only namespace switcher, one method; readability before reading.
- AD-4: scope by `TraceRef`; `instance`.
- AD-5: marks on disk; append-only storage; the production class holds structure only (`CallInterval` is structure here, as `StatusMonitor`'s is).
- AD-6 and AD-10: callback safety of the stop resolver; classifications unchanged.
- AD-15: the poller, `WatchMark`, one batch per scope per poll, `IncidentManager` the only incident writer.
- AD-16: fix copies are registered by Story 7.3.
- AD-18: `BackgroundCheck` written by `WatchOps`.
- AD-22: throwaway tests.
- AD-26: each batch its own trace session tagged with the session's `TraceRef`.
- AD-29 and AD-33: Lane A files; one writer of `WatchMark` (the poller).

**Integration ACs, Consumes, Consumed-by:**
- New services: `FailurePoller` (and its `FailureBatch` contract), `Reader.Failures`, `Watch.ErrorText`, `Watch.Mark`. In-story consumers: `IncidentManager` (AC 1, the completed batch headers in its trace) and stop_watch reading `Ownership.Checks` (AC 5).
- Consumes: `Watch.Reader`, `WatchOps`, the watch tools and `BackgroundCheck` rows (5.1); `Data.Session.TraceRefIndexOpen` and `Data.Ownership.Checks` (Epics 0 and 2); the Orders demo and `Partner.Send` (0.10); `Test.Data.Fixture.RemoveMessages`.
- Consumed-by:
  - Story 5.3: `IncidentManager` groups each batch's failures (item plus `ErrorText` pattern, per `OwnerRef`), and should ignore a header id it already holds (the only duplicate path is below);
  - Story 5.4: `EvidencePack` reads failures through `Reader.Failures` and `ErrorText`;
  - Story 5.6: `Checks` reads new errors through the reader, and a stopped production now listed reports its state;
  - Story 6.1: the fallback "Failures:" line takes `ErrorText.Sentence`;
  - Story 7.4: a copy's failure, recognised by its registered header id, is attributed to the fix (its own AC); the batch carries `HeaderId` and `Namespace` for that match.

**Extend, don't copy:**
- The failure read extends `Watch.Reader` inside its one switching method (no second switcher).
- The stop resolver reuses the reader's matcher (extracted from `Find`) and `WatchAnswers.Decide`.
- `FailurePoller` follows `Core.StatusMonitor`'s service pattern; nothing of it is shared code (Lane B, contended).
- `Test.Watch.Case.Fail` copies `Test.Demo.Production.Send` (three lines), because that method is private in Epic 4's contended file.

**Decided in-stage:**
- Failure definition (Always), measured: the BP logs before it sets `Status` 8, and an operation logs a repeated error once, so headers count failures and log rows only give their text, except rows with no session.
- The mark is time-based (`TimeProcessed` / `TimeLogged`, both indexed) with a 2-second overlap and a `Seen` set, not a header id: a retried operation's header can fail after a later header (an id mark would skip it), and IRIS assigns a time just before its write commits.
- The start of a production's reading is `max(MarkAt, earliest CreatedAt)`: exact for the first watch (a click of Break the feed within 3 s of the watch is not lost, which a "first poll" start would risk on the demo-path test) and for a re-watch after a gap (failures while nobody watched are not batched). The poller never deletes `WatchMark` rows.
- One batch per (production, scope) per poll; `PolledAt` identifies the poll. At most 500 failures per production per poll.
- Send first, then save the mark: `Ens.Queue.EnQueue` commits any open transaction, so the two cannot be atomic. A kill between them, or a failed send after another scope's send, re-sends that poll's failures once; never a skip. Recorded as the residual risk; 5.3 dedupes by header id.
- A production the reader does not read (unreadable, not the own production) keeps its mark, so nothing is skipped when access returns.
- Fix-copy attribution: there is no copy registry until Story 7.3 registers each new header id on the `FixRun` row, and Story 7.4's AC attributes such a failure to the fix. 5.2 batches every failure by scope and carries its `HeaderId`; it adds no lookup over a registry that does not exist.
- `IncidentManager` keeps `STUB`: it is still unbuilt for grouping and commands, so the stub test and the contended `CommandsInProduction` rows stay true.
- DW-222 stop: resolution reads the session's own watches through the ownership API (the sanctioned read of session-owned records), never the table directly; `WatchOps.OnStop` needs no change.

**Decided in-stage (implement, 2026-10-25):**
- Review patches (this stage): `Test.Watch.Reader.TestFailureDefinition` (fixture headers and log rows for the text fallbacks and the IsError-only negative; `Test.Watch.Case.FixtureHeader` and `FixtureLog`); `Test.Watch.Poller` TestNotOwnProduction makes a failed header in OCUTALON, TestFlood has two watching sessions and asserts the reader's limits, `OnAfterOneTest` clears the two marks; the `FailurePoller` description says a warning only when a read or send threw.
- The Flood row and the failed-send half of the Read or send error row are pinned in `Test.Watch.Poller` (TestFlood, TestSendErrorWarns) through `Test.Watch.PollerProbe`'s rows mode (the probe's read answers a test feed, its send is kept in-process or fails), on a production no running job reads (`Zz.FloodProduction`), so the class stays about 58 s.
- Task 0 held on build 154; no measurement contradicted it.
- The overlap is applied in `Mark.Start` (the later of `MarkAt` less 2 s and the earliest `CreatedAt`), so `Seen` keeps exactly the failures read whose time is not before `MarkAt` less 2 s; `Reader.Failures` is given `MAXFAILURES` plus the number of `Seen` keys as its limit, so the 500 new ones are never crowded out by the Seen ones that the overlap reads again.
- `Reader.Current` gained optional parameters (production, from, limit, Output rows, outcome, fault) instead of a second switching method; `fault` carries a caught error out so that `Failures` throws it (a poll warning) while `Productions` still leaves an unenterable namespace out. `Failures` answers `not_current` for an empty namespace or production, with no switch.
- A warning logged by a shadow instance of `Test.Watch.PollerProbe` has the probe as its `SourceClass`, so `Test.Watch.Poller` filters on the probe class.
- `Test.Watch.Case.Watch` now writes `CreatedAt` (as WatchOps does), and `Case.Rows` returns it as `createdAt`; `Case.WaitMark` waits for the mark row because the poller saves it just after its sends.
- The serial `Watch.Msg.Failure` carries the compiler's `StreamLocation` `^OcuTalon.Watch.Msg.FailureS`; a serial object has no extent and the global is never written, and `docker/tests/test-storage.sh` checks only classes with `DEFAULTGLOBAL`.
- `Test.Watch.Poller` keeps 5 "no further batch" waits (session-tagged, restart, watch-after-failures, unreadable, not-own-production) and drops them from the late-error, headerless and the end of the unreadable test, so the class takes about 56 s fresh.

**DW entries:** DW-35 is addressed (failure definition, `Reader.Failures` error text, `ErrorText.Sentence`, matrix row Session-tagged, `Test.Watch.Mark`). DW-222 is addressed (matrix rows Stopped production and Stop from own rows, AC 4 and 5). **Declined:** none.

**Footprint extensions** (not contended): `Test/Install/Production.cls` (the `FailurePoller` row), `Test/Bridge/CodeRules.cls` (one class in two lists). By orchestrator ruling also Epic 16's `Test/Data/Tables.cls` (two Contracts entries only).

**Orchestrator ruling (2026-10-25, on the plan's intent gap):** `Test/Data/Tables.cls` (Epic 16) is allowed as a one-time footprint extension: only the two Lane A entries of its Contracts XData change (`OcuTalon.Data.WatchMark` + `MarkAt`, `Seen`; `OcuTalon.Data.BackgroundCheck` + `CreatedAt`), nothing else in the file (option (a), decide; the registry is keyed by class and both classes are Lane A's under AD-33). A conflict at an integrate-forward is a plain union, both entries kept. DW-222's decide ruling stands.

**Spec-gate rulings (Epic 5 runner, 2026-10-25):**
- The three new stored properties (`WatchMark.MarkAt`, `WatchMark.Seen`, `BackgroundCheck.CreatedAt`): veto, inbox item U-83.
- Spine (Rule 20, light path): the candidates below were written as the Consistency Conventions row "Watch failures" (failure definition, own-production rule, time-based `WatchMark`, batch per production and scope per poll, send then save); AD-3 and AD-15 text is unchanged.
- Shard time: if the fresh `lane-a` shard passes 540 s on the developer machine, report the measured time in the spec (do not chain anything after it in the same call); the lead decides the split.

**Spine candidates for the lead (Rule 20):** AD-15's Rule could state the failure definition, the time-based `WatchMark` (`MarkAt`, `Seen`, 2 s overlap) and the batch per production and scope per poll, which 5.3, 5.4, 6.1 and 7.4 build on; AD-3's reader bullet could say "the running production, else the last started (`GetActiveProductionName`)".

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`. One command per call, each with `timeout: 600000`, never two IRIS test runs in one message.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e5s2iw ci/warm.sh up` -- once per stage, again after a `Production.cls` or `ci/mock` change (`down` then `up`). Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s2iw ci/iris.sh class <Class>`, one call per class, for `OcuTalon.Test.Watch.Mark`, `.Watch.Reader`, `.Watch.Ops`, `.Watch.Tools`, `.Watch.Grant`, `.Watch.Turns`, `OcuTalon.Test.Install.Production` and `OcuTalon.Test.Bridge.CodeRules` -- expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s2i ci/iris.sh class OcuTalon.Test.Watch.Poller` -- fresh, because a warm stack's running poller job keeps its old code. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e5s2i ci/iris.sh shard lane-a` -- alone in its call; expected: passed. It took 422-475 s before this story; if it passes 540 s, report the time and keep the new waits as stated.
- (once) `<lane> OCUTALON_RUN_TAG=e5s2i ci/iris.sh shard lane-b` -- holds `Test.Data.Tables` (the contract entries). Expected: passed.
- (once) `bash ci/checks.sh` -- expected: all pass (storage blocks, class rules).
- (once) `<lane> OCUTALON_RUN_TAG=e5s2iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s2i ci/iris.sh teardown`.

**Shared surfaces:**
- The production item table: `FailurePoller` pool, setting and `STUB` (`Test.Install.Production`), and one more running job in OCUTALON.
- The Data contracts of `WatchMark` and `BackgroundCheck` (`Test.Data.Tables`, Epic 16's file; two entries by ruling).
- `CALLBACKHELPERS` and `READERCLASSES`.
- The reader's list (stopped productions now listed): `Test.Watch.Reader`, `Test.Watch.Tools` (`unknown_production` lists).
- `BackgroundCheck` rows (`CreatedAt`) and the Orders `WatchMark` row (poller-owned; no test asserts it across classes).
- OCUORDERS' message store and event log (test failures are tagged and removed) and OCUTALON's event log (the poller logs only warnings, and only on errors).
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations** (Rule 19; each applied, run, observed red, reverted byte-identical; fresh = `Test.Watch.Poller` on a fresh lane-A stack, warm = the class on the warm stack, green again on the same stack after the revert):
- mutation: every failure scoped `instance` (`Set scope = ..#INSTANCE` for a found session) -> red (fresh): `Test.Watch.Poller` TestSessionTaggedAndUntagged (A's and the instance scope), TestScopesInOnePoll, TestAgainAfterRestart, TestLateError, TestUnreadable.
- mutation: one batch per failure (a unique key per failure in `Poll`) -> red (fresh): TestScopesInOnePoll ("three batches: one per scope", "one poll's batches") and TestAgainAfterRestart ("the two arrive in one batch").
- mutation: skip the `Seen` filter (`Mark.Fresh(rows, "")` in `Poll`) -> red (fresh): duplicates in TestSessionTaggedAndUntagged ("no batch follows within two polls"), TestAgainAfterRestart, TestLateError, TestUnreadable, TestWatchAfterFailures.
- mutation: mark by header id instead of time (`Mark.Fresh` drops a header below the highest `Seen` header id) -> red (fresh): TestLateError only ("it is batched once, later").
- mutation: keep the mark in a property of the poller instead of `WatchMark` -> red (fresh): TestAgainAfterRestart ("the first not again") and TestUnreadable ("the first failure made the mark").
- mutation: drop the readability check in `Reader.Failures` -> red (warm): `Test.Watch.Reader` TestFailuresUnreadable; red (fresh): `Test.Watch.Poller` TestUnreadable.
- mutation: start from `MarkAt` only (`Mark.Start` ignores `CreatedAt`, and starts at 2000-01-01 with no mark) -> red (fresh): TestWatchAfterFailures.
- mutation: `ErrorText.Sentence` returns its input -> red (warm): `Test.Watch.Mark` TestSentence (seven asserts); red (fresh, code review 2026-10-26): `Test.Watch.Poller` TestSessionTaggedAndUntagged ("with the error's own sentence", five asserts) and TestErrorTextIsRedacted (AC 1's ErrorText clause); reverted byte-identical.
- mutation: drop the `GetActiveProductionName` fallback in `Reader.Current` -> red (warm): `Test.Watch.Reader` TestStoppedProduction (listed, Find, Admits, failures read, start admitted).
- mutation: `StopWatch` calls `Resolve` instead of `ResolveStop` -> red (warm): `Test.Watch.Tools` TestResolveStop and TestStopWatchOfAnUnlistedProduction.
- mutation: `IncidentManager` answers 5003 to a batch -> red (fresh, re-observed in code review 2026-10-26 after the assertion moved behind the two-poll settle): TestSessionTaggedAndUntagged ("batch N is Completed at IncidentManager", both batches); reverted byte-identical.
- mutation: `Mark.MAXFAILURES` 500 -> 5000 (the Flood row: the cap and the limit given to the reader) -> red (fresh): `Test.Watch.Poller` TestFlood (first batch, second poll, rest, third poll); reverted byte-identical, class green again.
- mutation: `Poll` ignores the status of the send (`Do ..SendRequestAsync(...)` for `$$$ThrowOnError(...)`) -> red (fresh): `Test.Watch.Poller` TestSendErrorWarns (the warning, the missing mark, the batch after the send is back); reverted byte-identical, class green again.
- mutation: the not_current check dropped in `Reader.Current` (`If (name = "") {`) -> red (fresh, re-observed in code review 2026-10-26 with the new control): `Test.Watch.Poller` TestNotOwnProduction ("control: the reader answers not_current", "nothing is read from OCUTALON for the Orders production", "and it makes no mark"; the control "the poller runs" green); reverted byte-identical, class green again.
- mutation: `Poll` asks the reader for `MAXFAILURES` only (no Seen allowance) -> red (fresh): `Test.Watch.Poller` TestFlood ("the reader is asked for 500, then for 500 and the 3 failures ..."); reverted byte-identical.
- mutation: `Watched()` makes every watch row its own entry (`_$Increment(zzn)` in the key) -> red (fresh): `Test.Watch.Poller` TestFlood ("the first poll sends one batch", "read once"); reverted byte-identical.
- mutation: the session's-log-row-at-the-target branch of `Reader.Current` off (`If 'exact && 0`) -> red (warm): `Test.Watch.Reader` TestFailureDefinition (the target row's text); the header-ErrorStatus branch off (`&& 0`) -> red (warm): TestFailureDefinition (the header's own status); the query `(Status = 8 OR IsError = 1)` -> red (warm): TestFailureDefinition ("a response header with only IsError is not a failure"); each reverted byte-identical, the class green again on the same stack.
- mutation (AC 6): `FailurePoller` `PoolSize="0"` in `Production.cls` -> red (warm): `Test.Install.Production` TestDefinition ("item 11 is FailurePoller as the ownership table says"); the `CallInterval` setting removed -> red (warm): the same assertion; `IncidentManager.OnRequest` quitting OK for every request -> red (warm): TestStubsAnswer ("IncidentManager answers code 5003"); each reverted byte-identical, the class green again on the same stack.
- mutation: `WatchOps` writes no `CreatedAt` -> red (warm): `Test.Watch.Ops` TestStart ("CreatedAt is the same time as NextDueAt").

**QA pass (2026-10-25; warm stack `e5s2qw`, fresh stack `e5s2q`, both torn down).** Tests added or changed (QA):
- `src/ocutalon/cls/OcuTalon/Test/Watch/Reader.cls` (QA): `TestFailuresHeaderless` (rows with no session: type 2 gives kind error, type 6 kind alert, a type 3 row and a type 2 row with a session are not failures); and a flake fix in `TestFailures` (IRIS drops the trailing zeros of a stored time, so `at` has one to three fractional digits, and the old pattern of exactly three failed about one run in four).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Poller.cls` (QA): `TestNothingNew` (matrix row Nothing new, through the probe's rows mode: no failure, and only a seen failure, send nothing and make or change no mark; a new failure is the control).

Pinning mutations added by QA (each applied, run, observed red, reverted byte-identical against my own backup, `git diff` equal to the pre-mutation diff, the class green again on the same stack; fresh `Test.Watch.Poller` green at the end, 57 s class time):
- mutation: the headerless query `Type IN (2, 6)` -> `Type IN (2)` (Reader.Current) -> red (warm): `Test.Watch.Reader` TestFailuresHeaderless (matrix row Headerless log row).
- mutation: the headerless query without `AND SessionId IS NULL` -> red (warm): `Test.Watch.Reader` TestFailuresHeaderless (a log row with a session is no failure of its own; TestFailuresUnreadable and TestStoppedProduction also red).
- mutation: `Poll` saves the mark when nothing is new (the early `Quit` replaced by a save of `MarkAt`) -> red (warm): `Test.Watch.Poller` TestNothingNew ("and no mark is made", "and the mark is as it was") and TestFlood ("and leaves the mark") (matrix row Nothing new).
- mutation: `Poll` does not copy `HeaderId` into the batch item -> red (warm): `Test.Watch.Poller` TestSessionTaggedAndUntagged, TestUnreadable, TestWatchAfterFailures (matrix row Fix copy: each failure is batched with its header id).
- mutation: `FailurePoller` `INSTANCE` "instance" -> "inst" -> red (warm): `Test.Watch.Poller` TestSessionTaggedAndUntagged, TestScopesInOnePoll, TestAgainAfterRestart, TestHeaderlessLog, TestFlood (matrix row Untagged).
- mutation: the poll's catch logs `$$$LOGERROR` instead of `$$$LOGWARNING` -> red (warm): `Test.Watch.Poller` TestReadErrorWarns and TestSendErrorWarns (matrix row Read or send error: a Type 3 warning only).
- mutation: `Mark.OVERLAP` 2 -> 0 -> red (warm): `Test.Watch.Mark` TestStart (three asserts) and TestNext (three asserts).
- mutation: `OcuTalon.Data.BackgroundCheck` removed from `CALLBACKHELPERS` (kept in `READERCLASSES`) -> red (warm): `Test.Bridge.CodeRules` TestCallbackRule ("the watch tools run OcuTalon.Data.BackgroundCheck inside the callback ... so it is in CALLBACKHELPERS and scanned").

Runs: warm `Test.Bridge.CodeRules`, `Test.Watch.Mark`, `.Reader`, `.Tools`, `.Ops`, `Test.Install.Production` passed; fresh `Test.Watch.Poller` passed (57 s); `bash ci/checks.sh` passed.

**Code review pass (2026-10-26; warm stack `e5s2rw`, fresh stack `e5s2r`, all torn down).** Pinning mutations added by the review (each applied, run, observed red, reverted byte-identical from the reviewer's own backup, `git diff --stat` and `git status --short` equal to the patched state, the class green again on the same stack; fresh `Test.Watch.Poller` green on the patched tree, 62.6 s class time with READY 73 s under load):
- mutation: `Poll` stores `Sentence(failure.errorText)` without the redactor -> red (warm): `Test.Watch.Poller` TestErrorTextIsRedacted ("with the URL's password and the Bearer token redacted").
- mutation: `Poll` scopes with `Set scope = session.Ref` (no `$IsObject` guard) -> red (warm): `Test.Watch.Poller` TestUnknownSuperSession ("the failure is sent", "under instance with an empty SuperSession").
- mutation: `Watched()` keeps the latest `CreatedAt` (`created ] entry.created`) -> red (warm): `Test.Watch.Poller` TestFlood ("of the first 500 failures ... from the earliest watch on", and the polls after it).
- mutation: `Poll` sets `item.FailedAt = polledAt` -> red (fresh): `Test.Watch.Poller` TestSessionTaggedAndUntagged ("it carries its header's session, sender, body class and time to the second", five asserts).
- mutation: the reader row's `source` and `bodyClass` swapped in `Reader.Current` -> red (warm): `Test.Watch.Reader` TestFailures ("with its header's session, sender, body class and time", three asserts).
- mutation: the log-row-that-names-the-message branch off (`If (logs.%GetData(2) = id) && 0`) -> red (warm): `Test.Watch.Reader` TestFailureDefinition ("the session's row that names the message gives the text, before an earlier row at the target").
- mutation: the at-target condition dropped (`If (byItem = "") {`) -> red (warm): `Test.Watch.Reader` TestFailureDefinition ("... the session's row at its target gives the text, not an earlier row of another item").
- mutation: the readability check moved after the read in `Reader.Failures` -> red (warm): `Test.Watch.Reader` TestFailuresUnreadable (ZZNOSUCHNAMESPACE: `<NAMESPACE>` thrown on entering; "and no row is given").
- re-observed after the review's changes to their tests (warm, each red as recorded above, then green): the at-target branch off (`If 'exact && 0`) -> TestFailureDefinition; `Watched()` one entry per row (`_$Increment(zzn)`) -> TestFlood ("read once" and the polls); `Mark.MAXFAILURES` 5000 -> TestFlood; `Poll` limit `MAXFAILURES` only -> TestFlood ("500|503").
- Runs: warm `Test.Watch.Mark`, `.Reader`, `.Tools`, `.Ops`, `.Grant`, `.Turns`, `Test.Bridge.CodeRules` passed, and warm `Test.Watch.Poller` passed after each revert; fresh `Test.Watch.Poller` passed on the patched tree, and its four fresh mutation runs failed only where recorded (class time 62.3 to 64.1 s in all five, READY 63 to 93 s: the lane-A machine was loaded; TestNotOwnProduction's new control adds up to one poll, about 3 s, so the `lane-a` shard's 539 s may reach about 545 s; DW-227 holds the split); `bash ci/checks.sh` passed. No class of `lane-b` was touched. No class of `lane-b` was touched, so it was not run; the full `shard lane-a` was left to the lead (the Poller class takes the same time as before: `TestNothingNew` makes no wait).

## Auto Run Result

Status: done
Blocking condition: none

Implement and review pass, 2026-10-25.

**Summary.** `FailurePoller` is an `Ens.InboundAdapter` service (pool 1, `CallInterval` 3) that reads each watched production's new failures through `Reader.Failures` (inside the reader's one switching method), scopes them by `TraceRef` (else `instance`), sends `IncidentManager` one `FailureBatch` per production and scope per poll, then saves the time-based `WatchMark` (`MarkAt`, `Seen`, 2 s overlap, 500 cap). `IncidentManager` completes a batch and still answers 5003 to anything else (`STUB` stays). `Reader` lists a cleanly stopped production (`GetActiveProductionName`) and `stop_watch` resolves from the session's own watches first (DW-222). DW-35 (`ErrorText.Sentence`) addressed.

**Files changed** (all under `src/ocutalon/cls/OcuTalon/`):
- `Data/WatchMark.cls`, `Data/BackgroundCheck.cls`: `MarkAt`, `Seen`; `CreatedAt` (storage appended).
- `Watch/FailurePoller.cls`, `Watch/IncidentManager.cls`, `Watch/Reader.cls` (`Failures`, `Matches`, `Current` fallback), `Watch/Ops.cls` (`CreatedAt`), `Watch/ErrorText.cls`, `Watch/Mark.cls`, `Watch/Msg/Failure.cls`, `Watch/Msg/FailureBatch.cls`.
- `Tools/WatchAnswers.cls` (`ResolveStop`), `Tools/WatchTools.cls` (`StopWatch`).
- `Production.cls` (Lane A region: pool 1, `CallInterval` 3), `Test/Install/Production.cls` (oracle row), `Test/Bridge/CodeRules.cls` (`BackgroundCheck` in two lists), `Test/Data/Tables.cls` (the two ruled Contracts entries only).
- Tests: new `Test/Watch/Mark.cls`, `Poller.cls`, `PollerProbe.cls`; extended `Reader.cls`, `Ops.cls`, `Tools.cls`, `Case.cls`.

**Review.** Four layers (blind, edge-case, verification-gap, intent-alignment); 31 findings triaged (Review Triage Log): 0 high, 2 medium, 22 low, 6 false, 1 maybe-false. Patches applied (7 entries, 2 medium, 5 low): the reader limit assertion (medium), the poller-level not-own-production assertion with a failed OCUTALON header (medium), the error-text fallbacks and IsError-only negative (`TestFailureDefinition`), the two-sessions-one-read assertion, the mark clean-up, the corrected `FailurePoller` description, AC 6's mutation lines. Deferred: none. Rejected: every other finding with its reason in the log (spec-bound residuals: re-send after a failed send, empty-`CreatedAt` start, second-resolution `CreatedAt`; the rest unreachable or already covered).

**Follow-up review recommended:** false (no high patched; two medium patched, both test-strengthening only, no product code changed after the first review beyond a doc comment).

**Verification.** Warm stack (`e5s2iw`): `Test.Watch.Mark`, `.Reader`, `.Ops`, `.Tools`, `.Grant`, `.Turns`, `Test.Install.Production`, `Test.Bridge.CodeRules` passed (the Reader and Production classes again after the review patches). Fresh stack (`e5s2i`): `Test.Watch.Poller` passed (58 s class time) before and after the patches; `shard lane-a` passed, 54 classes, 539 s (ready in 93 s; just under the 540 s line); `shard lane-b` passed, 42 classes, 108 s (holds `Test.Data.Tables`); `bash ci/checks.sh` exit 0. Every Rule 19 mutation (Verification) was applied, observed red and reverted byte-identical (`cmp` against own backups), the class green again. Warm and fresh stacks torn down (`ci/warm.sh status`: none; no `e5s2` container left).

**Residual risks.** A crash between the send and the mark save, or a failed send after another scope's send, re-sends that poll's failures; Story 5.3 must dedupe by header id. A watch row with no `CreatedAt` (none is written by `WatchOps` any more) starts each poll at its own time. The serial `Watch.Msg.Failure` carries the compiler's `StreamLocation` `^OcuTalon.Watch.Msg.FailureS`, which is never written; `docker/tests/test-storage.sh` checks only classes with `DEFAULTGLOBAL`. The lane-a shard took 539 s with 54 classes: any further class pushes it past 540 s (the lead decides the split).
