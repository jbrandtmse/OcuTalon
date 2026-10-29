---
title: 'Story 16.9: Allowances cap messages, model cost and simulated emails'
type: 'feature'
created: '2026-10-29'
status: 'done'
baseline_revision: 'c6339034b26342969d6d9964d224b64623a5fe63'
baseline_commit: 'c6339034b26342969d6d9964d224b64623a5fe63'
review_loop_iteration: 0
followup_review_recommended: true
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, lines 99-111; AD-4, 155-178; AD-12, 330-344; AD-14, 396-407; AD-20, 529-554; AD-30, 813-834; AD-31, 835-852; AD-32, 853-864; AD-33, 865-875; the REST, Live events and Notice cards rows, 921-925; the event table, 1128-1137)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only lines 180, 258, 266-267, 308, 349-351, 436-441, 546, 742-743, 851-856)'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md (read only Story 16.9, lines 4602-4641)'
warnings: ['oversized', 'multiple-goals']
deferred:
  - summary: >-
      The class comment of Core/NoticesIn.cls still says that the daily-cap message of Story 16.9 is a sender "to come". BridgeSink sends it now. Only the comment is stale: the class itself needed no change.
    evidence: |-
      Task 0 (a): no bridge context is active in the Decide job that fires decision.recorded and budget.capped, so NoticesIn's two branches already give each notice its own session's TraceRef (D1: S1 and S3 each get their own card from one decision). The Footprint extension lists NoticesIn.cls only if Task 0 (a) needs it, so the comment was left alone.
---

<intent-contract>

## Intent

**Problem:** The online demo shares one model key and one instance, but nothing caps a visitor. `Allowance.TryConsume` allows everything, and a refusal would answer 500. The daily cost cap shows a banner but sends no chat message. The simulated mailbox takes any number of emails.

**Approach:** With the online-demo flag set:
- `TryConsume` counts each session's messages over a rolling hour, under the session row's lock. It refuses the 51st with `retryAt`, records the refused `Turn`, and flags the first refusal of the window. The refusal becomes a 429, plus one `allowance` notice in the chat.
- The session's `allowance` condition drives the banner and the `aria-disabled` composer and guide prompts until `retryAt`.
- `BridgeSink` sends the daily-cap message once a day to each active session.
- `SimMailboxIn` refuses the 21st email of the hour.

With the flag off, nothing changes.

## Boundaries & Constraints

**Always:**
- **Flag off changes nothing** (`Data.Setting.Get("onlineDemo") '= 1`, a local or IPM install). With the flag off:
  - `TryConsume` allows and writes nothing;
  - there is no email limit;
  - `BridgeSink` sends no daily-cap message;
  - a capped day shows only the local `costCap` banner, which is unchanged.
- **Owner-fixed numbers:**
  - 50 messages per session per rolling 3600 s, read from the public setting `messageAllowance`. Any value that is not a whole number of 1 or more counts as 50.
  - 20 simulated incoming emails per session per rolling 3600 s, samples included. This is `Allowance.EMAILLIMIT = 20`.
  - The cap is read only through `OcuTalon.Bridge.Budget.State()`. Its $20 is a start value.
- **What counts:**
  - The allowance counts web chat messages and guide prompts (`POST /api/v1/messages`, `fromGuide` too) and Telegram messages, all through the one `TryConsume`.
  - A refused message never counts, never reaches `Conversation` and never calls a model.
  - A duplicate `clientId` is answered before `TryConsume` and costs nothing.
- **Texts are the catalog's and the UX's only:**
  - catalog keys `conversation.sessionAllowance`, `conversation.dailyCap`, `banner.allowance` and `banner.dailyCap`;
  - EXPERIENCE.md:308 "You've simulated 20 emails this hour. You can send more at {time}.";
  - the veto items V2.
- **How times and words show:**
  - Chat and Telegram texts show instance time plus "ET" (`Catalog.Render` does this). The page shows page time (`pageTime`). Slots carry UTC ISO 8601 to the second.
  - Texts say "messages", never "turns".
- **Explained-disabled controls** stay focusable, with `aria-disabled="true"`, never `disabled`. Their visible reason is linked by `aria-describedby`.
- Break the feed, Approve and Reject are never disabled or refused by an allowance or by the cap.
- **Producers** send a key and slots and never render (AD-32). `WebChatIn`'s source never names `OcuTalon.Msg.Catalog` (`TestSourceKeepsToItsBoundaries`).
- **`BridgeSink`** waits at most 1 s on any lock, sends notices asynchronously, never publishes for the daily cap, and always returns OK (AD-31).
- **Session row writes** by `TryConsume`, `Refund` and `BridgeSink` follow `Core.Trace`'s row-lock pattern: `%LockId(id, 0, wait)`, then `%OpenId` and `%Reload`, set, `%Save`, `%UnlockId`. That row lock is the AC's "per-session lock". `SimMailboxIn` holds the same lock across its count and its save.
- **Hermetic tests:** every test added or changed passes on a fresh environment, in either order.
  - Every browser test signs out.
  - Instance-wide state that a test sets is restored in a `finally` or `afterAll`, also on failure: the capped mark `^OcuTalonBP.UsageCapped(day)`, seeded `Usage` rows, settings.

**Never:**
- **Contended paths are read only** (call them, never edit them): `src/bridge/**`, `Test/Bridge/**`, `Test/Watch/**`, `ci/mock/scenarios/A/**`, `Tools/WatchTools.cls`, `Install/**`, `src/module.xml`, `docs/**`, `release/**`.
  - The bridge APIs this story uses are `Budget.State`, `Bridge.Time`, `Approval.Answer` and `Ids.NewRef`.
  - Use the mock's `[[mock:daily-cap]]` as it is.
  - Needing to edit a contended path is a `## Clarification Needed` stop.
- **No new public text** beyond the lists above. A needed text that isn't listed is a `## Clarification Needed` stop.
- **No second publisher** of `status`, `chat.message` or `notification` (AD-33). `TryConsume` publishes nothing.
- **The refused `Turn` is never shown** in the chat, never in a recap and never given a `ClientId`.
- No WebSocket, and no edit to `Channel/Telegram/**` (Story 12.6). The Telegram cases stay off until Story 31.3.
- The splash's and the guide's README links are not changed.

## I/O & Edge-Case Matrix

| # | Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|----------|--------------|---------------------------|----------------|
| 1 | Allowed | Flag on. Fewer than `Limit()` entries in the past 3600 s. | `TryConsume` returns 1 with `retryAt` "" and `firstRefusal` 0, and appends now to `Session.AllowanceTimes`. `WebChatIn` sends the Item. 202 `{"clientId"}`. | No error expected |
| 2 | The 51st | Flag on. 50 entries in the past hour, from web, guide and telegram mixed. | `TryConsume` returns 0. `retryAt` = oldest kept entry + 3600 s, and `firstRefusal` is 1. `AllowanceUntil` = `retryAt`. In one transaction, a `Turn` is recorded: `State` "refused", the channel, the text, `CreatedAt` now, a new `Ref` and `ItemId`, no `ClientId`, no decision refs. `WebChatIn` sends no Item. It sends `Notify` one `Notification`: `Kind` "allowance", key `conversation.sessionAllowance`, slots `{limit, time: retryAt, readmeLink: INSTALLLINK}`, under the session's `TraceRef`. Output: `{"accepted":0,"duplicate":0,"refused":1,"retryAt","limit"}`. The answer is 429 `{"error":{"code":"allowance","message"},"retryAt","limit"}`. | A failed notice send is logged as a warning, and the refusal stands. |
| 3 | Same window | `AllowanceUntil` > now. | 0, with the same `retryAt` and `firstRefusal` 0. Another refused `Turn` is recorded. No notification. 429. | — |
| 4 | Telegram fixture | `TryConsume(s, "telegram", text)` at the limit. A telegram call also counts in the window. | As row 2, with the `Turn` channel telegram and the flag set when it is the window's first refusal. No Epic 12 code is involved. | — |
| 5 | New window | now ≥ `retryAt`, so the oldest entry has dropped out. | Allowed. A later refusal has `firstRefusal` 1 again and sends a new notice. | — |
| 6 | Flag off | Any number of calls. | 1, "" and 0. No row writes and no `Turn`. | — |
| 7 | No session row | Flag on, an unknown `sessionRef`. | 1, and nothing is recorded. The channel services check the row first. | — |
| 8 | Lock busy | The row lock is not free within `LOCKWAIT` (5 s), or an exception. | 0 with `retryAt` "". Nothing is recorded. `WebChatIn` answers an error status, so REST answers 500 and the page shows "Not sent". | The transaction rolls back. |
| 9 | Failed send | Allowed, then the Item send fails. | `WebChatIn` calls `Allowance.Refund(sessionRef)`, which removes the newest entry, and answers the error (500). | `Refund` never throws. |
| 10 | `/state` status | Flag on, `AllowanceUntil` > now. | `status[0]` = `{"condition":"allowance","active":true,"slots":{"limit","time":AllowanceUntil}}`, then the instance conditions as today. Absent otherwise, and absent with the flag off. | A failed read throws, as `StateBody` does today. |
| 11 | `StatusMonitor` | A session's condition changes: a refusal, or now passes `AllowanceUntil`. | Within one tick, one `status` event on that session's stream: the active view, or a clear (active false, no slots). The first run only remembers. Instance events are unchanged. | A failed read is a warning, and nothing is remembered. |
| 12 | Page, allowance | The `allowance` condition from the store, or a 429 refusal. | `banner.allowance` heads the stack: danger, cannot be closed, "Install it yourself" goes to the README's `#install-it-yourself`. The composer field and Send, and the guide's send prompts, get `aria-disabled` and `aria-describedby`, pointing to a visible reason that is the banner's own text. Presses and Enter are ignored. A 429'd typed text goes back to an empty composer, and a guide entry just leaves. At `retryAt` (page clock) all of it clears. Break the feed, Approve and Reject are unchanged. | A 429 while the composer already holds other text fails as today ("Not sent"). |
| 13 | Cap, IRIS count | Flag on, spent ≥ cap. | `Budget.State().capped` is true, so the online `dailyCap` banner shows. A turn falls back with `daily_cap` before any request. `decision.recorded` for session S makes `BridgeSink` send S the `conversation.dailyCap` notice (`Kind` allowance, slots `{time: Bridge.Time.DayEndUtc(day), readmeLink}`) through `NoticesIn` and set `S.DailyCapDay = day`. On `budget.capped {day}`, every open session with activity whose `DailyCapDay ≠ day` gets it once. | Lock busy for 1 s: a warning, nothing sent, and the next fallback retries it. |
| 14 | Cap, gateway 403 | `[[mock:daily-cap]]`, the cap not reached. | The decision falls back with `daily_cap` and the mock sees one request. The day is marked, so `Budget.State()` reports capped. Notices as row 13. | — |
| 15 | Active later | An open session with no activity at `budget.capped`. | It gets nothing then. Its first `daily_cap` fallback sends it the message, and a second fallback that day sends nothing. | — |
| 16 | Not a recipient | An ended session (`ResumeHash` empty), or flag off. | Nothing is sent on either event. Flag off also shows the `costCap` banner. | — |
| 17 | The 21st email | Flag on. 20 incoming `SimMessage` rows (mailbox, in) in the past hour, samples included. | `SimMailboxIn` saves, sends and publishes nothing. Output `{"refused":1,"retryAt"}`, with `retryAt` = oldest + 3600 s. The answer is 429 `{"error":{"code":"email_limit","message"},"retryAt"}`. The mailbox's Send and chips get `aria-disabled`, with the email text in page time, until `retryAt`. Flag off: no limit. | A failed count read is an error status (500). |

</intent-contract>

## Code Map

All class paths are under `src/ocutalon/cls/OcuTalon/`.

**Allowance and the session row**
- `Core/Allowance.cls`: the Story 2.4 stub. `TryConsume(sessionRef, channel, text, *retryAt, *firstRefusal) As %Boolean` keeps this signature, which `Test/Contract/Ac.cls:343` pins as a cross-lane API for Story 12.6. Add the online-demo count and the methods of task 3.
- `Data/Session.cls`:
  - Storage `<Value>` 1-10 are at lines 174-203. Append three properties as Values 11-13.
  - The row-lock writers are `Core/Trace.cls:55-125`, which uses `%LockId(id,0,LOCKWAIT)` with `%OpenId` and `%Reload`, and `Core/SessionOps.cls:335-352` (`RefIndexOpen(ref,4)`).
  - `Ownership.Resume` (`Data/Ownership.cls:162-175`) saves without a lock at sign-in. This is a known, harmless stale-write window (Design Notes).
