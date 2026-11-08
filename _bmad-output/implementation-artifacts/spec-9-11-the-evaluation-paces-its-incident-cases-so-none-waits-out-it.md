---
title: 'Story 9.11: The evaluation paces its incident cases so none waits out its timer in a queue'
type: 'bugfix'
created: '2026-11-08'
status: 'in-progress'
baseline_revision: '225042eab4d6874c706ffa5dbfa44c6cbda3c8b5'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-9-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `EvalIn` (`OcuTalon.Eval.In`) sends every incident case of a run at once. `Decide` starts a diagnosis's timer when it sends the request to `DiagnosisAgent`, which has one job, so the later incident cases spend their 60-second timer queued behind the earlier ones. On the 1.0.3 rc1 set the 10th and 11th incident cases (`returns-negative-weight`, `shipments-epoch-time`) timed out at about 60.1 s, so the cause score measured the queue, not the diagnosis (DW-878).

**Approach:** `EvalIn` paces its incident cases where it sends one (`SendIncident`). Each incident case after the first in a run is sent only once the previous one's `CaseResult` row is no longer in state sent. The wait is bounded by a new `INCIDENTWAIT` of 150 s, above `Decide`'s `MAXTIMER` of 110 s. At the bound, the run sends no more incident cases. Turn cases still go first (`SendOrder` is unchanged). A skipped incident case counts as not right in SM-2's incident score and stays in its denominator (`Eval.Report` tallies it), so a stall can only lower that score, never raise it (the Contest Planner's condition, 2026-11-08). Nothing else changes.

## Boundaries & Constraints

**Always:**
- **The pacing rule.** It applies per run, which is one `EvalIn` instance (`Start` creates a fresh one).
  - The instance keeps the IncidentRef and the case name of the last incident case it dispatched successfully (`PaceRef`, `PaceCase`).
  - The check comes after the snapshot checks and before `CaseResult.Open`, so a refused case never waits. It looks at the previous case's row: `StillSent(PaceRef)` is 1 while `CaseResult.Pending(PaceRef)` is an object.
  - While that row is still sent, it pauses `INCIDENTPOLL` (1) seconds through the existing `Pause` seam and checks again, at most `INCIDENTWAIT \ INCIDENTPOLL` (150) pauses.
  - Once the row is not sent (EvalSink completed it, or it was removed), the case is opened and dispatched as today, and it becomes the previous case.
  - The first incident case of a run is sent with no check. A refused case, or one whose dispatch failed, never becomes the previous case.
- **At the bound.** If the previous row is still sent after the last pause, `EvalIn` sets `PaceStalled` and does not send the case. It returns `REASONPACED`, with `{case}` set to `PaceCase` and `{seconds}` to `INCIDENTWAIT`. The case is then skipped like any refused case: no row, nothing dispatched, the existing `LOGSKIPPED` warning, and the reason in Start's `skipped`.
  - Every later incident case of the run gets the same reason at once, with no check and no pause, even if the stalled row completes later.
  - Non-incident cases are still sent.
  - The stalled row is left as it is, and a late `CaseResult` completes it as usual.
- **Why no two incident cases overlap.** Before the bound, an incident case is dispatched only when no earlier incident row of the run is still sent. After the bound, no incident case is dispatched at all. So at most one incident case of a run is in state sent at any time, and a late `CaseResult` never releases a second one.
- **Why a run cannot hang.** A wait is at most `INCIDENTWAIT \ INCIDENTPOLL` pauses, there is at most one wait per incident case, and there are none after a stall. The pacing therefore adds at most (incident cases - 1) x `INCIDENTWAIT` seconds, plus the time of the checks, to `Start`.
- **The bound.** `INCIDENTWAIT` = 150, which is above the longest a diagnose decision can take under `Decide`'s timers:
  - the first attempt's `TimerFor` is at most `MAXTIMER`;
  - the second-model retry's `RetrySeconds` keeps the whole decision at or under `MAXTIMER` = 110;
  - re-send back-offs stay inside the attempt's timer.

  The other 40 s cover the hops EvalIn -> IncidentManager -> Decide and IncidentManager -> EvalSink. A test pins `INCIDENTWAIT` > `Decide.MAXTIMER`.
- **What the pacing reads.** Only the previous case's `CaseResult` row: never a pool size, a setting or a queue. So it holds with `DiagnosisAgent` at PoolSize 1 or 2 (Story 5.14).
- **Unchanged.** `SendOrder`, `Start`, `Wait`, `Finish`, `Send`, the item, turn and digest paths, and the signature and value of every existing member of `Eval.In`. The new members are only the parameters, properties and private methods named under Tasks.
- **The tests** extend the existing double `OcuTalon.Test.Eval.ZzIn`, which overrides the private seams, and start no production.

**Never:**
- No change to an existing timer, timeout or wait: `TURNWAIT`, `BUSYWAIT`, `BUSYMAX`, `Wait`, `OCUTALON_EVAL_WAIT` and every timer of `Decide` stay as they are. No change to any case under `eval/`, to any score, or to `EvalIn`'s disabled state in the product.
- No edit to:
  - the frozen files: `eval/run.sh`, `release/*.sh`, the IPM artifact and the check scripts;
  - `Eval/Gate.cls`, `Eval/Sweep.cls`, `Eval/Sink.cls` and `Eval/Data/CaseResult.cls`;
  - `Eval/Report.cls` outside its header line about skipped cases (:61), `Build`'s last calls (:197-198) and `AddSkipped` (:952-966) (the Planner's condition; these hunks do not overlap Story 19.4's, ruled a plain union);
  - `Production.cls`, `Decide.cls`, `Watch/IncidentManager.cls` and `ci/units.sh`;
  - `Test/Eval/Cases.cls`.
