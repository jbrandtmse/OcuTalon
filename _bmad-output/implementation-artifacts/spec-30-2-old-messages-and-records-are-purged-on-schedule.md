---
title: 'Old messages and records are purged on schedule'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: '0cd2c9f438933759a2ba900d48ad97eb32e82f36'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      The three purge tasks all start at 03:00 and the two Interoperability purges can overlap on the message tables.
    evidence: |-
      The declared values name DailyStartTime 10800 for every task (AD-27), so the scheduled runs overlap. Test.Install.Retention runs the two together on a fresh stack and they pass, but the volume is tiny. What would settle it: a concurrent run of both on a stack with a large message table, watching for lock waits or a failed history row.
    location: >-
      src/ocutalon/cls/OcuTalon/Install/Step/Retention.cls
    severity: medium (unverified)
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

- 2026-10-30 (implement): the declared `StartDate` is "today" only while 03:00 is more than 300 s away, otherwise tomorrow (`Retention.Schedule()`, `STARTMARGIN`). Measured on build 154: the Task Manager refuses a once-daily task whose first start is not ahead of the clock (`ERROR #7432: Start Date and Time must be after the current date and time`), so a start after 03:00 with `StartDate` = `+$Horolog` failed `STEP Tasks`, and with it the whole start. The first run is always the next 03:00. `Test.Install.Retention` pins the first start as ahead of the clock and within a day and a half.
- 2026-10-30 (implement): the Task Manager keeps only the first 100 characters of a task's description (`%SYS.Task.Description`, `TRUNCATE = 1`). The review pass therefore rewrote the three descriptions of Design Notes to one plain sentence of at most 93 characters each (decided in-stage, same facts, no claim added); `TestDeclarations` pins the 100-character limit and `TestCreatedOnce` compares the stored text whole. The lead's ruling that the Task Manager texts stand was made before this was known; a different wording is a one-line change per task.
- 2026-10-30 (implement): `Test.Install.Retention` runs the two Interoperability tasks together and the OcuTalon purge task after them, so that matrix row 9 reads the history with the messages already gone.

## Review Triage Log

