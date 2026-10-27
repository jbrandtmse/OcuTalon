---
title: 'Story 6.3: Answer on the simulated phone and see every answer everywhere'
type: 'feature'
created: '2026-10-27'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md'
warnings: ['multiple-goals', 'oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** An incident notice reaches the simulated phone as a Delivery row only (`SimPhoneOut.CARDKINDS` is `tellnow,reminder`), so the phone has no message, no Approve or Reject and no in-place edit. Nothing on the page says when a request was answered somewhere else, the rail's approval row can't be pressed, and `NoticesIn` is still a stub. CI has no check that every copy shows the first answer within NFR-9's bounds.

**Approach:**
- **The phone.** `SimPhoneOut` renders `incident` and `approval` notifications as phone messages that carry the request's Ref. It edits the delivered message in place on an `answered` notification (`Delivery.FindByApproval`).
- **Answering from the phone.** The phone draws Approve and Reject for a request message and answers through 6.2's endpoint with channel `phone`, using the card's press logic, which is moved into a shared class.
- **The rest of the page.** The card announces an answer that came from elsewhere, and the rail row jumps to the card.
- **Server pieces.** `NoticesIn` becomes the real adapterless entry, and `BridgeSink.Step` accepts a SessionBroken retry's item (DW-128, waiting on a ruling).
- **Tests.** A new e2e unit `live:answers` pins NFR-9's 2 s and 5 s bounds and the first-answer rule on every CI run. Demo-path steps 4 and 5 run on fixtures.

## Boundaries & Constraints

**Always:**
- **Buttons on the phone (AD-32).** A phone message gets Approve and Reject only when `SimPhoneOut` stored the notification's `ApprovalRef` on it, and it stores one only for kinds `incident` and `approval`.
  - An `answered`, `result`, `tellnow` or `reminder` notification never gives a message an `ApprovalRef`.
  - The page draws the two buttons only for a message that has an `approvalRef` and has no answer, neither the server's nor the phone's own. It never derives them from the approvals store.
- **The phone follows only its own channel.** It follows the `answered` notification (the server's edit of its message) and its own press. It never follows the `approval` event. The web card follows the `approval` event, and the rail row leaves on it (6.2 as built).
- **Texts are the catalog's.**
  - The server's message text is `Msg.Catalog.Render(key, slots, "phone")`, the text form that Telegram also gets.
  - The page renders its own phone statuses in message form from the generated catalog (`renderMessageText`, times from `page-time.ts` `messageTime`), never from copies.
  - The late-press notice on the phone is the 409's own `error.message`.
  - Text is bound by interpolation, styles use DESIGN.md tokens, and non-ASCII is written as escapes (Rule 14).
- **One answer path.** The phone's press is `POST /api/v1/approvals/:ref/answer` with `{action, channel: "phone"}` through 6.2's `AnswersIn` → `AnswerOps` → `Approval.Answer`, with the same who-may-answer rules, busy rule and error texts. No `SessionRef` or user comes from the client (AD-4, AD-11).
- **Speech and focus.**
  - The page speaks only through `Announcer`, and focus moves only through `shared/focus-rule.ts` or the user's own move (`Layout.focusRegion`).
  - Each answer is announced once, and only where it didn't take focus (E:430).
  - The phone is not a live region. It announces only its own press's notices: busy, late press and errors.
- **NoticesIn joins a turn's thread** through the bridge context's `ThreadSessionId` and `SuperSession`, never through `Trace.Join` (AD-26). It forwards to `Notify` asynchronously.

**Never:**
- **No Lane A or other contended edits** except the DW-128 line, which waits on a ruling (Design Notes).
  - Not `src/bridge/**`, `Watch/**`, `Fix/**`, `docker/**` (existing files), `.github/**`, `ci/mock/**`, `Core/{SessionOps,StatusMonitor,Allowance,Trace}*.cls`, `Data/{Ownership,Session}.cls`, `Test/Web/**`, `web/src/app/{live,api,header,guide,mailbox}/**` (own entries in api-client and api-types excepted; `payloads.ts` regenerated only), `docker/tests/test-demo-path.sh` or any existing `docker/tests/**` file.
  - Never `rail-view.ts` L305-330: Epic 5's L308 and Epic 4's lines.
- **No new security object, grant or role.** No new catalog key, no new REST code and no change to the answer route.
- **No case added to `live floor`, `live sign-in` or `live demo-switch`.** Existing cases change only where a shared surface moved (Verification › Shared surfaces).
- **Not this story:**
  - result bands, Dismiss and `result` on the phone (6.4);
  - BridgeSink's tool-call notices through NoticesIn (31.2) and the daily-cap message (16.9);
  - standalone tool-call request cards (steps 4 and 5);
  - Telegram (10.3, 12.x).

## I/O & Edge-Case Matrix

Fixture values: session S in demo mode, incident R with its `incident` payload published, request A pending (kind fix, `incidentRef` R, dry run 50/50 `OrderDate` `10/16/2026` → `2026-10-16`, RequiredRole `OcuTalonUser`) with its `approval` event. "HH:MM" is the instance-zone clock of the time named.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Incident notice on the phone | `Notification` kind `incident`, key `incident.withFix` (count 50, itemNoun, time, cause, fixSummary, field, before, after, resendCount 50), `ApprovalRef` A, `IncidentRef` R | **Server:** one SimMessage (phone, out) with `Text` = `RenderAt(key, slots, "phone")`, `ApprovalRef` A and an empty `Answer`; one phone Delivery row (kind incident, A, ChannelMessageId = the message's Ref); one `phone` event with `approvalRef` A and an empty `answer`. **Page, in the phone, top to bottom:** the notice paragraph; the dry-run paragraph as an inset on `surface`, with `10/16/2026` in `mono-sm` danger-ink and `2026-10-16` in `mono-sm` success-ink; "Details and trace: on your OcuTalon page."; Approve (left, primary) and Reject (secondary) side by side, each half the row and 40 px tall, named "Approve: repair and resend 50 orders" and "Reject: ..."; the caption time. The web chat gets no notice card (6.1) | A render error: error status, no row, no event (as today) |
| Later request | kind `approval`, key `incident.laterRequest`, `ApprovalRef` A2 | a second phone message with its own buttons for A2 | — |
| No request on the message | kind `incident` with no `ApprovalRef` (`incident.fallback`), or a `tellnow` that carries an `ApprovalRef` | a message with an empty `approvalRef` and no buttons | — |
| Dry run unknown to the page | the store has no `approval` payload for A, or its `before`/`after` are not found in the text as "{field} {before} becomes {after}" | the text shows as plain paragraphs with no inset styling; the buttons are named "Approve" and "Reject" | — |
| Approve on the phone | press Approve → 200 | Both phone buttons are busy (spinner, `aria-busy`, `aria-disabled`, never `disabled`). Then "Approved from the simulated phone at HH:MM." (message form, `circle-check`) replaces them, and a focused button's focus moves to that line. **The card** shows "Approved from the simulated phone at HH:MM" within 2 s of the reply. **The rail row** leaves within one live update. **The row:** approved, AnsweredChannel `phone`, AnsweredBy the session's user, one AnswersIn→AnswerOps header. The card does not announce it while focus is on the phone's answer line | — |
| Reject on the phone | press Reject → 200 | "Rejected from the simulated phone at HH:MM. Nothing was changed." (`circle-slash`) | — |
| Answered on the web, phone follows | Approve on the card → 200; the stand-in for IncidentManager then sends `answered` (key `answered.approved`, slots {channel web, time AnsweredAt}, A, R) | **Server:** `FindByApproval(A, "phone", S)` finds the message, which keeps its Ref and Text and gets `Answer` "Approved from the web chat at HH:MM."; one more `phone` event with that ref; no new message; a phone Delivery row (kind answered, ChannelMessageId = the message's Ref). **Page:** the line replaces the phone's buttons within 5 s of the web answer's reply, in place (the feed doesn't move). Before that notification the phone keeps its buttons | `answered` whose message is missing (none delivered, or another session's): Delivery row only (ChannelMessageId ""), no message changed, no event |
| Late press on the phone | A already answered on the web (no `answered` notification yet), the phone still shows buttons; press Approve | 409. The notice is the reply's message, "Already answered: approved from the web chat at HH:MM.", shown and announced once. The answer line from the 409's payload replaces the buttons. The row is unchanged (channel `web`) | — |
| Phone busy and failure | reply held; 404; 403; 5xx; status 0 | Held: one POST however often pressed, `channel: "phone"` in the body; after 10 s both buttons restore, with "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting." shown and announced; a later answer still shows. 404: "That request is no longer available." 403 and 5xx: the reply's `error.message`. 0: the busy notice at once | — |
| Answered elsewhere, the card | A goes from pending to approved by the store's `approval` event (phone or Telegram); focus is on neither answer line of A | the card's status replaces its buttons and is announced once ("Approved from the simulated phone at HH:MM") | The card's own press (its local view), or focus then on the card's status or on the phone's answer line of A: no announcement |
| Rail row press | pending A whose incident card is in the chat; press its row | focus is on A's request card (`[data-part="approval"][data-key=A]`), and the card is in view; in the drawer band (1024-1279 px) the drawer stays open | A request with no `incidentRef` (tool_call): the row has no button. Card not in the chat: focus goes to the chat list |
| Phone holds for a pending request | a request message with buttons on screen, then a tell-now arrives | the feed's `scrollTop` is unchanged, New messages shows, Approve's box is unchanged (UX-DR67, UX-DR82) | — |
| NoticesIn | `NoticesIn.Send(notification)` from a job with no bridge context | it is sent to Notify async in a session of its own, with SuperSession = the session's TraceRef; delivered on each of the session's channels (a web Delivery row; the phone's message in demo mode) | Not a Notification, or no production running: an error status, nothing sent |
| NoticesIn inside a turn | the same, inside `Bridge.Context` with ThreadSessionId T and SuperSession X | the Notify header's SessionId is T and its SuperSession is X | ThreadSessionId 0 or empty: a session of its own, with SuperSession X |
| DW-128 retry step | running turn with ItemId I; context ItemId = `Conversation.RetryItemId(I)`; `turn.step` | one `turn.step` event with the turn's Ref | context ItemId = `RetryItemId` of another item: nothing (as for another item) |

</intent-contract>

## Code Map

**Server, to change:**
- **`src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls`**: the class doc (L1-12), `CARDKINDS` (L20), `OnNotification` (L38-52) and `Save` (L54-67). The doc's "until the story that designs that kind's phone form" ends here.
- **`Channel/Operation.cls`**: `IsSession` (L15-21), `Announce` (L25-34), and `Keep` (L38-58), which saves a message and its Delivery row in one transaction and is reused for the edit.
- **`Data/SimMessage.cls`**: the properties end at `Subject` (L35-36), followed by the indexes and storage. The class is Lane B's, with the global `^OcuTalonP.SimMsg`.
- **`Live/Payload/Phone.cls`**: `ApprovalRef` (L14-15) exists, and `FromRow` (L20-31) sets it to "".
- **`Core/NoticesIn.cls`**: the stub, with `STUB = 1` (L7).
  - The sibling is `Core/CommandsIn.cls` `Join` (L117-130), which sets `%SessionId` from the context's ThreadSessionId and `%SuperSession` from the context or the Session's TraceRef.
  - The probe pattern is `Test/Core/CommandsInProbe.cls`.
- **`Core/BridgeSink.cls`**: the `turn.step` bullet of the doc (L8-11), `Step` (L128-151), and the guard at L145 (DW-128).
- **`Test/Core/ProductionItems.cls`**: L26, the NoticesIn row with `"stub": 1`.

**Server, read only:**
- **`Data/Delivery.cls`**: `Record` (L48-67) and `FindByApproval` (L72-78), which gives the newest exact row through `Ownership.DeliveryFor`.
- **`Msg/Notification.cls`**: `ApprovalRef` and `IncidentRef` (L20-24).
- **`Core/Rule/Notify.cls`**: L42-47 sends any kind but pairing and allowance to WebChatOut, plus SimPhoneOut in demo mode.
- **`Bridge/Context.cls`**: `ThreadSessionId` (L35), `SuperSession`, and `Begin` (L59-73).
- **`Core/Conversation.cls`**: `RetryItemId` (L496-499), public.
- **The catalog:**
  - `Msg/Catalog/Watch.cls`: `incident.withFix` (L78) and `incident.laterRequest` (L99), each with a `one` form on `resendCount`, plus `incident.fallback` (L119).
  - `Msg/Catalog/Core.cls`: the `answered.*` keys (L80-155). Only `approved` and `approvedBy` have a `web` form.
  - `Msg/Catalog.cls`: L25 and L139-143 turn "at " into "on " before a dated time, and L163 defines dated as a time that is not `NN:NN`. L101: phone, telegram and mailbox render `text`.
- **`Web/Api.cls`**: the snapshot's `phone` (L591-596, `Phone.FromRow` per row) and `AnswerBody`, which accepts `phone` (L426).

**Server test patterns:**
- `Test/Demo/SimPhoneOut.cls`: the header (L1-20), `TestOtherKindsRecordOnly` (L167-195, which lists incident, approval and answered as record-only), and `TestThroughNotify` (L293).
- `Test/Data/Tables.cls`: the SimMessage contract (L393-410).
- `Test/Live/Payloads.cls`: the Phone row (L770-779).
- `Test/Core/BridgeSink.cls`: `TestTurnStepOfAnotherItem` (L482-504; `Request(itemId)`, `Sink`, `Events`).
- `Test/Core/InProduction.cls`, and `RoutingProduction.cls` (`SendTo`, `WaitDeliveries`, `WaitHops`, `WaitEvents`; L248-309).

**Web, to change:**
- **`web/src/app/phone/simulated-phone.ts`**: the template (L33-63, `.notification`/`.text`/`.time`), the `.text` style (L145-149), `messages` (L215), and the scrolling code (L231-307). Its doc says "Nothing here is a live region".
- **`phone/phone-view.ts`**: `PHONE_TEXTS`, `phoneOf`, and `pendingRef`/`pendingApproval` (L42-57), which are store-based.
- **`approvals/approval-request-card.ts`**: `ANSWER_RULE` (L46-49), `approvalContext` (L55-66), the root section (L93), the status `p` (~L161), and the press flow (L340-461: BusyState, `press`, `replied`, `noticeOf`, `notify`).
- **`approvals/approval-view.ts`**: `APPROVAL_TEXTS` (L22-46), `ApprovalContext` (render, timeBeside, title), `statusOf` (L216-232, reached through `approvalView(...).status`), `answerOutcomeOf`, and `latePressText` (L289-318).
- **`api/api-client.ts`**: `answerApproval` (L56-62) hard-codes `channel: 'web'`. It is 6.2's own entry.
- **The catalog generator:** `web/scripts/catalog.mjs` (header L1-27, `LISTED_KEYS` L40) and the generated `msg/catalog.ts` (`PAGE_TEXTS`, `renderPageText`).
- **`rail/rail-view.ts`**: `approvalTitle` (L165-175) and `approvalRow` (L191-203).
- **`rail/status-rail.ts`**: `FOCUS_RULE` (L35-39), the class doc ("Rows are read-only", L57-67), and the row template (L92-125). The button precedent is `rail/decision-row.ts` L34-41.

**Web, read only:**
- `chat/page-time.ts`: `messageTime(iso, nowMs, instanceZone, onlineDemo)` (L226-240).
- `shared/layout.ts`: `focusRegion(selector)` (L62-68), which focuses with `preventScroll` and then `scrollIntoView({block:'start'})`.
- `shared/focus-rule.ts`: `keepFocus` (L53). It records the focused item before a render. After the render it acts only if focus fell to the body, so of two hosts the first callback to move focus wins.
- `devices/device-panel.ts`: `FOCUS_RULE = {}` (L16-17), whose `keepFocus` runs on every store change (L254-258). The phone is inside this host.
- `chat/chat-panel.ts`: the list (L105-113), `onScroll` (L369-381), and `scrollToBottom`/`headlineTop` (L433-452). The cap yields while focus is inside the newest incident card.
- `live/live-store.ts`: L44 and L47 key `approval` and `phone` by ref, replaced in place. `live/live-state.ts` L18 sets `POLL_DELAY_MS = 1000`, a fixed delay with no long poll.
- `web/src/styles/tokens.css`: `--phone-notification-button-height` (L484), `--type-mono-sm-*` (L91-92), `--dry-run-block-*` (L424-431), `--danger-ink` and `--success-ink`.

**UX:**
- EXPERIENCE: L236 (the rail row), L301-302 (the phone), L379-382 (busy), L414-430 (focus and speech), L665-671 (answered, late press, message form), L792.
- DESIGN L839 (the phone notification) and L501-506.
- Mockups: `mockups/states.html` F1 (L864-884) and F2 (L888-911), and `main-page.html` L518-522 and L765-768.

**E2E and CI:**
- **`web/e2e/support/iris.ts`:**
  - `FixtureKind` (L44) and `NotificationFields` (L531-537, which has no `incidentRef`);
  - `sendNotification` (L617), `publishIncident` (L145), `sinkEvent` (L431) and `cleanFixtureRows` (L636);
  - `seedApproval` (L691), `answerQuietly` (L747), `readApproval` (L761) and `answerHeaders` (L779).
- **`support/devices.ts`:** `dropPhone(user, sinceUtc)` (L57) and `phoneRows` (L93).
- **Sign-in and floor helpers:** `sign-in/helpers.ts` `signIn` (L60) and `signInReadme` (L94); `support/floor.ts` `openFloor` (L135, the pattern) and `applied` (L143).
- **Patterns to follow:** `floor/approval.spec.ts` (the locators and `raise`/`incidentOf` at L49-131; A5 at L354-383); `chat/notice.spec.ts` N10 and N11 (L286-310 and L466-490, the P30 clock); `live/live.spec.ts` L106-128 (the 2 s bound).
- **Demo path:** `web/e2e/demo-path/04-incident.spec.ts` L92-93, `05-approval.spec.ts` L4, and `not-built.ts` L11-15.
- **The unit's wiring:**
  - `docker/tests/test-floor.sh` is the pattern for a browser unit, with `live_fixture_user` from `lib-live.sh`.
  - `ci/units.sh`: `group_units` (`browser` at L37) and `BROWSER_UNITS` (L42).
  - `web/playwright.config.ts` holds the projects, with chromium's `testIgnore`. `web/package.json` holds the `e2e:*` scripts (L14-17).
  - `web/scripts/playwright-projects.test.mjs` pins the projects.

## Tasks & Acceptance

**Execution:**

1. **`src/ocutalon/cls/OcuTalon/Data/SimMessage.cls`.** Add `ApprovalRef As %String(MAXLEN = 22)` (the approval request a phone message asks for) and `Answer As %String(MAXLEN = 1000)` (the answered line in message form that replaced its buttons). Neither has an index.
   - Export the storage block from the slot as compiled: new values after `Subject`.
   - Rows written before this read both as empty (AD-5).
   - Update the class doc. This is Veto V1.
2. **`Live/Payload/Phone.cls`.** Add `Answer As %String(%JSONFIELDNAME = "answer", MAXLEN = 1000)`. `FromRow` copies `ApprovalRef` and `Answer` from the row. Update the doc.
3. **`Channel/SimPhone/Out.cls`.**
   - Kinds `tellnow`, `reminder`, `incident` and `approval` become messages. `ApprovalRef` is stored on the message only for `incident` and `approval`.
   - **`answered` edits in place.**
     1. `Delivery.FindByApproval(ApprovalRef, "phone", SessionRef)` gives the message's Ref. The message is opened by `RefIndexOpen`, and it must be the same session's message of kind phone.
     2. `Answer` is set to `Render(CatalogKey, Slots, "phone")`.
     3. The message is saved with a Delivery row (kind answered, ChannelMessageId = the message's Ref) through `Keep`, and one `phone` event is published.
   - **When `answered` finds no message**, or the key is empty: `Delivery.Record` only (ChannelMessageId ""), no event. A render error on a found message gives an error status and changes nothing.
   - `result` and the other kinds stay record-only.
   - Update the class doc.
4. **`Core/NoticesIn.cls`.** Remove `STUB` and the stub handler.
   - **`ClassMethod Send(notification As OcuTalon.Msg.Notification) As %Status`** creates the service in the caller's process (`Ens.Director.CreateBusinessService("NoticesIn", ...)`) and calls `ProcessInput`. A missing production or service gives its error status.
   - **`OnProcessInput`:**
     - an input that is not an `OcuTalon.Msg.Notification` gives an error status and nothing is sent;
     - it then joins, by the CommandsIn.Join rule: inside an active `Bridge.Context`, `..%SessionId` is the context's ThreadSessionId when it is > 0, and `..%SuperSession` is the context's SuperSession; otherwise there is no SessionId, and the SuperSession is the TraceRef of the notification's Session row;
     - it then sends `SendRequestAsync("Notify", notification)` through a private `Send` seam (the probe's), and returns that status.
   - The class doc covers AD-26, AD-31 and AD-32 and names 31.2 and 16.9 as the senders to come.
5. **`Test/Core/ProductionItems.cls`.** The NoticesIn row gets `"stub": 0` (own row).
6. **`Core/BridgeSink.cls` (contended, allowed by the orchestrator's ruling; Design Notes: only L145 and the doc clause at L10-11).**
   - Replace L145 with a check that quits only when the context's ItemId is neither `running.ItemId` nor `##class(OcuTalon.Core.Conversation).RetryItemId(running.ItemId)`.
   - In the doc (L10-11), add "or of its SessionBroken retry".
   - If the ruling is no, skip this task and Task 10 and apply the fallback.
7. **`Test/Data/Tables.cls` and `Test/Live/Payloads.cls`.** Add `ApprovalRef` and `Answer` to the SimMessage contract (Lane B's own entry), and `Answer` to the Phone row.
8. **`Test/Demo/SimPhoneOut.cls`** (extend Story 4.5's class).
   - **Update `TestOtherKindsRecordOnly`** to the kinds `result,fallback,allowance,pairing,status,digest`. Its incident-with-tell-now-key half now gives a message with no ApprovalRef.
   - **Add these tests:**
     - `TestIncidentNoticeAsksForItsRequest`: the text, ApprovalRef, Delivery and event of the first Matrix row;
     - `TestLaterRequestHasItsOwnButtons`;
     - `TestOnlyRequestKindsCarryARequest`: tellnow, reminder and answered each carry an ApprovalRef and give no message with one;
     - `TestAnsweredEditsInPlace`: the same Ref and Text, the Answer equals `RenderAt(..., "phone")`, one message, two events, the answered Delivery row;
     - `TestAnsweredWithNoMessageRecordsOnly`;
     - `TestAnsweredNeverEditsAnotherSessionsMessage`;
     - `TestAnsweredRenderErrorChangesNothing`.
   - Expected texts come from `RenderAt` with the clock and the online-demo flag fixed. Update the header.
9. **`Test/Core/NoticesIn.cls`, `NoticesInProbe.cls` and `NoticesInProduction.cls`** (new). Neither probe adds anything to the product.
   - **`NoticesInProbe`** extends NoticesIn and overrides `Send` to record `%SessionId`, `%SuperSession` and the target.
   - **`Test.Core.NoticesIn`** runs with no production, on a shadow probe's `OnProcessInput`:
     - outside a context: no SessionId, SuperSession = TraceRef, target Notify;
     - inside a context with ThreadSessionId T and SuperSession X: T and X;
     - ThreadSessionId 0: a session of its own;
     - a non-Notification: an error, and nothing sent.
   - **`Test.Core.NoticesInProduction`** extends `InProduction` (throwaways and CI only):
     - `NoticesIn.Send` of a fixture tell-now with demo mode on gives, within WAIT, the session's web Delivery row and its phone SimMessage and Delivery row, and one NoticesIn→Notify header with SuperSession = TraceRef;
     - a fixture `incident` notification with an ApprovalRef gives the phone message with that ApprovalRef;
     - inside a `Bridge.Context` with ThreadSessionId T, the NoticesIn→Notify header's SessionId is T.
   - Remove the rows, the messages and the log rows as InProduction does.
10. **`Test/Core/BridgeSink.cls` (pending the same ruling).** Add `TestTurnStepOfARetry`:
    - a context with `RetryItemId(itemId)` publishes one `turn.step` with the turn's Ref;
    - `RetryItemId` of another item publishes nothing.

    Update the header bullet.
11. **`web/src/app/live/payloads.ts`.** Regenerate with `npm --prefix web run payloads`; never edit it by hand. `PhonePayload` gains `answer`.
12. **The catalog generator: `web/scripts/catalog.mjs`, `catalog.test.mjs`, and `web/src/app/msg/catalog.ts` (regenerated).**
    - Emit `MESSAGE_TEXTS`, the `text` form of each listed key that has a `web` form.
    - Emit `renderMessageText(key, slots)`. It fills `MESSAGE_TEXTS[key] ?? PAGE_TEXTS[key]` as `renderPageText` does, and applies the renderer's rule: a `time`-typed slot whose value, less a trailing " ET", is not `NN:NN` turns a preceding "at " into "on ".
    - Update the header contract and the tests. Each expected string is written out as `Catalog.RenderAt` gives it, including "Approved from the web chat on Thursday at 14:12.".
13. **`web/src/app/api/api-client.ts` and `api-types.ts`.** `answerApproval(ref, action, channel: 'web' | 'phone' = 'web')` posts `{action, channel}`. Update the doc.
14. **`web/src/app/approvals/answer-press.ts`** (new). This is the card's press logic moved out unchanged (Rule 2).
    - **What it holds:** one `BusyState` for both buttons; `press(ref, action)`, which ignores a repeat; the call with the given channel; `answerOutcomeOf`; the `local` approval from a done, already or expired reply; and the notice.
    - **The notices:**
      - `already` gives `latePressText(approval, ctx)` or the reply's message;
      - `gone` gives `APPROVAL_TEXTS.gone`;
      - `notAllowed` and `failed` give the reply's message;
      - `unreachable` gives the busy notice.
      - A new press clears the notice.
    - **What it announces:** each notice, once, and the busy notice after 10 s.
    - It is disposed with its host.

    **`approval-request-card.ts`** uses it with channel `web`, with identical behaviour (floor A2-A10 stay green). The card also announces the answered status when **all** of these hold:
    - the store's `approval()` goes from pending to answered;
    - no local view of its own exists;
    - focus, after the render (`afterNextRender`), is neither on its status nor on `app-simulated-phone [data-part="answer"][data-approval="<ref>"]`.

    Update the doc.
15. **`web/src/app/phone/phone-view.ts`.**
    - **`requestView(message, approval | undefined, local | undefined, ctx)`** gives:
      - `blocks`: the text split at blank lines, the one holding "{field} {before} becomes {after}" from `approval.dryRun` marked `inset`, with `before` and `after` parts;
      - `buttons`: `approvalRef` set, no `answer` and no `local`;
      - `answer`: `{text, tone, icon}`, the server's `answer` first, else `approvalView(local, ctx).status`, with the tone from `local`, else from the store's state, else neutral with no icon;
      - `approveName` and `rejectName`: from `approvalView(approval, ctx)`, else "Approve" and "Reject".
    - `pendingRef` and `pendingApproval` also require an empty `answer`.
    - Imports stay type-only.
16. **`web/src/app/phone/phone-request.ts`** (new, `app-phone-request`). It renders one request message inside the same `.notification` element (`tabindex -1`, `data-key`):
    - the blocks, with the inset on `surface` holding `mono-sm` danger-ink and success-ink spans;
    - then `<span data-part="answer" [attr.data-key]="message ref">` holding two `controls.css` buttons (primary Approve first, then secondary Reject), with a grid of two equal columns and a gap of `space-2`, height `--phone-notification-button-height`, `aria-busy` and `aria-disabled`, a spinner, and never `disabled`;
    - or, once answered, `<p data-part="answer" [attr.data-key]="message ref" [attr.data-approval]="approvalRef" tabindex="-1" class="answered">` with its icon;
    - the notice (`app-inline-notice` warning, `aria-describedby` on the buttons);
    - the caption time.

    It uses `AnswerPress` with channel `phone` and a message context:
    - `render` is `renderMessageText`;
    - `timeBeside` is `messageTime(iso, now, instanceZone, onlineDemo)`;
    - `title` is `approvalTitle`.

    Lost focus goes to the answer line through `keepFocus` with a `PHONE_ANSWER_RULE` of the `ANSWER_RULE` shape.
17. **`web/src/app/phone/simulated-phone.ts` and `web/src/app/devices/device-panel.ts`.**
    - **`simulated-phone.ts`:**
      - A message with an `approvalRef` renders `app-phone-request`, given its `approval` from the store and the snapshot's `instanceZone`, `onlineDemo` and `user`. Every other message keeps today's markup.
      - `showNew` looks up `.notification[data-key]`, so the answer part's key never matches.
      - Update the doc: the phone announces its own press's notices only.
    - **`device-panel.ts`:** its `FOCUS_RULE` (L17, today `{}`) gains the chat panel's item rule: `item: '[data-part][data-key]'`, with `keyOf` giving `${part}:${key}` and no `whenGone`.
      - **Why:** the panel's `keepFocus` (L254-258) runs on every store change and registers its `afterNextRender` before the request's. With `{}`, a server edit that replaces a focused phone button would send focus to the main region before the request's rule runs (`shared/focus-rule.ts`: the first callback to move focus wins).
      - **The mailbox is unchanged:** its rows carry `data-key` without `data-part`.
18. **`web/src/app/rail/rail-view.ts` and `status-rail.ts`.**
    - `approvalRow` adds `jump` (the ref) only when the request has an `incidentRef`, and `jumpName`, which is `RAIL_TEXTS.showInChat` "Show in the chat: {action}" with the lower-cased title (Veto V2).
    - The row's title becomes `<button type="button" class="jump" [attr.aria-label]="row.jumpName">`, like decision-row's line button, beside the trace link and never wrapping it.
    - A press calls `Layout.focusRegion` with `app-chat-panel [data-part="approval"][data-key="<CSS.escape(ref)>"]` when that element exists, else `app-chat-panel > .list`.
    - Update the doc ("Rows are read-only" no longer holds for this row). Nothing between L305 and L330 changes.
19. **The web script tests:** `phone-view.test.mjs`, `approval-view.test.mjs`, `approval-sources.test.mjs`, `announce-focus-sources.test.mjs`, `ux-strings.test.mjs`, `rail-view.test.mjs`, `catalog.test.mjs`, `payloads.test.mjs` and `playwright-projects.test.mjs`, plus `web/scripts/phone-request-sources.test.mjs` (new).
    - Unit-test every Matrix row of the page: the blocks, inset, buttons, names, tones, pending rules, outcome notices and message-form texts (written out).
    - **Move the card's source pins** to `answer-press.ts`: one BusyState, never `disabled`, posting only `{action, channel}`.
    - **The focus and speech inventory:** add `app/phone/phone-request.ts` (the notices of the phone's own press) and `answer-press.ts` to the speakers; add `phone-request.ts` with `PHONE_ANSWER_RULE` to the focus-rule hosts; change `device-panel.ts`'s pinned rule (L147, today `{}`) to its item rule; give the card's reason its answered-elsewhere announcement.
    - Add `RAIL_TEXTS.showInChat` to `ux-strings` (`ruled` V2).
    - Add `answers` to the projects test.
20. **The e2e helpers:**
    - `web/e2e/support/iris.ts`: `FixtureKind` gains `'ANSWERS'`, and `NotificationFields` gains `incidentRef?` (sets `m.IncidentRef`).
    - `web/e2e/support/devices.ts`: `phoneMessage(user, approvalRef)` gives `{ref, approvalRef, answer, text}` of the newest phone SimMessage with that ApprovalRef.
    - `web/e2e/support/approvals.ts` (new): `DRY_RUN`, `incidentOf` and `raise` for the new unit and the demo path (copy reason in Design Notes).
21. **`web/e2e/answers/answers.spec.ts`** (new, project `answers`, Chromium, `timezoneId` UTC, the real clock): cases X1-X8 under Verification. Every case has its own refs and cleans up in `finally` (`cleanFixtureRows`, `dropPhone`). Each timed case prints its elapsed ms.
22. **The new unit `live:answers`:**
    - `docker/tests/test-answers.sh` (new) follows `test-floor.sh`. It starts one throwaway, creates the fixture user `ZzAnswers` (OcuTalonUser, random password, never printed), and runs `npm --prefix web run e2e:answers` with `OCUTALON_URL`, `OCUTALON_ANSWERS_USER`/`PASSWORD`, `OCUTALON_E2E_IRIS_CONTAINER` and `OCUTALON_E2E_TIMEOUT_MS`. It prints one PASS/FAIL per check, with a 540 s default deadline.
    - `ci/units.sh` (Lane B's entries only): `browser) echo "live:demo-path live:sign-in live:answers"`, and add `answers` to `BROWSER_UNITS`.
    - `web/playwright.config.ts`: project `answers` (`./e2e/answers`, Desktop Chrome), with `**/e2e/answers/**` added to chromium's `testIgnore`; update the doc.
    - `web/package.json`: `"e2e:answers": "playwright test --project=answers"`.
23. **`web/e2e/demo-path/04-incident.spec.ts` and `05-approval.spec.ts`** (REL-2, as the README account, on fixtures, not `@floor`).
    - **04:** add "the incident card and the phone's notice, on fixtures for Lane A's raise path". It seeds A and R, publishes R, sends the `approval` event and sends the `incident.withFix` notification. The test expects the chat's card with Approve and Reject, the phone's message with its buttons, and the rail "Approval requests, 1".
    - **04's skips:** L92 becomes `notBuilt("Break the feed's real failures become that incident (IncidentManager)", '11.1')`. L93 stays.
    - **05:** add "Approve on the simulated phone, on fixtures". It expects the phone's line "Approved from the simulated phone at HH:MM.", the card's "Approved from the simulated phone at HH:MM", and the row approved from `phone`. 05's `notBuilt` becomes "Fixing, then "All 50 orders went through." and Resolved" (`'11.1'`).
    - Rows and phone messages are removed in `finally`.

**Acceptance Criteria:**
- **AC1:** Given a notification of kind `incident` or `approval` with an `ApprovalRef` in demo mode, when `SimPhoneOut` handles it, then the phone shows one message with the catalog's phone text and the compact dry run's values in `mono-sm`, in danger and success ink, with Approve (left) and Reject side by side, half width and 40 px tall. A later request is its own message. No `answered`, `result` or other kind ever carries buttons (`Test.Demo.SimPhoneOut`, X1, `phone-view.test`).
- **AC2:** Given a request message on the phone, when the user presses Approve or Reject, then the page posts `{action, channel: "phone"}` to the answer endpoint, which `AnswersIn` handles as a card's answer. The buttons are busy, restore after 10 s with the announced busy notice, and show the failure notices of the card. The statuses name "the simulated phone" (X2, X5).
- **AC3:** Given a request answered on one channel, when the other places learn of it, then:
  - the card follows the `approval` event;
  - the phone follows the `answered` notification, through `FindByApproval`, by an edit in place (the buttons become "Approved from {channel} at {time}.");
  - the rail row leaves within one live update;
  - a late press on stale buttons gets 409, shows "Already answered: approved from the web chat at {time}." and changes nothing.

  (X2, X3, X4, `Test.Demo.SimPhoneOut`.)
- **AC4 (NFR-9, required CI check):** Given the new unit on the CI stack, which has the model mock, when a request is answered, then:
  - the page shows the answered status within 2 s of the answering call's reply (X2);
  - the phone shows it within 5 s of the web answer's reply (X3);
  - every copy shows the first answer, and no copy accepts a second (X3, X4, and 6.2's A5).

  This runs as `live:answers` in CI group `browser`, on every run whose inputs changed.
- **AC5:** Given an answer, when it shows somewhere, then it is announced once, in the places it did not take focus. The card announces an answer that came from elsewhere. Its own press, or focus on the phone's answer line, means no announcement (X2, X8, `approval-sources.test`).
- **AC6 (REL-2):** Given the demo-path unit, when steps 4 and 5 run, then the incident card and the phone's notice, and Approve on the simulated phone, pass on fixtures for Lane A's raise and answer paths. The remaining parts stay `notBuilt(..., '11.1')` (`live demo-path`).
- **AC7:** Given a pending request with an incident in the rail, when its row is pressed, then focus moves to its approval request card and the card scrolls into view (X6).
- **AC8:** Given a pending request on the phone's screen, when another notification arrives, then the feed doesn't scroll and New messages shows, so Approve and Reject don't move (X7).
- **AC9:** Given a fixture `Notification` sent through `NoticesIn` (an adapterless real item, not a stub), when it is received, then it joins the turn's thread through the context's `ThreadSessionId` when there is one, reaches `Notify` asynchronously, and is delivered on each of the session's channels (`Test.Core.NoticesIn`, `Test.Core.NoticesInProduction`).
- **AC10 (DW-128, ruled yes):** Given a SessionBroken retry's bridge context (`RetryItemId` of the running turn's ItemId), when the gate reports a step, then its `turn.step` reaches the session's stream with the turn's Ref (`Test.Core.BridgeSink`).

## Spec Change Log

- 2026-10-27, runner (spec validation): the orchestrator allowed DW-128's contended edit in `Core/BridgeSink.cls` (option a: L145 and the doc clause at L10-11 only). Tasks 6 and 10 and AC10 stand; the fallback is dropped.

## Review Triage Log

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- **AD-11** (L314-328, amended 2026-10-27 by owner decision U-120 to the answer path as built). `AnswersIn` checks the session from the CSP session, and who may answer. It then hands the answer synchronously to its business operation `AnswerOps`, its only sender. `AnswerOps`' production job calls `Approval.Answer` and takes the answerer only from the server-side session (U-113). The phone's press uses that path unchanged, with channel `phone`.
- **AD-31** (L835-852, amended by U-120): the `approval.answered` fan-out runs in `AnswerOps`' job. For an incident's fix requests, `IncidentManager` (Lane A) sends the `answered` notifications. This story stands in for it with fixtures. BridgeSink's own notices through `NoticesIn` are 31.2's.
- **AD-32** (L853-863, amended by U-120):
  - the kinds, and `ApprovalRef`/`IncidentRef` on `answered`;
  - only `*Out` operations and the page render;
  - Approve and Reject only for `incident` and `approval` with `ApprovalRef`.
- **AD-14** (L396-406): `SimPhoneOut` finds the message to edit with `Delivery.FindByApproval`.
- **AD-12** (L330-343): `phone` and `approval` are full views keyed by Ref, and polling is every 1 to 2 s.
- **AD-26** (L737-755): NoticesIn joins through `ThreadSessionId`, never `Trace.Join`.
- **AD-4:** no client SessionRef, and Ownership reads.
- **AD-5:** the new SimMessage properties read empty on old rows.
- **AD-22:** the required checks are CI units.
- **AD-29:** fixtures and the Approval double stand in for Lane A.
- **AD-33:** SimMessage is Lane B's table, and `phone`'s only publisher is SimPhoneOut. No item, table or event type is new, so the tables don't change.
- **AD-1:** an answer and a notice are production messages.
- **Conventions:** Live events, Notice cards, Announcements and focus, Text OcuTalon sends, Times, SessionBroken retry, and Tests.
- No AC contradicts an AD's Rule.

**NFR-9 (Rule 5): measurable and non-flaky as planned. No halt.**
- **What the NFR says.** It bounds results "within 2 seconds of being sent" on the page, and the other channels within 5 s of the answer (FR-8).
- **The page clock.** X2 starts it when the answering call's reply reaches the browser (`page.waitForResponse`). `AnswerOps`' job publishes the event before `AnswersIn` replies (AD-31), so the reply follows the send. The bound is the expect timeout, 2000 ms, and the elapsed time is logged.
- **The phone clock.** X3 starts it at the web answer's reply. The fixture `answered` send, which stands in for IncidentManager's, follows at once and is counted in.
- **Precedents.** `live.spec.ts` L2 (2000 ms after a publish) and `notice.spec.ts` N11 (5 s from before a send) pass in CI on every run.
- **The margin.** The page polls 1 s after each answer (`POLL_DELAY_MS`), so the worst case is about 1 s plus two poll round trips, (inference) about 1.2 to 1.8 s on the CI hosts.
- **What CI doesn't cover.** IncidentManager's real latency is Lane A's. Epic 11's end-to-end run and the rehearsal measure it over real networks.
- **Where it runs.** `live:answers`, CI group `browser`, on its own throwaway in each run whose group inputs changed (`ci/changes.sh`).

**Contended edit, ALLOWED by the orchestrator's ruling (2026-10-27, decide, policy 36abb05): DW-128.** Option (a): `Step`'s L145 becomes the few lines that also accept `Conversation.RetryItemId(running.ItemId)`, plus the one doc clause at L10-11; nothing else in the class changes. The test is `Test.Core.BridgeSink:TestTurnStepOfARetry` (Epic 6's folder). The runner reports `Core/BridgeSink.cls` under footprint_extensions. Why: no open branch or live tree changes BridgeSink.cls against feature; a later Epic 16 edit elsewhere in the class merges as a plain union. The fallback below no longer applies.
- **The edit.** File `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls` (Epic 16's contended path), method `Step`.
  - L145, `If ##class(OcuTalon.Bridge.Context).Active(), ##class(OcuTalon.Bridge.Context).Current().ItemId '= running.ItemId Quit`, is replaced by about 4 lines that also accept `##class(OcuTalon.Core.Conversation).RetryItemId(running.ItemId)`.
  - The doc's turn.step clause (L10-11) gains "or of its SessionBroken retry".
- **Why.** `Conversation.Ask` sends a broken session's retry under `RetryItemId(turn.ItemId)` (Conversation.cls L406), and `Bridge.Context.Begin` copies that ItemId. So every `turn.step` of the retry is dropped, now that Epic 1's step emitter makes it reachable.
- **The test is Epic 6's:** `Test.Core.BridgeSink` `TestTurnStepOfARetry` (Task 10).
- **Fallback if the ruling is no:** skip Tasks 6 and 10 and record "Declined DW-128: the fix is a line of `Core/BridgeSink.cls`, Epic 16's contended path. The residual is re-owned to Epic 16: Step also accepts `RetryItemId(running.ItemId)`, with a test of a retried turn's steps." No other contended edit is needed.

**Decided in-stage:**
1. **The new e2e unit `live:answers`.**
   - Its parts: `docker/tests/test-answers.sh`, Playwright project `answers`, `web/e2e/answers/`, and its own fixture user `ZzAnswers`.
   - **Group `browser`, after `sign-in`.** Other groups were weighed:
     - `production` is excluded: it is a no-web-bundle group, and `test-ci-changes.sh` pins it.
     - `shards` would grow beyond its 21.5 min.
   - **Expected time:** about 150 s locally (a 55 s stack and about 90 s of cases, each real answer on a fixture row taking about 5 s), and about 400 to 480 s on the CI hosts (inference: 2.5 to 3.2 times the local time).
   - **Its group:** about 14.2 min now (run 40477992332), about 21 to 22 min with the unit, against REL-4's 35.
2. **The phone's buttons depend only on its message.** The message must have an `approvalRef`, and no answer from the server or from its own press. Until Epic 11 brings IncidentManager's `answered` notifications, a phone press after a web answer gets the late press, which is the AC's "buttons that lost the race no longer answer".
3. **The phone's own press shows its answer line from the reply's payload**, in message form (`renderMessageText`, `messageTime`), like the card's local view. The server's `answer` wins once the message is edited.
4. **The phone's late-press notice is the 409's own message**, rendered by the server in message form. Its answer line comes from the 409's payload.
5. **Dry-run styling uses the store's payload.** The inset and the two coloured values come from the store's `approval` payload. Without it, or without an exact "{field} {before} becomes {after}", the text is plain (the snapshot holds pending requests only, DW-292). No extra stored field is needed.
6. **The answer line's tone and icon** come from the local outcome or the store's state, else neutral ink with no icon.
7. **`answered` with no delivered phone message records its Delivery row only.** No new message is added (E:302 is an edit).
8. **The rail jump.**
   - **Which rows.** Only rows with an `incidentRef` jump: tool_call requests have no chat card until the standalone cards of steps 4 and 5.
   - **No card drawn:** focus goes to the chat list.
   - **The drawer band:** the drawer stays open; it pushes the chat aside and is no overlay.
   - **The move:** `Layout.focusRegion`, the app's one user-move focus and scroll, so no new `.focus(` call in the rail.
9. **Answer announcements (E:422, E:430).** The card announces a pending→answered change of the store's payload unless its own press made it, or focus then sits on an answer line of that request (its own, or the phone's, `data-approval`). The phone announces only its own press's notices.
10. **The NoticesIn API.**
    - The way in is `NoticesIn.Send(notification)`. The production test calls it, and so will 31.2's and 16.9's senders.
    - **Not switched to it:** the e2e helper `sendNotification` stays the stand-in for IncidentManager, which sends to Notify itself (AD-31).
11. **`app-phone-request` renders only request messages.** Plain messages keep today's markup, so N11, D1 to D7 and phone.spec's `.text` reads are unchanged.
12. **`result` stays record-only on the phone (6.4).** The fallback and no-fix `incident` notices now render as messages with no buttons. Their wording tests are 6.4's.
13. **The fixture sends use the real clock.** The phone's text times are message times, in the instance zone (UTC on the stacks).
14. **The demo-path tests are not `@floor`.** Epic 11 replaces them end to end.
15. **No Task 0.** The join rule is CommandsIn's, proven in production (AD-26). Answer duration on a fixture row was measured in 6.2 (about 5 s). The page and phone latencies are logged by every X2 and X3 run. Pool-1 Notify→SimPhoneOut keeps arrival order (inference: standard Interoperability FIFO for a pool-1 operation).

**Veto-window choices** (the runner files them):
- **V1, stored data: SimMessage gains `ApprovalRef` (22) and `Answer` (1000).**
  - **Choice.** They hold which request a phone message asks for and the answered line that replaced its buttons, so that a reload shows the edited message.
  - **Rejected options:**
    - deriving both from Delivery rows: a query per message in every snapshot, and no home for the answer text;
    - appending the answer to `Text`: the page could not put it in the buttons' place.
  - **To reverse:** drop the two properties and `FromRow`'s two lines; the storage slots stay unused.
  - **Against the ADs:** AD-5, AD-14 and AD-33 hold. The table's owner is unchanged, and old rows read empty.
- **V2, public text not in the UX: the rail row's accessible name, "Show in the chat: {action}"** ("Show in the chat: repair and resend 50 orders").
  - **Choice.** The visible title is unchanged, and the name contains it, which meets WCAG 2.5.3.
  - **Rejected options:** the bare title, which names an action the button doesn't take (honesty); no button, which the AC rules out.
  - **To reverse:** one `RAIL_TEXTS` entry and its `ruled` source.
  - **Against the ADs:** no AD is touched.

**Files and footprint classes:**
- **Footprint:**
  - `Test/Core/{NoticesIn,NoticesInProbe,NoticesInProduction}.cls` (new) and `Test/Core/BridgeSink.cls` (Task 10, pending the ruling);
  - `Core/NoticesIn.cls`;
  - `web/src/app/approvals/{answer-press.ts (new), approval-request-card.ts}`;
  - `web/src/app/rail/{rail-view,status-rail}.ts`;
  - `web/e2e/demo-path/0{4,5}-*.spec.ts`;
  - `web/src/app/live/payloads.ts`, regenerated only (the runner's footprint note; it sits in Epic 16's folder and is never hand-edited).
- **Shared by entry:**
  - `Test/Core/ProductionItems.cls` (the NoticesIn row);
  - `Test/Data/Tables.cls` (SimMessage, Lane B's own table);
  - `Test/Live/Payloads.cls` (the Phone row, Lane B's);
  - `web/src/app/api/{api-client,api-types}.ts` (6.2's `answerApproval`).
- **Shared by region:** `Data/SimMessage.cls` (Lane B's class); `ci/units.sh` (Lane B's `live:answers` token and its `BROWSER_UNITS` name).
- **Contended, new file:** `docker/tests/test-answers.sh`.
- **Contended, pending the ruling:** `Core/BridgeSink.cls` (Task 6).
- **Extension** (outside the footprint, no contended owner):
  - `Channel/SimPhone/Out.cls`, `Live/Payload/Phone.cls` and `Test/Demo/SimPhoneOut.cls` (Story 4.5's, Lane B);
  - `web/src/app/phone/{phone-view,simulated-phone}.ts`, `phone-request.ts` (new) and `web/src/app/devices/device-panel.ts` (its focus rule);
  - `web/scripts/catalog.mjs`, `msg/catalog.ts` (generated), and the `web/scripts/*.test.mjs` of Task 19, `phone-request-sources.test.mjs` (new) among them;
  - `web/e2e/support/{iris,devices}.ts`, `web/e2e/support/approvals.ts` (new) and `web/e2e/answers/answers.spec.ts` (new);
  - `web/playwright.config.ts` and `web/package.json`.
- **Not edited:**
  - `docker/tests/test-demo-path.sh`: its header's "no seeded event" was already stale with 04's check fixture, and the file is contended.
  - `README.md`: Epic 10's.
- **The runner may append** the unit's measured times to Rule 21's CI section (decide).

**Extend, don't copy (Rule 2):**
- **`answer-press.ts`** is the card's press logic moved, not copied: the card and the phone use one class. The phone's view reuses `approvalView`/`latePressText` through a message-form context.
- **`renderMessageText`** extends the generator beside `renderPageText`. `messageTime` exists.
- **NoticesIn's join copies CommandsIn.Join** (about 8 lines). Join is a private instance method on a Command, in `Core/CommandsIn.cls`, which Epic 8 owns by entry, and the shared home, `Core/Trace.cls`, is Epic 10's contended path.
- **The edit in place reuses `Operation.Keep` and `Announce`.**
- **The rail jump reuses `Layout.focusRegion`.** The button follows decision-row's.
- **`support/approvals.ts`** copies `floor/approval.spec.ts`'s private `incidentOf`/`raise` (about 20 lines). The floor spec is full and stays unchanged, and the new module is the shared home for the new unit and the demo path.
- **`test-answers.sh`** follows `test-floor.sh`'s skeleton on `lib-live.sh`'s helpers, as each browser unit does.

**Integration ACs (Rules 1 and 2):**
- `Notify`, `WebChatOut` and `SimPhoneOut` (consumers of `NoticesIn`) deliver a fixture notification on the session's channels (AC9, NoticesInProduction).
- The phone's `app-phone-request` (consumer of `SimPhoneOut`'s `phone` events and of the answer endpoint) answers in a real browser, and the card shows it (X2).
- `SimPhoneOut` (consumer of `Delivery.FindByApproval`) edits the message, which the phone shows (X3).

**Consumes:**
- Story 6.2's endpoint, `AnswersIn`/`AnswerOps`, request card, busy rule and `answered.*` page catalog;
- Story 6.1's incident card and `WebChatOut.INCIDENTKINDS`;
- Story 4.5's simulated phone, `SimPhoneOut` and New messages hold;
- Story 2.7's `Delivery.FindByApproval`;
- Story 2.15's `Layout.focusRegion`;
- Story 2.12's focus rule and Announcer;
- Story 0.9's `Catalog.Render` and `Data.Time.ForMessage` (`messageTime`);
- Epic 0's `Approval.Answer`.

**Consumed-by:**
- 6.4: result notifications and bands; Dismiss after a rejected or expired status on the card.
- 31.2: `NoticesIn.Send` for BridgeSink's tool-call `approval`, `answered` and `result` notifications.
- 16.9: `NoticesIn.Send` for the daily-cap message, and Approve and Reject on the phone at the caps.
- 10.3 and 12.x: Telegram's edit in place, mirroring the phone's.
- Epic 11: turns 04 and 05 on end to end, and replaces the fixture `answered` with IncidentManager's.

**Ledger inbox:** DW-128 is addressed by Tasks 6 and 10 and AC10 (the ruling allowed the edit).

**Known items, not re-filed:**
- DW-292: after a reload, answered requests and the phone's dry-run styling rely on pending-only snapshot data.
- DW-294.
- DW-299.

## Verification

`<B>` means `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=6 stage=implement'`.
- **Tags:** fresh `e6s3i`, warm `e6s3iw`. Run `<B> OCUTALON_RUN_TAG=e6s3iw ci/warm.sh up` once, and `ci/warm.sh down` at the end, also after a failure.
- **Calls:** one command per foreground call, with `timeout: 600000`. One `iris_execute_tests` per message, with `server` `ocutalon-slot-b` and namespace `OCUTALON` on every IRIS MCP call.
- **Slot B** is for loading, compiling and exporting storage only.

**Browser cases** (`web/e2e/answers/answers.spec.ts`; user ANSWERS; requests seeded with RequiredRole OcuTalonUser and the fixture dry run; the incident payload, the `approval` event and the notice sent through `support/approvals.ts` and `sendNotification`):
- **X1:** the phone notice. It checks:
  - the blocks, with the inset's `before`/`after` in `mono-sm` with `tokenColor` danger-ink and success-ink;
  - "Details and trace: on your OcuTalon page.";
  - Approve left and Reject right, equal widths of half the row less the gap, 40 px tall, with their names;
  - no web notice card;
  - an `incident.laterRequest` adds a second message with its own buttons;
  - an `incident.fallback` with no ApprovalRef has none.
- **X2:** phone Approve.
  - Both buttons busy, then "Approved from the simulated phone at HH:MM." with focus on it.
  - **The 2 s bound:** the card's "Approved from the simulated phone at HH:MM" with `{timeout: 2000}` from the reply, logged.
  - The rail row gone (`ONE_UPDATE_MS`).
  - Through iris: the row has channel `phone` and by ANSWERS, with one AnswersIn→AnswerOps header.
  - No card announcement of it.
- **X3:** card Approve, then the stand-in `answered` sent at once.
  - **The 5 s bound:** the phone's line "Approved from the web chat at HH:MM." replaces its buttons within 5000 ms of the reply, logged.
  - The same message ref, no new message, `scrollTop` unchanged.
  - Through `phoneMessage`: `answer` set.
  - Before the send, the phone still has its buttons.
- **X4:** `answerQuietly(web)`, then phone Approve: the 409 notice "Already answered: approved from the web chat at HH:MM." is announced once, the answer line shows, and the row is unchanged.
- **X5:** phone busy and failures.
  - Held by `page.route`: one POST with `channel":"phone"` however often pressed, `aria-busy` and `aria-disabled` and no `disabled`; after 10 s restored, the busy notice shown and announced; on release the line shows.
  - Then 404, 403 and 500 fulfilled: their notices.
- **X6:** a rail row press.
  - Focus on `[data-part="approval"][data-key=A]`, `toBeInViewport`.
  - At 1100×720 (drawer band), opened from Status: the same, with the drawer still open.
  - A tool_call request's row has no button.
- **X7:** a pending request message, then a tell-now arrives: `scrollTop` unchanged, New messages visible, Approve's `boundingBox` unchanged.
- **X8:** `answerQuietly(phone)` plus `sinkEvent('approval.answered')`, with focus in the composer: the card's status is announced exactly once.

**Commands:**

`(loop)`:
- `npm --prefix web test`: expected, every node test passes.
- `npm --prefix web run lint`: expected, exit 0.
- `node web/scripts/catalog.mjs --check` and `node web/scripts/payloads.mjs --check`: expected, exit 0, after `npm --prefix web run catalog` and `npm --prefix web run payloads`.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s3iw ci/iris.sh class OcuTalon.Test.Demo.SimPhoneOut`: expected, `CLASS ... passed`.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s3iw ci/iris.sh class OcuTalon.Test.Core.NoticesIn`: expected, passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s3iw ci/iris.sh class OcuTalon.Test.Core.NoticesInProduction`: expected, passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s3iw ci/iris.sh class OcuTalon.Test.Core.BridgeSink`: expected, passed (with `TestTurnStepOfARetry` if ruled yes).
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s3iw ci/iris.sh class OcuTalon.Test.Data.Tables`: expected, passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s3iw ci/iris.sh class OcuTalon.Test.Live.Payloads`: expected, passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s3iw ci/iris.sh class OcuTalon.Test.Install.Production`: expected, passed (the item oracle).
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh build`: expected, the image and the bundle build. Run it before a browser run that should see changed web code.
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh live answers`: expected, PASS with X1-X8; record the call's time and the logged X2 and X3 ms.

`(once)`:
- `bash ci/checks.sh`: expected, exit 0 (storage, ci-config with the new unit, ci-changes, ASCII).
- `bash docker/tests/test-web-build.sh`: expected, passes.
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh shard lane-b`: expected, every class passed.
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh shard lane-a`: expected, every class passed.
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh live demo-path`: expected, PASS with 04's and 05's fixture tests run and the rest skipped for 11.1.
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh live floor`: expected, PASS with no case added. The rail button and the phone buttons touch K5, U1-U4, W1-W4 and D4. Record the time against 540 s.
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh live sign-in`: expected, PASS with an unchanged count (rail R2, phone P1-P4, N11).
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh live demo-switch`: expected, PASS (the phone's tell-now and reminder).
- `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh live production`: expected, PASS (NoticesIn no stub).
- `<B> OCUTALON_RUN_TAG=e6s3iw ci/warm.sh down` and `<B> OCUTALON_RUN_TAG=e6s3i ci/iris.sh teardown`: expected, only this stage's projects are removed.

**Shared surfaces:**
- **The `phone` payload's shape** (`answer`): `payloads.ts`, `Test.Live.Payloads`, and the phone fixtures in `floor/devices.spec.ts` and `phone/phone.spec.ts`, which carry no `answer`.
- **The SimMessage contract:** `Test.Data.Tables` and the storage block.
- **SimPhoneOut's kinds:**
  - `Test.Demo.SimPhoneOut` `TestOtherKindsRecordOnly`.
  - Floor I5: its `incident.fallback` and `incident.laterRequest` with `{}` slots now log a render error on the phone and leave no message; it still asserts no notice card, and cleans with `dropPhone`.
  - Floor D4's fixture request message now draws buttons.
- **NoticesIn's stub flag:** `Test.Core.ProductionItems` and `Test.Install.Production`.
- **The rail's approval row:** a button for requests with an incident. It affects floor K5, U1-U4 and W1-W4 through `seedFullPage`'s request. Rail R2's requests have none, so R2 is unchanged.
- **The card's speech:** the answered-elsewhere announcement, against `recordAnnouncements` counts in floor A2-A5 and A8. The speakers list in `announce-focus-sources`.
- **The device panel's focus rule:** pinned at `announce-focus-sources` L147. The floor D-cases' focus moves inside the phone.
- **The card's press source pins:** `approval-sources.test`, moved to `answer-press.ts`.
- **`answerApproval`'s signature.**
- **The generated catalog:** `MESSAGE_TEXTS` and `renderMessageText`.
- **The CI recipe:** the `browser` group, `BROWSER_UNITS`, the Playwright projects (chromium ignores `answers/`), `test-ci-config.sh`, `test-ci-changes.sh` and `playwright-projects.test`.
- **The demo-path verdicts:** 04 and 05 are partly skipped.
- **The fixture sessions' phones:** every case cleans with `dropPhone`.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Planned mutations (Rule 19).** Apply each, observe red, revert, confirm that `git status --short` and `git diff --stat` are unchanged, and record it as `mutation: ... -> ...`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | `SimPhoneOut` stores ApprovalRef for every kind | `Test.Demo.SimPhoneOut` (`TestOnlyRequestKindsCarryARequest`) |
| 1 | the inset's before/after tokens swapped | `phone-request-sources.test`; X1 |
| 2 | `answer-press` posts channel `web` for the phone | X2 (row channel), `phone-request-sources.test` |
| 3 | the edit adds a new message instead of editing | `Test.Demo.SimPhoneOut` (`TestAnsweredEditsInPlace`); X3 |
| 3 | `FindByApproval` result not checked against the session | `TestAnsweredNeverEditsAnotherSessionsMessage` |
| 4 | `POLL_DELAY_MS` raised to 3000 (Epic 16's `live-state.ts`, temporary, restored byte-identical) | X2 (2 s) |
| 4 | SimPhoneOut publishes no event after the edit | X3 (5 s) |
| 5 | the card's announcement ignores the phone's focused answer line | X2 (an announcement) |
| 5 | the card announces nothing on a store transition | X8 |
| 6 | 05's phone press removed | `live demo-path` red |
| 7 | the rail press focuses the chat list always | X6 |
| 8 | `pendingApproval` ignores request messages | X7 (feed moves) |
| 9 | NoticesIn's join skips the context's ThreadSessionId | `Test.Core.NoticesIn`, `NoticesInProduction` |
| 10 | Step's retry clause removed | `Test.Core.BridgeSink` (`TestTurnStepOfARetry`) |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- Planned from `epic-6-context.md` (reused, valid), 6.2's spec (continuity) and the code at `3584541`. DW-128 is addressed as a contended edit pending the orchestrator's ruling, with a stated fallback; no other contended edit is needed. Veto-window choices V1 (SimMessage properties) and V2 (the rail row's accessible name) are for the runner to file.