- `Data/Turn.cls`:
  - `State` is free text (line 15). It is `ItemIdIndex`-unique (85). `ClientId` is "empty for a message from another channel" (36).
  - `Conversation.Take` (`Core/Conversation.cls:164-195`) drops an Item whose `ItemId` or `ClientId` already has a turn.
  - `Recap` (625) uses `done` turns only.
  - The queue sweep (230) uses `queued` and `running` turns.
- `Data/Ownership.cls`:
  - The statements are at about lines 600-680: `Turns` 602, `RecentTurns` 606, `TurnByClient` 610, queue 618, last replied 622, `recentNotices` 678 (`Kind IN ('tellnow', 'reminder')`).
  - `Watchers` (410-440) is the cross-owner read to copy: it is prepared with the privilege check and runs in production jobs only.
  - `Decision(ref, sessionRef, .sc)` is at 385-393, and the bridge `ApprovalRequest` open is at 734.
- `Data/Setting.cls` `Get(key, default)` reads public keys too. `Data/Public/Settings.cls` `KEYS` holds `messageAllowance`, seeded at 50 by `Install/Step/Public.cls:116` (read only).
- `Data/Time.cls` has `NowUtc` (18), `Seconds` (27) and `AddSeconds` (42). `OcuTalon.Bridge.Time` (bridge, call only) has `LocalDate(utc)` (34) and `DayEndUtc(day)` (55).

**Channels**
- `Channel/WebChat/In.cls`:
  - `Accept` (51-90) does, in order: dedupe, the row check, `Allowed` (60, which today returns `ERRORREFUSED`), `Trace.Join`, the Item.
  - The seams are `Send(target, request)` (93) and `Allowed` (99). `Allowed`'s one-line body is pinned by `Test/Core/WebChatMessages.cls` `TestAllowedAsksTheAllowance`.
- `Channel/WebChat/Out.cls`:
  - `CARDKINDS = "tellnow,reminder"` (24). Any other kind records a `Delivery` row only (54-57).
  - `Test/Core/WebChatOut.cls` `TestOtherKindsRecordOnly` (177) and `Test/Data/Ownership.cls` (824-848, tied to `CARDKINDS`) pin this.
- `Channel/SimMailbox/In.cls`:
  - `Accept` (91-138): fill a sample, validate, the session row and `SuperSession`, save the `SimMessage`, `Send("Intake")` (a failure deletes the row), `Announce`. The output is `{"ref"}`.
  - The seams are `Send` (140) and `Announce` (146).
- `Data/SimMessage.cls` has `SessionRef`, `Kind` (mailbox), `Direction` (in/out), `CreatedAt` and `SessionRefIndex`.
- `Core/NoticesIn.cls`: `Send(notification)` (21) creates the service in the caller's process. `Join` (37-48) uses the active bridge context's thread, else the notification's `TraceRef`. The class comment (10) names this story's daily-cap message.
- `Core/Rule/Notify.cls` (33-39) already routes `allowance` to `WebChatOut`, and to `TelegramOut` when paired, never to `SimPhoneOut`. `Test/Core/Routing.cls` `TestNotifyTargets` (188-214) pins it. No change.

**Bridge seam**
- `Core/BridgeSink.cls`:
  - `OnEvent` (38-55) quits for a non-session owner at 45, so the `budget.capped` branch goes before it.
  - `Recorded` (114-125) reads the row through `Ownership.Decision`. The row's `Fallback` and `FallbackReason` are `daily_cap` for a capped decision.
  - The seams are `Recipients`/`Receivers` (91-110) and `Publish` (153).
- `OcuTalon.Bridge.Ext.HostSink` (bridge) has `BUDGETCAPPED` (28) and `BudgetCappedPayload(day)` → `{"day"}`.
- `OcuTalon.Bridge.Budget.MarkCapped` (bridge `Budget.cls:104-131`, under a lock, fires once) is called from `Decide.RecordFallback` (`Process/Decide.cls:866-882`). That call follows `decision.recorded`, for the precheck (`Precheck` 589) and for the gateway 403 (`Classify` 676, `DAILYCAPTEXT`).
- `OcuTalon.Bridge.Context.Begin` is called only by the runner (`Bridge/Adapter/Agent.cls:318`). Task 0 (a).
- Bridge `Data/ApprovalRequest.cls`: `OwnerRef` (21), `State` (24), `AnsweredAt` (60).
- `Data/BreakFeedRun.cls`: `SessionRef`, `StartedAt`, and `RecentSessions` (51) as a cross-owner read example.

**Status**
- `Live/Payload/Status.cls`:
  - `CONDITIONS` (10) already starts with `allowance`.
  - `Computed` (57-65) covers the instance conditions. `Active(sessionRef)` (79-83) does not read `sessionRef` yet, and its comment says that Epic 16 adds `allowance`.
  - The builders `DailyCap` (100) and `TelegramPaused` (132) are the models.
  - `Part/StatusSlots.cls` has `Limit`, `Cap` and `Time`. There is no payload shape change, so `web/src/app/live/payloads.ts` stays as it is.
- `Core/StatusMonitor.cls`:
  - Instance loop 37-65: `Remembered` by condition, a silent first run, publish on change.
  - The `ResetSoon` pattern is at 70-104, and the seams `Readings` and `Stream` at 135-145.
  - `Test/Core/StatusMonitorProbe.cls` overrides the seams.

**REST** (`Web/Api.cls`)
- `Messages` (234-251) maps every WebChatIn error to 500.
- `BreakFeed` (312-340) is the model for parsing a service's JSON output.
- `MailAccepted` (383-404) requires `{"ref"}`.
- `Fail` (931-949): its `$Case` has no 429. Its fourth argument is `approval`.
- The MESSAGE parameters are at 69-111. `StateBody` (702-757): `status` at 740, then `idleSeconds` and `AddReset`.
- `ChatItems` (791-836) merges `RecentTurns`, incidents and `RecentNotices`.
- The test seams are in `Test/Web/ApiProbe.cls` (`Post`, `Mail`).

**Page** (`web/src/app/`)
- **Banners:** `banners/banner-view.ts`.
  - `ActionTarget = 'readme' | 'telegram'` (48).
  - `BANNERS` (66-77): `allowance` is first (67), then `dailyCap` (online), `demoBusy`, `noModelKey` (`howToSetKey`) and `costCap`.
  - `BannerFormat` is at 99-110, `textSlots` at 152-158, and `activeBanners`'s href choice at 186.
- **Banner stack:** `banners/banner-stack.ts`. `FORMAT` (18-24) sends both actions to `README_URL`. The status input is at 170-181.
- **README links:** `links.ts:5` `README_URL` (`#readme`, keep). `rail/rail-view.ts` has `TELEGRAM_ANCHOR` (58) and `readmeSection(url, anchor)` (164-167).
- **Outbox:** `chat/chat-outbox.ts`. `post` (88-107) and the online demo's 503 `refuse(entry)` (113-122), with `takeBackTo` for the composer.
- **Composer:** `chat/composer.ts`. The template is at 23-35, and its comment says "It is never disabled" (14). `send` (103), `takeBack` (83).
- **Guide:** `guide/demo-guide.ts`, the prompt bar (161-187). The `'send'` case (173) calls `send(prompt.text)` (539).
- **Chat view:** `chat/chat-view.ts`. `NoticeKind = 'tellnow' | 'reminder'` (129), `noticeOf` (196-224). `chat/notice-card.ts` picks the icon at 104-105.
- **Mailbox:** `mailbox/simulated-mailbox.ts`.
  - The chips (101-113) and the form's Send (162) are `app-server-button` with `describedBy`.
  - `samplePress` (511) and `send` (527) set `chipError`/`sendError`.
  - The texts are `mailbox/mailbox-view.ts` `MAILBOX_TEXTS` (25-41).
- **Shared:** `shared/server-button.ts` has `inactive` and `describedBy` (83-100). `header/header.ts` (155-170) shows the aria-disabled-with-reason pattern.
- **Live:** `live/reset-watch.ts` (86-105) arms a timer to a UTC time. `live/demo-busy-state.ts` is a root service the banner stack reads. `live/live-store.ts` (51, 177) keys `status` by condition across both streams.
- **API:** `api/api-client.ts` (`postMessage` 47, `accepted` 125) and `api/api-types.ts` `ApiError` (134).

**Tests and units**
- `Test/Core/WebChatMessages.cls` (`TestRefusalQueuesNothing` 119, `TestRefusedAndDuplicateMessagesTouchNoThread` 359). `Test/Core/WebChatInProbe.cls` refuses with `Refuse=1` and `retryAt` 2030.
- `Test/Core/TelegramCalls.cls:34-42`: its assertion text "the gate refuses nothing yet" goes stale.
- **`Test/Core/BridgeSink.cls`:**
  - DW-300 lines 287-295, 327-331, 374-378 and 398-404 (`Fixture.Check` with no `NextDueAt`).
  - `Events` (609-612) is untyped.
  - Lines 198-203 assert that `budget.capped` publishes nothing.
- `Test/Web/Api.cls` `TestStateSections` (328): `check1` and `check2` are seeded due at once (334-335), and line 398 asserts `check2` has no run.
- **Fixtures:**
  - `Test/Data/Fixture.cls` has `Check(s, ns, prod, fields)` (65) and `Approval(owner, incident, state, raisedAt, fields)` (102), with no `RequiredRole` by default.
  - `Test/Watch/Case.cls` `Ahead()` (467) gives now + 86400 s (read only).
- `Test/Data/Tables.cls` pins the `Session` columns at 272-290.
- `Test/Live/Status.cls` (`TestComputedDailyCap` 50). `Test/Web/MailboxApi.cls`. `Test/Demo/SimMailboxIn.cls` (`TestRefused`, ~268).
- **Node tests** (`web/scripts/*.test.mjs`, run by `npm --prefix web test`): `banner-view` (188-191 pin `README_URL` hrefs), `chat-view`, `mailbox-view`, `playwright-projects`, `ux-strings`, `api-client-sources`.
- **Browser specs that pin `#readme` hrefs:** `web/e2e/banners/banners.spec.ts` (46, 189, 307, 345-346, 401) and `web/e2e-online/busy.spec.ts` (36, 74).
- **Live units:**
  - `docker/tests/test-online-session.sh` is the model for a unit. It uses `lib-live.sh` and `lib-online.sh` (`online_override` 44-64: `MESSAGE_ALLOWANCE 50`, `DAILY_COST_CAP_USD 20`, `online_values`).
  - `docker/tests/test-online-demo.sh` `keys_point` (1280-1295) points the runners' keys at the mock (`Test.Agent.RunnerFixture`, `RestoreKeys`).
  - The mock's request log is mounted at `/opt/ocutalon/mock-log`.
- **Browser helpers:**
  - `web/e2e-online/support.ts`: `signInFromSplash` 51, `signOutGroup` 28, `openSession` 68, `epochOf` 61, `sessionRow` 154, `setPublic` 216, `populate` 321, `fixtureTurn` 400.
  - `web/e2e/support/iris.ts`: `irisScript` 90, `seedTurns`/SeedUsage 237-382, `seedApproval` 712.
  - `web/playwright.config.ts` (59-63): the `online-demo` project ignores `session/`; `workers: 1`.
- **CI lists** (`ci/units.sh`):
  - `group_units` install-upgrade: `live:install-upgrade live:audit`;
  - `BROWSER_UNITS`.
  - The last green `ci` run of this branch (40813183274) had install-upgrade at 13.7 min, the shortest group, against image's 40 min.
- **README check:** `docker/tests/test-readme.sh` `inventory`/`chk_product_links` (603-633) checks every `jbrandtmse/OcuTalon#x` in `src/**/*.cls` and every `*_ANCHOR = 'x'` in `web/src/app/**/*.ts` against the README headings. The `#readme` anchor must stay in the inventory. The README has `## Install it yourself` (50) and `## Set a model key` (126).

## Tasks & Acceptance

**Execution:**
- **Task 0, measure before building** (record the results under Design Notes > Implement pass):
  - (a) **Read** the call chain of `Decide.RecordFallback` for both `daily_cap` paths. Confirm that no bridge context is active in the job that fires `decision.recorded` and `budget.capped`, so that `NoticesIn` gives each notice its own session's `TraceRef`.
    - If one can be active, give `Core/NoticesIn.cls` a branch: a notification whose `SessionRef` differs from the context's session gets its own `TraceRef`.
    - Pin that branch in `Test/Core/NoticesIn.cls`.
  - (b) On the first run of `live online-allowance`, record as `MEASURED` lines the unit's seconds, the browser step's seconds and the 429 round trip.
