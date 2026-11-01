---
title: 'Ask OcuTalon what happened earlier, and it tells you from its own records'
type: 'feature'
created: '2026-10-31'
status: 'done'
baseline_revision: '7ca64df2ad1d2d3c0772d3a375d860af268dcb2c'
baseline_commit: '7ca64df2ad1d2d3c0772d3a375d860af268dcb2c'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred:
  - summary: >-
      Eval.Report TOOLCLASSES lists only WatchTools and ReminderTools, so Eval.Report.ReadOnly("recent_activity") is false and an eval injection case whose Chat turn calls recent_activity is scored as having acted.
    evidence: |-
      Eval/Report.cls L83 TOOLCLASSES = "OcuTalon.Tools.WatchTools,OcuTalon.Tools.ReminderTools"; ReadOnly reads READONLY<NAME> from those classes only; Test/Eval/Report.cls TestReadOnly has no recent_activity. AC4 of Story 5.13 says no Eval file changes, so this story cannot fix it. The fix is OcuTalon.Tools.RecentActivity added to TOOLCLASSES and recent_activity added to TestReadOnly's read-only list.
    location: >-
      src/ocutalon/cls/OcuTalon/Eval/Report.cls:83
    severity: medium
  - summary: >-
      Chat's INSTRUCTIONS give explicit per-tool guidance (check_status, dismiss_incident, list_productions) but none for recent_activity, so whether the real model calls it for "What was that failure earlier?" rests on the tool description alone.
    evidence: |-
      Agent/Chat.cls INSTRUCTIONS L53-61 name the other watch tools and when to call them; Chat.cls is outside this story's footprint (orchestrator ruling) and the mock scripts the tool call, so no test shows the real model's choice. Settled by one run of live:demo-path or a real-model eval case asking about the earlier failure, or by a one-line Chat instruction owned by a story that may edit Chat.cls.
    location: >-
      src/ocutalon/cls/OcuTalon/Agent/Chat.cls:53
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** In the owner's walk-through of the online demo, the visitor asked OcuTalon about the failure it had just fixed, and OcuTalon could not recall it. The incident card is an `IncidentManager` notice, not a chat turn, so it never enters Chat's AI session. Chat's tools cannot read past incidents, and `check_status` gives only the latest check, which reads "passed" once the fix has run. The online demo stays gated until this is fixed.

**Approach:** Add one read-only, trusted-output tool, `recent_activity`, in its own class `OcuTalon.Tools.RecentActivity`, and list it in the Watching toolset. It reads the session's own records through the ownership API: at most 5 incidents from the last 24 hours, newest first. Each incident carries only values that code built or checked, and the times are shown the way the catalog shows them. With nothing in 24 hours, the answer says so plainly and claims nothing about health.

## Boundaries & Constraints

