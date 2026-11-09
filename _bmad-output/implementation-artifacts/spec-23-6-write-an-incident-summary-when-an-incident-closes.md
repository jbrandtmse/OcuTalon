---
title: 'Story 23.6: Write an incident summary when an incident closes'
type: 'feature'
created: '2026-11-09'
status: 'done'
baseline_revision: '3071cd87f35e941fd5b824da26b2734c187fe771'
baseline_commit: '3071cd87f35e941fd5b824da26b2734c187fe771'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-23-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** When an incident closes (Dismiss, the replay rule, or 15 quiet minutes), nothing records what happened, so a user who wants to review or share it must rebuild the timeline from the cards, the trace and the audit log. The online demo's guided incident ends with no written account, so a judge never sees one.

**Approach:** On every move into `closed`, `IncidentManager` composes a summary in code from the incident's own rows (groups, approval requests, fix runs, the recorded diagnosis, usage rows; no model request), stores it on the `Incident` row, and sends one `Notification` of a new kind `summary` to each recipient session. The `*Out` operations render the stored summary through the catalog. A read-only, untrusted chat tool `incident_summary` returns it, and the demo guide's More to try panel gets one item that closes the guide's resolved incident so the summary appears.

## Boundaries & Constraints

**Always:**
- `IncidentManager` stays the only writer of `Incident` rows (AD-15, AD-33): the summary is composed by a pure builder and saved in `Move`'s one `%Save`, before the incident event and the notification go out.
- Every summary is code-built from rows: no `Decide` call, no new `Decision` or `Usage` row. Its cost is the sum of the `OcuTalon.Bridge.Data.Usage` rows of the incident's decisions (today only `Incident.DecisionRef`), through `Usage.Totals`; cost is per incident, never per step (AD-20).
- Every summary text is catalog keys and slots (prefix `summary.`, one block appended at the end of `Msg/Catalog/Watch.cls`), rendered only by `Catalog.Render`; the builder never renders.
- The `summary` Notification carries `IncidentRef`, `DecisionRef`, `CatalogKey` `summary.title`, `Slots` `{}` and no `ApprovalRef`, so no channel adds Approve or Reject and no user name or untrusted text travels in a production message (AD-4, AD-32).
- The summary and the tool are visible only to the sessions that own the incident (its owner session, or on a local install the watchers of an `instance` incident) through `Session.Recipients` and the ownership API (AD-4).
- The summary lives and dies with its incident row: `IncidentManager.PurgeOne` already deletes the row (AD-27, NFR-19, `daysToKeep` 90 by default).
- Evidence, sample error, cause and fix text are untrusted: the tool is `READONLY` 1 and `TRUSTEDOUTPUT` 0, so a turn that calls it is tainted (AD-10).
- A close always succeeds when the transition table allows it; a summary that cannot be built leaves `Summary` empty, logs one redacted warning, and sends no summary notification.
- The answerer is named only on a local install (never on the online demo), following EXPERIENCE's "Who answered" format rule.