- **`Data/Session.cls`.** Append three properties to storage as Values 11-13, and update the class comment:
  - `AllowanceTimes As %List`: the UTC times of the session's accepted messages in the rolling hour, oldest first, at most `Limit()` entries;
  - `AllowanceUntil As %String(MAXLEN = 20)`: the `retryAt` of the window that has had a refusal, otherwise "";
  - `DailyCapDay As %String(MAXLEN = 10)`: the instance-zone date on which the daily-cap message was sent.
- **`Data/Ownership.cls`.**
  - `RecentTurns` leaves out `State = 'refused'`.
  - `recentNotices` gains `'allowance'`.
  - Add `ActiveVisitors(Output sc) As %List`. It lists every row with a `ResumeHash` and at least one of: a `Turn`, a `BreakFeedRun`, or an owned bridge `ApprovalRequest` the user answered (`AnsweredAt` set and an approve or reject action; check the columns in `ApprovalRequest.cls`).
  - Add `AllowanceHeld(now, Output sc) As %List`: the rows with `AllowanceUntil > now`.
  - Both of those are cross-owner reads, prepared with the privilege check like `Watchers`.
  - Add `IncomingMail(sessionRef, since, Output oldest, Output sc) As %Integer`: an own-session read, prepared like the other own-session statements. It counts the session's `SimMessage` rows with Kind mailbox, Direction in and `CreatedAt > since`, and returns the oldest `CreatedAt`.
- **`Core/Allowance.cls`.**
  - **Parameters:** `WINDOW = 3600`, `LOCKWAIT = 5`, `EMAILLIMIT = 20` and `INSTALLLINK = "https://github.com/jbrandtmse/OcuTalon#install-it-yourself"`.
  - **`TryConsume`:** matrix rows 1-8, under the row lock. The two saves of a refusal share one transaction.
  - **`Refund(sessionRef)`:** removes the newest entry under the lock. With the flag off it does nothing, and it never throws.
  - **`Limit()`:** see Always.
  - **`Until(sessionRef, now = "")`:** `AllowanceUntil` when it is later than now, otherwise "".
  - **`Notice(sessionRef, retryAt) As OcuTalon.Msg.Notification`:** the row 2 notification.
  - **`DailyCapNotice(sessionRef, resetsAt)`:** Kind allowance, key `conversation.dailyCap`, slots `{time, readmeLink}`.
  - **`MailAllowed(sessionRef, now, Output retryAt, Output sc) As %Boolean`:** 1 with the flag off; otherwise uses `IncomingMail` with `EMAILLIMIT`.
  - **The class comment** states the window, the refused `Turn` and the flag rule.
- **`Channel/WebChat/In.cls`.**
  - **A refusal with `retryAt` ""** answers the error status `ERRORREFUSED` (row 8).
  - **Any other refusal**, before any Join:
    - on `firstRefusal`, it sets `%SessionId` "" and `%SuperSession` `TraceRef`, and calls `Send("Notify", Allowance.Notice(...))`;
    - it answers OK with the refused output (row 2).
  - **A failed Item send** calls `Allowance.Refund` (row 9).
  - **The class comment** loses "sends only to Conversation". Add `Parameter NOTIFY = "Notify"`.
- **`Channel/SimMailbox/In.cls`.**
  - After the row check, it takes the session row's `%LockId` (5 s; busy is an error status) across `MailAllowed` and the `SimMessage` save, and releases the lock before `Send` and `Announce`.
  - A refusal answers OK with `{"refused":1,"retryAt"}` and records, sends and publishes nothing (row 17).
  - Update the class comment.
- **`Web/Api.cls`.**
  - Add `Parameter HTTP429TOOMANYREQUESTS = "429 Too Many Requests"`.
  - `Fail` gains a 429 case and a fifth optional argument, `extra As %DynamicObject`, whose members follow `"error"`.
  - Add `MESSAGEALLOWANCE` and `MESSAGEEMAILLIMIT` (V2).
  - `Messages` parses the service's output like `BreakFeed`: refused gives 429 `allowance` with `retryAt` and `limit`. Update its doc comment.
  - `MailAccepted` parses the output: refused gives 429 `email_limit` with `retryAt`. Otherwise it behaves as today.
- **`Live/Payload/Status.cls`.**
  - Add `Allowance(sessionRef, now = "") As OcuTalon.Live.Payload.Status`. It is active when the flag is on and `Allowance.Until` is not "", and its slots are `Limit` and `Time`.
  - `Active(sessionRef)` puts it first when it is active (row 10). `Computed` is unchanged.
  - Update the class and method comments.
- **`Core/StatusMonitor.cls`.**
  - Add the property `RememberedAllowance [MultiDimensional, Private]` and the private seam `AllowanceSessions(now, Output sc) As %List` (`Ownership.AllowanceHeld`).
  - Add `AllowanceTick(first)`, run after the instance loop with the run's `first` flag, on the online demo only.
  - For every held or remembered session it builds `Status.Allowance` and publishes to that session's stream when the view changed. It remembers active views, and forgets one once its clear is published (row 11).
  - Update the class comment.
- **`Core/BridgeSink.cls`.**
  - Before line 45, `OnEvent` sends `budget.capped` to a new private `Capped(ownerRef, payload)`. With owner `instance`, the flag on and a `{day}` of the form YYYY-MM-DD, `Capped` calls `DailyCap` for each of `Visitors(.sc)`. `Visitors` is a private seam over `Ownership.ActiveVisitors`. A failed read is a warning naming the event.
  - In `Recorded`: with the flag on, a `Fallback` row whose reason is `daily_cap` calls `DailyCap(ownerRef, Bridge.Time.LocalDate(row.RecordedAt))`.
  - `DailyCap` [Private] takes the row lock for at most `LOCKWAIT` (1 s), sets `DailyCapDay` once, then sends `Notice(Allowance.DailyCapNotice(ref, Bridge.Time.DayEndUtc(day)))` through the private seam `Notice` → `NoticesIn.Send`. A busy lock or a failed send is a warning.
  - Rewrite the class comment's "budget.capped ... do nothing".
- **`Channel/WebChat/Out.cls`.**
  - `CARDKINDS = "tellnow,reminder,allowance"`.
  - Update the class comment. The text is rendered with `web`, and no `FallbackReason` is kept for it.
- **`web/src/app/banners/banner-view.ts` and `banner-stack.ts`** (DW-361).
  - `ActionTarget` becomes `'install' | 'setKey' | 'telegram'`. Every `bannerAction.installYourself` row targets `install`, and `howToSetKey` targets `setKey`.
  - `BannerFormat`'s `readmeUrl` becomes `installUrl` and `setKeyUrl`. `FORMAT` builds them with `readmeSection(README_URL, INSTALL_ANCHOR)` and `readmeSection(README_URL, SET_KEY_ANCHOR)`, with `const INSTALL_ANCHOR = 'install-it-yourself'` and `const SET_KEY_ANCHOR = 'set-a-model-key'`.
  - Export the function that renders a banner's text, so that the composer and the guide reuse it.
  - The stack takes the `allowance` condition from `AllowanceState`.
- **`web/src/app/live/allowance-view.ts` (new) and `web/src/app/live/allowance-state.ts` (new).**
  - The view is a pure, Node-runnable function `allowanceOf(condition, refusal, nowMs)`. It gives `{limit, time}` for the store's active condition or for a 429's `{limit, retryAt}`, whichever holds a future time, and undefined otherwise.
  - The root service holds the latest refusal (`refused({limit, retryAt})`) and a clock that a timer re-arms at the next time (as `reset-watch.ts` does). It exposes `active()`.
- **`web/src/app/api/api-types.ts`.** Add `ApiRefusal {error: {code, message}; retryAt: string; limit?: number}`, the body that a 429 `HttpErrorResponse.error` carries. `api-client.ts` keeps its calls.
- **`web/src/app/chat/chat-outbox.ts`.**
  - A 429 whose `error.code` is `allowance` calls `AllowanceState.refused`, then the existing `refuse(entry)`.
  - When `refuse` returns false, the entry fails as today.
  - Update the doc comment.
