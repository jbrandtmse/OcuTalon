---
title: 'Story 1.12: Items saved for the digest are kept for it'
type: 'feature'
created: '2026-10-23'
status: 'done'
baseline_revision: '22e77d9b13f8da6e618d71d31cfeefebd1a00db8'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, AD-2, AD-3, AD-4, AD-5, AD-6, AD-22, AD-23, AD-27, AD-29, AD-30 and AD-33, the Identifiers, Times, SQL reserved words, Logging and errors and Tests rows of Consistency Conventions, and the Production and Tables rows of the Ownership tables)'
warnings: ['oversized']
deferred:
  - summary: >-
      Item.Since returns every item of the session since the time, with no cap, so a digest period that gathers very many items returns them all in one array.
    evidence: |-
      Each entry is small (an 80-character summary and four Refs and a time), and nothing in this story reads the array: the first consumer is Story 17.6.
      Closed as accepted, not scheduled. reopen_if: Story 17.6's digest wants only a count and the newest N summaries, and a session's saved items between two digests can reach thousands.
    location: >-
      src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls (Since)
    severity: low
  - summary: >-
      The no-live-event check of TestKeepsInstance counts only events on the shared instance stream whose payload holds the ItemId or the DecisionRef, so a store that published an event with neither Ref in its payload would pass it.
    evidence: |-
      LiveEvents cannot count every event on the shared instance stream, since other publishers may use it. The session-owner case (TestKeeps) counts the owner's whole stream and goes red under the publish mutation, and Keep has no branch on the owner.
      Closed as accepted. reopen_if: any file under src/ocutalon/cls/OcuTalon/Digest/ names OcuTalon.Live.Publish (a search of that folder finds a hit).
    location: >-
      src/ocutalon/cls/OcuTalon/Test/Digest/Store.cls (LiveEvents)
    severity: low
  - summary: >-
      Keep's concurrent-repeat path (the pre-check finds no row, the save then fails on the unique index, and the second look finds the row) has no test, because a single send cannot make a row appear between the two steps.
    evidence: |-
      The production runs DigestStore with pool 1, so two messages never run at once. The sequential repeat (the pre-check finds the row) is pinned by TestOnce, and the unique index is pinned by the same test through the mutation that removes both.
      Closed as accepted. reopen_if: the DigestStore item in OcuTalon.Production has a PoolSize above 1.
    location: >-
      src/ocutalon/cls/OcuTalon/Digest/Store.cls (Keep)
    severity: low
---

<intent-contract>

## Intent

