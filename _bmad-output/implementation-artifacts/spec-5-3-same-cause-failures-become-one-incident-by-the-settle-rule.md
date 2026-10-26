---
title: 'Same-cause failures become one incident by the settle rule'
type: 'feature'
created: '2026-10-25'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `IncidentManager` only completes `FailureBatch` messages (Story 5.2), so failures in a watched production lead nowhere: there is no `Incident`, no `FailureGroup`, no `watch.progress` and no settle rule. UJ-1 needs the 50 failed orders to become one incident, and later one notice. Separately (DW-227), the fresh `lane-a` shard finishes only about a minute under the 10-minute foreground cap, and this story adds classes to it.

**Approach:** `IncidentManager` groups each batch's new failures (those it does not already hold, keyed `h<HeaderId>`/`l<LogId>`) by production item and error pattern, per production and scope, into one open incident per cause. The incident gets its `Ref` at the first failure, and `watch.progress` `noticed` and `settling` go to each recipient session's stream. One waiter per new group re-reads the rows on each wake and ends the settle rule (10 s quiet, or 30 s after the first failure, both from settings) by fixing `NoticeCount`. After the notice, same-cause failures update only `Count` and the `incident` event. The notice itself is sent by Story 5.4 (ruling R2). The first task gives `ci/iris.sh shard` a local `--part k/n` split.

## Boundaries & Constraints

**Always:**
- `OcuTalon.Watch.IncidentManager` alone writes `Incident` and `FailureGroup` rows, and alone publishes `incident` and `watch.progress`. It publishes through `OcuTalon.Live.Publish`, only after its own change has committed and never inside a transaction (AD-12, AD-15, AD-33). Its item keeps `PoolSize="1"`, so its one job serializes every row change: batches, wakes and, later, commands.
- **Same cause** means the same `Namespace`, `Production`, `OwnerRef` (the batch's scope), `ItemName` and error pattern, compared exactly (never under SQL's default case-folding collation). The **error pattern** is the failure's `ErrorText` with each run of digits replaced by `#`, whitespace runs collapsed to one space, and the result trimmed. A failure joins the newest incident of its cause that is not `closed`. When there is none, IncidentManager makes a new incident and group: `State` `open`, empty `OpenVariant`, `NoticedAt` and `NoticeCount`, and `Ref` from `OcuTalon.Bridge.Ids.NewRef()`.
- **A failure is held once.** If its key (`h<HeaderId>` or `l<LogId>`, as `Watch.Mark` keys it; spine row "Watch failures") is already in its group's `Seen`, the failure is ignored: it adds no count and no time. `Seen` keeps the keys of the group's newest 1000 failures (ruling R1).
- `Count` is the number of failures held. `FirstAt` and `LastAt` are the earliest and latest `FailedAt` held (UTC to the second). `NoticeCount` is set once, at the settle end, to `Count` at that moment, and never changes after that.
- **Settle rule.** Each new group gets one waiter: an `IncidentManager` instance started by an `OcuTalon.Watch.Msg.Settle` request that IncidentManager sends itself. On each wake the waiter re-reads the incident and group rows. The rule ends when `now - LastAt >= quiet` or `now - FirstAt >= max`, whichever comes first. `quiet` comes from `OcuTalon.Data.Setting.Get("watch.settleQuietSeconds", 10)` and `max` from `Get("watch.settleMaxSeconds", 30)`; a value that is not a positive integer gives the default. The decision never depends on memory (AD-5). A waiter whose row is gone, closed or already settled completes without writing anything.
- Each waiter starts the incident's own trace session: IncidentManager sends the waiter's `Settle` request with `%SessionId` cleared, keeping the batch's `SuperSession`. The incident's `TraceHeaderId` is that session (AD-26).
- **Events** go to each session that `OcuTalon.Data.Session.Recipients(ownerRef, incidentRef)` returns:
  - `watch.progress` `noticed` once when the incident is made, and `settling` once when its waiter starts, as `OcuTalon.Live.Payload.WatchProgress` (ref and stage only);
  - before the notice, no `incident` event and no count;
  - after the notice (`NoticedAt` set), each batch that adds failures publishes one `incident` event, `Live.Payload.Incident.FromRow(row)` (the same builder `/state` uses), to each recipient.

  A failed `Recipients` read or a failed publish logs one Type 3 warning and publishes nothing, and the rows stand. A failed read never means "nobody watches" (DW-68).
