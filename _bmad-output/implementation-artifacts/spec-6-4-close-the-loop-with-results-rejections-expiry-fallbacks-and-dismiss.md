---
title: 'Story 6.4: Close the loop with results, rejections, expiry, fallbacks and Dismiss'
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

**Problem:** An incident card has no ending.
- **No results:** nothing on the page reads a request's `result`, so a finished fix shows no result band.
- **Gaps on the card:** a fallback or no-fix card shows neither its notice nor its failure groups, and there is no Dismiss anywhere.
- **The route:** `POST /api/v1/incidents/:ref/dismiss` still answers 501 for a visible incident.
- **The phone:** a `result` notification is only a Delivery row, so nothing shows there.
- **Ledger items:**
  - `live floor` runs within 13 s of its 540 s deadline, because Epic 6's floor cases sit in it (DW-315).
  - `Test.Core.ConversationTurns` leaves Ens log rows behind (DW-105).

**Approach:**
- **The card.** Each request card gets its result band from the `incident` payload's `requests`, using the catalog's result texts. The card shows the fallback and no-fix notices with their groups, and puts Dismiss where DESIGN places it.
- **The route.** It submits the dismissal through `Commands.Submit` → `CommandsIn` → `IncidentManager`. In tests, a fixture IncidentManager (Epic 4's double, extended) answers it and publishes the closed view.
- **The phone.** `SimPhoneOut` renders `result` notifications as messages.
- **The tests.** 19 of Epic 6's 21 floor cases move into `live:answers` beside 6.4's new cases. I1 and A1, the only `@browsers` cases, stay in the floor, which runs them in all three engines. `ConversationTurns` cleans its own log rows.

## Boundaries & Constraints

**Always:**
- **The card reads only the `incident` payload's fields (AD-12, AD-15).** That covers the chip from `state`, the band from `requests[].state` and `requests[].result`, and the notices from `openVariant`, `fallback`, `fallbackReason`, `cause`, `causeCategory` and `groups`. The page never derives a state of its own.
  - The one local view: after a 200 from the dismiss route, the page shows that incident as closed. That reply is the owner's synchronous confirmation.
- **Dismiss is shown only on a card whose `state` is `resolved` or `open`.** It is never shown while awaiting approval, while fixing, or on a closed card. Where it sits:
  - with request cards, at the right end of the last request card's band;
  - else, at the right end of that card's answered-status row;
  - with no request card, in the card's actions row after Show details (DESIGN L810, L823, L826).
- **Texts:**
  - **Result texts** come from the generated catalog (`renderPageText` of the `result.*` keys and `audit.recorded`).
  - **The card's fallback and no-fix sentences, the "Failures:" label and the group line** are UX texts (EXPERIENCE L803-828) in `INCIDENT_TEXTS`, with their `ux` sources.
  - **A Dismiss failure** shows the reply's `error.message`, or `ServerButton`'s busy notice when there is no answer. The page adds no new text.
  - Straight ASCII quotes; non-ASCII only as escapes (Rule 14).
- **One path for a dismissal (AD-1, AD-15).**
  1. The route checks visibility first: `Ownership.Incident` for the CSP session's `SessionRef`, and 404 when the session can't see the incident.
  2. It then calls `Commands.Submit` with an `OcuTalon.Msg.Command.Dismiss` (`IncidentRef`, the server-side `SessionRef`) and origin `web_user`.
  3. It never reads the body and never takes a `SessionRef` from the client (AD-4).
- **Speech and focus (Conventions › Announcements and focus).**
  - A result text is announced once, when it first appears or changes on a card already shown.
  - The user's own Dismiss moves focus to the compacted headline and isn't announced.
  - Focus moves only through `shared/focus-rule.ts`. For Dismiss, the chat panel is the one host that moves it; the request card's and the phone's existing rules are unchanged.
- **The phone:** `result` gets a message with no `ApprovalRef` and no buttons (AD-32); `REQUESTKINDS` stays `incident,approval`.
- **Tests clean up after themselves** (Rule 19):
  - every case seeds and removes its own rows, events, phone messages and watch;
  - the double is swapped in and back by the class or spec that needs it;
  - the page clock follows the spec file's convention (real in `answers.spec.ts` and `close-loop.spec.ts`; fixed in the moved floor specs).

**Never:**
- **No Lane A class or contract edits:**
  - not `Watch/**` (`IncidentManager`), `Fix/**`, `Msg/Catalog/Watch.cls`, `Live/Payload/Incident.cls` or its parts, or `Data/Incident.cls`;
  - no `web` form added to any catalog key (`Test.Msg.Catalog` `TestWebWording` pins exactly four).
- **No contended edit beyond ruling Q2:**
  - not `Core/Commands*.cls` other than `CommandsIn.cls`;
  - not `Test/Core/CommandsInProduction.cls` (6.4 adds no row there);
  - not `Test/Web/Api.cls` outside Q2;
  - not `docker/tests/test-demo-path-gate.sh` or any other existing `docker/tests/**` file except Epic 6's own `test-answers.sh`;
  - not `ci/units.sh` (unchanged), `.github/**`, `README.md`, `Demo/Guide*.cls`, `web/src/app/{guide,feed,live,api}/**` (own api-client and api-types entries excepted), or `web/src/app/live/payloads.ts`.
- **No new floor case, sign-in case or CI unit, no new Playwright project, and no Firefox or WebKit run for `answers`.**
- **No new catalog key, security object, grant, role, stored property or table.**
- **Not this story:**
  - the real IncidentManager's dismiss, quiet close and replay (Epic 5);
  - the real results (Epic 7, Story 30.5);
  - Telegram's result message (Epic 12);
  - DW-292's snapshot of requests and results after a reload;
  - standalone tool-call request cards.

## I/O & Edge-Case Matrix

**Fixture values:**
- **The session:** S, the ANSWERS session, in demo mode and watching Orders (`Install.Step.Demo`'s `NAMESPACE` and `PRODUCTION`).
- **The incident:** R, an Orders incident of S, noticed, `count` 50, `itemNoun` {one "order", other "orders"}.
- **Its requests:** A and B, 6.2's fixture requests of R.
- **Times:** "HH:MM" is the instance-zone time of the moment named.

The result texts are the catalog's (Design Notes › Result mapping).

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| All went through | R `resolved`; A `done`, result {total 50, resent 50, completed 50} | **A's card**, below its answered status: a `result-success` band with `circle-check` and "All 50 orders went through.", with "Recorded in the IRIS audit log." beneath in caption, and a ghost Dismiss at the band's right end. **The incident card:** chip Resolved, success bar. **Speech:** when the band first appears on a card already shown, "All 50 orders went through." is announced once. | total 1: "The order went through." |
| Partial results | A `done` or `failed`, with failedAgain, skipped, both, interrupted, or resent 0 with a reason | A `result-partial` band with `triangle-alert` and the mapped text, for example "48 of 50 orders went through. 2 failed again (the order date still wasn't accepted). I won't retry them without a new approval." Each request keeps exactly one band. | The count-of-one forms, by the catalog's `one` rule |
| Still resending, then final | R `fixing`; A `executing`, result {total 50, completed 30} | **While fixing:** a `result-partial` band with `clock` and "Still resending: 30 of 50 orders have gone through so far. I'll tell you when it's done.", plus the fixing line "Repairing and resending 50 orders…". There is no Dismiss. **Final:** a `resolved` payload with the final result replaces that band's text in place. Each text is announced once. | — |
| Two requests | R `awaiting_approval`; A done with failedAgain; B pending | **While B is pending:** A's band; B's Approve and Reject; chip Awaiting approval; no Dismiss. **After B is rejected and R becomes `open`/`rejected`:** B's status "Rejected from the web chat at HH:MM. Nothing was changed."; Dismiss at the right end of B's status row; A's band unchanged. | — |
| Rejected or expired | R `open`/`rejected` or `expired`; A `rejected` or `expired` | **Status:** "Rejected from {channel} at HH:MM. Nothing was changed." with `circle-slash`, or "Expired at HH:MM. Nothing was changed." with `clock`. **The card:** no Approve or Reject; attention bar; Show details then Dismiss at the row's right end. **The guide:** Break the feed stays inactive (`incident_in_progress`). | — |
| Fallback | R `open`/`fallback`, `fallback` true, `fallbackReason` `timeout`, groups [{itemName "Order transform", count 50, errorSummary "date could not be read", firstAt}] | **Card:** chip Open with the Fallback flag; the headline; "I couldn't work out the cause (the model didn't answer within 60 seconds), so I'm not proposing a fix. Nothing was changed."; "Failures:" and "Order transform: 50, 'date could not be read', first at HH:MM"; no fix and no request card; Show details then Dismiss. **Speech:** at first sight, "Incident: {headline}. No fix proposed." **Phone:** the `incident.fallback` notice renders as one message with no buttons. | A dated `firstAt` reads "first on {day} at HH:MM" |
| No fix | R `open`/`no_fix`, cause and causeCategory set, groups | **Card:** the cause sentence; the evidence line; "None of my fixes applies to this, so I'm not proposing one. Nothing was changed."; the groups; Show details then Dismiss. **Phone:** the `incident.noFix` message with no buttons. | causeCategory `unknown`: "I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed." in place of the cause and the no-fix sentence |
| Dismiss pressed | R `open`/`rejected`; focus on Dismiss; press | **The press:** one POST of `{}` to `/api/v1/incidents/R/dismiss`; Dismiss busy (spinner, `aria-busy`, `aria-disabled`, never `disabled`, repeats ignored). **On 200:** the card compacts in place (chip Closed, border-strong bar, the headline and each request's band, Show details, no Dismiss, no request card); focus on the compacted headline; no announcement. **Server side:** the double records one `dismiss` (origin `web_user`, session S); R's row is closed; Break the feed becomes active within one live update. | See the next row |
| Dismiss fails | reply held; 409, 404, 403 or 500; status 0 | **Held:** after 10 s Dismiss is restored with "Couldn't reach OcuTalon. Try again. Nothing was changed.", shown and announced; a later 200 still compacts the card. **4xx or 5xx:** the reply's `error.message` shows beside Dismiss and is announced once; the card is unchanged. **Status 0:** the busy notice at once. | — |
| Closed by IncidentManager | an `incident` payload of R with `state` `closed` (quiet close, replay, or another tab's Dismiss) | The card compacts in place to the headline and each request's band. A later incident with a new Ref gets a card of its own. Either way the chat announces the closed state as 6.1 does ("Incident: {headline}. Closed."), because no Dismiss of this page made it. | — |
| Route, visible incident | POST from S's CSP session for R | `Commands.Submit(Dismiss{IncidentRef R, SessionRef S}, "web_user")` reaches IncidentManager as `IncidentCommand` `dismiss`, synchronously. That is one CommandsIn→IncidentManager header whose SuperSession is S's TraceRef. There is no Turn and no `chat.message`. The answers: Ok gives 200 `{"result":"done"}`; an owner refusal gives 409 `not_dismissible` with the owner's `Message`, else "OcuTalon can't dismiss this incident now. Nothing was changed."; CommandsIn's `not_built` gives 501 `not_built`; its `not_found` gives 404. | `failed`, any other CommandsIn code, an error status or a failed read: 500 `server_error` |
| Route, unseen incident | another session's incident, an unnoticed one, an `eval` one, an unwatched `instance` one, or an unknown ref; online-demo flag on or off (on: a watched `instance` one too) | 404 `not_found` with the error body, before anything is submitted. The row is unchanged, IncidentManager gets nothing, and no event is published. | — |
| Phone result | `Notification` kind `result`, key `result.allThrough`, slots {count 50, itemNoun}, ApprovalRef A, IncidentRef R | One new SimMessage with `Render(key, slots, "phone")` and an empty ApprovalRef, its phone Delivery row and one `phone` event. A's request message keeps its answer line. | A render error: an error status, nothing saved |
| The double gets `dismiss` | R `resolved`, or `open` and noticed | The row becomes `closed` with `ClosedAt`. The newest published `incident` payload of R, with `state` `closed`, is published to R's stream (each recipient for `instance`). It answers Ok 1, Outcome `closed`. | Any other state (`awaiting_approval`, `fixing`, `closed`, or `open` not noticed): Ok 0, Outcome `refused`, Message "zz the double refuses to dismiss an incident that is {state}". The "refuse" setting gives Ok 0 with no Message; the "error" setting gives an error status. |

</intent-contract>

## Code Map

Server paths are under `src/ocutalon/cls/OcuTalon/`.

**Server, to change:**
- **`Web/Api.cls`** (shared by entry; Epic 6's own route):
  - **Messages:** L59-91. `MESSAGENOTFOUND` is at L79 and `MESSAGENOTBUILT` at L91. `MESSAGENOTDISMISSIBLE` goes beside them.
  - **The route:** L100.
  - **`DismissIncident`:** L470-482, the doc and the handler to replace. Today it returns a raw `sc` on a failed read (L477, L479); 6.4 uses `ServerError`.
  - **Patterns:**
    - `AnswerApproval` L398-412 and `AnswerResponse` L436-470: the mapping of an owner's result to codes;
    - `Fail(status, code, message, approval)` L792-809;
    - `ServerError(sc)` L139-148.
  - **Keep away from:** `RailBody` L677-693 (Epic 5's checks push L683-685) and `CheckView` L695-715.
- **`Test/Demo/IncidentManagerDouble.cls`** (Epic 4's double, extension).
  - **Today:** L1-7 doc; `OnRequest` L12-40, which closes the row for any verb and publishes nothing.
  - **What it gains:**
    - the dismiss rule and the publish (for `dismiss` only);
    - `ClassMethod Use() As %Status` and `ClassMethod Restore() As %Status` for the e2e helpers.
- **`Channel/SimPhone/Out.cls`** (Story 4.5's, extension): `CARDKINDS` L29 (add `result`), `REQUESTKINDS` L32 (unchanged), `OnNotification` L51-65 and the class doc.
- **`Test/Web/Api.cls`** (contended, ruling Q2): `TestUnseenRefIs404` L642-699.
  - Only its doc's incident half (L644-645: "A visible incident answers 501 not_built") changes.
  - Only the loop L683-687 (`For ref = ownIncident, instanceWatched { ... DismissIncident ... 501 ... }`) changes.
- **`Test/Core/ConversationTurns.cls`** (footprint):
  - `OnBeforeAllTests` L81-91 and `OnAfterAllTests` L111-120;
  - `LastLog()` L1560.
  - The siblings for the cleanup are `Test/Core/BridgeSink.cls` L69 (`ID > LogMark AND SourceClass IN (...)`) and `Test/Core/AnswersIn.cls` L379.

**Server, read only:**
- **`Core/Commands.cls` L18:** `Submit(command As Msg.Command, origin, Output result As Msg.CommandResult) As %Status`. It errors only when CommandsIn was never reached. (Epic 8's contended file.)
- **`Core/CommandsIn.cls`:**
  - Routes XData L171: `Dismiss` → `IncidentManager`, from origins `web_user,web_admin,telegram,tool,timer,system`.
  - `Carry` L66-88. The visibility guard at L74-78 applies to origin `tool` only, so the route's Ownership check is the web guard.
  - `Dismissal` L132-142 builds the IncidentCommand. `Send` L92-95 is synchronous, `TIMEOUT` 120 (L33).
  - `Join` L119-130 gives SuperSession = TraceRef.
  - Outcomes: a stub's 5003 is `not_built`; other errors are `failed`.
- **Messages:** `Msg/Command/Dismiss.cls` (`IncidentRef`); `Msg/Command.cls` (`Origin`, `IdempotencyKey`, `SessionRef`); `Msg/CommandResult.cls` (`Ok`, `Message`, `Outcome`, `Ref`, `Data`); `Msg/IncidentCommand.cls` L6 (`VERBS`).
- **`Data/Ownership.cls`:**
  - `SessionRef(.sc)` and `Incident(ref, sessionRef, .sc)` L326-336;
  - `INCIDENTVISIBLE` L49: `NoticedAt` set; own, or (LocalFlag) a watched `instance` one;
  - `LocalFlag` L491-494, which is 0 on the online demo;
  - `IncidentInProgress` L450-456: `open`, `awaiting_approval` or `fixing`, for the watched production.
- **`Demo/Guide.cls`:** L53-54 (the Orders production from `Install.Step.Demo`), and the availability at L145-176 (`incident_in_progress` while an Orders incident is in progress; a closed one frees it). Read it, never change it.
- **`Watch/IncidentManager.cls`** has `Parameter STUB = 1` on this branch (Lane A).
- **Item swaps:** `Test/Agent/RunnerFixture.cls` `UseItemClass` L645-654 and `RestoreItemClass` L656-660. The pattern of use and its guard is `Test/Demo/BreakFeedProduction.cls` L1-18, L50-98 and L479-492.
- **Request helpers:**
  - `Test/Web/Api.cls`: `CallSession` L1107-1115 (the stand-in request and session), and `Written(Output sc, class, method, args...)`, a public ClassMethod at about L1166;
  - `Test/Web/StubRequest.cls`: `Make`, `MakeBody`;
  - the sibling API test class is `Test/Web/BreakFeedApi.cls`.
- **`Test/Data/Fixture.cls`:** `Session` L19, `Check(session, ns, prod)` L65, `Incident(owner, noticedAt, ns, prod, fields)` L81, `Approval` L102, `Clean` L331, `RemoveMessages`.
- **Live events:** `Live/Publish.cls` `Publish(stream, type, payload, .seq)` L62 (it refuses inside a transaction; a demo-mode publish of `incident` recomputes the guide); `Live/Event.cls` `Since(stream, after, max)` L34; `Live/Payload/Incident.cls` `FromRow` L65 (row fields only, no requests).
- **The catalog:**
  - `Msg/Catalog/Watch.cls` (Lane A): `result.*` L151-241 (no `web` forms; `one` forms on the count slots), `incident.fallback` L119, `incident.noFix` L130, `incident.noFixUnknown` L141 (slot type `groups`).
  - `Msg/Catalog/Core.cls`: `answered.*` L80-155, `fallbackReason.*` L181-235, `audit.recorded` L399.
  - `Msg/Catalog.cls`: `GROUPLINE` L47, the groups slot L210-224, the `one` form L109-121, and "at "→"on " L141-143 and L163.
- **Tests to extend:**
  - `Test/Demo/SimPhoneOut.cls`: `TestOtherKindsRecordOnly` L176-202 (its kinds at L179), `TestOnlyRequestKindsCarryARequest` L273; the helpers `Notification` L637, `FallbackSlots` L621, `Out` L600, `Phones` L655, `Newest` L661.
  - `Test/Msg/Catalog.cls`: `TestWebWording` L447-475 (unchanged); the `Fixtures` XData L1232-1243 holds the exact result and notice texts.

**Web, to change** (`web/src/app/`):
- **`incidents/incident-card.ts`:**
  - the doc L36-44;
  - the template: the chip row L57-67, the `.cause`/`.evidence-line`/`.fix` paragraphs L72-80, the request `@for` L84-93, and the actions row L94-114 (shown only with no request and a panel);
  - `requests` L284, which is `[]` when the card is compact.
- **`incidents/incident-view.ts`:**
  - `INCIDENT_TEXTS` L27-56;
  - `IncidentView` L110-135;
  - `fixSentenceOf` L223 and `fixingLineOf` L240;
  - `incidentView` L309, compact at L312-334;
  - `proposesNoFix` L340-342;
  - `announcementOf` L352-367.
- **`approvals/approval-request-card.ts`:**
  - the answer row L131-181: Show details sits at the right end (`margin-inline-start: auto`, L312-316);
  - then the expiry L182, the notice L185 and the panel L188-194; the section closes at L195;
  - the inputs, and `noteStore` L416-434.
- **`approvals/approval-view.ts`:** `APPROVAL_TEXTS` L25-49, `requestsOf` L142, `barOf` L197-202, `statusOf` L219-232 and `answerOutcomeOf` L289-308.
- **`chat/chat-panel.ts`:**
  - `FOCUS_RULE` L52-55, with no `whenGone` today;
  - the incident card L126-134;
  - the effects L300-309 (`keepFocus` on `entries()`);
  - `announce` L350-361.
- **`chat/chat-announcements.ts`:** `ChatAnnounceFormat.incidentText` L41-42 and `chatAnnouncements` L63-75, which remembers only the state per incident.
- **`chat/decision-strip.ts` L26-28:** the fallback reason's text (`REASON_KEYS`, `PAGE_TEXTS`), to export for reuse.
- **`api/api-client.ts` L61-63** (`answerApproval`, the pattern) and **`api/api-types.ts` L89-98** (`AnswerBody`).
- **`web/scripts/catalog.mjs`:** `LISTED_KEYS` L43-69, `SLOT_TYPES` L72, the refusal of `one` forms L157, and the emitters L158-172.
- **`msg/catalog.ts`:** generated.

**Web, read only:**
- **`shared/server-button.ts`:** the `ghost` variant, `action`, `describedBy`, `BUSY_NOTICE` L10 and `BusyState`. It shows no server message itself.
- **`shared/focus-rule.ts`:** `FocusRule.whenGone(lost)` L28-33 and `keepFocus` L53-80. It acts only when focus fell to the body; the first host's callback wins.
- **`feed/break-feed-view.ts`:** L5-7 and L154. The box takes its availability only from the server's guide.
- **`live/payloads.ts`:** `IncidentPayload` L258-278, `IncidentGroup` L60-65 (`itemName`, `count`, `errorSummary`, `firstAt`), `IncidentRequest` L67-71 (`ref`, `state`, `result?`), and `IncidentRequestResult` L73-81 (`total`, `resent`, `completed`, `failedAgain`, `skipped`, `interrupted`, `reason`).
- **Styles and icons:** `styles/tokens.css` L438-443 (`--result-success-*` and `--result-partial-*`, with dark forms at L727-730 and L950-953); `icon/icon.ts` (`circle-check`, `triangle-alert` and `clock` exist).

**Web tests:** each one pins a shared surface (Verification).
- `web/scripts/incident-sources.test.mjs`: L55-111 and L135-170, including the actions-row regex L70-85.
- `approval-sources.test.mjs`: L54-87, and the exact request `@for` regex L227-239.
- `announce-focus-sources.test.mjs`:
  - the incident card does not speak, L86-94;
  - the speakers, L96-111;
  - the `.focus(` counts, L116-132;
  - the `keepFocus` hosts and their rules, L142-161.
- `incident-view.test.mjs`: L105-222, about L430, and the `INCIDENT_TEXTS` deepEqual at about L482.
- `approval-view.test.mjs`: L137-200 and L308-335.
- `catalog.test.mjs`: L48-56, L72-78, L92-101 and L158-163.
- `chat-announcements.test.mjs` L148-180, and `ux-strings.test.mjs` L41-58.

**E2E and CI:**
- **`web/e2e/floor/incident.spec.ts`:**
  - imports L3-7, `KIND = 'FLOOR'` L26, the fixed clock L44-46, `open()` L94-100;
  - I1 (`@browsers`) L142-194, then I2-I11 L195-560.
- **`web/e2e/floor/approval.spec.ts`:** imports L3-16, `KIND` L34, the clock L49-51, the local helpers L40-119, A1 (`@browsers`) L137-206, then A2-A10 L207-582.
- **`web/e2e/answers/answers.spec.ts`:** `KIND = 'ANSWERS'` L28 and `open()` L61-68, which signs in as ANSWERS and waits for the snapshot and the phone.
- **`web/e2e/support/iris.ts`:**
  - `irisScript` L71, `publishIncident` L145, `sinkEvent` L431, `sendNotification` L618, `cleanFixtureRows` L638;
  - `seedApproval` L693 (`state` and the answered fields), `seedOtherSession` L736, `answerQuietly` L749;
  - `seedCheck` L826, `seedIncident(owner, {namespace, production, noticedAt, state, openVariant})` L928-963.
- **`web/e2e/support/approvals.ts`:** `incidentOf(ref, requests)` L29 (every request `pending`) and `raise` L57-71; its header L7-10.
- **`web/e2e/support/api.ts`:** `post(request, path, data)` L37.
- **`web/e2e/support/floor.ts`:** `openFloor` L135-140 is the FLOOR user's.
- **`web/e2e/demo-path/05-approval.spec.ts`:** the `@fixtures` test L1-66, and `notBuilt(... '11.1')` L68.
- **`docker/tests/test-answers.sh`:** header L26-33, PASS L91.
- **`web/playwright.config.ts`:** `workers: 1` L26, the projects L39-50 (unchanged).
- **`web/scripts/playwright-projects.test.mjs`:**
  - L96-117: `e2e:answers` lists `answers/` from disk;
  - L192: the floor keeps at least 37 titles.
- **`ci/units.sh`** L33-44 is unchanged.
- **`docker/tests/test-demo-path-gate.sh`** L362 pins the browser group's install sequence. That pin is why `answers` gets no Firefox or WebKit (Design Notes).

## Tasks & Acceptance

**Execution:**

1. **`src/ocutalon/cls/OcuTalon/Test/Demo/IncidentManagerDouble.cls`: the fixture IncidentManager for `dismiss` (AD-29).**
   - **For verb `dismiss` only, after the existing "answer" settings** ("error" gives an error status; "refuse" gives Ok 0, Outcome `refused`, no Message):
     1. It applies AD-15's dismiss rows:
        - `resolved`, or `open` with `NoticedAt` set: closed (`State` `closed`, `ClosedAt` now) and saved;
        - anything else: Ok 0, Outcome `refused`, Message "zz the double refuses to dismiss an incident that is {state}", and the row is unchanged.
     2. After the save, outside any transaction, it publishes the incident's full view. That is the newest `incident` event payload of that ref in its owner's stream (read through `Live.Event.Since`), with `state` set to `closed`, else `Live.Payload.Incident.FromRow`.
     3. It publishes through `Live.Publish.Publish` to the owner's stream, or for `instance` to each session of `Session.Recipients`.
     4. It answers Ok 1, Outcome `closed`, Ref.
   - **Unchanged:** `closeForReplay` and `closeQuiet`, which `Test.Demo.BreakFeedProduction` pins.
   - **`ClassMethod Use() As %Status`:**
     - it refuses unless `OcuTalon.Production` runs (as `BreakFeedProduction.OcuTalonRunning`);
     - it then calls `Test.Agent.RunnerFixture.UseItemClass("IncidentManager", <this class>, .saved)` and keeps `saved` as JSON under `^OcuTalonTest("IncidentManagerDoubleUse")`;
     - it kills `^OcuTalonTest("IncidentManagerDouble")`.
   - **`ClassMethod Restore() As %Status`:** `RestoreItemClass` from that global, then kills both nodes. With nothing saved it is OK and does nothing.
   - Update the doc (THROWAWAYS AND CI ONLY).
2. **`src/ocutalon/cls/OcuTalon/Web/Api.cls`: the dismiss route (AD-1, AD-4, AD-15).**
   - Replace `DismissIncident`'s doc and body. It never reads the body. In order:
     1. `Ownership.SessionRef` then `Ownership.Incident`. A failed read gives `ServerError(sc)`, and an unseen incident gives `Fail(404, "not_found", MESSAGENOTFOUND)`, before anything is submitted.
     2. A new `OcuTalon.Msg.Command.Dismiss` with `IncidentRef` = the row's Ref and `SessionRef` = sessionRef, then `Commands.Submit(command, "web_user", .result)`. An error status gives `ServerError`.
     3. The answer:
        - `result.Ok` gives 200 `{"result":"done"}` (content type JSON);
        - Outcome `not_built` gives `Fail(501, "not_built", MESSAGENOTBUILT)`;
        - `not_found` gives 404 `not_found`;
        - `failed`, `unknown_command` or `not_allowed` gives `ServerError` with a status naming the outcome;
        - any other outcome (the owner's refusal) gives `Fail(409, "not_dismissible", <result.Message if not empty, else MESSAGENOTDISMISSIBLE>)`.
   - Add `Parameter MESSAGENOTDISMISSIBLE = "OcuTalon can't dismiss this incident now. Nothing was changed.";` (Veto V1).
3. **`src/ocutalon/cls/OcuTalon/Test/Web/DismissApi.cls`** (new; Test/Web, a new class in a contended folder). The route's own tests run through the real production with the double behind IncidentManager.
   - **Setup and guard.** `OnBeforeAllTests` follows `BreakFeedProduction` L50-73: Fixture.Clean, then the guard (`OcuTalon.Production` runs, else every test fails with the reason), then `IncidentManagerDouble.Use()`. `OnAfterAllTests` restores, then removes the fixture rows, events and the sessions' messages (`Fixture.Clean`, `Fixture.RemoveMessages`).
   - **How it calls the route.** Each call sets `%request` (`Test.Web.StubRequest.Make`, or `MakeBody` for a body), `%response` and a CSP session whose `Data("OcuTalon.SessionRef")` is the fixture session, as `Test.Web.Api` L662-663 does. It then calls `##class(OcuTalon.Test.Web.Api).Written(.sc, "OcuTalon.Web.Api", "DismissIncident", ref)` (Rule 2: reused, not copied).
   - **The tests:**
     - `TestOwnOpenIncidentCloses`:
       - an own `open`/`rejected` noticed incident, with a published fixture `incident` payload that lists a request with a result;
       - expects 200 `{"result":"done"}`, the row closed, and one double command (verb `dismiss`, ref, the session, origin `web_user`);
       - expects one `incident` event in the session's stream with `state` `closed` and the earlier payload's `requests`;
       - expects one CommandsIn→IncidentManager header with SuperSession = the session's TraceRef;
       - expects no Turn row and no `chat.message` event.
     - `TestResolvedIncidentCloses`.
     - `TestBreakFeedAvailableAgain`: demo mode on (`Test.Demo.Step.Put`), the session watching Orders (`Fixture.Check` with `Install.Step.Demo`'s NAMESPACE and PRODUCTION), and an open noticed Orders incident.
       - Before the dismissal, `Guide.Compute(session).BreakFeed` is inactive with reason `incident_in_progress`; after it, it is active.
       - A `guide.state` event follows the closed `incident` event.
     - `TestRefusedIs409`: an `awaiting_approval` incident and a `fixing` one each answer 409 `not_dismissible` with the double's message, and the rows are unchanged. With the "refuse" setting (no Message), the body's message is `MESSAGENOTDISMISSIBLE`.
     - `TestOwnerErrorIs500`: the "error" setting gives 500 `server_error`, and the row is unchanged.
     - `TestOtherSessionsIncidentIs404` (AC7, the required CI check): with onlineDemo "" and then 1, each of these answers 404 with the `not_found` body:
       - another session's noticed incident;
       - an unnoticed own one;
       - an `eval` one;
       - an unwatched `instance` one;
       - with the flag 1, also a watched `instance` one;
       - an unknown ref.

       In every case the double records nothing, the rows are unchanged, and no `incident` event is published in either stream. onlineDemo is saved and put back.
     - `TestBodyIsIgnored`: a body `{"sessionRef": <other>}` neither reaches another session's incident (404) nor changes the command's SessionRef for one's own (the double's "session" is the CSP session's).
   - Header per Rule 14 (what it pins and needs).
4. **`src/ocutalon/cls/OcuTalon/Test/Web/Api.cls`** (contended; ruling Q2: only these two places).
   - **The doc.** In `TestUnseenRefIs404`'s doc, replace the incident half of the sentence at L644-645 with: "A visible incident's dismissal reaches its owner: 501 not_built while IncidentManager is a stub (its STUB parameter), and the owner's answer, never 404, once it is built."
   - **The loop.** Replace the loop L683-687 with a loop over `ownIncident, instanceWatched` that first notes the Ens log mark, then calls `DismissIncident`:
     - when `$Parameter("OcuTalon.Watch.IncidentManager", "STUB")` is 1, it asserts "501 Not Implemented" and the `notBuilt` body;
     - otherwise it asserts a status other than "404 Not Found" and a body without `"not_found"`.

     It then deletes the Ens log rows after the mark whose SourceClass is `OcuTalon.Watch.IncidentManager` (the stub's error rows that the dismissal caused).
   - Nothing else in the file changes.
5. **`src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls`:** `CARDKINDS` becomes `tellnow,reminder,incident,approval,result`, and `REQUESTKINDS` is unchanged. A `result` is a new message: the text is `Render(CatalogKey, Slots, "phone")`, with no ApprovalRef, its Delivery row and one `phone` event. Update the doc (results are messages, never edits; the answered edit stays the only edit).
6. **`src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls`** (extend).
   - **Changed:** `TestOtherKindsRecordOnly`'s kinds (L179) become `fallback,allowance,pairing,status,digest`.
   - **Added:**
     - `TestResultIsAMessage`: the Matrix row "Phone result", with the text = `RenderAt("result.allThrough", ..., "phone", now, 0)`. Count 1 gives "The order went through.". A's earlier request message keeps its Ref and Answer.
     - `TestFallbackAndNoFixWording`: `incident.fallback`, `incident.noFix` and `incident.noFixUnknown`, each with two groups (one dated) and no ApprovalRef. Each is one message whose Text equals `RenderAt(..., "phone")`, with an empty ApprovalRef.
     - `TestResultRenderError`: an unknown key gives an error status, no message and no event.
   - Update the header.
7. **`src/ocutalon/cls/OcuTalon/Test/Core/ConversationTurns.cls` (DW-105).** Add `Property LogMark As %Integer`, set in `OnBeforeAllTests` from `..LastLog()`. In `OnAfterAllTests`, delete `Ens_Util.Log` rows `WHERE ID > LogMark AND SourceClass = 'OcuTalon.Test.Core.ConversationProbe'`, the shape of `Test.Core.BridgeSink` L69. Update the header's teardown sentence.
8. **`web/scripts/catalog.mjs`, `catalog.test.mjs`, `web/src/app/msg/catalog.ts` (regenerated).**
   - **`LISTED_KEYS` gains:** `result.allThrough`, `result.failedAgain`, `result.skipped`, `result.failedAndSkipped`, `result.stillResending`, `result.interrupted`, `result.couldNotStart`, and `audit.recorded`.
   - **`SLOT_TYPES` gains `noun`.** A `{one, other}` value renders the form chosen by the entry's `count` slot, as `Catalog.cls` L197-208 does.
   - **`one` forms.** Instead of refusing an entry with a `one` form, the generator emits it (for example `PAGE_ONE_FORMS[key] = {slot, text}`). `renderPageText` uses that text when the named count slot is 1, as `Catalog.Template` L109-121 does.
   - **Tests.** Each expected string is written out as `Catalog.RenderAt` gives it (the `Fixtures` XData L1237-1243), including every count-of-one form. Update `PAGE_TEXTS`'s key set and `PAGE_SLOTS`.
9. **`web/src/app/api/api-client.ts` and `api-types.ts`** (own entries).
   - `dismissIncident(ref): Observable<HttpResponse<DismissBody>>` POSTs `{}` to `/incidents/${encodeURIComponent(ref)}/dismiss` with `observe: 'response'`.
   - `DismissBody` is `{result: 'done'}`.
10. **`web/src/app/approvals/approval-view.ts`: `resultView(request: IncidentRequest, itemNoun)`.**
    - It returns `{key, text, tone: 'success' | 'partial', icon: 'circle-check' | 'triangle-alert' | 'clock'}` by the Design Notes' Result mapping, or `undefined` when `request.result` is absent.
    - The text is `renderPageText(key, slots)`.
    - It also returns the audit line `renderPageText('audit.recorded')`.
11. **`web/src/app/approvals/result-band.ts`** (new, `app-result-band`; build it after Tasks 12 and 13, whose component it places).
    - **Inputs:** a result view, and an optional `dismiss` (a `DismissTarget`, Task 13).
    - **What it renders:** one band on `--result-{tone}-background`/`-foreground`/`-radius`, holding the icon (`aria-hidden`), the text, and at the right end the Dismiss (`app-incident-dismiss`) when `dismiss` is set. The audit line follows beneath in caption.
    - It is not a live region and holds no `.focus(`. Tokens only.
12. **`web/src/app/incidents/dismissals.ts`** (new, `Dismissals`, `providedIn: 'root'`).
    - It holds `refs: Signal<ReadonlySet<string>>`, the incidents that this page closed with a 200, and `add(ref)`.
    - It reads nothing of the server (Rule 2: a one-signal store; the live store is the server's).
13. **`web/src/app/incidents/incident-dismiss.ts`** (new, `app-incident-dismiss`).
    - **Its input:** `target`, a `DismissTarget` = `{ref, key}`: the incident's Ref, and the card's view key (`incident:<ref>`, `incidentView`'s `key`). The type is exported from this file.
    - **What it renders:** `<app-server-button variant="ghost" data-part="dismiss" [attr.data-key]="target().key" [action]=... [describedBy]=...>Dismiss</app-server-button>`, then, when a reply was an error, an `app-inline-notice` (warning) with the reply's `error.message`, whose id is in `describedBy`.
    - **The action** calls `api.dismissIncident(target().ref)`:
      - 200 calls `Dismissals.add(target().ref)`;
      - an error reply with a body sets the notice to `error.message` and announces it once (Announcer);
      - status 0 resolves with no notice, so `ServerButton` shows its busy notice.
    - A new press clears the notice.
14. **`web/src/app/approvals/approval-request-card.ts`.**
    - **New inputs:** `result` (the incident's `IncidentRequest` of this ref, or undefined), `itemNoun`, and `dismiss` (a `DismissTarget`, or undefined for none).
    - **The band.** When `resultView` gives a view, the card renders `app-result-band` between the answer row (L181) and the expiry, passing `dismiss`.
    - **Dismiss without a band.** When there is no band and `dismiss` is set, the answer row ends with `app-incident-dismiss` after Show details.
    - Update the doc.
15. **`web/src/app/incidents/incident-view.ts`.**
    - **`INCIDENT_TEXTS` gains** (each from EXPERIENCE, `ux` sources in `ux-strings`):
      - `fallbackNotice` "I couldn't work out the cause ({reason}), so I'm not proposing a fix. Nothing was changed."
      - `noFixNotice` "None of my fixes applies to this, so I'm not proposing one. Nothing was changed."
      - `noFixUnknown` "I couldn't tell the cause from the failed messages and their errors, so I'm not proposing a fix. Nothing was changed."
      - `failures` "Failures:"
      - `groupLine` "{item}: {count}, '{summary}', first at {time}"
      - `dismiss` "Dismiss"
    - **`IncidentView` gains:**
      - `notice` (the fallback or no-fix sentence). The `{reason}` is the reason's raw text, `PAGE_TEXTS['fallbackReason.' + (REASON_KEYS[reason] ?? 'generic')]`, as `chat/decision-strip.ts` L26-28 finds it. That lookup becomes one exported function used by both (Rule 2), and decision-strip keeps its `sentenceOf`;
      - `groups` (lines; the time in the headline's form, with "at " turned to "on " when that form is dated, as `Catalog.Fill` does);
      - `dismissable` (state `resolved` or `open`, and not compact);
      - `results` (for a compact card, each request's `resultView` in payload order).
    - **The no-fix rules.** For `openVariant` `no_fix` with `causeCategory` `unknown`, the cause sentence is empty and `notice` is `noFixUnknown`. A compact card has no notice and no groups.
16. **`web/src/app/incidents/incident-card.ts`.**
    - **Notice and groups.** They render after the evidence line, in the place of the fix.
    - **Request cards.** Each gets `[result]` (`incident().requests` matched by ref), `[itemNoun]` and `[dismiss]`, which is `{ref, key: view().key}` for the last request card when `view().dismissable`, else undefined.
    - **The actions row** shows when there is no request card and there is a panel or Dismiss: Show details (when there is a panel), then `app-incident-dismiss` (when dismissable).
    - **A compact card** draws, after the headline, one `app-result-band` per `view().results` (no Dismiss), then the actions row with Show details.
    - Update the doc.
17. **`web/src/app/chat/chat-panel.ts` and `chat-announcements.ts`.**
    - **Entries.** `entries()` shows an incident whose ref is in `Dismissals.refs()` with its payload's `state` as `closed`.
    - **`FOCUS_RULE` gains `whenGone`.** A lost item keyed `dismiss:<viewKey>` gives `[data-part="incident"][data-key="<viewKey>"] .headline` (with `CSS.escape`), else null.
    - **`chatAnnouncements`:**
      - It remembers, per incident, each request's band text as well as its state.
      - Through `announcementOf` (or a sibling in `incident-view.ts`) it gives, after the state's text, each band text that is new or changed since the last look. Nothing is given at first sight beyond 6.1's rule.
      - A change to `closed` of a ref in the dismissed set is recorded and not spoken.
18. **The web script tests:**
    - **To update:** `catalog.test.mjs`, `approval-view.test.mjs`, `incident-view.test.mjs`, `incident-sources.test.mjs`, `approval-sources.test.mjs`, `announce-focus-sources.test.mjs`, `chat-announcements.test.mjs` and `ux-strings.test.mjs`.
    - **What they must cover:**
      - **The Result mapping:** every row of the table, with the count-of-one forms, the tones and icons, and `undefined` with no result.
      - **The card:** the notices and groups (a dated time included); Dismiss visibility for every state; the placement (band, status row, actions row; last card only); the compact bands.
      - **Speech:** a result announced once, and no announcement for the page's own Dismiss.
      - **The pins:** the chat panel's rule with `whenGone`; `incident-dismiss.ts` among the speakers; the band and Dismiss in the source pins; and that `dismissIncident` posts `{}` only.
    - **The case lists (DW-315), in `web/scripts/playwright-projects.test.mjs`** (its `titlesOf`): the `floor` project holds I1 and A1 and none of I2-I11 or A2-A10, and the `answers` project holds each of I2-I11, A2-A10, X1-X10 and C1-C10.
19. **The e2e helpers.**
    - **`web/e2e/support/iris.ts` gains:**
      - `useIncidentManagerDouble()` and `restoreIncidentManager()`, which run `IncidentManagerDouble.Use()`/`Restore()` and throw on an error status;
      - `doubleCommands(ref)` → `[{verb, session, origin}]`;
      - `incidentState(ref)` → the row's `State`;
      - `seedIncident`'s owner may also be `{sessionRef}` (for `seedOtherSession`'s session), as `seedApproval`'s `ApprovalOwner` is.
    - **`web/e2e/support/approvals.ts`:** `incidentOf` takes each request as `{ref, state?, result?}` (Rule 2: extend; `pending` and no result by default), and its header no longer says the floor spec keeps its own copies.
20. **DW-315: `web/e2e/answers/incident-card.spec.ts` and `approval-card.spec.ts`** (moved; the `answers` project, so `live:answers`).
    - **What moves:** I2-I11 move from `floor/incident.spec.ts`, and A2-A10 from `floor/approval.spec.ts`, with their file-level settings, helpers and imports.
    - **The changes:** `KIND = 'ANSWERS'`, and an `open()` that signs in as ANSWERS with `signIn` (as `answers.spec.ts` L61-68) and keeps the floor's state checks (demo mode, UTC zone). Nothing a case asserts changes, apart from words in messages that say "floor".
    - **The floor:** `floor/incident.spec.ts` keeps only I1 and `floor/approval.spec.ts` only A1 (both `@browsers`, in all three engines), with only the helpers they use. Update both headers (where the other cases went, and why).
21. **`web/e2e/answers/close-loop.spec.ts`** (new; project `answers`; Chromium; `timezoneId` UTC; the real clock).
    - It runs cases C1-C10 under Verification.
    - **Lifecycle:** `test.beforeAll` calls `useIncidentManagerDouble()` and `test.afterAll` calls `restoreIncidentManager()`.
    - **Per case:** each case seeds its own rows (`seedIncident`, `seedApproval`, `seedCheck`), publishes its payloads (`publishIncident`) and events (`sinkEvent`), and removes everything in `finally` (`cleanFixtureRows`, `dropPhone`, its check).
22. **`docker/tests/test-answers.sh`** (Epic 6's own): the PASS line and the header name the answers project's cases (6.3's X1-X10, 6.1's I2-I11, 6.2's A2-A10 and 6.4's C1-C10). Nothing else changes.
23. **`web/e2e/demo-path/05-approval.spec.ts`** (REL-2; the README account; `@fixtures`, as 6.3's test is).
    - **The new test.** Add "Fixing, then "All 50 orders went through." and Resolved, on fixtures for Lane A's result path":
      1. It raises and answers as the first test does.
      2. It publishes R `fixing` with A `executing` and expects the chip Fixing and "Repairing and resending 50 orders…".
      3. It publishes R `resolved` with A's result {total 50, resent 50, completed 50} and expects the band "All 50 orders went through.", "Recorded in the IRIS audit log." and the chip Resolved.
      4. It sends the `result` notification and expects the phone's message "All 50 orders went through.".
    - **The skip.** L68 becomes `notBuilt('Fixing, then "All 50 orders went through." and Resolved, from the real fix (FixExecutor and IncidentManager)', '11.1')`.
    - Rows and phone messages are removed in `finally`.

**Acceptance Criteria:**
- **AC1 (results):** Given an `incident` payload whose `requests` give a request a `result`, when the card renders or updates, then that request's card shows one band beneath its answered status:
  - **The band:** `result-success` with `circle-check` only for all-through; `result-partial` with `triangle-alert` for failed again, skipped, both, interrupted or couldn't start; `result-partial` with `clock` for still resending.
  - **Its texts:** the catalog's text by the Result mapping, count-of-one forms included, with "Recorded in the IRIS audit log." beneath in caption.
  - **Between requests:** one request's band never replaces another's.
  - **Still resending** shows while the request is `executing` and is replaced in place by the final result.
  - **The chip** is the payload's `state`.
  - **Speech:** each new or changed band text is announced once (C1-C4, `approval-view.test`, `chat-announcements.test`).
- **AC2 (the result on the phone):** Given a `result` notification for the session in demo mode, when `SimPhoneOut` handles it, then the phone shows one new message with `Render(key, slots, "phone")` (the same text as the band) and no Approve or Reject. The request's message is not edited (`Test.Demo.SimPhoneOut`, C1).
- **AC3 (rejected and expired):** Given a request rejected or expired that leaves the incident Open, when its card renders, then:
  - it shows "Rejected from {channel} at {time}. Nothing was changed." or "Expired at {time}. Nothing was changed." in place of the buttons;
  - the card keeps the attention bar and offers Show details and Dismiss at the right end of the last request's status row;
  - in demo mode Break the feed stays inactive until the incident is dismissed.

  (C4, C5, C6, `Test.Web.DismissApi:TestBreakFeedAvailableAgain`.)
- **AC4 (fallback and no-fix):** Given a fallback incident, or a no-fix one (with a known or an unknown cause), when it arrives:
  - **The card** is Open (with the Fallback flag for a fallback). It shows the notice sentence (the reason's text; for no fix, the cause and the evidence line first), "Failures:" and one line per group, with no fix and no request card, and offers Show details then Dismiss.
  - **The phone** shows the catalog's notice with no buttons.
  - **Speech:** the announcement ends "No fix proposed.".

  (C7, C8, `incident-view.test`, `Test.Demo.SimPhoneOut:TestFallbackAndNoFixWording`.)
- **AC5 (Dismiss on the page):** Given a resolved incident or an Open one, when the user presses Dismiss, then:
  - **The call:** the page posts `{}` to `POST /api/v1/incidents/:ref/dismiss` under the busy rule.
  - **On 200:**
    - the card compacts in place to its headline and each request's band, with chip Closed, the border-strong bar and Show details;
    - focus moves to the compacted headline, and nothing is announced;
    - for an open Orders incident, the Break the feed button becomes available within one live update.
  - **On a failure** the card is unchanged, with the busy notice after 10 s or the reply's message announced once.
  - **Visibility:** Dismiss never shows while awaiting approval, while fixing, or on a closed card.

  (C1, C5, C10, `incident-view.test`, `incident-sources.test`.)
- **AC6 (the route, AD-1 and AD-15):** Given a visible incident, when its session posts the dismissal, then the route submits a `Dismiss` command for the CSP session (never the body's) with origin `web_user` through `Commands.Submit` to `CommandsIn` and on to `IncidentManager` as an `IncidentCommand` `dismiss`, synchronously.
  - **What it leaves:** one production message tagged with the session's TraceRef; no Turn and no `chat.message`.
  - **The answers:** 200 `{"result":"done"}`; 409 `not_dismissible` with the owner's message or the fallback text; 501 `not_built` for a stub owner; 500 `server_error` for a failure.

  (`Test.Web.DismissApi`, `Test.Web.Api:TestUnseenRefIs404`, C5.)
- **AC7 (cross-session, a required CI check: FR-15, AD-4, AD-22):** Given another session's incident (and an unnoticed, `eval`, unwatched `instance` or unknown one), with the online-demo flag set or not, when a session posts its dismissal, then the answer is 404 `not_found` with the error body before anything is submitted. The incident is unchanged and IncidentManager gets nothing.
  - **Where it runs:** `Test.Web.DismissApi:TestOtherSessionsIncidentIs404` in shard `lane-b` (CI group `image`), and C10's real HTTP call in `live:answers` (CI group `browser`).
- **AC8 (closed by IncidentManager):** Given a card, when an `incident` payload with `state` `closed` arrives, then the card compacts in place to its headline and each request's band, and a later incident with a new Ref opens a new card (C9).
- **AC9 (the fixture IncidentManager, AD-29):** Given the double behind IncidentManager, when it gets `dismiss`, then it applies AD-15's dismiss rows and publishes the closed full view. Its `closeForReplay` and `closeQuiet` are unchanged (`Test.Web.DismissApi`, `Test.Demo.BreakFeedProduction` still green).
- **AC10 (DW-315):** Given the move, when the units run, then:
  - `live floor` holds no I2-I11 or A2-A10, and I1 and A1 still pass in Chromium, Firefox and WebKit;
  - `live answers` runs the moved cases as the ANSWERS user with the same assertions;
  - both units pass inside their 540 s local deadline, with the measured times recorded.

  - [ ] DW-315: move 6.1's I2-I11 and 6.2's A2-A10 into `live:answers`, and keep I1 and A1 (`@browsers`) in the floor for cross-engine coverage (Tasks 20 and 22).
- **AC11 (DW-105):** Given a run of `Test.Core.ConversationTurns`, when it ends, then no `Ens_Util.Log` row of SourceClass `OcuTalon.Test.Core.ConversationProbe` written during the run remains.
  - [ ] DW-105: `ConversationTurns` removes its probe's log rows in `OnAfterAllTests` (Task 7).
- **AC12 (REL-2):** Given the demo-path unit, when step 5 runs, then "Fixing, then All 50 orders went through. and Resolved" passes on fixtures (`@fixtures`), and the real path stays `notBuilt(..., '11.1')` (`live demo-path`).

## Spec Change Log

## Review Triage Log

## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- **AD-1** (L99-110): the dismissal is a command submitted only through `Commands.Submit` with the origin from the authenticated context (`web_user`), and REST writes nothing itself.
- **AD-4** (L155-177) and **AD-13** (L366): the session comes from the CSP session. `Ownership.Incident` gives the 404, and the route takes no `SessionRef` from the client.
- **AD-11** (L314-328): the request states; an expired request can't be answered (6.2's 409).
- **AD-12** (L330-343):
  - the `incident` payload is the full view keyed by Ref, with `requests[].result`;
  - Break the feed's availability comes only from `Guide.Compute`, recomputed when `incident` is published.
- **AD-15** (L408-447):
  - the transition table: `dismiss` only from `resolved`, or from `open` once noticed; refused otherwise;
  - results per request; the chip follows `state`;
  - REST dismissals arrive through CommandsIn.
- **AD-16** (L450-463): the result's fields; couldn't start is `Resent` 0 with a reason; one final result per run, after an in-progress one.
- **AD-22** (L585-608): a cross-session dismiss is a required CI check, and the tests are CI units.
- **AD-26** (L737-755): CommandsIn's Join tags the dismissal with the session's TraceRef.
- **AD-29** (L777-792): fixtures and a fixture IncidentManager stand in for Lane A until Epic 11.
- **AD-32** (L853-863): `result` is its own kind, rendered only by `*Out` operations and the page, never with buttons.
- **AD-33** (L865-874): `incident` has one publisher, the IncidentManager item. In tests that item is the double, and the e2e helper stands in as 6.1 established.
- **AD-14** (L396-406): the Delivery rows of the phone.
- **Conventions:** REST (a new 409 code, V1), Live events, Notice cards, Announcements and focus, Text OcuTalon sends, Times, Tests.
- **No AC contradicts an AD's Rule.**

**Rule 5:** no NFR of this story is unmeasurable or contradictory. NFR-9's bounds are 6.3's (`live:answers` X2, X3 and X8). 6.4's live updates ride on the same polling, and the busy rule's 10 s is pinned by C10.

**Ruling Q2 (given in advance by the orchestrator), `Test/Web/Api.cls`.** In `TestUnseenRefIs404`, 6.4 replaces only the visible-incident `DismissIncident` loop (L683-687) and the incident half of the method's doc (L644-645), as Task 4 says. The route's own tests are in the new `Test.Web.DismissApi`. The loop is exact (501 and the body) while `Watch.IncidentManager` is a stub on this branch, and not-404 once Epic 5's real owner is merged. So it stays true across the merge, and it removes the stub's error log rows that the dismissal now causes (Rule 19).

**Contended edits pending the orchestrator's ruling:** none. The DW-315 route below needs no edit of `ci/units.sh` or `docker/tests/test-demo-path-gate.sh`.

**Result mapping** (page; the first matching row wins; `count` = `total`, `itemNoun` = the incident's):

| Condition on `requests[i]` | Key | Slots | Tone, icon |
| --- | --- | --- | --- |
| `state` `executing` | `result.stillResending` | count, itemNoun, completed | partial, `clock` |
| `interrupted` > 0 | `result.interrupted` | count, itemNoun, completed, remaining = total − completed | partial, `triangle-alert` |
| `resent`, `completed`, `failedAgain` and `skipped` all 0, and `reason` set | `result.couldNotStart` | reason | partial, `triangle-alert` |
| `failedAgain` > 0 and `skipped` > 0 | `result.failedAndSkipped` | count, itemNoun, completed, failedAgain, failReason = reason, skipped | partial, `triangle-alert` |
| `failedAgain` > 0 | `result.failedAgain` | count, itemNoun, completed, failedAgain, failReason = reason | partial, `triangle-alert` |
| `skipped` > 0 | `result.skipped` | count, itemNoun, completed, skipped | partial, `triangle-alert` |
| otherwise | `result.allThrough` | count, itemNoun | success, `circle-check` |

- **Why the page maps.** The payload carries the fields, not a key (Story 0.5's fixed contract, Lane A's). So the page maps the fields, and Lane A's producers of the phone's `result` notification (Stories 7.3, 7.5 and 30.5) must pick the same key from the same fields. That is a convention independent builders could drift on. **Spine note for the runner (Rule 20):** record it as a Conventions row "Result texts", or tell those stories in their inbox. It is not a veto item: no AD's Rule changes.

**Decided in-stage:**
1. **DW-315's route.**
   - **What moves.** I1 and A1, the only `@browsers` cases of the two files, stay in `live floor`, which already runs them in Chromium, Firefox and WebKit. The other 19 cases move to `live:answers`. That keeps the cross-engine coverage the item asks for with no change to `ci/units.sh`, the Playwright projects or `playwright-projects.test`.
   - **The rejected option.** Move all 21 and add `answers` to `FIREFOX_WEBKIT_UNITS`, with `answers-firefox` and `answers-webkit` projects. Why not:
     - it turns `docker/tests/test-demo-path-gate.sh` L362 red (contended, Epics 13/15; it pins the browser group's install sequence);
     - it changes `playwright-projects.test` L104;
     - it adds about 30 to 40 s of Firefox and WebKit runs to the larger unit.

     To reverse: move the two cases and wire those three places, after a ruling on L362.
   - **The estimates** (inference, from 6.1 to 6.3's measured times):
     - `live floor`: from 491-527 s to about 400-420 s;
     - `live answers`: from 222 s to about 410-450 s of 540 (19 moved cases about 115 s, C1-C10 about 80-100 s, the double's swap about 10 s);
     - the CI `browser` group: from about 21-22 min to about 26-30 min, inside REL-4's 35, with `shards` about 4-5 min shorter. Unit-time ratios on the CI hosts range 1.2 to 2.9 (Rule 21's runs).
   - **The threshold.** If `live answers` measures over 480 s locally, the implement stage records it and the runner rebalances (Rule 21).
2. **Where Dismiss sits.** DESIGN L823 and L826, and the mockups `states.html` A4 L462 and A5 L479: after Show details.
   - The page shows it on `resolved` and `open` states only. The server's refusal (409) covers a stale page.
   - Its accessible name is its visible text, "Dismiss", inside the incident card that its headline labels. No new name text.
3. **The page compacts on the 200** through `Dismissals`, before the owner's `incident` event arrives. The 200 is the owner's synchronous answer (AD-15), and the event then agrees. One host, the chat panel, keeps focus with `whenGone` to the headline, so the reply-first and event-first orders both land there.
4. **The user's own Dismiss isn't announced.** Focus moves to the headline, which reads it (UX L431's "unless it just took focus", applied to Dismiss). Any other close is announced as 6.1 does.
5. **Dismiss failures show the server's message** (409: the owner's or `MESSAGENOTDISMISSIBLE`; 404: "OcuTalon has nothing at this address."). With no answer, they show `ServerButton`'s busy notice. No page text is added.
6. **A `result` is a new phone message, not an edit.** EXPERIENCE L299 lists results among the phone's notifications. L797 doesn't say "edited" for a result, and L302's edit is the answered line only. The request's message keeps its answer line.
7. **Still resending uses `result-partial` with `clock`.** DESIGN L826 names only full success and partial; in-progress is not a success. `clock` exists (expired's icon). To reverse: one row of the mapping.
8. **The card's notices are page texts from EXPERIENCE L803-828.** The catalog's `incident.fallback` and `incident.noFix` texts hold the headline and the phone's last line, so the page can't take them whole. No `web` form is added (Lane A's class; `TestWebWording`).
   - The unknown-cause form is chosen by `causeCategory` `unknown` (AD-15: no fix includes `unknown`).
   - The group line's time takes the headline's time form, with "at "→"on " before a dated time, as the catalog does.
9. **A compact card draws the bands from `incident().requests` directly** (no request card). A rejected or expired request has no band, so a dismissed rejected incident compacts to its headline (EXPERIENCE L647: "the headline and each request's result").
10. **The double's dismiss** follows AD-15's dismiss rows and republishes the newest published payload with `state` `closed`, because Lane A's IncidentManager publishes full views. Only `dismiss` changed, so Story 4.3's `closeForReplay` tests stand.
11. **The e2e swaps the double per spec file** (`close-loop.spec.ts`'s `beforeAll`/`afterAll`), not in `test-answers.sh`. The state it changes is set up and put back by the spec that needs it (Rule 19). Workers are 1, so no other file runs meanwhile.
12. **No Task 0.** The route uses `Commands.Submit` in the REST process as `AnswersIn.FromPage` does (6.2, measured under the web roles by `Test.Core.AnswersInWebRoles`). The same privileges are enough (inference), and C5 and C10 prove it on every run.
13. **Not split.** The ACs interlock: Dismiss sits on the band or the status row, and every ending needs it. Moving ACs to a new story is a veto item. `multiple-goals` and `oversized` are recorded.

**Veto-window choices** (the runner files them):
- **V1. A REST code and a text.** A refused dismissal answers 409 `not_dismissible` with the owner's `CommandResult.Message`, else the new text "OcuTalon can't dismiss this incident now. Nothing was changed.". A done one answers 200 `{"result":"done"}`.
  - **Rejected options:**
    - reusing `incident_in_progress`: Break the feed's code, whose text tells the user to dismiss;
    - a generic 409 `conflict`: says nothing;
    - 200 for a refusal: dishonest.
  - **Reversing it:** one parameter and one branch of `DismissIncident`, plus `TestRefusedIs409`.
  - **Against the ADs:**
    - AD-15 is kept: refusal stays refusal.
    - AD-1 is kept.
    - The spine's REST convention row (L921) gains `409 not_dismissible` and the dismiss route's 200 body. That is an addition, not a change to an AD's Rule; the runner writes it under Rule 20.

**Files and footprint classes** (paths under `src/ocutalon/cls/OcuTalon/` for classes):
- **Footprint:**
  - `Test/Core/ConversationTurns.cls`;
  - `web/src/app/incidents/{incident-card,incident-view}.ts`, plus `dismissals.ts` and `incident-dismiss.ts` (new);
  - `web/src/app/approvals/{approval-request-card,approval-view}.ts`, plus `result-band.ts` (new);
  - `web/src/app/chat/{chat-panel,chat-announcements,decision-strip}.ts`;
  - `web/e2e/demo-path/05-approval.spec.ts`.
- **Shared by entry:** `Web/Api.cls` (its own route, handler and message); `web/src/app/api/{api-client,api-types}.ts` (`dismissIncident`, `DismissBody`).
- **Contended, ruled by Q2:** `Test/Web/Api.cls` (L644-645 and L683-687 only).
- **Contended, new file:** `Test/Web/DismissApi.cls`.
- **Extension** (uncontended, Lane B):
  - `Channel/SimPhone/Out.cls`, `Test/Demo/SimPhoneOut.cls` and `Test/Demo/IncidentManagerDouble.cls`;
  - `web/scripts/catalog.mjs`, `msg/catalog.ts` (generated), and the `web/scripts/*.test.mjs` of Task 18;
  - `web/e2e/support/{iris,approvals}.ts`;
  - `web/e2e/floor/{incident,approval}.spec.ts` (trimmed; Epic 6's own files; no new floor case);
  - `web/e2e/answers/{incident-card,approval-card,close-loop}.spec.ts` (new);
  - `docker/tests/test-answers.sh` (Epic 6's own).
- **Not edited:** `ci/units.sh`, `web/playwright.config.ts`, `web/package.json`, `docker/tests/test-demo-path-gate.sh`, `Test/Core/CommandsInProduction.cls`, `Core/Commands*.cls`, `Core/CommandsIn.cls`, `Demo/Guide*.cls`, and every Lane A class.
- **The runner may append** the measured unit times to Rule 21's CI section (decide).

**Extend, don't copy (Rule 2):**
- **The route's tests** reuse `Test.Web.Api.Written` and `Test.Web.StubRequest`, and follow `Test.Web.BreakFeedApi` and `Test.Demo.BreakFeedProduction`. Nothing is copied.
- **Dismiss** is `ServerButton` (ghost) plus a notice; `AnswerPress` isn't reused, because it is two-button, approval-specific and channel-bound.
- **`resultView`** extends `approval-view.ts` beside `statusOf`. `result-band.ts` is one component used by the request card and the compact card.
- **The reason text** is decision-strip's lookup, exported.
- **The double** is Epic 4's, extended; the item swap is `RunnerFixture.UseItemClass`.
- **`incidentOf`** in `support/approvals.ts` takes optional states and results instead of a new helper.
- **The log cleanup** has the shape of `Test.Core.BridgeSink` L69.
- **Kept as copies:** the moved floor specs' local helper copies (`floor/approval.spec.ts` L40-119, now in `answers/approval-card.spec.ts`). DW-311 (wontfix-accepted) stands: the move changes no assertion.

**Integration ACs (Rules 1 and 2):**
- The page's Dismiss (consumer of the route) closes a real incident row through CommandsIn and the IncidentManager item. The card compacts and the guide's Break the feed becomes active (C5).
- `SimPhoneOut` (consumer of `result` notifications) shows the result message (AC2, C1).
- The new `Dismissals` and `app-result-band` are consumed in this story by the chat panel and the two cards (C1, C5, C9).

**Consumes:**
- 6.1's incident card and announcements;
- 6.2's request card, statuses, route patterns and `answered.*` catalog;
- 6.3's phone, `live:answers` and `support/approvals.ts`;
- 4.3's `IncidentManagerDouble` and 4.2's `Guide.Compute`;
- 2.3's `Commands.Submit`/`CommandsIn`, 2.2's `Ownership.Incident` and 2.12's focus rule and Announcer;
- 0.9's catalog and renderer;
- `Test.Agent.RunnerFixture.UseItemClass`.

**Consumed-by:**
- Epic 5 / Epic 11: the real IncidentManager answers `dismiss` (Ok, or a refusal with `Message`) and publishes the closed full view, replacing the double.
- Stories 7.3, 7.5 and 30.5: the `Result` fields are read by the Result mapping, and their `result` notifications reach the phone.
- 12.x: Telegram's result message.
- 31.2: tool-call `result` notifications through `NoticesIn` now render on the phone.
- 16.9: Approve, Reject and Dismiss at the caps.

**Ledger inbox:**
- **DW-315** is addressed by Tasks 20 and 22 and AC10, with the route above (Decided in-stage 1).
- **DW-105** is addressed by Task 7 and AC11.
- No entry is declined.

**Known items, not re-filed:**
- DW-292: after a reload, the snapshot's incidents carry no `requests`, so the bands show only after the next event.
- DW-294, DW-299 and DW-310.

## Verification

`<B>` stands for `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=6 stage=implement'`.
- **Tags:** fresh `e6s4i`, warm `e6s4iw`. Run `<B> OCUTALON_RUN_TAG=e6s4iw ci/warm.sh up` once, and `ci/warm.sh down` at the end, also after a failure.
- **Calls:** one command per foreground call, with `timeout: 600000`. One `iris_execute_tests` per message, with `server` `ocutalon-slot-b` and namespace `OCUTALON` on every IRIS MCP call. Slot B is for loading, compiling and exporting only.

**Browser cases** (`web/e2e/answers/close-loop.spec.ts`; user ANSWERS; fixture values as in the Matrix):
- **C1, all went through, then Dismiss:**
  1. R is published `fixing`, then `resolved`, with A's result: the band (token colours of `result-success`, the `circle-check` icon, the text) and the audit line beneath it.
  2. "All 50 orders went through." is announced exactly once.
  3. The ghost Dismiss sits at the band's right end.
  4. The `result` notification gives a new phone message with that text and no buttons; A's request message keeps its line.
  5. A press on Dismiss compacts the card to the headline and the band, and focus is on the headline.
- **C2, partial results:** A's result is updated in place through failed again, skipped, both, interrupted and couldn't start (the fixture reason text). Each is the exact text with the `result-partial` colours and `triangle-alert`, and there is one band throughout.
- **C3, still resending, then final:** the band with `clock` and the fixing line, with no Dismiss. Then the final result replaces the text in the same band, and Dismiss appears. Each text is announced once.
- **C4, two requests:** A's band and B's buttons, the chip Awaiting approval, and no Dismiss. B is then rejected on the card (the real answer) and R published `open`/`rejected`: B's status, and Dismiss at the end of B's status row; A's band is unchanged.
- **C5, rejected, then Dismiss and Break the feed:**
  - **Setup:** S watches Orders (`seedCheck`), and R is an Orders incident `open`/`rejected` with A rejected.
  - **Before:** the Break the feed button is `aria-disabled`.
  - **The press:** focus on Dismiss and Enter. Dismiss goes busy, then the card compacts: the chip Closed, the border-strong bar, no request card and no Dismiss. Focus is on the headline, and no "Closed" announcement is made.
  - **Through the helpers:** `doubleCommands(R)` is one `dismiss` with origin `web_user`, and `incidentState(R)` is `closed`.
  - **After:** the Break the feed button is active within `ONE_UPDATE_MS`. A reload shows R compact.
- **C6, expired:** the status with `clock`, Dismiss at the end of the status row after Show details, and no Approve or Reject.
- **C7, fallback:** the chip and the Fallback flag, the notice, "Failures:" and the group line, no fix, Show details then Dismiss, and the announcement "Incident: … No fix proposed.". The phone's `incident.fallback` message has the server's exact text and no buttons.
- **C8, no fix and unknown cause:** the cause, the evidence line, the no-fix sentence and the groups. A second card with `causeCategory` `unknown` has the unknown sentence and no cause. The phone's `incident.noFix` message has no buttons.
- **C9, closed by IncidentManager:** R is published `closed` with A's result. The card compacts in place with the band, Show details and no Dismiss. A new ref of the same cause gets a second card.
- **C10, failures and the cross-session 404** (AC7):
  - `post` of another session's incident (`seedOtherSession`, `seedIncident`) gives 404 with the `not_found` body; the row is unchanged and `doubleCommands` is empty.
  - Through `page.route`:
    - a 200 `{"result":"done"}` fulfilled by the route (so no server event follows) compacts the card and focuses its headline: the page's own path;
    - 409 `{code: not_dismissible, message: "zz refused"}` shows the message, announced once, with the card unchanged;
    - 500 shows its message;
    - a held reply restores Dismiss after 10 s with the busy notice shown and announced.

**Commands:**

`(loop)`:
- `npm --prefix web run catalog`, then `node web/scripts/catalog.mjs --check` and `node web/scripts/payloads.mjs --check`: expected, exit 0.
- `npm --prefix web test`: expected, every node test passes.
- `npm --prefix web run lint`: expected, exit 0.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s4iw ci/iris.sh class OcuTalon.Test.Demo.SimPhoneOut`: expected, `CLASS ... passed`.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s4iw ci/iris.sh class OcuTalon.Test.Web.DismissApi`: expected, passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s4iw ci/iris.sh class OcuTalon.Test.Web.Api`: expected, passed.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s4iw ci/iris.sh class OcuTalon.Test.Demo.BreakFeedProduction`: expected, passed (the double's other verbs are unchanged).
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s4iw ci/iris.sh class OcuTalon.Test.Core.ConversationTurns`: expected, passed. **Manual check:** then, in the warm stack's IRIS (`docker exec <its iris container> iris session IRIS -U OCUTALON`), `SELECT COUNT(*) FROM Ens_Util.Log WHERE SourceClass = 'OcuTalon.Test.Core.ConversationProbe'` is 0.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s4iw ci/iris.sh class OcuTalon.Test.Core.CommandsInProduction`: expected, passed (unchanged; a regression check of the Dismiss route through CommandsIn).
- `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh build`: expected, the image and the bundle build. Run it before each browser run that should see changed web code.
- `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh live answers`: expected, PASS with X1-X10, I2-I11, A2-A10 and C1-C10. Record the call's time against 540 s.

`(once)`:
- `bash ci/checks.sh`: expected, exit 0 (storage, ci-config, ci-changes, demo-path-gate, ASCII).
- `bash docker/tests/test-web-build.sh`: expected, passes.
- `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh shard lane-b`: expected, every class passed (`Test.Web.DismissApi` and `Test.Web.Api` among them).
- `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh shard lane-a`: expected, every class passed.
- `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh live floor`: expected, PASS with I1 and A1 in three engines and no case added. Record the time against 540 s.
- `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh live demo-path`: expected, PASS. 05's two fixture tests pass, and the rest stays skipped for 11.1.
- `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh live sign-in`: expected, PASS with an unchanged count. The chat panel's focus rule and announcements are shared.
- `<B> OCUTALON_RUN_TAG=e6s4iw ci/warm.sh down` and `<B> OCUTALON_RUN_TAG=e6s4i ci/iris.sh teardown`: expected, only this stage's projects are removed.

**Shared surfaces:**
- **SimPhoneOut's kinds** (`result` is a message): `Test.Demo.SimPhoneOut` `TestOtherKindsRecordOnly`. I5 (moved) sends `result.allThrough` with `{}` slots, which now logs a render error only.
- **The dismiss route's answer for a visible incident:**
  - `Test.Web.Api:TestUnseenRefIs404` (Q2);
  - `web/e2e/api/api.spec.ts` BY_REF (404, unchanged);
  - `Test.Core.CommandsInProduction` (the stub row, unchanged).
- **IncidentManagerDouble's `dismiss`:** `Test.Demo.BreakFeedProduction` (other verbs only).
- **The generated catalog** (`result.*`, `audit.recorded`, `one` forms, `noun`): `catalog.test.mjs`, `ux-strings.test.mjs`.
- **`INCIDENT_TEXTS` and `IncidentView`:** `incident-view.test.mjs` (deepEqual), `ux-strings.test.mjs`.
- **The card's and the request card's templates:** `incident-sources.test.mjs` (the actions-row regex), `approval-sources.test.mjs` (the request `@for` regex, the answer row).
- **Focus and speech:**
  - the chat panel's `FOCUS_RULE` (pinned in `announce-focus-sources`);
  - the speakers list (`incident-dismiss.ts`);
  - `chat-announcements.test.mjs` (the remembered per-incident view).
- **The floor and answers units' case lists:**
  - `floor` loses I2-I11 and A2-A10;
  - `playwright-projects.test` (at least 37 floor titles; `e2e:answers` from disk);
  - the PASS line of `test-answers.sh`.
- **The guide:** a dismissal publishes `incident`, so `guide.state` follows (C5, `TestBreakFeedAvailableAgain`).
- **The production's IncidentManager item** while `DismissApi` or `close-loop.spec.ts` runs: swapped and restored by each.
- **The Ens log:** ConversationTurns' probe rows, and the stub's error rows from the Q2 loop.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Planned mutations (Rule 19).** Apply each, observe red, revert, confirm that `git status --short` and `git diff --stat` are unchanged, and record it as `mutation: ... -> ...`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | `resultView` checks `skipped` before `failedAgain` | `approval-view.test` (mixed row); C2 |
| 1 | the band reads the first request's result for every card | C4 (A's band on B), `incident-sources.test` |
| 1 | announced band texts not remembered (each update re-announces) | `chat-announcements.test`; C3 (twice) |
| 2 | `result` left out of `CARDKINDS` | `Test.Demo.SimPhoneOut` (`TestResultIsAMessage`); C1 |
| 3 | `dismissable` false for `open` | `incident-view.test`; C5, C6 |
| 4 | the no-fix notice ignores `causeCategory` `unknown` | `incident-view.test`; C8 |
| 5 | `FOCUS_RULE` without `whenGone` (focus to main) | C5 (focus on the headline) |
| 5 | `Dismissals.add` not called on 200 (the card waits for the event) | C10 (a 200 fulfilled by `page.route`, with no event, leaves the card uncompacted) |
| 6 | the route skips `Submit` and answers 200 | `Test.Web.DismissApi` (`TestOwnOpenIncidentCloses`: the row is still open) |
| 6 | an owner refusal mapped to 500 | `TestRefusedIs409` |
| 7 | the route submits before the Ownership check | `TestOtherSessionsIncidentIs404` (the double recorded a command); C10 |
| 8 | the compact card hides the bands | C9, `incident-view.test` |
| 9 | the double's dismiss publishes nothing | `TestOwnOpenIncidentCloses` (no closed event); C5 (Break the feed stays inactive) |
| 10 | I3 left in `floor/incident.spec.ts` as well as moved | `playwright-projects.test` (the floor holds a moved case) |
| 11 | the `OnAfterAllTests` delete removed | the manual count above 0 |
| 12 | 05's resolved publish removed | `live demo-path` red |

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

- **Planning only** (halt after planning). The spec was checked against the READY FOR DEVELOPMENT standard; no code changed.
- **Inputs used:**
  - the committed `epic-6-context.md`, reused and not recompiled;
  - 6.3's spec, for continuity;
  - the spine's AD-1, 4, 11, 12, 13, 14, 15, 16, 22, 26, 29, 31, 32 and 33, and the Conventions table;
  - EXPERIENCE and DESIGN's incident, result and Dismiss rules.
- **Version-control check at dispatch:** the one dirty path was the runner's own `cycle-log-epic-6.md`, a `lead_error` line written 12 s after the spawn. No bookkeeping commit was missed and the plan stage doesn't touch that file, so planning went on (Decided in-stage). The plan stage committed nothing.
- **For the runner:**
  - **Veto V1:** 409 `not_dismissible` and its fallback text, and the dismiss route's 200 body. Under Rule 20 the spine's REST convention row needs them.
  - **Spine note:** the Result mapping as a Conventions row, Rule 20.
  - **Contended edits:** none pending (ruling Q2 applied as given).
  - **Footprint extensions:** listed under Design Notes › Files and footprint classes.
