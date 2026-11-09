---
title: 'Story 23.6: Write an incident summary when an incident closes'
type: 'feature'
created: '2026-11-09'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
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

## Spec Change Log

- 2026-11-09 (runner, spec gate): orchestrator rulings on the contended paths recorded under Design Notes; Planner rulings pending.

## Review Triage Log

## Design Notes

**Architecture decisions:** AD-4 (ownership, no user name in production messages), AD-10 (read-only, untrusted tool through the gate), AD-11 (approval rows are the answer source), AD-15 (IncidentManager is the one writer; the close rows of the transition table), AD-16 (FixRun counts), AD-20 (cost from usage rows, per incident), AD-22 (tool name in the CI mock), AD-27 (purge with the incident), AD-29/AD-33 (lane ownership; see Veto-window items), AD-32 (notification contract, catalog, renderer).

**How the summary appears at the end of the guide's incident (decided in-stage).** With demo mode on, the guide's resolved incident closes only on Dismiss, Break the feed again (the replay rule) or 15 quiet minutes; Run again only writes a guide marker (`Web/Api.cls:770-786`). The smallest design that keeps UJ-1 real: the visitor closes it. The More to try panel opens by itself at the finish, and its new first item's control presses the card's own Dismiss, so the summary card lands in the chat and on the phone while the finish stays (`Guide.cls:112-113` counts a closed incident with no open variant as finished). Rejected: closing on the finish automatically (closes the visitor's incident without a press, against EXPERIENCE's "nothing is pressed without a press", and changes spec 07's Run again path). Measured by reading code, so no Task 0 is needed: the close lands in `Apply`/`Move`, `Notify`'s general branch routes any new kind, and the finish rule holds for `closed`.

**Why the Notification carries no content.** The answerer's IRIS user name (local installs) and the untrusted evidence must not travel in a production message (AD-4), so `Slots` is `{}` and each `*Out` operation renders the stored summary through `Watch.Summary.Text(IncidentRef, channel)`, which reads the row and calls `DigestText.Text`. The Out operations still render (AD-32); the producer never does.

**Part order.** title; one line per timeline event sorted by time (first failure `FirstAt`; notice `NoticedAt`; each request `RaisedAt`; its answer `AnsweredAt`, or `ExpiresAt` for an expired one; each FixRun `StartedAt` and `EndedAt`, interrupted or ended; closing `closedAt`); cause and element, or no cause; evidence (the first evidence line of the diagnosis payload, omitted when none); sample error (omitted when empty); fix (`FixSummary`) or no fix ran; groups (fallback and no fix ran only); messages (failed = `Count`; resent, completed, failed again and skipped summed over FixRuns); cost. A cancelled request shows only its raised line. Page and acknowledgement lines do not exist until Story 23.4 adds rows; the timeline sort leaves room for them.

**Decided in-stage.** (1) The summary is a column on `Incident`, not a table: "stored with the incident", purged by the existing row delete. (2) Cost when the decision has no usage rows is `$0` through `summary.cost`; an empty `CostUSD` row gives `summary.costUnknown`. (3) The answerer is named on a local install whenever `AnsweredBy` is known (a summary is a record to share), never on the online demo. (4) The tool takes no arguments and answers the newest closed visible incident with a summary (the CI mock sends static input). (5) The tool renders with channel `web`; no summary key has a `web` variant, so the text is the same on every channel. (6) The More to try item is first, because it continues the incident the visitor has just finished; the Planner may rule it last, and the tests follow the ruled order. (7) The panel is not at capacity: there is no item cap, and the panel scrolls in its own window (`more-to-try-room.ts`); no grouping is proposed. (8) No Task 0: every uncertain path was settled by reading code (above).

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

## Public Text

All drafts (EXPERIENCE.md and the PRD fix none of them; FR-30 fixes only the contents). Slot types in brackets.

Catalog keys, `src/ocutalon/cls/OcuTalon/Msg/Catalog/Watch.cls`, appended after `digest.cost` (~line 609):
- `summary.title`: "Incident summary: {count} {itemNoun} failed in {production}." [count count, itemNoun noun, production text]
- `summary.firstFailure`: "{time}: first failure." [time]
- `summary.noticed`: "{time}: OcuTalon told you." [time]
- `summary.requested`: "{time}: approval requested to repair and resend {count} {itemNoun}." [time, count, itemNoun noun]
- `summary.approved`: "{time}: approved from {channel}." [time, channel]
- `summary.approvedBy`: "{time}: approved by {user} from {channel}." [time, user text, channel]
- `summary.rejected`: "{time}: rejected from {channel}." [time, channel]
- `summary.rejectedBy`: "{time}: rejected by {user} from {channel}." [time, user text, channel]
- `summary.expired`: "{time}: the approval request expired." [time]
- `summary.fixStarted`: "{time}: the fix started." [time]
- `summary.fixEnded`: "{time}: the fix ended: {resent} resent, {completed} completed, {failedAgain} failed again, {skipped} skipped." [time, four count]
- `summary.fixInterrupted`: "{time}: the fix was interrupted after {resent} resent." [time, resent count]
- `summary.closedDismiss`: "{time}: closed by Dismiss." [time]
- `summary.closedReplay`: "{time}: closed when Break the feed was pressed again." [time]
- `summary.closedQuiet`: "{time}: closed after 15 quiet minutes." [time]
- `summary.cause`: "Cause: {cause}" [cause sentence]
- `summary.element`: "Element at fault: {element}." [element text]
- `summary.noCause`: "No cause was claimed: {fallbackReason}." [fallbackReason]
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

Run from `/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/epic-23`, one command per call with `timeout: 600000`, each finishing in about 150 s; never two test runs in one message. Prefix every `ci/` call with `OCUTALON_LOCK_DIR=/Users/jbrandt/git/contests/contest-49/OcuTalon/.worktrees/.coordination/locks/lane-d OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=23 stage=implement'`. Fresh tag `e23s6i`, warm tag `e23s6iw`; at the end `ci/warm.sh down`, then `ci/iris.sh teardown` with `e23s6i`. Every IRIS MCP call names `server` `ocutalon-slot-d` and `namespace` `OCUTALON`.

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
