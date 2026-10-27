---
title: 'The production watch runs on every heartbeat'
type: 'feature'
created: '2026-10-26'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** After Story 5.5, a watch row exists and incidents move through their states, but `Checks` is still a stub. No heartbeat ever runs a check, so the page's background-check row never shows a last run, a result or a trace link, and Story 5.7 has no results to answer "is everything fine?" from. A new or stopped watch also never reaches the page until a reload. Nothing sends `closeQuiet`, so a stale incident never closes quietly. `/state` builds the check view with its own copy (`Web.Api.CheckView`, DW-66), and that copy points the trace link at the watched production's namespace.

**Approach:** `OcuTalon.Checks.Process` handles each `Tick`:
- It sends `closeQuiet` for every unclosed incident whose last failure is more than 15 minutes old.
- It runs each production check that is due, once. The check reads the production's running state and the session's new failures through `Watch.Reader`, and the session's unclosed incidents from the rows.
- It records the result on the `BackgroundCheck` row and publishes the row as a `check` event, using the new `Live.Payload.Check.FromRow`.

`WatchOps` tells `Checks` when it starts or stops a watch, and `Checks` publishes that change as a `check` event. `/state` switches to `FromRow` (DW-66). This spec is written to the recommended answers of rulings Q1 to Q3 (Design Notes).

## Boundaries & Constraints

**Always:**
- **A Tick** (`OcuTalon.Msg.Tick`):
  - **Times.** `now` is `Data.Time.NowUtc()`. The tick time is `TickAt` when it is a UTC stamp (`YYYY-MM-DDTHH:MM:SSZ`), else `now`. `PreviousTickAt` and `CatchUp` need no branch of their own.
  - **First, the quiet sweep.** Every `Incident` row that is not `closed`, whose `LastAt` is more than `IncidentManager.#QUIETSECONDS` before `now` (`Settle.Quiet`), gets one `OcuTalon.Msg.IncidentCommand`:
    - the command is `Verb` `closeQuiet`, its `IncidentRef`, `Origin` `timer` and no `SessionRef`;
    - it is sent synchronously to `IncidentManager`, waiting at most `QUIETWAIT` (30) seconds, through one private seam, `SendQuiet`;
    - it goes in the Tick's trace session, with `SuperSession` set to the TraceRef of the owner's session (empty for `instance` or `eval`), and the BP's own `SuperSession` is put back after the send;
    - `Checks` does not act on the answer, because `IncidentManager` applies the table and publishes the incident event;
    - an error status or a timeout logs one Type 3 warning (`LOGQUIET`) that names the incident, and the sweep goes on.
  - **Then, the checks.** Every row of `Kind` `production` is due when its `NextDueAt` is empty, or is at most `DUESLACKSECONDS` (5) after the tick time. Each due row runs once, as below. An exception in one row's run logs one Type 3 warning (`LOGRUN`), and the next row still runs. `OnRequest` answers OK.
- **One run** of a row:
  1. **The run time.** `runAt` is `now`, read again at this row.
  2. **The read.** The private seam `Read(namespace, production, from, limit, .rows, .state)` reads with `Watch.Reader.Failures`. It reads from `Mark.Start(LastRunAt, CreatedAt, Mark.Normal(runAt))`, which is the previous run less `Mark.#OVERLAP` seconds, else the watch's creation. Its limit is `Mark.#MAXFAILURES`.
  3. **Scope (AD-4).** A failure is the session's when `FailurePoller.Scope(failure.superSession)` is the row's `SessionRef`. It is also the session's when that scope is `instance` and the instance is not the online demo (`Watch.Reader.OnlineDemo()`). Incidents follow the same rule: those of the row's namespace and production whose `OwnerRef` is the session, or `instance` off the online demo, and whose `State` is `open`, `awaiting_approval` or `fixing` (noticed or not).
  4. **The result.** The first rule that holds decides it:
     - **`not_checked`, with one reason:**
       - `REASONUNREADABLE` when the outcome is `unreadable`;
       - `REASONNOTCURRENT` when it is `not_current`;
       - `REASONTIMEOUT` when the state is `timeout`;
       - `REASONREAD` when the read threw (which also logs one Type 3 warning, `LOGREAD`, with the error redacted by `Bridge.Redact`), when the state is `unknown`, or when the incident read failed;
       - `REASONTOOMANY` when the read came back cut at its limit and none of its rows are the session's.
     - **`failed`,** when the state is not `running`, or the session has at least one new failure, or it has at least one unclosed incident. The finding joins up to three parts, in this order, with ", ", and the first letter is upper-cased:
       - the state: `FINDINGSTOPPED`, `FINDINGSUSPENDED`, `FINDINGTROUBLED`, or `FINDINGNOTRUNNING` (for `network_stopped`);
       - the new failures: `FINDINGFAILURE` for one, `FINDINGFAILURES` with the count, or `FINDINGATLEAST` with the count when the read was cut;
       - the most urgent unclosed incident: `FINDINGAWAITING`, else `FINDINGFIXING`, else `FINDINGOPEN`.
     - **`passed`** otherwise, with an empty finding.
  5. **The record.** One SQL `UPDATE` keyed by `Ref` sets `LastRunAt` (`runAt`), `Result`, `Finding`, `LastRunHeaderId` (the BP's `%SessionId`, which is the Tick's trace session) and `NextDueAt` (the tick time plus `INTERVALSECONDS`, 60). When no row is updated (the watch was stopped meanwhile), nothing more happens, and no row is ever re-created.
  6. **The event.** The row is opened again by `Ref`, and one `check` event with `Live.Payload.Check.FromRow(row)` is published on the row's `SessionRef` stream through `Live.Publish`, after the update's commit. A failed publish logs one Type 3 warning (`LOGPUBLISH`).
  7. **The log line.** The run writes one Type 4 info line (`LOGRAN`) in the Tick's session, naming the check's Ref, its display name, the result and the finding. The run can then be read in its trace (FR-32).
