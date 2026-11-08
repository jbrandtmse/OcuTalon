---
title: 'Story 41.5: "This was noise", and your approval answers, become precedents'
type: 'feature'
created: '2026-11-08'
status: 'done'
baseline_revision: 'd597ec58f445ec27d58dda396890e5d1f8fc5b6a'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-41-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** Story 41.2 built the precedent table, `PrecedentOps`, the noise route and `RecordPrecedent`, but nothing a person does reaches them. No page control calls the noise route, and `AnswerOps` never sends `RecordPrecedent`, so no precedent is ever written. Four ledger items are open: DW-923 (the `too_old` refusal has no card text), DW-932 (the route's answers are not run over real HTTP), DW-933 (`Record` trusts the message's `Action`) and DW-934 (a precedent written just after sign-out survives `SessionOps.End`).

**Approach:**
- A "This was noise" ghost button on the person's own tell-now and act notices, in the web chat and on the simulated phone. It posts the noise route, and then the button is replaced by the UX status line. A refusal shows the server's message.
- The phone payload gains `decisionRef` for tell-now messages.
- `AnswerOps` sends one asynchronous `RecordPrecedent` after `Approval.Answer` returns `done`.
- `PrecedentOps.Record` checks the request's stored answer (DW-933), and `Mark` and `Record` refuse a session that sign-out has ended (DW-934).
- A Playwright spec over the real stack, plus `OcuTalon.Test.Core` tests.

## Boundaries & Constraints

**Always:**
- **Where the control shows (FR-72).**
  - **Web chat:** a notice of kind `tellnow` whose served `decision.ref` is non-empty. Act decisions also arrive as kind `tellnow` (`Core/Rule/Notice.cls`).
  - **Phone:** a phone message with a non-empty `decisionRef` and no `approvalRef`.
  - **Never** on reminder, allowance, digest, approval, result or incident notices, on a request card, on a fallback tell-now that has no decision, or on any turn or reply.
- **The press.** `POST /ocutalon/api/v1/decisions/:ref/noise`, sent through the one `ApiClient`.
  - Body `{"channel":"web"}` from the chat, `{"channel":"phone"}` from the phone.
  - A 200 replaces the button with "Marked as noise at {time}. Similar items will take this into account.". `{time}` is `markedAt` in page time, `pageTimeBeside(markedAt, instanceZone)`, the same form as the reminder caption.
  - A repeat (`already_marked`) shows the first mark's time.
- **Busy and failure (EXPERIENCE "Busy and failure").** The button is an `app-server-button` with variant `ghost`: busy rule, 10-second `BUSY_NOTICE`, and a repeat press is ignored.
  - An error reply shows its `error.message` in an inline warning notice beside the button, announced once, and the button stays. This is `IncidentDismiss`'s rule. A reply with no answer (status 0) shows `BUSY_NOTICE`.
  - So `too_old` shows the server's 409 message, the approved text "This notice is too old to mark as noise. Nothing was changed." (`Web.Api.MESSAGETOOOLD`, DW-923).
- **Label and keyboard (NFR-25).** The accessible name is the visible label "This was noise". The control is a native button, so Tab reaches it and Enter or Space presses it.
  - When the status line replaces a focused button, focus moves to the control's container, which holds the status line. This uses the page's one focus rule (`shared/focus-rule.ts` `keepFocus`); the control makes no `.focus(` call of its own.
  - The status line is plain text, not a live region (`announce-focus-sources`).
