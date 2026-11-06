---
title: 'Story 17.6: Send the daily digest at the set time and on request'
type: 'feature'
created: '2026-11-06'
status: 'done'
baseline_revision: '566c9e64ef4f4a9e22168f0ec4ec52682802941f'
baseline_commit: '566c9e64ef4f4a9e22168f0ec4ec52682802941f'
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
- [x] `Install/Step/Digest.cls` `Run()`: also seed `digest.time` "08:00" through `Install.Seeds`, from a new `Digest.Process` method `Seeds()` (`digest.channels` is not seeded: ruled 2026-11-06, option (a)).
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
- [x] `Test/Bridge/CodeRules.cls` `TOOLVERBS` gains `SendDigest` (G1, ruled 2026-11-06; Clarification Needed 1 is answered by it; `Test.Agent.Runners` `TestToolInventory` is green).

- [x] Rulings of 2026-11-06 after the first implement pass (Design Notes): G1 `TOOLVERBS` append in `Test/Bridge/CodeRules.cls` :109; G2 the fixture-only edit in `Test/Checks/Heartbeat.cls` `TestDisabledItemIsReportedOnce` (its session has no digest due, preferring the digest off for it; assertions and tick times unchanged); keep the two confirmed side edits (`SLOTTYPES` `dailyCost`; `TestOtherKinds` without `digest`, with a green positive digest-kind Telegram test that includes Got it); the digest routing filter of option (a) with its four tests and the fixed-strings pin of the reachability failure text; drop the `digest.channels` install seed.
  - G1: `SendDigest` appended to `TOOLVERBS` (one term, and its doc line).
  - G2: one line in `TestDisabledItemIsReportedOnce`: the fixture session's `CreatedAt` is set to `2999-01-01T00:00:00Z`, so `Digest` finds no digest due for it (DW-651's "created after" rule); see Decided in-stage 30.
  - Side edits kept: `dailyCost` in `SLOTTYPES`; `TestOtherKinds` without `digest`; the positive tests are `TelegramDigest` `TestDigestMessage` (the digest-kind message) and `TestGotItButton`, `TestGotItPairedChat` (Got it), all green.
  - Routing filter (`Digest.Process`: `Own`, `Named`, `Channels`, `Deliver`, the `MESSAGENOCHANNEL` parameter) with `Test.Digest.Compose` `TestRouteOwn`, `TestRouteSubset`, `TestRouteNoneReachable` (which also pins the text byte for byte) and `TestRouteForeign`, plus `TestOwnChannels`.
  - The `digest.channels` seed is gone from `Digest.Process.Seeds`; `Test.Digest.Thresholds` `TestDigestSeeds` expects `digest.time` alone and no `digest.channels` row.

