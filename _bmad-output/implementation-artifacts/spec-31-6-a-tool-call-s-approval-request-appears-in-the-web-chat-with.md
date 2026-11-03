---
title: 'Story 31.6: a tool call''s approval request appears in the web chat with Approve and Reject (card)'
type: 'feature'
created: '2026-11-02'
status: 'done'
baseline_revision: 'fe6d6ed585ae1599ad17d355f896f3c47469ec73'
baseline_commit: 'fe6d6ed585ae1599ad17d355f896f3c47469ec73'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred:
  - summary: >-
      The chat announces a tool-call request or result notice through the generic notice branch (its full multi-line text), and no test pins what is spoken or that it is spoken once next to the request card's own announcements.
    evidence: |-
      chat-announcements.ts announces every unheard notice that is not a tell now as entry.text.trim(); Story 31.6 lets kinds approval and result into that list. No chat-announcements unit case names either kind, and X13 asserts no announcement. Whether a request is spoken twice (chat plus card) is unverified; a screen-reader pass or a unit case on the announcement list would settle it.
    location: >-
      web/src/app/chat/chat-announcements.ts:107
    severity: low (unverified)
---

<intent-contract>

## Intent

**Problem:** Since Story 31.5, a replayable session tool call sends its notices (`approval`, `answered`, `result`) to every channel, but the web chat shows none of them: `WebChatOut` records the web copy as a Delivery row with no text and no event (its `INCIDENTKINDS` path). So the web chat has no card with Approve and Reject for a tool call (FR-8; PRD "Channels"), no result message, and no web copy of DW-454's held-call reason. The phone and the paired chat already have all three.

**Approach:** `WebChatOut` renders the five `toolCall.*` notices for the web and publishes them as `notification` events through its existing card path. `Ownership.RecentNotices` keeps them, so they survive a reload. The chat panel draws a request notice with `ApprovalRequestCard`, bound to the store's `approval` payload, and answers through the existing `ApiClient.answerApproval`. A result shows as a plain notice with no buttons. The phone and the web chat render the same Notification, built by `BridgeSink` with `ServerOf` and `InputsOf`, so their texts always match.

## Boundaries & Constraints

**Always:**
- **Which notices become web cards.** A Notification is a tool-call card when all three hold:
  - its `Kind` is `approval` or `result`;
  - its `ApprovalRef` is set;
  - its `CatalogKey` is one of `BridgeSink`'s five tool-call keys (`KEYREQUEST`, `KEYREQUESTON`, `KEYDONE`, `KEYFAILED`, `KEYFAILEDWHY`), read with `$Parameter`, never copied.

  Such a card takes WebChatOut's existing card path: it is rendered for `web`, recorded with a new Ref as ChannelMessageId (with the ApprovalRef, kind, text and DecisionRef), and published as one `notification` event. Everything else is recorded as today: every other incident-kind notice (a fix's, any key outside the five) and kind `answered`, always.
- **One text, one source (U-212 (1)(2), DW-601).** The card's request text is WebChatOut's web render of the very Notification that `BridgeSink` built: the `server` and `inputs` slots that `ServerOf` and `InputsOf` produced. The page never derives, cuts or redacts a tool call's text, and no second implementation of the server rule or the inputs line exists. The first line is 'Run {tool} on {server}' when the server is known, else 'Run {tool}'. The inputs are one line, redacted, at most 200 characters, ending with '…' when cut. The card and the phone show the same strings.
- **The card.** The chat panel draws a notice of kind `approval` as `ApprovalRequestCard` when the live store holds an `approval` payload for its `approvalRef`. Its state, buttons, answered status and announcements come from that payload, as for a fix's card:
  - its action is the request text;
  - its Approve and Reject names come from the text's first line ("Approve: run zz_send on ops-mcp");
  - a press goes through `AnswerPress` and `ApiClient.answerApproval` with channel `web`.
- **First answer wins across every copy** (web card, simulated phone, paired chat). This is the existing answer API: the row is the truth (AD-11), and a later answer gets 409 `already_answered` and changes nothing. Every copy shows the first answer's line: the card through the store's payload, the phone through Story 31.5's in-place edit.
- **The Q3 reading (kept).** An answer edits the request in place: the card's buttons give way to its answered status. The result is a new chat message (a notice) with no buttons, and the card keeps its status.
- **U-222 (owner decision, kept with one condition).** After a reload, an answered, expired or finished tool-call request must not look pending. A request notice whose `approval` payload the store does not hold is a plain notice: its request text, no buttons, no "Approval needed" label, no badge, and no pending colour (not the request card's pending accent bar, not the tell-now attention bar). Its result notice follows it. A pending request is drawn as a live card again (the snapshot's `rail.approvals` holds it).
- **DW-454, the web half (W10).** An old held call's result notice (`toolCall.failedWithReason`, DecisionRef set) shows in the web chat as a plain notice with the reason and no buttons, and so does the raw-reason case's `toolCall.failed`.
- Every test added or changed creates and removes its own rows, phone messages and web Delivery rows, and passes on a fresh stack in either order.

**Never:**
- **Never edit these files:**
  - Lane A: `Watch/**`, `Fix/**`, `src/bridge/**`, `Test/Bridge/**`, `Test/Watch/**`;
  - `Test/Live/Payloads.cls` and `Web/Api.cls` (U-222: the answered line after a reload is DW-592, routed to the first daily release after 1.0.0);
  - `Test/Data/Fixture.cls` (calling it is fine);
  - `web/e2e/support/**` (importing is fine), above all `web/e2e/support/floor.ts`, plus `web/e2e/banners/banners.spec.ts` and `web/e2e-online/**`;
  - Epic 12's `web/src/app/rail/telegram-card/**`, `Channel/Telegram/**` and `Test/Channel/**`;
  - `web/src/app/icon/icon.ts`, `ci/units.sh` and `.github/**`.
