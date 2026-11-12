---
title: 'Story 21.10: Answer tool-call approval requests on every channel'
type: 'feature'
created: '2026-11-12'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-21-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-21-5-set-up-source-polls-and-answer-tool-call-approval-requests.md'
warnings: ['oversized', 'multiple-goals']
deferred: []
---

<intent-contract>

## Intent

**Problem:** A held tool call already reaches the web chat, the phone and Telegram (Stories 31.5, 31.6), but its request does not say why it waits, shows its inputs as one line cut at 200 characters, and its approval payload names no server. When Story 22.4 cancels a request because its MCP server was removed, nothing is sent: the phone and Telegram keep their buttons, and the chat card shows no status.

**Approach:**
- Extend `BridgeSink.ToolNoticeOf` and the two `toolCall.request*` catalog entries. The notice gains a code-written "Why:" line and the exact inputs as labelled lines, through a new `inputs` slot type in `Msg.Catalog` (built like `groups`).
- The approval payload gains `server` (the rail row reads "Run {tool} on {server}") and `cancelledAt`.
- For a cancelled MCP request whose server is gone, the sink sends kind `answered` with Story 35.2's accepted `answered.canceled`. The phone and Telegram then edit the message in place and drop the buttons, and the chat card shows the status.
- **Proposed split:** epics AC 2 (the standalone fix request) moves to a new sibling, 21.11 (Design Notes).

## Boundaries & Constraints

**Always:**
- Producers never render text (AD-32). `BridgeSink` gives slots, and `Msg.Catalog.Render` makes every text, for every channel.
- The inputs are exact:
  - one line per top-level member, in the stored (canonical) order;
  - each value is its JSON text, so a line break inside a value shows as `\n` and can never start a line of its own;
  - no cut;
  - the redactor (`Bridge.Redact.Text`) still masks secrets in each line, as today.
- `answered.canceled` is sent only when its text is true: for a replayable `tool_call` whose `ServerOf(ToolSource)` is not empty and whose server has no `OcuTalon.Mcp.Server` row any more. Any other cancellation sends nothing, as today. Its `{time}` is the time at which the sink received `approval.cancelled` (the same value for the notice and the payload).
- The rail keeps UX-DR52: a row shows the action, raised and expiry, and no answer buttons (X6 stays as it is).
- `BridgeSink` stays asynchronous. It waits on no lock for more than one second, and never fails its caller (AD-31).
- Only accepted or listed text ships (Public text). Every test added or changed creates and removes its own `zz` rows and sessions, and passes on a fresh environment, in either order.
- **Online demo:** no behaviour changes (Design Notes, "Online demo").

**Never:**
- The standalone fix request (epics AC 2; proposed 21.11).
- Any Lane A edit: `src/bridge/**`, `Mcp/**`, `Fix/**`, `Watch/**`, `Channel/Telegram/**`. `Mcp.Server` is only read.
- A stored column, a table, a route, a role, a grant or a privilege.
- Answer buttons on a rail row.
- A model-written reason.
- A real MCP server.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Raise, MCP | Replayable session row: ToolSource `mcp:remote:@{config:AI.MCP.OcuTalon_zzS}`, ToolName `zz_delete_ticket`, ToolArguments `{"id":"T-1","n":2}` | Kind approval, `toolCall.requestOnServer`, slots `{tool, server:"zzS", inputs:[{name:"id",value:"\"T-1\""},{name:"n",value:"2"}]}`. Phone text: `Run zz_delete_ticket on zzS` / T1 / `Inputs:` / `id: "T-1"` / `n: 2` / the no-dry-run sentence | -- |
| Raise, no server | Developer tool (class source) | `toolCall.request`: the same lines with no `on {server}` | -- |
| No inputs | ToolArguments `{}` or empty | `Inputs:` then `{}` | -- |
| Long or tricky value | A 5,000-character value; a value holding a line break and `Approve:` | Shown whole (Telegram splits into parts, buttons on the last); the line-break value stays one line with `\n` | -- |
| Unreadable arguments | ToolArguments not a JSON object (Raise refuses this, so only a hand-made row) | No notice; one warning naming the Ref | Fail closed |
| Cancel, server removed | Pending MCP row; `Approval.Cancel` after its server row is gone | Kind answered, `answered.canceled` `{time, server}`, ApprovalRef set. The phone answer line and Telegram message are edited and their buttons removed. The approval event has `state` cancelled, `server` and `cancelledAt`. The card shows "Canceled at HH:MM: the MCP server zzS was removed. Nothing was changed." The rail row leaves | Send failure: one warning |
| Cancel, other | Server still registered (a session end), a non-MCP tool call, or any fix | No notice; payload without `cancelledAt`; card shows no status (as today) | -- |
| Press after cancel | Web, phone or Telegram | 404 "That request is no longer available."; Telegram `press.unavailable`; nothing runs (existing) | -- |
| Online demo | Any | Unchanged (no MCP row exists there) | -- |