**Always:**
- Declare the classification as class parameters of the tool class, as `WatchTools` does: `CLASSIFICATIONRECENTACTIVITY` safe, `READONLYRECENTACTIVITY` 1, `TRUSTEDOUTPUTRECENTACTIVITY` 1, and `STEPLABELRECENTACTIVITY`. The gate reads these itself (`Gate.ClassificationOf` → `StepBuffer.ToolParameter`), so `Gate.cls` is not edited.
- Read every row through `OcuTalon.Data.Ownership` (`RecentIncidents`, `IncidentApprovals`, `Checks`), plus the Lane A row readers `FailureGroup.OfIncident` and `FixRun.OfRequest`. Take the session from the bridge context (`CommandCall.Session`), never from an argument.
- Every string in the answer comes from one of these: a fixed value list (the state, the cause category, the fix kind, the approval answer, the channel), a time formatted by `Data.Time.ForMessage`, an instance-defined name (a production's display name, an item name, a property name that the fix check verified), or a code-written constant.
- Return through `..Return` as a dynamic object (Tools.Result). Write nothing and submit nothing.
- Tests are self-contained: they create and delete their own Incident, FailureGroup, ApprovalRequest and FixRun rows and their own sessions.

**Never:**
- The cause sentence (`Incident.Cause`), `FixSummary`, `SampleError`, a group's `ErrorPattern` or `ErrorSummary`, `FixRun.Reason`, the request's `DryRun`, `ToolArguments` or `AnsweredBy`, or any message body or header text.
- Naming a bridge approval class in the tool's code (`Test.Bridge.CodeRules` GOVERNANCE). Rows come only through `Ownership.IncidentApprovals`.
- Edits to `Agent/Chat.cls`, `Tools/ReminderTools.cls`, `Test/Tools/CommandsDouble.cls`, Lane B classes, `Gate.cls`, or any other Epic 30 or Epic 13 file, apart from the two the blocking question names. No `docker/tests/test-*.sh` script, no new CI unit, no `ci/mock` file outside `scenarios/A/`. No reminders in the output.
- A real model key. Every model call in the tests goes to the mock.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Demo path, resolved | Session S has one resolved incident noticed 10 min ago: Count 50, Element `OrderDate`, group item `OrdersFromPartner`, one request in state done, answered `approve` on `web`, with fix field `OrderDate`, and a FixRun that ended with Resent 50, Completed 50, FailedAgain 0 | `{"ok":true,"hours":24,"incidents":[{"production":"Orders","item":"OrdersFromPartner","count":50,"firstFailure","lastFailure","element":"OrderDate","causeCategory":"data_format_change","fixKind":"repair_resend","state":"resolved","approvals":[{"answer":"approved","channel":"web","answered","fix":{"resent":50,"wentThrough":50,"failedAgain":0,"finished":true}}]}]}`. Each time is `ForMessage`, with " ET" on the online demo | No error expected |
| Poisoned free text | As above, but Cause, FixSummary, SampleError, ErrorPattern, ErrorSummary, Reason and DryRun all hold `ZZPOISON` sentences | The answer's JSON holds no `ZZPOISON`, and every object has exactly the pinned keys | No error expected |
| Element not verified | Element is a sentence that matches neither a request's fix field nor a group's ItemName | `element` is "" | No error expected |
| Approval states | Requests in each APPROVALSTATE value | pending → `waiting`; approved, executing, done, failed → `approved`; rejected → `rejected`; expired → `expired` (time = ExpiresAt); cancelled → `cancelled`. A channel outside Msg.Enum CHANNEL → "" | No error expected |
| No run, or a run still going | The request has no FixRun, or a run with EndedAt empty | `fix` is null, or `finished` is false with the counts so far | No error expected |
| Closed | State closed (by Dismiss, closeQuiet or closeForReplay) | `state` is `closed` | No error expected |
| Window and order | 7 incidents of S: 6 active within 24 hours, 1 last active 25 hours ago | The 5 newest by NoticedAt; the 25-hour one is never among them | No error expected |
| Nothing in 24 hours | S's only incident was last active 25 hours ago, or S has none | `{"ok":true,"hours":24,"incidents":[],"message":NONE}`. NONE holds no reserved sentence and no banned phrase of `ReplyGuard` | No error expected |
| Another session | Session B's incident; online demo on, with an instance incident of watched Orders | S never sees B's incident. With the online demo on, S does not see the instance incident; on a local install, S sees it while S watches Orders (AD-4) | No error expected |
| No session | No context, owner eval, or an empty ItemId | `CommandCall` NOSESSION, and nothing is read | Refusal answer |
| Unreadable | `RecentIncidents` gives an error status | `{"ok":false,"message":NOTREAD}` | Refusal answer |
| Chat turn (Integration AC) | The demo-path rows; "What was that failure earlier? [[mock:recent-activity]]" through WebChatIn | The turn is done with no fallback and Tainted 0. Its one tool step "Reading recent activity" is ok. The Chat agent's second request carries the tool result with count 50, element OrderDate, approved on web, wentThrough 50, state resolved, and no `ZZPOISON`. The reply holds no all-clear (the guard removed the scenario's), and nothing else of the reply is removed | No error expected |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/` unless they say otherwise.

- `Tools/Watching.cls` L1-4 (the class doc), L11 (the description), L12-16 (the tools): add `<Tool Name="recent_activity" Class="OcuTalon.Tools.RecentActivity" Method="RecentActivity"/>` and `DependsOn` the new class.
- `Tools/WatchTools.cls` is the sibling to follow:
  - the parameter naming L44-82;
  - `CheckStatus` L148-165: the doc comment is the model's description, and the method has the Session-then-read shape.
- `Tools/WatchAnswers.cls` is read-only:
  - `ResolveIncident` L109-145 shows how to read `Ownership.Incidents` and build an entry with `ForMessage`;
  - `WatchNames` L177-187 is private (the display names of the session's watches);
  - `Checked` L262-270 shows the time formatting.
- `Tools/CommandCall.cls`: `Session` L66-73 and NOSESSION L23. `Tools/Result.cls`: `Return` L35.
- `Tools/Names.cls`: add `RECENTACTIVITY = "recent_activity"` and append it to `RELEASE1`. The mock's `constants.test.mjs` L48-52 reads the names from this file.
- `Data/Ownership.cls`, Lane B, read-only:
  - `RecentIncidents` L294 (noticed incidents, newest NoticedAt first; on a local install the instance incidents of watched productions, and never on the demo);
  - `IncidentApprovals` L593 (any state, by RaisedAt);
  - `Checks` L274.
- Rows, read-only:
  - `Data/Incident.cls`: Production L18, State L21, NoticedAt L27, Count L30, FirstAt and LastAt L36-39, CauseCategory L48, Element L51 (model-written), ClosedAt L69, RequestRefs L81;
  - `Data/FailureGroup.cls`: `ItemName` L13, `OfIncident` L57;
  - `Data/FixRun.cls`: `OfRequest` L62, EndedAt L34, Resent, Completed and FailedAgain L41-45;
  - `src/bridge/.../Bridge/Data/ApprovalRequest.cls`: State L24, ExpiresAt L48, AnsweredChannel L54, AnsweredAt L60, FixKind L69, FixParameters L72 (JSON with `field`).
- `Msg/Enum.cls`: INCIDENTSTATE L18, APPROVALSTATE L24, CHANNEL L36.
- Times:
  - `Data/Time.cls`: `ForMessage` L88 (no suffix), `NowUtc`, `AddSeconds` L42;
  - the catalog's label rule: `Msg/Catalog.cls` `SlotText` L159-164 (private), which adds " ET" when online;
  - `Watch/Reader.cls` `OnlineDemo` L132.
- Why the element needs a check:
  - `Watch/Msg/DiagnosisPayload.cls` L37-38: ElementAtFault is free text from the model, up to 128 characters;
  - `CheckFix`: `fixParameters.field` must be a key of the sample body;
  - `Watch/Reader.cls` L342-356: those keys are the compiled property names of the body class.
- Gate, read-only:
  - `src/bridge/.../Policy/Gate.cls` `ClassificationOf` L176-195 and `Flag` L340;
  - `Bridge/Adapter/StepBuffer.cls` `ToolParameter` L167.
- Tests whose fixed lists change (shared surfaces), not contended (free to extend):
  - `Test/Watch/Tools.cls` `TestDeclarations` L59-90: five tools, all from WatchTools;
  - `Test/Agent/Runners.cls` `REMINDERTOOLS` L73, the doc L43-45, `TestToolInventory` L317-328;
  - `Test/Agent/Constants.cls` L6, L27 and L44 (11 names).
- Tests whose fixed lists change, **contended: one-name append only** (orchestrator ruling):
  - `Test/Tools/Reminders.cls` L263: `TestSetRelative`'s alphabetical `ToolNames` list (Epic 11);
  - `Test/Watch/Turns.cls` L63: the alphabetical offered-tools list (Epic 11's hunk sits at L64);
  - `Test/Agent/Instructions.cls` the doc L23-24 ("five tools (...)") and the `expected` `$ListBuild` at L205; the `arguments(...)` lines L206-212 are optional per tool (`If '$Data(arguments(tool.name)) Continue`, L226), so none is added;
  - `Test/Bridge/Gate.cls` `TRUSTEDTOOLS` L114 and `READONLYTOOLS` L116, which `TestFlagsAreListed` (L1346-1362) compares as sorted lists, so an end-append is enough.
