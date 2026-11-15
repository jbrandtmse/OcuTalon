---
title: 'Story 23.8: Watch a saved SQL query as a read-only SQL user'
type: 'feature'
created: '2026-11-15'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** An admin can't ask OcuTalon to watch a data condition. FR-33 (step 5, Could) asks for a saved SQL query that runs on a schedule as a SQL user that may only read, and reports when its result changes. Story 36.2 created the `SaveSqlWatch` verb and its `CommandsIn` route to `WatchOps`, but `WatchOps` has no handler, the reader user `OcuTalonSqlReader` that AD-18 names doesn't exist, and `Checks` runs no `sql_query` row.

**Approach:** The Users step creates `OcuTalonSqlReader` (off the online demo only) and a JDBC SQL Gateway loopback connection that logs in as it. `WatchOps` handles `SaveSqlWatch`: it validates the query, runs it once over that connection and saves a `Kind` `sql_query` row of `BackgroundCheck`. On each `Tick`, `Checks` runs the due rows over the same connection. It hashes the result, and when the hash differs from the last run's it sends one untrusted Item. The security overview lists the user and what it can and can't do. Task 0 measures the mechanism first.

## Boundaries & Constraints

**Always:**
- Commands go through `Commands.Submit` → `CommandsIn` → `WatchOps` (AD-1). `WatchOps` is the only writer of `Query` and the only creator and remover of rows. `Checks` writes only the run fields, `ResultHash` among them (AD-18, AD-33).
- Every saved query runs, at save and on schedule, only over the connection `OcuTalonSqlReader`, which logs in as the IRIS user `OcuTalonSqlReader`. It never runs as the production's user or through `%SQL.Statement` in the production job. The single exception is the parse-only `%Prepare` of the save check, which executes nothing.
- The reader's SQL privileges are the guard. A run never filters the stored text before it executes, so a non-SELECT that is stored at the database level reaches IRIS and is refused there.
- A run that fails is `not_checked` with a reason, keeps the previous `ResultHash`, and is never `passed` (AD-28). The first successful run after a save, or after a change to its query, sets the baseline and sends no Item.
- A changed result is one `OcuTalon.Msg.Item`: channel `system`, provenance `untrusted`, Subject the watch's name, and Text the rendered result. When the rendered result is longer than `ITEMMAX`, it is cut and followed by `Tools.Result.Note`, so the Item says that it was cut. The Item goes through `Record` and `SendOwn`, exactly like a source poll's (AD-14, AD-26).
- The reader's password is random and is replaced at every start. It is kept only as the SQL Gateway connection's wallet secret. It never goes into a message, log line, trace, audit text, test output, global or file (AD-19).
- Online demo: the installer creates no reader user, role or connection, and removes any it finds. `WatchOps` refuses every `SaveSqlWatch` with `not_available`, and `Checks` runs no `sql_query` row. Each of these three is pinned by a test.

**Never:**
- No new route, web code, live-event type, catalog key, tool, tool verb or third-party dependency. No edit of `Core/**`, `Web/**`, `web/**`, `Msg/**`, `Mcp/Ops.cls`, `.github/**`, `release/**`, `irislib/`, `irissys/` or the spine.
- The installer grants the reader no SQL privilege (an admin grants SELECT), no OcuTalon role, no escalation role and no `%Service_Native`.
- Never raise the reader's privileges to make a test pass. Never use `%ExecDirectNoPriv` or `checkPriv=0`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Save new | `web_admin`, `save`, CheckRef "", Name "Open orders", `SELECT COUNT(*) FROM T` (granted), 15 | one row: Kind `sql_query`, the admin's SessionRef, `Query`, `IntervalMinutes` 15, DisplayName = Name, `AskedBy`, CreatedAt = NextDueAt = now, `ResultHash` ""; `saved` Ok 1 with Ref; one `CheckChanged` | none |
| Save same name / CheckRef | the session's existing `sql_query` row (name compared case-insensitively, or by Ref) | that row is updated with the same Ref. A changed `Query` sets CreatedAt to now and `ResultHash` to "". A change of the name or interval alone keeps them | none |
| Bad name / interval / too long | Name blank or over 128 chars; interval not 5-1440; Query over 4000 | `bad_name` (`settings.sqlBadName`), `bad_interval`, `too_long`; Ok 0; no row, no connection | none |
| Not one SELECT | empty, `UPDATE T SET …`, `SELECT 1; DELETE FROM T`, DDL, `CALL …` | `not_select` Ok 0; no connection opened; nothing saved | parse error → `not_select` |
| Reader can't run it | SELECT on an ungranted table | `denied` Ok 0; nothing saved | SQLCODE -99 (Task 0 confirms) |
| Other failure at save | bad column; over `QUERYSECONDS`; connection refused or missing | `query_failed` / `timeout` / `no_reader`, Ok 0; nothing saved | no detail of the error in the answer |
| Remove | `remove` with the session's own Ref | row deleted, `removed`, one `CheckChanged` with stopped true | another session's Ref, or not a `sql_query` row → `not_found` Ok 0 |
| Online demo | flag on, any `SaveSqlWatch` | `not_available` (`settings.sqlOffOnDemo`); zero connection calls; nothing saved | none |
| First run | due row, `ResultHash` "" | `passed`; `ResultHash` set; no Item | none |
| Unchanged / changed | same rows in another order / a value changed | `passed`, no Item / `passed`, one Item, `ResultHash` replaced | none |
| Run refused | stored `Query` changed to INSERT, UPDATE, DELETE, CREATE/ALTER/DROP TABLE or an ungranted SELECT | `not_checked`, finding `REASONSQLDENIED`; `ResultHash` kept; no Item; data and table unchanged | none |
| Run fails | timeout / connection fails / other SQL error | `not_checked` with `REASONTIMEOUT` / `REASONSQLCONNECT` / `REASONREAD` | one redacted warning (`LOGSQL`) |
| Long result | rendered text over `ITEMMAX`, or over `MAXROWS` rows | Item Text cut and ended by `Tools.Result.Note`; hash covers the rows read plus a "more" marker | none |
| Stopped meanwhile | row deleted mid-run | nothing recorded, sent or published | none |
| Online demo run | flag on, a `sql_query` row exists | nothing run, recorded or sent | none |