</intent-contract>

## Code Map

**Existing (verified on this branch, HEAD e66ca209):**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - class doc :20-40 (`approval.cancelled: nothing` :32);
  - `OnEvent` :106-128;
  - `Approved` :144-163, the payload per recipient;
  - `ToolNotice` :206-224 and `Replayable` :227;
  - `ToolNoticeOf` :233-254: raised :235-241, expired :247, result :248-252;
  - `Compose` :258;
  - `ServerOf` :272 (private);
  - `InputsOf` :286-302 and `INPUTSMAX` :103 (the 200-character cut);
  - keys :86-100;
  - `HeldNotice` :341-345, which sets `payload.Reason` (the precedent for a sink-set payload member).
  - `Notice` :432 is the test seam.
- `Msg/Catalog/Core.cls`: `toolCall.request` :594 and `toolCall.requestOnServer` :602 (texts with "Inputs: {inputs}"), and `answered.canceled` :806 (accepted, Story 35.2; used by no product code).
- `Msg/Catalog.cls`: the slot types in the doc :7-20, the dispatch :159-194, `Groups` :213 and `GROUPLINE` :48 (the sibling of the new `inputs` type), and Clean's one-line rule :21-26.
- `Live/Payload/Approval.cls` :1-56. Its doc says "The reason has no source in the row". There is no `server` member.
- `Channel/WebChat/Out.cls`:
  - `ToolCallCard` :111-119 (the keys are unchanged);
  - kind answered gives a Delivery row only.
- `Channel/SimPhone/Out.cls` doc :20-26 and `Channel/Telegram/Out.cls` doc :44-57: a kind answered edits in place and removes the buttons, for any key (pinned by `Test.Channel.TelegramOut` `TestEditApproved`/`TestEditOnce`). `BUTTONLIMIT` 3840 :120. Neither class changes.
- Answering a cancelled request:
  - `Bridge/Approval.cls` `AnswerLocked` :357 gives `not_found`;
  - `Core/AnswersIn.cls` :143;
  - `Web/Api.cls` :680 gives 404.
  - The first answer wins at :358-362.
- `Bridge/Approval.cls` `Cancel` :423-432 stores no time and no reason; `Move` :462 fires `approval.cancelled` after the unlock (read only).
- `Mcp/Server.cls` `NameIndex` :32, which gives `NameIndexExists` (Lane A, read only).
- Web:
  - `web/src/app/chat/chat-panel.ts` :167-170 draws a live tool-call request as `app-approval-request-card` with the notice text (`chat-view.ts` `liveRequest` :284);
  - `web/src/app/approvals/approval-view.ts`: `statusOf` :373-387 (no cancelled case); `approvalView` :393 (the first line names the buttons); `AnswerStatus` tones :94-97;
  - `approval-request-card.ts`: `.action` is `pre-line` :288-291, and the tones are at :427-433;
  - `web/src/app/rail/rail-view.ts`: `RAIL_TEXTS.runTool` :49, `approvalTitle` :186-209, `approvalRow` :224 (no jump without an incident), `pendingApprovals`;
  - `web/scripts/catalog.mjs`: `LISTED_KEYS` :66 (the nine `answered.*` :89-97) and `TEXT_SLOT_KEYS` :131. It generates `web/src/app/msg/catalog.ts`;
  - `web/scripts/payloads.mjs` generates `web/src/app/live/payloads.ts` (`ApprovalPayload` :227).
