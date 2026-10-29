---
title: 'Story 16.9: Allowances cap messages, model cost and simulated emails'
type: 'feature'
created: '2026-10-29'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-1, lines 99-111; AD-4, 155-178; AD-12, 330-344; AD-14, 396-407; AD-20, 529-554; AD-30, 813-834; AD-31, 835-852; AD-32, 853-864; AD-33, 865-875; the REST, Live events and Notice cards rows, 921-925; the event table, 1128-1137)'
  - '{project-root}/_bmad-output/planning-artifacts/ux-designs/ux-OcuTalon-2026-10-16/EXPERIENCE.md (read only lines 180, 258, 266-267, 308, 349-351, 436-441, 546, 742-743, 851-856)'
  - '{project-root}/_bmad-output/planning-artifacts/epics.md (read only Story 16.9, lines 4602-4641)'
warnings: ['oversized', 'multiple-goals']
deferred: []
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

## Spec Change Log

- 2026-10-29, lead spec gate: `live:online-allowance` goes to `install-fresh`, not `install-upgrade`, because Story 16.4's CI rework (DW-220) moves `live:online-demo` into `install-upgrade`. V1 and V2 ruled keep as veto items U-151 and U-152; V3 written as spine Conventions rows (the REST row, the Notice cards row, a new Allowances row), AD-20's Rule unchanged.

## Review Triage Log

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

Status: ready-for-dev
Blocking condition: none

- **Plan stage (2026-10-29).** Planned from the cached `epic-16-context.md` and Story 16.8's continuity (16.4's Design Notes too). The dispatch said "Halt after planning", so it halted at the gate. Nothing was implemented and nothing was committed.
- **Bridge prerequisites are already in the tree.** `Budget.MarkCapped` (once, under a lock) fires `budget.capped`, both `daily_cap` paths reach `Decide.RecordFallback`, and `daily_cap` is never re-sent. So no bridge change is needed.
- **For the lead's spec gate:** the veto-window items V1 to V3 and the Rule 20 spine notes are under Design Notes. The new CI unit, `live:online-allowance`, joins `install-upgrade`.
