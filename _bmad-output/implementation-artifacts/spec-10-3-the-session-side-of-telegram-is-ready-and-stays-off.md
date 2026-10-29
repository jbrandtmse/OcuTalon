---
title: 'The session side of Telegram is ready and stays off'
type: 'feature'
created: '2026-10-28'
status: 'done'
review_loop_iteration: 0
baseline_revision: '3cc30457ca05ae31e069c0c8a04caf9c30eef81a'
baseline_commit: '3cc30457ca05ae31e069c0c8a04caf9c30eef81a'
followup_review_recommended: false
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-10-context.md']
warnings: ['multiple-goals', 'oversized']
deferred:
  - summary: >-
      The CI override sets the dummy TELEGRAM_BOT_TOKEN for every CI and throwaway start, so Story 12.1 must decide how a start with no bot token (FR-21: no token, so off) is expressed once Included() is 1.
    evidence: |-
      ci/compose.ci.yml sets TELEGRAM_BOT_TOKEN unconditionally, and live_key_count counts an empty token as a key. Nothing in the Design Notes says how a no-token start is made in CI, by a start without the override or by an explicit empty value. Unverified: it depends on how Story 12.1 enables the Telegram items; Story 12.1's design settles it.
    location: >-
      ci/compose.ci.yml
    severity: medium (unverified)
---

<intent-contract>

## Intent

**Problem:** Lane A's Telegram epic (Epic 12, shipped as 0.1.1) needs Lane B's session side to exist before it starts, and today it doesn't: `SessionOps` is a stub, `OcuTalon.Data.Pairing` has no methods, `AnswersIn` has no Telegram entry, nothing records or reports the Telegram state or pause, the pairing endpoints answer 501 once Telegram is included, the CI mock refuses every Bot API call, and `web/` has no pairing client methods, no QR-code library and no Telegram demo-path files. One more gap: the page still has a second typed API client, `feed/break-feed-api.ts` (DW-231).

**Approach:** Build every Lane B piece of Telegram that AD-4, AD-11, AD-14, AD-22 and AD-29 assign to Story 10.3. Each piece runs on fixtures and stays switched off, because `OcuTalon.Channel.Telegram.In.Included()` keeps its test-only body. The pieces are:
- `SessionOps` pairs, unpairs and unlinks, with audit entries, `pairing` events and notices to a dropped chat;
- the `Pairing` row methods;
- `AnswersIn.FromTelegram`;
- `StatusMark.RecordTelegram`, the `telegramPaused` condition and `/state`'s Telegram block;
- the pairing endpoints;
- the mock's Bot API side and the CI override's endpoint and dummy token;
- in `web/`, the client methods, the skipped `telegram-*.spec.ts` files, DW-231's fold, and a QR-code library pin, which is a separable task.

## Boundaries & Constraints

**Always:**
- **Hashes only (AD-4).** A pairing code lives only in the HTTP response of `POST /api/v1/pairing/code`. It is stored as `Pairing.HashCode(code)`: SHA-256 of the code's UTF-8 bytes, base64url, 43 characters, no padding. It never appears in a message, header, log line, live event or audit entry. `SessionOps` compares hashes only.
- **The Telegram identity.** It stays only in the chat's `Pairing` row. A chat id or display name never goes into a production message, an audit entry, `$$$LOG*`, an error status or a CommandResult. The display name reaches only the session's own page, through `/state` and the `pairing` event.
- **Two kinds of `Pairing` row.** `Ownership.Pairing(sessionRef)` treats any row whose `SessionRef` is set as a live pairing, so that column is set only on live pairings.
  - A *chat row* has a `ChatId`. Its `Ref` is the ChatRef. Its `SessionRef` is set only while the chat is paired.
  - A *code row* holds one session's pairing code in `CodeSessionRef`. It never has a `ChatId` or a `SessionRef`.
- **Invariants.** A session has at most one paired chat. A chat id has one chat row. A session has at most one code row: a new code replaces its hash, expiry and used mark in place.
- **Exact lookups.** `Ref`, `ChatId`, `CodeHash` and `CodeSessionRef` lookups compare the stored value exactly after an index open, because the default index collation ignores case.
- **SessionOps (AD-1, AD-17, AD-12, AD-32).** It is the only writer of a chat row's `SessionRef`, the only code that marks a code used (`StoreCode` only clears the mark when it replaces a code), and the only `pairing` publisher.
  - Every pair outcome writes its own `Pairing` audit entry (`linked` or `rejected`) through `OcuTalon.Bridge.Audit.Record`. The one exception is a repeat that changes nothing (Decided 3).
  - Each unlink a pair causes adds its own `unlinked` entry.
  - Every link or unlink publishes one `pairing` event to the session whose state changed.
  - It publishes outside any transaction, after the row is saved.
  - Notices are keys and slots only, sent to `Notify`. It renders no text.
  - A link is written only after its `linked` audit entry. If that entry can't be written, nothing links and the outcome is `failed`.
  - An unlink stands even when its audit entry or its event fails; the failure is logged as a warning.
- **The unlink API.** `SessionOps.Unlink` is the one way a chat is unlinked: by `/stop`, by a page Unpair, by a move, by a second chat, and in Story 16.4 by `SessionOps.End`. Its signature is the stable API that Story 16.4 calls (Design Notes).
- **AnswersIn's Telegram entry (AD-11, DW-200).**
  - It resolves the session only from the chat's live `Pairing` row and reuses `OnProcessInput`'s Story 6.2 rule set with channel `telegram`.
  - It passes `Approval.Answer`, through `AnswerOps`, only the paired session's 22-character `Ref`, never a ChatRef or chat id.
  - It returns exactly one code from {`approved`, `rejected`, `already_answered`, `expired`, `not_paired`, `not_visible`, `not_allowed`, `unknown`}, with the slots of the matrix.
- **REST (AD-1, AD-13, REST conventions).**
  - Both pairing routes answer 404 `not_found` while `Included()` is 0, before reading anything else.
  - Otherwise the routes behave as follows:
    - The code route writes only the code row's hash and expiry, through `Pairing.StoreCode`.
    - The unpair route submits `Unpair` through `Commands.Submit` with origin `web_user`.
    - Neither route takes a `SessionRef` from the client.
- **The switch stays off.** `Included()` and every class under `OcuTalon.Channel.Telegram` are untouched, and `TelegramIn` and `TelegramOut` stay disabled (AD-23, AD-29).
- **Tests turn Telegram on only through the test-only seam.** They do it through `^OcuTalonTest("TelegramIncluded")` (`Test.Data.Fixture.SetTelegramIncluded`) and put it back afterwards.
- **Notices while Telegram is included in production tests.** With `Included()` = 1, `Notify` sends a notice to the disabled `TelegramOut`, where it is queued (inference; Task 0 measures it).
  - `SessionOpsProduction` keeps `Included()` at 0 whenever a notice is sent.
  - `PairingApi`'s one paired-DELETE case removes its own queued `TelegramOut` item, as Task 0 settles. Nothing is left in `TelegramOut`'s queue.
- **The mock (AD-22).**
  - `/bot<token>/<method>` is served before the model API's key check.
  - The token is logged by its length only: the path is masked (`/bot[redacted]/…`) and the entry carries `tokenLength`.
  - A telegram scenario is never picked by the model API's selection.
  - The CI override is the only file that sets `OCUTALON_TELEGRAM_API_BASE` and a bot token. The token is a dummy that matches neither key pattern.
- **Source rules.** ObjectScript, TypeScript and mock code follow Rule 14: non-ASCII characters as escapes, and comments that state the contract.

**Never:**
- No edit to `src/ocutalon/cls/OcuTalon/Channel/Telegram/**`, `ci/mock/scenarios/A/**`, `web/src/app/rail/telegram-card/**`, `src/bridge/**`, `web/src/app/api/envelope.interceptor.ts`, `web/src/app/guide/**` or any other contended path.
- `Data/Ownership.cls` gets exactly one self-contained block appended at its end, and nothing else (Task A4).
- `web/package.json` and `web/package-lock.json` change only in the separable Task F5.
- No README text, and no Telegram claim in any release-1 text.
- No new catalog key, live-event type, table or production item.
- No change to `Notify`'s rule. It already routes kind `pairing` with a `ChatRef` to `TelegramOut` alone.
- No refusal path in `Allowance.TryConsume`, which is Story 16.9's.
- No `getFile`, which is Story 25.3's.
- `EndSession` is not implemented. It keeps answering 5003, so `not_built`, until Story 16.4.
- No real bot, token or key anywhere. No `docker compose restart`.

## I/O & Edge-Case Matrix