**Never:**
- No paging or acknowledgement lines (Story 23.4 is parked), no dependency on Stories 23.3, 23.4, 23.7, 23.8 or Epic 36.
- No new `/api/v1` route, no new table, no new live-event type, no new privilege, role or resource.
- No auto-close at the guide's finish: the visitor's own press (Dismiss, the More to try item, Break it again) or the quiet rule closes the incident.
- No summary text that contains "went through", "I checked ", "Yesterday's cost" or a greeting (the demo-path and online e2e filters count those).
- No edit of `EXPERIENCE.md` in this story (contended; see Design Notes), and no edit under `irislib/` or `irissys/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fixed incident dismissed | `resolved` incident with one approved request (answered on the phone), one FixRun (50 resent, 50 completed), a diagnose decision with two usage rows; `dismiss` | `closed`; `Summary` parts: title, first failure, notice, request raised, approved from the simulated phone, fix started, fix ended with counts, closed by Dismiss, cause, element, evidence, sample error, fix, messages, cost = sum of the two rows; one `summary` Notification to the owner | No error expected |
| Replay rule | `resolved`; `closeForReplay` from Break the feed | as above, closing line `summary.closedReplay` | No error expected |
| Quiet close | `resolved`, last failure older than 15 min; `closeQuiet` | closing line `summary.closedQuiet` | No error expected |
| Fallback incident | noticed `open`, `Fallback` 1, `FallbackReason` set, no request; `dismiss` | `summary.noCause` with the reason, `summary.noFixRan`, `summary.groups` listing every FailureGroup, messages with 0 resent, cost (0 when no usage rows) | No error expected |
| No-fix / rejected / expired | noticed `open` (variant `no_fix`, `rejected` or `expired`) | cause and evidence when a diagnosis exists, the request's rejected or expired line when there is one, `summary.noFixRan`, `summary.groups` | No error expected |
| Unknown cost | a usage row of the decision has an empty `CostUSD` | `summary.costUnknown` in place of `summary.cost` | No error expected |
| Instance incident, local install | `OwnerRef` `instance`, two watcher sessions | one `summary` Notification per watcher (Tell) | No error expected |
| Builder fails | a row read throws during the build | incident still `closed`; `Summary` empty; one redacted Type 3 warning; no `summary` Notification | Close not blocked |
| Refused close | `dismiss` while `fixing`, or anything on a `closed` incident | no move, no summary, no notification | Existing refusal |
| Chat ask | session asks "Show me the incident summary" | `incident_summary` answers `{"outcome": "summary", "production", "closedAt", "text"}` with the rendered summary of the session's newest closed visible incident that has one; the turn is tainted | No error expected |
| Chat ask, nothing to show | no closed visible incident with a summary, or another session's incident only | `{"outcome": "none"}` | No error expected |
| Chat ask, no session | eval, instance or empty owner, empty ItemId | `CommandCall.Session` refusal `NOSESSION` | Existing refusal |
| DW-877 | a `FailureBatch` holding `Failure` objects | `XMLExportToString` returns OK and the XML holds each failure | No ERROR #6249 |

</intent-contract>

## Code Map

- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- `Apply` (1071-1086) runs `Transitions.Next` then `Move`; `Move` (1050-1065) sets `ClosedAt` once and saves, then `Tell` (1400-1428) sends the given notification to every `Session.Recipients` session and publishes `incident`. `Command` (1179-1204) is the only caller that closes and passes no notification. `Notification(...)` (1035-1045) sets `DecisionRef`; `Compose(...)` (1251-1261) the answered/result shape. `Purge`/`PurgeOne` (1333-1375) delete closed incidents by `ClosedAt` with their groups and FixRuns. `Answered` (712-729) writes `Element`, `DecisionRef`.
- `src/ocutalon/cls/OcuTalon/Watch/Transitions.cls` -- close rows (98-101 open; 130-132 resolved); `Next` returns `variant` "" on a close, so the builder must read `OpenVariant`/`Fallback` before `Move`.
- `src/ocutalon/cls/OcuTalon/Watch/Notice.cls` -- the notice key/slot builder: sibling of the new builder; reuse its groups slot (`incident.noFix`'s `groups`) and `ResultSlots` counts.
- `src/ocutalon/cls/OcuTalon/Data/Incident.cls` -- properties (Ref, OwnerRef, DecisionRef, Namespace, Production, State, OpenVariant, NoticedAt, FirstAt, LastAt, ClosedAt, Count, ItemNoun, Cause, FixSummary, SampleError, CauseCategory, Element, Fallback, FallbackReason, RequestRefs); `Storage Default` at 95, last slot 28 `AskingSince` (179-180).
- `src/ocutalon/cls/OcuTalon/Data/FailureGroup.cls` -- `OfIncident(ref)` (57). `src/ocutalon/cls/OcuTalon/Data/FixRun.cls` -- `OfRequest(ref)` (66); StartedAt, EndedAt, Total, Resent, Completed, FailedAgain, Skipped, Interrupted, Unreached.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- RaisedAt, ExpiresAt, State, DryRun (`affected`, `itemNoun`), AnsweredAction/Channel/By/At. `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` -- `Payload` (39) holds the diagnosis JSON with `evidence` lines (`Watch/Msg/DiagnosisPayload.cls:43`). `src/bridge/cls/OcuTalon/Bridge/Data/Usage.cls` -- `Totals(decisionRef)` (178): `costUSD` "" when any row's cost is unknown, all empty with no rows.
- `src/ocutalon/cls/OcuTalon/Channel/DigestText.cls` -- `Text(slots, channel, .sc)` renders `{"parts": [...], "lines": [...]}` one piece per line through `Catalog.Render`: reused unchanged for the summary (empty `lines`).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- `CARDKINDS` (41), `INCIDENTKINDS` (44), digest branch (75). `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` -- `CARDKINDS` (39), digest branch (70). `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` -- `KINDS` (97), digest branch (173), split at 4096 (`Api.cls:28`).
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls:30` -- `NOTIFICATIONKIND`. `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` -- the general branch already routes any other kind to WebChatOut, SimPhoneOut (demo on) and TelegramOut (paired): no change.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- XData Entries; last key `digest.cost` (602), JSON closes ~609. `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- slot types (7-17); string slots lose line breaks; `groups` is the only multi-line slot.
- `src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls` -- the sibling the tool extends: per-name parameters (23-29), `CommandCall.Session(.context)` (57-59), `Ownership.RecentIncidents(owner, READMAX, .sc)` (92), `..Return(...)`. `src/ocutalon/cls/OcuTalon/Tools/WatchReads.cls:21-37` -- the `TRUSTEDOUTPUT... = 0` precedent.
- `src/ocutalon/cls/OcuTalon/Tools/Watching.cls` -- Chat watch toolset XData (11-20). `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- `TOOLSETS` (18), INSTRUCTIONS tool rules (~58-65). `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- last entry `DOCUMENTS` (52).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `INCIDENTVISIBLE` (69), `RecentIncidents` (390), `Incident(ref, sessionRef)` (523).
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls` -- `finished` (112-113) holds for `closed` with no open variant, so the finish stays after the close. `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- `Ids()` order. `src/ocutalon/cls/OcuTalon/Demo/BreakFeedIn.cls:93-104` -- `closeForReplay` per resolved Orders incident.
- `web/src/app/guide/more-to-try-view.ts` -- `MORE_TO_TRY_TEXTS` (21-69), `MoreToTryAction` (75), `MORE_TO_TRY_ITEMS` (87-95). `web/src/app/guide/more-to-try.ts:206-235` -- `press()`. `web/src/app/incidents/incident-view.ts:430` + `incident-dismiss.ts:46` -- Dismiss.
- `web/src/app/chat/chat-view.ts:221-229` -- `noticeOf` kind filter. `web/src/app/chat/notice-card.ts` -- kind classes (48), `white-space: pre-line` only for `.request`/`.digest` (121-123), icon by kind (201-210).
- `ci/mock/scenarios/A/recent-activity.json` -- marker-scenario shape to copy. `README.md:30` (Usability row, "seven more things"), `README.md:32-41` (New since 1.0.0).
- Tests: `Test/Watch/Lifecycle.cls` (probe fixtures `Incident` 1225, `Request` 1242, `Group` 1321, `Run` 1354, `Command` 1384, `Finish` 1399, `Outcome` 1462, `Result` 1473; `TestPurge` 954), `Test/Watch/IncidentProbe.cls` (records `SendNotice` in `host.Sent`), `Test/Data/Fixture.cls` (`Incident` 87, `Approval` 108, `FixRun` 126, `Decision` 141, `Usage` 160), `Test/Watch/Closing.cls` (dismiss over the running production), `Test/Tools/RecentActivity.cls` (`TestAnotherSession` 423-440, `TestNoSession` 443-466, `TestClassification` 509-524), `Test/Tools/RecentActivityTurn.cls`.

## Tasks & Acceptance

**Execution:**
- `src/ocutalon/cls/OcuTalon/Watch/Msg/Failure.cls` -- `Extends (%SerialObject, %XML.Adaptor)`, storage unchanged -- DW-877.
- `src/ocutalon/cls/OcuTalon/Data/Incident.cls` -- add `Property Summary As %String(MAXLEN = "")` (JSON `{"parts": [{key, slots}], "lines": []}`, empty when none) with its doc comment; append storage slot `<Value name="29"><Value>Summary</Value></Value>` -- the stored summary, purged with the row.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls` -- append the `summary.*` block of `## Public Text` after `digest.cost`, each with a `source` naming Story 23.6 and the Planner's Public Text ruling -- AD-32.
- `src/ocutalon/cls/OcuTalon/Watch/Summary.cls` (new, Lane A, abstract) -- `ClassMethod Build(incident, event, closedAt, onlineDemo, Output sc) As %DynamicObject`: reads the incident's FailureGroups, its requests (`RequestRefs`, rows naming the incident), their FixRuns, the diagnosis `Decision` payload's first evidence line and `Usage.Totals(DecisionRef)`; returns the parts in the order of Design Notes; never renders, never writes. `ClassMethod Text(incidentRef, channel, Output sc) As %String`: the stored `Summary` rendered by `DigestText.Text` ("" with an error status when the row or its summary is missing) -- the one composer and the one stored-summary reader.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- in `Apply`, when `to` is `closed` and `from` is not: compute `closedAt` (UTC now) and set `incident.ClosedAt`, call `Summary.Build` before `Move`, set `incident.Summary`, and pass a `summary` Notification (`Kind` `summary`, `CatalogKey` `summary.title`, `Slots` `{}`, `IncidentRef`, `DecisionRef`, no `ApprovalRef`) to `Move` unless a notification was given; on a build error log one redacted Type 3 warning and close without summary or notification -- one writer, one save, one send per recipient through `Tell`.
- `src/ocutalon/cls/OcuTalon/Msg/Enum.cls` -- append `summary` to `NOTIFICATIONKIND` -- AD-32 (amendment, see Veto-window items).
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- `summary` joins `CARDKINDS`; its text is `Watch.Summary.Text(IncidentRef, "web")`, kept on the Delivery row and published as a `notification` like a digest card -- the web chat consumer.
- `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` -- `summary` joins `CARDKINDS`, text from `Watch.Summary.Text(IncidentRef, "phone")`, no buttons -- demo mode's phone.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` -- `summary` joins `KINDS`, text from `Watch.Summary.Text(IncidentRef, "telegram")`, split at line breaks, no buttons -- paired chat.
- `src/ocutalon/cls/OcuTalon/Tools/Names.cls` -- one-line append `Parameter INCIDENTSUMMARY = "incident_summary";` with a `///` note that it is not in `RELEASE1`.
- `src/ocutalon/cls/OcuTalon/Tools/RecentActivity.cls` -- add `ClassMethod IncidentSummary() As %DynamicObject` (no arguments) with `STEPLABELINCIDENTSUMMARY = "Reading the incident summary"`, `CLASSIFICATIONINCIDENTSUMMARY = "safe"`, `READONLYINCIDENTSUMMARY = 1`, `TRUSTEDOUTPUTINCIDENTSUMMARY = 0`: session via `CommandCall.Session`; the newest closed incident with a non-empty `Summary` among `Ownership.RecentIncidents(owner, READMAX)`; answer `{"outcome": "summary", "production", "closedAt", "text": Watch.Summary.Text(ref, "web")}` or `{"outcome": "none"}`, through `..Return`.
- `src/ocutalon/cls/OcuTalon/Tools/Watching.cls` -- add `<Tool Name="incident_summary" Class="OcuTalon.Tools.RecentActivity" Method="IncidentSummary"/>` and update the description sentence.
- `src/ocutalon/cls/OcuTalon/Agent/Chat.cls` -- one INSTRUCTIONS rule: "If the user asks for an incident's summary, call incident_summary and give its text as it is; with outcome none, say there is no closed incident with a summary yet." (agent text, not shown to users).
- `ci/mock/scenarios/A/incident-summary.json` -- marker scenario: triage text, `toolUse` `incident_summary` `{}`, final text -- the CI mock's script for the tool (AD-22).
- `src/ocutalon/cls/OcuTalon/Demo/Features.cls` -- id `incidentSummary` first in `Ids()`, always present like `rejectFix`.
- `web/src/app/guide/more-to-try-view.ts`, `web/src/app/guide/more-to-try.ts` -- item `incidentSummary` (texts of `## Public Text`), action `incidentSummary`: focus and press the Dismiss of the newest incident card whose chip is resolved; with none, focus the newest summary notice card and press nothing.
- `web/src/app/chat/chat-view.ts`, `web/src/app/chat/notice-card.ts` -- `noticeOf` accepts kind `summary`; the card gets class `summary`, `white-space: pre-line` and the existing info icon; no new string.
- `README.md` -- line 30 "seven more things" -> "eight more things"; append the New-since bullet of `## Public Text` after line 41.
- Tests (update every pin the Shared surfaces line names, then add): `Test/Watch/Summary.cls` (new; the AC 1-2 table over Fixture rows through `IncidentProbe`), `Test/Watch/Lifecycle.cls` (close tests expect the one summary notice; `TestPurge` asserts the summarized row is gone), `Test/Watch/Closing.cls` (Integration AC), `Test/Watch/Poller.cls` (DW-877 export case), `Test/Msg/Catalog.cls` Fixtures, `Test/Tools/RecentActivity.cls` (tool cases incl. second session), `Test/Tools/RecentActivityTurn.cls` (mock marker turn, tainted), `Test/Core/WebChatOut.cls`, `Test/Demo/SimPhoneOut.cls`, `Test/Channel/TelegramOut.cls` (one `summary` case each), `Test/Demo/Features.cls`, `Test/Demo/Guide.cls` (finish holds after Dismiss), `web/scripts/more-to-try-view.test.mjs`, `more-to-try-sources.test.mjs`, `ux-strings.test.mjs` (`ruled` entries citing the Planner ruling), `chat-view.test.mjs`, `web/e2e/guide/more-to-try.spec.ts` (press the item at the finish: chip Closed, a summary card with the title line in the chat and on the phone, the finish still shown), `web/e2e/chat/notice.spec.ts` (a seeded `summary` notification keeps its line breaks).

