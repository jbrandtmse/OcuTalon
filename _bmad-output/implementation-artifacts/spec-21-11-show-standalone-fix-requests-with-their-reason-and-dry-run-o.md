---
title: 'Story 21.11: Show standalone fix requests with their reason and dry run on every channel'
type: 'feature'
created: '2026-11-15'
status: 'ready-for-dev'
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

## Spec Change Log

- 2026-11-15 (lane D lead). **Lane exception (orchestrator, Planner 1.0.11 priority):** lane D builds 21.11 because lane C is on DW-1347; lane C does not touch this branch. Runtime moves to lane D: slot `ocutalon-slot-d`, port 52804, the `lane-d` lock folder, tags `e21s11dw` (warm) and `e21s11d` (fresh). Integrated over feature 20b60564 (includes 21.9). DW-1347's files stay out of scope (`Mcp.Proxy`, `Bridge.Poll`, `Bridge.Process.Decide`, Bridge `HostData`/`Reply`, `Checks.Process`, `Test.Mcp.Source*`, `Test.Bridge.Poll`). The spine's AD-31 S2 is additive, written under `spine.lock`.

## Review Triage Log

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

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned only; nothing is implemented. The spec passed the READY FOR DEVELOPMENT check after one review pass. Before implement, the gate must rule veto items V1 to V8 (new texts N1 to N4, the Lane A Telegram edit, the stored-text note, and spine items S1 and S2).
