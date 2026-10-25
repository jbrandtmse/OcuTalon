---
title: 'New failures are picked up within seconds'
type: 'feature'
created: '2026-10-25'
status: 'blocked'
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
- No change to `OcuTalon.Msg.*` contracts, `Core/*`, `Data/Session.cls`, `Data/Ownership.cls`, or any contended path except the one named in Design Notes under the pending ruling.
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
- `src/ocutalon/cls/OcuTalon/Data/WatchMark.cls` -- add `MarkAt` (`%String(MAXLEN = 23)`: the newest failure time read, as IRIS stores it, UTC `YYYY-MM-DD HH:MM:SS.sss`) and `Seen` (`%String(MAXLEN = "")`: the failures already batched whose time is within the overlap before `MarkAt`, `h<header id>` / `l<log id>`, comma-separated). Storage appended by the compiler, committed (AD-5). [Contract change pending the ruling.]
- `src/ocutalon/cls/OcuTalon/Data/BackgroundCheck.cls` -- add `CreatedAt` (`%String(MAXLEN = 20)`, UTC to the second). [Contract change pending the ruling.]
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
- [CONTENDED, Epic 16; only under the ruling asked for in Auto Run Result] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- in the Contracts XData only: `OcuTalon.Data.WatchMark` gains `"MarkAt": "%String(MAXLEN=23)"`, `"Seen": "%String(MAXLEN=)"`; `OcuTalon.Data.BackgroundCheck` gains `"CreatedAt": "%String(MAXLEN=20)"`. Nothing else.
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

## Spec Change Log

## Review Triage Log

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

**DW entries:** DW-35 is addressed (failure definition, `Reader.Failures` error text, `ErrorText.Sentence`, matrix row Session-tagged, `Test.Watch.Mark`). DW-222 is addressed (matrix rows Stopped production and Stop from own rows, AC 4 and 5). **Declined:** none.

**Footprint extensions** (not contended): `Test/Install/Production.cls` (the `FailurePoller` row), `Test/Bridge/CodeRules.cls` (one class in two lists).

**Contended path (pending ruling):** `Test/Data/Tables.cls` (Epic 16). See Auto Run Result.

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
- The Data contracts of `WatchMark` and `BackgroundCheck` (`Test.Data.Tables`, contended).
- `CALLBACKHELPERS` and `READERCLASSES`.
- The reader's list (stopped productions now listed): `Test.Watch.Reader`, `Test.Watch.Tools` (`unknown_production` lists).
- `BackgroundCheck` rows (`CreatedAt`) and the Orders `WatchMark` row (poller-owned; no test asserts it across classes).
- OCUORDERS' message store and event log (test failures are tagged and removed) and OCUTALON's event log (the poller logs only warnings, and only on errors).
- Every test added or changed passes on a fresh environment, in either order.

**Planned pinning mutations** (Rule 19; the implement stage records the observed red):
- Every failure scoped `instance` → `Test.Watch.Poller` session-tagged test.
- One batch per failure → the scopes-in-one-poll test (two batches with one `PolledAt` and `OwnerRef`).
- Skip the `Seen` filter → duplicate header ids across batches.
- Mark by header id instead of time → the late-error test.
- Keep the mark in a property instead of `WatchMark` → the restart test.
- Drop the readability check in `Reader.Failures` → the unreadable test.
- Start from `MarkAt` only (ignore `CreatedAt`) → the watch-after-failures test.
- `ErrorText.Sentence` returns its input → `Test.Watch.Mark` and the poller's `ErrorText` assertion.
- Drop the `GetActiveProductionName` fallback → `Test.Watch.Reader` stopped-production test.
- `StopWatch` calls `Resolve` instead of `ResolveStop` → the `Test.Watch.Tools` own-row and real-path tests.
- `IncidentManager` answers 5003 to a batch → AC 1's `Completed` assertion.
- `WatchOps` writes no `CreatedAt` → `Test.Watch.Ops`.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: contended path `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` (Epic 16). AD-15 names `WatchMark` as the per-production high-water mark, but the table holds only `Namespace` and `Production`; the story needs `WatchMark.MarkAt` and `WatchMark.Seen`, and (recommended) `BackgroundCheck.CreatedAt`, and `Test.Data.Tables.TestContracts` pins both tables' exact property sets, so the change fails a contended test unless its Contracts XData changes.

**Questions for the lead / orchestrator:**
1. May Epic 5 edit only the two Contracts entries of `Test/Data/Tables.cls` (`OcuTalon.Data.WatchMark` + `MarkAt`, `Seen`; `OcuTalon.Data.BackgroundCheck` + `CreatedAt`), as a one-time footprint extension? Options:
   - (a) yes (recommended): two JSON entries Epic 16 does not own, so a later merge is a plain union;
   - (b) Epic 16 makes the edit and 5.2's implement stage waits for it;
   - (c) as (a) for `WatchMark` only, with `WatchOps` creating or resetting the production's `WatchMark` at its first watch instead of a `BackgroundCheck.CreatedAt` (no `BackgroundCheck` change, but two writers of `WatchMark`).
   Rejected: storing the mark anywhere else (a raw global, `StatusMark`, a new class outside `OcuTalon.Data`), because it breaks AD-15 or AD-33, or dodges the registry and contract checks.
2. Veto-window items (schema): the three new stored properties on Lane A tables (append-only, AD-5). No grant, no privilege change.

**Evidence:** `Test/Data/Tables.cls` L454-483; `Data/WatchMark.cls`; the measured behaviour under Code Map (the BP logs before the status, an operation logs a repeated error once, `EnQueue` commits open transactions), which is why the mark must be durable, time-based and exact at the watch's start. The rest of the spec is complete for option (a); for (c) only the `CreatedAt` tasks, the `Mark` start rule and one matrix row change.

**Task 0:** measured on the lane-A warm throwaway `e5s2pw` (started and torn down by this stage; lock released; tree unchanged).
