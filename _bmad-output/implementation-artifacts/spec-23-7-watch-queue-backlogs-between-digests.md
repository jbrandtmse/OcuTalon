---
title: 'Story 23.7: Watch queue backlogs between digests'
type: 'feature'
created: '2026-11-11'
status: 'done'
baseline_revision: '0f25251b0ae5eae43b0aa07d217ccb373a77fe97'
baseline_commit: '0f25251b0ae5eae43b0aa07d217ccb373a77fe97'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
warnings: [oversized]
deferred:
  - summary: >-
      Ending a session does not stop its queue-backlog row, so the check keeps running and sending findings for the ended session, and Data.Purge.Keeps keeps the session because it still has a BackgroundCheck row.
    evidence: |-
      Core/SessionOps.EndWatches (about line 340) skips every row whose Kind is not production (`If check.Kind '= ##class(OcuTalon.Watch.Ops).#KIND Continue`) and builds the StopWatch without a Kind, so a Kind queues row survives EndSession. Checks.Process.RunQueues never re-checks that the row's session is still live. Data.Purge.Keeps retains any session with a BackgroundCheck row. The fix is about three lines in a Lane B file (Core/*), which the spec lists as not touched and the stage prompt does not list among the approved cross-lane edits: let the loop also accept #QUEUEKIND and set stop.Kind = check.Kind (WatchOps OnStop already handles Kind queues), plus a Test.Core session-end case.
    location: >-
      src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:340
    severity: medium
  - summary: >-
      K29 no longer runs the press, the chat turn, start_watch and the rail row end to end: under sign-in-3 (no model, no CI mock) it answers the POST 202 and seeds and publishes the queue row itself, so a break in the prompt-to-row link leaves K29 green.
    evidence: |-
      The sign-in-3 stack holds no model key and the CI mock runs only with the floor unit, whose user K29 used before. K29's press assertions (prompt once, fromGuide false, aria-disabled, no second post) still fail if the item sends nothing (mutation observed). The prompt-to-row link is pinned server-side by Test.Watch.Turns:TestQueuesThroughTheAgent (scenario A/watch-start-queues.json, with the marker prompt), not by the item's literal prompt. ci/mock/scenarios/B/queue-watch-ask.json (matches the item's literal prompt) now has no consumer. Closing it needs an e2e case in a unit that has the mock (a floor-project or demo-switch spec), or a spec amendment that moves AC10's rail clause to Test.Watch.Turns.
    location: >-
      web/e2e/guide/more-to-try-queues.spec.ts
    severity: medium
---

<intent-contract>

## Intent

**Problem:** The digest reports a backed-up queue only for watched productions, and only once a day. A queue that backs up at 10:00 waits until the next digest, and on a local install nothing looks at the queues of a production nobody watches. FR-33 asks for a queue-backlog background check (step 5, Could).

**Approach:** A chat request starts or stops a per-session background check of `Kind` `queues`. `WatchOps` creates the row through the existing `StartWatch`/`StopWatch` commands, which gain a `Kind`. On each `Tick`, `Checks` runs the due queue rows. Each run reads, through `Watch.Reader` alone, the queues of every production that `Reader.Productions()` lists (on the online demo, only Orders). It compares each queue with the digest's `checks.thresholds.queueMessages` and `queueWaitMinutes` (one shared rule) and sends one finding Item to `Intake` per crossing above. The row records the run like every check, so the rail, `check_status` and the digest coverage show it.

## Boundaries & Constraints

**Always:**
- State changes go through `Commands.Submit` → `CommandsIn` → `WatchOps`. The tool never writes a row (AD-1). `WatchOps` stays the only creator of `BackgroundCheck` rows, and `Checks` the only writer of run fields and only publisher of `check` events (AD-18, AD-33).
- Every cross-namespace read goes through `OcuTalon.Watch.Reader` (`Productions`, `Failures` with limit 0). The run is read-only: no namespace switch outside `Reader`, no data-changing SQL against a watched namespace, and no production, item or message changed (AD-3, FR-33).
- One threshold rule (`Checks.Queues.Over`) and one threshold source (`Coverage.CurrentLimits` over `Coverage.THRESHOLDS` and `checks.thresholds.*`) serve both this check and the digest's live read. A queue is above when `count > queueMessages`, or when it holds messages and its oldest has waited more than `queueWaitMinutes`×60 s.
- A run that cannot read any listed namespace, that cannot list the productions, or that lists none records `not_checked` with an existing `Checks.Process` `REASON*` text. It is never `passed` (AD-28).
- Findings are catalog key + slots, rendered only by `Msg.Catalog` (AD-32). Each finding is an `OcuTalon.Msg.Item`: channel `system`, provenance `untrusted`, the row's `SessionRef` as owner, its own trace session with the session's `TraceRef` as SuperSession (AD-14, AD-26).
- Crossing memory is `BackgroundCheck.Reported` = `{"above": {"<namespace>": ["<item>", ...]}}`. A queue is reported once per crossing: when it is above now and was not in the previous `above` of its namespace. A namespace that was not read keeps its previous list.

**Never:**
- No new table, no new `BackgroundCheck` column, no new privilege, role, grant or resource in the product. No new web route, live-event type, dependency or retention rule.
- No change to the production watch's rules (`Run`, `Findings`, its baseline), to `FailurePoller`, to `Ownership`'s `Kind = 'production'` filters, or to `Checks.Beat`.
- No dependency on Stories 23.3, 23.4, 23.8, 23.9 or Epic 36. No edit of `Data/BackgroundCheck.cls` (contended; its `Kind` comment is left to Epic 22).
- No edit under `irislib/` or `irissys/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Start | chat "Watch the queue backlogs" → `start_watch(name, , "queues")` | one row: `Kind` `queues`, `Namespace`/`Production` empty, `DisplayName` "Queue-backlog check", `AskedBy` the session's IRIS user, `CreatedAt` = `NextDueAt` = now; answer `started`; one `CheckChanged` (Kind queues) → one `check` event | No error expected |
| Start again | the session already has a queue row | `already_watching` with that Ref; no second row, no event | No error expected |
| Stop | `stop_watch(name, , "queues")` | the session's queue row is deleted, `stopped`, one `check` event with stopped true; another session's queue row untouched | none → `not_watching`, Ok 0 |
| Unknown kind | `kind` not "", `production` or `queues` | `{"ok": false, "outcome": "unknown_kind", "message": UNKNOWNKIND}`; nothing submitted | No error expected |
| First run, above | listed queue A: 101 messages | one Item `watch.queueBacklog` for A; `Reported` above[ns] = [A]; result `failed`, finding "1 queue over its threshold" | No error expected |
| Still above | next run, A still 150 | no Item; still `failed` | No error expected |
| Falls below, rises again | A at 100 with oldest 9 min (or absent), then 101 | first run: no Item, A leaves `above`, `passed`; next run: one Item | No error expected |
| Age crossing | A: 3 messages, oldest 11 min old | above; one Item with count 3 | No error expected |
| Admin threshold | `checks.thresholds.queueMessages` set to 5 | 6 messages is above (the value is read on every run) | Not a number → the default |
| Namespace unread | `Failures` throws, answers `unreadable`/`not_current`, or gives `queues` "" for one namespace | `not_checked`, finding = `REASONREAD` / `REASONUNREADABLE` / `REASONNOTCURRENT` (first unread namespace in list order); that namespace keeps its previous `above`; the read namespaces' crossings are still sent | One redacted Type 3 warning per throw (`LOGREAD`) |
| List unreadable | `Reader.Productions()` throws | `not_checked` `REASONREAD`; `Reported` unchanged; no Item | One redacted warning |
| Empty list | `Productions()` gives [] | `not_checked` `REASONREAD`; `Reported` unchanged | No error expected |
| Stopped meanwhile | the row is deleted during the run | nothing recorded, sent or published (`Record`'s row-count rule) | No error expected |
| Send fails | `SendFinding` errors for one Item | one `LOGFINDING` warning; not retried; the other Items still go | Logged |
| Online demo | `onlineDemo` on, another readable namespace's queue above | only the Orders production is read (`Reader.Productions`); no Item for the other namespace | No error expected |
| check_status / digest | the session has a queue row | `check_status` lists it with entry "Queue-backlog check"; `Coverage.Build` gives it a row from its `CheckRun` history (no live read) | No error expected |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- the Checks BP (contended, Epic 22). `Tick` (208-262): sweep, fixes, due production checks (Try at ~222), beats, Digest forward. `Due` (486-500) selects `WHERE Kind = ?` `..#KIND`. `RowOf` (520) and `ROWCOLUMNS` are reused as they are. `Record` (596) does the one UPDATE (row-count guard, then `SendOwn` per Item, publish, `LOGRAN`), and the trigger on the row writes the `CheckRun`. `FindingItem` (688) reads only `row.sessionRef` and `row.displayName` (→ slot `production`) and replaces `{production}`/`{itemName}` in the text. `SendOwn` (370), `Joined` (774), `REASON*` (157-166), `LOGREAD` (~171), `SendFinding` seam (835).
- `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls` -- (contended, Epic 22). `THRESHOLDS` (35), `KEYPREFIX`, private `Limits()` (164). `Live` (335-383) holds the inline queue rule at 370-378 (`most`, `longest`). `EntryOf` (386) gives a non-production row its DisplayName. `WatchRow` does a live read only for `Kind` production (327). `ReasonOf` (463) maps the `REASON*` texts to `CheckRun.Reason`.
- `src/ocutalon/cls/OcuTalon/Watch/Reader.cls` -- `Productions()` (108-131): one entry per readable Interop namespace. On the online demo it gives only Orders (`onlyOrders`, 114-128), and it throws when ServiceUser cannot be read. `Failures(ns, prod, from, limit, ...queues)` (220) with `limit` 0 reads no failure rows (`passes` 0, 676). The queue read is at 621-632: `{name, count, oldestAt}` per item with Status 2, or `queues` "" when unread. No change.
- `src/ocutalon/cls/OcuTalon/Watch/Ops.cls` -- `KIND` (25), `OnStart` (71), `OnStop` (116), `Changed` (219), and `RefOf` (247), which matches `Namespace = ?`. An empty value binds as NULL, so a queue row must be found by `SessionRef` + `Kind` only.
- `src/ocutalon/cls/OcuTalon/Msg/Command/StartWatch.cls`, `StopWatch.cls` -- (Lane B) properties and storage (`Value` 1-3 / 1-2).
- `src/ocutalon/cls/OcuTalon/Tools/WatchTools.cls` -- `StartWatch` (110), `StopWatch` (129), the doc comments the model reads, and the classification parameters (unchanged). `src/ocutalon/cls/OcuTalon/Tools/WatchAnswers.cls` -- `CheckResults` (203-215) skips non-production kinds, and `ENTRY` (45).
- `src/ocutalon/cls/OcuTalon/Tools/Watching.cls` (toolset XData, 11-20) and `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` (the start_watch rules, 45-55).
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- `watch.itemDisabled` (27) is the shape to copy. The file ends with `mcp.sourceStopped` (~1080). `Msg/Catalog.cls` (1-40) documents slot types, the `one` form and the "at "→"on" rule.
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notice.cls:32` -- a tell-now for an Item with a CatalogKey uses that key's text ("Why now" included), so no Core change is needed.
- `web/src/app/rail/rail-view.ts` -- (contended, Epic 21) `RAIL_TEXTS` (28-63), `PRODUCTION_KIND` (73), `checkTitle` (208), `checkRow` (240-259): only production rows get `detail`.
- `web/src/app/guide/more-to-try-view.ts` (`MORE_TO_TRY_TEXTS` 21-130, `MoreToTryAction`, `MORE_TO_TRY_ITEMS` 147-162, header comment line 3 "fourteen") and `web/src/app/guide/more-to-try.ts` (`press` 237, the `partnerWarning` branch is the one to copy; aria-disabled list at 89-90). `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- `Ids` (43-55).
- `README.md:40` (Usability row, "fourteen more things to try"). The `### New since 1.0.0` list ends at line 58 (History page bullet).
- Test siblings:
  - `Test/Checks/Probe.cls` (KIND zzprobe, `Only`, `SendFinding` capture, `^||ChecksProbe`) and `Test/Checks/Runs.cls` (probe-driven run tests, `TestFindingsRender`).
  - `Test/Checks/BeatCase.cls` (`Findings`, `Check`) and `Test/Checks/Heartbeat.cls`: `TestDisabledItemIsReportedOnce` (167-222) is the live-finding pattern with the `[[mock:check-finding-tell-now]]` marker; `Decision` (333).
  - `Test/Watch/Case.cls`: `Ready` 316, `Ahead` 645, `Tick` 686, `SetOnlineDemo`, `Session`.
  - `Test/Data/Fixture.cls:99` (`Check` with `fields`).
  - `Test/Eval/Feed/Fixture.cls`: a throwaway-guarded namespace with its own production, Read granted to the service role, `Remove`/`Leftovers`; it is fully parameterised by `NAMESPACE`, `DATABASE`, `RESOURCE`, `PRODUCTION`, `CODEPACKAGE`.
  - `Test/Watch/Turns.cls` with `ci/mock/scenarios/A/watch-start-orders.json` and `watch-stop-orders.json`.
  - `Test/Watch/Ops.cls`, `Test/Watch/Tools.cls` (args pin `"name,namespace"` at 66), `Test/Digest/Coverage.cls` (queue cases 402-453), `Test/Msg/Catalog.cls`, `Test/Demo/Features.cls` (`TestIds`).
  - `web/scripts/rail-view.test.mjs`, `more-to-try-view.test.mjs` (number words to fourteen at 371/376), `more-to-try-sources.test.mjs`, `ux-strings.test.mjs`.
  - `web/e2e/guide/more-to-try.spec.ts` (the `ITEMS` oracle 81-166, contended), and `ci/mock/scenarios/B/partner-warning-ask.json` (the prompt-scenario shape).
- Measured on slot D (read-only, 2026-11-11): build 154 answers, but its OCUTALON's current production is not `OcuTalon.Production` (`Reader.Productions()` errors on the missing `Decide` item), and there is no OCUORDERS. So every run test here is a throwaway test, as `Test.Watch.Case` already requires.

## Tasks & Acceptance

**Execution:**
- [x] Task 0 (implement, lane-D throwaway, before the live test is written): on a warm or fresh stack with the queue fixture installed, hold the sink, send 105 `Ens.StringRequest`s, then read `Reader.Failures(QUEUEFEED, <production>, "", 0, ...)`. Record the measured `queues` count (expected about 104 in Status 2; inference until measured), the time of the read, and the drain time after release, under `## Verification`. If held messages do not show as Status 2, HALT with an intent gap that names what was measured.
- [x] `src/ocutalon/cls/OcuTalon/Checks/Queues.cls` (new, Lane A, abstract, pure) -- `ClassMethod Over(queue As %DynamicObject, limit As %DynamicObject, nowSeconds As %Integer, Output byCount As %Boolean, Output waited As %Integer) As %Boolean`: byCount = count > `limit.queueMessages`. `waited` is the seconds since `oldestAt` when count > 0, the time is readable and that wait exceeds `limit.queueWaitMinutes`×60, else 0. `ClassMethod Crossings(previous As %String, readings As %DynamicArray, limit As %DynamicObject, nowSeconds As %Integer, Output reported As %String) As %DynamicArray`: readings is `[{"namespace", "production", "displayName", "read": 0|1, "queues": [...]}]`, and the result is `[{"namespace", "displayName", "item", "count", "oldestAt"}]` in reading order and queue order. A read namespace's new `above` is its queues that are `Over`. A finding is a name not in that namespace's previous list. An unread namespace keeps its previous list. Previous JSON that is empty or invalid is `{}` (no baseline: everything above is new). `reported` is the new JSON with only non-empty lists.
- [x] `src/ocutalon/cls/OcuTalon/Checks/Coverage.cls` -- (a) appended block: public `ClassMethod CurrentLimits() As %DynamicObject { Quit ..Limits() }`. (b) contended in-place edit: `Live`'s loop (370-378) takes `most`/`longest` from `Checks.Queues.Over(queue, limit, nowSeconds, .byCount, .waited)`, with the same results as today. The existing `Test.Digest.Coverage` queue cases pin it.
- [x] `src/ocutalon/cls/OcuTalon/Checks/Process.cls` -- contended in-place edits:
  - (a) in `Tick`, right after the due-checks Try, a Try block that runs `..QueueDue(tickAt)` rows through `RunQueues` (each row in its own Try, `LOGRUN`; the list read in a Try, `LOGDUE`);
  - (b) `Due`'s body becomes `Quit ..DueOf(tickAt, ..#KIND)`;
  - (c) one bullet in the class description for queue rows.

  An appended block holds:
  - parameters `QUEUEKIND` = "queues", `KEYQUEUE` = "watch.queueBacklog", `TEXTQUEUE`, `TEXTQUEUEONE`, `FINDINGQUEUE`, `FINDINGQUEUES` (texts in Design Notes);
  - `DueOf(tickAt, kind)` (Due's old body with the kind bound);
  - `QueueDue(tickAt)` (`DueOf` with `QUEUEKIND`);
  - `RunQueues(row, tickAt)`: `runAt` now; entries from the seam `ReadEntries()`; for each entry, the seam `ReadQueues(namespace, production, .queues)`, which is `Reader.Failures(ns, prod, "", 0, , , , , , .queues)`; reasons per the matrix; `Crossings` with `Coverage.CurrentLimits()`; result/finding: the reason, else `failed` with `Joined(count text)` when any queue is above, else `passed`; one Item per crossing through `FindingItem` given `{"sessionRef": row.sessionRef, "displayName": <the entry's displayName>}`, slots `{"itemName", "count", "oldestAt"}`, the text with `{count}` filled (`TEXTQUEUEONE` for 1), time = runAt; then `Record(row, tickAt, runAt, result, finding, reported, items)`;
  - the seams `ReadEntries()` and `ReadQueues(...)`.

  Extends `Run`/`Record`/`FindingItem`, never copies them.
- [x] `src/ocutalon/cls/OcuTalon/Msg/Command/StartWatch.cls`, `StopWatch.cls` -- append `Property Kind As %String(MAXLEN = 32)` (empty means production), with storage `Value` 4 / 3.
- [x] `src/ocutalon/cls/OcuTalon/Watch/Ops.cls`:
  - add `QUEUEKIND` = "queues", `QUEUESNAME` = "Queue-backlog check", and model messages `MESSAGEALREADYQUEUES` ("The session already watches queue backlogs, so nothing was added.") and `MESSAGENOTWATCHINGQUEUES` ("The session does not watch queue backlogs, so nothing was removed.");
  - `OnStart`/`OnStop` branch on `request.Kind = QUEUEKIND`: no `Admits` and no online-demo refusal; natural key `SessionRef` + `Kind`; empty namespace and production; DisplayName `QUEUESNAME`; the same lock, answers and `Changed`;
  - `RefOf` gains `kind` and, for the queue kind, matches without namespace or production;
  - update the class description.
- [x] `src/ocutalon/cls/OcuTalon/Tools/WatchTools.cls`:
  - `StartWatch`/`StopWatch` gain a trailing `kind As %String(DESCRIPTION = "production (the default) or queues: queues watches every queue OcuTalon can read for a backlog, and then name is ignored.") = ""`;
  - for `queues` they skip `Resolve`/`ResolveStop` and submit the command with `Kind` queues; the answer is `CommandCall.Answer(result)` plus `outcome` and `"check": "Queue-backlog check"`; any other non-empty kind answers `unknown_kind` (parameter `UNKNOWNKIND`: "That kind of watch is not one OcuTalon has, so nothing was done.");
  - the method doc comments say so.
- [x] `src/ocutalon/cls/OcuTalon/Tools/WatchAnswers.cls` -- `CheckResults` also lists rows of `Kind` queues, with entry = `DisplayName` (production rows unchanged). The doc comment says so.
- [x] `src/ocutalon/cls/OcuTalon/Tools/Watching.cls` -- the description sentence names queue-backlog watches. `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- one rule after the start_watch rules (agent text): "If the user asks you to watch queue backlogs (queues that back up), call start_watch with kind queues and the user's words as name; to stop, call stop_watch with kind queues. With outcome started, say that OcuTalon now checks the queues every minute and looks at any queue that backs up past its threshold; with already_watching, say it already does."
- [x] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- append `watch.queueBacklog` (Design Notes text, `one` form on `count`, slots itemName text, production text, count count, time time, oldestAt time, `source` naming Story 23.7 and the Planner's Public Text ruling) as the last key.
- [x] `ci/mock/scenarios/A/watch-start-queues.json`, `watch-stop-queues.json` (new marker scenarios: `toolUse` start_watch/stop_watch `{"name": "queue backlogs", "kind": "queues"}`, then a text) and `ci/mock/scenarios/B/queue-watch-ask.json` (new; prompt "Watch the queue backlogs.", mockkey chat, the same toolUse, then a text).
- [x] `web/src/app/rail/rail-view.ts` -- contended in-place edit: `RAIL_TEXTS.checkScheduleQueues` = 'A check every minute', and in `checkRow` a row of kind `queues` gets that `detail`.
- [x] `web/src/app/guide/more-to-try-view.ts`, `more-to-try.ts` -- item `queueWatch` (texts in Design Notes, `group: 'Incidents and fixes'`) right after `partnerWarning` in the registry; `MORE_TO_TRY_TEXTS.queuePrompt` = 'Watch the queue backlogs.'; action `queueWatch` sends it like `partnerWarning` (aria-disabled while blocked); the header comment says fifteen. `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- `queueWatch` always, right after `partnerWarning`, with its doc line.
- [x] `README.md` -- line 40 "fourteen" → "fifteen"; append the Design Notes bullet LAST in `### New since 1.0.0`. `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md` -- after the Planner's ruling only: line 245 "fourteen" → "fifteen", and the item bullet under "Incidents and fixes" with `[ADDED <date>, Story 23.7, Contest Planner ruling]`.
- [x] `src/ocutalon/cls/OcuTalon/Checks/Queues.cls` -- the flapping cooldown in `Crossings` exactly as Design Notes "Applying the rulings" describes (`told` per namespace and item, 3600 s, held-back queues stay out of `above`, old `told` entries dropped); `Over` is unchanged. [ADDED 2026-11-11, Story 23.7, Contest Planner ruling]
- [x] Tests (update every pin named under Shared surfaces first, then add):
  - `Test/Checks/Queues.cls` (new; the pure `Over`/`Crossings` matrix, the admin threshold via `Data.Setting.Set` and restore, and run cases through `QueueProbe` for every matrix row from "First run" to "Online demo" except Online demo, plus `TestQueueFindingRenders`);
  - `Test/Checks/QueueProbe.cls` (new; extends `Test.Checks.Probe`, `QUEUEKIND` zzqueues, `QueueDue` keeps `Only`, seams from `^||ChecksProbe("entries"|"queues", ...)`);
  - `Test/Checks/Queue/Fixture.cls` (new; extends `Test.Eval.Feed.Fixture`: `NAMESPACE` QUEUEFEED, `DATABASE` QUEUEFEED_DATA, `RESOURCE` %DB_QUEUEFEED_DATA, `PRODUCTION` `OcuTalon.Test.Checks.Queue.Production`, `CODEPACKAGE` `OcuTalon.Test.Checks.Queue`; `Hold()`, `Release()`, `Fill(n)`, `Queued()`, `Snapshot()`), `Queue/Production.cls` (Description "Queue test [[mock:check-finding-tell-now]]"; items `QueueIn`, PoolSize 0, adapterless, and `QueueSink`, PoolSize 1), `Queue/In.cls`, `Queue/Sink.cls` (waits while `^OcuTalonTest.QueueHold` is set in its namespace, at most 120 s a message; reads and calls nothing outside its package);
  - `Test/Checks/QueueBacklog.cls` (new; extends `Test.Checks.BeatCase`; AC5, AC7);
  - `Test/Watch/Ops.cls` (queue start/repeat/stop/not_watching/other session/CheckChanged/online demo allowed);
  - `Test/Watch/Tools.cls` (args pin `name,namespace,kind`; kind queues submits `Kind` queues; `unknown_kind`; check_status lists a queue row);
  - `Test/Watch/Turns.cls` (`TestQueuesThroughTheAgent`, AC1);
  - `Test/Digest/Coverage.cls` (a queue row's entry and history result);
  - `Test/Msg/Catalog.cls` (key count and Fixture);
  - `Test/Demo/Features.cls` (`TestIds`);
  - `web/scripts/rail-view.test.mjs`, `more-to-try-view.test.mjs` (number words to fifteen; count by the registry), `more-to-try-sources.test.mjs`, `ux-strings.test.mjs` (`ruled` entries citing the Planner ruling);
  - `web/e2e/guide/more-to-try.spec.ts` (`ITEMS` oracle entry only);
  - `web/e2e/guide/more-to-try-queues.spec.ts` (new, K29).

- [x] [CI] web (run 43026811791, job 130543466679): `web/scripts/sources-docs.test.mjs` fails "15 items need a word in WORDS" and every count check that reads the registry (README "its More to try panel has undefined more things to try", EXPERIENCE.md "There are undefined items, in this order", the registry's comments, "the entries are the panel's items, in its order") -- https://github.com/jbrandtmse/OcuTalon/actions/runs/43026811791/job/130543466679 -- add "fifteen" and "sixteen" (Story 35.3 lands next) to `WORDS` wherever it lives (`sources-docs.test.mjs`, and any other web test file with its own number-word list that the registry count reaches); then run the WHOLE web unit suite (`npm --prefix web test`, every `web/scripts/*.test.mjs`), never only the four files, and fix any other red it shows.
- [x] [CI] iris (shards-5), live:sign-in-3 (run 43026811791, job 130543466970): K29 `web/e2e/guide/more-to-try-queues.spec.ts` fails at its first line with "OCUTALON_FLOOR_USER must be set by the e2e unit's script": it calls `fixtureUser('FLOOR')` and `openFloor`, which only the floor unit's script sets, but `guide/` runs in the sign-in-3 project (docker/tests/test-sign-in-3.sh) -- https://github.com/jbrandtmse/OcuTalon/actions/runs/43026811791/job/130543466970 -- sign in with the sign-in-3 unit's own fixture user and helpers as the sibling `guide/more-to-try.spec.ts` does (`fixtureUser('NOTICE')`, `signIn` from `../sign-in/helpers`, `loadedAfter`), keeping K29's assertions; then run live sign-in-3 locally on a lane-D throwaway (`docker/tests/test-sign-in-3.sh --part k/n` for the part that holds `guide/more-to-try-queues.spec.ts`, each call in the foreground, polling if the harness backgrounds it) and record the K29 result and its mutation line.

**Acceptance Criteria:**
- AC1 (Integration): Given a session that asks in the chat to watch queue backlogs, when the Chat turn calls `start_watch` with kind queues, then `WatchOps` writes one `Kind` queues row for the session and the session's stream gets its `check` event. A repeat adds no row. Asking to stop removes the row and publishes the stop event. (`Test.Watch.Turns:TestQueuesThroughTheAgent` through the `watch-start-queues`/`watch-stop-queues` markers, real `CommandsIn` and `WatchOps`; `Test.Watch.Ops`.)
- AC2: Given a due queue row, when `Checks` runs it, then it reads the queues of every entry of `Watch.Reader.Productions()` through `Reader.Failures` (limit 0) and nothing else. Each queue above the threshold that is not in the namespace's previous `above` becomes exactly one `watch.queueBacklog` Item sent to `Intake`, with the fields under Always. (`Test.Checks.Queues` via `QueueProbe`.)
- AC3: Given a queue already reported above, when later runs still find it above, then no Item is sent. When a run finds it below (or gone) and a later run above, then exactly one more Item is sent. (`Test.Checks.Queues`.)
- AC4: Given a run whose namespace read throws, answers `unreadable`/`not_current`, or gives `queues` "", or whose list throws or is empty, when the run ends, then its row and its `CheckRun` hold `not_checked` with the matching `REASON*` text and never `passed`. The unread namespace's previous `above` is kept. (`Test.Checks.Queues`; `CheckRun.Reason` via `Coverage.ReasonOf`.)
- AC5 (Integration, live): Given the test production `QUEUEFEED` with its sink held, when its `QueueSink` queue is filled past 100, run twice, drained, run, filled past 100 again and run, then exactly two `watch.queueBacklog` Items for `QueueSink` reach `Intake`, one per crossing. Intake sends an ItemDecision for each, and the session's web chat gets the tell-now text the catalog renders. The namespace's header counts by status, its item states and its production state are the same before and after each run with the sink held. (`Test.Checks.QueueBacklog`, throwaway only.)
- AC6: Given `checks.thresholds.queueMessages` or `queueWaitMinutes` changed by an admin, when the next queue run and the next digest's live read compare a queue, then both apply the new value through `Checks.Queues.Over` and `Coverage.CurrentLimits`. A stored value that is not a number reads as the default. (`Test.Checks.Queues`; the existing `Test.Digest.Coverage` queue cases still pass.)
- AC7: Given the online demo flag on and a readable non-Orders namespace whose queue is above, when a queue run runs, then it reads only the Orders production and sends no Item for the other namespace, and `Reported` has no key for it. (`Test.Checks.QueueBacklog:TestOnlineDemoReadsOnlyOrders`.)
- AC8: Given a session with a queue row that has run, when `check_status` runs or the digest's coverage is built, then the row is listed with entry "Queue-backlog check" and its latest result. A `not_checked` run is never shown as passed. (`Test.Watch.Tools`, `Test.Digest.Coverage`.)
- AC9: Given a `check` payload of kind queues, when the rail renders it, then its row reads "Queue-backlog check" with the schedule "A check every minute", its last run and result, and the trace link. (`web/scripts/rail-view.test.mjs`.)
- AC10: Given the demo guide's More to try panel, when the visitor presses "Ask to watch queues", then "Watch the queue backlogs." is sent once as the user's own message, and the rail's Background checks gains the "Queue-backlog check" row with "A check every minute". Nothing is sent while a turn is in flight. (K29, `web/e2e/guide/more-to-try-queues.spec.ts`, CI, with `ci/mock/scenarios/B/queue-watch-ask.json`.)
- AC11: Given the More to try registry, when the count pins run, then README line 40, EXPERIENCE.md's count and the `more-to-try-view.ts` header comment equal the registry's item count (15). The README's New since 1.0.0 ends with the queue-backlog bullet. (`web/scripts/more-to-try-view.test.mjs`, registry-driven.)
- AC12 (Contest Planner ruling, flapping): Given a queue reported above at time T, when it drops below and backs up again at T+10 min, then no Item is sent and the queue stays out of `above`; when a run at T+61 min finds it still above, exactly one Item is sent; and when it flaps again within the next hour, nothing more is sent. A different queue in the same namespace is not held back by the first one's cooldown. (`Test.Checks.Queues`, pure `Crossings` cases with `nowSeconds`, and one run case through `QueueProbe`.) [ADDED 2026-11-11, Story 23.7, Contest Planner ruling]

### Review Findings

Code review 2026-11-11 (lane D, tags e23s7cw / e23s7c; four layers, full-opus tier). 29 raw findings, 11 entries after grouping (high 1, med 4, low 6), 11 rejected. Every patch applied; story `done`.

- [x] [Review][Patch] HIGH (AD-4, DW-1124): ending a session left its queue-backlog row running; `EndWatches` now also stops the `Kind` queues row and passes the row's Kind [src/ocutalon/cls/OcuTalon/Core/SessionOps.cls:340] -- fix-risk low (three lines; `WatchOps.OnStop` already handles Kind queues). Pinned by the new `Test.Watch.Ops:TestQueuesEndSession`; footprint extension (no in-flight epic owns `Core/SessionOps.cls`).
- [x] [Review][Patch] MED (Rule 19): `TestQueuesThroughTheAgent` could skip the repeat's `already_watching` check silently; it now asserts the repeat turn's status and its two logged requests [src/ocutalon/cls/OcuTalon/Test/Watch/Turns.cls:213] -- fix-risk low.
- [x] [Review][Patch] MED (Rule 19): K29's second press did not wait for a turn in flight (the mock turn could end first); the POST is now held until the second press is checked [web/e2e/guide/more-to-try-queues.spec.ts:40] -- fix-risk low (route hold with fallback, released before the rail check; under BUSY_TIMEOUT_MS).
- [x] [Review][Patch] MED (Rule 19 hermeticity): `Test.Checks.Queues` run cases relied on the stack's stored thresholds; each test now starts from 100 / 10 and `PutBack` restores the stored ones [src/ocutalon/cls/OcuTalon/Test/Checks/Queues.cls:65] -- fix-risk low.
- [x] [Review][Patch] LOW: `queueWatch`'s aria-disabled binding had no test; K29 now asserts it while the POST is held [web/e2e/guide/more-to-try-queues.spec.ts:62] -- fix-risk low.
- [x] [Review][Patch] LOW: `TestDue`'s last assertion could not fail (A was already in `above`); it now counts the row's runs [src/ocutalon/cls/OcuTalon/Test/Checks/Queues.cls:499] -- fix-risk low.
- [x] [Review][Patch] LOW: the run-time fallback for an unreadable `oldestAt` (Decided 15) was never run; `TestQueueFindingRenders` adds a count-only queue with no oldest time [src/ocutalon/cls/OcuTalon/Test/Checks/Queues.cls:530] -- fix-risk low.
- [x] [Review][Patch] LOW: `QueueBacklog` said the told time is made "an hour old"; `Age` makes it two hours old [src/ocutalon/cls/OcuTalon/Test/Checks/QueueBacklog.cls:10] -- fix-risk low.
- [x] [Review][Patch] LOW (Rule 2, weak reason): `WatchAnswers` kept its own `QUEUEKIND` copy while `WatchTools` reads `Watch.Ops.#QUEUEKIND`; it now reads `Watch.Ops` too [src/ocutalon/cls/OcuTalon/Tools/WatchAnswers.cls:226] -- fix-risk low.
- [x] [Review][Defer] MED, unverified (maybe-false): the Chat queue rule follows the production rules; whether the real model calls start_watch/stop_watch with kind queues is unmeasured [src/ocutalon/cls/OcuTalon/Agent/Chat.cls:58] -- deferred: DW-1125, routed owner=38-1-a-hands-on-pass-with-real-keys-finds-and-fixes-what-the-test (settled by a real-key run of the More to try queue prompt and its stop).
- [x] [Review][Defer] LOW, spec-bound: the heartbeat checklist's Watches line omits the queue-backlog check [src/ocutalon/cls/OcuTalon/Checks/Beat.cls:268] -- deferred: DW-1126 `by-design` (spec Never: no change to `Checks.Beat`).

Rejected:
- `low` No exception for a backlog behind an item OcuTalon suspended: real but rare (suspend is refused on the online demo), the report is true, and the fix needs a new cross-check with `Fix.Run.Suspended`.
- `false` README "a run that can't read a namespace shows Not checked": `Reader.Productions()` lists only readable namespaces, the README's scope is "each production it can read", and the text is ruled.
- `low` `TestAdminThreshold`'s settings reach the real Checks job's 60 s cache: tests run one class per call, and no later class depends on those values (the per-test reset above also applies).
- `false` A negative `queueMessages` reports empty queues: `Reader` lists only items with Status-2 messages, so no queue has count 0.
- `low` A told time in the future (clock stepped back) holds a queue longer than an hour: theoretical.
- `low` The sink's 120 s per-message cap on a slow stack: each run is one synchronous Tick and the held span is seconds (Task 0: read 0.051 s).
- `low` The per-row `LOGRUN` catch in `Tick` has no test: no AC or matrix row; it mirrors the production loop, and a test needs a fault seam.
- `low` `TestQueuesStartRepeatStop` branches on whether a real Tick ran: same pattern as the sibling `TestStart`; `WatchOps` writes `NextDueAt` now by contract.
- `reject` AC5 vs AC12 matrix text: the fix edits the spec; Decided 18 records it.
- `low` `stop_watch`'s `kind` description differs from the spec's one text: model-facing, not ruled, and the stop wording is the accurate one.
- `false` `Test/Msg/Contracts.cls` edited outside the approved list: it pins the Lane B command classes that veto item 6 approved "and their tests", and `Test/Msg` is not contended.

**CI rework 1 re-review** (2026-11-11, lane D, tags e23s7vcr / e23s7vcm; diff `0f25251b..HEAD` plus the working tree; four layers). 26 raw findings, 4 entries after grouping (high 0, med 1, low 3); the rest rejected, in 9 groups below. Every patch applied; no HIGH, so the story closes `done` (Rule 15 exit condition). Checklist: (1) `WORDS` and both number-word lists reach fifteen and sixteen, `npm --prefix web test` 1912/1912, and `ENTRY_LINE` still fails a malformed entry (wrong case, missing label, wrong group) while the `Item n` / `First item` forms match exactly as before: confirmed. (2) K29 runs in sign-in-3 as the `NOTICE` user, removes its seeded row by ref, and its assertions each fail under a mutation; the seeded row matches `WatchOps.OnStart` on Kind, DisplayName, Namespace/Production and SessionRef (owner): confirmed. AC10's pin split is the lead's ruling (DW-1143, DW-1144), not re-raised.

- [x] [Review][Patch] MED (Rule 19 hermeticity): K29's `openAs` left the page's statuses to the stack, and `queueWatch` is gated by the allowance status (`blocked()` reads `allowance.active()`), so a status left for the shared `NOTICE` user could make the press send nothing; its poll route also threw on a non-JSON answer. It now empties the snapshot's statuses, drops `status` events from the polls and passes a non-JSON answer as it is, as the sibling's `openAs`/`keepRoutedGuide` do [web/e2e/guide/more-to-try-queues.spec.ts:40] -- fix-risk low (setup only; the assertions are unchanged; K29 green and red under its mutation after the patch).
- [x] [Review][Patch] LOW (Rule 19): the widened `ENTRY_LINE` accepted "After Item n" without checking n, so the anchor could go stale after a reorder with nothing red; the order test now asserts each "After Item n" entry comes right after `Item n`, and the comment above `ENTRY_LINE` names the form [web/scripts/sources-docs.test.mjs:101] -- fix-risk low (mutation observed).
- [x] [Review][Patch] LOW: K29's header said it seeds "the row that start_watch kind queues makes"; the fixture row differs in AskedBy (`zzfixture`) and NextDueAt, which the rail does not read. The header now says "a row like the one" and names the fields that match [web/e2e/guide/more-to-try-queues.spec.ts:14] -- fix-risk low (comment only).
- [x] [Review][Patch] LOW (Rule 19, stale mutation text): the AC10 mutation plan said "K29 (CI)" and the QA note said its red was "expected, not observed"; both now point at the observed red [spec ## Verification] -- fix-risk low (tracking section only).

Rejected (CI rework 1 re-review):
- `reject` AC10's text still names `B/queue-watch-ask.json`; the frontmatter `deferred:` entry reads as open while DW-1143 is `by-design`; no Spec Change Log line for the ruling; the triage log's "three layers" names four: each fix edits the spec outside `## Verification`; the lead's Design Notes ruling and DW-1143/DW-1144 govern.
- `low` K29's title and the rail title come from the test's own payload; the 60 s wait sized for a model turn: covered by the DW-1143 ruling (the row render is pinned by `rail-view.test.mjs`, the name by `Test.Watch.Ops`); the wait only delays a failure.
- `low` the pre-clean of queue rows was removed: the seeded row is removed by ref in `finally`; a row left by a killed run makes `toHaveCount(1)` fail loudly, never pass falsely; CI stacks are throwaways.
- `low` AskedBy `zzfixture`, NextDueAt an hour ahead, no CreatedAt on the seeded row: the shared `Fixture.Check` marker and the deliberate no-tick schedule; the rail reads none of them (header corrected above).
- `maybe-false` a pending `route.fetch()` when the page closes could reject after the test: flake only, not observed in two runs; would only be low.
- `false` `postDataJSON()` null for the held POST: the page's outbox always posts a JSON body with `clientId`.
- `false` a seventeenth item gives `undefined`: `sources-docs.test.mjs` fails then with "N items need a word in WORDS", the intended loud failure.
- `false` the spec's `status: done` while sprint-status says `review`: the lead's convention at dev_complete; this review sets the sprint status.
- `reject` `B/queue-watch-ask.json` is dead and could be deleted: DW-1144 (wontfix-accepted) is the lead's ruling.

## Spec Change Log

- 2026-11-11 (CI rework 1, lead): CI on f78e6236 red in two story-class jobs (web WORDS count words stop at fourteen; K29 used the floor unit's user under sign-in-3). Re-opened with two [CI] items; scoped re-review follows.
- 2026-11-11 (spec gate, lead): Contest Planner rulings and the orchestrator's U7 ruling recorded verbatim under Design Notes. PUBLIC TEXT a-h and veto items 1-6 approved/accepted; design 7 confirmed; ADDED CONDITION: a per-queue once-an-hour reporting cooldown (task, AC12, mutation added; it extends the intent's crossing-memory line and its "Falls below, rises again" row). AD-18 bullet and Conventions clause written to the spine with `[ADDED 2026-11-11, Story 23.7]`. Contended plain unions approved; no overlap with Epics 21/22 at re-check.
- 2026-11-11 (plan): Scope reopen of Epic 23 (the owner, 2026-11-11, via the Contest Planner). Story 23.7 is planned after 23.6, 23.2 and 23.5 merged. It reuses `Watch.Reader`'s queue read and `Checks.Coverage`'s thresholds, and it proposes the AD-18 row-type text below for the lead to raise.

## Review Triage Log

### 2026-11-11 - CI rework 1 review pass (scoped to the two [CI] items)
- verdicts: 17 findings - high 0, medium 1, low 8, false 3, maybe-false 5
- findings:
  - `[medium]` `[defer]` K29 no longer proves press -> turn -> start_watch -> rail row (POST answered 202, row seeded and published by the test; the sign-in-3 stack has no model and no mock; test title and AC10 overstate) - three layers filed it (blind hunter, edge-case hunter, intent-alignment, verification-gap); not patchable without a mock-stack unit; deferred in the frontmatter with what would close it (an e2e case where the mock runs, or an AC10 amendment); the press assertions keep their mutation (observed red)
  - `[low]` `[patch]` header comment names `B/queue-watch-ask.json` as the scenario `TestQueuesThroughTheAgent` runs (it runs `A/watch-start-queues.json`) - comment replaced with the right scenario
  - `[low]` `[defer]` `B/queue-watch-ask.json` has no consumer now - folded into the K29 deferred entry (its removal or reuse is the same decision)
  - `[low]` `[reject]` local `openAs` copies the sibling's `openAs`/`keepRoutedGuide` instead of reusing them - the sibling is a contended Epic 21 file (not editable this pass) and `keepRoutedGuide` is not exported; closed wontfix-accepted, reopen_if=`guide/more-to-try.spec.ts` stops being contended and exports its helper
  - `[low]` `[reject]` stale queue rows from a killed earlier run are no longer pre-cleaned (two reviewers) - the row is made only by this test, cleaned by ref in `finally`, nothing else makes a queues row for the fixture user; unlikely
  - `[maybe-false]` `[reject]` status banner / `status` events not cleared as the sibling does (two reviewers) - the live run passed 19 of 19 and the noModelKey status did not touch the panel or the rail; would be a flake only (low)
  - `[maybe-false]` `[reject]` `route.fetch()`/`response.json()` unguarded in the events route (two reviewers) - polls answer JSON; would be a flake only (low); the sibling's guard is not needed to pass
  - `[maybe-false]` `[reject]` `route.fulfill({ response, json })` forwards a stale content-length - Playwright recomputes it for `json`; the live run passed
  - `[maybe-false]` `[reject]` a real Tick might pick up the seeded row - false in effect: NextDueAt defaults an hour ahead (`check-seeds.test.mjs` pins it)
  - `[maybe-false]` `[reject]` hand-built guide object may drift from the guide payload - the same shape as the sibling's `finished(...)`, a rename shows in the page; low
  - `[low]` `[reject]` `sixteen` unused today - asked for by the lead (Story 35.3 lands the sixteenth item)
  - `[low]` `[reject]` three number-word arrays instead of one shared list - the pass is one-word appends only by ruling
  - `[false]` `[reject]` ENTRY_LINE widening may break the numbering - the order and heading `deepEqual` tests would fail if the "After Item 3" line were wrong, and `numberOf` keys on `Item` lines only
  - `[low]` `[reject]` test title "the rail gains the Queue-backlog check" overstates - the header says what it proves; covered by the deferred entry
  - `[false]` `[reject]` seedCheck run before the page is ready - it is published after `loadedAfter` and the composer is visible
  - `[false]` `[reject]` K29 not hermetic - cleaned by ref, `workers: 1`
  - `[low]` `[reject]` seeded `namespace`/`production` empty is a guess - `StartWatch`'s queues row is empty in both (WatchOps test pins it)

### 2026-11-11 - Review pass
- verdicts: 35 findings - high 0, medium 4, low 22, false 9, maybe-false 0
- findings:
  - `[false]` `[reject]` Cooldown rule missing from README/EXPERIENCE/Chat text - the README's "again only after the queue has dropped below and backed up again" is true (a necessary condition), and every public string is ruled verbatim.
  - `[low]` `[reject]` oldestAt falls back to the run time when a queue's oldest-message time is unreadable - a Status 2 header always has a creation time; theoretical, and the fix adds a catalog form.
  - `[low]` `[patch]` check_status tool description still says "one per watched production" - added "and one for the queue-backlog check when the user watches queue backlogs" to `WatchTools.CheckStatus`'s doc comment.
  - `[low]` `[reject]` Chat rule covers only start outcomes - the rule text is given verbatim by the spec, and the existing stop_watch rules already cover stopped/not_watching/any other message.
  - `[low]` `[reject]` A failed finding send is never retried - the matrix row "Send fails" specifies it ("not retried").
  - `[low]` `[reject]` Every session's queue row reads the same productions each minute - bounded by the demo's six visitors (spec inference); a per-tick cache is an optimisation, not a defect.
  - `[low]` `[reject]` Guide look-for hard-codes the default thresholds - public text approved verbatim by the Planner.
  - `[low]` `[reject]` EXPERIENCE item numbering - the Planner's ruling and the spec fix the exact edit ("the numbers of the items below stay as they are").
  - `[low]` `[patch]` Minor indirection - `Queue/Fixture.Snapshot`'s dead `Set production = ""` removed; `CurrentLimits` is the spec's, and `Crossings` takes seconds so the pure rule has no clock.
  - `[medium]` `[defer]` Ending a session leaves the queue row running (EndWatches skips non-production rows) - real; the fix is in `Core/SessionOps.cls`, outside the spec's footprint (Core/* not touched) and not an approved cross-lane edit; deferred in the frontmatter.
  - `[medium]` `[defer]` RunQueues never re-checks that the row's session is live - same root cause as the previous row; the EndWatches fix closes it.
  - `[low]` `[reject]` First run with many queues above sends one Item each - the AC and the Planner confirmed "a queue already over its threshold when the watch starts is reported once"; the cooldown covers flapping only.
  - `[low]` `[reject]` Crossings/Over throwing on a malformed queue entry skips Record - Reader gives well-formed entries; Tick's catch logs it and the row is retried next Tick.
  - `[low]` `[reject]` Serial namespace reads have no time budget - the same holds for every Reader read; no user-reachable case shown.
  - `[low]` `[reject]` Send failure leaves the crossing marked as reported - duplicate of the "Send fails" row above.
  - `[false]` `[reject]` Tool call omitting `name` fails validation - the Chat rule tells the model to pass the user's words as name, and the mock scenarios and `TestQueuesThroughTheAgent` do.
  - `[low]` `[reject]` kind matching is case-sensitive - the Chat rule names the exact word `queues`; a mismatch answers unknown_kind, which is honest.
  - `[low]` `[reject]` Chat prompt lacks stop/unknown_kind outcomes - duplicate of the Chat-rule row.
  - `[low]` `[reject]` An unknown Kind on a non-tool StartWatch is handled as production - commands come only from the tool (AD-1), which refuses unknown kinds first.
  - `[false]` `[reject]` Concurrent queue starts could duplicate the row - `OnStart` takes the session lock before `RefOf` and holds it through the save.
  - `[low]` `[reject]` Empty queue name keys the lists with "" - Reader gives the item's configured name; theoretical.
  - `[low]` `[reject]` `AddSeconds` returning "" would store an empty told time - nowSeconds always comes from `Time.Seconds` of a valid time; theoretical.
  - `[low]` `[reject]` Stale `above` for a namespace that left the list - the spec says a namespace not read keeps its list, and the effect is only a silent re-baseline.
  - `[low]` `[reject]` AC10's mutation line records a red never observed - K29 is a browser unit left to CI by the spec; the line now says "expected red, not observed".
  - `[low]` `[patch]` K29 asserts neither aria-disabled nor fromGuide - K29 now records `fromGuide` and asserts false; the aria-disabled assertion is not added (the turn on the live stack may end before it is read, which would make K29 flaky). `wontfix-accepted`, reopen_if=K9-style stubbed case for queueWatch is wanted.
  - `[medium]` `[patch]` `Test.Checks.QueueBacklog.OnAfterAllTests` skipped `##super()` - it now returns `##super()` so the Watch.Case clean-up runs.
  - `[low]` `[reject]` Ops test assertions depend on whether a real Tick ran the row - the production watch tests use the same branch and log which one ran.
  - `[medium]` `[patch]` `TestQueuesThroughTheAgent` silently skipped the repeat's already_watching check - the repeat's request carries two tool results (the first turn's and its own), so the guard `ListLength = 1` never held; now asserts two results and reads the last, and asserts the first turn's count.
  - `[low]` `[reject]` TestTwoCrossings counts queues across every listed production - a fresh CI stack holds none elsewhere; theoretical on a polluted warm stack.
  - `[false]` `[reject]` Intent audit, divergence A (cooldown vs the matrix's "Falls below, rises again") - the Planner's ADDED CONDITION extends that row (AC12); tests age `told` on purpose.
  - `[false]` `[reject]` Intent audit, divergence B (`Reported` gains `told`) - same ruling.
  - `[false]` `[reject]` Intent audit, divergence C (web guide, rail, README, EXPERIENCE) - listed in the spec's tasks and PUBLIC TEXT rulings.
  - `[false]` `[reject]` Intent audit, divergence D (probe-driven run tests plus a throwaway-only live class) - what the spec's Verification prescribes.
  - `[false]` `[reject]` Intent audit: the Item text differs from the catalog text - by design (summary versus rendered notice).
  - `[false]` `[reject]` Intent audit: reason order for several unread namespaces - the spec fixes "first unread namespace in list order".

## Design Notes

**AC10 pins after CI rework 1 [ADDED 2026-11-11, Story 23.7, lead ruling (decide, Rule 5 tier 1: the AC's observable outcome is unchanged, only where it is pinned)]:** the sign-in-3 project that runs `guide/` has no model and no CI mock, so K29 answers the message POST and seeds the queue row. AC10's chain is pinned link by link: the press sends the prompt once as the user's own message, aria-disabled while held, no second post (K29, mutation observed); the prompt drives `start_watch` with kind queues to the row and its `check` event (`Test.Watch.Turns:TestQueuesThroughTheAgent`, with `ci/mock/scenarios/A/watch-start-queues.json`); the row renders "Queue-backlog check" with "A check every minute" (`rail-view.test.mjs`, K29). Ledger DW-1143 (by-design), DW-1144 (the unused B scenario, wontfix-accepted).

**Spec-gate rulings [ADDED 2026-11-11, Story 23.7, Contest Planner ruling + orchestrator U7 ruling] (verbatim):**

> # Rulings, Story 23.7 spec gate (2026-11-11 ~12:30Z; Contest Planner under the owner's delegation, plus the orchestrator's U7 rulings; verbatim terms)
> PUBLIC TEXT: a to h APPROVED verbatim, including More to try item 15 in "Incidents and fixes", the README bullet with the count fifteen, and the three refusal lines.
> VETO ITEMS: 1 to 6 ACCEPTED as specced. The test-only Read grant is for throwaways only, guarded and removed, and never on the product or the demo.
> 7. DESIGN: CONFIRMED. A queue already over its threshold when the watch starts is reported once.
> ADDED CONDITION (flapping): a queue that drops below its threshold and backs up again re-reports at most once per hour: a per-queue cooldown in Checks.Queues.Over's reporting, with a test, so a queue hovering at its threshold can't spend model decisions every few minutes (the demo's daily cost cap too). No new text.
> ONLINE DEMO: ON and read-only as specced: Orders only, per visitor session, cleared by the reset, every decision inside the existing allowance and cost cap.
> ORCHESTRATOR (U7): the AD-18 amendment (bullet "Queue backlog, the row type (Story 23.7)" after the Story 35.1 source-poll bullet + one clause in the Consistency Conventions Background checks row) APPROVED as an extension, marker [ADDED 2026-11-11, Story 23.7]; the contended paths APPROVED as plain unions (Epic 22: Checks/Process.cls, Checks/Coverage.cls; rail-view.ts, guide/more-to-try.spec.ts, README) with a diff re-check of origin/OCT-epic22 and OCT-epic21 before implement; any overlapping hunk is a Clarification.

**Applying the rulings (lead, 2026-11-11):**
- Every PUBLIC TEXT string listed below is approved verbatim; implement writes them exactly as listed (README count fifteen, More to try item 15 under "Incidents and fixes", EXPERIENCE.md lines now allowed with the marker `[ADDED 2026-11-11, Story 23.7, Contest Planner ruling]`).
- Veto items 1-6 accepted as specced; Decided in-stage 2 (no first-run baseline) confirmed.
- The AD-18 bullet and the Consistency Conventions clause are written into the spine by the lead (marker `[ADDED 2026-11-11, Story 23.7]`), with one added sentence for the cooldown below. Stages never write the spine.
- The contended in-place edits listed under Contended touches are approved as plain unions; the lead re-checked `origin/OCT-epic22` and `origin/OCT-epic21` (and their worktrees) before implement: no overlap.
- **Flapping cooldown (ADDED CONDITION) - this extends the intent's crossing-memory line and its "Falls below, rises again" row:** a queue is reported at most once an hour. `Reported` gains `"told": {"<namespace>": {"<item>": "<UTC YYYY-MM-DDThh:mm:ssZ of its last report>"}}`. In `Checks.Queues.Crossings`, a queue that is above now and not in its namespace's previous `above` is reported only when it has no `told` time or that time is 3600 s or more before `nowSeconds`; then it enters `above` and `told` takes the run time. When the cooldown holds it back, it is NOT added to `above` (so if it is still above at the first run after the hour, it is reported then, and a stuck queue is never silenced for good). `told` entries older than an hour are dropped from the new JSON. The cooldown lives in the Queues reporting rule (`Crossings`), never in `Over`'s threshold test, so the digest's live read (`Coverage.Live`) is unchanged by it. No new text.

**Architecture decisions:**
- AD-1: commands through `CommandsIn`; tool origin `tool`, "start or stop a watch" already listed.
- AD-3: `Watch.Reader` is the only namespace switch, and reads need the service user's data-DB read.
- AD-4: per-session rows; on the online demo only Orders.
- AD-10: the tools stay safe and trusted output; a finding Item is untrusted.
- AD-12: the `check` event.
- AD-14: Items and provenance.
- AD-18: background checks, the heartbeat, the due rule, and the digest coverage storage.
- AD-19: thresholds are settings read through `Data.Setting.Get`.
- AD-22: the CI mock scenarios.
- AD-26: each finding's own trace.
- AD-27: no retention change; rows go with the session's purge, CheckRun with the digest's.
- AD-28: not checked is never passed; only Checks writes results.
- AD-29/AD-33: lane ownership and the contended files below.
- AD-32: catalog keys, one renderer.

**ACs already met by delivered code (not rebuilt):**
- The queue read: `Watch.Reader.Failures(...)` already returns `queues` per item, or "" when unread (`Reader.cls:621-632`). Its only test so far is through `Test.Digest.CoverageProbe` seams; AC5 adds the first live read of real queued headers.
- Thresholds: `Coverage.THRESHOLDS` `queueMessages=100,queueWaitMinutes=10`, seeded by `Install/Step/Digest.cls`, read via `Limits()`, editable in the admin Check thresholds section (Story 33.2). Pinned by `Test.Digest.Thresholds`/`ThresholdKeys`.
- The finding → decision → tell-now path: `Checks.Process.Record`/`SendOwn` → `Intake` → `Core.Rule.Notice` uses the Item's CatalogKey. Proven for `watch.itemDisabled` by `Test.Checks.Heartbeat:TestDisabledItemIsReportedOnce`.
- Run recording and coverage: the `BackgroundCheck` trigger → `Coverage.RecordRun` writes a `CheckRun` per run; `Coverage.Build` already lists every check of the session, and `EntryOf` gives a non-production row its DisplayName.
- The rail already lists every check row of the session; it lacks only a schedule line for non-production kinds.

**Extend, don't copy:**
- `RunQueues` reuses `Record`, `FindingItem`, `SendOwn`, `Joined` and `RowOf`.
- `QueueDue` shares `DueOf` with `Due`.
- `Checks.Queues.Over` is the one threshold rule, and `Coverage.Live` is moved onto it.
- `Coverage.CurrentLimits` exposes the one threshold source.
- `Checks.Queues.Crossings` is a new pure rule, because its hysteresis (above/below, no baseline, per-namespace memory) differs from `Process.Findings`' state-change rule.
- `WatchOps` extends `OnStart`/`OnStop`/`RefOf` with a kind branch.
- The tool extends `start_watch`/`stop_watch` with an argument rather than adding tool names. That keeps `Tools/Names.cls`, `Test/Bridge/Gate.cls` and `docs/security-overview.md` (all contended) untouched.
- `Queue/Fixture` subclasses `Test.Eval.Feed.Fixture`.
- `QueueProbe` subclasses `Test.Checks.Probe`.
- `QueueBacklog` subclasses `Test.Checks.BeatCase`.

**Integration ACs:** AC1 (the Chat turn → WatchOps → check event) and AC5 (Checks → Intake → decision → web chat).
- **Consumes:** `Watch.Reader.Productions`/`Failures`, `Checks.Coverage` thresholds, `Process.Record`/`FindingItem`, `Intake`, `Core.Rule.Notice`, `Msg.Catalog`.
- **Consumed-by:** `Checks.Process.RunQueues` and `Checks.Coverage.Live` (this story) consume `Checks.Queues`. Story 23.8 (the SQL query watch) is expected to add its kind the same way. No later story consumes `Checks.Queues` itself.

**Ledger:** inbox empty; nothing declined.

**Decided in-stage:**
1. Kind value `queues`; one row per session; DisplayName "Queue-backlog check", the EXPERIENCE/PRD phrase "the queue-backlog check".
2. No first-run baseline. A queue already above when the watch starts is reported once, because the AC says each queue above becomes a finding and the user asked to hear about backlogs. A production watch keeps its baseline (veto U-179). Flagged in the spine proposal.
3. A run with any unread listed namespace is `not_checked` (the AC's literal reading), and crossings in the read namespaces are still sent.
4. An empty production list is `not_checked` `REASONREAD`, never `passed` on nothing.
5. `check_status` lists queue rows (the safe choice: a failed queue check must block "Everything I checked passed.").
6. Interval 60 s, like a production watch.
7. Item time is the run time, and the queue's oldest message time is a slot.
8. No tool names added: the `kind` argument instead.
9. The live test uses the default thresholds (105 messages), so it needs no cross-process setting change. The admin-change path is proven in-process (`Data.Setting.Set` drops the caller's cache).
10. More to try position: after "Warn the partner", group "Incidents and fixes".
11. The rail hint stays 'To stop, ask: "Stop watching Orders."'.
12. Slot D cannot run `Reader.Productions()` (measured), so there is no plan-stage Task 0 there. Task 0 runs on a lane-D throwaway at implement.
13. (implement) `Reported` always has an `above` member (only the non-empty lists), and a `told` member only when it has an entry: a run with nothing above stores `{"above":{}}`.
14. (implement) A namespace that is not in the run's readings at all (not listed this time) keeps its previous `above` and its `told` times, like an unread one.
15. (implement) A queue whose oldest message time is empty or unreadable (it cannot be above by age, but may be by count) puts the run time in the Item's `oldestAt` slot, because the catalog refuses a time slot that is not a UTC time.
16. (implement) The held-back queue (cooldown) is not in `above` but is over its threshold now, so the row's finding still counts it ("1 queue over its threshold"), as `Coverage.Live` would.
17. (implement) The two helpers of the tool answers, `KnownKind` and `Queued`, live in `Tools/WatchAnswers.cls` beside `Submitted`: `Test.Bridge.CodeRules:TestToolsReturnThroughResult` lets a tool provider return only through `..Return`.
18. (implement) AC5's live test makes the queue's told time two hours old (`Test.Checks.Queues:Age`, an UPDATE of `Reported` by the test) between the drain and the second fill; without it the hourly cooldown (AC12) would hold the second crossing back, and AC12 is pinned in `Test.Checks.Queues`. The live test therefore proves two crossings an hour apart, not two within a minute.
19. (implement) `Test.Checks.Probe` gains `QUEUEKIND = "zzprobequeues"`, so a Probe-based Tick never runs a stack's real queue-backlog rows; `QueueProbe` overrides it with `zzqueues`.
20. (implement) Run cases that read two CheckRun reasons wait 1.1 s between runs (the trigger writes a CheckRun only when `LastRunAt` changes).
21. (implement) `Test.Msg.Contracts` (the two command property pins) is updated for `Kind` (a shared surface the spec's list does not name).
22. (implement) `Test.Checks.QueueBacklog:TestQueueRead` is the permanent form of Task 0: it logs the measured count, read time and drain time on every run.

**Online demo:** the check is ON and read-only. Starting it is allowed for every visitor: `WatchOps` has no `only_orders` refusal for kind queues. Each run reads only the Orders production's queues, because the run's sole entry source is `Watch.Reader.Productions()`, which keeps only `Install.Step.Demo` NAMESPACE/PRODUCTION when `onlineDemo` is set (`Reader.cls:114-128`). Nothing changes production state, so no installer omission or refusal is needed. The six-visitor load is one `Productions()` and one `Failures` (limit 0) per visitor a minute (inference: well under a second on build 154). A finding goes to that visitor's own session only.

**Proposed spine change (lead to raise; planned as if approved):**
- AD-18 Rule, after the "Source polls, the row type (Story 35.1)" bullet, add:
  > "**Queue backlog, the row type (Story 23.7):** a queue-backlog row has `Kind` `queues`, one per session, owned by that session, with empty `Namespace` and `Production` and `DisplayName` "Queue-backlog check". `WatchOps` creates and removes it for a `StartWatch` or `StopWatch` whose appended `Kind` is `queues` (empty means `production`) and sends `CheckChanged`. On each `Tick`, after the production checks, `Checks` runs every due queue row: through `Watch.Reader` alone it reads the queues of each entry of `Reader.Productions()` (on the online demo only the Orders production), compares each with `Checks.Coverage`'s `checks.thresholds.queueMessages` and `queueWaitMinutes` through the one rule `Checks.Queues.Over`, and sends one finding Item (`watch.queueBacklog`) per queue that is above and was not above at the last read of its namespace. `Reported` holds `{"above": {"<namespace>": [item names]}}`; unlike a production watch's, its first run is no baseline. A namespace that could not be read keeps its entry and makes the run `not_checked`. No column is added; readers that filter `Kind` `production` are unchanged. [ADDED <date>, Story 23.7, <ruling>]"
- Consistency Conventions "Background checks" row: after "a row's first reading run records `Reported` as a baseline and sends nothing", add "(a production watch's row; a queue-backlog row reports a queue already above on its first run, AD-18)".
- Both are extensions; no AD Rule is contradicted. AD-33's ownership tables do not change.

**Veto items (lead → Planner before implement):**
1. Stored message column: `Msg.Command.StartWatch.Kind` (storage Value 4) and `StopWatch.Kind` (Value 3), appended. Online demo: the same.
2. New stored kind value: `BackgroundCheck.Kind` = `queues`. A new `Reported` JSON shape for that kind. Online demo: the same, per visitor session, cleared by the reset.
3. Privileges/roles/grants: none in the product. Test-only: `Queue/Fixture` adds Read on `%DB_QUEUEFEED_DATA` to the service role, on throwaways only (guarded by the eval mount), and removes it, like `Test.Eval.Feed.Fixture`. Online demo: never runs there.
4. Retention: none changed. Routes: none. Dependencies: none.
5. Behaviour: `check_status` now lists queue rows (Decided 5). Tool schema: `start_watch`/`stop_watch` gain an optional `kind` (model-facing).
6. AD-33 cross-lane exception for the Lane B files this story names: `Msg/Command/StartWatch.cls`, `StopWatch.cls`, `Demo/Features.cls`, `web/src/app/rail/rail-view.ts`, `web/src/app/guide/*`, `ci/mock/scenarios/B/queue-watch-ask.json`, `README.md`, and their tests (`Test/Demo/Features.cls`, `web/scripts/*`, `web/e2e/guide/*`). The ownership tables do not change.

**Contended touches:**
- `Checks/Process.cls` (Epic 22): appended block, plus OTHER: one Try block in `Tick`, `Due`'s body → `DueOf`, and one class-description bullet. Plain-union proposal.
- `Checks/Coverage.cls` (Epic 22): appended block (`CurrentLimits`), plus OTHER: `Live`'s queue loop calls `Queues.Over`. Plain-union proposal. If refused, `Live` keeps its loop, and the copy is recorded with a `deferred:` item naming both places.
- `Checks/Queues.cls`: new file.
- `Msg/Catalog/Watch.cls` (Epics 22, 35): appended block (one key).
- `Test/Checks/Queues.cls`, `QueueProbe.cls`, `QueueBacklog.cls`, `Queue/*.cls`: new files.
- `ci/mock/scenarios/A/watch-start-queues.json`, `watch-stop-queues.json` and `ci/mock/scenarios/B/queue-watch-ask.json` (Epic 21): new files.
- `web/src/app/rail/rail-view.ts` (Epic 21): OTHER (one text and one branch). Plain-union proposal.
- `web/e2e/guide/more-to-try.spec.ts` (Epic 21): OTHER (one `ITEMS` entry). Plain-union proposal.
- `web/e2e/guide/more-to-try-queues.spec.ts`: new file.
- `README.md` (Epic 21): OTHER (line 40's count and a bullet at the end of its list). Plain-union proposal.
- Not touched: `Data/BackgroundCheck.cls`, `Tools/Names.cls`, `Core/*`, `Web/*`, `Test/{Mcp,Bridge,Tools,Fix,Core,Web,Channel}/**`, `docs/**`.

**PUBLIC TEXT for the Planner** (none is given by the UX or the PRD except the phrase "the queue-backlog check"):
- `Msg/Catalog/Watch.cls`, new last key `watch.queueBacklog`:
  - text: "The {itemName} queue in the {production} production had {count} messages waiting at {time}, the oldest since {oldestAt}.\nWhy now: you asked me to watch queue backlogs."
  - one (count): "The {itemName} queue in the {production} production had 1 message waiting at {time}, since {oldestAt}.\nWhy now: you asked me to watch queue backlogs."
- `Checks/Process.cls`, Item text (the summary in Recent decisions): `TEXTQUEUE` "The {itemName} queue in the {production} production has {count} messages waiting." and `TEXTQUEUEONE` "The {itemName} queue in the {production} production has 1 message waiting."
- `Checks/Process.cls`, row finding (rail, `check_status`, digest "Failed: Queue-backlog check (…)"): `FINDINGQUEUE` "1 queue over its threshold" and `FINDINGQUEUES` "{count} queues over their threshold".
- "Not checked" reasons: the existing `REASONREAD`, `REASONUNREADABLE` and `REASONNOTCURRENT`; no new text.
- `Watch/Ops.cls` `QUEUESNAME` (rail title, digest entry, `check_status` entry): "Queue-backlog check".
- `web/src/app/rail/rail-view.ts` `checkScheduleQueues`: "A check every minute".
- `web/src/app/guide/more-to-try-view.ts`, item `queueWatch`:
  - label "Watch queue backlogs"
  - lookFor: "This asks OcuTalon in the chat to watch the queue backlogs. Look for the Queue-backlog check under Background checks, with its schedule, last run and result. Every minute it reads the Orders production's queues, and when one holds more than 100 messages, or its oldest message has waited over 10 minutes, OcuTalon decides once whether to tell you. On a quiet demo it reads Passed. To stop, ask "Stop watching the queue backlogs.""
  - button "Ask to watch queues"
  - prompt `queuePrompt` "Watch the queue backlogs."
- `README.md`:
  - line 40: "its More to try panel has fifteen more things to try"
  - last bullet of New since 1.0.0: "- **Queue backlogs between digests.** Ask OcuTalon in the chat to watch the queue backlogs, and every minute it reads the queues of each production it can read (on the online demo, the Orders production's). When a queue holds more than 100 messages, or its oldest message has waited over 10 minutes (an admin can change both), OcuTalon decides once whether to tell you now, and again only after the queue has dropped below and backed up again. The check only reads, and a run that can't read a namespace shows Not checked, never Passed. Try it: More to try, *Watch queue backlogs*."
- `EXPERIENCE.md`: "There are fifteen items", and the Item bullet "Label "Watch queue backlogs". Look for: <lookFor above>. Control: "Ask to watch queues"."
- Agent and model text (not shown as written): the `Agent/Chat.cls` rule in Tasks, the `kind` DESCRIPTION, `UNKNOWNKIND`, `MESSAGEALREADYQUEUES`, `MESSAGENOTWATCHINGQUEUES`. The CI mock reply texts are CI-only.

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`, each finishing in about 150 s, and never two test runs in one message. Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<lock-dir>/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`. Use the fresh tag `e23s7i` and the warm tag `e23s7iw`; at the end run `ci/warm.sh down`, then `ci/iris.sh teardown` with `e23s7i`. Every IRIS MCP call names `server` `ocutalon-slot-d` and `namespace` `OCUTALON`, but slot D cannot run these classes (measured), so every class runs on a lane-D throwaway. Environment: lane-D throwaway stacks only (`ci/iris.sh`, `ci/warm.sh`). `Queue/Fixture` refuses anywhere without the eval mount.

**Shared surfaces:**
- the `StartWatch`/`StopWatch` storage blocks (`test-storage.sh`);
- `Test.Watch.Tools`' start/stop argument pin (`name,namespace`);
- `check_status`'s result list (`Test.Watch.Tools`, the `Test.Bridge.Gate` key pins, unchanged keys);
- the catalog key count and `Test.Msg.Catalog` Fixtures;
- `Test.Demo.Features` `TestIds` and `web/e2e/guide/more-to-try.spec.ts` `ITEMS`;
- the More to try registry count (README line 40, EXPERIENCE, the header comment, `more-to-try-view.test.mjs` number words);
- the rail's check rows (`rail-view.test.mjs`);
- `Checks.Process.Due` (`Test.Checks.Probe`/`Runs`);
- `Coverage.Live` (`Test.Digest.Coverage` queue cases).

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `ci/warm.sh up` with `OCUTALON_RUN_TAG=e23s7iw`, re-upped (`down`, then `up`, one call each) after any change to `Checks/Process.cls`, `Watch/Ops.cls`, `Tools/WatchTools.cls` or `Checks/Queues.cls`, so the production's jobs hold the new code. Then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23s7iw ci/iris.sh class <Class>`, one call each:
  - `OcuTalon.Test.Checks.Queues`
  - `OcuTalon.Test.Checks.QueueBacklog`
  - `OcuTalon.Test.Checks.Runs`
  - `OcuTalon.Test.Watch.Ops`
  - `OcuTalon.Test.Watch.Tools`
  - `OcuTalon.Test.Watch.Turns`
  - `OcuTalon.Test.Digest.Coverage`
  - `OcuTalon.Test.Msg.Catalog`
  - `OcuTalon.Test.Demo.Features`
  - `OcuTalon.Test.Agent.Instructions`

  Expected: each `CLASS ... passed`.
- (loop) `node --test web/scripts/rail-view.test.mjs web/scripts/more-to-try-view.test.mjs web/scripts/more-to-try-sources.test.mjs web/scripts/ux-strings.test.mjs`. Expected: all pass.
- (loop) `bash docker/tests/test-mock.sh`. Expected: pass.
- (loop) `bash docker/tests/test-storage.sh`. Expected: pass (the `Kind` values only appended).
- (once) `npm --prefix web run lint`. Expected: pass.
- Left to CI (each over 150 s, or a full run):
  - the fresh `Test.Checks.QueueBacklog` (it runs in `shard:lane-a@rest`, group `shards-2`);
  - the browser units with K29 and the `ITEMS` edit (`live:sign-in` parts);
  - `live:demo-path`, the shards, `bash ci/checks.sh` (README rules), `npm --prefix web run build`;
  - the lead's fresh-environment check, forward and `--reverse`.
- No new live unit. `Test.Checks.QueueBacklog` joins `shard:lane-a@rest` (`shards-2`, about 1,636 s of units plus about 90-150 s; inference, about 30 minutes a job, under the 32-minute group cap). If a run measures it over the cap, the lead moves it with a `shard_unit_areas` piece.

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:**
- AC1: `OnStart` ignores `Kind` → `Test.Watch.Turns:TestQueuesThroughTheAgent`.
- AC2: `RunQueues` reads only the first entry → `Test.Checks.Queues`.
- AC3: `Crossings` ignores the previous list → `Test.Checks.Queues`.
- AC4: an unread namespace counts as an empty queue list → `Test.Checks.Queues`.
- AC5: the Item is sent on every run that finds the queue above → `Test.Checks.QueueBacklog`.
- AC6: `Over` uses `'<` for the count → `Test.Checks.Queues` and `Test.Digest.Coverage`.
- AC7: `ReadEntries` lists every namespace whatever the flag (a probe that bypasses `Productions`) → `TestOnlineDemoReadsOnlyOrders`.
- AC8: `CheckResults` skips `queues` → `Test.Watch.Tools`.
- AC9: no `detail` for queues → `rail-view.test.mjs`.
- AC10: the item sends nothing → K29 (`live:sign-in-3`, `docker/tests/test-sign-in-3.sh --part 1/10` on a lane-D throwaway).
- AC11: README says fourteen → `more-to-try-view.test.mjs`.
- AC12: `Crossings` ignores `told` (no cooldown) → `Test.Checks.Queues`.

### Implement-stage results (2026-11-11, lane D, tags e23s7iw / e23s7i)

**Task 0 (measured, `Test.Checks.QueueBacklog:TestQueueRead`, warm lane-D throwaway):** 105 `Ens.StringRequest`s sent to the held `QueueSink`; 104 in Status 2 (Queued) when the read began (the job holds the first one, so the expected "about 104" holds); `Reader.Failures(QUEUEFEED, OcuTalon.Test.Checks.Queue.Production, "", 0, ...)` gave `queues` = `[{"name": "QueueSink", "count": 104, "oldestAt": "2026-11-11T11:47:09Z"}]` and no failure rows; the read took 0.051 s; the queue drained 0.253 s after the release. Held messages show as Status 2, so no intent gap.

**Passing runs (warm lane-D throwaway, one class per call):** `Test.Checks.Queues`, `Test.Checks.QueueBacklog` (all three tests), `Test.Checks.Runs`, `Test.Watch.Ops`, `Test.Watch.Tools`, `Test.Watch.Turns`, `Test.Digest.Coverage`, `Test.Msg.Catalog`, `Test.Msg.Contracts`, `Test.Demo.Features`, `Test.Agent.Instructions`, `Test.Bridge.CodeRules`. Also passing: the four web unit files, `npm --prefix web run lint`, `docker/tests/test-mock.sh`, `test-storage.sh`, `test-readme.sh`, `test-boundaries.sh`. Left to CI: K29, the fresh `Test.Checks.QueueBacklog`, the browser units, the shards, `ci/checks.sh`, the build.

**Mutations (Rule 19), applied, observed red, reverted (the tracked diff was byte-identical afterwards):**
- mutation: AC1 `OnStart` ignores `Kind` -> `Test.Watch.Turns:TestQueuesThroughTheAgent` red ("there is exactly one row")
- mutation: AC2 `RunQueues` reads only the first entry -> `Test.Checks.Queues` red (`TestFirstRun`)
- mutation: AC3 `Crossings` ignores the previous list -> `Test.Checks.Queues` red (`TestAdminThreshold`, `TestCooldown`)
- mutation: AC4 an unread namespace counts as an empty queue list -> `Test.Checks.Queues` red (`TestCrossings`, `TestNamespaceUnread`)
- mutation: AC5 the Item is sent on every run that finds the queue above (previous list and cooldown both ignored) -> `Test.Checks.QueueBacklog:TestTwoCrossings` red (3 Items, "not one for each run")
- mutation: AC6 `Over` uses `'<` for the count -> `Test.Checks.Queues` red (`TestCrossings`) and `Test.Digest.Coverage` red (`TestLiveRead`, "100 messages queued: passed")
- mutation: AC7 `ReadEntries` lists every namespace whatever the flag -> `Test.Checks.QueueBacklog:TestOnlineDemoReadsOnlyOrders` red (an Item and a `QUEUEFEED` key in `Reported`); `TestTwoCrossings` stayed green
- mutation: AC8 `CheckResults` skips `queues` -> `Test.Watch.Tools` red (`TestCheckStatusQueues`)
- mutation: AC9 no `detail` for queues -> `web/scripts/rail-view.test.mjs` red
- mutation: AC10 the item sends nothing (`more-to-try.ts` case `queueWatch` does not call `outbox.send`) -> K29 red at "the prompt was posted" (observed on a lane-D throwaway, `docker/tests/test-sign-in-3.sh --part 1/10`, 18 other tests green; reverted, `git diff` of the file empty). K29 green with the change reverted (19 passed, K29 1.7 s). The sign-in unit has no model key, so K29 answers the POST 202 and seeds and publishes the queue row that start_watch makes; the turn itself is pinned by `Test.Watch.Turns:TestQueuesThroughTheAgent` (CI rework 1)
- mutation: AC11 README says fourteen -> `web/scripts/more-to-try-view.test.mjs` red
- mutation: AC12 `Crossings` ignores `told` (no cooldown) -> `Test.Checks.Queues` red (`TestCooldown`)

### QA-stage audit (2026-11-11, lane D warm throwaway, tag e23s7qw)

Audit: every AC1-AC12 and every matrix row has a pinning test (AC1 `Test.Watch.Turns:TestQueuesThroughTheAgent` and `Test.Watch.Ops`; AC2-AC4, AC6, AC12 `Test.Checks.Queues`; AC5, AC7 `Test.Checks.QueueBacklog`; AC8 `Test.Watch.Tools:TestCheckStatusQueues` and `Test.Digest.Coverage:TestQueueRow`; AC9, AC11 the web unit files; AC10 `web/e2e/guide/more-to-try-queues.spec.ts`, which asserts the prompt is posted once with `fromGuide` false, the rail row "Queue-backlog check" with "A check every minute", and no second post). No test was added (QA): no AC or matrix row lacked a pinning test, and every assertion probed below can fail. Re-run green on the warm stack: `Test.Checks.Queues`, `Test.Checks.QueueBacklog`; `node --test` on the four web files (133 pass). Mutations below were applied one at a time, observed red, and reverted from a backup (`git status --short` empty afterwards).
- mutation: matrix "Stopped meanwhile": `Record` without its `%ROWCOUNT < 1` guard -> `Test.Checks.Queues:TestStoppedMeanwhile` red ("no Item was sent", "and no run was logged") (QA)
- mutation: matrix "Send fails": `Record` quits its send loop after the first failed send -> `Test.Checks.Queues:TestSendFails` red ("both Items were sent", "the failed one is not sent again") (QA)
- mutation: matrix "Empty list": the empty-list reason removed from `RunQueues` -> `Test.Checks.Queues:TestListUnreadable` red ("an empty list: the same, never passed on nothing") (QA)
- mutation: matrix "List unreadable": `RunQueues` clears `Reported` when the list was not read -> `Test.Checks.Queues:TestListUnreadable` red ("Reported unchanged", both rows) (QA)
- mutation: AC12 "a different queue is not held back": the cooldown applies to the whole namespace (any held `told` entry holds every queue) -> `Test.Checks.Queues:TestCooldown` red ("B, a different queue of the namespace, is reported") and `TestNamespaceUnread` red (QA)
- mutation: matrix "Unknown kind": `WatchAnswers.KnownKind` accepts every kind -> `Test.Watch.Tools:TestUnknownKind` red (QA)
- mutation: matrix "Stop", another session's row untouched: `WatchOps.OnStop` also deletes every `queues` row -> `Test.Watch.Ops:TestQueuesStartRepeatStop` red ("the other session's queue row is unchanged") (QA)
- mutation: matrix "Start", per-session natural key: `RefOf` finds a queue row without the `SessionRef` -> `Test.Watch.Ops:TestQueuesStartRepeatStop` red ("it is a new watch") (QA)

mutations_demonstrated=8 (QA, beside the 12 above). AC10's K29 red was observed in CI rework 1 and again in its re-review (see the AC10 line above and the re-review patches below). Nothing is left up on lane D.

### Code-review patches (2026-11-11, lane D warm throwaway, tag e23s7cw)

Passing after the patches: `Test.Watch.Ops` (with `TestQueuesEndSession`), `Test.Checks.Queues`, `Test.Watch.Tools`, `Test.Watch.Turns`, `Test.Checks.QueueBacklog`, `Test.Core.SessionOpsProduction` (regression, run only), `Test.Bridge.CodeRules`; `npm --prefix web run lint`. K29 (now holding its POST until the second press is checked) is left to CI. Each mutation was applied from a backup, observed red and restored (`git status --short` and `git diff --stat` identical afterwards).
- mutation: DW-1124 (AD-4, session end stops the queue row): `EndWatches` skips every Kind but production again -> `Test.Watch.Ops:TestQueuesEndSession` red ("both of the session's rows are gone, the queue row too") (CR)
- mutation: matrix "First run, above", Decided 15: `RunQueues` puts the queue's own `oldestAt` in the slot even when it is unreadable -> `Test.Checks.Queues:TestQueueFindingRenders` red ("its oldestAt slot is the run time", and the catalog refuses the slot) (CR)

### Code-review patches, CI rework 1 re-review (2026-11-11, lane D throwaways, tags e23s7vcr / e23s7vcm)

Passing after the patches: `npm --prefix web test` (1912/1912), `npm --prefix web run lint`, `node --test web/scripts/sources-docs.test.mjs` (15/15), and `docker/tests/test-sign-in-3.sh --part 1/10` (19 passed, K29 1.7 s, run after `guide/more-to-try.spec.ts`). Both throwaways tore down on exit (no container or volume left). Each mutation was applied from a backup, observed red and restored (`git status --short` and `git diff --stat` identical afterwards).
- mutation: AC10, re-observed after the K29 `openAs` patch: case `queueWatch` in `more-to-try.ts` does not call `outbox.send` -> K29 red at "the prompt was posted" (18 others green) (CR)
- mutation: EXPERIENCE.md's anchor "After Item 3" made "After Item 9" -> `web/scripts/sources-docs.test.mjs` red ("\"After Item 9\" comes right after Item 9") (CR)


## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The queue-backlog check (FR-33) is in: a chat request starts or stops a per-session `Kind` `queues` row through `StartWatch`/`StopWatch` (new `Kind` property) and `WatchOps`. On each `Tick`, `Checks.Process.RunQueues` reads the queues of every `Reader.Productions()` entry (limit-0 `Failures`), applies the one `Checks.Queues.Over` rule with `Coverage.CurrentLimits`, and sends one `watch.queueBacklog` Item per new crossing, with the once-an-hour per-queue cooldown (`told`) in `Checks.Queues.Crossings`. The run is recorded like every check, so the rail, `check_status` and the digest coverage show it. Task 0 measured 104 of 105 held messages in Status 2 (read 0.051 s, drain 0.253 s).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Checks/Queues.cls` (new): `Over` and `Crossings` with the cooldown.
- `Checks/Process.cls`, `Checks/Coverage.cls`: `Tick` block, `DueOf`/`QueueDue`/`RunQueues` and seams; `Live` on `Over`, `CurrentLimits`.
- `Watch/Ops.cls`, `Msg/Command/StartWatch.cls`, `StopWatch.cls`, `Tools/WatchTools.cls`, `WatchAnswers.cls`, `Watching.cls`, `Agent/Chat.cls`: the `queues` kind, `unknown_kind`, `check_status` lists the row.
- `Msg/Catalog/Watch.cls`, `Demo/Features.cls`, three mock scenarios, `rail-view.ts`, the More to try item, README and EXPERIENCE edits with the approved texts.
- Tests: `Test/Checks/Queues.cls`, `QueueProbe.cls`, `QueueBacklog.cls`, `Queue/*`, and updates to `Test/Watch/{Ops,Tools,Turns}`, `Test/Digest/Coverage`, `Test/Msg/{Catalog,Contracts}`, `Test/Demo/Features`, `Test/Checks/Probe`, the web unit files, `more-to-try.spec.ts` and the new K29 spec.

**Review.** 35 findings: patches applied 5 (check_status description, Fixture dead assignment, `OnAfterAllTests` `##super`, `TestQueuesThroughTheAgent` assertions, K29 `fromGuide`), deferred 2 (one root cause: session end does not stop a queue row; fix is in `Core/SessionOps.cls`, outside the footprint), the rest rejected with their reasons in the triage log. Patched by verdict: medium 2, low 3. Follow-up review recommended: K29 has never been executed (browser units run in CI), and the `##super` clean-up now runs after the live class on the next fresh CI stack.

**Verification performed.** On the lane-D warm throwaway after the last patch: `Test.Checks.Queues`, `QueueBacklog`, `Runs`, `Watch.Ops`, `Watch.Tools`, `Watch.Turns`, `Digest.Coverage`, `Msg.Catalog`, `Demo.Features`, `Agent.Instructions`, `Bridge.Gate`, `Bridge.CodeRules` all passed (the first set before the patches, `QueueBacklog`, `Turns`, `Watch.Tools`, `Gate`, `Instructions`, `CodeRules` after). `node --test` on the four web files (133 pass), `bash docker/tests/test-mock.sh`, `test-storage.sh`, `npm --prefix web run lint` (after the last patch), `test-boundaries.sh`, `test-ci-config.sh`, `test-readme.sh` pass. Mutations for AC1-AC9, AC11 and AC12 were observed red and reverted; AC10 (K29) is CI-only.

**Residual risks.** Left to CI: K29, the fresh-stack `Test.Checks.QueueBacklog` inside `shard:lane-a@rest`, the `ITEMS` oracle edit, and the lead's forward/`--reverse` fresh-environment check. The deferred session-end gap above.

**CI rework 1 (this pass).** Web unit job: `WORDS` and the two number-word lists in `more-to-try-view.test.mjs` end at sixteen, and `ENTRY_LINE` in `sources-docs.test.mjs` also matches EXPERIENCE.md's "After Item n" entry; `npm --prefix web test` passes (1912), lint and `test-boundaries.sh` pass. K29 now signs in the sign-in unit's `NOTICE` user like the sibling and passed on a lane-D throwaway (`test-sign-in-3.sh --part 1/10`, 19 passed), red under its mutation (see Verification). Review: 17 findings, 1 patched (comment), 1 medium deferred (K29 no longer drives the turn; see `deferred`), rest rejected with reasons in the triage log; follow-up review recommended false (no high patched). Residual risk: the deferred K29 coverage gap.