</intent-contract>

## Code Map

All paths are under `src/ocutalon/cls/OcuTalon/` unless they start with `docs/`, `docker/` or `ci/`.

- `Msg/Command/SaveSqlWatch.cls` (Lane B, read only): `Action`(16) `CheckRef`(22) `Name`(128) `Query`(4000) `IntervalMinutes`. `Core/CommandsIn.cls:379` routes it from `web_admin` only. An error from the owner other than 5003 → `failed` (140-144). No edit.
- `Watch/Ops.cls` (contended, Lane D): `MessageMap` (83-93) has only StartWatch/StopWatch. `FIELDS` (76). `OnStart` (96-140) and `OnStop` (143-176) show the pattern. `SetSource` (239-277) is the natural-key upsert sibling. `RemoveSource` (281-308), `Changed` (336-354), `RefOf` (365-379), `Lock` (382), `Answer` (389).
- `Data/BackgroundCheck.cls`: columns through `IntervalMinutes` (storage Value 19). Trigger `RecordRun` (69-72) writes `CheckRun` when `LastRunAt` changes. Default table `OcuTalon_Data.BackgroundCheck`.
- `Checks/Process.cls` (contended, Lane D): the `Tick` order is at 231-304, and the hook goes after the `RunSources` Try (271-275). `DueOf` (896). `Record(row, tickAt, runAt, result, finding, reported, items, keep)` (629-650). `SendOwn` (412). The source-poll block (1002-1333) is the sibling: `RunSources`, `PollsOff` (1064), `PollSource` (the interval `UPDATE NextDueAt` at 1097-1100), `RecordSource` (1264), `SourceItem` (1323). `REASON*` (166-174), `LOGDUE`.
- `Checks/Coverage.cls` (contended, Lane D): `isSource` at 322 is the only interval-aware rule. Without it, a row that runs every N > 3 minutes reads `missed`. `ReasonOf` (613) maps an unknown finding to `error`. `EntryOf` (469) gives a non-production row its DisplayName.
- `Mcp/Proxy.cls:81` `AnswerHash(text)`: SHA-256 as 64 hex characters (reuse). `Tools/Result.cls:74` `Note(shown, total)` (reuse).
- `Watch/Reader.cls:181` `OnlineDemo()`: the run-time flag.
- `Install/Step/Users.cls`: `Accounts` (89-121) reads `Data.Public.Settings.Get("onlineDemo")` at 91. `EnsureService` (316-331) and `NewPassword` (334-337) are the siblings. `Disable` (469). The class description is at 1-27.
- `Install/Step/Roles.cls:33` `SQLREADER` = "OcuTalonSqlReader" is already refused by `Assign`/`Refusal` (56). The `ASSIGNABLE` allow-list (30) already excludes any reader role. No edit.
- `Install/SecurityOverview.cls`: `Model()` (83), `ServiceUser()` (318), `PrivilegesText` (406-440), with its `### Service user` table. Fixed sentences are parameters (29-44) and must be ASCII (`NonAscii` 369). `docs/security-overview.md` is regenerated, never hand-edited, by `docker/tests/test-security-overview.sh --write`.
- Tests to copy:
  - `Test/Checks/Queues.cls` (`Host`/`Owner`/`Row`/`Tick` 544-570) and `QueueProbe.cls` (KIND override, `Only`, `^||ChecksProbe` seams).
  - `Test/Checks/Probe.cls:176/289` (`SendFinding` capture, `FindingItems`).
  - `Test/Mcp/SourceRun.cls` (`Hash` 821; the cut assertion 223).
  - `Test/Watch/Ops.cls` and `OpsProbe` (`Changes`).
  - `Test/Watch/Case.cls` (`SetOnlineDemo`).
  - `Test/Data/Fixture.cls:99` (`Check`).
  - `Test/Install/Users.cls`; `Test/Install/RolesAssign.cls:223` (`$SYSTEM.Security.Login` in a job).
- Pins that change:
  - `Test/Data/Tables.cls` 557-583 (the BackgroundCheck props and indexes);
  - `Test/Contract/Ac.cls:290`;
  - `docker/tests/test-storage.sh`;
  - `Test/Install/SecurityOverview.cls` (`TestDemoOnlyGrantsListed` 382-385, `TestPrivilegesMatchSecurityRecords` 648-679);
  - `Test/Install/Registry.cls` `TestEveryRole` 729-763 (account list 753).
- Pins that stay:
  - `Test/Core/CommandsRouting.cls` 164-170 (SaveSqlWatch refused from every origin but `web_admin`);
  - `Test/Agent/Runners.cls:323` `TestToolInventory` and `Test/Bridge/CodeRules.cls:968` `ToolCodeClean` (no tool runs data-changing SQL).