- No real model key. No new persistent class, table, production item, event or message class. No new `LOG*` text.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First incident case of a run | No incident case dispatched yet in this run | Dispatched at once, with no check and no pause | As today: a failed send deletes the row |
| Paced order | A command case, an item case and three incident cases, processed in `SendOrder`'s order on one service. Each previous incident row is answered on its 3rd check | The command is asked first. The incident cases are dispatched one at a time, each with no earlier incident row still sent. The item is sent with no wait. Each wait takes 2 pauses of `INCIDENTPOLL` | No error expected |
| Late `CaseResult` before the bound | The previous row is completed on its k-th check (k at most 151) | The next case is dispatched right after that check, never before | No error expected |
| Bound reached | The previous row is never completed | After 150 pauses, the case is skipped with `REASONPACED` (the previous case's name, 150): no row, nothing dispatched, one `LOGSKIPPED` warning | The run goes on with its other cases |
| After a stall | Later incident cases of the run, whether the stalled row completes late or not | Each is skipped at once with the same reason: no check, no pause, nothing dispatched. A digest or item case is still sent | No error expected |
| Previous case refused, or its send failed | A bad snapshot, or a dispatch error | It does not become the previous case, so the next incident case does not wait for it | As today |
| Previous row removed | `CaseResult.Remove` of that row | Counts as answered, so the next case is sent | No error expected |
| `DiagnosisAgent` with two jobs (Story 5.14) | PoolSize 2 | The same behaviour, because the rule reads rows only | No error expected |
| The three callers | `Report.Run` (eval/run.sh's set and release-candidate attempts), `Gate.Demo` (one incident case per run), `Sweep.Pass` (no incident case) | `Start` returns after the last incident case is sent, and `Wait` then bounds the rest as before. The demo and the sweep never wait | No error expected |
| Integration: Lane A's `evaluation` job (CI) | `eval/run.sh` unchanged, the CI mock, the 11 incident cases of `eval/` | `CHK\|problems\|0`, one `CHK\|case\|...\|incident` line for each incident case, and the demo 10 of 10 | A case paced out would be a `not sent` problem and fail the job |
| Skipped incident case in the report (the Planner's condition) | `Report.Build` given a skip of an incident case (`REASONPACED` or any other reason), held out or not | It counts in `scores.incidents` as not right: `total` includes it and `right` does not; when the case is held out, likewise in `heldOutIncidents`. It is still listed under `skipped` and is still a problem. A skip of any other kind counts in no score, as today | No error expected |
| The product | The judges' compose file, or an IPM install | `EvalIn` disabled (pool 0, Enabled 0), and `eval/` unchanged | No error expected |

</intent-contract>

## Code Map

Paths are relative to the repository root. Class paths are under `src/ocutalon/cls/OcuTalon/` unless they say otherwise. Line numbers are at `2fad2e97eb1e999335d612bc9e6f98a8ffd72407`.

**The class to change: `Eval/In.cls`**
- **Header.** The incident bullet is at :39-42; the pacing sentence goes there. The `SendOrder` bullet (:8-9) and the `Wait` line (:62) stay.
- **Parameters.**
  - `TURNWAIT` (:110, 150, "above the longest timer of Decide (110)") is the sibling of the new bound.
  - The new `INCIDENTWAIT` and `INCIDENTPOLL` go after `BUSYMAX` (:116) and before `CASEFILE` (:119).
  - `REASONWATCH` is at :153; the new `REASONPACED` goes after it and before `LOGSKIPPED` (:155-156).
- **Properties.** `Watches` is at :173; the new properties go after it.
- **The run.**
  - `Start` (:186-211) creates a fresh instance with `Ens.Director.CreateBusinessService` and `.service` undefined (`irislib/Ens/Director.cls` :1479-1481, `%New`). It calls `ProcessInput` once per case of `SendOrder`'s list (:193, :199-209).
  - `Wait` (:214-223) polls `CaseResult.Unanswered` every 0.25 s, by the clock.
- **One case.**
  - `OnProcessInput` (:297-315) logs `LOGSKIPPED` and the reason for any reason that is not empty (:312).
  - `Send` routes an incident case to `SendIncident` (:331).
- **`SendIncident` (:382-409).**
  - The snapshot checks are at :384-388, and the IncidentCase is built at :389-392.
  - `Pace` goes after :392 and before `Set opened = 0` (:393).
  - `CaseResult.Open` is at :395, and `DispatchIncident` at :399.
  - The send that failed is handled at :404-407. The new `PaceRef`/`PaceCase` assignment goes before `Quit ""` (:408).
- **The new methods.** `Pace` and `StillSent` go between `SendIncident` (:409) and `SendDigest`'s doc (:411).
- **Existing seams.** `DispatchIncident` (:481-484) sends asynchronously. `Pause` (:709-712) is `Hang seconds`, and the double records it.

**The double: `Test/Eval/ZzIn.cls`**
- The header's `DispatchIncident` bullet is at :5-7.
- `DispatchIncident` (:40-49) records a list `$ListBuild(IncidentRef, SourceItemId, format, failures, open, SuperSession)` at :44. Position 7 is appended there.
- `DispatchDigest` ends at :59 and `Ask` begins at :61. The new `Answer` and `StillSent` go between them.
- `Pause` (:109-112) is not edited (Epic 19 inserts just above it).

**The tests: `Test/Eval/In.cls`**
- **Header.** `TestSendsIncident` is described at :36-38, and `TestIncidentSendFails` at :41.
- **Setup.** `OnBeforeOneTest` (:91-99) and `OnAfterOneTest` (:101-110) kill `^OcuTalonTest("EvalIn")`, remove the run's rows and the `LOGSKIPPED` warnings.
- **The test that changes.** `TestSendsIncident` is at :766-789. It sends `zz-inc-a`, then `zz-inc-b` while a's row is still sent (:786); it is the old order pin.
- **Unchanged tests.**
  - `TestIncidentRefuses` (:792-826): its refusals come before `Pace`.
  - `TestIncidentSendFails` (:829-850): a failed send sets no `PaceRef`.
  - `TestSendOrder` (:745-763): `SendOrder` is unchanged.
  - `TestTurnBusy` (:546-592): its pause counts are turn-only.
- **The new tests** go after `TestIncidentSendFails` (:850) and before `TestSendsDigest`'s doc (:852).
- **Helpers to reuse:**
  - `Snapshot` :918, `WriteIncident` :926, `Incidents` :942, `IncidentAt` :949, `Digests` :955;
  - `Service` :998, `Process` :1008, `WriteCase` :1017, `Seen` :1034, `Asked` :1047, `Rows` :1082.
- **A minimal item case:** `{"kind": "item", "item": {"itemId": "..."}}` (:161). A command case: `{"kind": "command", "turn": {"text": "Please run df."}}` (:553).

**Read-only evidence**
- **`Test/Eval/Cases.cls` `TestRecordedCases` (:112-186).** It hands every `eval/` case, the 11 incident cases among them, to one ZzIn instance in name order. It asserts that each incident case is sent with its row open (:153-160) and counts them (:176-177).
  - It is tripped by pacing unless the double answers the previous row, which is why the double answers on EvalIn's first check by default.
  - Not edited: it is outside the footprint and contended by Epic 19.
- **`Eval/Data/CaseResult.cls`.** `Pending(itemId)` is at :115-121, `DECIDED` at :26, `Open` at :99-112, `Unanswered` at :134-140 and `RunCaseIndex` at :92.
- **`Eval/Sink.cls`** completes a row at :59 and :82-84: `Pending`, then State `DECIDED`, `DecidedAt` NowUtc, `%Save`. The double's `Answer` follows it.
- **`Watch/IncidentManager.cls`.**
  - Its eval branch is described at :98-104; `EvalCase` is at :1397-1408, `EvalAnswered` at :1427-1442 and `SendEval` at :1482-1485.
  - It has no timer of its own, so a row completes when `Decide` answers or when the case is refused.
- **`src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls`.**
  - `MAXTIMER` is :145 (110) and `MINTIMER` :148 (12). `TimerSeconds` (:220) defaults to 60.
  - The timer is set at send at :339-342. `TimerFor` is :515-522, and `RetrySeconds` :541-546; their contract is at :114-117.
- **`Eval/Report.cls`.**
  - `Run` (:316-331) calls Start, then `Wait(seconds)`.
  - A skip that is not `notRunYet` is a problem: "`<case>: not sent: <reason>`" (:215-218).
  - The Markdown lists skips under "## Cases skipped" (:274-283).
- **`Eval/Gate.cls`.** `Demo` runs `Report.Run(folder, DEMOCASE, seconds)` (:245), one incident case per run. The `clean` target fails on any problem (:19, :175, :670).
- **`Eval/Sweep.cls`.** `Pass` calls `Start` and `Wait` (:82-97). `SetNames` leaves out every incident case (:109-120), and `eval/persona-cases/` holds none.
- **`eval/run.sh` (frozen).**
  - `OCUTALON_EVAL_WAIT` is "the seconds each run may take, after it has sent its cases" (:20-23; default 180, and 900 for a release candidate; :260-275).
  - `eval_run` (:295-320) prints a first CHK line, then calls `Report.Run`.
- **`docker/tests/lib-live.sh`.** `iris_script` (:316-327) has no session timeout.
- **`.github/workflows/lane-a.yml`.** `evaluation` has `timeout-minutes: 30` (:55).
- **The disabled pins** (all unchanged):
  - `Production.cls` :55;
  - `Test/Eval/Switch.cls` `TestDefinition` :20;
  - `Test/Install/ProductionRules.cls` `TestDisabledItems` :79;
  - `docker/tests/test-production.sh` row 14 (:102-104).
- **`ci/units.sh`.** `shards-2` is `shard:lane-a@rest` (:103) and holds `Test.Eval.*`.
- **`docker/tests/test-class-rules.sh` `assert-concat`.** In the first argument of `$$$AssertTrue`/`$$$AssertEquals`, there is no `_` to the right of a top-level `[`. Compare with `$$$AssertEquals` against a computed expected text.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Eval/In.cls` -- [DW-878] Make these changes, each with a contract-only doc comment (Rule 14):
  - Parameters `INCIDENTWAIT = 150` and `INCIDENTPOLL = 1` after `BUSYMAX`.
  - `REASONPACED` (text under Design Notes, Strings) after `REASONWATCH`.
  - Properties `PaceRef` (`%String(MAXLEN = 22)`), `PaceCase` (`%String(MAXLEN = 128)`) and `PaceStalled` (`%Boolean`, initial 0) after `Watches`.
  - `Method StillSent(itemId As %String) As %Boolean [ Private ]`: `$IsObject(CaseResult.Pending(itemId))`.
  - `Method Pace() As %String [ Private ]`, as the Always tier says:
    - with no `PaceRef`, "";
    - when not stalled, the first check, then up to `INCIDENTWAIT \ INCIDENTPOLL` rounds of `Pause(INCIDENTPOLL)` and a check, ending at the first check that answers 0, with `PaceStalled` set when the last check still answers 1;
    - when stalled, the filled `REASONPACED`.
  - In `SendIncident`, `Set reason = ..Pace()` and `If reason '= "" Quit reason` after the IncidentCase is built. Set `PaceRef`/`PaceCase` right before the final `Quit ""`.
  - One header sentence on the incident bullet and `SendIncident`'s doc.

  This sends the incident cases one at a time, with a bound.
- `src/ocutalon/cls/OcuTalon/Test/Eval/ZzIn.cls` -- Make these changes:
  - `DispatchIncident` appends list position 7: the number of IncidentCases recorded before this one whose rows `CaseResult.Pending` still finds, counted before this record is added.
  - A public `ClassMethod Answer(itemId As %String) As %Status` completes the sent row of the ItemId as `Eval.Sink` does (State `DECIDED`, `DecidedAt` NowUtc, `%Save`). No row is OK.
  - Override `StillSent`:
    - count each check under `^OcuTalonTest("EvalIn", "checked")` (in all) and `("checked", itemId)` (per ItemId);
    - call `Answer` first when the per-ItemId count equals `$Get(^OcuTalonTest("EvalIn", "late"), 1)` (1 when the node is undefined; `"never"` never matches);
    - then `Quit ##super(itemId)`.
  - Header bullets: position 7, `StillSent` and `Answer`.

  These are the seams that make a result answered at once, late or never.
- `src/ocutalon/cls/OcuTalon/Test/Eval/In.cls` -- Change `TestSendsIncident`, add two tests and their header bullets:
  - **`TestSendsIncident`** keeps its assertions and adds, after `zz-inc-b` is sent:
    - `$List(..IncidentAt(2), 7)` = 0: the first row was no longer sent at the second dispatch;
    - `checked` = 1 and `paused` = 0;
    - `zz-inc-a`'s row is `decided`, answered by the double at EvalIn's check.
  - **`TestPacesIncidents`** (the order and a late result):
    - Cases: incident cases `zz-pace-a`, `zz-pace-c` and `zz-pace-e` (`WriteIncident`), the command `zz-pace-b` and the item `zz-pace-d`. Set `late` = 3.
    - It processes `SendOrder(..Folder, $ListBuild(a, b, c, d, e))` in order on one service. After each case it notes which count grew (`Asked`, `Seen`, `Incidents`) and builds the observed order.
    - It asserts the order `turn:zz-pace-b|incident:zz-pace-a|incident:zz-pace-c|item:zz-pace-d|incident:zz-pace-e`.
    - It asserts position 7 = 0 for all three incident records, 4 pauses each of `INCIDENTPOLL`, and 6 checks.
    - The rows of a and c are `decided`, and e's row is `sent`.
  - **`TestPaceBound`** (the bound, the stall and a late result after the bound):
    - Cases: incident cases `zz-bound-a` to `zz-bound-d` and the digest `zz-bound-dg` (`{"kind": "digest", "checks": []}`). Set `late` = `"never"`.
    - `a` is sent.
    - `b`:
      - its reason equals `REASONPACED` filled with `zz-bound-a` and `INCIDENTWAIT`;
      - it is not dispatched and has no row;
      - the pauses number `INCIDENTWAIT \ INCIDENTPOLL` and their seconds add up to at least `INCIDENTWAIT`;
      - `INCIDENTWAIT` > `$Parameter("OcuTalon.Bridge.Process.Decide", "MAXTIMER")`.
    - `c` gets the same reason, and the pause and check counts are unchanged.
    - `zz-bound-dg` is sent.
    - `ZzIn.Answer` of a's IncidentRef completes a's row late.
    - `d` gets the same reason, and nothing is dispatched.
    - Finally there are 1 incident record, 1 digest record and 2 rows, and 3 `LOGSKIPPED` warnings of the test.
  - Header bullets for the two new tests and the changed bullet of `TestSendsIncident`.

  These are the pins of AC1 to AC4.
- `src/ocutalon/cls/OcuTalon/Eval/Report.cls` -- [Planner condition 2026-11-08] Count a skipped incident case as not right in SM-2:
  - In `Build`, call `AddSkipped` before `Finish` and pass the tally: `Do ..AddSkipped(report, skipped, folder, .tally)` then `Do ..Finish(report, .tally)` (today Finish runs first, :197-198).
  - `AddSkipped(report, skipped, folder, ByRef tally)`: for an entry whose kind is `INCIDENTKIND` and that is not `notRunYet`, `Do ..Tally(.tally, "incidents", 0, heldOut, "heldOutIncidents")`, with `heldOut` read from the case as `Score` reads it (:406); `heldOut` is 0 when the case.json cannot be read. Nothing else in the entry changes.
  - The header line (:61) and `AddSkipped`'s doc say that a skipped incident case counts as not right in the incidents (and held-out incidents) and that any other skip counts in no score.
  - Touch nothing else in the class: above all not `Finish` (:917-922), `Text`, `Score` or the header lines 44-49, which Story 19.4 edits.
- `src/ocutalon/cls/OcuTalon/Test/Eval/In.cls` -- also add `TestSkippedIncidentScored` (the Planner's condition), with its header bullet: on one ZzIn double with `late` = `"never"`, process incident cases `zz-sc-a`, `zz-sc-b` and `zz-sc-c` (`zz-sc-c` with `heldOut: true` in its case.json); collect the skipped `{case, reason}` of `b` and `c` (both `REASONPACED`); `Answer` a's row; then build the report twice from the same rows: the control `Report.Build(<the run's RunRef>, ..Folder, [])` and `Report.Build(<the run's RunRef>, ..Folder, skipped)`. Assert, against the control, that `scores.incidents.total` is larger by exactly 2 and `right` is unchanged, that `scores.heldOutIncidents.total` is larger by exactly 1 and `right` unchanged (so the share can only fall), and that `b` and `c` are listed under `skipped` and counted by `Report.Problems`. Give the incident case.json files a recorded expectation (cause category and element at fault) if `WriteIncident` does not, so that a's row is scored, not unscored; record in the spec which it was. The assertion messages say a stall can only lower the score.
- `TestPaceBound` also pins the ruled text with a fixed string: `##class(OcuTalon.Eval.In).#REASONPACED` equals `the incident case {case} had no result after {seconds} seconds, so this run sends no more incident cases` exactly.
- [ ] [Gate] `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` -- RULED 2026-11-08 (orchestrator, decide): update the three pins that assert the old "a skip counts in no score" behaviour, which the Planner's condition (AC7) ruled out, and nothing else in the file (Story 19.4 edits its lines 1516-1522 and 1742-1747; these hunks are a plain union with them):
  - the header bullet at :48-49 gains the exception: a skipped incident case counts as not right in SM-2's incidents (any other skip is still scored in nothing);
  - `TestSkipped` (:1108): the incidents expectation becomes `"0 of 1 share 0 met 0"`, with a message saying the skipped incident case counts as not right;
  - `TestText` (:1268): the `Incidents (SM-2)` row takes the exact text the run gives for 0 right of 1 (run the class, read the row, pin it verbatim).
- No edit: `Test/Eval/Cases.cls`, `Test/Eval/Switch.cls` -- run them unchanged (AC5, AC6) -- `TestRecordedCases` relies on the double's default answer, and `Switch` pins the disabled `EvalIn`.

**Acceptance Criteria:**
- **AC1, order and pacing (DW-878).** Given a folder with a command case, an item case and three incident cases, and the double answering each previous incident row on its 3rd check with no production running, when `TestPacesIncidents` processes `SendOrder`'s list on one `EvalIn` double, then:
  - the command case is asked before any other case is sent;
  - every incident case after the first is dispatched only after the previous incident row has left state sent (position 7 is 0 for every incident record);
  - the item case is sent with no wait;
  - each wait is 2 pauses of `INCIDENTPOLL` seconds.
- **AC2, no overlap after a late result.** Given an incident row that is completed late (on its 3rd check, or by `ZzIn.Answer` after the bound), when `EvalIn` handles the next incident case, then that case is never dispatched while the earlier row is still sent. After the bound, the late completion releases no incident case of the run (`TestPacesIncidents`, `TestPaceBound`).
- **AC3, the bound.** Given an incident row that is never completed, when the next incident case is handled, then:
  - `EvalIn` pauses `INCIDENTWAIT \ INCIDENTPOLL` times (at least `INCIDENTWAIT` seconds, and `INCIDENTWAIT` > `Decide.MAXTIMER`);
  - it skips the case with `REASONPACED` naming the stalled case and 150, with no row, no dispatch and a `LOGSKIPPED` warning;
  - every later incident case of the run is skipped with that reason with no further pause, while a digest case is still sent (`TestPaceBound`).
- **AC4, the old order pin is updated, not removed.** Given two incident cases on one service, when `TestSendsIncident` sends the second, then it still asserts both sends and their rows, and also that the second was dispatched only after the first row was answered (position 7 = 0, one check, a's row `decided`).
- **AC5, the callers and the whole set.** Given the 11 incident cases of `eval/` and `eval/run.sh` unchanged:
  - when `Test.Eval.Cases.TestRecordedCases` hands every case to one `EvalIn` double, then every incident case is sent with its row open;
  - when Lane A's `evaluation` job runs in CI, then it reports `CHK|problems|0`, a `CHK|case` line for each incident case and 10 of 10 demo runs.
- **AC7, a stall can only lower SM-2 (the Planner's condition).** Given incident cases skipped by the pacing (one of them held out), when `Report.Build` builds the run's report, then each skipped incident case counts as not right in `scores.incidents` (and in `heldOutIncidents` when held out) and stays in the denominator; it is still listed under `skipped` and counted by `Problems`; a skip of any other kind still counts in no score (`TestSkippedIncidentScored`). The ruled `REASONPACED` text is pinned verbatim (`TestPaceBound`).
- **AC6, the product.** Given the product's production definition, when `Test.Eval.Switch.TestDefinition` lists its items, then `EvalIn` is an `OcuTalon.Eval.In` with pool 0 and Enabled 0. And `git diff --stat` of `eval/` and `Production.cls` against the story's baseline is empty.

## Spec Change Log

- 2026-11-08 04:3xZ, implement pass 1 halted (intent gap): AC7 trips `Test/Eval/Report.cls` `TestSkipped` (:1108) and `TestText` (:1268), whose pins assert the old behaviour. RULED (orchestrator, decide, logged): the three edits (header :48-49, `TestSkipped`, `TestText`) are allowed, a plain union with 19.4's hunks (1516-1522, 1742-1747), the condition's own consequence and not a waiver. Added as the one open [Gate] item. Re-dispatch: status `in-progress`; the pass-1 implementation of the other four classes is kept UNCOMMITTED in the working tree as the starting tree (only bookkeeping was committed).

- 2026-11-08, spec gate (lead), applying the orchestrator's resume message: (b) PUBLIC TEXT `REASONPACED` APPROVED as drafted by the Contest Planner under the owner's delegation, and the design approved (previous-row pacing, the 150 s stall bound, turn cases first, no timer changes); CONDITION (Planner): a skipped incident case counts as NOT RIGHT in SM-2 and stays in its denominator, pinned by a test with a mutation. Today `Report` counts a skipped case in no score (header :61; `AddSkipped` runs after `Finish`), so this spec now edits `Eval/Report.cls` (:61, :197-198, :952-966; no overlap with 19.4's hunks) and adds `TestSkippedIncidentScored` and AC7. (a) RULED (orchestrator, decide): the `Eval/In.cls`, `Test/Eval/ZzIn.cls` and `Test/Eval/In.cls` edits are plain unions with Story 19.4's hunks, and so is the non-overlapping `Eval/Report.cls` hunk. The intent block's Approach, Never list and matrix carry the condition.

## Review Triage Log

## Design Notes

**Architecture decisions (Rule 6).**

| AD | What it binds here |
|---|---|
| AD-22 | The evaluation set goes through `EvalIn`, which the production keeps disabled (only `OCUTALON_EVAL=1` enables it). The incident path is EvalIn -> IncidentManager -> Decide -> EvalSink. The CI mock is used, never a real key. `eval/run.sh` is unchanged. |
| AD-30 | The evaluation incident: `IncidentManager` sends `EvalSink` one `ItemDecision` with the IncidentRef as `ItemId`, and that completes the row the pacing reads. |
| AD-5 | A process keeps its state in rows. The wait reads the `CaseResult` row as its truth and is bounded. It runs inside `EvalIn` (a business service called in the caller's process), not in a business process, so no process holds a timer longer than two minutes. `TURNWAIT`'s 150-s synchronous call is the precedent. |
| AD-8 | `Decide`'s timers fix the bound: the first attempt defaults to 60 s, and a whole decision with its retry stays at or under `MAXTIMER` (110). None of them changes (`Timeouts.Derive` is untouched). |
| AD-16 | No case's expectation and no fix path changes. The testing switch stays off. |
| AD-26 | Each case is its own trace session with the run's Ref as SuperSession. Unchanged. |
| AD-29, AD-33 | Lane A, Epic 9's footprint. No new item, table, event or message class. |

No AC contradicts an AD's Rule, and no NFR is unmeasurable. "About 70 seconds each on Claude Haiku 5.5" is the charter's description, not a target. DW-878's evidence (the 10th case at 56.7 to 58.3 s on 1.0.2, its queue included) suggests about 6 s of diagnosis a case (inference). The design depends on neither figure, because it waits on the row and the bound is above `MAXTIMER`.

**Decided in-stage:**
1. **The pacing lives in `SendIncident`, per run.** `SendOrder` and `Start` are unchanged, so turn cases still go first and item and digest cases are not paced. Item cases that follow an incident case in name order are sent a little later. They are still decided while the later incident cases run (inference). This is the smallest change and the one furthest from Epic 19's hunks.
2. **The bound is counted in pauses.** It is `INCIDENTWAIT \ INCIDENTPOLL` = 150 pauses of 1 s through `Pause`, not clock time, so the double drives it without waiting. Each pause is a real `Hang`, so the wait in a run is at least 150 s. The 1-s poll costs at most about 1 s per incident case on the mock, where a diagnosis took 0.7 to 0.9 s (measured).
3. **At the bound the run sends no more incident cases.** That case and every later one get `REASONPACED`, even if the stalled row completes later. This is simpler and stricter than re-checking. A stall means a diagnosis outlived every `Decide` timer, and the skips are problems: a mock run fails, and a release-candidate attempt fails `clean`, so there is no false pass.
4. **A removed row counts as answered** (`Pending` is empty). A refused case or a failed send never becomes the previous case.
5. **The double answers at once by default.** `ZzIn.StillSent` completes the previous row at EvalIn's first check unless `late` says otherwise. So `Test.Eval.Cases.TestRecordedCases` stays green with no edit to `Cases.cls`, which is outside the footprint and contended. Tests that need a late result or none set `late`.
6. **No new mock scenario and no live test.** Lane A's `evaluation` job runs the paced set through the real production on the CI mock. `Test.Eval.Run` keeps one incident case per run, so its pins are unchanged.
   - AC1 to AC4 observe `OnProcessInput` called in `SendOrder`'s order on one instance, which is exactly `Start`'s loop (:193, :199-209).
   - `Start` itself needs the enabled `EvalIn` item and a running production, so its real-surface evidence is AC5's CI job, which runs `eval/run.sh` unchanged.
   - Adding a second incident case to `Test.Eval.Run`'s run 1 would also prove it live, but that file is outside the footprint, so it is not planned.
7. **(Implement stage.) `WriteIncident` records no expectation**, so `TestSkippedIncidentScored` writes its three case.json files itself (cause category `configuration`, element at fault `Orders.Process.Route`, with `heldOut` as a JSON boolean) beside `WriteSnapshot`. The answered case `zz-sc-a` is therefore scored (not unscored) and not right. `WriteIncident` is unchanged.
8. **(Implement stage.) Two existing pins of `Test/Eval/Report.cls` contradict the Planner's condition.** `TestSkipped` (the incidents line `0 of 0 share null met null` after a skip of an incident case) and `TestText` (the `| Incidents (SM-2) | 0 | 0 | not measured |` line) fail on the warm stack now that a skipped incident case is tallied as not right. That file is outside the footprint, so it is not edited here; its owner must update both pins (one skipped incident case: 0 of 1) before merge. The Verification line "`Test.Eval.Report` passed (no existing report pin changes)" does not hold.

**The three callers, with `eval/run.sh` unchanged.**
- **`Report.Run`** (eval/run.sh's push run, its `--on-mock` rehearsals and the release-candidate attempts):
  - `Start` now returns after the last incident case is sent, and `Wait(OCUTALON_EVAL_WAIT)` then bounds what is left: the last incident case and any item case. That matches eval/run.sh's header, "the seconds each run may take, after it has sent its cases".
  - The incident cases ran one after another in `DiagnosisAgent` before as well, so the set takes about as long. Only the hops of each case no longer overlap the queue (inference: about 1 to 2 s a case).
  - `iris_script` has no session timeout, and `eval_run`'s early CHK line keeps it from starting a run twice.
- **`Gate.Demo`** runs `Report.Run` with only `DEMOCASE`: one incident case per run, so it never waits.
- **`Sweep.Pass`**: `SetNames` leaves out every incident case and the persona cases hold none, so it never waits.
- **The CI `evaluation` job.** It took 10 min 48 s of its 30 on feature run 42438835464, with sets of 7 to 11 s on the mock. The pacing adds about 1 s per incident case per set: about 10 to 40 s over the push set and the key-proof rehearsal's three sets (inference). If the mock ever hung every diagnosis, the job would end by its timeout instead of by its problems. It fails either way (inference).

**Story 5.14 (DiagnosisAgent PoolSize 2).**
- The pacing reads only the previous case's row, so a second job changes nothing. `EvalIn` still sends one incident case at a time, and the second job is simply idle for the evaluation.
- With two jobs, a first job that is still finishing a request whose `Decide` timer fired can no longer delay the next case. With one job, AD-8's derived limits end that call by about the timer (the session's loop is bounded at the timer minus 5 s). So the runner is normally free by the time the row completes (inference).
- No test of this story reads a pool size. 5.14's pins in `Test/Agent/Runners.cls` and `Test/Install/Production.cls` do not interact.

**Measured (product default 5).**
- Slot `ocutalon-slot-b`, namespace `OCUTALON`, build 154, read only:
  - `Decide` `MAXTIMER` 110 and `MINTIMER` 12; `Eval.In` `TURNWAIT` 150;
  - PoolSize 1 for `DiagnosisAgent`, `IncidentManager`, `Decide`, `TriageAgent`, `ChatAgent`, `EvalSink` and `Intake`;
  - `EvalIn` pool 0 and Enabled false.
- Feature `lane-a` run 42438835464, `evaluation` job:
  - the set took 10 s, 11 s, 8 s and 7 s; the demo's 10 runs took 10 to 14 s;
  - the diagnosis time on the mock was a mean of 0.7 s and a maximum of 0.9 s;
  - all 11 incident cases ran with `CHK|problems|0`.

**Siblings (Rule 2: extend, don't copy).**
- **`Pace` and `Eval.In.Wait`.** `Wait` is a public ClassMethod with three callers. It polls all of a run's rows by the clock with its own `Hang`. `Pace` polls one row through the instance's `Pause` seam, by count, so that the double can drive it. Folding a one-row mode into `Wait` would change its signature or its clock loop for those callers. The polling is about 5 lines.
- **`StillSent`** wraps `CaseResult.Pending` and adds no query of its own.
- **`Pause`** is reused for the poll, not copied.
- **`INCIDENTWAIT` and `TURNWAIT`.** Both are 150 and are derived the same way. `INCIDENTWAIT` is a separate parameter because it bounds a different chain of hops, and a change of `TURNWAIT` must not move the pacing silently. The lead allows a new bound.
- **`ZzIn.Answer`** copies the three completion lines of `Eval.Sink` (:82-84). Calling the real Sink needs an `ItemDecision` and `Decision` rows that the double does not have. It is one definition, used by `StillSent` and by `TestPaceBound`.

**Integration and linkage (Rules 1 to 3).**
- No new service, module or shared component. The change is in `EvalIn`'s existing send of an incident case. The Integration row of the matrix is Lane A's `evaluation` job: `Report.Run`, run by `eval/run.sh`, consumes EvalIn's sends and produces `CHK|problems|0` with every incident case decided.
- **Consumes:**
  - `CaseResult.Pending` (Story 9.1);
  - IncidentManager's evaluation branch and `EvalSink`'s completion (Story 9.6);
  - `Decide.MAXTIMER` (AD-8, read by a test).
- **Consumed-by:**
  - `Eval.Report.Run`, and through it `eval/run.sh`'s runs and `Eval.Gate.Demo`;
  - `Eval.Sweep.Pass`, which sends no incident case;
  - later incident cases: Story 17.7's digest cases are not incident cases, but step 5's setting-change incidents are paced like any incident case.
- **Rule 3:** exempt. This is evaluation tooling that the product keeps disabled, with no user-facing surface.

**Ledger inbox.**
- DW-878 is addressed by the `Eval/In.cls` task (tagged [DW-878]) and pinned by AC1 to AC5.
- Declined: none.

**Strings** (for the lead to send to the Contest Planner before the implement stage).
- RULED 2026-11-08 (Contest Planner, under the owner's delegation): approved as drafted. New, in `src/ocutalon/cls/OcuTalon/Eval/In.cls`, parameter `REASONPACED`:
  `the incident case {case} had no result after {seconds} seconds, so this run sends no more incident cases`
  - `{case}` is the stalled case's folder name, and `{seconds}` is `INCIDENTWAIT` (150).
- Where the reason reaches, with no change to those classes:
  - the warning `EvalIn did not send the case <name>: <reason>` (the existing `LOGSKIPPED`);
  - `Report.Problems`' `<name>: not sent: <reason>`;
  - the report's "## Cases skipped" line `- <name> (incident): <reason>`, which a release-candidate result can carry.
- No other string literal is new or changed. There is no new `LOG*` parameter, and the parameters `INCIDENTWAIT` and `INCIDENTPOLL` are numbers.

**Contended lines (Epic 19).** Story 19.4's diff (`origin/feature/OCT_OcuTalon_MVP...origin/OCT-epic19`) was read. In every row below, the union is plain: both sides are kept.

| File | 9.11 changes or adds | 19.4 at the same lines? |
|---|---|---|
| `Eval/In.cls` | A header sentence at the end of the incident bullet (:39-42) | No. 19.4 inserts six header lines after :59 |
| `Eval/In.cls` | `INCIDENTWAIT` and `INCIDENTPOLL` after `BUSYMAX` (:116) | No. 19.4 changes `KINDS` (:79) and `TURNKINDS` (:85) and adds `DOCUMENTSKIND`/`DOCUMENTSWAIT` after :89 |
| `Eval/In.cls` | `REASONPACED` after `REASONWATCH` (:153) | No. 19.4 adds `REASONDOCUMENTS` after `REASONBEFORE` (:143) |
| `Eval/In.cls` | `PaceRef`, `PaceCase` and `PaceStalled` after `Watches` (:173) | No |
| `Eval/In.cls` | `SendIncident`'s doc (:379-381) and two insertions in its body (after :392, before :408) | No |
| `Eval/In.cls` | `Pace` and `StillSent` between :409 and :411 | No. 19.4 adds `Cite`, `DocumentsUp`, `AddOne` and `DocumentsDown` after `Render` (:686) |
| `Eval/In.cls` | Not touched: `Wait`/`Finish` (:222-236), `Send` (:332-335), `Converse` (:556) | 19.4 changes them, and its lines are kept |
| `Test/Eval/In.cls` | `TestSendsIncident`'s header bullet (:36-38), and two new bullets after :41 | No. 19.4 inserts two header lines after :21 |
| `Test/Eval/In.cls` | `TestSendsIncident`: assertions after :787 | No |
| `Test/Eval/In.cls` | `TestPacesIncidents` and `TestPaceBound` after :850 | No. 19.4 adds `TestSendsDocuments` and `TestDocumentsRefused` after :518 |
| `Test/Eval/ZzIn.cls` | `DispatchIncident`'s header bullet (:5-7), and a new bullet after :10 | No. 19.4 inserts three header lines after :20 |
| `Test/Eval/ZzIn.cls` | `DispatchIncident` body (:42-44) | No |
| `Test/Eval/ZzIn.cls` | `Answer` and `StillSent` between :59 and :61 | No. 19.4 adds `DocumentsUp` after `Deliver` (:107) |
| `Test/Eval/ZzIn.cls` | `Pause` (:109-112) is not touched | 19.4's insertion sits right above it |

| `Eval/Report.cls` | the header line about skipped cases (:61) | No. 19.4's header hunk is 44-49 |
| `Eval/Report.cls` | `Build`'s last two calls (:197-198) | No. 19.4's nearest hunks are 93-98 and 246-252 |
| `Eval/Report.cls` | `AddSkipped`'s doc, signature and body (:952-966) | No. 19.4's nearest hunk is 916-922 (`Finish`'s scores line), which 9.11 does not touch |

RULED 2026-11-08 (orchestrator, decide): the edits in `Eval/In.cls`, `Test/Eval/ZzIn.cls` and `Test/Eval/In.cls` are plain unions with 19.4's hunks, and a non-overlapping `Eval/Report.cls` hunk for the Planner's condition is a plain union too; whichever epic merges second takes the union. 19.4 also edits `Test/Eval/Cases.cls`, which 9.11 does not edit. The `documents` kind is a turn kind, so pacing never applies to it.

**Footprint.**
- Edited: `Eval/In.cls`, `Test/Eval/In.cls` and `Test/Eval/ZzIn.cls`, plus this spec.
- Footprint extensions (reported by the lead): `Eval/Report.cls` and `Test/Eval/Report.cls` (its three pins), for the Planner's condition only; both ruled plain unions with Story 19.4.
- No new mock scenario file. No frozen file is needed.

**Proposed spine text (for the lead, optional), an AD-22 as-built bullet:**
> **Incident pacing (Story 9.11).** `EvalIn` sends a run's incident cases one at a time. Each one after the first is sent only once the previous one's `CaseResult` row is no longer sent, after at most `INCIDENTWAIT` (150 s, above `MAXTIMER`) in 1-s pauses. At the bound, the run sends no further incident case (`REASONPACED`). It reads only that row, never a pool size.

**CI time.** No new test class and no `ci/units.sh` change. `Test.Eval.In` stays in `shards-2` (`shard:lane-a@rest`, about 1,500 s by `ci/units.sh`'s note, inference). The new tests add well under 1 s, because no pause hangs in the double.

## Verification

`<B>` stands for:
```
OCUTALON_LOCK_DIR=<lock-dir>/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=9 stage=<stage>'
```
`<lock-dir>` is the main checkout's `.worktrees/.coordination/locks` (the lead's value), and `<stage>` is the running stage (`implement`, `qa`, `review`).

**Run discipline.**
- Tags: fresh `e9s11i`, warm `e9s11iw` (implement). QA and review use their own tags.
- Run from the epic-9 worktree root. Each command runs in the foreground of its own call with `timeout: 600000`, and each finishes in about 150 s.
- One test class per call. Never two test runs in one message, and never a re-submit after a client-side timeout. At most one `iris_execute_tests` call per message.
- Pass `server: "ocutalon-slot-b"` and `namespace: "OCUTALON"` on every IRIS MCP call.
- No real `ANTHROPIC_API_KEY`, and never read `.env`.

**Runtime targets.**
- Slot B (`ocutalon-slot-b`, `OCUTALON`) is for the identity check and the compile only. It has no `eval/` mount, so `Test.Eval.In` and `Test.Eval.Cases` cannot run there.
- Every test runs on the lane's warm throwaway through `ci/iris.sh` with `<B>`.
- Tear down only `e9s11iw` and `e9s11i`.

**Shared surfaces:**
- ZzIn's IncidentCase record `^OcuTalonTest("EvalIn", "incident", n)` gains position 7; positions 1 to 6 are unchanged. It is read by `Test.Eval.In` and `Test.Eval.Cases`.
- ZzIn's new nodes `late` and `checked`, cleared by both classes' `Kill ^OcuTalonTest("EvalIn")`.
- ZzIn's default of answering the previous incident row at EvalIn's first check, which `Test.Eval.Cases.TestRecordedCases` relies on.
- The CaseResult rows that the double completes, removed by run in both classes' `OnAfterOneTest`.
- `EvalIn`'s skipped list, which can now hold `REASONPACED`. `Report.Build` lists it and `Report.Problems` counts it, and no test asserts it.
- The `LOGSKIPPED` warnings, removed by `OnAfterOneTest`.
- The timing of the incident cases in a run (the `RUN set` seconds of the `evaluation` job). Nothing asserts it.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `iris_server_info` on `ocutalon-slot-b`, then `iris_doc_load` with compile of `Eval/In.cls`, `Test/Eval/ZzIn.cls` and `Test/Eval/In.cls` on `ocutalon-slot-b`, namespace `OCUTALON`. -- expected: build 154, and each class compiles.
- (loop) `<B> OCUTALON_RUN_TAG=e9s11iw ci/warm.sh up` -- expected: the warm stack is ready, or `WARM up: project ... is already up`.
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s11iw ci/iris.sh class OcuTalon.Test.Eval.In` -- expected: a `WARM reloaded` line, then `CLASS OcuTalon.Test.Eval.In passed`.
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s11iw ci/iris.sh class OcuTalon.Test.Eval.Cases` -- expected: passed, with every incident case of `eval/` sent.
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s11iw ci/iris.sh class OcuTalon.Test.Eval.Switch` -- expected: passed.
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s11iw ci/iris.sh class OcuTalon.Test.Eval.Report` -- expected: passed, with `TestSkipped` and `TestText` updated to AC7 (the [Gate] item).
- (loop) `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e9s11iw ci/iris.sh class OcuTalon.Test.Eval.Gate` -- expected: passed.
- (loop) `bash docker/tests/test-class-rules.sh` -- expected: every rule PASS, `assert-concat` included.
- (loop) `git diff --stat -- eval/ src/bridge/ ci/ release/ docker/ .github/ src/ocutalon/cls/OcuTalon/Production.cls src/ocutalon/cls/OcuTalon/Eval/Gate.cls src/ocutalon/cls/OcuTalon/Eval/Sweep.cls src/ocutalon/cls/OcuTalon/Eval/Sink.cls src/ocutalon/cls/OcuTalon/Eval/Data/ src/ocutalon/cls/OcuTalon/Watch/ src/ocutalon/cls/OcuTalon/Test/Eval/Cases.cls` -- expected: empty output. `git status --short` lists only the five classes (`Eval/In.cls`, `Eval/Report.cls`, `Test/Eval/ZzIn.cls`, `Test/Eval/In.cls`, `Test/Eval/Report.cls`) and this spec; `git diff` of `Test/Eval/Report.cls` touches only :48-49, `TestSkipped` and `TestText`; `git diff` of `Eval/Report.cls` touches only :61, :197-198 and :952-966.
- (loop, at the stage's end, also after a failure) `<B> OCUTALON_RUN_TAG=e9s11iw ci/warm.sh down`, then `<B> OCUTALON_RUN_TAG=e9s11i ci/iris.sh teardown` -- expected: the projects are removed and no lock of this stage is left in the lane-b folder.

**Left to CI**, and so omitted here while CI is available:
- `shards-2` (`shard:lane-a@rest`, every `Test.Eval.*` class) and `shards` (`Test.Install.ProductionRules`);
- `production` (`docker/tests/test-production.sh` row 14);
- Lane A's `evaluation` job: `eval/run.sh` and `eval/key-proof.sh` on the mock, with every incident case sent and decided (AC5).

A local `eval/run.sh` does not fit in one 150-s call. The lead's Rule 19 fresh check (`Test.Eval.In` and `Test.Eval.Cases`, forward and reversed) is lead-owned.

**Planned mutations (Rule 19).** Apply each mutation on the warm stack, observe the red, then revert. Then see the class green again on the same stack, and confirm that `git status --short` and `git diff --stat` are as before. Then write the `mutation:` line.

| AC | Mutation | Expected red |
|---|---|---|
| AC1 (pinning) | Delete the `Pace()` call in `SendIncident` | `TestPacesIncidents` (position 7 is 1 and 2, no pause) |
| AC2 | At the bound, `Pace` returns "" (it sends anyway) | `TestPaceBound` (`b` dispatched with position 7 = 1) |
| AC3 | `Pace` never sets `PaceStalled` (it waits again for each later case) | `TestPaceBound` (the pauses double after `c`) |
| AC3 | `INCIDENTWAIT = 100` | `TestPaceBound` (not above `MAXTIMER`) |
| AC4 | Delete the `Pace()` call in `SendIncident` | `TestSendsIncident` (position 7 of `zz-inc-b` is 1) |
| AC5 | `Pace` returns `REASONPACED` whenever `PaceRef` is set | `Test.Eval.Cases` `TestRecordedCases` (the second incident case is skipped) |
| AC7 | `AddSkipped` no longer tallies the skipped incident case (skipped cases dropped from the denominator) | `TestSkippedIncidentScored` (`total` equals the control's, not control + 2) |
| AC7 | `REASONPACED` text changed by one word | `TestPaceBound` (the fixed-string pin) |
| AC6 | `Production.cls` sets EvalIn `Enabled="true"` | `Test.Eval.Switch` `TestDefinition` (green again after the revert) |

**Mutations run (implement stage, warm stack `e9s11iw`, reverted from backups in `<scratchpad>/e9s11impl/sub/`; after each revert the class was green again and `git status --short` / `git diff --stat` were as before):**
- mutation: AC1 -- deleted the `Pace()` call in `SendIncident` -> `Test.Eval.In` red: `TestPacesIncidents` (position 7 not 0, pauses and checks missing, last row state) -- reverted, green.
- mutation: AC4 -- the same deletion -> `TestSendsIncident` red (position 7 of `zz-inc-b` is 1, no check, `zz-inc-a`'s row still sent) -- reverted, green.
- mutation: AC2 -- `Pace` returns "" at the bound (`If 1 Quit ""` before the `REASONPACED` return) -> `TestPaceBound` red (`b` dispatched, row made, no reason; later cases sent too) -- reverted, green.
- mutation: AC3 -- `Pace` never sets `PaceStalled` (a local flag decides the return, so it waits again for each later case) -> `TestPaceBound` red (the pauses and checks grow after `c`; the late result releases `d`) -- reverted, green.
- mutation: AC3 -- `INCIDENTWAIT = 100` -> `TestPaceBound` red (not above `Decide.MAXTIMER`) -- reverted, green.
- mutation: AC5 -- `Pace` sets `PaceStalled` whenever `PaceRef` is set (REASONPACED for every incident case after the first) -> `Test.Eval.Cases` `TestRecordedCases` red (every incident case after the first is skipped) -- reverted, green.
- mutation: AC7 -- `AddSkipped` no longer tallies the skipped incident case -> `TestSkippedIncidentScored` red (`total` equals the control's, not control + 2; held-out likewise) -- reverted, green.
- mutation: AC7 -- one word of the `REASONPACED` text changed ("no more" to "no further") -> `TestPaceBound` red (the fixed-string pin) -- reverted, green.
- mutation: AC6 -- `Production.cls` sets EvalIn `Enabled="true"` (the warm stack took the reload) -> `Test.Eval.Switch` `TestDefinition` red ("EvalIn is disabled in the definition") -- reverted, `Switch` green, `Production.cls` unchanged in `git diff`.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: needs `src/ocutalon/cls/OcuTalon/Test/Eval/Report.cls` (outside the four named classes, and contended by Epic 19's Story 19.4)

- Implement stage (2026-11-08): the four named classes are implemented and left uncommitted in the epic-9 worktree (Eval/In.cls, Eval/Report.cls inside :61, :197-198 and :952-971, Test/Eval/ZzIn.cls, Test/Eval/In.cls), with the nine `mutation:` lines under Verification. Warm-stack runs on lane B: `Test.Eval.In`, `Cases`, `Switch` and `Gate` pass; `docker/tests/test-class-rules.sh` passes; the out-of-footprint `git diff --stat` is empty. The review layers were not run.
- The gap: AC7 (a skipped incident case counts as not right in SM-2) reverses two existing pins in `Test.Eval.Report`, which the spec's Verification expected to stay green. Both fail now:
  - `TestSkipped` (`Test/Eval/Report.cls` :1108): `Do $$$AssertEquals(..Line(report.scores.incidents), "0 of 0 share null met null", "the incident case is not scored")` must read the incident case as one not-right incident, `"0 of 1 share 0 met 0"` (value to confirm by running), with the message saying a skipped incident case is scored as not right.
  - `TestText` (:1268): `"| Incidents (SM-2) | 0 | 0 | not measured | 80% | not measured |"` must read `"| Incidents (SM-2) | 0 | 1 | 0.0% | 80% | not met |"` (by analogy with the items line at :1267), with the message adjusted.
  - The header bullet at :48-49 of the same class ("a skipped case is listed and scored in nothing") also needs the incident exception.
- Why it is a halt: the lead's instruction forbids editing `Test/Eval/Report.cls`, and Story 19.4 edits that file (45 lines on `origin/OCT-epic19`). Without the two pins updated, `shards-2` in CI is red.
- Resume: amend the spec's footprint to allow these three hunks of `Test/Eval/Report.cls` (a plain union with 19.4 if they do not overlap), then re-dispatch; the implementation in the tree needs only that edit, then the Verification loop (once the Report class is green), the review layers and the finalize commit. Verification line 395 ("no existing report pin changes") should read "TestSkipped and TestText updated for AC7".
- The warm stack `e9s11iw` was torn down; no fresh stack was started; `HEAD` is unchanged at the baseline.