- Anything other than a `FailureBatch` or a `Settle` is still answered 5003, and `STUB` stays. So `Test.Install.Production`'s stub row and Epic 4's `CommandsInProduction` row (`Dismiss` answers `not_built`) stay true.

**Never:**
- Before the notice: no `NoticedAt`, no `Notification`, no notice text and no `incident` event. The notice (diagnosis, the three variants, `NoticedAt`, one `Notification` per recipient session) is Story 5.4's (ruling R2). 5.3 sends no fallback notice either: its text names a model fallback reason, and only the bridge classifies one (AD-8).
- No state move other than making `open` incidents (that table is Story 5.5's), no `IncidentCommand` handling, no `closeQuiet`, no evidence pack, and no namespace switch or IRIS read (the batch carries everything).
- No edit to a contended path except the one `Test/Data/Tables.cls` entry under ruling R1. No change to `Msg/*`, `Core/*`, `Data/Session.cls`, `Data/Ownership.cls`, `Data/Setting.cls`, `Live/Publish.cls`, `Production.cls`, `ci/units.sh` or the CI workflows. No setting rows seeded (the code defaults stand until the settings page exists).
- No embedded SQL and no unchecked prepare (`ci/checks.sh` class rules). No NFR-7 time assertion: test waits are test bounds only.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Burst (real poller) | Session A watches Orders; 50 failing orders tagged with A's `TraceRef` | One `Incident`: `OwnerRef` A, OCUORDERS, `OcuTalon.Demo.Orders.Production`, `open`, `Count` 50, `FirstAt`/`LastAt` the first/last `FailedAt`, `NoticedAt` empty. One `FailureGroup`: `OrdersFromPartner`, the pattern of the measured sentence. A's stream gets `noticed` then `settling` for that `Ref`, and no `incident` event. At `LastAt` + 10 s (plus up to one wake) `NoticeCount` is 50, and `NoticedAt` is still empty | none |
| Trickle | One same-cause failure every 4 s (direct batches) | The settle ends at `FirstAt` + 30 s, with `NoticeCount` the count by then. Later failures raise `Count` and keep `NoticeCount`; there is still one incident | none |
| Re-sent | A batch repeats keys already held, plus new ones | The held keys are ignored; only the new ones count | none |
| Pattern | The same item with "got '10/16/2026'" and "got '10/17/2026'"; another item; other words | The two dates form one group. Another item, or other words, gives its own incident | none |
| Two sessions | A-tagged and B-tagged failures with the same item and pattern | Two incidents (owners A and B). Each stream holds only its own incident's events. Once both are noticed (fixture), `Ownership.Incidents(A)` lists only A's and `Ownership.Incidents(B)` only B's | none |
| Instance shared | A and B watch Orders; untagged failures | One incident with owner `instance`; `noticed` and `settling` on both A's and B's streams | none |
| After the notice | A noticed incident (fixture: `NoticedAt` and `NoticeCount` set, as 5.4's notice will set them); a same-cause batch arrives | `Count` and `LastAt` move, `NoticeCount` stays, and one `incident` event (`FromRow`, with the new count) goes to each recipient. No second incident, and no `Notification` carrying the `IncidentRef` | none |
| Before the notice | Any incident with `NoticedAt` empty | `Ownership.Incidents`, `RecentIncidents` and `Incident(ref)` leave it out for every session | none |
| Closed | A same-cause failure after the incident's `State` is `closed` (fixture) | A new incident with a new `Ref` and its own `noticed` | none |
| Restart while settling | IncidentManager temporarily stopped and started again during the wait | The settle still ends once (`NoticeCount` set). A waiter whose incident was deleted completes OK and writes nothing | none |
| Nobody to tell | An `instance` incident on a production nobody watches | The incident and group rows are made, and no event is published | none |
| Trace | Any new incident | `TraceHeaderId` is a session other than the batch's, and its first header's `SuperSession` is the scope's `TraceRef` (empty for `instance`) | none |
| Settings | `watch.settleQuietSeconds` 4 and `watch.settleMaxSeconds` 12 given in the process; absent; `0`; `x` | `Settle.Values` gives 4/12; the default 10/30 for absent, `0` and `x` | none |

</intent-contract>

## Code Map

Every `OcuTalon/...` path is under `src/ocutalon/cls/`.

- `OcuTalon/Watch/IncidentManager.cls` -- the 5.2 stub BP (27 lines): it completes a `FailureBatch`, answers 5003 to anything else, and has `STUB` 1. Build it here. Precedents: `Ens.BusinessProcess.SetTimer` (`irislib/Ens/BusinessProcess.cls:189`: an `Ens.AlarmRequest` whose `Timeout` takes seconds or a duration, answered into `OnResponse` with the completion key); `SendRequestAsync` (:160, `pResponseRequired` 0 for the self-send); and a BP's `%SessionId`/`%SuperSession`, passed by value to `acceptRequestAsync` (:224, :259).
- `OcuTalon/Data/Incident.cls` -- every property this story needs already exists (`Ref`, `OwnerRef`, `Namespace`, `Production`, `State`, `NoticedAt`, `Count` (SQL `FailureCount`), `NoticeCount`, `FirstAt`, `LastAt`, `TraceHeaderId`), with the `RefIndex` and `OwnerRefIndex` indexes.
- `OcuTalon/Data/FailureGroup.cls` -- has only `IncidentRef`, `ItemName` and `ErrorPattern`. It needs `Seen` (ruling R1).
- `OcuTalon/Test/Data/Tables.cls` (Epic 16, CONTENDED) L522-531 -- the Contracts entry for `OcuTalon.Data.FailureGroup`. `TestContracts` compares the property set exactly, through `Test/Contract.cls` `CompareProperty` (which understands only `list Of` collections, hence a plain `%String`).
- `OcuTalon/Watch/Mark.cls` L60-64 -- `Key(failure)` reads a reader row (`kind`, `headerId`, `logId`). A batch item is an `OcuTalon.Watch.Msg.Failure` serial (`Kind`, `HeaderId`, `LogId`), so the key rule is extended to take its parts.
- `OcuTalon/Watch/Msg/FailureBatch.cls`, `Watch/Msg/Failure.cls` -- the input: `Namespace`, `Production`, `OwnerRef`, `PolledAt`, and `Failures` (`Kind`, `HeaderId`, `ItemName`, `ErrorText` redacted sentence, `FailedAt` UTC to the second, `LogId`).
- `OcuTalon/Data/Session.cls:93` `Recipients(ownerRef, incidentRef, .sc)` (Lane B, call-only) -- a session's Ref, or for `instance` the watchers of the incident's production (`Ownership.Watchers`), none on the online demo. An error in `sc` means nothing.
- `OcuTalon/Data/Ownership.cls:42` `INCIDENTVISIBLE` (`NoticedAt <> ''`), `Incidents` L226, `RecentIncidents` L233 (what `/state` reads, `Web/Api.cls:313`), `Incident` L283 (Lane B, call-only).
- `OcuTalon/Live/Publish.cls:52` `Publish(stream, type, payload, .seq)` (Lane B, contended: call only); refused inside a transaction. `Live/Payload/Incident.cls:65` `FromRow`; `Live/Payload/WatchProgress.cls` (`Ref`, `Stage`, `STAGES` `noticed,settling,diagnosing`).
- `OcuTalon/Data/Setting.cls` `Get(key, default)` (Lane B, call-only) -- any key, with a 60-second per-process cache `^||OcuTalon.Setting(key) = $ListBuild(value, present, $ZHorolog)`.
- `OcuTalon/Production.cls:39` -- `IncidentManager` `PoolSize="1"`, unchanged. `Test/Install/Production.cls:139` `TestStubsAnswer` and the `:624` row (stub 1) stay as they are. `Test/Core/CommandsInProduction.cls:49,151` (Epic 4) expect `Dismiss` to answer `not_built` through `Core/CommandsIn.cls:145` `IsStub` (code 5003).
- `OcuTalon/Test/Watch/Case.cls` -- the base of the watch tests: `Watch` L399, `Fail` L427, `Since`/`Batches` L600-608, `DropRows` L407, and the hooks `OnBeforeOneTest` L100 and `OnAfterOneTest` L113. `Test/Core/RoutingProduction.cls:248` `SendTo` sends a message to an item from an adapterless host created in the test process, with a `SuperSession`. `Test/Core/Observe.cls:46` `Events(session, type, count, seconds)`. `Test/Data/Fixture.cls:292` `Clean` drops the fixture sessions' streams (Epic 16, call-only).
- `OcuTalon/Test/Bridge/CodeRules.cls:194` `TestOnlyTheAuditWriterAudits` and `:875` `Offenders(pattern, allowed)` -- the pattern for a "only X writes Y" rule.
- `ci/iris.sh` -- the usage header L7-28 (printed by `usage`), `test_classes` L134 (name order), `cmd_shard` L326-351 (`--reverse` sorts the list with `sort -r`, then calls `run_classes "shard-$name" "<title>" $classes`), and sourcing is safe (L508).
- `docker/tests/test-ci-config.sh` -- `shard_order` L1524-1545 sources `ci/iris.sh` with a `run_classes` stub. The file ends L1688-1698 with its summary and `exit 1` on failure.

## Tasks & Acceptance

**Execution:**
- Task 0 (DW-227, tooling, done first): in `ci/iris.sh`, `cmd_shard` accepts `--part k/n` in any position. After ordering (name order, or reversed with `--reverse`), it splits the class list into n contiguous parts whose sizes differ by at most one (the first `count mod n` parts are one larger) and runs part k. The title is `<name> part k/n` (`<name> (reversed) part k/n`); the label `shard-<name>` is unchanged; warm mode works as before. A malformed value, k < 1, k > n, or n greater than the shard's class count is refused with exit 2, naming `--part`. Without `--part`, nothing changes. The usage header documents the option. In `docker/tests/test-ci-config.sh`, one self-contained block is appended after the last line, changing no existing line: it sources `ci/iris.sh` with a `run_classes` stub, as `shard_order` does, and checks the following. It prints `PASS shard part` or `FAIL shard part` and exits 1 on failure (it runs only after the earlier summary has passed).
  - For n = 1, 2 and 3, parts 1..n joined in order equal `ci/iris.sh classes lane-a`, every part is non-empty, part sizes differ by at most one, and each title carries `part k/n`.
  - With `--reverse`, the joined parts equal the reversed list.
  - `0/2`, `3/2`, `2`, `a/b`, `1/0` and `1/999` exit 2.

  `ci/units.sh` and the workflows stay unchanged. Measure both parts of a fresh `shard lane-a --part k/2` and record the times under Verification.
- `src/ocutalon/cls/OcuTalon/Data/FailureGroup.cls` -- [ruling R1] add `Seen` (`%String(MAXLEN = "")`: the keys of the group's newest failures, comma-separated, newest last, at most `SEENMAX` 1000, which is two polls' worth of `Mark.MAXFAILURES`). The compiler appends the storage slot, and the slot is committed (AD-5).
- [Epic 16's file; footprint extension by ruling R1] `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` -- in the Contracts XData only: `"OcuTalon.Data.FailureGroup"` → `"props"` gains `"Seen": "%String(MAXLEN=)"`. Nothing else in the file changes.
- `src/ocutalon/cls/OcuTalon/Watch/Mark.cls` -- the key rule takes the parts (for example `KeyOf(kind, headerId, logId)`); `Key(row)` calls it. IncidentManager keys a `Watch.Msg.Failure` with it.
- `src/ocutalon/cls/OcuTalon/Watch/Settle.cls` -- new pure class:
  - `Pattern(text)`: the error pattern;
  - `Values(.quiet, .max)`: the two settings, with their defaults;
  - `Wait(firstAt, lastAt, now, quiet, max)`: 0 when the rule has ended, otherwise the whole seconds until the earlier of `LastAt + quiet` and `FirstAt + max`, at least 1;
  - `Hold(seen, keys)`: the new `Seen`, trimmed to `SEENMAX`, and which of the keys were new.

  `Data.Time` has no time arithmetic, so `Wait` turns the UTC ISO stamps into seconds itself (`$ZDateTimeH` with the `T` and `Z` removed, as `Mark.Shift` does for IRIS stamps); `now` is `Data.Time.NowUtc()`.
- `src/ocutalon/cls/OcuTalon/Watch/Msg/Settle.cls` -- new `Ens.Request` with `IncidentRef` (`%String(MAXLEN = 22)`); its storage block is committed.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- build:
  - `OnRequest(FailureBatch)`: for each cause in the batch, find or make the incident and group, keep the new keys, update `Count`/`FirstAt`/`LastAt`/`Seen`, and save both rows in one transaction. After the commit, publish `noticed` for each new incident, send one `Settle` per new group (with `%SessionId` cleared for that send and put back afterwards), and publish one `incident` event per noticed incident whose count moved.
  - `OnRequest(Settle)`: the waiter. It records `TraceHeaderId` from its own `%SessionId`, publishes `settling`, then loops `SetTimer(Settle.Wait(...))` → `OnResponse` re-reads → at the end sets `NoticeCount` and completes.
  - Everything else is answered 5003.
  - Warnings follow the Always rules. Update the doc comment.
- `src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls` -- add `TestOnlyIncidentManagerWritesIncidents`, shaped like `TestOnlyTheAuditWriterAudits`: no class outside `OcuTalon.Test` other than `OcuTalon.Watch.IncidentManager` names `%New(`/`%DeleteId(` on `OcuTalon.Data.Incident` or `OcuTalon.Data.FailureGroup`, runs SQL `INSERT`/`UPDATE`/`DELETE` on their tables, or calls `Publish(` with the literal type `"incident"` or `"watch.progress"`. The test first proves the pattern on sample lines, and its doc names what a static scan cannot see (a `%Save` of a row opened elsewhere).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls` -- add helpers:
  - `SendBatch(namespace, production, ownerRef, failures)`, from an adapterless host as in `RoutingProduction.SendTo`, with the scope's `TraceRef` as `SuperSession`. Synthetic header ids come from the run's own range, and item names are `zzIncidents<n>...`, so a group never matches a real Orders failure;
  - `Incidents(ownerRef, production)` and `Group(ref)` as plain objects;
  - `WaitIncident` and `WaitNoticeCount` (poll every 0.5 s; bounds of 20 s, and 45 s for the trickle);
  - `Notice(ref)`, the fixture that sets `NoticedAt` and `NoticeCount` as 5.4's notice will;
  - `Notifications(ref)`;
  - and a cleanup in `OnAfterOneTest` and `OnAfterAllTests` that deletes the `Incident` and `FailureGroup` rows owned by the run's sessions, plus the `instance` incidents with an ID above the test's floor (recorded in `OnBeforeOneTest`), with their groups. With this cleanup, the instance incidents that `Test.Watch.Poller`'s untagged failures now make are removed too.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Settle.cls` -- new, pure (warm): `Pattern`, `Wait` (burst and trickle edges, `max` < `quiet`, a late `FailedAt`), `Hold` (new and held keys, the 1000 trim, order), `Values` (row Settings: the given values are set only in the test process's cache, `^||OcuTalon.Setting(key)`, which is restored after the test, so no setting row is written and no production job can read them), and `Mark.KeyOf`.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Incidents.cls` -- new, over the running production (fresh only, because it tests a production item; it fails with the reason where OCUORDERS or demo mode is missing, as the 5.1 and 5.2 classes do). Tests:
  - `TestBurstThroughThePoller` (Burst and Trace, through `Case.Fail(50, A)`);
  - `TestTrickle`;
  - `TestResent`;
  - `TestPattern`;
  - `TestTwoSessions` (Two sessions, Before the notice);
  - `TestInstanceShared` (Instance shared, After the notice);
  - `TestClosedOpensNew`;
  - `TestWaitersAfterRestart` (`TempStopConfigItem("IncidentManager", 1, 1)` then `(..., 0, 1)`, as 5.2 does for the poller; one kept incident and one deleted);
  - `TestNobodyToTell`.

  Keep the class under about 100 s on the developer machine.

**Acceptance Criteria:**
- Given a throwaway with demo mode on and session A watching Orders, when the real `FailurePoller` sends the batches of 50 failing orders tagged with A, then `IncidentManager` makes exactly the matrix rows Burst and Trace (Integration AC: consumer `IncidentManager` of 5.2's `FailureBatch`, against the real poller).
- Given an incident that `IncidentManager` made, when Story 2.2's ownership API (the read behind `/state`, the guide and Break the feed) reads it before and after the notice, then it is absent for every session before, and afterwards present only for `Recipients`' sessions (Integration AC: consumer `Data.Ownership`).
- Given the product source, when `Test.Bridge.CodeRules` scans it, then no class but `IncidentManager` creates or deletes `Incident` or `FailureGroup` rows or publishes `incident` or `watch.progress`.
- Given `OcuTalon.Production`, when `Test.Install.Production` and Epic 4's `Test.Core.CommandsInProduction` run, then `IncidentManager` still has pool 1 and `STUB`, answers 5003 to an `Ens.StringRequest`, and a `Dismiss` still answers `not_built`; both classes are unchanged.
- Given `ci/iris.sh shard lane-a --part k/n [--reverse]` (DW-227), when it runs, then it runs exactly the k-th contiguous part of the shard's (reversed) name-ordered class list and titles it `part k/n`; bad values exit 2, and without `--part` the behaviour is unchanged. `bash docker/tests/test-ci-config.sh` prints `PASS shard part`, and `ci/units.sh` and `.github/workflows/*` are unchanged.

## Spec Change Log

## Review Triage Log

## Design Notes

**Pending rulings (this plan HALTs on them; the spec assumes the recommended answer to each):**
- **R1. Schema and contended contract.** IncidentManager cannot ignore a failure it already holds (spine row "Watch failures"; epic context "ignores keys it already holds") without storing keys, and neither `Incident` nor `FailureGroup` has a property for them. Recommended (a):
  - `OcuTalon.Data.FailureGroup` gains one stored property, `Seen As %String(MAXLEN = "")`. This is a schema change, a veto item.
  - Epic 16's `Test/Data/Tables.cls` changes one Contracts entry only: in `"OcuTalon.Data.FailureGroup"` → `"props"`, add `"Seen": "%String(MAXLEN=)"`. Nothing else in the file changes, and a conflict at merge-forward is a plain union, as 5.2's was.

  Alternative (b), no schema change: deduplicate against the keys of the previous `FailureBatch` of the same production and scope, read from the message store. That is enough, because the poller's only duplicate path re-sends the immediately previous batch of that scope. It needs an index on `FailureBatch`, though (otherwise every batch scans `Ens.MessageBody`), it depends on message retention, and it reads IncidentManager's own input messages. Not recommended.
- **R2. Who sends the notice.** [RULED 2026-10-26 by the epic lead: (a), veto U-86; epics.md 5.3 and 5.4 blocks amended accordingly] 5.3's criteria say "IncidentManager sets the incident's `NoticedAt` only at the notice", "when the incident is noticed ... one notice per watcher session" and "after the notice". But every notice variant needs 5.4's diagnosis: with-fix and no-fix need a usable diagnosis, and the fallback text names a model fallback reason that only the bridge classifies (AD-8; epic context "Only the bridge classifies fallbacks"). The catalog has no notice that code alone can send honestly, and a new text would be public text not in the UX. Recommended (a):
  - 5.3 ends at the settle rule, with `NoticeCount` fixed. It pins the post-notice rules (`Count` kept apart from `NoticeCount`, the `incident` event on each recipient's stream, no second incident or notice) and per-session visibility on a fixture-noticed incident.
  - "one notice per watcher session" for an `instance` incident moves to Story 5.4. 5.4's block already says "one `Notification` per recipient session"; add for example: "- For an `instance` incident with several watcher sessions, the notice is one `Notification` per session of `Session.Recipients` and the `incident` event on each watcher's stream (moved from 5.3 by ruling)". This is a veto item (an AC moved to a not-yet-planned story of the same release; no release gate depends on 5.3 rather than 5.4).

  Alternative (b): 5.3 also builds the delivery (`NoticedAt`, one `Notification` per recipient, the `incident` event) behind a notice step, tests it by swapping a test subclass behind the item (as `Case.UseDouble` does for `CommandsIn`), and leaves it unreached at run time until 5.4. This adds code and a guessed seam contract for 5.4's variants. Alternative (c), a fallback notice from 5.3, is rejected: it would claim a model fallback that never happened.

**Governing ADs:**
- AD-4: scope by `OwnerRef`; `instance` incidents go to every watcher through `Session.Recipients`.
- AD-5: settle state lives in rows and the persisted BP instance with its `Ens.Alarm`, never in memory; storage is append-only (R1); settle values are product settings, not production-class structure.
- AD-8: only the bridge classifies fallbacks (R2).
- AD-12: publish through `Live.Publish` after commit; the payload is the full view (`FromRow`, as `/state`).
- AD-15: one writer and one publisher; `Ref` at the first failure; one waiter per new group that re-reads rows; `NoticeCount` apart from `Count`; progress events before the notice; the transitions table limits 5.3 to creating `open`.
- AD-19: settle values in `Data.Setting`.
- AD-22: live tests in throwaways only.
- AD-26: the incident's own trace session.
- AD-29 and AD-33: Lane A files; the IncidentManager item and its tables and events.
- AD-32: no notification in 5.3 (R2).

Spine conventions: "Watch failures" (the dedupe key), "Times", "Identifiers", "Live events".

**Integration ACs, Consumes, Consumed-by:**
- New: IncidentManager's grouping and settle rule, `Watch.Settle`, `Watch.Msg.Settle`. In-story consumers: `Data.Ownership` (AC 2) and the session streams that the page polls (matrix rows).
- Consumes: `FailurePoller` and `FailureBatch` (5.2; AC 1 runs against the real poller), `Watch.Mark` key, `Session.Recipients`, `Ownership.Incidents` filter, `Live.Publish` and the two payload classes (Epics 0 and 2), `Data.Setting.Get`, `Bridge.Ids.NewRef`.
- Consumed-by:
  - 5.4: the settle end hands over to the diagnosis; it uses `NoticeCount`, `TraceHeaderId` (the incident's session, in which it diagnoses), the group's item and pattern, and, under R2 (a), the notice delivery to `Recipients` with the multi-watcher case;
  - 5.5: the table moves over these rows; the lookup's "not `closed`" makes "after closing opens a new incident" hold; `closeQuiet` reads `LastAt`;
  - 5.6: `Checks` reads the open incident and `LastAt`;
  - 6.x: incident cards from `incident` events;
  - 7.2: post-notice same-cause failures that no request covers form a later group in the same incident (in 5.3 they join the one group, because an open incident only updates its count, AD-15 P27);
  - 7.3: the group's message list; `Seen` keeps only the newest 1000 keys, so 7.3 reads the full list through the reader or extends the group.

**Extend, don't copy:**
- The key rule extends `Watch.Mark` (`Key` calls the new parts method).
- `Watch.Settle.Hold` is a new rule rather than a copy of `Mark.Fresh`/`Next`: the mark's `Seen` is bounded by a time overlap, the group's by count.
- `Case.SendBatch` copies the three lines of `RoutingProduction.SendTo`, which is private in Epic 2's test class.
- The waiter follows `Ens.BusinessProcess.SetTimer`; no OcuTalon sibling waits on a timer in a BP.

**Decided in-stage:**
- **The error pattern masks digit runs.** Dates, ids and counts that vary per message stay in one group, while names (a missing field, an item) stay apart. Exact text would split one cause across days, and masking quoted values would merge different missing fields.
- **Times are the failures' own `FailedAt`.** So the notice's "since {time}" and `closeQuiet`'s "last failure older than 15 minutes" both read failure times. The pickup delay (3 s or less) does not stretch the rule.
- **One group per incident in 5.3.** So the waiter's settle reads the incident row's `FirstAt`/`LastAt` and `Count` (that group's), and re-reads the group row to confirm it.
- **`settling` is published when the waiter starts.** The waiter starts right after `noticed` (the same job processes it next, so the order is kept).
- **`Seen` is bounded at 1000 keys.** The poller re-sends only the last poll's failures (500 at most per production), always as the group's newest arrivals, and an unbounded list would hit the long-string limit on a production that fails for days. A re-send after the incident has closed (a dismiss within the 3 s window) is theoretical.
- **No setting rows are seeded.** `Get` with the code defaults is the setting until the settings page exists.
- **The lookup** selects candidates by `OwnerRef` (indexed) and compares in ObjectScript, so the comparison is exact.
- **`STUB` stays**: commands come in 5.5.

**(inference), pinned by the tests and recorded by the implement stage:**
- A BP send with `%SessionId` cleared starts a new session, and the BP's own `%SessionId` is put back afterwards.
- `Ens.Alarm` wakes are within about 1 s.
- Pending alarms and waiting BP instances survive a temporary stop of the item (matrix row Restart while settling).

**DW entries:** DW-227 is addressed (Task 0, AC 5). **Declined:** none.

**Footprint extensions** (not contended): `ci/iris.sh` (DW-227), `docker/tests/test-ci-config.sh` (one appended block, by the lead's direction), `Test/Bridge/CodeRules.cls` (one test). Under ruling R1 also Epic 16's `Test/Data/Tables.cls` (one entry).

**Spine candidates for the lead (Rule 20):** the "Watch failures" row could add: same cause = item plus the digit-masked `ErrorText` per production and scope; a group holds the keys of its newest 1000 failures (`Seen`); the settle settings are `watch.settleQuietSeconds` and `watch.settleMaxSeconds`.

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`. Run one command per call, each with `timeout: 600000`, never two IRIS test runs in one message, and nothing chained after a shard.

**Commands:**
- (loop) `bash docker/tests/test-ci-config.sh` -- expected: all rules passed, then `PASS shard part`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s3iw ci/warm.sh up` -- once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s3iw ci/iris.sh class <Class>`, one call per class, for `OcuTalon.Test.Watch.Settle`, `OcuTalon.Test.Watch.Mark`, `OcuTalon.Test.Bridge.CodeRules` and `OcuTalon.Test.Install.Production` -- expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s3i ci/iris.sh class OcuTalon.Test.Watch.Incidents` -- fresh, because a warm stack's running IncidentManager job keeps its old code. Expected: passed.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s3i ci/iris.sh class OcuTalon.Test.Watch.Poller` -- fresh: its untagged failures now make incidents, and the `Case` cleanup changed. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e5s3i ci/iris.sh shard lane-a --part 1/2`, then in its own call `... --part 2/2` -- each alone in its call. Expected: passed. Record each part's time here. If a part takes more than 480 s, use `--part k/3` (three calls) and record those times.
- (once) `<lane> OCUTALON_RUN_TAG=e5s3i ci/iris.sh shard lane-b` -- it holds `Test.Data.Tables` (the R1 entry), `Test.Data.Ownership` and `Test.Core.CommandsInProduction`. Expected: passed.
- (once) `bash ci/checks.sh` -- expected: all pass (storage blocks, class rules).
- (once) `<lane> OCUTALON_RUN_TAG=e5s3iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s3i ci/iris.sh teardown`.

**Shared surfaces:**
- The `Incident` and `FailureGroup` tables: the real IncidentManager now makes rows from every watched failure, `Test.Watch.Poller`'s included, and the `Case` cleanup removes them.
- The `FailureGroup` contract (`Test.Data.Tables`, R1).
- The fixture sessions' live streams: `watch.progress` and `incident` events, which `Fixture.Clean` drops.
- IncidentManager's accepted requests (`Settle`). The stub oracle and `CommandsInProduction`'s `Dismiss` row are unchanged.
- The `lane-a` class list: two new classes, run as parts.
- `CodeRules`' rule list.
- The settings keys (read only; no test writes a setting row).
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19; the implement stage applies each, observes red, reverts byte-identical, and records it here; "fresh" means `Test.Watch.Incidents` on a fresh lane-A stack):

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | a new incident for every batch (no lookup) | TestBurstThroughThePoller ("one incident" when the burst spans batches), TestTrickle |
| AC 1, quiet | the waiter ignores `quiet` | TestBurstThroughThePoller (`NoticeCount` not by `LastAt` + 10 s) |
| AC 1, max | the waiter ignores `max` | TestTrickle |
| AC 1, re-read | the waiter computes its wake once and never re-reads | TestBurstThroughThePoller |
| AC 1, trace | the `Settle` send keeps `%SessionId` | TestBurstThroughThePoller (Trace) |
| AC 2 | `NoticedAt` set when the incident is made | TestTwoSessions and TestBurstThroughThePoller (visible before the notice) |
| AC 3 | a scratch class outside `OcuTalon.Test` publishing `"incident"` | TestOnlyIncidentManagerWritesIncidents |
| AC 4 | `IncidentManager` accepts every request | `Test.Install.Production` TestStubsAnswer |
| AC 5 | the last class of the last part dropped | `test-ci-config.sh` `shard part` |
| Re-sent | `Seen` not checked | TestResent |
| Pattern | the pattern is the unmasked text | TestPattern |
| Two sessions | `OwnerRef` left out of the lookup | TestTwoSessions |
| Instance shared | publish to the first recipient only | TestInstanceShared |
| After the notice | no `incident` event after the notice, and separately `NoticeCount` set to `Count` again | TestInstanceShared |
| Closed | `closed` incidents joined | TestClosedOpensNew |
| Settings | `Values` always gives the defaults | `Test.Watch.Settle` TestValues |

## Auto Run Result

Status: blocked
Blocking condition: intent gap. (R1) Story 5.3 must ignore a failure IncidentManager already holds (spine row "Watch failures"), but neither `OcuTalon.Data.Incident` nor `OcuTalon.Data.FailureGroup` can store failure keys, and Epic 16's contended `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` pins both property sets. Recommended: allow `FailureGroup.Seen As %String(MAXLEN = "")` (schema change, veto) and the one Contracts entry `"OcuTalon.Data.FailureGroup"` → `"props"` + `"Seen": "%String(MAXLEN=)"`, nothing else in the file; the alternative (dedupe against the previous `FailureBatch` of the same scope in the message store, no schema change) is under Design Notes. (R2) 5.3's criteria need a notice ("sets NoticedAt only at the notice", "one notice per watcher session", "after the notice"), but every notice variant needs Story 5.4's diagnosis (the fallback text names a model fallback reason that only the bridge classifies, AD-8), so 5.3 cannot send an honest notice. Recommended: 5.3 ends at the settle rule (`NoticeCount` fixed) and pins the post-notice rules on a fixture-noticed incident; "one notice per watcher session" for an `instance` incident moves to Story 5.4's notice criterion (veto: AC moved within the release; the proposed 5.4 line is under Design Notes). Alternative: 5.3 builds the delivery behind a test-only seam. The spec is complete under both recommended answers; on the rulings, set `status: ready-for-dev`.
