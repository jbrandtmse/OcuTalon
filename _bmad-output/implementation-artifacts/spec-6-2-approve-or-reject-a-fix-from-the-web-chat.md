---
title: 'Story 6.2: Approve or reject a fix from the web chat'
type: 'feature'
created: '2026-10-27'
status: 'done'
baseline_revision: 'a4f7234dd4dd50d16811779efeed143a3f530228'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md'
warnings: ['oversized', 'multiple-goals']
deferred:
  - summary: "After a page reload an answered request has no request card until its next approval or incident event: /state's rail.approvals holds pending requests only (Web/Api.cls RailBody, pinned by Test.Web.Api), and the snapshot's incident has no requests part (Story 6.1's deferred item 1)."
    evidence: "Api.cls L598 'the session's pending approval requests'; live-store.ts keys approvals from snapshot.rail.approvals; Live.Payload.Incident.FromRow fills no parts. Changing the rail's snapshot contract touches Test/Web/** (Epic 16) and the rail's pending-only list."
    location: 'src/ocutalon/cls/OcuTalon/Web/Api.cls RailBody; web/src/app/live/live-store.ts'
    severity: 'low'
  - summary: "Test.Bridge.CodeRules (Lane A) lists the approval classes a tool may not reference (Approval API, ApprovalStartIn, AnswersIn, ...); it does not name the new AnswerOps item. AnswerOps refuses any sender but AnswersIn at run time (Decided 12), so the static rule is a second line only."
    evidence: "Test/Bridge/CodeRules.cls L68 and L549 name AnswersIn; AnswerOps is new in this story."
    location: 'src/ocutalon/cls/OcuTalon/Test/Bridge/CodeRules.cls'
    severity: 'low'
  - summary: >-
      AC3 (headline, cause, dry-run count, Approve and Reject in view at 1280x600 without scrolling) holds in this build only with no status banner and the guide collapsed by Hide guide: with the guide open the chat list is 279 px (or 323 px without a banner) and the card is 466 px from its top to the bottom of Approve.
    evidence: |-
      A6 empties the snapshot's status and presses Hide guide (Decided in-stage 23). The guide's compact form of 56 px is not reached while its Break the feed box is 138 px tall (Epic 4's demo guide). Settles it: Epic 4 gives the guide a compact height that fits DESIGN.md's layout table, then A6 runs without Hide guide.
    location: 'web/src/app/guide (Epic 4), web/e2e/floor/approval.spec.ts A6'
    severity: medium
---

<intent-contract>

## Intent

**Problem:** An incident card shows what broke but nothing to answer: the approval request has no card, `POST /api/v1/approvals/:ref/answer` answers 501, and `AnswersIn` is a stub. Calling `Approval.Answer` in the signed-in user's REST request would also break the fan-out to other watchers (DW-68): the checked cross-owner reads fail there.

**Approach:** Draw one approval request card per request inside the incident card (label, action, fixed-targets line, dry run, Approve / Reject / Show details, expiry), wired to the answer endpoint with the shared busy rule. The endpoint goes through `AnswersIn`, which resolves the session from the CSP session and applies who-may-answer, then hands the answer to a new business operation, `AnswerOps`. `AnswerOps` calls `Approval.Answer` in a production job, so the answer, its audit entry and its live-event fan-out all run with the production's privileges. The card then shows the answered status from the response or from the `approval` event.

## Boundaries & Constraints

**Always:**
- **Who may answer** is checked in `AnswersIn.OnProcessInput` for every entry (the page today, Telegram in Story 10.3). The request must be visible through `Ownership.Approval(ref, sessionRef)`:
  - on a local or IPM install (onlineDemo not 1): the session's own request, or an `instance` request whose noticed incident's production the session watches;
  - with onlineDemo 1: the session's own request only.

  The role rule stays in `Approval.Answer`: the row's `RequiredRole`, checked against the session's IRIS user. No endpoint takes a `SessionRef` from the client (AD-4).
- **Cross-session refusals.** A request the session can't see, an unknown ref, a cancelled request and another session's request all answer 404 `not_found` with the same body, and change nothing: no answer, no audit entry, no event.
- **Production messages carry `SessionRef`, never a user name** (AD-4). `AnswerOps` reads the IRIS user from the `Session` row.
- **Approve and Reject are not turns:** no `Turn`, no `chat.message`, no `Allowance` call. They leave a production message (`AnswersIn` → `AnswerOps`, `SuperSession` = the session's `TraceRef`) and `Answer`'s Approval audit entry.
- **The page.**
  - It reads only the store's `approval` payloads (`ApprovalPayload`, generated) and the incident payload.
  - It renders the answered statuses and the late-press text from the generated catalog (`web/src/app/msg/catalog.ts`, the `answered.*` keys), and its own fixed texts from `APPROVAL_TEXTS` (Design Notes › Texts).
  - Text is bound by interpolation. Styles come from `DESIGN.md` tokens. Non-ASCII is written as escapes (Rule 14).
- **Speech and focus.** The page speaks only through `Announcer`, and focus moves only through `shared/focus-rule.ts`. When an update replaces a focused Approve or Reject, focus goes to the status line (`tabindex="-1"`). Focus on Show details is never moved.
- **Busy.** On a press, both buttons go busy together: spinner, `aria-busy`, `aria-disabled`, never `disabled`. Repeat presses are ignored. With no answer in 10 s both restore, and the notice "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting." is shown and announced. A later answer still shows.

**Never:**
- **No Lane A or contended edits.**
  - Don't edit `src/bridge/**`: not `Approval`, not `Policy.Gate`, no bridge test hook.
  - Don't edit `Core/BridgeSink*.cls`, `Data/{Ownership,Session}.cls`, `web/src/app/live/**` or `payloads.ts`.
  - Don't edit `Test/{Web,Data}/**`, except `Test/Web/Api.cls` L642-645 and L686-690 once the runner rules on them (Blocking condition).
  - Don't edit `docker/**`, `.github/**` or `ci/mock/**`.
- **No security changes.** No SQL grant, role or application change. The signed-in user gains no privilege.
- **No new e2e unit or fixture IRIS user.** Don't add a case to `live sign-in`.
- **Not this story's work:**
  - the result bands, Dismiss and the Open-variant handling (6.4);
  - the phone's buttons and in-place edit, the rail row's focus jump, and the answer announcements elsewhere (6.3);
  - `AnswersIn`'s Telegram entry (10.3);
  - the cap checks (16.9);
  - standalone request cards with "Why:" (steps 4 and 5).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Pending card | incident R (awaiting_approval) and an `approval` payload {ref A, kind fix, incidentRef R, state pending, dryRun {affected 50, resend 50, field "OrderDate", before "10/16/2026", after "2026-10-16", itemNoun order/orders}, expiresAt tomorrow 14:13} | Inside R's card, after the fix line, one request card, top to bottom: "Approval needed"; "Repair and resend 50 orders."; the fixed-targets line; the dry run ("Dry run", "50 orders affected", Before `OrderDate 10/16/2026` in mono danger-ink, After `OrderDate 2026-10-16` in mono success-ink, "Will resend 50 repaired copies; the originals stay unchanged.", "Nothing has changed yet."); one row with Approve (primary, first, name "Approve: repair and resend 50 orders"), Reject (secondary, "Reject: repair and resend 50 orders") and Show details (ghost, right end); then "Expires tomorrow at 14:13". No "Why:". The incident-level Show details row is gone | A dry run that is not an object, or has no numeric `affected`: the action reads "Repair and resend.", and the fixed-targets line and the dry run block are left out |
| Count of one | dryRun affected 1, resend 1 | "Repair and resend 1 order.", "...on this order, without asking the model again...", "1 order affected", "Will resend 1 repaired copy; the original stays unchanged." | — |
| Approve | press Approve → 200 `{"result":"done","approval":{...approved...}}` | Busy, then the label is "Approval request" and "Approved from the web chat at 14:15" replaces Approve and Reject in the row (no final period, `circle-check`). The fixed-targets line, the expiry and "Nothing has changed yet." go; the dry run stays. A focused button's focus is on the status line. Server: row approved, AnsweredChannel web, AnsweredBy = the session's IRIS user; one `approval` event per recipient | — |
| Reject | press Reject → 200 (rejected) | "Rejected from the web chat at 14:15. Nothing was changed." (`circle-slash`) | — |
| Lost the race | already answered on the phone at 14:15; the page still shows pending; press Approve | 409 `already_answered`, message "Already answered: approved from the simulated phone at 14:15.", body also `approval`. The notice under the row shows the page form and is announced, and the status replaces the buttons | — |
| Expired | ExpiresAt past, row still pending | 409 `expired`, "Expired at 14:13. Nothing was changed.", row expired; the card shows that status (`clock`) | — |
| Unseen or unknown | another session's, an eval, an unwatched instance, a cancelled or a random ref | 404 `not_found` "OcuTalon has nothing at this address."; row unchanged, no event. The page notice reads "That request is no longer available." | Body checked only after visibility, so an unseen ref is 404 whatever the body |
| Online demo, other session | onlineDemo 1; session B answers A's request (own or instance), by the page or the endpoint | 404, as unknown; row stays pending, no audit entry, no event on either stream (the required CI check) | — |
| Instance, two watchers | local; instance request on a production that S1 and S2 watch; S1 answers from a web-roles process | done; S1's and S2's streams each get the answered `approval` event (DW-68) | — |
| No role | the session's IRIS user lacks the row's RequiredRole | 403 `not_allowed`, "Only an approver for resends can answer this request." (kind fix); row pending | tool_call: Veto V2's text |
| Bad body | visible ref; action not approve/reject, or channel not web/phone, or no JSON object | 400 `bad_answer` (Veto V2's text); nothing sent | — |
| Inside a bridge context | `AnswersIn` called in a job with an active `Bridge.Context` (a tool) | `not_allowed`; nothing sent to `AnswerOps` | logged as a warning |
| Other sender | a message to `AnswerOps` whose source is not `AnswersIn` | error status, logged; nothing answered | — |
| No answer in 10 s | the POST is held | Both buttons busy; one POST however often pressed; after 10 s restored, with the busy notice shown and announced; when the answer then lands, the status shows and the notice clears | — |
| Network or server error | status 0 / 5xx | 0: the busy notice at once; 5xx with the error shape: its `error.message` (e.g. "Something went wrong inside OcuTalon. Try again."); buttons restored | — |
| Later request | a second `approval` A2 (incidentRef R, raisedAt later, affected 2) | Two request cards in `raisedAt` order; Show details only in the first card's row; A2's buttons name "repair and resend 2 orders" | — |
| Named answerer | local; `answeredBy` "zzsam" ≠ the snapshot's `user` | "Approved by zzsam from the simulated phone at 14:15"; with onlineDemo, or answeredBy = user: unnamed (Veto V5) | — |
| 1280×600 | viewport 1280×600, the pending card just landed | headline, cause, "50 orders affected", Approve and Reject are in the chat list's view; the test does not scroll | — |
| Cancelled, or no payload | request in `incident.requests` with no `approval` payload, or state cancelled | no request card for it | — |

</intent-contract>

## Code Map

**Read-only contracts and evidence (never edit):**
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls`
  - `Answer` L232-273: results `done|already_answered|expired|not_found|not_allowed`; `winner` {action, channel, at}. It refuses a sessionRef that is neither empty nor a Ref (L283). It fires `approval.answered` from its own job (L268-271).
  - `HoldsRole` L318-331: `GetUserRecursedRoleSet` needs `%Admin_Secure:USE` for another user.
  - `HoldTask` L511-516: a checked `%ExecDirect` on `EnsLib_Workflow.TaskResponse`.
  - `CompleteHoldTask` L518+: polls up to `TASKSECONDS` (5 s) for the task. A fixture row has no hold, so each real `Answer` on one takes about 5 s and logs a warning.
  - `LiveHold` L621.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls`
  - `Check(toolref, call, metadata, sinkClass)` L102. A held call goes to `Hold` L139-163 (`Approval.Raise`, a tool_call row). `ReportStep` L252-260 fires `turn.step` for an allowed call only.
  - Test pattern: `Test/Bridge/Gate.cls` `Begin` L1444, `Verdict` L1620, `TestSafeBuiltInIsAllowedAndReported` L183 (set_reminder, "Setting a reminder"), `TestRiskyByCodeAndUnclassified` L251.
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`
  - `SessionRef` L132-147 reads `%session.Data("OcuTalon.SessionRef")` and needs `IrisUser = $Username`.
  - `Approval` L351 and `APPROVALVISIBLE` L54 are unchecked (`Rows` L504), with `LocalFlag` L491 = onlineDemo ≠ 1.
  - `Watchers` L365 (checked, L373) and `ApprovalIncident` L404 (checked, L411) answer "" plus an error on a failed prepare.
- `Data/Session.cls`: `RefIndexOpen`, `IrisUser` L18. `Recipients` L93 passes `Watchers`' sc through (L101).
- `Core/BridgeSink.cls`
  - `Approved`/`Receivers` L58-108: the instance fan-out.
  - `Step` L128-151: needs a running Turn and the context's ItemId = that turn's.
- `Live/Payload/Approval.cls` `FromRow(row, sessionRef)` L62: every row field plus `DryRun` parsed into `Part.DryRun`. No action text.
- `web/src/app/live/payloads.ts`:
  - `ApprovalPayload` L187-206 and `DryRun` L18-26;
  - `IncidentRequest` L67-71 (ref, state and result only).
- `web/src/app/live/live-store.ts`
  - L44: `approval` goes to `approvals`, keyed by ref, replaced in place.
  - L115: the snapshot reads `rail.approvals`, pending only.
- `Msg/Catalog/Core.cls`
  - The `answered.*` keys L80-155, with `web` forms for approved and approvedBy only.
  - `Msg/Catalog.cls` `CHANNELNAMES` L41: web=the web chat, phone=the simulated phone, telegram=Telegram.
- `Install/Step/Web.cls` `APPLICATIONROLES` L35 (`:%DB_OCUTALON_CODE:%DB_OCUTALON_DATA:%DB_OCUTALON_PRIVATE`).
- Test patterns:
  - `Test/Bridge/WebStatus.cls`: the web-request context L1-25. `Probe` L289-300 runs a Job with one-argument `$SYSTEM.Security.Login(user)`. `RunProbe` L470. `CreateUser` L469-476 is private, in Lane A's class.
  - `Test/Web/StubRequest.cls` `MakeBody` (public).
  - `Test/Web/Api.cls` `Written` L1166 (public ClassMethod) and `CallSession` L1105-1113 (the pattern).
- `Test/Data/Fixture.cls` (contended; use only):
  - `Session(user)` L19, `Turn` L32, `Check` L65, `Incident` L81;
  - `Approval(owner, incidentRef, state, raisedAt, fields)` L102-118 sets no RequiredRole, so the real `Answer` gives not_allowed until `fields` sets one;
  - `Clean(refs)` L331.
- `Test/Core` patterns:
  - `InProduction.cls` (`Guard`, `Session`, cleanup);
  - `CommandsInProbe.cls` and `CommandsRouting.cls` L436-459 (a shadow probe instance with an overridden private `Send`);
  - `ProbeSeam.cls`, `Observe.Events` L46;
  - `BridgeSink.cls` `TestInstanceApprovalReachesEveryWatcher` L286 and `TestTurnStepOfAnotherItem` L482-504.
- `Test/Install/Production.cls` `Items()` L466 (the item oracle) and `docker/tests/test-production.sh` L7, L165 and L210 (every enabled pooled item has an Alive job).
- `web/src/app/shared/`:
  - `busy-state.ts`: `BusyState`, `BUSY_TIMEOUT_MS`;
  - `server-button.ts`: the busy markup, `BUSY_NOTICE`, the Announcer use;
  - `focus-rule.ts`: `keepFocus`, `FocusRule`;
  - `announcer.ts`.
- `web/src/app/rail/rail-view.ts` `approvalTitle` L165-176 (exported; "Repair and resend {n} {noun}"). Epic 5 owns one line of this file, so only import from it.
- `web/src/app/chat/page-time.ts`: `pageTimeBeside` L88, `pageWhenBeside` L195, `WHEN_TEXTS`.
- `web/src/app/api/envelope.interceptor.ts` L27-34 adds the POST headers and handles 401.
- UX:
  - EXPERIENCE.md: L180-189 (times, channels, who answered), L276-285 (components), L375-382 (busy), L656-669 (states), L690-700 (count of one, late press), L795 ("That request is no longer available.").
  - DESIGN.md: L677 (1280×600), L814-825.
  - `mockups/states.html` L353-375 (A1); `mockups/main-page.html` L475-479.
- `web/src/styles/tokens.css` L406-431: `--approval-request-card-*`, `--answered-status-*`, `--dry-run-block-*`.

**To change or reuse:**
- `src/ocutalon/cls/OcuTalon/Core/AnswersIn.cls`: the stub (STUB=1).
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`:
  - `AnswerApproval` L383-393 (404 via Ownership.Approval, else 501);
  - the message parameters L53-81, `Fail` L714, `ServerError` L129, `PayloadObject`, `BodyText` L220;
  - the class doc L19-20.
  - Don't touch L598-638 (Epic 5).
- `Production.cls` L51, the Lane B region. `Test/Core/ProductionItems.cls` L23 (AnswersIn `"stub": 1`).
- `web/src/app/incidents/incident-card.ts`:
  - the actions row L80-92, the panel L93-97, the ids L253-257, the inputs L244-250, `incidentContext` L20-28.
  - `incident-view.ts` `PanelView`/`panelOf` L289-299.
- `web/src/app/chat/chat-panel.ts`:
  - the card at L119-125 (inputs);
  - `scrollToBottom` L403-407;
  - the ResizeObserver L313-321, `onScroll` L344-355 and `showNew` L365-372 (`[data-part]` lookup);
  - `FOCUS_RULE` L50-53.
- `web/src/app/api/api-client.ts` (POST methods L21-65) and `api-types.ts` L86-88 (`ApiError`).
- `web/scripts/catalog.mjs` (`LISTED_KEYS` L39-56, `SLOT_TYPES` L59, the header contract), `catalog.test.mjs` and the generated `web/src/app/msg/catalog.ts`.
- `web/src/app/icon/icon.ts`: `IconName` lacks `circle-slash` and `clock`.
- `web/scripts/ux-strings.test.mjs` (`IMPORTED` L41-56, `SOURCES` L149-), `announce-focus-sources.test.mjs` (speakers L95-107, `hosts` L140-157) and `incident-sources.test.mjs` (6.1's anatomy pins).
- `web/e2e/support/iris.ts`:
  - `seedApproval` L674-692 hard-codes field and before/after and sets no RequiredRole;
  - `sinkEvent` L431, `setApprovalState` L695, `publishIncident` L145, `cleanFixtureRows` L636, `irisScript` L71.
- `web/e2e/floor/incident.spec.ts`: the pattern (clock fixed at 14:30 UTC, `unique`, `finally` cleanup).

## Tasks & Acceptance

**Execution:**

0. **Task 0** (implement stage, before Task 11's assertions are fixed; lane-B warm throwaway, never a slot). Run Task 11's probe job once and record in `## Verification`:
   - whether `Ownership.Watchers`, `Ownership.ApprovalIncident` and `Session.Recipients("instance", …)` fail there (an error status and "");
   - what `Approval.Answer` called directly in that job returns, and whether the hold's task is completed (informational: the evidence for Veto V1);
   - whether `%CSP.Session.%New(id, 0)` works in that job.

   If the checked reads do not fail there, Task 11 keeps only its DW-68 test, and DW-113 is recorded unresolved in the frontmatter `deferred:` list with the measurement. If `%CSP.Session` fails there, Task 11 uses a stub session (Task 8). Everything else is (inference) until this runs.
1. `src/ocutalon/cls/OcuTalon/Core/Msg/Answer.cls` and `AnswerResult.cls` (new).
   - `Answer Extends Ens.Request`: `Ref`, `Action`, `Channel`, `SessionRef` (all MAXLEN 22, Action and Channel 16). No user name.
   - `AnswerResult Extends Ens.Response`: `Result` (`done|already_answered|expired|not_found|not_allowed|bad_answer`), `WinnerAction`, `WinnerChannel`, `WinnerAt`.
   - Storage blocks as compiled (export from slot B). Class docs state the contract.
2. `src/ocutalon/cls/OcuTalon/Core/AnswerOps.cls` (new) -- `Extends Ens.BusinessOperation`, `OnMessage` in the `SettingsOps` shape.
   - `Parameter APPROVALAPI = "OcuTalon.Bridge.Approval"` is the double's seam.
   - A request whose header `SourceConfigName` is not `AnswersIn` is refused with an error status and logged.
   - A `SessionRef` with no `Session` row gives `not_found`.
   - Otherwise it calls `$ClassMethod(..#APPROVALAPI, "Answer", Ref, Action, Channel, session.IrisUser, SessionRef, .winner)` and copies the result and winner.
   - It never fails its caller with a partial result: an exception gives an error status.
   - -- So the call runs in a production job (DW-68, Veto V1).
3. `src/ocutalon/cls/OcuTalon/Core/AnswersIn.cls` -- build the item and remove `STUB` and its handler.
   - `ClassMethod FromPage(ref, action, channel, Output result As Msg.AnswerResult, Output sessionRef) As %Status`:
     - `sessionRef` comes from `Ownership.SessionRef` (the CSP session);
     - then `CreateBusinessService("AnswersIn")` and `ProcessInput(answer, .result)`.
   - `OnProcessInput`, in this order:
     1. an active `Bridge.Context` gives `not_allowed`, with a warning;
     2. a `SessionRef` that is not a Ref gives `not_found`;
     3. `Ownership.Approval(Ref, SessionRef)` empty gives `not_found`; its error gives an error;
     4. an Action other than approve/reject, or a Channel not in web, phone, telegram, gives `bad_answer`;
     5. it sets `..%SuperSession` to the session's `TraceRef` (a trace session of its own, not the daily thread) and sends through a private `Send` seam, `SendRequestSync("AnswerOps", …, TIMEOUT 30)`. No response gives an error.
   - It never calls `Allowance` or `Conversation`.
   - Update the class doc (AD-11; FromTelegram is Story 10.3's).
4. `src/ocutalon/cls/OcuTalon/Production.cls` -- in the Lane B region after AnswersIn: `<Item Name="AnswerOps" ClassName="OcuTalon.Core.AnswerOps" PoolSize="1" Enabled="true"/>`.
5. `src/ocutalon/cls/OcuTalon/Test/Core/ProductionItems.cls` -- AnswersIn `"stub": 0`; add the AnswerOps row (B, pool 1, enabled 1, stub 0, no settings) in production order.
6. `src/ocutalon/cls/OcuTalon/Web/Api.cls` -- rewrite `AnswerApproval(ref)`:
   - **Order of checks:** the session (`Ownership.SessionRef`); visibility (`Ownership.Approval`, which gives 404 `not_found`); the body, a JSON object with `action` approve or reject and `channel` web or phone (else 400 `bad_answer`); then `AnswersIn.FromPage`.
   - **Result mapping** (Matrix):
     - done: 200 `{"result":"done","approval":<..PayloadObject(Approval.FromRow(row, sessionRef))>}`, the row re-read through Ownership;
     - already_answered: 409, its message from `Catalog.Render("answered.alreadyApproved|alreadyRejected[By]", {channel, time, user}, "web")`, plus `approval`. The `By` form is used when onlineDemo is not 1 and the row's `AnsweredBy` ≠ `$Username`, compared without case (Veto V5);
     - expired: 409, `answered.expired` with `time` = the row's ExpiresAt, plus `approval`;
     - not_found: 404 `MESSAGENOTFOUND`;
     - not_allowed: 403, `MESSAGENOTAPPROVER` for kind fix, else `MESSAGENOTAPPROVERTOOL`;
     - bad_answer: 400;
     - an error: `ServerError`.
   - Add the three message parameters (Texts).
   - Correct the class doc's clause at L19-20 about this route.
7. `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` -- **allowed by the orchestrator's ruling Q1 (Design Notes, Orchestrator rulings)**:
   - L686-689, the `For ref = ownApproval, instanceApproval` loop only: each visible approval, called with no body, answers "400 Bad Request" with the `bad_answer` body;
   - L642-645: the approval half of the doc sentence says so.
   - Nothing else in the file changes (the 404 loops, the incident-vs-approval 404, both onlineDemo checks and the visible-incident `DismissIncident` loop stay). New endpoint tests go in a new class.
8. `src/ocutalon/cls/OcuTalon/Test/Core/ApprovalDouble.cls`, `AnswerOpsProbe.cls` and `AnswersInProbe.cls` (new). They add nothing to the product's surface.
   - `ApprovalDouble.Answer(ref, action, channel, irisUser, sessionRef, .winner)` returns the result scripted under `^OcuTalonTest("ApprovalDouble", run)` (default `done`) with Epic 0's winner shape, and records each call's arguments. It changes no row.
   - `AnswerOpsProbe Extends AnswerOps` sets `APPROVALAPI` to the double.
   - `AnswersInProbe Extends AnswersIn` overrides `Send`: a shadow `AnswerOpsProbe` whose `%RequestHeader` has source `AnswersIn`, called with `OnMessage` (the `CommandsInProbe` pattern). It records the sends.
   - A `StubSession` (a `%RegisteredObject` with a multidimensional `Data`) is added only if Task 0 needs it.
9. `src/ocutalon/cls/OcuTalon/Test/Core/AnswersIn.cls` (new, `%UnitTest.TestCase`, no production: shadow `AnswersInProbe.OnProcessInput`). It covers:
   - each of the double's five results passed through, with the winner;
   - `bad_answer` for a bad action and for a bad channel, where the double is not called;
   - not_found, with the double not called, for: another session's request (local and online), eval, an unwatched instance, a missing ref, and an instance request with onlineDemo 1;
   - a local watcher reaches the double for an instance request;
   - DW-199: the double saw `sessionRef` = the session's 22-character Ref, `irisUser` = its `Session.IrisUser` and the channel as sent; a malformed SessionRef never reaches it;
   - a bridge context gives not_allowed with no call;
   - a telegram-channel `Answer` reaches the double (the rules are entry-independent, for 10.3);
   - `AnswerOpsProbe` refuses a header from another source;
   - the double's not_allowed for a session whose IRIS user lacks the role reaches the caller.

   Two sessions per test; fixtures removed with `Fixture.Clean`; onlineDemo saved and restored.
10. `src/ocutalon/cls/OcuTalon/Test/Core/AnswersInProduction.cls` (new, extends `InProduction`, the real Approval API, fixture rows with `RequiredRole` "OcuTalonUser" unless stated). Through `Web.Api.AnswerApproval` (`StubRequest.MakeBody`, a `%CSP.Session` bound to the session, `Test.Web.Api.Written`):
    - 200, with the row approved: AnsweredChannel web, AnsweredBy = the session's IRIS user, an `approval` event on the session's stream (`Observe.Events`);
    - a second press: 409 already_answered with the winner and the catalog message;
    - ExpiresAt past: 409 expired and the row expired;
    - RequiredRole "ZzNoSuchRole": 403 and the row pending;
    - **the required check**: onlineDemo 1, session B answers A's own and A's instance request: 404 and the same body as an unknown ref; the rows pending; no event on A's or B's stream; B's answer header count unchanged;
    - a header AnswersIn→AnswerOps with SuperSession = the TraceRef;
    - no Turn row and no `chat.message` for the session;
    - DW-199: a malformed sessionRef passed straight to `Approval.Answer` answers not_allowed;
    - **DW-98** (the real gate, no bridge edit): a session with a running Turn, and `Bridge.Context.Begin` with that turn's ItemId and OwnerRef. Then:
      - `Gate.Check` of a safe built-in (set_reminder) with sink "" (Decide's HostSinkClass) puts a `turn.step` with that turn's Ref and "Setting a reminder" on the stream;
      - an unclassified call is held, and its pending `approval` event (kind tool_call) reaches the stream;
      - rejecting it through `AnswerApproval` gives a rejected `approval` event;
      - the held row is cleaned up as `Test.Bridge.Gate` does.
11. `src/ocutalon/cls/OcuTalon/Test/Core/AnswersInWebRoles.cls` (new; THROWAWAY STACKS AND CI ONLY, guarded like `InProduction`). It creates and deletes its own fixture IRIS user whose roles are exactly OcuTalonUser plus `Install.Step.Web`'s `APPLICATIONROLES` (the `WebStatus` pattern; the copy's reason is in Design Notes). A Job logs in as that user (one-argument `Login`) and reports under `^OcuTalonTest("AnswersInWebRoles", n)`:
    - **DW-113**: `Watchers`, `ApprovalIncident` and `Recipients("instance", R)` each return "" and an error status. In the test process they return the two watchers (the control).
    - **DW-68**: with a `%session` bound to a session of that user, which watches the production with a second session S2, `AnswersIn.FromPage` on an instance request gives done, and S1's and S2's streams each get the answered `approval` event.
    - The user, the rows and the reports are removed before and after.
12. `web/scripts/catalog.mjs`, `web/scripts/catalog.test.mjs` and `web/src/app/msg/catalog.ts` (regenerated with `npm --prefix web run catalog`):
    - list the nine `answered.*` keys (approved, approvedBy, rejected, rejectedBy, expired, alreadyApproved, alreadyRejected, alreadyApprovedBy, alreadyRejectedBy);
    - add slot types `channel` (rendered through `CHANNEL_NAMES`, read from `Msg/Catalog.cls` `CHANNELNAMES` the way `REASONKEYS` is read; an unknown code renders as given) and `text` (the caller's string, cleaned);
    - update the header's allowlist sentence and the tests.
13. `web/src/app/approvals/approval-view.ts` (new; framework-free, type-only imports, so Node runs it) and `web/scripts/approval-view.test.mjs` (new). It holds:
    - **Texts:** `APPROVAL_TEXTS`.
    - **The request list:** `requestsOf(incident, approvals)`: the approvals with `incidentRef` = the incident's `ref`, state not cancelled, sorted by `raisedAt`.
    - **The card view:** `approvalView(approval, ctx)`, with ctx = `{nowMs, instanceZone, onlineDemo, user, timeBeside, whenBeside}`. It gives `key`, `ref`, `pending`, `label`, `bar` (`pending|approved|closed`), `action`, `approveName`, `rejectName`, `fixedTargets`, `dryRun` (`countLine`, `field`, `before`, `after`, `resendLine`, `nothingYet`, or none), `expiry`, and `status` (`{text, tone: approved|rejected|expired, icon}` or none), with the statuses from `renderPageText`.
    - **The answer outcome:** `answerOutcomeOf(status, body)`, one of done, already, expired, gone, notAllowed, failed(message), unreachable.
    - **The late press:** `latePressText(approval, ctx)`.

    Unit-test every Matrix row of the page and every Decided rule, the texts written out.
14. `web/src/app/icon/icon.ts` -- add the Lucide (ISC) paths `circle-slash` and `clock` to `IconName` and the path map.
15. `web/src/app/api/api-types.ts` and `api-client.ts` (own entries):
    - `AnswerBody {result: 'done'; approval: ApprovalPayload}` and `AnswerError {error: {code; message}; approval?: ApprovalPayload}`;
    - `answerApproval(ref, action): Observable<HttpResponse<AnswerBody>>`, a POST of `{action, channel: 'web'}` to `/approvals/${encodeURIComponent(ref)}/answer`.
16. `web/src/app/approvals/approval-request-card.ts` (new), `app-approval-request-card`.
    - **Inputs:** `approval`, `ctx`, `details` (a `PanelView`, set only on the first card), `detailsId`, `detailsOpen`. **Output:** `toggleDetails`.
    - **Root:** a `section` with `data-part="approval"`, `data-key` = ref and `tabindex="-1"`; the label in the label token; the accent bar.
    - **Answer row:** a plain wrapper. In it, `@if` pending gives a `span data-part="answer" [data-key]` with two buttons. They carry `controls.css` classes, their names, a spinner, `aria-busy` and `aria-disabled` (never `disabled`), and share one `BusyState`. Otherwise it gives `p data-part="answer" [data-key] tabindex="-1" class="status"` with its icon. Show details (ghost, chevron, `aria-expanded`, `aria-controls`) sits outside the `@if`.
    - **Below the row:** the expiry caption while pending; the notice (`app-inline-notice`, warning); `app-evidence-panel` when `details` and open.
    - **A press:** `BusyState.press()`, then `answerApproval`, then `answered(call)`. A done, already or expired body's `approval` becomes a local view that wins while the input is still pending. A notice text is shown and announced (`Announcer`).
    - **Focus:** an effect calls `keepFocus(host, injector, popovers, ANSWER_RULE)` with `ANSWER_RULE = {item: '[data-part="answer"][data-key]', keyOf}`.
17. `web/src/app/incidents/incident-card.ts` and `incident-view.ts`:
    - new inputs `approvals` and `user`; render `requestsOf(...)` after the fixing line;
    - hand the first card `panel`, `panelId` and the `open` signal;
    - keep the incident-level actions row only when no request card renders, and on a compact card, which shows no request cards;
    - build the approval ctx from the card's times (no `.announce`, no `.focus(`).
18. `web/src/app/chat/chat-panel.ts`:
    - pass `[approvals]="live.store()?.approvals"` and `[user]="live.snapshot()?.user"`;
    - in `scrollToBottom`, when the newest entry is an incident card whose top would sit above the list's visible top, put that card's top at the list's top instead (Decided 9), keeping `atBottom` true and `lastTop` in step;
    - update the module doc's Scrolling paragraph.
19. `web/scripts/ux-strings.test.mjs`, `announce-focus-sources.test.mjs`, `incident-sources.test.mjs` and `web/scripts/approval-sources.test.mjs` (new):
    - import `APPROVAL_TEXTS` with a source for each string (Texts);
    - add `app/approvals/approval-request-card.ts` to the speakers (reason: the busy, late-press and error notices of the user's own press) and to the focus-rule hosts with `ANSWER_RULE`;
    - update 6.1's anatomy pins for Show details;
    - source pins: no `disabled` attribute, one `BusyState` for both buttons, interpolation only, tokens only, the status `p` with `tabindex="-1"` and `data-part="answer"`.
20. `web/e2e/support/iris.ts`:
    - extend `seedApproval` with optional `requiredRole`, `field`, `before`, `after`, `resend`, `state` and answered fields, keeping today's defaults;
    - add an owner of a fresh fixture session of another user;
    - add `answerQuietly(user, ref, action, channel)`: `Approval.Answer` from the script's job with sinkClass `OcuTalon.Bridge.Ext.HostSink` (no event).
21. `web/e2e/floor/approval.spec.ts` (new), cases A1-A7 under `## Verification`. Each case has its own refs, publishes the incident (`publishIncident`) and the approval event (`sinkEvent('approval.raised')`), and removes its rows in a `finally`.

**Acceptance Criteria:**
- **AC1:** Given a pending fix request of an incident in the session's store, when the incident card renders, then it shows the request card with the Matrix's parts, texts and order, and its buttons named with the object. A request card for a later request of the same incident appears second, in `raisedAt` order (A1, A3, `approval-view.test`).
- **AC2:** Given the dry run `{affected, resend, field, before, after, itemNoun}`, when the block renders, then it shows "Dry run", the count line, Before (mono, danger-ink) and After (mono, success-ink) naming the field, the Will resend line with `resend`, and "Nothing has changed yet." while pending, with the count-of-one forms (A1, `approval-view.test`).
- **AC3:** Given the browser at 1280×600 and a pending card that just landed, when nothing is scrolled, then the headline, the cause, the dry-run count, Approve and Reject are all in the chat list's view (A6).
- **AC4:** Given a press of Approve or Reject, when the page posts `{action, channel: 'web'}`, then `AnswersIn` resolves the session from the CSP session, applies the visibility and online-demo rules, and `AnswerOps` calls `Approval.Answer` with the session's Ref and IRIS user. The endpoint answers 200, 409 (with the winner), 409, 404, 403 or 400 with plain-English errors. Every result is covered with the double, and with the real API in both install modes, two sessions and a user lacking the role (`Test.Core.AnswersIn`, `Test.Core.AnswersInProduction`).
- **AC5:** Given the online-demo flag and two sessions, when one answers the other's request through the endpoint or the page's own call, then it gets 404 as for an unknown ref, and the request stays pending, with no answer recorded and no event. This runs in shard `lane-b` (CI group `image`) and in A7 (CI group `shards`) on every push.
- **AC6:** Given a press, when the answer is in flight, then both buttons are busy (spinner, `aria-busy`, `aria-disabled`, no `disabled`) and a repeat press sends nothing. After 10 s they restore with the notice shown and announced, and a later answer still shows (A4).
- **AC7:** Given the request answered here or elsewhere, when the card applies the response or the `approval` event, then the label is "Approval request", the status replaces the buttons in the same row, the fixed-targets line, the expiry and "Nothing has changed yet." go and the dry run stays, and a focused button's focus is on the status line (A2, A3, `approval-view.test`).
- **AC8:** Given a press that lost the race, when the 409 arrives, then the card shows "Already answered: approved from {channel} at {time}." and the winning status. Channels read "the web chat", "the simulated phone" or "Telegram", and on a local install an answer by another user names that user (A5, A3, `approval-view.test`).
- **AC9 (DW-68):** Given an instance request on a local install that two sessions watch, when one answers from a process with only the web roles, then both sessions' streams get the answered `approval` event (`Test.Core.AnswersInWebRoles`).
- **AC10 (DW-113):** Given a process with only the web roles, when it calls `Ownership.Watchers`, `Ownership.ApprovalIncident` and `Session.Recipients` for an instance incident, then each returns no recipients and an error status, while the test process reads the watchers (`Test.Core.AnswersInWebRoles`; Task 0 decides, as stated there).
- **AC11 (DW-199):** Given a web answer, when `AnswerOps` calls the Approval API, then it passes the session's 22-character Ref and that session's IRIS user. A malformed sessionRef answers not_allowed from `Approval.Answer` and never comes from `AnswersIn` (`Test.Core.AnswersIn`, `Test.Core.AnswersInProduction`).
- **AC12 (DW-98):** Given a running turn and the real gate in its bridge context, when a safe built-in is checked, then its `turn.step` with the turn's Ref and label reaches the session stream through `BridgeSink`. When an unclassified call is held and then rejected through the answer endpoint, then its pending and rejected `approval` events reach the stream, with no bridge edit (`Test.Core.AnswersInProduction`).
- **AC13:** Given an answer, when it is processed, then it creates no Turn, no `chat.message` and no Allowance call, and leaves one `AnswersIn` → `AnswerOps` header tagged with the session's `TraceRef` (`Test.Core.AnswersInProduction`, A2).
- **AC14 (owner condition, U-113):** Given a web answer, when `AnswersIn` hands it to `AnswerOps`, then (1) the answerer's IRIS user and SessionRef in the hand-off message come only from the server-side session (the CSP session's `Session` row), never from the request body: a test posts a body that names another user (and another sessionRef) and the recorded `AnsweredBy` is still the signed-in session's user; (2) `Approval.Answer` still runs its `RequiredRole` check on that user inside `AnswerOps`' job: a test with a real fixture row whose `RequiredRole` the session's user lacks answers 403 `not_allowed` and records nothing; (3) `AnswersIn` is `AnswerOps`' only sender (a message from any other item is refused, Decided 12), and the hand-off shows in Visual Trace (the `AnswersIn` -> `AnswerOps` header, AC13).
- **AC15 (owner condition, U-115):** Given a caller who may not answer a request (no `RequiredRole`, or a request its session can't answer), when the request is already answered or expired, then the endpoint answers 403 `not_allowed` with no `approval` payload, never a 409: the 403 check runs before the 409 checks. A test pins that order (an answered request and an expired request, each pressed by a user lacking the role, both give 403 with no payload). `src/bridge/**` is Epic 7's contended path: if `Approval.Answer`'s own order can't give this, `AnswerOps` checks the role first through the bridge's public API (the same check `Answer` makes), before it calls `Answer`; if the bridge exposes no such API, HALT with an `intent gap` naming it.
- **AC16 (owner condition, U-116):** Given `Test.Core.AnswersInWebRoles` (the test-only fixture IRIS user), when it starts, then (1) it refuses to run (fails its setup with a clear message, creating nothing) unless it is on a throwaway test stack, by an explicit guard that is false on the demo host, on a user's instance and in an IPM test run (the guard reads a marker only `ci/iris.sh`/`docker/tests/lib-live.sh` throwaways carry; it must exist without editing a contended file such as `ci/compose.ci.yml` or `docker/**`; if no such marker exists, HALT with an `intent gap` naming the marker you need); (2) the fixture user's password is random per run and never written to a log, the test output or a global; (3) teardown deletes the user even when a test fails (cleanup in `OnAfterAllTests`/`OnAfterOneTest` regardless of the result, and a leftover from an earlier failed run is removed first). Tests pin (1) the guard refusing outside a throwaway and (3) no user left after a forced failure.

## Spec Change Log

- 2026-10-27, runner (before implement): owner decisions U-113, U-115 and U-116 (answers #345, #347, #348) added as AC14-AC16 and under Design Notes, Owner decisions. U-114 and U-117 kept unchanged.

- 2026-10-27, runner (spec validation): the plan halted `blocked` on a contended-path edit (`Test/Web/Api.cls`, Epic 16). The orchestrator ruled Q1-Q4 (Design Notes, Orchestrator rulings): the visible-approval loop may be replaced; 6.4 may replace the dismiss loop later; the AD-33 item row and the REST row were written into the spine by the runner. Status reset to `ready-for-dev` (the plan was otherwise complete).

- 2026-10-27, implement stage: Task 0 measured (Verification), the follow-bottom cap, the dry run's one-row head and A6's conditions decided (Design Notes, Decided in-stage 19-26). AC3 holds only with no status banner and the guide collapsed (Decided 23).

- 2026-10-27, implement stage (review pass 1): five medium patches (server tests of the 403 text and the named 409, the online-demo required check with a watching session B, the browser cases A8 and A9, the focus exemption of the follow-bottom cap with A6's Show details check, a split class-doc line), recorded under Review Triage Log and Decided in-stage 27-28. No intent or AC changed.

## Review Triage Log

### 2026-10-27 - Review pass
- verdicts: 42 findings - high 0, medium 10, low 29, false 3, maybe-false 0 (nine mediums and one low patched, one medium deferred; see rows)
- findings:
  - `[false]` `[reject]` Blind: channel "phone" accepted from any web session - the Matrix, V3 and AC4 say the route takes web or phone (6.3's phone page posts phone); Telegram is refused, as the finding itself notes.
  - `[low]` `[reject]` Blind: a 30 s sync timeout answers 500 while AnswerOps may still commit - `Answer` takes at most about 12 s (Decided 13); a retry reads already_answered; not met in everyday use.
  - `[medium]` `[patch]` Blind: server 409 named/rejected forms and 403 tool_call text untested - added `TestLatePressNamesAnotherUserOnALocalInstall` and the tool_call body assertion (with V3 below).
  - `[medium]` `[patch]` Blind: the follow-bottom cap re-pins to the headline on every resize, so Show details' panel stays below the fold - patched: the cap is skipped while focus is inside the card (`chat-panel.ts` `headlineTop`); A6 now presses Show details and expects the panel in view (grouped with Edge 1).
  - `[low]` `[reject]` Blind: A4's fixed 400 ms wait and wall-clock `DAY` - the second press is ignored synchronously, so the wait only gives a late request time to show; midnight straddle is a flake, not a defect of the product.
  - `[low]` `[reject]` Blind: `failed` shows as "Approved ..." - Decided 6 and 14 write that the card records the answer (approved, executing, done, failed share the approved status) and the bar is closed.
  - `[low]` `[reject]` Blind: `AnswerOps.SENDER` is the item name literal - `ProductionItems` and `Test.Install.Production` pin the item name; a rename fails those and `TestAnswerOpsRefusesOtherSenders`.
  - `[low]` `[reject]` Blind: global state in the test fixtures (`ApprovalDouble` run pointer, user prefix sweep, log deletes) - the classes run one at a time in one process and clean up in `finally` and the next run's start; no concurrent runner exists.
  - `[low]` `[patch]` Blind: the class doc of `Web/Api.cls` has one very long line and does not say that Telegram enters through AnswersIn only - the line is split and the sentence added.
  - `[medium]` `[patch]` Edge: scroll snap-back (same root cause as Blind 4) - patched with it.
  - `[low]` `[reject]` Edge: with several request cards or an open panel the headline pin can put Approve below the fold - A6 pins the single-request case the AC names; the cap yields once focus is in the card.
  - `[low]` `[reject]` Edge: an `already_answered` with an empty winner makes `Catalog.Render` fail (500) - `Approval.Answer` fills the winner from the row's answer fields, which every state past pending has through Answer; only a hand-made row lacks them.
  - `[low]` `[reject]` Edge: done, then the re-read finds no row - the row would have to be cancelled or hidden between two reads of one request; theoretical.
  - `[low]` `[reject]` Edge: `Answer` gives not_found when the lock is not taken (a pending row shows "no longer available") - after a 12 s lock wait on one row; the card keeps its buttons and the next press answers; rare.
  - `[low]` `[reject]` Edge: AnswersIn times out while the answer lands - same as Blind 2.
  - `[low]` `[reject]` Edge: a 200 or expired reply without a readable approval object - the route always writes the payload; no client can send it.
  - `[low]` `[reject]` Edge: an answered status with an empty answeredAt - rows past pending carry the time; same as the empty winner.
  - `[low]` `[reject]` Edge: duplicate or undefined refs in the request list - the store keys approvals by Ref, so a duplicate cannot arise.
  - `[low]` `[reject]` Edge: `approvalCtx` reads `Date.now()` once, so "Expires tomorrow" can go stale - the incident card's own `view()` does the same (6.1); the day word changes only across midnight.
  - `[false]` `[reject]` Edge: phone channel from the web page - same as Blind 1.
  - `[low]` `[reject]` Edge: `ApprovalDouble`'s single run pointer - same as Blind 8.
  - `[false]` `[reject]` Edge (claim): the cap pins the headline, not the card's top - Decided in-stage 22 records the change and why (the card's top cannot meet AC3); the AC names the headline.
  - `[low]` `[reject]` Edge (claim): `AnswersInWebRoles` rows persist after an aborted run - the class removes its user and rows at the start of the next run (AC16 (3) pins the user).
  - `[medium]` `[patch]` Gap: the card's notices for 404, 403, 5xx and a network failure had only the `answerOutcomeOf` unit test - added floor case A8 (a held reply per status, buttons restored, notice shown and announced once, next press clears it); grouped with Intent 1 and 3.
  - `[medium]` `[patch]` Gap: the compact card hiding its request cards was pinned by a source regex only - added floor case A9 (a closed incident draws no request card and gets its Show details row back).
  - `[medium]` `[patch]` Gap: the 403 body for a tool_call request and the named 409 forms were not asserted - patched (with Blind 3).
  - `[low]` `[reject]` Gap: the 500 branches of the route and the failure paths of AnswersIn/AnswerOps have no test - defensive branches that no user input reaches; the double cannot throw; cost is a double extension for no reachable failure.
  - `[low]` `[reject]` Gap: AC13's no-Allowance check scans method text - the header and no-Turn assertions run; a computed class name would be a deliberate evasion.
  - `[medium]` `[patch]` Gap (other): the online-demo required check's instance half used a session B that watched nothing, so it held with the flag off - B now has a Check on the same production, a control asserts B sees the instance request with the flag off, and the mutation `LocalFlag` always 1 turns it red.
  - `[low]` `[reject]` Gap (other): the AC2 and AC6 mutation lines record red only for the source test - one demonstrated mutation per AC is the bar, and A1/A2/A4 assert the same in the browser.
  - `[low]` `[reject]` Gap (other): A4's fixed wait - same as Blind 5.
  - `[low]` `[reject]` Gap (other): immediate absence checks of events - the events are written in AnswerOps' job before the REST reply returns (the reply waits for it), so the check follows the write.
  - `[low]` `[reject]` Gap (other): a source test asserts `bad` equals [] with no control that the regex matched - the sibling `rule()` tests in the same file fail when the regex finds nothing.
  - `[low]` `[reject]` Gap (other): the empty-winner message edge - same as Edge 3.
  - `[medium]` `[patch]` Intent: the "no longer available" page notice and the 403/5xx/0 forms exist at unit level only - A8 (with Gap 1).
  - `[low]` `[reject]` Intent: the online-demo row "by the page" has no browser case - the rule is server-side and pinned by `AnswersInProduction` and the lane-b shard; A7 runs the local form; a page press is the same call.
  - `[medium]` `[patch]` Intent: expired/403/5xx/0, count of one and the non-object dry run are covered by view-model and server tests, not by the browser - A8 covers the replies; the rest are rendered by the same view code the unit tests run (grouped with Gap 1).
  - `[low]` `[reject]` Intent: DW-68 is verified through `AnswersIn.FromPage` in a web-roles process, not over HTTP - the REST handler adds nothing privileged to FromPage, and `AnswersInProduction` runs the handler.
  - `[medium]` `[defer]` Intent: A6 runs with no status banner and the guide collapsed, which the intent does not state - true: AC3 does not hold in the default floor state in this build (Decided 23); the cause is the guide's height (Epic 4's); deferred with the probe that settles it.
  - `[low]` `[reject]` Intent: `Test/Web/Api.cls` gained a `badAnswer` constant between the ruled ranges - it is the assertion's expected body in the ruled loop (Q1); no other line changed.
  - `[low]` `[reject]` Intent: the REST handler and `AnswersIn` both check visibility - Decided 10 (404 before 400); the same `Ownership.Approval` call.
  - `[low]` `[reject]` Intent: the Telegram channel is accepted by `AnswersIn` but not the route - by design (10.3 feeds the same rule set).


## Design Notes

**Architecture decisions** (spine `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`):
- **AD-1** (L99): an answer is a production message entered through a business service (`AnswersIn` via CreateBusinessService). Answers go only through `AnswersIn`: `AnswerOps` refuses other senders, and a bridge context is refused.
- **AD-4** (L155, L176-177): ownership through `Ownership`; no client SessionRef; the instance watchers; messages carry SessionRef and never a user name.
- **AD-11** (L314-328): `AnswersIn` resolves the session from the CSP session and applies who-may-answer, then the call to `Approval.Answer(Ref, Action, Channel, IrisUser, SessionRef)` is made by its operation in a production job (Veto V1). The results, the row as the truth and the role from `RequiredRole` are the bridge's.
- **AD-12** (L330-338): full-view payloads keyed by Ref; `traceUrl` added by the web layer (`PayloadObject`).
- **AD-13** (L366-370): no unchecked prepare is added; text is bound as text; the envelope headers.
- **AD-15** (L408-447): the page never decides the incident's state. Request cards come from their own payloads.
- **AD-16** (L456): the dry run is the row's `DryRun`.
- **AD-17** (L465-471): `Answer` writes the Approval entry naming the session's IRIS user, channel and SessionRef; production jobs run as the Interoperability system user.
- **AD-20**: not turns; no allowance.
- **AD-22** (L585): the required check runs as tests in CI groups.
- **AD-26** (L737-743): SuperSession = the session's TraceRef, in a session of its own, since an answer is not a turn.
- **AD-29** (L777): only Epic 0's API and Story 0.4/0.5's shapes; the double stands in.
- **AD-30** (L830): synchronous answers.
- **AD-31** (L840-850): the HostSink fires in the job that changed state, which is now `AnswerOps`' job. BridgeSink stays the only `approval` publisher.
- **AD-32** (L861): the page renders the catalog's `answered.*` texts.
- **AD-33** (L865-873): a new item goes into the ownership tables in the same change (spine update below).
- **Conventions** (L912-943): Production item names, Messages, Identifiers, Times, REST (Veto V3), Announcements and focus, Text OcuTalon sends, Approval requests, Audit entries, Angular, Tests.
- No AC contradicts an AD's Rule, and no NFR trips Rule 5. UX-DR20's 1280×600 is a measurable layout check (Decided 9 is the means).

**Orchestrator rulings (2026-10-27, policy 36abb05, all decide; recorded by the runner at spec validation):**
- **Q1, allowed.** In `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` `TestUnseenRefIs404`, replace ONLY the `For ref = ownApproval, instanceApproval` loop (the visible-approval 501 `not_built` assertions): a bodyless post now asserts 400 `bad_answer` plus the error body. Change only the approval half of the doc sentence ("A visible ref answers 501 not_built"). Keep exactly as they are: the unseen-incident and unseen-approval 404 loops, "an incident's ref is not an approval's" 404, both onlineDemo 404 checks, and the visible-incident `DismissIncident` loop (until 6.4). The new endpoint's own HTTP tests go in a NEW test class (preferred); if one must go in `Test/Web/Api.cls`, add one self-contained block at the END of the file (Epic 16 also appends at the end and adds one line near L21: a plain union at integrate-forward). The runner reports the file under `footprint_extensions`.
- **Q2 (for 6.4, in advance).** 6.4 may replace only the visible-incident `DismissIncident` loop and the incident half of the doc sentence, on the same terms.
- **Q3.** The AD-33 Production items row `AnswerOps` | `OcuTalon.Core.AnswerOps` | B is compliance with AD-33's own Rule, written by the runner as its own new row (done at spec validation). The item's `Production.cls` entry goes in Lane B's XData region; its `Test/Core/ProductionItems.cls` row is shared by entry (add this story's row only).
- **Q4.** The Conventions REST row is extended with U-115's codes and bodies, marked `[AMENDED 2026-10-27, Story 6.2 spec validation, Epic 6 runner, veto U-115 ...]` (done at spec validation). Implement against that row.

**Owner decisions (the owner's delegate, 2026-10-27, relayed by the orchestrator; applied at spec validation, before implement):**
- **U-113** (answer 2026-10-27T09:50:36Z#345): V1 kept, with three conditions, AC14.
- **U-115** (answer 2026-10-27T09:50:36Z#347): V3's four codes and the bodies kept; the 403 check runs before the 409 checks, AC15.
- **U-116** (answer 2026-10-27T09:50:36Z#348): V4 kept, with three conditions (throwaway-only guard, random unlogged password, teardown on failure), AC16.
- U-114 (V2 texts as worded) and U-117 (V5, naming the answerer) were kept with no change.

**Spine update for the runner** (Rule 20 light path; AD-33 requires it): add the row `AnswerOps` | `OcuTalon.Core.AnswerOps` | B to the Structural Seed's Production items table, and update the REST convention row as in Veto V3.

**Decided in-stage:**
1. Request cards come from the store's `approvals` with the incident's `incidentRef`, sorted by `raisedAt`. A request without an `approval` payload, or a cancelled one, is not drawn: the card needs the dry run, and the UX has no cancelled text.
2. **Show details placement.** Show details goes to the first request card's row (right end), and the evidence panel goes below that card's row and expiry (mockup A1). The incident-level actions row stays only when no request card renders, and on a compact card, which hides request cards (6.1 Decided 9).
3. **Times.** Status and late-press times are page clock times with the zone suffix (`pageTimeBeside`, E:180). The expiry is `pageWhenBeside` ("tomorrow at 14:13"). Expired uses the row's `expiresAt`.
4. **Status texts.** Statuses and the late press render from the catalog through the generated module: `web` form, else text. No page copies. The status icons are `circle-check`, `circle-slash` and `clock` (D:823).
5. **Field and counts.** `field` is shown as published (like 6.1's `element`); `leftOut` is not shown (no UX text).
6. **Accent bar:** pending → `accent-bar-pending`; approved, executing, done → `approved`; rejected, expired, failed → `closed`.
7. **Outcome map.**
   - 200 → done; 409 `already_answered` → the late press and the payload; 409 `expired` → the payload; 404 → "That request is no longer available." (E:795); 403 → E:669.
   - Status 0 → the busy notice at once. Any other status → its `error.message`, else the busy notice.
   - A new press clears the notice.
8. **Focus.** The buttons' wrapper and the status share `data-part="answer"` and `data-key`, so the shared rule moves a lost focus to the status. The card calls `keepFocus` itself because a local or approval update doesn't change the chat's entries.
9. **Follow-bottom cap.** While the list follows the bottom and the newest entry is an incident card taller than the remaining view, the follow stops at that card's top, so the 1280×600 parts stay in view. A later entry follows to the bottom as before. Spacing uses DESIGN tokens only.
10. **Check order (REST).** The REST handler checks session, then visibility (404), then body (400), then `AnswersIn`. This keeps an unseen ref at 404 whatever its body (api.spec row 16), and needs no production for 404 and 400. `AnswersIn.OnProcessInput` applies the rules again for every entry; it is the one rule set Story 10.3 reuses.
11. `AnswersIn` refuses inside a bridge context (a tool's job), because N-risky actions wait for a person.
12. `AnswerOps` accepts only `AnswersIn`'s messages (header `SourceConfigName`).
13. `AnswersIn` waits 30 s for `AnswerOps` (`Answer` can take about 12 s: a 7 s lock wait plus a 5 s task wait). The page restores at 10 s, and a later answer shows.
14. Story 6.2 renders the approved, rejected and expired statuses, because Reject is pressable here and a 409 can be expired. 6.4 adds Dismiss, the Open handling and the results.
15. **DW-113's pin** uses `Test.Bridge.WebStatus`'s web-request context (Job plus one-argument Login as a fixture user with exactly the application roles). The fixture-user helper is copied, about 10 lines, because `WebStatus.CreateUser` is private in Lane A's class (AD-33).
16. **Floor budget.** The floor was about 400 s of 540 s after 6.1. A1 is `@browsers`, the rest Chromium. If `live floor` passes 510 s, fold A3's Reject into A2 and A5 into A3, and record it.
17. `seedApproval`'s new options keep today's defaults, so the rail and floor callers are unchanged.
18. Two Lucide icons are added to the bundled set (same ISC source as the rest, no new dependency).

19. **Implement stage, hand-off wiring.**
    - `AnswersIn.FromPage` also outputs `sessionRef`, and `Msg.AnswerResult` carries `Result` plus the winner's three fields. `OnProcessInput` answers OK with an `AnswerResult` for `not_allowed`, `not_found` and `bad_answer`, and an error status only for a failed read, a failed send or no `AnswerResult` back.
    - `Web.Api.Fail` takes an optional fourth argument, the request's payload, written after `error` for a 409; `AnswerBody` and `AnswerResponse` are the route's new private helpers.
    - `AnswerApproval` releases its visibility row (`Kill row`) before `FromPage`, because `AnswerResponse` re-reads the request through `Ownership.Approval` and an open object would otherwise show the state from before the answer (the cache of an open persistent object, found by `AnswersInProduction`).
20. **View context.** `approval-view.ts` imports types only, so the catalog's `renderPageText` and the rail's `approvalTitle` come in through the context (`render`, `title`) beside `timeBeside` and `whenBeside`; `approvalContext` (in `approval-request-card.ts`) builds it from the page's real modules. The tests pass the real ones.
21. **Dry run layout.** The "Dry run" label and the count line share one row (mockups/main-page.html), and the card's spacing uses the 4 px and 8 px tokens, so that the five parts of AC3 fit the list.
22. **Follow-bottom cap (changes Decided 9).** The cap puts the incident card's *headline* (not the card's top) at the list's top, below its scroll padding: the chip row scrolls out above it. The card's top cannot give AC3: the card is 466 px from its top to the bottom of Approve and the list is 279 to 356 px high at 1280x600.
23. **A6's conditions.** At 1280x600 the floor stack's list is 279 px: the header 56, the no-key banner 44, the open guide 139 (its Break the feed box is 138 tall), the dock 82. A6 therefore runs under DESIGN.md's acceptance conditions: the snapshot's `status` is emptied (no banner) and Hide guide is pressed (the bar plus the box leave 106 px), which leaves a 356 px list. Without them AC3 does not hold in this build (open question for the owner: the guide's compact form of 56 px is not reached while its box is 138 px tall, which is Epic 4's).
24. **Fixture role.** The test process runs as irisowner (role %All), not as the README account, so `AnswersInProduction` gives its rows the first role of the process user's recursed role set (`HeldRole`) in place of "OcuTalonUser"; the browser cases use "OcuTalonUser" for the floor user, who holds it.
25. **The throwaway-only marker (AC16).** `AnswersInWebRoles.Reason` is empty only when `Test.Contract.Mock.MissingReason` is (OCUTALON_MODEL_BASE_URL is the mock's base URL and OCUTALON_MOCK_KEY_HEADER is 1: set only by `ci/compose.ci.yml`, so the demo host, a user's instance, an IPM test run and a slot do not carry them) and OcuTalon.Production runs. No contended file changed.
26. **Task 0 outcome.** The checked reads fail in a web-roles process, so `AnswersInWebRoles` keeps both its DW-113 and its DW-68 tests; `%CSP.Session.%New(id, 0)` works there, so no `StubSession`; DW-113 stays resolved (nothing added to `deferred:`).

27. **Review patch: the cap yields to focus.** `headlineTop` returns nothing while focus is inside the newest incident card, so a press on Show details (or on Approve) is followed to the bottom as before and the opened panel shows; A6 presses Show details at 1280x600 and expects the panel in view.
28. **Review patch: browser cases A8 and A9** (floor, Chromium): A8 fulfils the answer route with 500, 403, 404 and a network failure; A9 closes the incident. Floor time with both: 476 s of 540 s (Decided 16 not needed). `inOrder` reads the tops in one evaluation so that a scroll between reads changes nothing.

**Veto-window choices** (the runner files them):
- **V1 (security posture: where the answer runs).** Choice: `AnswersIn` (the request's process) resolves the session and applies the rules. A new business operation `AnswerOps` (pool 1) reads the session's IRIS user and calls `Approval.Answer` in its production job, with the Interoperability system user's privileges, so the fan-out and Answer's role-set read and Workflow query succeed (DW-68).
  - Rejected: `Answer` in the REST process (DW-68 stays, and `HoldsRole`/`HoldTask` need privileges the user lacks, inference until Task 0); an AD-13 allow-list amendment (not this runner's); any grant to `OcuTalonUser`.
  - Reversing: drop the item and call `Answer` from `AnswersIn`.
- **V2 (public texts not in the UX).** Sources:
  - `ruled` 'Story 6.2 veto item V2':
    - fixed-targets for one, "Approving runs exactly this change on this {noun}, without asking the model again. New failures need their own approval.";
    - Will resend values, "{count} repaired copies; the originals stay unchanged." and "1 repaired copy; the original stays unchanged." (mockup `states.html:369`, E:692);
    - "Reject: {action}" (`main-page.html:479`);
    - the API's 400 `MESSAGEBADANSWER` "An answer needs an action, approve or reject, and a channel, web or phone.";
    - the API's 403 for other kinds, `MESSAGENOTAPPROVERTOOL` "Only an approver can answer this request.".
  - Reusing E:795's Telegram alert sentence on the card.
  - Rejected: new wording beyond the mockups. Reversing: the constants plus their `ruled` entry.
- **V3 (REST conventions).** Choice: the REST row gains 400 `bad_answer`, 403 `not_allowed`, 409 `already_answered` and `expired`. A 409 body carries the request's `approval` payload beside `error`, and a 200 body is `{"result":"done","approval"}`.
  - Rejected: reusing `bad_message`/`not_found`; 409s without the payload (the card would wait for the event).
  - Reversing: rename the codes and edit the row.
- **V4 (test fixture user).** Choice: `AnswersInWebRoles` creates and deletes its own IRIS user (OcuTalonUser plus the application roles) on throwaways only. Rejected: a seam in Ownership or Session (Epic 16's, a product test hook). Reversing: delete the class (DW-113 reopens).
- **V5 (who is named).** Choice: name the answerer only when not on the online demo and when `answeredBy` ≠ the signed-in user (case-insensitive), on the page and in the 409 message. This is a subset of E:189's "local install with more than one user": a single-user install never names. Rejected: a user-count flag in `/state` (contended snapshot shape). Reversing: one view rule plus the server rule.

**Texts** (`APPROVAL_TEXTS`, exact; sources for `ux-strings`):
- `ux`: "Approval needed", "Approval request" (E:278); "Approve", "Reject", "Approve: {action}" (E:280); the fixed-targets line with {count} {noun} (E:663); "Dry run", "{count} {noun} affected", "Before", "After" (D:824); "Will resend" (E:782); "Nothing has changed yet."; "Only an approver for resends can answer this request." (E:669); "That request is no longer available." (E:795).
- `ac` 'Story 6.2: Approve or reject a fix from the web chat': "Expires {when}"; "Couldn't reach OcuTalon. Try again. Nothing was changed. The request is still waiting.".
- `ruled` V2: listed above.
- The action "{title}." takes its title from `approvalTitle` (`design`). Statuses and the late press come from the catalog (no constants). Show details reuses `INCIDENT_TEXTS.showDetails`.
- Server parameters: `MESSAGENOTAPPROVER` (E:669), `MESSAGENOTAPPROVERTOOL` and `MESSAGEBADANSWER` (V2). The 409 messages come from `Catalog.Render`.

**Files and footprint classes:**
- **footprint:**
  - `Core/AnswersIn.cls`;
  - `Test/Core/{AnswersIn,AnswersInProduction,AnswersInWebRoles,ApprovalDouble,AnswerOpsProbe,AnswersInProbe}.cls` (new);
  - `web/src/app/approvals/{approval-view,approval-request-card}.ts` (new);
  - `web/src/app/incidents/{incident-card,incident-view}.ts`;
  - `web/src/app/chat/chat-panel.ts`.
- **shared-by-entry:** `Web/Api.cls` (`AnswerApproval`, this route's entry, plus three parameters; away from Epic 5's L598-638), `Test/Core/ProductionItems.cls` (own rows), `web/src/app/api/{api-client,api-types}.ts` (own entries).
- **shared-by-region:** `Production.cls` (the Lane B region).
- **extension** (outside the footprint, no contended owner):
  - `Core/AnswerOps.cls` and `Core/Msg/{Answer,AnswerResult}.cls` (new);
  - `web/scripts/catalog.mjs`, `web/src/app/msg/catalog.ts` (generated), `web/src/app/icon/icon.ts`;
  - `web/scripts/{catalog,ux-strings,announce-focus-sources,incident-sources}.test.mjs`, `web/scripts/{approval-view,approval-sources}.test.mjs` (new);
  - `web/e2e/support/iris.ts`, `web/e2e/floor/approval.spec.ts` (new).
- **contended, allowed by ruling Q1:** `Test/Web/Api.cls` (Epic 16): only the visible-approval loop (L686-689) and the approval half of the doc sentence (L642-645); new endpoint tests in a new class, or one block appended at the end.
- No new CI unit, group or workflow: the Test/Core classes join shard `lane-b` automatically (`ci/units.sh` L18, `ci/iris.sh` L134-142), and the floor spec joins `live floor`.

**Extend, don't copy (Rule 2):**
- **Server:**
  - `AnswersIn.FromPage` follows `Commands.Submit`/`Api.Post`, and its `Send` seam follows `CommandsIn.Send`.
  - `AnswerOps` follows `SettingsOps`/`PartnerTrigger` (it reads the session row for the IRIS user, AD-4).
  - The probes follow `CommandsInProbe`/`CommandsRouting.NewProbe`.
  - The HTTP tests reuse `Test.Web.Api.Written` and `StubRequest.MakeBody`.
  - The REST visibility pre-check is the same `Ownership.Approval` call the stub makes, not a copy of rules (Decided 10).
- **Web:**
  - The buttons reuse `BusyState`, `InlineNotice`, `Icon` and `controls.css`. `ServerButton` is not reused because one instance owns one busy state and a fixed notice, and two buttons must share one state and the longer notice.
  - `approvalTitle` is imported from the rail; the times come from `page-time.ts`; the statuses from the generated catalog; the panel is `app-evidence-panel`.
- **Tests:** the fixture-user helper is copied (Decided 15).

**Integration ACs (Rules 1 and 2):**
- The approval request card (consumer) calls the endpoint in a real browser, and the status replaces the buttons (A2, A3, A5; AC7, AC8).
- `BridgeSink` (consumer of `AnswerOps`' `approval.answered`, real production) publishes to every recipient from the production job (AC9).
- The real gate's events reach the stream through `BridgeSink` (AC12).

**Consumes:** Epic 0 / Story 3.5 / 3.7 `Approval.Answer`; Story 2.2 `Ownership`; Story 2.8 `BridgeSink`, `Session.Recipients` and the rail's `approvalTitle`; Story 3.2 the gate; Story 0.4/0.5 `ApprovalRequest.DryRun` and `Live.Payload.Approval`; Story 6.1 the incident card and evidence panel; Story 2.12 the focus rule and Announcer; Story 2.5 the generated catalog.

**Consumed-by:**
- **6.3:** the endpoint with channel `phone` and the same busy rule; the rail row's focus jump to `[data-part="approval"]`; the answer announcements.
- **6.4:** result bands under a request card; Dismiss after a rejected or expired status.
- **10.3:** `AnswersIn.FromTelegram`, feeding the same `OnProcessInput`. `AnswersIn` answers `not_found` for both "unknown" and "can't see"; AD-11's Telegram codes `unknown`/`not_visible` need an Ownership read from Epic 16 to tell them apart.
- **12.7:** calls it. **16.9:** checks Approve and Reject at the caps.

**Ledger inbox:**
- **DW-68** is addressed by Tasks 2-3 (the answer and its fan-out in `AnswerOps`' job, Veto V1) and Task 11 / AC9 (the real web-roles answer reaches both watchers).
- **DW-113** is addressed by Task 11 / AC10 (the failing branches of `Watchers`, `ApprovalIncident` and `Recipients`' pass-through, in a real privilege-limited process), with Task 0's measured fallback.
- **DW-199** is addressed by Tasks 9-10 / AC11.
- **DW-98** is addressed by Task 10 / AC12.

## Verification

`<B>` means `OCUTALON_LOCK_DIR=<main checkout>/.worktrees/.coordination/locks/lane-b OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=6 stage=implement'`.
- **Tags:** fresh `e6s2i` and warm `e6s2iw`. Run `<B> OCUTALON_RUN_TAG=e6s2iw ci/warm.sh up` once, and `ci/warm.sh down` at the end, also after a failure.
- One command per foreground call, with `timeout: 600000`. One `iris_execute_tests` per message.
- Slot B (`ocutalon-slot-b`, `OCUTALON`, build 154) is for loading, compiling and exporting storage only.
- `AnswersInWebRoles` runs only on throwaways.

**Browser cases** (`web/e2e/floor/approval.spec.ts`; FLOOR user; browser UTC/en-GB; the page clock fixed at 14:30 UTC of one `DAY`; seeded rows with RequiredRole OcuTalonUser, `expiresAt` the next day at 14:13 UTC, and dry run 50/50 OrderDate 10/16/2026 → 2026-10-16). "HH:MM" is the row's `AnsweredAt` (the server's real clock), read back through iris and formatted in UTC, so the expected text is exact.
- **A1** (`@browsers`): the pending card's parts, texts and order; Approve and Reject classes and names; Show details last in the row with `aria-expanded`/`aria-controls`; its panel below the row; the expiry; no "Why:"; the dry-run tokens (mono, danger-ink, success-ink); no incident-level Show details row.
- **A2:** Approve. Both buttons are busy, then the status "Approved from the web chat at HH:MM" is in the row with focus on it. The label changes, the three lines go and the dry run stays. Through iris: the row is approved, with AnsweredChannel web, AnsweredBy FLOOR, and one AnswersIn→AnswerOps header with FLOOR's TraceRef.
- **A3:** two requests of one incident. The cards are in raised order, with Show details only in the first card's row. The second is seeded approved by "zzsam" from phone and reads "Approved by zzsam from the simulated phone at HH:MM". Reject on the first gives "Rejected from the web chat at HH:MM. Nothing was changed.".
- **A4:** the POST is held by `page.route`, and two presses give one request. Spinner, `aria-busy` and `aria-disabled`, and no `disabled`. At 10 s the buttons are restored, and the notice is shown and announced. On release, the status shows and the notice clears.
- **A5:** `answerQuietly` answers on phone first. The press then gets the 409 notice "Already answered: approved from the simulated phone at HH:MM." (announced) and the approved status.
- **A6:** at 1280×600, the headline, cause, "50 orders affected", Approve and Reject are `toBeInViewport` (ratio 1) without scrolling.
- **A7:** the page context posts to another fixture session's request: 404 `not_found`, and the row stays pending.

**Commands:**

`(loop)`:
- `npm --prefix web test` -- expected: every node test passes, including `approval-view`, `approval-sources`, `catalog`, `ux-strings`, `announce-focus-sources` and `incident-sources`.
- `npm --prefix web run lint` -- expected: exit 0.
- `node web/scripts/catalog.mjs --check` -- expected: exit 0, after `npm --prefix web run catalog`.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s2iw ci/iris.sh class OcuTalon.Test.Core.AnswersIn` -- expected: `CLASS ... passed`.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s2iw ci/iris.sh class OcuTalon.Test.Core.AnswersInProduction` -- expected: passed. It takes about 5 s per real answer on a fixture row.
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s2iw ci/iris.sh class OcuTalon.Test.Core.AnswersInWebRoles` -- expected: passed (Task 0 first).
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s2iw ci/iris.sh class OcuTalon.Test.Web.Api` -- expected: passed, with TestUnseenRefIs404's new 400 (after the ruling).
- `<B> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e6s2iw ci/iris.sh class OcuTalon.Test.Install.Production` -- expected: passed (the item oracle and the XData match).
- `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh build` -- expected: the image and the web bundle build. Run it before a browser run that should see changed web code.
- `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh live floor` -- expected: PASS in all three projects, A1-A7 and 6.1's I1-I11 included. Record the time; the target is under 510 s against 540 s (Decided 16).

`(once)`:
- `bash docker/tests/test-web-build.sh` -- expected: passes (payloads, catalog and token checks, budgets).
- `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh shard lane-b` -- expected: every class passed.
- `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh shard lane-a` -- expected: every class passed (`Test.Install.Production` reads the oracle).
- `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh live production` -- expected: PASS. AnswerOps has an Alive job, and AnswersIn is no stub.
- `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh live sign-in` -- expected: PASS with an unchanged case count, at about 447-463 s; api.spec row 16 still gives 404.
- `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh live demo-path` -- expected: PASS, with 04 and 05's `11.1` parts still skipped.
- `bash ci/checks.sh` -- expected: exit 0 (storage blocks, boundaries, ASCII).
- `<B> OCUTALON_RUN_TAG=e6s2iw ci/warm.sh down` and `<B> OCUTALON_RUN_TAG=e6s2i ci/iris.sh teardown` -- expected: only this stage's projects removed.

**Shared surfaces:**
- **The production's items:** `Production.cls`'s Lane B region and the `Test.Core.ProductionItems` oracle, which `Test.Install.Production` and `docker/tests/test-production.sh` read. AnswersIn is no longer a stub, and AnswerOps is added.
- **Test.Web.Api:** `TestUnseenRefIs404`'s visible-approval assertion (Task 7, blocked).
- **The incident card's anatomy:** 6.1's `incident-sources.test.mjs` and floor I3. When approvals with the incident's ref are in the store, Show details moves.
- **Specs that seed approvals:** `rail.spec.ts` L138-199 and `support/floor.ts:172` seed approvals with an `incidentRef`. While a matching incident card is in the chat, they now draw request cards.
- **The chat's `[data-part]` items:** the nested `approval` and `answer` parts, through `showNew`, `FOCUS_RULE` and floor counts of `[data-part="incident"]`.
- **Inventories:** the generated catalog (`PAGE_TEXTS`, `catalog.test.mjs`), the `ux-strings` inventory, the `announce-focus-sources` speakers and focus hosts, and `IconName`.
- **The FLOOR session's chat, approvals and stream:** each case cleans its rows.

Standing criterion: every test added or changed passes on a fresh environment, in either order.

**Task 0 measurements** (implement stage, warm throwaway `e6s2iw`, a job logged in with the one-argument `$SYSTEM.Security.Login` as a fixture user whose roles are exactly `OcuTalonUser,%DB_OCUTALON_CODE,%DB_OCUTALON_DATA,%DB_OCUTALON_PRIVATE`; `$SYSTEM.Security.Check("%Admin_Secure","USE")` is 0 there):
- `Ownership.Watchers`, `Ownership.ApprovalIncident` and `Session.Recipients("instance", incident)` each return `""` (a list of 0 for the first and third) with the error status `ERROR #5540: SQLCODE: -99 Message: User ... is not privileged for the operation`. In the test process the same reads return the two watchers and the incident. DW-113 is measured, not inferred.
- `Approval.Answer` called directly in that job on a fixture instance request returned `done` after 5.11 s (`HoldsRole` of the job's own user works without `%Admin_Secure:USE`; the 5 s is the wait for the hold's task, which a fixture row does not have) with winner `{}`. Of the two answers made in the job (one directly, one through `AnswersIn.FromPage`) the two watching sessions' streams each got exactly one `approval` event, so the direct answer's fan-out published nothing (DW-68) and `AnswerOps`' did. `AnswersIn.FromPage` in the job returned `done` in 5.42 s. Not measured: the completion of a real hold's task from a web-roles job (a fixture row has no hold); `HoldTask` is the same kind of checked SQL read.
- `%CSP.Session.%New(id, 0)` works in the job (an object), so `StubSession` is not needed.

**Run times** (final tree, after the review patches): `ci/iris.sh live floor` PASS in 476 s of its 540 s deadline (123 tests across Chromium, Firefox and WebKit; A1-A9 included, A1 in all three engines); `shard lane-b` 61 classes passed in 185 s; `shard lane-a` 47 classes in 446 s; `live production` 115 s; `live sign-in` 449 s (217 passed); `live demo-path` 95 s (2 of 6 steps ran, 8 skipped for Story 11.1, 0 failed); `bash ci/checks.sh` and `bash docker/tests/test-web-build.sh` pass; warm: `AnswersIn` 0.2 s, `AnswersInProduction` 15.5 s, `AnswersInWebRoles` 5.6 s, `Test.Web.Api` 1.0 s, `Test.Install.Production` 0.4 s; `npm --prefix web test` 836 tests pass; `npm --prefix web run lint` and `node web/scripts/catalog.mjs --check` exit 0; `Test.Bridge.CodeRules`, `Test.Msg.Catalog`, `Test.Web.PublicTexts`, `Test.Core.BridgeSink` and `Test.Core.CommandsRouting` passed warm in the first pass.

**Recorded mutations** (Rule 19; each applied, red observed, restored from the scratchpad backup and checked byte-identical):
- mutation: AC1 `requestsOf` drops the `raisedAt` sort -> `approval-view.test` ("are the approvals with the incident's ref, in raisedAt order"); A3 checks the order in the browser.
- mutation: AC2 Before and After swap their tokens in the card's styles -> `approval-sources.test` ("draw Before in the danger ink and After in the success ink"); A1 reads both colours in the browser.
- mutation: AC3 `scrollToBottom` stops using `headlineTop` (the list goes to the bottom) -> A6 red (observed in the browser run: the headline was out of view).
- mutation: AC4 `AnswersIn` skips the `Ownership.Approval` result check -> `Test.Core.AnswersIn` ("request ... is not_found", four requests).
- mutation: AC4 `AnswerResponse` answers 404 for `expired` -> `Test.Core.AnswersInProduction` (`TestExpiredRequestAnswersExpired`).
- mutation: AC5 the REST pre-check and `AnswersIn` both skip the `Ownership.Approval` result -> `Test.Core.AnswersInProduction` (`TestOnlineDemoOtherSessionIsNotFound`: B's answer is not 404, the request is not pending).
- mutation: AC6 the second button gets its own `BusyState` -> `approval-sources.test` ("share one BusyState") and A4 red in the browser (two requests).
- mutation: AC6 `aria-disabled` replaced by `disabled` -> `approval-sources.test` ("go busy together").
- mutation: AC7 the status `p` loses `data-part="answer"` -> `approval-sources.test` and A2 red in the browser (focus is not on the status line).
- mutation: AC8 the late press renders the done text (`answered.approved`) -> `approval-view.test` (four tests of "the late press"); A5 reads the notice in the browser.
- mutation: AC9 `AnswersIn` calls `Approval.Answer` itself instead of `Send` -> `Test.Core.AnswersInWebRoles` (`TestInstanceAnswerReachesBothWatchers`: neither session got the event).
- mutation: AC10 `Session.Recipients` drops `Watchers`' status (Epic 16's file, temporary, restored, `git diff` of it empty) -> `Test.Core.AnswersInWebRoles` (`TestWatcherReadsFailInAWebRequest`).
- mutation: AC11 `AnswerOps` passes "" as the sessionRef -> `Test.Core.AnswersIn` (`TestMalformedSessionRefNeverReaches`, `TestWatcherReachesInstanceRequest`).
- mutation: AC12 the gate test's sink is `OcuTalon.Bridge.Ext.HostSink` -> `Test.Core.AnswersInProduction` (`TestGateStepAndHeldCallReachTheStream`: no `turn.step`).
- mutation: AC13 `AnswersIn` leaves `%SuperSession` unset -> `Test.Core.AnswersIn` (`TestHandOffIsTracedToTheSession`); `AnswersIn` names `Allowance` -> `Test.Core.AnswersIn` (`TestNoAllowanceOrConversation`).
- mutation: AC14 `AnswerOps` answers as another user (the running item restarted before the run) -> `Test.Core.AnswersInProduction` (`TestApproveRecordsTheAnswer`); `AnswersIn` hands over another SessionRef -> the same; `AnswerOps` takes any sender -> `Test.Core.AnswersIn` (`TestAnswerOpsRefusesOtherSenders`).
- mutation: AC15 `AnswerResponse` has no 403 branch -> `Test.Core.AnswersInProduction` (`TestRoleRefusalsComeBeforeTheOtherChecks`: the approved, past-expiry and expired requests).
- mutation: AC16 `Reason` allows everything -> `Test.Core.AnswersInWebRoles` (`TestGuardRefusesOutsideAThrowaway`, five cases); the end-of-test hook leaves the user -> `Test.Core.AnswersInWebRoles` (`TestFixtureUserIsRemoved`).
- mutation: AC3/AC7 (review patch) `headlineTop` ignores focus (the exemption removed) -> A6 red in the browser (Show details' panel is not in view).
- mutation: AC4/AC8 (review patch) `AnswerResponse` sets `named` to 0 -> `Test.Core.AnswersInProduction` (`TestLatePressNamesAnotherUserOnALocalInstall`: the approval and the rejection by another user).
- mutation: AC5 (review patch) `Ownership.LocalFlag` always 1 (Epic 16's file, temporary, restored, `git diff` byte-identical) -> `Test.Core.AnswersInProduction` (`TestOnlineDemoOtherSessionIsNotFound`: session B, who watches the production, answers the instance request).
- mutation: AC4 (review patch) `noticeOf` returns "" for `gone` -> A8 red in the browser (the 404 notice does not show).
- mutation: AC1/AC7 (review patch) the compact card draws its request cards (`view().compact ? [] :` removed) -> A9 red in the browser.

**Planned mutations (Rule 19).** Apply each, observe red, revert, confirm that `git status --short` and `git diff --stat` are unchanged, and record it as `mutation: ... -> ...`.

| AC | Mutation | Expected red |
| --- | --- | --- |
| 1 | `requestsOf` drops the `raisedAt` sort | `approval-view.test`; A3 |
| 2 | Before/After swap their tokens | `approval-sources.test`; A1 |
| 3 | the follow-bottom cap removed (with a tall card) | A6 |
| 4 | `AnswersIn` skips `Ownership.Approval` | `Test.Core.AnswersIn` (another session's request reaches the double) |
| 4 | the REST maps `expired` to 404 | `Test.Core.AnswersInProduction` |
| 5 | the REST pre-check and `AnswersIn` both skip `Ownership.Approval` | `AnswersInProduction`'s required-check test (B's answer is recorded) |
| 6 | the second button gets its own `BusyState` | A4 (two POSTs) |
| 6 | `aria-disabled` replaced by `disabled` | `approval-sources.test` |
| 7 | the status `p` loses `data-part="answer"` | A2 (focus to the section, not the status) |
| 8 | the late press uses the done text | `approval-view.test`; A5 |
| 9 | `AnswersIn` calls `Approval.Answer` itself instead of `Send` | `AnswersInWebRoles` (S2 gets no event) |
| 10 | `Session.Recipients` drops Watchers' sc (temporary, reverted; Epic 16's file) | `AnswersInWebRoles` |
| 11 | `AnswerOps` passes "" as sessionRef | `Test.Core.AnswersIn` |
| 12 | sink "OcuTalon.Bridge.Ext.HostSink" in the gate test's context | `AnswersInProduction` (no turn.step) |
| 13 | `AnswersIn` leaves `%SuperSession` unset | `AnswersInProduction` (the header is not tagged). A guard in `Test.Core.AnswersIn` reads both classes' method code from `%Dictionary` and finds no `Allowance` or `Conversation` reference |

## Auto Run Result

Status: done
Blocking condition: none

- **Implemented.** The answer endpoint goes through `AnswersIn` (session from the CSP session, who-may-answer, bridge-context refusal) to the new `AnswerOps` operation, which calls `Approval.Answer` in a production job (DW-68, DW-199); `AnswerApproval` maps done/409/403/404/400 with the request's payload. The page draws one approval request card per request inside the incident card (dry run, shared busy rule, statuses and late press from the catalog, focus rule), with the follow-bottom cap for 1280x600. DW-113, DW-199, DW-98 and the owner's conditions U-113, U-115 and U-116 (AC14-AC16) are pinned by `Test.Core.AnswersIn`, `AnswersInProduction` and `AnswersInWebRoles`.
- **Files changed.** Server: `Core/AnswersIn.cls` (rebuilt), `Core/AnswerOps.cls`, `Core/Msg/Answer.cls` and `AnswerResult.cls` (new), `Production.cls` (item), `Web/Api.cls` (`AnswerApproval`, helpers, three messages, `Fail` payload), `Test/Core/ProductionItems.cls` (rows), `Test/Web/Api.cls` (ruled Q1 loop and doc sentence only); tests `Test/Core/{AnswersIn,AnswersInProduction,AnswersInWebRoles,ApprovalDouble,AnswerOpsProbe,AnswersInProbe}.cls`. Web: `approvals/{approval-view,approval-request-card}.ts` (new), `incidents/incident-card.ts`, `chat/chat-panel.ts`, `api/{api-client,api-types}.ts`, `icon/icon.ts`, `msg/catalog.ts` (generated) and `scripts/catalog.mjs`; tests `scripts/{approval-view,approval-sources}.test.mjs` (new), the four updated script tests, `e2e/support/iris.ts` and `e2e/floor/approval.spec.ts` (A1-A9).
- **Review findings.** 42 findings: 9 medium and 1 low patched (server tests for the 403 text and the named 409, the online-demo required check with a watching session B, floor cases A8 and A9, the cap's focus exemption with A6's Show details check, a split class-doc line); 1 medium deferred (AC3 holds only with the guide collapsed and no banner: Epic 4's guide height); 31 rejected (3 false, 28 low) with their reasons in the Review Triage Log.
- **Follow-up review recommended: true.** Five medium entries were patched (two or more). The unverified risk: the cap's focus exemption in `chat-panel.ts` is pinned only by A6 in Chromium; its interplay with other focus moves (the Announcer, `keepFocus` after a status replaces the buttons) has no case.
- **Verification.** All `(loop)` and `(once)` commands of `## Verification` passed on the final tree (run times above); every AC has a recorded mutation.
- **Footprint extensions.** `Test/Web/Api.cls` (ruling Q1); `Data/Ownership.cls` and `Data/Session.cls` were edited only temporarily for mutations and restored byte-identical. `web/scripts/catalog.mjs` gained the `channel` and `text` slot types (Epic 5's 5.7 may touch the same lines at integrate-forward).
- **Residual risks.** AC3 depends on the guide being collapsed (deferred); the real hold's task completion from a web-roles job was not measured (fixture rows have no hold).