- Tests that pin today's shape (shared surfaces):
  - `Test/Core/BridgeSink.cls`: `TestToolCallNoticeKinds` :816, `TestToolCallServerForm` :866, `TestToolCallInputsLine` :884, `TestToolCallNoticesOnlyForReplayableSessionRows` :938;
  - `Test/Core/ToolCallNotices.cls` (live; header :1-19);
  - `Test/Core/WebChatOut.cls` :206-217, :248;
  - `Test/Demo/SimPhoneOut.cls` :704, :796 (an `inputs` string slot);
  - `Test/Msg/Catalog.cls` :1138-1139, :1608-1609;
  - `Test/Live/Payloads.cls`;
  - `web/scripts/approval-view.test.mjs` :339, `chat-announcements.test.mjs` :392, `chat-view.test.mjs` :113-118, `rail-view.test.mjs`, `catalog.test.mjs`, `playwright-projects.test.mjs` :340 ("X1 to X13");
  - `web/e2e/answers/answers.spec.ts`: X6 :514-571, X12 :852-915, X13 :917+ (asserts the 200-character cut); helpers `seedApproval`, `setApprovalFields`, `sinkEvent`, `phoneMessage`;
  - `web/e2e/rail/rail.spec.ts` R3 :166-175.
- **From Story 22.4 (Lane A, in progress in the epic-22 worktree, not merged).** Approval:
  - `Approval.CancelPending` (cancels through `Cancel`, so `approval.cancelled` fires once per row);
  - `McpOps` calls it after a removal commits;
  - `ApprovalRequest.ToolFingerprint`;
  - `FinishExecution` `changed`.

  Its R1 hunk in `BridgeSink`:
  - the doc lines :30-31;
  - `KEYCHANGED` after `KEYFAILEDWHY` :94;
  - the result branch :248-252;
  - plus one row in `Test.Core.ToolCallNotices`.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement, before code; source reads only; record the results under Design Notes "Read at implement"):
  - (a) Confirm that 22.4 is merged into this branch: `Approval.CancelPending`, `McpOps` calling it, and the R1 branch in `BridgeSink`. If not, stop with `## Clarification Needed` (C1).
  - (b) Record the post-merge line numbers of R1's three regions in `BridgeSink`, and edit around them (never inside).
  - (c) Confirm that the Planner's ruling on T1 and T2 is recorded. Until then, build with the proposed wording and do not commit it (standing PUBLIC TEXT rule).
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls` -- new slot type `inputs`, after `groups`, built the same way:
  - the value is an array of `{name, value}` strings;
  - each member is one line, `INPUTLINE` `"{name}: {value}"`, and each part is cleaned like a string slot;
  - an empty array is the line `{}`;
  - a member that is not such an object is an error naming the key and the slot.
  - Update the class doc's type list.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls` -- `toolCall.request` and `toolCall.requestOnServer`: the T1/T2 texts (Public text). `inputs` becomes type `inputs`. Update `source`.