- No change to the `approval` or `notification` payload, `live-store.ts`, `api-types.ts`, `payloads.ts` or `BridgeSink`.
- No catalog change (`Msg/Catalog/Core.cls`, `Test/Msg/Catalog.cls`, `web/scripts/catalog.mjs`, `catalog.ts`). No new page string (`ux-strings.test.mjs` unchanged). No new stored property, column, global or table. No new CI job, group or unit.
- No second card component and no second answer path. Nothing in the page builds a tool call's text.
- No card or notice for a fix from this path: a fix keeps its card inside the incident card.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Card raised | a session's replayable `tool_call` row, ToolSource `mcp:zzx13`, page open; `approval.raised` | the web chat gets one `notification` (kind `approval`, approvalRef the Ref, text the web render of `toolCall.requestOnServer`), drawn as `ApprovalRequestCard` with action "Run zz_tool_x13 on zzx13\nInputs: …\nNo dry run is available for this tool. Approving runs exactly this call once.", Approve and Reject named "Approve: run zz_tool_x13 on zzx13" | server unknown: "Run zz_tool_x13" |
| Same strings (U-212, DW-601) | ToolArguments whose redacted one-line text is over 200 characters | the card's action equals the phone message's text exactly; its inputs line is 200 characters ending with '…' | none |
| Web answers first | Approve on the card | 200; within 2 s the card's status reads "Approved from the web chat at H:MM" and its buttons are gone; within 5 s of the reply the phone's request message holds "Approved from the web chat at HH:MM." | none |
| Second answer | any copy answers after the first | 409 `already_answered`; the row keeps the first answer; no copy changes | none |
| Phone answers first | the phone's answer and its `approval.answered`, card open | the card's buttons give way to "Approved from the simulated phone at H:MM" (the store's payload) | none |
| Result | `approval.result`, Result `done` (or `failed`) | a new web notice after the card: "zz_tool_x13 ran once at HH:MM." (or `toolCall.failed`'s text), no button; the card keeps its status | none |
| Reload after the answer (U-222) | the request answered (or expired, or finished); page reloaded | the request is a plain notice with its request text, no buttons, no "Approval needed", no pending bar or attention bar, no `[data-part="approval"]` for it, no rail row; its result notice follows it | none |
| Reload while pending | a pending request; page reloaded | a live card with Approve and Reject again | none |
| Held reason (DW-454) | an old held row; `decision.recorded` with `HELDBEFOREUPDATE` | a web notice "zz_send didn't run. This request was held before an update and cannot be run again safely, so please ask again.", decisionRef set, no buttons | raw reason: `toolCall.failed`'s text, never the raw line |
| Not a tool-call card | kind `answered` with a tool-call ApprovalRef; a `toolCall.*` key with no ApprovalRef; a fix's `approval` notice; any key outside the five | Delivery row only (no text, no ChannelMessageId, no event); not in `RecentNotices` | none |
| Render fails | a tool-call card whose slots do not render | an error status with no row and no event, as for any card (the existing path; `TestRenderErrorRecordsNothing`) | returned |

</intent-contract>

## Code Map

Line numbers are at `99de6badca4bcf7609dbce636e9077f7a14ec0ad`.

**IRIS: change**
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- doc :1-18, `CARDKINDS` :26, `INCIDENTKINDS` :29, `OnNotification` :51-64: the card path, with render, `Delivery.Record` (new Ref as ChannelMessageId) and `Announce` of `notification`. The non-card branch is :55-57. Siblings: the allowance cards (Story 16.9) took this same path.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- `RecentNotices` doc :316-321; its statement :780-783 (`Kind IN ('tellnow', 'reminder', 'allowance')`). An empty `%String` is SQL NULL (31.5 measured `= ''` matching nothing), so test `ChannelMessageId IS NOT NULL`.

**IRIS: read only**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls` -- `KEYREQUEST` :86 to `KEYFAILEDWHY` :94 (public parameters). `ToolNoticeOf` :232-254 builds the slots with `ServerOf` :271 and `InputsOf` :285 (private; they stay private, DW-601 W2). `HeldNotice` :313-350 sends `toolCall.failedWithReason` or `toolCall.failed` with DecisionRef. `Compose` :257.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` :559-599 -- the five keys, `text` only (no `web` form), so the web render equals the phone render (no time in the request; `{time}` renders alike on both channels).
- `src/ocutalon/cls/OcuTalon/Live/Payload/Notification.cls` `FromRow` :44-64 -- ref = ChannelMessageId, kind, text (whole for non-tellnow), approvalRef, decisionRef and decision.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls` :854-859 -- turns each `RecentNotices` row into a snapshot chat `notification` item; `rail.approvals` serves pending rows only (DW-592).
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` -- every notification goes to WebChatOut.

**Page: change** (Angular, signals)
- `web/src/app/chat/chat-view.ts` -- `NoticeKind` :128, `NoticeView` :131-150, `noticeOf` :196-225 (takes tellnow, reminder and allowance only).
- `web/src/app/chat/chat-panel.ts`:
  - the `@for` template :146-164 (incident cards get `[approvals]="live.store()?.approvals"` :158; else `app-notice-card` :162);
  - `instanceZone`, `onlineDemo` and `user` :295-304, `entries` :310-328;
  - `showNew` :428-438 finds the target by `data-part` and `data-key` (a notice's target is part `notice`, key `notification:<ref>`); `noteArrivals` :442.
- `web/src/app/chat/notice-card.ts` -- template :28, `.text` :94-99 (no `pre-line`), `icon` :113-116 (bell-ring, circle-alert, else bell).
- `web/src/app/approvals/approval-request-card.ts`:
  - `approvalContext` :54-65 (exported); the template :102 (`.label` with class `pending`, `.action` :105, the buttons, `.status`);
  - inputs :372-390; `view` :419 = `approvalView(this.shown(), this.ctx())`.
- `web/src/app/approvals/approval-view.ts` -- `approvalView` :240-269. `action` is `'{title}.'` and the names are `Approve: {lowerFirst(title)}`, with the title from `rail-view.ts` `approvalTitle` :173 ("Run {toolName}"). The phone's caller is `phone/phone-request.ts` :239 (unchanged).
- Reference only: `incidents/incident-card.ts` :110-120 and :360, the pattern for building the card's context. `live/live-store.ts` :132 seeds `approvals` from `snapshot.rail.approvals` (pending only); :177-178 replace a payload per event.

**Tests: IRIS**
- `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls` -- slot-safe shadow instance. Its pattern is `TestAllowanceCards` :187; `TestIncidentKindsRecordOnly` :169 uses `AssertRecordOnly` :315 with key `zz.notRendered`, so it stays green. Helpers: `Session` :334, `Out` :342, `Notification` :350, `Notifications` :368, `Newest` :374, `LastRow` :387.
- `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` -- `TestRecentNotices` :832 (a web `incident` row with a ChannelMessageId stays out; unchanged) and `TestRecentNoticesIncludeAllowanceCards` :961; `Fixture.Delivery(owner, fields)` (`Test/Data/Fixture.cls` :221; its default ChannelMessageId is a new Ref, and `"ChannelMessageId": ""` gives none).
- `src/ocutalon/cls/OcuTalon/Test/Core/ToolCallNotices.cls` -- production tests with the real replay. Doc :1-12 ("The phone is the only channel they read"). `TestApprovedCallReachesThePhone` :36, `TestRejectedAndExpiredEditInPlace` :73, helpers :111-264 (`Render` :256 renders for the phone). Old held rows come from `Test.Data.Fixture.Approval` and `Fixture.Decision`, as in `Test/Core/BridgeSink.cls` `TestHeldBeforeUpdateSaysWhy`.

**Tests: page**
- `web/scripts/chat-view.test.mjs` -- :62 pins that incident-kind notices with no `approvalRef` stay out (unchanged).
- `web/scripts/approval-view.test.mjs` -- :129-135, the tool-call card with no request text ("Run zz_tool.", "Approve: run zz_tool").
- `web/scripts/approval-sources.test.mjs` -- pins the card's template and `band` source shapes (:224-250).
- `web/scripts/playwright-projects.test.mjs` -- :272-276 pins X1 to X12 and 22 answers cases.
- `web/e2e/answers/answers.spec.ts`:
  - spec-local: doc :9-24, `requestCard` :54, `open` :65, `messageOf` :59, `lineOf` :115, `replyBody` :118, `nextReply` :123, `startOf` :128, `hhmm` :48, `pageHhmm` :51, `PAGE_MS`/`PHONE_MS` :35/:38, `rowOfRequest` :62; X10's reload :740-742; `setApprovalFields` :819, `newestPhoneMessage` :836, X12 :856-920 (the phone half, unchanged);
  - imports: `seedApproval`, `sinkEvent`, `answerQuietly`, `readApproval`, `cleanFixtureRows`, `phoneMessage`, and `dropPhone` (which also deletes the session's web Delivery rows since the start).

## Tasks & Acceptance

**Execution:**

IRIS:
- [ ] `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls`:
  - Add a private `ToolCallCard(request)`: 1 when Kind is `approval` or `result`, ApprovalRef is set, and CatalogKey is in `$ListBuild` of the five `BridgeSink` KEY parameters (W2).
  - In `OnNotification`, a tool-call card takes the card path, unchanged. DueAt is "" and FallbackReason comes from `FallbackReasonOf`, which is "" for these keys.
  - Update the class doc: tool-call cards are a fourth card branch, and `INCIDENTKINDS` keeps recording the rest.
- [ ] `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` -- the `recentNotices` statement also takes web rows of Kind `approval` or `result` whose `ChannelMessageId IS NOT NULL` (only WebChatOut's tool-call cards have one). Update `RecentNotices`' doc.

IRIS tests:
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls` -- new `TestToolCallCards`, and update the class doc:
  - Each of the five keys with its kind (`approval` for the two request keys, `result` for the three others), an ApprovalRef and slots (for `toolCall.failedWithReason`, also a DecisionRef) behaves as a card. It is rendered for `web` (the exact text written out, times in HH:MM with onlineDemo off), recorded with a ChannelMessageId, the ApprovalRef, the kind and the DecisionRef, published as one `notification` event whose payload carries `approvalRef` and the text, and is in `RecentNotices`.
  - These record their Delivery row only, with no event, and are not in `RecentNotices`: a `toolCall.request` with no ApprovalRef; kind `answered` with `answered.approved` and an ApprovalRef; kind `approval` with `incident.laterRequest` and an ApprovalRef (a fix's).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Data/Ownership.cls` -- new `TestRecentNoticesIncludeToolCallCards`, beside :961: web rows of kind `approval` and `result` with a ChannelMessageId are cards, newest first; the same kinds with `"ChannelMessageId": ""`, and with channel `phone`, are not.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ToolCallNotices.cls` -- the integration ACs against the running production. Update the class doc.
  - In `TestApprovedCallReachesThePhone`:
    - after the request, the session has one web Delivery row of kind `approval` with a ChannelMessageId, the Ref as ApprovalRef, and text equal to the phone message's `Text` (DW-601: one Notification, one text), in `RecentNotices`;
    - after `done`, a second web row of kind `result` holds the web render of `toolCall.done`;
    - the answered notice adds a web row with no ChannelMessageId.
  - New `TestHeldReasonReachesTheWebChat` (DW-454's web half):
    1. A fixture session's old held `tool_call` row (`failed`, ToolSource ""), and a fallback Decision (kind `tool`, ItemId the Ref, Fallback 1, Reasons `$Parameter("OcuTalon.Bridge.Process.Decide","HELDBEFOREUPDATE")`).
    2. Call `##class(OcuTalon.Core.BridgeSink).OnEvent("decision.recorded", session, {"ref": decisionRef})`.
    3. Within WAIT s the web chat has one row of kind `result` with a ChannelMessageId, the decision's Ref as DecisionRef, and the web render of `toolCall.failedWithReason` (the sentence), in `RecentNotices`.
    4. It cleans its rows.

Page:
- [ ] `web/src/app/chat/chat-view.ts` -- `NoticeKind` gains `approval` and `result`; `NoticeView` gains an optional `approvalRef`. `noticeOf` takes kind `approval` and `result` only when `payload.approvalRef` is set (no whyNow split; strip false). New exported `liveRequest(notice, approvals)`: the store's `approval` payload of a notice of kind `approval` whose `approvalRef` the store holds, else `undefined` (W3). Update the docs.
- [ ] `web/src/app/chat/chat-panel.ts`:
  - A notice whose `liveRequest(entry, live.store()?.approvals ?? {})` is a payload is drawn inside a wrapper `<div class="tool-call" data-part="notice" [attr.data-key]="entry.key" tabindex="-1">`, as `<app-approval-request-card [approval]="…" [ctx]="approvalCtx()" [request]="entry.text" />` (W4).
  - Any other notice, a request with no payload in the store included, stays `app-notice-card`.
  - Add `approvalCtx = computed(() => approvalContext(Date.now(), instanceZone(), onlineDemo(), user()))`, as `incident-card.ts` :360 builds it.
- [ ] `web/src/app/chat/notice-card.ts` -- kinds `approval` and `result` use the existing `info` icon. Kind `approval` adds class `request`, whose `.text` keeps line breaks (`white-space: pre-line`). There is no other class, no accent override and no new string (W5). Update the doc.
- [ ] `web/src/app/approvals/approval-view.ts` -- `approvalView(approval, ctx, request = '')`. When `request` is set, `action` is that text, and `approveName`/`rejectName` use its first line with a lower-case first letter. Nothing else changes, and the phone's call is unchanged (W6).
- [ ] `web/src/app/approvals/approval-request-card.ts` -- a new optional input `request` (default `''`), passed to `approvalView`; `.action` gets `white-space: pre-line`. Update the class doc: the chat panel also draws it for a tool call.
- [ ] `web/scripts/chat-view.test.mjs` -- kind `approval` and `result` notices with an `approvalRef` become notices with that kind, text and Ref; without one they stay out (:62 unchanged). `liveRequest`:
  - a pending payload in the store gives it;
  - an absent payload (an answered request after a reload) gives `undefined`;
  - kind `result` gives `undefined`.
- [ ] `web/scripts/approval-view.test.mjs` -- a request text gives the action and both names from its first line, pending and answered; with no text, :129-135 still holds.
- [ ] `web/scripts/approval-sources.test.mjs`, and any other `web/scripts/*-sources.test.mjs` that pins the old shape of the card's `view` or the panel's template, take the new shape and nothing else.
- [ ] `web/scripts/playwright-projects.test.mjs` -- X1 to X13, and 23 answers cases.

Browser (Rule 3):
- [ ] `web/e2e/answers/answers.spec.ts` -- new X13 and its doc line. It is the one Playwright case for the web card, with the session's rows its own (W8):
  1. Seed a session `tool_call` row (`zz_tool_x13`, `dryRun: null`, requiredRole OcuTalonUser) with `seedApproval`. With `setApprovalFields`, set ToolSource `mcp:zzx13`, Runner `ChatAgent`, and ToolArguments `{"to":"ops","note":"<280 x>"}` (no hold exists, so approving replays nothing). `open(page)`, then `sinkEvent('approval.raised')`.
  2. The card (`requestCard(page, ref)`) appears within `CARD_MS`:
     - its `.action` textContent equals `phoneMessage(user, ref).text`;
     - its first line is "Run zz_tool_x13 on zzx13";
     - its inputs line is 200 characters ending with `…`;
     - it has Approve and Reject named "Approve: run zz_tool_x13 on zzx13" and "Reject: run zz_tool_x13 on zzx13".
  3. Approve on the card:
     - the reply is 200;
     - within `PAGE_MS` the card's status reads `Approved from the web chat at ${pageHhmm(answeredAt)}` and `.buttons` is gone;
     - within `PHONE_MS` of the reply, `phoneMessage(...).answer` is `Approved from the web chat at ${hhmm(answeredAt)}.`.
  4. `answerQuietly(user, ref, 'reject', 'phone')` gives `already_answered`, and `readApproval` still shows `approve|web`. Neither the card's status nor the phone's line changes.
  4b. The phone answers first, on a second request: seed and set up a second row `zz_tool_x13b` the same way, then `sinkEvent('approval.raised')`, and its card appears. Then:
     - `answerQuietly(user, ref2, 'approve', 'phone')` gives `done`, then `sinkEvent('approval.answered', { ref: ref2 })`;
     - within `PAGE_MS` the second card's status reads `Approved from the simulated phone at ${pageHhmm(answeredAt2)}` (AnsweredAt from `readApproval`), and its `.buttons` is gone (the store's payload drives the card).
  5. With `setApprovalFields`, set State `done`, Result `done` and FinishedAt, then `sinkEvent('approval.result')`. A new chat notice (`app-chat-panel [data-part="notice"]` with text `zz_tool_x13 ran once at ${hhmm(finishedAt)}.`) follows the card in the DOM, with no button, and the card keeps its status.
  6. U-222: `page.reload()`, then wait for `data-snapshot` `loaded`:
     - `requestCard(page, ref)` has count 0 and `rowOfRequest(page, ref)` has count 0;
     - the request is an `app-notice-card` notice whose text holds "Run zz_tool_x13 on zzx13";
     - it has no button, no "Approval needed" text, and no element with class `pending` or `bar-pending`;
     - its computed `border-inline-start-color` is not the request card's pending bar colour (read from a probe styled `border-inline-start: var(--approval-request-card-accent-bar-pending)`) and not the tell-now bar's;
     - the result notice follows it.
  7. In `finally`: `dropPhone` (it also deletes the session's web Delivery rows) and `cleanFixtureRows`.

**Acceptance Criteria:**
- Given a replayable session tool call, when it is raised, then the web chat shows a card with the phone's exact texts ('Run {tool} on {server}' or 'Run {tool}'; the redacted one-line inputs capped at 200 characters) and Approve and Reject. The texts come from the one Notification that `BridgeSink` built with `ServerOf`/`InputsOf`, never a second implementation (U-212, DW-601; X13 steps 1-2, `TestToolCallCards`, `ToolCallNotices`).
- Given the card, when any copy is answered first, then that answer wins: the card's buttons give way to the answered status within 2 s, the phone's request message holds the same answer within 5 s, and a later answer from any copy gets 409 and changes nothing. An answer from the phone replaces the card's buttons with its status (X13 steps 3, 4 and 4b).
- Given an answered tool call, when its result arrives, then the web chat shows it as a new notice with no buttons, and the card keeps its status (X13 step 5).
- Given an answered, expired or finished tool-call request, when the page is reloaded, then it shows as a plain notice with its request text and no buttons, no "Approval needed" label, no badge, no pending colour and no rail row, followed by its result. A pending one is a live card again (U-222; X13 step 6, `chat-view.test.mjs` `liveRequest`). The answered line after a reload is DW-592's, not this story's.
- Given an old held tool call that Decide closes with a catalog reason, when `decision.recorded` arrives, then the web chat shows the reason notice with no buttons (DW-454; `ToolCallNotices.TestHeldReasonReachesTheWebChat`, `TestToolCallCards`).
- Given a fix's request, or any notice outside the five tool-call keys, when it reaches WebChatOut, then nothing changes: the fix keeps its card inside the incident card (`TestIncidentKindsRecordOnly`, `live cards` and `live floor` unchanged).
- Given the demo path, when `live:demo-path` runs, then it passes unchanged: UJ-1 has no tool call.

## Spec Change Log

## Review Triage Log

### 2026-11-02 - Review pass
- verdicts: 20 findings - high 0, medium 1, low 12, false 6, maybe-false 1
- findings:
  - `[medium]` `[patch]` (verification-gap) matrix row "Reload while pending" had no test -- X13 got a step 7: a third pending request, a reload, a live card with Approve and Reject by name; passed in `live answers` (23 passed)
  - `[low]` `[patch]` (blind) the `ToolCallNotices` header said the web request and result rows are not cards while the test asserts they are -- header rewritten as its own bullet
  - `[maybe-false]` `[defer]` (blind, edge, verification-gap) the chat's generic notice announcement speaks a request or result in full and may double the card's own announcement; nothing pins it -- recorded in `deferred:`
  - `[low]` `[reject]` (blind, edge) `.action` CSS (`pre-line`, `overflow-wrap`) is shared by fix cards -- fix cards' actions have no newline and a long token now wraps instead of overflowing; no harm named
  - `[false]` `[reject]` (blind, intent) the dry-run block or "Nothing has changed yet." may double the request text -- a tool call's dryRun is null, `dryRunOf` returns undefined and no block is drawn (X13 passes with the stated texts)
  - `[false]` `[reject]` (edge) a held-reason result keeps decision and fallbackReason on the view -- `notice-card.ts` reads them only inside the decision strip, which `noticeOf` forces off for a tool call
  - `[false]` `[reject]` (edge) `ChannelMessageId` stored as an empty string would make fix rows cards -- the fixture rows set "" and `TestRecentNoticesIncludeToolCallCards` passes with them excluded
  - `[false]` `[reject]` (edge, blind) a render error now records no row for these kinds -- the spec's matrix row "Render fails" requires exactly that (existing `TestRenderErrorRecordsNothing`)
  - `[low]` `[reject]` (blind, edge) an empty CatalogKey would match a missing `$Parameter` -- the five parameters exist and a notification always carries a key; theoretical
  - `[low]` `[reject]` (edge, blind) first line empty gives an empty button name, and a non-tool_call payload with a request text -- only the chat panel passes `request`, only for the five keys, and the text always starts with "Run"
  - `[low]` `[reject]` (edge) the card may swap from a plain notice to the card if the notification event precedes `approval.raised` -- the store holds the payload from the same event stream; a one-frame order effect with no wrong final state
  - `[low]` `[reject]` (blind, edge) the wrapper `tabindex -1` nests a focus target -- the panel's New messages lookup is by `[data-part]`, which the wrapper carries by design; no wrong focus shown
  - `[low]` `[reject]` (edge) a pending request older than 100 newer notices has no card after a reload -- the 100 cap is the existing RecentNotices bound; theoretical
  - `[low]` `[reject]` (edge, intent) the page filters by kind and approvalRef only -- the page cannot see the catalog key; the server filter and the ChannelMessageId rule keep fix notices out (spec: nothing on the page derives)
  - `[low]` `[reject]` (blind) the `ChannelMessageId IS NOT NULL` discriminator is implicit -- it is the spec's rule ("recorded with a new Ref as ChannelMessageId"), pinned by `TestRecentNoticesIncludeToolCallCards`
  - `[low]` `[reject]` (blind, verification-gap) tests hard-code catalog text; `as NoticeKind` cast; no unit case for `requestOf`, the icon or the CSS class; no web case for Reject, expiry or the held reason in the DOM -- the wording is pinned on purpose, the rest is presentation or covered at the server (`TestHeldReasonReachesTheWebChat`)
  - `[low]` `[reject]` (verification-gap) AC 7 has no mutation line, the AC 5 held-reason test cannot see a one-key mutation on a warm stack, the X13 text equality maps non-ASCII to `?` -- the spec names AC 7's unit as unchanged, the stack limit and the helper limit are recorded in the Verification section, and the ellipsis is asserted separately
  - `[low]` `[reject]` (edge) result and held-reason texts may differ from the phone's on the online demo (" ET") -- the spec requires equality for the request only
  - `[false]` `[reject]` (verification-gap) WaitWebRow ignores ApprovalRef -- each test uses its own fresh session
  - `[false]` `[reject]` (intent-alignment) a descriptive report with no defect claim; its uncovered-surface notes are the rows above

## Design Notes

**U-212 (owner decision; verbatim, as in Story 31.5).** Veto U-212, kept by the Contest Planner under the owner's delegation with four conditions (`at=2026-11-02T13:19:05Z#648`): "Keep, with four conditions. (1) Match the card: the first line is 'Run {tool} on {server}' when the server is known, and 'Run {tool}' only when it isn't. (2) {inputs} stays on one line through the bridge's redactor, and is capped at 200 characters, ending with '…' when cut; the phone and paired chat never get more of a call's inputs than the card shows. (3) {reason} in toolCall.failedWithReason is only ever a catalog reason (such as U-214's), never raw error or exception text; a test pins it. (4) {time} uses the same labelled form as the other catalog times (DW-574 will unify zones later). The Q3 reading (answer edits the request in place; the result is a new message with no buttons, as for a fix in Story 6.4) is kept."

**U-222 (owner decision; verbatim).** Kept with one condition, `at=2026-11-02T18:27:03Z#671`: "Keep (ledger), with one condition. After a reload, an answered, expired or finished tool-call card must not look pending: no buttons (as ruled), and no 'awaiting approval' label, badge or colour that suggests it's still waiting. If the reloaded card shows any pending cue today, removing it is in 31.6 (cheap). The full answered line after a reload (/state serving answered tool-call requests) goes to the ledger, routed to the FIRST daily release after 1.0.0, not later." The full answered line is DW-592 (`owner=burndown`, first daily release after 1.0.0), so `Web/Api.cls` stays unchanged. The no-pending-cue condition is the Boundaries' U-222 rule, the matrix row "Reload after the answer", AC 4 and X13 step 6.

**Governing ADs (Rule 6):**
- **AD-32:** producers never render; only WebChatOut renders the web copy, through `Catalog.Render(key, slots, "web")`; Approve and Reject only for kind `approval` with an ApprovalRef; the result has none.
- **AD-14:** Notify already sends every notification to the web chat; there is one Delivery row per copy.
- **AD-12:** the page applies generated payloads and never changes one; no payload changes (the `notification` payload already carries `approvalRef`).
- **AD-33:** WebChatOut stays the one publisher of `notification`, and BridgeSink of `approval`.
- **AD-11:** the row is the truth: the card's state is the store's `approval` payload, and the 409 comes from the answer API.
- **AD-31:** BridgeSink is unchanged.
- **AD-29:** Lane B files only. **AD-22:** production tests run in throwaways.

No AD Rule is contradicted, and the spine needs no change.

**Decided in-stage (unattended, small, reversible):**
- **W1. The card's source is WebChatOut's `notification`, as planned (re-checked against the code at `99de6bad`).** 31.5's notices already reach WebChatOut through Notify and are only recorded today. Rendering them for the web keeps three things true:
  - the phone and web texts come from one Notification, so they match by construction;
  - the chat places the card and the result in its own order;
  - the snapshot keeps them (W3).

  Deriving the card from the `approval` payload alone would need `server` and `inputs` there, and `Test/Live/Payloads.cls` (on the Never list) pins that payload's exact contract.
- **W2. DW-601 through the notice's own slots.** The card's text is the web render of the slots that `ServerOf` and `InputsOf` produced, so the helpers stay private, and "made reachable" (the epics bullet) is met through the Notification. The dispatch allows the notice's slots, and no second implementation exists anywhere. WebChatOut reads the five keys from `BridgeSink`'s public KEY parameters, so a renamed key cannot drift.
- **W3. `RecentNotices` keeps the tool-call cards** by ChannelMessageId: WebChatOut gives one only to a card, and records every other incident-kind row without one (`AssertRecordOnly` pins it). After a reload:
  - a pending request is in `rail.approvals`, so it is a live card;
  - an answered, expired or finished one has no payload in the store, so `liveRequest` gives `undefined` and it is a plain notice (U-222).
- **W4. The wrapper `data-part="notice"`** keeps the New messages button's target (part `notice`, key `notification:<ref>`) focusable when the notice is drawn as a card. The card's own `data-part="approval"` sits inside it, as an incident card's does.
- **W5. The plain request notice and the result** use the existing `info` icon and the notice card's default info bar (`--notice-card-accent-bar`, blue), never the request card's pending bar (red) or the tell-now attention bar. The reloaded request keeps its catalog text as the record of what was asked. Its last sentence ("Approving runs exactly this call once.") is the request's wording, not a waiting label, badge or colour, so U-222 leaves it. `icon.ts` is Epic 12's, so no new icon.
- **W6. The card's Approve and Reject names come from the request's first line,** so they name the server ("Approve: run zz_send on ops-mcp"). The phone keeps its existing names (X12 pins them); unifying them is not needed for 1.0.0.
- **W7. No catalog change.** The five keys have no `web` form, so the web chat shows their `text`, the same as the phone. The card's status lines are the existing `answered.*` web forms. No new page string.
- **W8. X13 is a new case,** not an extension of X12: X12 stays the phone half that Story 31.5 delivered, and each case owns its rows. X13 uses inputs over 200 characters, so it pins U-212 (2) on the card.
- **W9. A tool_call row with an IncidentRef** is never drawn twice in practice: gate-held calls carry none (31.5: "empty for a gate-held call"). No rule is added for it (inference).
- **W10. DW-454's web half** is the same result notice the phone gets: the sentence, no Approve. A held-before-update row is not replayable, so it never gets a request card on any copy, and `ApprovalRequestCard` needs no reason line.

**Integration ACs (Rule 1):** no new service. WebChatOut, `RecentNotices`, the chat panel and the card are extended.
- **Consumes:**
  - Story 31.5: `BridgeSink`'s tool-call notices, the five keys, the slots from `ServerOf`/`InputsOf`, and DW-454's held notice;
  - Story 6.2: `ApprovalRequestCard`, `AnswerPress` and `ApiClient.answerApproval`;
  - Story 2.7: WebChatOut's card path and `RecentNotices`;
  - Story 16.9: the allowance card branch, the precedent for a new card kind.
- **Consumed-by:**
  - the chat panel reads WebChatOut's `notification` events and the snapshot's `RecentNotices`, and draws the card and the result notice (X13 against the real stack);
  - `Web/Api.cls` serves the kept cards after a reload (X13 step 6; unchanged code);
  - DW-592 (the first daily release after 1.0.0) adds the answered line after a reload.

**Extend, don't copy (Rule 2):**
- The card is `ApprovalRequestCard` (`web/src/app/approvals/approval-request-card.ts`), extended by one input, with its `AnswerPress` and `ApiClient.answerApproval`. There is no second component and no second answer path. The panel builds its context with the exported `approvalContext`, as `incident-card.ts` does.
- `approvalView` gains one optional parameter.
- The web cards take WebChatOut's existing card path (render, `Delivery.Record`, `Announce`), and the result is `NoticeCard`.
- X13 reuses the spec's own helpers (`open`, `requestCard`, `setApprovalFields`, `nextReply`, `replyBody`, `rowOfRequest`, `hhmm`, `pageHhmm`) and the support helpers.

**Ledger inbox (Rule 17):**
- **DW-454** (its web half, W10) is addressed by: the Boundaries' DW-454 rule, the matrix row "Held reason", `TestToolCallCards` (`toolCall.failedWithReason` with DecisionRef), `ToolCallNotices.TestHeldReasonReachesTheWebChat`, and AC 5.
- **DW-601** is addressed by: the Boundaries' "One text, one source" rule, W2, the `ToolCallNotices` text equality, X13 step 2 (the card's action equals the phone's text), and AC 1.

**Footprint extensions (Rule 11 (b)).** Paths outside Epic 31's paths_hint:
- `Channel/WebChat/Out.cls` and `Data/Ownership.cls`;
- `Test/Core/{WebChatOut,ToolCallNotices}.cls` and `Test/Data/Ownership.cls`;
- `web/scripts/{chat-view,approval-view,approval-sources,playwright-projects}.test.mjs`, plus any `*-sources.test.mjs` the shape change touches;
- `web/e2e/answers/answers.spec.ts`.

None is contended: the dispatch checked them free, this story does not touch the catalog files Epic 40 appends to, and Epic 12's `ux-strings.test.mjs` and `icon.ts` are unchanged. `new_units:` none (the classes already sit in `shard:lane-b`).

**Size (implement to commit): about 4.5 to 5.5 hours.**
- **What drives it:**
  - About 15 files: 2 IRIS product classes, 5 page files, 3 IRIS test classes, 4 page unit tests and 1 Playwright spec.
  - Two new slot-safe IRIS tests and one new production test (DW-454's web half), plus web assertions added to an existing one.
  - One Playwright case with a reload.
  - The (once) browser units `answers`, `cards`, `floor`, `sign-in` in three parts, and `demo-path`, plus the fresh shard pair.
- **By stage:**
  - Implement: about 2.5 h.
  - Self-review: about 0.5 h.
  - QA: about 0.75 h.
  - Review: about 0.75 h.
  - Smoke and the fresh check: about 1 h. The browser units alone take about 40 minutes locally.

## Verification

Use these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`, with tags `e31s6i` (fresh) and `e31s6iw` (warm).
- **One call at a time, in the foreground.** Pass `timeout: 600000` on every call. Run everything in the foreground, one test-runner call per message. Never background a run, never use `Monitor`, and never re-submit after a client-side timeout. If the harness moves a foreground call to the background after about 180 s, poll its output file in foreground loops under 170 s, never a second copy.
- **The only IRIS MCP target** is server `ocutalon-slot-c`, namespace `OCUTALON`. Check its identity with `iris_server_info` first, and pass `server` and `namespace` on every call.
- **Rebuild the bundle first.** Before any browser unit, run `ci/iris.sh build`, because the bundle is not rebuilt by itself (Rule 21).
- No real model key, ever.
- **DW-597.** `live answers` case C1 (`close-loop.spec.ts`) passes since Story 31.5's CI rework (its incident row carries the item noun, cause category and element, and its Dismiss reply is held for the owner's closed view). A red C1 counts against this story.

**Commands:**
- (loop) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes, including `chat-view`, `approval-view`, `approval-sources`, `chat-announcements`, `page-safety`, `announce-focus-sources`, `ux-strings` and `playwright-projects`.
- (loop) `npm --prefix web run lint` -- expected: exit 0.
- (loop) `node web/scripts/catalog.mjs --check` and `node web/scripts/payloads.mjs --check`, one per call -- expected: both current with no change.
- (loop) `OCUTALON_RUN_TAG=e31s6iw ci/warm.sh up` once. Then run each of these on its own call; each is expected to print `CLASS ... passed`:
  - `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s6iw ci/iris.sh class OcuTalon.Test.Core.WebChatOut`
  - `... class OcuTalon.Test.Data.Ownership`
  - `... class OcuTalon.Test.Core.ToolCallNotices`
  - `... class OcuTalon.Test.Core.BridgeSink` (unchanged)
  - `... class OcuTalon.Test.Core.RoutingProduction` (unchanged; it counts cards)

  At the stage's end, also after a failure: `OCUTALON_RUN_TAG=e31s6iw ci/warm.sh down`.
- (once) `OCUTALON_RUN_TAG=e31s6i ci/iris.sh build` -- expected: the bundle is rebuilt with the page changes.
- (once) `OCUTALON_RUN_TAG=e31s6i ci/iris.sh live answers` -- expected: X1 to X13 and C1 to C10 pass.
- (once) `OCUTALON_RUN_TAG=e31s6i ci/iris.sh live cards` -- expected: passes (a fix's request card is unchanged).
- (once) `OCUTALON_RUN_TAG=e31s6i ci/iris.sh live floor` -- expected: passes (floor/approval.spec A1 and the focus and announcement specs).
- (once) `OCUTALON_RUN_TAG=e31s6i ci/iris.sh live sign-in --part 1/3`, then `--part 2/3`, then `--part 3/3`, one per call -- expected: every part passes (the chat and notice specs).
- (once) `OCUTALON_RUN_TAG=e31s6i ci/iris.sh live demo-path` -- expected: passes (UJ-1).
- (once) Fresh, Rule 19, one per call: `OCUTALON_RUN_TAG=e31s6i ci/iris.sh shard lane-b@Core,Data`, then the same with `--reverse`, then `... shard lane-b@Demo,Schedule`, then the same with `--reverse` -- expected: every class passes, with `STACK ...: project` and no `WARM` line. If a call nears 8 minutes, split it into one area per call.
- (once) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-storage.sh` and `bash docker/tests/test-ci-config.sh`, one per call -- expected: all pass.
- (once) `OCUTALON_RUN_TAG=e31s6i ci/iris.sh teardown`.

**Shared surfaces:**
- **WebChatOut's record-only kinds.** `Test.Core.WebChatOut` `TestIncidentKindsRecordOnly` uses key `zz.notRendered`, so it is unchanged.
- **The snapshot's chat cards (`Ownership.RecentNotices`).** These tests count a session's cards: `Test.Demo.SimPhoneOut`, `Test.Schedule.Reminders`, `Test.Core.AllowanceInProduction`, `Test.Core.RoutingProduction`, and `Test.Data.Ownership` `TestRecentNotices` (whose web `incident` row with a ChannelMessageId stays out). Confirm each seeds no replayable tool call.
- **The chat's notice kinds.** `chat-view.test.mjs` :62: notices with no `approvalRef` stay out.
- **`[data-part="approval"]` and `[data-part="notice"]` inside `app-chat-panel`.** A tool-call card appears only for a replayable row. Only X12 and X13 seed one, and `dropPhone` removes their web rows.
- **The session's `notification` events.** `Test.Bridge.Approval` `TestReplayReachesTheLiveStream` filters its stream by type `approval` (read only; unchanged).
- **The answers project's case list.** `playwright-projects.test.mjs` goes from X1-X12 and 22 cases to X1-X13 and 23.
- **The card's and panel's template pins** (`approval-sources`, `announce-focus-sources`, `page-safety`).

Every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations applied** (observed red, reverted, `git diff --stat` unchanged; X13 runs used the answers project with X1 to X12 skipped in a temporary copy of the spec, restored after):
- **AC 1:**
  - mutation: drop `ToolCallCard` from `OnNotification` → `TestToolCallCards` red (the five cards missing) and, on a fresh stack, `ToolCallNotices.TestApprovedCallReachesThePhone` (the web `approval` and `result` rows, the two cards) and `TestHeldReasonReachesTheWebChat` red;
  - mutation: drop the card's `[request]="entry.text"` binding → X13 step 2 red (the action reads "Run zz_tool_x13.");
  - mutation: render a request notice as `toolCall.request` whatever its key → `TestToolCallCards` red (`toolCall.requestOnServer` text and payload).
- **AC 2:** mutation: bind the card's `[approval]` to a fixed `{ref, kind: 'tool_call', state: 'pending'}` → X13 step 4b red (the second card never shows the phone's answer); steps 3 and 4 passed under it, as the spec says (the answer API and Story 31.5's edit are theirs).
- **AC 3:** mutation: take kind `result` out of `ToolCallCard` → `TestToolCallCards` red (`toolCall.done`, `toolCall.failed`, `toolCall.failedWithReason`) and X13 step 5 red (no result notice).
- **AC 4 (U-222):**
  - mutation: `liveRequest` returns a pending stand-in when the store has no payload → `chat-view.test.mjs` `liveRequest` "gives undefined for a request the store does not hold" red and X13 step 6 red (`requestCard` count is not 0 after the reload);
  - mutation: drop the `RecentNotices` change → `TestRecentNoticesIncludeToolCallCards` red and X13 step 6 red (no plain notice after the reload).
  - X13 step 7 (a pending request is a live card again after a reload, matrix row "Reload while pending") shares both mutations above: either turns the test red at an earlier step, so no mutation isolates step 7 alone; it passed on a fresh stack.
- **AC 5:** mutation: take `KEYFAILEDWHY` out of `ToolCallCard` → `TestToolCallCards` red (`toolCall.failedWithReason`). `ToolCallNotices.TestHeldReasonReachesTheWebChat` went red under the fresh-stack mutation of AC 1; a mutation of this one key is not seen by it on a warm stack, because the production's running hosts keep the code they started with.
- **AC 6:** mutation: replace the key check of `ToolCallCard` with `Quit 1` → `TestToolCallCards` red on the fix's `incident.laterRequest` (kind `approval` with an ApprovalRef; the existing `TestIncidentKindsRecordOnly` goes red too).
- **AC 7:** none (the existing unit, unchanged).

**Manual checks:**
- `git status --short` shows no path from the Never list, and no change to `BridgeSink.cls`, `Msg/Catalog/Core.cls`, `Test/Msg/Catalog.cls`, `web/src/app/live/**`, `api-types.ts`, `catalog.ts` or `ux-strings.test.mjs`.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A tool call's request, result and held-call reason (the five `toolCall.*` keys of `BridgeSink`) are now cards of the web chat. `WebChatOut` renders them for the web and publishes them as `notification` events; `Ownership.RecentNotices` keeps them across a reload; the chat panel draws a request as `ApprovalRequestCard` while the store holds its `approval` payload and as a plain notice otherwise (U-222). The card's text is the phone's (DW-601).

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls`: `ToolCallCard` and the card path for it.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`: `RecentNotices` includes web rows of kind approval or result with a ChannelMessageId.
- `web/src/app/chat/chat-view.ts`, `chat-panel.ts`, `notice-card.ts`: the notice kinds, `liveRequest`, the card branch, the plain form.
- `web/src/app/approvals/approval-view.ts`, `approval-request-card.ts`: optional `request` text as the action and the button names.
- Tests: `Test/Core/WebChatOut.cls`, `Test/Core/ToolCallNotices.cls`, `Test/Data/Ownership.cls`, `web/scripts/{chat-view,approval-view,playwright-projects}.test.mjs`, `web/e2e/answers/answers.spec.ts` (X13).

**Review.** 20 triaged findings (grouped by claim) from four layers: patches applied 2 (one medium: X13 step 7, "Reload while pending"; one low: the `ToolCallNotices` header), deferred 1 (the announcement of the new notices, unverified), rejected the rest with the reasons in the triage log.

**Follow-up review recommended:** false (no high patched; one medium patched).

**Verification.** `npm --prefix web test` 1262 pass, `npm --prefix web run lint`, `catalog.mjs --check` and `payloads.mjs --check` current; warm classes `WebChatOut`, `Data.Ownership`, `ToolCallNotices`, `BridgeSink`, `RoutingProduction` passed on the lead's own run; after the review patches, `ci/iris.sh build` and `live answers` (23 passed: X1-X13, C1-C10) and `test-class-rules.sh` passed. The implement stage's own runs of `cards` (20), `floor` (107), `sign-in` parts 1-3, `demo-path`, fresh shards `lane-b@Core,Data` and `lane-b@Demo,Schedule` (forward and reverse; one `Schedule.Heartbeat` flake on the first reverse run, green on the rerun), and the `test-boundaries`, `test-storage` and `test-ci-config` scripts passed before the patches; the patches touched only X13 and a class header comment, so those were not repeated.

**Residual risks.** Announcement of the new notices unpinned (deferred). The held-reason notice is proved at the server and by unit tests, not in the browser DOM. `Schedule.Heartbeat.TestStubSkipped` showed one order-dependent flake in a reverse shard run, unrelated to this change.
