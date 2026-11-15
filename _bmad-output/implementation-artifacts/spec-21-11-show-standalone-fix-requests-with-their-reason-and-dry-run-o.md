---
title: 'Story 21.11: Show standalone fix requests with their reason and dry run on every channel'
type: 'feature'
created: '2026-11-15'
status: 'done'
baseline_revision: '7f2ae7d5a9f70315e5cbce0345765c8051eb4a4f'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-10-answer-tool-call-and-standalone-approval-requests-on-every-c.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 22.7's email to someone other than the user is a `fix` request with no incident (FixKind `email`). It reaches the rail only, titled "Repair and resend". No channel gets a notification: `BridgeSink.ToolNotice` takes only replayable `tool_call` rows (`Replayable`), and `IncidentManager` never sees the row (its `ResultTarget` is `FixExecutor`). So the phone and Telegram get no buttons and no in-place edits, the web chat gets no card, and nothing shows "Why:" or the email that will be sent (FR-8, FR-44, UX-DR75).

**Approach:**
- Extend 21.10's tool-call path in `BridgeSink`. A standalone email request also gets its `approval`, `answered` and `result` notices through `NoticesIn`:
  - raise: kind `approval`, new key `fix.emailRequest`;
  - answer and expiry: the same `answered.*` branches a tool call uses;
  - result: new keys `fix.emailSent` and `fix.emailNotSent` {reason}.
- **The trace stays clean (22.7 P4).** `Msg.Notification` is an Ens message (`^Ens.MessageBodyD`), so its `Slots` carry no recipient, subject or text. Each `*Out` operation renders `fix.emailRequest` through a new `BridgeSink.RequestText`. It reads the stored `DryRun` through `Ownership.Approval` and fills the `inputs` slot with 21.10's `InputsOf`, so the redactor and V10's escaping apply. This is the way kind `summary` renders its stored summary.
- On the web, the card is drawn from the notice text, as a tool call's is (`WebChatOut.ToolCallCard` gains the three keys), and the rail row reads "Send an email".

## Boundaries & Constraints

**Always:**
- **Producers never render (AD-32).** `BridgeSink` sets keys and slots. Only `*Out` operations render, through `Msg.Catalog.Render`. `RequestText` builds slots and then calls `Render`.
- **What the request shows.** The dry run is `InputsOf(row.DryRun)`: the lines `to: [...]` (every recipient, as JSON), `subject: "..."` and `text: "..."`, in the stored order.
  - The text is never cut. Line breaks and tabs show as `\uXXXX` (V10), and spaces stay.
  - The redactor runs on the whole dry run first, as 21.10's Decided 9 does.
  - A dry run that can't be read renders nothing: the `*Out` sends nothing, and its error names only the Ref (fail closed, 21.10 Decided 7).
- **No email content in the trace.** For an email to anyone else, no recipient, subject or text marker is ever in `^Ens.MessageBody*`, `^Ens.MessageHeaderD` or `^Ens.Util.LogD`. The Notification carries only refs and `Slots` `{}` (or `{reason}` for a result). 22.7's TraceLeaks tests stay green unchanged.
- **Result text is only accepted sentences.** `fix.emailNotSent`'s reason is the run's `FixRun.Reason` only when it is one of these sentences:
  - `Channel.Email.Out`'s `MESSAGEREFUSED`, `MESSAGENOTCONNECTED`, `MESSAGEREJECTED`, `MESSAGEUNREACHABLE`, `MESSAGEREFUSEDLOGIN`, `MESSAGESIGNIN`, `MESSAGEUNAVAILABLE`, `MESSAGEFAILED` or `MESSAGEMAYHAVESENT`;
  - `Fix.Kind.Email`'s `EMAILNOSTART`.

  Any other reason, an empty one or `interrupted` gives `MESSAGEFAILED`. All of these are read with `$Parameter` and never copied.
- **Which rows qualify.** Only a row with Kind `fix`, an empty `IncidentRef`, FixKind `email` and an existing session as its owner, read through `Ownership.Approval`. Every other fix with no incident, every incident fix, and the owners `instance` and `eval` get nothing new. A cancellation sends nothing, as today.
- `BridgeSink` stays asynchronous. It waits no more than 1 s on a lock and never fails its caller (AD-31).
- Every test added or changed creates and removes its own `zz` rows and sessions, and passes on a fresh environment, in either order.
- Invisible characters are built in code (`$Char(9)`, `$Char(13,10)`, `\u` escapes in JS), never pasted into a file (Rule 14).

**Never:**
- A stored column, a table, a route, a role, a grant or a privilege.
- Recipients, subject or text in a Notification's `Slots`, a log line or any Ens message.
- Any Lane A edit except veto (b): `Channel/Telegram/Out.cls` (one parameter, one render branch and its doc line) and `Test/Channel/TelegramOut.cls` (one test). Never `StepBuffer.cls`, `Fix/**`, `Watch/**`, `Bridge/**`, `Msg/Catalog/Watch.cls` or Lane A's other tests.
- Telegram's over-long cut (V8) for an email request. The AC asks for the exact text on every channel, so a long email splits whole at `BUTTONLIMIT`, with the buttons on its last part.
- A model-written reason.
- Real mail.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Raise | Session-owned row: FixKind `email`, no incident, DryRun `{"to":["bob@example.test","ann@example.test"],"subject":"Late  order","text":"Hi Bob,\r\n\tSorry."}` (built in code) | Notice kind `approval`, `fix.emailRequest`, Slots `{}`, ApprovalRef set, IncidentRef "". Rendered for phone, Telegram and web: `Send an email` / the N1 Why line / `Dry run:` / `to: ["bob@example.test","ann@example.test"]` / `subject: "Late  order"` / `text: "Hi Bob,\u000D\u000A\u0009Sorry."` / `Approving sends exactly this email once.` The phone and Telegram show Approve and Reject. | -- |
| Approve or reject | `approval.answered` with `AnsweredAction` approve or reject | `answered.approved` or `answered.rejected` {channel, time}. The phone and Telegram edit the message in place and drop the buttons. The card shows the status. | -- |
| Expire | `approval.expired` | `answered.expired` {time = ExpiresAt}, edited in place | -- |
| Cancel | `approval.cancelled` (a session end) | Nothing (as today) | -- |
| Sent | `approval.result`, Result `done` | Kind `result`, `fix.emailSent` "The email was sent." | -- |
| Not sent, known reason | Result `failed`, FixRun Reason `MESSAGENOTCONNECTED` | `fix.emailNotSent` {reason: that sentence} | -- |
| Not sent, other | Result `failed` with a raw or empty reason, or `interrupted` | `fix.emailNotSent` {reason: `MESSAGEFAILED`} | No raw text |
| Long email | Text of 9,000 characters | Phone and web: whole. Telegram: whole, split at `BUTTONLIMIT`, buttons on the last part | -- |
| Secret in text | Text holding `sk-` plus 30 characters | `[redacted]` in that place on every channel | -- |
| Unreadable | DryRun not a JSON object, the redactor's `UNCHECKED`, a row another session owns, or a deleted row | `RequestText` gives an error whose text names only the Ref. That `*Out` sends nothing, and the others are unaffected. | Fail closed |
| Not standalone email | A fix with an incident, a fix with no FixKind, a `setting` row, owner instance or eval | No new notice | -- |
| Online demo | Any | Unchanged: no email request can be raised there (22.7) | -- |

</intent-contract>

## Code Map

All of it was checked on `OCT-epic21-s2111` at `21497b51d35a7257d17670c8b5a18e44b8f5789e` (21.10, 21.5 and 22.7 are merged).
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - class doc :3-61 (":22: A fix is IncidentManager's ... neither gets one here"; :37: "a fix cancel quietly");
  - `TOOLCALL` :81 and the keys :84-112;
  - `OnEvent` :115;
  - `ToolNotice` :220, which gates on `Replayable` :241 (the sibling to extend);
  - `ToolNoticeOf` :249: raised :251, answered :263, expired :268, cancelled :269, result :274;
  - `Compose` :285;
  - `InputsOf` :331 (public) and `Escapes` :359;
  - `HeldReasons` :385 (the allow-list precedent);
  - `Notice` :512 (the test seam).
