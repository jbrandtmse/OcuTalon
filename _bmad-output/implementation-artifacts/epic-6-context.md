# Epic 6 Context: Incidents and approvals you can answer from the page

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make the incident something the user can act on. Each incident shows as one live card in the web chat and as a notice on the simulated phone, with its count, cause, evidence, proposed fix and dry run, and one press of Approve or Reject answers it from either place. The first answer from any channel wins. Within seconds every other copy shows who answered, where and when, and its buttons stop answering. Every ending reads correctly and says plainly when nothing changed: a result, a partial result, a rejection, an expiry, a fallback, a no-fix notice or Dismiss. Nothing on the page can answer or dismiss another session's request. This is UJ-1's approval step. Lane B, on runner B; depends on Epic 4.

## Stories

- Story 6.1: Show each incident as one card in the chat
- Story 6.2: Approve or reject a fix from the web chat
- Story 6.3: Answer on the simulated phone and see every answer everywhere
- Story 6.4: Close the loop with results, rejections, expiry, fallbacks and Dismiss

## Requirements & Constraints

- **The first answer wins.** The answered status shows on the page within 2 s and on the phone within 5 s. Every copy shows the first answer, and no copy accepts a second. CI checks this against the mock on every run, and the rehearsal measures it over real networks. A late press shows "Already answered: approved from {channel} at {time}."
- **Who may answer:**
  - **Local or IPM install:** any signed-in session that can see the request through the ownership API (its own, or an `instance` incident's for a production it watches), whose IRIS user holds the bridge's approval role (`OcuTalonUser` by default).
  - **Online-demo flag set:** only the owning session, from any of its channels.
  - **Order of refusals:** a request the session can't see (or an unknown or cancelled ref) answers 404, whatever the body. A caller who may not answer gets 403 `not_allowed` with no payload, checked before any 409, so an answered or expired request pressed by a user without the role still gives 403.
  - **Cross-session attempts:** an answer or a dismissal aimed at another session's request or incident gets 404, the same as an unknown ref, and changes nothing. Both are required CI checks.
- **Not turns.** Approve, Reject and Dismiss each act on one press, with no confirmation and no dialog, and keep working at the message allowance limit. An answer creates no Turn, no `chat.message` and no allowance call. It leaves one production message (`AnswersIn` → `AnswerOps`, tagged with the session's `TraceRef`, so it shows in Visual Trace) and `Answer`'s Approval audit entry.
- **Busy and failure.** On a press both buttons go busy: a spinner, `aria-disabled` and `aria-busy` (never `disabled`), and repeat presses are ignored. If 10 s pass with no answer, they restore with the announced notice "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting." An answer that arrives later still shows. The phone uses the same rule.
- **Endings.** A rejected, expired, fallback or no-fix incident stays Open with Dismiss and Show details, and Break the feed stays inactive in demo mode until it is dismissed. A dismissal closes the incident synchronously; a resolved incident (or, with demo mode off, an Open one) also closes after 15 quiet minutes or by the replay rule. Either way the card compacts in place, and a later same-cause failure opens a new card.
- **Plain language.** Raw IRIS errors and item names appear only in the Show details evidence panel.
- **Layout floor.** At 1280×600 the incident card's headline, cause, dry-run count, Approve and Reject are visible without scrolling the chat. Today this holds only with the demo guide collapsed and no status banner (DW-299). The fix is the guide's compact height, which is Epic 16's area, not Epic 6's.
- **Test fixture users.** A test that creates an IRIS user runs only on a throwaway stack, behind a guard that refuses anywhere else. Its password is random and never logged, and teardown deletes the user even when a test fails (owner condition U-116; `Test.Core.AnswersInWebRoles` is the pattern).

## Technical Decisions

- **Build against Lane A's fixed contracts.**
  - Lane B builds against Story 0.5's payload contracts (`OcuTalon.Live.Payload.Incident`, `Approval` and the rest) and Epic 0's API signatures, using fixtures and doubles.
  - Epic 5 (`IncidentManager`, incidents) is live on another runner and unmerged. Epic 7 (fixes) has not started.
  - **Never build a Lane A class:** not `IncidentManager`, `Bridge.Approval`, `FixExecutor`, the `Incident` payload or the bridge tables.
  - **Until Epic 11 turns the real path on:**
    - fixture `incident` payloads are published through `Live.Publish`;
    - an `OcuTalon.Test.Core` double (`ApprovalDouble`) stands in for the Approval API and returns Epic 0's results;
    - a fixture `IncidentManager` answers `dismiss` synchronously and publishes fixture result payloads (6.4's tests).
- **Footprint.** Class paths are under `src/ocutalon/cls/OcuTalon/`.
  - **Classes:** `Core/{NoticesIn,AnswersIn,AnswerOps,CommandsIn}*.cls`, `Core/Msg/{Answer,AnswerResult}.cls`, `Channel/{SimPhone,WebChat}/Out*.cls`, `Data/Delivery.cls`, and `Web/Api.cls`. `CommandsIn` and `Web/Api.cls` are shared by entry.
  - **Tests:** `Test/{Core,Live}/**`.
  - **Web:** `web/src/app/{incidents,approvals,notices,chat,rail}/**`, `web/e2e/demo-path/0{4,5}-*.spec.ts`, `web/e2e/floor/{incident,approval}.spec.ts` and `web/e2e/answers/**`.
  - **6.3's footprint extensions (all Lane B):** `Live/Payload/Phone.cls`, `Data/SimMessage.cls`, `Test/Demo/SimPhoneOut.cls`, `web/src/app/{phone,devices}/**`, `web/e2e/support/**`, `web/playwright.config.ts`, Lane B's `ci/units.sh` region, and the unit script `docker/tests/test-answers.sh`. Report any new extension.
  - **Browser cases live in `live:answers`,** not `live floor`. It is `docker/tests/test-answers.sh` with Playwright project `answers` (`web/e2e/answers/`), in CI group `browser`, and ran 222 s of its 540 s local deadline at 6.3's smoke. Today `answers` is Desktop Chrome only: Firefox and WebKit runs exist only for the floor (`floor-firefox`, `floor-webkit`, grep `@browsers`; `FIREFOX_WEBKIT_UNITS="floor"` in `ci/units.sh`).
  - **Contended, not Epic 6's:**
    - `Core/BridgeSink*.cls` belongs to Epic 16. A test that drives it is Epic 6's work; a change to `BridgeSink` needs a ruling (6.3's DW-128 line in `Step` was ruled).
    - `Core/Trace.cls` and `README.md` are Epic 10's. Existing `docker/tests/**` files, such as `test-demo-path.sh` and `test-demo-path-gate.sh`, need a ruling.
    - `Test/Web/Api.cls`: in `TestUnseenRefIs404`, Story 6.4 may replace only the visible-incident `DismissIncident` loop (which expects 501 `not_built` today) and the incident half of its doc sentence (orchestrator ruling Q2, given in advance). Nothing else in that class.
  - **Generated files:** `web/src/app/live/payloads.ts` comes from `node web/scripts/payloads.mjs`, and `web/src/app/msg/catalog.ts` from `web/scripts/catalog.mjs`. Never edit either by hand.
- **The incident card reads only the `Incident` payload's fields.** Only `IncidentManager` publishes them.

  | Card part | Fields |
  | --- | --- |
  | Headline | `Count`, `ItemNoun` and `FirstAt` |
  | State chip and variants | `State`, `OpenVariant`, `Fallback` and `FallbackReason` |
  | Cause and evidence line | `Cause`, `CauseCategory` and `Element` |
  | Proposed fix | `FixSummary` |
  | "N more since the notice" | `Count` against `NoticeCount` |
  | Fallback and no-fix failure groups | `Groups` |
  | Each request card's state and result | `Requests`: `Ref`, `State`, and `Result` with `Total`, `Resent`, `Completed`, `FailedAgain`, `Skipped`, `Interrupted` and `Reason` |
  | Show details | `Evidence`, and `TraceTargets` (`diagnosis`, `sample`, `firstFailure`) |
  | Footer strip | `DecisionRef` |

  - **How payloads apply:** each one is the full view, keyed by `Ref`, and applied idempotently, so there is one card per `Ref`, never a duplicate.
  - **The snapshot** reads the session's incidents through the ownership API, which hides an incident until its `NoticedAt` is set. Its incident entries carry only the row-backed fields, not `Groups`, `Requests`, `Evidence` or `TraceTargets` (DW-292).
- **The dry run** is the request's stored `DryRun` JSON on `OcuTalon.Bridge.Data.ApprovalRequest`. Its keys are `affected`, `resend`, `leftOut`, `field`, `before`, `after` and `itemNoun`.
- **The state chip follows AD-15's transition table, never a single request:**
  - Fixing while a fix runs;
  - otherwise Awaiting approval while any request is pending;
  - otherwise the outcome of the request that finished last: Resolved after a finished fix, Open after a rejection or an expiry.

  The open variants (`fallback`, `no_fix`, `rejected`, `expired`) are stored beside the state. A dismiss is refused while the incident is awaiting approval or fixing.
- **The answer path as built** (Story 6.2, owner decision U-113). The spine's AD-11, AD-31, AD-32 and its incident and tool-call flow lines describe this path as built, with no "pending" wording (owner decision U-120).
  1. `POST /api/v1/approvals/:ref/answer` takes `{action, channel}`: action `approve` or `reject`, channel `web` or `phone`. The web card and the simulated phone both use this path, through one shared press class, `web/src/app/approvals/answer-press.ts`.
  2. `AnswersIn` checks the CSP session (never a `SessionRef` from the client) and refuses a call made inside a bridge context. It applies the rules on who may answer: 404 first, then 403. It then sends the answer synchronously, waiting up to 30 s, to the business operation `AnswerOps` (`OcuTalon.Core.AnswerOps`, Lane B). `AnswersIn` is its only sender, and `AnswerOps` refuses a message from any other source.
  3. `AnswerOps`' production job calls `OcuTalon.Bridge.Approval.Answer(Ref, Action, Channel, IrisUser, SessionRef)`.
     - The answerer comes only from the server-side session: the IRIS user from the `Session` row, and the session's 22-character Ref. Neither comes from the request body.
     - `Answer` still applies the row's `RequiredRole`.
     - The HostSink's `approval.answered` and `BridgeSink`'s fan-out run in that job. The fan-out goes to the owner, or to every watcher of an `instance` request. In the signed-in user's REST process the checked cross-owner reads fail, so the call must stay in the production job.
  4. **Responses:**
     - 200 is `{result: "done", approval}`.
     - 409 `already_answered` (the winner's action, channel and time) or `expired`. A 409 body carries the request's `approval` payload beside `error`, and its late-press and expired texts are rendered through `Catalog.Render`.
     - 403 `not_allowed` and 404 `not_found`.
     - 400 `bad_answer`: the action or the channel is missing or wrong.

     Every error body is a plain-English `{"error":{"code","message"}}`.
  5. Story 10.3 adds `AnswersIn`'s Telegram entry, which applies the same rules.
- **The dismiss path.** `POST /api/v1/incidents/:ref/dismiss` submits through `Commands.Submit` to `CommandsIn`, then to `IncidentManager` as an `IncidentCommand` `dismiss`, synchronously. `Submit` sets the command's origin from the authenticated context. Today the route answers 404 for an unseen ref and 501 `not_built` for a visible one; 6.4 builds the rest.
- **The notification contract.**
  - **Kinds:** every incident notice (with a fix, fallback or no fix) is kind `incident`, and its catalog key tells the variants apart. It carries the first request's `ApprovalRef`. Kind `approval` is only for a later request. `answered` and `result` notifications carry both `ApprovalRef` and `IncidentRef`.
  - **Rendering:** producers never render text. Each `*Out` operation renders through `OcuTalon.Msg.Catalog.Render(key, slots, channel)`, which picks the item noun's form from the `count` slot. Approve and Reject are added only for kinds `incident` and `approval` with `ApprovalRef` set, never for `answered` or `result`.
  - **`WebChatOut`:** for the kinds in `WebChatOut.INCIDENTKINDS` (`incident`, `approval`, `answered` and `result`), it records its `Delivery` row only and adds no notice card, because the incident card carries the notice.
  - **`SimPhoneOut`:** shows `incident` and `approval` notices with Approve and Reject. On an `answered` notification it finds the delivered message with `Delivery.FindByApproval(approvalRef, channel, ownerRef)` (an exact match that gives the newest row) and edits it in place. `SimMessage` and the `Phone` payload carry `ApprovalRef` and `Answer`, so an answered phone message survives a reload (veto U-121, kept).
  - **`NoticesIn`:** a real adapterless item in Core, not a stub. It receives `BridgeSink`'s notifications asynchronously, joins the turn's thread through the bridge context's `ThreadSessionId` (never `Trace.Join`), and forwards each notification to `Notify`. `BridgeSink`'s own sends through it arrive with Stories 31.2 and 16.9.
- **Live events and the rail.**
  - `BridgeSink` is the only `approval` publisher. It publishes each `approval` event to the owning session. For an `instance` request it publishes to each session that `Session.Recipients` returns after `Ownership.ApprovalIncident`. A failed cross-owner read is logged and publishes nothing.
  - `BridgeSink.Step` also accepts a SessionBroken retry's item (`RetryItemId(running.ItemId)`), so a retried turn's `turn.step` reaches the stream (DW-128).
  - The rail lists pending requests by raised time, and an answered request leaves the list within one live update. `/state`'s rail holds pending requests only.
- **Conventions.**
  - **REST:** state-changing calls need `application/json`, `X-OcuTalon-Request: 1` and a matching `Origin`. No endpoint accepts a `SessionRef` from the client.
  - **Times, trace links and speech:** times are UTC ISO 8601, rendered only through `Data.Time`. Trace URLs come only from `Web.TraceLink`. The page speaks only through `Announcer`, and focus moves through `shared/focus-rule.ts`.
  - **Page texts:** the page's statuses and the busy rule read from the generated catalog (`web/src/app/msg/catalog.ts`).

## UX & Interaction Patterns

- **The incident card, top to bottom:**
  1. the state chip (a static pill: "Open", "Awaiting approval", "Fixing", "Resolved" or "Closed"), with the fallback flag if any, and the time;
  2. the headline in `headline` type with no final period ("50 orders failed since 14:12 ET");
  3. the cause sentence;
  4. the evidence line ("Data format change · order date · 50 failures grouped into this incident");
  5. the proposed fix, without the message's closing "Approve?";
  6. the approval request cards, in the order raised;
  7. the evidence panel, when expanded;
  8. a footer with the decision strip and its trace link.
- **The 4px bar:**
  - `attention` while a person is needed, including the fallback, no-fix, rejected and expired variants of Open;
  - `info-ink` while fixing, with the text "Repairing and resending 50 orders…";
  - `success-ink` when resolved;
  - `border-strong` when closed. A closed card compacts to its headline and result.
- **A pending approval request card:**
  - the label "Approval needed" and the action in the imperative;
  - the fixed-targets line, then the dry run;
  - one row with Approve (primary, first) and Reject (secondary), and Show details as a ghost button at its right end;
  - the expiry in caption.

  Inside an incident card there is no "Why:" line. Button names include the object: "Approve: repair and resend 50 orders".
- **Once a request is answered:**
  - the label becomes "Approval request";
  - the status replaces the buttons in the same row ("Approved from the web chat at 14:15", with no final period);
  - the fixed-targets line, the expiry and "Nothing has changed yet." go, and the dry run stays as a record;
  - if a button had focus, focus moves to the status line (`tabindex="-1"`).

  Channels read "the web chat", "the simulated phone" or "Telegram". On a local install with more than one user, the status names who answered.
- **Rejected and expired statuses:** "Rejected from {channel} at {time}. Nothing was changed." and "Expired at {time}. Nothing was changed."
- **The dry run block,** on `sunken`:
  - the "Dry run" label and a count line ("50 orders affected");
  - an example naming its field, as two rows labelled in text: "Before" (`mono`, `danger-ink`) and "After" (`mono`, `success-ink`);
  - the "Will resend" line, and "Nothing has changed yet." while the request is pending.
- **Result bands,** one per approved request, and one request's result never replaces another's:
  - `result-success` or `result-partial`, with the texts in EXPERIENCE.md › Incidents and Approvals › Results, including the count-of-one forms, the still-resending band (while the incident stays Fixing) and the couldn't-start result ("Nothing was resent: {reason}. Nothing was changed.");
  - "Recorded in the IRIS audit log." beneath each band;
  - a ghost Dismiss at the right end of the last request's band, or of its status row when that request was rejected or expired.

  The result is announced, and the same text reaches the phone through a `result` notification.
- **Dismiss:** the card compacts to its headline and result and focus moves to the compacted headline.
- **Show details** (`aria-expanded`) opens inline below the approval row. It holds:
  - the cause category and the element at fault;
  - the sample excerpt and its error, in `mono-sm`;
  - failures by item, with first and last times;
  - "Held as an IRIS Workflow task until someone answers.";
  - trace links to the sample and the first failure, opening in the Orders namespace's trace application.
- **Announcements:**
  - a new incident is announced once, as "Incident: {headline}. Approval needed." or "Incident: {headline}. No fix proposed.";
  - a state change is announced with the card's update;
  - an answer is announced in the places where it didn't take focus.
- **The phone:**
  - one message per notification, rendered from its catalog key (the first notice, a later request, the fallback and no-fix notices), with the compact dry run's values in `mono-sm`, in danger and success ink;
  - Approve (left) and Reject side by side, each half width and 40px tall;
  - while an approval request is pending on screen, the phone doesn't scroll and the "New messages" pattern applies;
  - once answered, the buttons are replaced by the status in message form, with a final period ("Approved from Telegram at 14:15 ET.").
- **The rail:** a pending request's row is a button, "Show in the chat: {action}", whose accessible name holds the row's visible title verbatim (owner condition U-122). Pressing it moves focus to its card in the chat and scrolls it into view.
- **Times and texts:** a page time beside message text adds the browser's zone abbreviation when it differs from the instance's. Texts are exact (verbatim, straight ASCII quotes), and styles use DESIGN.md tokens only.

## Cross-Story Dependencies

- **Done:**
  - **Story 6.1:** the incident card (`web/src/app/incidents/`) and `WebChatOut.INCIDENTKINDS`.
  - **Story 6.2:** the approval request card (`web/src/app/approvals/`); `AnswersIn` and `AnswerOps`; the shared busy rule; the statuses and late press from the generated catalog.
  - **Story 6.3 (e88ec18):** the phone's notices, buttons and in-place edit; `answer-press.ts` shared by card and phone; `NoticesIn`; the rail row's focus jump; DW-128's `BridgeSink.Step` line; the `live:answers` unit (X1 to X10); demo-path steps 4 and 5 running on fixtures.
  - 6.1's and 6.2's browser cases are still in `web/e2e/floor/{incident,approval}.spec.ts` (I1 to I11, A1 to A10; I1 and A1 tagged `@browsers`).
- **Within the epic:** 6.4 extends 6.1's card and 6.2's request cards to every ending, with result bands and Dismiss, and its browser cases go in `live:answers`.
- **Lane A work stood in by fixtures:**
  - Epic 5's `IncidentManager` (`incident` events, notices, results and `dismiss`). Epic 4's `Test.Demo.IncidentManagerDouble` already stands in for that item and answers `IncidentCommand`s synchronously;
  - Story 7.2's later request;
  - Story 7.3's couldn't-start result;
  - the mixed, still-resending and interrupted results of Stories 30.5 and 7.5.

  The REL-2 specs for UJ-1's incident and approval steps run on fixtures until Epic 11 turns them on end to end.
- **Ledger items:**
  - **Resolved:** DW-68, DW-113, DW-98 and DW-199 in 6.2; DW-128 in 6.3.
  - **Story 6.4's inbox:**
    - DW-105: remove `Test.Core.ConversationTurns`' ConversationProbe event-log rows (Begin, Ask, Tell, OnResponse) in its teardown, in the `Observe.RemoveWarnings` shape (Rule 19).
    - DW-315: `live floor` runs 491-527 s of its 540 s local deadline because of Epic 6's floor specs (about 130 s). Move `incident.spec.ts` and `approval.spec.ts` into `live:answers`, keeping their `@browsers` cases' Firefox and WebKit coverage, so the floor regains its margin.
  - **Known open, not to re-file (re-owned at the burn-down, not Epic 6 story work):**
    - DW-292: after a reload, an answered request, a result or the evidence shows only after the next event.
    - DW-294: after a page load, the card's footer can't find its diagnosis decision.
    - DW-299: the layout floor needs the guide's compact height.
    - DW-310: `NoticesIn`'s thread join copies `CommandsIn`'s, because the shared home is contended.
- **Waiting on this epic:**
  - Story 10.3: `AnswersIn`'s Telegram entry, with 6.2's rules. Story 12.7 calls it.
  - Story 16.9: checks that Approve and Reject keep working at the caps.
  - Story 31.2: `BridgeSink`'s tool-call notices through `NoticesIn`.
  - Epic 9: runner B's next epic.
