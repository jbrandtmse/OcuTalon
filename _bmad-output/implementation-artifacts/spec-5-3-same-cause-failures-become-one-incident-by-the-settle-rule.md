---
title: 'Same-cause failures become one incident by the settle rule'
type: 'feature'
created: '2026-10-25'
status: 'done'
baseline_revision: '361f6010213caef0f2d0a42a310a50ce587a474a'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      The error branches of IncidentManager.Tell (a failed Session.Recipients read; a failed publish while other recipients still get the event) have no test.
    evidence: |-
      Tests assert only that no warning is logged on the success and nobody-watches paths. Forcing Recipients or Publish to return an error needs a seam (a double or a refused stream) that the story does not add; the code logs one Type 3 warning per event and leaves the rows standing, as the intent says.
    location: >-
      src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls Tell
    severity: low

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

- 2026-10-26, spec gate (Epic 5 runner): R1 ruled by the orchestrator (option (a), decide; standing ruling for Lane A tables' Contracts entries) with the schema change as veto U-87; R2 ruled by the runner (option (a), veto U-86; epics.md 5.3 and 5.4 blocks amended); the spine candidates written into the "Watch failures" row; status set to `ready-for-dev`.

## Review Triage Log

### 2026-10-26 — Review pass
- verdicts: 32 findings — high 0, medium 4, low 26, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind 1: the waiter is lost if `Start` fails or the job dies between the commit and the send — the window is one send to the item's own queue; a recovery sweep is new behaviour beyond a direct correction (reopen_if: a waiter-less incident is seen in a run).
  - `[low]` `[patch]` Blind 2: `Find` scans every incident of the owner — the SQL now also filters Namespace, Production and `State <> 'closed'` (the ObjectScript check stays exact).
  - `[low]` `[patch]` Blind 3: bare `TROLLBACK` undoes outer transactions — `Record` keeps `$TLevel` before `TSTART` and rolls back one level only.
  - `[low]` `[patch]` Blind 4: `Settle.Seconds` throws on a well-formed impossible stamp — Try/Catch gives "" (rule ended); `TestWait` pins it.
  - `[low]` `[patch]` Blind 5: the code rule misses `DELETE` without `FROM`, `INSERT OR UPDATE`, `%DeleteExtent`/`%KillExtent` — the pattern and its sample lines now cover them; the header names the remaining blind spots.
  - `[low]` `[reject]` Blind 6: `PASS shard part` prints after the "all rules passed" line — the block is appended after the file's last line by the lead's ruling, and the intent says it runs only after that summary.
  - `[low]` `[reject]` Blind 7: short fixed `Hang` before an absence assertion — each follows a wait for the positive marker (`WaitCount`, `Events` with a count) in the same job that publishes, so a second event cannot be pending; the trickle has 6 s of slack and ran green five times.
  - `[low]` `[defer]` Blind 8: no test of the failed `Recipients` read, the failed publish, a failed `Start` or a rolled-back `Record` — needs a seam the story does not add; deferred (frontmatter).
  - `[false]` `[reject]` Blind 9: the `Seen` cap re-counts a cut key — that is ruling R1 (newest 1000, a re-send of a cut key is theoretical) and `TestHold` pins it.
  - `[low]` `[patch]` Blind 10: truncated `WaitNoticeCount` comment fixed; the other helper remarks (an unchecked session in `SendBatch`, the cache node layout the spec names) stay.
  - `[medium]` `[patch]` Edge 1: `--part=` or `--part ""` skipped validation and ran the whole shard — `part_given` is tracked, an empty value exits 2; the block checks both forms.
  - `[low]` `[reject]` Edge 2: a held failure re-sent after its incident closed makes a ghost incident — the spec's in-stage decision names it theoretical (a dismiss inside the 3 s window).
  - `[low]` `[reject]` Edge 3: duplicate of Blind 1.
  - `[false]` `[reject]` Edge 4: pattern over 1000 or item over 128 characters — `Failure.ErrorText` is MAXLEN 1000 and `ItemName` 128, and the pattern is never longer than the text.
  - `[low]` `[patch]` Edge 5: duplicate of Blind 3.
  - `[low]` `[patch]` Edge 6: duplicate of Blind 2.
  - `[low]` `[reject]` Edge 7: a `FirstAt` in the future stretches the wait — `FailedAt` is IRIS's own clock on one instance; theoretical.
  - `[low]` `[patch]` Edge 8: duplicate of Blind 4.
  - `[low]` `[reject]` Edge 9: an absurd setting value — a positive whole number is what the spec accepts.
  - `[low]` `[reject]` Edge 10: `KeyOf` with an empty id — the reader always supplies the id of its kind.
  - `[low]` `[patch]` Edge 11: duplicate of Blind 5.
  - `[low]` `[reject]` Edge 12: an event type held in a variable or a call over lines is invisible to the scan — a documented limit of a static scan.
  - `[low]` `[reject]` Edge 13: a literal `#` in an error text collides with a masked digit — the masking is the spec's contract.
  - `[medium]` `[patch]` VGap 1: a batch joining an unnoticed incident publishing an `incident` event was not pinned — `TestResent` asserts no event; mutation demonstrated.
  - `[medium]` `[patch]` VGap 2: Namespace, Production and case in the cause key were not pinned — `TestPattern` sends the same item and text for another production, another namespace and an upper-cased item; mutation demonstrated.
  - `[medium]` `[patch]` VGap 3: `TestWaitersAfterRestart` stopped the item before the waiters had started — it waits for both `TraceHeaderId`s first, and also checks the waiters' sessions and the event log for errors; mutation demonstrated.
  - `[low]` `[defer]` VGap 4: duplicate of Blind 8.
  - `[low]` `[patch]` VGap 5: the `--part` block did not check `--part=k/n`, the position before the name, the label, the no-part title, a seven-digit value or the refusal message — all added; two mutations demonstrated.
  - `[low]` `[patch]` VGap 6a: the "nor on a session's stream" assertion of `TestNobodyToTell` could not fail — removed.
  - `[low]` `[reject]` VGap 6b: matrix rows without a mutation line — Rule 19 scopes one line per AC, which all have; the Restart row, which the finding names, now has one.
  - `[low]` `[reject]` VGap 6c: `TestTrickle`'s quiet-window assertion has about 4 s of slack — ran green five times; not worth a guard.
  - `[low]` `[reject]` VGap 6d: `TestInstanceShared` and `TestValues` assume no foreign instance incident or `watch.settle*` setting row — the cleanup floors and the no-seeding rule hold that.
- intent-alignment: no finding; its readings (runtime behaviour in a running production, with Task 0 at the command line) match the implemented one.

## Design Notes

**Rulings (the plan halted on them; both are now ruled as recommended, so the spec stands as written):**
- **R1. Schema and contended contract.** [RULED 2026-10-26: (a), orchestrator decide for the `Test/Data/Tables.cls` entry (and a standing ruling for the rest of Epic 5: only the Contracts entries of Lane A's own tables `BackgroundCheck`, `WatchMark`, `Incident`, `FailureGroup`, `FixRun`); the schema change is the runner's veto U-87] IncidentManager cannot ignore a failure it already holds (spine row "Watch failures"; epic context "ignores keys it already holds") without storing keys, and neither `Incident` nor `FailureGroup` has a property for them. Recommended (a):
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
- **Implement stage, `--part`:** `ci/iris.sh shard` also takes `--part=k/n`; k and n are at most six digits (a longer number is refused with exit 2); the check that n does not exceed the class count runs after the shard's classes are known.
- **Implement stage, failure times:** a failure with an empty `FailedAt` is held with the batch's `PolledAt` (the rule never reads an empty time).
- **Implement stage, errors:** a batch whose rows fail to save rolls back, publishes nothing and answers the error status (the message shows in error); a failed `Settle` send is answered as an error after the events went out, and the rows stand.
- **Implement stage, warnings:** `Tell` logs at most one Type 3 warning per event (the failed `Recipients` read, or the first failed publish when other recipients got the event).
- **Implement stage, tests:** a persistent object that a test still holds shows the values it was opened with (an `%OpenId` of the same row returns the held object), so `Case.WaitCount` and `Case.WaitNoticeCount` reopen the row afresh on each poll. `Case.SendBatch` records the `HomeFloor` itself, so the batches of a test are removed. `TestTrickle` sends seven failures 4 s apart (the last at 24 s), so the maximum (30 s) ends the rule before the quiet time after the last failure (34 s), then one more after the notice.

**(inference), pinned by the tests and recorded by the implement stage:**
- A BP send with `%SessionId` cleared starts a new session, and the BP's own `%SessionId` is put back afterwards.
- `Ens.Alarm` wakes are within about 1 s.
- Pending alarms and waiting BP instances survive a temporary stop of the item (matrix row Restart while settling).

Results (implement stage, fresh lane-A stack): all three hold. A `Settle` sent with `%SessionId` cleared starts a session of its own: the incident's `TraceHeaderId` is that session, none of the batches' sessions, and its first header is the `Settle` request with the scope's `TraceRef` as `SuperSession` (`TestBurstThroughThePoller`; with `%SessionId` kept it is red). The alarm wakes were within the tests' bounds (burst: `NoticeCount` set within 20 s of the failures; trickle: set at the 30 s maximum within the 45 s bound); the wake delay was not measured more finely. With the item stopped 2 s during the wait and started again, the kept incident still settled with `NoticeCount` 1, and the deleted incident's waiter completed with no error and wrote nothing (`TestWaitersAfterRestart`).

**DW entries:** DW-227 is addressed (Task 0, AC 5). **Declined:** none.

**Footprint extensions** (not contended): `ci/iris.sh` (DW-227), `docker/tests/test-ci-config.sh` (one appended block, by the lead's direction), `Test/Bridge/CodeRules.cls` (one test). By the orchestrator's R1 ruling also Epic 16's `Test/Data/Tables.cls` (the `FailureGroup` Contracts entry only). `docker/tests/test-ci-config.sh` is also changed on Epic 10's unmerged branch: keep this story's edit to the one self-contained block appended at its end.

**Spine (Rule 20), written by the lead at the spec gate into the "Watch failures" row:** the "Watch failures" row could add: same cause = item plus the digit-masked `ErrorText` per production and scope; a group holds the keys of its newest 1000 failures (`Seen`); the settle settings are `watch.settleQuietSeconds` and `watch.settleMaxSeconds`.

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

**Implement-stage results (lane-A throwaways, tags e5s3ih / e5s3ihw):**
- `bash docker/tests/test-ci-config.sh` -- all rules passed, then `PASS shard part`; `bash ci/checks.sh` -- all scripts passed.
- Warm (`e5s3ihw`): `Test.Watch.Settle`, `Test.Watch.Mark`, `Test.Bridge.CodeRules` and `Test.Install.Production` passed. Fresh: `Test.Watch.Incidents` passed in 59.8 s (class time; a first run before the stale-object fix of `Case.WaitCount`/`WaitNoticeCount` failed), `Test.Watch.Poller` passed in 63 s.
- `shard lane-b` passed (42 classes, 133 s).
- `shard lane-a --part 1/2` passed: 28 classes, 374 s (including the 72 s start). `shard lane-a --part 2/2` passed: 28 classes, 280 s (including the 73 s start). Each part is well under the 480 s limit, so no `--part k/3` run was needed.
- Teardown: `ci/warm.sh down` (tag e5s3ihw) and `ci/iris.sh teardown` (tag e5s3ih) left nothing behind.

**Mutation results** (each applied, observed red, and reverted byte-identically, checked by `shasum` against the backup; "fresh" is `Test.Watch.Incidents` on a fresh lane-A stack):
- mutation: AC 1, a new incident for every batch (no lookup) -> red: `TestTrickle`, `TestResent`, `TestPattern`, `TestInstanceShared` (`TestBurstThroughThePoller` stayed green: the burst reached `IncidentManager` as batches that the test did not split; the trickle and the re-sent rows pin the lookup).
- mutation: AC 1 quiet, the waiter ignores `quiet` -> red: `TestBurstThroughThePoller` (`NoticeCount` not set within the bound), `TestWaitersAfterRestart`.
- mutation: AC 1 max, the waiter ignores `max` -> red: `TestTrickle` (the rule did not end by the maximum).
- mutation: AC 1 re-read, the alarm ends the settle without re-reading the rows -> red: `TestTrickle` (`NoticeCount` is the count of the first wake, and the rule had not ended by the maximum); `TestBurstThroughThePoller` stayed green because its 50 failures arrive within the quiet time of one another, so the first wake is already the right end.
- mutation: AC 1 trace, the `Settle` send keeps `%SessionId` -> red: `TestBurstThroughThePoller` (Trace: the trace session is the batch's, and its first header is not the waiter's).
- mutation: AC 2, `NoticedAt` set when the incident is made -> red: `TestBurstThroughThePoller` and `TestTwoSessions` (visible before the notice).
- mutation: AC 3, a scratch class outside `OcuTalon.Test` publishing "incident" -> red: `Test.Bridge.CodeRules` `TestOnlyIncidentManagerWritesIncidents` (warm; green again on the same stack after the scratch class was deleted).
- mutation: AC 4, `IncidentManager` accepts every request -> red: `Test.Install.Production` `TestStubsAnswer` (fresh stack).
- mutation: AC 5, the last class of the last part dropped -> red: `test-ci-config.sh` prints `FAIL shard part`.
- mutation: Re-sent, `Seen` not checked -> red: `TestResent`.
- mutation: Pattern, the pattern is the unmasked text -> red: `TestPattern` (also `TestResent`, `TestTrickle`, `TestInstanceShared`, `TestTwoSessions` and the group assertion of `TestBurstThroughThePoller`).
- mutation: Two sessions, `OwnerRef` left out of the lookup -> red: `TestTwoSessions`.
- mutation: Instance shared, publish to the first recipient only -> red: `TestInstanceShared`.
- mutation: After the notice, no `incident` event after the notice -> red: `TestInstanceShared`.
- mutation: After the notice, `NoticeCount` set to `Count` again when the count moves -> red: `TestInstanceShared` (and `TestTrickle`).
- mutation: Closed, `closed` incidents joined -> red: `TestClosedOpensNew`.
- mutation: Settings, `Values` always gives the default for `quiet` -> red: `Test.Watch.Settle` `TestValues` (warm; green again on the same stack after the revert).

**Review-pass results (lead, lane-A throwaways, tags e5s3i / e5s3iw, after the review patches):**
- `bash docker/tests/test-ci-config.sh`: all rules passed, then `PASS shard part`; `bash ci/checks.sh`: all scripts passed.
- Warm: `Test.Watch.Settle`, `Test.Watch.Mark`, `Test.Bridge.CodeRules`, `Test.Install.Production` passed. Fresh: `Test.Watch.Incidents` passed (60.5 s class time), `Test.Watch.Poller` passed (63 s).
- `shard lane-a --part 1/2` passed (28 classes, 370 s including the 69 s start); `--part 2/2` passed (28 classes, 281 s). `shard lane-b` passed (42 classes, 115 s). Teardown of both tags left nothing behind.
- mutation: Before the notice, the `NoticedAt` guard dropped, so a batch that joins an unnoticed incident publishes an `incident` event -> red: `TestResent` (green again after the revert).
- mutation: Cause scope, Namespace and Production left out of the lookup (the SQL and the exact check) -> red: `TestPattern` (another production and another namespace); green again after the revert.
- mutation: Restart row, the waiter's wake answers an error status when its incident is gone -> red: `TestWaitersAfterRestart` ("the event log holds no error of the item"; the same mutation was green before the test read the event log); green again after the revert.
- mutation: AC 5, the `--part=*` branch removed -> `FAIL shard part`; an empty `--part` skipping validation -> `FAIL shard part`; both reverted byte-identically (`shasum`).

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

Status: done
Blocking condition: none

**Summary.** `IncidentManager` now groups each `FailureBatch`'s new failures into one open incident per cause (production item and digit-masked error pattern, per namespace, production and scope), gives each new incident its `Ref`, publishes `watch.progress` `noticed` and `settling` to `Session.Recipients`, and runs one persisted waiter per new group that ends the settle rule (10 s quiet or 30 s after the first failure, from settings) by fixing `NoticeCount`. After a notice (fixture-set in 5.3; sent in 5.4) a batch that adds failures publishes one `incident` event. Task 0 (DW-227): `ci/iris.sh shard <name> --part k/n`, with the lane-a shard measured at 370 s and 281 s as two parts.

**Files changed.**
- `ci/iris.sh`: `--part k/n` (also `--part=k/n`), validation, title `part k/n`, usage header.
- `docker/tests/test-ci-config.sh`: one appended `shard part` block (and the `PASS shard part` line).
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`: grouping, settle waiter, events.
- `src/ocutalon/cls/OcuTalon/Watch/Settle.cls`, `Watch/Msg/Settle.cls`: pure rules and the waiter's request (new).
- `src/ocutalon/cls/OcuTalon/Watch/Mark.cls`: `KeyOf`. `Data/FailureGroup.cls`: `Seen`. `Test/Data/Tables.cls`: the one `FailureGroup` Contracts entry (ruling R1).
- `src/ocutalon/cls/OcuTalon/Test/Watch/Settle.cls`, `Test/Watch/Incidents.cls` (new); `Test/Watch/Case.cls` (helpers and cleanup); `Test/Bridge/CodeRules.cls` (`TestOnlyIncidentManagerWritesIncidents`).

**Review.** 32 findings (high 0, medium 4, low 26, false 2). Patches applied: 4 medium (empty `--part` skipped validation; three tests that did not pin the pre-notice event, the cause scope, and the started-waiter restart) and 8 low rows over 6 root causes (`Find` SQL narrowing, `TROLLBACK` level, impossible stamp, code-rule coverage, comment, vacuous assertion, `--part` block checks). Deferred: 1 (the untested error branches of `Tell`, frontmatter). Rejected with reasons: see the Review Triage Log (a waiter lost between commit and send, a ghost incident after a close, the summary order of the appended block, short absence waits, a future `FirstAt`, a huge setting, an empty id, a variable event type, a literal `#`, the `Seen` cap (R1), and `MAXLEN` overflow, which cannot happen).

**Follow-up review recommended: true.** Four medium findings were patched in this pass (threshold two). The unverified risk: `Find` now narrows by Namespace, Production and `State` in SQL, which relies on SQL equality under the property collation being a superset of the exact comparison that follows (it holds for the values the product writes; `TestPattern` and the lane-a runs are green).

**Verification.** Every `## Verification` command ran green after the last patch (see "Review-pass results"); the matrix audit holds for each row (`TestBurstThroughThePoller`, `TestTrickle`, `TestResent`, `TestPattern`, `TestTwoSessions`, `TestInstanceShared`, `TestClosedOpensNew`, `TestWaitersAfterRestart`, `TestNobodyToTell`, and `Test.Watch.Settle`).

**Residual risks.** The `Ens.Alarm` wake delay was shown to be inside the test bounds, not measured finely. The `Tell` error branches are untested (deferred). A job death between the commit and the `Settle` send would leave an incident without a waiter (rejected as a rare window; reopen if seen).
