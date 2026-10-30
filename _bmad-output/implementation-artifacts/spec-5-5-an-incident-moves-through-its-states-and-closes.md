---
title: 'An incident moves through its states and closes'
type: 'feature'
created: '2026-10-26'
status: 'done'
baseline_revision: '38d126f368ed18ddb137b6c548ff7d824e020422'
baseline_commit: '38d126f368ed18ddb137b6c548ff7d824e020422'
review_loop_iteration: 0
followup_review_recommended: true
context: []
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      The real Execute order (target FixExecutor, the incident's trace SessionId and the kept SuperSession) is observed only at the test seam, not on a real message header.
    evidence: |-
      Test.Watch.IncidentProbe overrides SendExecute, so Lifecycle never runs SendRequestAsync; Closing only rejects. FixExecutor is a stub until Story 7.3, so a real approval has no handler to receive it. Lifecycle.TestExecuteTarget pins the item name only.
    location: >-
      src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls (Execute, SendExecute)
    severity: low

---

<intent-contract>

## Intent

**Problem:** After Story 5.8, an incident is grouped, settled, diagnosed and noticed, but it never leaves `open`. `IncidentManager` still carries `STUB` and answers every `IncidentCommand`, `ApprovalOutcome` and `FixResult` with "not implemented". So a dismissal through `CommandsIn` gets `not_built`, nothing ever closes an incident, the Fix area's `Execute` and `FixResult` messages do not exist, and closed incidents are never purged.

**Approach:** AD-15's transition table lives in one new pure class, `OcuTalon.Watch.Transitions`, and is unit-tested row by row. `IncidentManager` applies it to every input: the notice step, the synchronous `IncidentCommand` verbs (`dismiss`, `closeForReplay`, `closeQuiet`), `ApprovalOutcome` and `FixResult`. For each accepted move it saves the new state, publishes the incident's full view and, where the table says so, sends `Execute`. The story also creates `OcuTalon.Fix.Msg.Execute` and `FixResult`, and adds the Watch area's `Purge(daysToKeep)`. The spec is written to ruling R1 (a) (Design Notes): the chat dismiss tool moves to a sibling story, 5.9.

## Boundaries & Constraints

**Always:**
- **The table** is `Transitions.Next(state, noticed, event, facts, .to, .variant, .execute)`. It is pure and returns 1 for an accepted move and 0 for a refused one. `noticed` matters only for `open`. `execute` is `own` (the event's request), `earliest` (the earliest waiting request) or "". The rows:
  - (none) + `first` → `open`, no variant;
  - `open`, not noticed + `notice` (with facts `variant` `fallback` or `no_fix`) → `open` with that variant;
  - `open`, not noticed + `raised` → `awaiting_approval`;
  - `awaiting_approval` + `approved` → `fixing`, `execute` `own`;
  - `awaiting_approval` + `rejected` or `expired` → `open` with variant `rejected` or `expired` when `pending` is 0, else `awaiting_approval`;
  - `fixing` + `progress` → `fixing`;
  - `fixing` + `finished`: `waiting` 1 gives `fixing` with `execute` `earliest`; otherwise `awaiting_approval` when `pending` is 1, else `resolved`;
  - `fixing` + `approved`, `rejected` or `expired` → `fixing` (an approved request waits);
  - `awaiting_approval` or `resolved` + `raised` → `awaiting_approval`; `fixing` + `raised` → `fixing`;
  - `resolved` + `dismiss`, `closeForReplay` or `closeQuiet` → `closed`;
  - `open`, noticed + `dismiss` → `closed`; + `closeQuiet` → `closed` only when `demoMode` is 0.

  Every other move is refused, and so is every event on a `closed` incident. The variant is kept only while the state is `open`: any other target clears it.
- **Facts come from the rows (AD-11).** An incident's requests are the entries of `RequestRefs` whose `ApprovalRequest` row exists and names the incident (`IncidentRef`).
  - `pending`: another of its requests is `pending`, or is `approved` while the incident is `awaiting_approval` (that request's outcome is still on its way).
  - `waiting`: while the incident is `fixing`, another of its requests, other than the event's own, is `approved`. The earliest one in `RequestRefs` order is the one whose `Execute` goes.
  - `demoMode`: the setting `Install.Step.Demo` `MODEKEY` is "1". It is read through one private method, `DemoMode()`.
- **`IncidentCommand`** is answered synchronously with a `CommandResult`. The checks run in this order:
  1. A verb that is not one of `VERBS` is `unknown_command`.
  2. A missing incident is `not_found`.
  3. A `dismiss` whose `SessionRef` is not in `Session.Recipients(OwnerRef, Ref)` is also `not_found`. A failed read of the recipients is `failed` and logs one Type 3 warning.
  4. A `closeQuiet` whose `LastAt` is not more than `QUIETSECONDS` (900) before now (`Settle.Quiet`) is `not_quiet`.
  5. A move the table refuses is `not_allowed`.
  6. An accepted move is `Ok` 1 with `Outcome` `closed` and `Ref` set.

  Each answer that found the incident carries `Data` `{"state","openVariant"}` (after the command). `Message` is a plain-English class parameter, as in `WatchOps`. Neither `closeForReplay` nor `closeQuiet` checks a session: they have no `CommandsIn` route, and only product code sends them.
- **A close** sets `State` `closed`, `ClosedAt` (UTC now) and an empty `OpenVariant` in one save. Nothing is notified: the `incident` event is the only output.
- **`ApprovalOutcome`** maps to the events `approved`, `rejected` and `expired`. It is refused when its incident or request is not the incident's (see Facts), when `Outcome` is anything else (`cancelled` included, which the hold never sends), or when the request's row does not show that outcome (a repeat or a stale one).
- **`FixResult`** is `finished` when `Final` or `Interrupted` is 1, and `progress` otherwise. It is refused when its request is not one of the incident's.
- **An accepted event** saves the row when its state, variant or `ClosedAt` changes. After the commit, for a noticed incident, it publishes one `incident` event (`FromRow`) through `Tell`, even when the state stays the same, because the payload's `requests` may have changed. Then, when the table says so, it sends one `OcuTalon.Fix.Msg.Execute` (only `ApprovalRef`) to `FixExecutor`:
  - asynchronously, with no answer wanted;
  - in the incident's trace session (`TraceHeaderId`, with the `SuperSession` kept, AD-26);
  - through one private seam, `SendExecute`.

  A failed send logs one Type 3 warning, and the row stays as saved.
- **A refused event** writes, sends and publishes nothing. A refused `ApprovalOutcome` or `FixResult` logs one Type 4 info line (`LOGREFUSED`) that names the incident, the event and the state.
- **The notice step goes through the table.** `Notice` takes the state and the variant from `Next(…, "notice", {variant})`. A new private `Move(incident, to, variant, notification)` saves and then calls `Tell`, and `Deliver` becomes `NoticedAt` plus `Move`. `Record` takes a new incident's state from the `first` row.
- **`IncidentManager.Purge(daysToKeep)`** is a `ClassMethod` and stays on the only writer (`CodeRules`).
  - It deletes the incidents that are `closed` with a `ClosedAt` before the cutoff, together with their groups (`FailureGroup.OfIncident`), one incident per transaction. The cutoff is now (UTC) moved back `daysToKeep` days, by `Digest.Data.Item.Purge`'s rule.
  - It keeps every other incident, including a closed one with an empty `ClosedAt`.
  - A `daysToKeep` that is not a whole number of at least 1 is an error status, and nothing is deleted.
- **The Fix messages** (AD-16), both `Ens.Request`, neither with a `SessionRef`:
  - `Execute`: `ApprovalRef` (22), with `[ SqlTableName = FixExecute ]`, because `Execute` is an SQL reserved word (measured on slot A, build 154);
  - `FixResult`: `ApprovalRef` and `IncidentRef` (22), `Final` and `Interrupted` (`%Boolean`), `Total`, `Resent`, `Completed`, `FailedAgain` and `Skipped` (`%Integer`), and `Reason` (1000).
- **`STUB` goes.** The item is built: every input that AD-15 names is handled. Any other request class answers a 5001 error that names the class, not 5003.
- **Unchanged:** `PoolSize` 1; `IncidentManager` stays the only writer of `Incident` and `FailureGroup` and the only publisher of `incident` and `watch.progress`; `Tell`'s recipients and warnings; 5.8's notice.

**Never:**
- No chat dismiss tool, no `Tools/**` change and no `Agent/Chat.cls` change (R1: those belong to Story 5.9).
- None of the following, each owned by a later story:
  - no `answered` or `result` notification, no `FixRun`, no `requests` result and no `Raise` (Stories 7.2 to 7.4);
  - no `Execute` handler in `FixExecutor` (Story 7.3);
  - no `Checks` sender (Story 5.6), no `BreakFeedIn` (Story 4.3) and no REST change (Story 6.4);
  - no Install step (Story 30.2).
- No change to the `Incident`, `FailureGroup` or catalog definitions, and no `Live/Payload` change.
- No edit to a contended path or to product code of another lane: `Web/**`, `Core/**` (product code; `Test/Core/CommandsInProduction.cls` is the one test changed, below), `Data/{Ownership,Session,Setting}.cls`, `Install/**`, `Demo/**`, `Channel/**`, `Test/{Web,Data,Demo}/**`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Dismiss | Session A's noticed `open` `no_fix` incident, and a `resolved` one; `dismiss` from A | `1`, `closed`, the Ref; each row is `closed` with `ClosedAt` and no variant; one `incident` event (`closed`) on A's stream | none |
| Dismiss refused | From B, which is not a recipient; on `awaiting_approval`, `fixing`, `closed`, or an unnoticed `open` incident | `0`, `not_found` (B); `0`, `not_allowed`, `Data` with the state (the rest). Nothing is written or published | refusal |
| Instance dismiss | An instance incident watched by A and not by C | A gets `closed`; C gets `not_found` | refusal |
| Replay | `closeForReplay` on `resolved`; on `open`, `awaiting_approval` or `fixing` | `closed`; else `not_allowed` with the state | refusal |
| Quiet close | `LastAt` 16 min ago: `resolved`; noticed `open` with demo mode off, then on; `awaiting_approval`; `fixing`. `LastAt` 14 min ago | `closed`; `closed`, then `not_allowed`; `not_allowed`; `not_allowed`. `not_quiet` and nothing changes | refusal |
| Approved | `awaiting_approval`, R1's row `approved` | `fixing`; one `Execute` (R1) in the incident's trace session; one event | none |
| Rejected or expired | `awaiting_approval`, nothing else pending | `open`, with `rejected` or `expired` | none |
| Overlap, pending | R1 rejected while R2 is `pending`, or `approved` with its outcome not yet here | `awaiting_approval`; when R2's approval then arrives: `fixing` and `Execute` R2 | none |
| Overlap, fixing | `fixing` (R1): R2 approved; R2 rejected or expired; R1 in progress | `fixing`, no `Execute`, one event each | none |
| Finished | `fixing` R1, final (or `Interrupted` 1): nothing else; R2 pending; R2 and R3 approved | `resolved`; `awaiting_approval`; `fixing` with one `Execute` for R2 only | none |
| Refused events | `cancelled`; an outcome its row does not show (a repeat of R1 `approved` after R1 is `done`); a Ref not in `RequestRefs` or of another incident; no incident; a `FixResult` outside `fixing`; any event on `closed` | Nothing written, sent or published; one info line | dropped |
| Closed, then the same cause | The real production: A's dismissed no-fix incident, then a same-cause failure | A new incident with a new Ref and its own notice | none |
| Purge | Closed 91 and 89 days ago, both with groups; an `open` incident older than that; `daysToKeep` 90, then 0 and "x" | The 91-day one and its groups are gone, the rest stay; 0 and "x" are errors and nothing is deleted | error status |

</intent-contract>

## Code Map

Every path is under `src/ocutalon/cls/OcuTalon/` unless noted.

- `Watch/IncidentManager.cls` (519 lines):
  - the class doc L35-45 (it ends "states beyond open are Story 5.5's" and "still answered not implemented": rewrite it);
  - `STUB` L51, `OPEN` and `CLOSED` L54-56, `OnRequest` L96 (only `FailureBatch` and `Settle`), `Record` L151 (`State = ..#OPEN` at L193), `Find` L234 (skips `closed` at L237 and L242);
  - `Notice` L421 (calls `Deliver` with `..#OPEN` at L433), `Deliver` L443, `SendNotice` L464 (the seam pattern), `Open` L470, `Tell` L486.
- `Watch/Settle.cls`: `Wait` and the private `Seconds` (the time arithmetic that `Quiet` reuses). `Watch/Notice.cls`: `Key` and `Variant` L46-55.
- `Msg/IncidentCommand.cls` (`VERBS`, `IncidentRef`), `Msg/Command.cls` (`Origin`, `IdempotencyKey`, `SessionRef`) and `Msg/CommandResult.cls` (`Ok`, `Message`, `Outcome`, `Ref`, `Data`). The parameter style of `Watch/Ops.cls` L18-35.
- `Msg/Enum.cls`: `INCIDENTSTATE` L18, `INCIDENTOPENVARIANT` L21, `APPROVALSTATE` L24.
- `Core/CommandsIn.cls` (shared by entry; unchanged): `Dismiss` reaches `IncidentManager` as an `IncidentCommand` (`Dismissal` L133). A tool's dismissal is limited to `Ownership.Incident` (L74-78). `IsStub` L145 maps 5003 to `not_built`.
- `src/bridge/cls/OcuTalon/Bridge/Msg/ApprovalOutcome.cls` (`ApprovalRef`, `IncidentRef`, `Outcome`). `Bridge/Approval.cls` `HoldResponse` L584: on its expiry key it sends the row's `approved` or `rejected` state again, so a repeated outcome is possible (inference). `Bridge/Data/ApprovalRequest.cls`: `RefIndex`, `State`, `IncidentRef`.
- `Data/Incident.cls`: `State`, `OpenVariant`, `NoticedAt`, `LastAt`, `ClosedAt`, `TraceHeaderId`, `RequestRefs`. `Data/FailureGroup.cls` `OfIncident`. `Data/Session.cls` `Recipients` L93 (contended; call only).
- `Install/Step/Demo.cls` `MODEKEY` L40 ("demo.mode"; contended, read only, as `Web/TraceLink.cls` L36 does). `Digest/Data/Item.cls` `Purge` L64 (the validation and the cutoff). `Production.cls` L40 (`IncidentManager`) and L44 (`FixExecutor`, a stub until Story 7.3). `Fix/Executor.cls`.
- Tests:
  - `Test/Watch/IncidentProbe.cls`: the shadow-instance pattern (`SendNotice` override, `FailFor`).
  - `Test/Watch/Tell.cls`: `Host` L305, `Group` L255, `DropGroups` L271, `Events` L322, and the clean-up L62-82.
  - `Test/Data/Fixture.cls` (contended; call only): `Session` L19, `Check` L65, `Incident` L81 (defaults: state `open`, `LastAt` in 2030), `Approval` L102.
  - `Test/Watch/Case.cls`: `SendBatch` L888, `Incidents` L924 (add `closedAt`), `WaitIncident` L958, `WaitNotices` L1058, `NoticeBodies` L1034, `Stream` L1027, `PointKeys` L371.
  - `Test/Watch/Notices.cls` L30-62: the marker batches and the waits.
  - `Test/Watch/Incidents.cls` `TestClosedOpensNew` L340 (with a fixture close).
  - `Test/Bridge/Approval.cls`: `NewRow` L1552, `Raise` L1570 (with the probe `SINK` L87), `Answerer` L2118 (`ANSWERER` L93), `RaiseHeld` L2129, `WaitOutcomes` L2243, `TestAnswerRejects` L861.
  - `Test/Core/CommandsInProduction.cls` `TestToolDismissReachesIncidentManager` L151 (L169 asserts `0|not_built`).
  - `Test/Install/Production.cls`: the class doc L13 ("IncidentManager keeps STUB"), oracle row L624 (`IncidentManager`, `stub` 1) and `TestStubsAnswer` L139.
  - `Test/Bridge/CodeRules.cls` `TestOnlyIncidentManagerWritesIncidents` L268. `Test/Contract.cls` `AssertSqlNames` L46 (checks table names too).

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Fix/Msg/Execute.cls`, `src/ocutalon/cls/OcuTalon/Fix/Msg/FixResult.cls`: new. Their properties, types and table name are given in Always (the Fix messages). The class docs name the sender and handler of each (Stories 7.3 to 7.5). The `Storage` blocks are as the compiler writes them.
- `src/ocutalon/cls/OcuTalon/Watch/Transitions.cls`: new and pure. It holds `Next` and the table of Always, with parameters for the states, events and variants, and a class doc that lays out the table.
- `src/ocutalon/cls/OcuTalon/Watch/Settle.cls`: add `Quiet(lastAt, now, seconds) As %Boolean`. It gives 1 when `lastAt` is more than `seconds` before `now`, and 0 for a time it cannot read.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls`:
  - `OnRequest` dispatches `IncidentCommand`, `Bridge.Msg.ApprovalOutcome` and `Fix.Msg.FixResult`;
  - add the facts read, `Move`, `SendExecute`, `DemoMode` and `Purge`;
  - `Notice`, `Deliver` and `Record` use the table;
  - remove `STUB`;
  - add the parameters (`QUIETSECONDS`, `FIXEXECUTOR` "FixExecutor", the messages, `LOGREFUSED`, `LOGEXECUTE`);
  - rewrite the class doc.
- `src/ocutalon/cls/OcuTalon/Test/Watch/IncidentProbe.cls`: `SendExecute` records `{approvalRef, sessionId}` in `Executed` and answers OK, or an error when `FailExecute` is set; `DemoMode` gives `DemoModeIs` when it is set. Doc: why it overrides.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Transitions.cls`: new and pure (runs warm).
  - `TestRows`: every row of Always, each fact combination included.
  - `TestRefusedMoves`: every pair of state (unnoticed and noticed `open`, `awaiting_approval`, `fixing`, `resolved`, `closed`) and event (`first`, `notice`, `raised`, `approved`, `rejected`, `expired`, `progress`, `finished`, `dismiss`, `closeForReplay`, `closeQuiet`), with each fact at 0 and at 1, is refused unless it is a listed row.
  - `TestQuiet`: `Settle.Quiet` at 899, 900 and 901 seconds, and with an unreadable time.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls`: new; probe tests with `Fixture` rows on ZZNS (runs warm). It drives every message row through the probe's `OnRequest` with real `IncidentCommand`, `ApprovalOutcome` and `FixResult` objects.
  - Tests: `TestDismiss`, `TestInstanceDismiss`, `TestCloseForReplay`, `TestCloseQuiet`, `TestApprovalOutcomes`, `TestFixResults`, `TestRefusedEvents`, `TestEveryChangePublishes` (accepted: exactly one `incident` event, with the row's state, on each recipient's stream; refused: none), `TestRepeatDismiss`, `TestExecuteSendFails`, `TestPurge` and `TestFixMessages` (the properties and types of Always, and that `FixExecute` is not a reserved word).
  - After each test it removes its rows, its groups, its approval rows, its streams and its log lines.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Closing.cls`: new; it extends `Case` and runs over the running production (fresh only, about 100 s at most).
  - `TestDismissThroughCommandsIn`: a no-fix incident of A (a `[[mock:diagnosis-nofix]]` batch on ZZNS), once noticed, is dismissed with `Commands.Submit(Dismiss, "web_user")`. Then:
    - the result is `1|closed`, the row is `closed`, and the newest `incident` event on A's stream is `closed`;
    - the same `Dismiss` from session B is `0|not_found`;
    - a same-cause batch makes a second incident with a new Ref, and one `Notification` carries that Ref.
  - `TestRejectThroughTheHold`:
    - set-up: A's fixture incident is noticed and `awaiting_approval`; a real fix request is raised for it (as `Test.Bridge.Approval` does, with its probe sink and `ResultTarget` `IncidentManager`), and the row's `RequestRefs` is set to that request's Ref;
    - the `ANSWERER` account's `Answer(reject)` leaves the incident `open` and `rejected`, with an `incident` event on A's stream;
    - the hold ends, and the request row is removed afterwards.
- `src/ocutalon/cls/OcuTalon/Test/Watch/Case.cls`: `Incidents` also gives `closedAt`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: the `IncidentManager` oracle row gets `"stub": 0`, and the class doc (L13) lists `IncidentManager` among the built items (Lane A row and its doc line only).
- `src/ocutalon/cls/OcuTalon/Test/Core/CommandsInProduction.cls`: in `TestToolDismissReachesIncidentManager` (doc and L169), the session's own noticed incident now reaches the real `IncidentManager` and is closed (`1|closed`). The other assertions are unchanged.

**Acceptance Criteria:**
- Given AD-15's table, when `Transitions.Next` is called for every pair of state and event and every combination of facts, then the rows of Always give their target, variant and `execute`, and every other pair is refused, including `dismiss` while `awaiting_approval` or `fixing` and anything on a `closed` incident.
- Given fixture incidents, requests and sessions, when the probe's `OnRequest` receives each `IncidentCommand`, `ApprovalOutcome` and `FixResult` of the matrix, then the row, the `CommandResult`, the recorded `Execute` and the published events match the matrix. One fix runs at a time, and a refused event changes, sends and publishes nothing.
- Given A's noticed no-fix incident on the running production, when A submits `Dismiss` through `Commands.Submit` with origin `web_user`, then `CommandsIn` and `IncidentManager` close it synchronously (`Ok` 1, `closed`), and an `incident` event in state `closed` reaches A's stream. The same `Dismiss` from B is `not_found` (Integration AC: consumer `CommandsIn` of `IncidentManager`'s `dismiss`).
- Given a real fix request of an `awaiting_approval` incident, when it is rejected through `Approval.Answer`, then `ApprovalHold`'s `ApprovalOutcome` moves the incident to `open` with `rejected`, and its `incident` event reaches the owner's stream (Integration AC: `IncidentManager` consumes the real hold's outcome).
- Given a closed incident, when a failure with the same cause arrives, then a new incident opens with its own Ref and its own notice.
- Given incidents closed 91 and 89 days ago and an older open one, when `IncidentManager.Purge(90)` runs, then only the 91-day-old incident and its groups are deleted.
- Given the product source, when `Test.Bridge.CodeRules`, `Test.Install.Production`, `Test.Data.Tables` and `ci/checks.sh` run, then they pass: `IncidentManager` carries no `STUB` and is still the only writer and publisher, and no persistent class projects a reserved word.

### Review Findings

Code review, 2026-10-26 (four layers: blind-hunter, edge-case-hunter, verification-gap, acceptance-auditor; 29 raw findings, 12 entries after grouping, 11 rejected). Each entry: severity / fix-risk / footprint / spec-status.

- [x] [Review][Patch] A `failed` answer to a command whose save failed carried no `Data`, against the Conventions row "Incident commands" ("every answer that found the incident carries `Data`"; Rule 6) — high / low (two lines, the row read again) / in-story / clear. `Command` now answers the stored state (`%Reload`), since a failed `%Save` leaves the object moved; the probe's `FailMove` moves the object first, as a real failed save does, and `Lifecycle.TestFailedSaveChangesNothing` pins `0|failed||open|no_fix`. A failed read of the recipients still answers no `Data`: its caller is unverified, like a non-recipient's `not_found` (AD-4) [src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:622]
- [x] [Review][Patch] `Closing.TestApproveSendsExecuteToFixExecutor` repeated `TestRejectThroughTheHold`'s set-up (about 30 lines) with no stated reason (Rule 2) — med / low / in-story / clear. Both now use `HeldRequest` and `WaitHoldEnds` [src/ocutalon/cls/OcuTalon/Test/Watch/Closing.cls:127]
- [x] [Review][Patch] "No answer comes back" was asserted the moment the `Execute` header appeared, before `FixExecutor` had handled it, so an answer wanted could pass (Rule 19) — med / low / in-story / clear. The test waits for the header's handled status, then looks for an answer for `NOANSWERSECONDS` [src/ocutalon/cls/OcuTalon/Test/Watch/Closing.cls:167]
- [x] [Review][Patch] "Other than the event's own" in the `waiting` fact had no pinning test: with the exclusion removed every test stayed green (Rule 19) — med / low / in-story / clear. `TestFixResults` adds a final result whose own request still reads `approved`: `resolved`, no `Execute` [src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:552]
- [x] [Review][Patch] The SuperSession assertion could not fail: the header was found by `SuperSession` — low / low / in-story / clear. It is found by the incident's trace session (`SessionHeaders`) [src/ocutalon/cls/OcuTalon/Test/Watch/Closing.cls:160]
- [x] [Review][Patch] `Lifecycle`'s `Link`, `SetRequest` and `SetClosedAt` dropped the save status, so a fixture step could fail silently and a refusal pass for the wrong reason — low / low / in-story / clear. They throw on a failed save [src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls:838]
- [x] [Review][Patch] `TestPurge` pinned the cutoff from one side only: a purge that kept a day too long passed — low / low / in-story / clear. An incident closed an hour before the cutoff must go [src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls:593]
- [x] [Review][Patch] `FixResult`'s class doc named Sweep as a sender of interrupted runs only; AD-16: `Sweep` returns final results (ended in-progress runs and interrupted ones) and `Checks` sends them — low / low / in-story / clear [src/ocutalon/cls/OcuTalon/Fix/Msg/FixResult.cls:1]
- [x] [Review][Patch] `Notice` passed a fixed "not noticed" to the table instead of the row's `NoticedAt` — low / low / in-story / clear [src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls:478]
- [x] [Review][Patch] DW-281 still said the real `Execute` header is observed only at the seam, though QA's Closing test reads it — low / low / in-story / clear. Ledger trailer `resolved-by` this story (the spec's frontmatter `deferred:` entry and the Auto Run Result's residual-risk line are build-auto's sections, left for the lead)
- [x] [Review][Patch] `Transitions.TestQuiet`, the only pin of the 900-second boundary, had no `mutation:` line (Rule 19) — low / low / in-story / clear. Demonstrated and written under Verification
- [x] [Review][Defer] `Lifecycle`'s `Host`, `Group` and `DropGroups` repeat `Tell`'s; a FailureGroup fixture builder now sits in six Watch and Live test classes (Rule 2, weak reason: "follows Tell") — low / low / out-of-footprint (the shared home, `Test.Data.Fixture`, is contended) / clear [src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls:791] — deferred: DW-282 `wontfix-accepted`, reopen_if another test class adds its own FailureGroup or probe-host builder

Rejected:
- `low` blind: `Execute` on the `earliest` path keeps the SuperSession of whoever sent the `FixResult` — wontfix-theoretical: every sender of this story keeps the incident's SuperSession; real only if Story 7.5's `Checks` relays a `FixResult` with another SuperSession while an approved request waits and a reader attributes by the `Execute`'s SuperSession.
- `low` blind: `Purge` has no Try/Catch — only a digit string over 145 digits reaches `<MAXNUMBER>`, and the caller is a task's `%Integer` property (Story 30.2).
- `low` blind + edge: a failed `SendExecute` or a failed async save leaves the incident stuck — the send's handling is the spec's ("A failed send logs one Type 3 warning, and the row stays as saved"; by-design); a failed save of the only writer's own row (PoolSize 1) has no realistic trigger (wontfix-theoretical).
- `low` blind + auditor: `MESSAGENOTQUIET` says "15 minutes" beside `QUIETSECONDS` — developer text (the "Incident commands" row), and 900 is the PRD's fixed assumption; deriving it adds machinery.
- `false` edge: a final `FixResult` of a request that is not running resolves the incident — the intent refuses a `FixResult` only when it is not the incident's (spec-bound), and AD-16 sends one final result per run that started.
- `false` edge: a refused notice on an unnoticed incident that is not `open` is silent — `Notice` runs only on rows that `Open` passes, after `Answered` or `Refused`, and a with-fix diagnosis has no key, so no such row reaches the table.
- `low` edge: `closeQuiet` can read a demo mode cached for 60 s — `demo.mode` is written only by the install step's `Seed`, and every reader shares the cache (`TraceLink`, `Rule.Functions`); wontfix-theoretical: real if `demo.mode` is switched on while the production runs.
- `false` edge: `TestApproveSendsExecuteToFixExecutor` leaves its `Execute` header, body and the stub's log row — `InProduction.OnAfterAllTests` removes every session that carries the fixture session's TraceRef (`Fixture.RemoveMessages`), the `Execute`'s session with its body and log rows included.
- `low` verification-gap: `TestPurge` skips when the namespace holds a closed incident older than 59 days — fresh stacks hold none, and a seam would change `Purge`'s shape; probe: a fresh or CI run of `Test.Watch.Lifecycle` prints `SKIP` for `TestPurge`.
- `low` verification-gap: `Refuse` compares two empty snapshots for a missing incident — those three cases are carried by `Refuse`'s other assertions (nothing sent, nothing published, one info line).
- `false` auditor: a second `CommandsInProduction` test changed beyond the plan — recorded under "Beyond the spec's file list", and the file is this story's footprint extension.

## Spec Change Log

- 2026-10-26, spec gate (Epic 5 runner): R1 ruled (a), decide; Epic 5's 5.5 block amended and Story 5.9 added; spine rows "Incident commands" (new) and "SQL reserved words" (amended) written; status set to `ready-for-dev`.

## Review Triage Log

### 2026-10-26 - Review pass
- verdicts: 28 findings - high 0, medium 5, low 11, false 12, maybe-false 0
- findings:
  - `[false]` `[reject]` blind: `Purge` is never called and its query has no index - the caller is Story 30.2 (the intent's Never list), and the daily purge scans the closed rows once a day
  - `[false]` `[reject]` blind: an interrupted run resolves the incident - the intent says `finished` is `Final` or `Interrupted` (spec-bound; Story 7.4 owns the counts)
  - `[low]` `[reject]` blind: a cancelled outcome can leave `awaiting_approval` with nothing to move it - the intent refuses `cancelled`, "which the hold never sends"; theoretical
  - `[false]` `[reject]` blind: `raised` is never sent - the intent gives the sender to Stories 7.2 to 7.4
  - `[low]` `[reject]` blind: weak Execute failure handling, an empty `TraceHeaderId` - the warning and the unchanged row are the specified handling, `Record` always sets `TraceHeaderId`, and `Tell` uses the same session swap
  - `[low]` `[patch]` blind: the `failed` answer is missing from the class doc, and its branches are untested - the doc line is added; the branches have no seam (the same gap Story 5.3 accepted), so no test
  - `[low]` `[patch]` blind: a stray tab before `Do ..Deliver` in `Notice` - removed; the quiet quit on a refused `notice` is right (`Open` already checks closed and noticed)
  - `[medium]` `[patch]` blind: `TestPurge` deletes rows it did not make - it skips when the namespace holds a closed incident older than 59 days; the "minute" comment now says an hour (an exact-boundary case cannot be built: the cutoff is computed inside `Purge`)
  - `[false]` `[reject]` blind: `closeQuiet` checks quiet before the table - the intent fixes the order (step 4 before step 5)
  - `[false]` `[reject]` edge: `FixResult` has no row check - the intent refuses it only when its request is not the incident's
  - `[low]` `[reject]` edge: cancelled leaves `awaiting_approval` - same as the third finding above
  - `[medium]` `[patch]` edge: `TestPurge` over the whole table - same root cause as the blind finding, one patch
  - `[false]` `[reject]` edge: a refused `notice` is silent - `Open` guards closed and noticed rows, and a notice that does not apply is not an event to log
  - `[low]` `[reject]` edge: `SendExecute` throwing leaves `%SessionId` changed - `SendRequestAsync` answers a status and the handler's request ends anyway; Execute's swap follows `Tell`'s
  - `[false]` `[reject]` edge: `raised` on a noticed `open` incident is refused - AD-15's table has it only for an unnoticed one
  - `[false]` `[reject]` edge: a timer or system `Dismiss` has no session - the intent makes a `dismiss` need a recipient session
  - `[false]` `[reject]` edge: `closeQuiet` on an empty `LastAt` - `Record` always sets `LastAt`
  - `[false]` `[reject]` edge: claim "a repeat is refused by the row" - it is said of `ApprovalOutcome`, and its row check is there
  - `[low]` `[reject]` edge: a second `finished` can send the same `Execute` before `FixExecutor` changes the row - `FixExecutor` refuses it (Story 7.3); the intent's row rule is kept
  - `[medium]` `[patch]` verification-gap: the real `SendExecute` (target and header) is never run - `Lifecycle.TestExecuteTarget` now pins that `FIXEXECUTOR` is an enabled item of the production; the header (target, session, SuperSession) stays unobserved until Story 7.3's handler test, deferred below
  - `[medium]` `[patch]` verification-gap: the item's own `DemoMode()` reading is not asserted - `TestCloseQuiet` now writes `demo.mode` 1 and 0 with `DemoModeIs` unset and puts the row back
  - `[low]` `[patch]` verification-gap: the unknown-class error and the `failed` answers have no test - `TestUnknownRequest` added; `failed` has no seam (rejected as above)
  - `[low]` `[patch]` verification-gap: seven pinning tests have no `mutation:` line - the lines are demonstrated and written in `## Verification`
  - `[medium]` `[patch]` verification-gap: `TestPurge` not self-contained - same root cause as the first `TestPurge` finding
  - `[false]` `[reject]` verification-gap: `Closing` relies on the install account `ocutalon` - it asserts it with a reason; the account is the installer's by design
  - `[false]` `[reject]` intent-alignment: `Data` is absent on a non-recipient `not_found` - right: it must not tell a non-recipient the incident's state
  - `[low]` `[patch]` intent-alignment: the 5001 fallthrough has no test - `TestUnknownRequest`
  - `[low]` `[patch]` intent-alignment: `Execute` is observed only at the seam - same as the `SendExecute` finding; the residual is deferred

## Design Notes

**Ruling (R1) RULED 2026-10-26 by the epic lead as recommended (a)** (unattended, decide: a split into siblings planned next in the same epic, within `limits.split_children`). Epic 5's 5.5 block carries an `[AMENDED …]` marker, Story 5.9 "Ask OcuTalon in the chat to dismiss an incident" is added (key `5-9-ask-ocutalon-in-the-chat-to-dismiss-an-incident`, run right after 5.5), and the three spine candidates below are written: the Conventions row "Incident commands" (the result codes, `Data`, the session rule, `QUIETSECONDS`, and what "pending" means in AD-15's overlap rows; recorded as a Conventions row, so AD-15's text is unchanged) and the "SQL reserved words" row's `SqlTableName` clause. Originally: the plan halted on R1.
- **R1. Split** (product default 6; the lead asks for a split when a story does not fit one implement pass). Story 5.5's block holds two units, each the size of a story:
  - the incident lifecycle in `IncidentManager`: the table, its overlap rows, the Fix messages, the two message handlers with `Execute`, the three commands, a new incident after a close, and `Purge`;
  - the Chat agent's dismiss tool.

  The tool is a separate area: `Tools/WatchTools` and `Watching`, `Agent/Chat.cls`'s instructions, a mock scenario and a real-turn test. It also changes a shared surface: the tool list offered to the model, which `Test.Agent.Runners`, `Test.Agent.Instructions`, `Test.Tools.Reminders`, `Test.Watch.Turns`, `Test.Watch.Tools`, `Test.Bridge.Gate` and `Test.Bridge.Decide` (tool JSON size) assert. Planned whole, the story would be well over 5.8's size, which already carried `oversized`.
  - **Recommended (a):** two siblings.
    - 5.5 keeps every criterion of its block except the third paragraph ("Given a user asks in the chat to dismiss an incident", with its `And`).
    - A new sibling, **Story 5.9 "Ask OcuTalon in the chat to dismiss an incident"**, takes that paragraph verbatim. It is planned next and runs right after 5.5, before 5.6: UJ-1's rejected path says "Dismiss the incident in the chat" (product default 1). It consumes `IncidentManager`'s `dismiss` from this story and the `dismiss_incident` name already in `Tools/Names.cls`. `CommandsIn`'s tool limit (`Ownership.Incident`) is already built (`Test.Core.CommandsRouting.TestToolDismissOwnIncident`).
  - **Alternatives:** (b) one story, which is oversized; (c) a third child for `Purge`, which would be thin (about 40 lines and one test) and belongs with the only writer.
  - Under (a) the lead amends Epic 5's 5.5 block, adds the 5.9 block and its tracker key, and sets this spec to `ready-for-dev`.

**Governing ADs:**
- AD-1: commands reach the owner through `CommandsIn` and are answered synchronously.
- AD-4: `Recipients` decides who may dismiss, and gets the events.
- AD-5: the rows are the state.
- AD-11: the request row is the truth, so the facts are read from it.
- AD-12: the full view is published after commit.
- AD-15: the table, the overlap rule, `closeQuiet` and the variants.
- AD-16: the Fix messages, and `Execute` carries only the Ref.
- AD-22: throwaways and the mock.
- AD-26: `Execute` goes in the incident's trace session.
- AD-27: `Purge(daysToKeep)`.
- AD-29 and AD-33: Lane A, the only writer and publisher.

Conventions: "SQL reserved words" (applied here to a table name), "Messages", "Times", "Logging and errors".

**Integration ACs, Consumes, Consumed-by:**
- New: `Transitions`; `IncidentManager`'s handling of the three commands, `ApprovalOutcome` and `FixResult`; `Execute` and `FixResult`; `Purge`.
- Integration ACs: AC 3 (consumer `CommandsIn`) and AC 4 (the real `ApprovalHold`'s outcome), both on the running production.
- Consumes:
  - 5.8: `Notice`, `Deliver`, `Tell`;
  - 5.3: `Record`, `Find`;
  - Epic 0: `IncidentCommand`, `CommandResult`, `Live.Payload.Incident`;
  - Epic 2: `Session.Recipients`, `CommandsIn`'s `Dismiss` route, `Live.Publish`;
  - Epic 3: `ApprovalHold`'s `ApprovalOutcome`, `ApprovalRequest` rows, `Approval.Raise` and `Answer` (tests).
- Consumed-by:
  - 5.9: the dismiss tool, through `CommandsIn`;
  - 5.6: `Checks` sends `closeQuiet` and reads `not_quiet` and `not_allowed`;
  - 4.3: `BreakFeedIn` sends `closeForReplay` (`closed`, else `not_allowed` with `Data.state`);
  - 6.4: REST dismiss and the incident cards (the state chip follows the table);
  - 7.2: `raised` rows through `Transitions`, `Deliver` with `awaiting_approval`, and the answered notice added to the rejected and expired moves;
  - 7.3: `FixExecutor` handles the `Execute` that this story sends;
  - 7.4: records the `FixResult` counts;
  - 7.5: `Sweep`'s `FixResult` through `Checks`;
  - 30.2: the purge task calls `IncidentManager.Purge`.

**Extend, don't copy:**
- `Transitions` sits beside `Settle` and `Notice`, as a pure helper of `IncidentManager`. No table sibling exists.
- `Move` is `Deliver`'s save-then-`Tell` shape, and `Deliver` now calls it.
- `SendExecute` follows `SendNotice`. The probe's overrides follow `SendNotice` and `FailFor`.
- `Settle.Quiet` reuses `Settle.Seconds`.
- `Purge` copies `Digest.Data.Item.Purge`'s three-line cutoff. `Data.Time` has no days-before helper, and unifying the two would touch Digest, outside this story.
- `Lifecycle` follows `Tell`'s probe tests. `Closing` follows `Notices` and `Test.Bridge.Approval`'s `RaiseHeld` and `Answerer`.

**Ledger inbox:** none.

**Decided in-stage:**
- **The 5.5 block and AD-16 ("its unit test of IncidentManager covers every AD-15 row") select this reading:** `IncidentManager` handles `ApprovalOutcome` and `FixResult` and sends `Execute` now. Story 7.3's "IncidentManager sends Execute and handles FixResult" then consumes what exists. Epic 7 keeps `FixExecutor`'s side, the answered and result notices, the counts and `Sweep`.
- **"Pending" in the overlap rows** covers a request that is `approved` while the incident is still `awaiting_approval`. Its outcome is still on its way, so a rejection that arrives first must not lose the approval. This is the simplest reading consistent with AD-11 (the row is the truth). Spine candidate below.
- **Row checks make repeats harmless.** An outcome whose row does not show it is refused, and the `FixResult`'s own request is never counted as waiting, so an `Execute` that `FixExecutor` would refuse is never sent.
- **An accepted event publishes even when the state stays the same.** The payload's `requests` reads the rows live. A refused event publishes nothing.
- **The variant is cleared when the state leaves `open`.** `Fallback` keeps the fallback flag.
- **The result codes:** `closed`, `not_found`, `not_allowed`, `not_quiet`, `unknown_command` and `failed`, with `Data` `{state, openVariant}`. The messages are owner parameters, as `WatchOps` has them (5.9 and 6.4 write the words users see).
- **A repeated `dismiss` with the same key** finds the incident closed and answers `not_allowed` with state `closed`. The row is the idempotency, so no key is stored.
- **`closeForReplay` and `closeQuiet` take no session check** (no `CommandsIn` route). A `dismiss` from a session that is not a recipient answers `not_found`, like a missing incident (6.4's 404).
- **`QUIETSECONDS` is 900, a parameter** (PRD `[ASSUMPTION: 15 minutes]`). Like `Checks`, `IncidentManager` re-checks `LastAt` itself, so a failure that arrived meanwhile changes nothing.
- **A refused async event logs an info line, not a warning:** the hold's repeated outcomes are expected (inference). A failed `Execute` send is a warning.
- **`STUB` goes,** and an unknown request class is a 5001 error.
- **`Execute`'s SQL table is `FixExecute`.** Measured: `$SYSTEM.SQL.IsReservedWord("Execute")` is 1 on slot A (build 154), and none of `FixResult`'s property names is reserved.

**(inference), to be pinned by the tests:** a shadow instance's `OnRequest` returns the `CommandResult` in `response` without a primary header; the hold may deliver an outcome twice (task, then timer); `Approval.Raise` with the probe sink needs no `BridgeSink`.

**Footprint extensions** (none contended):
- `Fix/Msg/*.cls` (the Fix area);
- `Test/Install/Production.cls` (the Lane A oracle row);
- `Test/Core/CommandsInProduction.cls` (one assertion that this story breaks, Rule 19).

**Spine candidates (Rule 20, for the lead):**
- a Consistency Conventions row "Incident commands": the result codes, `Data`, the session rule and `QUIETSECONDS`;
- an AD-15 clarification: "pending" includes an approved request whose outcome has not arrived, and repeated outcomes are refused by the row;
- the row "SQL reserved words" extended to table names (`SqlTableName`).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/../.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=5 stage=implement'`. Run one command per call, each with `timeout: 600000`. Never put two IRIS test runs in one message, and chain nothing after a shard part.

**Commands:**
- (loop) `<lane> OCUTALON_RUN_TAG=e5s5iw ci/warm.sh up` -- once per stage. Expected: READY.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s5iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Watch.Transitions`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Tell`, `OcuTalon.Test.Watch.Settle`, `OcuTalon.Test.Bridge.CodeRules`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Install.Production` -- expected: `CLASS … passed`.
- (loop) `<lane> OCUTALON_RUN_TAG=e5s5i ci/iris.sh class <Class>`, fresh, one call per class, because the production item `IncidentManager` changed: `OcuTalon.Test.Watch.Closing`, `OcuTalon.Test.Watch.Notices`, `OcuTalon.Test.Watch.Diagnose`, `OcuTalon.Test.Watch.Incidents`, `OcuTalon.Test.Core.CommandsInProduction`, `OcuTalon.Test.Bridge.Approval` -- expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e5s5i ci/iris.sh shard lane-a --part 1/2`, then, in its own call, `... --part 2/2`. Record each part's time. If a part takes more than 480 s, run `--part k/3` instead (three calls) and record those times.
- (once) `<lane> OCUTALON_RUN_TAG=e5s5i ci/iris.sh shard lane-b` -- `Test.Core`, `Test.Data`, `Test.Web` and `Test.Live` are in it. Expected: passed.
- (once) `bash ci/checks.sh` -- expected: all pass (class rules, storage blocks, boundaries).
- (once) `<lane> OCUTALON_RUN_TAG=e5s5iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s5i ci/iris.sh teardown`.

**Shared surfaces:**
- **`IncidentManager` answers what was "not implemented":** `Test.Core.CommandsInProduction` (`not_built` becomes `closed`; updated), `Test.Bridge.Approval` (outcomes sent to `IncidentManager`: still handled), and `Test.Install.Production` (the stub oracle; updated).
- **Incidents now close:** every test that reads an incident's `state`, `ClosedAt` or the `incident` events of a watch session (`Test.Watch.*`, `Test.Web.Api`; the contended ones are run, never changed).
- **The `lane-a` class list:** three new classes, run in parts.
- Every test added or changed passes on a fresh environment, in either order.

**Pinning mutations to apply** (Rule 19). The implement stage applies each one, observes red, reverts byte-identically and records it here.

| AC or row | Mutation | Expected red |
|---|---|---|
| AC 1 | `dismiss` is accepted in `awaiting_approval` | `Transitions.TestRefusedMoves`, `Lifecycle.TestDismiss` |
| Overlap, pending | `pending` ignores an `approved` request while the incident is `awaiting_approval` | `Transitions.TestRows`, `Lifecycle.TestApprovalOutcomes` |
| Finished | `finished` ignores `waiting` | `Transitions.TestRows`, `Lifecycle.TestFixResults` |
| Earliest | the latest waiting request gets the `Execute` | `Lifecycle.TestFixResults` |
| Repeats | an outcome is accepted whatever its row shows | `Lifecycle.TestRefusedEvents` |
| AD-26 | `SendExecute` clears the session | `Lifecycle.TestApprovalOutcomes` |
| Quiet close | `closeQuiet` closes an `open` incident with demo mode on | `Lifecycle.TestCloseQuiet` |
| `not_quiet` | the `LastAt` check is dropped | `Lifecycle.TestCloseQuiet` |
| Recipient | `dismiss` skips `Recipients` | `Lifecycle.TestDismiss`, `Closing.TestDismissThroughCommandsIn` |
| Publish | an accepted move publishes nothing | `Lifecycle.TestEveryChangePublishes`, `Closing` |
| Close | `ClosedAt` is left empty | `Lifecycle.TestDismiss`, `Lifecycle.TestPurge` |
| AC 4 | `rejected` maps to `expired` | `Closing.TestRejectThroughTheHold` |
| AC 5 | `Find` takes `closed` incidents | `Closing.TestDismissThroughCommandsIn`, `Incidents.TestClosedOpensNew` |
| Purge | the cutoff moves by one day (`daysToKeep - 1`), or `open` rows are deleted too | `Lifecycle.TestPurge` |
| Fix messages | `FixResult` loses `Skipped` | `Lifecycle.TestFixMessages` |
| AC 7 | `STUB` is kept | `Install.Production.TestStubsAnswer` |
| Notice | `Notice` sets `fixing` | `Tell.TestNoticeToEachRecipient` |

**Mutations applied (Rule 19, implement stage; each reverted byte-identically, checked with `cmp` against a backup made first):**

- mutation: `dismiss` accepted in `awaiting_approval` (Transitions) -> `Transitions.TestRefusedMoves`, `Lifecycle.TestDismiss` red
- mutation: `pending` ignores an `approved` request while `awaiting_approval` (`Facts`) -> `Lifecycle.TestApprovalOutcomes` red (`Transitions.TestRows` cannot see it: the fact is read in `IncidentManager`, not in the table; the table-side twin, `rejected` ignoring `pending`, turns `Transitions.TestRows` red)
- mutation: `finished` ignores `waiting` (Transitions) -> `Transitions.TestRows`, `Lifecycle.TestFixResults` red
- mutation: the latest waiting request gets the `Execute` (`Facts`) -> `Lifecycle.TestFixResults` red
- mutation: an outcome is accepted whatever its row shows (`Outcome`) -> `Lifecycle.TestRefusedEvents` red
- mutation: the `Execute` clears the session (`Execute` sets `%SessionId` to "") -> `Lifecycle.TestApprovalOutcomes` red
- mutation: `closeQuiet` closes an `open` incident with demo mode on (Transitions) -> `Lifecycle.TestCloseQuiet` red
- mutation: the `LastAt` check is dropped (`Command`) -> `Lifecycle.TestCloseQuiet` red
- mutation: `dismiss` skips `Recipients` (`Command`) -> `Lifecycle.TestDismiss`, `Closing.TestDismissThroughCommandsIn` red
- mutation: an accepted move publishes nothing (`Move`) -> `Lifecycle.TestEveryChangePublishes` (and six more Lifecycle tests), `Closing.TestDismissThroughCommandsIn` and `Closing.TestRejectThroughTheHold` red
- mutation: `ClosedAt` is left empty (`Move`) -> `Lifecycle.TestDismiss`, `Lifecycle.TestCloseForReplay`, `Lifecycle.TestPurge` red
- mutation: `rejected` maps to `expired` (Transitions) -> `Closing.TestRejectThroughTheHold` red
- mutation: `Find` takes `closed` incidents (SQL filter and object check dropped) -> `Closing.TestDismissThroughCommandsIn`, `Incidents.TestClosedOpensNew` red (the first version of the Closing test sent a text of another pattern, so the mutation stayed green; the second batch now has the first one's text)
- mutation: the cutoff moves by one day (`daysToKeep - 1`) -> `Lifecycle.TestPurge` red; `Purge` selecting and deleting every incident older than the cutoff, `open` ones included -> `Lifecycle.TestPurge` red
- mutation: `FixResult` loses `Skipped` -> `Lifecycle.TestFixMessages` red
- mutation: `STUB` is kept -> `Install.Production.TestStubsAnswer` red
- mutation: `Notice` sets `fixing` -> `Tell.TestNoticeToEachRecipient` (and `TestFailedSendLeavesTheOthersTheirNotice`, `TestNobodyToNotice`) red
- mutation: `DemoMode` gives 0 (review pass; the item's own reading of `demo.mode`) -> `Lifecycle.TestCloseQuiet` red
- mutation: `FIXEXECUTOR` names an item the production does not have -> `Lifecycle.TestExecuteTarget` red
- mutation: an unknown request class answers OK (`OnRequest`) -> `Lifecycle.TestUnknownRequest` red
- mutation: `Result` ignores `Interrupted` -> `Lifecycle.TestFixResults` red
- mutation: a failed `SendExecute` is not logged (`Execute`) -> `Lifecycle.TestExecuteSendFails` red
- mutation: `dismiss` accepted on a `closed` incident (Transitions) -> `Lifecycle.TestRepeatDismiss`, `Lifecycle.TestDismiss` red
- mutation: `closeForReplay` accepted on a noticed `open` incident (Transitions) -> `Lifecycle.TestCloseForReplay` red
- mutation: `dismiss` skips the `Recipients` check (`Command`) also turns `Lifecycle.TestInstanceDismiss` red
- mutation: `Execute` loses `SqlTableName = FixExecute` -> `Test.Data.Tables.TestSqlNames` red (AC 7, reserved-word half)
- mutation: `Transitions` deletes an incident row (`%DeleteId`) -> `Test.Bridge.CodeRules.TestOnlyIncidentManagerWritesIncidents` red (AC 7, only-writer half)

**QA stage (Rule 19; each mutation reverted byte-identically, checked with `cmp` against a backup made first, and `git status --short` unchanged):**

Audit: every row of the I/O matrix and every AC has a pinning test in the table above. The QA pass found five assertions that no test could fail on and added tests for them (files marked `(QA)` below):
- the facts rule "an incident's requests are the entries of `RequestRefs` whose row exists and names the incident" (the `IncidentRef` check of `Facts`) was unpinned: `Lifecycle.TestOnlyTheIncidentsOwnRequestsCount` (QA);
- `Apply` quits on the error of `Move` before it sends an `Execute`, and `Command` answers `failed`: `Lifecycle.TestFailedSaveChangesNothing` (QA), with the probe's `Move` failing (`IncidentProbe.FailMove`; a test-side override, no product seam; a real failed `%Save` needs a row that another process locks);
- "the line names the incident, the event and the state" was counted but not read: `Lifecycle.TestRefusedLineNamesIncidentEventAndState` (QA);
- `Purge` with more days than the calendar has: `Lifecycle.TestPurgeFarCutoff` (QA);
- the real `SendExecute` header (the gap closed as DW-281) is reachable without a seam: `Closing.TestApproveSendsExecuteToFixExecutor` (QA) approves a real request through the real hold and reads the `Execute` header that `IncidentManager` sends to the `FixExecutor` stub (it stays a header with a refused handling; no answer is wanted), with the session and SuperSession. The handler's own behaviour is still Story 7.3's.
- Still without a test, by cause: the `failed` answer of a failed `Session.Recipients` read of `Dismiss` (it needs a process without %All, so an IRIS user made for the purpose, which is a privilege change: see `Test.Watch.Tell`).

- mutation: `Facts` drops the `IncidentRef` check -> `Lifecycle.TestOnlyTheIncidentsOwnRequestsCount` red
- mutation: `Apply` ignores the error of `Move` -> `Lifecycle.TestFailedSaveChangesNothing` red
- mutation: `Drop` logs the event where the state belongs -> `Lifecycle.TestRefusedLineNamesIncidentEventAndState` red
- mutation: `Purge` loses the `day < 0` guard -> `Lifecycle.TestPurgeFarCutoff` red (an exception)
- mutation: `Execute` does not set the incident's trace session -> `Closing.TestApproveSendsExecuteToFixExecutor` red (the real header's `sessionId`)

**Code review (Rule 19; each mutation reverted from a backup, checked with `cmp`, and `git status --short` and `git diff --stat` unchanged; warm `e5s5cw`, fresh `e5s5c`):**

- mutation: `Command`'s `failed` answer gives the object without reading the row again (AC 2, the "Incident commands" row's `Data`) -> `Lifecycle.TestFailedSaveChangesNothing` red
- mutation: `Facts` counts the event's own request (`|| (ref = own)` dropped) -> `Lifecycle.TestFixResults` red (the own request that still reads approved)
- mutation: `Purge` keeps one day too many (`- daysToKeep - 1`) -> `Lifecycle.TestPurge` red (the incident closed an hour before the cutoff)
- mutation: `Settle.Quiet` takes 900 seconds as quiet (`>` to `'<`) -> `Transitions.TestQuiet` red
- mutation: `SendExecute` asks for an answer (`SendRequestAsync(..., 1)`) -> `Closing.TestApproveSendsExecuteToFixExecutor` red ("no answer comes back")
- mutation: `Execute` clears the SuperSession for the send -> `Closing.TestApproveSendsExecuteToFixExecutor` red ("with the SuperSession kept")

Code review runs: warm `Test.Watch.Lifecycle`, `Transitions`, `Tell`, `Test.Bridge.CodeRules` passed after the reverts on the same stack; fresh `Test.Watch.Closing` (29 s test, 104 s with the start) and `Test.Watch.Notices` passed; `bash ci/checks.sh` passed. Both tags are torn down.

QA files (`(QA)`): `src/ocutalon/cls/OcuTalon/Test/Watch/Lifecycle.cls` (four tests and two helpers added), `src/ocutalon/cls/OcuTalon/Test/Watch/Closing.cls` (one test added), `src/ocutalon/cls/OcuTalon/Test/Watch/IncidentProbe.cls` (`FailMove` and a `Move` override). No new class.

QA runs: warm (`e5s5qw`): `Test.Watch.Lifecycle`, `Test.Watch.Tell`, `Test.Bridge.CodeRules` passed; fresh (`e5s5q`): `Test.Watch.Closing` passed (27 s test, about 110 s with the start); `bash ci/checks.sh` passed.

**Runs (stage loop):** warm (`e5s5iw`, up in 80 s): `Test.Watch.Transitions`, `Lifecycle`, `Tell`, `Settle`, `Test.Bridge.CodeRules`, `Test.Data.Tables`, `Test.Install.Production` passed. Fresh (`e5s5i`): `Closing` (27 s test, 100 s with the start), `Notices`, `Diagnose`, `Incidents`, `Test.Core.CommandsInProduction`, `Test.Bridge.Approval` passed.

**Beyond the spec's file list (needed to keep the tree green):** `Test.Core.CommandsInProduction.TestStubOwnersAnswerPlainEnglish` also sent a `Dismiss` to `IncidentManager` and expected `not_built`; that row is removed (the class doc follows), because the owner is no longer a stub. Method names of `IncidentManager` that the probe or `Ens.BusinessProcess` already use (`Answer`, `Refuse`, `Reply`) were avoided (`Verdict`, `Drop`). `IncidentManager.Purge(daysToKeep)` overrides the internal `Ens.BusinessProcess.Purge` ClassMethod with a different signature, as the spec requires; the framework calls only `Ens.BusinessProcess.Purge` on the base class.

## Auto Run Result

Status: done
Blocking condition: none

Summary: the incident lifecycle (AD-15) is built. `Watch.Transitions.Next` is the one pure table; `IncidentManager` applies it to the notice step, the `dismiss`, `closeForReplay` and `closeQuiet` commands (answered synchronously), `ApprovalOutcome` and `FixResult`; an accepted move saves, publishes the full `incident` view and, where the table says so, sends `Fix.Msg.Execute` in the incident's trace session. `STUB` is gone; any other request class is a 5001 error naming the class. `IncidentManager.Purge(daysToKeep)` is added. The chat dismiss tool is Story 5.9 (R1).

Files changed (all under `src/ocutalon/cls/OcuTalon/`):
- `Watch/Transitions.cls` (new): the table.
- `Watch/IncidentManager.cls`: handlers, facts, `Move`, `SendExecute`, `DemoMode`, `Purge`; `STUB` removed.
- `Watch/Settle.cls`: `Quiet`.
- `Fix/Msg/Execute.cls` (new, table `FixExecute`), `Fix/Msg/FixResult.cls` (new).
- `Test/Watch/Transitions.cls`, `Lifecycle.cls`, `Closing.cls` (new); `IncidentProbe.cls`, `Case.cls` (changed).
- `Test/Install/Production.cls` (oracle row `stub` 0), `Test/Core/CommandsInProduction.cls` (the dismiss assertion, and the stub-owner row for a dismiss, removed).

Review: 28 findings across four layers - high 0, medium 5, low 11, false 12. Patches applied (grouped): `TestPurge` skips when it would delete rows it did not make; `RealDemoMode` pins the item's own reading of `demo.mode`; `TestExecuteTarget` pins the `FixExecutor` item name; `TestUnknownRequest` pins the 5001 error; the `failed` outcome is in the class doc; a stray tab is removed; ten `mutation:` lines are demonstrated and written. Deferred: one (the real Execute header, for Story 7.3). Every rejected finding and its reason is in the triage log.

Follow-up review recommended: true. Three medium entries were patched (`TestPurge` hermeticity, the `SendExecute` target, the `DemoMode` reading). The unverified risk: a real `Execute` message header (target, session, SuperSession) is not observed until Story 7.3's handler exists.

Verification: warm (`e5s5iw`) `Watch.Transitions`, `Lifecycle`, `Tell`, `Settle`, `Bridge.CodeRules`, `Data.Tables`, `Install.Production` passed; fresh `Watch.Closing`, `Notices`, `Diagnose`, `Incidents`, `Core.CommandsInProduction` and `Bridge.Approval` passed. The shards ran after the implement pass: `lane-a` part 1/2 (33 classes, 396 s) and part 2/2 (32 classes, 408 s), `lane-b` (42 classes, 115 s), `bash ci/checks.sh` passed. After the review patches (one Lifecycle test file, one tab and one doc line in `IncidentManager`) `lane-a` part 2/2 (32 classes, 413 s) and `lane-b` (42 classes, 112 s) ran again and passed; part 1/2 (Agent and Bridge classes, no Watch class) was not rerun, because no file it covers changed in behavior. All stacks are torn down.

Residual risks: the real Execute header (deferred); the `failed` answers of `Command` have no seam to force them (as Story 5.3's recipients read); `Purge` has no caller until Story 30.2; an `Interrupted` run resolves the incident by the spec's own rule.
