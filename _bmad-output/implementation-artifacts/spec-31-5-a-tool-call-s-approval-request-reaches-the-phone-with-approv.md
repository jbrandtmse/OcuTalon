---
title: 'Story 31.5: a tool call''s approval request reaches the phone with Approve and Reject (notices)'
type: 'feature'
created: '2026-11-02'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad/custom/skill-rules.md'
warnings: ['oversized']
deferred:
  - summary: 'Telegram press alert for an approved tool call: AnswersIn.TelegramCode answers approved with no count or noun for a tool_call (no dry run), and TelegramIn renders press.approved ("Approved. Repairing and resending {count} {itemNoun}."), which has no tool-call form'
    evidence: 'Core/AnswersIn.cls :86-100 (slots from the dry run only); Msg/Catalog/Core.cls press.approved :52-58; TelegramOut is a stub on this branch (Channel/Telegram/Out.cls :1-14)'
    location: 'src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls (Epic 12), Story 31.4'
    severity: 'med'
---

<intent-contract>

## Intent

**Problem:** A risky tool call's approval request reaches no phone and no paired chat: `BridgeSink` publishes the `approval` live event for a `tool_call` row but sends no `Notification`, so there are no Approve and Reject buttons, no in-place answered line and no result message (AD-31, AD-32). An old held tool call that Decide closes as failed (Story 30.3, U-170) shows its plain-English reason only in the decision event (DW-454).

**Approach:** `BridgeSink` sends a tool call's notices through the existing `Notice` seam (`NoticesIn`), keyed from the request's row, exactly as `IncidentManager` sends a fix's:
- `approval.raised` sends kind `approval`;
- `approval.answered` and `approval.expired` send kind `answered`, which edits the request message in place;
- `approval.result` sends kind `result`, a new message with no buttons;
- an old held row instead gets one `result` notice that carries its reason, from `decision.recorded`.

Four `toolCall.*` keys are appended to `Msg.Catalog.Core`. `SimPhoneOut`'s answered edit only ever lands on a request message.