Abbreviations:
- **S, S1, S2:** fixture sessions.
- **C, C1, C2:** chat rows from `RecordChat`.
- **h:** `HashCode(code)`.
- **"audit X/r":** one `Pairing` entry `{change: X, reason: r, irisUser, sessionRef, channel}`. It holds no chat id or display name.
- **"event S→p":** one `pairing` event on S's stream with `paired` = p.

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HashCode vectors | `"abc"`; `"Zz-ChatCode_0123456789AB"`; `""` | `ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0`; `6f9GcqltZ27RM9XPj-t2niXmYo5dK6Pj--zHN-ak6oM`; `""` | none |
| RecordChat new / known | New chat id `"123456789"`, name "Dana"; then the same id with name "Dana B" | First call: a new chat row (22-character `Ref`, `ChatId`, `DisplayName`, no `SessionRef`, `CreatedAt` = `SeenAt` = now), and its `Ref` is returned. Second call: the same `Ref` is returned, and the name and `SeenAt` are updated. | none |
| RecordChat bad id | `""`, `"12a"`, a 21-digit id | `""` and an error status; no row | error sc names the rule, never the value |
| TakeReplySlot | C unpaired: first call, a call 30 s later, a call 61 s after the first; an unknown ref; a code row's `Ref` | 1 and `ReplySlotAt` = now; then 0; then 1; unknown ref 0; code row 0 | lock not taken → 0 |
| StoreCode replaces | `StoreCode(S, h1, t1)` then `StoreCode(S, h2, t2)` | One code row of S with `CodeHash` h2, `CodeExpiresAt` t2 and `CodeUsedAt` "" | empty session or hash → error, no row |
| Purge (AD-27) | Unpaired chat and code rows with `SeenAt` 40 days old; one 10 days old; a paired chat row 400 days old; `Purge(30)` | The 40-day unpaired rows are deleted; the others stay. `Install.Step.Core.Purge(30)` is the same, and `Install.Registry.Areas()` lists `OcuTalon.Install.Step.Core`. | `Purge(0)`, `Purge("x")` → error naming the class, nothing deleted |
| RecordTelegram | `("on","ocutalon_ci_bot")`; `("rejected","")`; `("off","")`; no mark | `TelegramState(.bot)` returns `on` with bot `ocutalon_ci_bot`; then `rejected`; then `off`; with no mark, `off` | `("paused","x")`, or a bot name not matching `^[A-Za-z0-9_]{0,64}$` → error, mark unchanged |
| Pair: valid code | Code of S unused and unexpired; C unpaired; S unpaired; `Pair` {CodeHash h, ChatRef C} with origin `telegram` | `Ok` 1, `paired`. `C.SessionRef` = S, `CodeUsedAt` = now, audit linked/`code` (S's IrisUser, S, `telegram`), event S→true with C's name. No Notification. | — |
| Pair: unknown code | h matches no code row | `Ok` 0, `unknown_code`; nothing linked; audit rejected/`unknown`, sessionRef "", irisUser = the job's `$Username` | — |
| Pair: expired / used | `CodeExpiresAt` ≤ now; or the code already used and C not on S | `expired_code` / `used_code`; nothing linked; audit rejected/`expired` or `used` with sessionRef S; the code row is unchanged | — |
| Pair: repeat | C already on S repeats S's used code | `paired`; nothing changes; no audit, no event | — |
| Pair: chat moves | C on S1 pairs with S2's code | C is on S2. Audit unlinked/`moved` (S1), then linked/`code` (S2). Events S1→false and S2→true. No Notification (the chat gets the pair reply). | — |
| Pair: second chat | S paired with C1; C2 pairs with S's new code | C1 is unlinked and C2 linked. A Notification {SessionRef S, ChatRef C1, Kind `pairing`, CatalogKey `pairing.otherChatPaired`, Slots `{}`} goes to `Notify`. Audit unlinked/`other_chat`, then linked/`code`. Events: S→false, then S→true with C2's name. | — |
| Pair: unknown chat | ChatRef matches no chat row (unknown, a code row's `Ref`, or a case-changed `Ref`) | `unknown_chat`; nothing linked; the code is unused; audit rejected/`unknown_chat`, sessionRef "" | — |
| Pair: audit fails | The `linked` entry can't be written | `failed`; nothing linked; the code is unused | warning logged |
| Unpair /stop | `Unpair` {ChatRef C}, origin `telegram`, C on S | `Ok` 1, `unpaired`; audit unlinked/`stop` (`telegram`); event S→false; no Notification | — |
| Unpair, not paired | Origin `telegram`, C unpaired or unknown | `Ok` 0, `not_paired`; no change, no audit, no event | — |
| Page Unpair | `DELETE /api/v1/pairing`, S paired with C (Included 1) | 200 `{"result":"done"}`; audit unlinked/`page` (`web`); Notification `pairing.unpairedFromPage` with ChatRef C; event S→false | — |
| Page Unpair, nothing paired | `DELETE`, S unpaired | 200 `{"result":"done"}`; no change, no audit, no event | — |
| Cross-session unpair | Origin `web_user`, SessionRef S, ChatRef of S2's chat | `not_paired`; S2's pairing stays | — |
| Unlink API (Story 16.4) | `Unlink(S, "", "session_end", "web", "", .changed)`: S paired, then again | First call: changed 1, audit unlinked/`session_end`, event. Second call: changed 0, OK, nothing. | channel not in `Msg.Enum` CHANNEL → error before any change |
| EndSession | Through Commands.Submit, origin `web_user` | Still `not_built` (5003) | — |
| Integration: Notify reads SessionOps' notice | The second-chat Notification run through `OcuTalon.Core.Rule.Notify`; Included 1, then 0 | With 1: `TelegramOut` alone. With 0: no target. | — |
| Integration: Notify reads the pairing | Included 1; a real pair of S, then `/stop` | `Rule.Functions.TelegramPaired(S)` is 1 after the pair (other kinds also go to `TelegramOut`) and 0 after `/stop` | — |
| Code route, switch off | Included 0: `POST /pairing/code`, `DELETE /pairing` | 404 `not_found` for both; nothing read or written | — |
| Code route, on | Included 1, state `on`, no pause | 200 `{"code","expiresAt"}`. The code is 22 characters of `[A-Za-z0-9_-]` and `expiresAt` = now + 600 s, UTC. S's code row holds `HashCode(code)`, and no `Pairing` column holds the code. A second call replaces the hash. A Pair with the code's hash then pairs. | — |
| Code route, off / paused | Included 1 and state `off`/`rejected`; or state `on` and `telegramPaused` in the future | 409 `not_available` with `MESSAGETELEGRAMOFF` / `MESSAGETELEGRAMPAUSED`; no code row change | — |
| telegramPaused (AD-12) | `StatusMark.Record("telegramPaused", t)` with t in the future, then t past | `Status.Computed` has `telegramPaused` active with slot Time = t, `/state` status lists it and `telegram.pausedUntil` = t. Once t has passed: inactive, and `pausedUntil` "". | a value that isn't a UTC time → inactive |
| /state Telegram block | Defaults; then Included 1, `RecordTelegram("on","ocutalon_ci_bot")`, S paired with "Dana" | Defaults: `{included:false, state:"off", botUserName:"", paired:false, displayName:"", pausedUntil:""}`. Then: `{included:true, state:"on", botUserName:"ocutalon_ci_bot", paired:true, displayName:"Dana", pausedUntil:""}` | — |
| Integration: Guide reads the same source | Demo on, Included 1, state `on`; S paired by a real Pair, then unpaired; then state `off` | Paired: `step4Variant` `paired`, `telegramRow` 0. Unpaired with step 1 not done: `telegramRow` 1. State `off`: counts as off (`unpaired`, no row). | — |
| FromTelegram approved | C on S; S's visible pending `fix` request (dry run affected 4, itemNoun order/orders); `approve` | `approved`, slots `{"count":4,"itemNoun":{"one":"order","other":"orders"}}`. `Answer` gets channel `telegram` and sessionRef S, never C (DW-200). | — |
| FromTelegram other answers | reject; already answered; expired; approver role not held | `rejected` `{}`; `already_answered` `{"action","channel","time"}`; `expired` `{"time": ExpiresAt}`; `not_allowed` `{"kind"}` | — |
| FromTelegram no pairing | C unknown, a code row, or unpaired | `not_paired` `{}`; AnswersIn is not called | — |
| FromTelegram bad session (DW-200) | C's `SessionRef` is not a Ref (for example `"123456789"`) | `not_allowed` `{}`; nothing reaches `Answer`; the row stays pending | — |
| FromTelegram not visible / unknown | S2's request; then an unknown, cancelled or malformed Ref, or the action `"maybe"` | `not_visible` `{}`; `unknown` `{}`; nothing changes | — |
| FromTelegram tool call | Approve a `tool_call` request | `approved` `{}` (no dry run) | — |
| TelegramIn's direct calls | `Allowance.TryConsume(S,"telegram","hello")`; `Trace.Join(S)` twice; `Delivery.Record(S,"telegram",C_":42",a)` | TryConsume: 1, retryAt "", firstRefusal 0. Join: the same positive id twice. `FindByApproval(a,"telegram",S)` = `<C>:42`; for S2, "". | — |
| Mock getMe | `GET` or `POST /bot<token>/getMe` | 200, the default getMe body. Log: path `/bot[redacted]/getMe`, `tokenLength` = the token's length. The token is in neither stdout nor `requests.jsonl`. | — |
| Mock refusals | `/bot/getMe`; `/bot<t>/getFile`; `/bot<t>/kick`; a multipart body | 401 `{"ok":false,"error_code":401,"description":"Unauthorized"}`; 404 Bot API error naming Story 25.3; 404 Bot API error; 400 Bot API error | — |
| Mock updates | `POST /_mock/telegram/updates` with two updates, then `getUpdates` with `offset` | Both updates, `update_id` 1 and 2. `offset=2` drops the first. With none queued it waits until one is queued or `min(timeout, 50)` s, then answers `[]`. | client close ends the wait |
| Mock replies and calls | `POST /_mock/telegram/replies` `{"scenario":<name>}` or `{"method","replies"}` (409 conflict, 429 `retry_after`, `delayMs`); `GET /_mock/telegram/calls`; `POST /_mock/telegram/reset` | Queued replies answer that method's next calls in order, then the defaults. `calls` lists every Bot API call `{seq, ts, method, params}`. `reset` clears updates, replies and calls. | a scenario that is not telegram → 400 |
| Mock scenario form | A scenario with `match.telegram` | Loads for `getMe`, `getUpdates`, `sendMessage`, `editMessageText` and `answerCallbackQuery` with replies of `status`, `headers`, `delayMs` and a required `body`. Any other method, `getFile`, `text`, `toolUse`, `stopReason` or a missing `body` → refused at load, naming the file. | server exits 1 |
| Integration: IRIS reaches the mock | `Test.Contract.Mock`: `%Net.HttpRequest` to `OCUTALON_TELEGRAM_API_BASE` + `/bot` + `TELEGRAM_BOT_TOKEN` + `/getMe`, then a queued update and a `sendMessage` | getMe ok with `username`; `getUpdates` returns the update; `calls` lists the `sendMessage`; the log line has `tokenLength` and no token | guard fails outside CI |
| CI env | Throwaway iris container | `check_no_key` passes: no `ANTHROPIC_API_KEY`, and `TELEGRAM_BOT_TOKEN` is absent or exactly the CI dummy. lib-live's decoy value `decoy` fails it. | fail line prints counts only |
| Web client | `api-client.ts` | `pairingCode()`: POST `/ocutalon/api/v1/pairing/code` `{}` → `PairingCode`. `unpair()`: DELETE `/ocutalon/api/v1/pairing` with body `{}` → `UnpairDone`. `breakFeed()`: POST `/ocutalon/api/v1/demo/break-feed` `{}` → `BreakFeedSent`. Only `api-client.ts` injects `HttpClient`. `feed/break-feed-api.ts` is gone (DW-231). | — |
| Demo-path files | `web/e2e/demo-path/telegram-page.spec.ts`, `telegram-approval.spec.ts` | One `notBuilt` test each, naming Story 12.4 and 12.7. `demo-path-summary.mjs` accepts both (the skip names a story). | — |

</intent-contract>

## Code Map

Paths under `src/ocutalon/cls/OcuTalon/` unless they start otherwise.

**Pairing, status and data**
- `Data/Pairing.cls`: the table. Columns `Ref` (the ChatRef), `SessionRef`, `ChatId`, `DisplayName` and `CreatedAt`; `RefIndex` unique, `SessionRefIndex` and `ChatIdIndex`, all default collation. No methods yet.
- `Data/Ownership.cls`. Contended (Epic 16 changed it); read only, except Task A4's appended block.
  - `:258-263,629` `Pairing(sessionRef,.sc)` = `SELECT TOP 1 ID … WHERE SessionRef = ?`. It is the one "paired" source for `/state` (`Web/Api.cls:593,612-618`), Notify (`Core/Rule/Functions.cls:36-47`) and Guide (`Demo/Guide.cls:101-109`).
  - `:351-358` `Approval(ref, sessionRef,.sc)`: visibility, a case-insensitive Ref match, any state.
  - `Rows` and `Statement` are Final and Private.
- `Data/StatusMark.cls`: `Record(mark,value)` and `Get(mark)` (Story 0.12), the siblings of `RecordTelegram` and `TelegramState`.
- `Data/Session.cls:12,18,93`: `Ref`, `IrisUser`, `Recipients`.
- `Data/Time.cls:18,27,42`: `NowUtc`, `Seconds(utc)`, `AddSeconds(utc,s)`.
- `Data/Delivery.cls:48,72`: `Record` and `FindByApproval`. Channel `telegram` is accepted, and `ChannelMessageId` has MAXLEN 128.
- `Digest/Data/Item.cls:64-87` `Purge(daysToKeep)` and `Install/Step/Digest.cls` (a declaration-only area): the siblings of the Pairing purge and `Install/Step/Core.cls`.
- `Install/Registry.cls:20-37,71-74`: `Areas()` finds every `OcuTalon.Install.Step.<name>`; `Purge` calls each one. `Install/Task/Purge.cls` is the task.
- `src/short-names.tsv:13`: Pairing's short name. A new column changes nothing there.

**SessionOps**
- `Core/SessionOps.cls`: the stub (`STUB=1`, answers 5003).
- `Production.cls`: `:69` SessionOps (pool 1, enabled); `:17` TelegramOut (disabled); `:66-68` Notify.
- `Core/CommandsIn.cls`:
  - routes at `:163-177`: Pair → SessionOps from `telegram` only (173); Unpair and EndSession → SessionOps from `web_user,web_admin,telegram,timer,system` (174-175);
  - `TIMEOUT` 120 (33);
  - 5003 → `not_built` (83, 145-148);
  - a response that isn't a CommandResult → `failed`.
- `Core/Commands.cls:18-37`: `Submit`.
- `Msg/CommandResult.cls`: `Ok`, `Message`, `Outcome`, `Ref`, `DueAt`, `Data`. `Msg/Command/Pair.cls` (`CodeHash`, `ChatRef`) and `Unpair.cls` (`ChatRef`).
- Siblings to mirror:
  - `Schedule/ReminderOps.cls`: `:73-96` OnMessage dispatch, with a catch that answers `failed`; `:184-189` the locked open; `:127-133,199-205` publish after save, a failure only warned; `:315-330` `Refuse`/`Done`/`Result`.
  - `Schedule/Reminder.cls:31,87-99,150`: `NOTIFYITEM="Notify"`, building a Notification, `SendRequestAsync`.
  - `Core/SettingsOps.cls`: `:24` the `CHANNELS` origin→channel map; `:50-77` audit first; `:83-94` typed `%Set` audit data; `:104-107` the `WriteAudit` seam.
  - `Watch/IncidentManager.cls:740-743`: the `SendNotice` seam.
- `Live/Publish.cls`: `:62` `Publish(stream,type,payload,.seq)`; `:65` refuses inside a transaction; `:15,21` `pairing` is already in `TYPES` and `GUIDETRIGGERS`.
- `Live/Payload/Pairing.cls`: `Paired`, `DisplayName`.
- `src/bridge/cls/OcuTalon/Bridge/Audit.cls` (read only): `:78` `Record(type,data)`; `:20,28` members `irisUser,sessionRef,channel` + `change,reason`; `:39` change ∈ `linked,unlinked,rejected`; `:93-156` string values only, a non-empty `irisUser`, a channel in the bridge CHANNEL list (holds `telegram`, `web`, `system`), sessionRef "" or a Ref.
- `src/bridge/cls/OcuTalon/Bridge/Ids.cls:7-10` `NewRef`, and `Core/Conversation.cls:496-499` `RetryItemId`: the SHA-256 base64url sibling of `HashCode`.
- `Msg/Notification.cls`: `SessionRef`, `ChatRef`, `Kind`, `CatalogKey`, `Slots`.
- `Core/Rule/Notify.cls:31,34`: pairing + ChatRef → TelegramOut when `TelegramOn()`, otherwise nothing. `Core/Rule/Functions.cls:30-47`.
- `Msg/Catalog/Core.cls:17-47`: `pairing.paired`, `badCode`, `start`, `notPaired`, `stopped`, `unpairedFromPage`, `otherChatPaired`.

**AnswersIn**
- `Core/AnswersIn.cls`:
  - `:23` `CHANNELS` (`web,phone,telegram`); `:26` `TIMEOUT` 30;
  - `:31-44` `FromPage` (CreateBusinessService("AnswersIn") → ProcessInput);
  - `:46-68` `OnProcessInput` in order: bridge context → `not_allowed`; non-Ref SessionRef → `not_found`; `Ownership.Approval` → `not_found`; `bad_answer`; `%SuperSession`; `Send`;
  - `:74` the `Send` seam; `:78` `Refuse`.
- `Core/AnswerOps.cls:34-60`: the IRIS user comes from `Session.IrisUser`. `Core/Msg/Answer.cls` (`Ref`, `Action`, `Channel`, `SessionRef`). `Core/Msg/AnswerResult.cls` (`Result`, `WinnerAction`, `WinnerChannel`, `WinnerAt`).
- `src/bridge/cls/OcuTalon/Bridge/Approval.cls` (read only):
  - `:213` `IsRef`;
  - `:247` `Answer` returns `done`, `already_answered`, `expired`, `not_found` or `not_allowed`;
  - `:283` the Story 3.7 check (sessionRef "" or a well-formed Ref) and `HoldsRole`.
- `src/bridge/cls/OcuTalon/Bridge/Data/ApprovalRequest.cls`: `Kind`, `State`, `ExpiresAt`, `DryRun` (`affected`, `itemNoun{one,other}`).
- `Live/Payload/Approval.cls:85-103`: the dry-run parse to reuse.

**Status, /state, routes and guide**
- `Live/Payload/Status.cls`: `:10` CONDITIONS already lists `telegramPaused`; `:50-57` `Computed` builds 3 conditions; `:100-112` `HeartbeatStalled`, the sibling. `Live/Payload/Part/StatusSlots.cls`: `Time`.
- `Core/StatusMonitor.cls:28-60`: publishes the conditions that changed. Not edited (Epic 16 edits its OnProcessInput).
- `Web/Api.cls`:
  - `:6-7,111-112` the class comment and the two routes that call `Pairing`;
  - `:566-571` `Pairing()` (404, then 501);
  - `:584-632` `StateBody`, with the Telegram block at `:612-618`;
  - `:477-511` `DismissIncident`, the Submit-and-map sibling;
  - `:799` `Fail`.
- `Demo/Guide.cls:17-18,204-214`: `TelegramOn`, and `TelegramState` hard-coded to "off".

**Tests to mirror or update**
- `Test/Core/AnswersIn.cls` with its `AnswersInProbe`, `AnswerOpsProbe` and `ApprovalDouble` (`Begin`, `Calls`, `Arg`): the probe pattern.
- `Test/Core/AnswersInProduction.cls`: `Request` (role held) and `:291` `TestMalformedSessionRefIsNotAllowed`.
- `Test/Core/InProduction.cls`: `Guard`, `Session`.
- `Test/Core/SettingsOps.cls:391` (shadow instance through `Ens.Host.GetShadowInstance`) and `Test/Core/SettingsOpsProbe.cls:13-19`.
- `Test/Web/DismissApi.cls`: a route through the real production with stand-in request objects. Throwaway and CI only.
- `Test/Web/Api.cls`: `:1073-1083` `TestPairing`; `:160,324-356` the snapshot's Telegram block. Shared by entry.
- `Test/Demo/Guide.cls:214-226` `TestTelegramCountsAsOff`.
- `Test/Core/Routing.cls:185-266`.
- `Test/Core/CommandsInProduction.cls:34`: the stub row `EndSession|SessionOps|web_user`.
- `Test/Core/ProductionItems.cls:32`: the SessionOps row, `"stub": 1`.
- `Test/Data/Tables.cls:346-360`: the Pairing contract, compared exactly.
- `Test/Contract/Ac.cls:289-346`: signatures; class methods only.
- `Test/Contract/Mock.cls`: `:36-48` BASEURL, LOGFILE; `:333-398` `Arm`, `LogMark`, `LogSince`; `:480-488` `NewRequest`.
- `Test/Bridge/AuditLog.cls:23,30,61`: `Now`, `Entries`, `Wait`.
- `Test/Data/Fixture.cls`: `Session`, `Approval`, `SetTelegramIncluded` and `Pairing`. Contended: call, never edit.

**Mock and CI**
- `ci/mock/mock.mjs`:
  - `:43-58` `KEY_LIKE`, `redact`; `:163-166` `shortPath`, which already masks `/bot…`;
  - `:173-190` `emit`, `send`; `:192-241` `control`; `:295-332` `build`;
  - `:340-400` `handle`: the `/_mock/` dispatch at 347, the 404 rule at 387-396 (today it names Story 10.3), then the `x-api-key` 401 at 397.
- `ci/mock/scenarios.mjs`: `:16` the header; `:98-143` `checkReply`; `:145-183` `checkScenario`, which refuses `telegram` at 164-165; `:209-278` `loadScenarios`.
- `ci/mock/test/server.test.mjs`: `:68-105` `makeTree`, `withServer`; `:587-659` row 14, which pins the log entry's keys; `:679-702` row 17 (Bot API → 404).
- `ci/mock/test/scenarios.test.mjs:56,103,208`: the reserved-telegram defects.
- `ci/mock/test/helpers.mjs`.
- `ci/compose.ci.yml`.
- `docker/tests/test-compose-file.sh`: `:205-238` `ci_file_is_exact`; `:279-294` the CI-only variable checks.
- `docker/tests/lib-live.sh`: `:82-85` the decoy env; `:645-655` `check_no_key`.
- `docker/tests/test-compose-start.sh:216-223`: the same key count.
- `docker/tests/test-boundaries.sh:39-41`: `key_like`, which includes `[0-9]{8,10}:[A-Za-z0-9_-]{35}`.

**Web**
- `web/src/app/api/api-client.ts`: `:8` `BASE`; `:51-53` `postGuideMarker` (Story 4.7, already here); `:61-72` `answerApproval`, `dismissIncident`; `:74-84` `accepted`.
- `web/src/app/api/api-types.ts`: `:21-29` `TelegramState` (since Story 2.8); `:48`; `:106-108` `ApiError`.
- `web/src/app/api/envelope.interceptor.ts`: `:11,27-29` sets `Content-Type` and `X-OcuTalon-Request` on POST, PUT, PATCH and DELETE. Contended: read only.
- `web/src/app/feed/break-feed-api.ts`: `BreakFeedApi.press()` and `BreakFeedSent`. Its only importer is `break-feed-box.ts:12,161,221`.
- `web/scripts/approval-sources.test.mjs:137-148` and `source-files.mjs`: the source-test sibling.
- `web/e2e/demo-path/not-built.ts:11`: `notBuilt(title, story)`.
- `web/scripts/demo-path-summary.mjs:29-55,126-127`: a file must be `telegram-<step>.spec.ts`, where step ∈ page, watch, reminder, incident, approval or trace, and a skip must name `Story N.M`.
- `web/e2e/api/api.spec.ts:57,140,323`: the default Telegram block and the pairing routes' 404.
- `web/e2e/support/iris.ts:71,89,1022`: `irisScript`, `chk`, `setTelegramIncluded`.
- `web/playwright.config.ts:28`: `workers: 1`.
- `web/package.json`: Angular 22.2.3, no QR library, lockfile v3. Contended.

## Tasks & Acceptance

**Execution** (groups A to F in dependency order; F5 is separable):

*0. Measure (once, on the warm stack, before `Test/Web/PairingApi.cls`'s paired-DELETE case is written)*
- Use a temporary `%UnitTest` class, `OcuTalon.Test.Core.ZzTelegramQueueProbe`, that extends `OcuTalon.Test.Core.InProduction`. Run it once with `ci/iris.sh class` on the warm stack, record what it logs, then delete the file; it is never committed.
- With `Included()` = 1 for the duration of the run, send one fixture kind-`pairing` Notification with a fixture ChatRef to `Notify`, through a business service created in the job, as `Test/Core/RoutingProduction.cls` sends. Record:
  - whether a `Notify`→`TelegramOut` header appears within 10 s, and its `Status`;
  - `##class(Ens.Queue).GetCount("TelegramOut")` before and after;
  - whether an event-log row of Type 2 or 6 is written.
- Then remove the item with `Ens.Queue` (`EnumerateItem` to find it, `AbortItem` to remove it). Confirm that the count returns and that the header is no longer queued. Restore `Included()`.
- Record the results under `## Verification`. They fix `PairingApi`'s clean-up: abort the item as measured, or nothing to clean if the send is refused. If an error row is written, `PairingApi` asserts the paired DELETE with `Included()` at 0 through `Test.Web.ApiProbe` instead, and Design Notes record the change.

*A. Data*
- `src/ocutalon/cls/OcuTalon/Data/Pairing.cls`. Append the columns and indexes below, with `COLLATION = "EXACT"` on the new string columns, recompile and commit the regenerated `Storage` block (AD-5, append-only).
  - Columns: `CodeSessionRef` (22), `CodeHash` (64), `CodeExpiresAt` (20), `CodeUsedAt` (20), `ReplySlotAt` (20), `SeenAt` (20).
  - Indexes: `CodeSessionRefIndex`, `CodeHashIndex`.
  - Add these class methods:
    - `HashCode(code) As %String`. Algorithm: `$Translate($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256,$ZConvert(code,"O","UTF8")),1),"+/=","-_")`; `""` for `""`.
    - `RecordChat(chatId, displayName, Output sc) As %String`.
      - The chat id is `?.1"-"1.20N`.
      - The name is trimmed, control characters are stripped and it is cut to 128.
      - Find-or-create runs under `LOCK +^OcuTalon.Data.Pairing("chat",chatId):5`.
      - It returns the `Ref`.
    - `TakeReplySlot(chatRef) As %Boolean`. Atomic under the row's exclusive lock; 60 s.
    - `StoreCode(sessionRef, codeHash, expiresAt) As %Status`. The code row is created with its own `NewRef()` `Ref`.
    - `Chat(chatRef) As OcuTalon.Data.Pairing`. The chat row with exactly this Ref and a `ChatId`, or "".
    - `ForCode(codeHash) As OcuTalon.Data.Pairing`. Exact.
    - `Purge(daysToKeep) As %Status`. Rows with no `SessionRef` whose `SeenAt` (or `CreatedAt` when it is empty) is before the cutoff. The validation and cutoff follow `Digest/Data/Item.cls:64-87`.
  - Every write opens its row with exclusive concurrency (4) and sets only its own columns.
  - Rationale: AD-4, AD-27 and the Integration ACs for Story 12.4/12.5.
- `src/ocutalon/cls/OcuTalon/Data/StatusMark.cls`. Add `RecordTelegram(state, botUserName) As %Status`, which writes the single mark `telegramState` with the JSON value `{"state","botUserName"}` through `Record`. Add `TelegramState(Output botUserName) As %String`, which answers `off` with no mark (AD-14).
- `src/ocutalon/cls/OcuTalon/Install/Step/Core.cls` (new). The Core area's declaration-only class: `Purge(daysToKeep)` → `##class(OcuTalon.Data.Pairing).Purge(daysToKeep)`. It mirrors `Install/Step/Digest.cls` and is not in `Order()` (AD-27; Story 30.2's task finds it).
- `src/ocutalon/cls/OcuTalon/Data/Ownership.cls`. Append exactly one self-contained block at the end of the class: `ClassMethod ApprovalKnown(ref As %String, Output sc As %Status) As %Boolean`.
  - It answers 1 when an `ApprovalRequest` with exactly this Ref exists in a state other than `cancelled`, whoever owns it.
  - It uses object access, uses no `Rows` or `Statement` path, and returns no row or field.
  - Rationale: AD-31 lets Core read `Bridge.Data` only through the ownership API.

*B. SessionOps*
- `src/ocutalon/cls/OcuTalon/Core/SessionOps.cls`. Delete `STUB` and the stub handler. `OnMessage` dispatches as follows, with a catch that answers `failed`:
  - **`Pair`.** It handles the rows of the matrix. Order: the chat (`Pairing.Chat`), then the code (`ForCode`: unknown, then used, which includes the repeat case, then expired), then the code's session row (a missing one counts as `unknown_code`), then the `linked` audit (audit first). Then come any moves through `Unlink`: `moved` with no notice, and `other_chat` with `pairing.otherChatPaired`. Last, the link: `SessionRef`, `SeenAt`, `CodeUsedAt`, then the event.
  - **`Unpair`.**
    - Origin `telegram`: `Chat(ChatRef)` gives the session, then `Unlink(session, chatRef, "stop", "telegram", "")`.
    - Any other origin: `Unlink(command.SessionRef, command.ChatRef, "page", <channel>, "pairing.unpairedFromPage")`, where a ChatRef, when given, must be the session's paired chat.
    - The result is `unpaired` or `not_paired`.
  - **`EndSession`.** Answers `$$$ERROR($$$NotImplemented)` until Story 16.4.
  - **The public unlink.** `Method Unlink(sessionRef As %String, chatRef As %String, reason As %String, channel As %String, noticeKey As %String = "", Output changed As %Boolean) As %Status`, as Design Notes specify.
  - **Seams.** Two private, overridable methods: `WriteAudit(data)` (SettingsOps) and `SendNotice(notification)` (IncidentManager), the latter being `SendRequestAsync("Notify", n, 0)`.
  - **Channels.** The origin→channel map is `telegram:telegram,web_user:web,web_admin:web,timer:system,system:system`.
  - **The audit's IRIS user.** It is that session's `IrisUser`, else `$Username`.
  - Rationale: AD-1, AD-4, AD-12, AD-17, AD-32.

*C. AnswersIn*
- `src/ocutalon/cls/OcuTalon/Core/AnswersIn.cls`. Add `ClassMethod FromTelegram(ref As %String, action As %String, chatRef As %String, Output code As %String, Output slots As %DynamicObject) As %Status`. In order:
  1. If the Ref isn't a Ref, or the action isn't approve or reject → `unknown`.
  2. If `Pairing.Chat(chatRef)` finds no chat row, or it has no `SessionRef` → `not_paired`.
  3. If the `SessionRef` isn't a Ref (`Approval.IsRef`) → `not_allowed`, and nothing is sent (DW-200).
  4. Otherwise it builds a `Core.Msg.Answer` (`Channel` `telegram`, `SessionRef` = the row's) and hands it to `AnswersIn` through a private class-method seam `Deliver(answer, .result)` (CreateBusinessService + ProcessInput, as `FromPage` does).
  5. It maps the result:
     - `done` → `approved` (slots `count` and `itemNoun` from the row's dry run, read through `Ownership.Approval(ref, S)` and parsed as `Live/Payload/Approval.cls:85-103` does) or `rejected`;
     - `already_answered` → `{action, channel, time}` from the Winner fields;
     - `expired` → `{time}` from the row's `ExpiresAt`;
     - `not_allowed` → `{kind}`;
     - `not_found` → `not_visible` when `Ownership.ApprovalKnown(ref)`, else `unknown`;
     - `bad_answer` → `unknown`;
     - an error status is returned as is.
  - Rationale: AD-11, AD-30, DW-200.

*D. Status, /state, routes, guide*
- `src/ocutalon/cls/OcuTalon/Live/Payload/Status.cls`.
  - `Computed` gains an optional fourth reading, `telegram` (`{"pausedUntil","now"}`). When it is omitted, it reads `StatusMark.Get("telegramPaused")` and `Data.Time.NowUtc()`.
  - A private `TelegramPaused(reading)` builds the condition after `heartbeatStalled`.
  - A public `TelegramPausedUntil(now = "") As %String` gives the mark's value while it is a UTC time after now, else "". `/state` and the code route use it.
- `src/ocutalon/cls/OcuTalon/Web/Api.cls`.
  - Routes are unchanged. `Pairing()` keeps the 404 first, then branches on `%request.Method` to two private methods:
    - `PairingCode()`:
      - checks `TelegramState` = `on`, else 409 `not_available` with `MESSAGETELEGRAMOFF`;
      - checks `TelegramPausedUntil` = "", else 409 `not_available` with `MESSAGETELEGRAMPAUSED`;
      - then makes the code with `Ids.NewRef()`, calls `StoreCode` with `HashCode` and now+600 s, and answers 200 `{"code","expiresAt"}`.
    - `Unpair()`: submits `Unpair` {SessionRef} with origin `web_user`. `Ok` and `not_paired` → 200 `{"result":"done"}`; `not_built` → 501; anything else → 500.
  - `StateBody`'s Telegram block takes `state` and `botUserName` from `StatusMark.TelegramState`, and `pausedUntil` from `TelegramPausedUntil`.
  - Update the class comment.
- `src/ocutalon/cls/OcuTalon/Demo/Guide.cls`. `TelegramState()` returns `##class(OcuTalon.Data.StatusMark).TelegramState()`, and the class comment drops "until Story 10.3".

*E. Mock and CI*
- `ci/mock/scenarios.mjs`. Accept `match.telegram` for the five methods (`BOT_METHODS`), in either folder. Telegram replies take `status`, `headers`, `delayMs` and a required object `body`, and nothing else. Refuse `getFile` with "arrives in Story 25.3". Several scenarios may name one method. Update the header.
- `ci/mock/mock.mjs`. Add a Bot API branch in `handle` before the `x-api-key` rule. It parses query, JSON and form params; it uses the queued reply, else the update queue for `getUpdates` (with long-poll and offset), else the defaults below. It reuses `entry`, `emit`, `build`'s `body` path, `send` and the delay.
  - New log fields: `tokenLength` (null for model calls) and `request` `{botMethod, paramNames}`.
  - `control` gains `POST /_mock/telegram/updates`, `POST /_mock/telegram/replies`, `GET /_mock/telegram/calls` and `POST /_mock/telegram/reset`.
  - The defaults:
    - `getMe` → `{"ok":true,"result":{"id":424242,"is_bot":true,"first_name":"OcuTalon CI","username":"ocutalon_ci_bot"}}`;
    - `sendMessage` and `editMessageText` → an `ok` Message with a `message_id` counter, `chat.id` as given and `text`;
    - `answerCallbackQuery` → `{"ok":true,"result":true}`.
  - Update the header.
- `ci/mock/test/helpers.mjs`, `server.test.mjs`, `scenarios.test.mjs`, `telegram.test.mjs` (new). Move `makeTree` and `withServer` into `helpers.mjs`. Update row 14 (keys + `tokenLength`), row 17 (Bot API now served) and the reserved-telegram defects. The new file covers every mock row of the matrix, and token redaction in both stdout and the log.
- `ci/compose.ci.yml`. In `iris.environment` add `OCUTALON_TELEGRAM_API_BASE: http://mock:8080` and `TELEGRAM_BOT_TOKEN: ocutalon-ci-dummy-bot-token`, and update the header comment (AD-19, AD-22).
- `docker/tests/test-compose-file.sh`. Update `ci_file_is_exact` and its comment. Add checks that the iris block sets each of the two variables once, and that the judges' files name neither (mirror `mock_key_header_absent`).
- `docker/tests/lib-live.sh` and `docker/tests/test-compose-start.sh`. `check_no_key`, and the start script through a shared lib-live function, accept `TELEGRAM_BOT_TOKEN` only when it equals the dummy that `ci/compose.ci.yml` sets. They read the dummy from that file, never from a second literal, compare it inside the container, print counts only, and update the PASS and FAIL texts.

*F. Web*
- `web/src/app/api/api-types.ts`. Add `PairingCode { code: string; expiresAt: string }`, `UnpairDone { result: 'done' }` and `BreakFeedSent` (moved from `feed/`). Add a doc comment on `TelegramState` that names its server source.
- `web/src/app/api/api-client.ts`. Add `pairingCode()`, `unpair()` (`this.http.delete<UnpairDone>(…, { body: {} })`) and `breakFeed()`.
- `web/src/app/feed/break-feed-box.ts`; delete `web/src/app/feed/break-feed-api.ts`. Inject `ApiClient` and call `breakFeed()`; the behaviour is unchanged. This addresses DW-231 and U-84.
- `web/e2e/demo-path/telegram-page.spec.ts` and `telegram-approval.spec.ts` (new). Each has one `notBuilt(...)` naming `'12.4'` and `'12.7'`, with a header saying Lane A owns the file from Epic 12 (AD-29).
- `web/package.json`, `web/package-lock.json` (Task F5; allowed by the orchestrator's ruling of 2026-10-28T20:05:05Z under the conditions in Design Notes, "Orchestrator ruling"). Run `npm --prefix web install --save-exact --ignore-scripts qrcode-generator@2.0.4` with the project's own npm (the same major CI uses). `package.json` gains exactly one line in `dependencies`, `"qrcode-generator": "2.0.4"`, and nothing else changes; the lockfile diff holds only the new `node_modules/qrcode-generator` entry and the root package's dependencies line. Check both with `git diff`; anything else that moved (lockfileVersion, another package's resolved or integrity field, a dedupe) is reverted and the step redone. `npm --prefix web ci` must pass on the result. Nothing in `web/src` imports it yet. The Stack row is written by the lead (Design Notes).
- `web/scripts/api-client-sources.test.mjs` (new). Pin the three client methods' verbs, URLs and bodies. Pin that `inject(HttpClient)` appears only in `api/api-client.ts`, that `feed/break-feed-api.ts` is absent and that `break-feed-box.ts` calls `breakFeed()`. Mirror `approval-sources.test.mjs`.
- `web/scripts/qr-pin.test.mjs` (new, with F5). Pin:
  - `package.json` pins `qrcode-generator` at exactly `2.0.4`;
  - the lockfile entry is 2.0.4, MIT, with no `dependencies`;
  - the library renders `https://t.me/ocutalon_ci_bot?start=` + a 22-character code to an `<svg` string with no Node API;
  - the spine's Stack section names `qrcode-generator` and `2.0.4`.
- `web/e2e/api/pairing.spec.ts` (new; the Rule 3 real-HTTP evidence; runs in `live:sign-in`). With the envelope headers:
  - Included 0: both routes answer 404.
  - Included 1 and `RecordTelegram("on",…)` through `irisScript`: POST answers 200 with a 22-character code; state `off` answers 409 `not_available`; DELETE answers 200 `{"result":"done"}`.
  - It restores both seams (`TelegramIncluded`, mark `telegramState`) in `finally`, because `api.spec.ts:140` expects the defaults.

*G. IRIS tests (each new class has a header saying what it pins and needs)*
- `Test/Data/PairingRows.cls` (new). Covers the HashCode, RecordChat, TakeReplySlot, StoreCode, Purge and RecordTelegram rows and the Delivery row. It cleans up its own rows by Ref.
- `Test/Core/SessionOps.cls` + `SessionOpsProbe.cls` (new). A shadow instance with the two seams captured covers every Pair, Unpair and Unlink row, the events (read from `Live.Event`) and "Integration: Notify reads SessionOps' notice". The captured Notification goes through the Notify rule as `Test/Core/Routing.cls` drives it.
- `Test/Core/SessionOpsProduction.cls` (new, `InProduction`, throwaway and CI only). A fixture TelegramIn submits `Pair` and `Unpair` through `Commands.Submit` with origin `telegram`, and `web_user` for the page. It checks the real audit entries (`Test.Bridge.AuditLog.Wait`, no chat id or name in their data), the events, `TelegramPaired`, `/state` `paired`, `Guide.Compute`, and `EndSession` still `not_built`. Included stays 0 while notices are sent.
- `Test/Core/AnswersTelegram.cls` (new). A probe class extends `AnswersIn` and overrides `Deliver` to drive `AnswersInProbe`'s `OnProcessInput` with `ApprovalDouble`. It covers every FromTelegram row and code. DW-200: `ApprovalDouble.Arg(n,"sessionRef")` = S, never C, and the malformed-session row never calls the double.
- `Test/Core/AnswersTelegramProduction.cls` (new, `InProduction`). Uses the real `Answer`:
  - approved with slots, and the row's `AnsweredChannel` = `telegram` and `AnsweredBy` = S's user;
  - the Approval audit entry's `sessionRef` = S;
  - `already_answered`, `expired` and `not_allowed` with their slots;
  - DW-200: the existing `AnswersInProduction.TestMalformedSessionRefIsNotAllowed` stays green, and a press from a chat whose row holds a chat id answers `not_allowed` with the row left pending.
- `Test/Core/TelegramCalls.cls` (new). TryConsume and Trace.Join with channel `telegram` (fixture TelegramIn calls; Story 16.9 adds refusals).
- `Test/Web/PairingApi.cls` (new; mirrors `DismissApi`; throwaway and CI only). Covers every code-route and page-Unpair row, through stand-in request objects and the real production. The paired-DELETE case cleans up as Task 0 settles. It checks that the code is in no `Pairing` column, no live-event payload and no audit entry written during the test.
- `Test/Web/Api.cls` (entries only). `TestPairing`: 404, then with Included 1 and state `off` a POST answers 409 `not_available`. The snapshot Telegram test gains the `/state` block row.
- `Test/Live/Status.cls`. The `telegramPaused` row through `Computed` with an injected reading, and the default read.
- `Test/Core/StatusMonitor.cls` (entries). A recorded future pause makes the next run publish one `status` event `telegramPaused` (active, Time = until). A run after the pause ends publishes it inactive. This mirrors the class's existing `heartbeatStalled` publish cases. The test removes its mark.
- `Test/Demo/Guide.cls`. Replace `TestTelegramCountsAsOff` with the Guide row.
- `Test/Data/Tables.cls` (the Pairing entry), `Test/Core/ProductionItems.cls` (the SessionOps row `"stub": 0`), `Test/Contract/Ac.cls` (signature entries for `Pairing.HashCode`, `RecordChat`, `TakeReplySlot`, `StoreCode`, `Purge`, `StatusMark.RecordTelegram`, `TelegramState`, `AnswersIn.FromTelegram`, `Ownership.ApprovalKnown`, `Install.Step.Core.Purge`). Update every other test that asserts a changed shared surface: search the test trees (Rule 19).
- `Test/Contract/Mock.cls`. Add `TestTelegramBotApi`, the "Integration: IRIS reaches the mock" row. It uses the existing guard pattern and checks that `OCUTALON_TELEGRAM_API_BASE` = `http://mock:8080` and that the token is non-empty. It never writes the token to a log, assertion text or status.

**Acceptance Criteria:**
- **Pairing (FR-9, FR-18, AD-4, AD-17).**
  - Given a fixture TelegramIn that hashes a code from `POST /api/v1/pairing/code` with `Pairing.HashCode` and submits `Pair` with origin `telegram` through `Commands.Submit`, with the ChatRef from `RecordChat`.
  - When SessionOps runs in the real production.
  - Then the chat is linked, the code is marked used, one `Pairing` audit entry names S's user, S and `telegram` and holds no chat id or name, and S's page receives a `pairing` event. An unknown, expired or used code links nothing and is audited. Every outcome comes back in the CommandResult.
- **Pairing's consumers.** Given a pairing made by SessionOps, when `Notify`'s `TelegramPaired`, `/state` and `Guide.Compute` read it, then each reports the session paired with Included 1 and state `on`, and unpaired after `/stop`. This is the Integration AC: the consumers are Notify, the web layer and the guide.
- **Notices to a dropped chat (FR-18, FR-19, AD-14, AD-32).** Given a page Unpair or a second chat, when SessionOps unlinks the first chat, then it sends one kind-`pairing` Notification with that chat's ChatRef and `pairing.unpairedFromPage` or `pairing.otherChatPaired`. Notify routes it to `TelegramOut` alone with Included 1, and nowhere with 0. A moved chat gets no notice.
- **The unlink API (AD-29; Consumed-by Story 16.4).** Given `SessionOps.Unlink` with its documented signature, when it is called for a paired session, then it unlinks with an audit entry and an event and reports `changed`. For an unpaired session it changes nothing.
- **Pairing rows (FR-15, FR-19, AD-27).** Given `RecordChat`, `TakeReplySlot` and the Core area's `Purge`, when they are called directly as Stories 12.4, 12.5 and 30.2 will, then they behave as the matrix says, and `Install.Registry.Areas()` lists the Core area.
- **The code route (FR-18, FR-21, FR-22, AD-1, AD-4).**
  - Given a signed-in session, when the page calls `POST /api/v1/pairing/code`:
    - Included 0: 404.
    - Included 1, state `on`, no pause: 200 with a 22-character code that is stored only as its hash, with a 10-minute expiry, replacing the session's earlier code.
    - Otherwise: 409 `not_available` and no code.
  - The same holds over real HTTP (`web/e2e/api/pairing.spec.ts`).
- **The unpair route.** Given a paired session and Included 1, when the page calls `DELETE /api/v1/pairing`, then the chat is unlinked through `CommandsIn` → `SessionOps` with an audit entry, an event and the page notice, and the answer is 200 `{"result":"done"}`. With Included 0 the answer is 404.
- **Status (FR-21, FR-22, AD-12).** Given `StatusMark.Record("telegramPaused", until)` and `RecordTelegram(state, bot)`, when `/state` is read and `StatusMonitor` ticks, then the `telegramPaused` condition is active with Time = `until` until that time and off after it, and `/state`'s `TelegramState` block reports `included`, `state`, `botUserName`, `paired`, `displayName` and `pausedUntil` from those sources. `included` is false in every judge's install, so the rail shows no Telegram section.
- **AnswersIn's Telegram entry (FR-8, FR-9, FR-20, AD-11, AD-30, DW-200).**
  - Given fixture `TelegramIn` calls to `AnswersIn.FromTelegram` with an approval Ref, the action and the press's ChatRef.
  - When AnswersIn handles them.
  - Then:
    - every code of the closed set comes back with its slots;
    - a press from the paired chat records channel `telegram` and the session's IRIS user on the real row;
    - `Approval.Answer` only ever receives the paired session's Ref;
    - a chat whose row holds no valid session Ref answers `not_allowed`.
- **Direct calls (FR-20, FR-40, AD-1, AD-14, AD-20, AD-26).** Given `Allowance.TryConsume`, `Trace.Join` and `Delivery.Record`/`FindByApproval` called with channel `telegram`, when a fixture TelegramIn calls them, then the call is allowed with `retryAt` "" and no first refusal, the thread id is stable, and a `<ChatRef>:<message_id>` delivery is found only for its own owner.
- **The mock (FR-22, NFR-11, AD-19, AD-22).**
  - Given the CI override.
  - When IRIS calls `<OCUTALON_TELEGRAM_API_BASE>/bot<TELEGRAM_BOT_TOKEN>/<method>`.
  - Then the mock serves the five methods with the queue, reply and call endpoints and the `telegram` scenario form. It logs the token by length only, including in the URL path, and every "start with no key" check still holds, with the dummy token the only bot token in the container.
- **Web (REL-2, AD-29, Stack row "Angular").** Given `web/`, when this story merges, then:
  - `ApiClient` is the page's one typed API client, with the pairing methods and `breakFeed()`, and DW-231 is closed;
  - the two `telegram-*.spec.ts` files exist and skip with their Lane A story;
  - with Task F5, `qrcode-generator` 2.0.4 is pinned and recorded in the spine's Stack section.
- **The switch.** Given all of the above, when a judge installs 0.1.0, then `Included()` returns 0 and nothing Telegram is visible or reachable: no rail section, the pairing routes answer 404, and `TelegramIn` and `TelegramOut` stay disabled.

### Review Findings

Code review of 2026-10-28 (`bmad-code-review`, full mode, diff `git diff 3cc3045` plus QA's uncommitted tests; four layers, 34 rows, plus two Rule 2 findings by the reviewer; 10 entries after grouping: high 0, med 6, low 4).

- [x] [Review][Patch] (med; Rule 19, Boundaries "Nothing is left in TelegramOut's queue") `TestBodyNamesNoSession` sends a paired DELETE with Included 1, so its `pairing.unpairedFromPage` notice is queued in the disabled `TelegramOut` and never removed [src/ocutalon/cls/OcuTalon/Test/Web/PairingApi.cls:238] — fixed: the test waits for the Notify-to-TelegramOut hop, aborts its own queued item and checks the queue count is back; the class header says so
- [x] [Review][Patch] (med) A reply queued for `getUpdates` while a long poll waits is not served until the poll times out (up to 50 s): `queueReplies` wakes no waiter and the wait loop checks only the update queue; Story 12.x's 409/429 tests would outlast their 20 s waits [ci/mock/mock.mjs:314] — fixed: `queueReplies` wakes the long polls, a waiting `getUpdates` ends when a reply is queued for it and serves that reply; header updated; new test in `telegram.test.mjs`
- [x] [Review][Patch] (med; Rule 19) Two tests assert on the Telegram marks without setting them: `HeartbeatLogic.TestStalledCondition` counts `ActiveOf` with the real `telegramPaused` mark, and `Test.Web.Api.TestStateSections` asserts state `off` and no pause before it saves or clears either mark [src/ocutalon/cls/OcuTalon/Test/Schedule/HeartbeatLogic.cls:117] — fixed: `HeartbeatLogic` passes a telegram reading of "" to every `Computed` call; `TestStateSections` saves and clears both marks before its first `StateBody` and puts them back
- [x] [Review][Patch] (med; Rule 19) `TestPageUnpairSendsTheNotice` checks that Notify sent nothing to `TelegramOut` after a fixed `Hang 2`, not after Notify has handled the Notification [src/ocutalon/cls/OcuTalon/Test/Core/SessionOpsProduction.cls:190] — fixed: it waits with the existing `Test.Core.Observe.WaitProcessed` (the SessionOps-to-Notify request completed) before the absence check
- [x] [Review][Patch] (low) `Data.Pairing.Chat`, which Lane A's `TelegramOut` calls to resolve a ChatRef, has no cross-lane signature pin [src/ocutalon/cls/OcuTalon/Test/Contract/Ac.cls:306] — fixed: `{Pairing, Chat, chatRef, OcuTalon.Data.Pairing}` added to the signatures and the class header
- [x] [Review][Patch] (low) `pairing.spec.ts` records the code's hash for the clean-up only after five assertions, so a failure among them leaves the code row behind [web/e2e/api/pairing.spec.ts:90] — fixed: each hash is taken right after its POST is read, before any assertion
- [x] [Review][Patch] (low) Decided 21 ("a 409 reads no session") is pinned by no test: a 409 from the code route must leave the CSP session unattached [src/ocutalon/cls/OcuTalon/Test/Web/Api.cls:1097] — fixed: `TestPairing` keeps the CSP session of the 409 call and asserts it holds no `OcuTalon.SessionRef`
- [x] [Review][Defer] (med) The mock's Bot API state is one global queue, call list and counter that assumes one client: `reset` restarts `update_id` at 1 (Decided 23), so a poller that keeps its offset drops new updates as confirmed, and `Test.Contract.Mock.TestTelegramBotApi` expects exactly its own three calls and `update_id` 1 [ci/mock/mock.mjs:330] — deferred: spec-bound (Decided 23) and reachable only once Story 12.1 runs an enabled `TelegramIn` poller against the mock; routed to Story 12.1 (DW-370)
- [x] [Review][Defer] (med; Rule 2) `Data.Pairing.Purge` repeats about 20 of the 22 lines of Lane A's `Digest.Data.Item.Purge` (the day validation and the cutoff), a copy forced by AD-29 and Task A's "follow" [src/ocutalon/cls/OcuTalon/Data/Pairing.cls:217] — deferred: Lane A owns the sibling; routed to Story 30.2, whose `Bridge.Purge` would be a third copy (DW-371)
- [x] [Review][Defer] (low; Rule 2) The new Pairing test classes each carry their own `NewChat`, `Code`, `Submit`, `Hops` and `WaitHops` helpers (`Test/Core/SessionOps`, `SessionOpsProduction`, `AnswersTelegramProduction`, `Test/Web/PairingApi`, beside `RoutingProduction.WaitHops`) [src/ocutalon/cls/OcuTalon/Test/Web/PairingApi.cls:312] — deferred: weak reason (per-class helpers bound to each class's clean-up list; the shared home `Test.Data.Fixture` is contended); not a two-way door; `wontfix-accepted` (DW-372)

Rejected (closed at emission):
- `false` A reverse-order fresh run is not recorded — it is the lead's pre-push check (Rule 19), after review.
- `false` `CommandsInProduction` still calls SessionOps "the stub owner" — the class sends only EndSession, which SessionOps still answers `not_built`, and Shared surfaces keeps that row.
- `false` The registry purge tests delete old unpaired Pairing rows on a slot — that is `Purge`'s contract (AD-27); a slot holds no real pairing in 0.1.0, and an unpaired chat row is recorded again on its next message.
- `false` The TryConsume assertion cannot fail and the StatusMonitor tick has no mutation line — `TryConsume`'s body is the code under test (a `Quit 0` mutation turns it red), and Rule 19 asks one mutation per AC: both ACs have one.
- `false` lib-live's decoy `TELEGRAM_BOT_TOKEN` is shadowed by the override's `environment` — the decoy env_file is dropped or kept whole, and `ANTHROPIC_API_KEY=decoy` still detects a kept one.
- `false` `StoreCode` does not re-compare `CodeSessionRef` after the index open — the column is `COLLATION = "EXACT"` and its index unique, so the open is exact.
- `false` The code route's "nothing read" is not testable — the auditor found the code compliant (`Included()` first).
- `low` (spec-bound, by-design) The mock's `editMessageText` answers a new `message_id` and `sendMessage` without `chat_id` answers 200 — Task E sets these defaults; a test can queue a reply for the real API's shape; reopen_if=a Lane A test needs the edited message's own id.
- `low` (spec-bound, by-design) An Unpair from origin `timer` or `system` is audited `page` with the page notice — Task B's "any other origin"; nothing sends such an Unpair (Story 16.4 calls `Unlink` with its own reason); reopen_if=a timer or system Unpair is added.
- `low` (spec-bound) `FromTelegram` maps an `Answer` `not_found` caused by a lock timeout on the session's own request to `not_visible` — Task C's mapping; it needs a lock held past LOCKSECONDS + TASKSECONDS; reopen_if=a press on the session's own pending request answers `not_visible`.
- `low` (theoretical) A `Link` that fails after the `linked` entry leaves that entry, and a `failed` Pair from an internal error (an `Unlink` or `Ownership` read error, the catch) writes no entry — audit first is Decided 5; both need a lock timeout or a failed save; reopen_if=a failed Pair is found with a `linked` entry or with none.
- `low` (already adjudicated) `Link` does not re-check the code against a concurrent `StoreCode` — the review pass rejected it; reopen_if=a code shown to a user is found used before they use it.
- `low` `RecordChat` cuts the name with `$Extract` and can split a surrogate pair at 128 — it needs a name of 128 UTF-16 units with an astral character across the cut, and the fix is a guard; reopen_if=a display name ends in U+FFFD.
- `low` The mock's Bot API method names are case-sensitive — a wrong case fails loudly with a 404, never a false green; reopen_if=a Lane A call uses another case.
- `low` (already adjudicated) `ApiClient.pairingCode()` and `unpair()` are pinned by source only — Task F names the source pins; Stories 12.3 and 12.4 are the first callers.
- `low` (already adjudicated) `PairingRows` does not enforce "throwaways and CI only" at run time — `Purge` is global by definition and the header says so.
- `low` `TestTelegramBotApi` calls the constant host, not the URL built from `OCUTALON_TELEGRAM_API_BASE` — the guard first requires the variable to equal that constant, so the call goes to the configured base.
- `low` `qr-pin.test.mjs` accepts any spine table row that names the library — only the Stack row does; reopen_if=another spine table row names `qrcode-generator`.

## Spec Change Log

## Review Triage Log

### 2026-10-28 — Review pass
- verdicts: 46 findings — high 0, medium 2, low 32, false 10, maybe-false 2
- findings:
  - Blind Hunter
    - `[low]` `[patch]` Pair can fail after a move or an other_chat drop, leaving the session with no chat and the dropped chat told of a pairing — real but deliberate: the matrix orders the unlinks before the `linked` entry, the dropped chat must learn that it lost its pairing, and the same unused code pairs again; the code is unchanged, the behaviour is stated in the class comment and pinned by the new `TestPairAuditFailsAfterADrop` (Decided 27).
    - `[low]` `[reject]` The rollback and failure branch of `Link` are untested — an error branch with no AC or matrix row, and testing the rollback needs a failure seam inside a transaction; reopen_if=a pairing is found linked with its code unused.
    - `[low]` `[reject]` `Link` does not re-check the code row against a concurrent `StoreCode` — it needs the user to ask for a new code in the same milliseconds as the old code pairs, and the only effect is that the new code reads as used; the fix adds a lock and re-checks; reopen_if=a code shown to a user is found used before they use it.
    - `[low]` `[patch]` `TestPurge` pins only coarse ages — rows an hour either side of the 30-day cutoff were added, by SeenAt and by CreatedAt; the mutation "cutoff a day older" is red.
    - `[low]` `[patch]` The mock reads a negative `getUpdates` offset as none — it now answers 400 (Decided 28), with a test, and the wait comment was reworded.
    - `[low]` `[patch]` The `FromTelegram` comment says `not_allowed {}` for a row with no session Ref — reworded: a row with no session value is `not_paired`, a value that is no Ref is `not_allowed {}`.
    - `[low]` `[patch]` The `TestBodyNamesNoSession` comment claims the caller's own chat is unlinked, and the `not_built` branch is untested — the test now pairs the caller's chat and asserts it is unlinked; the 501 branch stays because Task D requires it; reopen_if=an owner answers `not_built` again.
    - `[low]` `[patch]` `pairing.spec.ts` removes the wrong code row on failure — the latest hash is tracked and removed in `finally`; `live:sign-in` part 1 passes.
    - `[maybe-false]` `[defer]` The CI override's dummy bot token leaves no way to express a no-token start in CI once Included() is 1 — medium if true; it depends on how Story 12.1 enables its items; recorded in `deferred:` with what would settle it.
    - `[low]` `[patch]` Mutation evidence is missing for the key check, `pairing.spec.ts` and the QR pin, and the Auto Run Result status is stale — mutation lines were added for the key count and the QR pin, `pairing.spec.ts` runs in `live:sign-in`, and the Auto Run Result is rewritten at finalize.
    - `[low]` `[patch]` `PairingRows` holds an unused `MarkExisted` property — removed.
  - Edge Case Hunter
    - `[low]` `[patch]` Pair failure after drops — same root as the first Blind Hunter row: pinned, not changed.
    - `[low]` `[reject]` `Link` re-check — same root as the third Blind Hunter row.
    - `[low]` `[patch]` `RecordChat` treats a failed SQL lookup as "no chat" and makes a second row — a failed lookup is now an error status and no row (Decided 29); no test can cause the SQL error.
    - `[low]` `[patch]` A client that hung up before the long poll registers its close listener keeps the timer up to 50 s — the loop now also stops on a destroyed response.
    - `[low]` `[reject]` `Reject` writes an audit entry for every junk Pair — the AC audits every pair outcome (by design); a throttle belongs to the Telegram service, whose `TakeReplySlot` already limits replies; reopen_if=the audit log is flooded by junk /start commands.
    - `[low]` `[reject]` `qr-pin.test.mjs` fails with ENOENT when `web/node_modules` is absent — the web tests run after `npm ci` in CI, and the error names the file; unlikely and loud.
    - `[low]` `[patch]` Claim: the Pair order is moves first, not audit first — same root as the first Blind Hunter row (Decided 17 and 27).
    - `[false]` `[reject]` `telegramPaused` and the Telegram block read their marks without an Included() check — nothing writes either mark in 0.1.0 (the Telegram service of Story 12.2 does), so a judge's install holds the defaults, and the matrix rows for Status do not depend on Included().
  - Verification Gap
    - `[medium]` `[patch]` The "no Notification" assertions look in a trace that the Pair and /stop commands are not in — confirmed: those commands carry no session, and `CommandsIn.Join` sets the SuperSession only for a session. They now count the SessionOps-to-Notify headers newer than a mark, with a positive control in the page-Unpair test; the mutation "/stop sends a notice" is red.
    - `[low]` `[patch]` `RecordTelegram`'s "mark unchanged" assertion ran after successful writes — moved before them; the mutation "write before validating" is red.
    - `[low]` `[patch]` The unpair route's 500 mapping and the code route's 500s are untested — `TestNoSessionIs500` covers both routes (the mutation "404 for an unreadable session" is red); the `failed` outcome to 500 stays without a test because it needs a failure seam in a running production; reopen_if=an unpair that fails answers 200.
    - `[medium]` `[patch]` Three of the five origins in `CHANNELS` are never exercised — `TestUnpairOriginsAuditTheirChannel` covers web_user, web_admin, timer and system; the mutation "drop web_admin" is red.
    - `[low]` `[reject]` The lock and atomicity of `TakeReplySlot` and `RecordChat` are untested — a test needs a second job that holds the lock, and no consumer exists before Stories 12.4 and 12.5; reopen_if=two updates from one unpaired chat both get a reply.
    - `[low]` `[reject]` The `SessionOps` catch and the `Link` failure are untested — same root as the second Blind Hunter row (the catch is the generic safety net).
    - `[low]` `[patch]` Two fixed sleeps in the mock long-poll test — replaced by polling `/_mock/telegram/calls` until the `getUpdates` call is listed.
    - `[low]` `[patch]` One element of the token-in-refusal-body loop is vacuous — the loop now checks the text of every refusal, the 401 and the 405 included; the mutation "token in the 405 body" is red.
    - `[low]` `[patch]` `ApprovalKnown` exactness is untested — a wrong-case Ref of another session's request must answer `unknown`; the mutation "no exact compare" is red.
    - `[false]` `[reject]` Rule 19: some ACs have a mutation line that covers only part of the AC — Rule 19 asks for one demonstrated mutation per AC, and all 13 have one; more lines were added for the parts this review touched.
    - `[low]` `[reject]` `TestPurge` deletes every old unpaired row of the namespace — `Purge` is global by definition (AD-27), and the class header limits the test to throwaways and CI.
    - `[low]` `[reject]` `qr-pin.test.mjs` needs `web/node_modules` and reads the spine outside `web/` — same root as the sixth Edge Case Hunter row; the spine read is the Stack pin the spec requires.
    - `[low]` `[patch]` `pairing.spec.ts` leaks the second code row on failure — same patch as the seventh Blind Hunter row.
    - `[low]` `[reject]` Fixed `Hang` calls in two absence checks — they bound an absence check and cannot produce a false green.
    - `[maybe-false]` `[reject]` The second-chat notice is sent from a Pair command with no session, so it is in no session's trace — the spec is silent on its trace placement; if true it is low; reopen_if=a spec places the notice in the session's trace.
  - Intent Alignment (the divergences it reported)
    - `[false]` `[reject]` SessionOps rows run on the probe, with the real production only for some — by design (Task G: a shadow instance with the two seams, and the production classes for the end-to-end rows).
    - `[low]` `[patch]` Pair failure atomicity (C1 or C2) has no test after a drop — same root as the first Blind Hunter row; `TestPairAuditFailsAfterADrop` pins reading C2.
    - `[false]` `[reject]` "Origin telegram only" for Pair is not checked in SessionOps — the route map of `CommandsIn` sends Pair to SessionOps from `telegram` only (Code Map), and the comment says so.
    - `[low]` `[reject]` The REST rows are tested by direct calls and a subset over HTTP — as Task G and the Rule 3 note plan (`PairingApi` mirrors `DismissApi`, `pairing.spec.ts` is the real-HTTP evidence).
    - `[false]` `[reject]` No product caller of `RecordTelegram` or writer of the pause mark — intended: the first consumers are Stories 12.1 and 12.2 (Design Notes, Integration ACs).
    - `[low]` `[reject]` The web client is verified by a source scan — Task F names exactly these source pin tests; no Angular test host exists for `ApiClient` in this project.
    - `[false]` `[reject]` Nothing in the diff tests that `demo-path-summary.mjs` accepts both Telegram files — `live:demo-path` does, and its summary shows both skips (Story 12.4 and 12.7).
    - `[false]` `[reject]` The notice keys are not checked against the catalog — both keys are in `Msg/Catalog/Core.cls` (Code Map), and the Catalog tests own that file.
    - `[false]` `[reject]` Removing `STUB` while EndSession is unbuilt — Task B says to delete `STUB`, and EndSession keeps answering 5003 (`not_built`), pinned by two tests.
    - `[low]` `[reject]` The AD-6 scanner exempts `Data.Pairing.Chat` — Decided 18: a lookbehind on the receiver with a test that the same call on any other class is still flagged; reopen_if=a second class named `Chat` appears.
    - `[false]` `[reject]` No caller of `Purge` appears in the diff — Story 30.2 owns the task, and the Core area is how it finds `Purge` (Task A).
    - `[false]` `[reject]` The key check is tested with fakes except in `test-compose-start.sh` — the matrix row "CI env" names `test-lib-live.sh` and the compose-start key line, and `live:compose-start` passes with the dummy.

## Design Notes

**Governing ADs:** AD-1, AD-4, AD-5, AD-11, AD-12, AD-13, AD-14, AD-17, AD-19, AD-20, AD-22, AD-23, AD-26, AD-27, AD-29, AD-30, AD-31, AD-32 and AD-33.
- **AD-33.** `Pairing`, `StatusMark` and `Delivery` are Lane B's tables. `SessionOps` is the one `pairing` publisher.
- **No new item, table or event type**, so the ownership tables need no change.
- **No AC contradicts an AD Rule.** The paused 409 uses a plain parameter, not `Catalog.Render`, so AD-32's render exception, which names only the answer endpoint, is not widened.

**The unlink API (Consumed-by: Story 16.4):**

```
Method Unlink(sessionRef As %String, chatRef As %String, reason As %String, channel As %String,
              noticeKey As %String = "", Output changed As %Boolean) As %Status
```

- **Arguments.**
  - `sessionRef`: required.
  - `chatRef`: "" means the session's live pairing (`Ownership.Pairing`). A given ChatRef must be that chat.
  - `reason`: the audit `reason`.
  - `channel`: a `Msg.Enum` CHANNEL value, checked before any change.
  - `noticeKey`: "" sends no notice; otherwise one kind-`pairing` Notification carries the dropped ChatRef.
- **Effect when a chat is unlinked.**
  1. The chat row's `SessionRef` is cleared. The row stays, so `TelegramOut` can still resolve the ChatRef.
  2. One audit entry `unlinked/<reason>` names that session's `IrisUser`, else `$Username`.
  3. The notice, when `noticeKey` is set.
  4. One event, S→false.
  5. `changed` is 1.
- **Errors and no-ops.** An audit or publish failure is a warning. Nothing to unlink gives OK and `changed` 0.
- **Story 16.4's call.** In `End`, `..Unlink(command.SessionRef, "", "session_end", <its channel>, <its key or "">, .changed)`. The key is Story 16.4's choice.

**Decided in-stage:**
1. **Two kinds of `Pairing` row and `CodeSessionRef`.** `Ownership.Pairing`, which is contended, counts any row with a `SessionRef` as paired. Storing the code under `SessionRef` would show `paired: true` as soon as a code exists. The AC's "the session's `Pairing` row" is the code row keyed by `CodeSessionRef`.
2. **`SeenAt` defines "old" for the purge.** It is set by `RecordChat`, `StoreCode`, links and unlinks. "Old rows without a session" means a `SeenAt` (or a `CreatedAt` when it is empty) before the cutoff. A chat that keeps writing is never purged mid-conversation.
3. **Outcome codes.**
   - Pair: `paired`, `unknown_code`, `expired_code`, `used_code`, `unknown_chat`, `failed`.
   - Unpair: `unpaired`, `not_paired`, `failed`.
   - Audit reasons: `code`, `stop`, `page`, `moved`, `other_chat`, `session_end`, `unknown`, `expired`, `used`, `unknown_chat`.
   - Story 12.5 maps `unknown_code`, `expired_code` and `used_code` to `pairing.badCode`.
   - A used code repeated by the chat already on that session answers `paired` and changes nothing, so a re-sent update from TelegramIn is harmless.
4. **Which outcomes are audited.** Every pair outcome is audited. An unpair is audited only when it unlinks something.
5. **Audit first for links.** A missing `linked` entry refuses the link (SettingsOps' rule). Unlinks stand without one (Approval's rule), because refusing an unlink would keep access open.
6. **DW-200 reading.** The ledger body is about what reaches `Answer` ("any other sessionRef"). So:
   - no live pairing → `not_paired` (the AC);
   - a live pairing whose `SessionRef` is not a Ref → `not_allowed` with nothing sent ("an unresolvable one answers `not_allowed`");
   - a valid Ref → `Answer` gets exactly that Ref.
7. **`not_visible` versus `unknown`.** `ApprovalKnown` is appended to Ownership, because AD-31 forbids Core from reading `Bridge.Data` directly.
   - A cancelled request, a bad action and a malformed Ref answer `unknown`.
   - A tool-call approval has no dry run, so it carries empty slots (inference: Story 12.7 picks its text by kind).
8. **The page Unpair is idempotent.** It answers 200 when nothing was paired. No new error code is needed.
9. **One 409 code for the code route.** `not_available` matches the REST row's "409 (already answered, not available)". The messages are parameters:
   - `MESSAGETELEGRAMOFF` = "Telegram isn't on in this OcuTalon, so no pairing code was made."
   - `MESSAGETELEGRAMPAUSED` = "Telegram is paused, so no pairing code was made. Try again when the pause ends."
   - The 200 body is `{"code","expiresAt"}`. The page builds the `t.me` link from `/state`'s `botUserName` (Story 12.3).
10. **The `telegramState` mark.** One mark holds JSON `{state, botUserName}`, so `state` and `botUserName` change together. `pausedUntil` comes from the existing `telegramPaused` mark. `telegramPaused` is computed in `Live.Payload.Status.Computed`, which `/state` and `StatusMonitor` already share, so `StatusMonitor.cls`, which Epic 16 edits, is untouched.
11. **The mock.**
    - Bot API scenarios are named fixtures that tests queue through `/_mock/telegram/replies`. They are never auto-selected, because a Bot API call carries no marker. This is Story 12.1's "which tests queue through the mock's control endpoint".
    - `getUpdates` long-polls until `min(timeout, 50)` s, so a later poller never spins.
    - Parameter values go only to the in-memory `calls` endpoint. The log keeps parameter names and `tokenLength`.
    - The CI dummy is `ocutalon-ci-dummy-bot-token` with base `http://mock:8080`. Neither matches a key pattern.
12. **`check_no_key`.** The container may hold the CI dummy bot token. FR-38's "start with no key" is about the model key, which stays absent, and the decoy value still fails the check.
13. **The pairing routes keep their URL map.** `Pairing()` branches on the method, so `Test.Web.Api`'s route list is unchanged.
14. **Unlink notices.** `SessionOps` always sends its notice to `Notify`. `Notify` decides by `Included()`, so no Core code calls the switch.
15. **QR-code library: `qrcode-generator` 2.0.4.**
    - Facts read from the npm registry on 2026-10-28: MIT, zero runtime dependencies, bundled `.d.ts`, ESM `dist/qrcode.mjs`, canvas (`renderTo2dContext`) and SVG (`createSvgTag`) output, published 2025-08-07.
    - Rejected:
      - `qrcode` 1.5.4: CommonJS, with `yargs` and `pngjs` dependencies;
      - `uqr` 0.1.3: a 0.x version;
      - `lean-qr` 2.7.4: suitable, but younger and changing faster.
16. **No split.** Every part shares one contract: the row model, the outcome codes and the REST shapes. Epics 12 and 16 cite "Story 10.3" for the unlink, the mock and the client, so a split would rewrite dependency statements in other epics, which is owner-only. The task groups A to F are separable checkpoints inside one implement pass. If the lead prefers to split anyway, the natural cut is A–D (IRIS), E (mock and CI) and F (web).
17. **Move order of the audit entries.** The matrix orders a move's entries unlinked, then linked, and Task B puts the linked entry before the moves. The matrix stands: `Pair` runs the moves first, each through `Unlink` with its entry, event and (for a second chat) notice, then writes the `linked` entry, and only then writes the link. A failed `linked` entry still links nothing and answers `failed`. The old chat stays unlinked in that case, which is the safe side (Decided 5), and the unused code lets the user pair again.
18. **`Pairing.Chat` and AD-6's scanner.** `Test.Bridge.CodeRules` refuses any call of a method named `Chat` outside the runner and its adapter. `Pairing.Chat` is a table lookup. `CHATCALLS` therefore skips a call whose receiver is `OcuTalon.Data.Pairing`, and the test shows that the scanner passes that call and still flags the same call on any other class. Product code calls it only as `##class(OcuTalon.Data.Pairing).Chat(...)`.
19. **Unique code indexes.** `CodeSessionRefIndex` and `CodeHashIndex` are unique: IRIS does not check an empty value in a unique index, so the chat rows share it (measured on build 154). This gives `StoreCode`, which runs in a web request, and `ForCode` an index open, because the only unchecked SQL prepares are the three that `test-class-rules.sh` allows. `RecordChat` finds its chat by a checked `%ExecDirect` on the non-unique `ChatIdIndex`, because it runs only in the Telegram service's production job. An index open that finds nothing answers code 5770.
20. **Small validations.** `StoreCode` also refuses an expiry that is not a UTC time. `Unlink` also refuses an empty session and an empty reason, before any change. `TakeReplySlot` does not look at the pairing: the slot is the chat's, paired or not. The display name is stripped of control characters, then trimmed, then cut to 128.
21. **The code route reads the session last.** It checks the state and the pause first, so a 409 reads no session and makes no `Session` row. The 200 is `{"code","expiresAt"}`, and the code is the Ref `Ids.NewRef()` makes.
22. **`SessionOps` refuses a message that is not a command** with an error status of code 5001 and an error log row, as `ReminderOps` does. Row 16 of `docker/tests/test-production.sh` sent a string request to the stub and expected code 5003 from `SessionOps`; it now expects 5001 from `SessionOps` and keeps 5003 for `TriageAgent` (footprint extension, Rule 19).
23. **The mock's answers.** `GET /_mock/telegram/calls` answers `{"calls":[...]}`, and each call is `{seq, ts, method, params}` for every Bot API call that has a token, refused ones included (the 401 for an empty token and the 405 for a verb other than GET and POST are not calls). `POST /_mock/telegram/updates` takes a JSON list of update objects or `{"updates":[...]}` and always assigns `update_id` itself, counting from 1; `reset` also restarts the update and message counters. A queued reply of a method comes before the update queue of `getUpdates`. A long poll that the client hangs up on is logged with `rejected` `client-closed` and no status. The log entry has `tokenLength` after `keyLength`; a Bot API entry has the shape of a model entry, with `selectedBy` `telegram`, `queued`, `updates`, `empty` or `default`.
24. **`check_no_key`.** `live_key_count` (lib-live) counts `ANTHROPIC_API_KEY` and any `TELEGRAM_BOT_TOKEN` that is not exactly the dummy that `ci/compose.ci.yml` sets, and `check_no_key` and `test-compose-start.sh` both use it. `test-compose-file.sh`'s "no key variable" check allows exactly the two Telegram lines of the CI override, and "the judges' files name neither" is read as: no judge's file names `OCUTALON_TELEGRAM_API_BASE` or holds the dummy value (`.env.example` keeps its empty `TELEGRAM_BOT_TOKEN=` slot).
25. **Footprint extensions found by Rule 19.** Existing tests that pinned a changed shared surface were updated: `Test.Schedule.HeartbeatLogic` (four conditions), `Test.Bridge.CodeRules` (Decided 18), `Test.Demo.Guide`, `Test.Live.Status`, `Test.Web.Api` and `docker/tests/test-production.sh` (Decided 22). Two helper classes are new in `Test/Core`: `SessionOpsProbe` and `AnswersTelegramProbe`.
26. **Warm stacks and production jobs.** A warm run reloads classes, but a running production job keeps the class it started with. After a change to `SessionOps`, or to a class it calls, the tests that go through the production need `Ens.Director.EnableConfigItem("SessionOps", 0, 1)` and then `1` on the warm stack. A fresh stack starts with the new code and needs nothing.
27. **A failed `linked` entry after a drop.** The matrix orders a move's or a second chat's unlink entries before the `linked` entry, so the drops cannot wait for it. A failed `linked` entry therefore leaves the dropped chat unlinked, nothing linked and the code unused; the dropped chat has been told at the drop (`pairing.otherChatPaired`), so it is never left unpaired without a notice, and the same code pairs once the entry can be written. `Test.Core.SessionOps.TestPairAuditFailsAfterADrop` pins this.
28. **A negative `getUpdates` offset is a 400.** The Bot API reads a negative offset as "the last updates", which the mock does not model. Reading it as no offset would give a poller a false green, so the mock refuses it with a Bot API error (`rejected` `bad-offset`).
29. **`RecordChat` and a failed lookup.** A lookup that fails (SQLCODE below 0) is an error status and no row is made, because treating it as "no chat" would make a second row for a chat that has one.

**Ledger:**
- **DW-200:** addressed by Task C, the FromTelegram rows and the `AnswersTelegram`/`AnswersTelegramProduction` tests (Decided 6).
- **DW-231:** addressed in full.
  - The guide half was already done: Story 4.7 put `postGuideMarker` in `ApiClient` (`api-client.ts:51-53`), and the guide has no second client, so `web/src/app/guide/**` (contended) needs no edit.
  - The feed half is Task F (`breakFeed()`, `BreakFeedSent` moved, `break-feed-api.ts` deleted), pinned by `api-client-sources.test.mjs`.
  - U-84's condition is met before 1.0.0.
- **Declined:** none.

**Integration ACs:** the "Integration:" matrix rows and the Pairing, Notices, Direct-calls and Mock ACs.
- Real consumers in this story: Notify (`TelegramPaired` and the notice route), `/state`, `Guide.Compute`, the page-Unpair route and `Test.Contract.Mock`'s IRIS-side calls.
- No consumers in this story for `RecordChat`, `TakeReplySlot`, `FromTelegram` and `RecordTelegram`; the first consumer will be Story 12.2 for `RecordTelegram` and the pause, Story 12.4 for `RecordChat` and the pair command, Story 12.5 for `TakeReplySlot` and `/stop`, and Story 12.7 for `FromTelegram`. The fixture consumers are the G-group tests.
- No consumers in this story for the client methods and the QR library; the first consumer will be Story 12.3 (12.4 for `unpair()`). The fixtures are the source and pin tests and `pairing.spec.ts`.
- No consumers in this story for the mock's Bot API; the first consumer will be Story 12.1.
- No consumer in this story for `Unlink` outside SessionOps; the first will be Story 16.4.
- **Consumed-by:**
  - Story 12.1: the mock, the override, `RecordTelegram("off")`.
  - Story 12.2: `RecordTelegram`, `StatusMark.Record("telegramPaused")`.
  - Story 12.3: `pairingCode()`, the code route, `TelegramState`, the QR pin.
  - Story 12.4: `HashCode`, `RecordChat`, `Pair`, the `pairing` event, the guide.
  - Story 12.5: `TakeReplySlot`, `/stop`'s `Unpair`, the badCode outcomes.
  - Story 12.6: `TryConsume`, `Trace.Join`, `Delivery`, `Notify`.
  - Story 12.7: `FromTelegram`, `telegram-approval.spec.ts`.
  - Story 16.4: `Unlink`.
  - Story 16.9: the TryConsume refusal.
  - Story 25.3: `getFile`.
  - Story 30.2: the Core `Purge`.
- **Consumes:**
  - `Commands.Submit`/`CommandsIn` (Stories 0.6, 2.3);
  - `Live.Publish` (0.5);
  - `Bridge.Audit.Record` (0.4, 3.7);
  - `Approval.Answer` and `IsRef` (3.7);
  - AnswersIn/AnswerOps (6.2);
  - `Ownership` (2.2, 6.2);
  - the Notify rule (2.7);
  - `Delivery` (2.7);
  - `StatusMark.Record` (0.12);
  - `Allowance.TryConsume` (2.4);
  - `Trace.Join` (2.9);
  - the catalog keys (0.9);
  - `Included()` and `TelegramState` (2.8);
  - the mock (0.11);
  - `Test.Data.Fixture` and `Test.Bridge.AuditLog`.

**Extend, don't copy (Rule 2):**
- `HashCode` extends the SHA-256/base64url form of `Conversation.RetryItemId`, without truncation.
- `Pairing.Purge` mirrors `Digest.Data.Item.Purge`; `Install.Step.Core` mirrors `Install.Step.Digest`.
- `RecordTelegram` and `TelegramState` sit on `StatusMark.Record` and `Get`.
- SessionOps mirrors `ReminderOps` for dispatch, locks and publish, and reuses `SettingsOps`' audit-first shape and `WriteAudit` seam and `IncidentManager`'s `SendNotice` seam.
- `TelegramPaused` mirrors `HeartbeatStalled`.
- `FromTelegram` reuses `OnProcessInput` (one rule set) and `Live.Payload.Approval`'s dry-run parse.
- `PairingCode` and `Unpair` mirror `DismissIncident`.
- The mock branch reuses `entry`, `emit`, `build` and `send`. `withServer` moves into `helpers.mjs` rather than being copied.
- `check_no_key` and `test-compose-start.sh` share one lib-live function.
- The test classes mirror `AnswersIn`/`AnswersInProduction`, `DismissApi`, `SettingsOps` and `approval-sources.test.mjs`.

**Footprint extensions (Rule 11; report under `footprint_extensions:`):**
- **Outside the footprint, not contended:** `Live/Payload/Status.cls`, `web/src/app/feed/break-feed-box.ts` and `break-feed-api.ts` (deleted), `web/e2e/api/pairing.spec.ts`, `web/e2e/demo-path/telegram-{page,approval}.spec.ts`, the new `Test/Core/*` classes, and `Test/{Demo/Guide,Live/Status,Contract/Ac,Contract/Mock}.cls`.
- **New files in contended folders (standing precedent):** `Install/Step/Core.cls` (Epic 15's `Install/**`), `Test/Data/PairingRows.cls`, `Test/Web/PairingApi.cls`, `web/scripts/api-client-sources.test.mjs` and `qr-pin.test.mjs` (Epic 16's `web/scripts/**`).
- **One self-contained block appended at the end of a contended file:** `Data/Ownership.cls` (Epic 16 changed this file; a merge union at its end).
- **Contended, by the orchestrator's ruling of 2026-10-28T20:05:05Z (Task F5):** `web/package.json` (one `dependencies` line) and `web/package-lock.json` (the new entry and the root dependencies line).
- **Shared by entry:** `Web/Api.cls` (Epic 16 also edits `StateBody`, next to the Telegram block; a plain union), `api-client.ts`, `api-types.ts`, `Test/Web/Api.cls`, `Test/Data/Tables.cls` and `Test/Core/ProductionItems.cls`.

**Orchestrator ruling (2026-10-28T20:05:05Z, category decide, policy 6df0676; logged in the parallel cycle log):** option (a), Task F5 may edit the contended `web/package.json` and `web/package-lock.json`. Why: Epic 16 is waiting, not live; its branch changed one `scripts` line of `package.json` and never the lockfile, and no other open epic touches either file, so the edit is at worst a plain union at Epic 16's integrate-forward. Moving the pin to an Epic 16 story (an AC move across epics) and waiting for Epic 16 (16.4 waits on this story's unlink) were rejected. Conditions, binding on the implement stage:
1. `web/package.json`: exactly one added line in `dependencies`, `"qrcode-generator": "2.0.4"` (exact pin, no `^` or `~`). No other line changes: no script edits, no reformatting, no field reordering.
2. `web/package-lock.json`: produced by the project's own npm (the same major CI uses). Its diff holds only the new `node_modules/qrcode-generator` entry and the root package's dependencies line; if anything else moves (lockfileVersion, other packages' resolved or integrity fields, a dedupe), revert it and redo the step. `npm --prefix web ci` must pass on the result.
3. The dependency is a veto item (category 6): ruled by the lead, inbox U-138; reversal: remove the dependency and its Stack row, and render the QR code another way.
4. The spine's Stack row is written (the lead, at this gate); `web/package.json` and `web/package-lock.json` are footprint extensions.

The other contention points are accepted as planned: `Data/Ownership.cls` gets one self-contained `ApprovalKnown(ref)` block appended at the end of the file (Epic 16's hunks there are mid-file); the new files in contended folders are `Install/Step/Core.cls`, `Test/Data/PairingRows.cls`, `Test/Web/PairingApi.cls`, `web/scripts/api-client-sources.test.mjs` and `web/scripts/qr-pin.test.mjs`; nothing under `web/src/app/guide/**` changes. All are footprint extensions.

**Spine rows (Rule 20), written by the lead at this gate:**
- the Stack row: `| QR-code library (Story 10.3; drawn in the browser for the Telegram pairing link, AD-14) | qrcode-generator 2.0.4 (MIT), no runtime dependencies |`;
- the REST row: `409 not_available` (`POST /pairing/code`), the code's 200 body, and `DELETE /pairing` → 200 `{"result":"done"}` (veto U-137);
- the Status marks row: `telegramState` holds JSON `{state, botUserName}`, written only by `StatusMark.RecordTelegram` (veto U-137).

**Veto-window rulings (the lead, at this gate):**
- U-137: (3) the six `Pairing` columns, two indexes and the `telegramState` mark; (5) the two 409 messages and the DELETE body, unreachable in 0.1.0 because the routes answer 404 first; (1) the CI-only dummy bot token and the `check_no_key` rule (Decided 12). Kept; reversal: a fix story before 0.1.1 changes the named part.
- U-138: (6) the new dependency of F5. Kept; reversal: remove the dependency and its Stack row, and render the QR code another way.

**Story 16.3 and 16.9.** Story 16.3 has not merged, so per the AC nothing is turned on: Story 16.3 will check the real row. Story 16.9 owns `TryConsume` refusals, and this story only proves the allowed path with channel `telegram`.

**Rule 3:** the user-facing surfaces are the REST routes (`pairing.spec.ts` over real HTTP) and the CLI mock (`telegram.test.mjs` over real HTTP to the server). The page shows nothing new in 0.1.0.

## Verification

Lane C, implement stage. Every `ci/iris.sh` and `ci/warm.sh` call sets:
- `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c"`
- `OCUTALON_TEST_WEB_PORT=52803`
- `OCUTALON_LOCK_OWNER='epic=10 stage=implement'`
- `OCUTALON_RUN_TAG=e10s3i` for a fresh stack, or `e10s3iw` for the warm stack (with `OCUTALON_WARM=1` on that call only)

Each call ends with `ci/iris.sh teardown`, or `ci/warm.sh down` for the warm stack, with the same tag. At most one fresh throwaway runs at a time. Every call passes `timeout: 600000`, and there is one test class per call. Before loading anything there, check the dev slot `ocutalon-slot-c` (MCP `server: ocutalon-slot-c`, `namespace: OCUTALON`) with `iris_server_info`. Never use another instance.

**Commands:**
- (once) Task 0: `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e10s3iw ci/iris.sh class OcuTalon.Test.Core.ZzTelegramQueueProbe` (after `ci/warm.sh up`), then delete the class file. The next warm run reports it deleted. Expected: the four facts logged, and `GetCount("TelegramOut")` back to its starting value.
- (loop) `ci/warm.sh up`, once. After any change under `ci/mock/` or to `ci/compose.ci.yml`, run `ci/warm.sh down` then `up`, because a warm run refuses those changes. Expected: the stack is ready.
- (loop) `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e10s3iw ci/iris.sh class <Class>`, one per call, for each of these. Expected: `CLASS … passed`.
  - `OcuTalon.Test.Data.PairingRows`, `OcuTalon.Test.Core.SessionOps`, `OcuTalon.Test.Core.SessionOpsProduction`
  - `OcuTalon.Test.Core.AnswersTelegram`, `OcuTalon.Test.Core.AnswersTelegramProduction`, `OcuTalon.Test.Core.AnswersInProduction`, `OcuTalon.Test.Core.TelegramCalls`
  - `OcuTalon.Test.Web.PairingApi`, `OcuTalon.Test.Web.Api`
  - `OcuTalon.Test.Live.Status`, `OcuTalon.Test.Core.StatusMonitor`, `OcuTalon.Test.Demo.Guide`
  - `OcuTalon.Test.Data.Tables`, `OcuTalon.Test.Core.ProductionItems`, `OcuTalon.Test.Core.CommandsInProduction`, `OcuTalon.Test.Core.Routing`
  - `OcuTalon.Test.Contract.Ac`, `OcuTalon.Test.Contract.Mock`
  - `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Install.Production`
- (loop) `bash docker/tests/test-mock.sh`. Expected: every node test passes.
- (loop) `npm --prefix web test` and `npm --prefix web run lint`. Expected: exit 0.
- (loop) `bash docker/tests/test-compose-file.sh`, `bash docker/tests/test-boundaries.sh` and `bash docker/tests/test-ci-config.sh`. Expected: exit 0.
- (loop) `uvx --from shellcheck-py==0.9.0.6 shellcheck docker/tests/lib-live.sh docker/tests/test-compose-start.sh docker/tests/test-compose-file.sh`, a dev tool. Expected: no new findings.
- (once) `ci/warm.sh down`. Expected: the warm tag is gone.
- (once) `bash docker/tests/test-web-build.sh`. Expected: the build passes, including `payloads.mjs --check` and `catalog.mjs --check`.
- (once) `bash ci/checks.sh`. Expected: `checks: all scripts passed`.
- (once) With tag `e10s3i`, one per call: `ci/iris.sh build` (this story changes `web/`), `ci/iris.sh live sign-in --part 1/2`, then `--part 2/2` (`OCUTALON_LIVE_DEADLINE=900`), `ci/iris.sh live demo-path` and `ci/iris.sh live compose-start`, then `ci/iris.sh teardown`. Expected:
  - every unit passes;
  - demo-path's summary shows the two Telegram files as skipped for Story 12.4 and 12.7, and nothing fails;
  - compose-start's key line passes with the dummy token.
- (once) `ci/iris.sh shard lane-b --part 1/3`, `2/3` and `3/3`, fresh, one per call, then teardown. Expected: every class passes.

Shared surfaces:
- `Test.Data.Tables`: the Pairing contract.
- `Test.Core.ProductionItems`: the SessionOps row's `stub` value.
- `Test.Core.CommandsInProduction`: the EndSession stub row stays.
- `Test.Contract.Ac`: the signature list.
- `Live.Payload.Status.Computed`: now 4 conditions. Any test that counts them is updated.
- `/state`'s `telegram` values (keys unchanged; `api.spec.ts:140` expects the defaults).
- `Test.Web.Api.TestPairing`.
- `Test.Demo.Guide`'s Telegram rows.
- `Install.Registry.Areas()`, which gains the Core area.
- The mock's log entry keys (row 14) and scenario validation.
- `ci/compose.ci.yml`'s exact text.
- `check_no_key` and the compose-start key count.
- `api-types.ts` and `api-client.ts`.
- The demo-path summary's per-step counts: page and approval become "partly skipped".

Every test added or changed passes on a fresh environment, in either order. Known flake classes: DW-349 (a seeded check row with no `NextDueAt`) and DW-306 (`test-production.sh` row 21). Neither involves this story's tests.

Task 0 measurement (warm stack `e10s3iw`, Lane C, the temporary probe `OcuTalon.Test.Core.ZzTelegramQueueProbe`, deleted afterwards): with `Included()` = 1, one kind-`pairing` Notification with a fixture ChatRef sent to `Notify` produced
- one `Notify`->`TelegramOut` header within 10 s, with `Status` 2 (Queued) and `ErrorStatus` OK;
- `Ens.Queue.GetCount("TelegramOut")` "" (empty queue) before and 1 after;
- no event-log row of Type 2 or 6 (and no warning row, Type 3).

`Ens.Queue:EnumerateItem("TelegramOut")` found the item (priority 6, index 1) and `AbortItem` removed it with status OK. The count then read 0 and the header's `Status` read 7 (Aborted). So `Test.Web.PairingApi`'s paired-DELETE case aborts the queued item (through `EnumerateItem` and `AbortItem`) and `Included()` stays 1 for that case; no error row is written, so no change to the plan.

Mutations (Rule 19; the implement stage writes one `mutation:` line per AC). Examples:
- compare `CodeHash` without the used check → the used-code row is red;
- store the code under `SessionRef` → the snapshot `paired` row is red;
- pass `chatRef` as the sessionRef in `FromTelegram` → the DW-200 argument row is red;
- drop the `Included()` check in `Pairing()` → the 404 row is red;
- return `[]` at once from `getUpdates` → the long-poll row is red;
- log the raw path → the token-redaction row is red;
- skip `TelegramPaused` in `Computed` → the `Status` row is red;
- keep `break-feed-api.ts` → `api-client-sources` is red.

Demonstrated on the warm stack (apply, observe red, revert, `git diff` and `git status` byte-identical to before):
- mutation: `Pair` skips the used-code check (`If code.CodeUsedAt '= "" {` -> `If 0 {`) -> `Test.Core.SessionOps` `TestPairUsedCode` and `TestPairRepeatChangesNothing` red (AC Pairing);
- mutation: `StoreCode` also sets the code row's `SessionRef` (the code stored under the session's pairing) -> `Test.Core.SessionOpsProduction` `TestPairAndStopThroughTheProduction` and `TestPageUnpairSendsTheNotice` red (AC Pairing's consumers);
- mutation: `Pair` drops the notice key of the dropped second chat (`"pairing.otherChatPaired"` -> `""`) -> `Test.Core.SessionOps` `TestPairSecondChat` and `TestNotifyReadsTheNotice` red (AC Notices to a dropped chat);
- mutation: `Unlink` skips its channel check -> `Test.Core.SessionOps` `TestUnlinkApi` red (AC The unlink API);
- mutation: `TakeReplySlot` ignores its 60 seconds (`If 1 {`) -> `Test.Data.PairingRows` `TestTakeReplySlot` red (AC Pairing rows);
- mutation: the code route ignores the Telegram state (`If 0 Quit ..Fail(409, ...)`) -> `Test.Web.PairingApi` `TestCodeRouteNotAvailable` red (AC The code route);
- mutation: the unpair route answers 500 for `not_paired` -> `Test.Web.PairingApi` `TestPageUnpairNothingPaired` and `TestBodyNamesNoSession` red (AC The unpair route);
- mutation: `Computed` ignores the telegram reading (`..TelegramPaused("")`) -> `Test.Live.Status` `TestComputedTelegramPaused` and `TestTelegramPausedDefaultRead` red (AC Status);
- mutation: `FromTelegram` hands the ChatRef as the session (`answer.SessionRef = chatRef`) -> `Test.Core.AnswersTelegram` `TestApprovedAndRejected`, `TestOtherAnswers` and `TestToolCallHasNoSlots` red (AC AnswersIn's Telegram entry, DW-200);
- mutation: `Delivery.FindByApproval` answers only the message-id part of the id -> `Test.Core.TelegramCalls` `TestDeliveryIsFoundByItsOwner` red (AC Direct calls);
- mutation: the mock logs the raw Bot API path (`path: pathname`) -> `ci/mock/test/telegram.test.mjs` red in three tests, the token-in-the-log ones (AC The mock);
- mutation: `getUpdates` answers at once (`while (false)`) -> `ci/mock/test/telegram.test.mjs` "with none queued getUpdates waits" red (AC The mock);
- mutation: `feed/break-feed-api.ts` kept -> `web/scripts/api-client-sources.test.mjs` three tests red (AC Web);
- mutation: `Pairing()` skips the `Included()` check -> `Test.Web.Api` `TestPairing` red (AC The switch).

Added in the review pass (same method, each restored and byte-identical afterwards):
- mutation: `Unlink` also sends a notice for the reason `stop` -> `Test.Core.SessionOpsProduction` `TestPairAndStopThroughTheProduction` red at "and no Notification was sent" (the absence check reads the headers newer than a mark, not a session's trace; AC Notices to a dropped chat);
- mutation: `RecordTelegram` writes the mark before it validates -> `Test.Data.PairingRows` `TestRecordTelegram` red at "the refused calls left the mark as it was" (AC Status);
- mutation: `CHANNELS` without `web_admin:web` -> `Test.Core.SessionOps` `TestUnpairOriginsAuditTheirChannel` red (AC The unpair route);
- mutation: `Ownership.ApprovalKnown` without the exact Ref compare -> `Test.Core.AnswersTelegram` `TestNotVisibleAndUnknown` red (AC AnswersIn's Telegram entry);
- mutation: `Pairing.Purge` cutoff one day older (`- daysToKeep - 1`) -> `Test.Data.PairingRows` `TestPurge` red at "a row an hour outside the 30 days is deleted" (AC Pairing rows);
- mutation: the unpair route answers 404 instead of 500 for an unreadable session -> `Test.Web.PairingApi` `TestNoSessionIs500` red (AC The unpair route);
- mutation: the mock reads a negative `getUpdates` offset as none -> `ci/mock/test/telegram.test.mjs` "an offset confirms the earlier ones" red (AC The mock);
- mutation: the mock puts the token in its 405 body -> `ci/mock/test/telegram.test.mjs` "mock refusals" red (AC The mock);
- mutation: `web/package.json` pins `^2.0.4` -> `web/scripts/qr-pin.test.mjs` "package.json pins qrcode-generator at exactly 2.0.4" red (AC Web);
- mutation: `live_key_count` ignores `TELEGRAM_BOT_TOKEN` -> `docker/tests/test-lib-live.sh` six `live_key_count` rows red (AC The mock: the start-with-no-key checks still hold).
- Not mutated: `web/e2e/api/pairing.spec.ts`, which runs in `live:sign-in` (the `(once)` lines); `Test.Web.PairingApi` pins the same code-route and unpair rows by the mutations above.

QA stage (gap audit of every Tasks & Acceptance item and every I/O matrix row against its pinning test; Lane C warm stack `e10s3qw` for the class runs, then three fresh `shard lane-b --part k/3` runs). Tests added or changed (QA):
- `src/ocutalon/cls/OcuTalon/Test/Core/SessionOps.cls` (QA): `TestPairSameChatNewCode`, `TestPairMoveOntoASessionWithAChat`, `TestPairUsedCodeAfterItsExpiry`, `TestUnlinkSignature`; a "code that expires at this second" row in `TestPairExpiredCode`; a SeenAt row in `TestUnpairStop`.
- `src/ocutalon/cls/OcuTalon/Test/Data/PairingRows.cls` (QA): SeenAt rows in `TestStoreCodeReplaces`.
- `src/ocutalon/cls/OcuTalon/Test/Core/AnswersTelegramProduction.cls` (QA): `TestAnswerFollowsThePairingSessionOpsWrites` and its helpers `NewChat`, `Code` and `Submit`.
- `web/scripts/api-client-sources.test.mjs` (QA): the two Telegram parts of the demo path (the matrix row "Demo-path files").

Mutations (Rule 19, QA; one per AC at least; each applied, red observed, reverted from a backup in the stage's scratchpad, `git diff`, `git status --short` and `git diff --stat` byte-identical, then the class green again on the same stack):
- mutation: `Pair` drops the second-chat guard (`If otherId '= chatId {` -> `If 1 {`) -> `Test.Core.SessionOps` `TestPairSameChatNewCode` red (AC Pairing);
- mutation: the dropped second chat's unlink reason `other_chat` -> `moved` -> `Test.Core.SessionOps` `TestPairMoveOntoASessionWithAChat` and `TestPairSecondChat` red (AC Pairing);
- mutation: the expiry compare `expires <= now` -> `expires < now` -> `Test.Core.SessionOps` `TestPairExpiredCode` red at "a code that expires at this second is expired too" (AC Pairing);
- mutation: the used check is skipped for an expired code (`If code.CodeUsedAt '= "" {` -> `If (code.CodeUsedAt '= "") && (code.CodeExpiresAt ] now) {`) -> `Test.Core.SessionOps` `TestPairUsedCodeAfterItsExpiry` red (AC Pairing);
- mutation: `Guide.TelegramState()` quits `"off"` -> `Test.Core.SessionOpsProduction` `TestPairAndStopThroughTheProduction` red at the two guide rows (AC Pairing's consumers);
- mutation: the page Unpair passes no notice key (`"pairing.unpairedFromPage"` -> `""`) -> `Test.Core.SessionOps` `TestPageUnpair` and `TestUnlinkStandsWhenTheSideEffectsFail` red (AC Notices to a dropped chat);
- mutation: `Unlink` loses the default of `noticeKey` -> `Test.Core.SessionOps` `TestUnlinkSignature` red (AC The unlink API);
- mutation: `StoreCode` no longer sets `SeenAt` -> `Test.Data.PairingRows` `TestStoreCodeReplaces` red at three rows; `Unlink` no longer touches `SeenAt` -> `Test.Core.SessionOps` `TestUnpairStop` red (AC Pairing rows);
- mutation: the code route stores the code instead of its hash (`StoreCode(sessionRef, code, ...)`) -> `Test.Web.PairingApi` `TestCodeRoute` red (AC The code route);
- mutation: the unpair route submits with origin `telegram` instead of `web_user` -> `Test.Web.PairingApi` `TestPageUnpair` and `TestBodyNamesNoSession` red (AC The unpair route);
- mutation: `PauseHolds` reads `until >= now` -> `Test.Live.Status` `TestComputedTelegramPaused` red at the pause that ends at `now` (AC Status);
- mutation: `FromTelegram` answers on channel `web` -> `Test.Core.AnswersTelegram` `TestApprovedAndRejected` red; and `Unlink` keeps the chat row's `SessionRef` (SessionOps item restarted, Decided 26) -> `Test.Core.AnswersTelegramProduction` `TestAnswerFollowsThePairingSessionOpsWrites` red at six rows (AC AnswersIn's Telegram entry);
- mutation: `Delivery.FindByApproval` ignores its channel argument -> `Test.Core.TelegramCalls` `TestDeliveryIsFoundByItsOwner` red (AC Direct calls);
- mutation: the mock's `getUpdates` stops dropping the confirmed updates (`if (offset !== null)` -> `if (false)`) -> `ci/mock/test/telegram.test.mjs` two tests red; and the CI dummy bot token made key-shaped -> `docker/tests/test-compose-file.sh` four checks red (AC The mock);
- mutation: `ApiClient.unpair()` posts instead of deleting -> `web/scripts/api-client-sources.test.mjs` "unpair() is a DELETE of /pairing" red; and the story id of `telegram-page.spec.ts` `'12.4'` -> `'12.5'` -> the same file's "telegram-page.spec.ts declares one not-built part" red (AC Web);
- mutation: `Pairing()` skips the `Included()` check for DELETE -> `Test.Web.PairingApi` `TestSwitchOffAnswers404` red at five rows (AC The switch).
- mutations_demonstrated=20. Not mutated: `web/e2e/api/pairing.spec.ts` (unchanged by QA; its rows are the code route's and unpair route's, which `Test.Web.PairingApi` mutates above).

QA runs: the warm stack ran each changed class green; fresh `shard lane-b --part 1/3`, `2/3` and `3/3` passed (26, 26 and 26 classes), `npm --prefix web test` passed (1002 tests), `docker/tests/test-compose-file.sh` and `test-lib-live.sh` passed. Not run by QA: `live sign-in` and `live demo-path` (no spec or web source changed), the reverse-order fresh check (the lead's, Rule 19).

Code review (tests added or changed by the review's patches; Lane C, warm stack `e10s3rw`, fresh tag `e10s3r`; each mutation applied from a backup in the stage's scratchpad, red observed, restored, `git status --short`, `git diff --stat` and `git diff` byte-identical, then green again):
- `ci/mock/test/telegram.test.mjs` (review): "a reply queued for getUpdates while a long poll waits answers that poll at once". mutation: `queueReplies` no longer calls `wakeWaiters()` -> that test red (the poll answered after its 30 s timeout) (AC The mock);
- `src/ocutalon/cls/OcuTalon/Test/Web/Api.cls` (review): `TestPairing` asserts that the 409 leaves the CSP session unattached (Decided 21). mutation: `PairingCode` reads `Ownership.SessionRef` before the two checks -> `Test.Web.Api` `TestPairing` red at "the 409 read no session" (AC The code route);
- `src/ocutalon/cls/OcuTalon/Test/Web/PairingApi.cls` (review): `TestBodyNamesNoSession` removes its queued `TelegramOut` item and checks the count. mutation: the test's `AbortQueued` call removed -> `Test.Web.PairingApi` `TestBodyNamesNoSession` red at "the item the page notice queued for TelegramOut is removed" (Boundaries: nothing is left in TelegramOut's queue);
- not mutated (hermeticity or readiness fixes that change no assertion): `Test.Schedule.HeartbeatLogic` (a telegram reading of "" in every `Computed` call), `Test.Web.Api.TestStateSections` (both marks cleared first and put back), `Test.Core.SessionOpsProduction.TestPageUnpairSendsTheNotice` (`Observe.WaitProcessed` before the absence check), `Test.Contract.Ac` (the `Pairing.Chat` signature entry), `web/e2e/api/pairing.spec.ts` (the clean-up hash taken before the assertions).
- Runs: `bash docker/tests/test-mock.sh` (117 tests), `npm --prefix web test` (1002), `npm --prefix web run lint`, `docker/tests/test-class-rules.sh` and `bash ci/checks.sh` pass; on the warm stack `Test.Web.PairingApi`, `Test.Core.SessionOpsProduction`, `Test.Web.Api`, `Test.Schedule.HeartbeatLogic`, `Test.Contract.Ac` and `Test.Contract.Mock` pass; fresh, after `ci/iris.sh build`, `live sign-in --part 1/2` passes (127 tests, `api/pairing.spec.ts` included); both tags torn down.

## Auto Run Result

Status: done
Blocking condition: none

**Summary.** The session side of Telegram is built and stays off (`Included()` and `Channel.Telegram.**` untouched). `SessionOps` pairs, unpairs and unlinks (public `Unlink`, the API Story 16.4 calls) with audit entries, `pairing` events and notices to a dropped chat. `Data.Pairing` has its code rows, `HashCode`, `RecordChat`, `TakeReplySlot`, `StoreCode`, `Chat`, `ForCode` and `Purge`, and `Install.Step.Core` declares the purge. `AnswersIn.FromTelegram` answers a closed set of codes from the chat's live pairing only. `StatusMark.RecordTelegram`/`TelegramState`, the `telegramPaused` condition and `/state`'s Telegram block, the two pairing routes and the guide's Telegram state read the new marks. The CI mock serves the Bot API (five methods, queues, scenarios, token masked); the CI override carries the endpoint and the dummy token, and the no-key checks accept only that dummy. In `web/`: `pairingCode()`, `unpair()` and `breakFeed()` in `ApiClient` (DW-231 closed: `break-feed-api.ts` deleted), the two skipped `telegram-*.spec.ts` files, and `qrcode-generator` 2.0.4 pinned (Task F5, one `package.json` line and the new lockfile entry only; `npm ci` passes).

**Files changed.**
- Data and install: `Data/Pairing.cls` (columns, indexes, methods), `Data/StatusMark.cls`, `Data/Ownership.cls` (one appended `ApprovalKnown` block), `Install/Step/Core.cls` (new).
- Core and web layer: `Core/SessionOps.cls` (the stub replaced), `Core/AnswersIn.cls` (`FromTelegram`, `Deliver`), `Live/Payload/Status.cls` (`telegramPaused`), `Web/Api.cls` (code route, unpair route, `/state` block), `Demo/Guide.cls`.
- Mock and CI: `ci/mock/mock.mjs`, `ci/mock/scenarios.mjs`, the mock's `helpers.mjs`, `server.test.mjs`, `scenarios.test.mjs` and the new `telegram.test.mjs`; `ci/compose.ci.yml`; `docker/tests/lib-live.sh`, `test-compose-start.sh`, `test-compose-file.sh`, `test-lib-live.sh` and `test-production.sh` (row 16).
- Web: `api-client.ts`, `api-types.ts`, `feed/break-feed-box.ts`, `feed/break-feed-api.ts` (deleted), `package.json`, `package-lock.json`, `e2e/api/pairing.spec.ts`, `e2e/demo-path/telegram-{page,approval}.spec.ts`, `scripts/api-client-sources.test.mjs`, `scripts/qr-pin.test.mjs`.
- IRIS tests (new): `Test/Data/PairingRows`, `Test/Core/{SessionOps,SessionOpsProbe,SessionOpsProduction,AnswersTelegram,AnswersTelegramProbe,AnswersTelegramProduction,TelegramCalls}`, `Test/Web/PairingApi`; changed: `Test/Contract/{Ac,Mock}`, `Test/Core/{ProductionItems,StatusMonitor}`, `Test/Data/Tables`, `Test/Demo/Guide`, `Test/Live/Status`, `Test/Web/Api`, `Test/Schedule/HeartbeatLogic`, `Test/Bridge/CodeRules`.

**Review findings.** 46 findings from the four layers: high 0, medium 2, low 32, false 10, maybe-false 2. Patches applied (test-side or one-line, 21 rows): the two mediums (the vacuous "no Notification" absence checks, now by header id with a positive control; the three untested channel origins), the `RecordTelegram` mark-unchanged check, `TestNoSessionIs500`, `ApprovalKnown` exactness, `TestPurge` boundary rows, the pin test for a failed `linked` entry after a drop (Decided 27), the mock's negative-offset 400 and its `!res.destroyed` guard, the mock tests' readiness poll and non-vacuous token loop, `RecordChat`'s failed-lookup error, two comment fixes, the `pairing.spec.ts` clean-up, an unused property. One item deferred (the dummy bot token and a no-token CI start, for Story 12.1, medium unverified). Rejected with a recorded reason: 24 rows (false 10, maybe-false 1, low 13, with a reopen probe where one applies; some repeat a patched or rejected root).

**Follow-up review recommended: false.** Two mediums were patched, but both are test-only changes with a demonstrated red-then-green mutation (the stop-notice mutation; the dropped `web_admin` mutation), so no unverified risk can be named.

**Verification.** Warm stack `e10s3iw` (one class per call): all 20 `(loop)` classes pass, plus `Test.Bridge.CodeRules`; `test-mock.sh` 116 tests, `npm --prefix web test` 1000 tests, `npm --prefix web run lint`, `test-compose-file.sh`, `test-boundaries.sh`, `test-ci-config.sh`, `test-class-rules.sh`, `test-lib-live.sh` and shellcheck (68 findings before and after, the same codes) pass. Once, after the last patch: `ci/warm.sh down`; `test-web-build.sh` and `ci/checks.sh` pass; on fresh stack tag `e10s3i`: `ci/iris.sh build`, `live sign-in` 1/2 (127 tests, includes `pairing.spec.ts`) and 2/2 (96), `live demo-path` (12 passed, 9 skipped, summary names Story 12.4 and 12.7, floor 7 of 7), `live compose-start` (key line passes with the dummy), and `shard lane-b` 1/3, 2/3 and 3/3 (78 classes passed); teardown done. Task 0 (queue measurement) and 24 mutations (14 by the handoff, 10 in review) are recorded under `## Verification`. `ProductionItems` is a data class with no runnable tests, so the loop list's entry for it is covered by `Install.Production` and the lane-b shard.

**Residual risks.** (1) `web/e2e/api/pairing.spec.ts` ran once green; its `finally` clean-up on a failed assertion was not exercised. (2) Untested error branches, all rejected with a reopen probe: `Link`'s rollback, `SessionOps`' catch, the lock-timeout paths of `TakeReplySlot` and `RecordChat`, and the unpair route's `failed` outcome to 500. (3) A running production job keeps the class it started with, so a warm stack needs `Ens.Director.EnableConfigItem` off and on after a `SessionOps` change (Decided 26); a fresh stack is unaffected. (4) The deferred item above.