- **The finding is code-built.** The parts and reasons are `Checks` class parameters (Design Notes Q3), with counts as the only slots. No error text, event-log text or diagnosis text ever reaches `Finding`, which 5.7's trusted `check_status` will carry.
- **`Watch.Reader.Failures` gains `Output state`**, read in the same switch (`Current`):
  - the state is `running` (1), `stopped` (2), `suspended` (3), `troubled` (4) or `network_stopped` (5);
  - it is `timeout` when `Ens.Director.GetProductionStatus` answers its runtime-lock error (`LOCKSECONDS`), and `unknown` for any other error or state;
  - it is `""` with the outcomes `unreadable` and `not_current`;
  - nothing else in the reader changes, and `FailurePoller` ignores the state.
- **`FailurePoller.Scope(superSession)`** is a new public class method. It gives the Ref of the session whose TraceRef is `superSession`, else `instance`. `Poll` uses it, and the poller's behaviour is unchanged.
- **`Live.Payload.Check.FromRow(row)`** (DW-66):
  - it sets every row-backed field;
  - `stopped` is false;
  - only when `LastRunHeaderId` is set, `traceHeaderId` is that id and `traceNamespace` is `$Namespace`, the namespace that holds OcuTalon's production and the run's trace (AD-26, UX-DR139);
  - `Web.Api`'s rail builds each check with `FromRow`, and `CheckView` is removed.
  - The doc of `Stopped` says: "True only in the last event of a check whose watch was stopped; the page drops it" (Q2).
- **Start and stop.** After a `started` answer (a new row) and after a `stopped` answer, `WatchOps` sends one `OcuTalon.Checks.Msg.CheckChanged` to the `Checks` item:
  - **The message.** `Ens.Request`, with `CheckRef` and `SessionRef` (22), `Stopped` (`%Boolean`), `Kind` (32), and `Namespace`, `Production` and `DisplayName` (128).
  - **How it is sent.** Asynchronously, through one private seam, `SendChanged`. For a stop, `WatchOps` reads the row's fields before the delete.
  - **Nothing is sent** for `already_watching`, `not_watching`, `failed`, `no_session`, `unknown_production` or `only_orders`.
  - **A failed send** logs one Type 3 warning (`LOGCHANGED`), and the answer stays as it was.
  - **What `Checks` publishes:**
    - for a start, `FromRow` of the row it opens by Ref, and nothing when the row is gone;
    - for a stop, a payload of the message's Ref, kind, namespace, production and display name with `stopped` true, on the message's `SessionRef` stream.
- **The page (Q2).** The rail's check list leaves out a check whose payload has `stopped` true, so a stopped watch leaves within one live update, and the heading's count follows.
- **Unchanged:**
  - `Checks` keeps `PoolSize` 1;
  - `IncidentManager` stays the only writer of incidents (and its row is the idempotency);
  - `WatchOps` still creates and removes the rows, and `Checks` writes only the run fields;
  - the `Tick` and `HeartbeatIn` classes do not change.

**Never:**
- Each of these belongs to a later story:
  - no finding `Item` to `Intake`, and no "never report a finding twice" (Story 30.4);
  - no `Fix.Run.Sweep` call (Story 7.5);
  - no `Render`, `ReplyGuard` or `check_status` work (Story 5.7);
  - no `HeartbeatIn` or Task Manager task (Epic 8).