- IRIS APIs (reference: `irissys/Security/Users.cls`):
  - `Create` :354, `Modify` :570, `Delete` :383, `Exists` :405;
  - `irislib/%SYSTEM/SQL/Security.cls` `GrantPrivilege` :130, `RevokePrivilege` :566;
  - `irislib/%Library/SQLConnection.cls` (saved connection; `UpdateSecret` :98 puts the credentials into the wallet as `%SQLGateway.<name>`);
  - `irislib/%XDBC/Gateway/Connection.cls:90` `GetConnection`;
  - `irislib/%SQL/StatementMetadata.cls:25` (`statementType` 1 = SELECT);
  - `irislib/%SYSTEM/SQL/Util.cls:899` (SQL security);
  - `irislib/%SQL/Agent.cls:89` (privilege → SQLCODE -99).
- Measured on slot B, read only, 2026-11-15:
  - Build 154 (ARM). `/usr/bin/java` and `dev/java/lib/1.8/intersystems-jdbc-3.11.0.jar` are present.
  - `%Service_Bindings` is enabled with password authentication. `SQLSecurity` is 1, and `^%SYS("SSPort")` is 1972.
  - `%Service_SQL` has public U. `%Service_Native` and `%DB_OCUTALON_DATA`/`_CODE` have no public permission.
  - OCUTALON's globals are in `OCUTALON_DATA`, its routines in `OCUTALON_CODE`.
  - The `%SQL` role holds only `%Service_SQL:U`. `%Net.DB.DataSource` and `%Library.SQLGatewayConnection` exist.
  - An embedded-Python import failed through the MCP endpoint (HTTP 500), so Python is not used.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0 (implement, first; a fresh lane-B throwaway only):** before writing product code, write `Test/Checks/SqlTask0.cls`. On a throwaway it creates a fixture user `zzSqlTask0` and the role the design names (`%DB_OCUTALON_DATA:R` only), a JDBC `%Library.SQLConnection` `zzSqlTask0` (URL `jdbc:IRIS://127.0.0.1:<^%SYS("SSPort")>/OCUTALON`) and fixture tables. It removes them all at the end. Run it with `ci/iris.sh class`, and record each result under `## Verification › Task 0` and in `_bmad-output/implementation-artifacts/evidence/23-8-task0-sql-reader.md`:
  - (a) First and second `%XDBC.Gateway` connect times, and a granted SELECT.
  - (b) For each of INSERT, UPDATE, DELETE, CREATE TABLE, ALTER TABLE, DROP TABLE and a SELECT of an ungranted table: the error (SQLCODE, SQLSTATE), and the table's rows and existence unchanged afterwards.
  - (c) The same SELECT with no role at all (expected: refused, which confirms deviation D1), and whether `%DB_OCUTALON_CODE:R` is also needed.
  - (d) Whether `SELECT 1; DELETE …` is refused at `%Prepare`, and the `statementType` of SELECT, INSERT, DDL and CALL.
  - (e) Where the connection definition is stored, that its `pwd` property holds no clear password after the save, and that the instance's password policy accepts the generated password's length.
  - (f) The `%Service_CallIn` public permission.

  If the JDBC connection cannot be made on the base image, or any statement in (b) succeeds or changes data, HALT with status `blocked` and an `intent gap` that names the measurement. Do not switch mechanism: the recommended fallback, a Native API loopback with its own password store, needs a Planner ruling. After the measurement, delete `SqlTask0.cls`. The evidence file stays.