- **The status line** is caption text in `--ink-muted`, per DESIGN.md's "This was noise" control.
- **Approval answers (FR-72, AD-21).** When `Approval.Answer` returns `done`, and only then, `AnswerOps` sends `PrecedentOps` exactly one `RecordPrecedent` through a private seam, asynchronously and with no response. It carries `ApprovalRef` (the request's own Ref), `Action`, `Channel` and `SessionRef`.
  - `already_answered`, `expired`, `not_found`, `not_allowed` and a missing session send nothing.
  - A failed send is one warning, and the `AnswerResult` is unchanged.
  - `PrecedentOps` alone decides the kind: a `setting` request writes no row (existing).
- **DW-933.** `Record` writes only when the request's stored `AnsweredAction` equals the message's `Action` and its `State` is one of `approved`, `rejected`, `executing`, `done` or `failed`. Otherwise the answer is `not_recorded` (Ok 0) and nothing is written.
- **DW-934.** `Mark` and `Record` refuse a session that sign-out has ended: on the online demo (`Data.Setting.Get("onlineDemo") = 1`), a session whose row has an empty `ResumeHash`. This is `BridgeSink.DailyCap`'s rule. The refusals are `not_found` and `not_recorded`, with nothing written.
  - The online-demo read is a private seam (`OnlineDemo()`), so a probe can drive it.
  - Off the online demo nothing changes: a local session never ends.
- **The phone payload.** `Live.Payload.Phone` gains `DecisionRef` (`decisionRef`, MAXLEN 22). `FromRow` sets it from the session's own phone `Delivery` row of kind `tellnow` whose `ChannelMessageId` is the message's Ref. The read goes through a new `Data.Ownership` read, and runs only for a message with no `ApprovalRef`.
  - An empty value is left out of the JSON, as an empty `approvalRef` is.
  - The generated `web/src/app/live/payloads.ts` is regenerated.
- **Source rules.** Fixed page strings live in a new `NOISE_TEXTS` constant. ASCII source with non-ASCII as escapes. Comments state the contract only (Rule 14).
- **Hermeticity.** Every test added or changed passes on a fresh environment, in either order (Rule 19).

**Never:**
- Edit a Lane A class or test (`Agent/**`, `Eval/**`, `Test/Agent/**`, `Test/Eval/**`), `ci/mock/**`, `ci/units.sh`, `release/**`, `eval/run.sh`, IPM artifact or check scripts, the spine, EXPERIENCE.md or DESIGN.md.
- Change any demo-path spec (`web/e2e/demo-path/**`, `web/e2e-online/demo-path/**`, `web/e2e-rehearsal/**`; REL-2).
- Edit `web/src/app/chat/chat-view.ts`, `Msg/Catalog/Core.cls`, `Test/Msg/Catalog.cls`, `web/src/app/api/api-types.ts` or `web/e2e/support/*` (contended). Reading or importing them is fine.
- Any contended-file edit beyond the ones listed under Clarification 1.
- Add a second HTTP client: `inject(HttpClient)` stays in `api-client.ts` only (`api-client-sources.test.mjs`).
- Change the storage of any table. `SimMessage` gains no column.
- Change `SessionOps.End`, including its `Has()` gate (Decided in-stage, DW-934).
- Add an aria-label, error text or state text that is not listed under PUBLIC TEXT.
- Record a precedent from anything but a person's noise press or a `done` answer.

## I/O & Edge-Case Matrix

`S` is the signed-in session; `D` a decide Decision of `S` (outcome tellnow or act) whose Item is in its trace session; `D0` a decide Decision with no kept Item.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Mark, web | tell-now card of D; press (mouse, or keyboard Enter) | POST body `{"channel":"web"}`; 200 `{"result":"done","markedAt"}`; the button gives way to "Marked as noise at {time}. Similar items will take this into account."; one row: Answer noise, AnsweredChannel web, SourceRef D | none expected |
| Repeat via phone | D already marked on web; press on D's phone message | body `{"channel":"phone"}`; 200 with the FIRST markedAt (already_marked); the phone shows that time; still one row, AnsweredChannel web | none expected |
| Mark, phone first | a fresh D; press on the phone | one row with AnsweredChannel phone | none expected |
| Body mapping | POST with `{"channel":"Phone"}`, `{"channel":"phone","x":1}`, `{}` or no body | channel web | none expected |
| Too old | tell-now card of D0; press | 409 `{"error":{"code":"too_old","message":"This notice is too old to mark as noise. Nothing was changed."}}`; that text beside the button; the button stays; no row | inline warning, announced once |
| Other error | 404 / 500 / 501 | the body's `error.message` beside the button; status 0 gives BUSY_NOTICE | as IncidentDismiss |
| Not shown | reminder, allowance, digest, approval, result notice; a tellnow with no `decision.ref`; a phone message with `approvalRef`, or with no `decisionRef` | no control | none expected |
| Approve / reject done | Answer → done for a fix or a tool_call | one RecordPrecedent; one row approved / rejected, keyed as 41.2 | a failed send: one warning, result unchanged |
| Answer not done | already_answered, expired, not_found, not_allowed, no session row | no RecordPrecedent | none expected |
| Setting request | done for a setting | RecordPrecedent sent; not_recorded; no row | none expected |
| Mismatched message (DW-933) | Action reject for a request answered approve; or a pending, expired or cancelled request | not_recorded; no row | none expected |
| Ended session (DW-934) | online demo, S's ResumeHash cleared by End; then MarkNoise or RecordPrecedent arrives | not_found / not_recorded; no row | none expected |
| Local session | onlineDemo not 1, ResumeHash empty | marked / recorded as before | none expected |

</intent-contract>

## Code Map

Server paths are under `src/ocutalon/cls/OcuTalon/`; web paths are under `web/`.

**Files to change (server)**
- `Core/AnswerOps.cls`:
  - `Carry` (34-60): after `Set response.Result = result` (53), when `result = "done"`, build the `RecordPrecedent` and call a new private seam `SendPrecedent(message) As %Status`. That seam is `..SendRequestAsync(..#PRECEDENTITEM, message)`, the shape of `SessionOps.SendNotice` (`SessionOps.cls:583-585`). A failed status or a throw is `$$$LOGWARNING` and nothing else.
  - Add `Parameter PRECEDENTITEM = "PrecedentOps";` (sibling: `SessionOps.cls:82`).
  - Update the class comment (1-10).
- `Core/PrecedentOps.cls`:
  - `Record` (153-185): after the `approval` read (160-162), refuse `not_recorded` unless `approval.AnsweredAction = request.Action` and `$ListFind($ListBuild("approved","rejected","executing","done","failed"), approval.State)` (DW-933). Before the approval read, refuse `not_recorded` when `..Ended(sessionRef)` (DW-934).
  - `Mark` (102-134): refuse `not_found` when `..Ended(sessionRef)`, right after the session check at 106.
  - New private methods:
    - `Ended(sessionRef) As %Boolean`: `..OnlineDemo()` and the session row's `ResumeHash = ""`. A missing row counts as not ended here, because `Record` already refuses an unknown session (159).
    - `OnlineDemo() As %Boolean` [Private], a seam: `##class(OcuTalon.Data.Setting).Get("onlineDemo") = 1`, as `Web/Api.cls:335`.
  - Update the class comment (3-22).
- `Data/Ownership.cls`:
  - Add `PhoneDecision(messageRef, sessionRef, Output sc) As %String` after `DeliveryByRef` (483-497), its sibling. It returns the `DecisionRef` of the session's newest Delivery row with channel `phone`, kind `tellnow` and `ChannelMessageId` exactly `messageRef`, else "".
  - Add a `phoneDecision` kind to `Statement`, before its final `Quit ""` (about 1093): `SELECT ID FROM OcuTalon_Data.Delivery WHERE ChannelMessageId = ? AND Channel = 'phone' AND Kind = 'tellnow' AND OwnerRef = ? ORDER BY ID DESC`, binds `"ao"`. It narrows by `OwnerRefChannelIndex`, and the values are compared exactly after the read, as `DeliveryByRef` does.
  - Add one line to the class comment.
  - Epic 17 changes this file at about 40, 413 and 910. These insertions touch none of them, so they are a plain union.
- `Live/Payload/Phone.cls`: add `Property DecisionRef As %String(%JSONFIELDNAME = "decisionRef", MAXLEN = 22);` after `ApprovalRef` (15). In `FromRow` (25-35), when `row.ApprovalRef = ""`, set it from `Ownership.PhoneDecision(row.Ref, row.SessionRef, .sc)`. A failed read leaves it empty. The sibling is `Live/Payload/Notification.cls:65-72`, which reads the decision through Ownership.

**Files to change (DW-934 Option B, ruled in the Spec Change Log; it supersedes the intent block's "Change `SessionOps.End`" Never line and the Decided in-stage note for this one change)**
- `Core/SessionOps.cls` `EndPrecedents` (427-444): send the `DropPrecedents` call always, with no `Precedent.Has()` gate, so the drop queues behind every write already queued. Update the method and class comments (the class comment at 21 says "sent only when the session has rows").
- `Test/Core/SessionOpsProbe.cls`: override `DropPrecedents(request)` so it answers 0 and sends nothing when `Data.Precedent.Has(request.SessionRef)` is 0, and otherwise behaves as the real method. This keeps `Test.Core.SessionOps`, `SessionOpsDocuments` and any other test that runs `End` without a production free of sends.
- `Test/Core/SessionOpsPrecedents.cls` `TestNoRowsSendsNothing` (72-83) and its header comment: update to the new behaviour. Read `Test/Core/SessionOpsPrecedentsProbe.cls` first: the test records calls through that probe, so a session with no rows now makes one drop call, and the assertions and the header say so.

**Files to change (web)**
- `src/app/api/api-client.ts`: one method appended at the end of the class (after `runHeartbeat`, 206-208, before the closing `}` at 209):
  - `markNoise(ref: string, channel: import('./memory-types').NoiseChannel): Observable<import('./memory-types').NoiseMarked>` posts `` `${BASE}/decisions/${encodeURIComponent(ref)}/noise` `` with `{ channel }`.
  - The type queries are inline, so the file gets no new import line (Clarification 1).
  - A refusal fails as an `HttpErrorResponse` whose `error` is the body.
- `src/app/chat/notice-card.ts` (Clarification 1):
  - an import line after 6;
  - `imports: [DecisionStrip, Icon, NoiseControl]` (28);
  - one template line after 49, inside `.body`: `<app-noise-control [decisionRef]="noiseRef()" channel="web" [instanceZone]="instanceZone()" />`;
  - `noiseRef` as a `computed` appended at the end of the class (after 140): `noticeNoiseRef(this.notice())`;
  - one comment line after 24.
- `src/app/phone/simulated-phone.ts`:
  - in the `@else` branch (62-65), after `<span class="time">`: `@if (phoneNoiseRef(one); as ref) { <app-noise-control [decisionRef]="ref" channel="phone" [instanceZone]="instanceZone()" /> }`;
  - add `NoiseControl` to `imports` (36), and expose `phoneNoiseRef`;
  - update the class comment.
- `src/app/incidents/incident-dismiss.ts:22`: `export function messageOf`, so the control reuses it.
- `src/app/live/payloads.ts`: regenerated with `npm --prefix web run payloads`. Never edit it by hand.
- `playwright.config.ts:61`: `const SIGN_IN_3_FILES = ['heartbeat-card.spec.ts', 'memory-noise.spec.ts'];`, plus its comment (58-60) and the header list (line 13 names sign-in-3's files).
- `scripts/playwright-projects.test.mjs:86`: the same list, and the test name at 120 names the new file.
- `scripts/phone-request-sources.test.mjs:58`: the `@else` regex now allows the `@if (phoneNoiseRef(one); as ref) { <app-noise-control ... /> }` block after the time.
- `scripts/ux-strings.test.mjs` and `scripts/announce-focus-sources.test.mjs`: the appends under Clarification 1.

**Files to change (tests)**
- `Test/Core/PrecedentOps.cls`:
  - Update `TestApprovalAnswers`' fixtures (about 261-282) so each answered request carries `AnsweredAction` (`approve`/`reject`). `Fixture.Approval` sets State only.
  - Add `TestAnswerMustMatch` (DW-933) and `TestEndedSession` (DW-934).
- `Test/Core/PrecedentOpsProbe.cls`: add the `OnlineDemo` property ("" means the real method) and override `OnlineDemo()`.
- `Test/Core/AnswerOpsProbe.cls`: override `SendPrecedent`. It records each message under `^OcuTalonTest("AnswerOpsPrecedent", run)` and answers as a `FailSend` flag says. This keeps `Test/Core/AnswersIn.cls`, which uses the probe with the double's `done`, free of sends outside a production.
- `Test/Live/Payloads.cls:1189-1199` (XData Contracts): add the `DecisionRef` line.
- `Test/Demo/SimPhoneOut.cls`:
  - `TestTellNow` (78): the published payload's `decisionRef` is the notification's `DecisionRef`;
  - add `TestDecisionRefOnlyForTellNow`: reminder, incident and approval messages have none, and another session's tell-now Delivery is never read.
- `Test/Data/OwnershipPrecedents.cls`: add `TestPhoneDecision`. It covers own versus other session, channel web, kind reminder, a Ref differing only in case, `eval`/`instance`, and newest-first.
- `Test/Core/AnswersInProduction.cls` and `AnswersTelegramProduction.cls`: in their after-all cleanup, `Data.Precedent.DropSession` for each fixture session. With the real `AnswerOps`, their `done` answers on fix and tool_call fixtures now write rows (shared surface).

**New files**
- `src/app/chat/noise-view.ts`, framework-free:
  - `NOISE_TEXTS = { label: 'This was noise', marked: 'Marked as noise at {time}. Similar items will take this into account.' }`;
  - `noticeNoiseRef(notice: NoticeView): string`, which is "" unless the kind is `tellnow` and `decision?.ref` is set;
  - `phoneNoiseRef(message: PhonePayload): string`, which is "" when `approvalRef` is set;
  - `markedLine(markedAt, zone)`.
- `src/app/chat/noise-control.ts`, the `app-noise-control` component:
  - inputs `decisionRef` (with "" it renders nothing), `channel` (`web`|`phone`) and `instanceZone`;
  - a container `<div class="noise" [attr.data-noise]="decisionRef()" tabindex="-1">`, holding the ghost `app-server-button` with the label, or the status `<p class="marked">`, plus the inline notice;
  - the press calls `api.markNoise`, and a 200 sets `markedAt`.
  - Focus follows `phone-request.ts`' answer rule:
    - an exported `NOISE_RULE: FocusRule = { item: '[data-noise]', keyOf: (item) => item.getAttribute('data-noise') ?? '' }` (the sibling is `PHONE_ANSWER_RULE`, `phone-request.ts:29`);
    - an `effect(() => { this.markedAt(); untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, NOISE_RULE)); })` (the sibling is `phone-request.ts:247-249`), so it matches `announce-focus-sources.test.mjs:175-176`'s host form.
  - An error reply is handled as in `incident-dismiss.ts:101-117`: `messageOf(error) || BUSY_NOTICE`, announced, with the `shown` guard.
- `src/app/api/memory-types.ts`: `NoiseChannel = 'web' | 'phone'` and `NoiseMarked { result: 'done'; markedAt: string }`. Its siblings are `persona-types.ts` and `heartbeat-types.ts`. Story 41.6 adds its own types here.
- `scripts/noise-view.test.mjs` (node):
  - `NOISE_TEXTS` against fixed strings;
  - `markedLine`;
  - `noticeNoiseRef` for every kind;
  - `phoneNoiseRef`;
  - source pins: `<app-noise-control` appears only in `chat/notice-card.ts` (channel `"web"`) and `phone/simulated-phone.ts` (channel `"phone"`); `markNoise` posts the path and `{ channel }`.
- `e2e/memory-noise.spec.ts`: Playwright (Tasks 9).
- `Test/Core/AnswerPrecedents.cls`, slot-safe, over `AnswerOpsProbe` and `ApprovalDouble`.
- `Test/Core/AnswerPrecedentsProduction.cls`, which extends `Test.Core.InProduction`: throwaway and CI only.

**Consumed as built (read only)**
- 41.2:
  - `Web/Api.cls:1540-1574` `MarkNoise`, `NoiseBodyIsPhone` (1577) and `MESSAGETOOOLD` (158, pinned by `Test/Web/MemoryApi.cls:162`);
  - `PrecedentOps.Mark` and `Record`;
  - `Data.Precedent.KeyFor`, `KeyForRequest`, `Has` and `DropSession`.
- `Core/AnswersIn.cls` sends to `AnswerOps` synchronously (160), with a 30 s TIMEOUT.
- `Core/Rule/Notice.cls:30`: tellnow and act both make a tellnow Notification with `DecisionRef`.
- `Live/Payload/Notification.cls:33-72`: `decision` is served only when the owner sees it.
- `Channel/SimPhone/Out.cls:96-107`: `Save` writes the message and its Delivery row (with DecisionRef) in one transaction (`Operation.Keep`), then `Announce` calls `FromRow`.
- Web: `shared/server-button.ts` (`BUSY_NOTICE`, variant `ghost`), `shared/inline-notice.ts`, `shared/announcer.ts`, `shared/focus-rule.ts`, `chat/page-time.ts`, `incidents/incident-dismiss.ts` (the sibling).
- E2E support (read and import only):
  - `support/fixtures.ts`;
  - `support/api.ts` `post`;
  - `support/iris.ts`: `fixtureUser`, `irisScript`, `chk`, `seedDecision`, `sendItemDecision`, `sendNotification`;
  - `support/devices.ts`: `dropPhone`, `dropMail`;
  - `sign-in/helpers` `signIn`;
  - `support/floor.ts` `loadedAfter`;
  - `support/demo-path.ts` `phoneNotes`, a selector only.

## Tasks & Acceptance

**Execution:**
1. `Core/PrecedentOps.cls`: add `Ended` and the `OnlineDemo` seam, the DW-934 refusals in `Mark` and `Record`, and the DW-933 comparison in `Record`; update the class comment. `Test/Core/PrecedentOpsProbe.cls`: the `OnlineDemo` override.
2. `Core/AnswerOps.cls`: `PRECEDENTITEM`, the `SendPrecedent` seam and the send on `done`; update the class comment. `Test/Core/AnswerOpsProbe.cls`: the `SendPrecedent` override.
2b. DW-934 Option B: `Core/SessionOps.cls`, `Test/Core/SessionOpsProbe.cls`, `Test/Core/SessionOpsPrecedents.cls`, as under the Code Map's Option B heading. Run `Test.Core.SessionOps`, `SessionOpsDocuments`, `SessionOpsPrecedents` and `SessionOpsProduction` (the last in the throwaway) afterwards.
3. `Data/Ownership.cls`: `PhoneDecision` and the `phoneDecision` statement. `Live/Payload/Phone.cls`: `DecisionRef` and the `FromRow` lookup. Then `npm --prefix web run payloads`.
4. Server tests:
   - `Test/Core/PrecedentOps.cls`:
     - the `TestApprovalAnswers` fixtures;
     - `TestAnswerMustMatch`: approve sent for a request answered reject, reject for approve, a pending request, an expired one and a cancelled one are each `not_recorded` with no row; a matching approve on an `executing` and a `done` request is recorded;
     - `TestEndedSession`: probe `OnlineDemo` 1. A session with its ResumeHash set is marked and recorded. After its ResumeHash is cleared, Mark is `not_found` and Record is `not_recorded`, with no new row. With probe `OnlineDemo` 0 and an empty ResumeHash, both write.
   - `Test/Core/AnswerPrecedents.cls`, over `AnswerOpsProbe` and `ApprovalDouble`:
     - `TestDoneSendsOne`: approve and reject each send one message with Ref, Action, Channel and SessionRef as given, and the result is done;
     - `TestNotDoneSendsNone`: already_answered, expired, not_found, not_allowed and an unknown session send nothing;
     - `TestFailedSendKeepsTheAnswer`: `FailSend` "error" and "throw" each give AnswerResult done and one warning.
   - `Test/Core/AnswerPrecedentsProduction.cls` (InProduction). Each answer goes through `Web.Api.AnswerApproval` as `AnswersInProduction` does: a StubRequest body and a CSP session bound to a fixture session. The fixture `fix` request has an incident on `ZZNS/Zz.Production`; there is also a `tool_call` request and a `setting` request, each with the process's `HeldRole`. The test waits for PrecedentOps' row by `SourceRef`, bounded (`Observe`-style polling):
     - `TestApproveRecords`: fix approve gives one row, approved, key `production:ZZNS/Zz.Production`, AnsweredChannel web;
     - `TestRejectRecords`: tool_call reject gives one row, rejected, key `tool:<ToolName>`;
     - `TestRepeatAndSetting`: a second press (409 already_answered) adds no row, and an approved setting request leaves none;
     - cleanup: `Precedent.DropSession` and the fixture rows.
   - `Test/Live/Payloads.cls`, `Test/Demo/SimPhoneOut.cls`, `Test/Data/OwnershipPrecedents.cls`, `Test/Core/AnswersInProduction.cls` and `AnswersTelegramProduction.cls`, as in the Code Map.
5. `web/src/app/api/memory-types.ts` and the `markNoise` method of `api-client.ts`.
6. `web/src/app/chat/noise-view.ts`, `noise-control.ts`, and the `incident-dismiss.ts` export.
7. `web/src/app/chat/notice-card.ts` and `web/src/app/phone/simulated-phone.ts`. **The notice-card edits wait for Clarification 1.**
8. Web checks:
   - `web/scripts/noise-view.test.mjs`;
   - update `phone-request-sources.test.mjs` and `playwright-projects.test.mjs`, and `playwright.config.ts`;
   - the `ux-strings.test.mjs` and `announce-focus-sources.test.mjs` appends (Clarification 1). Then search `web/scripts/` for any other source pin that the new component or the phone branch trips, and update it.
9. `web/e2e/memory-noise.spec.ts`:
   - **Setup.** `test.use({ timezoneId: 'UTC', locale: 'en-GB' })`. Sign in as the notice fixture user (`fixtureUser('NOTICE')`, as `chat/notice.spec.ts`), so the README session and `api.spec`'s counts are untouched.
   - **Emails.** Each tell-now comes from a real email: `post(page.request, '/ocutalon/api/v1/mailbox/incoming', { from, subject: unique, body: 'zz ... [[mock:mail-tell-now]]' })`. It reaches a tell-now decide Decision whose Item is kept: a no-key fallback tellnow, or the mock's tellnow when keys point at it. Both are markable. The spec finds its card by the unique subject, and its phone message under `phoneNotes(page)` by the same text.
   - **Rows.** Each case reads the row through `irisScript`: `Precedent.SourceRefIndexOpen(<decisionRef>)` with `Answer`, `AnsweredChannel` and `OwnerRef`.
   - **Cases:**
     - **NZ1** (web mark, by keyboard): the card has one button named "This was noise". Focus it and press Enter. The request body is `{"channel":"web"}`, and the response is 200 `{result:'done', markedAt}` with `markedAt` an ISO time within the case's window. The card then shows "Marked as noise at HH:MM. Similar items will take this into account." (HH:MM is `markedAt` in UTC). No button is left, focus is inside the card (not the body), and there is one row with answer noise and channel web.
     - **NZ2** (repeat on the phone): the same Decision's phone message has the control. A press posts `{"channel":"phone"}` and gets 200 with NZ1's `markedAt`, and the phone shows that time. There is still one row, channel web.
     - **NZ3** (phone first): a new email, pressed on the phone, gives a row with channel phone.
     - **NZ4** (body mapping and repeat over HTTP): a new email. `post(page.request, noise(ref), {channel: 'Phone'})` answers 200 `{result, markedAt}` and the row's channel is web. A second `post` with `{channel:'phone'}` answers 200 with the same `markedAt`, and there is still one row.
     - **NZ5** (too_old, DW-923): `seedDecision(user, {outcome:'tellnow', summary})` and `sendItemDecision(...)` make a tell-now card with a decision and no kept Item. A press gets 409, whose body `error.code` is `too_old` and whose `error.message` is the fixed string "This notice is too old to mark as noise. Nothing was changed.". The card shows that string, the button is still there, and there is no row.
     - **NZ6** (never elsewhere): a reminder notice and a tell-now without a decision (`sendNotification` with no decisionRef) show no "This was noise" button in the chat or on the phone.
   - **Cleanup.** `afterEach` and `afterAll` drop the fixture session's Precedent rows (`Precedent.DropSession` through `irisScript`), its phone and mail rows since the case began (`dropPhone`, `dropMail`), and the fixture Decisions (`Test.Data.Fixture.Clean` of the refs).

**Acceptance Criteria:**
1. **Web mark (FR-72).** Given the person's own tell-now card with a decision in the web chat, when they press "This was noise", then the page posts the noise route with `{"channel":"web"}`, and the card shows "Marked as noise at {time}. Similar items will take this into account." in place of the button. Proof: NZ1; `noise-view.test.mjs`.
2. **Phone and repeat.** Given the same notice on the simulated phone, when the person presses the control there, then it posts `{"channel":"phone"}`. A repeat shows the first mark's time and writes no second row; a phone-first mark keeps channel phone. Proof: NZ2, NZ3.
3. **Where it shows.** Given any notice or message, when the chat and the phone render, then the control shows only on tell-now (and act) notices with a decision, never on reminders, allowance, digest, approval, result or incident notices, request cards, decisionless tell-nows or replies. Proof: `noise-view.test.mjs`, NZ6.
4. **Label and keyboard (NFR-25).** Given the control, when it is reached with Tab and pressed with Enter, then its accessible name is "This was noise" and the mark happens. After the replacement, focus is in the control's container, not on the body. Proof: NZ1.
5. **Refusals (DW-923).** Given a notice whose Item is no longer kept, when the person presses, then the card shows "This notice is too old to mark as noise. Nothing was changed." and nothing is written. Any other error reply shows its message. Proof: NZ5; `Test.Web.MemoryApi:TestTooOldText` stays green.
6. **Real HTTP (DW-932).** Given the running stack, when the route is called over HTTP, then 200 carries `markedAt` for `marked` and `already_marked` (the same time), the phone body maps to phone and any other body to web, and `too_old` is 409. Proof: NZ1, NZ2, NZ4, NZ5.
7. **Approval answers (FR-72, AD-21; Integration).** Given the real production, when a person approves a fix or rejects a tool_call through the answer route, then `AnswerOps` sends one `RecordPrecedent`, and `PrecedentOps` writes one row approved or rejected with the 41.2 key. A repeat, and a setting request, write none. Proof: `AnswerPrecedentsProduction`, `AnswerPrecedents`.
8. **Answer must match (DW-933).** Given a `RecordPrecedent` whose Action differs from the request's stored answer, or a request that is not answered, when `PrecedentOps` handles it, then it answers `not_recorded` and writes nothing. Proof: `TestAnswerMustMatch`.
9. **Ended session (DW-934).** Given an online-demo session that sign-out has ended (ResumeHash cleared), when a `MarkNoise` or `RecordPrecedent` for it arrives, then nothing is written. A local session is unaffected. Proof: `TestEndedSession`.
10. **No regression (REL-2).** Given the change, when the suites run, then the demo-path specs pass unchanged, and `chat/notice.spec.ts`, `floor/focus.spec.ts`, `floor/announcements.spec.ts`, `Test.Web.Api`, `Test.Core.AnswersIn`, `Test.Core.PrecedentOps`, `Test.Core.SessionOpsPrecedents` and `Test.Core.PrecedentOpsProduction` pass.

## Spec Change Log

- 2026-11-08 (orchestrator ruling, decide; Contest Planner informed): **Clarification 1 cleared — all three contended edits ALLOWED as plain unions**, done by whichever epic merges second (as 41.2's `Ownership.cls`): (e) `web/src/app/chat/notice-card.ts`, exactly the five listed edits; (c) `web/scripts/ux-strings.test.mjs`, the two `SOURCES.ux` appends; (d) `web/scripts/announce-focus-sources.test.mjs`, the sorted insertion. (a) the `api-client.ts` method and (b) the `IMPORTED` append are within the standing precedent and are reported. No other line of these files changes. Task 7 proceeds.

- 2026-11-08 (spec gate, lead): **DW-934 ruled (U3, veto item U-311): Option A AND Option B.** `Mark` and `Record` refuse a session whose sign-out has ended (online demo: `ResumeHash` cleared), and `EndPrecedents` always sends the drop so it queues behind every write already queued; `Test.Core.SessionOpsProbe` overrides `DropPrecedents` (answer 0 when `Has()` is 0) and `SessionOpsPrecedents:TestNoRowsSendsNothing` is updated accordingly (Lane B tests, this story's lane). The residual (a write in flight during End's last step) is accepted. Clarification 2 is cleared. Clarification 1 (contended-file edits) waits for the orchestrator.
- 2026-11-08 (spec gate, lead): the absolute working-directory path in `## Verification` is replaced by "the worktree root" (no local path in a tracked file).

## Review Triage Log

### 2026-11-08 — Review pass
- verdicts: 24 findings — high 0, medium 3, low 19, false 2, maybe-false 0
- findings:
  - Blind Hunter
    - `[low]` `[reject]` `Phone.FromRow` runs one SQL read per phone message — the spec's Design Notes decide it (at most PHONEMAX 100 per /state, narrowed by (OwnerRef, Channel); cost unmeasured, labelled inference); a batch read or a new index changes storage or the spec's approach; reopen_if a /state snapshot with 100 phone messages is measured over 1 s.
    - `[low]` `[reject]` a failed `PhoneDecision` read leaves the control out — the Code Map specifies "A failed read leaves it empty"; a later event shows it again; nothing false is claimed.
    - `[low]` `[reject]` `Ended()` race window and a failed End leaving the hash set — the residual is accepted in the Spec Change Log ruling (U-311, Options A and B); the always-send drop is what narrows it.
    - `[low]` `[reject]` probes skip the empty drop in `SessionOpsProbe` and `SessionOpsDropProbe`, so tests see less of the always-send path — ruled in the Spec Change Log; the real path runs in `SessionOpsPrecedents` and `SessionOpsProduction` (green in the throwaway).
    - `[low]` `[reject]` `Record` answers `not_recorded` (not `already_recorded`) for a repeat with a different Action — Approval.Answer sends nothing for a repeat, nothing is written either way, and the mismatch is pinned by `TestAnswerMustMatch`.
    - `[low]` `[reject]` fixed `Hang 1` in the answer production tests' precedent cleanup, copied into two classes — the stray row would belong to a unique fixture session that no other test counts; reopen_if a Precedent-count test goes red after these classes.
    - `[low]` `[patch]` `TestRepeatAndSetting` reads `row.Answer` unguarded (and waits on timers) — the read is now guarded with `$IsObject`; the waits stay, since the repeat press sends nothing and the setting case is an absence check.
    - `[low]` `[reject]` the web tests pin source text and have no component test — the project has no component test host; its sources tests are the convention (NZ1 to NZ6 cover behaviour).
    - `[low]` `[patch]` `noise-control.ts` imports `messageOf` from `incidents/` and binds an unused `as at` alias — the export is the spec's design (extend, do not copy); the alias is removed.
  - Edge Case Hunter
    - `[medium]` `[reject]` sign-out fails while PrecedentOps is unreachable, even with no rows — the Spec Change Log ruling (U-311) makes the drop unconditional; a down production fails End's other steps too; by-design.
    - `[false]` `[reject]` `Ended()` reads a live online-demo session with no ResumeHash as signed out — an online-demo session is made by `Session.NewVisitor`, which always sets a hash, and `BridgeSink.DailyCap` uses the same rule.
    - `[low]` `[reject]` a 200 with no `markedAt` shows an empty time — the route always answers `markedAt` with a 200 (`Test.Web.MemoryApi:TestNoise`, NZ1).
    - `[low]` `[reject]` a reused `NoiseControl` whose `decisionRef` changes keeps the old mark — no host rebinds one instance to another Ref (the card and the phone message are keyed by their own Ref).
    - `[low]` `[reject]` the cleanup `Hang 1` — same as the Blind Hunter row on it.
    - `[low]` `[reject]` the per-message SQL read — same as the Blind Hunter row on it.
    - `[low]` `[reject]` the `Record` repeat with a different Action — same as the Blind Hunter row on it.
    - `[false]` `[reject]` `SendRequestAsync(..., 0)` passes a description — the third parameter is `pResponseRequired`; `SessionOps.SendNotice` (583) and `SettingsOps` (519) send in the same form.
  - Verification Gap
    - `[medium]` `[patch]` the real `OnlineDemo` seam is never run (DemoFlag is always set) — `TestEndedSession` gained a block that sets the real `onlineDemo` Setting with `DemoFlag` empty and restores it; mutation `OnlineDemo` returns 0 went red.
    - `[medium]` `[patch]` the `State` half of DW-933 is not pinned — the pending, expired and cancelled fixtures of `TestAnswerMustMatch` now carry a matching `AnsweredAction`; mutation (State clause removed) went red.
    - `[low]` `[reject]` AC 4, 5 and 6 mutations were observed red on source pins only; the behavioural proofs (NZ1, NZ4, NZ5) are in CI — the spec leaves `live:sign-in-3` mutations to CI; NZ1 to NZ6 passed 143 of 143 on a fresh stack; reopen_if a CI run keeps NZ1 green with the `keepFocus` call removed.
    - `[low]` `[reject]` the negative assertions of `TestRepeatAndSetting` act on a 3 s timer — the repeat press (409) sends nothing; the setting case can only miss a write later than 3 s, and the row count is also checked by the first-press control.
    - `[low]` `[reject]` the `Hang 1` cleanup waits — same as the Blind Hunter row on it.
    - `[low]` `[patch]` `TestDecisionRefOnlyForTellNow` has no control that the case-variant Ref differs — an `AssertTrue` control added.
  - Intent Alignment
    - `[low]` `[reject]` the spec covers the Enter key, not Space, status 0, the busy rule or the phone's focus move — descriptive; the NZ1 to NZ6 list is the spec's, and the native button and `ServerButton` give Space and the busy rule.
- patches applied: 5 (medium 2, low 3).

## Design Notes

**Architecture decisions:**
- AD-21 as amended 2026-11-08: precedents only from a person's noise mark or a `done` answer, and dropped at sign-out;
- AD-1: MarkNoise from `web_user` through `Commands.Submit`;
- AD-4: owner-scoped reads through `Ownership`, the session from the CSP session;
- AD-11: the request row is the truth, which grounds DW-933;
- AD-12, AD-32 and AD-33: the server renders text, and the page shows the server's message;
- AD-13: the one client and the envelope;
- AD-29: lanes;
- AD-7 as amended: this story renders nothing for a model.

No AC contradicts an AD's Rule. DESIGN.md places the control "in the notice card's meta line, after the trace link". See Decided in-stage.

**Integration ACs:**
- AC 7: the real AnswersIn, AnswerOps, Approval.Answer and PrecedentOps.
- ACs 1, 2 and 6: the real page, the route, CommandsIn, PrecedentOps, SimPhoneOut and Delivery, against a real stack (Rule 2, Rule 3).

**Consumes:**
- 41.2: the noise route, `MarkNoise`, `RecordPrecedent`, `PrecedentOps`, `KeyFor` and `KeyForRequest`;
- 41.4: the precedent block, which carries these rows to Triage;
- Epic 31's phone notices;
- `Approval.Answer`;
- `Delivery`, written by `SimPhoneOut`.

**Consumed-by:**
- 41.6: reads the rows this story writes (the Your answers tab), and extends `memory-types.ts` and `ApiClient` with the list and Forget calls.
- 41.7: its eval cases read `noise` rows of the shape written here.

**Extend, don't copy:**
- `NoiseControl` follows `IncidentDismiss`: a ghost `ServerButton`, its error rule, and `messageOf`, exported rather than copied.
- `PhoneDecision` follows `Ownership.DeliveryByRef`.
- `Phone.FromRow`'s read follows `Notification.FromRow`'s.
- `SendPrecedent` and `PRECEDENTITEM` follow `SessionOps.SendNotice` and `SessionOps.PRECEDENTITEM`.
- `Ended` follows `BridgeSink.DailyCap`'s open-session rule (ResumeHash). It is a two-line local check and not a call into `DailyCap`, which works under its own lock.
- `AnswerPrecedentsProduction` follows `AnswersInProduction`'s answer path.
- `memory-types.ts` follows `persona-types.ts`.

**PUBLIC TEXT:** none needed.
- "This was noise": EXPERIENCE.md:1057 and 355.
- "Marked as noise at {time}. Similar items will take this into account.": EXPERIENCE.md:940 and 1057.
- The `too_old` text is APPROVED (DW-923), and it is the server's existing `MESSAGETOOOLD`.
- Every other error text is the server's existing message (`Web.Api` MESSAGENOTFOUND, MESSAGESERVERERROR, MESSAGENOTBUILT) or `BUSY_NOTICE`, shown exactly as `IncidentDismiss` shows them.
- No aria-label beyond the visible label, and no `already_marked` text: a repeat shows the status line.

**Decided in-stage:**
- **DW-934, the fix:** `Mark` and `Record` refuse an ended session, meaning on the online demo a row with an empty ResumeHash.
  - `SessionOps.End` stays as it is. Making its drop unconditional, the ordering fix, would send to PrecedentOps from every `End` test that runs without a production, such as `SessionOps`, `SessionOpsDocuments` and `SessionOpsPrecedents:TestNoRowsSendsNothing`, and turn them red.
  - **Residual (inference):** a write that PrecedentOps handles after End's `Has()` read and before End's final ResumeHash clear still survives. That is a window of End's last two steps, milliseconds long. Any write handled before `Has()` is dropped, and any write after the clear is refused.
  - A web answer and a Sign out from the same page are serialized by the CSP session (inference). Telegram is unlinked at End's first step. The online demo's reset clears any row left behind.
  - The lead may also ask for the ordering fix (Clarification 2).
- **DW-933:** compare `AnsweredAction`, and `State` in approved, rejected, executing, done or failed. The row's `AnsweredChannel` is not compared: `Approval.Answer` writes it from the same argument.
- **The page shows the server's refusal message** (IncidentDismiss's rule), not a page constant. So the `too_old` line is `Web.Api.MESSAGETOOOLD`, pinned in IRIS (`Test.Web.MemoryApi:162-165`) and on the page (NZ5's fixed string). Nothing is added to `Msg/Catalog/Core.cls`, which Epic 18 changes, or to `NOTICE_TEXTS` in `chat-view.ts`, which Epic 17 changes.
- **Placement:**
  - In the chat, the control sits in the card's body directly after the decision strip, which is the card's meta line, on its own line. It does not go inside `app-decision-strip`, because the strip is also used by replies, where the control must never show, and a flag through it would touch a shared component.
  - On the phone, it sits after the message's time.
  - The lead may overturn this to a flex row with the strip; that is a CSS-only change in the card.
- **Implement-stage choices:** the probe property is `DemoFlag` (a property and a method named `OnlineDemo` cannot share a class); `SessionOpsPrecedents:TestNoRowsSendsNothing` is renamed `TestNoRowsStillSends`; `SessionOpsDocuments:TestRealStubsEnd` and `SessionOpsDropProbe` follow the always-send drop through `SessionOpsProbe`; a comment line of `docker/tests/test-sign-in-3.sh` names the new spec file.
- **After a reload** the button shows again, because no payload carries a mark. A press then shows the first mark's time (`already_marked`). Persisting the mark would need payload fields on two events, which is out of scope.
- **The phone's `decisionRef`** comes from the Delivery row that `SimPhoneOut` already writes, so no storage changes. The read runs per phone message without an `ApprovalRef` (at most `PHONEMAX` 100 per `/state`). It narrows by `(OwnerRef, Channel)`, and its cost is not measured (inference).
- **`markNoise`'s types are inline `import()` type queries,** so `api-client.ts` needs only the appended method. Epic 18 inserts import names at about 10 and 21.
- **The spec joins `sign-in-3`** (`live:sign-in-3`, CI group `shards-5`) through `SIGN_IN_3_FILES`, not `chromium`, because `live:sign-in` runs close to its 1,200 s deadline (`ci/units.sh:81-83`). `playwright.config.ts` and `playwright-projects.test.mjs` are not contended.
- **The emails come through the real mail path** with `[[mock:mail-tell-now]]` (an existing Lane A scenario, used read-only), so the spec needs no new mock scenario and works with or without the mock key.
- **No Task 0:** no platform behaviour is unmeasured. `SendRequestAsync` from a business operation is `irislib/Ens/BusinessOperation.cls:726`, the form `SessionOps.SendNotice` already uses. JSON leaving out an empty string is pinned by `Test.Web.Api:229` for `approvalRef`.

**Contended paths checked** (`git diff HEAD...origin/OCT-epic{17,18,32}`, 2026-11-08):
- `notice-card.ts` (Epic 17: 19-20, 31, 80-82, 118-127);
- `api-client.ts` (Epic 18: 10, 21, 59-82);
- `ux-strings.test.mjs` (Epic 18: about 172, 188, 308-325, 570, 595; Epics 17 and 32: 680);
- `announce-focus-sources.test.mjs` (Epic 18: 97, 112-116, 139-146, 157);
- `Data/Ownership.cls` (Epic 17: 40, 413, 910).

This story does not touch `chat-view.ts`, `api-types.ts`, `Catalog/Core.cls` or `e2e/support/*`.

**Ledger:**
- **DW-923:** addressed by AC 5. The card shows the approved text, which comes from the server.
- **DW-932:** addressed by AC 6 (NZ1, NZ2, NZ4, NZ5).
- **DW-933:** addressed by AC 8.
- **DW-934:** addressed by AC 9, with the residual above (Clarification 2).

**Spine lines for the lead** (a sub-bullet after "Story 41.4, as built"):

> **Story 41.5, as built**: the page's "This was noise" (a ghost button on tell-now notices with a decision, web chat and simulated phone) posts the noise route with {"channel":"web"|"phone"}; Live.Payload.Phone gains decisionRef (from the session's phone Delivery row of kind tellnow, through Ownership.PhoneDecision); AnswerOps sends one RecordPrecedent asynchronously when Approval.Answer returns done; PrecedentOps.Record writes only when the request's AnsweredAction equals the message's Action and its State is answered, and Mark and Record refuse an online-demo session whose ResumeHash End has cleared.

## Clarification Needed

1. **Contended-file edits (lead's note 3).** Each is proposed as a plain union; none overlaps another epic's hunk. **(a)** and **(b)** are what the standing precedent allows (an appended block, a one-name list append); **(c)**, **(d)** and **(e)** need a ruling.
   - **(a) `web/src/app/api/api-client.ts`** (Epic 18): one method appended at the end of the class, between line 208 and the closing `}` at 209. No import line.
   - **(b) `web/scripts/ux-strings.test.mjs`** (Epics 17, 18, 32): append `['chat/noise-view.ts', ['NOISE_TEXTS']],` to `IMPORTED` after line 68.
   - **(c) `web/scripts/ux-strings.test.mjs`:** append two strings at the end of `SOURCES.ux`, after `'Checklist',` (line 555): `'This was noise',` and `'Marked as noise at {time}. Similar items will take this into account.',`. Both are verbatim in EXPERIENCE.md. Epic 18's ux hunk is at about 188, at the list's start.
   - **(d) `web/scripts/announce-focus-sources.test.mjs`** (Epic 18): insert `'app/chat/noise-control.ts',` after `'app/chat/chat-panel.ts',` (line 106). The list must stay sorted, so this is not an append. The control announces an error reply as `IncidentDismiss` does. Epic 18's insertions are at 112-116.
   - **(e) `web/src/app/chat/notice-card.ts`** (Epic 17):
     - a comment line after 24;
     - `import { NoiseControl } from './noise-control';` and `import { noticeNoiseRef } from './noise-view';` after 6;
     - line 28 becomes `imports: [DecisionStrip, Icon, NoiseControl],`;
     - after line 49 (the strip's closing `}`), `<app-noise-control [decisionRef]="noiseRef()" channel="web" [instanceZone]="instanceZone()" />`;
     - after line 140, `protected readonly noiseRef = computed(() => noticeNoiseRef(this.notice()));`.

     Epic 17 changes 19-20, 31, 80-82 and 118-127; line 28 sits two unchanged lines from 31, and every other edit is at least 4 lines from its hunks. Without these edits the web chat has no control and AC 1 cannot hold. The alternative, the control as a sibling of `app-notice-card` in `chat-panel.ts`, would sit outside the card, contradict EXPERIENCE ("on the ... notice cards"), and trip `approval-sources.test.mjs:331`, which Epic 17 also changes.
2. **DW-934's residual (veto 4, a guarantee: "sign-out clears answers").** Recommended: accept the Decided in-stage fix, which refuses ended sessions.
   - Its window is a write that PrecedentOps handles during End's last two steps.
   - Option B adds the ordering fix as well: `EndPrecedents` always sends the drop, so it queues behind every write already queued. That needs `Test.Core.SessionOpsProbe` to override `DropPrecedents` (answer 0 when `Has()` is 0) and an edit to `SessionOpsPrecedents:TestNoRowsSendsNothing`.
   - Even both together leave the write in flight during End's last step.

## Verification

Run every command from the worktree root (the lead's stated working directory), one per call, with `timeout: 600000`, each sized to about 150 s.
- **IRIS:** `server` `ocutalon-slot-a` and `namespace` `OCUTALON` on every MCP call, after `iris_server_info` shows build 154. One `iris_execute_tests` per message.
- **Throwaways:** prefix each `ci/` call with `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a" OCUTALON_TEST_WEB_PORT=52801 OCUTALON_LOCK_OWNER='epic=41 stage=implement'`, with `OCUTALON_RUN_TAG=e41s5impl`, and the warm tag `e41s5implw`.

**Commands:**
- (loop) Load with `iris_doc_load` (absolute paths, `baseDir` `<worktree>/src/ocutalon/cls`), then compile with `iris_doc_compile` `ck`, these classes:
  - `Core/AnswerOps.cls`, `Core/PrecedentOps.cls`, `Data/Ownership.cls`, `Live/Payload/Phone.cls`;
  - `Test/Core/AnswerOpsProbe.cls`, `PrecedentOpsProbe.cls`, `PrecedentOps.cls`, `AnswerPrecedents.cls`;
  - `Test/Data/OwnershipPrecedents.cls`, `Test/Live/Payloads.cls`, `Test/Demo/SimPhoneOut.cls`.

  Expected: no compile error.
- (loop) `iris_execute_tests`, one class per message, on slot A: `OcuTalon.Test.Core.PrecedentOps`, `.Core.AnswerPrecedents`, `.Data.OwnershipPrecedents`, `.Live.Payloads`, `.Demo.SimPhoneOut`. Expected: every assertion passes.
- (once) `iris_execute_tests` on slot A, one per message: `.Core.AnswersIn`, `.Core.SessionOpsPrecedents`, `.Web.MemoryApi`, `.Web.Api`, `.Data.Precedent`. Expected: each passes.
- (once) Warm lane-A throwaway, with the prefix:
  - `ci/warm.sh up` takes 120-400 s; if it is moved to the background, wait for it in bounded foreground polls.
  - Then, one per call: `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e41s5implw ci/iris.sh class OcuTalon.Test.Core.AnswerPrecedentsProduction`, then `... class OcuTalon.Test.Core.PrecedentOpsProduction`, then `... class OcuTalon.Test.Core.AnswersInProduction`.
  - Then `ci/warm.sh down`, also after a failure.

  Expected: each passes.
- (loop) `node --test web/scripts/noise-view.test.mjs`, then (once) each in its own call:
  - `node --test web/scripts/phone-request-sources.test.mjs web/scripts/announce-focus-sources.test.mjs web/scripts/ux-strings.test.mjs`;
  - `node --test web/scripts/playwright-projects.test.mjs web/scripts/payloads.test.mjs web/scripts/api-client-sources.test.mjs web/scripts/approval-sources.test.mjs`;
  - `npm --prefix web run lint`;
  - `npm --prefix web test`.

  Expected: all pass.
- (once) `npm --prefix web run build`. Expected: the payloads `--check` and `ng build` pass.
- (once) `bash ci/checks.sh`. Expected: every block passes.
- **Left to CI**, because each takes over 150 s locally:
  - `live:sign-in-3` in `shards-5` (`web/e2e/memory-noise.spec.ts`, Rule 3);
  - `live:demo-path` in `browser` (REL-2, unchanged);
  - `live:sign-in` (`chat/notice.spec.ts`) in `browser`;
  - `shard:lane-b` in `image` (every `Test.Core`, `Data`, `Demo`, `Live` and `Web` class, `AnswerPrecedentsProduction` included);
  - the fresh-environment check, forward and reversed.

  A stage that can hold a lane-A fresh stack may run `ci/iris.sh build`, then `ci/iris.sh live sign-in-3` (over 150 s; if it is moved to the background, wait for it in bounded foreground polls), then `ci/iris.sh teardown`.

**Mutations (Rule 19), one per AC; record each as `mutation: <change> -> <test red>`:**
- AC 1: `markNoise` posts `{channel:'phone'}` for the web channel -> `noise-view.test.mjs`, which reads the source, and NZ1.
  - mutation: `{ channel }` replaced by `{ channel: 'phone' }` in `ApiClient.markNoise` -> `noise-view.test.mjs` "post the noise path with the channel from the one client" red (observed); NZ1 in CI.
- AC 2: `phoneNoiseRef` returns "" always -> `noise-view.test.mjs`, and NZ2 in CI.
  - mutation: `phoneNoiseRef` returns "" -> `noise-view.test.mjs` "gives the decisionRef of a message with no approvalRef" red (observed); NZ2 in CI.
- AC 3: `noticeNoiseRef` accepts kind `reminder` -> `noise-view.test.mjs`.
  - mutation: `noticeNoiseRef` accepts kind `reminder` -> `noise-view.test.mjs` "gives \"\" for every other kind" red (observed).
- AC 4: the `keepFocus` call removed -> NZ1 (focus on the body).
  - mutation: the `keepFocus` call removed from `NoiseControl` -> `noise-view.test.mjs` source pin red (observed); NZ1 (focus on the body) in CI.
- AC 5: `messageOf(error) || BUSY_NOTICE` replaced by `BUSY_NOTICE` -> NZ5.
  - mutation: `messageOf(error) || BUSY_NOTICE` replaced by `BUSY_NOTICE` -> `noise-view.test.mjs` source pin red (observed); NZ5 in CI.
- AC 6: `NoiseBodyIsPhone` accepts any `channel` value case-insensitively (Lane B, temporary) -> NZ4. Also covered by the existing `Test.Web.MemoryApi:TestNoise`.
  - mutation: not applied here (`Web/Api.cls` is on this stage's never-edit list); NZ4 in CI, and `Test.Web.MemoryApi:TestNoise` passes unchanged.
- AC 7: the `SendPrecedent` call removed from `Carry` -> `AnswerPrecedents:TestDoneSendsOne` and `AnswerPrecedentsProduction:TestApproveRecords`.
  - mutation: the `Record` call (which sends through `SendPrecedent`) removed from `Carry` -> `AnswerPrecedents:TestDoneSendsOne` red (observed); `AnswerPrecedentsProduction:TestApproveRecords` in the throwaway.
- AC 8: the `AnsweredAction` comparison removed -> `PrecedentOps:TestAnswerMustMatch`.
  - mutation: the `AnsweredAction` comparison removed from `Record` -> `PrecedentOps:TestAnswerMustMatch` red (observed).
  - mutation: the `State` `$ListFind` clause removed from `Record` -> `PrecedentOps:TestAnswerMustMatch` red (observed; its pending, expired and cancelled fixtures carry a matching `AnsweredAction`).
- AC 9: `Ended` returns 0 -> `PrecedentOps:TestEndedSession`.
  - mutation: `Ended` returns 0 -> `PrecedentOps:TestEndedSession` red (observed).
  - mutation: `OnlineDemo` returns 0 instead of reading the Setting -> `PrecedentOps:TestEndedSession` red (observed; its last block sets the real `onlineDemo` Setting with `DemoFlag` empty and restores it).
- AC 10: `Phone.FromRow` sets `DecisionRef` for a request message too -> `SimPhoneOut:TestDecisionRefOnlyForTellNow`.
  - mutation: `Phone.FromRow` reads `PhoneDecision` whatever the `ApprovalRef` -> `SimPhoneOut:TestDecisionRefOnlyForTellNow` red (observed, after the test gained a tell-now Delivery row that names an approval message's Ref: the SQL's kind filter alone had hidden the mutation).

**Shared surfaces:**
- the phone payload's keys (`Test/Live/Payloads.cls` Contracts, `Test/Web/Api.cls:229` /state phone keys, `Test/Demo/SimPhoneOut.cls:107-111`, the generated `payloads.ts`);
- the tell-now notice card's contents (`chat/notice.spec.ts` N1, `floor/focus.spec.ts` P4, `floor/announcements.spec.ts` A2 and A7, `approval-sources.test.mjs:339-341`);
- the phone feed's `@else` markup (`phone-request-sources.test.mjs:58`);
- the page's speakers list (`announce-focus-sources.test.mjs:101-121`);
- the UX inventory (`ux-strings.test.mjs`);
- the sign-in projects' file lists (`playwright.config.ts`, `playwright-projects.test.mjs`);
- the Precedent table after the answer production tests (`AnswersInProduction`, `AnswersTelegramProduction` cleanup);
- `PrecedentOps.Record`'s fixtures (`TestApprovalAnswers`).

Every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** A "This was noise" ghost button on tell-now notices with a decision, in the web chat and on the simulated phone, posts the noise route and gives way to the status line (a refusal shows the server's message). The phone payload carries `decisionRef`. `AnswerOps` sends one asynchronous `RecordPrecedent` after a `done` answer. `PrecedentOps.Record` checks the stored answer (DW-933), and `Mark` and `Record` refuse a signed-out online-demo session (DW-934, with `SessionOps.EndPrecedents` always sending the drop, Option B). DW-923 and DW-932 are answered by NZ5 and NZ1, NZ2, NZ4 and NZ5.

**Files changed**
- Server: `Core/AnswerOps.cls` (send on done), `Core/PrecedentOps.cls` (DW-933, DW-934), `Core/SessionOps.cls` (always-send drop), `Data/Ownership.cls` (`PhoneDecision`), `Live/Payload/Phone.cls` (`DecisionRef`).
- Server tests: `Test/Core/PrecedentOps.cls`, `AnswerPrecedents.cls` (new), `AnswerPrecedentsProduction.cls` (new), the probes `AnswerOpsProbe`, `PrecedentOpsProbe`, `SessionOpsProbe`, `SessionOpsDropProbe`, `ApprovalDouble`, `SessionOpsPrecedents`, `SessionOpsDocuments`, `AnswersInProduction`, `AnswersTelegramProduction`, `Test/Data/OwnershipPrecedents.cls`, `Test/Live/Payloads.cls`, `Test/Demo/SimPhoneOut.cls`.
- Web: `api/memory-types.ts`, `chat/noise-view.ts`, `chat/noise-control.ts` (new); `api/api-client.ts` (`markNoise`), `chat/notice-card.ts`, `phone/simulated-phone.ts`, `incidents/incident-dismiss.ts` (export), `live/payloads.ts` (regenerated), `playwright.config.ts`, the source-pin tests (`phone-request-sources`, `playwright-projects`, `ux-strings`, `announce-focus-sources`), `scripts/noise-view.test.mjs` (new), `e2e/memory-noise.spec.ts` (new), a comment in `docker/tests/test-sign-in-3.sh`.

**Review findings.** 24 findings: high 0, medium 3, low 19, false 2. Patches applied: 5 (the real `OnlineDemo` seam case, the `State` pin of DW-933, the `$IsObject` guard in `TestRepeatAndSetting`, the unused alias, the case-variant control). Deferred: none. Rejected with reasons: see the Review Triage Log (the always-send drop failing sign-out while PrecedentOps is down is the ruled Option B; the per-message phone read is the spec's decision).

**Follow-up review recommended:** false. Two medium entries were patched, but both are test additions that were run and mutated red in this pass; no unverified risk remains.

**Verification performed.**
- Slot A, all green: `Test.Core.PrecedentOps` (20), `AnswerPrecedents`, `AnswersIn`, `SessionOps`, `SessionOpsDocuments`, `SessionOpsPrecedents`, `Test.Data.OwnershipPrecedents`, `Data.Precedent`, `Live.Payloads`, `Demo.SimPhoneOut` (one skip, `TestThroughNotify`, as before), `Web.MemoryApi`, `Web.Api`.
- Lane-A throwaway: `AnswerPrecedentsProduction`, `PrecedentOpsProduction`, `AnswersInProduction`, `AnswersTelegramProduction`, `SessionOpsProduction` and `Web.SessionEndApi` passed (the implementation run); `AnswerPrecedentsProduction` passed again after the review patches. `live:sign-in-3` passed 143 of 143, NZ1 to NZ6 included (the implementation run).
- Web: `noise-view.test.mjs`, the source-pin tests, `npm --prefix web test` (1555), lint, build; `bash ci/checks.sh` all passed.
- Left to CI: `live:demo-path`, `live:sign-in` (`chat/notice.spec.ts`), `floor/focus.spec.ts`, `floor/announcements.spec.ts`, `shard:lane-b`, the fresh-environment check forward and reversed, and the behavioural mutations of AC 4, 5 and 6 against NZ1, NZ5 and NZ4.

**Residual risks.** A write that PrecedentOps handles during End's last step still survives (accepted, U-311). A sign-out now fails while PrecedentOps is unreachable (ruled). The phone `decisionRef` read costs one SQL read per phone message (unmeasured). The `Hang`-based waits in the answer production tests could, on a very slow stack, leave a stray row of a fixture session.
