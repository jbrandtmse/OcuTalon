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

**Problem:** A held tool call already reaches the web chat, the phone and Telegram (Stories 31.5, 31.6), but its request does not say why it waits, shows its inputs as one line cut at 200 characters, and its approval payload names no server. When Story 22.4 cancels a request because its MCP server was removed, nothing is sent: the phone and Telegram keep their buttons, and the chat card shows no status. Story 22.4's `mcp.replayToolChanged` result reaches the phone and Telegram but draws no web chat card (DW-1232). The guide still says "cut to 200 characters" (DW-1266), and its "Approval and audit" paragraph says `send_email` is the only per-call built-in tool (DW-1314).

**Approach:**
- Extend `BridgeSink.ToolNoticeOf` and the two `toolCall.request*` catalog entries. The notice gains a code-written "Why:" line and the exact inputs as labelled lines, through a new `inputs` slot type in `Msg.Catalog` (built like `groups`). Every invisible or line-breaking character in an input shows as `\uXXXX` (V10).
- The approval payload gains `server` (the rail row reads "Run {tool} on {server}") and `cancelledAt`.
- For a cancelled MCP request whose server is gone, the sink sends kind `answered` with Story 35.2's accepted `answered.canceled`. The phone and Telegram then edit the message in place and drop the buttons, and the chat card shows the status.
- In Telegram, a tool-call request too long for one message shows its start, the V9 line and no buttons (V4, V8: a granted Lane A edit).
- The web chat draws `mcp.replayToolChanged` as a card (DW-1232).
- Text only: the ruled D1, D2, D3 and DW-1314 sentences in the guide, and their pins (DW-1266, DW-1315).
- **Split (approved, ruling E):** epics AC 2 (the standalone fix request) is Story 21.11.

## Boundaries & Constraints

**Always:**
- Producers never render text (AD-32). `BridgeSink` gives slots, and `Msg.Catalog.Render` makes every text, for every channel.
- The inputs are exact:
  - one line per top-level member, in the stored (canonical) order;
  - each value is its JSON text, never cut;
  - the redactor (`Bridge.Redact.Text`) runs on the WHOLE arguments object first, so its key rules (`api_key` and the rest) still mask a value; then each member is split out (Decided 9);
  - every character in Unicode categories Cc, Cf, Zl and Zp, plus tab, shows as a backslash, `u` and four upper-case hex digits, so no value can hide text or start a line of its own; an astral one shows as its two surrogate halves; ordinary spaces stay (V10, Design Notes "V10 definition").
- `answered.canceled` is sent only when its text is true: for a replayable `tool_call` whose `ServerOf(ToolSource)` is not empty and whose server has no `OcuTalon.Mcp.Server` row any more. Any other cancellation sends nothing, as today. Its `{time}` is the time at which the sink received `approval.cancelled` (the same value for the notice and the payload).
- The rail keeps UX-DR52: a row shows the action, raised and expiry, and no answer buttons (X6 stays as it is).
- `BridgeSink` stays asynchronous. It waits on no lock for more than one second, and never fails its caller (AD-31).
- Only accepted or ruled text ships (Public text). Every test added or changed creates and removes its own `zz` rows and sessions, and passes on a fresh environment, in either order.
- No invisible or line-breaking character is ever pasted into a file. Tests build them in code: `$Char(8203)`, `$Char(8238)`, `$Char(56128,56385)`, `$Char(8232)`, `$Char(13,10)`, `$Char(9)` in ObjectScript (also inside an e2e `irisScript` text), `\u` escapes in JS string literals.
- **Online demo:** no behaviour changes (Design Notes, "Online demo").