- No new table or column, and no change to the `BackgroundCheck`, `Incident` or `Live.Payload.Check` property sets (so `web/src/app/live/payloads.ts` is not regenerated). No new catalog entry.
- No check kind other than `production`. No namespace switch outside `Watch.Reader`. No raw error text in a row, a payload or a finding.
- No edit to a contended path beyond the two that the rulings allow (`Test/Web/Api.cls` for Q1, `web/src/app/rail/rail-view.ts` for Q2). In particular nothing in `Demo/**`, `Install/**`, `Channel/**`, `Live/Publish*.cls`, `Data/{Session,Ownership,Setting}.cls`, `web/e2e/**` or `.github/**`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Due | Rows with `NextDueAt` 7 min before the tick (missed runs, `CatchUp` 1), empty, 3 s after the tick, and 2 min after it | The first three run once each and the fourth does not. Each `NextDueAt` becomes the tick time + 60 s, and a second Tick with the same `TickAt` runs none of them | none |
| Passed | Running, no failure of the session since the last run; the only unclosed incidents are another session's, a resolved one and a closed one | `passed`, an empty finding, `LastRunAt` = now, `LastRunHeaderId` = the Tick's session, and one `check` event (`FromRow`) on the session's stream | none |
| Failed | Stopped, suspended, troubled; 1, 50, or a cut read of new failures; an open, awaiting-approval or fixing incident; combinations of these | `failed`, for example "50 new failures, a fix waiting for your approval", "Production stopped, 1 new failure", "At least 500 new failures", "An open incident" | none |
| Scope | Failures tagged with A's TraceRef, with B's, and untagged; incidents of A, of B and of `instance`; a local install, then the online demo | A's check counts A's failures and incidents, plus the untagged failures and `instance` incidents on a local install only, and never B's | none |
| Not checked | A read that throws; `unreadable`; `not_current`; state `timeout`; state `unknown`; a cut read with none of the session's rows; an incident read that fails | `not_checked` with its reason, never `passed`. A thrown read logs one Type 3 warning with the redacted error, and the finding holds no error text | not_checked |
| Window | A first run, then a later run | The first reads from `CreatedAt`, the later from `LastRunAt` less 2 s | none |
| Stopped meanwhile | The row is removed between selection and record | Nothing is recorded or published, and the row stays removed | none |
| Quiet close | Unclosed incidents with `LastAt` 16 min ago (resolved; open and noticed; awaiting approval; fixing), one 14 min ago, and a closed one | One `closeQuiet` for each 16-minute incident (origin `timer`, no session, the owner's TraceRef as `SuperSession`) and none for the others. `IncidentManager` closes the resolved one, and the open one only with demo mode off | A failed send logs one warning, and the other incidents still get theirs |
| Start and stop | `WatchOps` answers started, then stopped; also already_watching and not_watching | Start: one `check` event (`FromRow`, no run yet). Stop: one event with `stopped` true and the watch's name, which the rail drops. No event for the answers that change nothing | A failed send to `Checks` logs one warning, and the answer stays |
| `/state` (DW-66) | A check with a run and one without | The run carries `traceHeaderId` = `LastRunHeaderId`, `traceNamespace` = `$Namespace`, and a `traceUrl` into OCUTALON's trace application. The check with no run carries none | none |
| Unknown request | Any other class | An error 5001 that names the class | error |

</intent-contract>

## Code Map

Every path is under `src/ocutalon/cls/OcuTalon/` unless noted.

- **`Checks/Process.cls`** (19 lines: `STUB` L7 and `OnRequest` L11 answer "not implemented"): the whole item is written here.
  - `IncidentManager.cls` is its pattern: `OnRequest` dispatching by class and the 5001 fallthrough at L137-150, the `%SessionId` swap of `Execute` around a seam at L581-599, and the parameter style at L63-135.
- **The Tick and the heartbeat:**
  - `Msg/Tick.cls`: `TickAt`, `PreviousTickAt`, `CatchUp` (Lane B; read only);
  - `Schedule/HeartbeatIn.cls`: a stub until Epic 8, an adapterless service that tests use as the Tick's sender;
  - `Production.cls` L45: `Checks`, PoolSize 1. No change.
- **`Data/BackgroundCheck.cls`:** the run fields at L32-45 and the class doc L1. `Data/Incident.cls`: `OwnerRef`, `Namespace`, `Production`, `State`, `LastAt`, `NoticedAt`.
- **The reader** (`Watch/Reader.cls`):
  - `Failures` L169 and `Current` L235; `GetProductionStatus(.name, .state, lock, 1)` is at L247 (its error is swallowed today);
  - `LOCKSECONDS` L42, `OnlineDemo` L128;
  - the class doc L21-25 ("Failures reads …") gets the state.
  - Ens's own source is reference only: `irislib/Ens/Director.cls` L531-593 (the lock error `EnsErrCanNotAcquireRuntimeLock`, state `Unknown`) and `irislib/EnsConstants.inc` L8-14 (the state codes).
- **The poller and its arithmetic:**
  - `Watch/FailurePoller.cls`: the scope loop of `Poll` at L89-95 (this becomes `Scope`), the `Read` seam at L136, the class doc L7-9;
  - `Watch/Mark.cls`: `MAXFAILURES` L16, `OVERLAP` L19, `Normal` L23, `FromCreated` L33, `Shift` L40, `Start` L52, `FailedAt` L117.
- **The quiet rule:** `Watch/Settle.cls` `Quiet` L81. `Watch/IncidentManager.cls`: `QUIETSECONDS` L68, and `Command` L601 (the answer codes of the "Incident commands" row). `Msg/IncidentCommand.cls` holds `VERBS`, `Verb` and `IncidentRef`. `Msg/Command.cls` holds `Origin`, and `Msg/Enum.cls` `ORIGIN` L39 includes `timer`.
- **WatchOps** (`Watch/Ops.cls`): `OnStart` L50 (the save at L77), `OnStop` L94 (the delete at L106), `RefOf` L124. The class doc L1-13 says it is "the only writer", and that line changes.
- **The payload:**
  - `Live/Payload/Check.cls`: `Stopped` L20-21 and the trace fields L35-39;
  - `Live/Payload/Incident.cls` L128-150: the `$Namespace` trace target that `FromRow` follows;
  - `Live/Publish.cls` `Publish` L52 (refused inside a transaction; `check:Check` is already in `TYPES` L10).
- **`Web/Api.cls`** (shared by entry; the check entry only): `RailBody` L351-367 (L359 pushes `CheckView`) and `CheckView` L369-389, which goes.
- **Session reads** (`Data/Session.cls`, contended; call only): `RefIndexOpen(…).TraceRef` and `TraceRefIndexOpen`.
- **Tests and their patterns:**
  - `Test/Watch/IncidentProbe.cls` and `Test/Watch/PollerProbe.cls`: the shadow-instance probes (seam overrides; a shadow cannot `SendRequestAsync` or `SendRequestSync`).
  - `Test/Watch/Lifecycle.cls`: a probe test over fixture rows that runs warm, removes its rows, streams and log lines, and has helpers such as `Count` and `Newest` of a stream at L998-1010.
  - `Test/Watch/Case.cls`:
    - running-production helpers: `Fail` L463, `WaitFailed` L496, `StopOrders` L763, `StartOrders` L772, `OrdersRunning` L797, `Stream` L1027, `Watch` L435, `Rows` L415;
    - clean-up: `OnAfterOneTest` L147 deletes the run's BackgroundCheck and Incident rows.
  - `Test/Watch/Ops.cls`: `Host` L261 (a shadow of `Watch.Ops`), `TestThroughTheProduction` L149, and `Hold`/`Holder`/`Release` L311-340 (another job holds a lock).
  - `Test/Watch/Reader.cls`: `TestStoppedProduction` L258 (stops Orders and starts it again).
  - `Test/Agent/RunnerFixture.cls` `Send` L262 (a sync send to an item from an adapterless service).
  - `Test/Data/Fixture.cls` (contended; call only): `Session` L19, `Check` L65, `Incident` L81 (state `open`, `LastAt` 2030), `SessionHeaders` L392.
  - `Test/Install/Production.cls`: the doc L13 and the `Checks` oracle row L629 (`"stub": 1`).
  - `Test/Bridge/CodeRules.cls`: `INCIDENTWRITES` L121 and `INCIDENTWRITERS` L124, `TestOnlyIncidentManagerWritesIncidents` L268, and `Offenders` L961.
  - `Test/Live/Payloads.cls` `TestFromRowBuilders` L410 (lane-b).
  - **Contended (Q1):** `Test/Web/Api.cls` L246-253. L248's message names `CheckView`. L250 asserts `"31|ZZNS"`, and L251 asserts no `traceUrl`.
- **Web:**
  - **Contended (Q2):** `web/src/app/rail/rail-view.ts`. `railView` L307 (`const checks = inStoreOrder(store.checks)`), `checkRow` L204.
  - **Not contended:** `web/scripts/rail-view.test.mjs`. The `check()` fixture is at L73 (`stopped: false`) and `describe('background checks')` at L267.
  - **Unaffected:** `web/e2e/trace/links.spec.ts` L291 seeds its checks in `OCUTALON`, so its trace URL is the same before and after DW-66.
- **CI:** `ci/units.sh` L17, where the lane-a areas gain `Checks` (`docker/tests/test-ci-config.sh` needs every `Test/<Area>` in one shard).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Checks/Msg/CheckChanged.cls`: new. Its properties are given in Always (Start and stop). The class doc names its sender (`WatchOps`) and its handler (`Checks`). The `Storage` block is as the compiler writes it.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls`: `Failures` and `Current` gain `Output state`, as Always gives it. The class doc gets the state.
- `src/ocutalon/cls/OcuTalon/Watch/FailurePoller.cls`: `Scope(superSession)` is extracted, and `Poll` calls it. The class doc names it.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Check.cls` (footprint extension): add `FromRow`, and correct the docs of `Stopped` and the trace fields (Always).
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls`:
  - **Handlers.** The Tick handler, the run, the quiet sweep and the `CheckChanged` handler, as Always gives them. Any other request class is an error 5001 that names the class.
  - **Private methods.** `Due(tickAt)` gives the due rows as plain objects, and `Quiet(now)` gives the incidents to close. `Read` and `SendQuiet` are the seams. Publishing goes through the real `Live.Publish`.
  - **Parameters.** `INTERVALSECONDS`, `DUESLACKSECONDS`, `QUIETWAIT`, `MANAGER` "IncidentManager", `CHECKEVENT` "check", the texts of Q3 and the `LOG*` lines.
  - **Removed:** `STUB`.
  - **The class doc** states the contract.
- `src/ocutalon/cls/OcuTalon/Watch/Ops.cls`:
  - it sends `CheckChanged` through `SendChanged`, as Always gives it, with the parameters `CHECKS` "Checks" and `LOGCHANGED`;
  - the class doc says `WatchOps` creates and removes the rows and that `Checks` records each run (AD-18).
- `src/ocutalon/cls/OcuTalon/Data/BackgroundCheck.cls`: the class doc only. `WatchOps` creates and removes a row, and `Checks` records `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId` and `NextDueAt`.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` (shared by entry): `RailBody` uses `Check.FromRow`, `CheckView` is removed, and nothing else changes (DW-66).
- `web/src/app/rail/rail-view.ts` (contended; only under ruling Q2):
  - `railView` lists `inStoreOrder(store.checks).filter((check) => check.stopped !== true)`;
  - the module doc's line "every check in store order" becomes "every check that is not stopped, in store order".
- `web/scripts/rail-view.test.mjs` (footprint extension): a check with `stopped: true` is neither listed nor counted, and one with `stopped: false` or no `stopped` is.
- `ci/units.sh` (Lane A's own entry): `lane-a) echo "Agent Bridge Checks Install Tools Digest Watch"`.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls`: new, test only, and not an item of any production. It extends `Checks.Process`:
  - `Read` answers per production from a process-private global (outcome, state, rows, or throw) and records each `from` and `limit`;
  - `SendQuiet` records `{incidentRef, verb, origin, sessionRef, superSession, sessionId}` and answers OK, or an error when `FailQuiet` is set;
  - `Due` and `Quiet` keep only the Refs that the test lists (after `##super`), so that a warm stack's other rows are never touched.
  - The doc says why each override exists.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls`: new. Probe tests on a shadow instance of `Test.Checks.Probe`, over `Fixture` sessions, rows and incidents on fixture names (runs warm).
  - **One test per matrix row:** `TestDue`, `TestPassed`, `TestFailed` (every part and the exact texts), `TestScope` (with `onlineDemo` written and put back), `TestNotChecked` (each reason; the thrown read's warning is redacted, and the finding has no error text), `TestWindow`, `TestStoppedMeanwhile` (the probe's `Read` deletes the row), `TestQuietSweep` and `TestChanged` (start, stop, and a start whose row is gone).
  - **Per run:** `TestPublishes` asserts exactly one `check` event per run, equal to `FromRow`, and `TestRanLine` asserts one Type 4 line per run.
  - `TestUnknownRequest`.
  - It sets the probe's `%SessionId` to a known id, so that `LastRunHeaderId` is asserted.
  - After each test it removes its rows, incidents, streams and log lines.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Heartbeat.cls`: new. It extends `Test.Watch.Case`, runs over the running production, and runs fresh. A helper `Tick(tickAt)` creates `HeartbeatIn` with `Ens.Director.CreateBusinessService`, sends the Tick synchronously to `Checks` (60 s at most), and gives back the service's `%SessionId`.
  - `TestTickRunsTheWatch` (AC 1).
  - `TestFailingOrders` (AC 2): `Fail` with the session's TraceRef and `WaitFailed`, then a Tick. Then `StopOrders`, a Tick, `StartOrders`, and the test asserts that Orders runs.
  - `TestQuietClose` (AC 3): the closing `incident` header is found with `Fixture.SessionHeaders`, and it carries the owner's TraceRef as its `SuperSession`.
  - `TestStartAndStop` (AC 4): through the `WatchOps` item with `RunnerFixture.Send`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/OpsProbe.cls`: new, test only. It extends `Watch.Ops`: `SendChanged` records each message as a plain object and answers OK, or an error when `FailChanged` is set.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Ops.cls`:
  - `Host` makes a shadow of `OpsProbe`;
  - `TestStart` and `TestStop` also assert the one recorded `CheckChanged` (start: Ref, session, `Stopped` 0; stop: `Stopped` 1 with the row's kind, namespace, production and display name);
  - `TestRepeat` and `TestOwnerCheck` assert that nothing was sent for already_watching, not_watching, no_session and unknown_production;
  - new `TestChangedSendFails`: one warning, and the answer is still started or stopped.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Reader.cls`: new `TestFailuresState`.
  - Orders running gives `running`.
  - Orders stopped gives `stopped`. While it is stopped, another job holds `^Ens.Runtime("ConfigItem")` in OCUORDERS (following `Test.Watch.Ops`' `Holder`), and the state is `timeout`. Orders is started again.
  - `unreadable` and `not_current` give `""`.
- `src/ocutalon/cls/OcuTalon/Test/Live/Payloads.cls` (footprint extension): new `TestCheckFromRow`, which builds from unsaved rows:
  - every field, and `stopped` false;
  - with `LastRunHeaderId` set, the trace target is in `$Namespace`;
  - without it, there are no trace fields.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: the `Checks` oracle row gets `"stub": 0`, and the doc L13 lists `Checks` as built (Story 5.6).
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls`: new `TestOnlyChecksPublishesCheck`, built like `TestOnlyIncidentManagerWritesIncidents`:
  - a `CHECKPUBLISHES` pattern for `Publish(…, "check"…)`, whose look-alikes pass;
  - `CHECKPUBLISHERS` is "OcuTalon.Checks.Process", and the scan finds that class only.
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` (contended; only under ruling Q1). Only these lines change:
  - L248's message says "Check.FromRow's";
  - L250 asserts `"31|"_$Namespace`;
  - L251 asserts `traceUrl` `"/ocutalon/trace/ocutalon/EnsPortal.VisualTrace.zen?SESSIONID=31"`, as L243 does for an approval.

**Acceptance Criteria:**
- **AC 1 (Integration AC: consumer `/state`, through `Web.Api.StateBody`).** Given a fixture session that watches Orders through a due row on the running production, when `HeartbeatIn` sends a Tick to `Checks`, then:
  - the row holds `LastRunAt`, `passed`, an empty finding, and `LastRunHeaderId` equal to the Tick's session;
  - `NextDueAt` is the tick time + 60 s;
  - one `check` event equal to `FromRow` of the row is on the session's stream;
  - `StateBody(session)`'s rail check has that run, `traceNamespace` `$Namespace`, and a `traceUrl` into OCUTALON's trace application ending `SESSIONID=<the Tick's session>`.
- **AC 2.** Given the session's 3 failing orders in Orders (tagged with its TraceRef), when the next Tick runs, then the row is `failed`, and its finding begins "3 new failures". Given Orders stopped, when a Tick runs, then the finding begins "Production stopped". The production then runs again.
- **AC 3 (Integration AC: `IncidentManager` consumes `Checks`' `closeQuiet`).** Given a session's noticed resolved incident whose `LastAt` is 16 minutes old, and another whose `LastAt` is 14 minutes old, when a Tick runs, then the real `IncidentManager` closes the first: it is `closed` with `ClosedAt`, and an `incident` event `closed` is on the session's stream. The second stays `resolved`.
- **AC 4 (Integration AC: consumer the session's live stream and the page's rail).** Given a session, when the `WatchOps` item starts a watch of Orders and then stops it, then two `check` events reach the session's stream, in order:
  - one equal to `FromRow` of the new row, with no run;
  - one with that Ref and `stopped` true.
  - Applied to a page store in the order served, the rail lists the check after the first event and no longer lists or counts it after the second (`rail-view.test.mjs`, Q2).
- **AC 5.** Given the product source, when `Test.Bridge.CodeRules`, `Test.Install.Production`, `Test.Live.Payloads`, `Test.Web.Api` (Q1) and `bash ci/checks.sh` run, then they pass. `Checks` carries no `STUB` and is the only class that publishes `check`, `/state`'s check entry is `FromRow`'s, and `ci/units.sh` puts `Test.Checks` in lane-a.
- **AC 6.** Given the Orders production running, stopped, and stopped with its runtime lock held by another job, when `Watch.Reader.Failures` reads it, then the state is `running`, `stopped` and `timeout`. An unreadable namespace and a production that is not current give `""`.
- **DW-66** (ledger; routed by harvest 2026-10-22: `Web.Api.CheckView` copies what a `Live.Payload.Check.FromRow` would do; the publisher adds `FromRow`, confirms or replaces `traceNamespace`, and `StateBody` switches to it). Given a check row with a run and one without, when `/state` (`Web.Api.StateBody`) and `Checks`' `check` event build their payloads, then both are `Live.Payload.Check.FromRow`'s and `Web.Api` holds no copy of its own. `traceNamespace` is replaced by `$Namespace` (Q1), and the check with no run carries no trace fields. It is pinned by `Payloads.TestCheckFromRow`, `Web.Api` (Q1), AC 1 and the `/state` matrix row.

## Spec Change Log

- 2026-10-27, spec gate (Epic 5 runner): Q2 ruled (a) (decide; not contended), Q3 ruled keep (veto U-105); Q1 (contended `Test/Web/Api.cls`) sent to the orchestrator; status stays `blocked` until Q1 is ruled.

## Review Triage Log

## Design Notes

**Rulings needed (plan halted; recommended answers are what this spec is written to). Q2 RULED 2026-10-27 by the epic lead: (a), decide — `web/src/app/rail/` is in no live epic's footprint, so `rail-view.ts` is a reported footprint extension, not a contended path. Q3 RULED 2026-10-27 by the epic lead: keep as worded, veto U-105. Q1 is with the orchestrator (`Test/Web/**` is Epic 16's).**
- **Q1. Contended test `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` (DW-66).**
  - **Why `traceNamespace` must change.** The check's trace is its latest run. A run is the Tick's session in OcuTalon's own production (AD-26: "Rows that a link targets store the header id it needs (… latest check run …)"; UX-DR139: "check: latest run", apart from "evidence: failed messages in the Orders namespace"). So `traceNamespace` must be `$Namespace`, not the watched production's namespace. A header id of OCUTALON looked up in OCUORDERS opens the wrong message, or none.
  - **What that breaks.** Switching `StateBody` to `Check.FromRow` breaks two assertions:
    - `Test.Web.Api` L250: `"31|ZZNS"`, "a check with a run carries its trace";
    - L251: `view.%IsDefined("traceUrl")` is 0, "but a namespace with no trace application gives it no traceUrl".
  - **Recommended (a):** allow these two assertions and L248's message to change, as shared-by-entry. The check entry of `/state` is Lane A's payload. Q1 changes only these lines.
  - **Alternative (b):** route the `StateBody` switch and the test to a Lane B story. Until then, `/state` and the `check` event disagree, and the rail's trace link points into the wrong namespace after a reload.
- **Q2. Contended `web/src/app/rail/rail-view.ts` ("so a new watch shows at once and a stopped one leaves").**
  - **Why the page must change.** The rail lists every check in store order (L307), and the live store only puts payloads. So no `check` event can make a check leave without a page change. A new watch already shows at once, because the store puts its event.
  - **Recommended (a):**
    - The stop event carries the payload's existing `stopped` field as true. Its doc is corrected from "True when the production is stopped" to "the watch was stopped". The field has no row source, as `Web.Api.CheckView`'s comment says, and the production's running state is reported through `result` and `finding`. So the property set, and `payloads.ts`, do not change.
    - `railView` filters `stopped` checks: one line, and its test lives in the non-contended `web/scripts/rail-view.test.mjs`.
    - Allow the line as shared-by-entry (precedent: Epic 4's q3 ruling on `payloads.ts`).
  - **Alternative (b):** route the filter to a Lane B story (adding an AC to another epic's story). This story still publishes `stopped` true, and the check leaves only on a reload until then.
  - **Alternative (c):** a new payload field for removal. That regenerates the contended `payloads.ts` and leaves `stopped` meaningless.
- **Q3. Public-facing text not in the UX or PRD (veto window, item 5).**
  - **Where it shows.** The page's rail shows the finding ("Last run 14:13 · {finding}"), and Story 5.7's check rows will show it too. Only "50 new failures" is the UX's own fixture (UX-DR53).
  - **Proposed `Checks` parameters:**
    - `FINDINGSTOPPED` "production stopped", `FINDINGSUSPENDED` "production suspended", `FINDINGTROUBLED` "production troubled", `FINDINGNOTRUNNING` "production not running";
    - `FINDINGFAILURE` "1 new failure", `FINDINGFAILURES` "{count} new failures", `FINDINGATLEAST` "at least {count} new failures";
    - `FINDINGAWAITING` "a fix waiting for your approval" (5.7's own example says "a fix is waiting for your approval"), `FINDINGFIXING` "a fix running", `FINDINGOPEN` "an open incident";
    - the parts are joined with ", ", and the first letter is upper-cased;
    - the reasons: `REASONUNREADABLE` "No read access to its namespace", `REASONNOTCURRENT` "No longer its namespace's production", `REASONTIMEOUT` "No answer in time", `REASONREAD` "Couldn't be read", `REASONTOOMANY` "Too many new failures to count".
  - **Recommended:** accept them as worded, since a passed check shows the page's own word, Passed. The owner may reword any of them in the veto window, and that is a parameter edit.

Story size: recommended as one story, with `oversized`. It is about Story 5.5's size (some 450 product lines and 1,100 test lines), all in the Checks area. A split (start and stop with the page filter as a sibling, 5.10) would cost a full pipeline cycle for about 150 lines, so it is not recommended unless Q2 is answered (b).

**Governing ADs:**
- AD-18: the heartbeat's Tick, the one `BackgroundCheck` table, due checks run once, and the run fields;
- AD-28: results only from `Checks`, and a release-1 production check is the running state, new errors, open incident and run time;
- AD-12: the full view keyed by `Ref`, published after commit, with the trace target as `TraceHeaderId` plus `TraceNamespace`;
- AD-15: `closeQuiet` from `Checks`, and the table decides;
- AD-26: the run's trace session, and `SuperSession` on the messages for a session;
- AD-4: the session's scope, with `instance` only off the online demo;
- AD-3: the namespace switch is only in `Watch.Reader`;
- AD-5: `NextDueAt` in the row, and nothing in memory;
- AD-33: `Checks` is the single publisher of `check`;
- AD-1: components reach each other by message (`CheckChanged`, `IncidentCommand`);
- AD-29: Lane A;
- AD-22: throwaways.

Conventions:
- "Incident commands": `closeQuiet`'s codes, no session;
- "Watch failures": what a failure is, the reader reads only the namespace's own production, and the scope;
- "Tool classification": trusted output means a code-built finding;
- "Live events", "Times", "Logging and errors", "Messages" (`SessionRef` on `CheckChanged`), and "Tests".

**Integration ACs, Consumes, Consumed-by:**
- **New:** the built `Checks` item, `CheckChanged`, `Check.FromRow`, `Reader.Failures`' state, and `FailurePoller.Scope`.
- **Integration ACs:**
  - AC 1: consumer `/state`;
  - AC 3: `IncidentManager` consumes `closeQuiet`;
  - AC 4: consumer the session's stream and the page's rail.
- **Consumes:**
  - Epic 0: `Tick`, `BackgroundCheck`, `Live.Payload.Check`, `IncidentCommand`;
  - 5.1: `WatchOps`' rows and `Watch.Reader`;
  - 5.2: `Reader.Failures`, the poller's scope rule, and `Mark`;
  - 5.5: `closeQuiet`, `Settle.Quiet` and `QUIETSECONDS`;
  - Epic 2: `Live.Publish`, `Web.Api`'s rail, `TraceLink`, and `Session.TraceRefIndexOpen`.
- **Consumed-by:**
  - 5.7: `check_status` reads the recorded results, and the finding is trusted;
  - 8.1: `HeartbeatIn` sends the real Tick;
  - 8.2: the REL-2 "Orders production" check row with a real last run;
  - 7.5: `Fix.Run.Sweep` on each Tick;
  - 30.4: finding Items from these runs;
  - Epic 30: the 7-day purge of `Checks` messages.

**Extend, don't copy:**
- `Checks.Process` follows `IncidentManager`'s dispatch, seams and parameters.
- The window is `Mark.Start`, and the next-due time is `Mark.Shift`, `FromCreated` and `FailedAt`. No new time arithmetic is written.
- The scope is `FailurePoller.Scope`, extracted from `Poll`, not copied.
- The quiet rule is `Settle.Quiet` with `IncidentManager.#QUIETSECONDS`.
- `FromRow` replaces `Web.Api.CheckView`, so one builder remains.
- The probes follow `IncidentProbe` and `PollerProbe`.
- The timeout test's lock holder follows `Test.Watch.Ops`' `Holder` (a second holder, because it locks another global in another namespace; reason: different lock).
- `TestOnlyChecksPublishesCheck` follows `TestOnlyIncidentManagerWritesIncidents` and its `Offenders`.

**Ledger inbox:** DW-66 is addressed (AC "DW-66", Q1).

**Confirmed (the epic context's "(inference)" line):** a row's finding is written by code, never from raw error or event-log text. The spine's "Tool classification" row defines trusted output as "built by code from OcuTalon's own records and holds no text from outside a user's untainted turn". Its `dismiss_incident` clause excludes "diagnosis or error text". A watched production's error text comes from outside the instance's own records. So the finding carries counts, states and fixed texts only.

**Decided in-stage:**
- **"Latest run time"** (AD-28) is the check's own run time, `LastRunAt`. No threshold exists that a production activity time could fail.
- **An unclosed incident fails the check** while it is `open`, `awaiting_approval` or `fixing`, noticed or not, so a slow notice never gives a pass. `resolved` and `closed` do not fail it.
- **Due.** The next due time is the tick time + 60 s. A row is due when that time is at most 5 s after a tick, so an early tick still runs it. Missed minutes give one run, because the next due time comes from the tick and not from the old one.
- **The run's trace is the Tick's session,** which is why `traceNamespace` is `$Namespace` (DW-66).
- **The quiet sweep runs before the checks,** so a check sees the closes. Every unclosed quiet incident gets the command, because only the table decides. It goes in the Tick's session and never in the incident's own trace, which would fill the demo's climax trace with a refused command every minute.
- **The record is an SQL `UPDATE` keyed by `Ref`,** not `%Save`, so that a watch stopped meanwhile is never re-created.
- **The texts are `Checks` parameters, not catalog keys.** Epic 0 made `finding` a text, and a catalog key would change the page's generated catalog module, a contended file.
- **`not_checked` wins** whenever any part cannot be read.
- **Only `production` rows run.** Every `OnRequest` for a Tick answers OK, as `FailurePoller` does.

**(inference), to be pinned by the tests:**
- A shadow `Checks`' `%SessionId` can be set by the test (AC 1 pins the real one).
- A job that holds `^Ens.Runtime("ConfigItem")` makes `GetProductionStatus` with a 1-second wait answer its lock error while the production is stopped. That follows from the source at `irislib/Ens/Director.cls` L549-562; the skip for a running production does not apply then.
- The BP's `SendRequestSync` carries `%SuperSession` onto the header (`irislib/Ens/BusinessProcess.cls` L153).

**Footprint extensions** (none contended): `Live/Payload/Check.cls`, `Test/Live/Payloads.cls`, `Test/Install/Production.cls` (the Lane A row), `Test/Bridge/CodeRules.cls` and `web/scripts/rail-view.test.mjs`. These are shared by entry: `Web/Api.cls` (the check entry) and `ci/units.sh` (Lane A's areas). These are contended, only under the rulings: `Test/Web/Api.cls` (Q1) and `web/src/app/rail/rail-view.ts` (Q2).

**Spine candidates (Rule 20, for the lead):**
- a row in "Cross-area classes": `OcuTalon.Checks.Msg.CheckChanged`, sent by `WatchOps` and handled by `Checks` (A, Story 5.6);
- an AD-18 clarification:
  - `WatchOps` creates and removes rows, and `Checks` records each run with an `UPDATE` keyed by `Ref`;
  - the next due time is the tick + 60 s, and a row is due within 5 s of a tick;
  - a run's trace is its Tick's session in OCUTALON;
- an AD-12 note: the `check` payload's `traceNamespace` is OcuTalon's namespace, and `stopped` marks a check's last event;
- an AD-28 clarification of what a production check's result means: the three failed parts, the `not_checked` reasons, and the AD-4 scope.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`.
- Run one command per call, each with `timeout: 600000`.
- Never put two IRIS test runs in one message, and chain nothing after a shard part.

**Commands:**
- (loop) `node --test web/scripts/rail-view.test.mjs` -- expected: every test passes.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s6iw ci/warm.sh up` -- once per stage. Expected: READY, and the after-start `RESULT OK` line.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s6iw ci/iris.sh class <Class>`, one call per class -- expected: `CLASS … passed`. The classes:
  - `OcuTalon.Test.Checks.Runs`, `OcuTalon.Test.Watch.Ops`, `OcuTalon.Test.Watch.Reader`, `OcuTalon.Test.Watch.Poller`;
  - `OcuTalon.Test.Live.Payloads`, `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Bridge.CodeRules`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s6i ci/iris.sh class <Class>`, fresh, one call per class: `OcuTalon.Test.Checks.Heartbeat`, `OcuTalon.Test.Web.Api` -- expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e5s6i ci/iris.sh shard lane-a --part 1/4`, then `--part 2/4`, `--part 3/4` and `--part 4/4`, each in its own call. Lane-a has 67 classes with this story's two, and `Checks.Heartbeat` is slow, so four parts keep each under about 400 s. Record each part's time.
- (once) `<lane> OCUTALON_RUN_TAG=e5s6i ci/iris.sh shard lane-b` -- `Test.Live.Payloads` and `Test.Web.Api` are in it. Expected: passed.
- (once) `bash ci/checks.sh` -- expected: all pass (`ci-config` with the new area).
- (once) `bash docker/tests/test-web-build.sh` -- expected: passes (`payloads.mjs --check` finds no change).
- (once) `<lane> OCUTALON_RUN_TAG=e5s6iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s6i ci/iris.sh teardown`.

**Shared surfaces:**
- **`/state`'s rail check entry:** its `traceNamespace` and `traceUrl` (`Test.Web.Api` L248-253, Q1). `web/e2e/trace/links.spec.ts` seeds its checks in OCUTALON, so its URL does not change, and no e2e test sees a run before Epic 8 sends real ticks.
- **The `check` payload's `stopped`:** `rail-view.ts` and `rail-view.test.mjs` (its fixture has `stopped: false`).
- **The item stub oracle:** `Test.Install.Production` (`Checks` stub 0, and the stub count follows).
- **The lane-a area list:** `ci/units.sh` and `test-ci-config.sh`. The lane-a class count goes from 65 to 67.
- **Session streams:** a real start or stop through `WatchOps` now adds a `check` event to the session's stream. The implement stage greps the tests that start a watch through the real `WatchOps` (`Test.Watch.Turns`, `Test.Watch.Tools`, `Test.Watch.Ops`, `Test.Core.CommandsInProduction`) for stream assertions, and keeps them by type. Today they read rows, not streams.
- **`WatchOps`' shadow tests:** every start and stop now sends, so `Test.Watch.Ops` uses `OpsProbe`.
- **`Reader.Failures`' signature:** an optional output. `FailurePoller.Read` and `PollerProbe` do not change.
- **A real Tick acts on every row and quiet incident of the namespace.** `Checks.Heartbeat` runs fresh and asserts only on its own rows, and `Checks.Runs` filters through the probe.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19). The implement stage applies each one, observes red, reverts byte-identically and records it here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | `LastRunHeaderId` set from the row's old value | `Heartbeat.TestTickRunsTheWatch` |
| AC 1, DW-66 | `FromRow`'s `TraceNamespace` = `row.Namespace` | `Payloads.TestCheckFromRow`, `Heartbeat.TestTickRunsTheWatch`, `Web.Api` |
| Due | `NextDueAt` = the old `NextDueAt` + 60 s (replays minutes) | `Runs.TestDue` |
| Due | `DUESLACKSECONDS` 0 | `Runs.TestDue` (the row 3 s after) |
| Failed | the incident part dropped | `Runs.TestFailed` |
| Scope | the scope filter dropped (every failure counted) | `Runs.TestScope` |
| Scope | `instance` counted on the online demo | `Runs.TestScope` |
| Not checked | a thrown read recorded as `passed` | `Runs.TestNotChecked` |
| Not checked | the state `timeout` mapped to `unknown` | `Reader.TestFailuresState`, `Runs.TestNotChecked` |
| Window | `from` = `CreatedAt` on every run | `Runs.TestWindow` |
| Stopped meanwhile | the record made with `%OpenId` and `%Save` | `Runs.TestStoppedMeanwhile` |
| AC 2 | the state ignored | `Heartbeat.TestFailingOrders` |
| AC 3 | the sweep filtered to `open` only | `Heartbeat.TestQuietClose`, `Runs.TestQuietSweep` |
| Quiet close | `SuperSession` not set | `Heartbeat.TestQuietClose`, `Runs.TestQuietSweep` |
| AC 4 | `WatchOps` sends no message on stop | `Heartbeat.TestStartAndStop`, `Ops.TestStop` |
| AC 4 (page) | the `stopped` filter removed | `rail-view.test.mjs` |
| AC 5 | `STUB` kept | `Install.Production` |
| AC 5 | `Web.Api` publishes a `check` event | `CodeRules.TestOnlyChecksPublishesCheck` |
| AC 6 | `Current` keeps swallowing the lock error | `Reader.TestFailuresState` |

## Auto Run Result

Status: blocked
Blocking condition: intent gap: Q1 contended path src/ocutalon/cls/OcuTalon/Test/Web/Api.cls (DW-66 makes a check's traceNamespace $Namespace, which breaks the L250 assertion "31|ZZNS" and the L251 assertion of no traceUrl); Q2 contended path web/src/app/rail/rail-view.ts (for "a stopped one leaves", the rail must drop a check whose stop event carries stopped true); Q3 veto window item 5: the finding and reason texts are public-facing and not in the UX or PRD. The recommended answers are in Design Notes (Q1 (a), Q2 (a), Q3 as worded); the spec is written to them and needs only status ready-for-dev once they are ruled.

- Plan stage, 2026-10-26: the spec is fully planned (Code Map, tasks, six ACs, matrix, mutations, verification). The READY standard fails only on "Sufficient": three items need the orchestrator or owner (Rule 11 (c); unattended policy, veto window item 5).
- Read for planning: the epic context (cached, valid), the Story 5.6 block of `epics.md`, AD-1, AD-4, AD-12, AD-15, AD-18, AD-24, AD-26, AD-28 and AD-33, and the Conventions rows. No IRIS call was made and no runtime was started, so there is nothing to tear down.
- The epic context's "(inference)" line (a finding is code-built) is confirmed from the spine's "Tool classification" row (Design Notes).
