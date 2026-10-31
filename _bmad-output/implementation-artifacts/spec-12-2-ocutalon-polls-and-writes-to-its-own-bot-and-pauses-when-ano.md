---
title: 'Story 12.2: OcuTalon polls and writes to its own bot, and pauses when another process polls it'
type: 'feature'
created: '2026-10-30'
status: 'done'
baseline_revision: 'ac6c8021785b8cb7533a2b7d49faaa714f787122'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md (read only AD-3, AD-4, AD-5, AD-12, AD-14, AD-18, AD-19, AD-22, AD-23, AD-29, AD-32 and AD-33)'
warnings: ['oversized', 'multiple-goals']
deferred:
  - summary: >-
      Pairing.RecordChat(chatId, "") overwrites a known chat's DisplayName with an empty string, so TelegramIn's call for every private update would erase a name that Story 12.4 stores.
    evidence: |-
      Data/Pairing.cls RecordChat sets row.DisplayName = name unconditionally. This story's spec fixes the call as RecordChat(chatId, ""), and no story stores a name yet, so nothing is lost today. Pairing.cls is contended (Epic 11).
    location: >-
      src/ocutalon/cls/OcuTalon/Data/Pairing.cls RecordChat; src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls HandleUpdate
    severity: medium
---

<intent-contract>

## Intent

**Problem:** `TelegramIn` and `TelegramOut` are still stubs. Nothing learns the bot's name, reads updates, sends to a chat, or pauses when another process polls the same token. There is no Telegram API base host setting and no client SSL configuration, so even a real token could not reach the public API.

**Approach:**
- Build `TelegramIn` as a short long poller (5 seconds per `getUpdates`). It records the Telegram state, keeps its offset in Story 12.1's node, processes only private-chat messages and private-chat button presses (in this story that means recording the chat), and pauses for 5 minutes on a 409 through the `telegramPaused` mark.
- Build `TelegramOut`'s sending: plain text, split at 4,096 characters, and a retry after a 429, for an `Outbound` or `Notification` that names a chat.
- Both items share one new Bot API client. It uses `%Net.HttpRequest` and reads the token from the environment on every call.
- The Telegram step writes the API base host setting from `OCUTALON_TELEGRAM_API_BASE` at every start. The SSL step creates the verifying client SSL configuration.
- This spec covers the server side of every Given block. The card's paused state, the banner seen in the browser, and the page's own token search are proposed as a sibling story (Design Notes, "Proposed split").

## Boundaries & Constraints

**Always:**
- The token is read only with `$SYSTEM.Util.GetEnviron("TELEGRAM_BOT_TOKEN")`, inside the client, on each call. It is never kept in a property, setting, row, global, message, trace entry, audit entry, live event, `%Status` text or log line (AD-14, AD-19, NFR-11).
- **The client's request object:**
  - It builds a new `%Net.HttpRequest` for every call, because a reused one sends the previous URL as `Referer`.
  - It sets `FollowRedirect = 0`.
  - Every error text it returns or logs is a fixed phrase plus the method, the HTTP status and Telegram's `description`. It never includes the URL or the path.
  - Every text passes through `Safe`. It replaces the exact token, because `Bridge.Redact` does not recognise the CI dummy, and then applies `Bridge.Redact.Text`.
- **The offset node:** `TelegramIn`'s offset lives only in `$$$EnsStaticAppData("TelegramIn", "offset")`, Story 12.1's node.
  - It is read before every `getUpdates` and written after each handled update. No node means no offset.
  - An update whose `update_id` is below the offset is skipped (DW-422).
- **The pause mark:** `Record("telegramPaused", until)` is the one truth of the pause.
  - Its value is a UTC ISO time from `Data.Time.AddSeconds`.
  - `TelegramIn` reads it before every poll, so a restart honours it.
  - A successful `getUpdates` deletes it with `Record(mark, "")`.
- **The Telegram state:** `TelegramIn` records it only through `StatusMark.RecordTelegram`.
  - `OnInit` records `off`, because the item is not polling yet.
  - `on`, with `getMe`'s `username`, is recorded before the first `getUpdates`.
  - `rejected` is recorded when `getMe` answers 401 or 404.
  - `OnTearDown` records `off`, unless the state it recorded is `rejected`.
- **No blocking work at start:** `OnInit` makes no network call. `OnProcessInput` always returns `$$$OK`, logs failures as warnings (`$$$LOGWARNING`, never an error row), and makes at most one Bot API call per run.
- **Every long poll ends inside 10 seconds:** `getUpdates` `timeout` 5, HTTP read timeout 8. That is inside the platform's 10-second item stop (`UpdateTimeout`) and far inside the compose file's 60-second stop grace.
- **Live tests clean up after themselves.** A test that enables `TelegramIn` or `TelegramOut`:
  - stops the item before it returns;
  - restores the item's `Enabled` row, both Telegram marks and its fixture `Pairing` rows;
  - resets the mock's Bot API side through `Test.Channel.BotApi.Reset`.

  These tests run in throwaways and in CI only, against the CI mock and its dummy token.
- Rule 14 applies: ASCII escapes in code, and comments state the contract.

**Never:**
- No change to:
  - `Included()`'s body;
  - Lane B's mock code or its tests (`ci/mock/*.mjs`, `ci/mock/test/**`);
  - `Test/Contract/Mock.cls`;
  - `Install/Registry.cls` or its order;
  - `ci/compose.ci.yml`, `README.md` or `web/**`.