**Never:**
- The standalone fix request (epics AC 2; Story 21.11).
- Any Lane A edit (`src/bridge/**`, `Mcp/**`, `Fix/**`, `Watch/**`, `Channel/Telegram/**`) except the V8 grant: in `Channel/Telegram/Out.cls`, the two parameters and the over-long branch (with its doc lines); in `Test/Channel/TelegramOut.cls`, the three tests. Nothing else in Lane A. `Mcp.Server` is only read.
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls` (contended; not needed).
- A stored column, a table, a route, a role, a grant or a privilege.
- Answer buttons on a rail row.
- A model-written reason.
- A real MCP server.
- An Approve button on a Telegram tool-call request that is shown cut.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Raise, MCP | Replayable session row: ToolSource `mcp:remote:@{config:AI.MCP.OcuTalon_zzS}`, ToolName `zz_delete_ticket`, ToolArguments `{"id":"T-1","n":2}` | Kind approval, `toolCall.requestOnServer`, slots `{tool, server:"zzS", inputs:[{name:"id",value:"\"T-1\""},{name:"n",value:"2"}]}`. Phone text: `Run zz_delete_ticket on zzS` / T1 / `Inputs:` / `id: "T-1"` / `n: 2` / the no-dry-run sentence | -- |
| Raise, no server | Developer tool (class source) | `toolCall.request`: the same lines with no `on {server}` | -- |
| No inputs | ToolArguments `{}` or empty | `Inputs:` then `{}` | -- |
| Secret by key | ToolArguments `{"api_key":"abc123","q":"x"}` | `api_key: "[redacted]"`, `q: "x"` (the whole object was redacted first) | -- |
| Invisible characters (V10) | One input `note` holding ZWSP, U+202E, U+E0041, U+2028, CR LF and a tab | The one line `note: "a\u200Bb\u202Ec\uDB40\uDC41d\u2028e\u000D\u000Af\u0009g h"` on the web, the phone and Telegram | -- |
| Long value | A 5,000-character value | Web and phone: whole. Telegram: over 4,096 units, the head, a line break and "The inputs are too long to show here. See them on your OcuTalon page before you approve.", one message of at most `BUTTONLIMIT` (3,840) units, no buttons; 4,096 units or fewer: whole, split at `BUTTONLIMIT` with Approve and Reject on the last part (as today) | -- |
| Line-break value | A value holding a line break and `Approve:` | One line; the break shows as `\u000A` | -- |
| Unreadable arguments | ToolArguments not a JSON object (Raise refuses this, so only a hand-made row), or the redactor returns `UNCHECKED` | No notice; one warning naming the Ref | Fail closed |
| Cancel, server removed | Pending MCP row; `Approval.Cancel` after its server row is gone | Kind answered, `answered.canceled` `{time, server}`, ApprovalRef set. The phone answer line and Telegram message are edited and their buttons removed (a cut Telegram request too). The approval event has `state` cancelled, `server` and `cancelledAt`. The card shows "Canceled at HH:MM: the MCP server zzS was removed. Nothing was changed." The rail row leaves | Send failure: one warning |
| Cancel, other | Server still registered (a session end), a non-MCP tool call, or any fix | No notice; payload without `cancelledAt`; card shows no status (as today) | -- |
| Press after cancel | Web, phone or Telegram | 404 "That request is no longer available."; Telegram `press.unavailable`; nothing runs (existing) | -- |
| Changed result (DW-1232) | `approval.result` with Result `changed` | Web chat: a result card with the web render of `mcp.replayToolChanged` {tool, server}; phone and Telegram: a new message with its render (existing) | -- |
| Online demo | Any | Unchanged (no MCP row exists there) | -- |

</intent-contract>

## Code Map

**Existing (verified on this branch, OCT-epic21 HEAD e1eb0414, 2026-11-14; 22.4, 22.5, 22.6, 22.7, 21.4, 21.14 and 37.1 are merged):**
- `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - class doc :20-33 (tool-call notices; R1's `approval.result` bullet :30-32; `approval.cancelled: nothing` :33);
  - keys :86-104 (`KEYFAILEDWHY` :95, R1's `KEYCHANGED` :98, `KEYEXPIRED` :104); `INPUTSMAX` :107 (doc :106, the 200-character cut);
  - `OnEvent` :110-132; `IsApproval` :142;
  - `Approved` :148-167, the payload per recipient;
  - `ToolNotice` :210-228 and `Replayable` :231-234;
  - `ToolNoticeOf` :237-259: raised :239-245, answered :246-250, expired :251, R1's result branch :252-257;
  - `Compose` :263-273;
  - `ServerOf` :277-287 (private);
  - `InputsOf` :291-307 (doc :289-290; redacts the whole text, folds controls to spaces, cuts at :305);
  - `HeldNotice` :319-354, which sets `payload.Reason` :348 (the precedent for a sink-set payload member);
  - `Notice` :437 is the test seam.
- `Msg/Catalog/Core.cls`: `toolCall.request` :594-601 and `toolCall.requestOnServer` :602-610 (texts with "Inputs: {inputs}", `inputs` type `text`), and `answered.canceled` :811-818 (accepted, Story 35.2; used by no product code). `mcp.replayToolChanged` is in `Msg/Catalog/Watch.cls` :1068-1075 (Lane A, read only).
- `Msg/Catalog.cls`: the slot types in the doc :7-20 and the string-slot rule :21-26; `GROUPLINE` :48; the dispatch `SlotText` :153-196 (`groups` :194); `Groups` :213; `Clean` :276 (folds and strips, the opposite of V10, so `inputs` never calls it).
- `Live/Payload/Approval.cls`: properties :6-58 (no `server`); `FromRow` :71; its doc :60-70 says "The reason has no source in the row".
- `Channel/WebChat/Out.cls`:
  - class doc :26-32 ("one of Core.BridgeSink's five tool-call keys");
  - `ToolCallCard` :109-115 (doc :106-108): the five `KEY*` of the sink by `$Parameter`, no `KEYCHANGED` (DW-1232);
  - kind answered gives a Delivery row only.
- `Channel/SimPhone/Out.cls` doc :5-20 (`CARDKINDS` :41 holds result, so `mcp.replayToolChanged` already renders) and `Channel/Telegram/Out.cls` (`KINDS` :103 holds result, so it already renders too):
  - a kind answered edits in place and removes the buttons, for any key (doc :48-55; `EditAnswered` :283; pinned by `Test.Channel.TelegramOut` `TestEditApproved` :946 / `TestEditOnce` :1010);
  - Telegram's buttons bullet doc :41-47; `BUTTONKINDS` :106; `BUTTONLIMIT` 3840 :120; `OnNotification` :184-210 (render :197, keyboard :202-204); `Deliver` :255-266 (keeps the text only when there is a keyboard, :259-263); `Send` :452-470. `Channel/Telegram/Api.cls` `LIMIT` 4096 :28, `Split` :129.
- Answering a cancelled request:
  - `Bridge/Approval.cls` `AnswerLocked` :364 gives `not_found` for a cancelled row (:369);
  - `Core/AnswersIn.cls` :143;
  - `Web/Api.cls` `AnswerApproval` :770 / `AnswerResponse` :811 give 404 (`ReportHttpStatusCode` :455).
- `Bridge/Approval.cls` `Cancel` :448-457 (doc :440-447) stores no time and no reason; `CancelPending` :463 (22.4); `Move` :517 fires `approval.cancelled` after the unlock (read only).
- `Mcp/Ops.cls` (`src/ocutalon/cls/OcuTalon/Mcp/`, Lane A, read only): `Unregister` calls `CancelPending` :327, :338-342 after the removal commits. `Mcp/Server.cls` `NameIndex` :32 gives `NameIndexExists`.
- `Core/SessionOps.cls` `EndApprovals` :359 (a session end cancels too).
- `Bridge/Redact.cls` `Text` :45 (key rules need the whole object, doc :4-11; `UNCHECKED` on failure).
- Web:
  - `web/src/app/chat/chat-panel.ts` :178 draws a live tool-call request as `app-approval-request-card` with the notice text (`chat-view.ts` `liveRequest` :287);
  - `web/src/app/approvals/approval-view.ts`: `AnswerStatus` :95-99; `statusOf` :374-389 (no cancelled case); `approvalView` :393 (the first line names the buttons);
  - `approval-request-card.ts`: `.action` :291-298 is `white-space: pre-line` :294 (it collapses runs of spaces); the template `.action` :115; the tones :433-434;
  - `web/src/app/rail/rail-view.ts`: `RAIL_TEXTS.runTool` :49, `approvalTitle` :186-209, `approvalRow` :225 (no jump without an incident), `pendingApprovals` :340;
  - `web/scripts/catalog.mjs`: `LISTED_KEYS` :66 (the nine `answered.*` :89-97) and `TEXT_SLOT_KEYS` :131. It generates `web/src/app/msg/catalog.ts`;
  - `web/scripts/payloads.mjs` generates `web/src/app/live/payloads.ts` (`ApprovalPayload` :235).
  - `web/scripts/initial-bundle.test.mjs` `MAX_INITIAL_BYTES` 921,000 :20 (878.98 kB measured after 36.5).
- Docs and their pins:
  - `docs/security-overview.md`: "## Approval and audit" :125, its paragraph :127 ("Every built-in tool is safe except `send_email`, ..." to the end of the line); the tool-call bullet :138 (D1); the trace email line :170 (22.7); "## MCP tools" :207, the gate bullet :221 (D2 / 22.6's P2). All outside the generated markers (:5-108).
  - `docs/mcp-jira-example.md` :46, step 3's approval sentence (D3). It holds no "200 characters" today.
  - `docker/tests/test-readme.sh` rule `docs`: `L111` :1680 (= overview :138), `L187` :1681 (= :221), `L2115` :1683 (= :170, the 22.7 line), `chk_docs` :1685-1706 (:1692-1693, :1698, :1703), `rule_docs` controls :3216-3236 (the 200-character control :3223; the 22.7 line's control :3230).
  - `docker/tests/test-release-sequence.sh` rule `overviewdoc`: `mcp_doc_problems` :2331-2360 (the worked example), its controls :2480-2505, `t_overviewdoc` :2378.
- Tests that pin today's shape (shared surfaces):
  - `Test/Core/BridgeSink.cls`: `TestToolCallNoticeKinds` :816, `TestToolCallServerForm` :866, `TestToolCallInputsLine` :884 (the cut, :881-901), `TestToolCallNoticesOnlyForReplayableSessionRows` :938; class doc :38; probe `Test/Core/BridgeSinkNoticeProbe.cls` (`Notice` :15, `Visitors` :30);
  - `Test/Core/ToolCallNotices.cls` (live; header :1-19; `TestChangedResultSendsANotice` :134);
  - `Test/Core/WebChatOut.cls` :206-220 (the card cases), :248;
  - `Test/Demo/SimPhoneOut.cls` :704, :796 (an `inputs` string slot);
  - `Test/Msg/Catalog.cls` key list :1139-1140, fixtures :1610-1611;
  - `Test/Live/Payloads.cls`;
  - `Test/Channel/TelegramOut.cls` (Lane A): `TestButtons` :814, `TestEditApproved` :946;
  - `web/scripts/approval-view.test.mjs` :339, `chat-announcements.test.mjs` :392, `chat-view.test.mjs` :113-118, `rail-view.test.mjs`, `catalog.test.mjs`, `playwright-projects.test.mjs` :340 ("X1 to X13");
  - `web/e2e/answers/answers.spec.ts`: X6 :476-543, X12 :820-893 (its text :825), X13 :894+ (asserts the 200-character cut :922-924, doc :888); helpers `seedApproval`, `sinkEvent`, `irisScript` (`../support/iris`), `phoneMessage` (`../support/devices`), `setApprovalFields` :783;
  - `web/e2e/rail/rail.spec.ts` R3 :165-175;
  - `docker/tests/test-answers.sh` header :4-8.
- **From Story 22.4 (merged, 3d94a219):** `Approval.CancelPending`; `McpOps` calls it after a removal commits; `ApprovalRequest.ToolFingerprint`; `FinishExecution` `changed`. Its R1 regions in `BridgeSink`: the doc :30-32, `KEYCHANGED` :97-98, the result branch :252-257.

## Tasks & Acceptance

**Execution:**
- [ ] **Task 0** (implement, before code; source reads only; record the results under Design Notes "Read at implement"):
  - (a) 22.4 is merged (settled at this refresh: `CancelPending` `Bridge/Approval.cls`:463, `Mcp/Ops.cls`:327, R1 in `BridgeSink`). Re-confirm with one grep; if it is gone, stop with `## Clarification Needed` (C1).
  - (b) R1's regions sit at the lines above; edit around them (never inside).
  - (c) T1, T2, `toolCall.requestOnServer` (ruling E), V9, D1, D2, D3 and DW-1314 are ruled; nothing waits.
  - (d) 22.6 is merged (f138fcf8): D2 replaces 22.6's P2 bullet at :221, and D3 edits its example :46. 37.1 is merged (f29de0e7) and touched no Telegram file, so V8 needs no integrate-forward.
  - (e) If `docs/mcp-jira-example.md`:46, the overview :127, :138 or :221, or `test-readme.sh` :1680-1681 no longer read as quoted here, STOP: a ruled text moved.
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog.cls`:
  - new slot type `inputs`, after `groups`, built the same way: the value is an array of `{name, value}` strings; each member is one line, `INPUTLINE` `"{name}: {value}"`; an empty array is the line `{}`; a member that is not such an object is an error naming the key and the slot;
  - name and value are NOT cleaned: each goes through a new public `Visible(text)` (V10 definition) and nothing else, so spaces stay;
  - update the class doc's type list and its string-slot paragraph (the `inputs` exception).
- [ ] `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`:
  - `toolCall.request` and `toolCall.requestOnServer`: the T1/T2 texts (Public text); `inputs` becomes type `inputs`; update `source`;
  - new `toolCall.inputsTooLong`, no slots, text V9 word for word, `source` "EXPERIENCE Message Catalog / Tool calls / Telegram, inputs too long".
- [ ] `src/ocutalon/cls/OcuTalon/Core/BridgeSink.cls`:
  - `InputsOf` becomes public and gives the `%DynamicArray`: `Bridge.Redact.Text` of the WHOLE `ToolArguments` first; `UNCHECKED` or a result that is not a JSON object is unreadable (a warning naming the Ref, no notice); then per top-level member, in order, `{name, value}` where value is the member's `%ToJSON` text (a scalar's JSON text for a scalar) with JSON's short escapes normalized (`\b \f \n \r \t` become `\u0008 \u000C \u000A \u000D \u0009`, and every `\uXXXX` gets upper-case hex; `\"`, `\\`, `\/` stay). Remove `INPUTSMAX` and the cut. Empty arguments give an empty array.
  - New private `CanceledServer(row)`: `ServerOf(row.ToolSource)` when the row is `Replayable` and the private seam `Registered(server)` (`##class(OcuTalon.Mcp.Server).NameIndexExists`) is 0; else "".
  - `OnEvent` takes the time once for `approval.cancelled` (`Bridge.Time.NowUtc()`) and passes it to `Approved` and `ToolNotice`.
  - `Approved` sets `payload.CancelledAt` for that event when `CanceledServer` is not empty.
  - `ToolNoticeOf` gets an `approval.cancelled` branch beside the expired one: kind answered, new `KEYCANCELED` `answered.canceled` `{time, server}`, through `Compose`.
  - `ServerOf` becomes public (the payload calls it; no third parser of the attach form).
  - Update the class doc :20-33 (not R1's :30-32).
- [ ] `src/ocutalon/cls/OcuTalon/Live/Payload/Approval.cls`:
  - `Server` (`server`, MAXLEN 512, as `ToolSource`, since a bare `mcp:` form gives back its whole rest): set by `FromRow` from `Core.BridgeSink.ServerOf(row.ToolSource)` for a `tool_call` row.
  - `CancelledAt` (`cancelledAt`, MAXLEN 20): set only by the sink.
  - Update the doc.
- [ ] `src/ocutalon/cls/OcuTalon/Channel/WebChat/Out.cls` (DW-1232): `ToolCallCard` adds `$Parameter("OcuTalon.Core.BridgeSink", "KEYCHANGED")` to its keys; the class doc and the method doc say six tool-call keys. Nothing else.
- [ ] `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls` (V8, Lane A grant; the only Lane A product edit):
  - two parameters: `TOOLKEYS = "toolCall.request,toolCall.requestOnServer"` and `TOOLONGKEY = "toolCall.inputsTooLong"`;
  - the over-long branch, in `OnNotification` after the render: for kind approval with a `TOOLKEYS` key, when `$Length(text)` (UTF-16 units) is over `##class(OcuTalon.Channel.Telegram.Api).#LIMIT` (4,096):
    - the line = `Render(TOOLONGKEY, "", "telegram")`;
    - the head = the text up to its last line break at which the head, a line break and the line fit in `BUTTONLIMIT` units (so the answered edit still fits); with no such break, the first units that fit, never ending on a high surrogate;
    - send head, line break and line as one message with NO keyboard; `Deliver` still records the ApprovalRef and keeps the redacted text, so the answered and cancelled edits work as for a buttons message;
  - a request of 4,096 units or fewer, and every other kind, is unchanged;
  - the buttons bullet of the class doc gains one sentence for the branch.
- [ ] `web/scripts/catalog.mjs` -- `answered.canceled` joins `LISTED_KEYS` and `TEXT_SLOT_KEYS` (slot `server`). `toolCall.inputsTooLong` is Telegram only and is not listed. Then regenerate `src/app/msg/catalog.ts` (`node scripts/catalog.mjs`) and `src/app/live/payloads.ts` (`node scripts/payloads.mjs`). Update the generator's header list.
- [ ] `web/src/app/approvals/approval-view.ts` -- `statusOf` handles `cancelled` when `cancelledAt` and `server` are set: `answered.canceled` with `{time: timeBeside(cancelledAt), server}`, tone `rejected`, icon `circle-slash`. Otherwise it stays undefined. Update the header doc.
- [ ] `web/src/app/approvals/approval-request-card.ts` -- a card drawn from a request text (a tool call) shows its action with `white-space: pre-wrap`, so a value's spaces stay (Decided 10); every other card keeps `pre-line`.
- [ ] `web/src/app/rail/rail-view.ts` -- `RAIL_TEXTS.runToolOn` `'Run {toolName} on {server}'`. `approvalTitle` uses it for a `tool_call` with a `server`. Update the doc.
- [ ] **Tests (ObjectScript):**
  - `Test/Core/BridgeSink.cls`, with `BridgeSinkNoticeProbe.cls`, which also overrides the `Registered` seam:
    - update `TestToolCallNoticeKinds`/`ServerForm`/`InputsLine` to the array; the class doc :38;
    - add rows for no inputs, the long value (whole), the line-break value, a secret by key (`api_key` masked), unreadable arguments, the redactor's `UNCHECKED`, cancel with the server gone (`Registered` seam 0), cancel with it registered, cancel of a non-MCP row, and the payload's `cancelledAt` and `server`;
    - **new `TestToolCallInputsVisible` (V10's one test):** one fixture row whose ToolArguments hold ONE input `note` = `"a"_$Char(8203)_"b"_$Char(8238)_"c"_$Char(56128,56385)_"d"_$Char(8232)_"e"_$Char(13,10)_"f"_$Char(9)_"g h"` (built with `%DynamicObject`, never pasted). The probe catches the notice; then `Msg.Catalog.Render(key, slots, "web")` (what `WebChatOut` shows) and `Render(key, slots, "telegram")` (what `TelegramOut` sends, `Out.cls`:197) each hold the exact line `note: "a\u200Bb\u202Ec\uDB40\uDC41d\u2028e\u000D\u000Af\u0009g h"` once, and neither holds any character of the V10 set.
  - `Test/Msg/Catalog.cls`: the `inputs` type (lines, empty, bad member, a name with a V10 character, spaces kept), `Visible` over each class edge (U+0000, U+001F, U+007F, U+009F, U+00AD, U+061C, U+200B-U+200F, U+202A-U+202E, U+2060, U+2066-U+2069, U+FEFF, U+2028, U+2029, the TAG pair, a lone surrogate) and over a plain space, a no-break space and an emoji (unchanged); the new texts for web, phone and telegram; `toolCall.inputsTooLong` in the key list and the fixtures.
  - `Test/Live/Payloads.cls`: `server` for the attach form, the bare form and a class source.
  - `Test/Core/WebChatOut.cls` and `Test/Demo/SimPhoneOut.cls`: fixtures to the array slot. `WebChatOut` adds a card case for kind result `mcp.replayToolChanged` {tool, server} with an ApprovalRef (DW-1232).
  - `Test/Channel/TelegramOut.cls` (V8: exactly three tests, nothing else):
    - `TestToolCallTooLong`: a `toolCall.requestOnServer` approval whose render is over 4,096 units: one sendMessage with no `reply_markup`, text = the head (it starts with "Run zz_t on zzS") + line break + the V9 line, at most `BUTTONLIMIT` units; the Delivery row has the ApprovalRef and the text; then an `answered.canceled` notification edits it in place (stored text, a blank line, the status) with no keyboard;
    - `TestToolCallFits`: a request of exactly 4,096 units keeps Approve and Reject on its last part, and its sent text holds the V10 line (from an `inputs` slot whose value is built with `$Char`) exactly once;
    - `TestLongFixRequestUnchanged`: a kind incident request over 4,096 units still splits at `BUTTONLIMIT` with both buttons on the last part.
  - `Test/Core/ToolCallNotices.cls`:
    - the phone text with T1 and the labelled lines;
    - `TestChangedResultSendsANotice` also asserts the web row's text is the web render of `mcp.replayToolChanged` and that it is in `RecentNotices` (a card), and that the phone gets the phone render (DW-1232);
    - new `TestCancelledEditsInPlace`: a fixture MCP row whose server has no row, then `Approval.Cancel`. The phone answer becomes the phone render of `answered.canceled`, and no second message is added.
- [ ] **Tests (web):**
  - `web/scripts/approval-view.test.mjs` (cancelled with and without `cancelledAt`), `rail-view.test.mjs` (`runToolOn`), `catalog.test.mjs`, and the fixture strings in `chat-view.test.mjs`/`chat-announcements.test.mjs` (any raw V10 character only as a `\u` escape).
  - `web/e2e/answers/answers.spec.ts`:
    - **X12** and **X13** are updated to the new text. X13 asserts the long note whole, the "Why:" line, a value with two spaces shown with both, and the V10 line (the row seeded through `irisScript` with `$Char(...)` in its ObjectScript text; the expected line an ASCII literal), on the card and the phone; and that the rail row reads "Run zz_tool_x13 on zzx13" with no button. Its doc :888 loses the cut.
    - New **X14**: a pending MCP-form request shows its card, rail row and phone message. Then the case cancels it through `Approval.Cancel` (irisScript), and: within one live update the rail row is gone; the card shows the cancelled status with no buttons; the phone line is the canceled text with no buttons; a press through the answer route gets 404.
  - `web/scripts/playwright-projects.test.mjs` "X1 to X14", and the case list in the `docker/tests/test-answers.sh` header.
- [ ] **Docs (text only; ruled word for word; same commit as the cut's removal, DW-1266):**
  - `docs/security-overview.md` :138 becomes D1, :221 becomes D2 (this is also 22.6's P2 bullet; P2 repeats it nowhere else: `docs/mcp-jira-example.md` has no such bullet), and :127 from "Every built-in tool is safe except" to the end of that paragraph becomes the DW-1314 text.
  - `docs/mcp-jira-example.md` :46: the sentence `The chat shows an approval request that reads "Run add_comment on Jira", with its inputs and "No dry run is available for this tool. Approving runs exactly this call once."` becomes D3. The rest of :46 stays.
  - `docker/tests/test-readme.sh` rule `docs`:
    - `L111` := D1 and `L187` := D2 (:1680-1681);
    - the control "the approval section line without the 200 characters" (:3223) becomes "the approval section line without its Telegram sentence" (it deletes D1's last sentence -> red); a new control deletes D2's last sentence -> red;
    - DW-1315 (a): a new pin of the DW-1314 text, e.g. `APPROVAL_TAIL`: exactly one line of the overview ends with it, and that line is the first paragraph under "## Approval and audit". Two controls: "`send_email` and `call_mcp_tool`, which are classified per call" put back to "`send_email`, which code classifies per call" -> red; the last sentence ("A risky MCP call waits ...") deleted -> red;
    - DW-1315 (b): the 22.7 overview line ("No email's recipients are in the trace...", overview :170) is ALREADY pinned whole by `L2115` (:1683, check :1698) with the control "the email trace line changed" (:3230, which rewrites that sentence -> red). Keep it; run it as the evidence; add nothing (Decided 12);
    - the header comment of rule `docs` names Story 21.10's pins.
  - `docker/tests/test-release-sequence.sh` rule `overviewdoc`, `mcp_doc_problems` (D3's catalog check): the example holds the D3 sentence exactly once; and the catalog's `toolCall.requestOnServer` text, read from `src/ocutalon/cls/OcuTalon/Msg/Catalog/Core.cls`, has a first line that, with `{tool}` = `add_comment` and `{server}` = `Jira`, equals "Run add_comment on Jira", and a last line that equals "No dry run is available for this tool. Approving runs exactly this call once.". Two controls: the example's first quoted string changed -> red; a copy of the catalog with its last line changed -> red (the function takes the catalog path as an optional argument).
- [ ] **Docs and spine** (marker `[ADDED <the day the lead writes it>, Story 21.10]`): S1-S3 of Design Notes go into `_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md` (AD-31 :1240, AD-32). In `_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md`, Step 4's tool-call bullet :1146 and catalog rows with T1/T2 and the V9 line go in together with the catalog (DW-1045). All of it is ruled; the lead writes both in this story.

**Acceptance Criteria:**
- Given a pending `tool_call` request with an MCP server (a fixture row), when it shows in the web chat, then its card shows:
  - "Approval needed";
  - "Run {tool} on {server}";
  - "Why:" with T1;
  - "Inputs:" and the exact inputs as labelled lines, uncut, with their spaces;
  - "No dry run is available for this tool. Approving runs exactly this call once.";
  - Approve and Reject, named "Approve: run {tool} on {server}";
  - and the expiry.

  (X13, `Test.Core.BridgeSink`, `Test.Msg.Catalog`)
- Given the same request, when it shows on the phone and in Telegram, then each has the same text as plain text, with Approve and Reject (in Telegram, when it fits in one message; see the next AC). The rail row reads "Run {tool} on {server}" with its raised and expiry times and no answer button. The first answer wins everywhere (X12, X13, X6, `ToolCallNotices`; first answer: `Approval.AnswerLocked`, existing).
- [ ] (Planner condition V4, V8, V9) Given a tool-call request whose full Telegram text would exceed 4,096 characters, when TelegramOut renders it, then the message shows the head of the request, carries NO Approve button (and no Reject: the renderer offers the two only together), and ends with "The inputs are too long to show here. See them on your OcuTalon page before you approve."; the web card shows the full inputs; a test pins the over-long case on both channels (mutation: the length check removed -> red), and a request that fits keeps both buttons. (`TelegramOut` `TestToolCallTooLong`, `TestToolCallFits`, `TestLongFixRequestUnchanged`; X13 for the web)
- Given an input holding a zero-width space, U+202E, U+E0041, U+2028, CR LF and a tab, when the request shows, then the web and Telegram show the one line `note: "a\u200Bb\u202Ec\uDB40\uDC41d\u2028e\u000D\u000Af\u0009g h"` (V10; `Test.Core.BridgeSink` `TestToolCallInputsVisible`; `TelegramOut` `TestToolCallFits`; X13 in the browser).
- Given a pending MCP request that 22.4 cancels because its server was removed, when the cancellation arrives, then:
  - a press on any channel answers nothing;
  - the phone and Telegram messages are edited to "Canceled at {time}: the MCP server {server} was removed. Nothing was changed." with their buttons removed;
  - the rail row leaves within one live update;
  - and the card shows that status in place of its buttons.

  (X14, `ToolCallNotices` `TestCancelledEditsInPlace`, `Test.Core.BridgeSink`, R3)
- Given a cancellation that was not a server removal, when it arrives, then no notice is sent and no card claims a removed server (`Test.Core.BridgeSink`).
- Given an approved MCP call refused because its tool changed (22.4 R1), when its result arrives, then the web chat shows a card with the catalog's `mcp.replayToolChanged` text, and the phone and Telegram show the same text as today (DW-1232; `Test.Core.WebChatOut`, `ToolCallNotices` `TestChangedResultSendsANotice`; mutation: `KEYCHANGED` left out of `ToolCallCard` -> red).
- Given the guide, when this story lands, then `docs/security-overview.md` holds D1, D2 and the DW-1314 text, and `docs/mcp-jira-example.md` holds D3, each word for word; D3's two quoted strings equal the catalog's text; and each is pinned with a mutation that turns it red (`test-readme.sh docs`, `test-release-sequence.sh overviewdoc`; DW-1266, DW-1314, DW-1315).
- Given the online demo, when the demo path runs, then nothing changes (`live demo-path`, X1-X11 unchanged).

## Spec Change Log

- 2026-11-12 (lead, spec gate): Planner rulings E applied (split to 21.11 approved; V2-V7 approved; the V4 Telegram 4,096-character condition added as an AC with its approved line; T1, T2, toolCall.requestOnServer verbatim).
- 2026-11-14 (plan, spec refresh, final; redoes a lost refresh; rulings `epic-21-rulings-20261113-1800.md` "## 21.10", ~02:00Z, ~05:30Z, ~07:20Z, the ~22:00Z StepBuffer note): every Code Map and task line re-read on OCT-epic21 e1eb0414. Task 0 settled: 22.4, 22.6 and 37.1 are merged; C1 is met. Folded in as tasks, each with an AC and a pin: DW-1232 (the web card of `mcp.replayToolChanged`; the phone and Telegram already render it), V8 (the Telegram over-long branch, three Lane A tests), V9 (`toolCall.inputsTooLong`), V10 (the pinned escape definition and its one test), V11 D1/D2/D3 with DW-1266, DW-1314 and DW-1315. Corrections found at the refresh: per-value redaction would miss key rules, so the whole object is redacted first (Decided 9); `Clean` folds spaces, so the `inputs` type uses `Visible` only, and the card keeps spaces (Decided 10); the 22.7 line is already pinned (Decided 12). Verification moved to lane C's commands with the doc rules and the bundle test. No new public text.

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
- AD-29: lanes (the V8 grant is the one Lane A edit).

No AC contradicts an AD's Rule.

**V10 definition (ruled, pinned):** `Msg.Catalog.Visible(text)` writes each character of this set as `\` `u` and four upper-case hex digits, and every other character as it is:
- Cc: U+0000-U+001F (tab, LF, CR included) and U+007F-U+009F (U+0085 included);
- Zl U+2028 and Zp U+2029;
- Cf (Unicode 15.1): U+00AD, U+0600-U+0605, U+061C, U+06DD, U+070F, U+0890-U+0891, U+08E2, U+180E, U+200B-U+200F, U+202A-U+202E, U+2060-U+2064, U+2066-U+206F, U+FEFF, U+FFF9-U+FFFB, U+110BD, U+110CD, U+13430-U+1343F, U+1BCA0-U+1BCA3, U+1D173-U+1D17A, and the whole TAG block U+E0000-U+E007F (the ruling names the block);
- an astral character of the set (IRIS holds it as a surrogate pair) shows as its two halves: U+E0041 is the twelve ASCII characters `\uDB40\uDC41`;
- ordinary spaces (U+0020) stay. A no-break space or another Zs character is not in the set and stays.

The sink's JSON text holds `%ToJSON`'s short escapes, which the sink normalizes to the same `\uXXXX` form, so a CR LF shows as `\u000D\u000A` whether it arrived raw or escaped.

**Read for 21.10 (21.5's claims, checked on this branch):**
- Already met, confirmed:
  - The notices on the phone, Telegram and web chat: `ToolNoticeOf` :237-259, `WebChatOut.ToolCallCard` :109-115, and Telegram's buttons for kind approval.
  - First answer wins: `AnswerLocked` :364-369.
  - The cancelled row leaves the rail: `pendingApprovals` :340; R3 :165-175.
  - The card's label, buttons and expiry: `approvalView`, X13. The tool-call card is drawn from the notice's text (`chat-panel.ts` :178), not from the incident card.
  - A press on a cancelled request already answers nothing: `AnswerLocked` :369, `AnswersIn` :143, `Api` :770/:811.
- Gaps, confirmed:
  - no reason (no column, `FromRow`'s doc);
  - the one cut line (`InputsOf`, `INPUTSMAX` 200, X13);
  - no `server` member;
  - no cancelled notice (:33);
  - `answered.canceled` unused (grep: only the catalog);
  - no status for a cancelled card (`statusOf` default);
  - no web card for `mcp.replayToolChanged` (DW-1232; `ToolCallCard` lists five keys);
  - no notice or card for a fix with no incident (21.11).
- New, not in 21.5's list:
  - Cancel stores no time, so the sink stamps the time.
  - Session end also cancels requests (`SessionOps.EndApprovals` :359), so "the server was removed" must be checked, not assumed.
  - `rail-view.approvalTitle` would title an email fix "Repair and resend" (for 21.11).

**Split (approved, ruling E; written into `epics.md`):**
- **21.10 (this spec):** epics AC 1 (the tool-call card and its plain-text copies) and AC 3 (the cancelled request on every channel).
- **21.11: "Answer a standalone fix request on every channel".** Epics AC 2, verbatim. It runs after 22.7 (merged).
- **Read for 21.11:** `Replayable` :231 restricts notices to `tool_call`; `WebChatOut.ToolCallCard` :109-115 lists the keys; `approval-view.requestsOf` :208-213 needs an incident; `approvalTitle` falls to `RAIL_TEXTS.repair`; Telegram's approved alert has no text without a count (`Telegram/In.cls` :41); 21.6's accepted email texts can serve as result texts; 21.10's `answered`/cancel branches are reusable as they are.

**Decided in-stage (reversible inside this story):**
1. **The rail row (the AC's "same content as plain text").** The rail carries the request's action ("Run {tool} on {server}") with its raised and expiry times, as UX-DR52 defines a rail row. Approve and Reject are on the card, the phone and Telegram. X6's reason holds: a tool call has no incident, so its row has no control. X6 is not changed (V6).
2. **The reason is code-written** (T1). Every held call is held because its tool counts as risky (AD-10): no stored column, no classification read at notice time, no model text.
3. **Inputs are exact**: JSON text values, no cut. A call's arguments come from one model reply, which max_tokens 8,000 bounds (about 32,000 characters; inference). Telegram's limit is handled by V8.
4. **The cancel time** is the sink's clock when `approval.cancelled` arrives. It fires right after the commit in the cancelling job (inference: same job, after `Lock -`).
5. **"Server removed" is checked** (`Mcp.Server` has no row of that name), because a session end cancels requests too.
6. **The cancelled status** uses the rejected tone with `circle-slash` (nothing was changed). DESIGN has no cancelled tone.
7. **Unreadable arguments send no notice** (fail closed). An approver never sees a request whose exact call cannot be shown.
8. **The escape set is V10's ruled definition** (above). A lone surrogate half (category Cs, not named by the ruling) is also written as `\uXXXX`, because it cannot be shown; this adds visibility only (inference).
9. **Redact the whole object first.** `Bridge.Redact.Text` masks a value by its key (`api_key`, `authToken`, `chat.id`; `Redact.cls` doc :4-11), so redacting each value alone would show such a secret. `InputsOf` redacts `ToolArguments` whole, then splits it; `UNCHECKED` fails closed (Decided 7).
10. **Spaces stay on the web.** `Clean` collapses whitespace and the card's `.action` is `pre-line`, which collapses runs of spaces; the `inputs` type never cleans, and a request-text card uses `pre-wrap`. No collapsible block (the ruling allows one; the full text wraps).
11. **Telegram's boundary.** "Too long for one message" is over `Api.LIMIT` 4,096 units (the AC's number). A request of 3,841-4,096 units is shown whole in two parts with the buttons on the last, as every long buttons message is today. A cut request is one message of at most `BUTTONLIMIT` units, so its answered or cancelled edit fits. Reject goes too: the keyboard holds both buttons, and the ruling allows Reject only where the renderer offers it separately.
12. **DW-1315 (b) is met by the existing pin.** The 22.7 line at overview :170 is `L2115`, checked whole and once, with a control that rewrites "No email's recipients are in the trace." and must turn red. Adding a second pin of the same line would only duplicate it.
13. **V10's one test is `Test.Core.BridgeSink:TestToolCallInputsVisible`.** It starts from `ToolArguments` and runs the real sink and renderer for web and telegram (`TelegramOut` sends the telegram render as it is, plain text, :197). `TelegramOut` `TestToolCallFits` adds the sent-message check, and X13 the browser and the phone.

**Clarifications for the lead (non-blocking):**
- **C1 (order):** met at this refresh (22.4 merged, 3d94a219).
- **C2:** the split (V1) was approved.

**Contended files (Rule 11):**
- `src/bridge/cls/OcuTalon/Bridge/Adapter/StepBuffer.cls`: NOT touched. Both rules stay as they are on the branch: an MCP call's step shows server and tool only; a `send_email` step shows the name and the recipient count only (`StepBuffer.cls` :152-153, :172). A test that adds an MCP request does not change any step record.
- `web/src/app/rail/rail-view.ts` and the generated `web/src/app/live/payloads.ts`: 21.10 changes both; 21.5 is next on lane C and touches `rail-view.ts` (its rail line) and possibly `payloads.ts`. Whoever lands second integrates forward and regenerates `payloads.ts` from `payloads.mjs` (never a hand merge).
- `Channel/Telegram/Out.cls` and `Test/Channel/TelegramOut.cls`: Lane A, V8 grant only; 37.1 is merged and touched neither.
- `Core/BridgeSink.cls`: R1's regions (22.4, merged) are kept as they are.
- `docker/tests/test-readme.sh` rule `docs` (Epic 0's file; 21.14 and 22.6 edited the same rule): only `L111`, `L187`, the new pin and their controls.

**Bundle:** the binding initial target is 921 kB (`initial-bundle.test.mjs`; 878.98 kB measured after 36.5, about 42 kB of room under it, and 120 kB under the 1 MB `maximumError`). 21.10's web growth is small and sits where the code already is: the `statusOf` case, the rail title, one listed key in `catalog.ts`, one CSS rule; types add nothing (estimate under 1 kB, inference). No new dependency, route or chunk. `node --test web/scripts/` runs the budget.

**Online demo:** no behaviour changes.
- No MCP server can be registered there (22.2, 22.4), so no `tool_call` with a server exists, and no MCP cancel or changed result happens.
- A session end's cancellations fail the server check and send nothing new.
- Fix cards and UJ-1 are untouched: the incident card skips cancelled requests (`requestsOf`), the new status needs `cancelledAt`, and Telegram's branch needs a tool-call key.
- `live demo-path` and answers X1-X11 stay green.

**Ledger:**
- Inbox: none.
- DW-1232, DW-1266, DW-1314 (decision-pending, ruled ~07:20Z) and DW-1315 are routed to 21.10; the lead marks each resolved at merge, citing its pin.
- DW-592 (wontfix-accepted, U-254) stays closed: after a reload a cancelled card is a plain notice with no pending cue.
- DW-1045 does not reopen: the tool-call texts change in `Catalog.Core` and EXPERIENCE together (the docs task).
- DW-1288 (cancelled spelling, burndown) touches `answered.canceled`, which this story shows for the first time: veto item V12.

**Integration ACs (Rule 1):**
- The `inputs` slot type is consumed by the real `SimPhoneOut`, `TelegramOut` and `WebChatOut` through `Render` (`ToolCallNotices`, X12, X13, `TelegramOut`).
- `server`/`cancelledAt` are consumed by the real card and rail (X13, X14).
- `mcp.replayToolChanged` reaches the real web card (`ToolCallNotices` `TestChangedResultSendsANotice`).

**Consumes:**
- 22.4: `approval.cancelled` from `CancelPending`, MCP rows, R1's `changed`.
- 31.5/31.6: `ToolNoticeOf`, the card.
- 35.2: `answered.canceled`.
- 6.3: the in-place edits.
- 22.6: the worked example and P2.
- `Mcp.Server`.

**Consumed-by:**
- 21.11: the cancelled branch and the `answered` compose for a fix with no incident.
- 21.5: the rail title and the payload's `server`.

**Extend, don't copy (Rule 2):**
- `inputs` follows `Groups`/`GROUPLINE`.
- The cancelled notice is a `ToolNoticeOf` branch through `Compose`, beside the expired one.
- `CancelledAt` follows `HeldNotice`'s `payload.Reason`.
- `server` reuses `BridgeSink.ServerOf`; no new parser (22.4's routed LOW: `reopen_if` = a third parser).
- The status extends `statusOf`, and the rail title extends `approvalTitle`.
- The phone and Telegram edits are the existing ones; Telegram's cut message reuses `Deliver`'s kept text.
- `ToolCallCard` reads `KEYCHANGED` by `$Parameter`, as it reads the other five.

**Spine items (additive):**
- **S1, AD-31:** "(step 4's email fix, Story 22.7; this part built in Story 21.5)" becomes "...built in Story 21.11, split from Story 21.10".
- **S2, AD-31, after the tool-call notice sentence:** "On `approval.cancelled` of a replayable MCP `tool_call` whose server has no `Mcp.Server` row, it sends kind `answered`, `answered.canceled` {time, server}, and the approval event carries `server` and `cancelledAt`. Any other cancellation sends nothing [ADDED, Story 21.10]".
- **S3, AD-32 renderer:** "slot type `inputs`: an array of {name, value}, one line `{name}: {value}` each, `{}` for none; every Cc, Cf, Zl or Zp character and tab in it shows as `\uXXXX` [ADDED, Story 21.10]".

**Planner rulings at the spec gate (Contest Planner, owner's delegation, 2026-11-12 ~23:00Z, `prompts/gate-rulings-20261112-1810.md` E / 21.10; binding):** the split into new 21.11 (after 22.7) APPROVED (written into `epics.md`); V2, V3, V5, V6, V7 APPROVED. V4 (no 200-character cut; secrets masked by `Bridge.Redact`) APPROVED WITH A CONDITION for Telegram: if the full request does not fit in one Telegram message (4,096 characters), the Telegram card shows the head, gets NO Approve button, and says: "The inputs are too long to show here. See them on your OcuTalon page before you approve." The web card shows everything (collapsible is fine). Test the over-long case. PUBLIC TEXT: T1, T2 and `toolCall.requestOnServer` approved verbatim, plus that Telegram line. Order: implements after 22.4 merges (integrate forward first).

**Planner rulings after the gate (binding; `prompts/epic-21-rulings-20261113-1800.md`):**
- 21.10 V8 GRANTED (Lane A: `Channel/Telegram/Out.cls`, the two parameters and the over-long branch; `Test/Channel/TelegramOut.cls`, the three tests; nothing else; integrate forward over 37.1 if it lands first). V9 APPROVED (the key and text). V10 APPROVED with the definition above and its one test. V11: D1 approved with its changed last sentence; D2 approved; D3 approved after 22.6 merges, both quoted strings equal to the catalog, a mismatch is a STOP.
- ~02:00Z Nov 14: D2 keeps "an audit entry for each call it lets run" and "A call to a removed server's tool runs nothing and writes no audit entry."
- ~05:30Z Nov 14: D2's final text (one comma, one added sentence); test-readme L187 in the same commit; DW-1266: 21.10's commit switches :221, L187, 22.6's P2 and the worked example together.
- ~07:20Z Nov 14: DW-1314's paragraph text and DW-1315's pins land in 21.10's commit, text only.
- ~22:00Z cross-lane note: StepBuffer's two rules (see Contended files).

**Read at implement (Task 0):** (filled by the implement stage)

## Veto items

| # | Item | Recommended | Online demo |
| --- | --- | --- | --- |
| V1 | Split: epics AC 2 moves verbatim to new Story 21.11 (after 22.7) | approved (E) | -- |
| V2 | Changed public text: both `toolCall.request*` entries gain "Why:" (T1) and the labelled inputs (T2) | approved (E) | never shown (no tool calls) |
| V3 | Live `approval` payload gains `server` and `cancelledAt`. These are event members, not stored; every page gets them | approved (E) | always empty |
| V4 | The 200-character inputs cut is removed (31.5's INPUTSMAX): approvers see the exact call. Redaction is kept | approved with the Telegram condition (E) | -- |
| V5 | Lane B reads Lane A's `Mcp.Server` (`NameIndexExists`), read only, to keep `answered.canceled` true | approved (E) | no rows |
| V6 | The AC's rail reading (Decided 1): action and times, no answer buttons | approved (E) | unchanged |
| V7 | Order C1: implements after 22.4 merges | approved (E); met | -- |
| V8 | Lane A edit for the Telegram over-long branch | GRANTED (Nov 13) | never reached |
| V9 | `toolCall.inputsTooLong` text | APPROVED (Nov 13) | never shown |
| V10 | The invisible-character definition and its test | APPROVED (Nov 13) | -- |
| V11 | D1, D2, D3 guide texts | APPROVED (Nov 13, D2 final ~05:30Z Nov 14) | the guide states MCP is off there |
| V12 | **OPEN.** DW-1288 says public text should spell "cancelled". `answered.canceled` reads "Canceled at {time}: ..." (Story 35.2, accepted) and is first shown by this story. Taking DW-1288's one-word change here means the catalog text, EXPERIENCE :722 and :1034, the regenerated `catalog.ts` and the pins of every test that holds it | take it in 21.10 if ruled; with no ruling, ship 35.2's accepted text unchanged | never shown |

There is no new command, route, grant, role, privilege, table, column, retention or web dependency.

## Public text

**Reused (accepted):**
- "Approval needed", "Run {tool} on {server}", "No dry run is available for this tool. Approving runs exactly this call once.", Approve, Reject, and the expiry ("Expires {when}");
- `answered.canceled` "Canceled at {time}: the MCP server {server} was removed. Nothing was changed." (Story 35.2; on the page it keeps its period, as EXPERIENCE :722 says; spelling: V12);
- `mcp.replayToolChanged` "{tool} on {server} didn't run: the tool changed after this request was made, so it needs a new approval. Nothing was changed." (Story 22.4; now also on the web card);
- "That request is no longer available."; `press.unavailable`.

**Ruled (approved word for word; every channel; online demo: never shown):**
- **T1, the reason line** (both entries): "Why: {tool} counts as risky, so it runs only after an approval."
- **T2, the inputs block.** The line "Inputs:" (it was "Inputs: {inputs}"), then one line per input, "{name}: {value}", with the value as JSON (for example `id: "T-1"`, `n: 2`), and the line "{}" for a call with no inputs.
- **The full `toolCall.requestOnServer` text:** "Run {tool} on {server}\nWhy: {tool} counts as risky, so it runs only after an approval.\nInputs:\n{inputs}\nNo dry run is available for this tool. Approving runs exactly this call once." `toolCall.request` is the same text without " on {server}".
- **V9, `toolCall.inputsTooLong`** (Telegram only): "The inputs are too long to show here. See them on your OcuTalon page before you approve."
- **D1** (`docs/security-overview.md` :138): "- It is fixed to exact targets and shows its dry run (a fix), or the tool, its MCP server when it has one, and each of its inputs on a line of its own through the redactor, with the full call kept in the approval record (a tool call). In Telegram, an approval request for a tool call that is too long for one message shows only its start, with no Approve button."
- **D2** (`docs/security-overview.md` :221, 22.6's P2 bullet): "- Every call passes the gate, an approval request when needed (showing the tool, its server and each of its inputs on a line of its own, through the redactor, with the full call kept in the approval record), an audit entry for each call it lets run (read-only calls included) and an agent step. A call to a removed server's tool runs nothing and writes no audit entry. A request too long to show in full on Telegram has no Approve button there."
- **D3** (`docs/mcp-jira-example.md` :46, step 3): "The chat shows an approval request that reads "Run add_comment on Jira", says why it waits, lists each of its inputs on a line of its own and ends with "No dry run is available for this tool. Approving runs exactly this call once."" Checked at this refresh: both quoted strings equal the catalog today (`Msg/Catalog/Core.cls` :603, first line "Run {tool} on {server}" with `add_comment`/`Jira`, last line the no-dry-run sentence; there is no `web` variant), and T1/T2 keep both.
- **DW-1314** (`docs/security-overview.md` :127, from "Every built-in tool is safe except" to the end of the paragraph): "Every built-in tool is safe except `send_email` and `call_mcp_tool`, which are classified per call. Code classifies `send_email`: an email to the connected mailbox's own address is safe, and an email to anyone else is risky. `call_mcp_tool` takes the admin's classification of the server's tool at its current fingerprint, and an unclassified tool counts as risky. Each risky built-in action, such as repair and resend or an email to anyone else, is a fix kind that waits for a person's approval and shows first exactly what it will do. A risky MCP call waits for a person's approval of that exact call, as the MCP servers section below describes."

**New:** none.

**Findability:** no More to try item; MCP is off on the demo.

## Verification

Run every command from the worktree root, after `git rev-parse --show-toplevel` matches it. Lane C only.
- `<vars>` = `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=21 stage=<stage>'`.
- Tags: warm `e21s10iw` and fresh `e21s10i`; QA `e21s10qw`/`e21s10q`; review `e21s10rw`/`e21s10r`. The live units and `ToolCallNotices` (it changes the production) run only on lane-C fresh throwaways.
- One command per foreground call, with `timeout: 600000`, each sized to about 150 s (the harness backgrounds a call at about 170-180 s). One class per call; split a slow class with `class <Class>:<Method>`. If a call is backgrounded, wait in bounded foreground polls, never `Monitor`.
- Never two test runs in one message. One `iris_execute_tests` per message, with `server` and `namespace`. Never a slot, `ocutalon-aihub-test` or another lane's stack; tear down only this stage's tags.

**Shared surfaces:**
- the `toolCall.request*` texts and the `inputs` slot (`Test.Core.BridgeSink`, `Test.Core.WebChatOut`, `Test.Demo.SimPhoneOut`, `Test.Msg.Catalog`, `Test.Channel.TelegramOut`, the X12/X13 strings, the fixtures of `approval-view`/`chat-view`/`chat-announcements`);
- the `approval` payload (`payloads.ts`, `Test.Live.Payloads`);
- the page catalog's listed keys (`catalog.test.mjs`);
- the rail's tool-call title (`rail-view.test.mjs`, X6, R3);
- the answers project's case inventory (`playwright-projects.test.mjs`, `test-answers.sh`);
- the guide's ruled lines (`test-readme.sh docs`, `test-release-sequence.sh overviewdoc`).

Criterion: every test added or changed passes on a fresh environment, in either order.

**Commands:**
- (once) `<vars> OCUTALON_RUN_TAG=e21s10iw ci/warm.sh up` -- ready.
- (loop) `<vars> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e21s10iw ci/iris.sh class OcuTalon.Test.Core.BridgeSink` -- passed. Mutations:
  - `InputsOf` back to one line -> the inputs rows go red;
  - the cut kept -> the long-value row goes red;
  - each value redacted alone -> the secret-by-key row goes red;
  - no short-escape normalization -> `TestToolCallInputsVisible` red (`\r\n`, `\t`);
  - no cancelled branch -> the server-gone row goes red;
  - `CanceledServer` without the `Registered` check -> the still-registered row goes red;
  - `CancelledAt` never set -> the payload row goes red.
- (loop) `... class OcuTalon.Test.Msg.Catalog` -- passed. Mutations: no "Why:" line in `toolCall.requestOnServer` -> its fixture red; `INPUTLINE` without `{value}` -> red; `Visible` without the Cf ranges -> red; an astral character escaped as one unit -> red; `inputs` through `Clean` -> the spaces row red.
- (loop, one per call) `... class OcuTalon.Test.Live.Payloads`, `... OcuTalon.Test.Core.WebChatOut`, `... OcuTalon.Test.Demo.SimPhoneOut` -- passed. Mutations: `FromRow` without `Server` -> `Payloads` red; `KEYCHANGED` left out of `ToolCallCard` -> `WebChatOut` red.
- (loop) `... class OcuTalon.Test.Channel.TelegramOut` -- passed. Mutations: the length check removed -> `TestToolCallTooLong` red; `>=` for `>` -> `TestToolCallFits` red; the key filter removed -> `TestLongFixRequestUnchanged` red; the kept text dropped for the cut message -> the edit in `TestToolCallTooLong` red.
- (once) `... class OcuTalon.Test.Core.AnswersIn` -- passed (unchanged).
- (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh class OcuTalon.Test.Core.ToolCallNotices` (fresh throwaway) -- passed. Mutations: no cancelled branch -> `TestCancelledEditsInPlace` red; `KEYCHANGED` left out of `ToolCallCard` -> `TestChangedResultSendsANotice` red.
- (once) `cd web && node scripts/catalog.mjs --check && node scripts/payloads.mjs --check`, then (once) `node --test web/scripts/` (holds `initial-bundle.test.mjs`, the 921 kB budget) -- passed. Mutations: `statusOf` without the cancelled case -> `approval-view.test` red; `approvalTitle` ignoring `server` -> `rail-view.test` red.
- (once each) `cd web && npx tsc -p tsconfig.e2e.json --noEmit` and `cd web && npm run build` -- clean.
- (loop) `bash docker/tests/test-readme.sh docs` -- exit 0, every control red where it should be: D1's and D2's Telegram sentences deleted; the DW-1314 text's two mutations; "the email trace line changed" (DW-1315 b). Then (once) `bash docker/tests/test-readme.sh` -- exit 0.
- (loop) `bash docker/tests/test-release-sequence.sh overviewdoc` -- exit 0, with D3's two controls red (the example's quoted string changed; the catalog copy's last line changed). If the D3 check finds the catalog and the example apart, STOP (V11 D3).
- (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh build`, then (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh live answers` -- passed. **Browser:** Chromium, Playwright project `answers` (X1-X14, C1-C10); X13 checks the card, the phone and the rail in the page; X14 the cancel. It took 446 s in CI on x64 and cannot be split; expect the harness to background it, then poll. Mutation: no cancelled branch -> X14's phone and card lines red.
- (once) `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh live demo-path` -- passed. **Browser:** Chromium, the demo path (online-demo safety, UJ-1).
- (once each) `bash docker/tests/test-class-rules.sh`, `bash docker/tests/test-boundaries.sh` -- pass (the boundaries check sees the V8 files; cite the grant if it flags them).
- (once each, also after a failure) `<vars> OCUTALON_RUN_TAG=e21s10iw ci/warm.sh down` and `<vars> OCUTALON_RUN_TAG=e21s10i ci/iris.sh teardown`.
- (once, after S1-S3) `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` -- no finding beyond the baseline.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none
