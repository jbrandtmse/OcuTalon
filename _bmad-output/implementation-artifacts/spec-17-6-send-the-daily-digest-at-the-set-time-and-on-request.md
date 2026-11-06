---
title: 'Story 17.6: Send the daily digest at the set time and on request'
type: 'feature'
created: '2026-11-06'
status: 'blocked'
baseline_revision: '814a4e1499f7299ea25b7736f03eef60f1b4cb72'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-17-context.md'
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `OcuTalon.Digest.Process` is a stub (`STUB` = 1, answers 5003) and the `Digest` item is disabled, so no digest is ever sent. A `SendDigest` from Settings answers `failed` (DW-696). Nothing reaches `Digest` on a tick. `TelegramOut` drops kinds `digest` and `handled`. Telegram tell-now messages have no **Got it** button. `digest.cost`, `button.gotIt`, `handled.marked` and the needs-you overflow line are missing from the catalog (DW-661, Q2, Q4).

**Approach:**
- `Checks` forwards each `Tick` to `Digest` with one `Try` block, the last statement of `Tick` (Q1).
- On a tick, `Digest` applies AD-18's amended due rule (DW-651) under a per-session lock, and queues one `Compose` per due session.
- On `SendDigest`, `Digest` answers `ok` at once and queues one `Compose`; it composes asynchronously (Q5, AD-18 as amended 2026-11-06).
- A `Compose` builds the digest from `Coverage.Build`, `Checks.Render`, the needs-you sources (Q4), `Digest.Data.Item.Since` (with at most one asynchronous `Decide` turn) and yesterday's `Usage` cost.
- It sends one `Notification` of kind `digest` to `Notify`, then writes one `Sent` row.
- A chat tool `send_digest` submits `SendDigest`.
- `TelegramOut` renders a digest as one plain-text message, adds **Got it** to tell-now messages, and edits its copy on a `handled` notification. `TelegramIn` submits `GotIt` for a press from the paired chat.

## Boundaries & Constraints

**Always:**
- **Due rule (AD-18 as amended, DW-651).** On a tick at `tickAt`:
  - `due` is the latest instant at or before `tickAt` whose instance-zone clock reads `digest.time`. It is computed only through `OcuTalon.Data.Time` (`ToLocal`, `FromLocal`). `digest.time` is read through `Data.Setting.Get("digest.time", "08:00")`; an unreadable value means `08:00`.
  - A session that has not ended is due when all of these hold:
    - `due` > its `CreatedAt`;
    - it has no `Sent` row with `Kind` `scheduled` and `DueAt` >= `due`;
    - it has no `Compose` message body with `Kind` `scheduled` and `DueAt` >= `due` (a digest already queued for that time);
    - the check gives the same answer again under `Lock +^OcuTalon.Digest.Due(sessionRef):5`. The `Compose` is created and sent inside that lock.
  - A scheduled row stores `DueAt` = `due`. A requested row stores `DueAt` "" (DW-649), and the due lookup filters on `Kind = 'scheduled'`.
  - So a digest missed while IRIS was down goes once (only the latest `due` counts), and never twice.
- **Ended.** On the online demo (`onlineDemo` = 1), a session has ended when its `ResumeHash` is empty. On a local install no session ends, so every `Session` row counts.
- **Compose (`OcuTalon.Digest.Msg.Compose`, new).** It holds `SessionRef`, `Kind`, `DueAt`, `IdempotencyKey`, `WindowStart` and `WindowEnd`, and no text (AD-3). `Digest` sends it to itself with `SendRequestAsync` and no response. It never blocks the `Digest` job on another item: the summary request is `SendRequestAsync` to `Decide` with a response, finished in `OnResponse`.
- **Window.** `WindowStart` is the session's newest `Sent.SentAt` of either kind, or 24 hours before `WindowEnd` for its first digest. `WindowEnd` is the time the `Compose` is created. Either kind of digest starts the next window.
- **Composition**: one `Notification`, `Kind` `digest`, `SessionRef`.
  - `CatalogKey` = `Checks.Render` over the non-vital rows when the session watches anything, and over `[]` when it watches nothing (AD-28).
  - `DecisionRef` = the model request's, or "".
  - `Slots` = `{"parts", "lines", "rows"}` (AD-32). `parts` holds these, in this order:
    1. greeting by the compose hour in the instance zone (`digest.greetingMorning` 00-11, `Afternoon` 12-17, `Evening` 18-23);
    2. `digest.healthy` when all five vital rows passed (`count` = upDays, `itemNoun` `{"one":"day","other":"days"}`, `databasesFull`, `licenseUse`), else `digest.vitalsNotAll` (`whatFailed` = the entries of the vital rows that did not pass);
    3. either `digest.checkedQuiet` (every non-vital row passed) or `digest.checked`, followed by `Render`'s key with `{}`. When nothing is watched, this part is `digest.nothingWatched` alone;
    4. needs you: `digest.needsYouOne` `{what}` or `digest.needsYou` `{count, what}`, then `digest.needsYouMore` `{n}` on overflow; no part when nothing needs the user;
    5. saved for later: `digest.savedNone`, `digest.saved` `{count, summary}`, or `digest.savedNoSummary` `{count, fallbackReason}`;
    6. `digest.cost` `{cost}`, yesterday's cost.
  - `lines` and `rows` are `Coverage.Build`'s, unchanged.
- **Needs you (Q4, FR-35).** The entries, in this order:
  1. the failed non-vital rows, each named `<entry>: <finding>` (the entry alone when the finding is empty);
  2. the session's `decide` Decisions (`Ownership.Decisions`) with outcome `tellnow` or `act` whose `Ref` is not `Handled.Marked`, newest first, each named by its code-written `Summary`;
  3. the session's incidents (`Ownership.Incidents`) in state `awaiting_approval`, each named by the code-written `Summary` of its diagnose Decision (`Incident.DecisionRef`), or its `Production` when that is empty.
  - **De-duplicate:** a Decision whose `Ref` is an `awaiting_approval` incident's `DecisionRef`, or whose `ItemId` is that incident's `Ref`, appears once, as the incident.
  - **Bound:** at most `NEEDSYOUMAX` (5) entries are named. On overflow the newest are kept and the oldest dropped (each entry's time: a row's `checkedAt`, a Decision's `RecordedAt`, an incident's `NoticedAt`), and the kept entries stay in the order above. `count` is the total, and `digest.needsYouMore` `{n}` (`n` = total minus kept) follows. The composed digest rendered for Telegram is at most 4096 characters with 200 open items.
- **The model request (AD-30)** is made at most once per digest, and only when `Item.Since(sessionRef, WindowStart)` holds an item recorded at or before `WindowEnd`.
  - It is an `OcuTalon.Bridge.Msg.Request` with `Kind` `turn`, `Provenance` `untrusted` and `SessionMode` `fresh`. It has no `SeedText`.
  - `OwnerRef` is the session, `ItemId` is a new `Bridge.Ids.NewRef()`, and `Channel` is `system`.
  - `Input` is `Agent.Input.Render` of an `OcuTalon.Msg.Item` with channel `system`, subject "Saved for later", and text one stored `Summary` per line.
  - The reply text, already filtered by Decide's guard, is cut by code to 240 characters.
  - Any `Fallback`, error, timeout or empty text gives `digest.savedNoSummary` with the reason (an unknown reason gives `unusable`). The fallback is logged with one `$$$LOGINFO` line in the Compose's session, and the Decision row carries it (Visual Trace).
- **Cost.** The sum of `Bridge.Data.Usage.CostUSD` where `OwnerRef` is the session or `instance` (never `eval`) and `RecordedAt` is in [yesterday 00:00, today 00:00) in the instance zone, both converted through `Data.Time.FromLocal`. It is passed as a number to slot type `dailyCost`.
- **Record.** One `Sent` row per digest sent (`Ref` = `NewRef()`, every AD-18 field, `IdempotencyKey` included), written after the `Notification` is sent. `AllClear` = 1 only when `CatalogKey` = `checks.allPassed`.
- **Failure path (Q5 (c)).** An error in a `Compose`'s handling (a seam's error status or an exception) is returned as that handling's error `%Status`. Ensemble then records it on the `Compose`'s message header and as an Error entry in its trace session, which Visual Trace shows. No `Notification` and no `Sent` row follow.
- **SendDigest (U-268, Q5).**
  - It is taken from CommandsIn (origins `tool`, `web_admin`) and takes no recipient.
  - Destinations come only from `Notify` and `digest.channels`. Nothing in `Digest` reads a destination from the command, the model or an item.
  - Under `Lock +^OcuTalon.Digest.Due(sessionRef):5`: when the `IdempotencyKey` is not empty and a `Sent` row or a `Compose` body of the session already holds it, nothing new is queued (Q5 (a)); otherwise one `Compose` (`Kind` `requested`, `DueAt` "") is queued.
  - The answer, at once, is `CommandResult` `Ok` 1, `Outcome` `sending`, `Message` = `Digest.Process` `MESSAGESENDING`, both for a new request and for a repeat. Never `failed` (DW-696).
  - The tool result the model sees says the digest is being sent, never that it was sent (Q5 (b)).
- **The digest tool `send_digest`** is a safe action (classification `safe`, not read-only, trusted output).
  - It submits `SendDigest` through `Tools.CommandCall.Run` (origin `tool`, key `ItemId:position`).
  - It takes no input and returns `CommandCall.Answer(result)`.
  - Its name is a new `Tools.Names` parameter `DIGESTTOOLS` = `"send_digest"`, not in `RELEASE1` (Q6), and a mock scenario calls it.