### 2026-10-30 - Review pass
- verdicts: 29 findings - high 0, medium 5, low 18, false 5, maybe-false 1
- findings:
  - `[low]` `patch` Blind: Run reads the clock twice (DaysCutoff and the session part) - `now` is now resolved once at the top of `Bridge.Purge.Run`.
  - `[low]` `patch` Blind: a link with an empty `SessionId` aborts the session part with `<SUBSCRIPT>` - skipped when building the linked set; `TestLinkWithoutSession` pins it (mutation line).
  - `[low]` `patch` Blind: sessions are deleted while the cursor over `%AI_Agent.Session` is open - due ids are collected first and deleted after the cursor is read.
  - `[false]` `reject` Blind: the session rule is broader than the sessions the bridge made - the spec states it (V1, veto item U-165), and `src/` has one `%Save` of an AI session (`SaveLinked`, which points the link right after).
  - `[false]` `reject` Blind: `ApprovalRequest` is not purged - the spec's Never list excludes it (the AC names decisions and usage).
  - `[low]` `patch` Blind: `DaysCutoff` is called "the one day check" but only two callers use it - the `Bridge.Time` doc now names the two callers; the Lane B and Epic 9 copies are the spec's named residual.
  - `[false]` `reject` Blind: `Digest.Data.Item` now depends on `Bridge.Time` - AD-2 lets OcuTalon call the bridge; the spec names this call.
  - `[low]` `patch` Blind: the Task Manager descriptions are cut mid-sentence at 100 characters - the three descriptions are one sentence of at most 93 characters; `TestDeclarations` pins the limit, `TestCreatedOnce` compares the stored text whole.
  - `[low]` `patch` Edge: empty `SessionId` (same root as the Blind row) - fixed together.
  - `[low]` `reject` Edge: a session deleted between the read and `%DeleteId` returns an error status - needs two overlapping purge runs; the next run is clean (wontfix-theoretical).
  - `[low]` `patch` Edge: deleting under an open cursor (same root as the Blind row) - fixed together.
  - `[low]` `reject` Edge: a mark in the future (clock set back) delays a deletion - wontfix-theoretical; it clears when the clock catches up.
  - `[low]` `reject` Edge: `DeleteBefore` is public and takes a table name - its callers are `Run` and the test double; the argument is never user input.
  - `[maybe-false]` `defer` Edge: the three tasks start together at 03:00 and may contend - the start time is the declared value (AD-27); recorded in `deferred:` as medium (unverified), with what would settle it.
  - `[low]` `patch` Edge: `RunTasks` overwrites a saved settings copy that an aborted run left - `OnBeforeAllTests` restores a leftover first.
  - `[low]` `patch` Edge: `%OpenId` can return "" in the retry loop - guarded with `$IsObject`.
  - `[medium]` `patch` Verification gap: no test made a part inside `Run` fail - `Test.Bridge.ZzPurgeFailing` fails the Decision delete, `TestPartsRunAlone` asserts the later parts ran and the error came back (mutation line).
  - `[medium]` `patch` Verification gap: matrix 15 did not check the session rule with an empty cutoff - `TestDecisionsAndUsage` marks and deletes a session through `Run(100000, T)` (mutation line).
  - `[medium]` `patch` Verification gap: the StartDate branch depended on the time of day - `Schedule(now)` takes a Horolog value and `TestStartDate` pins seven clocks (mutation line).
  - `[medium]` `patch` Verification gap: the OCUORDERS-untouched assertion had not been shown to fail - mutation run with the all task set to OCUORDERS: the assertion went red (mutation line).
  - `[low]` `patch` Verification gap: behaviours without a mutation line (row 16 order, `BodiesToo`, the CodeRules pins) - the three got lines; `TestMarks` pins an internal detail, not an AC, and gets none.
  - `[low]` `reject` Verification gap: future-now runs delete other classes' unlinked sessions - the spec accepts and states it (Shared surfaces).
  - `[false]` `reject` Verification gap: `TestCreatedOnce` relies on the start - the spec's task says the start made the tasks; that is the thing under test.
  - `[low]` `reject` Verification gap: `Links()` reads only the test's own owner - the `CodeRules` source scan is the guard for the writer; one more owner adds nothing.
  - `[low]` `reject` Verification gap: `Data.Pairing.Purge` and `IncidentManager.Purge` keep copies - the spec's named residual (Lane B, Epic 9).
  - `[low]` `patch` Verification gap: the `TestLinkedAgain` label claimed a recount - relabelled to what it checks.
  - `[medium]` `patch` Intent alignment: the declared `StartDate` is today only while 03:00 is more than 300 s away - the platform refuses a past first start (`ERROR #7432`); decided in-stage and recorded in the Spec Change Log; flagged for the lead in the Auto Run Result.
  - `[low]` `reject` Intent alignment: the row 1 error path (a task that cannot be created fails `STEP Tasks`) has no test here - it is `Tasks.Create`'s existing behaviour, pinned in `Test.Install.Registry`.
  - `[false]` `reject` Intent alignment: `Digest.Data.Item.Purge` has no new test - `Digest.Store.TestPurgeRefuses`, `TestPurgeDays` and `TestPurgeByTheTask` ran green on it and go red with the `DaysCutoff` mutation.

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

**Measured (Task 0, build 154, first fresh runs of `Test.Install.Retention` and `Test.Bridge.Purge`, 2026-10-30):**
- The start's Tasks step creates both `Ens.Util.Tasks.Purge` tasks and the `OcuTalon purge` task as the installing user (`STEP Tasks OK`), and `task.Settings` reads back every declared value (`TypesToPurge`, `NumberOfDaysToKeep`, `optionalMessageLimitToConfigItems`, `KeepIntegrity`, `BodiesToo`, `DaysToKeep`), with `NameSpace` `OCUTALON`.
- A first version with `StartDate` = today failed the start after 03:00 (`ERROR #7432`, see the Spec Change Log); with the 300 s margin it creates at any time of day.
- The Task Manager stores only 100 characters of a description.
- `RunNow` of each of the three tasks leaves a `%SYS_Task.History` row with no error. The three took 55.2 s when run together (one Task Manager poll, 2026-10-30, build 154); run in two groups (the two Interoperability purges, then the OcuTalon purge) the class takes 112.84 s (`CLASS OcuTalon.Test.Install.Retention passed 112.84s`); run all three together it took 33.8 to 55.6 s.
- The backdated fixtures of rows 5 and 6 go as the Ens source says: the 9-day heartbeat and check headers with their bodies, the 92-day header and body, the 92-day completed process instance (saved first), rule-log row and event-log row; the 5-day, 88-day and `WebChatIn` rows stay. The 92-day message in `OCUORDERS` and its body stay.
- An `%AI.Agent.Session` that is `%New()`ed and `%Save`d with no agent, with `CreatedAt` set and a context stream, and then `%DeleteId`ed, leaves no `^AI.Agent.SessionS` node (`Test.Bridge.Purge.TestSessions` asserts it).
- `OCUORDERS` does not exist yet when the Tasks step runs at a start, so a task declared with `"NameSpace": "OCUORDERS"` fails the start (`<NAMESPACE>CheckClass+4^%SYS.TaskSuper`); the namespace guard is therefore also a start failure, and the AC 2 mutation uses `HSCUSTOM`.
- `%SYS.Audit.Delete` in `%SYS` accepts a date range only, no event source (`$$$CanOnlySelectDateRange`), so the audit mutation deletes the whole audit log.
- `Test.Bridge.Purge` passes in 0.14 s; `Test.Bridge.Time` 1.4 s and `Test.Bridge.CodeRules` 1.7 s warm; `Test.Install.Registry` 2.4 s, `Test.Digest.Store` 0.8 s and `Test.Digest.Zone` 0.1 s fresh. A fresh stack was ready in 85 to 107 s.

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