- [x] Review patches, part A (code and test fixes; triage of 2026-11-06, see `## Review Triage Log`; each fix is the smallest one, each behaviour change gets a pinning test and a `mutation:` line in `## Verification` per Rule 19):
  - PA1 `Digest/NeedsYou.cls` :58: `$Data(owned("item", decision.ItemId))` throws `<SUBSCRIPT>` when `decision.ItemId` is empty: test `decision.ItemId '= ""` first. `Bound` (:95): `Set byTime($List(entries(i), 2), i)` throws on an empty entry time: index an empty time under a placeholder that sorts before every real time (for example `" "`), so the entry counts as the oldest. Two tests in `Test/Digest/NeedsYou.cls` (a Decision with an empty `ItemId`; more than `NEEDSYOUMAX` entries including one with an empty time), each with a mutation.
  - PA2 `Digest/Process.cls` `Finish` (`row.AllClear`): a stored `AllClear` 1 must also require that all five vital rows passed and that nothing needs the user (`needs.count = 0`), not `CatalogKey` alone (a failed vital sign or an open needs-you entry with all non-vital rows passed must give `AllClear` 0: no false all-clear). Test in `Test/Digest/Compose.cls` (`TestSentRow` or a new test) and a mutation.
  - PA3 `Digest.Process` `ITEMS` (the per-channel delivery path of the narrowed route is never run against the real production): add a test that each name in `ITEMS` is an item of `OcuTalon.Production` (read the production's item list the way `Test.Install.Production` does), with a mutation (rename one `ITEMS` name: red).
  - PA4 doc comments: `Test/Channel/TelegramDigest.cls` header says "200 open items" and "And 195 more" while `TestQuietAndLimits` makes 201 entries and asserts "And 196 more": correct the header to what the test does. `Msg/Catalog/Watch.cls` header comment still says `digest.cost` waits for the `dailyCost` slot type: correct it, and mention `button.gotIt`, `handled.marked` and `digest.needsYouMore` (comments state the contract only, ASCII).
  - PA5 `Test/Digest/Compose.cls` `TestSummaryFallback`, case `error|unusable`: assert that `OnError(...)` for the summary call returns OK (the framework runs `OnResponse` only then), with a mutation (`OnError` returns `pErrorStatus` unchanged: red).
  - PA6 hermeticity and weak assertions:
    - Digest tests that run the real `Channels()` (`Test/Digest/Due.cls`, `Compose.cls`, `Send.cls`, and any other Digest test class that sends) must create the state they need: remove any saved `digest.channels` row in their setup (and restore what they found), so a leftover row cannot fail them with the reachability text.
    - `Test/Digest/Send.cls` `Composes(mark)` counts every Compose header after the mark: count only those of the test's session (`TestRepeatKey`, `TestComposeFailureInTrace`). `TestRepeatKey`'s fixed `Hang 2` before the "nothing queued" count: wait for the stable state with a bounded poll instead (or assert on the Compose count directly), never a bare sleep alone.
    - `Test/Digest/Compose.cls` `TestOwnChannels` restores `^OcuTalonTest("TelegramIncluded")` and demo mode on the straight-line path only: restore in `OnAfterOneTest` or a `Try`/`Catch`.
    - `Test/Channel/TelegramDigest.cls` `TestDigestMessage` expects "Yesterday's cost: $0.04." from its own session Usage row but `Cost.Yesterday` also sums every `instance` Usage row of yesterday: make the expectation independent of other rows (compute the instance part in the test, or have the test own the `instance` rows of that window and restore them).
    - `Test/Digest/Due.cls` ~:171 (`+$Get(^||DigestProbe("summary")) = 0`, "which has asked nobody yet") cannot fail: make it observable or delete it. `Compose.cls` `TestRouteNoneReachable` (second and third calls) and `TestRouteForeign` (cases 2 and 4) must assert the error text is `MESSAGENOCHANNEL`, not only `StatusNotOK`. `TestSummaryFallback`, `send` case: assert `Sent.ItemId` is empty for a failed summary send.
  - PA7 `Test/Digest/Due.cls` `TestLock`: add the variant in which the lock holder writes a covering `Sent` row (or `Compose` body) before it releases, and the tick then queues nothing (the re-check under the lock), with a mutation (line `If '..Covered(...) Set sc = ..Queue(...)` made unconditional: red). If `ProcessProbe.Hold` cannot do it without a large change, say so in the spec and the report instead.
- [x] Review patches, part B (Rule 19 `mutation:` lines for pinning tests that have none; no production-code change; strengthen a test only when its mutation survives): for each, apply the named mutation (back up the file in the scratch folder first), run the named class, observe red, restore, check the tree is byte-identical, and write one `mutation:` line in `## Verification` under "Mutations, second review pass": (1) AC5 request shape (`Provenance` "untrusted" to "user" or `SessionMode` "fresh" to another value in `SummaryRequest`: `Compose` `TestSavedSummary`, `Send` `TestSavedSummaryThroughDecide`); (2) nothing saved asks nobody (always make the summary request: `TestNothingSaved`, `Send` `TestNothingSavedNoRequest`); (3) AC5 log line (drop the `$$$LOGINFO` of the fallback: `TestSummaryFallback`, `Send` `TestSavedFallback`); (4) AC6 150 words (add a long extra part, for example the coverage lines twice: `Compose` `TestQuietDay`, `TelegramDigest` `TestQuietAndLimits`); (5) AC3 parts (greeting band edge: `TestGreeting`; `digest.vitalsNotAll` never chosen: `TestVitalsNotAll`; the nothing-watched part: `TestNothingWatched` or its equivalent; `checkedQuiet` versus `checked`; `AllClear` set from `CatalogKey` alone: `TestSentRow` after PA2; the cost window edge, for example [yesterday 00:00, today 00:00) widened by an hour: `TestCost`); (6) AC4 4096 (the existing `NEEDSYOUMAX` mutation also run on `TelegramDigest` `TestQuietAndLimits`, name it in that line); (7) AC7 and DW-649 (the window ignores a requested `Sent`: `Due` `TestRequestedAndScheduled`; a requested `DueAt` filled with `due`: same test); (8) AC1 `Due` (the per-session lock removed: `TestLock`; the ended-session check removed: `TestEndedOnlineDemo`; `FromLocal` replaced by a UTC reading: `TestDaylightSaving`; an unreadable `digest.time` not defaulting to 08:00: `TestBadTime`); (9) AC10 (the Got it button dropped from the keyboard: `TestGotItButton`; the `Pairing.Chat` check dropped, the `Delivery`-row-exists check dropped, the `IsRef` check dropped in `In.GotIt`: `TestGotItPairedChat` and `TestGotItOtherChat`; the first handled edit not kept, that is the `row.Kind = "handled"` quit dropped: `TestHandledEdit`; the no-marker warning dropped: `TestHandledEdit`); (10) the Telegram layout (`AFTERLINES` placement of the coverage lines moved: `TestDigestMessage`). A mutation that survives means the test is weak: strengthen it, rerun it red, and say so.

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

- 2026-11-06 lead: the Planner ruled option (a) for the digest routing until 18.2 (a narrowing filter; the reachability failure text; four tests; no install seed of digest.channels); spec-33-2 :145 amended; status set to in-progress for the implement re-dispatch on the held tree.

- 2026-11-06 lead: G1, G2 (fixture-only) and the two side edits ruled; the interim route's condition 1 failed (a REST writer of digest.channels exists on feature); the choice is with the Planner; no finalize before it.

- 2026-11-06 lead spec gate: U-268 (3) re-read done: the Sent contract test widened (33-1); the interim digest route before 18.2 recorded as an open question for the orchestrator (33-2, U-268 (1)).

- 2026-11-06 lead: Q7 ruled by the orchestrator (the two one-term edits in Epic 19's files; a fixed-strings pin of the tool result); MESSAGESENDING ruled by the Contest Planner (reworded, exact). Status set to ready-for-dev at the lead's spec gate.

- 2026-11-06 lead: Q1-Q6 and the public text ruled (orchestrator: Q1, Q3, Q6; Contest Planner under the owner's delegation: texts 1-3, Q2, Q4, Q5). Re-plan to fold them in.

## Review Triage Log

### 2026-11-06 - Review pass 1 (second implement pass)
- verdicts: 51 findings - high 0, medium 1, low 42, false 5, maybe-false 3
- findings (BH = blind hunter, EC = edge-case hunter, VG = verification gap, IA = intent alignment):
  - `[low]` `[reject]` BH1 the next window starts at `SentAt`, so items recorded between `WindowEnd` and `SentAt` (the Decide wait) are in no digest (also EC7, VG other) - real, but seconds wide, and the fix changes what `SentAt` means or adds a column, which the contract (window rule, AC "next window starts at its SentAt") fixes; rejected as a rare low, listed under residual risks.
  - `[low]` `[reject]` BH2 a failed scheduled Compose is not retried that day (also EC9) - Decided in-stage 11 states it; the fix edits the spec.
  - `[low]` `[patch]` BH3 `NeedsYou.Bound` null subscript on an empty time (also EC2) - patch PA1.
  - `[low]` `[patch]` BH4 the narrowed route's per-channel sends never run against the production (also VG4) - patch PA3.
  - `[low]` `[reject]` BH5 no volume limit on `send_digest` - not in the intent; no harm shown beyond the per-turn tool caps.
  - `[low]` `[reject]` BH6 the Heartbeat fix is a one-test workaround - ruled (G2, option c); the Checks shard passed on a fresh stack; Epic 39's new tick tests are the lead's integrate-forward check.
  - `[low]` `[reject]` BH7 `Ticked` queries every session each tick - small tables; the index fix is a storage change for no shown harm.
  - `[low]` `[patch]` BH8 `TelegramDigest` header says 195, test asserts 196 - patch PA4.
  - `[low]` `[patch]` BH9 `Catalog/Watch.cls` header comment is stale - patch PA4.
  - `[low]` `[patch]` BH10 `TestRepeatKey` fixed `Hang 2` - patch PA6.
  - `[low]` `[patch]` EC1 `NeedsYou.cls` :58 null subscript on an empty `ItemId` - patch PA1.
  - `[low]` `[patch]` EC2 see BH3 - patch PA1.
  - `[low]` `[reject]` EC3 a name of invisible characters only - names are code-written summaries; no path shown.
  - `[low]` `[reject]` EC4 a model summary of invisible characters only - the guard filters the reply; extreme; the fix adds a branch.
  - `[low]` `[reject]` EC5 `Finish` does not render the parts - slots are code-built and typed; a render error is the matrix's "nothing sent".
  - `[low]` `[reject]` EC6 a later channel send fails after an earlier one went - needs the queueing call to fail; rare.
  - `[low]` `[reject]` EC7 see BH1.
  - `[low]` `[reject]` EC8 a scheduled and a requested Compose queued before either is sent share a window - narrow; Decided in-stage 13 fixes the window at queue time.
  - `[low]` `[reject]` EC9 see BH2.
  - `[low]` `[reject]` EC10 a failed requested Compose still holds its key - Q5 (a) and Decided in-stage 11.
  - `[low]` `[reject]` EC11 a cost failure discards the digest - the contract's failure path (a seam's error status).
  - `[medium]` `[patch]` EC12 `AllClear` set from `CatalogKey` alone is 1 for a digest whose vital sign failed or that has open needs-you entries (a stored false all-clear) - patch PA2.
  - `[maybe-false]` `[reject]` EC13 an empty `CatalogKey` when `Render` returns "" for watched rows - needs malformed rows from `Coverage.Build`; the if-true harm is low (a missing sentence).
  - `[maybe-false]` `[reject]` EC14 empty vital rows give an empty `whatFailed` - `Build` always returns the five vital rows; the if-true harm is low.
  - `[maybe-false]` `[reject]` EC15 a passed vital row with an empty figure reads 0 - `Build`'s contract (Story 17.5); the if-true harm is low.
  - `[low]` `[reject]` EC16 no timeout on the summary call - Decide always answers (its own fallback); `Intake.Send` is the same pattern.
  - `[low]` `[reject]` EC17 a handled edit with an empty stored text - Decided in-stage 16: one warning, nothing edited.
  - `[low]` `[reject]` EC18 repeated Got it presses submit again - the writer and its idempotency are Story 18.4's (Lane B).
  - `[low]` `[reject]` EC19 a digest over 4096 characters splits - bounded by `NEEDSYOUMAX`; the 200-item test passes; no shown way to exceed.
  - `[low]` `[reject]` EC20 claim: 150 words with many rows - the AC is pinned for the matrix's quiet day.
  - `[low]` `[reject]` EC21 claim: partial delivery on a failed Compose - see EC6.
  - `[low]` `[patch]` VG1 `OnError`'s return is not asserted - patch PA5.
  - `[low]` `[patch]` VG2 the re-check under the lock is not pinned - patch PA7.
  - `[low]` `[reject]` VG3 unknown-session and busy-lock answers are untested - Decided in-stage 23, no AC.
  - `[low]` `[patch]` VG4 see BH4 - patch PA3.
  - `[low]` `[patch]` VG5 ACs whose pinning tests have no `mutation:` line - patch, part B.
  - `[low]` `[patch]` VG6a tests rely on `digest.channels` being unset - patch PA6.
  - `[low]` `[patch]` VG6b `TestDigestMessage` cost depends on other Usage rows - patch PA6.
  - `[low]` `[patch]` VG6c `Composes(mark)` counts other sessions' Composes - patch PA6.
  - `[low]` `[patch]` VG6d `TestOwnChannels` restores state on the straight path only - patch PA6.
  - `[low]` `[patch]` VG7a `Due.cls` ~:171 assertion cannot fail - patch PA6.
  - `[low]` `[patch]` VG7b `Route*` asserts do not check the error text - patch PA6.
  - `[low]` `[patch]` VG7c `Sent.ItemId` empty on a failed send is not asserted - patch PA6.
  - `[low]` `[reject]` VG other 1 see BH1.
  - `[low]` `[reject]` VG other 2 other tick-sending tests are unverified - see BH6.
  - `[false]` `[reject]` IA1 `Digest` reads `digest.channels` and sends to channel items - ruled by the Contest Planner, 2026-11-06, option (a) (Design Notes); no `Notify` edit exists, so a subset needs this.
  - `[false]` `[reject]` IA2 slots on the checked part - Decided in-stage 20: the catalog refuses `{}` for those keys.
  - `[false]` `[reject]` IA3 the literal `checks.nothingWatched` - `Checks.Render.Render([])` returns that same key (`Render.cls` :27, :58).
  - `[false]` `[reject]` IA4 contended-file edits beyond the "Never" list - each is ruled (G1, G2, Q1 to Q7, Q2).
  - `[low]` `[reject]` IA5 most matrix rows are asserted on a shadow instance - the live rows (`Send`, `Tool`, `TelegramDigest`) ran on fresh stacks in this pass.
  - `[false]` `[reject]` IA6 CommandsIn routing of `SendDigest` to `Digest` is not in the diff - `CommandsIn` :179 routes it already; the live `Send` tests pass.

## Design Notes

**Rulings on the implement stage's gaps (orchestrator 2026-11-06, confirmed by the Contest Planner; binding):**
- **G1:** append `SendDigest` to `TOOLVERBS` in `Test/Bridge/CodeRules.cls` :109 (one term; Epic 19's diff in that file changes only `CALLBACKHELPERS`: a plain union). Footprint extension.
- **G2, option (c), fixture-only:** in `Test/Checks/Heartbeat.cls` `TestDisabledItemIsReportedOnce` only, the fixture session has no digest due: use the setting the as-built `Digest` reads, preferring the digest off for that fixture session. Its assertions and tick times stay unchanged (Epic 39's hunks there are around :26, :275, :351, :578: a plain union). Options (a) (a change to the ruled due rule) and (b) are rejected. At the integrate-forward after Epic 39 merges, the lead also runs Epic 39's new tick tests (`TestAnHourOfTicks`, `TestBeatNow*`); the same fixture-only fix applies if one hits the digest-due notice; any assertion change is a Clarification. Footprint extension.
- **Side edits CONFIRMED:** `dailyCost` in `SLOTTYPES` of `Test/Msg/Catalog.cls` (Epic 39 edits another hunk, about :120: a plain union); `digest` removed from `Test/Channel/TelegramOut.cls` `TestOtherKinds`, on the condition that a positive test of the digest kind's Telegram message, with Got it, exists and is green. Footprint extensions.
- **Interim digest route:** the Planner kept it on condition that nothing can write `digest.channels` before Story 18.2 (with a fallback test and a never-silently-rerouted test). The lead's check found a writer on the feature branch today (see the lead's report to the orchestrator, 2026-11-06): `POST /v1/settings/daily-digest` (`Web/Api.cls` :165 -> `SaveSection` -> `SettingsOps.Save` -> `SaveProduct` -> `Apply`; the `daily-digest` section maps `channels` to `digest.channels`, `SettingsOps.cls` :624-626, `ALLOWLIST` :52), admin-only; the 1.0.1 page itself shows "This part of OcuTalon isn't built yet." for Daily digest (`settings-page.ts` :65-66). The Planner then RULED option (a) (below), which replaces condition 1.

**Digest routing until Story 18.2: Contest Planner ruling under the owner's delegation, 2026-11-06, option (a), a filter that can only narrow (binding):**
- A digest goes only to the session's OWN channels (those `Notify`'s generic route reaches for the session) that `digest.channels` names; the default `web,phone,telegram` (the `SettingsOps` default, read when no row is saved) means all of them. It never goes to a channel outside the session's own: an unknown or foreign value in `digest.channels` never adds a destination.
- If the filter leaves no channel, nothing is sent and the failure is recorded on the digest's failure path, visible in Visual Trace, with exactly this operator diagnostic (a `Digest.Process` parameter): `No digest channel is reachable: none of the saved digest channels is one of this session's channels.` A fixed-strings test pins it.
- The filter lives in Lane A (`Digest`): no Lane B edit; `SettingsOps`, `Web/Api.cls` and `Notify` stay as they are.
- Drop the `digest.channels` seed from this story's `Install/Step/Digest.cls` (`Run` seeds `digest.time` only, if it seeds digest keys at all); the default lives in `SettingsOps` only.
- Required tests, each with its mutation: (1) with no `digest.channels` saved, the digest reaches exactly the session's own channels and nothing else; (2) a saved subset narrows delivery to that subset; (3) a saved value with no reachable channel: nothing is sent, and the failure is recorded with the text above; (4) a foreign or unknown channel value never adds a destination.
- The writer evidence behind this ruling (the lead's check, 2026-11-06): on the feature branch, Epic 17 and Epic 19, `POST /v1/settings/daily-digest` (`Web/Api.cls` :165 -> `SaveDailyDigest` :732 -> `SaveSection` :753 -> `SettingsOps.Save` :690/:716-717 -> `SaveProduct` :775 -> `Apply`) writes `digest.channels` for an admin (section map `SettingsOps.cls` :624-626, `ALLOWLIST` :52); the 1.0.1 page shows "This part of OcuTalon isn't built yet." for Daily digest (`settings-page.ts` :65-66); no installer step on feature or Epic 19 and no chat tool writes it.
- spec-33-2 :145 is amended in place (marker `[AMENDED 2026-11-06, Story 17.6, owner ruling via the Contest Planner]`).

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
30. **G2 uses the session's `CreatedAt`, not a setting (second implement pass).** The ruling says "use the setting the as-built Digest reads, preferring the digest off for that fixture session". No setting turns the digest off for one session: `digest.time` cannot (the test's ticks are a day ahead, so `due` is always later than the fixture session's `CreatedAt`), and `digest.channels` set to a value naming none of the session's channels would make each scheduled `Compose` fail with an Error entry in the event log, and is instance-wide. So the one fixture line moves the fixture session's `CreatedAt` to `2999-01-01T00:00:00Z`: by DW-651's rule a session created after the due time gets no digest, the row goes with the session, and no setting needs putting back. Assertions and tick times are unchanged. The test is red without the line and green with it.
31. **The routing filter lives in `Digest.Process` (second implement pass).** `Own(sessionRef)` is the session's own channels as `Core.Rule.Functions` reads them for Notify's generic route (`DemoOn`, `TelegramPaired`): web, phone, telegram. `Named()` is the known channels that `digest.channels` names (`Data.Setting.Get` with the default `web,phone,telegram` when no value is saved; names are trimmed and read without regard to case; an unknown name, or the name of an item, names nothing). `Channels` is own narrowed to named, in Notify's order, so a value outside the session's own channels never adds a destination. `Deliver` sends to Notify when every own channel is named (Notify's route then reaches exactly the own channels), and otherwise to the item of each remaining channel (`WebChatOut`, `SimPhoneOut`, `TelegramOut`), because `Notify` cannot be told a subset (no Lane B edit). The check is made twice: early in `Composed`, so that no model request is made for a digest that cannot go, and again in `Finish` just before the send, so that a value changed while the summary was awaited is honoured. When no channel is left the handling returns an error status holding `MESSAGENOCHANNEL` (the ruled text, a `Digest.Process` parameter): no `Notification`, no `Sent` row, and Ensemble records it on the `Compose`'s header and in its trace session (Q5 (c)). A read error of the setting is also an error status, never a fall-back to all channels. The seam `SendNotice` takes the item name now (`SendNotice(notification, item)`); `Test.Digest.ProcessProbe` records it as the sixth field of its notice record and gets `OwnChannels` and `ReadOwn`.
32. **The `digest.channels` seed is dropped.** `Digest.Process.Seeds()` returns `digest.time` alone; `CHANNELSDEFAULT` stays as the value read when no row is saved and `Thresholds` `TestDigestSeeds` pins that it equals the section default of `SettingsOps`.
33. **G1** is the one-term append (`SendDigest`) in `Test/Bridge/CodeRules.cls` `TOOLVERBS`, with a short addition to its doc line. **Footprint extensions of this pass:** `Test/Bridge/CodeRules.cls` (Epic 19's footprint, one term) and `Test/Checks/Heartbeat.cls` (Epic 39's, one fixture line in `TestDisabledItemIsReportedOnce`); no other Lane B or contended file was touched.
34. **Not run here:** the fresh-stack shards, `live production` and `live install-start` (the parent runs them); the `Digest.Process` doc comment was rewritten for the routing, and `Install/Step/Digest.cls`'s for the dropped seed.
35. **Review patches, part A (third implement pass).** PA1: `NeedsYou.List` skips the `ItemId` link when the Decision has no ItemId, and `Bound` indexes an empty time under `" "`, so an entry with no time is the oldest. PA2: `Finish` stores `AllClear` 1 only when `CatalogKey` is `checks.allPassed`, the vital-signs part is `digest.healthy` and `needs.count` is 0; the Notification's `CatalogKey` is unchanged (Render's key over the watched rows, AD-28). PA3: `Compose` `TestItemsAreInTheProduction` reads `OcuTalon.Production` through `Ens.Config.Production` and also checks `SELF`, `DECIDE` and `NOTIFY` and one delivering item for each channel.
36. **PA6 hermeticity.** `Test.Digest.ProcessProbe` gains `ForgetChannels` / `PutChannelsBack` (the `digest.channels` row out of the way and back); `Due`, `Send`, `Tool` and `TelegramDigest` use them in `OnBeforeAllTests` / `OnAfterAllTests` (`Tool` and `TelegramDigest` are also classes that send; `Tool` gains the `PROBE` parameter), and `Compose` takes the row out in `OnBeforeOneTest` with its own `SaveChannels("")`. In the two production classes (`Send`, `Tool`) the Digest job keeps its own 60-second cache of the setting, so a row left a moment before a run can still be read for up to a minute; the classes cannot clear another process's cache.
37. **PA6 other items.** `Send.Composes(mark, session)` counts only the session's Compose headers and `WaitComposed` replaces the two `Hang 2` (a bounded poll until the session's Composes are finished); `TestRepeatKey` queues a digest for a bystander session so that the session filter is pinned; `TestComposeFailureInTrace` looks for its session's Compose header. `TelegramDigest` `TestDigestMessage` expects the session's 0.042 plus the instance part of yesterday, read with `Cost.Yesterday` for a session with no rows. `Compose` `AssertNoChannel` checks the error text of the no-channel cases; `TestSummaryFallback` asserts that `OnError` returns OK and that a failed send leaves `Sent.ItemId` empty; `TestOwnChannels` wraps its body in `Try`/`Catch` and asserts that demo mode and the Telegram setting are put back.
38. **PA7.** `ProcessProbe.Hold` takes an optional `coverDue`: the holding job writes a scheduled Sent row for that due time (`Cover`) just before it lets go, and `Due` `TestLockRecheck` ticks while it holds the lock (0.8 s hold against the probe's 1 s lock wait): the tick checks again under the lock and queues nothing. No large change to the probe was needed.
39. **Watch catalog comment (PA4).** Only the class doc comment of `Msg/Catalog/Watch.cls` changed (`digest.cost` slot type, `digest.needsYouMore`, `button.gotIt`, `handled.marked`); the entries are untouched.
40. **Part B1 strengthens one test (fourth implement pass).** `Test.Digest.Send` `TestSavedSummaryThroughDecide` read the mock's log and the Sent row but not the request, so the `Provenance` mutation of `SummaryRequest` survived it. It now also takes a header mark before the SendDigest, reads the `OcuTalon.Bridge.Msg.Request` body of the one Digest-to-Decide header of the session (new private helper `RequestsOf`) and asserts kind `turn`, provenance `untrusted`, session mode `fresh`, no seed, owner the session and channel `system`, the AC5 request shape, on the real production. The class doc line of `Send` says so. No production code changed in this pass: every mutation was reverted from a backup.
41. **`TestSentRow` is not the pin of "AllClear needs more than the CatalogKey".** Its three cases (all passed, a failed entry, nothing watched) have a healthy vital part and nothing open, so the CatalogKey-alone mutation is indistinguishable there; `TestAllClearNeedsVitalsAndNothingOpen` (PA2) pins it. `TestSentRow` is pinned by its own mutation (`AllClear` from `checkKey '= "checks.nothingWatched"`).
42. **Part B2 strengthens two assertions in `Test/Channel/TelegramDigest.cls`** (no production code changed). `TestGotItOtherChat` gains a fifth press, `gotit:notaref` in the paired chat, against a telegram Delivery row of the session in that chat with `DecisionRef` "notaref", so that the `IsRef(decisionRef)` term of `In.GotIt` is pinned (it survived: every Ref the test pressed was a real one). `TestHandledEdit` asserts that a repeated `handled` Notification logs no further warning, so that the `row.Kind = "handled"` quit of `EditHandled` is pinned (it survived: the handled row's empty text also stops the repeat). The class header says so.
43. **The `Pairing.Chat` terms of `In.GotIt` are an equivalent mutant.** Dropping `'$IsObject(chat)`, `chat.SessionRef = ""` and `IsRef(chat.SessionRef)` changes nothing observable: the next call, `Ownership.DeliveryByRef`, answers an error status for an empty session, `instance` or `eval` (`Ownership.Rows` :677-681), and `GotIt` quits on an error status. They stay as defence in depth; the test pins what is observable (an unpaired chat submits nothing).
44. **`ClockTime`'s read failure has no seam.** `TestBadTime` pins the values that are read but not time-shaped; a `Setting.Get` that throws, and an empty value, reach the same final default and cannot be told apart from it by a test without a seam in `Data.Setting` (not Digest). Left as it is.

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

Second implement pass (2026-11-06, rulings after the first pass; applied on warm `e17s6jw`, each reverted from a backup, the tree hash identical before and after):
- mutation: `Deliver` never sends to Notify (`If channels = own` made `If 0`): `Compose` `TestRouteOwn` red (and `TestRouteForeign`; the digest then goes to the item of each channel instead of Notify).
- mutation: `Channels` ignores the saved value (`If $ListFind(named, channel)` made `If 1`): `Compose` `TestRouteSubset` red (and `TestRouteNoneReachable`, `TestRouteForeign`).
- mutation: the no-channel check removed (`If $ListLength(channels) = 0` made `If 0`): `Compose` `TestRouteNoneReachable` red (and `TestRouteForeign`).
- mutation: `Channels` walks the named channels instead of the session's own (`While $ListNext(own, ...)` made `$ListNext(named, ...)`): `Compose` `TestRouteForeign` red (a channel outside the session's own becomes a destination; `TestRouteNoneReachable` and `TestRouteSubset` too).
- mutation: `MESSAGENOCHANNEL` changed ("not one of this session's channels" for "none of the saved digest channels is one of this session's channels"): `Compose` `TestRouteNoneReachable` red (the fixed-strings pin).
- mutation: `Seeds` also seeds `digest.channels`: `Thresholds` `TestDigestSeeds` red.
- mutation: `SendDigest` removed from `TOOLVERBS` (G1): `Agent.Runners` `TestToolInventory` red for `ChatAgent` and `ChatAgentRetry`.
- mutation: the `CreatedAt` update removed from `Heartbeat` `TestDisabledItemIsReportedOnce` (G2): that test red ("whose text is the catalog's rendering...", "with the Why now line"), the second notice being a scheduled digest.

Mutations, second review pass (part A, 2026-11-06; applied on warm `e17s6jw`, each from a backup in the scratch folder, reverted, the hash of `git diff` and the untracked files identical before and after):
- mutation (PA1): the `decision.ItemId '= ""` test removed from the `owned("item", ...)` lookup in `NeedsYou.List`: `NeedsYou` `TestEmptyItemId` red (`<SUBSCRIPT>` on an empty ItemId).
- mutation (PA1): the placeholder removed from `NeedsYou.Bound` (`Set byTime($List(entries(i), 2), i)`): `NeedsYou` `TestOverflowEmptyTime` red (`<SUBSCRIPT>` on an empty time).
- mutation (PA2): `AllClear` set from the `CatalogKey` alone in `Finish`: `Compose` `TestAllClearNeedsVitalsAndNothingOpen` red; with only the `needs.count = 0` term dropped, its case "an entry needs the user" is red; with only the vital-signs term dropped, its case "a vital sign failed" is red.
- mutation (PA3): `ITEMS` renamed (`WebChatOut` to `WebChatOutX`): `Compose` `TestItemsAreInTheProduction` red (and `TestRouteSubset`).
- mutation (PA5): `OnError` returns `pErrorStatus` unchanged: `Compose` `TestSummaryFallback` red (case `error`: "OnError returns OK").
- mutation (PA6, hermetic `digest.channels`): `Compose` `OnBeforeOneTest` saves `telegram` instead of removing the row: `Compose` red in every test that sends (the reachability text). `ProcessProbe.ForgetChannels` saves `email` after taking the row out: `Due` (`TestCatchUpOnce`, `TestRequestedAndScheduled`), `TelegramDigest` (`TestDigestMessage`, `TestQuietAndLimits`), `Send` (`TestWebAdminSends`, `TestRepeatKey`, `TestSavedSummaryThroughDecide`, `TestSavedFallback`, `TestTickReachesDigest`) and `Tool` (`TestResultSaysSending`) red. (`phone` instead of `telegram` or `email` survives in `Compose` on a stack with demo mode on, because phone is then one of the session's own channels.)
- mutation (PA6, error text): the no-channel error carries another text when the session has more than one own channel: `Compose` `TestRouteNoneReachable` (own web and phone) and `TestRouteForeign` (the names of items, own three) red through `AssertNoChannel`.
- mutation (PA6, `send` case): the `Set ..ItemId = ""` after a failed `SendSummary` removed: `Compose` `TestSummaryFallback` red ("a request that was never sent leaves the Sent row no ItemId").
- mutation (PA6, `Composes` by session): the session filter removed from `Send.Composes`: `Send` `TestRepeatKey` red against the Compose of the bystander session that the test now queues (the filter of `TestComposeFailureInTrace`'s header search has no such pin: its mutation cannot be told apart without a second failing session; it stays a code-only change).
- mutation (PA6, `TestOwnChannels` restore): a `Throw` inserted in its `Try` body: `Compose` `TestOwnChannels` red only for the caught "channels test failed", and its new assertions that demo mode and the Telegram setting are put back stay green (the straight-line version would have left demo mode on).
- mutation (PA6, `TestDigestMessage` cost): the expectation made the constant "Yesterday's cost: $0.04." with a stray `instance` Usage row of yesterday (0.5) made in the test: `TelegramDigest` `TestDigestMessage` red; the control (the new expectation with the same stray row made before the instance part is read) is green ("$0.54").
- mutation (PA7): the line `If '..Covered(...) Set sc = ..Queue(...)` of `Schedule` made unconditional: `Due` `TestLockRecheck` red (the existing `TestLock` stays green: it did not pin the re-check).
- No mutation line (not a behaviour change or a new pin): PA4's comments; the deletion of `Due`'s vacuous `+$Get(^||DigestProbe("summary")) = 0` assertion; the bounded poll `WaitComposed` that replaces `TestRepeatKey`'s two `Hang 2` (its assertions are the same ones; the existing key-check mutation still reddens `TestRepeatKey`).

Mutations, second review pass (part B1, 2026-11-06; items 1 to 5 of review patches part B; applied on warm `e17s6jw`, each from a backup in the scratch folder, reverted, the hash of `git diff HEAD` and the untracked files identical before and after; the baseline was 81ee0a95... before the one test change below and 78ce689a... after it):
- mutation (AC5, request shape): `Provenance` "untrusted" made "user" in `SummaryRequest`: `Compose` `TestSavedSummary` red ("it is an untrusted, fresh turn with no seed, ..."). `Send` `TestSavedSummaryThroughDecide` SURVIVED (green): it read the mock's log and the Sent row but never the request. Strengthened (Decided in-stage 40): it now reads the `Request` body of the Digest-to-Decide header and asserts `turn|untrusted|fresh||<session>|system`; rerun with the mutation: red on that assertion; restored: green.
- mutation (AC5, request shape): `SessionMode` "fresh" made "continue" in `SummaryRequest`: `Compose` `TestSavedSummary` red and, with the strengthened assertion, `Send` `TestSavedSummaryThroughDecide` red (the same assertion as above; the original `Send` test checked neither field).
- mutation (AC5, nothing saved asks nobody): the empty-items branch of `Composed` made unreachable (`If items.%Size() = 0 {` made `If 0 {`, so the summary request is always made): `Compose` `TestNothingSaved` red ("no item in the window: no request to Decide", "and the digest goes at once"; a dozen other Compose tests go red too, because the digest then waits for an answer), and `Send` `TestNothingSavedNoRequest` red ("and the mock logged no request").
- mutation (AC5, log line): the fallback's `$$$LOGINFO(..#LOGFELLBACK_reason)` removed from `OnResponse`: `Compose` `TestSummaryFallback` red ("each fallback is logged once, with its reason") and `Send` `TestSavedFallback` red ("and one information line says so").
- mutation (AC6, 150 words): twelve copies of the vital-signs part appended after the cost part in `Finish`: `Compose` `TestQuietDay` red ("a quiet digest has at most 150 words: 300"; and its key-order assertion) and `TelegramDigest` `TestQuietAndLimits` red ("and has at most 150 words: 296").
- mutation (AC3, greeting band): `hour < 12` made `hour < 13` in `Greeting`: `Compose` `TestGreeting` red ("2030-06-03T12:00:00 in the instance zone"); `hour < 18` made `hour < 19`: red ("2030-06-03T18:00:00 in the instance zone").
- mutation (AC3, vital signs): the `digest.vitalsNotAll` branch of `Vitals` never taken (`If (missing.%Size() > 0) || (vitals.rows.%Size() = 0) {` made `If 0 {`): `Compose` `TestVitalsNotAll` red (and `TestAllClearNeedsVitalsAndNothingOpen`, case "a vital sign failed").
- mutation (AC3, nothing watched): the nothing-watched branch of `Finish` made unreachable (`If watched.%Size() = 0 {` made `If 0 {`): `Compose` `TestNothingWatched` red ("with nothing watched the checked part is digest.nothingWatched alone"; and the render of an empty `checked` slot in four other tests). Not run, an equivalent mutant: dropping `Set checkKey = "checks.nothingWatched"` there, because `Render([])` returns that key.
- mutation (AC3, checked versus checked quiet): the key always `digest.checked`: `Compose` `TestQuietDay` red ("a quiet day has no needs-you part", "it says what was checked"; and `TestVitalsNotAll`); the key always `digest.checkedQuiet`: `Compose` `TestPartOrder` red ("the parts are in the order of the contract").
- mutation (AC3, AllClear from the CatalogKey alone, after PA2): `row.AllClear` set from `checkKey = "checks.allPassed"` alone: `Compose` `TestAllClearNeedsVitalsAndNothingOpen` red (cases "a vital sign failed" and "an entry needs the user"); `TestSentRow` stays green on it, by design, because its three cases have a healthy vital part and nothing open (the PA2 test is the pin; no change made). `TestSentRow`'s own pin: `row.AllClear` set to `checkKey '= "checks.nothingWatched"`: `TestSentRow` red ("checks.notEverything: the CatalogKey and AllClear"), with `TestAllClearNeedsVitalsAndNothingOpen` red as well.
- mutation (AC3, cost window): the lower bound of the Usage sum in `Cost.Yesterday` widened by an hour (`AddSeconds(from, -3600)`): `Compose` `TestCost` red (the session's 7 of 2030-06-01T23:59:59 is summed: "it sums the session's and instance's cost of yesterday ...", "and renders with two decimals", "Cost.Yesterday gives the same sum"); the upper bound widened by an hour (`AddSeconds(to, 3600)`, so today's midnight row of 5 is summed): the same three assertions red.

Mutations, second review pass (part B2, 2026-11-06; items 6 to 10 of review patches part B; applied on warm `e17s6jw`, each from a backup in the scratch folder, reverted, the hash of `git diff HEAD` and the untracked files identical before and after each one; the baseline was 78ce689a... before the two test changes below and d9e83a60... after them):
- mutation (AC4, 4096; the existing `NEEDSYOUMAX` line of the first pass, also run on the Telegram test): `NEEDSYOUMAX` ignored (`If count <= ..#NEEDSYOUMAX {` made `If 1 {` in `NeedsYou.Bound`): `TelegramDigest` `TestQuietAndLimits` red ("as one message", "five of them are named", "and the rest are counted").
- mutation (AC7, window): the newest-`SentAt` lookup of `Process.WindowStart` limited to `Kind = 'scheduled'` (the window ignores a requested `Sent`): `Due` `TestRequestedAndScheduled` red ("and its window starts at the SentAt of the requested digest").
- mutation (DW-649, requested `DueAt`): `Requested` queues the requested `Compose` with `DueAt` = `..DueFor(now)` instead of "": `Due` `TestRequestedAndScheduled` red ("requested, with an empty DueAt", "the Sent row is requested with an empty DueAt").
- mutation (AC1, lock): the per-session lock of `Schedule` not taken (`Lock +^...` replaced by `Set locked = 1` and the `$Test` test by `locked`): `Due` `TestLock` red ("a tick that cannot take the lock queues no Compose") and `TestLockRecheck` red.
- mutation (AC1, ended session): the ended-session test of `Ticked` made unreachable (`If 0 && online && (... ResumeHash ... = "") Continue`): `Due` `TestEndedOnlineDemo` red ("on the online demo one session is queued").
- mutation (AC1, zone): both `FromLocal(...)` calls of `DueFor` replaced by a UTC reading (`$ZDate(day, 3)_"T"_time_":00Z"`, and the same for `day - 1`): `Due` `TestDaylightSaving` red (seven assertions: the 03:30 EDT hour, both change days at 07:00 and 08:01, the 02:30 EST skipped hour), and `TestCreatedBefore`, `TestCreatedAfter`, `TestCatchUpOnce`, `TestEndedOnlineDemo`, `TestLock`, `TestLockRecheck`, `TestQueuedNotRepeated` and `TestRequestedAndScheduled` red as well.
- mutation (AC1, bad time): an unreadable `digest.time` not defaulting (the last line of `ClockTime` made `Quit value`): `Due` `TestBadTime` red ("'25:00' means 08:00", "'8:00'", "'abc'", "'07:61'"). Not mutated, and not testable without a seam: the `Catch` of the `Setting.Get` read (the read throwing) and the empty value ("" is answered by `Setting.Get`'s own default); both reach the same final `Quit ..#TIMEDEFAULT` (Decided in-stage 44).
- mutation (AC10, the button): the Got it keyboard never added (`ElseIf $ListFind(...GOTITKINDS...) && ...` made `ElseIf 0 && ...` in `Out.OnNotification`): `TelegramDigest` `TestGotItButton` red ("the message carries a keyboard"); `TestHandledEdit` red too (a message with no button keeps no text to edit).
- mutation (AC10, the paired check): the `Pairing.Chat` terms of `In.GotIt` (`'$IsObject(chat) || (chat.SessionRef = "") ||` and the `IsRef(chat.SessionRef)` term) all dropped: SURVIVED (`TelegramDigest` green, including `TestGotItOtherChat`). It is an equivalent mutant: an unpaired chat has `SessionRef` "", and `Ownership.DeliveryByRef` answers an error status for an empty session (and for `instance` or `eval`, through `Ownership.Rows`), on which `GotIt` quits; the substantive guards are the Delivery row of the paired session and the chat of its message, which `TestGotItOtherChat` pins ("another paired chat", "an unpaired chat"). No test can make the dropped terms matter, so none was added (Decided in-stage 43).
- mutation (AC10, the Delivery row): the check that the row exists dropped (`'$IsObject(row) ||` made to let a missing row through): `TelegramDigest` `TestGotItOtherChat` red ("and none submits a command: ... a Ref with no message ...").
- mutation (AC10, `IsRef`): the `IsRef(decisionRef)` term of `In.GotIt` dropped: SURVIVED the original `TelegramDigest` (every pressed Ref was a real one). Strengthened (Decided in-stage 42): `TestGotItOtherChat` also presses `gotit:notaref` in the paired chat of a session that has a telegram Delivery row of that chat with `DecisionRef` "notaref" and expects nothing submitted (five presses, five answers). Rerun with the mutation: red ("... a message of the pressing chat whose Ref is not a reference"); restored: green.
- mutation (AC10, the first handled edit kept): the `If $IsObject(row) && (row.Kind = "handled") Quit $$$OK` line of `EditHandled` removed: SURVIVED the original `TestHandledEdit` (the handled row has the text "", so the next line's `row.Text = ""` test also edits nothing; only a second warning differs). Strengthened (Decided in-stage 42): after the second handled Notification the test asserts that the warning count is still 1 ("and the repeat logs no further warning"). Rerun with the mutation: red on that assertion; restored: green.
- mutation (AC10, no-marker warning): `$$$LOGWARNING(..#LOGNOHANDLED)` removed from `EditHandled`: `TelegramDigest` `TestHandledEdit` red ("and logs one warning", and the new "the repeat logs no further warning" as the count is 0).
- mutation (Telegram layout, `AFTERLINES`): `AFTERLINES` shortened to the saved-for-later and cost keys, so the coverage lines move from before needs you to before saved for later: `TelegramDigest` `TestDigestMessage` red ("the text holds '2 things need you: ...' after the one before it").

## Clarification Needed

Both items below are ANSWERED by the rulings of 2026-11-06 (Design Notes, "Rulings on the implement stage's gaps"): 1 by G1, 2 by G2. They are kept for the record.

1. **intent gap: `Test/Bridge/CodeRules.cls` `TOOLVERBS` must name `SendDigest`.** `Test.Agent.Runners` `TestToolInventory` runs `CodeRules.ToolCodeClean` over every tool class, and it refuses `DigestTools` ("names the command class SendDigest, which is not a tool verb"), because `TOOLVERBS` (line 109) lists only `SetReminder,ListReminders,CancelReminder,StartWatch,StopWatch,Dismiss`. `CommandsIn` `TOOLVERBS` already allows `SendDigest` from origin `tool` (AD-1). The file is Epic 19's (`OCT-epic19` changes it) and no ruling names it, so it is not edited and `TestToolInventory` is red for `ChatAgent` and `ChatAgentRetry`. Recommended resolution: a Q7-shaped one-term edit, appending `SendDigest` to `TOOLVERBS` and extending its doc line, reported as a footprint extension (a plain union with Epic 19's memory verbs at the merge).
2. **intent gap: the Tick forward makes `Test.Checks.Heartbeat` `TestDisabledItemIsReportedOnce` red.** Epic 30/39's tests send ticks `AHEADSECONDS` (a day) into the future (`Test.Watch.Case` `Ahead`). With the forward, `Digest` takes the due rule at `tickAt`, finds the fixture session created before tomorrow's `digest.time`, and sends it a scheduled digest. The session's web chat then holds two notices where the test asserts one ("the session's web chat got one notification"). Every other Checks, Watch, Digest, Agent, Tools and `Schedule.Heartbeat` class passed on the fresh stack. The test is Epic 39's contended file and no ruling covers it. Recommended resolution: the due rule uses the earlier of `tickAt` and the clock (a tick from the future cannot make a digest due before its time; real heartbeat ticks are taken at the clock, so nothing else changes), with a clock seam in `Digest.Process` so that `Test.Digest.Due` keeps its 2030 times; or the lead has Epic 39 move its ticks to a time that crosses no `digest.time`. Not implemented here, because it changes the ruled due rule.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** `OcuTalon.Digest.Process` is now the real daily digest: the Tick forward from `Checks`, the DW-651 due rule under a per-session lock, the asynchronous `Compose`, the six-part AD-32 digest with the needs-you list (Q4), the optional one-turn untrusted summary (AD-30), yesterday's cost, the `Sent` row with `IdempotencyKey`, `SendDigest` answering `ok` / `sending` at once, the `send_digest` chat tool, the Telegram digest message, **Got it** and the in-place handled edit. This second pass added the ruled gap fixes: G1 (`SendDigest` in `TOOLVERBS`), G2 (the Heartbeat fixture session's `CreatedAt` set after any due time: Decided in-stage 30), the interim digest routing filter (option (a): the session's own channels that `digest.channels` names; none left gives the ruled `MESSAGENOCHANNEL` failure; no `digest.channels` seed), and the two confirmed side edits.

**Files changed** are the 42 paths of the diff since `baseline_revision`: the Digest, Telegram channel, Tools, Catalog/Watch, Production and Install-step sources; the new Digest tests and probes; the ruled edits to contended or Lane B test files (`Test/Msg/Catalog.cls`, `Test/Install/{Production,SecurityOverview}.cls`, `Test/Tools/Reminders.cls`, `Test/Bridge/{Gate,CodeRules}.cls`, `Test/Checks/Heartbeat.cls`); `Checks/Process.cls` (Q1 only); two mock scenarios; the regenerated `docs/security-overview.md`.

**Review.** Four layers reported 51 findings: patches 19 rows (1 medium: `AllClear` could be stored as 1 for a digest with a failed vital sign or open needs-you entries; 18 low), no defers, rejected 32 (5 false with their refutation, 3 maybe-false whose if-true harm is low, 24 low, each with its reason in the Review Triage Log). Patches: NeedsYou null subscripts, `AllClear` also needs healthy vitals and nothing open, an `ITEMS`-in-production oracle, header comments, hermeticity of the Digest tests, weak assertions, the re-check under the lock, and new `mutation:` lines (parts A, B1 and B2). Two mutations survived and led to stronger tests (`Send` `TestSavedSummaryThroughDecide`; `TelegramDigest` `TestGotItOtherChat`, `TestHandledEdit`); one is an equivalent mutant (the `Pairing.Chat` terms of `In.GotIt`).
`followup_review_recommended: false`: one medium patched, no high.

**Verification.**
- Warm classes (loop list, plus `Bridge.CodeRules`), all green after the last change.
- Fresh stack `e17s6j`: `lane-a@Agent,Tools` (2 parts), `lane-a@Checks`, `lane-a@Install` (2 parts), `lane-a@Digest` (3 parts), `lane-a@Channel` (2 parts), `live install-start`: all passed.
- `test-security-overview`, `test-mock` (131), `test-storage`, `test-ci-config`, `test-boundaries`, `test-class-rules` and the web `catalog.test.mjs` (65) pass; no non-ASCII bytes in the diff.
- Not re-run in this pass: `live production` (run in the first pass; the production item list is unchanged) and the `lane-a@Watch`/`rest` shards (the first pass ran them; this pass changed no code they cover except Digest/Channel tests and `Msg/Catalog/Watch.cls` comments).

**Residual risks.**
- The next digest's window starts at `SentAt`, so an item recorded between a Compose's queue time and its send (the Decide wait) is in no digest (BH1; rejected as rare; the contract fixes the window rule).
- A failed scheduled Compose is not retried the same day (Decided in-stage 11); a saved `digest.channels` that names no own channel therefore costs that day's digest, visible in Visual Trace with the ruled text.
- When `digest.channels` names a subset, the digest goes straight to the channel items and not through `Notify` (Notify cannot be told a subset until Story 18.2); the Digest job also caches the setting for 60 s.
- `Own` mirrors `Notify`'s generic route and must follow it until Story 18.2 replaces both.
- G2 uses `CreatedAt` (no per-session digest-off setting exists). At the integrate-forward after Epic 39 merges, the lead runs Epic 39's new tick tests (`TestAnHourOfTicks`, `TestBeatNow*`); the same fixture-only fix applies if one hits a digest-due notice.
- The ruled `Checks/Process.cls` `Tick` block must be re-placed as the last statement of the merged `Tick` at that integrate-forward.