- [ ] `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - `InputsOf` gives the array. It parses `ToolArguments`; a value is the member's JSON text, through `Bridge.Redact.Text`; there is no cut. Remove `INPUTSMAX`. Unreadable arguments are a warning, and no notice is sent.
  - New private `CanceledServer(row)`: `ServerOf(row.ToolSource)` when the row is `Replayable` and the private seam `Registered(server)` (`##class(OcuTalon.Mcp.Server).NameIndexExists`) is 0; else "".
  - `OnEvent` takes the time once for `approval.cancelled` (`Bridge.Time.NowUtc()`) and passes it to `Approved` and `ToolNotice`.
  - `Approved` sets `payload.CancelledAt` for that event when `CanceledServer` is not empty.
  - `ToolNoticeOf` gets an `approval.cancelled` branch beside the expired one: kind answered, new `KEYCANCELED` `answered.canceled` `{time, server}`, through `Compose`.
  - `ServerOf` becomes public (the payload calls it; no third parser of the attach form).
  - Update the class doc :20-32. Do not touch R1's regions.
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls`:
  - `Server` (`server`, MAXLEN 512, as `ToolSource`, since a bare `mcp:` form gives back its whole rest): set by `FromRow` from `Core.BridgeSink.ServerOf(row.ToolSource)` for a `tool_call` row.
  - `CancelledAt` (`cancelledAt`, MAXLEN 20): set only by the sink.
  - Update the doc.
- [ ] `web/scripts/catalog.mjs` -- `answered.canceled` joins `LISTED_KEYS` and `TEXT_SLOT_KEYS` (slot `server`). Then regenerate `src/app/msg/catalog.ts` (`node scripts/catalog.mjs`) and `src/app/live/payloads.ts` (`node scripts/payloads.mjs`). Update the generator's header list.
- [ ] `web/src/app/approvals/approval-view.ts` -- `statusOf` handles `cancelled` when `cancelledAt` and `server` are set: `answered.canceled` with `{time: timeBeside(cancelledAt), server}`, tone `rejected`, icon `circle-slash`. Otherwise it stays undefined. Update the header doc.
- [ ] `web/src/app/rail/rail-view.ts` -- `RAIL_TEXTS.runToolOn` `'Run {toolName} on {server}'`. `approvalTitle` uses it for a `tool_call` with a `server`. Update the doc.
- [ ] **Tests (ObjectScript):**
  - `Test/Core/BridgeSink.cls`, with `BridgeSinkNoticeProbe.cls`, which also overrides the `Registered` seam:
    - update `TestToolCallNoticeKinds`/`ServerForm`/`InputsLine` to the array;
    - add rows for no inputs, the long value, the line-break value, unreadable arguments, cancel with the server gone (`Registered` seam 0), cancel with it registered, cancel of a non-MCP row, and the payload's `cancelledAt` and `server`.
  - `Test/Msg/Catalog.cls`: the `inputs` type (lines, empty, bad member) and the new texts for web, phone and telegram.
  - `Test/Live/Payloads.cls`: `server` for the attach form, the bare form and a class source.
  - `Test/Core/WebChatOut.cls` and `Test/Demo/SimPhoneOut.cls`: fixtures to the array slot.
  - `Test/Core/ToolCallNotices.cls`:
    - the phone text with T1 and the labelled lines;
    - new `TestCancelledEditsInPlace`: a fixture MCP row whose server has no row, then `Approval.Cancel`. The phone answer becomes the phone render of `answered.canceled`, and no second message is added.
- [ ] **Tests (web):**
  - `web/scripts/approval-view.test.mjs` (cancelled with and without `cancelledAt`), `rail-view.test.mjs` (`runToolOn`), `catalog.test.mjs`, and the fixture strings in `chat-view.test.mjs`/`chat-announcements.test.mjs`.
  - `web/e2e/answers/answers.spec.ts`:
    - **X12** and **X13** are updated to the new text. X13 asserts the long note whole and the "Why:" line, and adds that the rail row reads "Run zz_tool_x13 on zzx13" with no button.
    - New **X14**: a pending MCP-form request shows its card, rail row and phone message. Then the case cancels it through `Approval.Cancel` (irisScript), and:
      - within one live update the rail row is gone;
      - the card shows the cancelled status with no buttons;
      - the phone line is the canceled text with no buttons;
      - a press through the answer route gets 404.
  - `web/scripts/playwright-projects.test.mjs` "X1 to X14", and the case list in the `docker/tests/test-answers.sh` header.
- [ ] **Docs and spine** (after the gate, marker `[ADDED <the day the lead writes it>, Story 21.10]`): S1-S3 of Design Notes go into `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`. In `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`, Step 4's tool-call bullet :1080 and a catalog row with the accepted T1/T2 go in together with the catalog (DW-1045). The lead writes both after the Planner's ruling.

**Acceptance Criteria:**
- Given a pending `tool_call` request with an MCP server (a fixture row until 22.4's rows exist), when it shows in the web chat, then its card shows:
  - "Approval needed";
  - "Run {tool} on {server}";
  - "Why:" with T1;
  - "Inputs:" and the exact inputs as labelled lines, uncut;
  - "No dry run is available for this tool. Approving runs exactly this call once.";
  - Approve and Reject, named "Approve: run {tool} on {server}";
  - and the expiry.

  (X13, `Test.Core.BridgeSink`, `Test.Msg.Catalog`)
- Given the same request, when it shows on the phone and in Telegram, then each has the same text as plain text, with Approve and Reject. The rail row reads "Run {tool} on {server}" with its raised and expiry times and no answer button. The first answer wins everywhere (X12, X13, X6, `ToolCallNotices`; first answer: `Approval.AnswerLocked`, existing).
- Given a pending MCP request that 22.4 cancels because its server was removed, when the cancellation arrives, then:
  - a press on any channel answers nothing;
  - the phone and Telegram messages are edited to "Canceled at {time}: the MCP server {server} was removed. Nothing was changed." with their buttons removed;
  - the rail row leaves within one live update;
  - and the card shows that status in place of its buttons.

  (X14, `ToolCallNotices` `TestCancelledEditsInPlace`, `Test.Core.BridgeSink`, R3)
- Given a cancellation that was not a server removal, when it arrives, then no notice is sent and no card claims a removed server (`Test.Core.BridgeSink`).
- Given the online demo, when the demo path runs, then nothing changes (`live demo-path`, X1-X11 unchanged).

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs (Rule 6):**
- AD-10: every held call counts as risky; that is T1's reason.
- AD-11: the row is the truth; `Cancel`; `not_found` after a cancel.
- AD-14: the channels' in-place edits.
- AD-16: no dry run for a tool call.
- AD-31: `BridgeSink` is the one sink. It sends its notices asynchronously through `NoticesIn` and waits on no lock for more than one second.
- AD-32: producers never render; the one renderer gains a slot type; Approve and Reject only for kinds incident and approval.
- AD-33: `Mcp.Server` is read, never written, by Lane B.
- AD-29: lanes.

No AC contradicts an AD's Rule.

**Read for 21.10 (21.5's claims, checked on this branch):**
- Already met, confirmed:
  - The notices on the phone, Telegram and web chat: `ToolNoticeOf` :233-254, `WebChatOut.ToolCallCard` :111-119, and Telegram's buttons for kind approval.
  - First answer wins: `AnswerLocked` :358-362.
  - The cancelled row leaves the rail: `pendingApprovals`; R3 :175.
  - The card's label, buttons and expiry: `approvalView`, X13. Correction: the tool-call card is drawn from the notice's text (`chat-panel.ts` :167), not from the incident card.
  - A press on a cancelled request already answers nothing: :357, AnswersIn :143, Api :680.
- Gaps, confirmed:
  - no reason (no column, `FromRow`'s doc);
  - the one cut line (`InputsOf`, `INPUTSMAX` 200, X13);
  - no `server` member;
  - no cancelled notice (:32);
  - `answered.canceled` unused (grep: only the catalog);
  - no status for a cancelled card (`statusOf` default);
  - no notice or card for a fix with no incident (`Replayable` :229, `ToolCallCard` keys, `requestsOf`).
- New, not in 21.5's list:
  - Cancel stores no time, so the sink stamps the time.
  - Session end also cancels requests (`SessionOps.EndApprovals` :359), so "the server was removed" must be checked, not assumed.
  - `rail-view.approvalTitle` would title an email fix "Repair and resend" (for 21.11).

**Proposed split (doctrine U5; the lead rules; this spec plans only 21.10's child):**
- **21.10 (this spec):** epics AC 1 (the tool-call card and its plain-text copies) and AC 3 (the cancelled request on every channel). Both rest on 22.4.
- **21.11 (new, proposed): "Answer a standalone fix request on every channel".** Epics AC 2 moves to it verbatim. It runs after 22.7 merges, with fixture rows until then. Moving the AC is veto item V1.
- **Why split:**
  - 22.7 is in the backlog with no spec, so the email row's shape (DryRun `to`/`subject`/`text`, its FixParameters, and Raise's `FixTargets` rule, which refuses a fix without targets today) is not fixed.
  - AC 2 needs its own new texts (the request with the exact body and every recipient, and its results), a slot type for a body with line breaks (`Render` folds them today), a new `Receivers`/`ToolNotice` branch for kind fix, a web card branch, and a rail title.
  - Together the two parts touch about 22 files.
- **Read for 21.11:**
  - `Replayable` :229 restricts notices to `tool_call`.
  - `WebChatOut.ToolCallCard` :111-119 lists the keys.
  - `approval-view.requestsOf` :205-213 needs an incident.
  - `approvalTitle` falls to `RAIL_TEXTS.repair`.
  - Telegram's approved alert has no text without a count (`Telegram/In.cls` :41), which fits an email fix.
  - The accepted email texts of 21.6 ("The email was sent." and the refusals) can serve as result texts.
  - 21.10's `answered`/cancel branches are reusable as they are.

**Decided in-stage (reversible inside this story):**
1. **The rail row (the AC's "same content as plain text").** The rail carries the request's action ("Run {tool} on {server}") with its raised and expiry times, as UX-DR52 defines a rail row. Approve and Reject are on the card, the phone and Telegram. X6's reason holds: the only control a rail row has is its jump to an incident's card, and a tool call has no incident, so it has no control. X6 is not changed (V6).
2. **The reason is code-written** (T1). Every held call is held because its tool counts as risky (risky or unclassified, AD-10), which needs no stored column, no classification read at notice time, and no model text.
3. **Inputs are exact**: JSON text values, no cut. A call's arguments come from one model reply, which max_tokens 8,000 bounds (about 32,000 characters; inference). Telegram already splits a long message at `BUTTONLIMIT`.
4. **The cancel time** is the sink's clock when `approval.cancelled` arrives. It fires right after the commit in the cancelling job, so it is within a second of the cancel (inference: same job, after `Lock -`).
5. **"Server removed" is checked** (`Mcp.Server` has no row of that name), because a session end cancels requests too.
6. **The cancelled status** uses the rejected tone with `circle-slash` (nothing was changed). DESIGN has no cancelled tone.
7. **Unreadable arguments send no notice** (fail closed). An approver never sees a request whose exact call cannot be shown.

**Clarifications for the lead (non-blocking; the plan runs on the stated default):**
- **C1 (order, for the orchestrator's graph):** 21.10 implements only after 22.4 merges into this branch. `epic-dependencies.yaml` has no `"21.10"` story wait (epic-21 :364-369). Default: Task 0 (a) stops the implement stage until 22.4 has merged.
- **C2:** the split into 21.10 + 21.11 (V1).

**Contended edits needed:** none. Every Lane A piece is used through a published record or API: 22.4's `approval.cancelled` per row, `ToolSource`/`Runner`, and a read of `Mcp.Server`. In `Core.BridgeSink` this story touches:
- the class doc :20-32, outside R1's :30-31;
- the keys after :100;
- `OnEvent`, `Approved`, `ToolNotice`;
- `ToolNoticeOf`'s raised branch :235-241 and a new cancelled branch after :247;
- `ServerOf` :272 and `InputsOf` :286-302.

It never touches R1's result branch or `KEYCHANGED`. Because 21.10 implements after 22.4 merges (C1), there is no union to make; Task 0 (b) records the merged lines.

**Online demo:** no behaviour changes.
- No MCP server can be registered there (22.2, 22.4), so no `tool_call` with a server exists, and no MCP cancel happens.
- A session end's cancellations fail the server check and send nothing new.
- Fix cards and UJ-1 are untouched: the incident card skips cancelled requests (`requestsOf`), and the new status needs `cancelledAt`.
- `live demo-path` and answers X1-X11 stay green.

**Ledger:**
- Inbox: none.
- DW-592 (wontfix-accepted, U-254) stays closed: after a reload a cancelled card is a plain notice with no pending cue, as for any answered request.
- DW-1045 does not reopen: the tool-call texts change in `Catalog.Core` and EXPERIENCE together (the docs task).

**Integration ACs (Rule 1):**
- The new `inputs` slot type is consumed by the real `SimPhoneOut`, `TelegramOut` and `WebChatOut` through `Render` (`ToolCallNotices`, X12, X13).
- `server`/`cancelledAt` are consumed by the real card and rail (X13, X14).

**Consumes:**
- 22.4: `approval.cancelled` from `CancelPending`, and MCP rows.
- 31.5/31.6: `ToolNoticeOf`, the card.
- 35.2: `answered.canceled`.
- 6.3: the in-place edits.
- `Mcp.Server`.

**Consumed-by:**
- 21.11: the cancelled branch and the `answered` compose for a fix with no incident.
- 22.6: documents the held-call card.

**Extend, don't copy (Rule 2):**
- `inputs` follows `Groups`/`GROUPLINE`.
- The cancelled notice is a `ToolNoticeOf` branch through `Compose`, beside the expired one.
- `CancelledAt` follows `HeldNotice`'s `payload.Reason`.
- `server` reuses `BridgeSink.ServerOf`; it is not a new parser (22.4's routed LOW: `reopen_if` = a third parser).
- The status extends `statusOf`, and the rail title extends `approvalTitle`.
- The phone and Telegram edits are the existing ones, unchanged.

**Spine items (after the gate; additive):**
- **S1, AD-31:** "(step 4's email fix, Story 22.7; this part built in Story 21.5)" becomes "...built in Story 21.11, split from Story 21.10". If the split is declined, it becomes "Story 21.10".
- **S2, AD-31, after the tool-call notice sentence:** "On `approval.cancelled` of a replayable MCP `tool_call` whose server has no `Mcp.Server` row, it sends kind `answered`, `answered.canceled` {time, server}, and the approval event carries `server` and `cancelledAt`. Any other cancellation sends nothing [ADDED, Story 21.10]".
- **S3, AD-32 renderer:** "slot type `inputs`: an array of {name, value}, one line `{name}: {value}` each, `{}` for none [ADDED, Story 21.10]".

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | Split: epics AC 2 moves verbatim to new Story 21.11 (after 22.7) | approve | -- |
| V2 | Changed public text: both `toolCall.request*` entries gain "Why:" (T1) and the labelled inputs (T2) | Planner | never shown (no tool calls) |
| V3 | Live `approval` payload gains `server` and `cancelledAt`. These are event members, not stored; every page gets them | approve | always empty |
| V4 | The 200-character inputs cut is removed (31.5's INPUTSMAX): approvers see the exact call. Redaction is kept | approve | -- |
| V5 | Lane B reads Lane A's `Mcp.Server` (`NameIndexExists`), read only, to keep `answered.canceled` true | approve | no rows |
| V6 | The AC's rail reading (Decided 1): action and times, no answer buttons | approve | unchanged |
| V7 | Order C1: implements after 22.4 merges (a cross-epic story wait) | approve | -- |

There is no new command, route, grant, role, privilege, table, column, retention or web dependency.

## Public text

**Reused (accepted):**
- "Approval needed", "Run {tool} on {server}", "No dry run is available for this tool. Approving runs exactly this call once.", Approve, Reject, and the expiry ("Expires {when}");
- `answered.canceled` "Canceled at {time}: the MCP server {server} was removed. Nothing was changed." (Story 35.2; on the page it keeps its period, as EXPERIENCE :722 says);
- "That request is no longer available."; `press.unavailable`.

**New, for the Planner** (every channel; online demo: never shown):
- **T1, the reason line** (both entries): "Why: {tool} counts as risky, so it runs only after an approval."
- **T2, the inputs block.** The line "Inputs:" (it was "Inputs: {inputs}"), then one line per input, "{name}: {value}", with the value as JSON (for example `id: "T-1"`, `n: 2`), and the line "{}" for a call with no inputs.
- **The full `toolCall.requestOnServer` text:** "Run {tool} on {server}\nWhy: {tool} counts as risky, so it runs only after an approval.\nInputs:\n{inputs}\nNo dry run is available for this tool. Approving runs exactly this call once." `toolCall.request` is the same text without " on {server}".

**Findability:** no More to try item; MCP is off on the demo.

## Verification

Run every command from the worktree root, after `git rev-parse --show-toplevel` matches it.
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s10iw` and fresh `e21s10i`; QA `e21s10qw`/`e21s10q`; review `e21s10rw`/`e21s10r`. The live units and `ToolCallNotices` (it changes the production) run only on lane-C throwaways.
- One command per foreground call, with `timeout: 600000`, each sized to about 150 s (the harness backgrounds a call at about 170-180 s). If one is backgrounded, wait in bounded foreground polls, never `Monitor`.
- Never two test runs in one message. One `iris_execute_tests` per message, with `server` and `namespace`. Never a slot, `ocutalon-aihub-test` or another lane's stack; tear down only this stage's tags.