- Reuse for the tests:
  - `Test/Watch/Case.cls`: `Begin` L559, `SetOnlineDemo` L369, the fixture sessions, and the Incident and FailureGroup clean-up;
  - `Test/Checks/Turns.cls`: the pattern of a turn through WebChatIn with a triage `tellnow` reply (`Ask` L115, `AssertNoAllClear` L130, `AssertToolStep` L164);
  - `Test/Agent/RunnerFixture.cls`: `ToolResults` and `ToolNames`;
  - the scenario shape: `ci/mock/scenarios/A/checks-false-all-clear.json`;
  - `Checks/ReplyGuard.cls` RESERVED L19 and BANNED L22.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls` (new, extends `OcuTalon.Tools.Result`). It holds the four parameters, NONE, NOTREAD, HOURS 24, MAX 5 and READMAX 100, and `RecentActivity()`:
  1. Run `Session`; a refusal is returned as it is.
  2. Read `RecentIncidents(owner, READMAX)`; an error answers NOTREAD.
  3. Keep the incidents whose latest of NoticedAt, LastAt and ClosedAt is at or after `AddSeconds(NowUtc(), -86400)`, and take the first MAX.
  4. Build each entry as the matrix says:
     - the production is the session's watch display name, else the row's Production;
     - the item is the first group's ItemName;
     - the element is kept only when it exactly equals a request's fix `field` or a group's ItemName, else "";
     - the approvals come from `IncidentApprovals`, with the fix from `FixRun.OfRequest`;
     - each time is `ForMessage(utc)` plus " ET" when `Reader.OnlineDemo()`.
  5. An empty list gets the message NONE.

  The method's doc comment is the model's description. It says when to call the tool (the user asks about earlier failures, incidents, approvals, fixes or what happened), what each member means, to say an empty list plainly, and never to say that everything is fine. The class doc states the trusted-output contract.
- `src/ocutalon/cls/OcuTalon/Tools/Watching.cls`: the new `<Tool>` line, DependsOn both providers, and the description and doc name the sixth tool.
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls`: RECENTACTIVITY, added to RELEASE1.
- `ci/mock/scenarios/A/recent-activity.json` (new), with the marker `recent-activity`. The replies are:
  - the triage `tellnow`;
  - a `toolUse` of `recent_activity` with `{}`;
  - the text "Earlier, 50 orders failed on the OrdersFromPartner item because of OrderDate. You approved the fix on the web, and all 50 went through. Everything is fine now."
- `src/ocutalon/cls/OcuTalon/Test/Tools/RecentActivity.cls` (new, extends `Test.Watch.Case`). It covers the matrix rows Demo path, Poisoned, Element, Approval states, No run, Closed, Window, Nothing, Another session, No session and Unreadable, through `Begin` and a direct call. Two more tests:
  - `TestClassification`: `Gate.ClassificationOf("OcuTalon.Tools.RecentActivity","recent_activity")` is `{"classification":"safe","readOnly":1,"trustedOutput":1,"by":"code"}`, and the Watching toolset offers the tool from that provider;
  - `TestDescription`.

  It deletes its own ApprovalRequest and FixRun rows.
- `src/ocutalon/cls/OcuTalon/Test/Tools/RecentActivityTurn.cls` (new, extends `Test.Watch.Case`): the Integration AC row, in the `Test.Checks.Turns` pattern, with the fixture's LastAt 2 minutes old so that closeQuiet leaves it alone. It cleans up its turns and rows.
- Non-contended shared-surface updates: `Test/Watch/Tools.cls` (6 tools; recent_activity comes from RecentActivity with ("safe",1,1,"Reading recent activity","","")), `Test/Agent/Runners.cls` (the inventory and its doc) and `Test/Agent/Constants.cls` (12 names in `OcuTalon.Tools.Names`).
- Contended lists, **one-name append only** (orchestrator ruling). Each file gains the one name on the named line(s); **nothing else in these four files changes**:
  - `Test/Tools/Reminders.cls` L263: `recent_activity` inserted in its alphabetical place (after `list_reminders`);
  - `Test/Watch/Turns.cls` L63: the same insertion;
  - `Test/Agent/Instructions.cls`: `##class(OcuTalon.Tools.Names).#RECENTACTIVITY` appended to the `expected` list at L205, and the doc L23-24 names the sixth tool, recent_activity (Story 5.13). No `arguments` line is added;
  - `Test/Bridge/Gate.cls`: `,OcuTalon.Tools.RecentActivity:recent_activity` appended to `TRUSTEDTOOLS` and to `READONLYTOOLS`.

  On Reminders L263 and Turns L63, the assertion message on the same line keeps its count true (Decided in-stage).

**Acceptance Criteria:**
- **AC1.** Given the Chat agent, when its tools are discovered, then:
  - Watching offers `recent_activity` from `OcuTalon.Tools.RecentActivity` once;
  - the gate classifies it safe, read-only and trusted output by code;
  - its description names earlier failures, incidents, approvals, fixes and what happened.
- **AC2.** Given the matrix rows, when `recent_activity` runs in a session's turn, then each row's output holds, and no output holds a cause sentence, a message text or another session's incident.
- **AC3.** Given the demo path's records, when the user asks "What was that failure earlier?", then:
  - the Chat agent reads the count, the element, the approval and the fix result from the tool;
  - the turn stays untainted;
  - the reply holds no all-clear.
- **AC4.** Given the change, when it merges, then:
  - CI is green on every workflow;
  - `Test.Eval.Run` passes with no Eval file changed;
  - the diff is the files above.

### Review Findings

Code review 2026-11-01 (`bmad-code-review`, full mode, four layers; 30 rows, 9 entries after grouping: high 1, med 4, low 5 counted below; 14 rejected).