- **`web/src/app/chat/composer.ts`.**
  - While `AllowanceState.active()` holds:
    - the reason `<p id="composer-allowance-reason">` (the banner's text) sits above the field;
    - the textarea and Send get `aria-disabled="true"` and `aria-describedby` set to that id;
    - `send()` and Enter return early, and the text is kept.
  - Rewrite "It is never disabled".
- **`web/src/app/guide/demo-guide.ts`.**
  - While it holds, each `'send'` prompt button gets `aria-disabled` and `aria-describedby="guide-allowance-reason"`, the reason `<p>` shows in the prompt bar, and a click is ignored.
  - The other actions are unchanged.
- **`web/src/app/chat/chat-view.ts` and `notice-card.ts`.** `NoticeKind` adds `'allowance'`, and `noticeOf` takes it. The card has no strip and no caption, and uses the `circle-alert` icon and the danger accent (Decided).
- **`web/src/app/mailbox/mailbox-view.ts` and `simulated-mailbox.ts`.**
  - Add `MAILBOX_TEXTS.emailLimit` (E:308). Its `{time}` is `pageTime`.
  - A 429 `email_limit` sets `limitUntil`, which is cleared by a timer at `retryAt`. The chips and Send get `[inactive]` and `describedBy`, which names a visible reason `<p>` in each view. No error text is shown for it.
- **`docker/tests/lib-online.sh` and `test-online-demo.sh`.** Move `keys_point` and its restore into `lib-online.sh` unchanged, and source them from both units.
- **New unit `docker/tests/test-online-allowance.sh`.**
  - It starts a flag-on throwaway with `online_override`, points the keys at the mock, runs the Playwright project `online-allowance`, runs the IRIS checks, and prints PASS or FAIL lines.
  - It uses the lane's deadline and the EXIT-trap teardown, like `test-online-session.sh`.
- **`web/e2e-online/allowance/messages.spec.ts` (new).**
  - **A1:** sign in from the splash, then 50 `POST /api/v1/messages` through `page.request` (distinct `clientId`s, all 202). Then type the 51st in the composer. Assert:
    - the 429;
    - the banner first, with no Close and its href `#install-it-yourself`;
    - the composer and the guide send prompts have `aria-disabled` and `aria-describedby` pointing to a visible reason equal to the banner text;
    - the typed text is back in the field;
    - exactly one allowance notice card;
    - a 52nd post through the API gets a 429 and adds no second card;
    - the refused `Turn` rows are State refused with no `ClientId`, and no queued turn exists for them;
    - Break the feed's `aria-disabled` is unchanged from before the refusal.
  - **A2:** a new session whose `AllowanceTimes` is seeded with 50 entries about 3580 s old (`irisScript`). The 51st is refused with `retryAt` about 20 s ahead. Within 45 s:
    - the banner clears and the controls return;
    - the session's `GET /api/v1/events` carries an `allowance` `status` event with `active` false;
    - a send gets 202.
  - **E1:** 20 posts through `page.request`, mixing samples and incoming, then a chip press. Assert the 429, that the chips and Send have `aria-disabled` with the email text (page time), and that no 21st row, Item or `mailbox` event exists.
  - **E2:** a new session with 20 incoming `SimMessage` rows seeded about 3580 s old. A form Send is refused, and within 45 s the chips and Send return and a press gets 202.
  - Every case signs out.
- **`web/e2e-online/allowance/daily-cap.spec.ts` (new).** It runs serially. A `finally` deletes the seeded `Usage` row and kills the day's mark.
  - **D1:**
    - S3 signs in and sends one message. S2 signs in and stays idle.
    - A `Usage` row of $20 is seeded for today.
    - S1 sends, and its reply is the `daily_cap` fallback.
    - Assert:
      - S1 has one `conversation.dailyCap` card, with an "ET" time and the install link;
      - S3 has one, from the broadcast;
      - S2 has none until its own send, then one;
      - another send from S1 adds none;
      - the online `dailyCap` banner shows on all three, once S1's fallback has marked the day. In a web process `Budget.State()` counts only the mark and the gateway spend (its `NOPRIVILEGE` fault), while `StatusMonitor` reads the spend itself;
      - the composer stays usable;
      - `DailyCapDay` is today on all three.
  - **D2:** the clean state, then `[[mock:daily-cap]]` from S4. Assert the `daily_cap` fallback, one request in the mock log, the day marked, the banner, and one card.
  - **AP:** S1, still capped, has an allowance window (seeded `AllowanceTimes` and one 429), plus a real Orders watch started through `Commands.Submit`.
    - A fixture approval (`Fixture.Approval`) answered through `OcuTalon.Bridge.Approval.Answer` returns `done`.
    - A Break the feed press answers 200.
- **`web/playwright.config.ts`.**
  - Add the project `online-allowance` (`./e2e-online/allowance`, Desktop Chrome).
  - The `online-demo` project's `testIgnore` adds `**/e2e-online/allowance/**`.
  - Update `web/scripts/playwright-projects.test.mjs`.
- **`ci/units.sh`.**
  - `install-fresh` becomes `live:install-start live:bundle-folder live:online-session live:online-allowance` (lead, spec gate: Story 16.4's CI rework moves `live:online-demo` into `install-upgrade`).
  - Add `online-allowance` to `BROWSER_UNITS`.
  - Update `docker/tests/test-ci-config.sh` and `test-ci-changes.sh` expectations only if they list the units.
- **IRIS unit tests, for the matrix edge cases:**
  - **New `Test/Core/Allowance.cls`**, rows 1-9:
    - the 50 and 51 boundary, mixed channels, `retryAt` arithmetic;
    - the first-refusal flag across two windows, using seeded `AllowanceTimes`;
    - the refused `Turn`'s fields, telegram included;
    - flag off, no row, a lock held by another job (`$Job` probe), `Refund`;
    - `Limit()` with bad values;
    - `MailAllowed` at 19, 20 and 21 with outgoing rows ignored;
    - `Conversation`'s source names no `OcuTalon.Core.Allowance`.
  - **`Test/Core/WebChatMessages.cls`:** update `TestRefusalQueuesNothing` (an OK status with the refused output, no Item, one Notify send on the first refusal and none on a later one), and add a case for the refund and for a lock error.
  - **`Test/Core/WebChatInProbe.cls`:** record the target of each send.
  - **`Test/Core/TelegramCalls.cls`:** reword the stale assertion.
  - **`Test/Web/Api.cls`:**
    - 429 `allowance` with exactly `{error, retryAt, limit}`;
    - an error with an empty `retryAt` gives 500;
    - `/state` puts `allowance` first, with key order kept;
    - DW-300: `TestStateSections` seeds `check1` and `check2` with `{"NextDueAt": (##class(OcuTalon.Test.Watch.Case).Ahead())}`, keeps `check1`'s later 2030 values, and asserts that `check2`'s `NextDueAt` is more than 23 h after now.
  - **`Test/Web/MailboxApi.cls`:** 429 `email_limit` for incoming and for a sample.
  - **`Test/Demo/SimMailboxIn.cls`:** the 21st refused, with no row, Item or event, samples counted, and flag off unlimited.
  - **`Test/Live/Status.cls`:** `Allowance`, and its place in `Active`.
  - **`Test/Core/StatusMonitor.cls` and its probe:** publish on a refusal, clear at `AllowanceUntil`, a silent first run, the session's stream only, and instance events unchanged.
  - **`Test/Core/BridgeSink.cls` and `BridgeSinkProbe.cls`:**
    - a `Notice` seam recorder;
    - `budget.capped` reaches only the active open sessions, once;
    - the `decision.recorded` daily_cap path, and a second fallback that does nothing;
    - with the flag off, nothing on either event;
    - a busy row lock gives up within 1 s;
    - lines 198-203 still publish nothing;
    - **DW-300:** the four methods seed with `{"NextDueAt": (##class(OcuTalon.Test.Watch.Case).Ahead())}`, and assert that each seeded row's `NextDueAt` is more than 23 h after now. `Events(session, type = "")` counts only the type that a caller names (`approval` in those methods).
  - **`Test/Data/Ownership.cls`:** `ActiveVisitors` (each activity kind, an ended row left out), `AllowanceHeld`, `IncomingMail`, `RecentTurns` without refused turns, and `recentNotices` with allowance.
  - **`Test/Data/Tables.cls`:** the three columns.
  - **`Test/Core/WebChatOut.cls`:** `allowance` is a card (the rendered "ET" text and the event), and `TestOtherKindsRecordOnly` keeps the other kinds.
- **Node tests:**
  - `banner-view.test.mjs`: install and set-key hrefs for every action row, and the allowance text that is reused.
  - `allowance-view.test.mjs` (new): the store condition, a refusal, both, a past time, and undefined.
  - `chat-view.test.mjs`: an allowance notice.
  - `mailbox-view.test.mjs`: the email text with page time.
  - `ux-strings.test.mjs`: a SOURCES entry for E:308.
- **Browser hrefs:** `web/e2e/banners/banners.spec.ts` and `web/e2e-online/busy.spec.ts` expect `#install-it-yourself` and `#set-a-model-key` in place of `#readme`.

**Acceptance Criteria:**
- **AC 1, the message allowance.** **Given** an online-demo session with 50 messages in the past rolling hour, **when** it sends another from the web chat, **then**:
  - `POST /api/v1/messages` answers 429 with `retryAt` and `limit`;
  - `TryConsume` has recorded a refused `Turn`;
  - no Item reaches `Conversation`;
  - no model is called;
  - `Conversation` never checks the allowance.
  - Pinned by live A1, `Test.Core.Allowance`, `Test.Core.WebChatMessages` and `Test.Web.Api`.
- **AC 2, Telegram.** **Given** a fixture `TryConsume(..., "telegram", ...)` at the limit, **when** it is called, **then** it is refused as in row 4, with the refused `Turn` and the first-refusal flag, and no Epic 12 code is involved (`Test.Core.Allowance`).
- **AC 3, the notice.** **Given** the first refused message of a window, **when** `WebChatIn` handles it, **then** the chat shows exactly one card with "You've used this session's 50 messages for the hour. You can send more at {HH:MM} ET, or install OcuTalon yourself to keep going: https://github.com/jbrandtmse/OcuTalon#install-it-yourself". Further refusals send nothing. `Notify` sends it to the web chat and the paired chat only, never the phone (A1, `Test.Core.WebChatOut`, `Test.Core.Routing`).
- **AC 4, the banner and the controls.** **Given** the session's `allowance` condition, **when** the page shows it, **then** row 12 holds, including the clear at `retryAt` in both the page and `StatusMonitor` (A1, A2, node tests).
- **AC 5, the daily cap.** **Given** the online demo's cap, **when** it is reached by IRIS's count or by the gateway's 403, **then** rows 13-16 hold (D1, D2, `Test.Core.BridgeSink`).
- **AC 6, the local cap.** **Given** a local install whose day is capped, **when** the cap is reached, **then** the `costCap` banner shows and no chat message is sent (`Test.Core.BridgeSink` with the flag off, `banner-view.test.mjs`).
- **AC 7, the email limit.** **Given** 20 simulated emails in the past hour, **when** the 21st is sent from the form or a chip, **then** row 17 holds, and the controls return at `retryAt`. A local install has no limit (E1, E2, `Test.Demo.SimMailboxIn`, `Test.Web.MailboxApi`).
- **AC 8, approvals under both caps.** **Given** both caps holding, **when** a fixture approval is answered through `Approval.Answer` and Break the feed is pressed, **then** both complete (AP).
- **AC 9, DW-300.** **Given** a real heartbeat tick during `Test.Core.BridgeSink`'s four methods or `Test.Web.Api.TestStateSections`, **when** it runs, **then** no seeded check row is due, and the counts take only the named event type. Each method asserts that its seeded rows' `NextDueAt` is more than 23 h after now.
- **AC 10, DW-361.** **Given** any banner with "Install it yourself" or "How to set a key", **when** it renders, **then** its href is `https://github.com/jbrandtmse/OcuTalon#install-it-yourself` or `#set-a-model-key`, and `test-readme.sh` passes.

### Lead addition at the spec gate (DW-220 residual, 2026-10-29)

- [ ] DW-220 (residual, routed to this story by 16.4's re-review): with `live:online-demo` in `install-upgrade` (Story 16.4's CI rework, 0d98165), the `image` job still sums to about 2047 s on CI (run 40866408272: storage-roundtrip about 257, build-inputs 9, compose-start 200, demo-switch 467, shard:lane-b 866, install-script-live about 213), about 34.6 minutes against REL-4's 35-minute run budget, and DW-220's reopen_if (30 minutes) is still met. Rebalance in `ci/units.sh`, moving only Lane B's own units (this epic keeps Lane B's files: `shard:lane-b`, `live:demo-switch`, `live:online-demo`, `live:online-session`, and this story's `live:online-allowance`; never Lane A's or Epic 10's `install-script-live`), so that no IRIS job is expected to pass about 1800 s, using the CI times above and install-fresh 1339 s (with online-session), install-upgrade about 1355 s (with online-demo), production 942 s, browser 1464 s, shards 1896 s. `production` must stay web-bundle-free: a unit that needs the web bundle or a browser cannot go there (check what `shard:lane-b`'s classes need before considering it). Record the expected job times in `## Design Notes`, update every expectation that pins the groups, and cite DW-220; if no arrangement keeps every job near 30 minutes, keep the best one and say so (owner-fixed value 9: after the rebalance, CI capacity is the owner's action). — `ci/units.sh`, `docker/tests/test-ci-config.sh`, `test-ci-changes.sh` — `bash ci/checks.sh` passes.

## Spec Change Log

- 2026-10-29, lead (after Story 16.4's CI re-review): DW-220's residual (the image job about 2047 s) added as a Tasks item; owned_ledger now DW-220, DW-300, DW-361.

- 2026-10-29, lead spec gate: `live:online-allowance` goes to `install-fresh`, not `install-upgrade`, because Story 16.4's CI rework (DW-220) moves `live:online-demo` into `install-upgrade`. V1 and V2 ruled keep as veto items U-151 and U-152; V3 written as spine Conventions rows (the REST row, the Notice cards row, a new Allowances row), AD-20's Rule unchanged.

## Review Triage Log

### 2026-10-29 - Review pass
- verdicts: 44 findings - high 0, medium 5, low 34, false 5, maybe-false 0
- findings:
  - Blind Hunter
    - `[low]` `[reject]` Refused messages are written without limit (one `Turn` per refusal, the full text) - matrix row 3 says "Another refused Turn is recorded" and AD-20 records each refusal; the demo's reset (P10) bounds the rows; spec-bound, not worth a rate limit that the spec does not name.
    - `[low]` `[reject]` The 429 carries no `Retry-After` header - the 429 body is fixed by row 2 and V2 as `{error, retryAt, limit}`; a header adds a public surface nobody consumes.
    - `[false]` `[reject]` `Messages()` reads the refusal output less strictly than `MailAccepted` - `WebChatIn` answers an error status when `retryAt` is empty and always writes `retryAt` and `limit` otherwise, so the output the unchecked members come from cannot lack them.
    - `[low]` `[patch]` `Data/Turn.cls` still says State is "queued, running or done" - one doc line now names `refused` (patched).
    - `[low]` `[patch]` `incomingMail` is missing from the refusal loop of `Test.Data.Ownership` - added to the loop (patched).
    - `[low]` `[reject]` The cap fan-out runs inside the bridge's decision call - row 13 defines it; at the demo's capacity (about 6 visitors, P12) it is a few sends, and a lock waits 1 s only when busy.
    - `[low]` `[reject]` No concurrent-burst test for the row lock - the lock is `Core.Trace`'s established pattern, a held-lock probe pins the busy path, and a multi-job race test costs far more than 15 lines.
    - `[low]` `[patch]` Two stale comments (the `Test.Core.StatusMonitor` header names methods that do not exist; `playwright.config.ts` says "Nine projects" and lacks `online-allowance`) - both comments corrected (patched).
    - `[low]` `[patch]` Fixed sleeps and A2's `[true, false]` needing a monitor run inside an about 18 s window - A2's window is now about 30 s (patched); the absence checks keep their fixed waits because an absence cannot be polled.
    - `[low]` `[reject]` The same values (20, the install URL) are written in several places - each copy is mandated (the REST message, the UX text, `INSTALLLINK`, the independent oracles of the specs); no consumer reads one from another.
    - `[low]` `[patch]` `DailyCap` ignores a failed revert save - the failure is now a warning (patched, with the Edge Case Hunter's exception finding).
    - `[low]` `[reject]` The email limit is not rebuilt after a reload - Design Notes decide it: the page learns it from the 429 and `/state` carries no field for it.
    - `[false]` `[reject]` The spine does not list `email_limit` - the spine's REST row lists `email_limit` and the `limit` member (amended 2026-10-29, veto U-152, line 921), and the Allowances row is there (line 926).
  - Edge Case Hunter
    - `[low]` `[reject]` `MailAllowed`'s `retryAt` when the count is above 20 - row 17 fixes `retryAt` as the oldest plus 3600 s, and under the row lock with the flag on the count cannot pass 20.
    - `[low]` `[patch]` `DailyCap` sends nothing and logs nothing for an unreadable day - a warning that names the day is logged (patched; pinned in `TestBudgetCappedBadInputsSendNothing`).
    - `[low]` `[patch]` `DailyCap` leaves `DailyCapDay` set when `Notice` throws - the send is wrapped, the day is taken back and a failed take-back is a warning (patched; pinned in `TestFailedDailyCapSendIsRetried`).
    - `[low]` `[reject]` The `budget.capped` fan-out can stall the firing job - same as the Blind Hunter's fan-out finding.
    - `[low]` `[reject]` `StatusMonitor`'s allowance first-run flag stays true when `Readings` throws on every run - a persistent `Readings` failure also fails `/state`, so no allowance can show; the first good run recovers.
    - `[low]` `[reject]` A client clock off from the server's moves the page's clear - the spec puts the clear at `retryAt` on the page's clock.
    - `[low]` `[reject]` Unbounded refused `Turn` rows from scripted posts - same as the Blind Hunter's first finding.
    - `[low]` `[reject]` Retry on a failed entry while the window is open posts again and records another refused `Turn` - harmless, not in row 12, and reached only through the "composer holds other text" case.
    - `[low]` `[reject]` A clientId re-posted before `Conversation` makes its `Turn` counts twice - Design Notes accept it (bounded at one per retry).
    - `[low]` `[reject]` `Off()`, `RefIndexExists` and `%LockId` sit outside `TryConsume`'s Try - a global read, a generated index lookup and a call that returns a status; none throws on a reachable input.
    - `[low]` `[patch]` `SimMailboxIn` takes the row lock with the flag off, against "flag off changes nothing" - the lock is taken only on the online demo (patched; pinned by the flag-off busy-row case of `TestEmailLimit`).
    - `[low]` `[patch]` The `ci/units.sh` comment says no group is expected to pass about 1800 s, which the recorded times do not show - the comment now says only that the Lane B units are spread to even out the times (patched).
  - Verification Gap
    - `[medium]` `[patch]` The Composer and DemoGuide guards that ignore presses are pinned by no test - A1 now presses Send (forced, the control is aria-disabled), presses Enter in the field and clicks the guide prompt, and asserts no `POST /messages` and the text kept (patched; mutations on both guards red).
    - `[medium]` `[patch]` `WebChatIn.Refund` is mocked away in its only test - `TestFailedSendRefundsTheRealAllowance` runs the real forwarder on the real allowance through a `RealRefund` probe option (patched; mutation red).
    - `[low]` `[patch]` `TestStateSections` asserts `NextDueAt` for `check2` only - `check1` too (patched; mutation line added).
    - `[medium]` `[patch]` The 429-to-banner wiring is checked only through a race with the monitor's tick - A1 and A2 assert the banner within 2 s of the 429 (patched; mutation red).
    - `[medium]` `[patch]` `TestActiveVisitors` never observes the ended-session exclusion (an assertion that cannot fail) - it asserts the ended session is absent from the full list (patched; mutation red).
    - `[medium]` `[patch]` `TestBudgetCappedSendsToEachActiveSessionOnce` is not self-contained (the real read writes `DailyCapDay` into other sessions) - it cuts the real read down to its own fixtures (patched; mutation red).
    - `[low]` `[reject]` The `StatusMonitor` failed-read test's "nothing remembered" parts cannot fail - the warning count and the final "the run that reads again publishes" carry the case; the stale header is patched with the comments.
    - `[low]` `[reject]` `TestConversationNamesNoAllowance` is source text - the Tasks name it, it repeats an existing rule, and A1's exact refused-Turn list goes red if `Conversation` counted.
    - `[low]` `[reject]` Fixed sleeps in the absence checks - an absence cannot be polled; each fails loudly when late.
    - `[low]` `[reject]` Some mutation lines pin one half of a bundled AC - Rule 19 asks one demonstrated mutation per AC; the patches add lines for the new pins.
  - Intent Alignment Auditor
    - `[false]` `[reject]` The page wiring is checked only by the browser specs - the live specs run the real components against the real stack; the node tests cover the pure views.
    - `[low]` `[reject]` No new test for a guide prompt's 429 ("a guide entry just leaves") or for a 429 with other text in the composer - both reuse `ChatOutbox.refuse`, which Story 16.5's 503 cases pin.
    - `[low]` `[reject]` AP answers the approval through `Approval.Answer`, not the page's buttons - the spec's AP says so.
    - `[low]` `[patch]` "Flag off changes nothing" is checked per method, and `SimMailboxIn` locked with the flag off - same patch as the Edge Case Hunter's lock finding; `Messages()` parsing the output on every post gives the same result for an accepted output.
    - `[low]` `[reject]` Telegram is exercised only as a `TryConsume` fixture - the spec keeps the Telegram cases off until Story 31.3.
    - `[low]` `[reject]` The daily-cap banner is asserted after a fallback marks the day, not when spend reaches the cap - the spec's D1 says why (`Budget.State()` in a web process counts only the mark and the gateway spend).
    - `[false]` `[reject]` Seam-level versus composed tests - the composed chain (`TryConsume`, REST, `Notify`, `WebChatOut`, `NoticesIn`) runs in the live A1, D1 and D2.
    - `[false]` `[reject]` The two REST message literals are outside the contract's text list - veto item V2 (U-152) rules them kept, and the spine's REST row records them.
    - `[low]` `[reject]` `test-online-allowance.sh` never calls `keys_restore` - the unit's own stack is removed by the EXIT trap, so no key entry outlives it.

## Design Notes

**Architecture decisions** (each Rule checked; no AC contradicts one; no NFR is unmeasurable):
- **AD-20** governs:
  - `TryConsume`: synchronous, under a per-session lock, before queueing; it returns allowed, `retryAt` and the first-refusal flag; it records the refused `Turn`;
  - the 429 with `retryAt`;
  - `Conversation` never checks the allowance;
  - "The day's cap, once";
  - `Budget.State()` as the only read of the cap;
  - the once-a-day message to active sessions, recorded on `Session`.
- **AD-12:**
  - `allowance` and `dailyCap` come from the closed catalog, computed on read and published by `StatusMonitor`, the one publisher of `status`;
  - payloads are full views;
  - the online demo only polls.
- **AD-14:** kind `allowance` goes to the web chat and the paired chat only. The routing is unchanged.
- **AD-31:**
  - `budget.capped` with `{day}` and owner `instance`;
  - `BridgeSink` is the one sink: asynchronous notices through `NoticesIn`, at most 1 s on a lock, and it never fails its caller.
- **AD-32:**
  - `Notification` carries a key and slots, with UTC times;
  - only `*Out` renders;
  - kind `allowance` covers both the session allowance and the daily cap.
- **AD-33:**
  - `WebChatOut` stays the `notification` publisher, `Conversation` the `chat.message` publisher, and `StatusMonitor` the `status` publisher;
  - `Session` and `Turn` stay Lane B's;
  - `Allowance` is the second writer of `Turn` that AD-20 sanctions.
- **AD-30:** `Conversation` alone owns the queue, and a refused `Turn` is never queued.
- **AD-1:** channel inputs enter through the business services, and REST still writes nothing new itself.
- **AD-4:** `SessionRef` always comes from the server, and the activity reads are per session.
- **AD-19:** `messageAllowance` is a public key, and `DailyCostCapUSD` stays on `Decide`.
- **AD-26:** the notices' `SuperSession` is the recipient's `TraceRef`.
- **AD-22 and AD-29:** throwaways only, and the Telegram cases stay off.
- **AD-8:** `daily_cap` is never re-sent. That is the bridge's job, which this story only observes.

**Decided in-stage:**
- **The refused message is never shown in the chat.** It returns to the composer, as Story 16.5's 503 does.
  - `chat.message` has one publisher (`Conversation`), so a refused `Turn` in the snapshot would never arrive as an event, and the snapshot and the events would drift (AD-12). It also would not reach Telegram's page view.
  - The composer is `aria-disabled` with its reason (UX-DR68), so the kept text can be sent at `retryAt`.
  - No new text is needed: the banner and the one notice explain.
  - The refused `Turn` is the AD-20 record: State `refused`, no `ClientId`, so a later resend is never a duplicate. It is left out of `RecentTurns`, the queue and the recap.
- **The `allowance` condition runs from the first refusal of a window until its `retryAt`.** It does not start at the 50th message.
  - This gives the AC's 429 for the 51st from the page, and the notice "once" of UX-DR96.
  - The banner text ("You've used ... messages") is true throughout.
- **A window** is the time from its first refusal until `retryAt` (`AllowanceUntil`). With a rolling hour, `retryAt` stays fixed inside a window.
- **The counts live on the `Session` row and are written under its lock.** `Turn` rows are made asynchronously by `Conversation` (`Take`), so counting them would let a burst pass the limit. The AD's "per-session lock" is the row lock that `Core.Trace` already uses, so these writes serialize with the trace writes.
- **Edge cases of `TryConsume` and the counts:**
  - **A session with no row** (flag on) is allowed and recorded nowhere. `WebChatIn` and `Conversation` already refuse such a message.
  - **A busy lock** answers an error (500, "Not sent") rather than a 429 with no time.
  - **A failed Item send** refunds its entry. The 2.4 review left this to 16.9 (reopen_if).
  - **A re-post that races `Conversation.Take`** may count twice. That is bounded at one per retry, and accepted.
  - **The email count** reads the `SimMessage` rows themselves under the session row lock, because `SimMailboxIn` saves its row synchronously. Outgoing rows are not counted.
- **The README link of both chat messages** is `#install-it-yourself`, as DW-361 rules for the page. It lives in `Allowance.INSTALLLINK`, because `Tools/WatchTools.#READMELINK` is contended. `test-readme.sh` checks the anchor.
- **The allowance card in the chat** is a notice card with no title (the catalog text stands, like the other cards). It uses the danger banner's `circle-alert` icon and danger accent, with no strip and no caption. This is visual only.
- **The daily-cap message's `{time}`** is `Bridge.Time.DayEndUtc(day)`, the same end of day that `Budget.State()` gives as `resetsAt`.
- **Who gets the daily-cap message:**
  - **Every session-owned `daily_cap` fallback** sends it (once a day). Such a decision exists only because the session did something.
  - **Activity** is any `Turn` (refused ones too), any `BreakFeedRun`, or an owned request the user answered. "Since it began" is the row's lifetime.
  - **"Open"** means the row still has its `ResumeHash`, which `SessionOps.End` clears.
- **The mailbox limit is held by the page from the 429.** `/state` gets no field for it: the AC needs the state only after a press, and smaller is better. After a reload, the next press learns it again.
- **The limit of 20 is fixed in the UX text.** It is a parameter, not a public setting: `Public.Settings` `KEYS` is fixed by AD-19, and `Test.Install.Public` pins it.
- **DW-361 scope:** every banner action: "Install it yourself" on allowance, dailyCap and demoBusy, and "How to set a key" on noModelKey. The splash's "Install it yourself (README)" and the guide's finish link are not banners, so they are left alone (see For the lead).
- **The new live unit is `online-allowance`, in the `install-fresh` group** (lead, spec gate 2026-10-29: Story 16.4's CI rework, DW-220, moves `live:online-demo` (556-561 s on CI) from `image` into `install-upgrade`, about 1355 s; `install-fresh` with `online-session` ran 1339 s on run 40866408272; `shards` is about 1900 s. Record the unit's CI seconds in the spec after the first push; if the run then passes REL-4's 35 minutes, that is owner-fixed value 9's case, reported, not a blocker). The planner's reasons below stand:
  - The cap is instance-wide, so it cannot share `online-session`'s stack hermetically.
  - `online-demo` (386-422 s) cannot grow.
  - `install-upgrade` was the shortest group on run 40813183274 (13.7 min).
  - Expected about 5-6 min locally `(inference)`.
- **The runners' keys point at the mock for the whole unit.** `Decide`'s prechecks run `no_key` before `daily_cap`, so without a key D1 would fall back with `no_key`. Unmarked messages get the mock's 500, a quick fallback.
- **`Ownership.Resume`'s unlocked save at sign-in** could write back a stale `AllowanceTimes`, losing at most one count. That is harmless, and Resume is not changed.

**Veto-window items** (each with a recommendation, for the lead's spec gate):
- **V1, stored data.**
  - `Session` gains `AllowanceTimes` and `AllowanceUntil`, beside the AC's own `DailyCapDay`, appended to storage. Existing rows read "".
  - `Turn` rows gain the State value `refused`, with no new column.
  - **Recommendation: keep.** An alternative table would be new storage plus an AD-33 row.
- **V2, the REST contract and its texts.**
  - 429 `allowance` on `POST /messages`, with `retryAt` and `limit` beside `error`. Its message is `MESSAGEALLOWANCE` = "You've used this session's {limit} messages for the hour."
  - 429 `email_limit` on `POST /mailbox/incoming` and `/mailbox/samples/:name`, with `retryAt`. Its message is `MESSAGEEMAILLIMIT` = "You've simulated 20 emails this hour."
  - Both messages are the first sentences of the UX's own texts (E:743, E:851 and E:308). The page shows neither, because its texts come from the catalog and the UX.
  - **Recommendation: keep.** As with U-20 and U-100, the lead adds the codes to the spine's REST row (Rule 20).
- **V3, AD wording (Rule 20, light path).**
  - AD-20 should name the refused `Turn`'s State `refused`, the window rule (from the first refusal to `retryAt`) and the `Session` fields.
  - The "Notice cards" convention should add `allowance` cards.
  - **Recommendation: keep.** They complete AD-20 without contradicting it, and Story 12.6 builds on this rule.

**Rule 2 (extend, don't copy):**
- **Server:**
  - `TryConsume` extends Story 2.4's stub, and its locking is `Core.Trace.Join`'s.
  - `ActiveVisitors` and `AllowanceHeld` follow `Ownership.Watchers`. `IncomingMail` follows the own-session statements.
  - `Status.Allowance` follows `DailyCap` and `TelegramPaused`. `AllowanceTick` follows `StatusMonitor`'s instance loop and `PublishReset`.
  - The 429 extends `Fail` and parses the output as `BreakFeed` does.
  - `BridgeSink`'s `Visitors` and `Notice` seams follow `Recipients` and `NoticesIn.Forward`.
  - `Allowance.Notice` is the one builder, for `WebChatIn` now and `TelegramIn` in Story 12.6.
- **Page:**
  - `AllowanceState` follows `reset-watch.ts` (the timer) and `demo-busy-state.ts` (the root service).
  - The 429 reuses `ChatOutbox.refuse`.
  - The reasons reuse the banner text function and `header.ts`'s aria-disabled pattern.
  - The mailbox uses `server-button`'s `inactive` and `describedBy`.
  - The anchors use `readmeSection`.
- **Units:** `keys_point` moves to `lib-online.sh` and is not copied. The new unit and specs reuse `lib-live.sh`, `online_override`, `signInFromSplash`, `signOutGroup`, `sessionRow`, `irisScript` and `Fixture`.
- No copy is planned.

**Integration ACs:**
- `WebChatIn` consumes `TryConsume`. Observable: the 429, the refused `Turn`, no queued turn, and one card (A1).
- `/state` and `StatusMonitor` consume `Allowance.Until` and `Status.Allowance`. Observable: the banner and the disabled controls, cleared at `retryAt` (A1, A2).
- `BridgeSink` consumes `budget.capped` and `decision.recorded` from the real bridge, and `NoticesIn` → `Notify` → `WebChatOut`. Observable: the daily-cap card on the recipients only, once (D1, D2).
- `SimMailboxIn` consumes `MailAllowed`. Observable: the 429 and the disabled chips (E1).

**Consumes:**
- 2.4: `TryConsume`, `WebChatIn` and its probes.
- 1.4 and Epic 1: `Budget.State`, `MarkCapped`, `budget.capped` and the `daily_cap` fallback.
- 2.10: the banners and `StatusMonitor`.
- 2.7: `WebChatOut` and `Delivery`.
- 16.1: `messageAllowance` and the start values.
- 4.6: `SimMailboxIn`.
- Epic 6: `Approval.Answer`.
- 16.4: `SessionOps.End` clears `ResumeHash`, and `lib-online.sh`.
- 16.8: `StatusMonitor`'s remembering pattern.
- 16.5: `ChatOutbox.refuse`.
- 10.2: the README headings and `test-readme.sh`.

**Consumed-by:**
- 12.6: `TelegramIn` calls `TryConsume` and sends `Allowance.Notice` on the first refusal.
- 31.3: turns on the Telegram cases.
- 31.2: extends `BridgeSink`.
- 29.4: the load test counts the allowance.
- 19.5 and 34.2 do not touch these files.

**Ledger inbox:**
- **DW-300: addressed.** The BridgeSink and Api test tasks: rows a day ahead plus typed counts (AC 9).
- **DW-361: addressed.** The banner tasks (AC 10).

**Footprint extensions** (not contended; the lead checked or `git diff` shows no unmerged branch touching them):
- **IRIS classes:**
  - `Channel/WebChat/In.cls`, `Channel/WebChat/Out.cls` and `Channel/SimMailbox/In.cls`;
  - `Core/NoticesIn.cls`, only if Task 0 (a) needs it;
  - `Live/Payload/Status.cls`.
- **IRIS tests:**
  - `Test/Core/Allowance.cls` (new);
  - `Test/Core/WebChatMessages.cls`, `WebChatInProbe.cls`, `BridgeSinkProbe.cls`, `StatusMonitor.cls`, `StatusMonitorProbe.cls`, `WebChatOut.cls`, `TelegramCalls.cls`, and `NoticesIn.cls` if (a);
  - `Test/Live/Status.cls` and `Test/Demo/SimMailboxIn.cls`.
- **Browser tests:** `web/e2e/banners/banners.spec.ts`.
- **Live-unit scripts:**
  - `docker/tests/test-online-allowance.sh` (new), `lib-online.sh` and `test-online-demo.sh` (the extraction only);
  - `test-ci-config.sh` and `test-ci-changes.sh`, expectations only.

Everything else is in the paths_hint or shared by entry.

**For the lead:**
- V1 to V3 above.
- **Spine (Rule 20):** the REST codes, AD-20's refused `Turn` and window rule, and the "Notice cards" row.
- **CI:** `live:online-allowance` joins `install-fresh` (lead, spec gate). The job grows by about 10-14 min on CI `(inference)`.
  - Run 40813183274's `image` job took 40 min, over REL-4's 35. That predates this story and is reported only.
- **Links left alone:** the splash's and the guide's README links still open `#readme`. Ruling on them is outside DW-361.

**Implement pass** (2026-10-29):

- **Task 0 (a), no bridge context in the Decide job. No `NoticesIn` branch.** Both `daily_cap` paths reach `Decide.RecordFallback` in the Decide business process's own job: the precheck (`OnRequest`, line 260) and the key resend or timer (`Resend` 359, `Classify`'s `daily_cap`). `RecordFallback` fires `decision.recorded` and then `Budget.MarkCapped`, which fires `budget.capped`, both in that job. `OcuTalon.Bridge.Context.Begin` is called only by `Adapter.Agent.Answer` (the runner's job, `Agent.cls:318`), which ends the context on every path, and the context lives in `^||OcuTalonBP.Context`, process-private. So `NoticesIn.Join` takes its second branch: each notice is a session of its own under the notified session's `TraceRef`. Live proof: D1 gives S1 and S3 each their own card from one decision. `Core/NoticesIn.cls` and `Test/Core/NoticesIn.cls` are unchanged.
- **Task 0 (b), measured locally on lane C `(MEASURED)`:** `live online-allowance` took 244, 241 and 237 s; its browser step 151, 151 and 149 s; the 429 round trip of the 52nd post through the API 3 ms. The unit is far under 8 minutes, so it is not split with `--part`.
- **DW-220 (residual): the expected job times.** Inputs are CI run 40866408272 (image 2047 s with storage-roundtrip 257, build-inputs 9, compose-start 200, demo-switch 467, shard:lane-b 866, install-script-live 213), install-fresh 1339, install-upgrade 1355, production 942, browser 1464, shards 1896. `shard:lane-b` cannot go to `production`: its Web classes read the built bundle (`Test.Web.Shell`, `Install`, `SignIn`, `Status`, `Splash`, `PublicTexts` name it), and `production` must stay web-bundle-free. No other group has room for its 866 s. So `ci/units.sh` moves `live:demo-switch` (467 s) from `image` to `install-upgrade`, and `live:online-allowance` joins `install-fresh`:

  | group | units now | expected `(inference)` |
  | --- | --- | --- |
  | install-fresh | install-start, bundle-folder, online-session, online-allowance | 1339 s plus the new unit's CI time (about 1740 s if it costs 400 s, which is its 237 s here plus a stack start on the runner) |
  | install-upgrade | install-upgrade, audit, online-demo, demo-switch | about 1355 + 467 = 1822 s |
  | production | unchanged | 942 s |
  | browser | unchanged | 1464 s |
  | shards | unchanged (Lane A's shard, floor, cards) | 1896 s |
  | image | storage-roundtrip, build-inputs, compose-start, shard:lane-b, install-script-live | about 2047 - 467 = 1580 s |

  This is the best arrangement of Lane B's units that keeps `production` web-bundle-free. `shards` (1896 s, units outside this lane) and `install-upgrade` (about 1822 s) stay near 30 minutes, not under it. `install-fresh` stays under about 1800 s only while `online-allowance` takes less than about 460 s on CI; the spec's earlier inference of 10 to 14 minutes for it would put the group at 1940 to 2180 s, and then the next move is the owner's capacity action (owner-fixed value 9). The lead records the unit's CI seconds after the first push. `test-ci-config.sh` and `test-ci-changes.sh` read the groups from `ci/units.sh`, so neither needed an edit.
- **Decided in-stage:**
  - **`DailyCap` needs an open session on both paths** (matrix row 16: an ended session gets nothing on either event). It sets `DailyCapDay`, sends, and takes the day back when the send fails, so the next fallback retries. A busy lock (1 s) is a warning with nothing sent.
  - **A new test class, `Test.Core.BridgeSinkNoticeProbe`**, records the `Notice` seam and can fail it or the `Visitors` seam. `BridgeSinkProbe` is left alone: its handlers throw on purpose, so it could not reach the real `Recorded` and `Capped`.
  - **`web/package.json` gained the script `e2e:online-allowance`**, as `e2e:online-session` is the session project's: `playwright-projects.test.mjs` lists a project through its npm script, and the unit runs it through the same script.
  - **The 429 `allowance` message has `{limit}` filled in** (`MESSAGEALLOWANCE` is the template). The page shows neither REST message.
  - **An allowed message does not clear `AllowanceUntil`.** A window runs from its first refusal to its `retryAt`, as the intent says. `Until` reads the row fresh and throws on a failed read.
  - **`AllowanceState`**: when the store's condition and a 429 refusal both hold a future time, the later wins. The composer and the guide render their reason with `allowanceReason` (an exported thin wrapper over `bannerText` in `banner-stack.ts`, whose `FORMAT` stays private).
  - **One reason paragraph for the email limit**, `#mailbox-email-limit`, above the chips, serves the chips and the form's Send in every view, because the chips are always on the panel.
  - **`SimMailboxIn` takes the session row's lock only on the online demo** (review patch): the Task's lock is the count's, and with the flag off there is no count, so a local install takes no lock and a busy row can never refuse its email ("flag off changes nothing").
  - **AP presses Break the feed in the page.** A1's check that its `aria-disabled` is unchanged cannot catch a button that both caps disable, because with no Orders watch the box is inactive already. AP has the watch, reloads, and clicks the button; the AC 8 mutation is caught there.
  - **A2's window is about 30 s, not 20 s** (review patch): the entries are seeded about 3570 s old. `StatusMonitor` runs every 15 s, and the stream's active and clear events (`[true, false]`) need a run inside the window, which about 18 s left too little room for on a loaded runner. The page's own clear at `retryAt` and the 45 s bound are unchanged.
  - **`banners.spec.ts` seeds the allowance condition with a future time** (`ALLOWANCE_UNTIL`, 12:00 UTC on 2037-07-01, which the page shows as 17:30 in Asia/Kolkata and 8:00 AM in New York, as `T` did): `AllowanceState` counts the store's condition only while its time is ahead of the page's clock, and the server only ever sends an active `allowance` with a future time. B5, B8 and B12 failed on the past `T` in the first `live sign-in --part 1/2`.
  - **`TestBudgetCappedSendsToEachActiveSessionOnce` sends to its own fixtures only** (review patch): it takes the real `Ownership.ActiveVisitors` read, keeps the test's own sessions, and gives those to the probe's `Visitors` seam, so that no other open session of the instance is written. `TestActiveVisitors` pins the ended-session exclusion on the full list.
  - **D2 and AP wait 20 s after the cap is lifted** (`settleMonitor`). `StatusMonitor` publishes a change only, so a cap that is lifted and reached again inside one 15-second tick is no change to it and a page that loaded in between would never get the banner (a reload shows it). This is test timing, not a defect.

## Verification

**Targets and variables:**
- Run every command from the worktree root, in the foreground, with `timeout: 600000`, one per call. Never put two test-runner calls in one message.
- **Tags:**
  - implement `e16s9i` (fresh) and `e16s9iw` (warm);
  - QA `e16s9q` and `e16s9qw`, with stage `qa`;
  - review `e16s9r` and `e16s9rw`, with stage `code-review`.
- Each stage tears down only its own tags. Flag-on checks run only in throwaways, never on `ocutalon-slot-c`.
- Run `ci/iris.sh build` before the first browser unit, and again after any change under `web/` (Rule 21).

**Commands:**
- (loop) `npm --prefix web test` -- every node test passes: `banner-view`, `allowance-view`, `chat-view`, `mailbox-view`, `playwright-projects`, `ux-strings` and `api-client-sources` among them.
- (loop) `npm --prefix web run lint` -- `tsc` passes over `e2e/` and `e2e-online/`.
- (loop) `bash docker/tests/test-web-build.sh` -- the build passes and the tree stays clean (`catalog.mjs --check`, `payloads.mjs --check`).
- (loop) `bash ci/checks.sh` -- every block passes (`readme`, `ci-config`, `ci-changes`, `boundaries`, `class-rules`).
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9iw bash ci/warm.sh up` -- once, at the stage's start.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_WARM=1 OCUTALON_RUN_TAG=e16s9iw bash ci/iris.sh class <Class>` -- one call per class, each printing `CLASS ... passed` after a `WARM reloaded` line. The classes:
  - `OcuTalon.Test.Core.Allowance`, `OcuTalon.Test.Core.WebChatMessages`, `OcuTalon.Test.Core.TelegramCalls`, `OcuTalon.Test.Core.ConversationTurns`;
  - `OcuTalon.Test.Core.BridgeSink`, `OcuTalon.Test.Core.NoticesIn`, `OcuTalon.Test.Core.StatusMonitor`, `OcuTalon.Test.Core.WebChatOut`, `OcuTalon.Test.Core.Routing`;
  - `OcuTalon.Test.Live.Status`, `OcuTalon.Test.Live.Payloads`;
  - `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Web.MailboxApi`, `OcuTalon.Test.Demo.SimMailboxIn`;
  - `OcuTalon.Test.Data.Ownership`, `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Contract.Ac`, `OcuTalon.Test.Msg.Catalog`.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9iw bash ci/warm.sh down` -- at the stage's end, and after a failure.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh build` -- before the first live run, and after every change under `web/`.
- (loop) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh live online-allowance` -- PASS for A1, A2, E1, E2, D1, D2 and AP and for the IRIS checks, with Task 0 (b)'s `MEASURED` lines. Expected about 300-400 s. If it nears 8 minutes, split the specs with `--part`, as `sign-in` does.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh live online-demo` -- PASS, with `busy.spec.ts`'s new href, `keys_point` from `lib-online.sh`, and the project's new `testIgnore`.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh live online-session` -- PASS: the `/state` status and banner changes break no leave or sign-out row.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_LIVE_DEADLINE=900 OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh live sign-in --part 1/2` -- PASS (`banners.spec.ts` hrefs; the chat and the composer).
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_LIVE_DEADLINE=900 OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh live sign-in --part 2/2` -- PASS.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh shard lane-b --part 1/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh shard lane-b --part 2/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh shard lane-b --part 3/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh shard lane-a --part 1/3` -- every class passes. `Test.Agent.Decide` exercises the real `BridgeSink` on both daily-cap paths with the flag off.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh shard lane-a --part 2/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh shard lane-a --part 3/3` -- every class passes.
- (once) `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=16 stage=implement' OCUTALON_RUN_TAG=e16s9i bash ci/iris.sh teardown` -- nothing tagged `e16s9i` is left.
- **Left to CI:** install-fresh, install-upgrade's other units, production, demo-path, floor, cards, answers, and image's other units.

**Pinning tests and their mutations** (the implement stage writes each `mutation:` line):
- AC 1: `Test.Core.Allowance` 51st case. Mutation: count `< Limit() + 1`.
- AC 2: the telegram case. Mutation: skip the `Turn` for a telegram call.
- AC 3: A1's single card. Mutation: send the notice on every refusal.
- AC 4: A2's clear. Mutation: the `AllowanceState` timer is never re-armed.
- AC 5: the `BridgeSink` broadcast. Mutation: drop the `DailyCapDay` check.
- AC 6: the flag-off case. Mutation: ignore the flag in `Capped`.
- AC 7: the `SimMailboxIn` 21st. Mutation: `EMAILLIMIT` 21.
- AC 8: AP's and A1's Break the feed checks. Mutation: `feed/break-feed-box.ts` passes `[inactive]` while `AllowanceState.active()` holds.
- AC 9: the seeded-row assertion in each DW-300 method. Mutation: seed one row with no `NextDueAt`.
- AC 10: `banner-view.test.mjs`. Mutation: target `README_URL`.

- mutation: AC 1, `Allowance.TryConsume` counts `< limit + 1` -> `Test.Core.Allowance` red (`TestTheFiftyFirstIsRefused`, `TestMixedChannelsCountTogether`, `TestNewWindow`, `TestFailedSaveRollsBack`); reverted, tree byte-identical.
- mutation: AC 2, `Allowance.Refused` returns before it saves the Turn of a telegram call -> `Test.Core.Allowance` red (`TestTelegramFixtureIsRefusedTheSameWay`); reverted.
- mutation: AC 3, `WebChatIn` sends the notice on every refusal (the `firstRefusal` test removed) -> live `online-allowance` red (A1, `adds no second card`); reverted, tree byte-identical.
- mutation: AC 4, `AllowanceState`'s timer callback no longer sets the clock or arms the timer again -> live `online-allowance` red (A2, the banner is still there after 45 s); reverted, tree byte-identical.
- mutation: AC 5, `BridgeSink.DailyCap` without the `DailyCapDay '= day` test -> `Test.Core.BridgeSink` red (`TestBudgetCappedSendsToEachActiveSessionOnce`, `TestDailyCapFallbackSendsToThatSessionOnce`); reverted.
- mutation: AC 6, `BridgeSink.Capped` without the online-demo flag test -> `Test.Core.BridgeSink` red (`TestDailyCapSendsNothingWithTheFlagOff`); reverted.
- mutation: AC 7, `Allowance.EMAILLIMIT` 21 -> `Test.Demo.SimMailboxIn` red (`TestEmailLimit`); reverted.
- mutation: AC 8, `feed/break-feed-box.ts` passes `[inactive]` while `AllowanceState.active()` holds -> live `online-allowance` red (AP, `Break the feed is not disabled by either cap`); A1's check alone stayed green, since the box is inactive there already, so AP presses the button in the page; reverted, tree byte-identical.
- mutation: AC 9, the `Check` helper of `Test.Core.BridgeSink` seeds its rows with no `NextDueAt` -> `Test.Core.BridgeSink` red in all four methods (`the check row of ... is due more than 23 hours from now`); reverted.
- mutation: AC 10, the allowance banner's action target back to the README's top (`readme`) -> `banner-view.test.mjs` red (`gives each banner its catalog key, variant, icon, action and closing`, `open the section that the row's target names`); reverted.
- mutation: AC 4 (presses ignored, review patch), `Composer.send` without its `AllowanceState.active()` guard -> live `online-allowance` red (A1, `a press of Send, Enter in the field and a click on the guide prompt send nothing while the allowance is used up`); `DemoGuide.send` without its guard -> the same assertion red; each reverted, tree byte-identical.
- mutation: AC 4 (the page's own 429, review patch), `ChatOutbox` without `this.allowance.refused(refusal)` -> live `online-allowance` red (A1 and A2, `the allowance banner shows at once, from the page's own 429`, within 2 s); reverted, tree byte-identical.
- mutation: AC 1 (matrix row 9, review patch), `WebChatIn.Refund` emptied -> `Test.Core.WebChatMessages` red (`TestFailedSendRefundsTheRealAllowance`); reverted, tree byte-identical.
- mutation: AC 5 (review patch), `Ownership.ActiveVisitors` without `s.ResumeHash <> ''` -> `Test.Data.Ownership` red (`TestActiveVisitors`, `an ended session (no resume hash) with a turn is not in the list`) and `Test.Core.BridgeSink` red (`TestBudgetCappedSendsToEachActiveSessionOnce`); reverted, tree byte-identical.
- mutation: AC 5 (review patch), `BridgeSink.DailyCap` without the Try around the `Notice` send -> `Test.Core.BridgeSink` red (`TestFailedDailyCapSendIsRetried`, `the day is taken back to the one before`); without the unreadable-day warning -> `TestBudgetCappedBadInputsSendNothing` red; each reverted, tree byte-identical.
- mutation: AC 6 / AC 7 (flag off, review patch), the lock of `SimMailboxIn` taken whatever the flag -> `Test.Demo.SimMailboxIn` red (`TestEmailLimit`, `with the flag off the busy row is no obstacle`); reverted, tree byte-identical.
- mutation: AC 9 (second line, review patch), `TestStateSections` seeding `check1` with no `NextDueAt` -> `Test.Web.Api` red (`check1 is due more than 23 hours from now`); reverted, tree byte-identical.

**QA pass** (stage qa, 2026-10-29; tags `e16s9q` and `e16s9qw`). The pass applied 112 mutations to the source of the story (a runner kept a byte copy of each file, restored it and compared `git status` and `git diff` with the tree from before the mutation: identical every time). 93 went red on the tests of the implement stage. 12 survived and are closed by the tests below; 5 are equivalent mutants (`Ownership.ActiveVisitors`'s `AnsweredAction IN ('approve', 'reject')` and `AnsweredAt <> ''` are redundant with each other, because `Approval.Answer` saves the four answer fields in one save; `BridgeSink.Capped`'s form test, because `DayEndUtc` rejects every malformed day too; `Web.Api.Messages`'s `+limit`, because the limit already is a number; `SimMailboxIn`'s `ElseIf` guard, because the error status leaves first).

Tests added or changed by the QA pass (all discovered by the default runs: the `Test/` folders are shard areas, `web/scripts/*.test.mjs` is `npm test`, the browser cases are in the `online-allowance` project):
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/AllowanceInProduction.cls` (new, over the running production, warm stack and CI shards): a refused message gives one web card and none on the phone, the daily-cap message reaches the web chat once through the real sink and NoticesIn, the flag off sends nothing.
- (QA) `src/ocutalon/cls/OcuTalon/Test/Core/BridgeSinkVisitorsProbe.cls` (new): the real `BridgeSink` with only its read of the sessions cut down to the test's own, for `AllowanceInProduction`.
- (QA) `web/scripts/allowance-sources.test.mjs` (new): the page glue that Node cannot run, read as source (the banners' README targets, the explained-disabled controls and their guards, the outbox's 429 order, the mailbox's limit, who reads `AllowanceState`).
- (QA) changed: `Test/Core/Allowance.cls` (3 cases), `Test/Core/WebChatMessages.cls` (2), `Test/Core/StatusMonitor.cls` and `StatusMonitorProbe.cls` (a `HeldReads` count), `Test/Live/Status.cls` (1), `Test/Web/Api.cls` (1) and `Test/Web/ApiProbe.cls` (an `output` seam), `web/e2e-online/allowance/messages.spec.ts` (A3 and A4).

- mutation: AC 1 / matrix 17 (a failed count read), `Allowance.MailAllowed` without `If $SYSTEM.Status.IsError(sc) Quit 0` -> `Test.Core.Allowance` red (`TestMailAllowedFailedReadIsNotAnAllowance`); reverted, tree identical.
- mutation: AC 3 (the limit in the notice), `Allowance.Notice` with the limit 50 written in -> `Test.Core.Allowance` red (`TestNoticeCarriesTheConfiguredLimit`) and `Test.Core.WebChatMessages` red (`TestRefusalReportsTheConfiguredLimit`); reverted.
- mutation: AC 1 (the limit in the 429), `WebChatIn`'s refused output with `"limit": 50` -> `Test.Core.WebChatMessages` red (`TestRefusalReportsTheConfiguredLimit`); reverted.
- mutation: AC 4 / matrix 10, `Status.Allowance` with `Slots.Limit = 50` -> `Test.Live.Status` red (`TestAllowanceLimitIsTheSetting`); reverted.
- mutation: AC 6 / matrix 6 (a local install does no extra read), `StatusMonitor.AllowanceTick` without its flag test -> `Test.Core.StatusMonitor` red (`TestAllowanceOnlyOnTheOnlineDemoAndFailedReadRemembersNothing`, `HeldReads` 0); reverted.
- mutation: matrix 2 (a lowered limit), `Allowance.Kept` keeping the oldest entries -> `Test.Core.Allowance` red (`TestOnlyTheNewestEntriesCountWhenTheLimitDrops`); reverted.
- mutation: matrix 2 (the notice's own session), `WebChatIn.Notify` without `Set ..%SessionId = ""` -> `Test.Core.WebChatMessages` red (`TestNoticeStartsASessionOfItsOwnOnAReusedService`); reverted.
- mutation: AC 5 (the real chain), `BridgeSink.Notice` answering OK without `NoticesIn.Send` -> `Test.Core.AllowanceInProduction` red (`TestTheDailyCapMessageReachesTheWebChatOnce`); `BridgeSink.DailyCap` without the `DailyCapDay '= day` test -> the same case red (the second event); `Capped` without the flag test -> `TestTheFlagOffSendsNothing` red; reverted.
- mutation: AC 3 (the real chain), `WebChatIn` without the notice -> `Test.Core.AllowanceInProduction` red (`TestARefusedMessageGivesOneWebCard`); a notice on every refusal -> the same case red (a second card); `WebChatOut` `CARDKINDS` without `allowance` (after the item `WebChatOut` was restarted, because a warm reload does not restart production jobs) -> both production cases red (the card has no text); `Allowance.TryConsume` without the flag test -> `TestTheFlagOffSendsNothing` red; each reverted.
- mutation: AC 1 (an unreadable answer), `Web.Api.Messages` without its error exit after parsing the service's output -> `Test.Web.Api` red (`TestMessagesUnreadableOutputIs500`); reverted.
- mutation: AC 10 (the production hrefs), `banner-stack.ts` with `installUrl: README_URL`, and `setKeyUrl` built from the install anchor -> `allowance-sources.test.mjs` red (the stack builds the install and set-a-key addresses); the anchor `install-it-yourself` or `set-a-model-key` misspelled -> `allowance-sources.test.mjs` and `test-readme.sh` red; the guide's README link changed to a section -> `allowance-sources.test.mjs` red; reverted.
- mutation: AC 4 / matrix 12 (the guards, fast tier), `Composer.send` without its `AllowanceState.active()` guard, `DemoGuide.send` without its guard, the composer's Send bound to `[disabled]`, the guide's `aria-describedby` dropped, a reason id renamed, `BannerStack.withAllowance` unused, dropping the stored condition or the limit -> `allowance-sources.test.mjs` red in each case; reverted.
- mutation: AC 7 / matrix 17 (the mailbox page), `SimulatedMailbox`'s chip handler without `this.limit(error)`, Send without `[inactive]="limited()"`, and the timer that never re-arms -> `allowance-sources.test.mjs` red; reverted.
- mutation: AC 8 (fast tier), `feed/break-feed-box.ts` injecting `AllowanceState` -> `allowance-sources.test.mjs` red (AllowanceState is injected by the banner stack, the composer, the guide and the outbox and by nothing else); reverted.
- mutation: matrix 12 (a guide entry just leaves), `ChatOutbox`'s 429 branch without the `refuse(entry)` offer -> live `online-allowance` red (A3, and A1's typed text); reverted, tree identical.
- mutation: matrix 12 (other text in the composer), `ChatOutbox`'s 429 branch returning whether or not the text was taken back -> live `online-allowance` red (A4 alone); reverted, tree identical.

Measured by the QA pass `(MEASURED)`: `live online-allowance` with A3 and A4 took 263 s (browser step 149 s, 9 cases; A3 0.4 s, A4 0.4 s), against 235 to 237 s without them on the implement stage's runs. The new production cases run in 8.5 s on the warm stack, `Test.Core.Allowance` in 5.3 s, `allowance-sources.test.mjs` in 0.1 s.

Not pinned, by design: the transaction of `TryConsume` when the `Turn` saves and the session row's save then fails (no seam makes the second save fail; `TestFailedSaveRollsBack` pins the first save's failure), the Telegram service (Story 12.6), and `Web.Api.Messages` for a JSON array as the service's output, which it reads as accepted although its doc says an output that is no object is 500 (the service never answers one; reported).

**Shared surfaces:**
- **The schema:** the `Session` columns (`Test.Data.Tables`). The new `Turn` State `refused` is read by `RecentTurns`, the chat snapshot and the queue.
- **The notice card kinds:** `CARDKINDS` and `recentNotices` (`Test.Core.WebChatOut`, `Test.Data.Ownership`, `chat-view.test.mjs`).
- **The `/state` status order and its keys** (`Test.Web.Api`).
- **Service outputs and REST bodies:**
  - `WebChatIn`'s output and `POST /messages` (`Test.Core.WebChatMessages`, `Test.Web.Api` `TestMessages*`);
  - `SimMailboxIn`'s output and the mailbox routes (`Test.Web.MailboxApi`, `Test.Demo.SimMailboxIn`);
  - `Api`'s MESSAGE parameters and REST codes.
- **Page targets:**
  - the banner action targets and hrefs (`banner-view.test.mjs`, `banners.spec.ts`, `busy.spec.ts`);
  - `test-readme.sh`'s link inventory;
  - the ux-strings inventory.
- **CI lists:**
  - the Playwright projects and the `online-demo` `testIgnore` (`playwright-projects.test.mjs`);
  - `ci/units.sh` groups and `BROWSER_UNITS` (`test-ci-config.sh`, `test-ci-changes.sh`).
- **Instance-wide state:** the daily cap's mark, `Usage` rows and Decide settings. Every test that sets them restores them.
- **Standing criterion:** every test added or changed passes on a fresh environment, in either order.

## Auto Run Result

Status: done
Blocking condition: none

- **Summary.** Story 16.9 is implemented on the Lane C slot's tree. With the online-demo flag set, `Allowance.TryConsume` counts a session's messages over a rolling hour under its `Session` row lock, refuses the 51st with `retryAt`, records a refused `Turn` and flags the window's first refusal; `WebChatIn` turns that into one `allowance` notice and `Web.Api` into a 429. The session's `allowance` condition (`/state` and `StatusMonitor`) drives the banner and the `aria-disabled` composer and guide prompts until `retryAt`. `BridgeSink` sends the daily-cap message once a day to each open session with activity, on `budget.capped` and on a session's `daily_cap` fallback. `SimMailboxIn` refuses the 21st incoming email of the hour with a 429 `email_limit`. DW-300 (the check rows a day ahead), DW-361 (the banner actions open the README's own sections) and DW-220's residual (`ci/units.sh`) are addressed. With the flag off nothing changes.
- **Files changed (by area).**
  - IRIS source: `Core/Allowance.cls` (rewritten), `Core/BridgeSink.cls`, `Core/StatusMonitor.cls`, `Channel/WebChat/In.cls` and `Out.cls`, `Channel/SimMailbox/In.cls`, `Data/Ownership.cls`, `Data/Session.cls` (storage values 11 to 13), `Data/Turn.cls` (State doc only), `Live/Payload/Status.cls`, `Web/Api.cls` (429 and `Fail`'s `extra`).
  - IRIS tests: new `Test/Core/Allowance.cls` and `Test/Core/BridgeSinkNoticeProbe.cls`; changed `Test/Core/{BridgeSink,BridgeSinkProbe,StatusMonitor,StatusMonitorProbe,TelegramCalls,WebChatInProbe,WebChatMessages,WebChatOut}.cls`, `Test/Data/{Ownership,Tables}.cls`, `Test/Demo/SimMailboxIn.cls`, `Test/Live/Status.cls`, `Test/Web/{Api,ApiProbe,MailboxApi}.cls`.
  - Page: new `live/allowance-view.ts` and `live/allowance-state.ts`; changed `banners/{banner-view,banner-stack}.ts`, `chat/{chat-outbox,chat-view,composer,notice-card}.ts`, `guide/demo-guide.ts`, `mailbox/{mailbox-view,simulated-mailbox}.ts`, `api/api-types.ts`.
  - Node tests: new `allowance-view.test.mjs`; changed `banner-view`, `chat-view`, `mailbox-view`, `playwright-projects` and `ux-strings` tests.
  - Browser specs and units: new `web/e2e-online/allowance/{messages,daily-cap}.spec.ts` and `docker/tests/test-online-allowance.sh`; changed `web/e2e-online/{support,busy.spec}.ts`, `web/e2e/banners/banners.spec.ts`, `web/playwright.config.ts`, `web/package.json` (script `e2e:online-allowance`), `docker/tests/{lib-online,test-online-demo}.sh` (`keys_point` moved), `ci/units.sh` (`online-allowance` in `install-fresh` and `BROWSER_UNITS`; `demo-switch` to `install-upgrade`).
- **Footprint extensions (Rule 11 (b), none contended).** Outside the epic's `paths_hint` and the spec's approved list: `Data/Turn.cls` (one doc comment), `Test/Core/{BridgeSink,BridgeSinkNoticeProbe}.cls`, `web/src/app/chat/{chat-outbox,chat-view,composer,notice-card}.ts` (the Tasks name them), `web/package.json`, `web/playwright.config.ts`, `web/scripts/*.test.mjs`, `web/e2e-online/**`, and `ci/units.sh` (shared by region: the lane's own entries). No contended path was touched, and the spine was not edited.
- **Review (one pass, 4 layers, 44 findings).** high 0, medium 5, low 34, false 5. Patched: 5 medium and 11 low rows, some sharing one patch (guards pinned by A1; the real `Refund` forwarder tested; the page's own 429 asserted within 2 s; the ended-session exclusion observed; the capped test made hermetic; `check1`'s `NextDueAt` asserted; `DailyCap`'s unreadable day, throwing notice and failed take-back; `SimMailboxIn`'s lock only on the online demo; the `Turn.State` doc, the refusal-loop kind, three stale comments; A2's window widened to about 30 s). Deferred: 1 (the stale `NoticesIn` class comment, in the frontmatter). Rejected: every other finding, each with its reason in the triage log.
- **Follow-up review recommended: true.** Five medium entries were patched. The unverified risk: the A1 assertions added in the patch press `aria-disabled` controls with a forced click and expect the banner within 2 s of the 429; they passed locally in three runs and failed red under their mutations, but a loaded CI runner has not run them.
- **Verification (final tree).**
  - Node: `npm --prefix web test` 1106 pass; `npm --prefix web run lint`, `bash docker/tests/test-web-build.sh` and `bash ci/checks.sh` pass.
  - IRIS classes on the warm stack (`e16s9iw`): all 18 listed classes pass.
  - `live online-allowance` passes (7 browser cases and the IRIS checks); `MEASURED`: unit 235 to 237 s, browser step 149 s, the 429 round trip 2 to 3 ms (Task 0 (b)).
  - The `(once)` lines pass: `live online-demo`, `live online-session`, `live sign-in --part 1/2` and `2/2`, `shard lane-b` 1/3 to 3/3 (84 classes) and `shard lane-a` 1/3 to 3/3 (70 classes). `live sign-in --part 1/2` first failed on B5, B8 and B12 (a past time in the allowance fixture, fixed in `banners.spec.ts`) and then on B7 (known flake DW-349: the heartbeat ran the unseeded check row), and passed on the third run.
  - Mutations (Rule 19): the ten lines of the implement pass and the seven of the review pass in `## Verification`, each red then reverted byte-identical. Teardown: `e16s9i` and `e16s9iw` are gone.
  - Protocol: two single-class runs were issued in one message by mistake (`TelegramCalls`, `ConversationTurns`); both were run again alone and passed.
- **Residual risks.**
  - DW-220 may still fail on CI: `shard:lane-b` cannot move to `production` (its Web classes read the web bundle), so `install-upgrade` is expected at about 1822 s and `shards` (Lane A's units) at 1896 s; `install-fresh` stays under about 1800 s only if `online-allowance` costs less than about 460 s on CI. Beyond that the next step is the owner's capacity action (owner-fixed value 9). The lead records the unit's CI seconds after the first push.
  - B7 of `banners.spec.ts` still seeds its check row without `nextDueAt` (DW-349).
  - The cap fan-out in `BridgeSink.Capped` runs inside the bridge's decision call; at about 6 visitors it is a few sends.