- `src/ocutalon/cls/OcuTalon/Channel/{SimPhone,WebChat,Telegram}/Out.cls`: the render branches with the `digest` and `summary` precedent:
  - SimPhone :71-78 (`OnNotification` :63);
  - WebChat :80-87 (its class doc :17-19 states the summary rule: "its Slots are empty, so no untrusted text and no user name travels in the message");
  - Telegram :200-206 (`OnNotification` :192; `TOOLKEYS` :112, `BUTTONKINDS`, `BUTTONLIMIT` 3840 :128).

  The answered edits (SimPhone :100, Telegram `EditAnswered` :319-348) render only the `answered.*` key and need no change. `WebChat.Out.ToolCallCard` :109-116 lists BridgeSink's six keys and SettingsOps' three by `$Parameter`. Its doc :106-108 and the class doc :26-32 count them.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls` `Approval(ref, ownerRef, .sc)` (the read). `Data/FixRun.cls` `OfRequest(ref)` :66 (object access) and `Reason` :52. Read only.
- `Fix/Executor.cls` `Finish` :625-644: `End` saves `Reason` before `Close` calls `FinishExecution` (which fires `approval.result`), so the reason is there when the sink reads it. `Fix/Run.cls` `MarkOne` :179-188 is `interrupted` with an empty reason. Lane A, read only.
- `Fix/Kind/Email.cls` (Lane A, read only):
  - `Raise` :226-270 sets Kind `fix`, OwnerRef = the session, FixKind `email`, and no IncidentRef;
  - `DryRun` :169 is `{to, subject, text}`;
  - `EMAILNOSTART` :40;
  - the text may hold tab, LF and CR (:78); `TEXTMAX` is 100,000 (`Channel/Email/Out.cls` :102). The `MESSAGE*` sentences are at :119-139.
- `Msg/Catalog/Core.cls`: `toolCall.*` :639-683 (the T1/T2 pattern; place the new keys after them); `answered.*` :87-128. `Msg/Catalog.cls` doc :7-30: the slot types, `inputs` and `Visible`.
- `Msg/Notification.cls`:2 `Extends Ens.Request`, so the body lands in `^Ens.MessageBodyD` (`irislib/Ens/MessageBody.cls`:30).
- `Test/Core/SecretHandoff.cls` `TraceLeaks` :240-249 scans `^Ens.MessageBodyD/S`, `^Ens.MessageHeaderD` and `^Ens.Util.LogD`.
- Storage: `Data.Delivery` (`^OcuTalonP.DeliveryD`) and `Data.SimMessage` (`^OcuTalonP.SimMsg`) are in the private database (`docker/merge.cpf`:11), as `^OcuTalonBP.ApprovalD` is.
- Web:
  - `web/src/app/chat/chat-view.ts` `noticeOf` :234-272 already makes a kind `approval` notice with an `approvalRef` a request card, and `liveRequest` :287-293;
  - `chat-panel.ts` :176-178 draws `app-approval-request-card [request]=text`;
  - `approval-view.ts` `approvalView` :401-436 (an email gets no `dryRunView` and no `partnerView`; the title is the request's first line);
  - `web/src/app/rail/rail-view.ts` `RAIL_TEXTS` :30-73, `approvalTitle` :208-234 (email falls to `repair` at step 6).
- Tests that pin today's shapes:
  - `Test/Core/BridgeSink.cls`: class doc :41 ("a fix ... send none"), `TestToolCallNoticesOnlyForReplayableSessionRows` :999 (its `Fixture.Approval` fix row has no incident and no FixKind, so it must stay silent); probe `Test/Core/BridgeSinkNoticeProbe.cls`; `Test/Data/Fixture.cls` `Approval` :137;
  - `Test/Core/WebChatOut.cls` `TestToolCallCards` :210-247 ("six cards");
  - `Test/Demo/SimPhoneOut.cls`; `Test/Msg/Catalog.cls` (key list and fixtures; Core count 155);
  - `Test/Channel/TelegramOut.cls` (Lane A);
  - `Test/Core/ToolCallNotices.cls` (the live pattern: `InProduction`, `WaitMessage`);
  - `Test/Fix/Email.cls` (Lane A, unchanged): `TestApprovedEmailIsInNoTraceGlobal` :1171, `TestChatTurnsLeaveNoAddressSubjectOrTextInTheTrace` :1296, `TestEmailToolErrorLeavesNoAddressInTheTrace` :1343;
  - web: `rail-view.test.mjs` :309, `ux-strings.test.mjs` (`RAIL_TEXTS` :45), `chat-view.test.mjs` :112;
  - `web/e2e/answers/answers.spec.ts`: X12-X14, helpers `seedApproval` (`support/iris.ts`:774), `sinkEvent` :497, `irisScript` :108, `phoneMessage` (`support/devices.ts`:112);
  - `playwright-projects.test.mjs` :340-344 (X1-X14, 25 cases); the `docker/tests/test-answers.sh` header :8.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement, before any code; reads only, recorded under Design Notes "Read at implement"):
  - (a) `Executor.Finish` still saves `Reason` before `Close`.
  - (b) `Fix.Kind.Email.DryRun` is still `{to, subject, text}`.
  - (c) The `*Out` render branches sit where the Code Map says.
  - (d) The veto items are ruled. A changed text is applied word for word; an item refused is a STOP with `## Clarification Needed`.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- add N1 `fix.emailRequest` (slot `inputs` of type `inputs`), N2 `fix.emailSent` (no slots) and N3 `fix.emailNotSent` (slot `reason` of type `text`), word for word from Public text. Each has a `source` of "EXPERIENCE Incidents and Approvals / ... An email's request|result, Story 21.11".
- [ ] `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - add keys `KEYEMAILREQUEST`, `KEYEMAILSENT` and `KEYEMAILNOTSENT`, and `FIXKIND = "fix"` and `EMAILKIND = "email"`;
  - add a private `Standalone(row)`: Kind fix, IncidentRef "" and FixKind email;
  - `ToolNotice` gates on `Replayable(row) || Standalone(row)`;
  - in `ToolNoticeOf`, a raised standalone row composes `KEYEMAILREQUEST` with `{}`. Answered and expired reuse the existing branches; cancelled already gives "" (`CanceledServer` needs `Replayable`). A result for a standalone row gives `KEYEMAILSENT` for done, and `KEYEMAILNOTSENT` {reason: `EmailReason(row)`} for failed or interrupted;
  - add a private `EmailReason(row)`: `FixRun.OfRequest(row.Ref).Reason` when it is in the allow-list (Boundaries), else `Channel.Email.Out` `MESSAGEFAILED`;
  - add a public `RequestText(notification, channel, Output sc) As %String`:
    - read `Ownership.Approval(ApprovalRef, SessionRef)`;
    - require `Standalone`;
    - `inputs = InputsOf(row.DryRun)`, which must be an object, or the result is an error naming the Ref;
    - merge `inputs` into the notification's slots;
    - return `Msg.Catalog.Render(CatalogKey, slots, channel, .sc)`;
  - update the class doc (:20-38).
- [ ] `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` and `Channel/WebChat/Out.cls`:
  - a branch beside `summary`: kind `approval` with `$Parameter("OcuTalon.Core.BridgeSink","KEYEMAILREQUEST")` renders through `RequestText`;
  - `WebChat.ToolCallCard` adds the three new keys by `$Parameter` (nine BridgeSink and SettingsOps keys in all);
  - update the docs.
- [ ] `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` (**veto b**, Lane A):
  - a parameter `STOREDKEYS = "fix.emailRequest"`;
  - in `OnNotification`, beside `summary`, a kind `approval` with a `STOREDKEYS` key renders through `##class(OcuTalon.Core.BridgeSink).RequestText(request, ..#TEXTCHANNEL, .sc)`;
  - one doc line. Nothing else changes: the buttons, the split, `Deliver` and the edit stay as they are.