**Acceptance Criteria:**
- AC1: Given an incident that closes by Dismiss, the replay rule or 15 quiet minutes, when `IncidentManager` closes it, then its row stores a summary with the timeline (first failure, notice, each request raised and answered, each fix started and ended, closing), cause and element at fault, evidence line and sample error, fix and result, each answer's channel and time (and the answerer on a local install), messages failed, resent, completed, failed again and skipped, and the model cost; `Test.Watch.Summary` pins each part against the Fixture rows.
- AC2: Given an incident whose decision has usage rows, when it closes, then no `Decide` call is made and no `Decision` or `Usage` row is added, and the cost slot equals the sum of the usage rows of the incident's decisions (`Usage.Totals`); with an unknown row cost the part is `summary.costUnknown`.
- AC3: Given a fallback incident, or one that closes with no fix run, when it closes, then the summary holds `summary.noCause` (fallback) or the cause, `summary.noFixRan` and `summary.groups` listing every FailureGroup.
- AC4: Given an incident with one or more recipient sessions, when it closes, then exactly one Notification of kind `summary` (CatalogKey `summary.title`, `Slots` `{}`, IncidentRef and DecisionRef set, no ApprovalRef) goes to each recipient session, and none for a refused move or a failed build.
- AC5 (Integration): Given a session's resolved incident in the running production, when it is dismissed through `CommandsIn`, then `WebChatOut` records that session's Delivery row of kind `summary` whose text is the rendered summary with its line breaks, and a second session gets no row (`Test.Watch.Closing`).
- AC6 (Integration): Given a closed incident with a summary, when the user asks in the chat, then `incident_summary` returns the rendered summary built by code with the summary's catalog keys, the tool is classified safe, read-only and not trusted output (`Test.Bridge.Gate` `READONLYTOOLS`), and the reply goes to the channel asked on and to the web chat (`Test.Tools.RecentActivityTurn` through the mock marker).
- AC7: Given a closed incident owned by another session (or an `instance` incident on the online demo), when a session calls `incident_summary`, then it answers `none` (`Test.Tools.RecentActivity` second-session case).
- AC8: Given `IncidentManager.Purge(daysToKeep)`, when a summarized incident's `ClosedAt` is older than the cutoff, then its row and summary are gone; a newer one keeps its summary.
- AC9: Given `incident_summary` in `OcuTalon.Tools.Names`, the Chat toolset and `ci/mock/scenarios/A/incident-summary.json`, when the tool-list tests and the mock tests run, then every tool-list pin passes and `bash docker/tests/test-mock.sh` passes.
- AC10: Given the online demo guide finished on a resolved incident, when the visitor presses More to try's "Close the incident", then the incident card shows Closed, a summary notice appears in the web chat and on the Simulated phone, and the finish state stays (`web/e2e/guide/more-to-try.spec.ts`, CI).
- AC11: Given the README, when a judge reads New since 1.0.0 and the Usability row, then the incident-summary bullet of `## Public Text` is there and line 30 says eight.
- AC12 (DW-877): Given a `FailureBatch` holding failures, when it is exported as XML, then the export succeeds and holds each failure; `Failure`'s storage block is unchanged.