**Shared surfaces:**
- the `toolCall.request*` texts and the `inputs` slot (`Test.Core.BridgeSink`, `Test.Core.WebChatOut`, `Test.Demo.SimPhoneOut`, `Test.Msg.Catalog`, the X12/X13 strings, the fixtures of `approval-view`/`chat-view`/`chat-announcements`);
- the `approval` payload (`payloads.ts`, `Test.Live.Payloads`);
- the page catalog's listed keys (`catalog.test.mjs`);
- the rail's tool-call title (`rail-view.test.mjs`, X6, R3);
- the answers project's case inventory (`playwright-projects.test.mjs`, `test-answers.sh`).

Criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `<vars> OCUTALON_RUN_TAG=e21s10iw ci/warm.sh up` -- ready.
- (loop) `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s10iw ci/iris.sh class OcuTalon.Test.Core.BridgeSink` -- passed. Mutations:
  - `InputsOf` back to one line → the inputs rows go red;
  - the cut kept → the long-value row goes red;
  - no cancelled branch → the server-gone row goes red;
  - `CanceledServer` without the `Registered` check → the still-registered row goes red;
  - `CancelledAt` never set → the payload row goes red.
- (loop) `... class OcuTalon.Test.Msg.Catalog` -- passed. Mutations: no "Why:" line in `toolCall.requestOnServer` → its fixture goes red; `INPUTLINE` without `{value}` → red.
- (loop, one per call) `... class OcuTalon.Test.Live.Payloads`, `... OcuTalon.Test.Core.WebChatOut`, `... OcuTalon.Test.Demo.SimPhoneOut` -- passed. Mutation: `FromRow` without `Server` → `Payloads` goes red.
- (once each, one per call) `... class OcuTalon.Test.Channel.TelegramOut`, `... OcuTalon.Test.Core.AnswersIn` -- passed (unchanged).
- (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh class OcuTalon.Test.Core.ToolCallNotices` (fresh throwaway) -- passed. Mutation: no cancelled branch → `TestCancelledEditsInPlace` red.
- (once) `cd web && node scripts/catalog.mjs --check && node scripts/payloads.mjs --check`, then (once) `node --test web/scripts/` -- passed. Mutations: `statusOf` without the cancelled case → `approval-view.test` red; `approvalTitle` ignoring `server` → `rail-view.test` red.
- (once each) `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `cd web && npm run build` -- clean.
- (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh build`, then (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh live answers` -- passed. It took 446 s in CI on x64; about 150 s is expected here (inference). Mutation: no cancelled branch → X14's phone and card lines go red.
- (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh live demo-path` -- passed (online-demo safety, UJ-1).
- (once each) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh` -- pass.
- (once each, also after a failure) `<vars> OCUTALON_RUN_TAG=e21s10iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh teardown`.
- (once, after S1-S3) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- no finding beyond the baseline.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
