---
title: 'Old messages and records are purged on schedule'
type: 'feature'
created: '2026-10-30'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon's databases grow without limit. No area declares the standard purge tasks, so heartbeat and check messages, old Interoperability data, bridge decisions and usage, closed incidents and the AI sessions that rotation (and, from Story 30.1, compaction) leave behind are never deleted. `OcuTalon.Install.Task.Purge` exists, but nothing creates its task, `OcuTalon.Bridge.Purge` does not exist, and no area calls `Watch.IncidentManager.Purge`.

**Approach:** A new Lane A area, `OcuTalon.Install.Step.Retention`, declares in `Tasks()` the three daily 03:00 tasks of AD-27: two standard `Ens.Util.Tasks.Purge` tasks (7 days for `HeartbeatIn` and `Checks`, 90 days for everything else) and the `OcuTalon purge` task (90 days). Its `Purge(daysToKeep)` calls the new `OcuTalon.Bridge.Purge.Run(daysToKeep)`, which keeps decisions and usage for that many days and deletes AI sessions that no conversation link has named for a day. A new `OcuTalon.Install.Step.Watch` area declares the incident purge. The existing Tasks step creates each task once, and the existing purge task reaches both areas through the registry. The day check and UTC cutoff move into one bridge helper, `Bridge.Time.DaysCutoff` (DW-371, Lane A's side).

## Boundaries & Constraints

**Always:**
- Every task runs in namespace `OCUTALON`, and every purge touches only OcuTalon's own data: OCUTALON's Interoperability data, OcuTalon's tables and the AI sessions in OCUTALON. Nothing runs in `OCUORDERS` or any watched production's namespace. This is the owner's rule; a test fails if a task targets another namespace.
- Interoperability data is purged only by the standard `Ens.Util.Tasks.Purge` (AD-27's Prevents line: no hand-written message purge).
- The day counts are task properties, written only when the Tasks step creates a task: `NumberOfDaysToKeep` 7 and 90, and `DaysToKeep` 90. No purge reads `OcuTalon.Data.Setting` (AD-19, AD-27).
- The declared values, exactly:
  - `OcuTalon purge heartbeat and check messages`: class `Ens.Util.Tasks.Purge`, settings `TypesToPurge` `messages`, `NumberOfDaysToKeep` 7, `optionalMessageLimitToConfigItems` `HeartbeatIn,Checks` (no spaces), `KeepIntegrity` 1, `BodiesToo` 1.
  - `OcuTalon purge Interoperability data`: class `Ens.Util.Tasks.Purge`, settings `TypesToPurge` `all`, `NumberOfDaysToKeep` 90, `KeepIntegrity` 1, `BodiesToo` 1.
  - The task named by `OcuTalon.Install.Task.Purge`'s `TaskName` parameter (`OcuTalon purge`): class `OcuTalon.Install.Task.Purge`, settings `DaysToKeep` 90.
  - Every task has the schedule `TimePeriod` 0, `TimePeriodEvery` 1, `DailyFrequency` 0, `DailyStartTime` 10800 (03:00 instance time), `StartDate` today (`+$Horolog`) and `RescheduleOnStart` 1. No declaration sets `NameSpace`, `RunAsUser` or `Suspended`.
- `Bridge.Purge.Run(daysToKeep, now = "")`, where `now` is a UTC time `YYYY-MM-DDThh:mm:ssZ` (default `Bridge.Time.NowUtc()`):
  - It deletes the `Decision` and `Usage` rows whose `RecordedAt` is before the cutoff (`now` moved back `daysToKeep` whole days). A row recorded exactly at the cutoff stays.
  - It deletes an AI session (`%AI.Agent.Session`) only when no `ConversationLink` named it at an earlier run, at least 86,400 s before `now`, and none names it now. Its mark is `^OcuTalonBP.Unlinked(sessionId)` = the UTC time of the first run that found it unlinked (V1). A run clears the mark of a linked session, and the mark of a session that is gone.
  - It never takes the conversation lock and never writes a link. It reads the links' `SessionId` values with one `SELECT` and compares them in ObjectScript.
  - It names no other OcuTalon package (AD-2) and does nothing in any other namespace.
  - The decision, usage and session parts each run whatever an earlier part returned, and their errors are combined into one status.
- `Bridge.Time.DaysCutoff(daysToKeep, caller, .cutoff, now = "")` returns an error status, `<caller> needs a whole number of days, at least 1, not '<first 40 characters>'`, for anything but a whole number of at least 1 (`""`, `0`, `-1`, `1.5`, `abc`, `00`). Otherwise it returns OK, with the cutoff, or with `""` when the cutoff falls before the calendar's first date. Each caller deletes nothing on an error, and nothing older than an empty cutoff.
- `Digest.Data.Item.Purge` keeps its exact behaviour and error text.
- Storage is unchanged: no persistent class, property, index or storage block is added or changed (AD-5).

**Never:**
- Edit a Lane B class (AD-33): `Data.Pairing`, `Data.Time`, `Data.Ownership`, `Install.Step.Core`, `.Web` and `.Schedule`, `Live.Event`, `Data.AddressCounter`, `Test.Schedule.*`.
- Edit a contended file: `Install/Task/Purge.cls`, `Install/Step/Tasks.cls`, `Install/Registry.cls`, `Install/Step.cls` (Epic 15), `Watch/IncidentManager.cls`, `Production.cls` (Epic 9). A mutation in Verification may change one of these temporarily, but it is reverted byte-identically and never committed.
- Let a purge touch the IRIS audit log (tests write their marker entry only through `Bridge.Audit`), or let `Bridge.Purge` write a link or name the link's globals or lock (`^OcuTalonBP.ConvLink*`, `^OcuTalonBP.Conv`).
- Purge `ApprovalRequest`, `Price`, `ModelFamily`, `BackgroundCheck` or `WatchMark` rows: the AC names decisions and usage only.
- Run the Tasks step, a purge or this story's tests on `ocutalon-slot-a`. They run on throwaway stacks only (Rule 21).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 1. First start | a fresh throwaway's after-start runs the Tasks step | each of the three task names exists exactly once, with the declared class, settings and schedule, and `NameSpace` `OCUTALON` | a task that cannot be created fails `STEP Tasks`, naming the Retention area (existing `Tasks.Create`) |
| 2. Second start or upgrade | the Tasks step runs again; one of the three was deleted first (an older version had none) | one of each; the deleted one is recreated as declared, and the other two keep their ids | none |
| 3. Admin change kept | `NumberOfDaysToKeep` 7→10, `DaysToKeep` 90→120 and `DailyStartTime` 10800→7200 changed on the tasks, then the Tasks step runs | the changed values are still there | the test restores the values |
| 4. Own namespace only | OCUORDERS holds a completed message header 92 days old; the three tasks run | every declared task's `NameSpace` is `OCUTALON`; the OCUORDERS header and its body still exist | none |
| 5. 7-day messages | completed headers with bodies: `HeartbeatIn`→`Checks` 9 days and 5 days old, `Checks`→`IncidentManager` 9 days, `WebChatIn`→`Conversation` 9 days | the two 9-day heartbeat and check headers and their bodies are gone; the 5-day one and the `WebChatIn` one are kept | none |
| 6. 90-day all | a header with a body, a completed business-process instance, a rule-log row and an event-log row, each 92 and 88 days old (the 92-day process instance is saved first) | the 92-day rows are gone; the 88-day rows are kept | none |
| 7. OcuTalon purge, through the Task Manager (Integration AC, Rule 1) | the `OcuTalon purge` task's stored `DaysToKeep` set to 60; Decision and Usage rows, an incident closed, and a digest item, each 61 and 59 days old | the Task Manager's run reaches `Bridge.Purge` and every area's `Purge` with 60: the 61-day rows are gone and the 59-day rows are kept | the history row of the run has no error |
| 8. Audit untouched | an OcuTalon audit entry carrying a fresh marker, written before the run | the entry is still found after the three runs (`Test.Bridge.AuditLog.Wait`) | none |
| 9. History reads tables | a 59-day decision whose trace session's headers are 92 days old; an incident closed and noticed 30 days ago whose `Checks` header is 9 days old | the headers are gone; `Data.Ownership.Decision(ref, owner)` and `Data.Ownership.Incident(ref, owner)` still return both rows | none |
| 10. Decisions and usage | `Run(30)`: rows 31 days, 30 days + 1 h, 30 days − 1 h, 29 days and 0 days old; a row exactly at the cutoff | the first two are gone; the other three and the one at the cutoff are kept | none |
| 11. Sessions, one day | a linked session created 3 days ago, an unlinked one created 3 days ago, an unlinked one created now; `Run(90, T)`, `Run(90, T+86399 s)`, `Run(90, T+86400 s)` | the first two runs delete nothing; the third deletes both unlinked sessions (and their `ContextData` streams) and keeps the linked one | none |
| 12. A link moves | `Point` moves a link from S to S2 at T1 | S is marked by the first run after T1 and deleted by the first run at least 86,400 s after its mark, never earlier; S2 is kept | none |
| 13. Linked again before a day | a session is marked, then a link names it | the next run clears its mark and keeps it | none |
| 14. Bad day count | `Run` and `DaysCutoff` with `""`, `0`, `-1`, `1.5`, `abc`, `00` | an error status naming `OcuTalon.Bridge.Purge.Run` (and the given caller for `DaysCutoff`); no row or session is deleted and no mark is written | error status |
| 15. Far day count | `Run(100000)` | OK; no decision or usage row is deleted; the session rule still applies | none |
| 16. Unreadable now | `Run(90, "yesterday")` | an error status; nothing deleted, no mark written | error status |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Install/Task/Purge.cls:7-15` -- `TaskName` "OcuTalon purge", `DaysToKeep` 90, `OnTask` → `Registry.Purge(..DaysToKeep)`. Unchanged (contended, Epic 15). It reaches `Bridge.Purge` through the Retention area.
- `src/ocutalon/cls/OcuTalon/Install/Registry.cls:20-36` -- `Areas()`: every compiled, non-abstract `OcuTalon.Install.Step.<name>`. `:71-92`: `Purge` → `CallAreas("Purge", days)`, which calls every area and appends errors by area. `:97-123`: `Declared("Tasks")`. Unchanged.
- `src/ocutalon/cls/OcuTalon/Install/Step/Tasks.cls:33-47` -- `Check`: the name starts with `OcuTalon`, no name is declared twice, and the class extends `%SYS.Task.Definition`. `:51-72` `Create`: it skips a name that `FindId` finds. It sets `NameSpace = $Namespace` (line 60) and then `Assign(task, entry.task)` (line 62), so a declared `NameSpace` would override it: the owner-rule test guards this. The settings go through `definition.%New()` + `Assign` + `task.AssignSettings`. Unchanged.
- `src/ocutalon/cls/OcuTalon/Install/Step.cls:35-47` -- the `Tasks()` and `Purge(daysToKeep)` contract.
- `src/ocutalon/cls/OcuTalon/Install/Step/Schedule.cls:27-46` -- the sibling `Tasks()` declaration (the heartbeat, Lane B): its shape and schedule fields.
- `src/ocutalon/cls/OcuTalon/Install/Step/Digest.cls:1-12` -- the sibling `Purge` declaration. `Install/Step/Approvals.cls:1-13` is the precedent for an area that delegates to a bridge class (`Bridge.Approval.Reconcile`).
- `src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls:62-85` -- `Purge`: the day check and the cutoff that `DaysCutoff` takes over (DW-371).
- `src/ocutalon/cls/OcuTalon/Data/Pairing.cls:213-237` -- Lane B's copy (read only).
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:1229-1281` -- `Purge`/`PurgeOne`: closed incidents with their groups and fix runs. Called, not edited (contended, Epic 9).
- `src/bridge/cls/OcuTalon/Bridge/Time.cls:1-21, 82-101` -- the bridge clock: `NowUtc`, and `PlusSeconds`, which returns `""` for unreadable input.
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls:68-69`, `Usage.cls:58-59` -- `RecordedAt`, UTC `YYYY-MM-DDThh:mm:ssZ` (string order is time order). There is no index on it, so the DELETE scans; that is fine once a day.
- `src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls:1-14` -- the doc line "No other product class names this class". `:24-33`: `OwnerRef`, `Agent`, `SessionId` (string), unique on (OwnerRef, Agent). `:44-57`: `Point`, the only writer.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/Agent.cls:358-387, 447-461` -- `AnswerLinked`/`SaveLinked`: `session.%Save()` then `Point`. This is the only `%Save` of an AI session in `src/`. A link only ever moves forward, to a new id (`NewSession` or a 30.1 fork), so once a session is unlinked it stays unlinked. A session being saved and not yet pointed was created seconds ago, so its mark protects it for a day.
- `irislib/%AI/Agent/Session.cls:17, 721-751` -- `CreatedAt` (UTC); the storage globals `^AI.Agent.SessionD`, `S` and `I`. SQL `%AI_Agent.Session` answered on slot A (2026-10-30, read only, 0 rows).
- `irislib/Ens/Util/Tasks/Purge.cls:12-49` -- the properties. `KeepIntegrity` defaults to 1 and `BodiesToo` to 0. The `TypesToPurge` VALUELIST includes `messages` and `all`. `optionalMessageLimitToConfigItems` matches `SourceConfigName` or `TargetConfigName`. `:60-150`: `OnTask`.
- `irislib/Ens/Purge.cls:14-64` -- `PurgeAll` covers the event log, messages, business processes (always with KeepIntegrity), rule logs, I/O logs, host monitor data and managed alerts. `:235-249` `GetDoNotDeleteDate`: the cutoff is local midnight at the start of day today − days + 1, so the fixtures keep 2 days' margin.
- `irislib/Ens/Util/MessagePurge.cls:263-306` -- the selection: `TimeCreated` < cutoff. With KeepIntegrity, the whole session must be done (Status 4, 7, 8 or 9). The config-item list is matched as `,name,`.
- `irislib/Ens/BusinessProcess.cls:1182-1201` -- with KeepIntegrity it deletes completed instances whose ID is at most the highest ID created before the cutoff. So the newer fixture must get the higher ID, and every older completed instance on the stack goes too (fine on a throwaway).
- `src/ocutalon/cls/OcuTalon/Production.cls:45, 71` -- the items `Checks` and `HeartbeatIn`.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls:378-396` -- `Incident(ref, sessionRef)` (noticed, own) and `Decision(ref, sessionRef)` (own): the read surface for row 9. Lane B, read only.
- `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls:174-209` -- `TestTasksStep`: a fixture area receives the fixture purge task's `DaysToKeep` (33). This existing pin stays. `:1171` is the fixture declaration's schedule fields.
- `src/ocutalon/cls/OcuTalon/Test/Schedule/Heartbeat.cls:64, 303, 799-837` -- the Task Manager pattern (Lane B): `RunNow(FindId(name))`, `HistoryMark`, `RunsWhere`, `RunErrors`, `WaitRuns` over `%SYS_Task.History`. Measured: `RunNow` takes up to a minute.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/AuditLog.cls:22-70` -- `Now`, `Entries` and `Wait`, by marker. Reuse them.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls:147-167, 394-451` -- `LINKREFERENCE`, `LINKNAMERS`, `LINKCALL`, `LINKWRITES`, `TestOnlyTheRunnerWritesLinks`.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Source.cls` -- `Text`, `Matches`, `Lines`: source scans with comment lines dropped.
- `src/ocutalon/cls/OcuTalon/Test/Digest/Store.cls:389-475`, `Test/Digest/Zone.cls:80-96` -- the Digest purge pins, which must stay green unchanged. `Store.NewRow(sessionRef, itemId, recordedAt, .sc)` makes fixtures.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls:761-821, 934-941` -- the `IncidentManager.Purge` pins (unchanged) and its incident and group fixture pattern.
- `src/bridge/cls/OcuTalon/Bridge/Budget.cls:7-9` -- precedent for a plain mark global in the private database: `^OcuTalonBP.UsageCapped(day)`. `docker/merge.cpf:12` maps `OcuTalonBP.*` → `OCUTALON_PRIVATE`.
- `ci/units.sh:17` -- the lane-a areas already include `Bridge` and `Install`, so no `ci/units.sh` change is needed.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure, on the first fresh run of `Test.Install.Retention`; add the results to this spec as a **Measured** list at the end of Design Notes) -- Confirm on build 154 that:
  - the start's Tasks step creates both `Ens.Util.Tasks.Purge` tasks as the installing user (`STEP Tasks OK`; `task.Settings` reads back the declared values);
  - `RunNow` of each of the three tasks leaves a `%SYS_Task.History` row with no error, and how long it takes;
  - the backdated fixtures of rows 5 and 6 go as the Ens source says;
  - an `%AI.Agent.Session` that is `%New()`ed and `%Save`d with no agent attached, with `CreatedAt` set, and then `%DeleteId`ed, leaves no `^AI.Agent.SessionS` node.

  Anything left unmeasured is labelled (inference).
- `src/bridge/cls/OcuTalon/Bridge/Time.cls` -- add `ClassMethod DaysCutoff(daysToKeep As %String, caller As %String, Output cutoff As %String, now As %String = "") As %Status`, per Always. Use date arithmetic on the UTC date, as `Digest.Data.Item.Purge` does today. An unreadable `now` is an error. Add one line to the class doc list. -- This is the one day check and cutoff that DW-371 asks for. OcuTalon code may call the bridge (AD-2).
- `src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls` -- `Purge` calls `Bridge.Time.DaysCutoff(daysToKeep, "OcuTalon.Digest.Data.Item.Purge", .cutoff)`: it quits on an error or an empty cutoff, then runs the same DELETE. Same behaviour and text. -- DW-371, Lane A's side.
- `src/bridge/cls/OcuTalon/Bridge/Purge.cls` -- new class `OcuTalon.Bridge.Purge` with `ClassMethod Run(daysToKeep As %Integer, now As %String = "") As %Status`, per Always. Its doc comment says the session rule covers every AI session of the namespace, and that only the bridge's runner saves sessions in OCUTALON. -- AD-27's bridge purge.
- `src/bridge/cls/OcuTalon/Bridge/Data/ConversationLink.cls` -- doc comment only: the classes that name it are the adapter, Decide and `Bridge.Purge`, which reads `SessionId` through one SELECT and writes nothing. -- Keeps the class's stated contract true. No storage change.
- `src/ocutalon/cls/OcuTalon/Install/Step/Watch.cls` -- new area: `Purge(daysToKeep)` returns `##class(OcuTalon.Watch.IncidentManager).Purge(daysToKeep)`. It declares nothing else and is not in the order. -- AD-27's "incidents for that many days (Lane A)".
- `src/ocutalon/cls/OcuTalon/Install/Step/Retention.cls` -- new area (Lane A installer core, not in the order). `Tasks()` returns the three declarations of Always, the purge task's name read from `$Parameter("OcuTalon.Install.Task.Purge", "TaskName")`. `Purge(daysToKeep)` returns `##class(OcuTalon.Bridge.Purge).Run(daysToKeep)`. Descriptions are one plain sentence each (Design Notes). -- AD-27, AD-23.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- add `OcuTalon.Bridge.Purge` to `LINKNAMERS`. In `TestOnlyTheRunnerWritesLinks`, assert that Purge calls no method of the link class (`LinkCalls` is empty), names the link's table on exactly one line, which is a SELECT and matches no `LINKWRITES`, and never names `ocutalonbp\.conv`. Update the class doc lines. -- AD-6 "only the runner writes it" stays pinned, with one more pinned reader.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Time.cls` -- add `TestDaysCutoff`: the matrix's row 14 values, a whole day count with a fixed `now`, `00`, `100000` (OK with an empty cutoff), an unreadable `now`, and the caller named in the error. -- DW-371.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/Purge.cls` -- new test class covering matrix rows 10 to 16. Its header says THROWAWAY STACKS AND CI ONLY (Rule 21): it deletes rows and sessions that it did not make.
  - Fixtures: Decision and Usage rows with fresh Refs; `%AI.Agent.Session` rows saved with no agent and with `CreatedAt` set; links through `ConversationLink.Point` under a fresh `OwnerRef`.
  - `now` steps from one fixed T.
  - Clean-up deletes its own links, sessions, rows and `^OcuTalonBP.Unlinked` nodes, also after a failure.
- `src/ocutalon/cls/OcuTalon/Test/Install/Retention.cls` -- new test class, THROWAWAY STACKS AND CI ONLY (Rule 21).
  - `TestDeclarations`: `Retention.Tasks()` is exactly the three entries of Always; no entry has a `NameSpace` key; `HeartbeatIn` and `Checks` are items of `OcuTalon.Production` (`Ens.Config.Production`).
  - `TestCreatedOnce`: the three tasks exist before the test runs the step (the start made them), then matrix rows 1 and 2. To simulate the upgrade, it deletes and recreates one task.
  - `TestAdminChangesKept`: row 3. It restores the values on every path.
  - `TestNoSettingRead`: the code of `Install.Task.Purge`, `Install.Step.Retention`, `Install.Step.Watch`, `Install.Step.Digest`, `Bridge.Purge`, `Bridge.Time` and `Registry`'s `Purge`/`CallAreas` names no `OcuTalon.Data.Setting` (`Test.Bridge.Source`). It first shows that the scanner flags a sample.
  - `OnBeforeAllTests`:
    1. seeds the fixtures of rows 4 to 9. OCUORDERS's fixture is written with a test-only `New $Namespace`; a missing OCUORDERS is a failure, not a skip;
    2. sets the `OcuTalon purge` task's stored `DaysToKeep` to 60;
    3. calls `RunNow` for every task that `Retention.Tasks()` declares, by name;
    4. waits for each task's history row after a mark (ceiling 180 s), then puts `DaysToKeep` back.
  - `TestOwnNamespaceOnly`, `TestMessagesPurge`, `TestAllPurge`, `TestOcuTalonPurge`, `TestAuditUntouched` and `TestHistoryReadsTables` then only read that outcome (rows 4 to 9) and assert that every run's history has no error.
  - `OnAfterAllTests` removes every fixture that remains and the OCUORDERS fixture. It restores the tasks' settings.
  - Its history helpers are name-keyed copies of `Test.Schedule.Heartbeat`'s (Rule 2 note).
  -- This covers AC 1 to 5 and the owner rule.

**Acceptance Criteria:**
- AC 1. Given a first start or an upgrade, when the installer core's Tasks step runs, then exactly one task of each of the three names exists in Task Manager, with the declared class, settings and daily 03:00 schedule, all from `Install.Step.Retention`'s `Tasks()`, and a second start still leaves one of each (NFR-19, AD-23, AD-27; matrix 1, 2).
- AC 2. Given the three tasks, when the Task Manager runs them, then each runs in `OCUTALON` and an old message in `OCUORDERS` is untouched (the owner's rule; matrix 4).
- AC 3. Given `Bridge.Purge.Run(daysToKeep)`, when it runs, then it keeps decisions and usage for that many days and deletes AI sessions that no conversation link has named for a day; and when the Task Manager runs `OcuTalon purge`, then `Bridge.Purge` and every area's `Purge(daysToKeep)` get the task's `DaysToKeep`, the fixture area of `Test.Install.Registry.TestTasksStep` included (NFR-19, AD-27; matrix 7, 10-16).
- AC 4. Given the tasks were created, when an admin changes a day count or the schedule in the Task Manager and a later start runs the Tasks step, then the changed value is kept, and no purge reads `OcuTalon.Data.Setting` (NFR-19, AD-2, AD-27; matrix 3).
- AC 5. Given fixture records older and newer than each retention period, when the purge tasks run, then only the records past their period are gone (business-process instances, rule logs and event-log entries included), the audit entries are untouched, and history still reads from OcuTalon's and the bridge's tables after the messages are purged (NFR-19, AD-27; matrix 5-9).

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**
- AD-27: the rule this story builds. It names the two standard tasks, `Bridge.Purge`, `Install.Task.Purge` with `DaysToKeep`, day counts as task properties, 03:00, and history read from tables.
- AD-23: area declarations (`Tasks()`, `Purge(daysToKeep)`), names starting `OcuTalon`; the Tasks step creates a task once and leaves it alone. Lane A owns the tasks part of the installer core.
- AD-19: tasks are seed; no `Data.Setting` read.
- AD-2: the bridge names no OcuTalon package; OcuTalon may call `Bridge.Time`.
- AD-29 and AD-33: `Install.Step.<Area>` follows its area's lane; Lane B classes are not edited.
- AD-5: no storage change; private data stays in the private database.
- AD-3: only tests switch namespace, and the bridge never does.
- AD-6: only the runner writes links; `Bridge.Purge` reads them.
- AD-17: the audit log is untouched.
- AD-26: traces are kept 90 days. An incident chain has its own trace session. The 7-day `Checks` purge removes `Checks`' own messages, which belong to the Tick's session (inference).
- AD-20: `Budget.State` reads only today's `Usage`, which a purge of at least 1 day never deletes.
- AD-22: the throwaway stacks.

**V1. The one-day session rule needs a mark. For the lead's ruling, because the veto window covers how stored data is kept.**
- **Chosen:** `Bridge.Purge` keeps `^OcuTalonBP.Unlinked(sessionId)` = the UTC time of the first run that found the session with no link. A run deletes a session once its mark is at least 86,400 s old and it is still unlinked. It clears the marks of linked or vanished sessions.
  - Links only move forward (`SaveLinked`: a new id), so this is exactly "no link has pointed to it for a day".
  - With the daily run, a session that is left goes one or two days later.
  - It is a plain global of the private database, written and read only by this class, like `^OcuTalonBP.UsageCapped` and `^OcuTalonBP.KeyState`. No persistent class, column, index or storage block changes.
- **Rejected:**
  - (a) `CreatedAt` older than a day and unlinked now. That deletes, minutes after a rotation, a session the link named until then, which breaks the AC's wording.
  - (b) A `PreviousSessionId`/`MovedAt` column on `ConversationLink`. That is a schema change, it holds only one previous session per link, and `Point` would change.
  - (c) An index on `SessionId`. That is a storage change and an index rebuild on upgrade.
- **Recommendation:** keep as planned.
- **Lead ruling (spec gate, 2026-10-30):** kept as planned — veto item U-165 (the owner may reverse it before the release: drop the mark and the session clause, kill `^OcuTalonBP.Unlinked`). Also ruled (decide): the three Task Manager names and descriptions above are operator-facing and stand as written (accurate, the heartbeat task's precedent); the purge classes' `(loop)` runs stay fresh, as planned; the Retention area's `Purge` path (no edit to `Install/Task/Purge.cls`) stands.

**Decided in-stage.**
- `Bridge.Purge` is reached through the Retention area's `Purge`, as `Install.Step.Approvals` reaches `Bridge.Approval.Reconcile`. So `Install/Task/Purge.cls` (contended, Epic 15) is unchanged, and the observable effect is that of a direct call (matrix 7). If the lead prefers the direct call, that is a contended edit of `Install/Task/Purge.cls` (`OnTask` calls `Bridge.Purge.Run` and appends the registry's status, about 4 lines), and Retention's `Purge` goes away.
- Incidents go through a new `Install.Step.Watch` area, the Digest pattern, rather than through Retention.
- Task names (`OcuTalon purge heartbeat and check messages`, `OcuTalon purge Interoperability data`) and descriptions. They are operator-facing Task Manager text, like the heartbeat task's.
  - Messages task: "Purges OcuTalon's heartbeat and check messages (HeartbeatIn and Checks), with their bodies, older than NumberOfDaysToKeep days (NFR-19)."
  - All task: "Purges OcuTalon's Interoperability data older than NumberOfDaysToKeep days: messages and bodies, business processes, rule logs, the event log, I/O logs, host monitor data and managed alerts; unfinished sessions are kept (NFR-19)."
  - OcuTalon purge: "Deletes OcuTalon's own records older than DaysToKeep days (bridge decisions and usage, closed incidents, digest items and the areas' other records) and the AI sessions no conversation link has named for a day (AD-27)."
- `RescheduleOnStart` 1: a run that a stop missed is not replayed during a start. `StartDate` is today, as for the heartbeat. `KeepIntegrity` 1 is written out on the 7-day task too; it is the class default, and the AC names it only for the 90-day task.
- The method is `Run(daysToKeep, now = "")`. The `now` seam follows `Core.Trace.Join`.
- The session rule does not depend on `daysToKeep`. A bad day count or an unreadable `now` deletes nothing and marks nothing.
- The session rule covers every AI session in OCUTALON. There, only `Adapter.Agent.SaveLinked` saves one.
- `ApprovalRequest`, `Price` and `ModelFamily` are not purged, because the AC names decisions and usage. A later story may add approval rows.
- Verification: the purge classes delete rows they did not make, so they run fresh, per the project block's "destructive tests always use fresh stacks", not warm as the lead's `(loop)` default says.

**Contended edits:** none planned. Two Verification mutations change `Install/Step/Tasks.cls` temporarily; both are reverted byte-identically and never committed.

**Lane B need (AD-33), not planned:** `Data.Pairing.Purge` could call `Bridge.Time.DaysCutoff(daysToKeep, "OcuTalon.Data.Pairing.Purge", .cutoff)` in place of its copy.

**DW-371 (ledger inbox): addressed for Lane A's side.** `Bridge.Time.DaysCutoff` is the one day check and cutoff, used by `Bridge.Purge` and `Digest.Data.Item.Purge`. Residual: `Data.Pairing.Purge` (Lane B) and `Watch.IncidentManager.Purge` (Lane A, in Epic 9's contended footprint) keep their copies; each becomes a one-line call.

**Integration ACs (Rule 1).** Matrix row 7: the Task Manager's run of `OcuTalon purge` (`Install.Task.Purge` → `Registry.Purge` → `Install.Step.Retention` and `.Watch`) reaches `Bridge.Purge` and `IncidentManager.Purge` on the real stack, and the 61-day rows go.
- **Consumed-by:**
  - Story 30.1, whose compaction forks leave sessions that `Bridge.Purge` removes, so 30.1 adds no cleanup of its own;
  - Lane B's `Data.Pairing.Purge` (`DaysCutoff`, optional);
  - Epic 9 (`IncidentManager.Purge` may adopt `DaysCutoff`).
- **Consumes:**
  - `Install.Step.Tasks`, `Install.Registry` and `Install.Task.Purge` (Story 0.2);
  - `Watch.IncidentManager.Purge` (Epic 5);
  - `Digest.Data.Item` (Story 1.12);
  - `Data.Ownership` `Decision`/`Incident` (Lane B, read only);
  - `Test.Bridge.AuditLog` and `Test.Bridge.Source`;
  - `Ens.Util.Tasks.Purge` and `%SYS.Task` (platform).

**Extend, don't copy (Rule 2).**
- `Install.Step.Retention` and `.Watch` extend the `Install.Step` contract, like `Digest`, `Core` and `Approvals`.
- `Bridge.Time.DaysCutoff` is taken out of `Digest.Data.Item.Purge` (the DW-371 sibling) and replaces that copy.
- `Test.Install.Retention`'s task-history helpers are name-keyed copies of `Test.Schedule.Heartbeat`'s `HistoryMark`/`RunsWhere`/`RunErrors`/`WaitRuns`. Those are Lane B's (AD-33) and keyed to its `TASK` parameter.
- The audit reads reuse `Test.Bridge.AuditLog`. The digest fixtures reuse `Test.Digest.Store.NewRow`.

**Spine note for the lead (Rule 20), optional:** AD-27 could name the mark `^OcuTalonBP.Unlinked`. No AD Rule changes.

**Files outside "Ours" (Rule 11):**
- `src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls`, a Lane A file this story names (DW-371).
- The new `Install/Step/Retention.cls` and `Install/Step/Watch.cls`, new files in a contended folder, which the footprint allows.

No existing contended file is edited.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=30 stage=implement'`, run from the worktree root. The fresh tag is `e30s2i`; the warm tag is `e30s2iw`.
- Run one command per tool call, in the foreground, with `timeout: 600000`. Never run two IRIS test runs in one message. The harness moves a call to the background after about 180 s; poll it to completion in foreground loops of under 170 s, and never start a second copy.
- **Throwaway stacks only.** The recipe is `ci/iris.sh class|shard` with the lane's variables: fresh for the purge classes, warm for the rest. Never warm for a destructive class or the fresh-environment check.
- On `ocutalon-slot-a` (MCP `server` `ocutalon-slot-a`, `namespace` `OCUTALON`, checked with `iris_server_info`, build 154), only load and compile the changed classes (`iris_doc_load`, `baseDir` `src/bridge/cls` or `src/ocutalon/cls`) to catch compile errors. Never run the Tasks step, a purge or these tests there.
- Tear down only your own tags, after a failure too.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e30s2iw ci/warm.sh up`, once per stage, after the code is written. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e30s2iw ci/iris.sh class <Class>`, one call per class. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Bridge.Time`
  - `OcuTalon.Test.Bridge.CodeRules`
- (loop) `<lane> OCUTALON_RUN_TAG=e30s2i ci/iris.sh class <Class>`, fresh, one call per class. Expected: passed.
  - `OcuTalon.Test.Install.Retention` (first, with Task 0)
  - `OcuTalon.Test.Bridge.Purge`
  - `OcuTalon.Test.Install.Registry`
  - `OcuTalon.Test.Digest.Store`
  - `OcuTalon.Test.Digest.Zone`
- (once) `bash ci/checks.sh`. Expected: every script passes, `test-boundaries` included (the bridge names no OcuTalon package).
- (once) `<lane> OCUTALON_RUN_TAG=e30s2i ci/iris.sh shard lane-a --part k/4` for k = 1, 2, 3 and 4, fresh, one call each. Expected: passed. Record each part's time. A part near 8 minutes means splitting to `--part k/6`.
- (once) `<lane> OCUTALON_RUN_TAG=e30s2i ci/iris.sh shard lane-b --part 1/2`, then `--part 2/2`, one call each. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e30s2iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e30s2i ci/iris.sh teardown`. Run both after a failure too.

**Shared surfaces:**
- **Task Manager:** three new OcuTalon tasks on every start, on fresh and warm stacks, in CI and in installs. `Test.Schedule.Heartbeat` and `Test.Install.Registry` count tasks by their own names and classes, so they are unaffected. No live script checks tasks.
- **The registry's areas:** `Install.Step.Retention` and `Install.Step.Watch` are new areas.
  - `Test.Install.Registry.TestAreas` checks inclusion only.
  - `Registry.Purge(n)` now also runs `Bridge.Purge` and `IncidentManager.Purge`, so every caller still gets OK and errors that name their area: `Test.Install.Registry` `TestPurge`, `TestPurgeTaskDefaults` and `TestTasksStep`, and `Test.Digest.Store` `TestPurgeByTheTask`, `TestPurgeDays` and `TestPurgeRefuses`. On a stack they delete decisions, usage and closed incidents older than n days, and they mark unlinked sessions.
  - `Test.Watch.Lifecycle.TestPurge`'s skip guard (a closed incident older than 59 days) can only be helped by this.
- **Completed business-process instances:** the 90-day run deletes every one with an ID below its old fixture. They are only earlier classes' leftovers.
- **`Test.Bridge.Purge`'s future-`now` runs:** they delete unlinked sessions that an earlier run on the same stack marked. No test keeps an unlinked session across classes.
- **`Bridge.Time`** gains a method, **`CodeRules`' `LINKNAMERS`** gains `Bridge.Purge`, and **`Digest.Data.Item.Purge`** keeps its text.
- **CI time:** `Test.Install.Retention` is in the `Install` area, so it runs in the `shards` group (`shard:lane-a@Checks,Install,Watch`, 20.4 min measured on 2026-10-29). It adds up to about 3 minutes (three `RunNow` waits of up to a minute each). No `ci/units.sh` change.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations (Rule 19).** Apply each mutation, observe red, revert byte-identically (`git status --short` and `git diff --stat` unchanged), and record a `mutation: … → …` line here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | the messages declaration's `DailyStartTime` 10800 → 7200 | `Retention.TestDeclarations`, `TestCreatedOnce` |
| AC 1, one of each | temporary: `Tasks.Create` drops its `FindId` skip (reverted, never committed) | `Retention.TestCreatedOnce` |
| AC 2 | the messages declaration gains `"NameSpace": "OCUORDERS"` | `Retention.TestOwnNamespaceOnly` (NameSpace, and the OCUORDERS fixture gone), `TestDeclarations` |
| AC 3, days | `Bridge.Purge.Run` uses `daysToKeep + 1` | `Bridge.Purge.TestDecisionsAndUsage` |
| AC 3, a day | `Run` deletes an unlinked session at its first sighting | `Bridge.Purge.TestSessions` |
| AC 3, the links | `Run` skips the link read (every session counts as unlinked) | `Bridge.Purge.TestSessions` (the linked session is deleted) |
| AC 3, the task's days | `Retention.Purge` passes 90 instead of `daysToKeep`, and separately `Watch.Purge` passes 90 | `Retention.TestOcuTalonPurge` (the 61-day decision, then the 61-day incident, stays) |
| AC 4, kept | temporary: `Tasks.Create` deletes and recreates an existing task (reverted, never committed) | `Retention.TestAdminChangesKept` |
| AC 4, no setting | `Retention.Purge` reads `##class(OcuTalon.Data.Setting).Get(...)` | `Retention.TestNoSettingRead` |
| AC 5, messages | `optionalMessageLimitToConfigItems` drops `Checks` | `Retention.TestMessagesPurge` |
| AC 5, all | the all task's `NumberOfDaysToKeep` 90 → 95 | `Retention.TestAllPurge` |
| AC 5, audit | temporary line in `Bridge.Purge.Run` that deletes OcuTalon-source audit rows (or the implementer's equivalent that removes the marker entry during the run) | `Retention.TestAuditUntouched` |
| AC 5, history | `Bridge.Purge.Run` also deletes decisions whose `TraceSessionId` has no message header left | `Retention.TestHistoryReadsTables` |
| DW-371 | `DaysCutoff` drops its `+daysToKeep < 1` check | `Bridge.Time.TestDaysCutoff`, `Digest.Store.TestPurgeRefuses` |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Planned 2026-10-30 from epic-30-context.md (valid, committed) and the Story 30.2 block of epics.md, against ARCHITECTURE-SPINE.md (AD-27, AD-23, AD-19, AD-2, AD-29, AD-33, AD-5, AD-3, AD-6, AD-17, AD-26, AD-20, AD-22). No earlier Epic 30 story is done, so there is no previous-story continuity.
- For the lead's spec gate: V1, a new private mark global `^OcuTalonBP.Unlinked` for the one-day session rule (veto window: how stored data is kept; the recommendation is to keep it). No contended edit is planned. DW-371 is addressed for Lane A's side, with the Lane B residual and the Epic 9 contended residual named.
- Halted after planning, as the dispatch asked.