**Added at the spec gate from the Contest Planner's rulings (2026-11-09):**
- [x] Rendering: `{channel}` slots render "the web chat", "the Simulated phone", "Telegram" (the README's names), never an internal id; cause, evidence, fix and sample error render as plain text on every channel (escaped in the web chat; no parse mode or markup in Telegram); the sample error is cut to the incident notice's length; `summary.closedQuiet`'s 15 becomes a slot if the quiet period is a setting.
- [x] More to try fallback: with no resolved incident to close, the button sends "Show me the incident summary" to the chat (an e2e case in `web/e2e/guide/more-to-try.spec.ts`); if the lookFor text must change, HALT with an intent gap naming the new text (public text) instead of committing it.
- [x] README: the New since 1.0.0 bullet is appended LAST in that list; line 30's count, EXPERIENCE.md's item count and the `more-to-try-view.ts` header comment equal the registry's item count; every count pin this story adds or changes reads the registry, not a literal.
- [x] `EXPERIENCE.md`: this story writes its marked additive lines with the ruled texts (the item count, the new item bullet, the control clause with the fallback).
- AC13: Given a summary with an approval answered from each channel, when it renders, then `{channel}` reads "the web chat", "the Simulated phone" or "Telegram", never an internal id.
- AC14: Given an incident whose evidence line, cause and sample error contain markup (for example `<b>x</b>` and `*y*`), when the summary is delivered to the web chat, the Simulated phone and Telegram, then each shows the text literally (escaped in the web chat; Telegram sent with no parse mode), and the sample error is no longer than in the incident notice; one test per channel.
- AC15: Given the online demo, when a summary renders an answered request, then no line carries an IRIS user name (`summary.approved`/`summary.rejected` only); on a local install with `AnsweredBy` known, `summary.approvedBy`/`summary.rejectedBy` name the user; one test.
- AC16: Given the guide has no resolved incident to close (closed by the quiet rule or Break the feed again, or the guide not run), when the visitor presses More to try's "Close the incident", then "Show me the incident summary" is sent to the chat (e2e case).
- AC17: Given an install upgraded from v1.0.5 with existing closed incidents and no `Summary` values, when the upgrade harness runs (`live:install-upgrade`, CI), then it passes and those incidents read with an empty summary; the purge test proves the summary goes with its row (AC8).
- AC18: Given the More to try registry, when the count pins run, then README line 30, EXPERIENCE.md's count, the `more-to-try-view.ts` header comment and every count test match the registry's item count (tests read the registry).

## Spec Change Log

- 2026-11-09 (runner, after QA): Contest Planner Part A rulings recorded (Lane B extras allowed; mailbox name approved; email dropped, patched at code review).

- 2026-11-09 (runner, spec gate): Contest Planner rulings applied: six keys reworded, rendering conditions (a)-(c), More to try fallback, README order, veto conditions, spine additions written (AD-32, AD-15), AD-33 exception scope, registry-driven count; AC13-AC18 added.

- 2026-11-09 (runner, spec gate): orchestrator rulings on the contended paths recorded under Design Notes; Planner rulings pending.

## Review Triage Log

### 2026-11-09 — Review pass
- verdicts: 36 findings — high 0, medium 6, low 23, false 7, maybe-false 0
- findings:
  - `[low]` `reject` Blind: CHANNELNAMES also maps mailbox and email, untested — "the Simulated mailbox" is the README's name; the unnamed-channel path is now pinned by TestAnswerEdges; a line for an unrulled channel would need a ruled text.
  - `[low]` `reject` Blind: Close the incident can do nothing while a turn is in flight; lookFor says it closes — the lookFor text is ruled verbatim; the fallback is the Planner's ruling; no realistic harm.
  - `[low]` `reject` Blind: only the sample error is length-capped — cause, evidence and fix come from the stored diagnosis, which is bounded by its own producer; the ruling asks the cut for the sample error only.
  - `[false]` `reject` Blind: non-fallback incident with empty cause gets no cause statement — the matrix and Design Notes give summary.noCause to the fallback only; the cause line is omitted when empty by design.
  - `[low]` `reject` Blind: closedQuiet's 15 is a literal while QUIETSECONDS is 900 — QUIETSECONDS is a Parameter (a constant), so the ruling's literal stands; no setting can change it.
  - `[medium]` `patch` Blind: several Build branches untested — fixed with TestTimelineOrder, TestRunEdges, TestGroupsOnlyWithoutFix, TestAnswerEdges and TestMarkup in Test.Watch.Summary (mutations demonstrated, see Verification).
  - `[false]` `reject` Blind: cost may understate when more decisions exist — the spec fixes the cost basis as Incident.DecisionRef (AC2, "today only DecisionRef"); no other decision is recorded for an incident today.
  - `[false]` `reject` Blind: the model regenerates the tool text — by design (AD-10: the tool returns values, the Chat instruction says to give the text as it is); the code-built card path is the other channel.
  - `[low]` `patch` Blind: JSDoc of 08-quiet-outcomes.spec.ts misplaced — moved the quietNotes block above the suite's doc block.
  - `[low]` `reject` Blind: Auto Run Result still read ready-for-dev and the AC5/AC6/AC10 mutation notes are thin — the result is written at finalize; AC5/AC6 are demonstrated on their pinning classes, AC10 is CI.
  - `[low]` `reject` Edge: Usage.Totals read failure shows a cost of 0 — Totals is a Lane B file outside the footprint and answers rows 0 on an SQL error; an SQL error on a plain SELECT has no realistic path.
  - `[false]` `reject` Edge: re-diagnosis overwrites DecisionRef, lowering the cost — the spec ties the cost to Incident.DecisionRef; same as above.
  - `[false]` `reject` Edge: Interrupted above 0 with EndedAt empty skips fixInterrupted — FixRun.Mark sets Interrupted and ends the run in the same save (FixRun doc comment), so the combination is transient and never closed over.
  - `[low]` `reject` Edge: a row time that is not a UTC time drops its line silently — every time is written by Data.Time in that format; no user-reachable path.
  - `[low]` `reject` Edge: an answer from an unnamed channel is missing from the timeline — the answer channels of a fix approval are web, phone and Telegram; the line needs a ruled text for any other channel, so it stays left out and TestAnswerEdges pins it.
  - `[low]` `reject` Edge: incident_summary scans only the 100 newest incidents — the spec fixes the read as Ownership.RecentIncidents(owner, READMAX); a user with over 100 newer incidents is not a realistic case.
  - `[low]` `reject` Edge: Closing sets ClosedAt and Summary before a Move whose save may fail — a failed save leaves the in-memory row unused; the next command reopens the row from disk.
  - `[false]` `reject` Edge: an unnoticed incident gets a summary but no notification — Transitions allows no close of an unnoticed incident (Dismiss is not_allowed while unnoticed; the replay and quiet rules read resolved or noticed rows).
  - `[low]` `reject` Edge: AC5 mutation lands in WebChatOut, not Closing — Closing reads the same CARDKINDS in the running production and passes on a fresh stack; the line says so.
  - `[low]` `reject` Edge: AC2 claims "decisions" but sums one — the spec's own note ("today only Incident.DecisionRef").
  - `[medium]` `patch` Gap: the timeline sort is not pinned — added TestTimelineOrder (two requests out of time order); mutation recorded.
  - `[medium]` `patch` Gap: interrupted and not-ended fix runs untested — added TestRunEdges; mutation recorded.
  - `[medium]` `patch` Gap: groups-only-without-a-fix has no ran-side test — added TestGroupsOnlyWithoutFix; mutation recorded.
  - `[medium]` `patch` Gap: answer-line and request-line branches untested — added TestAnswerEdges (unnamed channel, cancelled, pending, executing, done, failed, affected count, no count).
  - `[medium]` `patch` Gap: AC14 markup never passes through Build — added TestMarkup (cause, evidence, fix and sample error on three channels); mutation recorded.
  - `[low]` `reject` Gap: More to try blocked case and newest-of-several untested — an e2e case would only run in CI; the blocked case is a no-send by design and a wrong card is cosmetic; no realistic harm.
  - `[low]` `patch` Gap: "and not B's" cannot fail (same text, B older) — B's incident now has another text and is newer (TestIncidentSummaryAnotherSession).
  - `[low]` `reject` Gap: TestIncidentSummary's older-incident assertion cannot fail from a tool defect — a harmless sanity check; the newest-wins check is the answer.text comparison above it.
  - `[low]` `reject` Gap: TestPurge repeats the Exists assertion for the summary — harmless duplicate, the column lives on the row.
  - `[low]` `reject` Gap: classification test checks the doc comment wording — the comment is the tool description the model reads; pinning it is intended.
  - `[low]` `reject` Gap: whole-table Decision and Usage counts could flake under a concurrent writer — the class runs alone in a namespace with no production; no concurrent writer exists in the unit tests.
  - `[low]` `reject` Gap: K26 relies on K25's cleanup and a fixed sleep — Playwright runs one worker, K25 cleans in finally; the sleep follows a settled UI.
  - `[low]` `patch` Gap: no mutation lines for AC13-AC18 — written in Verification after demonstrating each (AC16 CI, AC17 harness).
  - `[low]` `reject` Gap: AC5, AC6 and AC10 mutation demonstrations are thin — each is demonstrated on its pinning class; AC10 is the CI e2e.
  - `[false]` `reject` Gap: docs/security-overview.md edited by hand — Test.Install.SecurityOverview compares it to the generated table and passes.
  - `[low]` `reject` Intent: the judge-visible path is covered by a seeded e2e and the online spec is not updated — descriptive; AC10 names more-to-try.spec.ts K25/K26 and the online filters were checked; nothing to patch.

## Design Notes

**Architecture decisions:** AD-4 (ownership, no user name in production messages), AD-10 (read-only, untrusted tool through the gate), AD-11 (approval rows are the answer source), AD-15 (IncidentManager is the one writer; the close rows of the transition table), AD-16 (FixRun counts), AD-20 (cost from usage rows, per incident), AD-22 (tool name in the CI mock), AD-27 (purge with the incident), AD-29/AD-33 (lane ownership; see Veto-window items), AD-32 (notification contract, catalog, renderer).

**How the summary appears at the end of the guide's incident (decided in-stage).** With demo mode on, the guide's resolved incident closes only on Dismiss, Break the feed again (the replay rule) or 15 quiet minutes; Run again only writes a guide marker (`Web/Api.cls:770-786`). The smallest design that keeps UJ-1 real: the visitor closes it. The More to try panel opens by itself at the finish, and its new first item's control presses the card's own Dismiss, so the summary card lands in the chat and on the phone while the finish stays (`Guide.cls:112-113` counts a closed incident with no open variant as finished). Rejected: closing on the finish automatically (closes the visitor's incident without a press, against EXPERIENCE's "nothing is pressed without a press", and changes spec 07's Run again path). Measured by reading code, so no Task 0 is needed: the close lands in `Apply`/`Move`, `Notify`'s general branch routes any new kind, and the finish rule holds for `closed`.

**Why the Notification carries no content.** The answerer's IRIS user name (local installs) and the untrusted evidence must not travel in a production message (AD-4), so `Slots` is `{}` and each `*Out` operation renders the stored summary through `Watch.Summary.Text(IncidentRef, channel)`, which reads the row and calls `DigestText.Text`. The Out operations still render (AD-32); the producer never does.

**Part order.** title; one line per timeline event sorted by time (first failure `FirstAt`; notice `NoticedAt`; each request `RaisedAt`; its answer `AnsweredAt`, or `ExpiresAt` for an expired one; each FixRun `StartedAt` and `EndedAt`, interrupted or ended; closing `closedAt`); cause and element, or no cause; evidence (the first evidence line of the diagnosis payload, omitted when none); sample error (omitted when empty); fix (`FixSummary`) or no fix ran; groups (fallback and no fix ran only); messages (failed = `Count`; resent, completed, failed again and skipped summed over FixRuns); cost. A cancelled request shows only its raised line. Page and acknowledgement lines do not exist until Story 23.4 adds rows; the timeline sort leaves room for them.

**Decided in-stage.** (1) The summary is a column on `Incident`, not a table: "stored with the incident", purged by the existing row delete. (2) Cost when the decision has no usage rows is `$0` through `summary.cost`; an empty `CostUSD` row gives `summary.costUnknown`. (3) The answerer is named on a local install whenever `AnsweredBy` is known (a summary is a record to share), never on the online demo. (4) The tool takes no arguments and answers the newest closed visible incident with a summary (the CI mock sends static input). (5) The tool renders with channel `web`; no summary key has a `web` variant, so the text is the same on every channel. (6) The More to try item is first, because it continues the incident the visitor has just finished; the Planner may rule it last, and the tests follow the ruled order. (7) The panel is not at capacity: there is no item cap, and the panel scrolls in its own window (`more-to-try-room.ts`); no grouping is proposed. (8) No Task 0: every uncertain path was settled by reading code (above). (9) Implement-stage decisions: the `{channel}` slots of the summary are `text` slots holding the README's names ("the web chat", "the Simulated phone", "Telegram"), made by `Watch.Summary`, because the catalog's `channel` type renders the phone as "the simulated phone" (lower case) and changing it would touch the shared renderer; an answer from a channel with no name gets no answer line rather than an internal id. (10) `summary.groups` is left out when the incident has no failure group (the catalog refuses an empty list), and `summary.requested` is left out when the request's dry run holds no resend or affected count; neither fails the build. (11) `Data.Ownership` `RecentNotices` lists the web Delivery rows of kind `summary` (with a message id) so that a reload shows the card, as it does for a digest; `Notice.Common`/`Groups` gained the small public surface the builder reuses (`Common` public, `Groups` with `every`, new `Notice.Noun` shared with `IncidentManager.Noun`). (12) With no resolved incident card the More to try control sends "Show me the incident summary" (the Planner's ruling 2) instead of focusing the newest summary notice card (the Task line, superseded); the control is not `aria-disabled` in that fallback, it sends nothing while a turn is in flight or the allowance is used up. (13) The approved lookFor text is unchanged: it does not mention the fallback.

**Extend, don't copy.** The builder `Watch.Summary` is a sibling of `Watch.Notice` and reuses its groups slot building and result counts instead of copying them; rendering reuses `Channel.DigestText.Text` unchanged (summary slots carry an empty `lines`); the tool is a method of `Tools.RecentActivity`, reusing its session and ownership reads; tests reuse `Test.Data.Fixture` and `IncidentProbe`.

**Integration ACs:** AC5 (WebChatOut renders the stored summary as a notice card) and AC6 (the chat turn returns it).
**Consumes:** `Bridge.Data.Usage.Totals`, `Bridge.Data.ApprovalRequest`, `Bridge.Data.Decision`, `Data.FailureGroup.OfIncident`, `Data.FixRun.OfRequest`, `Channel.DigestText.Text`, `Msg.Catalog.Render`, `Data.Ownership.RecentIncidents`, `Data.Session.Recipients` (through `Tell`).
**Consumed-by:** Story 23.2 (suspend, resume and reroute add their own `summary.*` timeline keys to `Watch.Summary.Build`), Story 23.5 (the partner notice's sent line), Story 28.1 (post-contest; its draft joins the summary).

**Ledger.** DW-877 is addressed by the first Execution task and AC12; removing Story 31.4's Lane B fallback is Lane B's, not this story's.

**Contended:** `EXPERIENCE.md` (Epics 35/41 in flight) should gain, after the Planner rules the Public Text: line 245 "There are seven items" -> "eight items", a new Item bullet with the More to try texts, and in the control bullet (~line 251) "item 8 presses the newest resolved incident card's Dismiss, or puts focus on the newest incident summary when there is none". This story does not edit it; `ux-strings.test.mjs` takes `ruled` entries instead. `Msg/Catalog/Watch.cls` changes only by the appended block, and `Tools/Names.cls` only by the one-name append. No other contended path is touched.

**Orchestrator rulings (2026-11-09, U14, category decide; recorded by the runner):**
- `Agent/Chat.cls` (Epic 41 in flight): plain union. This story adds its one INSTRUCTIONS line by the watch-tool rules and `incident_summary` in the doc comment's tool list, in hunks separate from Epic 41's.
- `Msg/Catalog/Watch.cls` and `Test/Msg/Catalog.cls` (Epic 35 in flight): one append-only `summary.*` block; the key-count pin is the union of both sides' keys (reconciled at integrate-forward).
- `EXPERIENCE.md`: this story writes its marked additive lines itself (the item count, the new More to try item bullet, the control clause) once the Planner has ruled the Public Text; a plain union at merge, the count line reconciled at integrate-forward. This supersedes "No edit of `EXPERIENCE.md` in this story" under Boundaries and the `Contended:` note above.
- Pending with the Contest Planner: the Public Text, the veto-window items (the `Incident.Summary` column, the `incident_summary` tool), the AD-32 and AD-15 amendments (AD-32 is cited by merged Story 41.5's spec, so it is the Planner's call under U7) and the AD-33/U-177 cross-lane exception. No implement spawn before those rulings are recorded here.

**Contest Planner rulings (2026-11-09, relayed by the orchestrator; binding for implement, QA and review):**
1. Public Text: the 26 `summary.*` keys are approved as drafted except six, now worded as ruled under `## Public Text` (`summary.requested`, `summary.fixInterrupted`, `summary.closedDismiss`, `summary.closedQuiet`, `summary.element`, `summary.noCause`). Conditions: (a) `{channel}` renders as the README's names, "the web chat", "the Simulated phone", "Telegram", never an internal id; (b) the untrusted parts (cause, evidence, fix, sample error) render as plain text on every channel: escaped in the web chat, no parse mode or markup in Telegram; the sample error is cut to the incident notice's length; one test per channel covers an evidence line containing markup; (c) on the online demo no line ever carries an IRIS user name (`summary.approvedBy`/`summary.rejectedBy` are local-only), with one test.
2. More to try: label, lookFor and button approved as drafted, placed FIRST. Condition: when there is no resolved incident to close (already closed by the quiet rule or by Break the feed again, or the guide not run yet), the button sends "Show me the incident summary" to the chat instead of doing nothing; an e2e case covers it. If that changes the lookFor text, the new text goes to the Contest Planner as public text before it is committed (the implement stage HALTs with an intent gap naming the new text rather than commit it).
3. README: the line 30 count change and the New since 1.0.0 bullet are approved as drafted; the bullet is appended LAST in that list.
4. Veto items kept: (a) the `Incident.Summary` column (slot 29), on condition that the purge test proves the summary goes with its row and the upgrade harness from v1.0.5 (`live:install-upgrade`) passes with existing closed incidents that have no summary; (b) the `incident_summary` tool as specified (read-only, untrusted, owner sessions only, second-session test required).
5. Spine: the AD-32 and AD-15 additions are approved as worded, as additive lines, written by the runner with the marker [ADDED 2026-11-09, Story 23.6, Contest Planner ruling] (done at the spec gate).
6. AD-33 cross-lane exception: allowed, limited to additive `summary` kind branches (`Channel/WebChat/Out.cls`, `Channel/SimPhone/Out.cls`, `web/src/app/chat/*`), the one More to try item (`Demo/Features.cls`, `web/src/app/guide/*`) and the `NOTIFICATIONKIND` append in `Msg/Enum.cls`, with their tests. If another branch touches those files first it is a plain union.
7. The orchestrator's plain-union rulings stand; `EXPERIENCE.md` gets the ruled texts above (this story writes its marked additive lines).
8. The More to try count (Planner, standing): README line 30 ("N more things to try"), EXPERIENCE.md's item count and the `more-to-try-view.ts` header comment must match the number of items in the registry after merges (Story 20.2, lane B, also adds an item; whichever merges second sets the count, nine if both). Any test that pins the count reads the registry, never a literal: every count pin this story adds or changes is registry-driven now.
9. Route rule (corrected, standing): no new `/api/v1` route in this story, so the real-HTTP route rule does not bite; the tool's second-session test is required (AC7).

**Contest Planner rulings, Part A [RULED 2026-11-09, Contest Planner]:** (1) the five extra Lane B edits from implement (`Data/Ownership.cls` RecentNotices `'summary'`; `Test/Data/Tables.cls` column map; `web/e2e/support/iris.ts` seed field; `web/scripts/approval-sources.test.mjs` regexes; the moved JSDoc in `web/e2e/demo-path/08-quiet-outcomes.spec.ts`) are allowed under this story's AD-33 exception as a plain union, listed under footprint_extensions; (2) channel names: "the Simulated mailbox" is approved; "email" is DROPPED until real email exists: `Watch/Summary.cls` `CHANNELNAMES` loses `email=email`, so an answer from email gets no answer line (code review patches it, with its test).

## Public Text

All drafts (EXPERIENCE.md and the PRD fix none of them; FR-30 fixes only the contents). Slot types in brackets.

Catalog keys, `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`, appended after `digest.cost` (~line 609):
- `summary.title`: "Incident summary: {count} {itemNoun} failed in {production}." [count count, itemNoun noun, production text]
- `summary.firstFailure`: "{time}: first failure." [time]
- `summary.noticed`: "{time}: OcuTalon told you." [time]
- `summary.requested`: "{time}: OcuTalon asked for approval to repair and resend {count} {itemNoun}." [RULED 2026-11-09, Contest Planner]
- `summary.approved`: "{time}: approved from {channel}." [time, channel]
- `summary.approvedBy`: "{time}: approved by {user} from {channel}." [time, user text, channel]
- `summary.rejected`: "{time}: rejected from {channel}." [time, channel]
- `summary.rejectedBy`: "{time}: rejected by {user} from {channel}." [time, user text, channel]
- `summary.expired`: "{time}: the approval request expired." [time]
- `summary.fixStarted`: "{time}: the fix started." [time]
- `summary.fixEnded`: "{time}: the fix ended: {resent} resent, {completed} completed, {failedAgain} failed again, {skipped} skipped." [time, four count]
- `summary.fixInterrupted`: "{time}: the fix was interrupted after resending {resent}." [RULED 2026-11-09, Contest Planner]
- `summary.closedDismiss`: "{time}: closed with Dismiss." [RULED 2026-11-09, Contest Planner]
- `summary.closedReplay`: "{time}: closed when Break the feed was pressed again." [time]
- `summary.closedQuiet`: "{time}: closed after 15 minutes with no new failures." (if the 15 is a setting rather than a constant, it becomes a slot) [RULED 2026-11-09, Contest Planner]
- `summary.cause`: "Cause: {cause}" [cause sentence]
- `summary.element`: "Where it failed: {element}." [RULED 2026-11-09, Contest Planner]
- `summary.noCause`: "No cause was found: {fallbackReason}." [RULED 2026-11-09, Contest Planner]
- `summary.evidence`: "Evidence: {evidence}" [evidence sentence]
- `summary.sampleError`: "Sample error: {error}" [error text]
- `summary.fix`: "Fix: {fix}" [fix sentence]
- `summary.noFixRan`: "No fix ran, so nothing was changed." []
- `summary.groups`: "Failure groups:\n{groups}" [groups]
- `summary.messages`: "Messages: {failed} failed, {resent} resent, {completed} completed, {failedAgain} failed again, {skipped} skipped." [five count]
- `summary.cost`: "Model cost of this incident: {cost}." [cost]
- `summary.costUnknown`: "Model cost of this incident: not known." []

Notification: kind `summary`, `CatalogKey` `summary.title`, text = the rendered parts above, one per line (no other fixed text).

Chat tool reply: no fixed wording; the tool returns the rendered summary as `text`, and the Chat instruction (agent text, `Agent/Chat.cls` ~line 60, not shown to users) says to give it as it is.

More to try item, `web/src/app/guide/more-to-try-view.ts` (~line 25, first item):
- label: "Read the incident summary"
- lookFor: "This closes the guide's resolved incident, as Dismiss on its card does. Look for the incident summary in the chat and on the Simulated phone: what happened and when, the cause and the evidence, each approval, the orders affected and the model cost. Later, ask "Show me the incident summary" to get it again."
- button: "Close the incident"

README, `README.md`:
- line 30 (changed): "its More to try panel has eight more things to try"
- new bullet after line 41: "- **Incident summaries.** When an incident closes, OcuTalon writes a summary from its own records, with no extra model request: the timeline, the cause and evidence, each approval with its channel and time, the messages affected and the incident's model cost. It arrives in the chat, on the Simulated phone and in Telegram when it is paired, and you can ask for it again in the chat. Try it: after the guide's incident, More to try, *Read the incident summary*."

## Veto-window items

- **Security posture:** none changed. No secret or credential is handled; the new tool is read-only, `safe`, not trusted output, and runs under the existing gate.
- **Privileges, roles, grants:** none. The tool and the composer read tables the service user already reads; no resource, role or grant is added.
- **Stored data:** new column `OcuTalon.Data.Incident.Summary` (`%String(MAXLEN = "")`, JSON parts, storage slot 29 of `^OcuTalonP.IncidentD`, append-only). It holds model-written cause, evidence and fix text, the sample error, counts, times, channels and, on a local install only, the answering IRIS user name. Retention: deleted with its incident by `IncidentManager.Purge(daysToKeep)` (closed incidents whose `ClosedAt` is older than `daysToKeep`, 90 by default). No migration: incidents closed before the upgrade have no summary. No new table.
- **New tool:** `incident_summary` (read-only, untrusted) in `OcuTalon.Tools.Names`, the Chat toolset, the Chat instructions and `ci/mock/scenarios/A/incident-summary.json`.
- **Routes:** none (no new or changed `/api/v1` route).
- **Public text:** every string under `## Public Text` (drafts).
- **Architecture decisions (lead writes the spine, Rule 20):** AD-32 gains Kind `summary` and a bullet: "An incident summary is one `Notification` of kind `summary` per recipient, `CatalogKey` `summary.title`, `Slots` `{}`; each `*Out` operation renders the incident's stored summary through `Watch.Summary.Text`." AD-15 gains: "On every move into `closed`, `IncidentManager` composes the incident's summary in code (`Watch.Summary`), stores it on the row in the same save and sends the `summary` notification." AD-33 exception for the Lane B files this story names: `Channel/WebChat/Out.cls`, `Channel/SimPhone/Out.cls`, `Demo/Features.cls`, `web/src/app/chat/*`, `web/src/app/guide/*`, their tests (`Test/Core/WebChatOut.cls`, `Test/Demo/SimPhoneOut.cls`, `Test/Demo/Features.cls`, `Test/Demo/Guide.cls`, `web/scripts/*`, `web/e2e/chat/notice.spec.ts`, `web/e2e/guide/more-to-try.spec.ts`), and the append to the shared `Msg/Enum.cls` (precedent: Story 17.10, DW-874). The ownership tables do not change.
- **Dependencies:** none.

## Verification

Run from the epic-23 worktree root, one command per call with `timeout: 600000`, each finishing in about 150 s; never two test runs in one message. Prefix every `ci/` call with `OCUTALON_LOCK_DIR=<the lane-d lock folder of the dispatch> OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`. Fresh tag `e23s6i`, warm tag `e23s6iw`; at the end `ci/warm.sh down`, then `ci/iris.sh teardown` with `e23s6i`. Every IRIS MCP call names `server` `ocutalon-slot-d` and `namespace` `OCUTALON`.

**Shared surfaces:** `Incident`'s storage block; `Msg.Enum` `NOTIFICATIONKIND`; the catalog key count and `Test.Msg.Catalog` Fixtures ("163 keys"); the tool lists and counts in `Test.Agent.Constants` (19), `Test.Agent.Instructions` `TestToolsets` (15), `Test.Agent.Runners` `REMINDERTOOLS`/`TestToolInventory`, `Test.Watch.Tools` ("seven tools"), `Test.Bridge.Gate` `READONLYTOOLS`, `Test.Install.SecurityOverview` (and `docs/security-overview.md`, regenerated when a check compares its tool list); the notifications `IncidentProbe` records on a close in `Test.Watch.Lifecycle` and the double in `Test.Demo.BreakFeedIn`; the WebChatOut/SimPhoneOut/TelegramOut kind lists and their tests; the More to try registry (seven-item pins in `web/scripts/more-to-try-view.test.mjs`, `more-to-try-sources.test.mjs`, `web/e2e/guide/more-to-try.spec.ts`, `Test.Demo.Features` "the seven in order"); the phone-note counts of `web/e2e/demo-path/05`, `07`, `08` and `web/e2e-online/demo-path/demo-path.spec.ts` step 7 (the summary's wording avoids their filters; spec 07's Break the feed press now also delivers a summary).

Every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (loop) `ci/warm.sh up` with `OCUTALON_RUN_TAG=e23s6iw` once, then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e23s6iw ci/iris.sh class <Class>`, one call each: `OcuTalon.Test.Watch.Summary`, `OcuTalon.Test.Watch.Lifecycle`, `OcuTalon.Test.Watch.Poller`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Tools.RecentActivity`, `OcuTalon.Test.Agent.Constants`, `OcuTalon.Test.Agent.Instructions`, `OcuTalon.Test.Watch.Tools`, `OcuTalon.Test.Bridge.Gate`, `OcuTalon.Test.Install.SecurityOverview`, `OcuTalon.Test.Channel.TelegramOut`, `OcuTalon.Test.Core.WebChatOut`, `OcuTalon.Test.Demo.SimPhoneOut`, `OcuTalon.Test.Demo.Features`, `OcuTalon.Test.Demo.Guide`, `OcuTalon.Test.Demo.BreakFeedIn`. Expected: each `CLASS ... passed`.
- (loop) `OCUTALON_RUN_TAG=e23s6i ci/iris.sh class <Class>`, fresh because the production's jobs must hold the new code, one call each: `OcuTalon.Test.Watch.Closing`, `OcuTalon.Test.Tools.RecentActivityTurn`, `OcuTalon.Test.Agent.Runners`. Expected: passed.
- (loop) `node --test web/scripts/more-to-try-view.test.mjs web/scripts/more-to-try-sources.test.mjs web/scripts/ux-strings.test.mjs web/scripts/chat-view.test.mjs web/scripts/catalog.test.mjs`. Expected: all pass.
- (loop) `bash docker/tests/test-mock.sh`. Expected: pass.
- (loop) `bash docker/tests/test-storage.sh`. Expected: pass (slot 29 appended only).
- (once) `npm --prefix web run lint`. Expected: pass.
- **Left to CI** (each over 150 s): the browser units (`live:sign-in` parts with `web/e2e/guide/more-to-try.spec.ts` and `web/e2e/chat/notice.spec.ts`, `live:demo-path`, the online demo path), `live:storage-roundtrip` (slot 29 matches the compiler), the shards, `bash ci/checks.sh`, `npm --prefix web run build`, and the lead's fresh-environment check (forward and `--reverse`).

**Mutations (Rule 19), one per AC, recorded as `mutation: <change> -> <test red>`:** AC1 drop the closing line -> `Test.Watch.Summary`; AC2 add 0.01 to the cost slot -> the cost assertion; AC3 omit `summary.groups` for a fallback -> `Test.Watch.Summary`; AC4 send the notice only when `OwnerRef` is a session -> the instance case in `Test.Watch.Lifecycle`; AC5 leave `summary` out of `CARDKINDS` -> `Test.Watch.Closing`; AC6 set `TRUSTEDOUTPUTINCIDENTSUMMARY` 1 -> `Test.Bridge.Gate`; AC7 read `RecentIncidents` without the owner -> the second-session case; AC8 skip the purge cutoff check -> `Test.Watch.Lifecycle:TestPurge`; AC9 remove the Names line -> `Test.Agent.Constants`; AC10 the item presses nothing -> `more-to-try.spec.ts` (CI); AC11 n/a (text); AC12 remove `%XML.Adaptor` -> the DW-877 case.

mutation: AC1 drop the closing line (the `Event` call for `closedAt` in `Watch.Summary.Build`) -> `Test.Watch.Summary` red (TestClosingLines, TestFixedDismissed, TestFallback, TestNoFixVariants); reverted, tree byte-identical.
mutation: AC2 add 0.01 to the cost slot (`Summary.Cost`) -> `Test.Watch.Summary:TestFixedDismissed` red ("the cost is the sum of the two usage rows"); reverted, tree byte-identical.
mutation: AC3 omit `summary.groups` for a fallback incident (groups only when `'ran && 'Fallback`) -> `Test.Watch.Summary:TestFallback` red; reverted, tree byte-identical.
mutation: AC4 send no summary Notification for an `instance` incident (`IncidentManager.Closing`) -> `Test.Watch.Lifecycle:TestInstanceDismiss` red ("one summary Notification per watcher"); reverted, tree byte-identical.
mutation: AC5 leave `summary` out of `WebChat.Out` `CARDKINDS` -> `Test.Core.WebChatOut:TestSummaryCard` red (six assertions); `Test.Watch.Closing` reads the same code in the running production and is pinned by the fresh-stack run; reverted, tree byte-identical.
mutation: AC6 set `TRUSTEDOUTPUTINCIDENTSUMMARY` 1 -> `Test.Bridge.Gate:TestFlagsAreListed` red; reverted, tree byte-identical.
mutation: AC7 read `RecentIncidents` for another owner (`"instance"`) in `IncidentSummary` -> `Test.Tools.RecentActivity:TestIncidentSummaryAnotherSession` red; reverted, tree byte-identical.
mutation: AC8 ignore the purge cutoff (`IncidentManager.Purge` sets a cutoff in the year 9999) -> `Test.Watch.Lifecycle:TestPurge` red ("the one closed 89 days ago stays"); reverted, tree byte-identical.
mutation: AC9 remove the `INCIDENTSUMMARY` line of `Tools.Names` -> `Test.Agent.Constants:TestToolNames` red ("there are 20 tool names"); reverted, tree byte-identical.
mutation: AC10 the item presses nothing -> `web/e2e/guide/more-to-try.spec.ts` K25 (CI, not run here).
mutation: AC12 remove `%XML.Adaptor` from `Watch.Msg.Failure` -> `Test.Watch.Poller:TestBatchExportsAsXml` red (ERROR #6249); reverted, tree byte-identical.
mutation: AC1 (timeline order) key the timeline by sequence alone in `Watch.Summary.Event` -> `Test.Watch.Summary:TestTimelineOrder` red (two assertions); reverted, tree byte-identical.
mutation: AC1 (interrupted fix) never read `Interrupted` in `Watch.Summary.RunEvents` -> `Test.Watch.Summary:TestRunEdges` red; reverted, tree byte-identical.
mutation: AC3 (groups only without a fix) list the groups whenever the incident has any -> `Test.Watch.Summary:TestGroupsOnlyWithoutFix` red; reverted, tree byte-identical.
mutation: AC13 the phone's name is "phone" in `Watch.Summary` `CHANNELNAMES` -> `Test.Watch.Summary:TestChannelNames` red; an unnamed channel falls back to its internal id -> `TestAnswerEdges` red; reverted, tree byte-identical.
mutation: AC14 `Watch.Summary.Clean` removes `<`, `>` and `*` -> `Test.Watch.Summary:TestMarkup` red (stored slots and the rendered lines of the three channels); the per-channel delivery cases (`Test.Core.WebChatOut:TestSummaryCard`, `Test.Demo.SimPhoneOut:TestSummaryMessage`, `Test.Channel.TelegramOut:TestSummary`) pin each channel's text and, for Telegram, the absence of a parse mode; reverted, tree byte-identical.
mutation: AC15 name the answerer on the online demo too (drop the `'onlineDemo` test) -> `Test.Watch.Summary:TestUserName` red; reverted, tree byte-identical.
mutation: AC16 the item presses nothing when no card is resolved -> `web/e2e/guide/more-to-try.spec.ts` K26 (CI, not run here).
mutation: AC17 n/a here: `live:install-upgrade` (CI) runs the upgrade harness; the empty-summary read is pinned by `Test.Watch.Summary:TestText` and `Test.Tools.RecentActivity:TestIncidentSummary` (a closed incident with no summary gives none).
mutation: AC18 README line 30 says "seven more things" -> `web/scripts/more-to-try-view.test.mjs` "counts the items by the registry" red; reverted, tree byte-identical.

(QA) Tests added or extended (QA stage, 2026-11-09), no test removed or weakened:
- (QA) `Test/Watch/Summary.cls` `TestMarkupCut`, `TestPlaceholderText`, `TestInvisibleText` (AC14) and the shared fixture `Built`/`CutLine`; `Test/Core/WebChatOut.cls` `TestSummaryBuilt`, `Test/Demo/SimPhoneOut.cls` `TestSummaryBuiltMessage`, `Test/Channel/TelegramOut.cls` `TestSummaryBuilt` (AC14, one per channel, through `Build`: markup literal, sample error cut to the notice's length, Telegram with no parse mode); `Test/Tools/RecentActivityTurn.cls` `TestIncidentSummaryAnotherSessionInTheChat` (AC7 through the real chat turn).
- (QA) Product fix inside this story's own file: `Watch/Summary.cls` `Clean` (and the sample-error part) now returns "" for text that shows nothing, so a cause, evidence, fix or sample error made of invisible characters cannot make the stored summary unrenderable (found by `TestInvisibleText`: `Catalog.Render` refused the empty `summary.cause` slot, so no card, message or tool text could be made).
mutation: AC14 (QA) the sample error part is not cut (`Build` uses `Clean(incident.SampleError)` in place of the notice's `ErrorText.Summary`) -> `Test.Watch.Summary:TestMarkupCut`, `Test.Core.WebChatOut:TestSummaryBuilt`, `Test.Demo.SimPhoneOut:TestSummaryBuiltMessage` and `Test.Channel.TelegramOut:TestSummaryBuilt` red; reverted, tree byte-identical.
mutation: AC14 (QA) the old `Clean` (no test for text that shows nothing) -> `Test.Watch.Summary:TestInvisibleText` red (`summary.cause` slot empty) before the fix; green with it.
mutation: AC7 (QA) `Data.Ownership` `INCIDENTVISIBLE` gains `OR 1 = 1` (every session sees every incident) -> `Test.Tools.RecentActivityTurn:TestIncidentSummaryAnotherSessionInTheChat` red (B's tool result carried A's summary) and `Test.Tools.RecentActivity:TestIncidentSummaryAnotherSession` red; reverted, tree byte-identical.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** On every accepted move into `closed`, `IncidentManager.Closing` builds the incident's summary in code (`Watch.Summary.Build`, no model request), stores it in `Incident.Summary` (storage slot 29) in `Move`'s one save with `ClosedAt`, and sends one `summary` Notification (`summary.title`, no slots) per recipient. WebChat, SimPhone and Telegram `Out` render the stored summary through `Watch.Summary.Text` and `DigestText`; Telegram sends it as plain text. The read-only, untrusted `incident_summary` tool returns it for the session's newest closed visible incident. More to try gains the first item "Read the incident summary" (closes the guide's resolved incident, else sends "Show me the incident summary"). DW-877: `Watch.Msg.Failure` extends `%XML.Adaptor`.

**Files changed.** Core: `Watch/Summary.cls` (new builder and reader), `Watch/IncidentManager.cls` (`Closing`), `Watch/Notice.cls` (`Common`, `Noun`, `Groups` extended), `Data/Incident.cls` (`Summary`), `Data/Ownership.cls` (web summary cards survive a reload), `Msg/Enum.cls`, `Msg/Catalog/Watch.cls` (26 keys), `Watch/Msg/Failure.cls`; channels `Channel/{WebChat,SimPhone,Telegram}/Out.cls`; tool `Tools/{Names,RecentActivity,Watching}.cls`, `Agent/Chat.cls`, `ci/mock/scenarios/A/incident-summary.json`, `docs/security-overview.md`; demo `Demo/Features.cls`; web `chat/*`, `guide/*`; README line 30 and bullet; EXPERIENCE.md marked lines; tests in `Test/**`, `web/scripts`, `web/e2e`.

**Review.** 36 findings: patches applied 9 (medium 6, low 3: the JSDoc move, the "not B's" assertion and the AC13-AC18 mutation lines), items deferred 0, rejected the rest with the reasons in the Review Triage Log.

**Follow-up review recommended: true.** Unverified risk: the browser units (`web/e2e/guide/more-to-try.spec.ts` K25 and K26, `web/e2e/chat/notice.spec.ts` N20, the demo-path specs) and `live:install-upgrade`, the shards and the fresh-environment check are CI-only and not run here.

**Verification performed.** Warm: `Test.Watch.Summary`, `Lifecycle`, `Poller`, `Msg.Catalog`, `Tools.RecentActivity`, `Agent.Constants`, `Agent.Instructions`, `Watch.Tools`, `Bridge.Gate`, `Install.SecurityOverview`, `Channel.TelegramOut`, `Core.WebChatOut`, `Demo.SimPhoneOut`, `Demo.Features`, `Demo.Guide`, `Demo.BreakFeedIn` all passed; fresh: `Watch.Closing`, `Tools.RecentActivityTurn`, `Agent.Runners` passed. `node --test` of the five web scripts (191 tests), `docker/tests/test-mock.sh` (134), `test-storage.sh`, `test-boundaries.sh` and `npm --prefix web run lint` passed. After the patches: `Test.Watch.Summary` and `Test.Tools.RecentActivity` green again on the warm stack; warm and fresh throwaways torn down.

**Residual risks.** A summary cost counts the diagnosis decision only (the spec's basis); an answer from a channel other than web, phone, Telegram, mailbox or email gets no answer line; the More to try fallback button sends nothing while a turn is in flight.