- **Telegram.**
  - **Digest.** `TelegramOut` renders a digest as one plain-text message (`Catalog.Render(..., "telegram")` for every `{key, slots}`, and nothing else). The order is: greeting, vitals, the checked part and its reserved sentence, one coverage line per row, needs you (and its overflow line), saved for later, cost. Each piece goes on its own line, with no Markdown. It records a `Delivery` row.
  - **Tell-now.** A `tellnow` message with a `DecisionRef` gets one inline button `button.gotIt`, with `callback_data` `gotit:<DecisionRef>` (22 random base64url characters, `Bridge.Ids`).
  - **A press.** `TelegramIn` submits `OcuTalon.Msg.Command.GotIt` (`Ref`, `Channel` `telegram`, the session) through `Core.Commands.Submit(..., "telegram")` only when all of these hold:
    - the chat is paired (`Pairing.Chat`);
    - the session's `Delivery` row for that Ref (`Ownership.DeliveryByRef(ref, "telegram", session)`) exists;
    - that row's chat is the pressing chat.

    It answers the callback with no text. Any other press submits nothing.
  - **Handled.** On a `handled` Notification, `TelegramOut` edits its copy in place (`Delivery.FindByRef`) to the kept text plus a blank line and `handled.marked` `{time}` (`time` = `Handled.Marked(ref)`), with no `reply_markup`, so the button is removed.
- **Source rules.** ASCII source and contract-only comments (Rule 14). Storage is append-only (AD-5).

**Never:**
- An edit to an existing contended file beyond the rulings: in `Checks/Process.cls` only Q1's `DIGEST` parameter and last `Try` block of `Tick` (no other line, no doc-comment line); in `Test/Install/Production.cls` only Q3's row and doc line; in `Test/Install/SecurityOverview.cls` only Q6's one term and doc line; `docs/security-overview.md` only as regenerated (Q6); `Test/Tools/Reminders.cls` and `Test/Bridge/Gate.cls` only as Q7 rules. Never `Checks/Beat.cls`, `Test/Checks/**`, `Core/**`, `Data/Ownership.cls`, `Msg/Enum.cls`, the rest of `docs/**`, `ci/units.sh`, `src/short-names.tsv`, the spine.
- An edit to a Lane B class or test (U-177) beyond the one-time exception: `Test/Msg/Catalog.cls`, four fixture rows and their Keys and counts (Q2).
- A recipient, channel or address on `SendDigest` or the tool, or a `Digest` code path that picks a destination.
- Composing synchronously inside `SendDigest`'s CommandsIn call, or a synchronous call from `Digest` to another item (Q5: a deadlock on the one-job `ChatAgent`).
- A tool result or code-written text that says the digest was sent or delivered.
- The all-clear rules' own tests, the evaluation cases, the guard's banned-phrase test (Story 17.7), the web and phone digest copies, the Got it writer, `Notify`'s `digest.channels` routing (Lane B, Stories 18.2 and 18.4).
- `Bridge.Time` in `Digest` (only `Data.Time`; AD-18). No `temperature`, `top_p` or `top_k`.
- User-facing text beyond the approved and proposed list under Design Notes.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Created before (DW-651) | `digest.time` 08:00, session created 07:30 today, tick 08:01 | one scheduled digest, `DueAt` today 08:00; a second tick sends none | none |
| Created after (DW-651) | created 08:30 today, ticks 08:31 to 23:59 | none today; one at the tomorrow-08:00 tick | none |
| Restart catch-up | no ticks 07:00 to 10:00 for two days, then a tick at 10:00 | one digest (`DueAt` the latest 08:00), never repeated | none |
| Queued, not yet sent | a scheduled `Compose` for 08:00 waits on Decide; tick 08:02 | no second `Compose` | none |
| Requested (DW-649) | `SendDigest` web_admin at 07:00, tick 08:01 | two digests; requested `DueAt` ""; the scheduled one still goes; its window starts at the requested `SentAt` | none |
| Repeat key (Q5 a) | the same `IdempotencyKey` twice, before and after the first is sent | one digest; both answers `ok`, `sending`, `MESSAGESENDING` | none |
| Disabled item fixed (DW-696) | real production, `SendDigest` web_admin | `ok` at once, then one `Notification` kind `digest` at `Notify` | never `failed` or `not_built` |
| Compose fails (Q5 c) | the `Rows` seam returns an error | no `Notification`, no `Sent` row; the `Compose` header is an error and its trace session holds one Error entry | the SendDigest answer stays `ok` |
| Saved, summary | 3 items saved in the window, mock text of 300 characters | `digest.saved` `{count: 3, summary: <first 240>}`; one Decide request | none |
| Saved, fallback | mock `provider-error` | `digest.savedNoSummary` `{3, fallbackReason}`; the digest still goes; one `LOGINFO` line | none |
| Nothing saved | no item | `digest.savedNone`; no Decide request (mock log) | none |
| Needs you, order (Q4) | 1 failed row, 2 unhandled tell-now Decisions, 1 handled, 1 awaiting incident | `digest.needsYou` `{count: 4}`, `what` = row; newer Decision; older Decision; incident | none |
| Needs you, de-dup (Q4 a) | an `act` Decision whose Ref is an awaiting incident's DecisionRef | listed once, as the incident | none |
| Needs you, overflow (Q4 b) | 200 unhandled tell-now Decisions | 5 newest named, `count` 200, then "And 195 more on the OcuTalon page."; Telegram text <= 4096 characters | none |
| Cost | Usage today 0.5 (session), yesterday 0.012 (session) + 0.03 (instance) + 9 (eval) + 1 (other session) | `{cost: 0.042}` rendered "Yesterday's cost: $0.04." | none |
| Quiet day | everything passed, nothing needs the user | rendered Telegram text <= 150 words | none |
| Telegram digest | fixture digest notification to `TelegramOut` | one `sendMessage`, no `parse_mode`, lines "Passed:", "Failed:", "Not checked:", cost `$0.04` | render error: nothing sent |
| Got it, paired chat | tell-now message with **Got it**; press from that chat | one `GotIt` submitted, origin `telegram`, Ref = the `DecisionRef` | none |
| Got it, other chat | the same `callback_data` pressed in another chat | nothing submitted | none |
| Handled | fixture `handled` notification and fixture marker | the message is edited to "...\n\nMarked as handled at {time}" with no button | no row: one warning |
| Tool (Q5 b) | chat marker scenario calling `send_digest` | `SendDigest` with origin `tool` and key `ItemId:1`; the tool result is `{ok: true, message: MESSAGESENDING}`; the digest goes | none |
| Tick forward (Q1) | a real `Tick` through `Checks` with a due session | one `Tick` header Checks to Digest in the tick's session; no `BackgroundCheck` row added by it | a failed send: one warning, Tick still OK |

</intent-contract>

## Code Map

Paths are under `src/ocutalon/cls/OcuTalon/`; the bridge is under `src/bridge/cls/OcuTalon/Bridge/`. No source has changed since the first plan (only bookkeeping commits), so the anchors stand.

- `Digest/Process.cls`: the stub (extends `Ens.BusinessProcess`). Its doc comment states the old due rule; replace it.
  - Siblings: `Core/Intake.cls` `RequestFor` :151-164 and the untrusted `turn` on act :185-187; `Send` :250 (async, answer in `OnResponse` :108).
  - Read a Reply as `Core/Conversation.cls` `Replied` :445-459 does. The fallback reasons are in `Bridge/Msg/Enum.cls` :15.
- `Bridge/Msg/Request.cls` (Kind, Provenance, Input, ItemId, Summary, OwnerRef, TraceRef, Channel, ThreadSessionId, SessionMode, SeedText, SystemNote) and `Bridge/Msg/Reply.cls` (Text, Fallback, FallbackReason, DecisionRef).
  - `Decide` (PoolSize 1, `Production.cls` :20) routes `turn` to `ChatAgent` (PoolSize 1, :34; `Bridge/Process/Decide.cls` :140), and the guard already runs there (`Production.cls` :22).
  - Any provenance other than `user` limits the turn to safe read-only tools (`Bridge/Policy/Gate.cls` :142).