- [x] [Review][Patch] HIGH (Rule 6, spine Conventions "Tool classification" `recent_activity` clause: "an element at fault shown only when it exactly matches the approved fix's field or an item name"): `Element` accepted the fix field of any request, rejected, pending, expired and cancelled included [src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls:Element] — fixed: new `APPROVED` parameter (approved, executing, done, failed: the states whose answer is approved), and only those requests' fix field confirms the element; pinned by the new `TestElementApprovedOnly`. fix-risk low (one guard line; the demo path's request is done). Sources: blind-hunter + acceptance-auditor + edge-case-hunter.
- [x] [Review][Patch] MED (DW-517, lead directive): `Eval.Report` `TOOLCLASSES` omitted `OcuTalon.Tools.RecentActivity`, so `Eval.Report.ReadOnly("recent_activity")` was 0 and an eval Chat turn calling it was scored as having acted [src/ocutalon/cls/OcuTalon/Eval/Report.cls:83] — fixed: the one-name append (the class doc names no classes, so it is unchanged), pinned by `TestClassification` asserting `ReadOnly("recent_activity") = 1`; `Test/Eval/Report.cls` untouched. fix-risk low. Sources: all four layers.
- [x] [Review][Patch] MED (Rule 19 hermeticity): `TestNothing`'s old incident was `resolved` with LastAt 25 hours ago, which the Checks quiet sweep (every Tick, all owners) may `closeQuiet`, setting ClosedAt to now and moving it into the window [src/ocutalon/cls/OcuTalon/Test/Tools/RecentActivity.cls:TestNothing] — fixed: the fixture is `closed` with ClosedAt 25 hours ago, which the sweep never touches. fix-risk low. Source: verification-gap.
- [x] [Review][Patch] LOW: the tool description said nothing for `ok` false (NOTREAD, NOSESSION), so a model could read a refusal as "nothing recorded" [src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls:RecentActivity doc] — fixed: "When ok is false, the answer has only a message: say that the records could not be read, and say nothing about what happened." Source: blind-hunter.
- [x] [Review][Patch] LOW: the description said "channel: where it was answered; answered: when", false for an expired request (the time is ExpiresAt) and a waiting one (empty) [same doc] — fixed: "channel: where it was answered, empty when nobody answered it; answered: when it was answered, or when it expired, and empty while it waits". Source: blind-hunter.
- [x] [Review][Patch] LOW: the turn test compared only the reply's first sentences, so "nothing else of the reply is removed" (matrix, Integration AC row) was not pinned [src/ocutalon/cls/OcuTalon/Test/Tools/RecentActivityTurn.cls:TestEarlierFailureInTheChat] — fixed: the whole `ReplyText` equals KEPT plus " now." (the guard deletes the phrase only), as `Test.Checks.Turns` asserts its whole filtered reply. Sources: blind-hunter + acceptance-auditor.
- [x] [Review][Patch] LOW: `Test.Tools.RecentActivity`'s class doc left out `TestUnreadableRuns` and said only two tests need no production (TestUnreadable needs none either) — fixed, and the doc names the review's `TestElementApprovedOnly` and the Eval.Report assertion. Source: blind-hunter.
- [x] [Review][Patch] LOW (Rule 19): AC3's tool-result and no-all-clear assertions had no observed red — closed in-pass: two mutations recorded under Verification (Review). Source: verification-gap.
- [x] [Review][Defer] MED (Rule 2, forced copy): `RecentActivity.WatchNames` is a line-for-line copy of the private `WatchAnswers.WatchNames` (L178-187), and `Shown` repeats the catalog's private " ET" time rule (`Catalog.cls` L159-164); the spec's Design Notes record both as forced by the footprint [src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls:WatchNames, Shown] — deferred: DW-519 `routed owner=burndown` (in-epic, fix-risk low: make both helpers public and call them). Source: reviewer (Rule 2 check).
- [x] [Review][Defer] MED unverified (DW-518): Chat's INSTRUCTIONS give no `recent_activity` guidance, and `Agent/Chat.cls` L3's class doc still lists five watching tools [src/ocutalon/cls/OcuTalon/Agent/Chat.cls:3] — deferred: occurrence appended to DW-518 (escalated, decision sheet); Chat.cls is out of footprint. Source: blind-hunter.

Rejected:
- `low` by-design: a failed request reads `approved` with no failure flag (blind) — the matrix pins failed to approved; the incident's state and the fix counts carry the outcome.
- `low`: `TestNoSession` does not prove "nothing is read" (blind) — the Session check is the method's first line; proving the order needs instrumentation in the double, more than a direct correction.
- `low`: `RecentActivityUnread` and `KIND` are not in the Tasks list (auditor) — the fix is a spec edit; both are recorded in the Review Triage Log and Auto Run Result.
- `low`: a running FixRun shows counts the product sets only at End (edge) — the test exercises the code path; a real running run shows 0 counts with finished false, which the description frames.
- `low`: a marked (restart-cut) run reads as still running (edge) — transient: Reconcile and the Sweep end a marked run.
- `false`/theoretical (edge), each real only if: an empty cutoff (Data.Time.AddSeconds of NowUtc gave ""); READMAX 100 hides an in-window incident (a session with 100 newer-noticed incidents all outside the window); a null subscript (an incident or production watch row with an empty Namespace or Production, which IncidentManager and WatchOps never write); a future timestamp (a non-code-written time); `executing` before its FixRun is saved (a read inside that sub-second window); uncapped approvals cut by Result's room (about 50 requests on one incident); an onlineDemo setting outside 0 and 1 (a hand-set value).
- theoretical (edge + verification-gap): exact-count tests assume no foreign instance incident of Orders — `Test.Watch.Case` removes every instance incident created after a class begins; real only if a stack holds an instance incident of OCUORDERS/Orders noticed within 24 hours before the class starts.

## Spec Change Log