- [ ] `Data/BackgroundCheck.cls` -- append `Property Query As %String(MAXLEN = 4000)` and `Property ResultHash As %String(MAXLEN = 64)`, both commented "a sql_query row's (Story 23.8); empty for every other kind", as storage Values 20 and 21. No other edit.
- [ ] `Checks/SqlReader.cls` (new, Lane A) -- the one class that talks to the reader:
  - parameters `CONNECTION` = `USER` = "OcuTalonSqlReader", `ROLE` = "OcuTalonSqlReaderRole", `QUERYSECONDS` 20, `CONNECTSECONDS` 10, `MAXROWS` 1000, `ITEMMAX` 4000;
  - `IsSelect(query) As %Boolean`: a parse-only `%SQL.Statement.%Prepare` in OCUTALON with `%Metadata.statementType` = 1 and exactly one statement, using Task 0 (d)'s rule;
  - `Run(query, Output columns As %DynamicArray, Output rows As %DynamicArray, Output more As %Boolean) As %String`: one connection per call, closed in every path, with the query timeout. It answers `passed`, `denied` (Task 0's privilege code), `timeout`, `unreachable` (connect failed, or no connection definition) or `error`;
  - `Hash(columns, rows, more)`: each row's values joined by `$C(9)`, the row lines sorted, the column line first, a `more` line when cut, through `Mcp.Proxy.AnswerHash`;
  - `Text(columns, rows, more)`: tab-separated lines, cut at `ITEMMAX` with a line break and `Tools.Result.Note(shown, total)`, or `unknown` as the total when `more` is set;
  - `Ensure() As %Status` and `Remove() As %Status`: the user, role and connection (see the Users step).

  No other class opens a connection as the reader.
- [ ] `Install/Step/Users.cls` -- `Accounts`: with the flag off, call `##class(OcuTalon.Checks.SqlReader).Ensure()`; with it on, call `Remove()`. `Ensure` (structural, at every start), in `%SYS`:
  - the role `ROLE`, holding exactly the resources Task 0 measured (expected `%DB_OCUTALON_DATA:R`);
  - the user `USER`: FullName "OcuTalon SQL-watch user", Roles exactly `ROLE`, no EscalationRoles, Enabled 1, NameSpace OCUTALON, ChangePassword 0, PasswordNeverExpires 1, a new `NewPassword()` at every start;
  - then the connection `CONNECTION` with that user and password, saved so that IRIS keeps them as its wallet secret.

  `Remove` deletes the connection, user and role when they exist. Extend `EnsureService`'s pattern rather than copying it; `NewPassword` is reused. Update the class description (one bullet).
- [ ] `Watch/Ops.cls` -- contended:
  - (a) one `MapItem` `OcuTalon.Msg.Command.SaveSqlWatch` → `OnSaveSql`;
  - (b) `FIELDS` gains `,Query,ResultHash`;
  - (c) an appended block with `SQLKIND` = "sql_query", the `MESSAGESQL*` parameters (texts under Design Notes › For the Planner's gate) and `OnSaveSql(request, Output response)`.

  `OnSaveSql` works in this order:
  1. online demo → `not_available`;
  2. Session row → else `no_session`;
  3. Action → `bad_action`;
  4. for `remove`: the session's own `sql_query` Ref → delete, `removed` and `Changed(…, stopped 1, …)`, else `not_found`;
  5. for `save`: Name, interval and length checks; `IsSelect`; `Run`, with each outcome → its answer;
  6. under `Lock`: an upsert by natural key (SessionRef, `sql_query`, Name in any letter case) or by CheckRef (the session's own, else `not_found`), like `SetSource`, with the Query-change reset;
  7. `saved` with the Ref, then `Changed`.

  An exception → `failed` with `MESSAGEFAILED`. The query, the result and errors never enter the answer. Seams for tests: `SqlOff()`, `SqlCheck(query, .outcome)`.
- [ ] `Checks/Process.cls` -- contended:
  - (a) one Try block after the `RunSources` Try in `Tick`: `Do ..RunSqlWatches(tickAt)`, with a `LOGDUE` warning on an exception;
  - (b) an appended block, before `Storage`, with:
    - `SQLKIND`, `SQLPERTICK` 2, `REASONSQLDENIED`, `REASONSQLCONNECT`, `LOGSQL`;
    - `RunSqlWatches(tickAt)`: nothing when `SqlOff()` (`Watch.Reader.OnlineDemo()`). Otherwise `DueOf(tickAt, SQLKIND)`, oldest `NextDueAt` first, at most `SQLPERTICK` rows, each in its own Try (`LOGSQL`);
    - `RunSql(row, tickAt)`:
      1. `UPDATE NextDueAt` = tick + `IntervalMinutes`×60 (as `PollSource`; row count 0 → quit);
      2. read `Query` and `ResultHash` by Ref;
      3. seam `SqlRead(query, .columns, .rows, .more)` → `SqlReader.Run`;
      4. passed: a baseline when `ResultHash` is "" or `LastRunAt` is empty or before `CreatedAt`, else one Item when the hash differs. `UPDATE ResultHash` (row count 0 → quit), then `Record(row, "", runAt, "passed", "", "", items, 1)`;
      5. not passed: `Record(…, "not_checked", <reason>, "", empty, 1)`, with `ResultHash` untouched;
    - `SqlItem(row, text)`, copying `SourceItem`'s fields.

    Extends `DueOf`/`Record`/`SendOwn`; copies nothing.
- [ ] `Checks/Coverage.cls` -- contended, one in-place line (322): the interval-aware rule also covers `Kind` `sql_query` with `IntervalMinutes` > 0. `Test.Digest.Coverage` gets a `sql_query` row case.
- [ ] `Install/SecurityOverview.cls` -- `Model()` gains `sqlReader` (`{user, roles, grants: [{resource, permission}], login: "password, SQL only", demo: "absent"}`, read from `Checks.SqlReader` parameters). `PrivilegesText` appends a `### SQL-watch user` table and `SQLREADERSTATEMENT` after `### Service user`. Then regenerate `docs/security-overview.md` with `bash docker/tests/test-security-overview.sh --write` (the lane-B variables) and commit only its generated region.
- [ ] Tests (update every pin under Shared surfaces first, then add):
  - `Test/Checks/SqlProbe.cls`: a new probe that extends `Test.Checks.Probe`, with `SQLKIND` zzsql, `Only`, and `SqlRead`/`SqlOff` from `^||ChecksProbe`.
  - `Test/Checks/SqlWatch.cls` (new, warm): the run rows of the matrix through `SqlProbe`, the cut Item, order-insensitivity, the per-tick cap, `NextDueAt` = tick + interval, stopped meanwhile, and online demo with zero `SqlRead` calls.
  - `Test/Checks/SqlReader.cls` (new, fresh throwaway only, guarded like `Test.Checks.QueueBacklog`): AC4 and AC5 against the installed reader, with fixture tables in schema `OcuTalon_Test`, a grant and revoke, and a drop at the end.
  - `Test/Watch/SqlWatch.cls` (new, warm, through the real `CommandsIn` with `SqlCheck` seams): every save and remove row of the matrix, `CheckChanged`, another session's Ref, the online demo (no row, zero `SqlCheck` calls), and the leak check (AC7).
  - `Test/Install/SqlReader.cls` (new, fresh throwaway only): AC1 and AC6.
  - `Test/Install/SecurityOverview.cls`: the model and `TestPrivilegesMatchSecurityRecords` cover the reader.
  - `Test/Data/Tables.cls`, `Test/Contract/Ac.cls`, `Test/Digest/Coverage.cls`.

**Acceptance Criteria:**
- AC1: Given a local install, when the Users step runs, then `OcuTalonSqlReader` exists, enabled, with exactly the role `OcuTalonSqlReaderRole`, no escalation roles, no OcuTalon role and no SQL privilege. The role holds exactly the resources Task 0 measured and nothing forbidden. A second run gives a different password hash and the same roles. The connection `OcuTalonSqlReader` logs in as it. (`Test.Install.SqlReader`.)
- AC2 (Integration): Given an admin's session, when a test submits `SaveSqlWatch` from `web_admin` through `Commands.Submit` with a granted SELECT and the next two Ticks run with the table changed between them, then `WatchOps` saves one `sql_query` row, the first Tick sets the baseline with no Item, and the second sends exactly one untrusted Item to `Intake` with the watch's name as Subject. (`Test.Checks.SqlReader:TestSavedQueryEndToEnd`.)
- AC3: Given a `SaveSqlWatch` with a statement other than one SELECT, an ungranted table, a bad name, a bad interval or a query that fails, when `WatchOps` handles it, then it answers the matrix outcome with Ok 0 and its plain message, and no row is written. (`Test.Watch.SqlWatch`; `denied` live in `Test.Checks.SqlReader`.)
- AC4: Given a saved row whose `Query` is changed by SQL `UPDATE` to an INSERT, UPDATE, DELETE, CREATE TABLE, ALTER TABLE or DROP TABLE, or to a SELECT of an ungranted table, when `Checks` runs it, then each statement fails with the privilege error Task 0 recorded, every fixture table keeps its rows and definition, the row and its `CheckRun` are `not_checked` with `REASONSQLDENIED`, and no Item is sent. (`Test.Checks.SqlReader:TestRefusedStatements`.)
- AC5: Given the tool inventory, when `Test.Agent.Runners:TestToolInventory` and `Test.Bridge.CodeRules:TestToolCodeScan` run, then both pass unchanged and no tool class references `OcuTalon.Checks.SqlReader`. (Existing tests plus one assertion in `Test.Checks.SqlReader`.)
- AC6 (online demo): Given the online-demo flag on, when the Users step runs, then no reader user, role or connection exists, and an existing one is removed. When an admin-origin `SaveSqlWatch` arrives, it answers `not_available` with zero connection calls. When a `sql_query` row exists and a Tick runs, nothing is run, recorded or sent. (`Test.Install.SqlReader:TestOnlineDemoHasNoReader`, `Test.Watch.SqlWatch:TestOnlineDemoRefused`, `Test.Checks.SqlWatch:TestOnlineDemoRunsNothing`.)
- AC7: Given installs, saves and runs, when the test scans the messages of the save's session, `^OcuTalonP.Check`, the production's event log since the test began and the connection's properties, then the reader's password appears nowhere. (`Test.Install.SqlReader:TestPasswordNeverStored`.)
- AC8: Given the security overview, when it is regenerated, then `### SQL-watch user` lists the user, its role and grants, its login and `SQLREADERSTATEMENT`, and `TestPrivilegesMatchSecurityRecords` finds the security records equal to the table. (`Test.Install.SecurityOverview`; `live:security-overview` in CI.)
- AC9: Given a `sql_query` row with `IntervalMinutes` 15 that ran on time, when the digest coverage is built, then it is not `missed` or `stale`. (`Test.Digest.Coverage`.)

## Spec Change Log

- 2026-11-15 ~20:45Z (lead, Planner gate): APPROVED with conditions (extended Task 0 hard gate a-d; SELECT results untrusted); D1-D3 accepted; AD-18/AD-24 amended in the spine; contention granted; public text approved verbatim.

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-1: the command path.
- AD-3: `%SYS` work in the installer; the private database stays unreadable.
- AD-14: untrusted Items.
- AD-17: no new audit entry; the command is a traced message.
- AD-18: the `sql_query` row and reader mechanism.
- AD-19: the secret's home is the IRIS Wallet, through the SQL Gateway connection.
- AD-22: throwaways.
- AD-23: an installer step, structural.
- AD-24: users, roles, the overview, `Roles.Assign` refusal.
- AD-25: no SQL client on the demo.
- AD-26: trace sessions.
- AD-27: rows aren't purged; `CheckRun` ages out.
- AD-28: not checked is never passed.
- AD-29: Lane B's verb and route are untouched.
- AD-32: WatchOps answers are plain sentences, not catalog keys.
- AD-33: WatchOps creates, Checks records.

**Consumes:** Story 36.2's `SaveSqlWatch` and its `CommandsIn` row; Story 36.1's names (AD-18); Epic 14's overview generator; Epic 22's `IntervalMinutes`; the run machinery of Stories 23.7 and 22.11 (`DueOf`, `Record`, `SendOwn`). **Consumed-by:** Story 24.2 submits `SaveSqlWatch` and lists the rows (schedule, last run, last result). Once AC4 is green, Story 24.2 may ship the read-only claim the Planner held back from `settings.sqlHelp` (V7 condition). Integration ACs: AC2, with `Checks` reading the row `WatchOps` wrote.

**Extend, don't copy:**
- `RunSqlWatches`/`RunSql` extend the source-poll siblings (`RunSources`, `PollSource`'s interval update, `RecordSource`'s baseline rule, `SourceItem`'s fields) through the shared `DueOf`/`Record`.
- `OnSaveSql`'s upsert follows `SetSource`.
- `Ensure` follows `EnsureService` and reuses `NewPassword`.
- The hash reuses `Mcp.Proxy.AnswerHash` and the cut reuses `Tools.Result.Note`.
- The SQL code sits in one new class because both `WatchOps` and `Checks` need it.

**Decided in-stage:**
- The online demo is OFF, which resolves the epic context's gap. AD-25 says nothing on the demo host holds a SQL client, and the demo's OCUTALON tables hold visitor sessions, so read-only over them is not safe.
- A changed result leaves the row `passed` (as a source poll's new answer does), so no new finding text is needed.
- The hash ignores row order, so an unordered query doesn't flap.
- At most 1,000 rows are read, and a change past them is not seen.
- The interval runs from 5 to 1,440 minutes, as for source polls.
- At most 2 rows run per Tick, and each query waits at most 20 s.
- A changed query starts a new baseline.
- The password is replaced at every start.
- The connection to OCUTALON uses `127.0.0.1` and `^%SYS("SSPort")`.
- `check_status` and the rail are unchanged. The rail renders any kind's row with its title, and source rows are also left out of `check_status`.
- `EndSession` leaves the rows, as it does source rows. An admin session is durable (AD-4).
- Ledger: none owned (`LEDGER slice` empty, `owned_ledger=0`).

### Planner rulings, 2026-11-15 (binding; prompts/story-238-rulings-20261115.md "23.8")
- APPROVED, own installs only; nothing of it exists on the online demo. Vetoes 1-6 APPROVED.
- **Task 0 is an extended HARD GATE.** Besides refusing INSERT, UPDATE, DELETE, DDL and a SELECT on an ungranted table (each changing nothing), Task 0 must prove, on a fresh lane-B throwaway:
  - (a) Sessions: `OcuTalonSqlReader` can open no session except SQL over one service: no Terminal, no Object or other binding, no CSP or web application, no Portal. Name the exact service it logs in through, pin it with a test, and confirm whether that service is `%Service_SQL` or `%Service_Bindings` on this build.
  - (b) Resources: it holds no `%Development`, `%Admin_*`, `%Ens_*` or `%DB_*` resource other than `%DB_OCUTALON_DATA:R`.
  - (c) Image: the JDBC loopback works on the shipped image as it stands. If it needs Java or any component not already in the image: STOP (HALT `blocked`, `intent gap: Task 0 (c) ...`). Never add a dependency.
  - (d) Password: after a start, grep for the password in the CPF, the audit log, messages, the trace and the logs: it never appears.
  Any failure of (a)-(d) or of the refusals is an `intent gap` HALT with the evidence; never work around it.
- Untrusted content: SELECT results, and any Items they become, are untrusted content, exactly as a source's (marked, cut, never instructions).
- D1, D2, D3 ACCEPTED; AD-18 and AD-24 amended in the spine by the lead (markers 2026-11-15, Story 23.8).
- Contention GRANTED under the plain-union rule: Checks/Process (the Try block in Tick plus the appended block), Checks/Coverage.cls:322 (the change in place), Watch/Ops (MapItem, FIELDS, the appended block), BackgroundCheck (the two appended columns).
- Public text APPROVED verbatim: the 11 WatchOps answers, the 2 not-checked reasons, the security-overview heading, table and SQLREADERSTATEMENT; settings.sqlOffOnDemo and settings.sqlBadName reused.

### For the Planner's gate

**(a) Veto items, each with its online-demo behaviour:**
1. A new IRIS user `OcuTalonSqlReader`: FullName "OcuTalon SQL-watch user", enabled with a password login, NameSpace OCUTALON, no OcuTalon role, no escalation role. The installer grants it no SQL privilege; an admin grants SELECT per table in the Management Portal or with SQL `GRANT`. `Roles.Assign` already refuses it. *Demo:* never created, and removed if found.
2. A new role `OcuTalonSqlReaderRole`, held only by that user, with exactly `%DB_OCUTALON_DATA:R`, plus `%DB_OCUTALON_CODE:R` only if Task 0 shows that SQL needs it. Login uses `%Service_SQL`, which already has public U, so the role holds no service. It is not composed from area `Grants()`, can't be assigned, and holds nothing on the forbidden list. *Demo:* absent. This is deviation D1.
3. Credential: a random password, replaced at every start, set on the user and saved in the SQL Gateway connection `OcuTalonSqlReader`. IRIS keeps it as the wallet secret `%SQLGateway.OcuTalonSqlReader` (SQL usage, readable only by IRIS's gateway classes). It is never printed, logged, traced or audited (AC7). *Demo:* absent.
4. The separate connection: JDBC through the SQL Gateway, a loopback to `127.0.0.1:<superserver port>/OCUTALON`, one connection per run or save, with a 10 s connect and a 20 s query limit. It needs the JVM that the base image has. *Demo:* no connection definition exists, so nothing connects.
5. Stored data: `BackgroundCheck` gains `Query` (4000) and `ResultHash` (64), the columns AD-18 promised. The admin's query text lives in the row and in the traced `SaveSqlWatch` message, which the trace role can see. *Demo:* no row can be saved.
6. Routes: none new. Story 24.2's `sql-watches` route stays 24.2's.

**(b) PUBLIC TEXT** (every user-facing string, verbatim):
- Approved (Story 36.2, Planner ruling V7, EXPERIENCE.md Message Catalog), reused verbatim in `Watch/Ops.cls`:
  - `MESSAGESQLOFFDEMO` = `settings.sqlOffOnDemo`: "SQL query watches are off on the online demo. They work on your own install."
  - `MESSAGESQLBADNAME` = `settings.sqlBadName`: "Enter a name of 1 to 128 characters. Nothing was changed."
- NEW, `Watch/Ops.cls`. These are WatchOps answers, which Story 24.2 shows as field errors:
  - `MESSAGESQLSAVED`: "The SQL query watch was saved."
  - `MESSAGESQLREMOVED`: "The SQL query watch was removed."
  - `MESSAGESQLNOTFOUND`: "That SQL query watch isn't one of yours, so nothing was changed."
  - `MESSAGESQLBADACTION`: "The command was neither save nor remove, so nothing was changed."
  - `MESSAGESQLBADMINUTES`: "Enter a whole number of minutes from 5 to 1440. Nothing was saved."
  - `MESSAGESQLTOOLONG`: "The query is longer than 4,000 characters. Nothing was saved."
  - `MESSAGESQLNOTSELECT`: "The query must be one SELECT statement. Nothing was saved."
  - `MESSAGESQLDENIED`: "OcuTalon's read-only SQL user may not run this query. An admin must grant it SELECT on each table the query reads. Nothing was saved."
  - `MESSAGESQLFAILED`: "The query didn't run as OcuTalon's read-only SQL user. Check the query and try again. Nothing was saved."
  - `MESSAGESQLTIMEOUT`: "The query took longer than 20 seconds. Nothing was saved."
  - `MESSAGESQLNOREADER`: "This install can't connect as OcuTalon's read-only SQL user, so SQL query watches can't run here. Nothing was saved."
- NEW, `Checks/Process.cls`. These are the row's not-checked findings, shown in the rail and the digest:
  - `REASONSQLDENIED`: "Its SQL user may not run the query"
  - `REASONSQLCONNECT`: "Couldn't connect as the read-only SQL user"
  - Reused: `REASONTIMEOUT` "No answer in time" and `REASONREAD` "Couldn't be read".
- NEW, `Install/SecurityOverview.cls` → `docs/security-overview.md`:
  - The heading "### SQL-watch user".
  - The table header "| User | Role | Resource | Permission | Login |".
  - The row: `OcuTalonSqlReader` | `OcuTalonSqlReaderRole` | `%DB_OCUTALON_DATA` | R | password, SQL only.
  - `SQLREADERSTATEMENT`: "OcuTalon runs each saved SQL query watch as `OcuTalonSqlReader`, over its own SQL connection to OCUTALON, never as the production's user. It holds no OcuTalon role, and the installer grants it no SQL privilege: it can run a `SELECT` only on the tables an admin grants it. It can't insert, update or delete rows, create, change or drop tables, or read a table it wasn't granted (tested). Its one role lets it read OCUTALON's data database, which SQL needs, and not OcuTalon's private database. Its password is random, replaced at every start and kept only in IRIS's SQL Gateway connection `OcuTalonSqlReader`; it is never shown. The online demo has no SQL-watch user and no SQL query watches."
- Not user-facing: the Item Text is the query's own result, and the cut note is the existing `Tools.Result.CUTNOTE`, which is text for the model.

**(c) Contended-file overlaps** (approval as plain unions is asked for, with a diff re-check against `origin/OCT-epic22` before implement):
- Lane D (Epic 22):
  - `Checks/Process.cls`: one Try block in `Tick`, plus an appended block.
  - `Checks/Coverage.cls`: one in-place line (322).
  - `Watch/Ops.cls`: one `MapItem` and the `FIELDS` value, in place, plus an appended block.
  - `Data/BackgroundCheck.cls`: two properties and two storage Values, appended.
  - New files in its folders: `Checks/SqlReader.cls`, `Test/Checks/Sql*.cls`, `Test/Watch/SqlWatch.cls`.
- Lane C (Epic 21) and Lane A (Epic 25): none.
- Epic 23's own footprint: `Install/Step/Users.cls`.
- Footprint extensions:
  - `Install/SecurityOverview.cls`, `docs/security-overview.md` (Lane A docs);
  - `Test/Data/Tables.cls`, `Test/Contract/Ac.cls` (pins only);
  - `docker/tests/test-storage.sh`, only if it pins the column list.

**(d) Deviations, with recommendations:**
- **D1 (AC1 / AD-18 wording):** "no privilege beyond SQL SELECT" can't hold as worded. On slot B, `%DB_OCUTALON_DATA` and `%DB_OCUTALON_CODE` have no public permission, so a user with no role cannot read any table through SQL; Task 0 (c) confirms this on a throwaway. *Recommend:* accept one reader-only role with database Read, which SQL needs. SQL privileges still decide which tables it can read, and the private database stays unreadable. Amend AD-18's sentence to: "holds no OcuTalon role, only `OcuTalonSqlReaderRole` (Read on OCUTALON's data database, which SQL needs) and the SQL `SELECT` an admin grants", and add the role to AD-24's list.
- **D2 (AD-18's delegated mechanism):** a JDBC SQL Gateway loopback, with the password kept as the connection's wallet secret and replaced at every start. *Recommend:* write that into AD-18 at the ruling (Rule 20). Implement does not edit the spine.
- **D3 (the epic context's gap):** the online demo is OFF, as above. *Recommend:* add "On the online demo the installer creates no reader and `Checks` runs no `sql_query` row" to AD-18.

**(e) CI:** no new live unit, group or workflow, and no `release/**` or `.github/**` hunk. The new classes join existing areas:
- `Test.Checks.*` → `shard:lane-a@rest` (`shards-2`);
- `Test.Watch.SqlWatch` → `shard:lane-a@Watch` (`shards-8`);
- `Test.Install.SqlReader` → `shard:lane-a@Install,Digest,Eval` (`shards`).

The JDBC first connect adds Task 0's measured seconds to those jobs (inference until measured; the lead moves a piece if a group passes its cap). `live:security-overview` (`shards-5`) checks the regenerated document.

## Verification

Run from the epic-23 worktree root (`git rev-parse --show-toplevel`), one command per call with `timeout: 600000`, each sized to about 150 s, never two test runs in one message, and never `run_in_background` or `Monitor`. Prefix every `ci/` and `docker/tests/` call with:

`OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`

Tags: fresh `e23b8i`, warm `e23b8iw`. At the end run `ci/warm.sh down`, then `ci/iris.sh teardown` with `e23b8i`. Every IRIS MCP call names `server` `ocutalon-slot-b` and `namespace` `OCUTALON`; the slot is used for reads only. Every security or destructive test runs on a lane-B throwaway.

**Shared surfaces:**
- the `BackgroundCheck` column list and storage (`Test.Data.Tables`, `Test.Contract.Ac`, `test-storage.sh`, `Watch.Ops` `FIELDS`);
- WatchOps' `MessageMap`;
- the BackgroundCheck kinds (`Coverage` 322; the probes' kinds);
- the security overview's users and roles lists (`Test.Install.SecurityOverview`, `docs/security-overview.md`);
- the forbidden-list and every-role tests (`Test.Install.Registry` `TestEveryRole`);
- the managed accounts (`Test.Install.RolesAssign`, `Test.Web.RolesApi`; unchanged);
- the command verbs (`Test.Core.CommandsRouting`, `Test.Msg.Contracts`; unchanged);
- the tool inventory (`Test.Agent.Runners`, `Test.Bridge.CodeRules`; unchanged);
- the stored-table registry (`Test.Data.Tables`; no new table).

Every test added or changed passes on a fresh environment, in either order.

**Task 0:** (record here, and in `_bmad-output/implementation-artifacts/evidence/23-8-task0-sql-reader.md`)

**Commands:**
- (loop) `OCUTALON_RUN_TAG=e23b8i ci/iris.sh class OcuTalon.Test.Checks.SqlTask0`, Task 0 only, once per Task 0 iteration. Expected: the measurements are printed.
- (loop) `OCUTALON_RUN_TAG=e23b8iw ci/warm.sh up`, re-upped (`down`, then `up`) after any change to `Checks/Process.cls`, `Watch/Ops.cls` or `Checks/SqlReader.cls`. Then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23b8iw ci/iris.sh class <Class>`, one call each, for:
  - `OcuTalon.Test.Checks.SqlWatch`
  - `OcuTalon.Test.Watch.SqlWatch`
  - `OcuTalon.Test.Watch.Ops`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Checks.Queues`
  - `OcuTalon.Test.Digest.Coverage`
  - `OcuTalon.Test.Data.Tables`
  - `OcuTalon.Test.Contract.Ac`
  - `OcuTalon.Test.Install.SecurityOverview`
  - `OcuTalon.Test.Install.Registry`
  - `OcuTalon.Test.Install.RolesAssign`
  - `OcuTalon.Test.Core.CommandsRouting`
  - `OcuTalon.Test.Msg.Contracts`
  - `OcuTalon.Test.Bridge.CodeRules`

  Expected: each `CLASS ... passed`.
- (loop) `OCUTALON_RUN_TAG=e23b8i ci/iris.sh class OcuTalon.Test.Checks.SqlReader` (fresh; security fixtures). Expected: passed.
- (loop) `OCUTALON_RUN_TAG=e23b8i ci/iris.sh class OcuTalon.Test.Install.SqlReader` (fresh). Expected: passed.
- (loop) `OCUTALON_RUN_TAG=e23b8i ci/iris.sh class OcuTalon.Test.Install.Users` (fresh). Expected: passed.
- (loop) `bash docker/tests/test-storage.sh`. Expected: pass.
- (once) `bash docker/tests/test-security-overview.sh --write`, then `bash docker/tests/test-security-overview.sh`. Expected: the second prints PASS. If either is moved to the background, poll it in the foreground.
- (once) `bash ci/checks.sh`. Expected: pass.
- Left to CI: `Test.Agent.Runners` (`TestToolInventory`, which needs the running runners), the shards, the install groups (`live:install-start`, `live:install-upgrade`) and the lead's fresh-environment check, forward and `--reverse`.

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:**
- AC1: `Ensure` gives the user `OcuTalonUser` too → `Test.Install.SqlReader`.
- AC2: `RunSql` never sends the Item → `TestSavedQueryEndToEnd`.
- AC3: `OnSaveSql` skips `IsSelect` → `Test.Watch.SqlWatch`.
- AC4: `Run` executes in the production job with `%SQL.Statement` instead of the connection → `TestRefusedStatements`.
- AC5: a tool class calls `SqlReader.Run` → `Test.Checks.SqlReader`'s reference check.
- AC6: `SqlOff` returns 0 → `TestOnlineDemoRunsNothing`.
- AC7: `Ensure` writes the password to a `^OcuTalonP` node → `TestPasswordNeverStored`.
- AC8: the overview's row drops its grant → `TestPrivilegesMatchSecurityRecords`.
- AC9: line 322 reverted → `Test.Digest.Coverage`.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