**Problem:**
- **Nothing keeps a digest item.** `DigestStore` (`OcuTalon.Digest.Store`, Lane A's region of the production) is Epic 0's stub: it carries `Parameter STUB = 1` and answers every message "not implemented". So an untrusted item that Triage decides to save for later is lost once Lane B's Story 2.7 routes it there, and the step-2 digest (Story 17.6) has nothing to summarise.
- **No table, no read, no retention.** `OcuTalon.Digest.Data.Item`, the table the spine's ownership tables already give Lane A, does not exist. Nothing reads one session's saved items since a time, and the digest area declares no `Purge(daysToKeep)`.

**Approach:**
- **A real store.** `DigestStore` becomes a real business operation. It keeps each digest `OcuTalon.Msg.ItemDecision` as one row of the new `OcuTalon.Digest.Data.Item`, once per `ItemId`, sends nothing on and publishes nothing.
- **A read and a purge on the table.** `Item.Since(sessionRef, since, .items)` reads one session's items since a time, newest first, for Story 17.6. `Item.Purge(daysToKeep)` deletes the older items, and a new area class, `OcuTalon.Install.Step.Digest`, declares it to the purge task through the registry.
- **Tested at the edges.** Fixture `ItemDecision`s go straight to the running item (as the AC says, until Story 2.7 merges), the purge runs through the purge task, and a real IRIS restart is a new row of `docker/tests/test-production.sh`.

## Boundaries & Constraints

**Always:**
- **The table (AD-3, AD-5, AD-33).** `OcuTalon.Digest.Data.Item Extends %Persistent`, SQL `OcuTalon_Digest_Data.Item`.
  - `Parameter DEFAULTGLOBAL = "^OcuTalonP.DigestItem";` and the row `DigestItem	^OcuTalonP.DigestItem	OcuTalon.Digest.Data.Item	A` in `src/short-names.tsv`.
  - **The properties** (the AC's six fields):

    | Property | Type | Holds |
    | --- | --- | --- |
    | `SessionRef` | `%String(COLLATION = "EXACT", MAXLEN = 22)` | the `ItemDecision`'s `OwnerRef`: a session's Ref or the literal `instance` |
    | `ItemId` | `%String(COLLATION = "EXACT", MAXLEN = 22)` | the item's Ref |
    | `DecisionRef` | `%String(COLLATION = "EXACT", MAXLEN = 22)` | the Ref of the item's `Decision` row |
    | `Channel` | `%String(MAXLEN = 32)` | the item's source, one of `Msg.Enum` CHANNEL |
    | `Summary` | `%String(MAXLEN = 80)` | the code-written one-line summary, never model text (AD-6) |
    | `RecordedAt` | `%String(MAXLEN = 20)` | when the store kept it, UTC `YYYY-MM-DDThh:mm:ssZ` |

  - **The indexes:** `ItemIdIndex On ItemId [ Unique ]`, `SessionRefRecordedAtIndex On (SessionRef, RecordedAt)` and `RecordedAtIndex On RecordedAt`.
  - **The storage:** the compiler-generated `Storage Default` block is committed (Task 0 (b)). A property that is an SQL reserved word keeps its name and gets an `SqlFieldName` (Task 0 (a)).
- **The store (AD-1, AD-30, AD-33).** `OcuTalon.Digest.Store Extends Ens.BusinessOperation`, with no `STUB` parameter. Its `OnMessage` follows `OcuTalon.Bridge.Operation.Steps`: `pResponse` is `""`, and a message that is not an `OcuTalon.Msg.ItemDecision` gets `$$$ERROR($$$NotImplemented)`.
  - **What it keeps.** An `ItemDecision` whose `Outcome` is `digest`, whose `ItemId` is not empty and whose `OwnerRef` is neither empty nor `eval` is saved as one row: the fields as in the table above, `RecordedAt` from `OcuTalon.Data.Time.NowUtc()`. The status is OK.
  - **A repeat.** When a row with that `ItemId` exists, the status is OK and nothing changes: the first row stays as it was. A save that fails on the unique index because a row appeared meanwhile counts as a repeat.
  - **What it refuses.** Any other `Outcome`, an empty `ItemId`, and an `OwnerRef` that is empty or `eval` (evaluation decisions go to `EvalSink` only, AD-30): an error status (`5001`) whose text names what is wrong and the item's `ItemId` when it has one, and no row. Ens logs the error, so the store logs nothing of its own.
  - **What it never does.** It sends no message (no `SendRequestSync`, `SendRequestAsync` or alert), calls no `OcuTalon.Live` class, makes no model call and writes no other table.
- **The read (AD-4).** `ClassMethod Since(sessionRef As %String, since As %String, Output items As %DynamicArray) As %Status` on `Item`.
  - **What it gives:** in `items`, the rows whose `SessionRef` equals `sessionRef` exactly and whose `RecordedAt` is at or after `since`, newest first. Rows of the same second come later-saved first.
  - **Each entry:** `{"itemId", "decisionRef", "channel", "summary", "recordedAt"}`, these keys only. No row id.
  - **The arguments:** `since` is `""` (every item of the session) or a UTC time that `Data.Time.ToLocal` reads. An empty `sessionRef` or an unreadable `since` is an error status, with `items` an empty array.
- **The purge (AD-27).** `ClassMethod Purge(daysToKeep As %Integer) As %Status` on `Item`.
  - **What it deletes:** every row whose `RecordedAt` is earlier than the cutoff, which is `Data.Time.NowUtc()` moved back `daysToKeep` whole days (UTC date arithmetic, no zone conversion). A row at the cutoff stays.
  - **A bad day count:** a `daysToKeep` that is not a whole number of at least 1 (`""`, `0`, `-1`, `1.5`, `abc`) is an error status, and nothing is deleted.
  - **The declaration:** `OcuTalon.Install.Step.Digest Extends OcuTalon.Install.Step` overrides only `Purge(daysToKeep)`, which returns `Item.Purge(daysToKeep)`. It is not in `Registry.Order()`, so it only declares. The day count comes only from the caller (the purge task's `DaysToKeep`, 90 by default). No purge reads `OcuTalon.Data.Setting`.
- **References (AD-2).** Of OcuTalon's packages, `OcuTalon.Digest` names only `OcuTalon.Msg.ItemDecision`, `OcuTalon.Data.Time` and its own classes. No `%AI`, no `EnsLib.AI`.
- **The oracle.** `OcuTalon.Test.Install.Production`'s XData `Items` row of `DigestStore` says `"stub": 0`, and its header names DigestStore (Story 1.12) beside Decide, the runners and AgentSteps. Nothing else in the row changes.
- **The shard.** Lane A's `lane-a` entry of `ci/units.sh` becomes `Agent Bridge Install Tools Digest`.
- **The restart row.** A new last row of `docker/tests/test-production.sh` (and its bullet in the header):
  - it keeps two fixture items of one fixture session through the running `DigestStore` and reads them with `Since`;
  - it restarts the `iris` container cleanly (Task 0 (c)), so IRIS stops and starts and the after-start script runs again;
  - it waits until that start ends ready, and checks that the container's start time changed;
  - it reads the two items again and finds them equal, field for field, to the first reading;
  - then it deletes them.

  Its ObjectScript may live in a class method of `OcuTalon.Test.Digest.Store`.
- **Tests (Rule 19).** Every test creates and removes its own rows: by `ItemId` and by its fixture `SessionRef`s, in `OnAfterOneTest` and also in `OnBeforeAllTests`. Live tests first check `RunnerFixture.RunningReason()` and `WaitAllRun()`. They need the running production of a throwaway, and no model mock.
- **Text.** All new text in `src/`, `ci/` and `docker/` is ASCII (Rule 14). Comments state the contract only.

**Never:**
- **Lane B's files.** Not one of them changes: `OcuTalon.Msg.*` (`ItemDecision` is read only), `OcuTalon.Core.*` (`OutcomeRouter` and its rule included), `OcuTalon.Live.*`, Lane B's `OcuTalon.Data.*` classes, `Test/{Core,Data,Contract,Msg,Web,Live,Demo}/**`, `ci/**` outside Lane A's `lane-a` entry of `ci/units.sh`, and `docker/tests/**` outside the new row of `test-production.sh` and its header bullet.
- **Other stories' work.**
  - No `Tasks()` declaration and no task registration: that is Story 30.2.
  - No `OcuTalon.Bridge.Purge`: that is Story 30.2 too.
  - No digest composition, `OcuTalon.Digest.Process` or `Digest` item: that is Story 17.6.
  - No routing: `OutcomeRouter`'s digest route is Story 2.7's.
- **No other changes.** No change to `Production.cls` (the item is already there, pool 1, enabled), to the bridge or to `src/module.xml`. No new production item, event type, catalog key or setting.
- **No key, no commit and no push.**

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Kept (live) | A fixture `ItemDecision`: new `ItemId`, `OwnerRef` A (a new Ref), `Channel` `mailbox`, `Summary` "Test <ItemId>", a new `DecisionRef`, `Outcome` `digest`. Sent to `DigestStore` with `RunnerFixture.Send`. | 1. **The answer:** OK, with no response object.<br>2. **The row:** exactly one `Item` row for the `ItemId`, with `SessionRef` A and the message's `DecisionRef`, `Channel` and `Summary`. Its `RecordedAt` matches `YYYY-MM-DDThh:mm:ssZ` and lies between `NowUtc()` read just before and just after the send.<br>3. **Nobody notified:** `RunnerFixture.Headers(<the send's session>, "DigestStore")` is empty.<br>4. **No live event:** no `OcuTalon_Live.Event` row has `Stream` A, and none since the test began holds the `ItemId` or the `DecisionRef` in its `Payload`. | OK |
| Kept, instance (live) | The same with `OwnerRef` `instance` | One row with `SessionRef` `instance`. | OK |
| Refused (live) | `Outcome` `tellnow`, `act` or `ignore`; `OwnerRef` `eval` or empty; `ItemId` empty | Each gets an error status whose text names the reason and the `ItemId` when there is one, and no row (by `ItemId`, and by `SessionRef` for the empty `ItemId`). No header from `DigestStore`. | error status |
| Another class (live) | An `Ens.StringRequest` sent to `DigestStore` | Error code 5003, no response, no row. | error status |
| Once (live) | The same `ItemId` sent twice, the second with another `Summary` and `DecisionRef` | 1. **The answers:** both OK.<br>2. **The row:** one row, with the first message's `Summary` and `DecisionRef`.<br>3. **Case counts:** an `ItemId` that differs from it only in the case of its letters is kept as a second item. | OK |
| Since (in process) | Fixture rows of session A at `t1` < `t2` (two rows, saved in that order) < `t3`. One row of session B (A's Ref with the case of its letters swapped) at `t2`. | 1. **From a time:** `Since(A, t2)` gives A's `t3` row, then the second and the first `t2` rows. The boundary is included, and `t1` is not.<br>2. **From the start:** `Since(A, "")` gives A's four rows, newest first.<br>3. **Other sessions:** `Since(B, "")` gives B's row only, and `Since(<an unused Ref>, "")` gives `[]`.<br>4. **The entries:** each has exactly the five keys, with the row's values. | OK |
| Since, refused (in process) | `since` `2026-10-20 08:00:00`, `yesterday` or `2026-13-40T08:00:00Z`; `sessionRef` `""` | An error status each time, and `items` is `[]`. | error status |
| Purge through the task (in process) | Rows of a fixture session recorded now, 89 days ago and 91 days ago. `OcuTalon.Install.Task.Purge` `%New()` (its default `DaysToKeep`), then `OnTask()`. | 1. **The task:** `OnTask()` is OK.<br>2. **The rows:** the 91-day row is gone, and the other two are kept.<br>3. **The registry:** `Registry.Areas()` lists `OcuTalon.Install.Step.Digest`, and `Registry.Order()` does not name `Digest`. | OK |
| Purge, 30 days (in process) | Rows recorded 31 and 29 days ago. `Registry.Purge(30)`. | The 31-day row is gone, and the 29-day row is kept. | OK |
| Purge, refused (in process) | `Install.Step.Digest.Purge` with `""`, `0`, `-1`, `1.5` and `abc`, and a 91-day row in place | An error status each time, and the row stays. | error status |
| Private and durable (in process) | `Install.Step.PrivateData.StorageGlobals(.storage)` | `storage("OcuTalonP.DigestItemD")` and `storage("OcuTalonP.DigestItemI")` name `OcuTalon.Digest.Data.Item`, and `PrivateData.Run()` is OK. So both resolve to OCUTALON_PRIVATE on the durable volume. | n/a |
| Not a stub (in process) | `Test.Install.Production.TestStubsAnswer` | `$Parameter("OcuTalon.Digest.Store", "STUB")` is empty, and the oracle row says `"stub": 0`. | n/a |
| Restart (live script, `test-production.sh`) | Two items kept through `DigestStore` for one fixture session, then the `iris` container restarted | 1. **The restart:** the start after it ends ready, and the container's start time changed.<br>2. **The items:** `Since(<session>, "")` gives the same two entries as before the restart, field for field.<br>3. **The cleanup:** the rows are deleted. | PASS lines |

</intent-contract>

## Code Map

- **The stub and the item (Lane A):**
  - `src/ocutalon/cls/OcuTalon/Digest/Store.cls:1-15`: Epic 0's stub (`STUB = 1`, `OnMessage` answers `$$$NotImplemented`). Rewrite in place.
  - `src/ocutalon/cls/OcuTalon/Production.cls:43`: `DigestStore`, pool 1, enabled, inside Lane A's region (`:15`, `:44`). Unchanged.
  - **The pattern of a real operation that answers nothing:** `src/bridge/cls/OcuTalon/Bridge/Operation/Steps.cls:7-12` (`%IsA`, `pResponse = ""`, other classes `$$$NotImplemented`).
- **The input (Lane B, read only):**
  - `src/ocutalon/cls/OcuTalon/Msg/ItemDecision.cls:5-36`: `ItemId` (22), `SourceItemId`, `OwnerRef` (22), `Channel` (32), `Summary` (80), `DecisionRef` (22), `Outcome` (32), `Fallback`, `FallbackReason`, `CatalogKey`, `Slots`. It has no time field, so `RecordedAt` is the store's.
  - `src/ocutalon/cls/OcuTalon/Data/Time.cls:15-18` (`NowUtc`) and `:22-28` (`ToLocal`, "" for an unreadable time; use it to validate `since`).
- **Table siblings:**
  - `src/ocutalon/cls/OcuTalon/Data/Delivery.cls:5-24` and `Data/WatchMark.cls:5-14`: `DEFAULTGLOBAL` from the registry, a UTC `RecordedAt` of MAXLEN 20, and the doc line of the parameter.
  - `src/ocutalon/cls/OcuTalon/Live/Event.cls:17` (`COLLATION = "EXACT"` on a Ref) and `:30-46` (`Since`, a read that gives dynamic objects with camelCase keys).
- **The registry and the purge (Lane A):**
  - `src/ocutalon/cls/OcuTalon/Install/Step.cls:43-47`: the `Purge(daysToKeep)` contract.
  - `Install/Registry.cls`:
    - `:20-36`, `Areas`: every non-abstract `OcuTalon.Install.Step.<name>`; a class outside `Order()` only declares;
    - `:71-74`, `Purge`, through `CallAreas` (`:78-92`): every area is called, and a failure names its area.
  - `Install/Task/Purge.cls:10-15`: `DaysToKeep` (90), and `OnTask` calls `Registry.Purge`.
  - `Install/Step/PrivateData.cls:27-46`: `StorageGlobals` lists every `^OcuTalonP.` storage global, and `Run` checks that each resolves to OCUTALON_PRIVATE.
- **The CI checks that pick the new class up with no change:**
  - `docker/tests/test-storage.sh:2-12`: the registry rows and the committed `Storage` block;
  - `docker/tests/test-storage-roundtrip.sh:1-14`: every compiled class with storage equals its committed block;
  - `docker/tests/test-class-rules.sh:1-20`: `ai-allowlist`; and `unchecked-prepare`, so use the checked default of `%Prepare` and `%ExecDirect`, with no `ALLOW_UNCHECKED` entry;
  - `Test/Data/Tables.cls:68-84`, `TestSqlNames` (Lane B, shard `lane-b`): no reserved word in any persistent OcuTalon class.
- **CI:**
  - `ci/units.sh:17`: `lane-a) echo "Agent Bridge Install Tools"`.
  - `docker/tests/test-ci-config.sh:586-602`: every `Test/<Area>/` is in exactly one shard.
  - `ci/iris.sh:112-127`: `is_test_case` and `test_classes`.
- **The oracle:**
  - `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`:
    - `:11-13`: the header's list of the items that carry no STUB;
    - `:139-186`: `TestStubsAnswer`;
    - `:604-629`: XData `Items`, with DigestStore's row at `:628`.
  - `docker/tests/test-production.sh:153-183`: row 16's sweep reads the oracle, so DigestStore leaves the sweep with no edit.
- **The test helpers to reuse (Lane A):** `src/ocutalon/cls/OcuTalon/Test/Agent/RunnerFixture.cls`:
  - `RunningReason` (`:81`) and `WaitAllRun` (`:112`);
  - `Send` (`:214-221`, through `ApprovalStartIn`, a stand-in for `OutcomeRouter`);
  - `Headers` (`:275-283`), `SessionOf` (`:380-386`) and `HeaderMark` (`:389-394`).
- **The registry tests, a shared surface:** `src/ocutalon/cls/OcuTalon/Test/Install/Registry.cls`:
  - `TestAreas` (`:61-77`) and `TestOrder` (`:80-97`, 15 steps, unchanged);
  - `TestTasksStep` (`:160-165`), `TestPurge` (`:204-217`) and `TestPurgeTaskDefaults` (`:242-252`): they call `Registry.Purge` with 33, 21, 8 and 90 days, so the Digest area's `Purge` now runs there too.
- **The restart row:**
  - `docker/tests/test-production.sh`: the header at `:2-38`, the end at `:340-353`;
  - `docker/tests/test-production-restart.sh:99-128`: the pattern of a restart (`started_at`, `dc start`, `wait_started_ready 300`, `cid`);
  - `docker/tests/lib-live.sh`: `check_session` (`:465`), `iris_script` (`:303`), `started_at` (`:321`) and `wait_started_ready` (`:358`).
- **For a mutation:** `src/ocutalon/cls/OcuTalon/Live/Publish.cls:52`, `Publish(stream, type, payload, .seq)`.

## Tasks & Acceptance

**Execution:**

**Task 0: measure, and record the facts under `## Verification` (Measured in implementation).**
- **The targets.** Slot A (`ocutalon-slot-a`, namespace `OCUTALON`, after `iris_server_info` shows build 154) for compiles and for facts that need no production. Throwaway tag `e1s12a` for the rest.
- **(a) Reserved words.** On slot A, `$SYSTEM.SQL.IsReservedWord` for `Item`, `SessionRef`, `ItemId`, `DecisionRef`, `Channel`, `Summary` and `RecordedAt`. A reserved one keeps its name and gets an `SqlFieldName` (Conventions).
- **(b) The storage block.** Compile `OcuTalon.Digest.Data.Item` on slot A (`iris_doc_load`), and take the compiler's `Storage Default` block into the committed source.
- **(c) The restart.** In the throwaway of `live production`, measure that a clean restart of the `iris` service (`dc restart iris`, or `dc stop iris` then `dc start iris`) stops IRIS, runs the after-start script again and ends ready. Record how long it takes. The row uses the form that does this.
- **(d) The refusal through the production.** `RunnerFixture.Send` to `DigestStore` gives the store's own error text for a refused `ItemDecision`, so a test can assert what it names.
- **Stop:** if a fact contradicts an AC, stop with status `blocked` and the condition `intent gap: <the AC>, measured <fact>`.

**The digest area (Lane A).**
- `src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls` (new): the table, `Since` and `Purge`, as in Boundaries, with the committed storage block. Rationale: AD-3, AD-4, AD-5, AD-27, AD-33.
- `src/ocutalon/cls/OcuTalon/Digest/Store.cls`: no `STUB`, and the `OnMessage` that keeps, ignores a repeat or refuses; the class doc states the contract. Rationale: AD-1, AD-6, AD-30.
- `src/ocutalon/cls/OcuTalon/Install/Step/Digest.cls` (new): the `Purge(daysToKeep)` declaration only. Rationale: AD-23, AD-27.
- `src/short-names.tsv`: the row `DigestItem`. Rationale: AD-3.
- `ci/units.sh`: `lane-a` gains `Digest`. Rationale: AD-22, and the precedent of Story 1.9 (`Tools`).

**Tests.**
- `src/ocutalon/cls/OcuTalon/Test/Digest/Store.cls` (new): the matrix rows other than "Not a stub" and "Restart":
  - `TestKeeps`, `TestKeepsInstance`, `TestRefuses` (with the other message class) and `TestOnce` (live);
  - `TestSince` and `TestSinceRefuses` (in process);
  - `TestPurgeByTheTask`, `TestPurgeDays` and `TestPurgeRefuses` (in process);
  - `TestPrivate` (in process).

  Its header says what each pins and that the live tests need the running production of a throwaway. The helper for the restart row may live here. Rationale: Rule 8, Rule 19.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: DigestStore's oracle row says `"stub": 0`, and the header names it. Rationale: AD-29 (STUB marks an unbuilt item).
- `docker/tests/test-production.sh`: the restart row, last, and its header bullet. Rationale: NFR-16; the AC's "When IRIS restarts".

**Acceptance Criteria:**
- **AC1, a digest item is kept (Integration AC: the running production delivers the `ItemDecision` to the `DigestStore` item, with `ApprovalStartIn` standing in for `OutcomeRouter` until Story 2.7 merges; FR-1, AD-6, AD-30, AD-33).**
  - **Given** an `ItemDecision` with outcome `digest`, for a session or for `instance`,
  - **when** it reaches `DigestStore` over the running production,
  - **then:**
    - one `OcuTalon.Digest.Data.Item` row holds its `SessionRef` (the `OwnerRef`), `ItemId`, `DecisionRef`, `Channel`, `Summary` and the UTC time it was kept;
    - the store answers OK with no response, sends no message and publishes no live event.

  (`Test.Digest.Store.TestKeeps`, `TestKeepsInstance`)
- **AC2, a real item that keeps only digest items (AD-29, AD-30).**
  - **Given** `DigestStore`,
  - **when** its class and the production oracle are read, or it receives a decision that is not `digest`, one owned by `eval` or by no one, one with no `ItemId`, or a message of another class,
  - **then:**
    - the class carries no `STUB` and the oracle marks it `"stub": 0`;
    - each such message gets an error status (code 5003 for a message of another class), no row is written, and nothing is sent on.

  (`Test.Install.Production.TestStubsAnswer`; `Test.Digest.Store.TestRefuses`)
- **AC3, read for one session since a time (AD-4).**
  - **Given** stored items of several sessions, two of whose Refs differ only in letter case,
  - **when** `Item.Since(sessionRef, since, .items)` is called,
  - **then:**
    - it returns only that session's items recorded at or after `since` (all of them for `""`), newest first;
    - each entry has the five keys;
    - an unreadable `since` or an empty `sessionRef` is an error with no items.

  (`Test.Digest.Store.TestSince`, `TestSinceRefuses`)
- **AC4, stored once (AD-1).**
  - **Given** the same `ItemId` sent to the store twice,
  - **when** the second arrives,
  - **then:**
    - both are answered OK;
    - exactly one row exists, the first's;
    - an `ItemId` that differs only in case is a different item.

  (`Test.Digest.Store.TestOnce`)
- **AC5, intact after IRIS restarts (NFR-16, AD-3, AD-5).**
  - **Given** items kept by the store,
  - **when** IRIS restarts,
  - **then:**
    - they are read back unchanged;
    - their data and index globals are private-mapped, in the database on the durable volume.

  (`test-production.sh`, the restart row; `Test.Digest.Store.TestPrivate`)
- **AC6, the store declares its purge (Integration AC: the purge task `OcuTalon.Install.Task.Purge`, through `Registry.Purge`, calls the Digest area's declaration and the expired items are gone; NFR-19, AD-23, AD-27).**
  - **Given** items older and newer than the retention,
  - **when** the purge task runs with its default `DaysToKeep` (90), or `Registry.Purge(30)` runs,
  - **then:**
    - only the items older than that many days are deleted;
    - a day count that is not a whole number of at least 1 is refused and deletes nothing.

  (`Test.Digest.Store.TestPurgeByTheTask`, `TestPurgeDays`, `TestPurgeRefuses`)

## Spec Change Log

## Review Triage Log

### 2026-10-23 - Review pass
- verdicts: 27 findings - high 0, medium 1, low 19, false 7, maybe-false 0
- findings (blind hunter 1-5, edge case hunter 6-11, verification gap 12-14, intent alignment 15-27):
  - `[low]` `[patch]` 1. Instance-owner live-event check counts only payload matches (`LiveEvents`) - real and known (decision 18); the cheap part is patched (the query answers -1 on an SQL error, mutation recorded); the rest is in `deferred:` with its `reopen_if`.
  - `[low]` `[patch]` 2. "A row at the cutoff stays" is untested, and `<=` would pass - `TestPurgeDays` now retries until a purge falls in the second of the row's time, then asserts the row stays; mutation `<=` -> red.
  - `[low]` `[patch]` 3. `Keep`'s save-failure and race path is untested and not in the class doc - class doc patched; the untested concurrent path is in `deferred:` (pool is 1).
  - `[low]` `[reject]` 4. Purge tests delete non-fixture rows - true, but spec-bound (the matrix names `Registry.Purge(30)` and the purge task) and the existing `Test.Install.Registry` purge tests already do the same on a throwaway; no slot runs these classes (Verification Targets), so a user does not meet it.
  - `[low]` `[patch]` 5. `Store` doc says "session's Ref or instance" but only empty and `eval` are refused - doc reworded; the missing format check is decision 3 (by design).
  - `[low]` `[patch]` 6. Run deadline already spent when the restart block starts - the only reachable harm is a misleading `die` text, which now says the wait is also bounded by the run's deadline.
  - `[low]` `[reject]` 7. `Since` returns an unbounded array - already in `deferred:` (item 1), a duplicate.
  - `[low]` `[reject]` 8. Free-text `OwnerRef` is stored under a SessionRef no session owns - decision 3 (no format check; the row is read by nobody and purged), and the spec's refusal list excludes it.
  - `[low]` `[patch]` 9. `items.%Get(0).recordedAt` on an empty array aborts `TestSince` with an invalid OREF - guarded by `If items.%Size() = 1`.
  - `[low]` `[reject]` 10. `Registry.Purge(30)` runs every area's purge on the test database - same as 4.
  - `[low]` `[reject]` 11. "Ends within about 9 minutes" can overrun by the stop's grace (60 s) - the header says "about", the row runs about 15 s, and a guard would add a branch to a shared script.
  - `[medium]` `[patch]` 12. Another class's "nothing is sent on" is not asserted (AC2) - `TestRefuses` now reads the headers of the `Ens.StringRequest` send; mutation (the branch forwards the request) -> red.
  - `[low]` `[patch]` 13. A day count beyond the calendar's first date (the `If day >= 0` guard) is unpinned - control `Purge(100000)` added to `TestPurgeRefuses`; mutation (guard removed) -> red.
  - `[low]` `[patch]` 14. The live-event check cannot see an `instance` event and cannot fail on a broken query - the second half is patched with 1; the first is in `deferred:`.
  - `[false]` `[reject]` 15. The literal matrix text "Headers(session, "DigestStore") is empty" cannot hold - not a defect of the code: Task 0 (d) measured one reply header with no body in every send, so the tests exclude exactly that header (decision 14); a fix would edit the spec, and the mutation that sends on goes red. Reported as a residual risk.
  - `[low]` `[reject]` 16. The `instance` live-event check is payload-only - same as 1 and 14.
  - `[low]` `[patch]` 17. The refusal code 5001 is not asserted - `TestRefuses` asserts it for each refused decision.
  - `[false]` `[reject]` 18. `OutcomeRouter` to `DigestStore` is not exercised - the intent excludes it (Story 2.7), and `ApprovalStartIn` stands in as the AC says.
  - `[low]` `[reject]` 19. The race-repeat path is untested - same as 3.
  - `[false]` `[reject]` 20. Keep, refuse and repeat run only in the live production - the spec asks for live tests for them (matrix rows 1 to 5), and `Keep` is private by decision 16.
  - `[false]` `[reject]` 21. The restart row does not show the volume itself - AC5's durability is `TestPrivate` plus `PrivateData.Run()` (the private database is on the durable volume); the row shows the rows survive an IRIS stop and start.
  - `[false]` `[reject]` 22. The registry tests now also run the Digest purge - decision 20; the area finds no row there and the class passed.
  - `[false]` `[reject]` 23. Cleanup by prefix instead of by tracked Refs - the same outcome, and it also cleans after a failure.
  - `[false]` `[reject]` 24. `RunnerFixture.ReadyReason` also checks the CI guard - the spec names `RunningReason()` and `WaitAllRun()` and the tests need no mock.
  - `[low]` `[reject]` 25. The restart uses stop and start with extra checks - inside "restarts the iris container cleanly" (decision 19); the checks only add evidence.
  - `[low]` `[reject]` 26. The restart row compares JSON text - the five keys have a fixed order, so text equality is field-for-field equality.
  - `[low]` `[reject]` 27. `short-names.tsv` and the `lane-a` entry carry no dedicated assertion - `storage` and `ci-config` of `bash ci/checks.sh` check both, and passed.

## Design Notes

**The architecture decisions that govern this story (Rule 6):**
- **AD-1:** the store, as an owner, ignores a repeat. One row per `ItemId`.
- **AD-2:** `OcuTalon.Digest` names no `%AI` or `EnsLib.AI` (`test-class-rules.sh` `ai-allowlist`). `OwnerRef` is a session's Ref, `instance` or `eval`.
- **AD-3:** `DEFAULTGLOBAL` `^OcuTalonP.DigestItem`, registered in `src/short-names.tsv`, maps to the private database.
- **AD-4:** the read is scoped to one session, compared exactly.
- **AD-5:** the storage block is committed and append-only. State lives on the durable volume.
- **AD-6:** the store makes no model call. `Summary` is the caller's code-written line.
- **AD-22:** the tests are `OcuTalon.Test.Digest.*`, in shard `lane-a`.
- **AD-23:** an area class outside `Order()` only declares.
- **AD-27:** retention goes through the area's `Purge(daysToKeep)`, called by `OcuTalon.Install.Task.Purge` with its own `DaysToKeep`. No `Setting` read.
- **AD-29:** `ItemDecision` is Lane B's contract, read only. The STUB marker goes when the item is built.
- **AD-30:** digest goes to `DigestStore`, which notifies nobody. Evaluation decisions never reach it.
- **AD-33:** the item and the table are Lane A's (the ownership tables list both), so no spine update is needed.

No acceptance criterion contradicts an AD's Rule. No NFR is unmeasurable: NFR-16 is the restart row, and NFR-19's "90 days by default" is the purge task's `DaysToKeep`.

**Decided in-stage:**
1. **The field names.**
   - `Channel` keeps the message's name for the item's source, so nothing is renamed along the pipeline.
   - `RecordedAt` is the house name of a row's UTC time (`Decision`, `Delivery`).
   - The message has no time of its own, so the time is when the store kept the item.
2. **`instance` is kept as `SessionRef` `instance`.** Intake routes owners that are a session or `instance` to `OutcomeRouter`, and the AC maps `OwnerRef` to `SessionRef` as is. Whether a session's digest also shows `instance` items is Story 17.6's call.
3. **What is refused, and how.** A non-`digest` outcome, an `eval` or empty owner and an empty `ItemId` are refused.
   - **Why:** a tell-now item must never also show as saved for later; an `eval` decision there is a routing bug; and an empty `ItemId` would make every later empty one a "repeat".
   - **How:** an error status, the honest signal. It marks the message in Visual Trace, and Ens logs it.
   - **Not checked:** the format of `OwnerRef`. An odd owner's row is read by no session and is purged, so a format check would only copy `Live.Publish.IsStream` and `CommandCall.IsSessionRef` a third time.
4. **A repeat is silent and keeps the first row.** `Decide` returns the recorded decision for a repeated item (AD-6), so a second `ItemDecision` for an `ItemId` carries the same decision. The unique index makes a concurrent repeat safe as well, if the pool size is ever raised.
5. **EXACT collation on the three Refs**, as `Live.Event.Stream` has it.
   - **Why:** base64url Refs are case-sensitive, and the default SQLUPPER collation would match two sessions whose Refs differ only in case, and would merge two such `ItemId`s into one row.
   - **The tests:** both cases are cheap to pin (AC3, AC4).
6. **`since` is inclusive, and `""` means from the start.** "Saved for later" must lose nothing, and at second resolution an item kept in the digest's own second would fall between two digests with `>`. At worst, an item is mentioned in two digests.
7. **`Since` returns a status, with `items` as an Output.** This differs from `Live.Event.Since`, which throws.
   - **Why:** the house rule is "%Status throughout", and an unreadable `since` is the caller's error, which a production job must see as a status.
   - **The prepare:** it is checked. Production jobs run as the Interoperability system user (AD-24), so the query needs no entry in `ALLOW_UNCHECKED`.
8. **The purge cutoff is computed in the Digest area** from `Data.Time.NowUtc()`, by UTC date arithmetic.
   - **Why not Data.Time:** it has no "days ago" helper, and it is Lane B's.
   - **AD-18 holds:** this converts no zone.
   - **A bad day count:** a day count under 1 is refused. A blank or garbled task property must never delete every item.
9. **Read and purge live on the table, writing in the store.** The store is the only writer, as `Live.Publish` is for `Live.Event`, and the table holds the read (`Live.Event.Since`'s place) and the purge. `Install.Step.Digest` is the area's declaration that AD-23 asks for.
10. **The restart is a real IRIS restart.**
    - **Why:** the AC says "When IRIS restarts". A production restart (Story 1.8's) keeps IRIS running, so it cannot show that the rows are on disk.
    - **Where:** `test-production.sh` is the one live script whose rows Lane A may add. The row goes last, so no earlier row sees a restarted stack.
    - **The fast pin:** `TestPrivate` pins, inside the loop, the storage location that the restart relies on.
11. **No log line for a repeat or a refusal.** Ens logs the refusal's error, and a repeat is the normal at-least-once case.
12. **No change to `Production.cls`.** The item already exists with the right class, pool and enablement. Only the oracle's stub flag changes.
13. **The shard.** `Digest` joins `lane-a` through Lane A's entry of `ci/units.sh`, as `Tools` did in Story 1.9, with no spine change. AD-22's as-built sentence ("`lane-a`: Agent, Bridge and Install") is behind since Story 1.9 (see the lead's items).

14. **The reply header is not a message sent on (Task 0 (d)).**
    - **Measured:** `RunnerFixture.Headers(<the send's session>, "DigestStore")` holds one header for every send, kept or refused: DigestStore's synchronous reply to the service ApprovalStartIn (`target` `ApprovalStartIn`, no body class, no body id). The matrix row "Kept (live)" 3 says the list is empty.
    - **Decided:** the tests read "empty" as no header from DigestStore other than that reply (`Test.Digest.Store.SentOn`). AC1 holds as written ("sends no message"): a request sent to another item is a header with a target and a body class, and the mutation of the table below goes red on it.
15. **The refusal texts.** Error code 5001, and the first failing check names the reason, in the order outcome, ItemId, owner: `DigestStore refuses the item <ItemId>: its outcome is '<outcome>', not digest`; `...: it has no ItemId`; `...: its owner is eval, not a session or instance` or `...: its owner is empty, ...`. The ItemId is left out of the text when the message has none.
    - **A save that fails** (a Summary over 80 characters, an ItemId over 22) is `DigestStore could not keep the item <ItemId>: <the save's text>`, unless a row for the ItemId exists by then, which is a repeat (decision 4).
16. **`Keep` is a private method of the store.** The store is the table's only writer (decision 9), so the write is not a method that another class can call.
17. **A day count is the digits of a whole number, at least 1.** The test is the pattern `1.N` and then `+daysToKeep >= 1`, so `""`, `0`, `00`, `-1`, `1.5` and `abc` are refused (the spec's list, and `00`), and so are `1e2`, `7.0` and `" 5"`, as text. A count so large that the cutoff is before the first date the calendar holds (1840-12-31) deletes nothing and is OK. A refused count never reaches the date arithmetic.
18. **The shape of `Test.Digest.Store`.**
    - **The Refs:** fixture Refs begin with `zzDigest` (22 characters, from a counter in `^OcuTalonTest("Digest","n")`); session B is A with the case of its letters swapped, so it begins `ZZdIGEST`, and the clean-up deletes by both prefixes.
    - **The rows:** read by SQL (`RowOf`), not through the unique index's generated methods, so no test depends on the index being unique.
    - **The live-event check:** counts events since the test began whose payload holds the ItemId or the DecisionRef, and, for a session, events on its own stream. On the shared `instance` stream only the payload counts, since another publisher may use that stream.
    - **The refusals:** each case has an owner of its own, and each asserts that the table's row count did not change (an empty `SessionRef` cannot be counted by a SQL comparison, since an empty string is NULL there).
19. **The restart row stops and starts the container (`dc stop iris`, then `dc start iris`), not `dc restart`.**
    - **Why:** so that the exit code of the stop is read between the two. 0 is a clean shutdown of IRIS; the iris service's `stop_grace_period` is 60 s (only the mock's is 2 s in the CI override), so a stop that needs time is not killed.
    - **A marker in IRISTEMP** (`^IRIS.TempOcuTalonDigestMark`), put before the stop and gone after the start, shows that IRIS itself restarted and not only the container.
    - **The deadline:** the row does not extend the run's deadline; the whole script takes about 95 s here (Task 0 (c)), and the row waits at most 300 s for the start.
20. **No change to `Test.Install.Registry`.** Its purge tests call `Registry.Purge` and assert on their fixture areas; the Digest area now runs in them with 33, 21, 8 and 90 days and finds no row. A search of the test trees for `DigestStore`, `Digest.Store`, `STUB`, `Registry).Purge`, `short-names` and `Areas()` found only the oracle row and header of `Test.Install.Production`, the zone scan of `Test.Bridge.Time` (which reads `Test.Digest`; the new class makes no zone call) and the registry tests above.
21. **Three assertions were added to the pinning tests after review.**
    - **The boundary row:** `Purge` reads the clock itself, so `TestPurgeDays` adds a row at `AgoUtc(30 days)` and purges, retrying up to 20 times until `NowUtc()` read before the add and after the purge is the same second. Then the cutoff is the row's time exactly, and the row must stay. A purge that straddles a second boundary is retried, so the test cannot fail by timing.
    - **A day count beyond the calendar:** `TestPurgeRefuses` holds a control that `Purge(100000)` is OK and deletes nothing (decision 17).
    - **Another class sends nothing on:** the `Ens.StringRequest` block of `TestRefuses` reads the headers of its session (`SentOn`) like the `ItemDecision` rows.
    - **Also:** `TestRefuses` asserts code 5001 for each refused decision, `LiveEvents` answers -1 when its query fails (so a changed `OcuTalon_Live.Event` cannot read as "no event"), and the class doc of `Store` says that only an empty or `eval` owner is refused.

**Integration ACs (Rule 1):**
- **AC1:** the running production (its `ApprovalStartIn` service, a stand-in for `OutcomeRouter` until Story 2.7 merges) delivers the `ItemDecision` to the `DigestStore` item. The observable effect is the row, with nothing sent on.
- **AC6:** the purge task `OcuTalon.Install.Task.Purge` (Story 0.2's) reads the Digest area's declaration through `Registry.Purge`. The observable effect is that the expired items are gone.
- **`Since`:** no consumer in this story; the first consumer will be Story 17.6.

**Consumed-by:**
- **Story 2.7 (Lane B, built in Epic 2, not merged here):**
  - `OutcomeRouter`'s digest route forwards the `ItemDecision` unchanged to `DigestStore`;
  - the store refuses another message class (5003) and a non-digest outcome (an error).
- **Story 17.6 (Lane A):** the digest's "saved for later" part calls `Item.Since(sessionRef, <the last digest's time>, .items)` for the count and the stored summaries.
- **Story 30.2 (Lane A):**
  - its `Tasks()` declaration registers `OcuTalon.Install.Task.Purge`, which calls the Digest area's `Purge(daysToKeep)` with the task's `DaysToKeep`;
  - `OcuTalon.Bridge.Purge` keeps decisions for the same count, so digest items live as long as their decisions;
  - AD-2 keeps the bridge from naming the Digest cutoff, so if Story 30.2 adds a bridge helper for "N days ago", the Digest purge should move onto it.
- **Story 11.5:** the release check reads `STUB`, and DigestStore no longer carries it.

**Consumes:**
- **Epic 0:**
  - `OcuTalon.Msg.ItemDecision` (Story 0.4);
  - the `DigestStore` item and its oracle row (Story 0.6);
  - the step registry, the `Purge(daysToKeep)` contract and the purge task (Story 0.2);
  - `src/short-names.tsv` and the storage checks (Stories 0.4 and 0.7);
  - `Data.Time.NowUtc` and `ToLocal`.
- **Stories 1.3 and 1.5:** `RunnerFixture.Send`, `HeaderMark`, `SessionOf`, `Headers`, `RunningReason` and `WaitAllRun`.

**Extend, don't copy (Rule 2):**
- **The siblings followed:**
  - the store follows `OcuTalon.Bridge.Operation.Steps` (a real operation that answers nothing);
  - the table follows `OcuTalon.Data.Delivery` and `WatchMark` (the registry global, the UTC `RecordedAt`) and `Live.Event` (EXACT Refs, a `Since` read);
  - the area class follows the `OcuTalon.Install.Step` contract, like the registry tests' fixture area.
- **Reused, not copied:**
  - the tests send through `RunnerFixture.Send` and read headers with its helpers;
  - `TestPrivate` calls the product's own `PrivateData.StorageGlobals` and `Run`;
  - `since` is validated through `Data.Time.ToLocal`.
- **Not a sibling yet:** no `Purge(daysToKeep)` is implemented anywhere. The bridge's is Story 30.2's, so this is the first implementation of the contract (decision 8 says how they meet).
- **Copies avoided:** no Ref-format check (decision 3).

**Ledger (Rule 17):** this story's inbox is empty, so there is no entry to address or decline.

**For the lead (rulings recommended, not blocking):**
- **The spine:** AD-22's as-built sentence lists `lane-a` as "Agent, Bridge and Install". Since Story 1.9 it also holds `Tools`, and with this story `Digest`. The recommendation is a text correction in the Rule 20 light path: `lane-a` holds Lane A's areas.
- **CI time:** the restart row adds one clean IRIS restart to `live production`. That is under a minute on the developer machine and about 2 to 3 minutes on the x64 runner `(inference: from the upgrade-start figures of S1 and the run records)`. Task 0 (c) measures it. The `production` group (10 to 12 minutes) stays under the `install` group (about 14 minutes), so REL-4's 35 minutes holds.
- **The veto window:** nothing of this story is in it. The table is the spine's own (the ownership tables), its fields are the AC's, and its retention is the purge task's 90 days.

## Verification

**Targets:**
- **The slot.** `ocutalon-slot-a` only (MCP `server: ocutalon-slot-a`, `namespace: OCUTALON`, after `iris_server_info` shows build 154), for `iris_doc_load` compiles and Task 0 (a) and (b). No test class runs there.
- **Throwaways.**
  - Everything else runs through `ci/iris.sh`, with `OCUTALON_RUN_TAG=e1s12a OCUTALON_LOCK_OWNER='epic=1 stage=implement' OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-a OCUTALON_TEST_WEB_PORT=52801`.
  - QA uses the tag `e1s12q` (`stage=qa`), and review uses `e1s12r` (`stage=code-review`).
  - One stack at a time, one command per call, each with `timeout: 600000`.
- **Never** `ocutalon-aihub-test`, `ocupilot*`, `iris-community-edition`, `ocutalon-slot-b` or `ocutalon-slot-c`. No push, no `gh workflow run`, and never read `.env`.

**Commands** (each with the variables above):
- **(loop)** `bash ci/checks.sh`. Expected: every block passes, among them `storage` (the registry row and the committed block), `class-rules`, `ci-config` (`Test/Digest` in exactly one shard) and `boundaries`. About 20 s.
- **(loop)** `bash ci/iris.sh build`. Expected: exit 0.
- **(loop)** `bash ci/iris.sh class <Class>`, one call per class, for `OcuTalon.Test.Digest.Store`, `OcuTalon.Test.Install.Production` and `OcuTalon.Test.Install.Registry`. Expected: `CLASS ... passed`, about 1 to 2 minutes a call.
- **(loop)** `bash ci/iris.sh teardown`. Expected: it removes only `e1s12a`'s projects.
- **(once)** `bash ci/iris.sh shard lane-a`. Expected: every class passes, `Test.Digest.Store` included. The only SKIP is the existing `TestStepHelpers`.
- **(once)** `bash ci/iris.sh shard lane-b`. Expected: every class passes, `Test.Data.Tables` (`TestSqlNames`, the private records) and `Test.Contract.Ac` included.
- **(once)** `bash ci/iris.sh live production`. Expected: PASS for every row, the restart row and row 16's sweep (one stub fewer) included.
- **(once)** `bash ci/iris.sh live production-restart`. Expected: PASS (the kill and restart with the new table).
- **(once)** `bash ci/iris.sh live storage-roundtrip`. Expected: PASS. The compiled block of `OcuTalon.Digest.Data.Item` equals the committed one.
- **(once)** `bash ci/iris.sh live demo-path`. Expected: PASS, with `@floor` passed.
- **(once)** `bash ci/iris.sh teardown`. Expected: nothing of `e1s12a` is left.

**Shared surfaces:**
- **The production's item roster and DigestStore's stub flag.**
  - **Where:** `Test.Install.Production` (its XData `Items`, `TestStubsAnswer`'s count of stubs, its header), and `test-production.sh` row 16, which sweeps the oracle's enabled stubs (one fewer, no edit).
  - **Later:** Story 11.5's release check.
- **`src/short-names.tsv`** gains a row: `test-storage.sh` (the registry rules), and `Test.Data.Tables` (at least 23 rows, its own list; unchanged).
- **The set of persistent classes** gains one:
  - `Test.Data.Tables.TestSqlNames` (at least 45, plus the reserved-word check);
  - `Install.Step.PrivateData` (every `^OcuTalonP.` global, at every start);
  - `test-storage-roundtrip.sh` (the compiled set equals the committed set).
- **`Registry.Areas()`** gains `OcuTalon.Install.Step.Digest`.
  - **What runs it:** `Test.Install.Registry`'s `TestTasksStep`, `TestPurge` and `TestPurgeTaskDefaults` now also run the Digest purge with 33, 21, 8 and 90 days, and delete any digest row older than that.
  - **What does not change:** `TestOrder` (15 steps) and `TestAreas` (no count).
- **The `lane-a` shard** gains the `Digest` area: `ci/units.sh`, `ci/iris.sh classes lane-a`, and `test-ci-config.sh`'s units rule.
- **Lane A's test packages:** `Test.Bridge.Time.TestZoneCase` scans `Test.Digest` too. The new class makes no zone call.
- **Production state during the live tests:** `ItemDecision` messages and their headers, `Item` rows of fresh Refs (removed), and no setting, item class or key changed.
- **The search:** search the test trees for `DigestStore`, `Digest.Store`, `STUB`, `Registry).Purge`, `short-names` and `Areas()`.

**Standing criterion:** every test added or changed passes on a fresh environment, in either order. The lead runs `shard lane-a` and `shard lane-b` forward, then both with `--reverse`.

**Mutations to demonstrate (Rule 19),** at least one per AC. Record each as `mutation: <change> -> <test went red>`.

| AC | Change | Test that goes red |
| --- | --- | --- |
| AC1 | the store saves `DecisionRef` empty | `Digest.Store.TestKeeps` |
| AC1 | the store also sends the `ItemDecision` on to another item (`SendRequestAsync`) | `Digest.Store.TestKeeps` (a header from DigestStore) |
| AC1 | the store publishes a live event on the owner's stream | `Digest.Store.TestKeeps` (the live-event check) |
| AC2 | `Parameter STUB = 1` is put back | `Install.Production.TestStubsAnswer` |
| AC2 | the outcome check is removed | `Digest.Store.TestRefuses` (a `tellnow` row) |
| AC3 | `Since` leaves out the `SessionRef` condition | `Digest.Store.TestSince` |
| AC3 | `Since` compares with `>` instead of `>=` | `Digest.Store.TestSince` (the boundary rows) |
| AC3 | `SessionRef` without `COLLATION = "EXACT"` | `Digest.Store.TestSince` (B's row read for A) |
| AC4 | the repeat check and the unique index are removed | `Digest.Store.TestOnce` (two rows) |
| AC5 | `DEFAULTGLOBAL` is `^IRIS.TempOcuTalonDigestItem` | `Digest.Store.TestPrivate`; the restart row of `live production` |
| AC6 | `Install.Step.Digest` declares no `Purge` | `Digest.Store.TestPurgeByTheTask` |
| AC6 | the cutoff is `daysToKeep - 2` days back | `Digest.Store.TestPurgeByTheTask` (the 89-day row gone) |
| AC6 | the day-count check is removed | `Digest.Store.TestPurgeRefuses` |

### Measured in implementation (Task 0; slot A for (a) and (b), throwaway tag `e1s12a` for (c) and (d), build 154)

- **(a) Reserved words.** On slot A, `$SYSTEM.SQL.IsReservedWord` is 0 for `Item`, `SessionRef`, `ItemId`, `DecisionRef`, `Channel`, `Summary` and `RecordedAt` (and for `Since` and `Purge`). No property needs an `SqlFieldName`.
- **(b) The storage block.** `OcuTalon.Digest.Data.Item` compiled on slot A with `ck` and no warning. The compiler's `Storage Default` block is the committed one: the data `ItemDefaultData` with `%%CLASSNAME` and the six properties in the order of the class (values 2 to 7), and `^OcuTalonP.DigestItemD` (data and id), `^OcuTalonP.DigestItemI` (index) and `^OcuTalonP.DigestItemS` (stream). The document exported from slot A after loading the committed file ends with the same block.
- **(c) The restart** (`live production`, Apple-silicon Docker, warm image).
  - **The form:** `dc stop iris`, then `dc start iris`. The stop took 2 s and left the container's exit code at 0, a clean shutdown (the service's `stop_grace_period` is 60 s). The start ended `ready` (this start's after-start log, begun after the container's new start time, and Docker `healthy`) 7 to 12 s after the start command (12 s, 12 s and 7 s in three runs; the first run, before the row printed the two times, printed 8 s from the stop to ready).
  - **IRIS restarted:** the container's `StartedAt` changed, and a marker global in IRISTEMP, put before the stop, was gone after the start.
  - **The cost of the row:** about 10 to 15 s. The whole `live production` took 94 to 96 s. The spec's estimate for the x64 runner (2 to 3 minutes) is not measured here.
  - **Row 16's sweep:** 16 enabled stubs with a pool (one fewer than before), every one PASS.
- **(d) The refusal through the production.** `RunnerFixture.Send` to `DigestStore` gives the store's own error status for a refused `ItemDecision` (code 5001), whose text holds `DigestStore`, the reason and the `ItemId` (asserted by `TestRefuses` for each case), and for an `Ens.StringRequest` code 5003 with no response. A kept decision and a refused one each leave exactly one header with DigestStore as its source: its reply to ApprovalStartIn, with no body class and no body id (decision 14). A request to another item would be a second header.
- **Time in the class:** `Test.Digest.Store` runs in 0.3 to 1.8 s inside the class, 52 to 58 s with the stack.

### Mutations demonstrated (Rule 19; throwaway tag `e1s12a`)

Each mutation was applied to the working tree, the test run, and the tree put back; `git status --short` and `git diff --stat` were unchanged, and a hash of the status, the tracked diff and the untracked files' contents was the same before and after (`547a44d821628fd2` on the final tree).

- mutation: the store saves `DecisionRef` empty -> `Digest.Store.TestKeeps`, `TestKeepsInstance` and `TestOnce` went red
- mutation: the store also sends the `ItemDecision` on (`SendRequestAsync("EvalSink", decision)`) -> `Digest.Store.TestKeeps` and `TestKeepsInstance` went red (a header from DigestStore other than its reply)
- mutation: the store publishes a `notification` live event on the owner's stream (`Live.Publish.Publish`) -> `Digest.Store.TestKeeps` went red (the live-event check); `TestKeepsInstance` stays green, since an empty payload on the shared `instance` stream is not counted (decision 18)
- mutation: `Parameter STUB = 1` is put back -> `Install.Production.TestStubsAnswer` went red (DigestStore does not carry STUB, and the count of stubs)
- mutation: the outcome check is removed -> `Digest.Store.TestRefuses` went red (the `tellnow`, `act` and `ignore` rows)
- mutation: `Since` leaves out the `SessionRef` condition (`WHERE (SessionRef = ? OR 1 = 1)`) -> `Digest.Store.TestSince` went red (the four rows of A, B's row, the unused Ref)
- mutation: `Since` compares with `>` instead of `>=` -> `Digest.Store.TestSince` went red (the boundary rows), and no other assertion
- mutation: `SessionRef` without `COLLATION = "EXACT"` -> `Digest.Store.TestSince` went red (B's row read for A, and A's for B)
- mutation: the repeat check (both calls of `ItemIdIndexExists`) and `[ Unique ]` are removed -> `Digest.Store.TestOnce` went red (two rows for the ItemId)
- mutation: `DEFAULTGLOBAL` and the four storage locations are `^IRIS.TempOcuTalonDigestItem...` -> `Digest.Store.TestPrivate` went red (six assertions), and the restart row of `live production` went red (`FAIL digest restart: the items read after the restart differ from the reading before it`, every other row PASS)
- mutation: `Install.Step.Digest` declares no `Purge` (the method is renamed) -> `Digest.Store.TestPurgeByTheTask` (the 91-day item is not gone), `TestPurgeDays` and `TestPurgeRefuses` went red
- mutation: the cutoff is `daysToKeep - 2` days back -> `Digest.Store.TestPurgeByTheTask` (the 89-day item is gone) and `TestPurgeDays` went red
- mutation: the day-count checks are removed (`1.N` and the minimum of 1) -> `Digest.Store.TestPurgeRefuses` went red (all six bad counts, `""`, `0`, `-1`, `1.5`, `abc` and `00`, deleted the 91-day item, and five of them were accepted; `1.5` failed in the date arithmetic)

After review, four mutations at once, each in code that only one test reads (tree restored, `git status --short`, `git diff --stat` and the SHA-1 of the five changed files identical before and after):

- mutation: the other-class branch of `OnMessage` also sends the request on (`SendRequestAsync("EvalSink", pRequest)` before the 5003) -> `Digest.Store.TestRefuses` went red on "and DigestStore sent no message but its reply" only (the six `ItemDecision` rows stayed green)
- mutation: `Purge` deletes with `RecordedAt <= ?` instead of `< ?` -> `Digest.Store.TestPurgeDays` went red on "the item recorded exactly at the cutoff is kept"; no other test went red on it
- mutation: the `If day >= 0` guard of `Purge` is `If 1` -> `Digest.Store.TestPurgeRefuses` went red on the `Purge(100000)` control (`<VALUE OUT OF RANGE>`)
- mutation: `LiveEvents` reads a column that does not exist (`Payloadx`) -> `Digest.Store.TestKeeps` and `TestKeepsInstance` went red on the live-event check (the query answers -1)

**Lead's rulings at the spec gate (2026-10-24, Epic 1 runner, unattended):**
- **Decided:** the table as planned (the AC names its fields and retention; AD-33 lists it), the real IRIS restart row in `test-production.sh`, and the planner's 13 in-stage choices.
- **No spine edit here:** AD-22's as-built `lane-a` area list is left for the orchestrator's merge reconciliation.

## Auto Run Result

Status: done
Blocking condition: none

**Plan stage (2026-10-23).** The spec was planned on the epic-story path from the committed `epic-1-context.md`, with Story 1.10's spec as continuity, and checked against the READY FOR DEVELOPMENT standard. The run halted after planning, as the dispatch asked. Nothing was implemented, measured on a runtime or committed.

**Implement stage (2026-10-23).**
- **Summary of the change.** `DigestStore` is a real business operation with no `STUB`. It keeps each digest `ItemDecision` as one row of the new `OcuTalon.Digest.Data.Item` (once per `ItemId`, EXACT collation on the three Refs, private global `^OcuTalonP.DigestItem`), answers OK with no response, sends nothing and publishes nothing, and refuses any other outcome, an empty `ItemId` and an `eval` or empty owner with an error status (5001) that names the reason and the `ItemId`. `Item.Since` reads one session's items since a time, newest first. `Item.Purge` deletes the older ones, and the area class `OcuTalon.Install.Step.Digest` declares it to the purge task. `Digest` joins the `lane-a` shard, and `live production` has a last row that restarts the iris container and reads the items back.
- **Files changed.**
  - `src/ocutalon/cls/OcuTalon/Digest/Data/Item.cls` (new): the table, `Since`, `Purge`, the committed storage block.
  - `src/ocutalon/cls/OcuTalon/Digest/Store.cls`: the real operation.
  - `src/ocutalon/cls/OcuTalon/Install/Step/Digest.cls` (new): the `Purge(daysToKeep)` declaration.
  - `src/short-names.tsv`: the `DigestItem` row.
  - `ci/units.sh`: `Digest` in `lane-a`.
  - `src/ocutalon/cls/OcuTalon/Test/Digest/Store.cls` (new): the matrix tests and the restart row's helpers.
  - `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: DigestStore's oracle row says `"stub": 0`, and the header names it.
  - `docker/tests/test-production.sh`: the restart row, last, and its header bullet.
- **Review.** Four layers reported 27 findings: 1 medium, 19 low, 7 false. Patches applied: 8 entries (1 medium, 7 low), listed in the triage log. Items deferred: 3 (the unbounded `Since`, the payload-only live-event check for `instance`, the untested concurrent-repeat path), each with its `reopen_if` where it is a closed LOW. Rejected: 14 findings, each with its reason in the triage log.
- **Follow-up review recommendation: false.** One medium entry was patched (fewer than two) and no high.
- **Verification performed.** `bash ci/checks.sh` passed (every script). `ci/iris.sh build` exited 0. `ci/iris.sh class` passed for `Test.Digest.Store`, `Test.Install.Production` and `Test.Install.Registry` after the review patches. `ci/iris.sh shard lane-a` passed (39 classes, the only SKIP is the existing `TestStepHelpers`) and `shard lane-b` passed (24 classes, `Data.Tables` and `Contract.Ac` among them). `live production` passed (30 PASS, the digest restart rows and row 16's sweep of 16 stubs among them), `live production-restart` passed, `live storage-roundtrip` passed and `live demo-path` passed with `@floor` (1 of 1). `ci/iris.sh teardown` for `e1s12a` left nothing. The matrix test audit found every row covered by a test that ran and passed. Mutations: 13 before review and 4 after, each red in the test named under `## Verification`, each reverted byte-identical.
- **Residual risks.**
  - **Matrix row 3 of "Kept (live)" is read, not literal.** `Headers(session, "DigestStore")` holds one reply header to `ApprovalStartIn` with no body in every send (Task 0 (d), decision 14). The tests count only headers other than that reply; AC1's "sends no message" holds and the sending mutations go red. The lead may want to amend the matrix text.
  - **AD-22's as-built `lane-a` area list is behind** (it now holds `Tools` and `Digest`); left to the orchestrator as the lead ruled.
  - **The restart row's runner time is not measured.** The stop took 2 s and the start 6 to 12 s on the Apple-silicon machine; the x64 figure is an inference.
  - **The reverse-order runs (`--reverse`) of Rule 19 are the lead's.** They were not run here.