- 2026-11-01 (lead, after implement): DW-517 (owner this story) is fixed in this story at code review: `Eval/Report.cls` `TOOLCLASSES` gains `OcuTalon.Tools.RecentActivity` (one-name append, a non-contended footprint extension), pinned by an assertion in `Test.Tools.RecentActivity` (not in `Test.Eval.Report`, which is in Epic 30's diff). AC4's "no Eval file changed" now reads: no Eval file changed except that one append. DW-518 (Chat INSTRUCTIONS) is out of footprint and goes to the decision sheet.

- 2026-11-01 (plan round 1 -> round 2): the orchestrator ruled on the round-1 intent gap (contended test lists). See Design Notes, "Orchestrator ruling (2026-11-01)". Status reset to draft for re-planning around the ruling.
- 2026-11-01 (plan round 2): applied the ruling. The four contended files are one-name appends, and the Tasks say that nothing else in them changes. Three in-stage choices are recorded (alphabetical placement, the same-line message counts, no Instructions `arguments` line). The intent gap is marked resolved, the "For the lead" items are dropped (the spine clause is written, and AD-22 is the orchestrator's), and the Shared surfaces carry no "blocked". KEEP: the rest of the round-1 plan (the intent, the matrix, the element check, the window, the times, the tests and the mutations).

## Review Triage Log

### 2026-10-31 — Review pass
- verdicts: 29 findings — high 0, medium 3, low 18, false 6, maybe-false 2
- findings:
  - `[low]` `[reject]` Blind: `WatchNames` and `KIND` copy `WatchAnswers` — the copy and its reason are recorded in Design Notes (Rule 2); a private 8-line helper outside the footprint.
  - `[low]` `[reject]` Blind: `Shown` repeats the catalog's " ET" rule — recorded copy (private one-line helper); the time tests pin the form.
  - `[low]` `[reject]` Blind: a multi-group incident shows the first group's item — the spec pins "the item is the first group's ItemName"; the fix would add an items member to the pinned keys.
  - `[low]` `[reject]` Blind: one unreadable incident turns the whole answer into NOTREAD — refusing is the honest answer and claims nothing about health (AD-28); a partial answer could read as an all-clear for the missing incident.
  - `[false]` `[reject]` Blind: `Latest` can drop an incident with malformed times — NoticedAt of a noticed incident is written by code as UTC; no reachable row has none of the three.
  - `[medium]` `[patch]` Blind: `TestUnreadable` only greps the source and the unread-approvals branch has no test — patched: private `ReadIncidents` and `ReadApprovals` seams, `Test.Tools.RecentActivityUnread` and `TestUnreadableRuns`; both NOTREAD paths now run, with a mutation for each.
  - `[low]` `[reject]` Blind: test assumptions (RaisedAt order, `Demo` LastAt before NoticedAt, `ForMessage` at two instants) — the order assertions pass and the fixtures' times are fixed UTC values, so the two `ForMessage` calls differ only across a day change by microseconds; the LastAt/NoticedAt offset is cosmetic.
  - `[low]` `[reject]` Blind: garbled `Runners.cls` header, hard-coded provider string, `Chat.cls` not mentioning the tool — the header follows the file's existing "(seven since ..., eight since ...)" form and is true; the provider string is test data; the `Chat.cls` part is the deferred Chat-instructions entry.
  - `[low]` `[reject]` Edge: null subscript when Namespace or Production is empty (`names(...)`) — the same pattern as `WatchAnswers`; an incident row always holds its production.
  - `[low]` `[reject]` Edge: null subscript in `WatchNames` for a check with empty Namespace or Production — as above; a production watch row always holds both.
  - `[low]` `[reject]` Edge: no Try/Catch around the whole method — the siblings have none and the reads return statuses; an exception reaches AI Hub's tool-error path, which tells the model the call failed.
  - `[low]` `[reject]` Edge: several groups on different items — same as the multi-group row above.
  - `[low]` `[reject]` Edge: one unreadable incident discards the good entries — same as the NOTREAD row above.
  - `[false]` `[reject]` Edge: a failed request with no run reads as approved with fix null — the matrix pins failed to approved; `fix` null says no run was recorded.
  - `[low]` `[reject]` Edge: a request with a state outside APPROVALSTATE is dropped — the state is a fixed-list property; no reachable value.
  - `[false]` `[reject]` Edge: expected times formatted at a later instant than the tool's — both format the fixture's fixed UTC times; only a day change between two calls microseconds apart could differ.
  - `[low]` `[reject]` Edge: the scenario's "Everything is fine now." leaves " now." after the guard — the spec states the guard removes the all-clear and "nothing else of the reply is removed"; the test checks the kept prefix.
  - `[medium]` `[defer]` Verification gap: `Eval.Report` TOOLCLASSES misses `RecentActivity`, so the eval scores a `recent_activity` step as an action — out of footprint and AC4 forbids an Eval edit; in the spec's `deferred:` list.
  - `[medium]` `[patch]` Verification gap: the Unreadable row is pinned only by source text and the Entry-unread path is untested — same root cause as the Blind row; patched as above.
  - `[low]` `[reject]` Verification gap: behaviours with a test but no `mutation:` line (approval mapping, fix counts, " ET", MAX, ClosedAt, NONE, description) — Rule 19 asks one demonstrated mutation per AC; AC1 to AC3 each have one, and the per-behaviour tests assert exact values.
  - `[low]` `[reject]` Verification gap: `TestWindow`'s first half cannot catch the filter — its second half and `TestNothing` do, and the 24-hour mutation turned both red.
  - `[low]` `[reject]` Verification gap: `TestAnotherSession` expects count 7 on a local install — `Test.Watch.Case` removes the instance rows it created and the class passed on a fresh stack, in the shard and warm.
  - `[low]` `[reject]` Verification gap: `TestDescription` asserts source text — the description is the AC; a text assertion is the test of a text.
  - `[maybe-false]` `[defer]` Verification gap: Chat's INSTRUCTIONS do not mention `recent_activity` — in the spec's `deferred:` list (Chat.cls is outside the footprint; settled by a real-model run).
  - `[maybe-false]` `[defer]` Intent: tool choice is scripted by the mock, so the real model's choice is unverified — same entry as the Chat-instructions defer.
  - `[false]` `[reject]` Intent: "no all-clear" comes from the existing guard — AC3 says the guard applies to the reply; the tool adds NONE and NOTREAD, tested against the guard's lists.
  - `[false]` `[reject]` Intent: the reply is canned in the mock — AC3's Given/Then reads the tool result in the second request, which the test checks.
  - `[false]` `[reject]` Intent: rows are fixtures, not production-written — the spec's Design Notes decide "the Given state is fixture rows shaped like the demo path's"; `live:demo-path` stays the full run.
  - `[low]` `[reject]` Intent: deployment and freshness of the running Chat agent are not shown — the Verification runs the turn on a fresh stack for that reason; a deploy is not this story's.

## Design Notes

**Governing ADs:**
- AD-10 rule 3 and the Tool classification convention: trusted output holds no text from outside a user's untainted turn. This is why the element is checked, and why the cause and the texts are left out.
- AD-4 and AD-13: the session scope goes through the ownership API.
- AD-28: no all-clear in the answer; the guard applies to the reply.
- AD-7: the Chat agent's toolsets.
- AD-20 (usage, cost, budgets and allowances; added by the lead at the spec gate): the tool call is one more step inside the user's own chat turn, counted with that turn's usage and inside the demo's per-session message allowance; the tool itself makes no model call. (The agents and their toolsets are AD-7.)
- AD-29 and AD-33: Lane A files; Ownership and Session are Lane B's and are only read.
- Conventions: Times (`Data.Time`) and Tool results (`Tools.Result`).
- AD-22: tests on the mock.
- No NFR is affected. The tool adds one tool definition to each Chat request, which counts under NFR-3's 10,000-token budget for results only.

**Integration ACs (Rules 1 and 2):**
- Consumed-by: the Chat agent, through the Watching toolset. The `RecentActivityTurn` test is the Integration AC (the matrix's last row), on the real Conversation, Decide and ChatAgent.
- Consumes: 5.1 Watching; 5.5 the states; 5.7 `ReplyGuard`; 5.9 the pinned trusted-output pattern; 7.2 and 7.4 the requests and the FixRun counts; Lane B's Ownership API.

**Extend, don't copy:**
- The class follows `WatchTools.CheckStatus` and `WatchAnswers.ResolveIncident`: the parameters, `Session`, the ownership reads and `ForMessage`.
- Two copies, each with its reason:
  - the session's watch display names (`WatchAnswers.WatchNames`, private, 8 lines);
  - the catalog's " ET" rule (`Catalog.SlotText`, private, 1 line).

  The AC's footprint names only the new class, so neither private helper is opened. A follow-up can make them public.
- The tests reuse `Test.Watch.Case`, the `Test.Checks.Turns` pattern and `RunnerFixture`.

**Orchestrator notes (binding):**
- "declare it read-only and TrustedOutput by the SAME mechanism check_status and the reminder list use". This is verified: `ClassificationOf` reads the tool class's own parameters, so `Gate.cls` needs no edit.
- "From the bridge's approval rows: the answer, its channel and its time. NEVER the model-written cause sentence".
- "With no incident in 24 h: say so plainly, no all-clear".
- "Prefer leaving [reminders] out". They are left out.

**Decided in-stage:**
- **The element at fault is checked, not copied.**
  - `Incident.Element` is the Diagnosis model's free text (up to 128 characters), written in an untrusted turn from failed messages.
  - The AC asks for "code-built fields only" and for output that stays trusted, so the element is given only when it exactly equals an instance-defined name: a request's fix `field` (which CheckFix verified to be a compiled property name of the body class) or a group's ItemName. Otherwise it is "".
  - On the demo path, OrderDate is the fix field, so it is shown.
  - It was flagged as security posture in round 1; the orchestrator's ruling (item 4) accepted it.
- **`closed` stays `closed`.** The row does not record whether it was closed by a dismiss, by closeQuiet or by closeForReplay. Calling a quiet close "dismissed" would be false (honest text), and the card's chip says "Closed" too.
- **The window and the order.**
  - An incident is in the window when its latest of NoticedAt, LastAt and ClosedAt falls within the last 24 hours.
  - Incidents are ordered newest NoticedAt first, as `RecentIncidents` gives them.
  - Incidents that were never noticed are left out, as every ownership read leaves them out.
- **Times.** Times follow the catalog's rule exactly: `ForMessage`, plus " ET" on the online demo, and no label on a local install.
- **The answer's words.** The approval answers are `waiting`, `approved`, `rejected`, `expired` and `cancelled`, and the step label is "Reading recent activity". Both follow the precedent of earlier step labels, which the UX does not list.
- **The Given state of AC3** is fixture rows shaped like the demo path's records. The When and the Then run through the real chat pipeline. A full Break the feed run in this test would repeat `live:demo-path` at several minutes of CI time.

**Orchestrator ruling (2026-11-01, on the round-1 intent gap; binding):**
1. **Contended test lists: allowed, one-name append-only.** This story may add `recent_activity` (or `OcuTalon.Tools.RecentActivity:recent_activity`) to exactly these lists and nothing else in those files: `Test/Tools/Reminders.cls` L263 (`TestSetRelative`'s sorted list), `Test/Watch/Turns.cls` L63 (the offered-tools list), `Test/Agent/Instructions.cls` (the doc at L23-24 and the expected list at L205-212), and `Test/Bridge/Gate.cls` `TRUSTEDTOOLS` and `READONLYTOOLS` (append `OcuTalon.Tools.RecentActivity:recent_activity` to each). No other line of those four files changes. A merge conflict on them is a plain union (both sides kept, plus the new name).
2. **Non-contended extensions allowed:** `Tools/Names.cls`, `Test/Watch/Tools.cls`, `Test/Agent/Runners.cls`, `Test/Agent/Constants.cls`.
3. **Spine:** the Conventions "Tool classification" row gains the `recent_activity` clause (written by the lead at the spec gate). AD-22's "11 built-in tool names" is NOT edited in this story: the orchestrator writes the as-built count (12) at the merge gate (veto item U-199). Do not plan any spine edit; `Test/Agent/Constants.cls` may still assert 12 names in `OcuTalon.Tools.Names`.
4. **Decided in-stage choices accepted:** the element at fault only on an exact match with the approved fix's field or an item name, otherwise empty; a closed incident reads "closed", not "dismissed"; "reminders fired today" omitted.
The intent gap below is resolved by this ruling; re-plan with it and keep the rest of the plan.

**Intent gap (resolved by the ruling above).** Round 1 asked whether this story may edit `Test/Tools/Reminders.cls` L263 and `Test/Bridge/Gate.cls` `TRUSTEDTOOLS` and `READONLYTOOLS`, which go red when any tool is added to Chat. These are "the two the blocking question names" in the intent's Never list. The ruling allows them, with `Test/Watch/Turns.cls` L63 and `Test/Agent/Instructions.cls`, as one-name appends.

**Spine:** none in this story. The Tool classification row's `recent_activity` clause is already in the spine (pinned by `Test.Tools.RecentActivity`, so that class name is fixed). AD-22's "11 built-in tool names" is the orchestrator's to write (12) at the merge gate; `Test/Agent/Constants.cls` asserts 12 regardless.

**Decided in-stage (round 2, within the ruling):**
- The sorted lists (Reminders L263, Turns L63) get `recent_activity` in its alphabetical place, because `RunnerFixture.ToolNames` sorts. "Append" means one name added, not a position.
- The assertion message on those same lines keeps its count true ("eight tools" becomes "nine"; Reminders names Story 5.13 and six watching tools). A stale count in a message is a false claim, and the change stays on the line the ruling opens.
- `Test/Agent/Instructions.cls` gets no `arguments("recent_activity")` line. That loop skips a tool with no arguments, and `Test.Tools.RecentActivity`'s No-session row pins the NOSESSION answer, so the contended file changes less.

**Ledger inbox:** none.

## Verification

`<lane>` stands for:

```
env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=5 stage=implement'
```

The rules for every run:
- Use one command per call, each with `timeout: 600000`, and never put two IRIS test runs in one message.
- QA and review use their own stage and tags.
- If a run reports a missing or stale web bundle, run `<lane> OCUTALON_RUN_TAG=e5s13i ci/iris.sh build` once.

**Commands:**
- **(loop)** `<lane> OCUTALON_RUN_TAG=e5s13iw ci/warm.sh up`, once. Then, one per call:
  - `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e5s13iw ci/iris.sh class OcuTalon.Test.Tools.RecentActivity`;
  - `… class OcuTalon.Test.Watch.Tools`;
  - `… class OcuTalon.Test.Agent.Constants`.

  Expected: passed.
- **(loop)** Fresh, because the running ChatAgent job keeps the old toolset. One per call:
  - `<lane> OCUTALON_RUN_TAG=e5s13i ci/iris.sh class OcuTalon.Test.Tools.RecentActivityTurn`;
  - then `… class OcuTalon.Test.Agent.Instructions`, `… OcuTalon.Test.Agent.Runners`, `… OcuTalon.Test.Watch.Turns`, `… OcuTalon.Test.Tools.Reminders` and `… OcuTalon.Test.Bridge.Gate`.

  Expected: passed.
- **(once) Mutations.** Apply each one, observe red, revert, and confirm that `git status --short` and `git diff --stat` are unchanged:
  - add `"cause": (row.Cause)` to the entry → the Poisoned test goes red;
  - copy `Element` without the check → the Element test goes red;
  - read `Ownership.Incidents` of every owner instead of the session's → the Another-session test goes red;
  - drop the 24-hour filter → the Window and Nothing tests go red;
  - `TRUSTEDOUTPUTRECENTACTIVITY` 0 → `TestClassification` and the turn's Tainted assertion go red;
  - remove the `<Tool>` line → `TestClassification` and the turn test go red.

Observed in the implement stage (each applied, red seen, reverted, tree byte-identical):
- mutation: `Set entry.cause = row.Cause` added to the entry → `Test.Tools.RecentActivity` `TestPoisoned` red (AC2).
- mutation: `Element` copied from the row without the check → `TestElement` red (AC2).
- mutation: the read replaced with an SQL read of every owner's noticed incidents → `TestAnotherSession` red (AC2).
- mutation: the 24-hour `Continue` line removed → `TestWindow` and `TestNothing` red (AC2).
- mutation: `TRUSTEDOUTPUTRECENTACTIVITY` 0 → `TestClassification` red, and `Test.Tools.RecentActivityTurn` red on "the Turn is done, with no fallback, and untainted" (AC1, AC3).
- mutation: the `<Tool name="recent_activity">` line removed → `TestClassification`/`TestDescription` red, and `RecentActivityTurn` red on "exactly one tool step" and "both offer recent_activity" (AC1, AC3).
- mutation: the incidents read's `$$$ISERR(sc)` test removed → `TestUnreadableRuns` red on "a failing read of the incidents answers NOTREAD" (AC2, Unreadable row); the `If unread Quit ..Return(...)` line changed to ignore an unread approvals read → `TestUnreadableRuns` red on "a failing read of the approvals answers NOTREAD". A session's turn cannot make Ownership fail, so `Test.Tools.RecentActivityUnread` (the tool with a failing read on demand, through the private `ReadIncidents` and `ReadApprovals`) triggers it; `TestUnreadable` also pins the source.
(QA) Tests added to `src/ocutalon/cls/OcuTalon/Test/Tools/RecentActivity.cls` (no new file; run warm, tag e5s13qw, passed; each mutation applied, red seen, reverted, tree byte-identical):
- `TestProductionName` (AC2, Production: display name of the watch, else the row's Production) - mutation: the `$Select` fallback `row.Production` replaced with "" in `Entry` -> `TestProductionName` red (only that test).
- `TestGroupsAndFixKind` (AC2, item is the first group's; later group's name accepted as the element; the fix kind is the first known one) - mutation: `groups.GetAt(1)` -> `groups.GetAt(groups.Count())` -> `TestGroupsAndFixKind` red on "the item is the first group's ItemName"; mutation: the known-kind test dropped from the fixKind line -> `TestGroupsAndFixKind` and `TestElement` red.
- `TestWindowEdge` (AC2, window just inside at 23 h 50 min and just outside at 24 h 10 min) - mutation: `HOURS * 3600` -> `HOURS * 3000` in `RecentActivity()` -> `TestWindowEdge` red (only that test).
- Gap check: every matrix row and AC1-AC3 has a pinning test that was already red under a recorded mutation; AC4 (CI, Eval, diff) is a gate, not a test.
(Review) Each mutation applied, red seen, reverted, tree byte-identical (`git status --short` and `git diff --stat` unchanged); warm runs on tag e5s13rw, fresh on e5s13r:
- mutation: the `APPROVED` state guard removed from `Element` -> `Test.Tools.RecentActivity` `TestElementApprovedOnly` red (only that test; AC2, spine clause).
- mutation: `,OcuTalon.Tools.RecentActivity` removed from `Eval.Report` `TOOLCLASSES` -> `TestClassification` red on "the eval report scores it read-only" (DW-517).
- mutation: the 24-hour `Continue` line removed, with `TestNothing`'s new closed fixture -> `TestNothing`, `TestWindow` and `TestWindowEdge` red (AC2).
- mutation (one fresh run, two independent mutations): `ReplyGuard.Filter` returning the text unfiltered -> `RecentActivityTurn` red on "only the all-clear is removed" and "the reply does not say 'everything is fine'"; `Set entry.cause = row.Cause` in `Entry` -> red on "the tool result holds no ZZPOISON" (AC3).
- After the reverts: `Test.Tools.RecentActivity`, `Test.Eval.Report`, `Test.Watch.Tools` and `Test.Bridge.CodeRules` passed warm; `Test.Tools.RecentActivityTurn` passed fresh.

- **(once)** `bash docker/tests/test-mock.sh`. Expected: pass (it covers the scenario and the constants test).
- **(once)** Fresh shards, one part per call:
  - `<lane> OCUTALON_RUN_TAG=e5s13i ci/iris.sh shard lane-a@Tools`;
  - `… shard lane-a@Agent`;
  - `… shard lane-a@Watch --part 1/3`, `2/3` and `3/3`.

  Expected: passed.
- **(once)** `<lane> OCUTALON_RUN_TAG=e5s13i ci/iris.sh class OcuTalon.Test.Eval.Run`. Expected: passed, with no Eval file changed.
- **(once)** `bash ci/checks.sh`. Expected: all pass.
- **(once)** `<lane> OCUTALON_RUN_TAG=e5s13iw ci/warm.sh down`, then `<lane> OCUTALON_RUN_TAG=e5s13i ci/iris.sh teardown`, also after a failure. Confirm that the lane-b lock folder holds none of this stage's locks.

**Shared surfaces:**
- the Watching toolset's tool list and Chat's offered tool list: `Test.Watch.Tools` and `Test.Agent.Runners` (free), and the contended one-name appends `Test.Agent.Instructions` (doc L23-24, L205), `Test.Watch.Turns` L63 and `Test.Tools.Reminders` L263;
- `Tools.Names` and RELEASE1's count: `Test.Agent.Constants`, and the mock's `constants.test.mjs`;
- the trusted and read-only tool lists: `Test.Bridge.Gate` `TRUSTEDTOOLS` and `READONLYTOOLS` (contended one-name appends), checked by `TestFlagsAreListed`;
- the mock's scenario set: one new file.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The Chat agent now has a sixth watching tool, `recent_activity` (`OcuTalon.Tools.RecentActivity`), read-only and trusted-output by class parameters. It answers from the session's own records (at most 5 incidents of the last 24 hours, newest first) through `Ownership.RecentIncidents`, `IncidentApprovals` and `Checks` plus `FailureGroup.OfIncident` and `FixRun.OfRequest`. Every string comes from a fixed list, a `ForMessage` time (" ET" online), an instance name, or a constant; the element is kept only when it equals an approved fix's field or an item name. With nothing in 24 hours it says so and claims nothing about health.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls` (new): the tool, with private `ReadIncidents` and `ReadApprovals` seams.
- `src/ocutalon/cls/OcuTalon/Tools/Watching.cls`, `Tools/Names.cls`: the `<Tool>` line, DependsOn, `RECENTACTIVITY` in `RELEASE1`.
- `ci/mock/scenarios/A/recent-activity.json` (new): the triage, tool-use and reply scenario.
- `Test/Tools/RecentActivity.cls`, `Test/Tools/RecentActivityTurn.cls`, `Test/Tools/RecentActivityUnread.cls` (new): the matrix tests, the chat-turn Integration AC, and the failing-read double.
- `Test/Watch/Tools.cls`, `Test/Agent/Runners.cls`, `Test/Agent/Constants.cls`: shared-surface updates (6 tools, 12 names).
- Contended one-name appends: `Test/Tools/Reminders.cls` L263, `Test/Watch/Turns.cls` L63, `Test/Agent/Instructions.cls` (doc and expected list), `Test/Bridge/Gate.cls` `TRUSTEDTOOLS` and `READONLYTOOLS`.

**Review.** 29 findings (high 0, medium 3, low 18, false 6, maybe-false 2). Patched: 1 entry (medium; the NOTREAD paths had only a source-text test, now `TestUnreadableRuns` runs both through `RecentActivityUnread`, with two mutations). Deferred: 2 (Eval.Report TOOLCLASSES misses the tool, medium; Chat INSTRUCTIONS do not mention the tool, medium unverified), both out of footprint. Rejected with reasons: see the Review Triage Log.

**Follow-up review recommended:** false (one medium entry patched, no high).

**Verification.**
- Warm: `Test.Tools.RecentActivity`, `Test.Watch.Tools`, `Test.Agent.Constants` passed; after the patch `RecentActivity` passed and all six mutations were red and reverted (tree identical each time; the two chat-turn parts of mutations 5 and 6 were observed before the patch).
- Fresh: `RecentActivityTurn`, `Agent.Instructions`, `Agent.Runners`, `Watch.Turns`, `Tools.Reminders`, `Bridge.Gate` passed; after the patch `shard lane-a@Tools` (4 classes) and `Test.Bridge.CodeRules` passed.
- Shards before the patch: `lane-a@Tools`, `lane-a@Agent` (10 classes), `lane-a@Watch` parts 1/3, 2/3, 3/3 passed; `Test.Eval.Run` passed with no Eval file changed.
- `bash docker/tests/test-mock.sh` (118 pass) and `bash ci/checks.sh` (all scripts passed), both before and after the patch. Throwaways torn down; the lane-b lock folder is empty.

**Residual risks.** Whether the real model calls `recent_activity` for "What was that failure earlier?" is unverified (mock-scripted; deferred entry 2). Eval scoring treats the tool as an action until `Eval.Report` lists it (deferred entry 1). The patch changed the tool after the full lane-a shards ran; the post-patch shard and CodeRules runs passed, and the Agent and Watch shards were not repeated.
