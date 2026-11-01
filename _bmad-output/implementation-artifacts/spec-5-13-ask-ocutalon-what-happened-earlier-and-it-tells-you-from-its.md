---
title: 'Ask OcuTalon what happened earlier, and it tells you from its own records'
type: 'feature'
created: '2026-10-31'
status: 'blocked'
review_loop_iteration: 0
followup_review_recommended: false
context: []
warnings: ['oversized']
deferred: []
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
- Tests whose fixed lists change (shared surfaces):
  - `Test/Watch/Tools.cls` `TestDeclarations` L59-90: five tools, all from WatchTools;
  - `Test/Agent/Instructions.cls` L205-212 and the doc L23-24;
  - `Test/Agent/Runners.cls` `REMINDERTOOLS` L73, the doc L43-45, `TestToolInventory` L317-328;
  - `Test/Watch/Turns.cls` L63;
  - `Test/Agent/Constants.cls` L6, L27 and L44 (11 names).
  - **Blocked:** `Test/Tools/Reminders.cls` L263 and `Test/Bridge/Gate.cls` L114 and L116, which `TestFlagsAreListed` (L1343-1361) checks.
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
- Updates for the shared surfaces: `Test/Watch/Tools.cls` (6 tools; recent_activity comes from RecentActivity with ("safe",1,1,"Reading recent activity","","")), `Test/Agent/Instructions.cls`, `Test/Agent/Runners.cls`, `Test/Watch/Turns.cls` and `Test/Agent/Constants.cls` (12). Then, after the ruling: `Test/Tools/Reminders.cls` L263, and `Test/Bridge/Gate.cls` TRUSTEDTOOLS and READONLYTOOLS, each gaining `OcuTalon.Tools.RecentActivity:recent_activity`.

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

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-10 rule 3 and the Tool classification convention: trusted output holds no text from outside a user's untainted turn. This is why the element is checked, and why the cause and the texts are left out.
- AD-4 and AD-13: the session scope goes through the ownership API.
- AD-28: no all-clear in the answer; the guard applies to the reply.
- AD-7: the Chat agent's toolsets.
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
  - This is flagged for the lead as security posture.
- **`closed` stays `closed`.** The row does not record whether it was closed by a dismiss, by closeQuiet or by closeForReplay. Calling a quiet close "dismissed" would be false (honest text), and the card's chip says "Closed" too.
- **The window and the order.**
  - An incident is in the window when its latest of NoticedAt, LastAt and ClosedAt falls within the last 24 hours.
  - Incidents are ordered newest NoticedAt first, as `RecentIncidents` gives them.
  - Incidents that were never noticed are left out, as every ownership read leaves them out.
- **Times.** Times follow the catalog's rule exactly: `ForMessage`, plus " ET" on the online demo, and no label on a local install.
- **The answer's words.** The approval answers are `waiting`, `approved`, `rejected`, `expired` and `cancelled`, and the step label is "Reading recent activity". Both follow the precedent of earlier step labels, which the UX does not list.
- **The Given state of AC3** is fixture rows shaped like the demo path's records. The When and the Then run through the real chat pipeline. A full Break the feed run in this test would repeat `live:demo-path` at several minutes of CI time.

**For the lead (Rule 20, at the spec gate):**
- The spine's Tool classification row gains "so is the read-only `recent_activity` ... pinned by `Test.Tools.RecentActivity`".
- AD-22's "the 11 built-in tool names" becomes 12.
- Footprint extension: `Tools/Names.cls`, and five Lane A tests whose fixed lists change.

**Ledger inbox:** none.

**Intent gap (blocking).** Adding any tool to Chat makes two tests red in files that the orchestrator's footprint forbids:
1. `src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls` L263 (Epic 11, live). `TestSetRelative` asserts Chat's exact offered list, "cancel_reminder,...,stop_watch".
2. `src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls` L114 and L116 (in Epic 30's diff). `TestFlagsAreListed` (L1343-1361) requires every trusted-output or read-only built-in tool to be listed in TRUSTEDTOOLS and READONLYTOOLS. The class doc makes that edit "the review of what its result can hold". The AC's "the gate's tool classification entry" plausibly means this.

There is no compliant alternative. Another toolset would change `Chat.cls` and the same list, and a setting-based classification would plan around the AC.

**Recommendation:** allow both edits in this story, each one line and append-only:
- add `recent_activity` to L263's sorted list;
- append `OcuTalon.Tools.RecentActivity:recent_activity` to both parameters.

Serialize them against Epics 11 and 30 at merge. Routing them to those epics instead would leave 5.13's CI red until they land.

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
- the Watching toolset's tool list and Chat's offered tool list: `Test.Watch.Tools`, `Test.Agent.Instructions`, `Test.Agent.Runners`, `Test.Watch.Turns`, `Test.Tools.Reminders` L263 (blocked);
- `Tools.Names` and RELEASE1's count: `Test.Agent.Constants`, and the mock's `constants.test.mjs`;
- the trusted and read-only tool lists: `Test.Bridge.Gate` `TestFlagsAreListed` (blocked);
- the mock's scenario set: one new file.

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: adding recent_activity to Chat's Watching toolset (the AC) turns two tests red in files the orchestrator's footprint forbids, so the story cannot merge green without editing them: (1) src/ocutalon/cls/OcuTalon/Test/Tools/Reminders.cls L263 (Epic 11, live): TestSetRelative asserts Chat's exact offered tool list; (2) src/ocutalon/cls/OcuTalon/Test/Bridge/Gate.cls L114/L116 TRUSTEDTOOLS/READONLYTOOLS, which TestFlagsAreListed (L1343-1361) requires to list every trusted-output or read-only built-in tool (Epic 30's diff; plausibly the AC's "gate's tool classification entry"). Recommended amendment: permit both one-line append-only edits in Story 5.13, serialized against Epics 11 and 30 at merge. Gate.cls itself needs no edit (verified). The rest of the plan is complete above; on the ruling, reset status to draft and re-dispatch.