- No CI start enables a Telegram item. The step's switch is unchanged.
- No real bot, no call to `api.telegram.org`, no real token, no read of `.env`.
- No `Delivery` rows, no routing by `SessionRef`, no `answerCallbackQuery`, no `editMessageText`, no pairing, no replies to chats and no turns (Stories 12.4 to 12.7).
- No chat id or display name in any log line, status text or message. The update's `from` name is not stored.
- No new live unit and no new CI start.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Start (Integration: `/state`, 12.3's input) | Token set; mark `rejected` before; no kept offset; `TelegramIn` enabled | The mark becomes `on`, name `ocutalon_ci_bot`. `/calls` shows `getMe`, then `getUpdates` with `timeout` 5, `allowed_updates` `["message","callback_query"]` and no `offset`. `Web.Api.StateBody` gives `telegram.state` `on` and `botUserName` `ocutalon_ci_bot`. | — |
| Stop during a long poll | Running, with an open `getUpdates` and nothing queued | `EnableConfigItem("TelegramIn", 0)` returns OK within 10 s. No `TelegramIn` job remains. The mark is `off`. | — |
| Offset node (DW-422) | `BotApi.SetOffset(3)` before the start; then three updates (ids 1 to 3) queued through `/updates` | The first `getUpdates` carries `offset` 3. Only id 3 is handled. `BotApi.Offset()` becomes 4, and the next `getUpdates` carries `offset` 4. | — |
| Restart loses nothing | Update A handled; item stopped; update B queued while stopped; item started | B is handled once after the start. A is not handled again. `Offset()` advances past B. | — |
| Already handled id | `Offset()` 2; scripted `telegram-private-update` (id 1, chat 7001) | Skipped: no `Pairing` row for 7001 appears, and `Offset()` stays 2. | — |
| Private only (FR-19) | One `/updates` batch: a group message, a `channel_post`, a press from a group chat, a private message, and a press from a private chat | The two private chats get a `Pairing` row each, through `RecordChat(chatId, "")`, with no session and no name. The three others get no row. No `sendMessage` call, no message header from `TelegramIn`, and no audit entry since the mark. `Offset()` is past all five. | A `RecordChat` failure logs a warning with no id, and the update is still confirmed. |
| Rejected token (FR-21) | New scenario `telegram-getme-rejected` (401) queued before the start | The mark is `rejected` with an empty name. Within 3 s the only call is `getMe`. One warning says that Telegram rejected the token and stays off until the next start, and no log row holds the token. `StateBody` gives `rejected`. After a stop the mark is still `rejected`. | Other failures (5xx, no connection, not JSON) are not a rejection: a warning, and another try after 5 s. |
| `getUpdates` busy | New scenario `telegram-updates-busy` (429, `retry_after` 3), queued while a poll is open | The next `getUpdates` arrives at least 3 s after the 429. One warning, with no token. | With no `retry_after`, the wait is 5 s. |
| 409 pause (FR-22) | `telegram-conflict` queued while a poll is open | Within 2 s the `telegramPaused` mark is a UTC time 300 s ahead (within 5 s). No `getUpdates` follows in the next 4 s. A warning names the pause and its time, without the token. `StateBody`'s `status` holds `telegramPaused`, active, with that time. `StatusMonitor` publishes that onset on the instance stream within 30 s. | — |
| Resume succeeds (FR-22) | Mark moved to 2 s ahead, after its onset was published | No `getUpdates` arrives before the mark's time. The first 200 deletes the mark. `StateBody` has no `telegramPaused`. `StatusMonitor` publishes the clear within 30 s, with no `telegramPaused` event between the onset and the clear. | — |
| Resume meets another 409 | Mark 2 s ahead; `telegram-conflict` queued during the pause | The first poll after the mark gets the 409, and the mark becomes 300 s ahead again. | — |
| Plain text (FR-20) | An `Outbound` with `ChatRef` (a row with chat id 8501) and text ``a*b_c [x](y) `z` <b>&amp; 1.5! #t``, sent to `TelegramOut` | One `sendMessage` with numeric `chat_id` 8501, `text` byte-identical, and no `parse_mode` or `entities`. | — |
| Split at line breaks | A 9,000-character text of 90-character lines | The parts are 4,096 characters or fewer, each is cut at the last line break inside the limit, and they are sent in order. The parts joined with a line feed equal the text. | — |
| Split one long line | A 9,000-character line with no break; a surrogate pair that straddles 4,096 | Parts of 4,096, then 4,096 (or 4,095 so that the pair is not split), then the rest. The parts joined with nothing equal the text. | Empty parts are not sent. |
| 429 on a message (UX-DR108) | `telegram-rate-limited` queued; one short text | Two `sendMessage` calls with the same text, the second at least 2 s after the first. The operation returns OK. | After five 429s for one part: an error status with a safe text, and the parts already sent stay sent. |
| 429 on the second part | New scenario `telegram-sent-then-limited` (a 200, then a 429 with `retry_after` 1); a two-part text | Three calls: part 1, part 2, and part 2 again at least 1 s later. Part 1 is never sent twice. | — |
| Notification for a chat | A `Notification` with `ChatRef` and the key `pairing.paired` | One `sendMessage` whose text is `Catalog.Render(key, slots, "telegram")`. | A render error: an error status, and nothing is sent. |
| No chat | A `ChatRef` with no chat row, or no `ChatRef` | No call. One warning that names neither a Ref nor an id. OK. | — |
| Endpoint settings | A start in CI, and `Install.Step.Telegram.Base("")` | `ApiBase` rows for both items: `http://mock:8080` in CI, `https://api.telegram.org` when the variable is empty. A row changed by hand is rewritten by the next `Run()`. Both items resolve `SSLConfig` to `OcuTalonClient`. | A base that is not `http(s)://host[:port][/path]`: the client returns an error that names the setting. |
| SSL configuration | A start; then `VerifyPeer` set to 0 by hand; then `SSL.Run()` | `OcuTalonClient` exists: client, enabled, `VerifyPeer` 1, `CAFile` `%OSCertificateStore`. `Run()` puts it back. | The step's first failure is its status. |
| Token search (NFR-11; the page's search goes to the sibling) | After a rejected start, a 409, a `getUpdates` 429, a `sendMessage` 429, a client call to a closed port, and one to the mock with no token | The dummy token is in none of these: `KeyScan.Find` (settings, item settings, event log), the `%Status` texts, the message headers and bodies since the mark, `AuditLog.Entries`, the live events since the mark, and `StateBody`. Each new scan finds a value that its store does hold. | — |

</intent-contract>

## Code Map

**The items (Epic 12's own)**
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls:1-23`: the stub. Delete `STUB` and the stub handler. Keep `Included()` and its doc comment as written:
  - `docker/tests/test-readme.sh` reads its body;
  - `docker/tests/test-boundaries.sh:67-75` allows the one read of `^OcuTalonTest` there and in no other product class.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls:1-14`: the stub. Delete `STUB` and the stub handler.
- `src/ocutalon/cls/OcuTalon/Production.cls:16-17`: the two entries in Lane A's region. `:37-39` (FailurePoller) shows how an adapter `CallInterval` setting is written.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls:613-614`: Epic 12's oracle rows. `TestStubsAnswer` (:139-184) compares `stub` with `$Parameter(class, "STUB")`, and `expectedStubs > 0` still holds through EvalIn and EvalSink.

**Siblings to follow**
- `Watch/FailurePoller.cls`, an `Ens.InboundAdapter` service: `LOG…` parameters (:29-31), an outer `Try` in `OnProcessInput` (:33-51), `$$$LOGWARNING(..#LOGX_…)` and `Quit $$$OK`.
- `irislib/Ens/InboundAdapter.cls:23-28` and `irislib/Ens/BusinessService.cls:285-355`. After every call the adapter waits `CallInterval` minus the time spent, so a 5-second poll with `CallInterval` 1 polls back to back. A stop or quiescence is noticed only between calls.
- `Channel/Operation.cls`, the abstract base of the channel operations. A subclass sets `LOGNOTASESSION` and `LOGPUBLISH`, and its `Keep` is what 12.6 uses. `Channel/SimPhone/Out.cls:39-46` shows the MessageMap pattern.
- `Msg/Outbound.cls` (`ChatRef`, `Text`, `CatalogKey`, `Slots`) and `Msg/Notification.cls` (`ChatRef`, `Kind`, `CatalogKey`, `Slots`).
- `Msg/Catalog.cls:51`: `Render(key, slots, channel, .sc)`, which accepts `"telegram"`.
- `Data/Pairing.cls`:
  - `RecordChat(chatId, displayName, .sc)` :79. It is for production jobs only, and its errors name no value.
  - `Chat(chatRef)` :195. It returns `""` for an unknown or code row.
- `Data/StatusMark.cls:21` `Record`, :56 `RecordTelegram`, :70 `TelegramState`. `Data/Time.cls:18` `NowUtc`, :42 `AddSeconds`.
- `Live/Payload/Status.cls:14,64,156-182` reads the `telegramPaused` mark verbatim and keeps the pause while `until > now`. `Core/StatusMonitor.cls:47-82` publishes it on change every 15 s. `Web/Api.cls:737` is `StateBody(session)`, and `:765-775` holds the Telegram block and `status`.
- `src/bridge/cls/OcuTalon/Bridge/Redact.cls:43` `Text(text)`. It masks real bot tokens but not the CI dummy, so `Safe` also replaces the exact token.
- `irislib/%Net/HttpRequest.cls`:
  - `Timeout` :711, `Https` :677, `SSLConfiguration` :680, and `FollowRedirect` (default off for POST).
  - The redirect error embeds the location (:1561).
  - `Reset()` builds the next `Referer` from the location (:1690-1700, :66-77).
  - HTTPS with no configuration fails with `HttpSSLNoConfig` (:1262).

**Install (contended, Epic 15's `Install/**`; see Footprint)**
- `Install/Step/Telegram.cls:24-27`: `Run()` (12.1). `Apply` (:37-49) and its rows stay as they are. Use `Install/Step/Production.cls:268` `WriteDefault(production, item, setting, value, description)`.
- `Install/Step/SSL.cls:1-9`: the empty stub, which its doc says the first story that needs a client configuration fills in place. `Install/Registry.cls:14` runs it after `Web` and before `Telegram` (pinned by `Test/Install/Registry.cls:126`).
- `irissys/Security/SSLConfigs.cls`: `Create(Name, .Properties)` :224, `Exists(Name)` :255 and `Modify(Name, .Properties)` :337. Properties: `Type` 0 (client), `VerifyPeer` 1, `CAFile` (`%OSCertificateStore` :50-54) and `Enabled`. Switch to `%SYS` as `Install/Step/Users.cls:126-127` does.
- Measured on slot A (build 154U, read only): the image has `/etc/ssl/certs/ca-certificates.crt`.

**Test helpers to call**
- `Test/Channel/BotApi.cls`: `Offset` :30, `SetOffset` :36, `PollerReason` :46, `Reset` :60 and `BotReply` :72.
- `Test/Channel/TelegramMock.cls:18-50`: `Token`, `Ready`, `Finish` and `Safe`, which move to the new base.
- `Test/Contract/Mock.cls`:
  - `TelegramMissingReason` :394, `BotCall` :403, `Control` :417 and `Calls` :429 (records `{seq, ts, method, params}`);
  - `TELEGRAMBASEVAR` :56 and `TELEGRAMTOKENVAR` :58.
- `Test/Agent/RunnerFixture.cls`:
  - `RunningReason` :86, `Jobs(item)` :127, `EventMark` :182 and `LogRowsHolding` :190;
  - `Send(target, message, .response)` :262 (sync, through `ApprovalStartIn`);
  - `SnapshotDefault` :670, `RestoreDefault` :704 and `PutDefault` :682.
- `Test/Agent/KeyScan.cls`:
  - `Find(value)` :174 scans the AI.LLM entries, the System Default Settings, the item settings, the whole event log, the sessions and the agent steps;
  - `SetEnv`, `UnsetEnv` and `HasEnv` :279-293 change the process environment.
- `Test/Bridge/AuditLog.cls`: `Now()` :23 and `Entries(since, …, marker)` :30. `Live/Event.cls:34` `Since(stream, after, max, label)`.
- `Test/Schedule/Stalled.cls:53-84,164-200` and `Test/Schedule/StallFixture.cls:73,80` are the pattern for checking a status condition through `StateBody` and `StatusMonitor`'s instance-stream event. `Data.Session.ForUser("zz…", .sc)` makes a fixture session.
- `Test/Data/Fixture.cls:230` `Pairing(sessionRef, displayName)` makes a chat row. Its `ChatId` is not numeric, so a test sets a numeric one.
- `irislib/Ens/Director.cls:1561` `EnableConfigItem(item, enable, doUpdate)`. When the item's `Enabled` comes from a System Default Setting row, this call rewrites that row, so snapshot the row first and restore it.
- `irislib/Ens/Director.cls:1084` resolves `Enabled` through `%GetSetting` before the item's own flag (source shows), so 12.1's `Enabled` row does enable a pool-1 service at a start. This story's tests enable the items on the running production instead.

**The mock (Lane B's; read only)**
- `ci/mock/mock.mjs`:
  - Any non-empty token is accepted, and the `getMe` default is `ocutalon_ci_bot`.
  - A queued reply answers first, for any method `getMe` included, and is sent as written.
  - `getUpdates` waits `min(timeout, 50)` s, wakes when something is queued, drops the ids below the offset, and ignores `allowed_updates`.
  - `/calls` records every parameter.
- `ci/mock/scenarios.mjs`: a telegram file is `{name, match: {"telegram": "<method>"}, replies: [...]}`, and one file may hold several replies. Files load at mock start only, so `ci/warm.sh down` then `up` after adding one.

## Tasks & Acceptance

**Execution:**
- `ci/mock/scenarios/A/telegram-getme-rejected.json`, `telegram-updates-busy.json` and `telegram-sent-then-limited.json` (new). Write these first, because a warm stack refuses changes under `ci/mock/`.
  - `getMe`: 401 `{"ok": false, "error_code": 401, "description": "Unauthorized"}`.
  - `getUpdates`: 429 `{"ok": false, "error_code": 429, "description": "Too Many Requests: retry after 3", "parameters": {"retry_after": 3}}`.
  - `sendMessage`: first a 200 `{"ok": true, "result": {"message_id": 1, "date": 0, "chat": {"id": 8601, "type": "private"}, "text": "part"}}`, then a 429 with `retry_after` 1.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Api.cls` (new), the Bot API client of both items:
  - Parameters `TOKENVAR`, `BASEVAR` (`OCUTALON_TELEGRAM_API_BASE`), `PUBLICBASE` (`https://api.telegram.org`), `SSLCONFIG` (`OcuTalonClient`) and `LIMIT` 4096.
  - `Call(base, sslConfig, method, params As %DynamicObject, seconds, Output httpStatus, Output sc) As %DynamicObject`:
    - It POSTs JSON to `<prefix>/bot<token>/<method>`, with the token read at the call, and sets `Https` and `SSLConfiguration` only for `https`.
    - It returns Telegram's parsed answer whatever the HTTP status, or `""` with `sc` set on a failure to connect, a timeout or a body that is not JSON.
    - Statuses follow the error rule under Always.
  - `Endpoint(base, .server, .port, .https, .prefix) As %Status`.
  - `Split(text, limit) As %List`, following the matrix.
  - `Safe(text)`: `$Replace` of the exact token, then `Bridge.Redact.Text`.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/In.cls`: build it.
  - Host settings `ApiBase` (default `PUBLICBASE`) and `SSLConfig` (default `SSLCONFIG`), with `SETTINGS`.
  - Parameters: `POLLSECONDS` 5, `READMARGIN` 3, `PAUSESECONDS` 300, `RETRYSECONDS` 5, and the `LOG…` texts.
  - `OnInit` and `OnTearDown`, and `OnProcessInput`'s order:
    1. rejected at this start, or a pause or a retry time in the future: return;
    2. not started: call `getMe`;
    3. otherwise, one `getUpdates` with the kept offset;
    4. handle the answer: 200, 401 or 404, 409, 429, other.
  - The handling of private updates (`RecordChat(chatId, "")`) and the skip rule follow the matrix.
  - Doc comment: the contract (AD-14, AD-18). `Included()` stays unchanged.
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/Out.cls`: build it.
  - It extends `OcuTalon.Channel.Operation`, sets its two `LOG…` parameters, and has the same two host settings.
  - A MessageMap for `Msg.Outbound` and `Msg.Notification`:
    - text: the `Outbound`'s `Text`, else the catalog rendering of its `CatalogKey`; or the `Notification`'s rendering;
    - chat: `Pairing.Chat(ChatRef).ChatId`.
  - `Send(chatId, text) As %Status`:
    - `Split`, then one `sendMessage` per part with `{chat_id (JSON number through %Set(…, "number")), text}`;
    - on a 429, `Hang` `retry_after` (at least 1) and send the same part again, at most 5 tries;
    - any other failure is an error status.
- `src/ocutalon/cls/OcuTalon/Production.cls`: on the `TelegramIn` entry only, add `<Setting Target="Adapter" Name="CallInterval">1</Setting>`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: Epic 12's two oracle rows get `"stub": 0`, and `TelegramIn`'s settings get `{"target": "Adapter", "name": "CallInterval", "value": "1"}`. In the class doc's list of built items (:13), add `TelegramIn` (built in Story 12.2, an inbound adapter service with the setting `CallInterval` 1) and `TelegramOut`.
- `src/ocutalon/cls/OcuTalon/Install/Step/Telegram.cls` (a contended edit):
  - New `Base(value) As %Status` writes the structural `ApiBase` row of both items through `WriteDefault`: the value, or `Api.#PUBLICBASE` when it is empty. Its description says that it is written at every start from `OCUTALON_TELEGRAM_API_BASE`, and not to edit it.
  - `Run()` becomes `Apply(…)`, then `Base($SYSTEM.Util.GetEnviron(Api.#BASEVAR))`. The first failure is the status.
  - Update the class doc.
- `src/ocutalon/cls/OcuTalon/Install/Step/SSL.cls` (a contended edit, filled in place): `Run()` makes `OcuTalonClient` match the matrix in `%SYS`, with `Create` when it is absent and `Modify` otherwise (structural). The first failure is the status. The doc states the contract.
- `src/ocutalon/cls/OcuTalon/Test/Channel/LiveCase.cls` (new): the abstract base of the live Telegram tests, with no `Test` methods.
  - `Token`, `Ready`, `Finish` and `Safe`, moved from `TelegramMock` unchanged.
  - `ReadyLive()`: `Ready`, plus a failure with the reason when `RunningReason()` is not empty. The new live classes use it.
  - `StartItems(items)`: snapshot each `Enabled` row, `EnableConfigItem(item, 1, 1)`, then wait for a job.
  - `StopItems()`: disable, wait for no job, then restore the rows.
  - `SaveMarks()` and `RestoreMarks()` for `telegramState` and `telegramPaused`.
  - `DropChats(ids)` deletes the `Pairing` rows of those chat ids.
  - Wait helpers for the offset, the mark and a call.
  - Every test calls `StopItems`, `RestoreMarks`, `DropChats` and `Finish` on every path.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramMock.cls`: extends `LiveCase`. Its own copies of `Token`, `Ready`, `Finish` and `Safe` go, and its tests are unchanged.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramSwitch.cls`: also snapshot and restore both `ApiBase` rows (`Run()` now writes them).
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramApi.cls` (new, runs anywhere):
  - the split rows: line breaks, one long line, the surrogate pair, empty parts, a text of exactly 4,096, and the join rules;
  - `Endpoint` on good and bad bases;
  - with a fake token set through `KeyScan.SetEnv` (then unset), a `Call` to `http://127.0.0.1:1` gives an error status that holds neither the token nor `/bot`, and `Safe` removes the token.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramIn.cls` (new, live): the matrix rows Start (with `StateBody` through a `zztgin<n>` fixture session), Stop during a long poll, Offset node (DW-422), Restart loses nothing, Already handled id, Private only, Rejected token and `getUpdates` busy. Use fixture chat ids 7001 and 83xx only.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramPause.cls` (new, live): the rows 409 pause, Resume succeeds and Resume meets another 409.
  - It follows `Test.Schedule.Stalled`: the `StateBody` members and `StatusMonitor` events after `InstanceSeq`.
  - The test stands in for elapsed time by moving the mark.
  - It waits for its own clear before it returns, so that no `telegramPaused` event lands in a later test's window.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramOut.cls` (new, live):
  - the rows Plain text, Split at line breaks, Split one long line, 429 on a message, 429 on the second part, Notification for a chat and No chat;
  - messages go through `RunnerFixture.Send("TelegramOut", …)`;
  - assertions read only the calls whose `chat_id` the test made (85xx and 86xx), because a warm stack may hold messages queued for `TelegramOut` by other tests.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramSettings.cls` (new; fresh throwaways and CI only, because it changes the SSL configuration): the rows Endpoint settings and SSL configuration, restoring both.
- `src/ocutalon/cls/OcuTalon/Test/Channel/TelegramNoToken.cls` (new, live): the Token search row. The message scan reads the headers since the mark and their bodies (export each body). The live-event scan uses `OcuTalon_Live.Event` rows after the mark. Each new scan gets a positive control:
  - the test's unique text in the `Outbound` body;
  - the pause time in `StatusMonitor`'s onset;
  - `ocutalon_ci_bot` in `StateBody`.

**Acceptance Criteria:**
- **The owner's U-164 condition (1):** given the installer's client SSL configuration `OcuTalonClient`, when a test runs against the shipped image (a fresh throwaway or CI stack built from the image, never a dev slot), then the CA file the configuration names exists in that image, and a request through `OcuTalonClient` to a disposable TLS server with a bad certificate (self-signed or for another host, started by the test inside its own throwaway, never a real external host) is refused (NFR-11, AD-19, AD-23).
- **The owner's U-164 condition (2):** given an `http://` `ApiBase` (the CI mock through `OCUTALON_TELEGRAM_API_BASE`; AD-19), when `TelegramIn` and `TelegramOut` call the Bot API, then they stay plain HTTP and work with no SSL configuration in the way: the request is not HTTPS, and a missing or broken `SSLConfig` changes nothing on an `http://` base (AD-19, AD-22).
- Given a token set and `TelegramIn` started, when it starts, then:
  - it reads the token only from the environment;
  - it learns the bot's user name from `getMe` and records `on` with it before its first poll, and `off` when it stops;
  - it long-polls `getUpdates` with `%Net.HttpRequest` through its `ApiBase` and `SSLConfig` host settings, which the Telegram step and the SSL step provide;
  - it confirms each handled update with the next offset and skips an id it already handled, so a restart neither loses nor repeats an update (FR-21, AD-14, AD-19, AD-5).
- Given `getMe` rejects the token, when `TelegramIn` starts, then:
  - Telegram stays off for that start and the mark is `rejected`;
  - `/state` says `rejected`, so the card shows "Telegram not set up" (R11, unchanged);
  - the log says that the token was rejected without showing it (FR-21, NFR-11, AD-14, UX-DR56).
- Given updates from groups, channels and private chats, when `TelegramIn` handles them, then:
  - only private-chat messages and private-chat presses are processed;
  - the others get no reply and create no message, row or audit entry;
  - an item stop during an open long poll ends within 10 s, inside the 60-second stop grace (FR-19, AD-23).
- Given a message for a chat, when `TelegramOut` sends it, then:
  - it is sent as plain text with no parse mode, exactly as written;
  - a text over 4,096 characters is split at line breaks, and a longer single line at the limit;
  - a 429 is retried after its `retry_after`, without losing or repeating any part (FR-20, AD-14, UX-DR108, UX-DR136).
- Given `getUpdates` answers 409, when `TelegramIn` receives it, then:
  - it stops polling for 5 minutes;
  - it logs the pause without the token;
  - it records the time through `StatusMark.Record("telegramPaused", until)`, from which `/state` and `StatusMonitor` turn on `telegramPaused` with that time (FR-22, AD-12, AD-18). The page's banner and card are the proposed sibling's.
- Given the pause has run out, when `TelegramIn` polls again, then:
  - on success the mark is removed, and `StatusMonitor`'s next `status` event clears the condition, which is the live update that removes the banner (FR-22, UX-DR34);
  - on another 409 it pauses again for 5 minutes.
- Given a Telegram test run against the mock, when a test searches every production setting, `%Status` text, event-log entry, trace message, audit entry, live event and the `/state` body for the dummy token, then it finds none (NFR-11, AD-14).
- Given DW-422, when `TelegramIn` runs, then its offset is the node `Test.Channel.BotApi.Offset()` reads. A value set there is the offset of its first poll, and each handled update moves that node (DW-422).
- Given this story merged, when CI starts OcuTalon, then:
  - `Included()` is unchanged;
  - no start enables a Telegram item, and `check_items_run` and `check_telegram_off` pass;
  - `TestStubsAnswer` passes with the two items no longer stubs;
  - the mock code and `Test.Contract.Mock` are unchanged (AD-22, AD-23, AD-29).
- Given the CI groups measured on the integrate-forward head af47ff3c (`ci` run 41188445340: install-fresh 34, install-upgrade 32, shards-2 31, shards 30, image 28, browser 26, production 25 minutes) and the dispatch's rule "never add a unit to a group over 30 minutes without moving another out", when this story adds its `Test.Channel` classes, then they no longer run inside `shard:lane-a@rest` (`shards-2`): `ci/units.sh` gains the unit `shard:lane-a@Channel` in the `production` group (so `@rest` loses `Channel` by `shard_unit_areas`), and `shard:lane-a@Channel` joins `NO_WEB_BUNDLE_UNITS` only if the unit is shown not to read the web bundle (record how it was shown under `## Verification`); if it cannot be shown, the unit goes into `browser` instead and `NO_WEB_BUNDLE_UNITS` is unchanged. `docker/tests/test-ci-config.sh` (every class of every shard runs once) and `test-ci-changes.sh` pass, and the change touches only Epic 12's own entries of `ci/units.sh` (the `Channel` piece and its group placement) (runner ruling, decide, 2026-10-31).

## Spec Change Log

- 2026-10-30, before implementation (runner): the owner's U-164 answer added two acceptance criteria (the CA file in the shipped image and a refused bad certificate; plain HTTP on an `http://` override) and a Design Notes block saying how they are tested. Story 12.7 carries condition (3).

- 2026-10-30, spec gate (runner, from the orchestrator's rulings): both `Install/**` edits are allowed as file-level extensions; the SSL configuration stays one general client configuration with no secret, as planned, and is veto item U-164. No other change to the plan.

- 2026-10-30, spec gate (runner): the proposed split is decided (unattended ruling, split, decide). The page side (the third criterion's banner and card clause, "the banner leaves within one live update", and the search of the page) moved verbatim to the new Story 12.8, planned next (`12-8-the-page-shows-when-telegram-is-paused-and-when-it-will-try`). This spec keeps the server side as planned. The two contended `Install/**` edits wait on the orchestrator's ruling.

- 2026-10-31, before implementation (runner C, re-dispatch after Epic 9): the epic now runs on runner C, so `## Verification`'s `<lane>` uses lane C (`locks/lane-c`, web port 52803) and slot C (`ocutalon-slot-c`) instead of lane A and slot A, and the two "never slot A" phrases read "never a dev slot". The branch was integrated forward onto 366a79ab (Epics 9 and 29); no AD this spec names changed in a way that touches it. No other change to the plan.

- 2026-10-31, before implementation (runner C ruling, decide): the `Channel` classes leave `shard:lane-a@rest` (`shards-2`, 31 minutes on af47ff3c) for their own unit `shard:lane-a@Channel` in `production` (25 minutes; in `NO_WEB_BUNDLE_UNITS` only if shown bundle-free), else `browser` (26 minutes); new Tasks & Acceptance item; `## Verification`'s "Left to CI" note on `shards-2` is superseded by it.

- 2026-10-31, implement blocked then resumed at review (runner C, orchestrator ruling, decide): the implement pass halted on the contended `Test/Install/Production.cls`; the orchestrator allowed the Telegram oracle rows and the `TestStubsAnswer` relaxation and dropped the class-doc edit (DW-482 to Story 15.3). The saved attempt patch was applied with those two changes, the patch file removed, and the spec set to `in-review` so build-auto resumes at its review step (Design Notes, "Orchestrator ruling of 2026-10-31").

## Review Triage Log

### 2026-10-31 — Review pass
- verdicts: 43 findings — high 0, medium 5, low 32, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` Blind: `TestStubsAnswer` guard `expectedStubs >= 0` cannot fail — orchestrator ruling of 2026-10-31 (spec Design Notes); the exact-count assertion on the next line still pins the test (the `Out.cls` STUB mutation turns it red); DW-482 carries the rest to Story 15.3
  - `[false]` `[reject]` Blind: Ens retry resends the whole message from part 1 after a partial failure — default ReplyCodeActions is E=F and `Retry` is never set (the client is `%Net.HttpRequest`, not the HTTP outbound adapter), so an error status fails the message and moves on; no resend
  - `[low]` `[reject]` Blind: no distinct handling of 403 or 400 from sendMessage — the status is an error with a safe text and the message is not retried; per-kind delivery handling belongs to Stories 12.6 and 12.7; reopen_if=a 403 is seen to loop
  - `[low]` `[reject]` Blind: `Out` sleeps the uncapped `retry_after` — the spec says to wait `retry_after` and resend; a stop is still bounded by the platform's item stop; reopen_if=a flood wait over 30 s is seen on a real bot
  - `[low]` `[reject]` Blind: empty text is dropped with OK and no warning — nothing exists to send; no user-reachable harm
  - `[low]` `[reject]` Blind: a whitespace-only part would get a 400 — only a text of more than 4,096 line feeds; theoretical
  - `[low]` `[reject]` Blind: `Endpoint` rejects an underscore in a host name — an underscore is not valid in a host name; the owner-fixed base is `http://mock:8080` or the public API
  - `[low]` `[reject]` Blind: any 404 is a rejection, and a 409 may mean a webhook — spec-bound: the matrix and the third acceptance criterion define 401 or 404 as a rejection and 409 as another process
  - `[false]` `[reject]` Blind: the pause mark is written on every successful poll — `StatusMark.Record(mark, "")` with no row only reads the index and writes nothing
  - `[low]` `[patch]` Blind: `TestCAFileInImage` has no `Guard()` — added `If '..Guard() Quit`, as the other tests of the fresh-only class; TelegramSettings fresh: passed
  - `[low]` `[reject]` Blind: `TestBadCertificateRefused` needs `openssl` and a free random port — the shipped image has openssl (measured in the implement pass) and a collision on a loopback port in 10,000 is rare
  - `[low]` `[reject]` Blind: the `ci/units.sh` timing comment is stale — the new sentence records the move and its reason; the older figures are labelled estimates
  - `[false]` `[reject]` Blind: `Out` carries two unused parameters — the spec requires `Out` to set both `LOG...` parameters (Operation's contract, used by Stories 12.6 and 12.7)
  - `[medium]` `[patch]` Blind: failure paths of `TelegramIn` (5xx, not JSON, ok false) have no test — added `TelegramIn.TestStartFailureRetries` (a 500 for getMe: not rejected, one warning, getMe again after 5 s, then on); the 'not JSON' and 'ok false' branches share the same `Failed` line
  - `[low]` `[reject]` Edge: `Out` sleeps the uncapped `retry_after` — carried: same as the Blind row
  - `[low]` `[reject]` Edge: with a pause mark in the future at start, `Run()` skips getMe and the state stays off — spec-bound: Always section and the plan's step 1 put the pause check before getMe
  - `[low]` `[reject]` Edge: `AddSeconds` returning empty would delete the mark — theoretical: `NowUtc` always gives a valid time
  - `[low]` `[reject]` Edge: a 404 on getUpdates sets rejected — carried: spec-bound, same as the Blind row
  - `[low]` `[reject]` Edge: an update with no integer `update_id` is never confirmed — theoretical: Telegram always sets an integer `update_id`
  - `[low]` `[reject]` Edge: a kept offset survives a token change — DW-422 and the spec keep the offset in the node alone; reopen_if=Story 12.7's hands-on pass changes the bot of an installed instance
  - `[medium]` `[defer]` Edge: `RecordChat(chatId, "")` overwrites a known chat's DisplayName with an empty name — verified in `Data/Pairing.cls` (`Set row.DisplayName = name`); no name is stored by any story yet, so nothing is lost today; contended file (Epic 11); deferred to Story 12.4, which stores names
  - `[low]` `[reject]` Edge: the status of the pause-mark delete is ignored — a failed delete is retried by the next 200 poll
  - `[low]` `[reject]` Edge: empty text sends nothing — carried: same as the Blind row
  - `[low]` `[reject]` Edge: whitespace-only part — carried: same as the Blind row
  - `[low]` `[reject]` Edge: `Base` writes an unchecked value — spec-bound: the client returns the error that names the setting
  - `[low]` `[reject]` Edge: control characters in a base path — owner-set environment value; no user-reachable path
  - `[low]` `[reject]` Edge: the SSL step's Modify leaves other properties as found — the matrix names Type, Enabled, VerifyPeer and CAFile as structural; a hand-edit of other properties is an administrator's act; reopen_if=Story 12.7 asks for a full reset
  - `[low]` `[reject]` Edge: `TestStubsAnswer` guard relaxed — carried: orchestrator ruling
  - `[low]` `[reject]` Gap: `TestStubsAnswer` guard cannot fail — carried: orchestrator ruling
  - `[low]` `[patch]` Gap: `TestBadCertificateRefused` has no mutation line — mutation run (VerifyPeer 0 in the SSL step, fresh): the refusal and 'no HTTP answer' assertions went red; the line is written below; the test now also asserts that OcuTalonClient exists with VerifyPeer 1 before the refusal
  - `[medium]` `[patch]` Gap: `TestPlainHttpIgnoresSSLConfig` passes with no assertion when the mock is absent — the guard branch now fails with the reason (as Ready and Guard do) and the class doc says so; TelegramApi: passed
  - `[medium]` `[patch]` Gap: non-401 getMe and getUpdates failures are not pinned — carried: patched with `TestStartFailureRetries`; mutation `Rejection` treats any status over 399 as a rejection: red (state never on, no second getMe, no warning)
  - `[low]` `[reject]` Gap: matrix rows without their own mutation line (TRIES, retry_after, surrogate, Notification, No chat) — Rule 19 asks one demonstrated mutation per acceptance criterion; each of these AC groups has its line (429 retry, no repeat, split)
  - `[low]` `[reject]` Gap: `NO_WEB_BUNDLE_UNITS` for a shard unit is not mechanically guarded — shown bundle-free by a recorded grep; `test-ci-config.sh` guards live units only; reopen_if=a Test.Channel class reads a file of the bundle
  - `[low]` `[reject]` Gap: settings tests rely on the install start's state — the class is fresh-only and guarded; the start always runs the SSL and Telegram steps
  - `[false]` `[reject]` Gap: `TestRejected` readiness signal is weak — the later assertions (exactly one getMe, one warning row after the log mark) cannot be satisfied by a stale mark
  - `[false]` `[reject]` Gap: `TestPrivateOnly` zero counts have no positive control — the same test asserts that the two private chats get a row
  - `[medium]` `[defer]` Gap: `RecordChat` clears the name — carried: deferred with the Edge row
  - `[false]` `[reject]` Gap: an unconditional mark write on every poll — carried: no write happens
  - `[low]` `[reject]` Gap: the https half of the plain-HTTP test targets a plain-HTTP mock — the first half pins the AC; the second only shows that a missing configuration is refused for https
  - `[low]` `[reject]` Intent: untested branches (429 without `retry_after`, a `RecordChat` failure) — small branches with a fixed default; the 5xx start branch is now pinned
  - `[low]` `[reject]` Intent: a 401 or 404 on a later getUpdates also sets rejected — carried: spec-bound
  - `[low]` `[reject]` Intent: pause before start — carried: spec-bound

## Design Notes

**The owner's U-164 answer (2026-10-30T09:39:29Z, applied by the runner before implementation).** Keep the one general client configuration `OcuTalonClient`, with three conditions; conditions (1) and (2) are this story's acceptance criteria above, and (3) is Story 12.7's (its hands-on pass records a verified handshake with `api.telegram.org`).
- Condition (1) is checked against the built image, never on a dev slot: either a `Test.Channel` %UnitTest class that runs on a fresh throwaway built from the image (the runner's lane locally, lane C since the 2026-10-31 re-dispatch; `shards-2` in CI), or a new `docker/tests` script run as a unit in `shards` or `shards-2` (with `ci/units.sh` and `docker/tests/test-ci-config.sh` updated). "The CA file the configuration names": if the configuration keeps `%OSCertificateStore`, the test proves the OS store resolves to a CA bundle present in the image (and records which file); if an explicit `CAFile` is the cleaner way to make that provable, the implement stage may name the image's bundle instead and record why. The bad-certificate server is disposable and local to the test's own stack (for example `openssl s_server` with a certificate the test generates, or a Node `https` server in the stack), torn down by the test; record what was measured.
- Condition (2): `Api` sets the request's SSL configuration only for an `https://` base; a test pins that an `http://` base makes a plain request (no `Https`, no `SSLConfiguration`) and keeps working when `SSLConfig` names a configuration that does not exist. The existing CI mock tests over `http://mock:8080` are the "it works" evidence.
- Both get rows in the mutation table (for example: `Api` sets `Https` for an `http://` base; `OcuTalonClient` with `VerifyPeer` 0; the CA file check pointed at a missing file).

**Spec-gate rulings (orchestrator, 2026-10-30; binding).**
1. `Install/Step/Telegram.cls`: the `Base` method and the `ApiBase` rows written by `Run()` are allowed under the file-level extension already granted for 12.1.
2. `Install/Step/SSL.cls`: filled in place, allowed (file-level extension). `Install/Registry.cls`'s `Order()` stays untouched. Conditions: the client SSL configuration is one general configuration for all of OcuTalon's outbound HTTPS (the later email story reuses "the installer's client SSL configuration"), not a Telegram-only one; it holds no secret (no private key, certificate password or credential of any kind); and it is a veto item under security posture (inbox U-164, runner ruling).
3. The split stands: the page side is Story 12.8, planned next.
4. Both `Install/**` files are footprint extensions the runner reports in its contract.

**Footprint (Rule 11). Both contended edits are allowed (rulings above).**
- **Epic 12's own:**
  - `Channel/Telegram/In.cls`, `Out.cls` and `Api.cls` (new);
  - `Test/Channel/LiveCase.cls`, `TelegramApi.cls`, `TelegramIn.cls`, `TelegramPause.cls`, `TelegramOut.cls`, `TelegramSettings.cls` and `TelegramNoToken.cls` (new);
  - `Test/Channel/TelegramMock.cls` and `TelegramSwitch.cls` (edited);
  - three new `ci/mock/scenarios/A/telegram-*.json` files.
- **Contended, Epic 15's `Install/**`:**
  - `Install/Step/Telegram.cls`: a new `Base` method and a two-line change to `Run()`.
  - `Install/Step/SSL.cls`: filled in place.

  A new `Install/Step` class would not serve. The registry runs only the classes in its fixed `Order()`, which is `Install/Registry.cls`, also in `Install/**`, so a new step would never run without a third contended edit. The SSL step is AD-23's named home for SSL configurations, and its own doc says that the first story that needs a client configuration fills it in place. The Telegram step is already the one writer of the Telegram items' structural rows (AD-19, AD-23).
- **Shared by region:** `Production.cls`, `TelegramIn`'s entry (Epic 12's).
- **Shared by entry:** `Test/Install/Production.cls`, Epic 12's two oracle rows.
- **Called, never edited:**
  - Lane B's `Data.StatusMark`, `Data.Pairing`, `Data.Time`, `Msg.Catalog`, `Msg.Outbound`, `Msg.Notification`, `Channel.Operation` (extended), `Web.Api.StateBody` and `Live.Event`;
  - `Bridge.Redact`;
  - the test helpers `KeyScan`, `RunnerFixture`, `AuditLog`, `Fixture`, `StallFixture` and `Test.Contract.Mock`.
- **No other path,** and nothing under `web/`.

**Proposed split (a recommendation; the runner decides and amends `epics.md`).** This spec plans the first child, 12.2 as above. The proposed sibling, planned next in this epic, takes:
- Given 3's second And clause: the page's banner seen from a real pause, and the card's "Telegram paused" and "Trying again at {time}" with the QR code withdrawn.
- Given 4's "the banner leaves within one live update", seen on the page.
- Given 5's "the page", a search of the rendered page.

Why:
- **Most of it is built.** The banner, its catalog key and its "Set up a bot" link exist and are tested by Lane B (`banners.spec.ts`, `banner-view.ts:76`). The work left is the card's state, two new page strings, the `pause-circle` icon, and a browser spec.
- **It is in another layer with contended files.**
  - The card's texts sit in Lane B's `rail-view.ts` `RAIL_TEXTS`, which `rail-view.test.mjs` checks exactly.
  - Page strings are listed in `ux-strings.test.mjs`.
  - Icons are in `icon/icon.ts`.
  - The card gets no live `status` today: `status-rail.ts:254` passes only the snapshot's `telegram`.
- **12.3 already names the card's paused state** in its second AC. 12.3 is the alternative home, since it reworks the same card and meets the same text-location questions. Moving an AC into a not-yet-planned story is the runner's call (veto window 7).

**Governing ADs:**
- AD-14: the channel pair, the Telegram transport rules, and the state and pause marks.
- AD-18: who writes the marks.
- AD-19: the token from the environment only; the endpoint override; structural values.
- AD-23: the one switch, and the SSL and Telegram steps.
- AD-12: status conditions through `/state` and `StatusMonitor`.
- AD-5: the offset survives restarts.
- AD-3: the XData holds structure; the `CallInterval` is structural.
- AD-4: no chat id or name outside the `Pairing` row.
- AD-32: `Outbound` and `Notification`, and only the `*Out` operations render.
- AD-22: the mock; Lane A only adds scenario files.
- AD-29: stubs, lanes and the seam.
- AD-33: one owner per item and table.

No acceptance criterion contradicts an AD. The NFRs are measurable.

**Decided in-stage:**
1. **The poll.** `getUpdates` `timeout` is 5 s, the HTTP read timeout 8 s, and `CallInterval` 1. The AC asks for a poll inside the 60-second stop grace. Stops in the platform and in tests wait 10 s (`UpdateTimeout`, `StopProduction(10)`), and from 12.7 `TelegramIn` runs at every CI start, so a longer poll would turn those stops red. The mock wakes a waiting poll when something is queued, so nothing becomes slower.
2. **`getMe` runs in `OnProcessInput`, not `OnInit`.** The start's "every enabled item runs" check is never delayed by the network, and a network failure is never mistaken for a rejection.
   - Only 401 or 404 means `rejected`.
   - `OnInit` records `off`, so a stale `on` from a job that crashed never shows.
3. **The offset node is the only copy.** It is read before every poll and written after each update, which is at-least-once only in the window of a crash. An update that fails to be handled is logged and confirmed (no poison loop).
4. **Processing a private update in 12.2 is `RecordChat(chatId, "")`.** That is the first step that 12.4 (`/start`), 12.5 (unpaired chats) and 12.7 (presses) all need, and it is what makes the private-only filter observable.
   - No name is stored, which is the safe default (12.5: an unpaired row holds only what its replies need).
   - 12.4 decides when a name is kept.
   - `allowed_updates` also asks Telegram for messages and presses only.
5. **The pause mark is the one truth.** It survives a restart, so two installs never fight right after a restart. `OnTearDown` leaves it, and it expires by its own time. Success deletes it.
6. **A 429 on `getUpdates`** waits `retry_after`, or 5 s. This is the epic's rule, which is not an AC of its own.
7. **TelegramOut in 12.2.** It handles an `Outbound` and a `Notification` that name a chat by `ChatRef`; a message with none is a warning and an OK status.
   - Routing by `SessionRef`, `Delivery` rows (`Keep`), the kinds and the message-edits are 12.6 and 12.7.
   - It extends `Channel.Operation` now, so 12.6 only adds.
   - Other send failures are error statuses, visible in the trace.
8. **The split counts UTF-16 units** (`$Length`, as Telegram does). It never splits a surrogate pair and drops the line break at a cut.
9. **A 429 on `sendMessage`** waits `retry_after` (at least 1 s) and sends the same part again, at most 5 tries. One residual is inference: a container stop during a very long `retry_after` can leave the message in progress, and IRIS recovery would resend it from part 1.
10. **The endpoint.** `ApiBase` is a structural row written at every start, from the variable or the public API, so that removing the override restores the default. `SSLConfig` keeps its default `OcuTalonClient`, with no row, since no variable overrides it.
11. **One SSL configuration, `OcuTalonClient`, for all of OcuTalon's outbound HTTPS.** It verifies the server against the OS store (`%OSCertificateStore`, which works where IPM installs into a non-Linux instance), with TLS 1.2 or later by default.
    - Turning verification on is the only safe option. It matches AD-19's rule for the model provider (`accept_invalid_*` false).
    - The CA bundle in the image was measured. Whether `%OSCertificateStore` resolves to it on Linux is inference, and the first real handshake is 12.7's hands-on pass. The implement stage's Task 0 checks only that the configuration saves and activates on a throwaway.
12. **One client class.** No product service or operation uses `%Net.HttpRequest` yet; only test classes do. Product code may not call test classes, so `Api.Call` cannot reuse `Test.Contract.Mock.BotCall` or `Test.Channel.BotApi.BotReply`. The copy of about 10 lines of request building is the product's own. The tests rely on the mock's `getMe` default (`ocutalon_ci_bot`) rather than a scenario.
13. **The two host settings are declared in each item.** There are two properties and a `SETTINGS` line; a mixin's `SETTINGS` would not merge across the two Ens superclasses.
14. **The log texts are admin-facing English** in the `LOG…` parameters. No page text is added.
15. **No `Included()` check inside the items.** The step is the one switch (AD-23).

**Extend, don't copy (Rule 2):**
- `TelegramIn` follows `FailurePoller`'s shape.
- `TelegramOut` extends `Channel.Operation` and follows `SimPhoneOut`'s MessageMap.
- The rows go through `WriteDefault`.
- The live-test helpers move from `TelegramMock` into `LiveCase`, so there is no second copy.
- The pause tests follow `Test.Schedule.Stalled` (private helpers of its shape, as Stalled keeps them).
- The token search calls `KeyScan.Find`, `AuditLog.Entries`, `Live.Event` and `StateBody`. Only the message-body scan is new, because no helper scans bodies for a secret.
- Item control calls `RunnerFixture`'s snapshot helpers.

**Integration ACs (Rule 1):**
- `/state` (`Web.Api.StateBody`) reads what `TelegramIn` records: `on` with the bot name, which is 12.3's link input, `rejected`, and `telegramPaused`.
- `StatusMonitor` publishes the onset and the clear.
- The card's "not set up" for `rejected` is R11's.
- `TelegramOut`'s consumer is the Bot API, read back through the mock's `/calls`.
- `TelegramIn` and `TelegramOut` consume `Api`.

**Consumed-by:**
- 12.3: `botUserName` in `/state`.
- 12.4: the private handler where `/start` is parsed, and `TelegramOut`'s `Notification`-by-`ChatRef` path for pairing replies.
- 12.5: unpaired rows (no name) and the replies through `TelegramOut`.
- 12.6: `TelegramOut`'s transport (the split also meets DW-30), plus `Delivery` rows, routing by `SessionRef`, and turns through `TelegramIn`.
- 12.7: private presses, `Api.Call` for `answerCallbackQuery` and `editMessageText`, and the 5-second poll that keeps CI's 10-second stops working once `TelegramIn` runs at every start.

**Consumes:**
- From Story 10.3: `StatusMark`, `Pairing.RecordChat` and `Chat`, `Live.Payload.Status`, `StatusMonitor` and `StateBody`.
- `Catalog.Render`, `Data.Time`, `Channel.Operation`, `Bridge.Redact` and `WriteDefault`.
- The mock, 12.1's scenarios, and `BotApi`.

All are used against the real mock and the running production.

**Lane B mock ask (AD-22, AD-33):** none. A rejected `getMe`, a busy `getUpdates` and a 200 followed by a 429 are new Lane A scenario files that the existing loader and queue serve.

**Owned ledger:** DW-422 is addressed by the "Offset node (DW-422)" matrix row, the DW-422 acceptance criterion and `Test.Channel.TelegramIn`'s offset test.

### Orchestrator ruling of 2026-10-31: the contended test file

`src/ocutalon/cls/OcuTalon/Test/Install/Production.cls` is contended (Epics 15 and 13). Ruling (orchestrator, decide): two edits are allowed as a file-level extension, reported under `footprint_extensions:`. (1) Lane A's own Telegram oracle rows: `TelegramIn` and `TelegramOut` go to `"stub": 0`, and `TelegramIn` gains `CallInterval` 1; the file's oracle rows are shared by row, like `Production.cls`'s lane regions. (2) `TestStubsAnswer` line 170 is relaxed from `expectedStubs > 0` to `expectedStubs >= 0`: with the Telegram items built, no production item is a stub any more (EvalIn and EvalSink have been `"stub": 0` since Story 9.1), and the exact-count assertion on the next line still pins the test (keeping `STUB` on `Out.cls` turns it red). The class doc's line 13 (its list of items without STUB), which Epic 15 also changes, is NOT edited: DW-482 (low, routed to Story 15.3) adds `TelegramIn` and `TelegramOut` there. The runner applied the implement stage's saved patch with edit 3 left out and edit 2 added, and ran `ci/iris.sh class OcuTalon.Test.Install.Production` on a fresh lane-C throwaway (tag `e12s2rc`): passed (its `TestStepHelpers` SKIP is pre-existing).

## Verification

`<lane>` stands for `env OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-c" OCUTALON_TEST_WEB_PORT=52803 OCUTALON_LOCK_OWNER='epic=12 stage=<stage>'`, run from the worktree root.

How to run:
- One command per foreground tool call, with `timeout: 600000`, and never two IRIS test runs in one message.
- A call that the harness moves to the background is polled in foreground calls of under 170 s each.
- Tests never run on a dev slot (this runner's is `ocutalon-slot-c`); IRIS MCP calls name `server: ocutalon-slot-c` and `namespace: OCUTALON`.
- Tear down only `e12s2i` and `e12s2iw`, also after a failure.

**Commands:**
- (once) Task 0, on a fresh throwaway after the SSL step exists:
  - `<lane> OCUTALON_RUN_TAG=e12s2i ci/iris.sh class OcuTalon.Test.Channel.TelegramSettings`. Expected: `OcuTalonClient` saves and is enabled with `%OSCertificateStore`.
  - If it is refused, record the refusal and stop with a clarification. Do not lower verification.
- (loop) `bash docker/tests/test-mock.sh`. Expected: `scenarios.test.mjs` row 15 loads the three new files.
- (loop) `<lane> OCUTALON_RUN_TAG=e12s2iw ci/warm.sh up`. After any later change under `ci/mock/`, run `down` and then `up`.
- (loop) `<lane> OCUTALON_WARM=1 OCUTALON_RUN_TAG=e12s2iw ci/iris.sh class <Class>`, one call per class: `OcuTalon.Test.Channel.TelegramApi`, `TelegramIn`, `TelegramPause`, `TelegramOut`, `TelegramNoToken`, `TelegramMock` and `TelegramSwitch`. Expected: `CLASS … passed`. `TelegramPause` takes about 90 s; the others take under 60 s each (inference).
- (loop) `<lane> OCUTALON_RUN_TAG=e12s2i ci/iris.sh class OcuTalon.Test.Channel.TelegramSettings` (fresh, never warm).
- (once) Warm, one call each: `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Install.Registry`, `OcuTalon.Test.Web.Api`, `OcuTalon.Test.Web.PairingApi`, `OcuTalon.Test.Contract.Mock`, `OcuTalon.Test.Live.Status` and `OcuTalon.Test.Core.StatusMonitor`. Expected: passed.
- (once) `<lane> OCUTALON_RUN_TAG=e12s2iw ci/warm.sh down`.
- (once) `<lane> OCUTALON_RUN_TAG=e12s2i ci/iris.sh live production-restart`. Expected: every PASS line. The starts run the SSL step and the new rows, and `check_telegram_off` and `check_items_run` stay green.
- (once) The fresh-environment check, one call each: `<lane> OCUTALON_RUN_TAG=e12s2i ci/iris.sh shard lane-a@Channel`, then the same with `--reverse`. Expected: every Channel class passes in both orders.
- (once) `bash docker/tests/test-ci-config.sh`, `test-ci-changes.sh`, `test-readme.sh` and `test-boundaries.sh`, one per call. Then write the changed and new paths to a file in the stage's scratchpad folder and run `bash ci/changes.sh ci.yml --paths-from <file>`. Then `bash ci/checks.sh`.
- (once) `<lane> OCUTALON_RUN_TAG=e12s2i ci/iris.sh teardown`.
- (once) `git status --short -- ci/mock/mock.mjs ci/mock/scenarios.mjs ci/mock/server.mjs ci/mock/health.mjs ci/mock/test src/ocutalon/cls/OcuTalon/Test/Contract/Mock.cls src/ocutalon/cls/OcuTalon/Install/Registry.cls web README.md` prints nothing.
- Left to CI (Rule 23), which runs every group on fresh instances on each push:
  - `shards-2` (`lane-a@rest`, now with about 3 more minutes of Channel classes on the runner; inference, still under REL-4's 35);
  - `install-fresh` and `install-upgrade` (the SSL step at a first start and at an upgrade);
  - `production`, `browser` (R11 unchanged), `image` and `shards`.

**Shared surfaces:**
- **The production's stub markers.** `TelegramIn` and `TelegramOut` lose `STUB`, and `TelegramIn` gains `CallInterval` 1. Readers: `Test.Install.Production` (its oracle rows and `TestStubsAnswer`'s count). The enabled flags are unchanged, so `check_items_run` and `Test.Core.ProductionItems` (which has no Telegram rows) are unaffected.
- **New structural System Default Setting rows** (`ApiBase` of both items), written at every start. `KeyScan.FindSettings` scans every row. `Test.Fix.Snapshot` compares rows only inside one test. `TelegramSwitch` restores them.
- **A new SSL configuration, `OcuTalonClient`, in `%SYS`,** made at every start. No test lists SSL configurations (a grep of `src`, `docker` and `ci` finds none).
- **The marks `telegramState` and `telegramPaused`.** Readers: `/state` (`Test.Web.Api`, `Test.Web.PairingApi`), `Live.Payload.Status` (`Test.Live.Status`, `Test.Core.StatusMonitor`), `rail.spec.ts` R11 and `banners.spec.ts`. Every test restores both marks.
- **The `telegramPaused` status events on the instance stream.** Each pause test waits for its own clear. `Test.Schedule.Stalled` reads only `heartbeatStalled`, and only in its own window.
- **`Pairing` rows of the fixture chats** (7001, 83xx, 85xx and 86xx), made and deleted by the tests.
- **The mock's Bot API state and the kept offset,** reset through `BotApi.Reset` at the start and end of each test. The mock's scenario list gains three files.
- **Messages and headers to `TelegramOut`.** Assertions read only the test's own chat ids.
- **Every test added or changed passes on a fresh environment, in either order.**

**Pinning mutations to apply (Rule 19).** The implement stage applies each one, sees red, reverts it byte for byte, and records `mutation: … -> …` here. No mutation may point a call at the public API: every mutated call still goes to the mock, or to nothing.

| AC or row | Mutation | Expected red |
|---|---|---|
| Start, `on` and the name | `RecordTelegram("on", "")` | `TelegramIn` start row (the name) |
| Off at stop | `OnTearDown` records nothing | `TelegramIn` stop row |
| Token from the environment only | `Api.Call` copies the token into a host setting | `TelegramNoToken` (`KeyScan.Find`) |
| Host settings used | `Endpoint` drops the base's port, so calls go to `mock:80` and are refused | `TelegramIn` start row (the mark never becomes `on`) and `TelegramOut` plain row |
| Offset node (DW-422) | The offset is kept at `$$$EnsStaticAppData("TelegramIn", "next")` | `TelegramIn` offset row (first poll without `offset` 3; `Offset()` unchanged) |
| Skip handled ids | The `update_id < offset` check is removed | `TelegramIn` already-handled row (a row for 7001 appears) |
| Restart loses nothing | `OnInit` adds 10 to the kept offset, so the backlog is skipped | `TelegramIn` restart row (B is never handled) |
| Private only | The chat-type check is removed | `TelegramIn` private-only row (rows for the group ids) |
| Rejected | 401 handled as a retry | `TelegramIn` rejected row (repeated `getMe`, mark not `rejected`) |
| Stop inside the grace | `POLLSECONDS` 50 | `TelegramIn` stop row (over 10 s) |
| `getUpdates` 429 | `retry_after` ignored | `TelegramIn` busy row (gap under 3 s) |
| 409 pause | `PAUSESECONDS` 0, or no mark written | `TelegramPause` 409 row |
| Resume clears | Success leaves the mark | `TelegramPause` resume row (the mark is still there) |
| Pause read each poll | The pause is read only in `OnInit` | `TelegramPause` re-pause row (a poll during the pause) |
| Plain text | `parse_mode` `MarkdownV2` added | `TelegramOut` plain row |
| Split | Cut at the limit, ignoring line breaks | `TelegramOut` line-break row and `TelegramApi` |
| 429 retry | A 429 is not retried | `TelegramOut` 429 rows |
| No repeat | A retry resends from part 1 | `TelegramOut` second-part row (4 calls) |
| No token anywhere | The 409 warning holds `Api.Call`'s location | `TelegramNoToken` (the event log) |
| SSL configuration | `VerifyPeer` 0 | `TelegramSettings` SSL row |
| Structural `ApiBase` | `Base` writes only when the row is absent | `TelegramSettings` endpoint row |
| Stubs gone | `Out.cls` keeps `STUB` | `Test.Install.Production` `TestStubsAnswer` |

**Recorded by the implement stage (runner C, 2026-10-31).**

- Task 0: on a fresh throwaway the SSL step created `OcuTalonClient` as a client configuration, enabled, `VerifyPeer` 1, `CAFile` `%OSCertificateStore` (`TelegramSettings`, run fresh). The shipped image keeps `/etc/ssl/certs/ca-certificates.crt` (121 certificates on build 154U); OpenSSL's `/usr/lib/ssl/cert.pem` leads to it, and `TestCAFileInImage` checks both. `%OSCertificateStore` resolving to that file on Linux stays inference until Story 12.7's hands-on pass; the configuration keeps the OS store and no explicit `CAFile`.
- U-164 condition 1 (`TestBadCertificateRefused`): the test makes a self-signed certificate with `openssl req` and runs `openssl s_server` on a loopback port inside the throwaway's own IRIS container (both exist in the image), then deletes the folder and stops the process. The same server answers HTTP 200 to a test-only client configuration that trusts the certificate, and `OcuTalonClient` is refused with no HTTP answer.
- U-164 condition 2 (`TelegramApi.TestPlainHttpIgnoresSSLConfig`): a call to the mock's `http://` base with `SSLConfig` set to a configuration that does not exist answers 200 with `getMe`; the same host over `https://` with that configuration gets no answer.
- `shard:lane-a@Channel` and `NO_WEB_BUNDLE_UNITS`: shown bundle-free by (1) a grep of every `Test/Channel` class for the bundle markers of `docker/tests/test-ci-config.sh` (`csp/`-style paths, the web folder names, `index.html`, `ensure_web_bundle`) with no hit; (2) the only web class that the Channel tests call, `Web.Api.StateBody`, reads rows, marks and the IPM module version, never a file of the bundle (`Web/Api.cls` has no reference to the bundle or its files). The unit sits in `production` and in `NO_WEB_BUNDLE_UNITS`; `test-ci-config.sh` (198 test classes, each in exactly one shard unit, 3 of them pieces) and `test-ci-changes.sh` pass. On the fresh stack `lane-a@Channel` runs 8 classes in 225 s (forward) and 266 s (reversed), build excluded, and both orders pass.
- Runs: all seven `Test.Channel` live classes, `Install.Production` (see the intent gap below), `Install.Registry`, `Web.Api`, `Web.PairingApi`, `Contract.Mock`, `Live.Status` and `Core.StatusMonitor` on the warm stack; `live production-restart` fresh (every PASS line, `check_telegram_off` and `check_items_run` green); `shard lane-a@Channel` and `--reverse` fresh; `test-mock.sh`, `test-ci-config.sh`, `test-ci-changes.sh`, `test-readme.sh`, `test-boundaries.sh`, `ci/changes.sh ci.yml --paths-from` and `ci/checks.sh` pass.
- **Intent gap (for the runner).** `TestStubsAnswer` ends with `Do $$$AssertTrue(expectedStubs > 0, "the oracle marks item classes as stubs")`. The spec says that this still holds through EvalIn and EvalSink, but both are built (`"stub": 0`; Story 9.1), so after this story no item of the oracle carries `STUB` and that one assertion fails (`Install.Production` otherwise passes). It was not edited here, because `Test/Install/Production.cls` allows only the named rows; with the guard relaxed to `expectedStubs >= 0` as an experiment (reverted byte for byte) the class passes, and keeping `STUB` on `Out.cls` turns it red. The fix is that one line, for the runner to decide.

Mutations (Rule 19), each applied with the warm stack's reload, run, and reverted byte for byte (`cmp` against my own backup, `git status` unchanged):

- mutation: `RecordTelegram("on", "")` -> `Test.Channel.TelegramIn` TestStart (the name, and StateBody's name)
- mutation: `OnTearDown` records nothing -> `TelegramIn` TestStop (the state is off, with no name)
- mutation: `Api.Call` copies the token into a host setting (an `SSLConfig` row of TelegramIn; the row deleted afterwards) -> `TelegramNoToken` (the KeyScan of the settings, and the audit scan)
- mutation: `Endpoint` drops the base's port -> `TelegramIn` (TestStart, TestOffsetNode, TestAlreadyHandled: the state never becomes on) and `TelegramOut` (TestPlainText, TestNotification: no answer from the Bot API)
- mutation: the offset kept at `$$$EnsStaticAppData("TelegramIn", "next")` (read and write; the leftover node killed afterwards) -> `TelegramIn` TestOffsetNode (the first poll without offset 3, `Offset()` unchanged), TestAlreadyHandled, TestRestartLosesNothing and TestStart
- mutation: the `update_id < offset` check removed -> `TelegramIn` TestAlreadyHandled (a row for 7001 appears)
- mutation: `OnInit` adds 10 to the kept offset -> `TelegramIn` TestRestartLosesNothing (B is never handled), TestOffsetNode, TestAlreadyHandled
- mutation: the chat-type check removed -> `TelegramIn` TestPrivateOnly (rows for the group, channel and group-press chats)
- mutation: 401 handled as a retry (never rejected) -> `TelegramIn` TestRejected (the state never becomes rejected, repeated calls)
- mutation: `POLLSECONDS` 50 -> `TelegramIn` TestStop (the job failed to stop within 10 seconds; the stack was cleaned afterwards)
- mutation: `retry_after` ignored on a getUpdates 429 -> `TelegramIn` TestUpdatesBusy (the gap was 1.01 s)
- mutation: `PAUSESECONDS` 0 -> `Test.Channel.TelegramPause` TestPause409 (the mark is not 300 s ahead; no pause; no member in StateBody)
- mutation: success leaves the pause mark -> `TelegramPause` TestResumeSucceeds (the first 200 does not delete the mark)
- mutation: the pause read only at the first run -> `TelegramPause` TestResumeMeetsAnother409 (a poll during the pause), TestPause409 and TestResumeSucceeds
- mutation: `parse_mode` `MarkdownV2` added -> `Test.Channel.TelegramOut` TestPlainText
- mutation: `Split` ignores line breaks -> `TelegramOut` TestSplitAtLineBreaks and TestSentThenLimited, and `TelegramApi` TestSplitLineBreaks
- mutation: a 429 is not retried -> `TelegramOut` TestRateLimited and TestSentThenLimited
- mutation: a retry resends part 1 -> `TelegramOut` TestSentThenLimited (part 2 again, never part 1; three calls, the third is part 1) and TestRateLimited
- mutation: the 409 warning holds `Api.Call`'s location (the path with the token) -> `Test.Channel.TelegramNoToken` (the event-log scan)
- mutation: `VerifyPeer` 0 in the SSL step -> `Test.Channel.TelegramSettings` TestSSLConfiguration
- mutation: `Base` writes only when the row is absent -> `TelegramSettings` TestEndpointSettings (the public API is not written, and a row changed by hand is not rewritten)
- mutation: `Out.cls` keeps `STUB` -> `Test.Install.Production` TestStubsAnswer (TelegramOut carries STUB, answers 5003, and the stub count differs); the baseline fails on the guard above, so this red was shown with the guard relaxed
- mutation: `Api` sets `Https` for an `http://` base (U-164 condition 2) -> `TelegramApi` TestPlainHttpIgnoresSSLConfig
- mutation: the CA-file check pointed at a missing file (U-164 condition 1) -> `TelegramSettings` TestCAFileInImage
- mutation: the VerifyPeer of the SSL step set to 0 (U-164 condition 1, fresh stack) -> `TelegramSettings` TestBadCertificateRefused (OcuTalonClient no longer refuses the self-signed certificate, and an HTTP answer is read), TestSSLConfiguration and TestCAFileInImage
- mutation: `Rejection` treats any status over 399 as a rejection (a 500 for getMe) -> `TelegramIn` TestStartFailureRetries (the state never becomes on, no second getMe, no warning); the class passes again after the revert

## Auto Run Result

Status: done
Blocking condition: none

Summary: `TelegramIn` (short long poller: getMe, then getUpdates every 5 s, kept offset in Story 12.1's node, private chats only, 5-minute pause on a 409 through the `telegramPaused` mark) and `TelegramOut` (plain text, split at 4,096, retry after a 429) are built on one new Bot API client (`Api`). The Telegram step writes the `ApiBase` rows at every start, the SSL step makes `OcuTalonClient`, and the Channel test classes sit in their own unit `shard:lane-a@Channel` in `production`.

Files changed:
- `src/ocutalon/cls/OcuTalon/Channel/Telegram/{Api,In,Out}.cls`: the client and the two items.
- `src/ocutalon/cls/OcuTalon/Install/Step/{Telegram,SSL}.cls`: the `ApiBase` rows and `OcuTalonClient` (file-level extensions).
- `src/ocutalon/cls/OcuTalon/Production.cls`: `CallInterval` 1 on `TelegramIn`.
- `src/ocutalon/cls/OcuTalon/Test/Install/Production.cls`: the two Telegram oracle rows and line 170, by the orchestrator's ruling.
- `src/ocutalon/cls/OcuTalon/Test/Channel/*`: `LiveCase`, `TelegramApi`, `TelegramIn`, `TelegramPause`, `TelegramOut`, `TelegramNoToken`, `TelegramSettings` (new), `TelegramMock` and `TelegramSwitch` (changed).
- `ci/mock/scenarios/A/telegram-{getme-rejected,updates-busy,sent-then-limited}.json`: three new scenarios.
- `ci/units.sh`: `shard:lane-a@Channel` in `production` and `NO_WEB_BUNDLE_UNITS`.

Review (43 findings from four layers): patches applied 4 (`TelegramIn.TestStartFailureRetries` added for the 5xx-start branch; `TestPlainHttpIgnoresSSLConfig` fails with its reason instead of passing with no assertion; `TestCAFileInImage` gets the `Guard()`; `TestBadCertificateRefused` asserts the configuration first and now has its mutation line); deferred 1 (RecordChat clears a stored name, for Story 12.4); every other finding is rejected with its reason in the triage log (false 6, spec-bound or theoretical lows, the orchestrator-ruled `>= 0` guard).

Follow-up review recommended: false. Patched counts by verdict: medium 3 (one root cause counted twice in the log), low 2; no high; the patches touch only test classes and were each run.

Verification: the implement pass's full verification list and 22 table mutations (recorded above) were green before the halt; the lead's fresh run of `Test.Install.Production` passed after the ruling. This pass re-ran the classes its patches touch: `TelegramIn` (warm) passed with the new test, red under its mutation and green after the revert; `TelegramApi` (warm) passed; `TelegramSettings` (fresh) passed, and red in `TestBadCertificateRefused` under the `VerifyPeer` 0 mutation. Warm stack `e12s2rw` torn down; `e12s2r` leaves nothing.

Residual risks: `%OSCertificateStore` resolving to the image's CA file on Linux stays inference until Story 12.7's hands-on pass; the deferred RecordChat name overwrite for Story 12.4; footprint extensions to report: `Install/Step/Telegram.cls`, `Install/Step/SSL.cls`, `Test/Install/Production.cls` (the two oracle rows and line 170).