Mutation results (2026-10-30, tags e30s2h and e30s2hw; every file reverted byte-identically, `git diff --stat` on `Install/Step/Tasks.cls` empty, `git status --short` unchanged):
- mutation: `Retention` messages declaration `DailyStartTime` 10800 -> 7200 -> red: `Retention.TestDeclarations`, `TestCreatedOnce`.
- mutation: `Tasks.Create` drops its `FindId` skip (temporary) -> red: `Retention.TestCreatedOnce` (more than one task of each name).
- mutation: messages declaration gains `"NameSpace": "HSCUSTOM"` -> red: `Retention.TestOwnNamespaceOnly`, `TestDeclarations`, `TestCreatedOnce`. With `"OCUORDERS"` as the spec names it the start itself fails (`STEP Tasks FAILED`, the namespace does not exist yet), so no test ran; `HSCUSTOM` exists at the Tasks step.
- mutation: `Bridge.Purge.Run` uses `daysToKeep + 1` -> red: `Bridge.Purge.TestDecisionsAndUsage` (the 31-day and 30-day + 1 h rows stay).
- mutation: `Run` deletes an unlinked session at its first sighting -> red: `Bridge.Purge.TestSessions`, `TestLinkMoves`, `TestLinkedAgain`, `TestMarks`.
- mutation: `Run` skips the link read (every session counts as unlinked) -> red: `Bridge.Purge.TestSessions` (the mark of the linked session), `TestLinkMoves`, `TestLinkedAgain`.
- mutation: `Retention.Purge` passes 90 instead of `daysToKeep` -> red: `Retention.TestOcuTalonPurge` (the 61-day decision stays); `Watch.Purge` passes 90 -> red: `Retention.TestOcuTalonPurge` (the 61-day incident stays). Applied in one run, each on its own assertion.
- mutation: temporary: `Tasks.Create` deletes and recreates an existing task -> red: `Retention.TestAdminChangesKept`, and `TestCreatedOnce` (the id changes).
- mutation: `Retention.Purge` reads `##class(OcuTalon.Data.Setting).Get(...)` -> red: `Retention.TestNoSettingRead`.
- mutation: `optionalMessageLimitToConfigItems` drops `Checks` -> red: `Retention.TestMessagesPurge` (the 9-day `Checks` header stays), also `TestDeclarations`, `TestHistoryReadsTables`.
- mutation: the all task's `NumberOfDaysToKeep` 90 -> 95 -> red: `Retention.TestAllPurge` (the four 92-day rows stay), also `TestDeclarations`.
- mutation: temporary line in `Bridge.Purge.Run` that deletes the audit log (`%SYS.Audit.Delete` with no range) -> red: `Retention.TestAuditUntouched`.
- mutation: `Bridge.Purge.Run` also deletes decisions whose `TraceSessionId` has no message header left -> red: `Retention.TestHistoryReadsTables` (and `TestOcuTalonPurge`, where the 59-day decision goes).
- mutation: `DaysCutoff` drops its `+daysToKeep < 1` check -> red: `Bridge.Time.TestDaysCutoff` ('0' and '00'), `Digest.Store.TestPurgeRefuses`.
- mutation (review pass, warm stack e30s2iw for the bridge classes): `Bridge.Purge.Run` quits at the first failed part (`If $$$ISERR(sc) Quit sc` after the Decision delete) -> red: `Bridge.Purge.TestPartsRunAlone` (the Usage rows stay and the session is not marked).
- mutation: `Run` quits when the cutoff is empty (`If cutoff = "" Quit sc` before the session part) -> red: `Bridge.Purge.TestDecisionsAndUsage` (the session is not marked by `Run(100000, T)` and not deleted a day later).
- mutation: `Sessions` stops skipping an empty link `SessionId` -> red: `Bridge.Purge.TestLinkWithoutSession` (`<SUBSCRIPT>`, the run is not OK).
- mutation: `Run` runs the session part before it validates the day count -> red: `Bridge.Purge.TestBadArguments` (a mark is written for every bad argument).
- mutation: `Bridge.Purge.Run` calls `ConversationLink.SessionOf` -> red: `CodeRules.TestOnlyTheRunnerWritesLinks` (Purge calls no method of the link class).
- mutation (fresh stack e30s2i, one run for the three): `STARTMARGIN` 300 -> 0 -> red: `Retention.TestStartDate` (10,500 s and 10,799 s of the day); the messages declaration without `BodiesToo` -> red: `Retention.TestDeclarations` (its settings); the test sets the all task's `NameSpace` to `OCUORDERS` before `RunNow` -> red: `Retention.TestOwnNamespaceOnly` (the 92-day `OCUORDERS` message and its body are gone) and `TestCreatedOnce` (the task runs in OCUTALON). In that run the Task Manager also left the tasks unrun for the whole 180 s ceiling, the stall of the known flake DW-376; the unrun tasks show in the other reds of that run and are not part of these mutations.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: three daily 03:00 purge tasks (`Install.Step.Retention`: two standard `Ens.Util.Tasks.Purge`, 7 and 90 days, and the `OcuTalon purge` task at 90 days), `Install.Step.Watch` (incident purge), `Bridge.Purge.Run` (decisions, usage and the one-day session rule with the `^OcuTalonBP.Unlinked` mark, V1 / U-165) and `Bridge.Time.DaysCutoff` (DW-371, Lane A side; `Digest.Data.Item.Purge` uses it).
- Files: `src/bridge/cls/OcuTalon/Bridge/{Purge,Time}.cls`, `Bridge/Data/ConversationLink.cls` (doc only), `src/ocutalon/cls/OcuTalon/Install/Step/{Retention,Watch}.cls`, `Digest/Data/Item.cls`, and the tests `Test/Bridge/{Purge,Time,CodeRules,ZzPurgeFailing}.cls`, `Test/Install/{Retention,ZzRetentionProcess}.cls`. No contended file and no Lane B class edited; `Install/Task/Purge.cls` and `Install/Step/Tasks.cls` are unchanged (their two Verification mutations were temporary and reverted).
- FOR THE LEAD (deviations from the intent contract's declared values, both measured on build 154 and logged in the Spec Change Log): (1) `StartDate` is `+$Horolog` only while 03:00 is more than 300 s away, else tomorrow, because the Task Manager refuses a past first start (`ERROR #7432`, which failed the whole start after 03:00); the first run is always the next 03:00. (2) The three Task Manager descriptions were shortened to at most 93 characters because the Task Manager keeps only 100; this changes the texts the lead had ruled to stand.
- Review: 29 findings; 16 patched (5 medium, 11 low among them the above), 1 deferred (the 03:00 overlap, medium unverified), 12 rejected with reasons in the Review Triage Log. Follow-up review recommended: 5 medium findings were patched (test seams `ZzPurgeFailing` and `Schedule(now)`, new mutation-pinned tests); the unverified risk is the Task Manager stall below.
- Verification: `(loop)` fresh `Test.Install.Retention` passed (79.75 s on the final run; earlier runs 112.84 s, 102.74 s, 245.43 s with a retried RunNow), `Test.Bridge.Purge` (0.15 s), `Test.Install.Registry` (2.26 s), `Test.Digest.Store` (1.06 s), `Test.Digest.Zone` (0.12 s) passed; warm `Test.Bridge.Time` (1.44 s) and `Test.Bridge.CodeRules` (1.73 s) passed. `(once)` `bash ci/checks.sh` passed. `shard lane-a --part k/4`: 1/4 374 s, 2/4 221 s, 3/4 637 s (wall 10:43, over the 10-minute Bash cap; it passed after the harness moved it to the background, so lane A needs a finer split, e.g. `--part k/6`, for foreground runs), 4/4 432 s, all passed. `shard lane-b --part k/2`: 1/2 270 s, 2/2 504 s, both passed. Stacks `e30s2i` and `e30s2iw` torn down.
- Residual risks: a run of `Test.Install.Retention` failed once before the retry was added (the Task Manager did not run the two Interoperability tasks within 180 s; the same stall as the known flake DW-376), and the retry (`RUNSECONDS` 180, `RETRYSECONDS` 60) raised one run to 245 s; a failed run now names the task's state in its message. The spec's `(loop)` text said warm for the Time and CodeRules classes and fresh for the purge classes; that is what ran. The purge task deletes every unlinked AI session of the namespace after a day (V1, U-165: the owner may reverse it).