**Web chat card [AMENDED 2026-11-02, Story 31.5, Contest Planner under the owner's delegation: "The web-chat tool-call approval gap is 1.0.0-VISIBLE: PUT IT INTO 31.5"; it was a `deferred:` item].** A tool call's approval request also appears in the web chat, as a card with Approve and Reject (FR-8; PRD "Channels": the web chat, the simulated phone and the paired chat, with inline Approve and Reject). Its texts are the phone's (the U-212 conditions below), it is answered once with the first answer winning across every copy (web chat, simulated phone, paired chat), and its result shows as a new message with no buttons. It reuses the fix card's component (`web/src/app/approvals/approval-request-card.ts`, today drawn only inside an incident card) and the existing approval API (`ApiClient.answerApproval`, `POST /ocutalon/api/v1/approvals/:ref/answer`) -- Rule 2: extend, don't copy; the plan names the sibling it extends under Design Notes.

## Boundaries & Constraints

**Always:**
- **Which rows get notices.** `BridgeSink` sends tool-call notices only when all of these hold:
  - the request's `Kind` is `tool_call`;
  - the owner is a session that exists (`Data.Session.RefIndexExists(ownerRef)`);
  - the row reads through `Ownership.Approval(ref, ownerRef)`;
  - the row is **replayable**: `ToolSource` and `Runner` are both set, the inverse of `Decide.HeldBeforeUpdate`.

  Kind `fix` is `IncidentManager`'s, and `setting` is its owner's (AD-11), so neither ever gets one from `BridgeSink`. An owner that is `instance`, `eval`, or a Ref with no session sends nothing.
- **What each event sends.** Every notification is built from the row as read, never from the event's order:

  | Event | Kind | Key and slots |
  |---|---|---|
  | `approval.raised` | `approval` | `toolCall.request` {`tool` = ToolName, `server` when it is known (U-212 (1)), `inputs` = `Bridge.Redact.Text(ToolArguments)` on one line and capped at 200 characters (U-212 (2)), or `{}` when that is empty} |
  | `approval.answered` | `answered` | from the row's `AnsweredAction`, not its `State`: `approve` gives `answered.approved` and `reject` gives `answered.rejected`, both {`channel` = AnsweredChannel, `time` = AnsweredAt}; an empty action sends nothing |
  | `approval.expired` | `answered` | `answered.expired` {`time` = ExpiresAt} |
  | `approval.result` | `result` | `Result` `done` gives `toolCall.done`; `failed` or `interrupted` gives `toolCall.failed`; both {`tool`, `time` = FinishedAt}. An empty Result or FinishedAt sends nothing |
  | `approval.cancelled` | none | nothing, as for a fix |

- **What every notification carries.**
  - `SessionRef` is the owner.
  - `ApprovalRef` is the row's `Ref`.
  - `IncidentRef` is the row's `IncidentRef`, empty for a gate-held call.
  - `DecisionRef` is empty, except on the DW-454 notice.
- **DW-454: an old held row (`ToolSource` or `Runner` empty).** Its `approval.result` sends nothing. On `decision.recorded`, `BridgeSink` acts only when all of these hold:
  - the Decision row has `Kind` `tool`, `Fallback` 1, and a first `Reasons` line that is not empty;
  - its `ItemId` names, through `Ownership.Approval`, the session's `tool_call` row;
  - that row is `failed` and not replayable.

  Then `BridgeSink` does two things:
  - It sends one kind `result` notice, `toolCall.failedWithReason` {`tool`, `reason` = that first line}, with `DecisionRef` set to the decision's Ref.
  - It publishes one `approval` event: `Live.Payload.Approval.FromRow(row, owner)` with `Reason` set to the same line.
- **U-212: the texts (veto, kept by the Contest Planner under the owner's delegation with four conditions, `at=2026-11-02T13:19:05Z#648`).** Verbatim: "Keep, with four conditions. (1) Match the card: the first line is 'Run {tool} on {server}' when the server is known, and 'Run {tool}' only when it isn't. (2) {inputs} stays on one line through the bridge's redactor, and is capped at 200 characters, ending with '…' when cut; the phone and paired chat never get more of a call's inputs than the card shows. (3) {reason} in toolCall.failedWithReason is only ever a catalog reason (such as U-214's), never raw error or exception text; a test pins it. (4) {time} uses the same labelled form as the other catalog times (DW-574 will unify zones later). The Q3 reading (answer edits the request in place; the result is a new message with no buttons, as for a fix in Story 6.4) is kept." So:
  - (1) The request's first line, on every channel and on the web card, is 'Run {tool} on {server}' when the call's server is known (an MCP tool: the server named by the row's MCP toolref in `ToolSource`), else 'Run {tool}'. The web card's title and the phone's first line come from the same rule, so they always match.
  - (2) `{inputs}` is `Bridge.Redact.Text(ToolArguments)` folded to one line and cut to at most 200 characters, ending with '…' (written `…`-style in source, Rule 14) when cut. The web card shows the same string, and no channel ever gets more of a call's inputs than the card shows.
  - (3) `{reason}` in `toolCall.failedWithReason` is only ever one of a fixed set of catalog reasons (Decide's `HELDBEFOREUPDATE`, U-170's no-key wording, U-214's unreachable-endpoint sentences), never raw error or exception text. A fallback Decision whose first `Reasons` line is anything else sends `toolCall.failed` instead (no reason slot). A test pins it with a raw error line.
  - (4) `{time}` is a catalog `time` slot, rendered in the same labelled form as the other catalog times (as `answered.*` render theirs).
- **The web chat card.** A replayable session `tool_call` request (the same gate as the notices) appears in that session's web chat as a card with Approve and Reject:
  - It reuses `ApprovalRequestCard` and the answer path a fix card uses (`ApiClient.answerApproval`); no second card component and no second answer API.
  - Answered once: the first answer from any copy (web card, simulated phone, paired chat) wins; a later press on another copy changes nothing and the card shows the answered line, as a fix card does today.
  - When it is answered, the card's buttons give way to the answered line in place; its result shows as a new chat message with no buttons, and the card keeps its answered line (the Q3 reading).
  - A non-replayable row, a `fix` row and another session's row get no tool-call card (a fix keeps its card inside the incident card).
- **Errors never escape.** A failed read or send logs one warning that names the event type and the request's Ref and sends nothing. `OnEvent` still returns OK, publishes its events as today and waits on no lock for more than 1 s (AD-31).
- **`SimPhoneOut.EditAnswered` edits only a request message.** The found message must carry `ApprovalRef` = the notification's `ApprovalRef`. Any other message (a result message) counts as "no such message", so only its Delivery row is recorded.
- **The catalog change is appended.** The four keys go at the end of `Msg/Catalog/Core.cls`'s Entries, after `audit.recorded`. In `Test/Msg/Catalog.cls`, only the count lines change and the appended `Keys` and `Fixtures` entries are added (Q1 ruling; the only shared-file edits).
- **Web texts come from the catalog.** The web card's texts are catalog texts (a `web` form of the same keys, or existing web keys such as the rail's "Run {toolName}" extended for the server), never hand-written page strings; any new web key is appended (`web/scripts/catalog.mjs`, `catalog.ts` regenerated) and any new string is appended to `web/scripts/ux-strings.test.mjs` (a plain union with Epic 12). [AMENDED 2026-11-02: it read "The keys are channel-only: the web catalog lists none of them"]
- Every test added or changed creates and removes its own rows and phone messages, and passes on a fresh stack in either order.

**Never:**
- **Never edit these files:**
  - Lane A: `Watch/**`, `Fix/**`, `src/bridge/**`, `Test/Bridge/**`, `Test/Watch/**`;
  - Epic 11 and Epic 12: `Test/Live/Payloads.cls`, `Test/Data/Fixture.cls` (calling its helpers is fine), `web/e2e/support/**` (importing is fine), `Channel/Telegram/**`, `Test/Channel/**`, `Web/Api.cls`, `ci/units.sh`, `.github/**`;
  - Epic 12's `web/src/app/rail/telegram-card/**`; `web/e2e/support/floor.ts`, `web/e2e/banners/banners.spec.ts`, `web/e2e-online/**` (standing rulings);
  - `web/src/app/api/api-types.ts` and `web/src/app/live/live-store.ts` only with a recorded reason (Epic 11's files until its part 2; a one-field append is the most it may take).
  [AMENDED 2026-11-02 for the web chat card: Part 1 (Story 31.2) is done, so `web/src/app/approvals/**` and `web/src/app/chat/**` are this story's to extend; `Channel/WebChat/Out.cls` and `Live/Payload/Approval.cls` may change if the card needs it (an append to the `approval` payload only, Lane B's).]
- No new stored property, column, global or table. The `approval` payload's existing fields keep their shape (an appended optional field, such as the server, is allowed).
- No hand-written page string (web texts come from the catalog, above). No new CI job, group or unit.
- No notice for `fix` or `setting` rows from `BridgeSink`. No change to `IncidentManager`.
- No real model key: the replay test runs on the CI mock key.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Raised | session row `tool_call`, pending, ToolName `zz_send`, ToolArguments `{"to":"ops"}`, ToolSource and Runner set | one notice: kind `approval`, `toolCall.request` {tool `zz_send`, inputs `{"to":"ops"}`}, ApprovalRef the Ref, IncidentRef "", DecisionRef ""; phone text "Run zz_send\nInputs: {"to":"ops"}\nNo dry run is available for this tool. Approving runs exactly this call once." with Approve and Reject | none |
| Raised, server known (U-212 (1)) | as Raised, but the call is an MCP tool whose toolref names server `ops-mcp` | first line "Run zz_send on ops-mcp", on the phone and on the web card alike | server unknown: "Run zz_send" |
| Long inputs (U-212 (2)) | ToolArguments whose redacted one-line text is over 200 characters, or holds line breaks or a secret | `inputs` is one line, redacted, exactly 200 characters ending with '…'; the web card shows the same string; no channel gets more | none |
| Web card raised | the same row, the session's web chat open | a card with the request's texts (the same first line and inputs as the phone) and Approve and Reject, drawn with `ApprovalRequestCard` | a non-replayable, `fix` or other-session row: no tool-call card |
| Web card answered first | Approve pressed on the web card | `POST .../approvals/:ref/answer` approves once; the card's buttons give way to the answered line; the phone's request message gets the same answered line in place | none |
| Answered on another copy first | Approve pressed on the phone, then the web card's Approve (or the reverse) | the first answer wins; the second press changes nothing (the existing answered/409 path) and every copy shows the first answer's line | none |
| Web card result | `approval.result` with Result `done` (or failed) | a new chat message with the result text and no buttons; the card keeps its answered line | none |
| Answered approve | the row approved (or already `executing`/`done`), AnsweredAction `approve`, channel `phone` | kind `answered`, `answered.approved` {channel, time AnsweredAt}; the phone's request message gets the line "Approved from the simulated phone at HH:MM." in place | none |
| Answered reject | AnsweredAction `reject` | `answered.rejected`; line "Rejected from ... at HH:MM. Nothing was changed."; no result notice | none |
| Expired | `approval.expired`, row expired | `answered.expired` {time ExpiresAt} | none |
| Result | Result `done` / `failed` / `interrupted`, FinishedAt set | `toolCall.done` "zz_send ran once at HH:MM." / `toolCall.failed` "zz_send failed at HH:MM. I won't run it again without a new approval."; a new phone message with no buttons; the request message keeps its line | Result or FinishedAt empty: nothing |
| Cancelled | `approval.cancelled` | no notice (the approval event is unchanged) | none |
| Not for us | a `fix` or `setting` row; owner `instance`, `eval` or a Ref with no session; another session's row | no notice; the approval events are as today | none |
| Not replayable | ToolSource or Runner empty, any `approval.*` | no notice | none |
| DW-454 | the row `failed`/`failed`, ToolSource "" (or Runner ""); then `decision.recorded` of a Decision row kind `tool`, ItemId the Ref, Fallback 1, Reasons = `Decide.#HELDBEFOREUPDATE` | after `approval.result`: no notice. After `decision.recorded`: one kind `result` notice "zz_send didn't run. This request was held before an update and cannot be run again safely, so please ask again." (DecisionRef set, no buttons) and one `approval` event with state `failed` and `reason` the sentence | Reasons empty, or the row is not failed: nothing |
| Raw reason (U-212 (3)) | as DW-454, but the Decision's first `Reasons` line is raw error text (for example `ERROR #5002: ObjectScript error`) | `toolCall.failed` with no reason slot, never the raw text; no `{reason}` ever carries text outside the catalog's reasons | none |
| Send fails | `NoticesIn.Send` returns an error, or throws | one warning naming the type and the Ref; `OnEvent` returns OK; the approval event is still published | logged |
| Answered after a result | phone: request message R (ApprovalRef A), then result message M (Delivery newest for A), then answered for A | M unchanged; R unchanged; one answered Delivery row with an empty ChannelMessageId | none |

</intent-contract>

## Code Map

Line numbers are at the worktree head `c5bfcbe26cf1351fa25f85a97c0a5747f4a326ea`.

**Producer**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - Class doc :1-34. `OnEvent` :52-73. `Approved` :88-107 (one `Ownership.Approval` read per recipient; for a session owner the recipient is the owner). `Recorded` :132-144, which already reads the Decision row.
  - The send seam `Notice` :227-230 → `NoticesIn.Send`. Its sibling user is `DailyCap` :170-211. `Member` :269-273.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- read only. It is the model:
  - `AnswerNotice` :1176-1189 (keys and slots);
  - `Compose` :1192-1201 (the shape: Kind, CatalogKey, Slots JSON, IncidentRef, ApprovalRef, no DecisionRef);
  - `KEY*` parameters :178-187.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- read only. `ToolName` :30, `ToolArguments` :33, `AnsweredAction` (`approve`|`reject`) :51, `AnsweredChannel`/`AnsweredAt` :54/:60, `Result` :63, `FinishedAt` :66, `ToolSource` :78, `Runner` :81.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- read only.
  - `HELDBEFOREUPDATE` :133 and `HeldBeforeUpdate` :542-546.
  - :270-272: `FailUnroutable` fires `approval.result` first, then `RecordFallback` fires `decision.recorded` with the reason.
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` -- `Kind`, `ItemId`, `Reasons`, `Fallback`. Read only.
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` -- read only.
  - `Answer` :277-305 fires `approval.answered` after the unlock, in AnswerOps' job.
  - `FinishExecution` :402-408 fires `approval.result`.
  - `Expire` :367-370.
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls` :43 `Text` -- read only.
- `src/ocutalon/cls/OcuTalon/Core/NoticesIn.cls` :10-11 -- its doc says the tool-call notices are "to come (Story 31.2)". Make that present tense.

**Consumers**
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` -- read only. Routes to WebChatOut, to SimPhoneOut (demo mode) and to TelegramOut (paired; off on this branch).
- `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls`:
  - `EditAnswered` :69-89 (`FindByApproval` takes the newest Delivery row, `Data/Delivery.cls` :69-78) and the class doc :14-20.
  - `Save` keeps the ApprovalRef for `REQUESTKINDS` only (:102), so a result message has none.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` :29 -- `approval`, `answered` and `result` record a Delivery row only. Unchanged.
- `web/src/app/phone/phone-request.ts`, `phone-view.ts`, `web/src/app/rail/rail-view.ts` `approvalTitle` :172-176 ("Run {toolName}") -- read only. The phone already draws any message that has an `approvalRef`.

**Catalog (Q1, appended)**
- `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- the last entry is `audit.recorded` :554-558; append after it (its closing `}` gains a comma). The class doc :1-3 is left as is (Epic 40 edits it).
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- the count lines are the doc :3 ("95 keys"), `TestEntries` :80 and :82 (95), and `TestEveryKeyOnEveryChannel` :121 (119). Append to the `Keys` "core" list after `"audit.recorded"` :1050, and to `Fixtures` after :1292. The fixture context is now `2026-10-16T18:20:00Z`, zone America/New_York, online demo on, so times read "14:12 ET".

**Tests to extend**
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls` -- slot-safe.
  - The doc :1-37 and `Session` :808 (a real, open session).
  - `NoticeSink`/`Notices`/`NoticeOf`/`NoticeCall` :826-862 read the probe. `Sink` :872, `Events` :879, `Warnings` :960.
  - Seed rows with `Test.Data.Fixture.Approval(owner, incident, state, raisedAt, fields)` (:102, its `fields` override Kind and the rest) and `Fixture.Decision(owner, "tool", recordedAt, fields)` (:120).
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSinkNoticeProbe.cls` :12-24 -- it records sessionRef, kind, catalogKey and slots. Extend it to record `approvalRef`, `incidentRef` and `decisionRef` too.
- `src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls` -- `TestAnsweredEditsInPlace` :399 and `TestResultIsAMessage` :182 are the patterns, with the helpers :690-790.
- New `src/ocutalon/cls/OcuTalon/Test/Core/ToolCallNotices.cls`, extending `OcuTalon.Test.Core.InProduction` (`Guard` :61, `Session` :100, cleanup :52):
  - Its model is `Test/Bridge/Approval.cls` `TestReplayReachesTheLiveStream` :1632, with `HeldCall` :2598, `UseReplayAgent` :2561, `Answerer` :2715 and `WaitState` :2796, which are private there. Copy their few lines, or call the public helpers:
    - `Test.Bridge.Approval` `TrackOwner` :2478, `Clean` :2408 and `WaitTask` :2136, as `Test.Bridge.Gate` does;
    - `Test.Agent.RunnerFixture` `ReadyReason` :306, `PointKeys` :456, `RestoreKeys` :463, `UseAgent` :524 and `RestoreAgent` :535.
  - The tool is `zz_replay_send`, of class `OcuTalon.Test.Bridge.ZzReplayTool`. `ChatAgent` runs `OcuTalon.Test.Bridge.ZzReplayAgent`.
  - `Gate.Check(tool, call, metadata, "")` raises with the `HostSinkClass` setting (`Approval.cls` :112), so `approval.raised` reaches the real `BridgeSink`.
- `web/e2e/answers/answers.spec.ts`:
  - The doc :9-24 and X2 :241-307 (the press, `lineOf`, `replyBody`, `hhmm`) are the pattern.
  - Seed with `seedApproval`, `sinkEvent`, `irisScript`, `quoted`, `chk` and `cleanFixtureRows` (support/iris.ts :90-186, :450, :712), and `dropPhone`/`phoneMessage` (support/devices.ts :57, :109). These are imports only.
  - X6 :543-553 seeds a tool_call row with no ToolSource and Runner, so it stays unchanged.

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure, no code; the record goes under Verification): on the warm stack, before any edit, run `OcuTalon.Test.Bridge.Approval` once and record its seconds, as the baseline for the regression run below. If it nears 8 minutes, the regression run uses `ci/iris.sh class` on a fresh stack instead.
- [ ] `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - In `Approved`, after the publish loop, call a new private `ToolNotice(type, ownerRef, ref)` that applies the Boundaries' gate and table.
  - In `Recorded`, after the publish, call a new private `HeldNotice(ownerRef, row)` for DW-454: the notice, plus the `approval` event with `Reason`.
  - Both build the Notification once (a private `Compose` like `IncidentManager`'s) and send through `..Notice`. A failed send is one `$$$LOGWARNING` naming the type and the Ref.
  - Add the parameters `KEYREQUEST`, `KEYDONE`, `KEYFAILED`, `KEYFAILEDWHY`, `KEYAPPROVED`, `KEYREJECTED` and `KEYEXPIRED`.
  - Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- append the four entries of Design Notes D2 (slot types `text` and `time`; ASCII `source`) -- AC 1-3.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls`:
  - The counts become 95 → 99 (doc :3, :80, :82) and 119 → 123 (:121).
  - Append the four keys to Keys "core", and their four Fixtures with the exact message-channel texts of D2, at 14:12 ET.
- [ ] `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` -- in `EditAnswered`, treat a found message whose `ApprovalRef` differs from the request's as not found. Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Core/NoticesIn.cls` -- doc :10-11 only.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSinkNoticeProbe.cls` -- also record `approvalRef`, `incidentRef` and `decisionRef`, and update its doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls` -- new probe tests, slot-safe. Each seeds and removes its rows. Update the class doc.
  - `TestToolCallNoticeKinds`: the matrix rows Raised, Answered approve (with the row already `done`, so the key comes from AnsweredAction), Answered reject, Expired, the three Result values and Cancelled. Each checks kind, key, slots, ApprovalRef, IncidentRef "" and DecisionRef "", and that the approval events are still published.
  - `TestToolCallNoticesOnlyForReplayableSessionRows`: the matrix rows "Not for us" and "Not replayable", with the probe at 0 calls.
  - `TestHeldBeforeUpdateSaysWhy`: the DW-454 row, in Decide's order; the probe holds exactly one call, and the event's `reason` is the sentence (DW-454).
  - `TestToolCallNoticeFailureIsLogged`: the probe's `failNotice` and `throwNotice` give one warning each, OK, and the approval event.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls` -- new `TestAnsweredNeverEditsAResult`: the matrix's last row. Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ToolCallNotices.cls` (new; the integration AC, real production and real replay):
  - `TestApprovedCallReachesThePhone`:
    1. A held call of a fixture session goes through the real gate. The phone gets the `toolCall.request` message with the session's ApprovalRef, within WAIT s.
    2. `Approval.Answer(ref, "approve", "phone", ANSWERER, NewRef)`, then wait for the row to be `done`.
    3. The same message's `Answer` is `answered.approved`'s phone render.
    4. A second message is `toolCall.done`'s phone render, with ApprovalRef "" and Answer "".
  - `TestRejectedAndExpiredEditInPlace`:
    - one held call rejected: the line `answered.rejected`, no second message;
    - another expired through `Approval.Expire`: `answered.expired`.
  - Restore ChatAgent's agent and the keys, and clean the rows (`Test.Bridge.Approval.TrackOwner`/`Clean`), also after a failure.
- [ ] `web/e2e/answers/answers.spec.ts` -- new X12, plus the doc line. The real-runtime evidence (Rule 3):
  1. Seed a session `tool_call` row (`zz_tool_x12`, requiredRole OcuTalonUser). With a local `irisScript` helper, set ToolSource `OcuTalon.Test.Bridge.ZzReplayTool`, Runner `ChatAgent` and ToolArguments `{"to":"ops"}`. Then `sinkEvent('approval.raised')`.
  2. The phone message shows the three lines, and Approve and Reject named "Approve: run zz_tool_x12".
  3. Approve on the phone. The answer line "Approved from the simulated phone at HH:MM." (AnsweredAt from the reply) replaces the buttons within 5 s of the reply (NFR-9), and the server's message holds it (`phoneMessage(...).answer`).
  4. Set State `done`, Result `done` and FinishedAt with `irisScript`, then `sinkEvent('approval.result')`. A new message "zz_tool_x12 ran once at HH:MM." has no buttons, and the request message keeps its line.
  5. In `finally`: `dropPhone` and `cleanFixtureRows`.

**Acceptance Criteria:**
- Given an approval of kind `tool_call`, when the bridge reports `approval.raised`, `approval.answered` or `approval.result`, then `BridgeSink` sends `Notification`s of kinds `approval`, `answered` and `result` through `NoticesIn`, each carrying the request's `ApprovalRef` and its (empty) `IncidentRef`. So the phone gets Approve and Reject, an in-place answered line and a result message (pinned by `ToolCallNotices`, with the real replay, and by X12).
- Given a request of kind `fix`, when the same events arrive, then `BridgeSink` sends nothing, and `IncidentManager`'s answered and result notifications still carry both Refs (`Test.Watch.Tell` `TestAnsweredToEachRecipient`, unchanged; AD-31).
- Given an approved tool call held before the update that Decide closes as failed, when its events arrive, then the person gets exactly one result notice with the plain-English reason and no buttons, and the `approval` event carries the reason (DW-454, U-170, U-178).
- Given a result message that is newer than the request message, when an answered notice arrives, then the result message is never edited.
- Given the demo path, when `live:demo-path` runs, then it passes unchanged: UJ-1 has no tool call, and every product tool is `safe`.

## Spec Change Log

- 2026-11-02 (lead, epic-31 runner, after hold #2; re-plan): (a) U-212 applied (`apply U-212 at=2026-11-02T13:19:05Z#648`): its four conditions are written into the intent contract's Boundaries and the I/O matrix (server form of the first line, 200-character one-line inputs, catalog-only `{reason}`, labelled `{time}`); Design Notes item 6's "no `on {server}` form" is superseded. (b) The web chat tool-call approval card moves from `deferred:` into scope (the Contest Planner under the owner's delegation: "The web-chat tool-call approval gap is 1.0.0-VISIBLE: PUT IT INTO 31.5"), with an `[AMENDED 2026-11-02, Story 31.5, Contest Planner under the owner's delegation]` acceptance bullet in epics.md. Status reset to `draft` so the plan re-derives the Code Map, Tasks, Verification and size around the amended intent.

## Review Triage Log

## Design Notes

**U-212 (owner decision, lead-written; keep verbatim through the re-plan).** Veto U-212, kept by the Contest Planner under the owner's delegation with four conditions (`at=2026-11-02T13:19:05Z#648`): "Keep, with four conditions. (1) Match the card: the first line is 'Run {tool} on {server}' when the server is known, and 'Run {tool}' only when it isn't. (2) {inputs} stays on one line through the bridge's redactor, and is capped at 200 characters, ending with '…' when cut; the phone and paired chat never get more of a call's inputs than the card shows. (3) {reason} in toolCall.failedWithReason is only ever a catalog reason (such as U-214's), never raw error or exception text; a test pins it. (4) {time} uses the same labelled form as the other catalog times (DW-574 will unify zones later). The Q3 reading (answer edits the request in place; the result is a new message with no buttons, as for a fix in Story 6.4) is kept." The Boundaries say how each condition binds; item 6 below is superseded where it says the request has no `on {server}` form.

**Web chat card (lead-written; keep).** Moved from `deferred:` into scope (see the Intent's amendment). The sibling to extend is `web/src/app/approvals/approval-request-card.ts` (`ApprovalRequestCard`, today drawn by `web/src/app/incidents/incident-card.ts` inside a fix's incident card) with `ApiClient.answerApproval`; Rule 2 applies.

**Governing ADs (Rule 6):**
- **AD-31:** `BridgeSink` sends the tool-call notices through `NoticesIn`, asynchronously, never waiting more than 1 s; `IncidentManager` keeps fixes.
- **AD-32:** the shape of a Notification; producers never render; Approve and Reject only for kind `approval` with an ApprovalRef.
- **AD-11:** the row is the truth, so keys come from its fields, not from the event's order; `answered.*` statuses reused.
- **AD-14:** `FindByApproval` and in-place edits.
- **AD-33:** `BridgeSink` stays the one publisher of `approval` events; `SimPhoneOut` of `phone`.
- **AD-10 and AD-30:** the replay runs once with no model; the inputs are shown and nothing is run without approval.
- **AD-29:** Lane B files only.
- **AD-22:** production tests in throwaways.
- **AD-2:** the bridge stays unaware of the host catalog.

No AD Rule is contradicted, and the spine needs no change.

**Decided in-stage (unattended, small, reversible):**
1. **Q3, result behaviour = a fix's (Story 6.4):** answered edits the request message in place, and the result is a new message with no buttons. This differs from the user story's "edited in place ... when its result arrives": the result arrives as its own message, and the request message keeps its answered line, as for a fix and as the UX's phone rule says.
2. **The replayable gate** (ToolSource and Runner set) mirrors `Decide.HeldBeforeUpdate`. A row Decide would close without running never offers Approve. As a side effect, the fixture tool_call rows of existing specs (rail, layout G2, trace links, answers X6) get no phone message, so those shared surfaces stay as they are.
3. **Answered reads `AnsweredAction`, and the edit guard sits in `SimPhoneOut`.** This follows the lead's design point that the answered edit must never land on the result message. Notify and SimPhoneOut have PoolSize 1, and the result is causally after the answer (inference: an ordering race is unlikely), so the guard is defence in depth.
4. **Cancelled and expired:** no notice for `cancelled` (as for a fix); `expired` sends `answered.expired` (as for a fix).
5. **DW-454's "approval card":** the page renders no tool-call card and no `approval.reason` (the rail lists pending rows only). The card half is therefore the `approval` live event's `reason`, published by `BridgeSink` from the existing fallback Decision row. There is no new column and no `FromRow` change, so the snapshot stays unchanged. The visible half is the phone and paired-chat result notice, with no buttons.
6. **Inputs** are `Bridge.Redact.Text(ToolArguments)` on one line, because the renderer folds line breaks in a slot. The text says "Inputs:", not "exact inputs". The request text has no `on {server}` form until MCP servers are classified (step 4, FR-47). The Telegram length limit is TelegramOut's (Epic 12).
7. **Q1 footprint:** besides the count lines, `Test/Msg/Catalog.cls` gains the four appended `Keys` and `Fixtures` entries, because `TestEntries` and `TestEveryKeyOnEveryChannel` assert the exact key lists. These are the same places Epic 40 appends to. At merge the entries are a plain union, and the count lines take the sum: 95 + 3 + 4 = 102 Core keys.

**Decided in-stage -- new public text (veto item for the lead).** Channel-only (phone and Telegram), with no `web` form and no web catalog entry:
- D2a `toolCall.request`: "Run {tool}\nInputs: {inputs}\nNo dry run is available for this tool. Approving runs exactly this call once." The first line and the last sentence are EXPERIENCE.md's; the inputs line is the card's labelled inputs.
- D2b `toolCall.done`: "{tool} ran once at {time}."
- D2c `toolCall.failed`: "{tool} failed at {time}. I won't run it again without a new approval."
- D2d `toolCall.failedWithReason` (DW-454): "{tool} didn't run. {reason}"
- Reused as they are: `answered.approved`, `answered.rejected` and `answered.expired`.

**Integration ACs (Rule 1):** no new service; `BridgeSink` is extended.
- **Consumes:** Story 30.3's real `approval.result`, `ToolSource`/`Runner`, `HELDBEFOREUPDATE`; Story 6.3's `SimPhoneOut` answered edit; Story 6.4's result message; Story 16.9's `Notice` seam.
- **Consumed-by:**
  - `SimPhoneOut`, which turns these notices into phone messages (pinned against the real production in `ToolCallNotices` and the real browser in X12);
  - `TelegramOut`, which turns them into Telegram messages (Epic 12 / Story 31.4 covers it: TelegramOut is a stub here, and Notify routes to it only for a paired session).

**Extend, don't copy (Rule 2):**
- `ToolNotice` and `Compose` follow `IncidentManager.AnswerNotice` and `Compose`. That is a copy across lanes: AD-33 forbids Lane B editing `IncidentManager`, and the shape is five lines.
- The send reuses `BridgeSink.Notice`.
- `ToolCallNotices` extends `InProduction` and reuses `Test.Bridge.Approval`'s public helpers. Its held-call lines copy the private `HeldCall`, because `Test/Bridge/**` is Lane A's.

**Ledger inbox (Rule 17):** DW-454 is addressed (the `BridgeSink` task, `TestHeldBeforeUpdateSaysWhy`, AC 3).

**Footprint extensions (Rule 11 (b); none is contended, checked against `origin/OCT-epic{11,12,13,15,30,40}`):**
- `Channel/SimPhone/Out.cls`;
- `Test/Core/{BridgeSink,BridgeSinkNoticeProbe,ToolCallNotices}.cls`;
- `Test/Demo/SimPhoneOut.cls`;
- `web/e2e/answers/answers.spec.ts`;
- the Q1 appended blocks in `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls`.

`new_units:` none. The new class joins `shard:lane-b` (Core area, group `image`) by area.

**Size:** 9 files (1 new), about 8 new IRIS test methods and 1 Playwright case. CI: the Core catalog change runs every group; the story's own tests are in `shard:lane-b` (image) and `live:answers` (browser). One implement pass.

## Verification

Use these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`, with tags `e31s5i` (fresh) and `e31s5iw` (warm).
- Pass `timeout: 600000` on every call.
- One test-runner call per message, and never re-submit a call after a client-side timeout.
- The only IRIS MCP target is server `ocutalon-slot-c`, namespace `OCUTALON`; check its identity first.
- No real model key, ever.

**Commands:**
- (loop) `OCUTALON_RUN_TAG=e31s5iw ci/warm.sh up` once. Then run each of these on its own call; each is expected to print `CLASS ... passed`:
  - `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s5iw ci/iris.sh class OcuTalon.Test.Core.BridgeSink`
  - `... class OcuTalon.Test.Demo.SimPhoneOut`
  - `... class OcuTalon.Test.Msg.Catalog`
  - `... class OcuTalon.Test.Core.ToolCallNotices`
  - `... class OcuTalon.Test.Core.NoticesInProduction` (unchanged)

  At the stage's end, also after a failure: `OCUTALON_RUN_TAG=e31s5iw ci/warm.sh down`.
- (once) `... class OcuTalon.Test.Bridge.Approval` on the warm stack (Task 0 sizes it; use a fresh `class` call if it nears 8 minutes) -- expected: passes. Its `TestReplayReachesTheLiveStream` session now also gets an answered Delivery row and a result message, which `Fixture.Clean` removes.
- (once) `node web/scripts/catalog.mjs --check` -- expected: `catalog.ts` is current, with no change (the keys are channel-only).
- (once) `npm --prefix web run lint` -- expected: exit 0.
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh build`, then `OCUTALON_RUN_TAG=e31s5i ci/iris.sh live answers` -- expected: passes, X12 included.
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh live demo-path` -- expected: passes (UJ-1).
- (once) Fresh `ci/iris.sh shard lane-b@Core,Demo,Msg`, then the same with `--reverse`, one per call (Rule 19) -- expected: every class passes.
- (once) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-storage.sh` and `bash docker/tests/test-ci-config.sh`, one per call -- expected: all pass.
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh teardown`.

**Shared surfaces:**
- The Core catalog's key count and lists (`Test/Msg/Catalog.cls`).
- The session's phone feed and Delivery rows: every spec that sends `approval.*` through the real `BridgeSink` for a session's `tool_call` row (rail.spec :176-206, floor/layout.spec G2 :231-238, trace/links.spec :839-845, answers.spec X6 :543-553, `Test.Bridge.Approval` row 2). Search `web/e2e` and `Test/` for `tool_call` and confirm that each seeds no ToolSource and Runner, or cleans its session.
- The probe's recorded fields (`BridgeSinkNoticeProbe`, read only by `Test.Core.BridgeSink`).

Every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to apply** (the implement stage writes `mutation: <change> → <red test>` next to each):
- AC 1: drop the `approval.raised` branch → `TestToolCallNoticeKinds` and `ToolCallNotices.TestApprovedCallReachesThePhone` go red. Key answered on `State` → the "already done" answered case goes red.
- AC 2: drop the `Kind = tool_call` check → the fix case of `TestToolCallNoticesOnlyForReplayableSessionRows` goes red.
- AC 3: drop `HeldNotice` → `TestHeldBeforeUpdateSaysWhy` goes red. Drop the replayable gate → the same test goes red (two notices).
- AC 4: drop the `ApprovalRef` guard → `TestAnsweredNeverEditsAResult` goes red.
- AC 5: none (the existing unit, unchanged).

**Manual checks:**
- `git status --short` shows no path from the Never list.
- `git diff` of `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls` shows only the appended blocks, the one comma and the count lines.

## Auto Run Result

Status: draft (re-plan after the 2026-11-02 amendment)
Blocking condition: none