- [ ] `web/src/app/rail/rail-view.ts` -- `RAIL_TEXTS.sendEmail` 'Send an email' (N4). `approvalTitle` gives it for kind `fix` with fixKind `email`, before the `repair` fallback. Update the doc.
- [ ] **Tests (ObjectScript):**
  - `Test/Core/BridgeSink.cls` (with the probe):
    - new `TestStandaloneEmailNotices`: one row per matrix line, through `Fire`. Assert the kind, key, `Slots` (`{}` for raise, and no recipient, subject or text in any call's slots), ApprovalRef, an empty IncidentRef, the allow-listed reason, the `MESSAGEFAILED` fallback for a raw reason and for `interrupted`, and nothing for a cancel;
    - an incident email row, the instance and eval owners, and another session's row each send nothing;
    - new `TestRequestTextFillsTheDryRun`: the exact phone, web and telegram text of the matrix's Raise row (V10 escapes, the two spaces kept, every recipient); the secret row redacted; the four unreadable cases give an error and no text; a non-email key's slots are unchanged;
    - keep `TestToolCallNoticesOnlyForReplayableSessionRows` green and update the class doc :41.
  - `Test/Msg/Catalog.cls`: N1-N3 in the key list and the fixtures, rendered for web, phone and telegram; the Core count goes to 158.
  - `Test/Core/WebChatOut.cls`: a `fix.emailRequest` notification for a stored email row is a card whose text holds the dry-run lines; `fix.emailSent` is a result card; "nine cards". `Test/Demo/SimPhoneOut.cls`: the same message with the buttons, and an unreadable row sends nothing.
  - `Test/Channel/TelegramOut.cls` (**veto b**, one test): `TestEmailRequestRendersTheStoredDryRun`. One sendMessage holds the dry-run lines with Approve and Reject on its last part. A 9,000-character text is split whole, with the buttons on the last part. An unreadable row sends nothing.
  - NEW `Test/Core/EmailRequestNotices.cls` (live, `InProduction`, fresh throwaway, like `ToolCallNotices`):
    - a fixture email row with unique markers in its recipient, subject and text;
    - the real `BridgeSink.OnEvent("approval.raised")`: the phone message within `WAIT` holds the exact dry-run lines and the ApprovalRef, and the web Delivery row is a card with the same lines;
    - then `Bridge.Approval.Answer` reject: the phone message is edited to `answered.rejected`, with no second message;
    - then `SecretHandoff.TraceLeaks` finds none of the three markers (the P4 pin).
- [ ] **Tests (web):**
  - `web/scripts/rail-view.test.mjs` (`sendEmail`, no jump) and `ux-strings.test.mjs` (N4's source).
  - `web/e2e/answers/answers.spec.ts` new **X15**:
    - seed an email row with `seedApproval` (dry run with `\u0009`, a line break and two spaces, built in `irisScript` with `$Char`), then `sinkEvent` `approval.raised`;
    - the chat card shows N1's lines with Approve and Reject and the expiry, and the rail row reads "Send an email" with no button and no jump;
    - the phone message has the same text and buttons;
    - Reject on the phone edits it in place, and the card shows the rejected status;
    - a `sinkEvent` `approval.result` with Result `done` shows the result card "The email was sent.".
  - `playwright-projects.test.mjs` "X1 to X15" (26 cases), and the `test-answers.sh` header list.
- [ ] **Docs and spine (the lead; each marker reads `[ADDED`, the date of writing, `, Story 21.11]`):**
  - S1 and S2 (Design Notes) go into `ARCHITECTURE-SPINE.md` AD-32 and AD-31 (veto d);
  - N1-N4 go into EXPERIENCE.md's catalog, with the catalog in the same commit (DW-1045).

**Acceptance Criteria:**
- Given a pending standalone email request (no incident) to two other addresses, when it shows in the web chat, then its card shows:
  - "Send an email";
  - the line "Why: an email to any address but the connected mailbox's own counts as risky, so it is sent only after an approval.";
  - "Dry run:" and the lines `to:` (every recipient), `subject:` and `text:`, exact and uncut, with line breaks as `\u000A`;
  - "Approving sends exactly this email once.";
  - Approve, Reject and the expiry.

  The rail row reads "Send an email", with its raised and expiry times and no answer button. (X15, `Test.Core.WebChatOut`, `Test.Core.BridgeSink` `TestRequestTextFillsTheDryRun`)
- Given the same request, when it reaches the phone and Telegram, then each shows the same text with Approve and Reject. In Telegram, a long text splits whole at 3,840 units, with the buttons on the last part. The first answer wins everywhere (as it does today). (X15, `Test.Demo.SimPhoneOut`, `TelegramOut` `TestEmailRequestRendersTheStoredDryRun`, `EmailRequestNotices`)
- Given that request answered or expired, when the answer arrives, then the phone and Telegram edit the request's message in place to the `answered.*` text with no buttons, and the card shows the status. (`EmailRequestNotices`, `TestStandaloneEmailNotices`, X15)
- Given an approved request's run ends, when its result arrives, then every channel shows "The email was sent." or the run's accepted reason, and never raw text. (`TestStandaloneEmailNotices`, X15)
- Given an email request to another address, when its notices are sent and shown, then its recipients, subject and text are in no Notification slot and in none of the trace globals, and 22.7's TraceLeaks tests stay green. (`EmailRequestNotices`; `Test.Fix.Email` P4 methods, unchanged)
- Given a fix with an incident, any other fix with no incident, or a cancellation, when its events arrive, then `BridgeSink` sends nothing new and `IncidentManager` is unchanged. (`TestStandaloneEmailNotices`, `TestToolCallNoticesOnlyForReplayableSessionRows`)
- Given the online demo, when the demo path runs, then nothing changes. (`live demo-path`, X1-X14 unchanged)

### Review Findings

Code review 2026-11-15 (lane D, Tier 1, full; Blind Hunter, Edge Case Hunter, Verification Gap and Acceptance Auditor). 26 entries after grouping: high 0, medium 1, low 22, false 3; 0 decision-needed, 8 patch (all applied), 0 defer, 18 rejected. DW-1347's files and Lane A's other paths are untouched. Fresh check: `class OcuTalon.Test.Core.EmailRequestNotices` on a fresh stack passed (13.78 s).

- [x] [Review][Patch] `EmailRequestNotices.Mailbox()` asserted that no mailbox address was saved at all, while its message speaks only of this class's own leftover, so it went red whenever another class left an address (Rule 19 hermeticity; medium, fix-risk low, in-story) -- now asserts the address does not start with `zzqa` [src/ocutalon/cls/OcuTalon/Test/Core/EmailRequestNotices.cls:342]
- [x] [Review][Patch] `TestRealApproveWithNoMailServerIsReportedNotSent` left EmailOut stopped for the class's later methods until `OnAfterAllTests` (Rule 19; low) -- `OnAfterOneTest` starts it again after the method that stopped it [src/ocutalon/cls/OcuTalon/Test/Core/EmailRequestNotices.cls:408]
- [x] [Review][Patch] `TestRequestTextFillsTheDryRun` asserted the Slots of a new notification that was never passed to `RequestText` (unfalsifiable; low) -- one notification now goes through the three channels and its Slots are asserted; mutation observed below [src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls:1163]
- [x] [Review][Patch] `TestStandaloneEmailNotices` asserted a `$ListLength` of 10 on a list the test builds itself (cannot fail; low) -- deleted; the loop over the sentences is the pin [src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls:1088]
- [x] [Review][Patch] `TestToolCallCards` checked that the newest card (a `fix.emailNotSent` built from the test's own reason) holds no recipient and counted the dry-run card again after the loop had asserted each card's text (cannot fail; low) -- both deleted [src/ocutalon/cls/OcuTalon/Test/Core/WebChatOut.cls:255]
- [x] [Review][Patch] The class doc of `Test.Core.BridgeSink` still said "a fix ... send none" for `TestToolCallNoticesOnlyForReplayableSessionRows` (low) -- now "a fix with no FixKind" [src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls:41]
- [x] [Review][Patch] `EmailReason`'s doc said an interrupted run gives `MESSAGEFAILED`, while the code passes an accepted Reason whatever the Result (as AD-31 S2 says); an interrupted run's Reason is empty (`Fix.Run.MarkOne`) (low) -- the doc now says so; no code change [src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls:379]
- [x] [Review][Patch] AC 7 (online demo) had no `mutation:` line (Rule 19; low) -- the gate that keeps the demo's incident fix silent was mutated and observed red; the line is under `## Verification`

**Rejected:**
- `false` Acceptance Auditor and Verification Gap: the second test in `Test/Channel/TelegramOut.cls` (`TestEmailRequestEditKeepsItsStoredDryRun`, QA) breaches V5's "one test" -- the lead's ruling for this review: lane D builds as Lane A, the file's owner, so it is judged on merit (Rule 19). On merit it holds: it creates and removes its own `zz` rows, pins AC 3's in-place edit of the stored dry run on Telegram with the secret redacted, and its mutation (`Set kept = ""`) was observed red.
- `low` Acceptance Auditor: the Telegram doc runs over two `///` lines and the parameter has its own doc line -- moot under the same ruling; the text is accurate.
- `low` Acceptance Auditor: the spec says "nine BridgeSink and SettingsOps keys in all" while `ToolCallCard` lists twelve -- the code is right (nine BridgeSink keys plus three SettingsOps keys); the fix would edit the spec's intent.
- `low` Verification Gap: the Auto Run's residual-risk line and "Read at implement" (`row.OwnerRef` check) are stale -- the fix would edit the spec's history.
- `low` Blind Hunter: `STOREDKEYS` copies the key -- by-design: V5 grants exactly this parameter, and `TestEmailRequestRendersTheStoredDryRun` fails on a rename.
- `low` Blind Hunter: the card shows the redacted dry run while saying "Approving sends exactly this email once." -- by-design: 21.10 Decided 9 and the matrix's "Secret in text" row; the approved text is fixed.
- `low` Blind Hunter: the catalog `source` lines cite "EXPERIENCE Incidents and Approvals / ..." while the rows sit in the step 4 catalog block -- the spec prescribes these sources, and 21.10's `toolCall.*` entries use the same form.
- `low` Blind Hunter: `EmailReasons` lists its sentences by hand -- by-design: the Boundaries name the allow-list, read by `$Parameter`.
- `low` Blind Hunter and Edge Case Hunter: `RequestText` does not check the dry run's members -- `wontfix-theoretical`: only `Fix.Kind.Email.DryRun` writes an email row and it always writes `to`, `subject` and `text`; real if another writer of FixKind `email` rows appears.
- `false` Blind Hunter: `Mailbox()` asserts `onlineDemo` = 0 and fails when it is unset -- the setting reads 0 on a fresh install (the fresh check passed).
- `low` Blind Hunter: X15 posts a `done` result for a rejected request -- the card's render does not depend on the answer, the real approve paths are pinned by `TestRealApproveWithNoMailServerIsReportedNotSent` and `TestResultsReachThePhoneAndTheWebChat`, and a second seeded flow adds more than it pins.
- `low` Blind Hunter: the trace pin does not cover Telegram -- `wontfix-theoretical`: Telegram sends over HTTP and logs only `Api.Safe` status texts; real only if a `Delivery.Record` failure echoed the text into its status.
- `low` Blind Hunter: EXPERIENCE does not say that Telegram splits a long email -- the text is still the same on every channel (split whole), and Decided 3 (V8 KEEP) records the behaviour.
- `low` Blind Hunter and Edge Case Hunter: a request that cannot be rendered reaches no channel -- by-design: fail closed (Boundaries, the matrix's "Unreadable" row).
- `false` Edge Case Hunter: `approvalTitle` does not check `incidentRef` -- an email fix never has an incident (Decided 1; `IncidentManager.RaiseFix` sets no FixKind `email`).
- `low` Edge Case Hunter: `StopMailOut` sets its flag before the stop -- on a throwaway, starting a running item again is harmless.
- `low` Edge Case Hunter: a removed row or message gives an INVALID OREF error, not a failed assertion -- the test still fails, with a less clear message.
- `low` Edge Case Hunter: the commit subject says "standalone fix requests" but only email is handled -- by-design: Decided 1.

## Spec Change Log

- 2026-11-15 (lane D lead). **Lane exception (orchestrator, Planner 1.0.11 priority):** lane D builds 21.11 because lane C is on DW-1347; lane C does not touch this branch. Runtime moves to lane D: slot `ocutalon-slot-d`, port 52804, the `lane-d` lock folder, tags `e21s11dw` (warm) and `e21s11d` (fresh). Integrated over feature 20b60564 (includes 21.9). DW-1347's files stay out of scope (`Mcp.Proxy`, `Bridge.Poll`, `Bridge.Process.Decide`, Bridge `HostData`/`Reply`, `Checks.Process`, `Test.Mcp.Source*`, `Test.Bridge.Poll`). The spine's AD-31 S2 is additive, written under `spine.lock`.

## Review Triage Log

### 2026-11-15 - Review pass
- verdicts: 25 findings - high 0, medium 0, low 23, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: Telegram's `STOREDKEYS` hard-codes the key while the other channels read `KEYEMAILREQUEST` by `$Parameter` -- V5 grants exactly "a parameter `STOREDKEYS`" in Lane A's class, which must not reference more of Lane B's surface; a rename would be caught by `TestEmailRequestRendersTheStoredDryRun`.
  - `[low]` `[reject]` Blind: the card shows redacted text while "Approving sends exactly this email once" -- spec-bound: 21.10's Decided 9 runs the redactor on the whole dry run first and the matrix has the "Secret in text" row.
  - `[low]` `[reject]` Blind: an unreadable dry run gives the user no explanation -- spec-bound: the Boundaries and the matrix's "Unreadable" row fail closed with no text.
  - `[low]` `[reject]` Blind: `EmailReason` never looks at `row.Result` for `interrupted` -- unreachable: `Fix.Run.MarkOne` leaves an interrupted run with an empty Reason, so `MESSAGEFAILED` results; any other string is not in the allow-list (the near-miss rows).
  - `[low]` `[reject]` Blind: no upper bound on a Telegram email request -- spec-bound: Decided 3 and the Planner's V8 KEEP.
  - `[low]` `[reject]` Blind: no Telegram test of `fix.emailSent` and `fix.emailNotSent` -- they take Telegram's generic path (no new branch), covered by `Test.Msg.Catalog` and `TestStandaloneEmailNotices`.
  - `[low]` `[reject]` Blind: `approvalTitle` does not test `incidentRef` -- spec-bound: Decided 1 (an email fix never has an incident, `IncidentManager.RaiseFix` always sets one) and the Tasks name `kind fix with fixKind email`.
  - `[low]` `[reject]` Blind: N1's text is a literal in six tests -- a wording change is a Planner ruling and the tests are meant to pin the exact words; a shared constant would hide a drift.
  - `[low]` `[reject]` Blind: `TestToolCallCards` checks only the newest result card -- `fix.emailSent` and `fix.emailNotSent` are each asserted with their own row and card.
  - `[low]` `[reject]` Edge: a dry run that is an object without to, subject or text shows an empty "Dry run:" -- unreachable: `Fix.Kind.Email.DryRun` always writes the three members, and nothing else creates an email row.
  - `[low]` `[reject]` Edge: members in another order, or extra ones, are shown as stored -- spec-bound: "in the stored order" and Decided 2.
  - `[low]` `[reject]` Edge: a request answered before its `*Out` renders it is still delivered with buttons -- the same ordering as 21.10's tool-call path; the answered edit then finds the Delivery row, and "the first answer wins everywhere" is the AC.
  - `[low]` `[reject]` Edge: an interrupted run with an accepted Reason shows that Reason -- same evidence as the fourth row: that state is not reachable.
  - `[low]` `[reject]` Edge: an unknown Result sends nothing and logs nothing -- `FinishExecution` takes only `done`, `failed` and `interrupted`.
  - `[low]` `[reject]` Edge: `EmailReason`'s `Catch` is silent -- the fallback is the safe sentence `MESSAGEFAILED`, and a warning would add a log line for a state with no user-visible cost.
  - `[false]` `[reject]` Edge: `ToolNotice` never checks `OwnerRef` for an email row -- it reads the row through `Ownership.Approval(ref, ownerRef)`, whose `APPROVALVISIBLE` returns only the owner's row, and an instance row needs a matching Incident, which a standalone email (`IncidentRef` "") never has.
  - `[low]` `[patch]` Verification gap: pins with no `mutation:` line (phone branch, web branch, answered and expired, result done, the `IncidentRef` clause, `RequestText`'s guards, Telegram's cut) -- patched: each mutation applied, observed red and reverted byte-identical; the lines are in `## Verification`.
  - `[low]` `[patch]` Verification gap: `RequestText`'s `row.OwnerRef '= notification.SessionRef` clause is dead -- verified: `Ownership.Approval` already filters by owner and an instance row needs an incident, so the mutation stayed green; patched by deleting the clause.
  - `[low]` `[reject]` Verification gap: the fixed `Hang 2` before the "no second phone message" check -- `WaitAnswer` has already seen the answered edit, so the absence check follows the event it guards.
  - `[low]` `[reject]` Verification gap: Telegram is not in the trace pin -- `Telegram/Out` writes no message text to a log (its warnings carry `Api.Safe` error text only) and sends over HTTP, not an Ens message.
  - `[false]` `[reject]` Verification gap: chat id 8633 may collide -- no other test uses it and the test removes its own rows.
  - `[low]` `[reject]` Intent: the row's origin (`Fix.Kind.Email.Raise`) is not exercised by the new tests -- the spec names 22.7's `Test.Fix.Email` P4 methods, run unchanged, as that check, and Task 0 read the row's shape.
  - `[low]` `[reject]` Intent: the rail's gate does not check `incidentRef` while `Standalone` does -- same evidence as the seventh row.
  - `[low]` `[reject]` Intent: no new test asserts the online demo is unchanged -- the spec's check is `live demo-path`, which passed, and no demo-flag branch was added.
  - `[low]` `[reject]` Intent: no Telegram end-to-end test -- the spec's Telegram pin is `TelegramOut` `TestEmailRequestRendersTheStoredDryRun` (one test, V5).

## Design Notes

**Governing ADs (Rule 6):**
- AD-31: `BridgeSink` sends a standalone fix's notices; the spine already says so for "a fix request with no incident ... built in Story 21.11".
- AD-32: kind `approval` for a fix request with no incident; producers never render; `inputs`; kind `summary`'s stored-text precedent.
- AD-10 and FR-44: an email to anyone else is risky (the Why line).
- AD-11: the row is the truth; the first answer wins.
- AD-14: the in-place edits and Delivery rows.
- AD-16: the stored dry run is what is sent.
- AD-33: `BridgeSink` is the one sender of these notices.

No AC contradicts an AD's Rule.

**Why the dry run is read at render time.** Putting `to`, `subject` and `text` in `Slots` would put them in `^Ens.MessageBodyD`. That would break 22.7's ruled P4, its security-overview line (:170) and three Lane A tests. The row already holds them, and the Notification carries its `ApprovalRef`. This is the way `EmailOut` reads `FixParameters` by `ApprovalRef` (P4 a) and the way kind `summary` renders its stored summary. The rendered text lands where every notice's does: `Delivery` and `SimMessage`, in the private database (veto c).

**Decided in-stage (reversible inside this story):**
1. **Only FixKind `email`.** It is the only fix with no incident (`IncidentManager.RaiseFix` always sets one), and N1's words are about email. Any other kind without an incident stays silent until a story gives it text.
2. **The dry-run lines are `InputsOf(DryRun)`.** These are 21.10's exact, redacted, V10-escaped lines (Rule 2). A `text` slot would fold the email's line breaks and spaces, and a new multi-line slot type would change AD-32's no-new-line rule. The labels are the stored member names `to`, `subject` and `text`.
3. **Telegram splits whole.** An over-long email is not cut: the AC asks for the exact text on every channel. The cut (V8, V9) was ruled for tool calls only, and its V9 line speaks of "inputs". A 100,000-character text is about 27 messages. Inference: rare, since a model reply bounds it.
4. **Result reasons come from an allow-list**, as `HeldReasons` does for a held call. A raw error never reaches a notice. `interrupted` and the rest give `MESSAGEFAILED`, which says that the command may not have finished.
5. **The rail title** is N1's first line, so the rail and the card agree. "Repair and resend" was false.
6. **The security overview :170 stays** ("An email to anyone else keeps them only in its approval record"). The bullet is about what the trace role reads, and the private database holds the request's messages, where the trace role has no access. This is for the Planner (see Veto items); no text changes.
7. **The Telegram press alert** for an approved email stays empty (`Telegram/In.cls`:42, no count), as for a tool call. No Lane A edit.
8. **No cancelled notice.** A session end cancels quietly, as for every fix (`answered.canceled` is an MCP server sentence).

**Integration ACs (Rule 1):** `BridgeSink.RequestText` is consumed by the real `SimPhoneOut`, `WebChatOut` and `TelegramOut`, and each produces the request's text: `EmailRequestNotices` (phone and web, in the production), X15 (browser and phone), and `TelegramOut` `TestEmailRequestRendersTheStoredDryRun`.

**Consumes:**
- 22.7: the email row and its `DryRun`, FixRun `Reason`, `EMAILNOSTART`.
- 21.10: `InputsOf`, `Visible`, `ToolNotice` and `ToolNoticeOf`'s answered and expired branches, the request-text card.
- 21.6: `EmailOut`'s sentences.
- 6.3: the in-place edits.
- 31.5 and 31.6: the notice and card path.

**Consumed-by:** no later story is known.

**Extend, don't copy (Rule 2):**
- `Standalone` sits beside `Replayable`, and the new branches go into `ToolNoticeOf` through `Compose`.
- `EmailReason` follows `HeldReasons`.
- `RequestText` reuses `InputsOf` and `Render`.
- The `*Out` branches follow `summary`'s.
- `ToolCallCard` reads the keys by `$Parameter`.
- The web reuses the request-text card and `approvalTitle`.

**Spine items (veto d; additive, no Rule changed):**
- **S1, AD-32**, after the incident summary bullet: "**A standalone email request** [ADDED, Story 21.11]. Its request is kind `approval`, `fix.emailRequest`, with no recipient, subject or text in `Slots`; each `*Out` operation renders it through `Core.BridgeSink.RequestText`, which reads the stored dry run through `Ownership.Approval` and fills the `inputs` slot (to, subject, text), as kind `summary` renders the stored summary, so none of them is in the trace (Story 22.7, P4)."
- **S2, AD-31**, after the cancelled sentence: "For a fix request with no incident (FixKind `email`, a session owner), `approval.raised` sends `fix.emailRequest`; `approval.answered` and `approval.expired` send the `answered.*` notices of a tool call; `approval.result` sends `fix.emailSent` for done and `fix.emailNotSent` for failed or interrupted, whose reason is the run's when it is one of `EmailOut`'s or `Fix.Kind.Email`'s sentences, else `MESSAGEFAILED`; a cancellation sends nothing [ADDED, Story 21.11]." It has no braces, so `lint_spine.py` keeps its baseline.

**Contended files (Rule 11):**
- `Core/BridgeSink.cls`: no open branch edits it (21.9 does not).
- 21.9 (`OCT-epic21-s219`) also edits `web/scripts/ux-strings.test.mjs` (+2 lines) and `ARCHITECTURE-SPINE.md` (AD-21). These are different lines and ADs, merged as a union, and whoever lands second integrates forward.
- Lane D's 22.11 edits `Mcp/Ops.cls`: no overlap.
- `StepBuffer.cls`: not touched. Both of its rules stand (MCP: server and tool; send_email: name and count).
- `Channel/Telegram/Out.cls`: only veto (b).

**Ledger:** the inbox (`slice 21-11-...`) is empty. 22.7's card entry is resolved by 22.7 (`EmailPart`). This story gives the email row's channels their text, so the security overview's "shows first exactly what it will do" (DW-1306) holds on every channel.

**Bundle:** one string and one branch in `rail-view.ts` (well under 1 kB), against the 921 kB budget (886 kB measured at 21.10). No new dependency or chunk.

**Read at implement (Task 0):** (a) `Fix/Executor.cls` `Finish` still calls `End` (which saves `Reason` on the FixRun) before `Close` (which fires `FinishExecution` and so `approval.result`). (b) `Fix.Kind.Email.DryRun` is still `{to, subject, text}`. (c) The `*Out` render branches sit where the Code Map says (`summary`'s branch in SimPhone, WebChat and Telegram `OnNotification`; `WebChat.Out.ToolCallCard`'s `$Parameter` list). (d) V1 to V8 are ruled (Spec gate rulings above): N1 to N4 word for word, V5 granted for `Channel/Telegram/Out.cls` and `Test/Channel/TelegramOut.cls` only. Small decisions made while implementing: the `EmailReasons` allow-list reads the ten sentences by `$Parameter`; `RequestText` merges `inputs` only for the key `fix.emailRequest` (any other key renders from its own slots), and requires `row.OwnerRef` to be the notification's `SessionRef`; every failure of `RequestText` is replaced by one error that names only the Ref; the "nine cards" count in `TestToolCallCards` is the nine BridgeSink keys (six tool-call, three email) in the web card path; the Telegram test and `EmailRequestNotices` create their own `zz` rows and remove them. A throwaway `node_modules` copy of the sibling worktree's (same lockfile) served the web tests.

## Veto items

| # | Gate | Item | Recommended | Online demo |
| --- | --- | --- | --- | --- |
| V1 | (a) new text | N1 `fix.emailRequest`, text and web: "Send an email\nWhy: an email to any address but the connected mailbox's own counts as risky, so it is sent only after an approval.\nDry run:\n{inputs}\nApproving sends exactly this email once." (`{inputs}` gives the lines `to: [...]`, `subject: "..."`, `text: "..."`, labelled by the stored member names) | approve | never shown |
| V2 | (a) new key, accepted text | N2 `fix.emailSent`: "The email was sent." (= `EmailOut` `MESSAGESENT`, Story 21.6) | approve | never shown |
| V3 | (a) new key | N3 `fix.emailNotSent`: "{reason}", whose reason is only one of the accepted sentences in Boundaries, else `MESSAGEFAILED` | approve | never shown |
| V4 | (a) new page text | N4 `RAIL_TEXTS.sendEmail`: "Send an email" (N1's first line; it replaces the false "Repair and resend" on an email's rail row) | approve | never shown |
| V5 | (b) cross-lane | `Channel/Telegram/Out.cls`: `STOREDKEYS`, one render branch and one doc line; `Test/Channel/TelegramOut.cls`: one test. Nothing else in Lane A | grant | never reached |
| V6 | (c) stored data | No schema change. A standalone email request's rendered text (recipients, subject and text, redacted) is kept as every notice's is: web `Delivery.Text` (whole), Telegram's last part (redacted), and `SimMessage`, all in the private database (`^OcuTalonP.*`). It goes to Telegram for a paired chat | accept | none |
| V7 | (d) AD | S1 (AD-32) and S2 (AD-31), additive | approve | -- |
| V8 | for the Planner | Decided 3 (Telegram splits whole, not V8's cut) and Decided 6 (security overview :170 unchanged) | keep as decided | -- |

There is no new command, route, grant, role, privilege, table, column, retention or web dependency.

## Public text

**New (V1-V4, word for word; every channel unless noted):**
- **N1 `fix.emailRequest`** (`web` the same): "Send an email\nWhy: an email to any address but the connected mailbox's own counts as risky, so it is sent only after an approval.\nDry run:\n{inputs}\nApproving sends exactly this email once."
- **N2 `fix.emailSent`:** "The email was sent." (Story 21.6's `MESSAGESENT`)
- **N3 `fix.emailNotSent`:** "{reason}", where the reason is one of the accepted sentences in Boundaries.
- **N4 rail title:** "Send an email"
- The dry run's line labels are the stored member names: `to`, `subject`, `text`.

**Reused (accepted):** "Approval needed", Approve, Reject, "Expires {when}", `answered.approved`, `answered.rejected`, `answered.expired`, and `EmailOut`'s and `EMAILNOSTART`'s sentences (as reasons).

**Findability:** none (email is off on the online demo).

## Spec gate rulings (Contest Planner, ~09:10Z Nov 15, BINDING)

- APPROVED, with one wording fix: V1 N1 ships as "Send an email\nWhy: an email to any address but the connected mailbox's own counts as risky, so it is sent only after an approval.\nDry run:\n{inputs}\nApproving sends exactly this email once." `{inputs}` is as proposed (`to`, `subject`, `text`). The spec's three mentions of N1 carry this text.
- V2, V3 and V4 APPROVED: V2 "The email was sent."; V3 "{reason}", an accepted Boundaries sentence, otherwise `MESSAGEFAILED`; V4 `RAIL_TEXTS.sendEmail` is "Send an email".
- V5 GRANTED: `Channel/Telegram/Out.cls` (`STOREDKEYS`, one render branch, one doc line) and the one test in `Test/Channel/TelegramOut.cls`.
- V6 ACCEPTED, on one CONDITION: a pin shows that the Ens trace carries only references for this notice, with no recipient, subject or body (it keeps 1.0.10's release-note claim "No email's recipients are in the trace" true). The pin needs its `mutation:` line (put a recipient, the subject or the text into a notice's Slots -> the pin goes red).
- V7 APPROVED: AD-32 S1 and AD-31 S2, both additive.
- V8 KEEP: Decided 3 and Decided 6.
- Order: DW-1347 first, then 21.11.

## Verification

Run every command from the worktree root, after `git rev-parse --show-toplevel` matches it. Lane D only (lane exception, below).
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-d" OCUTALON_TEST_WEB_PORT=52804 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s11dw` and fresh `e21s11d`. `<stage>` is the running stage's name (implement, qa, review). In the commands, `...` repeats the previous line's prefix up to `class`.
- One command per foreground call, with `timeout: 600000`, each sized to about 150 s. One class per call; split a slow class with `class <Class>:<Method>`. Never two test runs in one message, and one `iris_execute_tests` per message, with `server` and `namespace`. Never a slot or another lane's stack. Tear down only this stage's tags. If a call is backgrounded, wait in bounded foreground polls, never `Monitor`.

**Shared surfaces:**
- the Core catalog's key list and count (`Test.Msg.Catalog`);
- WebChatOut's card keys ("nine cards", `Test.Core.WebChatOut`);
- BridgeSink's notice gate (`Test.Core.BridgeSink`);
- the rail's approval titles (`rail-view.test.mjs`, `ux-strings.test.mjs`);
- the answers project's case inventory (`playwright-projects.test.mjs`, `test-answers.sh`).

Criterion: every test added or changed passes on a fresh environment, in either order.

**Mutations to run (Rule 19; each applied, observed red, reverted byte-identical, with `git status --short` and `git diff --stat` unchanged):**
- `ToolNotice` gating on `Replayable` only -> `TestStandaloneEmailNotices` red.
- `Standalone` without the FixKind check -> `TestToolCallNoticesOnlyForReplayableSessionRows` red.
- `EmailReason` passing any reason through -> `TestStandaloneEmailNotices` (raw-reason row) red.
- `RequestText` with `Clean`ed text slots in place of `InputsOf` -> `TestRequestTextFillsTheDryRun` red.
- The raise composing the `inputs` into `Slots` -> `EmailRequestNotices` (TraceLeaks) red.
- No "Why:" line in N1 -> `Test.Msg.Catalog` red.
- `KEYEMAILREQUEST` left out of `ToolCallCard` -> `Test.Core.WebChatOut` and X15 red.
- The Telegram `STOREDKEYS` branch removed -> `TestEmailRequestRendersTheStoredDryRun` red.
- `approvalTitle` without the email branch -> `rail-view.test.mjs` red.

**Mutations observed (Rule 19; each applied, red, reverted byte-identical with `cmp`, `git status --short` and `git diff --stat` unchanged):**
- mutation: `ToolNotice` gate `'..Replayable(row) && '..Standalone(row)` cut to `'..Replayable(row)` -> `Test.Core.BridgeSink:TestStandaloneEmailNotices` red.
- mutation: `Standalone` without the `FixKind` check -> `Test.Core.BridgeSink:TestToolCallNoticesOnlyForReplayableSessionRows` red ("no notice was sent for any of them").
- mutation: `EmailReason` passes any non-empty reason through -> `TestStandaloneEmailNotices` red (the raw-reason, `interrupted` and near-miss rows).
- mutation: `RequestText` fills `inputs` from the dry run folded to one `text` line in place of `InputsOf` -> `TestRequestTextFillsTheDryRun` red (exact phone, web and telegram text).
- mutation (V6, the trace pin): the raise composes `{"inputs": InputsOf(DryRun)}` into `Slots` instead of `{}` -> `Test.Core.EmailRequestNotices` red: "every one holds the key and empty Slots", and "no trace global holds" the recipients, the subject and the text.
- mutation: the "Why:" line cut from N1 -> `Test.Msg.Catalog` red (`TestEveryKeyOnEveryChannel`, `TestLocalInstallEveryKey`).
- mutation: `KEYEMAILREQUEST` left out of `ToolCallCard` -> `Test.Core.WebChatOut` `TestToolCallCards` red, and `live answers` X15 red (the only failure: 25 passed, 1 failed).
- mutation: the Telegram `STOREDKEYS` branch made `ElseIf 0` -> `Test.Channel.TelegramOut:TestEmailRequestRendersTheStoredDryRun` red.
- mutation: `approvalTitle` without the email branch -> `web/scripts/rail-view.test.mjs` red ("Repair and resend", expected "Send an email").
- mutation (review pass): the SimPhone `fix.emailRequest` render branch made `ElseIf 0` -> `Test.Demo.SimPhoneOut:TestEmailRequestMessage` red.
- mutation (review pass): the WebChat `fix.emailRequest` render branch made `ElseIf 0` -> `Test.Core.WebChatOut` `TestToolCallCards` red.
- mutation (review pass): an expired standalone email request sends nothing -> `TestStandaloneEmailNotices` red.
- mutation (review pass): `done` composes `fix.emailNotSent` -> `TestStandaloneEmailNotices` red ("result done: of kind result with the key fix.emailSent").
- mutation (review pass): `Standalone` without the `IncidentRef = ""` clause -> `TestStandaloneEmailNotices` red (the incident row sends no notice).
- mutation (review pass): `RequestText` without its `Standalone` check -> `TestRequestTextFillsTheDryRun` red.
- mutation (review pass): `RequestText` without the empty-dry-run check -> `TestRequestTextFillsTheDryRun` red.
- mutation (review pass): `fix.emailRequest` added to Telegram's `TOOLKEYS` (the tool-call cut) -> `TestEmailRequestRendersTheStoredDryRun` red (the long request is cut and has no buttons on its last part).

**QA additions (QA; tests only, no new file; each in a file of this story's list):** the QA stage found every AC and matrix row pinned at the sink and per-channel level, and added the runtime rows that the fixtures did not reach, on the warm stack (`e21s11dqw`):
- (QA) `Test/Core/EmailRequestNotices.cls` `TestRealRaiseThenExpireEditsInPlace`: the request is raised through the real `Fix.Kind.Email.Raise` and `Bridge.Approval.Raise` (the production's own sink, no direct `OnEvent`); the phone and web card show the exact lines; `Approval.Expire` edits the phone message in place to `answered.expired`, with no second message, and the web chat gets the answered row; no trace global holds a marker.
- (QA) `Test/Core/EmailRequestNotices.cls` `TestRealApproveWithNoMailServerIsReportedNotSent`: the real request is approved with EmailOut stopped (nothing can be sent); the real `FixExecutor` ends it failed with `MESSAGENOTCONNECTED` in the `FixRun`; the phone message is edited to `answered.approved`; a new phone message and a web result card are the render of `fix.emailNotSent` with that sentence, with no buttons; no trace global holds a marker.
- (QA) `Test/Core/EmailRequestNotices.cls` `TestResultsReachThePhoneAndTheWebChat`: `FinishExecution` done gives "The email was sent." on the phone (no buttons) and as a web result card; a failed run whose `FixRun.Reason` is a raw error text gives `MESSAGEFAILED` and none of the raw text.
- (QA) `Test/Channel/TelegramOut.cls` `TestEmailRequestEditKeepsItsStoredDryRun`: Telegram's Delivery row stores the redacted dry run as the request's text, and `answered.rejected` (from Telegram) and `answered.expired` edit the message in place to that text, a blank line and the status, with no buttons and a `sk-` secret redacted in the message, the stored text and the edit.
- Not added: the online demo (no email request can be raised there; `Test.Fix.Email` `TestOnlineDemoSendsNothing` and `live demo-path` already pin it); the web rail's expired or rejected row (the rail's title is pinned by `rail-view.test.mjs`; the row's state text is generic and unchanged).

**Mutations observed (QA; each applied on the warm stack, red, reverted; `git status --short` shows only the test files):**
- mutation: `ToolNotice` gate cut to `'..Replayable(row)` -> `Test.Core.EmailRequestNotices` `TestRealRaiseThenExpireEditsInPlace`, `TestRealApproveWithNoMailServerIsReportedNotSent` and `TestResultsReachThePhoneAndTheWebChat` red (no message arrives), with the existing `TestRequestReachesTheChannelsAndLeavesNoTrace`.
- mutation: `EmailReason` never passes a reason (`If 0 Quit reason`) -> `TestRealApproveWithNoMailServerIsReportedNotSent` red (the phone and web render of `fix.emailNotSent` with `MESSAGENOTCONNECTED`).
- mutation: `EmailReason` passes any non-empty reason (`If reason '= "" Quit reason`) -> `TestResultsReachThePhoneAndTheWebChat` red (the raw reason shows).
- mutation: the expired branch skips a standalone email row -> `TestRealRaiseThenExpireEditsInPlace` red (no `answered.expired` edit, no answered row on the web).
- mutation: a done standalone email composes no `fix.emailSent` (`If 0 Quit ...`) -> `TestResultsReachThePhoneAndTheWebChat` red ("The email was sent." is not shown).
- mutation (V6, the trace pin, real path): the raise composes `{"inputs": InputsOf(DryRun)}` into `Slots` -> `TestRealRaiseThenExpireEditsInPlace` red (no trace global may hold the recipients, the subject or the text).
- mutation: Telegram's stored text of a request with buttons made empty (`Set kept = ""` in `Channel/Telegram/Out.cls`) -> `Test.Channel.TelegramOut:TestEmailRequestEditKeepsItsStoredDryRun` red (the row stores no dry run, so the edit is not made).

**Mutations observed (code review; warm stack `e21s11dcrw`, each applied, red, reverted byte-identical with `cmp`, `git status --short` and `git diff --stat` unchanged):**
- mutation (code review): `RequestText` writes the merged slots back (`Set notification.Slots = slots.%ToJSON()`) -> `Test.Core.BridgeSink:TestRequestTextFillsTheDryRun` red ("the notification passed to RequestText for the three channels still holds no slot").
- mutation (code review, AC 7, online demo): the demo raises no email request (22.7, `Test.Fix.Email` `TestOnlineDemoSendsNothing`), and its fix is an incident's, which the `Standalone` gate keeps silent. `Standalone` without the `IncidentRef = ""` clause -> `Test.Core.BridgeSink:TestStandaloneEmailNotices` red ("an email request with an incident ... send no notice").
- mutation (code review, V6 re-observed): the raise composes `{"inputs": InputsOf(DryRun)}` into `Slots` -> `Test.Core.EmailRequestNotices:TestRequestReachesTheChannelsAndLeavesNoTrace` red: "every one holds the key and empty Slots" and four `TraceLeaks` failures (both recipients, the subject and the text).

**Commands:**
- (once) `<vars> OCUTALON_RUN_TAG=e21s11dw ci/warm.sh up` -- ready.
- (loop) `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s11dw ci/iris.sh class OcuTalon.Test.Core.BridgeSink` -- passed.
- (loop) `... class OcuTalon.Test.Msg.Catalog` -- passed.
- (loop, one per call) `... class OcuTalon.Test.Core.WebChatOut`, `... OcuTalon.Test.Demo.SimPhoneOut`, `... OcuTalon.Test.Channel.TelegramOut` -- passed.
- (once, one method per call) `... class OcuTalon.Test.Fix.Email:TestApprovedEmailIsInNoTraceGlobal`, then `...:TestChatTurnsLeaveNoAddressSubjectOrTextInTheTrace` -- passed, unchanged (P4 with the new notices in the production).
- (once) `<vars> OCUTALON_RUN_TAG=e21s11d ci/iris.sh class OcuTalon.Test.Core.EmailRequestNotices` (fresh) -- passed.
- (once) `cd web && node scripts/catalog.mjs --check`, then (once) `node --test web/scripts/` (the 921 kB budget included) -- passed.
- (once each) `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `cd web && npm run build` -- clean.
- (once) `<vars> OCUTALON_RUN_TAG=e21s11d ci/iris.sh build`, then (once) `<vars> OCUTALON_RUN_TAG=e21s11d ci/iris.sh live answers` -- passed: X1-X15, C1-C10. **Browser:** Chromium, project `answers`. This unit cannot be split, and it runs longer than 150 s (446 s in CI), so expect the harness to background it and poll.
- (once) `<vars> OCUTALON_RUN_TAG=e21s11d ci/iris.sh live demo-path` -- passed (online-demo safety).
- (once each) `bash docker/tests/test-class-rules.sh` and `bash docker/tests/test-boundaries.sh` -- pass.
- (once, after S1 and S2) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- no finding beyond the baseline.
- (once each, also after a failure) `<vars> OCUTALON_RUN_TAG=e21s11dw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s11d ci/iris.sh teardown`.
- (code review, fresh check) `<vars> OCUTALON_RUN_TAG=e21s11dcr ci/iris.sh class OcuTalon.Test.Core.EmailRequestNotices` (fresh) -- passed (13.78 s), then `... ci/iris.sh teardown`. After the review patches, warm `e21s11dcrw`: `class OcuTalon.Test.Core.BridgeSink`, `... OcuTalon.Test.Core.WebChatOut` and `... OcuTalon.Test.Core.EmailRequestNotices` (twice, the second on the used stack) -- passed; then `ci/warm.sh down`.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A standalone email request (kind `fix`, no incident, FixKind `email`, a session owner) now reaches every channel. `BridgeSink` raises `fix.emailRequest` with empty `Slots`, reuses a tool call's `answered.*` branches, and sends `fix.emailSent` or `fix.emailNotSent` {reason} (an accepted sentence, else `MESSAGEFAILED`). Each `*Out` operation renders the request through the new `BridgeSink.RequestText`, which reads the stored dry run by the ApprovalRef, so no recipient, subject or text is in a Notification or the Ens trace (V6 pin: `Test.Core.EmailRequestNotices`, mutation shown red). The rail row reads "Send an email". S1 (AD-32) and S2 (AD-31) are in the spine; N1-N4 are in EXPERIENCE.md.

**Files changed.**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`: N1-N3.
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`: keys, `Standalone`, `EmailReasons`, `EmailReason`, `RequestText`, the `ToolNotice` gate and the `ToolNoticeOf` branches, class doc.
- `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls`, `Channel/WebChat/Out.cls`: the request branch; WebChat's `ToolCallCard` lists the three keys.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls`: `STOREDKEYS`, one render branch, one doc line (V5).
- `web/src/app/rail/rail-view.ts`: `RAIL_TEXTS.sendEmail` and the `approvalTitle` branch.
- Tests: `Test/Core/BridgeSink.cls`, `Test/Core/EmailRequestNotices.cls` (new, live), `Test/Core/WebChatOut.cls`, `Test/Demo/SimPhoneOut.cls`, `Test/Channel/TelegramOut.cls` (one test), `Test/Msg/Catalog.cls`, `web/scripts/rail-view.test.mjs`, `web/scripts/ux-strings.test.mjs`, `web/scripts/playwright-projects.test.mjs`, `web/e2e/answers/answers.spec.ts` (X15), `docker/tests/test-answers.sh`.
- Docs: `ARCHITECTURE-SPINE.md` (S1, S2), `EXPERIENCE.md` (N1-N4).

**Review.** 25 findings from four layers: 0 high, 0 medium, 23 low, 2 false. Two low patches applied: the review's missing `mutation:` lines were run and recorded (eight more, each red and reverted), and the dead `row.OwnerRef` clause in `RequestText` was deleted. The other 21 were rejected with their reasons in the Review Triage Log. No deferrals.

**Follow-up review recommended:** false (no high or medium patch).

**Verification (final tree, lane D).** Warm: `BridgeSink`, `Msg.Catalog` (158 Core keys), `WebChatOut`, `SimPhoneOut`, `TelegramOut`, and the Fix.Email P4 methods `TestApprovedEmailIsInNoTraceGlobal` and `TestChatTurnsLeaveNoAddressSubjectOrTextInTheTrace` passed. Fresh: `EmailRequestNotices` passed; `live answers` passed (26 cases, X1-X15 and C1-C10); `live demo-path` passed. `catalog.mjs --check` current, `node --test web/scripts/` 2,115 pass, `tsc -p tsconfig.e2e.json` clean, `npm run build` clean, `test-class-rules.sh` and `test-boundaries.sh` pass, `lint_spine.py` 10 findings, the same as the baseline. The nine spec mutations and nine more were each observed red and reverted with `cmp`. All stacks were torn down.

**Residual risks.** The new tests build the email row by fixture; the real raise path is covered only by 22.7's unchanged P4 tests. A Telegram request with a very long text splits into many messages (Decided 3, V8 KEEP). The spec's "nine BridgeSink and SettingsOps keys" is nine BridgeSink keys in `ToolCallCard` (six tool-call and three email).
