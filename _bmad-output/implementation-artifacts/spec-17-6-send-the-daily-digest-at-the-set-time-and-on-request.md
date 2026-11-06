---
title: 'Story 17.6: Send the daily digest at the set time and on request'
type: 'feature'
created: '2026-11-06'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Digest.Process` is a stub (`STUB` = 1, answers 5003) and the `Digest` item is disabled, so no digest is ever sent. A `SendDigest` from Settings answers `failed` (DW-696). Nothing reaches `Digest` on a tick. `TelegramOut` drops kinds `digest` and `handled`. Telegram tell-now messages have no **Got it** button. `digest.cost` is missing from the catalog (DW-661).

**Approach:**
- `Checks` forwards each `Tick` to `Digest` (pending Q1).
- On a tick, `Digest` applies AD-18's amended due rule (DW-651) under a per-session lock.
- On `SendDigest`, `Digest` accepts at once and composes asynchronously (Q5).
- Each digest is composed from `Coverage.Build`, `Checks.Render`, the needs-you sources (Q4), `Digest.Data.Item.Since` (with at most one `Decide` turn) and yesterday's `Usage` cost.
- It writes one `Sent` row and sends one `Notification` of kind `digest` to `Notify`.
- A chat tool `send_digest` submits `SendDigest`.
- `TelegramOut` renders a digest as one plain-text message, adds **Got it** to tell-now messages, and edits its copy on a `handled` notification. `TelegramIn` submits `GotIt` for a press from the paired chat.

## Boundaries & Constraints

**Always:**
- **Due rule (AD-18 as amended, DW-651).** On a tick at `tickAt`:
  - `due` is the latest instant at or before `tickAt` whose instance-zone clock reads `digest.time`. It is computed only through `OcuTalon.Data.Time` (`ToLocal`, `FromLocal`). `digest.time` is read through `Data.Setting.Get("digest.time", "08:00")`; an unreadable value means `08:00`.
  - A session that has not ended is due when all three hold:
    - `due` > its `CreatedAt`;
    - it has no `Sent` row with `Kind` `scheduled` and `DueAt` >= `due`;
    - the check gives the same answer again under `Lock +^OcuTalon.Digest.Due(sessionRef):5`. The digest is composed and recorded inside that lock.
  - A scheduled row stores `DueAt` = `due`. A requested row stores `DueAt` "" (DW-649), and the due lookup filters on `Kind = 'scheduled'`.
  - So a digest missed while IRIS was down goes once (only the latest `due` counts), and never twice.
- **Ended (decided in-stage).**
  - On the online demo (`onlineDemo` = 1), a session has ended when its `ResumeHash` is empty.
  - On a local install no session ends, so every `Session` row counts.
- **Window.** It starts at the session's newest `Sent.SentAt` of either kind, or 24 hours before now for its first digest. It ends now. Either kind of digest starts the next window.
- **Composition**: one `Notification`, `Kind` `digest`, `SessionRef`.
  - `CatalogKey` = `Checks.Render` over the non-vital rows when the session watches anything, and over `[]` when it watches nothing (AD-28).
  - `DecisionRef` = the model request's, or "".
  - `Slots` = `{"parts", "lines", "rows"}` (AD-32). `parts` holds these, in this order:
    1. greeting by the compose hour in the instance zone (`digest.greetingMorning` 00-11, `Afternoon` 12-17, `Evening` 18-23);
    2. `digest.healthy` when all five vital rows passed (`count` = upDays, `itemNoun` `{"one":"day","other":"days"}`, `databasesFull`, `licenseUse`), else `digest.vitalsNotAll` (`whatFailed` = the entries of the vital rows that did not pass);
    3. either `digest.checkedQuiet` (every non-vital row passed) or `digest.checked`, followed by `Render`'s key with `{}`. When nothing is watched, this part is `digest.nothingWatched` alone;
    4. needs you (Q4): `digest.needsYouOne` or `digest.needsYou`, or no part when nothing needs the user;
    5. saved for later: `digest.savedNone`, `digest.saved` `{count, summary}`, or `digest.savedNoSummary` `{count, fallbackReason}`;
    6. `digest.cost` `{cost}`, yesterday's cost.
  - `lines` and `rows` are `Coverage.Build`'s, unchanged.
- **The model request (AD-30)** is made at most once per digest, and only when `Item.Since(sessionRef, windowStart)` is not empty.
  - It is an `OcuTalon.Bridge.Msg.Request` with `Kind` `turn`, `Provenance` `untrusted` and `SessionMode` `fresh`. It has no `SeedText`.
  - `OwnerRef` is the session, `ItemId` is a new `Bridge.Ids.NewRef()`, and `Channel` is `system`.
  - `Input` is `Agent.Input.Render` of an `OcuTalon.Msg.Item` with channel `system`, subject "Saved for later", and text one stored `Summary` per line.
  - The reply text, already filtered by Decide's guard, is cut by code to 240 characters.
  - Any `Fallback`, error, timeout or empty text gives `digest.savedNoSummary` with the reason (an unknown reason gives `unusable`). The fallback is logged with one `$$$LOGINFO` line in the Digest session, and the Decision row carries it (Visual Trace).
- **Cost.** The sum of `Bridge.Data.Usage.CostUSD` where `OwnerRef` is the session or `instance` (never `eval`) and `RecordedAt` is in [yesterday 00:00, today 00:00) in the instance zone, both converted through `Data.Time.FromLocal`. It is passed as a number to slot type `dailyCost`.
- **Record.** One `Sent` row per digest sent (`Ref` = `NewRef()`, every AD-18 field), written after the `Notification` is sent. `AllClear` = 1 only when `CatalogKey` = `checks.allPassed`.
- **SendDigest (U-268).**
  - It is taken from CommandsIn (origins `tool`, `web_admin`) and takes no recipient.
  - Destinations come only from `Notify` and `digest.channels`. Nothing in `Digest` reads a destination from the command, the model or an item.
  - A repeat of a non-empty `IdempotencyKey` for the session sends no second digest (Q5).
  - The answer is `CommandResult` `ok` once the compose is queued, never `failed` (DW-696).
- **The digest tool `send_digest`** is a safe action (classification `safe`, not read-only).
  - It submits `SendDigest` through `Tools.CommandCall.Run` (origin `tool`, key `ItemId:position`).
  - It takes no input and returns `CommandCall.Answer(result)`.
  - Its name goes in `Tools.Names` (one-name append, not in `RELEASE1`), and a mock scenario calls it.
- **Telegram.**
  - **Digest.** `TelegramOut` renders a digest as one plain-text message (`Catalog.Render(..., "telegram")` for every `{key, slots}`, and nothing else). The order is: greeting, vitals, the checked part and its reserved sentence, one coverage line per row, needs you, saved for later, cost. Each piece goes on its own line, with no Markdown. It records a `Delivery` row.
  - **Tell-now.** A `tellnow` message with a `DecisionRef` gets one inline button `button.gotIt`, with `callback_data` `gotit:<DecisionRef>` (22 random base64url characters, `Bridge.Ids`).
  - **A press.** `TelegramIn` submits `OcuTalon.Msg.Command.GotIt` (`Ref`, `Channel` `telegram`, the session) through `Core.Commands.Submit(..., "telegram")` only when all of these hold:
    - the chat is paired (`Pairing.Chat`);
    - the session's `Delivery` row for that Ref (`Ownership.DeliveryByRef(ref, "telegram", session)`) exists;
    - that row's chat is the pressing chat.

    It answers the callback with no text. Any other press submits nothing.
  - **Handled.** On a `handled` Notification, `TelegramOut` edits its copy in place (`Delivery.FindByRef`) to the kept text plus a blank line and `handled.marked` `{time}`, with no `reply_markup`, so the button is removed.
- **Source rules.** ASCII source and contract-only comments (Rule 14). Storage is append-only (AD-5).

**Never:**
- An edit to an existing contended file beyond the precedent or the rulings: `Checks/{Beat,Process}.cls` (Q1), `Test/Checks/**`, `Test/Tools/**`, `Test/Install/**` (Q3, Q6), `Core/**`, `Data/Ownership.cls`, `Msg/Enum.cls`, `docs/**` (Q6), `ci/units.sh`, `src/short-names.tsv`, the spine.
- An edit to a Lane B class or test (U-177) beyond the one-time exception: `Test/Msg/Catalog.cls` for `digest.cost` (and Q2's keys if ruled).
- A recipient, channel or address on `SendDigest` or the tool, or a `Digest` code path that picks a destination.
- Composing synchronously inside `SendDigest`'s CommandsIn call (Q5, a deadlock on the one-job `ChatAgent`).
- The all-clear rules' own tests, the evaluation cases, the guard's banned-phrase test (Story 17.7), the web and phone digest copies, the Got it writer, `Notify`'s `digest.channels` routing (Lane B, Stories 18.2 and 18.4).
- `Bridge.Time` in `Digest` (only `Data.Time`; AD-18). No `temperature`, `top_p` or `top_k`.
- User-facing text beyond the proposed list under Design Notes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Created before (DW-651) | `digest.time` 08:00, session created 07:30 today, tick 08:01 | one scheduled digest, `DueAt` today 08:00; a second tick sends none | none |
| Created after (DW-651) | created 08:30 today, ticks 08:31 to 23:59 | none today; one at the tomorrow-08:00 tick | none |
| Restart catch-up | no ticks 07:00 to 10:00 for two days, then a tick at 10:00 | one digest (`DueAt` the latest 08:00), never repeated | none |
| Requested (DW-649) | `SendDigest` web_admin at 07:00, tick 08:01 | two digests; requested `DueAt` ""; the scheduled one still goes; its window starts at the requested `SentAt` | none |
| Repeat key | the same tool `IdempotencyKey` twice | one digest, both answers `ok` | none |
| Disabled item fixed (DW-696) | real production, `SendDigest` web_admin | `ok`, then one `Notification` kind `digest` at `Notify` | never `failed` or `not_built` |
| Saved, summary | 3 items saved in the window, mock text of 300 characters | `digest.saved` `{count: 3, summary: <first 240>}`; one Decide request | none |
| Saved, fallback | mock `provider-error` | `digest.savedNoSummary` `{3, fallbackReason}`; the digest still goes; one `LOGINFO` line | none |
| Nothing saved | no item | `digest.savedNone`; no Decide request (mock log) | none |
| Cost | Usage today 0.5 (session), yesterday 0.012 (session) + 0.03 (instance) + 9 (eval) + 1 (other session) | `{cost: 0.042}` rendered "Yesterday's cost: $0.04." | none |
| Quiet day | everything passed, nothing needs the user | rendered Telegram text <= 150 words | none |
| Telegram digest | fixture digest notification to `TelegramOut` | one `sendMessage`, no `parse_mode`, lines "Passed:", "Failed:", "Not checked:", cost `$0.04` | render error: nothing sent |
| Got it, paired chat | tell-now message with **Got it**; press from that chat | one `GotIt` submitted, origin `telegram`, Ref = the `DecisionRef` | none |
| Got it, other chat | the same `callback_data` pressed in another chat | nothing submitted | none |
| Handled | fixture `handled` notification | the message is edited to "...\n\nMarked as handled at {time}" with no button | no row: one warning |
| Tool | chat marker scenario calling `send_digest` | `SendDigest` with origin `tool` and key `ItemId:1`; the digest goes | none |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/`; the bridge is under `src/bridge/cls/OcuTalon/Bridge/`.

- `Digest/Process.cls`: the stub. Its doc comment states the old due rule; replace it.
  - Siblings: `Core/Intake.cls` `RequestFor` :151-164 and the untrusted `turn` on act :185-187; `Send` :250 (async, answer in `OnResponse` :108).
  - Read a Reply as `Core/Conversation.cls` `Replied` :445-459 does. The fallback reasons are in `Bridge/Msg/Enum.cls` :15.
- `Bridge/Msg/Request.cls` (Kind, Provenance, Input, ItemId, Summary, OwnerRef, TraceRef, Channel, ThreadSessionId, SessionMode, SeedText, SystemNote) and `Bridge/Msg/Reply.cls` (Text, Fallback, FallbackReason, DecisionRef).
  - `Decide` routes `turn` to `ChatAgent` (`Bridge/Process/Decide.cls` :140), and the guard already runs there (`Production.cls` :22).
  - Any provenance other than `user` limits the turn to safe read-only tools (`Bridge/Policy/Gate.cls` :142).
- `Agent/Input.cls` `Render(item, now)` :15. `Msg/Item.cls` :6-27. `Bridge/Ids.cls` `NewRef()` :7.
- `Checks/Coverage.cls` `Build(sessionRef, fromUtc, toUtc, *rows, *lines, *vitals)` :125 and `Thresholds()` :111. `Checks/Render.cls` `Render(results, *rows) As %String` :36 (keys :18-27).
- `Digest/Data/Sent.cls` (all AD-18 fields; `SessionRefDueAtIndex` has no Kind, so filter on Kind; DW-649). `Digest/Data/Item.cls` `Since` :38.
- `Data/Time.cls`: `NowUtc` :18, `Seconds` :27, `AddSeconds` :42, `ToLocal` :54, `FromLocal` :68 (fold 0, skipped hour +1 h).
- `Data/Session.cls`: `Ref`, `CreatedAt` :35, `ResumeHash`. There is no end marker; `SessionOps.End` clears `ResumeHash`.
- `Data/Setting.cls`: `Get` :39 (instance-wide, 60 s cache), `Seed` :57.
- `Core/SettingsOps.cls` (Lane B, read only): `digest.time` "08:00" :192 and `digest.channels` "web,phone,telegram" :193.
- `Install/Step/Digest.cls` `Run()` :10 (one `Install.Seeds.Defaults` call). `Install/Seeds.cls` :9.
- `Bridge/Data/Usage.cls`: `OwnerRef` :31, `CostUSD` :55, `RecordedAt` :61. `Ownership.RunCost` :97 has only a lower bound and no `instance`, so it is not reused. Lane A reads bridge rows directly, as `Checks.Process.Fixes` does.
- `Msg/Catalog/Watch.cls`: `button.approve` :313, `button.reject` :318, and the `digest.*` keys :323-484. Add `digest.cost` (and Q2's keys) here. The `dailyCost` slot is `Msg/Catalog.cls` :17, `DailyCost` :242.
- `Data/Handled.cls` `Marked(ref)` (Lane B, read only). `Data/Delivery.cls`: `Record` :48, `FindByRef` :83. `Data/Ownership.cls` `DeliveryByRef` :381 (read only; contended).
- `Channel/Telegram/Out.cls`:
  - `KINDS` :78 (no digest or handled); `OnNotification` :135, which drops other kinds :139.
  - `Render` :142; `BUTTONKINDS` :81; `Keyboard` :154-161 (`approve:`/`reject:` callback_data).
  - `Deliver` :187, which keeps the text only with markup (:192); `Recorded` :201.
  - `EditAnswered` :215-241 is the sibling for the handled edit; `Send` :353.
- `Channel/Telegram/In.cls`: `HandleUpdate` :331, `Press(chatRef, query)` :378 (the action is `$Piece(data,":",1)`), the answerCallbackQuery :401-405, `Outcome` :534 (`Commands.Submit(command, "telegram", .result)`). The paired-chat check for approvals is `Core/AnswersIn.cls` :56-68 (`Pairing.Chat`).
- `Core/Rule/Notify.cls` (Lane B) :42-53: kinds `digest` and `handled` take the generic route today, so `TelegramOut` gets them when the session is paired.
- `Core/CommandsIn.cls` (Lane B, read only): the `SendDigest` route :179; the context check :81; the sync `Send` :104; `IsStub` :148.
- Tools:
  - `Tools/CommandCall.cls` `Run` :36 and `Answer` :88; `Tools/ReminderTools.cls` :59-69 is the sibling.
  - The per-tool `STEPLABEL`, `CLASSIFICATION`, `READONLY` and `TRUSTEDOUTPUT` parameters are read by `Gate` :197-210.
  - `Tools/Watching.cls` :12-17 is the toolset; `Tools/Names.cls` :6-28 holds the names.
  - `Agent/Chat.cls` `TOOLSETS` :17 is pinned by `Test/Tools/Reminders.cls` :171 (contended), so the tool goes into `Watching`.
- CI mock: `ci/mock/scenarios.mjs` :12-20 (format), `mock.mjs` :25-36 (the marker first). Siblings: `A/reminder-set-relative.json` (a tool call) and `A/provider-error.json` (a fallback). `ci/mock/test/constants.test.mjs` :50, :86-99 checks every `toolUse.name` against `Names.cls`.
- Tests that change:
  - `Test/Digest/Contracts.cls` `TestDigestStub` :54-68.
  - `Test/Install/Production.cls` :673, the oracle row (Q3).
  - `docker/tests/test-production.sh` rows 14 and 16, which pass with no stub left (:192).
  - `Test/Watch/Tools.cls` `TestDeclarations` (the exact list of `Watching`).
  - `Test/Install/SecurityOverview.cls` :37-44 (12 rows = `RELEASE1`), with `docs/security-overview.md` (Q6).
  - `Test/Msg/Catalog.cls`: the count :81 and :122, the Keys list ~:1105, `Fixtures` ~:1395.
- Test helpers:
  - `Test/Channel/TelegramOut.cls` (LiveCase): `PairedChat` :111, `SentTo` :63, `TellNow` :165, `Rows` :133.
  - `Test/Channel/TelegramApproval.cls`: `Paired` :144, `Press` :154.
  - `Test/Channel/LiveCase.cls`: `StartItems` :165, `Enable` :183.
  - `Test/Core/SessionOpsProduction.cls` `HopsSince` :550; `Test/Core/ProbeSeam.cls`.
  - `Test/Digest/CoverageProbe.cls`, which stands in for Build's seams.

## Tasks & Acceptance

**Execution (in order; tasks marked Qn wait for that ruling):**
- [ ] Task 0 (warm throwaway `e17s6iw`; record under Design Notes "Measured"):
  - an async self-send from `Digest`'s `OnRequest` for a SendDigest, answered `ok` while CommandsIn waits;
  - a `turn` to `ChatAgent` from `Digest` while a chat turn's tool is inside CommandsIn: it completes without a deadlock;
  - `FromLocal` of `YYYY-MM-DDT08:00:00` across a daylight-saving day.

  A contradiction stops the task with Clarification Needed.
- [ ] (Q1) `Checks/Process.cls`: `Parameter DIGEST = "Digest"`, and after the due checks one `Try` block that sends the Tick to `Digest` (`SendRequestAsync`, no answer); a failure logs one warning.
- [ ] `Digest/Process.cls`: drop `STUB`.
  - `OnRequest` takes `Msg.Tick`, `Msg.Command.SendDigest` and a new `Digest/Msg/Compose.cls` (`SessionRef`, `Kind`, `DueAt`, `IdempotencyKey`), which `Digest` sends itself asynchronously.
  - The private seams `Rows` (Coverage.Build), `Saved`, `Summarize` (Decide), `Cost`, `NeedsYou` and `SendNotice` (Notify) are what the tests override.
  - Due, Window, Compose and Record follow the contract.
- [ ] `Digest/Msg/Compose.cls` (new message class, with a storage block).
- [ ] `Digest/Cost.cls` (new): `Yesterday(sessionRef, now, *sc) As %Numeric`.
- [ ] (Q4) `Digest/NeedsYou.cls` (new): `List(sessionRef, failedRows, *sc) As %DynamicArray` of `{what}`; the failed entries first.
- [ ] (Q5) `Digest/Data/Sent.cls`: append `Property IdempotencyKey As %String(MAXLEN = 64)` (storage slot 13, compiler-appended), and the repeat lookup.
- [ ] `Production.cls` line 60: `Digest` `Enabled="true"` (DW-696).
- [ ] `Install/Step/Digest.cls` `Run()`: also seed `digest.time` "08:00" and `digest.channels` "web,phone,telegram" through `Install.Seeds`, from a new `Digest.Process` method `Seeds()`.
- [ ] `Msg/Catalog/Watch.cls`: add `digest.cost` (and `button.gotIt` and `handled.marked` if Q2 is ruled) with the texts under Design Notes.
- [ ] `Test/Msg/Catalog.cls` (Lane B, ruled exception): the `digest.cost` fixture row and Keys entry; Watch count 50 to 51 and the total 152 to 153, with the U-177 marker on the `Fixtures` doc comment and beside the count. Q2 would add two more. Fix any web catalog test the key trips.
- [ ] `Tools/DigestTools.cls` (new, extends `Tools.Result`): `SendDigest()` with `STEPLABELSENDDIGEST` "Sending your digest", `CLASSIFICATIONSENDDIGEST` safe, `READONLYSENDDIGEST` 0, `TRUSTEDOUTPUTSENDDIGEST` 1.
  - `Tools/Watching.cls`: add `<Tool Name="send_digest" .../>` and `DependsOn` it.
  - `Tools/Names.cls`: append `Parameter SENDDIGEST = "send_digest";` (not in `RELEASE1`).
- [ ] (Q6) `Test/Watch/Tools.cls` `TestDeclarations`: add `send_digest` to `Watching`'s exact list. Regenerate `docs/security-overview.md`'s tools table, and update `Test/Install/SecurityOverview.cls`'s row count, as ruled.
- [ ] New `ci/mock/scenarios/A/` files:
  - `digest-summary.json` (marker; a 300-character text);
  - `digest-send-now.json` (marker; `toolUse` `send_digest` `{}`, then text).
- [ ] `Channel/Telegram/Out.cls`:
  - add `digest` and `handled` to the handled kinds;
  - `Digest(request)` renders and joins the pieces;
  - `GOTITKINDS` = `tellnow` with the Got it keyboard;
  - `EditHandled(request)` follows `EditAnswered`'s pattern.
- [ ] `Channel/Telegram/In.cls` `Press`: the `gotit` action, with the checks above, then `Submit`. The approve and reject paths are unchanged.
- [ ] Tests (new; Lane A areas; no `ci/units.sh` edit):
  - `Test/Digest/Due.cls`: matrix rows 1-4, the DST day, the lock (a second job holding it: no send), and an ended online-demo session;
  - `Test/Digest/Compose.cls`: the part order and keys, the cost row, saved, fallback, nothing saved, the 240 cut, 150 words, and `Sent` fields;
  - `Test/Digest/Send.cls` (production): web_admin and tool give `ok` and one Notification (`HopsSince` Digest to Notify); the repeat key; U-268 (no recipient: `SendDigest`'s properties equal `Msg.Command`'s, and a mutation that adds a `Channel` property is shown red); the tick integration (Q1);
  - `Test/Digest/Tool.cls`: the mock marker turn calls `send_digest`;
  - `Test/Channel/TelegramDigest.cls` (LiveCase, mock Telegram): matrix rows Telegram digest, Got it paired and other, Handled.
  - Update `Test/Digest/Contracts.cls` (no stub), `Test/Digest/Thresholds.cls` (the seven seeds), and `Test/Install/Production.cls` (Q3).

**Acceptance Criteria:**
- Given `digest.time` and a session created before today's time, when the heartbeat's tick passes it, then `Digest` sends one `Notification` of kind `digest` to `Notify` with the AD-32 Slots, and records one scheduled `Sent` row. Given a session created after it, then none is sent until tomorrow's tick (DW-651).
- Given ticks stopped across `digest.time` for two days, when ticks resume, then exactly one digest goes, and no later tick repeats it.
- Given a digest being composed, when its Slots are filled, then `parts` follow the six-part order above with `Coverage.Build`'s `lines` and `rows`, the cost sums the session's and `instance`'s Usage of yesterday and never `eval`'s, and needs you lists failed entries first (Q4).
- Given items saved in the window, when the digest is composed, then exactly one `turn` reaches Decide with an untrusted, fresh, unseeded request and the summary is at most 240 characters. Given that request falls back, the digest still goes with `digest.savedNoSummary`, and the fallback is in the Decision row and one log line.
- Given every entry passed and nothing needs the user, when the Telegram text is rendered, then it has at most 150 words.
- Given a chat turn that calls `send_digest`, or Settings' `SendDigest` with origin `web_admin`, when CommandsIn routes it to the enabled `Digest`, then the answer is `ok`, one digest of kind `requested` goes to `Notify`, and the next window starts at its `SentAt` (DW-696, U-268).
- Given a kind `digest` Notification sent to `TelegramOut` for the paired chat (the integration AC: Digest is the producer, TelegramOut the consumer, on a real throwaway production with the Telegram mock), when it is delivered, then the paired chat receives one plain-text message as the contract says.
- Given a tell-now message in the paired chat, when the user presses **Got it** there, then one `GotIt` command is submitted with origin `telegram`. Given a press from another chat, nothing is submitted. Given a `handled` notification, then the message is edited in place to "Marked as handled at {time}" with the button removed.

## Spec Change Log

- 2026-11-06 lead: Q1-Q6 and the public text ruled (orchestrator: Q1, Q3, Q6; Contest Planner under the owner's delegation: texts 1-3, Q2, Q4, Q5). Re-plan to fold them in.

## Review Triage Log

## Design Notes

**Rulings of 2026-11-06 on Q1-Q6 (binding on re-derivation; they answer the open questions below, which stay for the record).**
- **PUBLIC TEXT (Contest Planner under the owner's delegation, exact):** (1) `digest.cost` = `Yesterday's cost: {cost}.` (slot `cost`, type `dailyCost`) APPROVED. (2) `button.gotIt` = `Got it` and `handled.marked` = `Marked as handled at {time}`, verbatim from UX-DR143, APPROVED. (3) the `send_digest` tool's step label `Sending your digest` APPROVED. (4) the overflow line `And {n} more on the OcuTalon page.` APPROVED (Q4 (b)). Any other new user-facing text (for example the Q5 (b) tool result) is PUBLIC TEXT: propose it verbatim under Design Notes; the lead sends it, and nothing that contains it is committed before the answer.
- **Q1 ALLOWED (orchestrator, option 1):** one `DIGEST` parameter and one self-contained `Try` block (`SendRequestAsync(..#DIGEST, tick, 0)`) as the LAST statement of `Checks/Process.cls` `Tick`, before its `Quit $$$OK`, changing no line Epic 39 changed. A test proves a Tick reaches `Digest`. It is a forward, not a heartbeat path: a beat still makes no `BackgroundCheck` row (the 17.5 rule). Epic 39 is expected to merge first: at the lead's integrate-forward after that, the block is re-placed as the final statement of the MERGED `Tick` in the SAME push as the integrate-forward (never a later fix-up), and Checks' Tick tests run green on the merged `Tick`; an exit path that would skip the block, or a placement that needs a behaviour choice, is a Clarification for the lead.
- **Q2 GRANTED (Planner):** the one-time U-177 exception extends to exactly two more fixture rows in Lane B's `Test/Msg/Catalog.cls`, `button.gotIt` and `handled.marked` (count 153 -> 155; the union with Epic 39's count is fine); the Q4 (b) overflow line's key is covered by the same exception if it needs a fixture row (report the final count). No other Lane B line changes. The marker goes on the `Fixtures` XData doc comment, citing "Contest Planner ruling, 2026-11-06, one-time U-177 exception, Story 17.6".
- **Q3 ALLOWED (orchestrator):** the one oracle row in `Test/Install/Production.cls` (Digest `"enabled":1,"stub":0`) and its doc line :13. Epic 19 changes the MemoryOps row of the same file: different rows, a plain union.
- **Q4 APPROVED (Planner, FR-35):** "needs you" lists, in order: (1) the failed non-vital rows; (2) the session's `decide` Decisions with outcome `tellnow` or `act`, not yet handled, newest first; (3) the session's incidents in `awaiting_approval`, named by their code-written `Summary`. Conditions: (a) DE-DUPLICATE: an `act` Decision whose incident is listed as awaiting approval appears once, as the incident. (b) BOUND: the composed digest fits one Telegram message (4096 characters) and the web card without scrolling past it; on overflow keep the newest, drop the oldest, and end the list with the catalog line `And {n} more on the OcuTalon page.`; a test with 200 open items pins it.
- **Q5 ACCEPTED (owner ruling via the Contest Planner, additive AD-18 amendment, marker `[AMENDED 2026-11-06, Story 17.6, owner ruling via the Contest Planner]`):** `SendDigest` answers `ok` at once and `Digest` composes asynchronously; `Digest.Data.Sent` gains `IdempotencyKey` (AD-1's repeat key; an appended property). Conditions: (a) a repeat with the same key sends nothing new (a test); (b) the tool result the model sees says the digest is BEING sent, never that it was sent, so the chat reply never claims delivery (a test on the tool result text; if that text is new it is PUBLIC TEXT, see above); (c) an async compose or send failure is recorded on the existing digest failure path and is visible in Visual Trace (a test); (d) none of AD-18's heartbeat text changes (Epic 39's seven citing specs must still read true). The lead writes the AD-18 amendment into the spine.
- **Q6 ALLOWED (orchestrator, in this shape, which Epic 19 follows too):** a NEW `Tools.Names` parameter for step 2's digest tool (for example `DIGESTTOOLS`, holding `send_digest`); ONE term for it appended to `Test/Install/SecurityOverview.cls`'s expected set (line 37's `released` expression) and its doc line 31 extended; do not rewrite the test to count toolsets. `docs/security-overview.md` is regenerated through `OcuTalon.Install.SecurityOverview`, never hand-edited, and regenerated again after any merge.

**Open questions (the HALT; each needs a ruling before this spec can be ready).**
- **Q1, contended edit, blocking.**
  - Evidence: AD-18 says `Digest` "takes the `Tick` that `Checks` forwards after each tick's checks". But `Checks/Process.cls` `Tick` (:159-189) forwards nothing.
  - The file is Epic 39's: OCT-epic39 rewrote `Tick`'s tail (`BeatRunDue`, `SendOwn`, `AnnounceBeats`), and the project block says "Do not edit `Checks/Process.cls`". The precedent (an append at the end of a file) can't reach a call inside `Tick`, and there is no other path that respects the spine.
  - Recommended: let 17.6 add one `DIGEST` parameter and one self-contained `Try` block (a `SendRequestAsync(..#DIGEST, tick, 0)`) as the last statement of `Tick` before `Quit $$$OK`, with the lead resolving the merge against Epic 39's tail. Or have Epic 39 add it on its branch, or hold 17.6 until Epic 39 merges.
- **Q2, Lane B test beyond the one-time U-177 exception.**
  - Evidence: Telegram's **Got it** needs two catalog lines that UX-DR143 fixes ("Got it" and "Marked as handled at {time}"). No key exists for either, and every new key needs a fixture row and a count in Lane B's `Test/Msg/Catalog.cls`. The 2026-11-06 exception covers `digest.cost` only.
  - That file is also changed on OCT-epic39, at :123 (the refused channels), next to the count at :122, so expect a merge conflict.
  - Recommended: extend the exception to `button.gotIt` and `handled.marked` in `Catalog.Watch` (Watch total 53, overall 155 in this worktree). Lane B's 18.4 renders the same keys for the web and phone.
- **Q3, contended test.**
  - Evidence: enabling `Digest` (DW-696) changes the oracle row `{"name":"Digest",...,"enabled":0,"stub":1}` in `Test/Install/Production.cls` :673. `Test/Install/**` is in Epic 19's footprint, though OCT-epic19 has not changed this file.
  - Recommended: allow the one-row edit (`"enabled":1,"stub":0`), plus the class doc line :13.
- **Q4, product scope (observably different readings).**
  - Evidence: FR-35 says needs you is "failed checks, and tell-now items the user hasn't yet dealt with by answering its approval request or marking it handled with Got it". The spine does not name the source, the time span, or what counts as a tell-now item that has an approval request.
  - Recommended:
    - The failed non-vital rows' entries first.
    - Then the session's `Decision` rows (kind `decide`, owner the session) with outcome `tellnow` or `act`, whose `Ref` is not `Handled.Marked`, newest first.
    - Then the session's incidents in state `awaiting_approval` (the approval not answered). Each is named by its code-written `Summary`, with no time bound beyond retention (AD-27).
  - Alternatives: only the window's items, or only `tellnow`.
- **Q5, an AD-18 field list and a schema change.**
  - Evidence: CommandsIn calls the owner synchronously (`Send` :104). A tool's `SendDigest` runs inside a `ChatAgent` turn, and `ChatAgent` has pool size 1. So a digest that makes its summary request inline would wait on `ChatAgent` itself until the timeout.
  - The owner must also "ignore a repeat" key (AD-1), but `Sent` has no field for it.
  - Recommended: `Digest` answers `ok` at once and sends itself a `Compose` message asynchronously ("sends one at once" still holds). Append `IdempotencyKey` to `Sent` (an append-only property; AD-18's Record list amended), and check the key under the per-session lock both at acceptance and in Compose.
- **Q6, contended generated doc and test.**
  - Evidence: a new built-in tool adds a row to the generated tools table of `docs/security-overview.md` (changed on OCT-epic39, and in Epic 11's `docs/**`). `Test/Install/SecurityOverview.cls` :37-44 asserts 12 rows = `RELEASE1` (Epic 19's footprint).
  - Recommended: allow regenerating that one table row through `OcuTalon.Install.SecurityOverview`. Change the test to count the tools of `OcuTalon.Tools.*` toolsets, or add a `STEP2` list beside `RELEASE1` that the test also counts.

**Rulings that bind this story (recorded, not re-derived).**
- **U-268** (Contest Planner under the owner's delegation, 2026-11-04):
  1. `SendDigest` from origin `tool` or `web_admin` takes no recipient. The destinations come only from the session's `digest.channels`, so neither the model nor an item can choose where a digest goes. A test pins this, with the mutation shown (`Test/Digest/Send.cls`).
  2. `SendDigest` stays non-risky only because it reaches the session's own channels. Any later external target is a new ruling.
  3. The specs that cite AD-1 and AD-14 are re-read at this story's spec gate; grep alone does not clear them.
- **DW-651** (orchestrator ruling via the Contest Planner, 2026-11-05): build and test AD-18's amended due rule. A session is due when the latest `digest.time` has passed, AND that time is later than the session's `CreatedAt`, AND the session has no scheduled `Sent` row with that `DueAt` or later. The before-and-after tests are in `Test/Digest/Due.cls`. `SendDigest` is unaffected.
- **DW-661 and the U-177 exception** (Contest Planner under the owner's delegation, 2026-11-06):
  - Add `digest.cost` to `Msg/Catalog/Watch.cls` with the `dailyCost` slot type.
  - This is a one-time U-177 exception for this story, scoped to the catalog-count test. Add `digest.cost`'s fixture row to Lane B's `Test/Msg/Catalog.cls` and raise the count from 152 to 153. Put the U-177 marker on the `Fixtures` XData doc comment, citing "Contest Planner ruling, 2026-11-06, one-time U-177 exception, Story 17.6".
  - Fix any web catalog test the new key trips. Nothing else in any Lane B class or test.
  - Note for the lead: the feature branch's count is now 154 (other epics' keys). At the merge the count becomes the union.
- **PUBLIC TEXT**: below; the lead sends it to the Planner before any commit.

**Proposed text (for the Planner): digest.cost.**
- `digest.cost`: `Yesterday's cost: {cost}.`, with slot `cost` of type `dailyCost`. Source: EXPERIENCE.md, Message Catalog / Daily digest / "Every digest (the cost)", verbatim. Rendered with 0.042, it reads "Yesterday's cost: $0.04.".

**Proposed text (for the Planner), only if Q2 is ruled:**
- `button.gotIt`: `Got it`, no slots. Source: EXPERIENCE.md, Later Steps / Step 2 (UX-DR143).
- `handled.marked`: `Marked as handled at {time}`, with slot `time` of type `time`. Source: UX-DR143, verbatim, with no full stop, as the UX writes it.

No other new user-facing text. The tool's step label "Sending your digest" is shown in the turn's steps, so it is user-facing too: it follows the release-1 labels ("Setting a reminder"). It is listed here for the Planner.

**Governing ADs (Rule 6):** AD-1, AD-5, AD-6, AD-8, AD-10, AD-14, AD-18, AD-20, AD-22, AD-28, AD-29, AD-30, AD-32 and AD-33. No AC contradicts an AD's Rule; Q5 would amend AD-18's Record field list.

**Ledger (Rule 17).**
- DW-649 is addressed by the due rule's `Kind` filter and requested `DueAt` "" (matrix "Requested").
- DW-651 is addressed by the due rule and matrix rows 1-2.
- DW-696 is addressed by enabling the item and the matrix row "Disabled item fixed".
- DW-661 is addressed by the `digest.cost` key and the catalog test task.

**Decided in-stage.**
1. **Ended sessions** are as stated in the contract, because the Session row has no end marker.
2. **`{checked}`** is each non-vital entry prefixed "the", joined with ", " and " and " (for example "the Orders production").
3. **`{whatFailed}`** is the vital entries joined the same way, and needs you's `{what}` is the summaries joined with "; ".
4. **The summary request's `SystemNote`** is a fixed, model-facing parameter: "Summarize the saved items in one or two plain sentences. Don't say whether things are fine."
5. **Telegram layout:** one piece per line, coverage lines after the checked part. The UJ-2 sample is prose, and the AC asks for lines that start with their result.
6. **A Got it press** gets an answerCallbackQuery with no text, so it adds no new text.
7. **The cost reads `Usage` directly** (a Lane A read of bridge rows, as `Checks.Process.Fixes` reads `ApprovalRequest`), because `Ownership.RunCost` has no upper bound and excludes `instance`.
8. **The tool goes into the `Watching` toolset,** because `Chat.TOOLSETS` is pinned by contended `Test/Tools/Reminders.cls`.

**Contention (Rule 11) and allowed appends.**
- `Tools/Names.cls`: a one-name append.
- `ci/mock/scenarios/A/`: new files only.
- `Test/Msg/Catalog.cls`: the ruled exception. It is changed on OCT-epic39 (the line next to the count), so the lead resolves it at the merge.
- Q1, Q3 and Q6 are the contended edits that need a ruling.
- Not touched: `Core/**`, `Data/Ownership.cls`, `Msg/Enum.cls`, `ci/units.sh`, `src/short-names.tsv`, `Test/Checks/**`, `Test/Tools/**`.
- Footprint extensions: `Production.cls`, `Test/Watch/Tools.cls`, `Test/Channel/TelegramDigest.cls`.

**Story 30.7 check.** Nothing here changes the purges, approvals, `Reconcile`, `Bridge.Redact`, `Test.Eval.KeyProof` or `list_productions`. TelegramIn's approve and reject path is left as it is.

**Extend, don't copy (Rule 2).**
- `Compose` follows `Intake.RequestFor`.
- `EditHandled` follows `EditAnswered`.
- `DigestTools.SendDigest` follows `ReminderTools.SetReminder`.
- The seeds go through `Install.Seeds`.
- The cost sum is new (no ranged sibling exists).

**Integration ACs (Rule 1):** the TelegramOut AC above. `Digest` (the producer) and `TelegramOut` (the consumer) run in one real throwaway production.

**Consumes:**
- 17.5: `Coverage.Build` rows, lines and vitals, and the seeds step;
- 33.1 and 33.2: `Sent`, the keys, `dailyCost`, `SendDigest`, `GotIt`, `Handled`;
- 12.x: TelegramOut and TelegramIn.

**Consumed-by:**
- 17.7: the composition, for the all-clear rules and the eval cases;
- 18.2: `Notify`'s routing of kind `digest`;
- 18.4: the web and phone copies, and the Got it writer, which sends `handled`;
- 22.5: the sources section.

## Verification

Every `ci/*.sh` call carries:
- `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-a"`
- `OCUTALON_TEST_WEB_PORT=52801`
- `OCUTALON_LOCK_OWNER='epic=17 stage=<stage>'`

Run one command per call, in the foreground, with `timeout: 600000`. The tags are `e17s6iw` (warm) and `e17s6i` (fresh). Run `ci/warm.sh down` at the end, also after a failure. On `ocutalon-slot-a` use only `iris_doc_load`, with `server` and `namespace` on every call; nothing destructive runs there.

**Commands:**
- (once) `OCUTALON_RUN_TAG=e17s6iw ci/warm.sh up`.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e17s6iw ci/iris.sh class <C>`, one class per call. Each must print `CLASS <C> passed`. The classes:
  - `OcuTalon.Test.Digest.Due`, `.Compose`, `.Send`, `.Tool`, `.Contracts`, `.Thresholds`;
  - `OcuTalon.Test.Channel.TelegramDigest`, `OcuTalon.Test.Channel.TelegramOut`, `OcuTalon.Test.Channel.TelegramApproval`;
  - `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Watch.Tools`, `OcuTalon.Test.Install.Production`.
- (once) `bash docker/tests/test-mock.sh`, then `test-security-overview.sh`, `test-class-rules.sh`, `test-boundaries.sh`, `test-storage.sh` and `test-ci-config.sh`, one per call: each passes.
- (once) `cd web && node --test scripts/catalog.test.mjs`: passes.
- (once) Fresh, `OCUTALON_RUN_TAG=e17s6i`, one per call:
  - `ci/iris.sh live production`, then `live install-start`;
  - `shard lane-a@Checks,Install,Watch` and `shard lane-a@rest`, with `--part k/n` so that each call stays under about 8 minutes;
  - `ci/iris.sh teardown`.

**Shared surfaces:**
- the production item list (`Test.Install.Production` oracle, `test-production.sh` rows 14 and 16);
- the catalog key count and Keys list (`Test.Msg.Catalog`, the web catalog tests);
- `Tools.Names` (`ci/mock/test/constants.test.mjs`);
- the `Watching` tool list (`Test.Watch.Tools`, `Test.Agent.Runners` `TestToolInventory`);
- the security overview's tools table;
- the `Data.Setting` rows `digest.time` and `digest.channels`;
- the `Sent` rows.

Every test added or changed passes on a fresh environment, in either order.

**Planned mutations (Rule 19), one per AC:**
- The `CreatedAt` clause removed: `Due` `TestCreatedAfter` red.
- `>=` made `>` in the scheduled lookup: `TestCatchUpOnce` red.
- The cost includes `eval`: `Compose` `TestCost` red.
- The part order swapped (saved before needs you): `TestPartOrder` red.
- The 240 cut removed: `TestSummaryCut` red.
- Fallback ignored: `TestSummaryFallback` red.
- `Enabled="false"` restored: `Send` `TestWebAdminSends` red.
- A `Channel` property added to `SendDigest`: `TestNoRecipient` red.
- Telegram: `parse_mode` added: `TelegramDigest` `TestPlainText` red.
- The paired-chat check dropped: `TestGotItOtherChat` red.
- `reply_markup` kept on edit: `TestHandledEdit` red.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: Q1-Q6 under Design Notes need rulings before this story is ready. Q1: the Tick forward requires an edit to contended Checks/Process.cls (Epic 39). Q2: the Telegram Got it texts need two catalog keys beyond the one-time U-177 exception. Q3: enabling Digest changes Test/Install/Production.cls (Epic 19 footprint). Q4: needs-you sources and time span are not fixed. Q5: tool-path deadlock and idempotency need async compose and an IdempotencyKey on Sent (AD-18 field list). Q6: the new tool changes the generated docs/security-overview.md (Epic 39 and Epic 11) and Test/Install/SecurityOverview.cls (Epic 19).