- `Agent/Input.cls` `Render(item, now)` :15. `Msg/Item.cls` :6-27. `Bridge/Ids.cls` `NewRef()` :7.
- `Checks/Coverage.cls` `Build(sessionRef, fromUtc, toUtc, *rows, *lines, *vitals)` :125 and `Thresholds()` :111. `Checks/Render.cls` `Render(results, *rows) As %String` :36 (keys :18-27).
- `Checks/Process.cls` (Epic 39's, contended): `Tick` :159-187, the due-checks `Try` ends :185, `Quit $$$OK` :186. The forward goes between them (Q1). Parameters :56-146; the async-send sibling is `SendFixResult` :225-227.
- `Digest/Data/Sent.cls`: all AD-18 fields in storage slots 2-12; `SessionRefDueAtIndex` has no Kind, so filter on Kind (DW-649). `Digest/Data/Item.cls` `Since` :38 (`>= since`, newest first).
- `Msg/Command.cls`: `IdempotencyKey` `MAXLEN = 128` :12. `Msg/Command/SendDigest.cls` (base fields only; U-268). `Msg/CommandResult.cls` (Ok, Message, Outcome, Ref, DueAt, Data).
- `Data/Time.cls`: `NowUtc` :18, `Seconds` :27, `AddSeconds` :42, `ToLocal` :54, `FromLocal` :68 (fold 0, skipped hour +1 h).
- `Data/Session.cls`: `Ref`, `CreatedAt` :35, `ResumeHash`. There is no end marker; `SessionOps.End` clears `ResumeHash`.
- `Data/Setting.cls`: `Get` :39 (instance-wide, 60 s cache), `Seed` :57.
- `Core/SettingsOps.cls` (Lane B, read only): `digest.time` "08:00" :192 and `digest.channels` "web,phone,telegram" :193.
- `Install/Step/Digest.cls` `Run()` :10 (one `Install.Seeds.Defaults` call). `Install/Seeds.cls` :9.
- `Bridge/Data/Usage.cls`: `OwnerRef` :31, `CostUSD` :55, `RecordedAt` :61. `Ownership.RunCost` :97 has only a lower bound and no `instance`, so it is not reused.
- Needs-you sources (read only):
  - `Data/Ownership.cls` `Decisions(sessionRef, max)` :282 (Kind decide, newest `RecordedAt` first) and `Incidents(sessionRef)` :289 (the session's noticed incidents, and `instance`'s on a local install).
  - `Bridge/Data/Decision.cls`: `Ref`, `Kind`, `ItemId`, `OwnerRef`, `Summary` (code-written, 80), `Outcome`, `RecordedAt`.
  - `Data/Incident.cls`: `Ref`, `State`, `Production`, `NoticedAt`, `DecisionRef` :63 (its diagnose Decision, whose `Summary` is `IncidentManager.SummaryOf` :676, "<count> failures at <item>"). The state constant is `Watch/Transitions.cls` `#AWAITING`.
  - `Data/Handled.cls` `Marked(ref)` :26 (Lane B).
- `Msg/Catalog/Watch.cls`: `button.approve` :313, `button.reject` :318, the `digest.*` keys :323-484 (`digest.needsYou` :455 is the shape for `count` + `text` slots). The `dailyCost` slot is `Msg/Catalog.cls` :17, `DailyCost` :242; slot types :10-17.
- `Data/Delivery.cls`: `Record` :48, `FindByRef` :83. `Data/Ownership.cls` `DeliveryByRef` :381 (read only; contended).
- `Channel/Telegram/Out.cls`:
  - `KINDS` :78 (no digest or handled); `OnNotification` :135, which drops other kinds :139.
  - `Render` :142; `BUTTONKINDS` :81; `Keyboard` :154-161 (`approve:`/`reject:` callback_data).
  - `Deliver` :187, which keeps the text only with markup (:192); `Recorded` :201.
  - `EditAnswered` :215-241 is the sibling for the handled edit; `Send` :353.
- `Channel/Telegram/In.cls`: `HandleUpdate` :331, `Press(chatRef, query)` :378 (the action is `$Piece(data,":",1)`), the answerCallbackQuery :401-405, `Outcome` :534 (`Commands.Submit(command, "telegram", .result)`). The paired-chat check for approvals is `Core/AnswersIn.cls` :56-68 (`Pairing.Chat`).
- `Msg/Command/GotIt.cls` (`Ref`, `Channel`); `Core/CommandsIn.cls` routes it to `SessionOps` :181 (answers `not_built` until Story 18.4).
- `Core/Rule/Notify.cls` (Lane B) :42-53: kinds `digest` and `handled` take the generic route today, so `TelegramOut` gets them when the session is paired.
- `Core/CommandsIn.cls` (Lane B, read only): `TOOLVERBS` :32 holds `SendDigest`; the context check :81; the sync `Send` :104 (`TIMEOUT` 120 s); `IsStub` :148; the route :179.
- Tools:
  - `Tools/CommandCall.cls` `Run` :36 and `Answer` :88 (`{ok, message}` = the owner's `Message` unchanged); `Tools/ReminderTools.cls` :59-69 is the sibling. The owner-message sibling is `Schedule/ReminderOps.cls` `MESSAGESET` :44.
  - The per-tool `STEPLABEL`, `CLASSIFICATION`, `READONLY` and `TRUSTEDOUTPUT` parameters are read by `Gate` :197-210 (pattern: `Tools/RecentActivity.cls` :22-28).
  - `Tools/Watching.cls` :12-17 is the toolset; `Tools/Names.cls` :6-28 holds the names.
  - `Agent/Chat.cls` `TOOLSETS` :17 is pinned by `Test/Tools/Reminders.cls` :171 (contended), so the tool goes into `Watching`.
- CI mock: `ci/mock/scenarios.mjs` :12-20 (format), `mock.mjs` :25-36 (the marker first). Siblings: `A/reminder-set-relative.json` (a tool call) and `A/provider-error.json` (a fallback). `ci/mock/test/constants.test.mjs` :50-52 reads every `Parameter X = "...";` of `Names.cls` except `RELEASE1` as a tool name and requires them distinct (so one parameter holds `send_digest`, never two).
- Tests that pin the shapes this story changes:
  - `Test/Digest/Contracts.cls` `TestDigestStub` :54-68.
  - `Test/Install/Production.cls` doc :13 and the oracle row :673 (Q3). `docker/tests/test-production.sh` rows 14 and 16 (:164-171) pass with no stub left.
  - `Test/Install/SecurityOverview.cls` doc :37 and `released` :43 (Q6; the ruling's "line 37 / doc line 31" are these two lines). `docs/security-overview.md` tools table :13-22, written by `bash docker/tests/test-security-overview.sh --write`.
  - `Test/Msg/Catalog.cls`: the Watch count :81-84 (50) and the total :122 (152), the Keys list ~:1105, `Fixtures` XData :1246 (rows ~:1396-1400).
  - Lane A tests outside the footprint, not contended: `Test/Agent/Constants.cls` `TestToolNames` :27-51 (12 names), `Test/Agent/Runners.cls` `REMINDERTOOLS` :77 and `TestToolInventory` :320-337, `Test/Agent/Instructions.cls` :25 and :234, `Test/Watch/Tools.cls` `TestDeclarations` :68-77, `Test/Watch/Turns.cls` :63.
  - Contended, Epic 19's footprint (Q7, RULED 2026-11-06 by the orchestrator: a plain union, in Q6's shape): `Test/Tools/Reminders.cls` :275 (the exact sorted tool names of a chat request) and `Test/Bridge/Gate.cls` `TRUSTEDTOOLS` :117 (`TestFlagsAreListed` :1347-1365 requires every trusted-output tool there).
  - Regression only (read, not edited): `Test/Checks/Heartbeat.cls` :215 (a quiet-sweep session's first header is the Tick), `Test/Checks/Runs.cls`, `Test/Schedule/Heartbeat.cls` :263, `Test/Digest/Runs.cls` :208.
- Test helpers:
  - `Test/Channel/TelegramOut.cls` (LiveCase): `PairedChat` :111, `SentTo` :63, `TellNow` :165, `Rows` :133.
  - `Test/Channel/TelegramApproval.cls`: `Paired` :144, `Press` :154.
  - `Test/Channel/LiveCase.cls`: `StartItems` :165, `Enable` :183.
  - `Test/Core/SessionOpsProduction.cls` `HopsSince` :550; `Test/Core/ProbeSeam.cls`; `Test/Data/Fixture.cls` `SessionHeaders`.
  - `Test/Digest/CoverageProbe.cls`, which stands in for Build's seams.

## Tasks & Acceptance

**Execution (in order):**
- [x] Task 0 (warm throwaway `e17s6iw`; record under Design Notes "Measured"):
  - a `SendRequestAsync` from `Digest` to its own config name inside the `OnRequest` of a SendDigest that CommandsIn sent synchronously: CommandsIn gets `ok` before the `Compose` runs;
  - a `turn` from a `Compose` to `Decide` (async, with a response) while a chat turn's `send_digest` is inside CommandsIn: both finish, with no wait near CommandsIn's 120 s;
  - `FromLocal` of `YYYY-MM-DDT08:00:00` across a daylight-saving day.

  A contradiction stops the task with Clarification Needed.
- [x] `Checks/Process.cls` (Q1, ruled): add `Parameter DIGEST = "Digest";` with its own one-line doc comment, and, as the last statement of `Tick` before `Quit $$$OK`, one `Try` block that sends `tick` with `..SendRequestAsync(..#DIGEST, tick, 0)`; an error status or exception logs one Type 3 warning. Change no other line. The lead re-places the block as the last statement of the merged `Tick` at the integrate-forward after Epic 39 merges, in the same push.
- [x] `Digest/Msg/Compose.cls` (new, extends `Ens.Request`, with its storage block): `SessionRef`, `Kind`, `DueAt`, `IdempotencyKey` (`MAXLEN = 128`), `WindowStart`, `WindowEnd`; `Index SessionKeyIndex On (SessionRef, IdempotencyKey)`.
- [x] `Digest/Data/Sent.cls` (Q5, ruled): append `Property IdempotencyKey As %String(COLLATION = "EXACT", MAXLEN = 128);` (storage value 13, appended by the compiler; slots 2-12 unchanged), and `Index SessionRefKeyIndex On (SessionRef, IdempotencyKey)`; update the class doc.
- [x] `Digest/Process.cls`: drop `STUB`; replace the doc comment with the contract.
  - `OnRequest` takes `Msg.Tick` (Due, then one `Compose` per due session), `Msg.Command.SendDigest` (the key check, one `Compose`, the answer) and `Digest.Msg.Compose`.
  - `OnResponse` finishes a `Compose` whose summary request came back.
  - The private seams `Rows` (Coverage.Build), `Saved`, `SendSummary` (Decide, async), `Cost`, `NeedsYou`, `SendNotice` (Notify) and `SendCompose` (self) are what the tests override.
  - `Parameter MESSAGESENDING` holds exactly the Planner's ruled text (Design Notes, "Ruled text: MESSAGESENDING").
- [x] `Digest/Cost.cls` (new): `Yesterday(sessionRef, now, *sc) As %Numeric`.
- [x] `Digest/NeedsYou.cls` (new, Q4): `List(sessionRef, failedRows, *sc) As %DynamicObject` = `{count, names: [...], more}`, with `NEEDSYOUMAX` = 5, the order, the de-duplication and the bound of the contract.
- [x] `Production.cls` line 60 (lane A region): `Digest` `Enabled="true"` (DW-696).
- [x] `Install/Step/Digest.cls` `Run()`: also seed `digest.time` "08:00" and `digest.channels` "web,phone,telegram" through `Install.Seeds`, from a new `Digest.Process` method `Seeds()`.
- [x] `Msg/Catalog/Watch.cls`: add `digest.cost`, `digest.needsYouMore`, `button.gotIt` and `handled.marked` with the approved texts under Design Notes.
- [x] `Test/Msg/Catalog.cls` (Lane B, the ruled one-time exception, Q2): the four fixture rows and Keys entries; Watch count 50 to 54 and the total 152 to 156, with the U-177 marker on the `Fixtures` XData doc comment ("Contest Planner ruling, 2026-11-06, one-time U-177 exception, Story 17.6") and beside the counts. Fix any web catalog test the keys trip. Report the final count (156 here; the union at the merge).
- [x] `Tools/DigestTools.cls` (new, extends `Tools.Result`): `SendDigest()` with `STEPLABELSENDDIGEST` "Sending your digest", `CLASSIFICATIONSENDDIGEST` safe, `READONLYSENDDIGEST` 0, `TRUSTEDOUTPUTSENDDIGEST` 1; the doc comment is the model-facing description.
  - `Tools/Watching.cls`: add `<Tool Name="send_digest" Class="OcuTalon.Tools.DigestTools" Method="SendDigest"/>`, `DependsOn` it, and extend the description.
  - `Tools/Names.cls` (Q6): append `Parameter DIGESTTOOLS = "send_digest";` with a doc comment ("step 2's digest tool, Story 17.6"); not in `RELEASE1`.
- [x] `Test/Install/SecurityOverview.cls` (Q6, ruled): append the one term `_","_$Parameter("OcuTalon.Tools.Names", "DIGESTTOOLS")` to `released` (:43) and extend the doc (:37). Regenerate `docs/security-overview.md` with `test-security-overview.sh --write`; never hand-edit it.
- [x] `Test/Install/Production.cls` (Q3, ruled): the Digest row `"enabled": 1, "stub": 0` and the doc line :13 ("Story 17.6 built Digest: it is enabled and carries no STUB").
- [x] Lane A tool-list tests (footprint extensions): `Test/Agent/Constants.cls` (13 names, `RELEASE1` still 12), `Test/Agent/Runners.cls` (`send_digest` from `DigestTools` for ChatAgent and its retry), `Test/Agent/Instructions.cls` (seven Watching tools), `Test/Watch/Tools.cls` `TestDeclarations`, `Test/Watch/Turns.cls` :63.
- [x] (Q7, RULED by the orchestrator 2026-11-06) `Test/Tools/Reminders.cls` :275: insert `send_digest` into the sorted tool-name list and extend that assertion's message with "and, since Story 17.6, send_digest"; `Test/Bridge/Gate.cls` `TRUSTEDTOOLS` :117: append the term `OcuTalon.Tools.DigestTools:send_digest` (send_digest is trusted; no veto). Nothing else in either file (Epic 19 makes its own two edits there: a plain union). Condition: `send_digest`'s result holds only the fixed `MESSAGESENDING` text, with no digest content and no names; a fixed-strings test pins the tool result to that text byte for byte (`Test/Digest/Tool.cls`), with the mutation shown. Both files are reported as footprint extensions.
- [x] New `ci/mock/scenarios/A/` files:
  - `digest-summary.json` (marker; a 300-character text);
  - `digest-send-now.json` (marker; `toolUse` `send_digest` `{}`, then a text that claims no delivery).
- [x] `Channel/Telegram/Out.cls`:
  - add `digest` and `handled` to the handled kinds;
  - `Digest(request)` renders and joins the pieces;
  - `GOTITKINDS` = `tellnow` with the Got it keyboard;
  - `EditHandled(request)` follows `EditAnswered`'s pattern.
- [x] `Channel/Telegram/In.cls` `Press`: the `gotit` action, with the checks above, then `Submit`. The approve and reject paths are unchanged.
- [x] Tests (new; Lane A areas; no `ci/units.sh` edit):
  - `Test/Digest/Due.cls`: matrix rows Created before, Created after, Restart catch-up, Queued not yet sent, Requested; the DST day; the lock (a second job holding it: no `Compose`); an ended online-demo session (DW-651's before-and-after tests);
  - `Test/Digest/Compose.cls`: the part order and keys, the cost row, saved, fallback, nothing saved, the 240 cut, 150 words, and `Sent` fields;
  - `Test/Digest/NeedsYou.cls`: matrix rows Needs you order, de-dup and overflow (200 items, 4096 characters);
  - `Test/Digest/Send.cls` (production): web_admin and tool give `ok` and one Notification (`HopsSince` Digest to Notify); the repeat key; the Compose failure in Visual Trace; U-268 (no recipient: `SendDigest`'s properties equal `Msg.Command`'s); the Tick forward (Q1);
  - `Test/Digest/Tool.cls`: the mock marker turn calls `send_digest`, and the tool result the model read is `MESSAGESENDING`;
  - `Test/Channel/TelegramDigest.cls` (LiveCase, mock Telegram): matrix rows Telegram digest, Got it paired and other, Handled.
  - Update `Test/Digest/Contracts.cls` (no stub; and the `Sent` contract in `XData Contracts` gains `IdempotencyKey` `%String(MAXLEN=128)` and its index, and `TestRefCollation` lists `Sent||IdempotencyKey`: the lead's U-268 (3) gate) and `Test/Digest/Thresholds.cls` (the seven seeds).
- [ ] `Test/Bridge/CodeRules.cls` `TOOLVERBS` gains `SendDigest` (NOT DONE: Clarification Needed 1; `Test.Agent.Runners` `TestToolInventory` stays red until it is ruled).

**Acceptance Criteria:**
- Given `digest.time` and a session created before today's time, when the heartbeat's tick passes it, then `Checks` forwards the Tick, `Digest` sends one `Notification` of kind `digest` to `Notify` with the AD-32 Slots, and records one scheduled `Sent` row. Given a session created after it, then none is sent until tomorrow's tick (DW-651).
- Given ticks stopped across `digest.time` for two days, when ticks resume, then exactly one digest goes, and no later tick repeats it, also while its `Compose` waits on Decide.
- Given a digest being composed, when its Slots are filled, then `parts` follow the six-part order above with `Coverage.Build`'s `lines` and `rows`, and the cost sums the session's and `instance`'s Usage of yesterday and never `eval`'s.
- Given failed rows, unhandled tell-now and act Decisions and awaiting incidents, when needs you is composed, then the failed entries come first, then the Decisions newest first, then the incidents; an act Decision of a listed incident appears once; with 200 open items, 5 are named, the overflow line counts the rest, and the Telegram text fits 4096 characters (Q4).
- Given items saved in the window, when the digest is composed, then exactly one `turn` reaches Decide with an untrusted, fresh, unseeded request and the summary is at most 240 characters. Given that request falls back, the digest still goes with `digest.savedNoSummary`, and the fallback is in the Decision row and one log line.
- Given every entry passed and nothing needs the user, when the Telegram text is rendered, then it has at most 150 words.
- Given a chat turn that calls `send_digest`, or Settings' `SendDigest` with origin `web_admin`, when CommandsIn routes it to the enabled `Digest`, then the answer is `ok` at once, the tool result the model reads says the digest is being sent, one digest of kind `requested` goes to `Notify`, and the next window starts at its `SentAt` (DW-696, U-268, Q5 (b)).
- Given the same `IdempotencyKey` twice, when both reach `Digest`, then one digest goes and both answers are `ok` (Q5 (a)). Given a `Compose` that fails, then no digest goes and the failure is on the `Compose`'s header and in its trace session (Q5 (c)).
- Given a kind `digest` Notification sent to `TelegramOut` for the paired chat (the integration AC: Digest is the producer, TelegramOut the consumer, on a real throwaway production with the Telegram mock), when it is delivered, then the paired chat receives one plain-text message as the contract says.
- Given a tell-now message in the paired chat, when the user presses **Got it** there, then one `GotIt` command is submitted with origin `telegram`. Given a press from another chat, nothing is submitted. Given a `handled` notification, then the message is edited in place to "Marked as handled at {time}" with the button removed.

## Spec Change Log

- 2026-11-06 lead: G1, G2 (fixture-only) and the two side edits ruled; the interim route's condition 1 failed (a REST writer of digest.channels exists on feature); the choice is with the Planner; no finalize before it.

- 2026-11-06 lead spec gate: U-268 (3) re-read done: the Sent contract test widened (33-1); the interim digest route before 18.2 recorded as an open question for the orchestrator (33-2, U-268 (1)).

- 2026-11-06 lead: Q7 ruled by the orchestrator (the two one-term edits in Epic 19's files; a fixed-strings pin of the tool result); MESSAGESENDING ruled by the Contest Planner (reworded, exact). Status set to ready-for-dev at the lead's spec gate.

- 2026-11-06 lead: Q1-Q6 and the public text ruled (orchestrator: Q1, Q3, Q6; Contest Planner under the owner's delegation: texts 1-3, Q2, Q4, Q5). Re-plan to fold them in.

## Review Triage Log

## Design Notes

**Rulings on the implement stage's gaps (orchestrator 2026-11-06, confirmed by the Contest Planner; binding):**
- **G1:** append `SendDigest` to `TOOLVERBS` in `Test/Bridge/CodeRules.cls` :109 (one term; Epic 19's diff in that file changes only `CALLBACKHELPERS`: a plain union). Footprint extension.
- **G2, option (c), fixture-only:** in `Test/Checks/Heartbeat.cls` `TestDisabledItemIsReportedOnce` only, the fixture session has no digest due: use the setting the as-built `Digest` reads, preferring the digest off for that fixture session. Its assertions and tick times stay unchanged (Epic 39's hunks there are around :26, :275, :351, :578: a plain union). Options (a) (a change to the ruled due rule) and (b) are rejected. At the integrate-forward after Epic 39 merges, the lead also runs Epic 39's new tick tests (`TestAnHourOfTicks`, `TestBeatNow*`); the same fixture-only fix applies if one hits the digest-due notice; any assertion change is a Clarification. Footprint extension.
- **Side edits CONFIRMED:** `dailyCost` in `SLOTTYPES` of `Test/Msg/Catalog.cls` (Epic 39 edits another hunk, about :120: a plain union); `digest` removed from `Test/Channel/TelegramOut.cls` `TestOtherKinds`, on the condition that a positive test of the digest kind's Telegram message, with Got it, exists and is green. Footprint extensions.
- **Interim digest route:** the Planner kept it on condition that nothing can write `digest.channels` before Story 18.2 (with a fallback test and a never-silently-rerouted test). The lead's check found a writer on the feature branch today (see the lead's report to the orchestrator, 2026-11-06): `POST /v1/settings/daily-digest` (`Web/Api.cls` :165 -> `SaveSection` -> `SettingsOps.Save` -> `SaveProduct` -> `Apply`; the `daily-digest` section maps `channels` to `digest.channels`, `SettingsOps.cls` :624-626, `ALLOWLIST` :52), admin-only; the 1.0.1 page itself shows "This part of OcuTalon isn't built yet." for Daily digest (`settings-page.ts` :65-66). The choice (honour a saved value, or hold kind `digest` until 18.2) is the Planner's. Also: this story's own install step seeds `digest.channels` (uncommitted): under the condition, no installer step may write it, so that seed is dropped unless the ruling says otherwise. **No finalize commit until that ruling is relayed.**

**Lead's spec gate, 2026-11-06: U-268 (3) re-read of the 15 specs that cite AD-1 and AD-14 (an Opus reader; 13 clear).**
- **Decided (in-footprint, lead):** spec-33-1 :126 and :149 pin `Digest.Data.Sent`'s exact properties and indexes in `Test/Digest/Contracts.cls` `XData Contracts` (:97-116). 17.6 appends `IdempotencyKey` and its index, so the task that updates `Test/Digest/Contracts.cls` also adds `"IdempotencyKey": "%String(MAXLEN=128)"` and the new index (for example `"SessionRefKeyIndex": "SessionRef,IdempotencyKey"`, whatever name the code uses) to the `Sent` contract, and `Sent||IdempotencyKey` to `TestRefCollation`'s exact-collation list.
- **Open with the orchestrator (does not block the build):** spec-33-2 :145 and U-268 (1) say the destinations come only from the session's `digest.channels`. Routing kind `digest` by `digest.channels` is Story 18.2's (`Notify`, Lane B, backlog), so until 18.2 lands an enabled `Digest`'s digests take `Notify`'s generic route: the session's own channels (web chat record, phone record in demo mode, the paired Telegram chat). The safety half of U-268 (1) holds (no recipient; only the session's own channels), but the ruled `MESSAGESENDING` wording "to the user's digest channels" is ahead of 18.2. Interim assumption for this build: no `Notify` change; the interim route is stated under Boundaries and Consumed-by (18.2). The lead carries the question to the orchestrator; its answer may add a task.

**Rulings of 2026-11-06 on Q1-Q6 (binding on re-derivation; they answer the open questions below, which stay for the record).**
- **PUBLIC TEXT (Contest Planner under the owner's delegation, exact):** (1) `digest.cost` = `Yesterday's cost: {cost}.` (slot `cost`, type `dailyCost`) APPROVED. (2) `button.gotIt` = `Got it` and `handled.marked` = `Marked as handled at {time}`, verbatim from UX-DR143, APPROVED. (3) the `send_digest` tool's step label `Sending your digest` APPROVED. (4) the overflow line `And {n} more on the OcuTalon page.` APPROVED (Q4 (b)). Any other new user-facing text (for example the Q5 (b) tool result) is PUBLIC TEXT: propose it verbatim under Design Notes; the lead sends it, and nothing that contains it is committed before the answer.
- **Q1 ALLOWED (orchestrator, option 1):** one `DIGEST` parameter and one self-contained `Try` block (`SendRequestAsync(..#DIGEST, tick, 0)`) as the LAST statement of `Checks/Process.cls` `Tick`, before its `Quit $$$OK`, changing no line Epic 39 changed. A test proves a Tick reaches `Digest`. It is a forward, not a heartbeat path: a beat still makes no `BackgroundCheck` row (the 17.5 rule). Epic 39 is expected to merge first: at the lead's integrate-forward after that, the block is re-placed as the final statement of the MERGED `Tick` in the SAME push as the integrate-forward (never a later fix-up), and Checks' Tick tests run green on the merged `Tick`; an exit path that would skip the block, or a placement that needs a behaviour choice, is a Clarification for the lead.
- **Q2 GRANTED (Planner):** the one-time U-177 exception extends to exactly two more fixture rows in Lane B's `Test/Msg/Catalog.cls`, `button.gotIt` and `handled.marked` (count 153 -> 155; the union with Epic 39's count is fine); the Q4 (b) overflow line's key is covered by the same exception if it needs a fixture row (report the final count). No other Lane B line changes. The marker goes on the `Fixtures` XData doc comment, citing "Contest Planner ruling, 2026-11-06, one-time U-177 exception, Story 17.6".
- **Q3 ALLOWED (orchestrator):** the one oracle row in `Test/Install/Production.cls` (Digest `"enabled":1,"stub":0`) and its doc line :13. Epic 19 changes the MemoryOps row of the same file: different rows, a plain union.
- **Q4 APPROVED (Planner, FR-35):** "needs you" lists, in order: (1) the failed non-vital rows; (2) the session's `decide` Decisions with outcome `tellnow` or `act`, not yet handled, newest first; (3) the session's incidents in `awaiting_approval`, named by their code-written `Summary`. Conditions: (a) DE-DUPLICATE: an `act` Decision whose incident is listed as awaiting approval appears once, as the incident. (b) BOUND: the composed digest fits one Telegram message (4096 characters) and the web card without scrolling past it; on overflow keep the newest, drop the oldest, and end the list with the catalog line `And {n} more on the OcuTalon page.`; a test with 200 open items pins it.
- **Q5 ACCEPTED (owner ruling via the Contest Planner, additive AD-18 amendment, marker `[AMENDED 2026-11-06, Story 17.6, owner ruling via the Contest Planner]`):** `SendDigest` answers `ok` at once and `Digest` composes asynchronously; `Digest.Data.Sent` gains `IdempotencyKey` (AD-1's repeat key; an appended property). Conditions: (a) a repeat with the same key sends nothing new (a test); (b) the tool result the model sees says the digest is BEING sent, never that it was sent, so the chat reply never claims delivery (a test on the tool result text; if that text is new it is PUBLIC TEXT, see above); (c) an async compose or send failure is recorded on the existing digest failure path and is visible in Visual Trace (a test); (d) none of AD-18's heartbeat text changes (Epic 39's seven citing specs must still read true). The lead writes the AD-18 amendment into the spine.
- **Q6 ALLOWED (orchestrator, in this shape, which Epic 19 follows too):** a NEW `Tools.Names` parameter for step 2's digest tool (for example `DIGESTTOOLS`, holding `send_digest`); ONE term for it appended to `Test/Install/SecurityOverview.cls`'s expected set (line 37's `released` expression) and its doc line 31 extended; do not rewrite the test to count toolsets. `docs/security-overview.md` is regenerated through `OcuTalon.Install.SecurityOverview`, never hand-edited, and regenerated again after any merge.

**How each ruling is folded in (each with its pinning test and mutation under `## Verification`).**
- Q1: the Tasks item on `Checks/Process.cls`; matrix row "Tick forward"; `Send` `TestTickReachesDigest`. The doc comments of the class and of `Tick` stay as they are (the ruling allows no other line); the new parameter's own doc comment states the forward.
- Q2: the catalog Tasks items; the four keys; counts 54 / 156 in this worktree.
- Q3: the `Test/Install/Production.cls` Tasks item.
- Q4: the "Needs you" contract, `Digest/NeedsYou.cls`, three matrix rows, `Test/Digest/NeedsYou.cls`. The web card half of the bound is Story 18.4's (Consumed-by).
- Q5: the Compose contract, the key check, the answer, the failure path; matrix rows "Repeat key", "Compose fails", "Tool"; the proposed text below. (d): this story edits no spine text.
- Q6: `Names.DIGESTTOOLS`, the one `SecurityOverview` term, the regenerated doc.

**Open questions (the first HALT; Q1-Q6 are ANSWERED by the rulings above).**
- **Q1, contended edit. ANSWERED (Q1 ALLOWED).**
  - Evidence: AD-18 says `Digest` "takes the `Tick` that `Checks` forwards after each tick's checks". But `Checks/Process.cls` `Tick` (:159-189) forwards nothing.
  - The file is Epic 39's: OCT-epic39 rewrote `Tick`'s tail (`BeatRunDue`, `SendOwn`, `AnnounceBeats`), and the project block says "Do not edit `Checks/Process.cls`". The precedent (an append at the end of a file) can't reach a call inside `Tick`, and there is no other path that respects the spine.
  - Recommended: let 17.6 add one `DIGEST` parameter and one self-contained `Try` block (a `SendRequestAsync(..#DIGEST, tick, 0)`) as the last statement of `Tick` before `Quit $$$OK`, with the lead resolving the merge against Epic 39's tail. Or have Epic 39 add it on its branch, or hold 17.6 until Epic 39 merges.
- **Q2, Lane B test beyond the one-time U-177 exception. ANSWERED (Q2 GRANTED).**
  - Evidence: Telegram's **Got it** needs two catalog lines that UX-DR143 fixes ("Got it" and "Marked as handled at {time}"). No key exists for either, and every new key needs a fixture row and a count in Lane B's `Test/Msg/Catalog.cls`. The 2026-11-06 exception covers `digest.cost` only.
  - That file is also changed on OCT-epic39, at :123 (the refused channels), next to the count at :122, so expect a merge conflict.
  - Recommended: extend the exception to `button.gotIt` and `handled.marked` in `Catalog.Watch` (Watch total 53, overall 155 in this worktree). Lane B's 18.4 renders the same keys for the web and phone.
- **Q3, contended test. ANSWERED (Q3 ALLOWED).**
  - Evidence: enabling `Digest` (DW-696) changes the oracle row `{"name":"Digest",...,"enabled":0,"stub":1}` in `Test/Install/Production.cls` :673. `Test/Install/**` is in Epic 19's footprint, though OCT-epic19 has not changed this file.
  - Recommended: allow the one-row edit (`"enabled":1,"stub":0`), plus the class doc line :13.
- **Q4, product scope (observably different readings). ANSWERED (Q4 APPROVED).**
  - Evidence: FR-35 says needs you is "failed checks, and tell-now items the user hasn't yet dealt with by answering its approval request or marking it handled with Got it". The spine does not name the source, the time span, or what counts as a tell-now item that has an approval request.
  - Recommended:
    - The failed non-vital rows' entries first.
    - Then the session's `Decision` rows (kind `decide`, owner the session) with outcome `tellnow` or `act`, whose `Ref` is not `Handled.Marked`, newest first.
    - Then the session's incidents in state `awaiting_approval` (the approval not answered). Each is named by its code-written `Summary`, with no time bound beyond retention (AD-27).
  - Alternatives: only the window's items, or only `tellnow`.
- **Q5, an AD-18 field list and a schema change. ANSWERED (Q5 ACCEPTED; AD-18 amended by the lead).**
  - Evidence: CommandsIn calls the owner synchronously (`Send` :104). A tool's `SendDigest` runs inside a `ChatAgent` turn, and `ChatAgent` has pool size 1. So a digest that makes its summary request inline would wait on `ChatAgent` itself until the timeout.
  - The owner must also "ignore a repeat" key (AD-1), but `Sent` has no field for it.
  - Recommended: `Digest` answers `ok` at once and sends itself a `Compose` message asynchronously ("sends one at once" still holds). Append `IdempotencyKey` to `Sent` (an append-only property; AD-18's Record list amended), and check the key under the per-session lock both at acceptance and in Compose.
- **Q6, contended generated doc and test. ANSWERED (Q6 ALLOWED, in the ruled shape).**
  - Evidence: a new built-in tool adds a row to the generated tools table of `docs/security-overview.md` (changed on OCT-epic39, and in Epic 11's `docs/**`). `Test/Install/SecurityOverview.cls` :37-44 asserts 12 rows = `RELEASE1` (Epic 19's footprint).
  - Recommended: allow regenerating that one table row through `OcuTalon.Install.SecurityOverview`. Change the test to count the tools of `OcuTalon.Tools.*` toolsets, or add a `STEP2` list beside `RELEASE1` that the test also counts.

**Open question of the re-plan (the HALT now).**
- **Q7, two contended tests that every new chat tool trips (blocking; not covered by Q6).**
  - Evidence: any tool offered to the Chat agent changes two exact pins in Epic 19's footprint (`Test/{Tools,Bridge}/**`, contended; OCT-epic19 has not changed either file yet):
    - `Test/Tools/Reminders.cls` :275 asserts the exact sorted tool names of a chat request (`cancel_reminder,...,recent_activity,set_reminder,start_watch,stop_watch`). `send_digest` sorts between `recent_activity` and `set_reminder`. The tool can't avoid it: the pin is on what the Chat request offers, whatever the toolset.
    - `Test/Bridge/Gate.cls` `TRUSTEDTOOLS` :117 must list every built-in tool with `TRUSTEDOUTPUT` 1 (`TestFlagsAreListed` :1347-1365; by design "that edit is the review of its output"). `send_digest`'s output is `CommandCall.Answer`: `ok` plus `Digest`'s fixed message, all code-written, so `TRUSTEDOUTPUT` 1 is the honest flag. 0 would taint every turn that asks for a digest (AD-10) and push the next turn into a fresh session.
  - The rulings name the only edits allowed to contended files, and these two are not among them. A failed `Test.Tools.Reminders` or `Test.Bridge.Gate` would block the story's push.
  - Recommended: allow two one-term edits in Q6's shape, which Epic 19's memory tools will need too: insert `send_digest` in `Reminders.cls` :275's sorted list, and append `OcuTalon.Tools.DigestTools:send_digest` to `Gate.cls` `TRUSTEDTOOLS`. At the merge with Epic 19 these become a plain union of names. Alternative: Epic 19 makes both pins read `Tools.Names` (one edit by the owner of the files), and 17.6 waits for it.

**Rulings that bind this story (recorded, not re-derived).**
- **U-268** (Contest Planner under the owner's delegation, 2026-11-04):
  1. `SendDigest` from origin `tool` or `web_admin` takes no recipient. The destinations come only from the session's `digest.channels`, so neither the model nor an item can choose where a digest goes. A test pins this, with the mutation shown (`Test/Digest/Send.cls` `TestNoRecipient`).
  2. `SendDigest` stays non-risky only because it reaches the session's own channels. Any later external target is a new ruling.
  3. The specs that cite AD-1 and AD-14 are re-read at this story's spec gate; grep alone does not clear them.
- **DW-651** (orchestrator ruling via the Contest Planner, 2026-11-05): build and test AD-18's amended due rule. A session is due when the latest `digest.time` has passed, AND that time is later than the session's `CreatedAt`, AND the session has no scheduled `Sent` row with that `DueAt` or later. The before-and-after tests are in `Test/Digest/Due.cls` (`TestCreatedBefore`, `TestCreatedAfter`). `SendDigest` is unaffected.
- **DW-661 and the U-177 exception** (Contest Planner under the owner's delegation, 2026-11-06; extended by Q2):
  - Add `digest.cost` to `Msg/Catalog/Watch.cls` with the `dailyCost` slot type.
  - The one-time U-177 exception for this story covers the catalog-count test only: `Test/Msg/Catalog.cls` gets the fixture rows of `digest.cost`, `button.gotIt`, `handled.marked` and `digest.needsYouMore`, Watch 50 to 54 and the total 152 to 156, and the U-177 marker on the `Fixtures` XData doc comment.
  - Fix any web catalog test the new keys trip. Nothing else in any Lane B class or test.
  - Note for the lead: the feature branch's count is now 154 (other epics' keys). At the merge the count becomes the union.

**Approved texts (Planner, 2026-11-06), with their entries.**
- `digest.cost`: `Yesterday's cost: {cost}.`, slot `cost` type `dailyCost`. Source: EXPERIENCE.md, Message Catalog / Daily digest / "Every digest (the cost)". With 0.042 it reads "Yesterday's cost: $0.04.".
- `button.gotIt`: `Got it`, no slots. Source: UX-DR143.
- `handled.marked`: `Marked as handled at {time}`, slot `time` type `time`, no full stop. Source: UX-DR143.
- `digest.needsYouMore`: `And {n} more on the OcuTalon page.`, slot `n` type `count`. Source: Contest Planner ruling 2026-11-06, Q4 (b).
- The tool's step label `Sending your digest`.

**Ruled text: MESSAGESENDING (Contest Planner under the owner's delegation, 2026-11-06, a reword of the proposal below; exact):** `The digest is on its way to the user's digest channels. Its delivery is not confirmed yet: tell the user it is on its way, not that it has arrived.`

**Proposed text (for the Planner, superseded by the ruling above): `OcuTalon.Digest.Process` `MESSAGESENDING`** (the `CommandResult.Message` of an accepted `SendDigest`, which the model reads as the tool result through `CommandCall.Answer`; Settings may show it later):
- `The digest is being sent to the session's digest channels now; its delivery is not confirmed.`
- Why new: no existing text says a digest is being sent (searched `src/`). It follows the owners' model-facing style (`ReminderOps` `MESSAGESET` "The reminder is set."). It is true for a first request and for a repeat, and it never claims delivery (Q5 (b)). The ruled text above replaces it; it may be committed.

No other new user-facing text. The mock scenario's final chat text is CI-only fixture text and claims no delivery.

**Governing ADs (Rule 6):** AD-1, AD-3, AD-5, AD-6, AD-8, AD-10, AD-14, AD-18 (as amended 2026-11-05 and 2026-11-06), AD-20, AD-22, AD-26, AD-28, AD-29, AD-30, AD-32 and AD-33. No AC contradicts an AD's Rule.

**Ledger (Rule 17).**
- DW-649 is addressed by the due rule's `Kind` filter and requested `DueAt` "" (matrix "Requested").
- DW-651 is addressed by the due rule and matrix rows "Created before" and "Created after" (`Due` `TestCreatedBefore`, `TestCreatedAfter`).
- DW-661 is addressed by the `digest.cost` key and the catalog test task.
- DW-696 is addressed by enabling the item and the matrix row "Disabled item fixed" (`Send` `TestWebAdminSends`).

**Measured (Task 0; warm `e17s6iw` and fresh `e17s6i`, 2026-11-06).**
- **Self-send inside a synchronous SendDigest.** `Commands.Submit` (origin `web_admin`) on the warm production returned in 6 ms with `Ok` 1 and `Outcome` `sending`. The headers: `CommandsIn->Digest` SendDigest created 13:37:43.772, processed .775; `Digest->Digest` Compose created .774, processed .781; the `CommandResult` header .775; `Digest->Notify` Notification created .780. So CommandsIn had its `ok` before the `Compose` ran, in the one `Digest` job. No contradiction.
- **A `turn` from a `Compose` while a chat turn's `send_digest` is inside CommandsIn.** `Test.Digest.Tool` `TestResultSaysSending` on the fresh stack: one saved item, the marker turn `digest-send-now` calls `send_digest`, the tool returns at once, the chat turn ends, then the summary request runs on the one-job `ChatAgent`; both finish and the digest carries the 240-character summary. The whole test took 7.07 s (its assertion allows 60 s), nowhere near CommandsIn's 120 s. No contradiction.
- **`FromLocal` across a daylight-saving day** (zone America/New_York, `Test.Digest.Due` `TestDaylightSaving`): 08:00 on 2030-03-10 (EDT) is 12:00:00Z and 08:00 on 2030-03-09 (EST) is 13:00:00Z (a 23-hour day); 08:00 on 2030-11-03 (EST) is 13:00:00Z and 08:00 on 2030-11-02 (EDT) is 12:00:00Z (a 25-hour day); the skipped 02:30 on 2030-03-10 is 07:30:00Z. A tick at 07:00 on either change day is due for the day before. No contradiction for these.
- **Observation (inference, not covered by a test).** For the repeated hour, `FromLocal("2030-11-03T01:30:00")` answers `05:30:00Z` (the first instant, as its doc says) when it is the first conversion in the process, but `06:30:00Z` after the same process converted `2030-11-03T08:00:00` (measured in the warm container: a, b, c in one session gave 05:30 each time; the order 08:00 then 01:30 gave 06:30). A `digest.time` inside the repeated hour (01:00 to 01:59 in New York) could therefore give two different `due` values on that one night and one extra digest. Left as it is: `Data.Time` is Base's and the case is one night a year for an unusual setting; reported to the lead.

**Decided in-stage.**
1. **Ended sessions** are as stated in the contract, because the Session row has no end marker.
2. **`{checked}`** is each non-vital entry prefixed "the", joined with ", " and " and " (for example "the Orders production").
3. **`{whatFailed}`** is the vital entries joined the same way, and needs you's `{what}` is the kept names joined with "; ".
4. **The summary request's `SystemNote`** is a fixed, model-facing parameter: "Summarize the saved items in one or two plain sentences. Don't say whether things are fine."
5. **Telegram layout:** one piece per line, coverage lines after the checked part. The UJ-2 sample is prose, and the AC asks for lines that start with their result.
6. **A Got it press** gets an answerCallbackQuery with no text, so it adds no new text.
7. **The cost reads `Usage` directly** (a Lane A read of bridge rows, as `Checks.Process.Fixes` reads `ApprovalRequest`), because `Ownership.RunCost` has no upper bound and excludes `instance`.
8. **The tool goes into the `Watching` toolset,** because `Chat.TOOLSETS` is pinned by contended `Test/Tools/Reminders.cls` :171.
9. **The ruled folds go into the intent block.** The plan stage itself wrote this intent in the first pass, with "pending Qn" markers. The rulings bind, and a ready spec has no pending item, so the rulings are folded into the `<intent-contract>` block as the lead directed. No earlier promise is dropped.
10. **One async path.** Ticks and `SendDigest` both queue a `Compose` to `Digest` itself, and the summary request is async with `OnResponse`. A sync call from `Digest` would block its one job: a second `send_digest` would then wait on `Digest` while `Digest` waits on `ChatAgent`.
11. **A queued `Compose` is the pending marker.** The lock can't span an async reply. So the due check and the key check also read `Compose` bodies (`OcuTalon_Digest_Msg.Compose`, kept until the message purge), and the `Sent` row once written. A `Compose` that failed is not retried for the same `DueAt`; its failure is in Visual Trace. This keeps "never twice" (AD-18).
12. **The failure path (Q5 (c))** is Ensemble's own: the `Compose` handling's error status, on its header and as an Error entry in its trace session. No user notice, because that would need new text.
13. **The window is fixed at queue time** (`WindowStart`, `WindowEnd` on the `Compose`), so the count and the summary cover the same items.
14. **Needs you, names and bound.** A failed row is `<entry>: <finding>`. An incident is named by its diagnose Decision's code-written `Summary`, because `Incident` has no `Summary` column. `NEEDSYOUMAX` = 5 bounds the list (an implementation size). The overflow line is its own part, right after the needs-you part, and `count` is the total. `Ownership.Decisions` is read with `max` 1000. An older unhandled Decision past that is not counted (inference: rare inside retention).
15. **De-duplication link.** A Decision matches an incident by `Ref` = `Incident.DecisionRef` or `ItemId` = `Incident.Ref`, the only stored links. A decide Decision and an incident have no other link.
16. **`handled.marked`'s time** is `Handled.Marked(ref)`. A `handled` notification with no marker, or with no `Delivery` row, edits nothing and logs one warning.
17. **`Names.DIGESTTOOLS` holds the name itself** (`"send_digest"`). A second parameter with the same value would fail `constants.test.mjs`'s "distinct" check, and the code reads the name through `DIGESTTOOLS`.
18. **`Sent.IdempotencyKey` is `MAXLEN = 128`**, the same as `Msg.Command`'s (the first plan's 64 was too short).
19. **`CommandResult.Outcome` is `sending`** for an accepted request and for a repeat (free text, like `ReminderOps`' outcomes; no `Msg.Enum` change).
20. **`whatFailed` on the two failing Render keys.** The contract says `Render`'s key goes in "with `{}`", but `checks.notEverything` and `checks.notEverythingRestPassed` declare the slot `whatFailed` and a render with `{}` is refused ("the slot is missing"). So those two keys carry `{"whatFailed": <the entries of the non-vital rows that did not pass, joined as in 2 and 3>}` and every other key carries `{}`.
21. **A Compose that is already answered sends nothing.** `Composed` first checks the `Sent` rows: a Compose whose `IdempotencyKey` is held by a `Sent` row, or a scheduled one whose `DueAt` is covered by a scheduled `Sent` row, ends OK with no Notification (the acceptance key check and the due check stay the first gate; this is the second, per Q5).
22. **A needs-you entry with no name is left out** (a Decision with an empty `Summary`); it is not counted.
23. **`SendDigest` for an unknown session, or when the session's lock is not free in `LOCKSECONDS`, returns an error status.** CommandsIn answers `failed` with its own existing text, so no new text is needed; a scheduled tick that cannot take the lock logs one warning and tries again at the next tick.
24. **The window of a scheduled digest ends at the time its `Compose` is queued (the clock), not at `tickAt`,** and the greeting hour and yesterday's cost use that `WindowEnd`.
25. **The handled edit records a `Delivery` row of kind `handled`** with the same message id and `DecisionRef` and the text "", so a repeated `handled` notification edits nothing (the first edit stays), like `answered`.
26. **`Test/Msg/Catalog.cls` also gains `dailyCost` in its `SLOTTYPES` list and in the negative-amount branch of its refusal checks.** The ruled fixture row for `digest.cost` cannot pass `TestEntries` without it (a Lane B test line beyond the four rows; reported).
27. **`Test/Channel/TelegramOut.cls` `TestOtherKinds` no longer lists `digest`** among the kinds that send nothing (Lane A test; the kind is now sent).
28. **New test helpers:** `Test/Digest/ProcessProbe.cls` (the seams of `Digest.Process` under test control), `FailRowsDigest.cls` (a Digest whose `Rows` seam fails, put behind the item by `Send`) and `TickProbe.cls` (a `Test.Checks.Probe` whose send to Digest is under test control; no existing `Test/Checks/**` file is edited).
29. **`TestRepeatKey` also counts the `Compose` requests that Digest sent to itself.** The second gate (21) would otherwise hide a missing acceptance check, because a repeated `Compose` is dropped later; "nothing new is queued" is asserted directly.

**Contention (Rule 11) and allowed edits.**
- Ruled edits to contended files: `Checks/Process.cls` (Q1), `Test/Install/Production.cls` (Q3), `Test/Install/SecurityOverview.cls` and `docs/security-overview.md` (Q6), `Test/Msg/Catalog.cls` (Q2, Lane B). `Test/Msg/Catalog.cls` and `docs/security-overview.md` are also changed on OCT-epic39, so the lead resolves them at the merge (the doc by regenerating it).
- Q7 ruled: `Test/Tools/Reminders.cls` (one name in the sorted list, the message extended), `Test/Bridge/Gate.cls` (one `TRUSTEDTOOLS` term); footprint extensions.
- `Tools/Names.cls`: a one-name append. `ci/mock/scenarios/A/`: new files only.
- Not touched: `Checks/Beat.cls`, `Core/**`, `Data/Ownership.cls`, `Msg/Enum.cls`, `ci/units.sh`, `src/short-names.tsv`, `Test/Checks/**`, the spine.
- Footprint extensions (outside the paths_hint, not contended): `Production.cls`, `Test/Agent/{Constants,Runners,Instructions}.cls`, `Test/Watch/Tools.cls`, `Test/Watch/Turns.cls`, `Test/Channel/TelegramDigest.cls`.
- New storage: `Digest.Msg.Compose` is a message class. Its global name comes from the compiler's default for message bodies, so it needs no `src/short-names.tsv` row (inference: `test-storage.sh` decides; a refusal there is a Clarification, never an edit to the contended TSV).

**Story 30.7 check.** Nothing here changes the purges, approvals, `Reconcile`, `Bridge.Redact`, `Test.Eval.KeyProof` or `list_productions`. TelegramIn's approve and reject path is left as it is.

**Extend, don't copy (Rule 2).**
- `Compose`'s summary request follows `Intake.RequestFor`; its async send and `OnResponse` follow `Intake.Send` / `OnResponse`.
- `EditHandled` follows `EditAnswered`.
- `DigestTools.SendDigest` follows `ReminderTools.SetReminder`; `MESSAGESENDING` follows `ReminderOps`' messages.
- Needs you reads `Ownership.Decisions` and `Ownership.Incidents` and `Handled.Marked`; it copies no query.
- The seeds go through `Install.Seeds`.
- The cost sum is new (no ranged sibling exists).

**Integration ACs (Rule 1):** the TelegramOut AC above. `Digest` (the producer) and `TelegramOut` (the consumer) run in one real throwaway production. Also the Tick forward: `Checks` (producer) to `Digest` (consumer), `Send` `TestTickReachesDigest`.

**Consumes:**
- 17.5: `Coverage.Build` rows, lines and vitals, and the seeds step;
- 33.1 and 33.2: `Sent`, the keys, `dailyCost`, `SendDigest`, `GotIt`, `Handled`;
- 12.x: TelegramOut and TelegramIn;
- Epic 39's `Tick` in `Checks` (Q1).

**Consumed-by:**
- 17.7: the composition, for the all-clear rules and the eval cases;
- 18.2: `Notify`'s routing of kind `digest`, and Settings' `SendDigest` (which may show `MESSAGESENDING`);
- 18.4: the web and phone copies, the Got it writer (which sends `handled`), and Q4 (b)'s web-card half of the bound (at most 5 named needs-you entries plus the overflow line);
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
  - `OcuTalon.Test.Digest.Due`, `.Compose`, `.NeedsYou`, `.Send`, `.Tool`, `.Contracts`, `.Thresholds`;
  - `OcuTalon.Test.Channel.TelegramDigest`, `OcuTalon.Test.Channel.TelegramOut`, `OcuTalon.Test.Channel.TelegramApproval`;
  - `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Watch.Tools`, `OcuTalon.Test.Watch.Turns`, `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Install.SecurityOverview`;
  - `OcuTalon.Test.Agent.Constants`, `OcuTalon.Test.Agent.Runners`, `OcuTalon.Test.Agent.Instructions`, `OcuTalon.Test.Tools.Reminders`, `OcuTalon.Test.Bridge.Gate`;
  - the Tick regressions: `OcuTalon.Test.Checks.Heartbeat`, `OcuTalon.Test.Checks.Runs`, `OcuTalon.Test.Schedule.Heartbeat`, `OcuTalon.Test.Digest.Runs`.
- (once) `bash docker/tests/test-security-overview.sh --write` (writes the doc), then `bash docker/tests/test-security-overview.sh`: passes.
- (once) `bash docker/tests/test-mock.sh`, then `test-class-rules.sh`, `test-boundaries.sh`, `test-storage.sh` and `test-ci-config.sh`, one per call: each passes.
- (once) `cd web && node --test scripts/catalog.test.mjs`: passes.
- (once) Fresh, `OCUTALON_RUN_TAG=e17s6i`, one per call:
  - `ci/iris.sh live production`, then `live install-start`;
  - `shard lane-a@Checks,Install,Watch` and `shard lane-a@rest`, with `--part k/n` so that each call stays under about 8 minutes;
  - `ci/iris.sh teardown`.

**Shared surfaces:**
- the production item list (`Test.Install.Production` oracle, `test-production.sh` rows 14 and 16);
- the catalog key count and Keys list (`Test.Msg.Catalog`, the web catalog tests);
- `Tools.Names` (`Test.Agent.Constants`, `ci/mock/test/constants.test.mjs`);
- the Chat agent's tool list (`Test.Watch.Tools`, `Test.Watch.Turns`, `Test.Agent.Runners`, `Test.Agent.Instructions`, `Test.Tools.Reminders`, `Test.Bridge.Gate` `TRUSTEDTOOLS`);
- the security overview's tools table (`Test.Install.SecurityOverview`, `docs/security-overview.md`);
- the `Data.Setting` rows `digest.time` and `digest.channels`;
- the `Sent` rows and `Compose` bodies;
- the Tick's downstream hops: a real Tick now also sends one `Tick` to `Digest`, and a session alive across `digest.time` gets a digest (the `Test.Checks` and `Test.Schedule` tick tests, and the mock-log request counts of Epic 39's heartbeat tests after the merge).

Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19), applied and observed in the implement pass; each reverted, the tree checked byte-identical (a hash of `git diff` and the untracked files before and after):**
- mutation: the `CreatedAt` clause removed from `Process.Ticked`: `Due` `TestCreatedAfter` red (DW-651; "a session created after today's time gets none today").
- mutation: `>=` made `>` in the scheduled lookup of `Process.Covered`: `Due` `TestCatchUpOnce` red (and `TestCreatedBefore`).
- mutation: the `Compose` lookup removed from `Process.Covered`: `Due` `TestQueuedNotRepeated` red (and `TestCatchUpOnce`, `TestCreatedBefore`).
- mutation: the `Try` block removed from `Checks.Tick`: `Send` `TestTickReachesDigest` red (Q1; and `TestTickForwardFails`).
- mutation: the cost includes `eval` (`OwnerRef IN (?, ?, 'eval')`): `Compose` `TestCost` red.
- mutation: the part order swapped (the saved part before needs you): `Compose` `TestPartOrder` red (and `TestNeedsYouParts`).
- mutation: Decisions listed before the failed rows: `NeedsYou` `TestOrder` red (Q4; and `TestOverflow`).
- mutation: the de-duplication removed: `NeedsYou` `TestActIncidentOnce` red (Q4 (a)).
- mutation: `NEEDSYOUMAX` ignored (`If 1` in `Bound`): `NeedsYou` `TestOverflow` and `TestOverflow200` red (Q4 (b); `Compose` `TestNeedsYouParts` too).
- mutation: the `Handled.Marked` filter removed: `NeedsYou` `TestHandledLeftOut` red (and `TestOrder`).
- mutation: the 240 cut removed: `Compose` `TestSummaryCut` red.
- mutation: the fallback ignored (`If 0` for `answer.Fallback`): `Compose` `TestSummaryFallback` red.
- mutation: `Enabled="false"` restored for `Digest` in `Production.cls`: `Send` red on the fresh stack (every SendDigest fails: `TestComposeFailureInTrace`, `TestRepeatKey`, `TestSavedFallback` and the others lose "Ok at once, sending", DW-696; the run took 1412 s because every test waits for the item, so `TestWebAdminSends`, the first of the class by name, was cut off the capped failure print: it makes the same first assertion). The warm `Install.Production` oracle row pins it too.
- mutation: the key check removed (`If 1` in `Requested`): `Send` `TestRepeatKey` red (Q5 (a)); only its Compose count sees it, because the second gate drops the repeated `Compose` later.
- mutation: `MESSAGESENDING` changed to "The digest was sent.": `Tool` `TestFixedText` and `TestResultSaysSending` red (Q5 (b), Q7 fixed-strings pin; fresh stack).
- mutation: the `Compose` handling made to return OK on a seam error (`Quit $$$OK` after `Rows`): `Compose` `TestFailurePath` and `Send` `TestComposeFailureInTrace` red (Q5 (c)).
- mutation: a `Channel` property added to `SendDigest`: `Send` `TestNoRecipient` red (U-268).
- mutation: `send_digest` removed from `Watching`: `SecurityOverview` `TestToolRows` and `Watch.Tools` `TestDeclarations` red (Q6).
- mutation: `parse_mode` added to `sendMessage`: `TelegramDigest` `TestDigestMessage` red (`TestPlainText` of the plan).
- mutation: the paired-chat check (the chat of the row's message id) dropped from `In.GotIt`: `TelegramDigest` `TestGotItOtherChat` red.
- mutation: `reply_markup` kept on the handled edit: `TelegramDigest` `TestHandledEdit` red.

## Clarification Needed

1. **intent gap: `Test/Bridge/CodeRules.cls` `TOOLVERBS` must name `SendDigest`.** `Test.Agent.Runners` `TestToolInventory` runs `CodeRules.ToolCodeClean` over every tool class, and it refuses `DigestTools` ("names the command class SendDigest, which is not a tool verb"), because `TOOLVERBS` (line 109) lists only `SetReminder,ListReminders,CancelReminder,StartWatch,StopWatch,Dismiss`. `CommandsIn` `TOOLVERBS` already allows `SendDigest` from origin `tool` (AD-1). The file is Epic 19's (`OCT-epic19` changes it) and no ruling names it, so it is not edited and `TestToolInventory` is red for `ChatAgent` and `ChatAgentRetry`. Recommended resolution: a Q7-shaped one-term edit, appending `SendDigest` to `TOOLVERBS` and extending its doc line, reported as a footprint extension (a plain union with Epic 19's memory verbs at the merge).
2. **intent gap: the Tick forward makes `Test.Checks.Heartbeat` `TestDisabledItemIsReportedOnce` red.** Epic 30/39's tests send ticks `AHEADSECONDS` (a day) into the future (`Test.Watch.Case` `Ahead`). With the forward, `Digest` takes the due rule at `tickAt`, finds the fixture session created before tomorrow's `digest.time`, and sends it a scheduled digest. The session's web chat then holds two notices where the test asserts one ("the session's web chat got one notification"). Every other Checks, Watch, Digest, Agent, Tools and `Schedule.Heartbeat` class passed on the fresh stack. The test is Epic 39's contended file and no ruling covers it. Recommended resolution: the due rule uses the earlier of `tickAt` and the clock (a tick from the future cannot make a digest due before its time; real heartbeat ticks are taken at the clock, so nothing else changes), with a clock seam in `Digest.Process` so that `Test.Digest.Due` keeps its 2030 times; or the lead has Epic 39 move its ticks to a time that crosses no `digest.time`. Not implemented here, because it changes the ruled due rule.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: (1) Test/Bridge/CodeRules.cls TOOLVERBS must name SendDigest (Test.Agent.Runners TestToolInventory red for ChatAgent and ChatAgentRetry; a contended Epic 19 file with no ruling); (2) the Tick forward makes Epic 39's Test.Checks.Heartbeat TestDisabledItemIsReportedOnce red (ticks a day ahead make the fixture session due; the fix changes the ruled due rule or Epic 39's test). Both are written up with recommended resolutions under Clarification Needed. The implementation, tests and mutation lines are in the working tree, uncommitted; no finalize commit was made.
