---
title: 'Story 31.5: a tool call''s approval request reaches the phone with Approve and Reject (notices)'
type: 'feature'
created: '2026-11-02'
status: 'ready-for-dev'
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
  - summary: 'When Story 30.7 lands (deferred after the v1.0.0 tag), its replay-failure reasons (U-214''s unreachable-endpoint sentences, U-170''s no-key wording) could reach the tool-call result as toolCall.failedWithReason; until then a replayable row''s failed result sends toolCall.failed with no reason, and BridgeSink''s reason allowlist holds only Decide''s HELDBEFOREUPDATE'
    evidence: 'U-214 (#650) and its story are set aside (cycle log 2026-11-02T14:11:59Z); the texts exist nowhere in src/'
    location: 'src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls (reason allowlist), Story 30.7'
    severity: 'low'
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

**Web chat card: Story 31.6** [AMENDED 2026-11-02, Story 31.5 split, orchestrator ruling (decide, Rule 5 tier-2 split into a sibling planned next): the web chat tool-call approval card that the Contest Planner put into 31.5 ("The web-chat tool-call approval gap is 1.0.0-VISIBLE: PUT IT INTO 31.5") is Story 31.6, planned and built right after this story on the same run. This story (part A) keeps the notices, U-212's texts on the phone and in the paired chat, DW-454 and the SimPhoneOut edit guard.]

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
  - (1) The request's first line, on every channel (and on Story 31.6's web card, which uses the same rule), is 'Run {tool} on {server}' when the call's server is known (an MCP tool: the server named by the row's MCP toolref in `ToolSource`), else 'Run {tool}'. The web card's title and the phone's first line come from the same rule, so they always match.
  - (2) `{inputs}` is `Bridge.Redact.Text(ToolArguments)` folded to one line and cut to at most 200 characters, ending with '…' (written `…`-style in source, Rule 14) when cut. Story 31.6's web card shows the same string, and no channel ever gets more of a call's inputs than the card shows.
  - (3) `{reason}` in `toolCall.failedWithReason` is only ever one of a fixed set of catalog reasons (Decide's `HELDBEFOREUPDATE`, U-170's no-key wording, U-214's unreachable-endpoint sentences), never raw error or exception text. A fallback Decision whose first `Reasons` line is anything else sends `toolCall.failed` instead (no reason slot). A test pins it with a raw error line.
  - (4) `{time}` is a catalog `time` slot, rendered in the same labelled form as the other catalog times (as `answered.*` render theirs).
- **The web chat card is Story 31.6's** [AMENDED 2026-11-02, split]: this story changes no page file and draws no web card.
- **Errors never escape.** A failed read or send logs one warning that names the event type and the request's Ref and sends nothing. `OnEvent` still returns OK, publishes its events as today and waits on no lock for more than 1 s (AD-31).
- **`SimPhoneOut.EditAnswered` edits only a request message.** The found message must carry `ApprovalRef` = the notification's `ApprovalRef`. Any other message (a result message) counts as "no such message", so only its Delivery row is recorded.
- **The catalog change is appended.** The four keys go at the end of `Msg/Catalog/Core.cls`'s Entries, after `audit.recorded`. In `Test/Msg/Catalog.cls`, only the count lines change and the appended `Keys` and `Fixtures` entries are added (Q1 ruling; the only shared-file edits).
- **The keys are channel-only in this story:** the web catalog lists none of them (`web/scripts/catalog.mjs` and `catalog.ts` are unchanged); Story 31.6 adds any `web` forms the card needs. [AMENDED 2026-11-02, split: it read "Web texts come from the catalog ..." while the card was in this story]
- Every test added or changed creates and removes its own rows and phone messages, and passes on a fresh stack in either order.

**Never:**
- **Never edit these files:**
  - Lane A: `Watch/**`, `Fix/**`, `src/bridge/**`, `Test/Bridge/**`, `Test/Watch/**`;
  - Epic 11 and Epic 12: `Test/Live/Payloads.cls`, `Test/Data/Fixture.cls` (calling its helpers is fine), `web/e2e/support/**` (importing is fine), `Channel/Telegram/**`, `Test/Channel/**`, `Web/Api.cls`, `ci/units.sh`, `.github/**`;
  - Epic 12's `web/src/app/rail/telegram-card/**`; `web/e2e/support/floor.ts`, `web/e2e/banners/banners.spec.ts`, `web/e2e-online/**` (standing rulings);
  - `web/src/app/api/api-types.ts` and `web/src/app/live/live-store.ts` only with a recorded reason (Epic 11's files until its part 2; a one-field append is the most it may take).
  [AMENDED 2026-11-02, split: `web/src/app/**`, `Channel/WebChat/Out.cls`, `Data/Ownership.cls` and `Live/Payload/Approval.cls` are Story 31.6's; this story leaves them unchanged.]
- No new stored property, column, global or table. The `approval` payload's existing fields keep their shape (an appended optional field, such as the server, is allowed).
- No hand-written page string (web texts come from the catalog, above). No new CI job, group or unit.
- No notice for `fix` or `setting` rows from `BridgeSink`. No change to `IncidentManager`.
- No real model key: the replay test runs on the CI mock key.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Raised | session row `tool_call`, pending, ToolName `zz_send`, ToolArguments `{"to":"ops"}`, ToolSource and Runner set | one notice: kind `approval`, `toolCall.request` {tool `zz_send`, inputs `{"to":"ops"}`}, ApprovalRef the Ref, IncidentRef "", DecisionRef ""; phone text "Run zz_send\nInputs: {"to":"ops"}\nNo dry run is available for this tool. Approving runs exactly this call once." with Approve and Reject | none |
| Raised, server known (U-212 (1)) | as Raised, but the call is an MCP tool whose toolref names server `ops-mcp` | first line "Run zz_send on ops-mcp", on the phone (Story 31.6's card follows the same rule) | server unknown: "Run zz_send" |
| Long inputs (U-212 (2)) | ToolArguments whose redacted one-line text is over 200 characters, or holds line breaks or a secret | `inputs` is one line, redacted, exactly 200 characters ending with '…'; Story 31.6's card shows the same string; no channel gets more | none |
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

Line numbers are at `7d44e4bc0de4b7cb2dbd2b96654529803dc30d84`; no file under `src/`, `web/`, `ci/` or `docker/` changed between it and the re-plan head `d57dfbeb8a497848c32285b9be2c3e435eef4ecd`.

**Producer (IRIS)**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - Class doc :1-34. `OnEvent` :52-73. `Approved` :88-107 (one `Ownership.Approval` read per recipient; for a session owner the recipient is the owner). `Recorded` :132-144, which already reads the Decision row.
  - The send seam `Notice` :227-230 → `NoticesIn.Send`, which works from any process (it creates the service in the caller's process), so `sinkEvent`'s direct `OnEvent` call reaches Notify too. Its sibling user is `DailyCap` :170-211. `Member` :269-273. `Publish` :262.
- `src/ocutalon/cls/OcuTalon/Watch/IncidentManager.cls` -- read only. The model: `AnswerNotice` :1176-1189 (keys and slots), `Compose` :1192-1201 (Kind, CatalogKey, Slots JSON, IncidentRef, ApprovalRef), `KEY*` :178-187.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls` -- read only. `ToolName` :30, `ToolArguments` :33, `AnsweredAction` :51, `AnsweredChannel`/`AnsweredAt` :54/:60, `Result` :63, `FinishedAt` :66, `ToolSource` :78, `Runner` :81.
- `src/bridge/cls/OcuTalon/Bridge/Policy/Gate.cls` -- read only. `Hold` :158-184 sets `ToolSource` from `Source` :187-192: the toolref itself when it starts `mcp:` (any case, `IsMcp` :412), else `metadata.origin_class`. `MCPPREFIX` :92 is public. Tests use the toolref `mcp:zzserver` (`Test/Bridge/Gate.cls` :461, :625). Spine :338: the toolref "names the `OcuTalon.Mcp.Server` row"; spine :720: servers attach as `mcp:remote:@{config:AI.MCP.OcuTalon_<server>}`.
- `src/bridge/cls/OcuTalon/Bridge/Process/Decide.cls` -- read only. `HELDBEFOREUPDATE` :133, `HeldBeforeUpdate` :542, and :270-272 (`FailUnroutable` fires `approval.result`, then `RecordFallback` fires `decision.recorded` with the reason).
- `src/bridge/cls/OcuTalon/Bridge/Data/Decision.cls` (`Kind`, `ItemId`, `Reasons`, `Fallback`), `Bridge/Approval.cls` (`Answer` :277-305, `Expire` :367-370, `FinishExecution` :402-408; a seeded row has no `ApprovalHold`, so approving it replays nothing, doc :17-26) and `Bridge/Redact.cls` `Text` :43 (returns `UNCHECKED` when it cannot check) -- read only.
- `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls` -- read only. `Reason` :21 already exists (DW-454's event sets it); its contract is pinned by `Test/Live/Payloads.cls` (Never list), so no field is added.
- `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` doc :1-30 -- read only. Slot types (`text`, `time` = `Data.Time.ForMessage` with " ET" on the online demo); a string slot is trimmed and its line breaks collapse to one space; `web` text is used when an entry has one, else `text`; a `one` form keys only on a count slot.
- `src/ocutalon/cls/OcuTalon/Core/NoticesIn.cls` :10-11 -- its doc says the tool-call notices are "to come (Story 31.2)".

**Consumers (IRIS)**
- `src/ocutalon/cls/OcuTalon/Core/Rule/Notify.cls` -- read only. Routes every notification to WebChatOut, to SimPhoneOut (demo mode) and to TelegramOut (paired; a stub here).
- `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` -- `EditAnswered` :69-89 (`FindByApproval` takes the newest Delivery row of the channel, `Data/Delivery.cls` :72-78); `Save` keeps the ApprovalRef for `REQUESTKINDS` (:33) only (:102), so a result message has none.
- `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` -- read only in this story (Story 31.6's). `INCIDENTKINDS` :29 holds `approval`, `answered`, `result`, so `OnNotification` :51-64 records a tool-call notice's web Delivery row with no text, no ChannelMessageId and no event, and renders nothing.

**Page** -- unchanged. The phone's buttons are named by `web/src/app/phone/phone-view.ts` `requestView` :147-169 from the store's `approval` payload (`approvalView`, title "Run {toolName}"), so a tool call's phone Approve is named "Approve: run {tool}"; read only here.

**Tests to extend (IRIS)**
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls` -- slot-safe. Doc :1-37, `Session` :808, `NoticeSink`/`Notices`/`NoticeOf`/`NoticeCall` :826-862, `Sink` :872, `Events` :879, `Warnings` :960. Seed with `Test.Data.Fixture.Approval(owner, incident, state, raisedAt, fields)` :108 and `Fixture.Decision(owner, "tool", recordedAt, fields)` :141.
- `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSinkNoticeProbe.cls` :12-24 -- records sessionRef, kind, catalogKey and slots.
- `src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls` -- `TestAnsweredEditsInPlace` :399 and `TestResultIsAMessage` :182, helpers :690-790.
- `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- counts: doc :3 ("95 keys"), `TestEntries` :80 and :82 (95), `TestEveryKeyOnEveryChannel` :121 (119). Append to `Keys` "core" after `"audit.recorded"` :1050 and to `Fixtures` after :1292 (context `2026-10-16T18:20:00Z`, America/New_York, online demo on: times read "14:12 ET").
- New `Test/Core/ToolCallNotices.cls`, extending `OcuTalon.Test.Core.InProduction` (`Guard` :61, `Session` :100, cleanup :52). Model: `Test/Bridge/Approval.cls` `TestReplayReachesTheLiveStream` :1632 with its private `HeldCall` :2598, `UseReplayAgent` :2561, `Answerer` :2715, `WaitState` :2796; public helpers `Test.Bridge.Approval` `TrackOwner` :2478, `Clean` :2408, `WaitTask` :2136; `Test.Agent.RunnerFixture` `ReadyReason` :309, `PointKeys` :459, `RestoreKeys` :466, `UseAgent` :527, `RestoreAgent` :538. Tool `zz_replay_send` of `OcuTalon.Test.Bridge.ZzReplayTool`; `ChatAgent` runs `OcuTalon.Test.Bridge.ZzReplayAgent`. `Gate.Check(tool, call, metadata, "")` raises with the `HostSinkClass` setting (`Approval.cls` :112), so the real `BridgeSink` gets `approval.raised`.

**Tests to extend (browser)**
- `web/e2e/answers/answers.spec.ts` -- doc :9-24 (X1 to X11); X2 :241-306 (phone press, its busy state, the answer line; it pins the server's `answer` as "" for a fix, because no answered notification came), X6 :511-577 (a `tool_call` row with no ToolSource/Runner: no phone message; unchanged), X11 :764. Local helpers: `open` :64, `messageOf` :58, `noticeOnPhone` :92 (incident notices only), `approveOf`/`rejectOf` :110-111 (names fixed to the fix's), `lineOf` :114, `nextReply` :122, `startOf` :127, `hhmm` :47, `PAGE_MS` :34. Imports only from `support/iris.ts`: `irisScript` :93 (not yet imported here), `sinkEvent` :453 (calls `BridgeSink.OnEvent` in an iris job), `cleanFixtureRows` :660, `seedApproval` :717 (no ToolSource/Runner/ToolArguments fields), `answerQuietly` :774, `readApproval` :788; `support/devices.ts` `dropPhone` :60, `phoneMessage` :112 (newest phone message with that ApprovalRef: ref, approvalRef, answer, text).

## Tasks & Acceptance

**Execution:**
- [ ] Task 0 (measure, no code; record under Verification): on the warm stack, before any edit, run `OcuTalon.Test.Bridge.Approval` once and record its seconds, as the baseline for its (once) run. If it nears 8 minutes, that run uses a fresh `ci/iris.sh class` call instead.

IRIS, notices (U-212, DW-454):
- [ ] `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - In `Approved`, after the publish loop, call a new private `ToolNotice(type, ownerRef, ref)` that applies the Boundaries' gate and table. The raised key is `toolCall.requestOnServer` {`tool`, `server`, `inputs`} when `ServerOf(row.ToolSource)` is not empty, else `toolCall.request` {`tool`, `inputs`} (Design Notes W6, W7).
  - Private `ServerOf(source)`: "" unless `source` starts, in any case, with `$Parameter("OcuTalon.Bridge.Policy.Gate", "MCPPREFIX")`; else the rest, trimmed, and when the rest is `remote:@{config:AI.MCP.OcuTalon_<name>}`, `<name>`.
  - Private `InputsOf(arguments)`: `Bridge.Redact.Text(arguments)`, control characters and every whitespace run (line breaks included) folded to one space, trimmed; "" gives `{}`; a text over `INPUTSMAX` (200) characters becomes its first 199 characters plus `$Char(8230)` (Rule 14).
  - In `Recorded`, after the publish, call a new private `HeldNotice(ownerRef, row)` for DW-454 (the Boundaries' DW-454 gate). When the first `Reasons` line is one of `HeldReasons()` (Decide's `HELDBEFOREUPDATE`, read with `$Parameter`, never copied; W8), it sends `toolCall.failedWithReason` {`tool`, `reason`} with `DecisionRef` and publishes the `approval` event with `Reason` set. Any other line sends `toolCall.failed` {`tool`, `time` = FinishedAt} with no reason slot and publishes no extra event (U-212 (3); W9).
  - Both build the Notification once with a private `Compose` like `IncidentManager`'s and send through `..Notice`. A failed read or send is one `$$$LOGWARNING` naming the type and the Ref.
  - Add the parameters `KEYREQUEST`, `KEYREQUESTON`, `KEYDONE`, `KEYFAILED`, `KEYFAILEDWHY`, `KEYAPPROVED`, `KEYREJECTED`, `KEYEXPIRED` and `INPUTSMAX`. Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- append the five entries of Design Notes D2 after `audit.recorded` (slot types `text` and `time`; no `web` text; ASCII `source`).
- [ ] `src/ocutalon/cls/OcuTalon/Test/Msg/Catalog.cls` -- the counts become 95 → 100 (doc :3, :80, :82) and 119 → 124 (:121). Append the five keys to `Keys` "core", and their five `Fixtures` with D2's exact texts at "14:12 ET" (U-212 (4): the same labelled time as `answered.*`).
- [ ] `src/ocutalon/cls/OcuTalon/Channel/SimPhone/Out.cls` -- in `EditAnswered`, a found message whose `ApprovalRef` differs from the request's counts as not found. Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Core/NoticesIn.cls` -- doc :10-11 only (present tense).

IRIS tests:
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSinkNoticeProbe.cls` -- also record `approvalRef`, `incidentRef` and `decisionRef`; update its doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSink.cls` -- new probe tests, slot-safe; each seeds and removes its rows; update the class doc:
  - `TestToolCallNoticeKinds`: the matrix rows Raised, Answered approve (the row already `done`, so the key comes from AnsweredAction), Answered reject, Expired, the three Result values and Cancelled. Each checks kind, key, slots, ApprovalRef, IncidentRef "" and DecisionRef "", and that the approval events are still published.
  - `TestToolCallServerForm` (U-212 (1)): ToolSource `mcp:zzserver` gives `toolCall.requestOnServer` {server `zzserver`}; `MCP:zzserver` the same; `mcp:remote:@{config:AI.MCP.OcuTalon_zzdocs}` gives server `zzdocs`; a class source and `mcp:` alone give `toolCall.request` with no `server` slot.
  - `TestToolCallInputsLine` (U-212 (2)): ToolArguments with a line break, a `password` member holding `zz-secret` and 300 characters give `inputs` with no line break and no `zz-secret`, exactly 200 characters, ending with `$Char(8230)`; a 200-character text is unchanged; "" gives `{}`.
  - `TestToolCallNoticesOnlyForReplayableSessionRows`: the matrix rows "Not for us" and "Not replayable", with the probe at 0 calls.
  - `TestHeldBeforeUpdateSaysWhy`: the DW-454 row in Decide's order; exactly one call, `toolCall.failedWithReason` with the sentence and the DecisionRef; the event's `reason` is the sentence.
  - `TestHeldReasonIsCatalogOnly` (U-212 (3)): the matrix row "Raw reason": one call, `toolCall.failed` with slots {tool, time} only; no slot and no published payload holds the raw line.
  - `TestToolCallNoticeFailureIsLogged`: the probe's `failNotice` and `throwNotice` give one warning each, OK, and the approval event.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Demo/SimPhoneOut.cls` -- new `TestAnsweredNeverEditsAResult`: the matrix's last row. Update the class doc.
- [ ] `src/ocutalon/cls/OcuTalon/Test/Core/ToolCallNotices.cls` (new; the integration AC, real production and real replay, phone only):
  - `TestApprovedCallReachesThePhone`:
    1. A held call of a fixture session goes through the real gate. Within WAIT s the phone gets the `toolCall.request` message (its phone render, "Run zz_replay_send" first, the session's ApprovalRef, Answer "").
    2. `Approval.Answer(ref, "approve", "phone", ANSWERER, NewRef)`, then wait for the row to be `done`.
    3. The phone message's `Answer` is `answered.approved`'s phone render.
    4. A second phone message is `toolCall.done`'s phone render, with ApprovalRef "" and Answer "".
  - `TestRejectedAndExpiredEditInPlace`: one held call rejected gives the line `answered.rejected` and no second phone message; another expired through `Approval.Expire` gives `answered.expired`.
  - It asserts nothing about the web chat (Story 31.6 changes it). Restore ChatAgent's agent and the keys, and clean the rows (`Test.Bridge.Approval.TrackOwner`/`Clean`), also after a failure.

Browser (Rule 3):
- [ ] `web/e2e/answers/answers.spec.ts` -- new X12 and its doc line, the phone half only (no web card, no page change):
  1. Seed a session `tool_call` row (`zz_tool_x12`, `dryRun: null`, requiredRole OcuTalonUser) with `seedApproval`. With a local helper over the imported `irisScript`, set ToolSource `mcp:zzx12`, Runner `ChatAgent` and ToolArguments `{"to":"ops"}` (no hold exists, so approving replays nothing). Open the page, then `sinkEvent('approval.raised')`.
  2. `phoneMessage(user, ref)` appears within `CARD_MS`, with text "Run zz_tool_x12 on zzx12\nInputs: {\"to\":\"ops\"}\nNo dry run is available for this tool. Approving runs exactly this call once." (D2e), and the phone shows it (`messageOf`) with Approve and Reject, named "Approve: run zz_tool_x12" and "Reject: run zz_tool_x12" (the page's existing names).
  3. Press Approve on the phone. The reply is 200; the local line reads "Approved from the simulated phone at HH:MM."; within 5 s of the reply the server has edited the request message: `phoneMessage(...).answer` is "Approved from the simulated phone at HH:MM." (the BridgeSink answered notice; X2 pins "" for a fix). HH:MM is the reply's AnsweredAt.
  4. `answerQuietly(user, ref, 'reject', 'phone')` gets 409, and `readApproval` still shows the phone approval; the request message is unchanged.
  5. Set State `done`, Result `done` and FinishedAt with the local helper, then `sinkEvent('approval.result')`. The phone gets a second message "zz_tool_x12 ran once at HH:MM." (FinishedAt in the stack's zone) with no buttons, and the request message keeps its line.
  6. In `finally`: `dropPhone` and `cleanFixtureRows`.

**Acceptance Criteria:**
- Given an approval of kind `tool_call`, when the bridge reports `approval.raised`, `approval.answered` or `approval.result`, then `BridgeSink` sends `Notification`s of kinds `approval`, `answered` and `result` through `NoticesIn`, each carrying the request's `ApprovalRef` and its (empty) `IncidentRef`, so the phone gets Approve and Reject, an in-place answered line and a result message (`ToolCallNotices` with the real replay; X12).
- Given a request of kind `fix`, when the same events arrive, then `BridgeSink` sends nothing, and `IncidentManager`'s notifications still carry both Refs (`Test.Watch.Tell` `TestAnsweredToEachRecipient`, unchanged; AD-31).
- Given an approved tool call held before the update that Decide closes as failed, when its events arrive, then the person gets exactly one result notice with the plain-English reason and no buttons on the phone (and the paired chat, through Notify), and the `approval` event carries the reason (DW-454, U-170, U-178). The same notice in the web chat is Story 31.6's.
- Given a replayable session tool call whose server is known, when it is raised and answered on the phone, then the phone shows "Run {tool} on {server}", the one-line inputs and the no-dry-run sentence with Approve and Reject; Approve replaces the buttons and the server's in-place answered line follows within 5 s of the reply; a second answer gets 409 and changes nothing; the result is a new phone message with no buttons (X12).
- Given a result message that is newer than the request message, when an answered notice arrives, then the result message is never edited.
- Given the demo path, when `live:demo-path` runs, then it passes unchanged: UJ-1 has no tool call, and every product tool is `safe`.

## Spec Change Log

- 2026-11-02 (plan, re-plan of part A after the split): the Code Map, Tasks, Acceptance Criteria, Design Notes, footprint, Shared surfaces and Verification are narrowed to part A. Removed (Story 31.6's): WebChatOut's tool-call cards, `Ownership.RecentNotices`, `ApprovalRequestCard`'s `request` input, `approval-view.ts`, `chat-view.ts`, `chat-panel.ts`, `notice-card.ts`, their web unit tests, `Test.Core.WebChatOut` `TestToolCallCards`, `Test.Data.Ownership` `TestRecentNoticesIncludeToolCallCards`, `ToolCallNotices`' web assertions, X12's web half, W1 to W5 and W10's web half, and the browser units `cards` and `floor`. Kept as decided: D2a to D2e, the server rule, W6 to W9, the test names, the mutations. AC 4 is restated for the phone (X12's phone half, with the 409 check through the phone). The `<intent-contract>` block is unchanged.
- 2026-11-02 (lead, after the orchestrator's split ruling): Story 31.5 is part A (the notices, U-212's texts on the phone and in the paired chat, DW-454, the SimPhoneOut edit guard); the web chat card (part B) moved to Story 31.6 with its epics.md bullet. The intent contract's card parts are replaced by pointers to 31.6; status reset to `draft` for a re-plan of part A. The whole two-part plan is kept for 31.6's plan outside git.
- 2026-11-02 (lead, epic-31 runner, after hold #2; re-plan): (a) U-212 applied (`apply U-212 at=2026-11-02T13:19:05Z#648`): its four conditions are written into the intent contract's Boundaries and the I/O matrix (server form of the first line, 200-character one-line inputs, catalog-only `{reason}`, labelled `{time}`); Design Notes item 6's "no `on {server}` form" is superseded. (b) The web chat tool-call approval card moves from `deferred:` into scope (the Contest Planner under the owner's delegation: "The web-chat tool-call approval gap is 1.0.0-VISIBLE: PUT IT INTO 31.5"), with an `[AMENDED 2026-11-02, Story 31.5, Contest Planner under the owner's delegation]` acceptance bullet in epics.md. Status reset to `draft` so the plan re-derives the Code Map, Tasks, Verification and size around the amended intent.

## Review Triage Log

## Design Notes

**U-212 (owner decision, lead-written; keep verbatim through the re-plan).** Veto U-212, kept by the Contest Planner under the owner's delegation with four conditions (`at=2026-11-02T13:19:05Z#648`): "Keep, with four conditions. (1) Match the card: the first line is 'Run {tool} on {server}' when the server is known, and 'Run {tool}' only when it isn't. (2) {inputs} stays on one line through the bridge's redactor, and is capped at 200 characters, ending with '…' when cut; the phone and paired chat never get more of a call's inputs than the card shows. (3) {reason} in toolCall.failedWithReason is only ever a catalog reason (such as U-214's), never raw error or exception text; a test pins it. (4) {time} uses the same labelled form as the other catalog times (DW-574 will unify zones later). The Q3 reading (answer edits the request in place; the result is a new message with no buttons, as for a fix in Story 6.4) is kept." The Boundaries say how each condition binds; item 6 below is superseded where it says the request has no `on {server}` form.

**Web chat card (lead-written; keep).** Moved from `deferred:` into scope (see the Intent's amendment). The sibling to extend is `web/src/app/approvals/approval-request-card.ts` (`ApprovalRequestCard`, today drawn by `web/src/app/incidents/incident-card.ts` inside a fix's incident card) with `ApiClient.answerApproval`; Rule 2 applies. *[Moved to Story 31.6 by the split of 2026-11-02; this story builds no card.]*

**Governing ADs (Rule 6):**
- **AD-31:** `BridgeSink` sends the tool-call notices through `NoticesIn`, asynchronously, never waiting more than 1 s; `IncidentManager` keeps fixes.
- **AD-32:** the Notification shape; producers never render (the server, inputs and reason are code-written `text` slots, the wording is the catalog's); only `*Out` operations render; Approve and Reject only for kind `approval` with an ApprovalRef.
- **AD-14:** one routing rule (Notify sends every notification to each channel); one Delivery row per copy; `FindByApproval` and in-place edits per channel.
- **AD-33:** `BridgeSink` stays the one publisher of `approval`, `SimPhoneOut` of `phone`.
- **AD-11:** the row is the truth, so keys come from its fields, not from the event's order.
- **AD-10 and AD-30:** the replay runs once with no model; the inputs are shown and nothing runs without approval; MCP tools are governed like built-in tools (the server is shown, not trusted).
- **AD-12:** the `approval` payload keeps its shape (DW-454 sets its existing `reason`).
- **AD-29:** Lane B files only. **AD-22:** production tests in throwaways. **AD-2:** the bridge stays unaware of the host catalog (`BridgeSink` reads the bridge's public parameters only).

No AD Rule is contradicted, and the spine needs no change.

**Decided in-stage (unattended, small, reversible):**
1. **Q3, result behaviour = a fix's (Story 6.4):** answered edits the request in place; the result is a new message with no buttons, and the request keeps its answered line.
2. **The replayable gate** (ToolSource and Runner set) mirrors `Decide.HeldBeforeUpdate`, so a row Decide would close without running never offers Approve. The fixture tool_call rows of existing specs (rail, layout G2, trace links, answers X6) seed neither, so they get no phone message.
3. **Answered reads `AnsweredAction`, and the edit guard sits in `SimPhoneOut`** (defence in depth: Notify and SimPhoneOut have PoolSize 1 and the result follows the answer; inference).
4. **Cancelled and expired:** no notice for `cancelled`; `expired` sends `answered.expired` (as for a fix).
5. **The page is Story 31.6's.** In this story WebChatOut records a tool-call notice's web Delivery row only (its `INCIDENTKINDS` path, unchanged) and the web chat shows nothing new.
6. **Inputs** are `Bridge.Redact.Text(ToolArguments)` on one line, capped by `BridgeSink` (the renderer folds line breaks but never cuts). The text says "Inputs:", not "exact inputs". *(Its "no `on {server}` form" is superseded by U-212 (1); see W6, W7.)* The Telegram length limit is TelegramOut's (Epic 12).
7. **Q1 footprint:** besides the count lines, `Test/Msg/Catalog.cls` gains the appended `Keys` and `Fixtures` entries, because `TestEntries` and `TestEveryKeyOnEveryChannel` assert the exact key lists. At merge with Epic 40 the entries are a plain union and the count lines take the sum: 95 + 3 + 5 = 103 Core keys.
8. **X12 is the phone half of the old X12** (the dispatch's narrowing): the server form, the phone's Approve, the server's answered line within 5 s of the reply, the 409 second answer through the phone (no web card needed), and the result message. The phone's button names stay the page's existing "Approve: run {tool}" (W5's server-named form is Story 31.6's).
- **W1 to W5: Story 31.6's.**
- **W6. A fifth key for the server form.** U-212 (1) needs two first lines. The catalog's only variant mechanism, the `one` form, keys on a count slot, and every text must hold exactly its declared slots, so the server form is its own appended key, `toolCall.requestOnServer`. The Intent's "Four `toolCall.*` keys" (Approach) and "The four keys go at the end" (Boundaries) predate U-212. Their rule still holds for five keys: they are appended at the end, and only the count lines change. No text or behaviour differs.
- **W7. How a held call's server is known.** The gate stores the MCP toolref itself as `ToolSource` for an MCP call (`Gate.Source` :187-192); spine :338 says that toolref names the `OcuTalon.Mcp.Server` row.
  - The rule: the server is the text after the `mcp:` prefix (any case, `Gate.#MCPPREFIX`), trimmed. When that text is `remote:@{config:AI.MCP.OcuTalon_<name>}` (the attach form, spine :720), the server is `<name>`.
  - A class source, an empty source or a bare `mcp:` means unknown, and the first line is "Run {tool}".
  - Measured: only the `mcp:zzserver` form, in `Test.Bridge.Gate`. What AI Hub passes as the toolref of a live MCP call is unmeasured, because no MCP server exists before step 4 (FR-47) (inference).
- **W8. The reason allowlist is Decide's `HELDBEFOREUPDATE` alone today.** U-170's no-key wording and U-214's sentences are Story 30.7's (set aside until after the v1.0.0 tag) and exist nowhere in `src/`. They are replay failures of replayable rows, which reach the person as `toolCall.failed` through `approval.result`, never through `HeldNotice`. A frontmatter `deferred:` item (low) records the follow-up.
- **W9. The raw-reason case publishes no extra `approval` event,** so raw error text never reaches a payload. `approval.result` has already published the failed state.
- **W10. DW-454's split.** This story closes its notice and event half: the phone and paired-chat result notice with the reason (`toolCall.failedWithReason`) and the `approval` event's `reason`. Its web chat half (the same result notice in the web chat, U-178's "approval card" condition) is Story 31.6's; the lead re-owns that residual to 31.6 at adjudication.

**Decided in-stage -- new public text (veto item for the lead).** These texts are shown on the phone and in Telegram, with no `web` form (Story 31.6 decides the web chat's copy):
- D2a `toolCall.request`: "Run {tool}\nInputs: {inputs}\nNo dry run is available for this tool. Approving runs exactly this call once." The first line and the last sentence are EXPERIENCE.md's; the inputs line is the card's labelled inputs.
- D2e `toolCall.requestOnServer` (U-212 (1)): "Run {tool} on {server}\nInputs: {inputs}\nNo dry run is available for this tool. Approving runs exactly this call once."
- D2b `toolCall.done`: "{tool} ran once at {time}."
- D2c `toolCall.failed`: "{tool} failed at {time}. I won't run it again without a new approval."
- D2d `toolCall.failedWithReason` (DW-454): "{tool} didn't run. {reason}"
- Reused as they are: `answered.approved`, `answered.rejected` and `answered.expired`.
- No new page string: `web/scripts/ux-strings.test.mjs` and `catalog.ts` are unchanged.

**Integration ACs (Rule 1):** no new service; `BridgeSink` and `SimPhoneOut` are extended.
- **Consumes:** Story 30.3's real `approval.result`, `ToolSource`/`Runner` and `HELDBEFOREUPDATE`; Story 6.3's `SimPhoneOut` answered edit and the phone's press; Story 6.4's result message; Story 16.9's `Notice` seam.
- **Consumed-by:**
  - `SimPhoneOut` turns these notices into phone messages (pinned against the real production in `ToolCallNotices` and the real browser in X12);
  - `TelegramOut` turns them into Telegram messages (Epic 12 / Story 31.4: a stub here, and Notify routes to it only for a paired session);
  - Story 31.6: WebChatOut renders the same keys and notices as the web chat's tool-call card and result notice.

**Extend, don't copy (Rule 2):**
- `ToolNotice` and `Compose` follow `IncidentManager.AnswerNotice` and `Compose`. That is a copy across lanes: AD-33 forbids Lane B editing `IncidentManager`, and the shape is five lines.
- The send reuses `BridgeSink.Notice`. `ServerOf` reads `Gate.#MCPPREFIX` and `HeldReasons` reads `Decide.#HELDBEFOREUPDATE`, so no text is copied.
- `ToolCallNotices` extends `InProduction` and reuses `Test.Bridge.Approval`'s public helpers. Its held-call lines copy the private `HeldCall`, because `Test/Bridge/**` is Lane A's.
- X12 reuses the spec's own helpers (`open`, `messageOf`, `lineOf`, `nextReply`, `startOf`, `hhmm`) and the support helpers; its row helper is a local `irisScript` call, because `support/iris.ts` is import-only.

**Ledger inbox (Rule 17):** DW-454 is addressed (its notice and event half): the `BridgeSink` task (`HeldNotice`), `TestHeldBeforeUpdateSaysWhy`, `TestHeldReasonIsCatalogOnly`, AC 3, and W10. Its web chat half is Story 31.6's (W10).

**Footprint extensions (Rule 11 (b)).** Paths outside Epic 31's paths_hint:
- `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls`: the Q1 appended blocks only.
- `Channel/SimPhone/Out.cls`.
- `Test/Core/{BridgeSink,BridgeSinkNoticeProbe,ToolCallNotices}.cls`, `Test/Demo/SimPhoneOut.cls`.
- `web/e2e/answers/answers.spec.ts`.

None is contended. Checked against `origin/OCT-epic{12,13,14,15,30,40}` at the merge base: the only overlap is Epic 40's appends to the two catalog files (Q1).

`new_units:` none. `Test.Core.ToolCallNotices` joins `shard:lane-b` (Core area, group `image`) by area.

**Size (implement to commit, part A): about 5 to 6 hours.**
- **What drives it:**
  - About 11 files, all IRIS but one Playwright spec; no page change.
  - Eight new IRIS test methods in slot-safe classes, plus two production test methods with the real replay (`ToolCallNotices`), whose held-call setup is copied from Lane A's private helper.
  - One Playwright case on the phone (X12).
  - The (once) runs: `Test.Bridge.Approval`, the browser units `answers`, `demo-path` and `sign-in` in three parts (the phone, rail and trace specs), and the fresh shard pair.
- **Estimate by stage:** implement about 2.5 to 3 h; self-review about 0.5 h; the lead's QA about 1 h; review about 0.75 h; smoke and the fresh check about 1 h.

## Verification

Use these variables on every `ci/iris.sh` and `ci/warm.sh` call: `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=31 stage=implement'`, with tags `e31s5i` (fresh) and `e31s5iw` (warm).
- Pass `timeout: 600000` on every call. Run everything in the foreground, one test-runner call per message; never background a run, never `Monitor`, and never re-submit after a client-side timeout. If the harness moves a foreground call to the background after about 180 s, poll its output file in foreground loops under 170 s, never a second copy.
- The only IRIS MCP target is server `ocutalon-slot-c`, namespace `OCUTALON`; check its identity with `iris_server_info` first, and pass `server` and `namespace` on every call.
- Before any browser unit, run `ci/iris.sh build`, because the bundle is not rebuilt by itself (Rule 21).
- No real model key, ever.

**Commands:**
- (loop) `OCUTALON_RUN_TAG=e31s5iw ci/warm.sh up` once. Then run each of these on its own call; each is expected to print `CLASS ... passed`:
  - `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e31s5iw ci/iris.sh class OcuTalon.Test.Core.BridgeSink`
  - `... class OcuTalon.Test.Demo.SimPhoneOut`
  - `... class OcuTalon.Test.Msg.Catalog`
  - `... class OcuTalon.Test.Core.ToolCallNotices`
  - `... class OcuTalon.Test.Core.NoticesInProduction` (unchanged)
  - `... class OcuTalon.Test.Core.WebChatOut` (unchanged; the tool-call notices take its record-only path)

  At the stage's end, also after a failure: `OCUTALON_RUN_TAG=e31s5iw ci/warm.sh down`.
- (once) `... class OcuTalon.Test.Bridge.Approval` on the warm stack (Task 0 sizes it; a fresh `class` call if it nears 8 minutes) -- expected: passes. Its `TestReplayReachesTheLiveStream` session now also gets phone notices, which its `Clean` removes.
- (once) `npm --prefix web test` -- expected: every `scripts/*.test.mjs` passes (no page change).
- (once) `node web/scripts/catalog.mjs --check` and `node web/scripts/payloads.mjs --check`, one per call -- expected: both current with no change (the page renders none of the new keys; no payload changes).
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh build` -- expected: the bundle is built.
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh live answers` -- expected: passes, X12 included.
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh live sign-in --part 1/3`, then `--part 2/3`, then `--part 3/3`, one per call -- expected: every part passes (the phone, rail and trace specs unchanged).
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh live demo-path` -- expected: passes (UJ-1).
- (once) Fresh `OCUTALON_RUN_TAG=e31s5i ci/iris.sh shard lane-b@Core,Demo,Msg`, then the same with `--reverse`, one per call (Rule 19) -- expected: every class passes, with `STACK ...: project` and no `WARM` line.
- (once) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh`, `bash docker/tests/test-storage.sh` and `bash docker/tests/test-ci-config.sh`, one per call -- expected: all pass.
- (once) `OCUTALON_RUN_TAG=e31s5i ci/iris.sh teardown`.

**Shared surfaces:**
- The Core catalog's key count and lists (`Test/Msg/Catalog.cls`).
- The session's phone feed and Delivery rows (phone and web): every spec that sends `approval.*` through the real `BridgeSink` for a session's `tool_call` row (rail.spec :176-206, floor/layout.spec G2 :231-238, trace/links.spec :839-845, answers.spec X6 :511-577, `Test.Bridge.Approval` row 2). Search `web/e2e` and `Test/` for `tool_call` and confirm that each seeds no ToolSource and Runner, or cleans its session.
- The probe's recorded fields (`BridgeSinkNoticeProbe`, read only by `Test.Core.BridgeSink`).

Every test added or changed passes on a fresh environment, in either order.

**Pinning tests and the mutations to apply** (the implement stage writes `mutation: <change> → <red test>` next to each):
- AC 1: drop the `approval.raised` branch → `TestToolCallNoticeKinds` and `ToolCallNotices.TestApprovedCallReachesThePhone` go red. Key answered on `State` → the "already done" answered case goes red.
- AC 2: drop the `Kind = tool_call` check → the fix case of `TestToolCallNoticesOnlyForReplayableSessionRows` goes red.
- AC 3: drop `HeldNotice` → `TestHeldBeforeUpdateSaysWhy` goes red. Drop the replayable gate → the same test goes red (two notices).
- AC 4: drop the `approval.answered` branch → X12 step 3 goes red (the server's `answer` stays ""). Drop `ServerOf` → X12 step 2 goes red.
- AC 5: drop the `ApprovalRef` guard → `TestAnsweredNeverEditsAResult` goes red.
- AC 6: none (the existing unit, unchanged).
- U-212 (1): drop `ServerOf` → `TestToolCallServerForm` goes red. (2): drop the cut → `TestToolCallInputsLine` goes red. (3): drop the allowlist check → `TestHeldReasonIsCatalogOnly` goes red. (4): `TestEveryKeyOnEveryChannel` with the " ET" fixtures.

**Manual checks:**
- `git status --short` shows no path from the Never list, and no change under `web/src/`, nor to `Channel/WebChat/Out.cls`, `Data/Ownership.cls`, `Live/Payload/Approval.cls`, `web/scripts/catalog.mjs` or `ux-strings.test.mjs`.
- `git diff` of `Msg/Catalog/Core.cls` and `Test/Msg/Catalog.cls` shows only the appended blocks, the one comma and the count lines.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
