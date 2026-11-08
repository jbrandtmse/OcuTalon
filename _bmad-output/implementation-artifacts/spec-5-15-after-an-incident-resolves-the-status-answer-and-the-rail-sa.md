---
title: 'After an incident resolves, the status answer and the rail say so within seconds'
type: 'bugfix'
created: '2026-11-08'
status: 'done'
baseline_revision: '1bbee0d97ada7cfd97765ae107aa4e49e134934f'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** The status answer (`check_status`, Story 5.7) and the rail's Background checks read the production watch's last check, which runs only on the one-minute heartbeat. So for up to a minute after an approved fix finishes, both still say "50 new failures, a fix waiting for your approval" while the incident card already reads Resolved (DW-851).

**Approach:** This is the Contest Planner's ruling under the owner's delegation (2026-11-08T12:32Z), and it is fixed for this story. When `IncidentManager` accepts a move that resolves an incident, or that reopens it after its fix request was rejected or expired, or that closes a noticed open incident by `dismiss` or `closeQuiet` (the Planner's widening of 2026-11-08, DW-957: any move that changes what "An open incident" reads refreshes the check at once), it sends `Checks` one new asynchronous request, `OcuTalon.Checks.Msg.CheckNow`. `Checks` then runs each production watch of that production whose scope includes the incident (AD-4) once, straight away, through its existing run (`Run` and `Record`). That run leaves `NextDueAt` as the schedule set it.

## Boundaries & Constraints

**Always:**
- The trigger is an accepted move in `IncidentManager.Apply`. It fires for exactly these moves and no others:
  - event `finished` (final or interrupted) whose target is `resolved`;
  - event `rejected` or `expired` whose target is `open`;
  - event `dismiss` or `closeQuiet` whose source is `open` and whose target is `closed` (a noticed open incident; DW-957, the Planner's ruling of 2026-11-08).
- The selection uses AD-4's rule, the same one `Unclosed` applies. It takes the rows of `Kind` production (`..#KIND`) with the incident's `Namespace` and `Production` and then:
  - owner = a session: that session's row only;
  - owner `instance`: every session's row, but none on the online demo;
  - owner `eval` or empty: none.
- Each selected row goes through the existing run: the same read, scope, findings, result, the single SQL `UPDATE` keyed by Ref, the finding Items, the `check` event (`FromRow`) and the `LOGRAN` line.
  - The only difference is that the UPDATE does not set `NextDueAt`.
  - `LastRunAt`, `Result`, `Finding`, `LastRunHeaderId` (the run's session) and `Reported` are written exactly as a scheduled run writes them.
  - The update trigger still adds its `Digest.Data.CheckRun` row.
- `IncidentManager` sends the request asynchronously, with no answer wanted. It goes in the incident's trace session with the SuperSession kept, as `Execute` sends (AD-26), and only after the move's save.
- `Checks` answers OK with no response.
- Failure handling. No new text is user-facing; the two new log lines are listed under Design Notes.
  - A failed send logs one Type 3 warning in `IncidentManager` (`LOGCHECKNOW`), and the move stands.
  - A failed read of the rows logs one Type 3 warning in `Checks` (`LOGNOW`), and nothing changes.
  - A row's run that throws logs the Tick's `LOGRUN`.
  - When no row matches, nothing is logged and nothing changes.
- Tests use the CI mock only. Each test creates and removes its own rows, sessions and log lines. Fixture watches are due a day ahead (`Case.Watch`, DW-289), so a real Tick never runs them.

**Never:**
- No change to the check's rules (the read, scope, findings, result, and the FINDING* and REASON* texts).
- No change to the schedule (HeartbeatIn, `INTERVALSECONDS`, `DUESLACKSECONDS`, how a Tick sets `NextDueAt`) or to Checks' PoolSize 1.
- No new user-facing string.
- A `CheckNow` never runs the quiet sweep (`Sweep`), the fix sweep (`Fixes`/`FixRunSweep`) or the beats (`BeatRunDue`), and never forwards to `Digest`.
- The design does not treat a check result older than the resolution as stale; that option was not chosen.
- No edit to:
  - `Event`, `Drop`, `Purge` or `PurgeOne` of `IncidentManager` (Epic 30's hunk is at L1288-1320);
  - `Watch/Reader.cls`, `Tools/WatchAnswers.cls`, `Tools/WatchTools.cls`, `Test/Watch/Reader.cls` or `Test/Watch/Tools.cls`;
  - `Web/Api.cls`, `Production.cls`, `Test/Install/Production.cls`, `ci/units.sh`, `release/*` or `eval/run.sh`.
- No real model key.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Resolved | S's incident I on ZZNS/P is `fixing` with R1 approved; a final FixResult(R1) arrives | I `resolved`; one CheckNow {ZZNS, P, S, I} in I's TraceHeaderId session | No error expected |
| Interrupted | As Resolved, with Interrupted 1 and Final 0 | As Resolved | No error expected |
| Rejected | I is `awaiting_approval` with only R1 pending; ApprovalOutcome rejected | I `open`/rejected; one CheckNow | No error expected |
| Expired | As Rejected, with expired | I `open`/expired; one CheckNow | No error expected |
| Dismissed (DW-957) | I is `open` and noticed; an IncidentCommand `dismiss` | I `closed`; one CheckNow | No error expected |
| Quiet-closed (DW-957) | I is `open` and noticed, not on the online demo; an IncidentCommand `closeQuiet` | I `closed`; one CheckNow | No error expected |
| Not resolving | A `progress` FixResult; `finished` with another approved request waiting (stays fixing, execute earliest) or another pending (`awaiting_approval`); `rejected` with another pending (stays awaiting); `approved`; a refused event (a repeat, an unknown request); a failed save (`FailMove`); `dismiss`, `closeQuiet` or `closeForReplay` of a `resolved` incident (it was not counted as open); a refused `closeQuiet` on the online demo | No CheckNow | No error expected |
| Instance | An `instance` incident resolves | CheckNow with OwnerRef `instance` | No error expected |
| Send fails | The CheckNow send answers an error | One `LOGCHECKNOW` warning naming I; I stays resolved; its event and result notice went out; status OK | Logged, move kept |
| Check now runs | CheckNow {ZZNS, P1, A}; rows A/P1 (NextDueAt N, a day ahead), A/P2 and B/P1; `Swept` canned | Only A/P1 runs: its run fields are set, NextDueAt is still N, one `check` event (FromRow) on A's stream, one LOGRAN line. A/P2 and B/P1 are unchanged. Nothing quieted, no fix result sent, no beat, no Digest send | No error expected |
| Empty NextDueAt | A matching row with NextDueAt "" | Runs; NextDueAt stays "" | No error expected |
| Scope | OwnerRef B; `instance` on a local install; `instance` on the online demo; `eval`; another namespace | B/P1 only; A/P1 and B/P1; none; none; none | No error expected |
| Read fails / no row | The row selection throws; no row matches | One `LOGNOW` warning naming I, with nothing changed and nothing published; no row: no log line and nothing changed. OK either way | Logged once |
| Integration: resolved (DW-851) | Real production. S watches Orders (due a day ahead; the row says `failed`, "A fix running"). T watches Orders too, and S watches ZZNS/Zz.Production. S's noticed incident on OCUORDERS/Orders is `fixing` with R1 approved. A final FixResult(R1) goes to IncidentManager | Within 10 s, `check_status` for S gives Orders `passed`, "", with a checked time after the send. `/state`'s rail shows the same run. One check event FromRow is on S's stream. NextDueAt is unchanged. T's row and S's ZZNS row are unchanged | No error expected |
| Integration: rejected | As above with I `awaiting_approval`, R1 rejected (row state rejected), and the row `failed`, "A fix waiting for your approval"; an ApprovalOutcome rejected | Within 10 s, `check_status` gives `failed`, "An open incident" | No error expected |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless stated otherwise.

- `Checks/Process.cls` (751 lines, Lane A):
  - the class doc L1-70 (the request list L1-34; Record L61-66);
  - `LOGBEATPUBLISH` L167;
  - `OnRequest` L181-190;
  - `Tick` L193-247 (Sweep, Fixes, Due/Run with LOGRUN L214, BeatRunDue, the Digest forward L241) is the path a CheckNow must not take;
  - `BeatNow` L250-285;
  - `Due` L452-464 (the SELECT and the row object);
  - `Run` L467-524 (runAt is now; `tickAt` reaches only Record);
  - `Record` L528-545 (nextDueAt L530, the UPDATE L531, a row count of 0 quits L533, Announce L543, LOGRAN L544);
  - `Unclosed` L611-628 (the scope test L621);
  - `ScopedFailures` L648-657.
- `Watch/IncidentManager.cls` (1492 lines; contended with Epic 30 at L1288-1320):
  - the class doc, states bullet, L57-71;
  - the parameters L110-222;
  - `Apply` L1061-1071, called by `Command` L1158 and by `Event` L1275-1282 for `Outcome` L1182-1191 and `Result` L1225-1235;
  - `Execute` and `SendExecute` L1114-1131 are the sibling and the seam pattern.
- `Watch/Transitions.cls` `Next` (read-only): finished goes to resolved only with no waiting and no pending request; rejected or expired goes to open only with no pending request.
- `Checks/Msg/CheckChanged.cls` and `BeatNow.cls`: the sibling message classes (doc, `MAXLEN`s, generated storage).
- `Data/Incident.cls`: `OwnerRef` (MAXLEN 22), `Namespace` and `Production` (128) and `TraceHeaderId`.
- `Data/Session.cls` `Recipients` L192-204 and `Data/Ownership.cls` `Watchers` L532: for `instance`, the sessions with a production row on the namespace and production, and none on the online demo. These give the same set as the AD-4 selection.
- `Data/BackgroundCheck.cls`: the trigger `RecordRun` L56-59 (a CheckRun row whenever LastRunAt changes) and the index `NamespaceProductionIndex`.
- `Watch/Reader.cls` `OnlineDemo` L163 (read-only); `Tools/WatchTools.cls` `CheckStatus` L154 and `Tools/WatchAnswers.cls` `CheckResults` L202 (read-only, called by the tests).
- Tests:
  - `Test/Checks/Probe.cls`: the doc L1-35, `KIND` zzprobe L38, the `Due` override L232-240 (the "keep `Only`" pattern), the `FixRunSweep`/`SendFixResult` seams with `Swept`/`Sent`, `Beats` and `Quieted`/`SweptAt`.
  - `Test/Checks/Runs.cls`: the header L1-75, `OnAfterOneTest` L143 and these helpers: `Host` L1576, `Owner` L1585, `Watch` L1599, `Incident` L1615, `Feed` L1632, `Tick` L1686 (the pattern for sending a CheckNow), `Row` L1758, `Events` L1779, `Warnings` L1835, `Ran` L1850 and `RemoveLogs` L1880. `TestScope` L253-300 toggles the online demo with `Data.Public.Settings.Set("onlineDemo", ...)`.
  - `Test/Digest/TickProbe.cls`: it records the sends to Digest.
  - `Test/Watch/IncidentProbe.cls`: the doc L1-20 and the `SendExecute` override L89-95 (the pattern).
  - `Test/Watch/Lifecycle.cls`: the header L1-80; `TestApprovalOutcomes` L267, `TestFixResults` L375 and `TestExecuteSendFails` L778; the helpers `Host` L1046, `Incident` L1068, `Request` L1085, `Finish` L1242, `Outcome` L1305 and `Result` L1316; `RemoveLogs` L1420.
  - `Test/Eval/ZzIncident.cls` extends IncidentProbe and inherits the recording.
  - `Test/Watch/Case.cls`:
    - `Ready` L316, `Begin` L582 (a bridge context, so `WatchTools.CheckStatus()` reads S), `Watch` L637 and `Ahead` L645;
    - `SendExecute` L2114-2125 (a send from `SimMailboxIn`, its session kept in `ExecuteSessions` and removed by `DropExecuteSessions`), `WaitIncidentState` and `Fixture` L842.
  - `Test/Checks/Heartbeat.cls` `TestTickRunsTheWatch` L62-97: the pattern for asserting the check event, `/state` (`Web.Api.StateBody`) and the trace.
  - `Test/Data/Fixture.cls`: `Check` L70, `Incident` L87, `Approval` L108 and `Session` L22.
- Spine (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`): the AD-18 Rule L554-556, the Conventions row "Background checks" L1158, and the message table's CheckChanged row L1359 and BeatNow row L1372.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Checks/Msg/CheckNow.cls` (new). It extends `Ens.Request` and has these properties:
  - `Namespace` and `Production` (MAXLEN 128);
  - `OwnerRef` and `IncidentRef` (MAXLEN 22).

  Its doc names the sender (IncidentManager, asynchronously, no answer wanted), the handler (Checks) and Lane A, in the style of CheckChanged (DW-851).
- `src/ocutalon/cls/OcuTalon/Checks/Process.cls` (DW-851):
  - `OnRequest` routes `OcuTalon.Checks.Msg.CheckNow` to a new private `Now(request)`. `Now` calls `Watching`, then `Run(row, "", 1)` for each row, each in its own Try/Catch that logs `LOGRUN` as the Tick does. A `Watching` that throws logs one `LOGNOW` warning, `request.IncidentRef`, ": " and the redacted error. `Now` answers OK.
  - A new private `Watching(namespace, production, ownerRef)` selects the rows of `Kind = ..#KIND` with that namespace and production (in ID order) that `InScope(ownerRef, sessionRef, OnlineDemo())` keeps. Each row has the same shape as `Due`'s.
  - The row object is built once, by a new private `RowOf(rs)`, used by both `Due` and `Watching`.
  - A new public `InScope(owner, sessionRef, onlineDemo)` holds the rule of `Unclosed` L621: `owner = sessionRef`, or `owner = instance` and not the online demo. `Unclosed` calls it.
  - `Run` gets a trailing `keep As %Boolean = 0` and passes it to `Record`. `Record` computes the next due time only when keep is 0. With keep 1, its UPDATE omits `NextDueAt` and sets the other five fields.
  - A new parameter `LOGNOW` (text under Design Notes).
  - The class doc names the fourth request and its rules (Boundaries), and Record's keep.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` (DW-851). Nothing between `Event` and `PurgeOne` changes.
  - `Apply`: before `Next`, keep `from = incident.State`. After an accepted move and its Execute, call `..CheckNow(incident)` when `(event = FINISHED && to = RESOLVED) || ((event = REJECTED || event = EXPIRED) && to = OPEN) || ((event = DISMISS || event = CLOSEQUIET) && from = OPEN && to = CLOSED)` (the last clause: DW-957).
  - A new private `CheckNow(incident)` and its seam `SendCheckNow(request)` (`SendRequestAsync(..#CHECKS, request, 0)`), placed after `SendExecute`:
    - they build the request from the incident's Namespace, Production, OwnerRef and Ref;
    - they set `%SessionId` to `incident.TraceHeaderId` and put it back after the send, as `Execute` does;
    - a failed send logs `LOGCHECKNOW`, the Ref, ": " and the redacted error.
  - New parameters `CHECKS = "Checks"` and `LOGCHECKNOW`.
  - The class doc's states bullet names the CheckNow.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls`:
  - a `Watching` override that keeps only the `Only` Refs after `##super`, as `Due` does;
  - a `FailWatching` flag that throws instead;
  - the doc says so.
- `src/ocutalon/cls/OcuTalon/Test/Checks/Runs.cls` -- the matrix rows Check now runs, Empty NextDueAt, Scope and Read fails / no row:
  - `TestCheckNow` sends a CheckNow through `host.OnRequest`. It shows that a CheckNow sends nothing to Digest by running one case on a `Test.Digest.TickProbe` shadow and checking `^||TickProbe("digest")`;
  - `TestCheckNowScope`;
  - `TestCheckNowFailures`;
  - `RemoveLogs` also removes the `LOGNOW` lines;
  - the header lists the three tests.
- `src/ocutalon/cls/OcuTalon/Test/Watch/IncidentProbe.cls`:
  - a `SendCheckNow` override records `{namespace, production, ownerRef, incidentRef, sessionId}` in a new `CheckNows` and answers OK, or an error when `FailCheckNow` is set;
  - the doc says so.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls` -- the matrix rows Resolved, Interrupted, Rejected, Expired, Dismissed, Quiet-closed, Not resolving, Instance and Send fails (`TestResolvingMovesCheckNow` covers Dismissed and Quiet-closed, DW-957):
  - `TestResolvingMovesCheckNow`;
  - `TestCheckNowSendFails`;
  - `RemoveLogs` also removes the `LOGCHECKNOW` lines;
  - the header lists the two tests.
- `src/ocutalon/cls/OcuTalon/Test/Checks/AfterResolve.cls` (new) -- the two Integration rows. It extends `Test.Watch.Case` and runs on throwaway stacks and CI only.
  - `TestResolvedFixIsCheckedAtOnce` and `TestRejectedFixIsCheckedAtOnce`.
  - Set-up: fixture sessions and watches (`Watch`, then the run fields set on the row as the matrix says, with `LastRunAt` the set-up time so that the read window starts then), the incident (`Fixture.Incident`, with TraceHeaderId set) and R1 (`Fixture.Approval`). The test first asserts that no other unclosed incident of OCUORDERS/Orders is in S's scope (the instance ones included), and fails with that reason if one is.
  - A private `SendToManager(message)` sends from `SimMailboxIn` asynchronously and appends its session to `ExecuteSessions`.
  - It polls `WatchTools.CheckStatus()` under `Begin(S, ...)` every 0.25 s, up to 10 s.
  - Assertions:
    - the incident's state;
    - the answer's row for Orders;
    - `StateBody`'s `rail.checks` entry;
    - exactly one new `check` event on S's stream, equal to `FromRow`;
    - `LastRunHeaderId` = the incident's TraceHeaderId;
    - NextDueAt unchanged;
    - T's row and S's ZZNS row unchanged.
  - It logs the milliseconds from the send to the row's LastRunAt with `$$$LogMessage`.
  - Cleanup follows `Test.Fix.Execute`.
- Shared-surface sweep (Rule 19). Before the loop, run `rg -n 'Stream\(|"check"|LastRunAt|CheckNow|Sent\.%Size|Warnings\(' src/ocutalon/cls/OcuTalon/Test/Fix src/ocutalon/cls/OcuTalon/Test/Watch src/ocutalon/cls/OcuTalon/Test/Eval web/e2e/demo-path`.
  - Update any exact expectation that a resolved, rejected, expired, dismissed or quiet-closed incident of a session that watches Orders now breaks: one extra check event, one LOGRAN line and a CheckNow header in the incident's trace session.
  - Never weaken one.
  - List what changed under `## Verification`.
- This spec's `## Verification` -- the implement stage adds the measured milliseconds, each class's seconds and each `mutation:` line.

**Acceptance Criteria:**
- AC1 (DW-851; AD-15, AD-18, AD-33). Given an incident whose fix run finishes into `resolved`, or whose only pending request is rejected or expires, or a noticed open incident that is dismissed or quiet-closed (DW-957), when IncidentManager applies the event, then the matrix rows Resolved, Interrupted, Rejected, Expired, Dismissed, Quiet-closed, Instance and Not resolving hold.
- AC2 (AD-4, AD-18, AD-26, AD-28). Given a CheckNow, when Checks handles it, then the rows Check now runs, Empty NextDueAt and Scope hold. The run's row, event and log line equal those of a Tick's run of the same read, except that NextDueAt is unchanged.
- AC3. Given a failed send, a failed row read or no matching row, when the CheckNow is sent or handled, then the rows Send fails and Read fails / no row hold: at most one warning and no other change.
- AC4 (Integration AC: Checks consumes IncidentManager's CheckNow, and the status answer and the rail read the result). Given the real production, when a fix finishes or is rejected, then the two Integration rows hold.
- AC5. Given the change, when it merges, then:
  - Checks keeps PoolSize 1, and the FINDING*, REASON*, INTERVALSECONDS and DUESLACKSECONDS parameters and the Tick path are unchanged;
  - no user-facing string is added;
  - the diff is the Execution list;
  - CI is green on every workflow, on the mock only.

## Spec Change Log

- 2026-11-08, lead, spec gate (the Contest Planner's rulings under the owner's delegation, relayed by the orchestrator): (1) proceed at about 2.5 h as designed: one CheckNow, the existing Run and Record, NextDueAt unchanged, no sweeps, Checks PoolSize 1, no AD change; (2) expired requests stay in the trigger; (3) DW-957: the trigger is widened to `dismiss` and `closeQuiet` of a noticed open incident (open to closed), on the principle that any move that changes what "An open incident" reads refreshes the check at once. Intent contract (Approach, Boundaries), matrix, Execution, AC1, Design Notes, spine row, mutations and shared surfaces amended to match; (4) the `Watch/IncidentManager.cls` hunks are a plain union with Epic 30's 30.7 `Purge` hunk (decide; the Planner agrees). The two spine rows were written by the lead (Rule 20 light path).

## Review Triage Log

### 2026-11-08 — Review pass
- verdicts: 26 findings — high 0, medium 0, low 21, false 5, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: no test pins the `Checks` item name or the `CheckNow` message shape — `AfterResolve` sends through the real item, and the item names are pinned by the production tests; a message-shape test would add a new test class of surface for a name that cannot drift unseen.
  - `[false]` `[reject]` Blind: docs say "noticed" but `closesOpen` never checks `NoticedAt` — `Transitions.Next` allows dismiss and closeQuiet from `open` only when noticed (L98-104), so `from = open` and `to = closed` already means noticed.
  - `[false]` `[reject]` Blind: `TestCheckNowScope` leaks `onlineDemo` — `Runs.OnAfterOneTest` resets the setting.
  - `[low]` `[reject]` Blind: "exactly one check event" uses a fixed `Hang 1` — the second run would follow the first by well under a second (PoolSize 1, 250 ms measured); a longer or counted wait adds complexity for a case nobody will meet.
  - `[low]` `[reject]` Blind: the recorded latency is one poll step — the record already states the 0.25 s poll step and calls the figure a bound.
  - `[low]` `[reject]` Blind: a CheckNow is sent for eval or empty owners that `Watching` discards — spec-bound (matrix row Scope: the scope is decided in Checks, Design Notes); the cost is one message.
  - `[low]` `[patch]` Blind: mutation list leaves the REJECTED clause, the session restore and the session switch unmutated — the restore, the switch and the `LOGCHECKNOW` warning were mutated and their lines written; the REJECTED clause is the same expression as EXPIRED, covered by the same test.
  - `[low]` `[reject]` Blind: repeated CheckNows are not coalesced — by design (Design Notes: the second run reads the same state and is harmless).
  - `[low]` `[patch]` Blind: the `IncidentProbe` doc spliced a clause into a sentence — restored the original sentence and added the SendCheckNow sentence on its own.
  - `[low]` `[reject]` Edge: other state-changing moves (resolved re-raised, fixing to awaiting) are not triggers — the Contest Planner's ruling lists exactly three move families and the matrix row Not resolving pins the rest.
  - `[low]` `[reject]` Edge: the intent's "any move that changes what An open incident reads" wording is wider than the code — same ruling; the enumerated list governs ("exactly these moves and no others").
  - `[low]` `[reject]` Edge: `SendCheckNow` throwing would leave `%SessionId` swapped — `SendRequestAsync` answers a status; `Execute` and `SendExecute` are the precedent and carry no Try.
  - `[low]` `[reject]` Edge: an empty `TraceHeaderId` sets `%SessionId` empty — `Execute` does the same; a noticed incident's trace id is set when it is raised.
  - `[low]` `[reject]` Edge: no coalescing of a burst of CheckNows — duplicate of the Blind finding, by design.
  - `[low]` `[reject]` Edge: the fixed `Hang 1` in `AfterResolve` — duplicate of the Blind finding.
  - `[low]` `[patch]` Verification-gap: AC3 send-fail has no mutation line (warning, restore, switch) — three mutations applied, red observed, reverted, lines written.
  - `[low]` `[patch]` Verification-gap: `Now` calling `Sweep` or `BeatRunDue`, the per-row Catch and the eval guard have no mutation — four mutations applied, red observed, reverted, lines written. AC5's "Tick path unchanged" is pinned by the existing Tick tests, which ran green.
  - `[false]` `[reject]` Verification-gap: closeForReplay of an open incident is not pinned — `Transitions.Next` refuses closeForReplay for an open incident, so no move is accepted and no CheckNow can fire.
  - `[false]` `[reject]` Verification-gap: the `Kill response` assertion cannot fail — it fails if `OnRequest` ever sets a response for a CheckNow; a mutation of `Now` to return one would turn it red.
  - `[low]` `[patch]` Verification-gap: the `Size` helper reads 0 for a seam that never ran — the Sweep and BeatRunDue mutations show the combined assertion goes red when each seam runs.
  - `[low]` `[reject]` Verification-gap: `AfterResolve` timing-based absence check — duplicate of the Blind finding.
  - `[low]` `[reject]` Verification-gap: `AfterResolve` leaves the trace counter global — a monotonically increasing id counter in the test global; no assertion reads it.
  - `[low]` `[reject]` Verification-gap: `AfterResolve` cannot detect stale warm code — a CI-only class run on fresh stacks, and the spec's warm rule states it.
  - `[false]` `[reject]` Verification-gap: `TestCheckNowScope` sets `onlineDemo` — restored by `Runs.OnAfterOneTest`.
  - `[low]` `[reject]` Verification-gap: `TestCheckNowFailures` sub-cases share a cumulative warning count — one method, fixed order, and a failure would show as red, not as a false green.
  - `[low]` `[reject]` Verification-gap: row order of `Watching` is not observed — the order is only a determinism choice; no AC depends on it.
  - Intent alignment: descriptive audit, no findings. It reports that the diff implements the enumerated reading (R2), tests R4(b) and R4(c) in process, and covers the user-visible surface for two of the six trigger scenarios; the other scenarios are pinned at the component boundary, as the matrix states them.

## Design Notes

**Governing ADs:**
- **AD-18.** Checks runs the background checks and records the last run, the result and the trace header id. A CheckNow is one more run of the same row by the same owner, through the same path. NextDueAt is left as it was, so the due rule and "missed runs run once" hold. Its Rule is not contradicted, and no amendment is proposed.
- **AD-33.** Checks stays the only publisher of `check` and the only writer of the run fields; IncidentManager stays the only writer of incidents. So IncidentManager asks, and Checks runs.
- **AD-4.** The scope rule is the one `Unclosed` applies, now one method, `InScope`.
- **AD-15.** The transition table decides the trigger, and Transitions is unchanged.
- **AD-26.** The run goes in the incident's trace session, the Execute precedent.
- **AD-28.** The result comes from Checks' code alone; `check_status` and `Checks.Render` are unchanged.
- **AD-1 and AD-5.** The request is a production message, and nothing lives in memory.
- **AD-12.** The event is published after the UPDATE commits.
- **AD-22.** The tests run on the mock.
- **AD-29.** These are Lane A's files.

**Decided in-stage:**
- **Expired is included.** The table moves `awaiting_approval + expired` with nothing pending to `open`, exactly as a rejection does, so the story's carve-out ("unless the spec shows it moves the incident the same way") is met. The stale "a fix waiting for your approval" finding is the same defect.
- **Excluded moves.** `finished` into `fixing` (another approved request runs) or into `awaiting_approval`, `approved` into `fixing`, and the commands are not resolutions in the ruling's sense. The incident is still in flight.
- **Dismiss and closeQuiet are covered (lead, from the Planner's ruling of 2026-11-08, DW-957).** A dismiss or a `closeQuiet` of a noticed open incident (open to closed) also sends a CheckNow, because it changes what "An open incident" reads. A `closeQuiet` comes from Checks' own quiet sweep inside a Tick (SendQuiet, synchronous); the CheckNow it causes is asynchronous, so Checks (PoolSize 1) handles it after that Tick ends, and the same row may run twice within seconds. That is harmless (the second run reads the same state) and needs no guard. A move from `resolved` to `closed` changes nothing the check counts, so it sends none.
- **The schedule is kept by omitting `NextDueAt` from the UPDATE.** Recomputing it from the old row would have the same effect but adds a read.
- **Scope is decided in Checks, not by Recipients in IncidentManager.** Checks owns the BackgroundCheck reads, and IncidentManager would otherwise need a cross-session read. The set is the same: `Recipients(instance)` is `Watchers(ns, prod)`, the production rows of every session, and none on the online demo.
- **The name is `CheckNow`.** "Re-check" already names Story 7.3's FixExecutor re-check (`Test.Fix.Recheck`).
- **A row that matches nothing logs nothing.** "At most one warning" allows none, and an unwatched production is normal.
- **The integration tests inject the FixResult and the ApprovalOutcome from `SimMailboxIn`.** The producers are pinned elsewhere: `Test.Fix.Execute` for the FixResult and `Test.Bridge.Approval` for the outcome. The full mock-diagnosis chain would cost a minute of CI per test.
- **The integration bound is 10 s.** It is a test bound, not an NFR.

**Extend, don't copy (Rule 2):**
- `RowOf` and `InScope` are shared with `Due` and `Unclosed`, not copied.
- `Run` and `Record` are reused, with a flag.
- `CheckNow` and `SendCheckNow` copy the 8-line session swap of `Execute` and `SendExecute`. Each seam has to stay typed for its probe, and a shared helper would need `$Method` indirection, which reads worse.
- `SendToManager` copies `Case.SendExecute`'s 8 lines, because that method is typed to `Execute` and synchronous, and it reuses `ExecuteSessions` for the clean-up.
- `CheckNow.cls` mirrors `CheckChanged.cls`.

**Integration ACs (Rules 1 and 2):**
- Consumed-by: Checks (AC2, AC4), and through it `check_status` (Story 5.7), the rail and `/state`, and the digest's coverage (an extra CheckRun row per CheckNow).
- Consumes: the Story 5.5 table, the Story 5.6 run, and the Epic 7 `FixResult` and `ApprovalOutcome`.

**Ledger inbox:** DW-851 is addressed by the Execution items marked DW-851 and by AC1 to AC4.

**Spine (for the lead, Rule 20 light path; no AD changes).**
- A new message-table row after L1372:
  > | `OcuTalon.Checks.Msg.CheckNow` (AD-18, AD-33): `Namespace`, `Production`, `OwnerRef`, `IncidentRef`, sent by `IncidentManager`, asynchronously with no answer wanted and in the incident's trace session, after an accepted move that resolves an incident, reopens it after a rejected or expired request, or closes a noticed open incident by dismiss or closeQuiet; handled by `Checks`, which runs each production watch of that production in the incident's scope (AD-4) once through the normal run, leaving `NextDueAt` as it was | A | Story 5.15 |
- In the Conventions row "Background checks" (L1158), this sentence goes after the closeQuiet sentence:
  > After such a move `Checks` runs each in-scope watch once at once (no sweep, fix sweep, beats or Digest forward); that run's trace is the incident's trace session and its `UPDATE` leaves `NextDueAt` unchanged.

**Spec-gate answers:**
1. **Footprint** (every file and method):
   - `Checks/Msg/CheckNow.cls` (new);
   - `Checks/Process.cls`: the class doc, `LOGNOW`, `OnRequest`, `Now`, `Watching`, `RowOf`, `InScope`, `Due`, `Run`, `Record` and `Unclosed`;
   - `Watch/IncidentManager.cls`: the class doc, `CHECKS`, `LOGCHECKNOW`, `Apply`, `CheckNow` and `SendCheckNow`. The nearest edit is at about L1132, so the Epic 30 hunk merges as a plain union;
   - `Test/Checks/Probe.cls`, `Test/Checks/Runs.cls`, `Test/Watch/IncidentProbe.cls` and `Test/Watch/Lifecycle.cls`;
   - `Test/Checks/AfterResolve.cls` (new; area Checks exists, so `ci/units.sh` is unchanged);
   - any test the sweep updates;
   - this spec.

   No footprint extension.
2. **User-facing strings: none.** Two new operator-facing Type 3 log lines, each followed by the incident Ref, ": " and the redacted error, and never a SessionRef:
   - `Checks could not read the checks to run now for incident `
   - `IncidentManager could not ask Checks to run the checks of incident `
3. **Effort: about 2.5 hours**, a little over the Planner's 2-hour threshold:
   - product code, about 40 minutes;
   - the unit tests in `Runs` and `Lifecycle`, about 50 minutes;
   - the integration class, warm runs and mutations, about 60 minutes.

   The parts cannot ship apart: a send with no handler is an error 5001.

## Verification

`<lane>` stands for:

```
env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=5 stage=implement'
```

**Rules for every run:**
- One command per call, `timeout: 600000`, and never two IRIS test runs in one message.
- Each command must finish in about 150 s.
- QA uses the tags `e5s15q` and `e5s15qw`, and review uses `e5s15r` and `e5s15rw`.
- No step uses the slot.
- **The warm production.** The warm stack runs the code it loaded at `up`. So run `up` only after editing `Checks/Process.cls`, `Checks/Msg/CheckNow.cls` and `Watch/IncidentManager.cls`. After any later edit or mutation of one of them, run `<lane> OCUTALON_RUN_TAG=e5s15implw ci/warm.sh down`, then `up`, each in its own call, before `AfterResolve`. `Runs` and `Lifecycle` run shadow instances in the test process, so a warm reload is enough for them.

**Commands:**
- **(loop)** `<lane> OCUTALON_RUN_TAG=e5s15implw ci/warm.sh up`, under the rule above. If the harness moves the call to the background, poll `ci/warm.sh status` in the foreground until it exits.
- **(loop)** One per call, `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s15implw ci/iris.sh class <Class>`, for:
  - `OcuTalon.Test.Checks.Runs`;
  - `OcuTalon.Test.Watch.Lifecycle`;
  - `OcuTalon.Test.Checks.AfterResolve`.

  Expected: passed, with each class's seconds recorded. The aim for `AfterResolve` is at most 40 s, because its group `shards` runs about 1,830 s against 2,100.
- **(once)** One per call, the same way: `OcuTalon.Test.Watch.Tell`, `OcuTalon.Test.Eval.Incident`, `OcuTalon.Test.Digest.Send`, and every class the shared-surface sweep changed. Expected: passed.
- **(once)** The mutations (Rule 19). Apply each, observe the red, revert it, and confirm that `git status --short` and `git diff --stat` are unchanged; record each as `mutation: <change> -> <test> red`:
  - the `..CheckNow(incident)` call removed from `Apply`. `TestResolvingMovesCheckNow` goes red, and after `down` and `up` both `AfterResolve` tests go red (AC1, AC4);
  - the trigger widened to every accepted move. The Not resolving cases go red (AC1);
  - `EXPIRED` dropped from the trigger. The Expired case goes red (AC1);
  - the `DISMISS`/`CLOSEQUIET` clause dropped from the trigger. The Dismissed and Quiet-closed cases go red (AC1, DW-957);
  - `keep` ignored, so the UPDATE sets NextDueAt. `TestCheckNow` goes red on "NextDueAt unchanged" (AC2);
  - `Now` calling `Tick`'s path (or `Sweep`). `TestCheckNow` goes red on nothing quieted, swept or beaten (AC2);
  - `InScope` returning 1. `TestCheckNowScope` goes red (AC2);
  - the `LOGNOW` warning removed. `TestCheckNowFailures` goes red (AC3).
- **(once)** `bash ci/checks.sh`. Expected: every check passes.
- **(once)** `<lane> OCUTALON_RUN_TAG=e5s15implw ci/warm.sh down`, also after a failure. Then confirm that the lane-c lock folder holds none of this stage's locks.

**Left to CI and the lead.** CI is available:
- the full shards;
- `Test.Checks.Heartbeat`, `Test.Fix.Execute` and the other `Test.Fix` production classes (they now run a CheckNow at resolve);
- the live units and `demo-path`;
- fresh stacks, whose start-up and tests do not fit one call.

The lead runs the fresh-environment check, forward and reverse (Rule 19).

**Shared surfaces:**
- A resolved, rejected, expired, dismissed or quiet-closed (from open) incident now adds a CheckNow header (IncidentManager to Checks), a LOGRAN Info row and the run's warnings to the incident's trace session.
- Each in-scope watch gets one more run: its row's run fields, one `check` event, and one `Digest.Data.CheckRun` row through the update trigger.
- `IncidentProbe` gains a recorded seam that `ZzIncident` inherits.
- `Checks.Probe` gains `Watching`.

**Shared-surface sweep (Rule 19), implement stage.** The `rg` over `Test/Fix`, `Test/Watch`, `Test/Eval` and `web/e2e/demo-path` found no exact expectation that a resolved, rejected, expired, dismissed or quiet-closed incident now breaks, so no test was changed by the sweep. Stream readers filter by event type (`incident`, `watch.progress`), header readers filter by source and target or run before the resolution, and the Eval probe records CheckNows in its own property.

**Implement-stage record** (Lane C warm stack, run tag `e5s15implw`, ARM developer machine):
- Seconds per class (warm, passed): `Test.Checks.Runs` 2.0 to 3.1, `Test.Watch.Lifecycle` 0.2 to 0.3, `Test.Checks.AfterResolve` 3.3 to 3.9 (aim at most 40), `Test.Watch.Tell` 15.8, `Test.Eval.Incident` 2.6, `Test.Digest.Send` 10.7.
- Milliseconds from the send to the row's LastRunAt (AfterResolve, measured once by a temporary assertion that printed the figure): 251 (resolved) and 257 (rejected), against the test's 0.25 s poll step. The bound is 10 s.
- Mutations (Rule 19), each applied, observed red, reverted; `md5` of `Checks/Process.cls` and `Watch/IncidentManager.cls`, `git status --short` and `git diff --stat` identical to before:
  - mutation: `..CheckNow(incident)` call removed from `Apply` -> `TestResolvingMovesCheckNow` and `TestCheckNowSendFails` red; after `ci/warm.sh down` and `up`, `TestResolvedFixIsCheckedAtOnce` and `TestRejectedFixIsCheckedAtOnce` red (AC1, AC4); green again on a fresh `up` after the revert.
  - mutation: trigger widened to every accepted move (`If resolves || reopens || closesOpen` replaced by a bare call) -> `TestResolvingMovesCheckNow` red on the Not resolving cases (a progress result, a finished that stays fixing, awaiting, approved, a failed save, a dismiss/closeQuiet/closeForReplay of a resolved incident, a refused closeQuiet) (AC1).
  - mutation: `EXPIRED` dropped from the trigger -> `TestResolvingMovesCheckNow` red on "expired: one CheckNow" (AC1).
  - mutation: `closesOpen` clause dropped from the trigger -> `TestResolvingMovesCheckNow` red on "dismiss: one CheckNow" and "closeQuiet: one CheckNow" (AC1, DW-957).
  - mutation: `keep` ignored in `Record` (`If keep {` replaced by `If 0 {`, so the UPDATE sets NextDueAt) -> `TestCheckNow` red on "and NextDueAt is as it was" (AC2).
  - mutation: `Now` also calling the fix sweep `..Fixes()` (Tick's path) -> `TestCheckNow` red on "nothing was quieted, no fix result sent, no beat run and nothing sent" (AC2).
  - mutation: `InScope` returning 1 -> `TestCheckNow` (the production was read once; B's row unchanged) and `TestCheckNowScope` (session, session B, instance on the online demo) red (AC2).
  - mutation: the `LOGNOW` warning removed from `Now` -> `TestCheckNowFailures` red on "a read of the rows that throws logs one warning" (AC3).
  - mutation: the `LOGCHECKNOW` warning removed from `CheckNow` -> `TestCheckNowSendFails` red on "one warning names the incident" (AC3).
  - mutation: `IncidentManager.CheckNow` not putting `%SessionId` back after the send -> `TestCheckNowSendFails` red on "the handler's own session is put back" (AC3).
  - mutation: `IncidentManager.CheckNow` not switching `%SessionId` to the incident's TraceHeaderId -> `TestResolvingMovesCheckNow` red on "final/interrupted: one CheckNow, in the incident's trace session" and `TestCheckNowSendFails` red on "the send was tried once" (AC1, AC3).
  - mutation: `Now` also calling `Sweep` (the quiet sweep) -> `TestCheckNow` red on "nothing was quieted, no fix result sent, no beat run and nothing sent" (AC2).
  - mutation: `Now` also calling `BeatRunDue` -> `TestCheckNow` red on the same assertion (AC2).
  - mutation: the eval/empty-owner guard removed from `Watching` -> `TestCheckNowScope` red on "eval: the rows that ran" (AC2).
  - mutation: `Now`'s per-row Catch rethrowing instead of logging `LOGRUN` -> `TestCheckNowFailures` red on "a run that throws logs one LOGRUN warning" (AC3).

- `bash ci/checks.sh`: all 31 scripts passed (about 19 minutes in this stage because other lanes shared the machine; the call was moved to the background and polled to its end).
- The review patch (a doc sentence in `Test.Watch.IncidentProbe`) was followed by a green re-run of `Test.Watch.Lifecycle`, `Test.Eval.Incident`, `Test.Checks.Runs` and `Test.Checks.AfterResolve`. `Test.Watch.Tell` (15.8 s) and `Test.Digest.Send` (10.7 s) do not use the probe and were not repeated.
- `ci/warm.sh down` ran for tag `e5s15implw`; the lane-c lock folder holds none of this stage's locks. The implement handoff subagent sent two test-runner calls in one message twice (all passed, nothing overlapped visibly); every class was re-run here one per call.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

- Summary: after an accepted move that resolves an incident, reopens it after a rejected or expired request, or closes a noticed open incident by dismiss or closeQuiet, `IncidentManager` sends `Checks` one asynchronous `CheckNow` in the incident's trace session; `Checks` runs each in-scope production watch once through `Run` and `Record` with `keep`, leaving `NextDueAt` as it was (DW-851, DW-957). No user-facing string was added.
- Files changed:
  - `src/ocutalon/cls/OcuTalon/Checks/Msg/CheckNow.cls` (new): the request.
  - `src/ocutalon/cls/OcuTalon/Checks/Process.cls`: `Now`, `Watching`, `RowOf`, `InScope`, `Run` and `Record` with `keep`, `LOGNOW`, class doc.
  - `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`: `CHECKS`, `LOGCHECKNOW`, the trigger in `Apply`, `CheckNow`, `SendCheckNow`, class doc. Nothing between `Event` and `PurgeOne` changed.
  - `src/ocutalon/cls/OcuTalon/Test/Checks/Probe.cls`, `Test/Checks/Runs.cls`, `Test/Watch/IncidentProbe.cls`, `Test/Watch/Lifecycle.cls`: the seams and the matrix tests.
  - `src/ocutalon/cls/OcuTalon/Test/Checks/AfterResolve.cls` (new): the two Integration rows.
  - This spec: Verification record, triage log.
- Decided in-stage: `Watching` returns no row for an `eval` or empty owner before any read, because an eval incident's owner equals the eval session's Ref and `InScope` alone would run an evaluation run's watch row; the matrix row Scope says eval and empty give none.
- Review: 26 findings, none high or medium. Patches applied: 4 (the probe doc sentence and three groups of added mutation lines, which needed no code change). Deferred: 0. Rejected: 22, each with its reason in the Review Triage Log (5 false, 17 low).
- Follow-up review recommended: false (no high patched, no medium patched).
- Verification: `Runs`, `Lifecycle`, `AfterResolve`, `Tell`, `Eval.Incident` and `Digest.Send` passed warm on the lane-C stack; all 15 mutations went red and were reverted byte-identical; `bash ci/checks.sh` passed all 31 scripts. See the Implement-stage record under Verification.
- Residual risks: left to CI and the lead are `Test.Checks.Heartbeat`, `Test.Fix.Execute` and the other `Test.Fix` production classes (they now run a CheckNow at resolve), the live units, `demo-path`, and the fresh-environment check forward and reverse. The `AfterResolve` timing (3 s warm) is far under its 40 s aim.
