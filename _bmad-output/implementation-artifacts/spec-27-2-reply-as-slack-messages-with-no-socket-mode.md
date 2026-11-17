---
title: 'Story 27.2: Reply as Slack messages, with no socket mode'
type: 'feature'
created: '2026-11-17'
status: 'ready-for-dev'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-27-context.md'
warnings: [oversized]
deferred: []
---

<intent-contract>

## Intent

**Problem:** A linked Slack member's direct message becomes a turn (27.1, 27.3), but its reply reaches only the web chat: `Core.Rule.Notify` has no Slack target, no `SlackOut` exists, `Msg.Catalog` refuses the channel `slack`, and setup step 1 lacks the `chat:write` scope a reply needs. CI has no Slack API mock and nothing proves the Slack code never uses socket mode.

**Approach:** Add `SlackOut` (`OcuTalon.Channel.Slack.Out`), which posts a Slack turn's reply to the linked member with `chat.postMessage` (built with `%Net.HttpRequest`, token from the environment at use), as the same plain text Telegram gets, and records a `Delivery` row. Notify's `Outbound` rule gains one `when` (a Slack turn with Slack on and a link → `WebChatOut,SlackOut`). The catalog renders `slack`. CI's mock gains a Slack Web API side with `B/` scenarios, a hermetic check bans socket mode, setup step 1 names `chat:write`, and inbound Slack markup is decoded to plain text before the turn.

## Boundaries & Constraints

**Always:**
- Only an `OcuTalon.Msg.Outbound` whose `OriginChannel` is `slack` reaches `SlackOut`, and only while `Channel.Slack.In.On()` is 1 and the session has a `Data.SlackLink` row. `SlackOut`'s MessageMap names `Msg.Outbound` only, so a Notification is never sent to Slack even if misrouted. Notification rules of `Notify` are not changed.
- The recipient is the session's linked member id (`chat.postMessage` with `channel` = the member id, which posts into the app's direct-message conversation with that member). The member id, the team id and Slack's DM channel id are in no trace, log, status text, `Delivery` row or message (R8). `Delivery.ChannelMessageId` is `<SlackLink Ref>:<ts>`.
- The text is exactly Telegram's: the reply text (or the catalog render for channel `slack` of a fallback key), then the check sentence and the learned lines, joined as Telegram joins them. Before sending, `&`, `<`, `>` become `&amp;`, `&lt;`, `&gt;`; the body sets `mrkdwn` false, `unfurl_links` false and `unfurl_media` false. Parts of at most 4,000 UTF-16 units, cut at line breaks (Telegram's `Api.Split`); a part that was sent is never sent again.
- HTTP 429: wait the `Retry-After` header's seconds (missing, not a number or below 1 → 1) and retry, at most 5 tries; a wait over 30 s is not taken: the send fails with its plain reason. Any other failure (no answer, non-200, `ok` false) fails at once.
- A failure is the operation's error status (Visual Trace marks the message), with a fixed plain reason and at most Slack's error code (letters, digits and `_`, 64 characters). `SLACK_BOT_TOKEN` is read with `$SYSTEM.Util.GetEnviron` at each call, sent only in the `Authorization: Bearer` header, never stored, and stripped from every error text before `Bridge.Redact`.
- `OCUTALON_SLACK_API_BASE` (AD-19), read at use, default `https://slack.com/api`; CI sets `http://mock:8080/api` only in `live:slack-hook`'s own `$tmp` override and in-process in unit tests (R9). `ci/compose.ci.yml` is not edited. No test or pipeline step calls slack.com.
- No Slack code opens a WebSocket, uses `%Net.WebSocket`, calls `apps.connections.open` or handles an app-level token (`xapp-`); a hermetic check in `ci/checks.sh` proves it.
- The online demo: Slack is off there, `Notify` never routes to `SlackOut`, and `SlackOut` refuses (error, nothing sent). Pinned.
- Every test added or changed passes on a fresh environment, in either order.

**Never:**
- No edit to a Lane A file (Telegram's `Out`/`Api`/`In`, `Agent/*`, `Eval/*`, `ci/mock/scenarios/A/**`), to `Core/Conversation.cls` (Story 0.38's), to `ci/compose.ci.yml`, `.github/workflows`, `release/**` or `README.md`.
- No new role, grant, resource, `Data.Setting` key, install step, table or third-party dependency; no Slack text other than the gate-ruled sentences.
- No socket mode, no Events API change, no Slack approval surface, no Notification to Slack.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Reply to a Slack turn | Outbound, OriginChannel `slack`, Slack on, session linked | Notify → `WebChatOut,SlackOut`; one `chat.postMessage` (`channel` member id, escaped text, `mrkdwn` false); one `Delivery` row (`slack`, `<link Ref>:<ts>`) | — |
| Long reply | text over 4,000 units | parts in order, cut at line breaks; one Delivery row (last part's ts) | part n fails → error, parts after n not sent, no row |
| Rate limited | 429, `Retry-After: 1`, then ok | two calls ≥ 1 s apart; one row | `Retry-After: 120` → one call, error "asked to wait" reason, no row |
| Slack error | 200 `{"ok":false,"error":"channel_not_found"}` | error status, reason names `channel_not_found`; no row; token in no text | — |
| No link | Outbound slack, link removed after the turn | Notify → `WebChatOut` only | SlackOut reached anyway → one warning, OK, nothing sent |
| Slack off / online demo | either env empty, or `onlineDemo` 1 | Notify → `WebChatOut` only | SlackOut refuses with `ERROROFF`, no call |
| Notification | any Kind, session linked, Slack on | never `SlackOut` (rules unchanged) | `SlackOut`'s message map has no entry for it, so it can post nothing |
| Refused turn | `not_user` Item (27.3) | no Outbound, no `chat.postMessage` in the mock log | — |
| Inbound markup | DM text `a &amp; b &lt;3 <@U0X> <https://e.x|e.x>` | turn text `a & b <3 @someone e.x (https://e.x)` | — |

</intent-contract>

## Code Map

All classes under `src/ocutalon/cls/OcuTalon/`. Lane B unless marked.

**Reply path (read-only siblings, Lane A, U-177):**
- `Channel/Telegram/Out.cls` -- `OnOutbound` 171-186 (Target → text or `Catalog.Render(key, slots, TEXTCHANNEL)` → check sentence `text_$c(10,10)_sentence` → `Memory.Learned.Lines(request.Learned, request.Text, channel)` after a blank line, LF-joined, via `Joined` 189 → `Deliver`); `CheckSentence` 425-447 and `WhatFailed` 452-496 (PRIVATE: `PLAINKEYS` 150, `FAILEDKEYS` 153, `SEPARATOR` 156; rows `{result, entry, finding, checkedAt}`, `Data.Time.ForMessage` + " ET" on the demo); `Send` 509-526 (loop over `Api.Split`, stops at the first error, counts `sent`, keeps `lastText`); `Post` 543-559 (TRIES 5, 429 retry); `Deliver` 311-322 and `Recorded` 325-335 (record only when sent ≥ 1 and the send succeeded; a failed `Record` is one warning, OK); `TRIES` 87, `SENDSECONDS` 15 (90).
- `Channel/Telegram/Api.cls` -- public `Split(text, limit)` 232-260 and `Endpoint(base, .server, .port, .https, .prefix)` 205-226 (its error names `ApiBase`; reuse the parse, replace the text); `SSLCONFIG` `OcuTalonClient` 28; `Call` 48-100 is the `%Net.HttpRequest` recipe (new request per call, `FollowRedirect` 0, `Timeout`, https → `SSLConfiguration`, UTF-8 body); `Safe` 264-270 (exact-token strip, then `Bridge.Redact.Text`).
- `Test/Channel/TelegramOut.cls` -- `WithChecks` 195 and its expected check sentences: the oracle for `ReplyText`'s parity test.

**Own files:**
- `Channel/Operation.cls` -- base: `IsSession` 15-21, `LOGNOTASESSION` 9. No MessageMap.
- `Channel/DigestText.cls`, `Channel/PageText.cls` -- precedent for a Lane B shared text class of the `*Out` operations.
- `Channel/Slack/In.cls` -- `On(demo)` 52-58 (the one switch), `TOKENVARIABLE` 38, `Turn` 114-153 (`item.Text = text` at 134).
- `Data/SlackLink.cls` -- `SessionRefIndex` 51 (unique), `Unlink` 174 uses `SessionRefIndexOpen`; no SessionRef → member method yet.
- `Msg/Outbound.cls` -- SessionRef, OriginChannel, Text, CatalogKey, Slots, CheckRows, CheckKey, DecisionRef, Learned. `Core/Conversation.cls` `Tell` 861-880 sends it to Notify (not edited).
- `Data/Delivery.cls` -- `Record(ownerRef, channel, channelMessageId, approvalRef, kind, text, decisionRef, ...)` 70-91; `slack` is in `Msg.Enum` CHANNEL; `ChannelMessageId` MAXLEN 128; no reader of `slack` rows.
- `Msg/Catalog.cls` -- `CHANNELS` 46 (`web,phone,mailbox,telegram,email`), refusal 108-110, line 115 (non-web channels use `text`), `CHANNELNAMES` 49. `Test/Msg/Catalog.cls` -- `TestEveryKeyOnEveryChannel` 140-169 (refused set 146, loop 150, refused loop 160-165), `TestErrors` 368 (`"webhook","slack","system",""`), `TestChannelNames` 706.
- `Memory/Learned.cls` `Lines` 75-90 (channel only goes to `Catalog.Render`).
- `Core/Rule/Notify.cls` -- `Outbound` rule 31-39; class doc 1-24. `Core/Rule/Functions.cls` -- `TelegramPaired` 36-48 is the shape for `SlackLinked`; names unique across FunctionSets, never throw.
- `Test/Core/Routing.cls` -- `TestNotifyTargets` 238-294 (reply loop 271-277), `TestFunctions` 470 (name list 524), `TestRuleTargetsAreProductionItems` 544-597 (expected Notify targets 562), `Route` 647.
- `Production.cls` -- lane B region, `SlackIn` 107, `<!-- lane B: end -->` 108. `Test/Core/ProductionItems.cls` -- the `SlackIn` row is last.
- `Test/Agent/KeyScan.cls` `SetEnv`/`UnsetEnv` -- in-process env for unit tests (27.1 precedent). `Test/Channel/EmailOut.cls` 173-179 -- calling an operation's handler on an instance directly.
- `Test/Contract/Mock.cls` -- `Control(route, body)` 478 and `Calls()` 490-496 hard-wired to `/_mock/telegram/`; `NewRequest` 647-653 (`mock:8080`).

**CI mock (`ci/mock/`):**
- `mock.mjs` -- `control()` 273-326 (`/_mock/telegram/*` → `telegramControl` 321-323); `tg` state 246, `emit` 248-254 (redacted line to stdout and `requests.jsonl`), `queueReplies` 362-366, `telegramControl` 369-442, `handleBot` 563-674 (token by length 570-579, calls `{seq, ts, method, params}` 601, file log keeps `paramNames` 600, `takeQueued` 616-625), `build` 517-524 (reply headers merged case-insensitively), `delayMs` 668-673; `handle` 726-750 (routing order; Slack path goes before the model API); `KEY_LIKE` 77-85.
- `scenarios.mjs` -- `MATCH_TYPES` 37, `TELEGRAM_REPLY_FIELDS` 41, `BOT_METHODS` 43, `checkReply` 116-158 (telegram: `body` object required, `text`/`toolUse`/`stopReason` refused), `checkTelegramReplies` 169, `checkScenario` 176-227. `scenarios/A/telegram-rate-limited.json` is the shape.
- `test/telegram.test.mjs` (73-486: token by length, queue/calls/reset 247, bad scenario 400 at 292, never picked by a model request 317, no token in stdout or `requests.jsonl` 356), `test/scenarios.test.mjs` (bad-case table, telegram rows 57-66), `test/constants.test.mjs`. Run by `docker/tests/test-mock.sh` (`WEB_SCRIPTS`, hosted `web` job).
- `ci/warm.sh` 73-79: a `ci/mock` change (not `ci/mock/test/`) makes a warm stack stale: change the mock BEFORE `ci/warm.sh up`, or `down`/`up`.

**Live and checks:**
- `docker/tests/test-slack-hook.sh` (`live:slack-hook`, `shards-3`, 373 s measured) -- override printf 175 (`DUMMY` 43, `token` 45); phase 3b 278-342 (linked DM → Turn 280-297); leak scan 359-394 (`log_hits` 362-364 greps `dc logs`, which include the mock's output); phase 7 427-570 (`sends()` 458-460, `settled` 463). Mock calls read through an `iris_script` `%Net.HttpRequest` to `mock:8080`: precedent `docker/tests/test-production-restart.sh:96,125`.
- `docker/tests/test-boundaries.sh` -- `scan_rule "<label>" <scanner> <bad> <good> "<files>"` (`lib-scan.sh:24-45`), examples 246, 296. Not contended. Legitimate `%CSP.WebSocket` users: `Web/Live.cls:16`, `Web/SessionEvents.cls`, `web/src/app/live/*` (must stay clean).
- `ci/units.sh` -- `shards-3` 168 (≈ 28.7 min planned); `Test/Channel` runs in `shard:lane-a@Channel` (group `production`, 163); `Test/Core|Data|Msg|Contract` in lane-b pieces. No units change.

**Docs:**
- `GUIDE.md` `## Slack` 257-262 (four lines, step 1 at 259); `## For admins and developers` 294. `web/scripts/slack-setup-steps.test.mjs` -- header 1-3, `STEPS` 16-21 (step 1 at 17), exactly four lines 56-59, no-`chat:write` cases 65-67 and 89-91. `EXPERIENCE.md` Later Steps › Step 7 1204-1214 (step 1 at 1208, intro tag 1206). `README.md` unchanged (2,235/2,300 words; More paragraph already links `GUIDE.md#slack`; `test-readme.sh` 841 bans "Slack" in "How you talk to it").

**Spine** (`_bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16/ARCHITECTURE-SPINE.md`, 1,938 lines, by range): AD-14 525-561 (Notify 532, `*Out` Delivery 535, Telegram outbound bullet = grammar model); AD-19 715 (endpoint overrides; `OCUTALON_SLACK_API_BASE` "read only by `SlackOut`"); AD-22 955 (mock serves model + Telegram), 964 (match list), 965 (Bot API side), 975-979 ("mock as built" sides); AD-32 1320 (renderer channels); production-item row 1567 (`SlackOut` already listed); Deferred 1932 (Slack row, the only socket-mode sentence).

## Tasks & Acceptance

**Execution (in this order):**
- `ci/mock/mock.mjs`, `ci/mock/scenarios.mjs` -- the Slack Web API side, inside `createMock` beside the Bot API side (extend: same `emit`, `queueReplies`/`takeQueued` per method, `build`, `delayMs`): `SLACK_PATH` `/^\/api\/([A-Za-z.]+)$/` handled before the model API; `POST /api/chat.postMessage` with `Authorization: Bearer <token>` (token logged by length only; missing → 200 `{"ok":false,"error":"not_authed"}`); every call kept in memory as `{seq, ts, method, params}` while the log line keeps `paramNames` only (no member id, text or token in stdout or `requests.jsonl`); default answer 200 `{"ok":true,"channel":"D0MOCK<seq>","ts":"<epoch>.<6-digit seq>"}`; any other method 200 `{"ok":false,"error":"unknown_method"}` (so `apps.connections.open` is never served); control `/_mock/slack/{calls,replies,reset}` (`replies` takes `{scenario}` or `{method, replies}`). `scenarios.mjs`: `slack` in `MATCH_TYPES`, `SLACK_METHODS = ['chat.postMessage']`, replies checked as telegram's (`status`, `headers`, `delayMs`, `body` object). `KEY_LIKE` is not changed (it mirrors `lib-keys.sh`; the token is never written to a log, so nothing needs redacting).
- `ci/mock/scenarios/B/slack-posted.json`, `slack-rate-limited.json` (429, `headers` `{"Retry-After":"1"}`, body `{"ok":false,"error":"ratelimited"}`), `slack-not-found.json` (200, `{"ok":false,"error":"channel_not_found"}`) -- new.
- `ci/mock/test/slack.test.mjs` (new, shape of `telegram.test.mjs`) and rows in `scenarios.test.mjs` -- token by length; `not_authed`; default answer; queued replies, calls, reset; 429 with `Retry-After` header; `unknown_method` for `apps.connections.open`; a slack scenario never answers a model request; no token, member id or text in stdout or `requests.jsonl` over a real server process; bad slack scenarios refused.
- `Test/Contract/Mock.cls` -- `Control(route, body, side = "telegram")` and `Calls(side = "telegram")` (extend; existing callers unchanged).
- `Data/SlackLink.cls` -- `MemberFor(sessionRef, Output linkRef) As %String`: the member id of the session's link (`SessionRefIndexOpen`), else "" (linkRef ""). Class doc line.
- `Channel/ReplyText.cls` (new, abstract, shape of `DigestText`) -- `Text(request As Msg.Outbound, channel, Output sc, Output warning) As %String`: Telegram's text exactly (reply or catalog render, check sentence, learned lines, joins). Holds a copy of Telegram's private `CheckSentence`/`WhatFailed` (Rule 2: copy forced by U-177; see Design Notes). A failed check sentence is left out and returned in `warning` (no ids, text redacted).
- `Channel/Slack/Out.cls` (new, `SlackOut`, extends `Channel.Operation`) -- MessageMap `Msg.Outbound` → `OnOutbound` only. `OnOutbound`: `'Slack.In.On()` → error `ERROROFF`; `IsSession`; `MemberFor` "" → one warning `LOGNOMEMBER`, OK; text = `ReplyText.Text(request, "slack", ...)` (render error → status); `Telegram.Api.Split(text, 4000)`; per part: escape `&`→`&amp;` first, then `<`, `>`; private `Post(member, part, .ts)` (a new `%Net.HttpRequest` per call, `FollowRedirect` 0, `Timeout` 15, https → `SSLConfiguration` `OcuTalonClient`, `ContentType` `application/json; charset=utf-8`, header `Authorization`, UTF-8 JSON `{channel, text, mrkdwn:false, unfurl_links:false, unfurl_media:false}`, POST `<prefix>/chat.postMessage`); 429 loop per the Boundaries (header `Retry-After`, `MAXWAIT` 30, `TRIES` 5); success = 200 and `ok` true; record `Delivery.Record(sessionRef, "slack", linkRef_":"_ts, "", "", "", request.DecisionRef)` when ≥ 1 part was sent and all succeeded (ts kept only if `^[0-9]{1,12}\.[0-9]{1,8}$`, else empty after the colon); failed record → one warning, OK. Private seams `Token()`, `Base()` (env at use; base checked with `Telegram.Api.Endpoint`, its error replaced by `ERRORBASE`), `Safe(text)` (strip the exact token, then `Bridge.Redact.Text`). Fixed texts as parameters (gate a). Class doc states the contract.
- `Channel/Slack/Markup.cls` (new) -- `Plain(text) As %String` per Slack's documented format: `<@U…|label>`/`<@W…|label>` → `@label`, `<@U…>`/`<@W…>` → `@someone`; `<#C…|name>` → `#name`, `<#C…>` → `#channel`; `<!here>`/`<!channel>`/`<!everyone>` → `@here`/`@channel`/`@everyone`; `<!subteam^…|@h>` → `@h`; other `<!…|fallback>` → fallback, other `<!…>` → ""; `<url|label>` → `label (url)` (just `url` when label = url), `<url>` → url, `mailto:` dropped from a label-less mail link; then `&lt;`→`<`, `&gt;`→`>`, `&amp;`→`&` (amp last). No id survives. `Channel/Slack/In.cls` `Turn` :134 -- `Set item.Text = ##class(OcuTalon.Channel.Slack.Markup).Plain(text)`; class doc line. (Gate d.)
- `Core/Rule/Functions.cls` -- `SlackLinked(sessionRef) As %Boolean`: `Slack.In.On()` and `SlackLink.SessionRefIndexExists(sessionRef)`; 0 on any error. `Core/Rule/Notify.cls` -- in `Outbound`, before the telegram `when`: `<when condition="Document.OriginChannel=&quot;slack&quot; &amp;&amp; SlackLinked(Document.SessionRef)"><send transform="" target="WebChatOut,SlackOut"></send></when>`; class doc bullet.
- `Production.cls` -- `<Item Name="SlackOut" ClassName="OcuTalon.Channel.Slack.Out" PoolSize="1" Enabled="true"/>` after `SlackIn`, before `<!-- lane B: end -->`. `Test/Core/ProductionItems.cls` -- the matching row.
- `Msg/Catalog.cls` -- `CHANNELS` `web,phone,mailbox,telegram,email,slack`; doc lines 32/108 updated. `CHANNELNAMES` unchanged. `Test/Msg/Catalog.cls` -- refused set `webhook,system,heartbeat` (146), `slack` in the loop (150) with every key's `slack` render equal to its `telegram` render, `TestErrors` 368 without `slack`.
- `docker/tests/test-boundaries.sh` -- rule `slack-no-socket-mode`: on code lines of `src/**/Channel/Slack/**`, `src/**/Test/Channel/Slack*` and `ci/mock/*.mjs`, no `WebSocket`, `apps.connections`, `socket_mode`, `socket mode` (case-insensitive) or `xapp-`; and nowhere in `src/` (outside `src/ocutalon/csp/`) `%Net.WebSocket` or `apps.connections`. Bad and good samples; `Web/Live.cls` stays clean.
- `GUIDE.md` :259, `EXPERIENCE.md` :1208 (+ `[AMENDED <date>, Story 27.2, Contest Planner ruling]` on the intro line 1206), `web/scripts/slack-setup-steps.test.mjs` (`STEPS[0]`, header, the two cases flip to "step 1 names chat:write") -- the ruled step-1 sentence (gate a), in the same commit as `SlackOut`.
- `docker/tests/test-slack-hook.sh` -- override adds `OCUTALON_SLACK_API_BASE: "http://mock:8080/api"`; phase 3b resets the mock's Slack side first, then pins the reply (I/O row 1: one call per turn, `channel` equals the fixture member compared inside IRIS and printed only as 1/0, `text` the escaped `ReplyText`, `mrkdwn` false, the Delivery row `<link Ref>:<ts>` of that call, Notify headers to `WebChatOut` and `SlackOut`); a `&`/`<`/`>` and mention event pins Markup end to end (Turn text decoded); phase 7 resets the side at its start and pins zero `chat.postMessage` calls for every refused account; the leak scan adds the mock's `requests.jsonl` (`/opt/ocutalon/mock-log/requests.jsonl`) and the trace bodies for `$DUMMY` and the member id. Header comment updated.
- **Tests (new):** `Test/Channel/SlackOut.cls` (env in-process via `KeyScan.SetEnv`, mock through `Test.Contract.Mock` side `slack`, reset first; `TestReply`, `TestEscaped`, `TestSplit`, `TestNoResendAfterFailure`, `TestRateLimited`, `TestWaitTooLong`, `TestSlackError`, `TestTokenNeverLogged` (token in no status, `Ens_Util.Log` row or mock log), `TestNoMember`, `TestOffAndOnlineDemo`, `TestOnlyOutboundMapped` (the compiled `MessageMap` names `OcuTalon.Msg.Outbound` and nothing else), `TestRecordHoldsNoIds`); `Test/Channel/ReplyText.cls` (`TestSameAsTelegram` with `TelegramOut.WithChecks`' rows and expected sentences, `TestLearnedLines`, `TestFallbackKey`); `Test/Channel/SlackMarkup.cls` (each form, entities, amp last, no `U…`/`W…`/`C…` id left); `Test/Data/SlackLink.cls` `TestMemberFor`; `Test/Core/Routing.cls` `TestNotifySlackTargets` (slack reply × {on/off, demo, link/no link} and every Notification Kind never `SlackOut`), `SlackLinked` in `TestFunctions` and its name list, `SlackOut` in the expected targets (562).
- **Spine** (Rule 20, same change; gate f) -- apply gate item (f) exactly as the Planner rules it (every `<date>` in its tags is the UTC date of the edit, written out); `memlog.py append`; `lint_spine.py` `"ok": true` (no new placeholder); refresh `updated:`.

**Acceptance Criteria:**
- Given a turn from Slack, when `Conversation` sends its reply to `Notify`, then it reaches `WebChatOut` and `SlackOut`, `SlackOut` posts it with `chat.postMessage` to the linked member as Telegram's text (escaped, `mrkdwn` false) and records one `Delivery` row `<link Ref>:<ts>` (Integration AC: `live:slack-hook` phase 3b, real production and the CI mock; `Routing.TestNotifySlackTargets`; `SlackOut.TestReply`) (FR-46, AD-14, AD-32, UX-DR18, UX-DR108).
- Given any Notification kind with Slack on and a link, when Notify routes it, then `SlackOut` is never a target, and `SlackOut`'s message map handles `Msg.Outbound` only (`TestNotifySlackTargets`, `SlackOut.TestOnlyOutboundMapped`).
- Given a 429 or an error answer, when `SlackOut` handles it, then it waits `Retry-After` before retrying (≤ 30 s, ≤ 5 tries), fails with its plain reason in Visual Trace, records no row, and the token is in no status, log, trace or mock log (`TestRateLimited`, `TestWaitTooLong`, `TestSlackError`, `TestTokenNeverLogged`; live leak scan) (NFR-11, NFR-20).
- Given the repository, when `bash ci/checks.sh` runs, then `slack-no-socket-mode` passes on the tree and fails on its bad sample; the Slack tests use only the mock with `B/` scenarios (AD-22, REL-4).
- Given a refused (`not_user`) Slack turn, when it settles, then the mock lists no `chat.postMessage` (live phase 7).
- Given Slack off or the online demo, when a Slack reply would be sent, then Notify routes only to `WebChatOut` and `SlackOut` refuses with nothing sent (`TestOffAndOnlineDemo`, `TestNotifySlackTargets`) (AD-25).
- Given a DM with Slack markup, when it becomes a turn, then its text is the decoded plain text with no member, channel or subteam id (`SlackMarkup`; live phase 3b).
- Given the guide, when it is read, then `GUIDE.md` › Slack's four steps (linked from the README's More paragraph) explain creating the app with the ruled step 1 (`chat:write`), subscribing events on a public HTTPS address, the environment variables and linking a member, word for word with `EXPERIENCE.md` (`slack-setup-steps.test.mjs`), and `test-readme.sh` passes (FR-58, NFR-24).
- Given the change, when it lands, then the spine carries gate item (f) and `lint_spine.py` reports `"ok": true`.

## Spec Change Log

## Review Triage Log

## Design Notes

**Governing ADs:** AD-1 (no command change), AD-4 (identity only in its own row), AD-13 (our replies come back as bot messages, Ignored), AD-14 (channel pair; Notify routing: amended), AD-19 (env-only token; `OCUTALON_SLACK_API_BASE`), AD-22 (the mock's Slack side: amended), AD-24/R8 (no ids in records), AD-25 (online demo), AD-26 (trace), AD-27 (Delivery retention unchanged), AD-29/AD-33 (Lane B files; production-item row already lists `SlackOut`), AD-32 (renderer channels: amended). No AC contradicts an AD Rule; the three amendments extend lists the ADs say steps extend.

**Decided in-stage:**
1. Recipient: `chat.postMessage` with `channel` = the linked member id, found by `SlackLink.MemberFor(SessionRef)`; Slack posts it into the app's DM with that member (Slack docs, docs.slack.dev chat.postMessage; needs `chat:write` only; (inference) until the Planner's hands-on pass). Nothing new is carried on the Item or Outbound, and no DM channel id is stored.
2. `ChannelMessageId` = `<SlackLink Ref>:<ts>`: the Ref is opaque (27.3 Decided 5), the ts is Slack's message time; same shape as Telegram's `<chatRef>:<id>`.
3. Routing condition `SlackLinked` = Slack on + a link row (shape of `TelegramPaired`), so the online demo and an unlinked session never reach `SlackOut`; `SlackOut` still checks both (defence in depth).
4. `SlackOut` Enabled, PoolSize 1, gated by `On()` (SlackIn's precedent; no install step, 27.1 Decided 3). One idle job also on the demo.
5. Size 4,000 (Slack's recommendation; its 40,000 truncation is never reached even when escaping grows a part fivefold); escaping after the split; `mrkdwn` false keeps Telegram's plain text; unfurls off (no previews of links in replies).
6. Rate limit: Slack's `Retry-After` header; `MAXWAIT` 30 s because the operation's one job blocks while it waits; a longer wait fails honestly instead of retrying early. Only 429 is retried (Telegram's rule).
7. Rule 2: `ReplyText` holds a copy of Telegram's private `CheckSentence`/`WhatFailed` (~70 lines): U-177 forbids editing or extracting from `Telegram/Out.cls`, and both are private. Lane B's `ReplyText` is the shared class (precedent `DigestText`, `PageText`); the lead ledgers the unification (TelegramOut calls `ReplyText`) as a routed entry for the next Lane A story that touches `Telegram/Out.cls`, else `burndown`. Reused as they are: `Telegram.Api.Split`, `Telegram.Api.Endpoint` (parse only), `Bridge.Redact.Text`, `Slack.In.On`/`TOKENVARIABLE`, `Channel.Operation.IsSession`, `Delivery.Record`, `Memory.Learned.Lines`, `Test.Contract.Mock` (extended with a side), the mock's Bot API machinery (extended in `createMock`).
8. `CHANNELNAMES` gains no `slack`: it names the channel an approval was answered from, and nothing typed in Slack answers one (R6), so a `slack` name would let a text claim what the product doesn't do.
9. Socket-mode check in `test-boundaries.sh` (not contended; `test-class-rules.sh` is edited on `OCT-epic28`); scoped so the live-events WebSocket stays legal.
10. Unit tests set `SLACK_*` and `OCUTALON_SLACK_API_BASE` in-process (`KeyScan.SetEnv`, unset after), so shards exercise the real `SlackOut` against the mock with no global env (R9).
11. AC 4 placement: Story 0.30 moved install and admin material to `GUIDE.md`, the README is capped (65 words left) and its More paragraph already links `GUIDE.md#slack`, and the four approved steps cover exactly the four topics AC 4 names. So the "developer section" is `GUIDE.md` › Slack with the ruled step 1; README and the R12 four-line structure are unchanged. Amendment for the lead (Rule 5 apply-and-report, a file-name correction): AC 4 "the README" → "`GUIDE.md`, linked from the README".
12. Inbound markup is decoded in 27.2 (27.1/27.3 residual): it restores the characters the person typed (the same text the message would carry from the web chat or Telegram) and removes member, channel and subteam ids from the turn text, its trace and the model input (R8). Model-facing: gate (d).
13. Size: one cohesive reply path (operation, routing, renderer, mock, check, docs), the shape of 27.1/27.3; nothing separable without leaving the reply untested (the mock) or the setup text wrong (step 1 ships with the code). No split proposed.
14. CI: no new unit or group. `live:slack-hook` grows by about 30-60 s (inference; `shards-3` ≈ 29.5 min ≤ 32); `Test.Channel.SlackOut`/`ReplyText`/`SlackMarkup` join `shard:lane-a@Channel` (`production` group, a few seconds plus ≤ 3 s of rate-limit waits).

**Integration ACs / Consumed-by / Consumes:**
- Consumes: `Notify` (routes the Outbound), `Data.SlackLink` (`MemberFor`, extended), `Channel.Slack.In.On`, `Msg.Catalog`, `Memory.Learned`, `Telegram.Api.Split`/`Endpoint`, `Bridge.Redact`, `Data.Delivery`, CI's mock.
- Integration AC: Notify (the producer side) sends a real `Conversation` reply to `SlackOut`, and the mock (the consumer of the post) records the `chat.postMessage` with the Delivery row (AC 1, `live:slack-hook`, real production).
- Consumed-by: `ReplyText` — no other consumer in this story; the first will be the Lane A story that unifies TelegramOut (routed entry above). `SlackOut` has no downstream consumer story.

**Ledger inbox:** none. DW-1454, DW-1465, DW-1466 are not this story's (Story 0.38 owns the `Conversation` gate; 27.2 does not edit it).

### Planner gate items

- (a) PUBLIC TEXT, verbatim:
  - Setup step 1 (GUIDE.md › Slack, EXPERIENCE.md Later Steps › Step 7, `slack-setup-steps.test.mjs`): "Create a Slack app for your workspace at api.slack.com/apps. In App Home, turn on the Messages Tab and allow users to send messages from it. Give its bot the im:history and chat:write scopes, and install it to the workspace."
  - No other guide or README sentence (Decided 11). README unchanged.
  - Visual Trace texts of `SlackOut` (event log and status; not catalog text): `ERROROFF` "Slack is off, so SlackOut sends nothing."; `LOGNOMEMBER` "SlackOut found no linked Slack member for this session, so the reply went only to the web chat."; `ERRORBASE` "OCUTALON_SLACK_API_BASE must be http(s)://host[:port][/path]."; `ERRORREACH` "OcuTalon could not reach Slack, so the reply was not sent to Slack."; `ERRORREFUSED` "Slack did not take the reply (HTTP {status}, error {code}), so it was not sent to Slack."; `ERRORWAIT` "Slack asked OcuTalon to wait {seconds} seconds, longer than the 30 it waits, so the reply was not sent to Slack."; `LOGRECORD` "SlackOut sent the reply but could not record its delivery: {reason}"; `LOGCHECK` "SlackOut sent the reply without its check sentence: {reason}".
- (b) OUTWARD: `SlackOut` sends `POST <OCUTALON_SLACK_API_BASE or https://slack.com/api>/chat.postMessage` with `Authorization: Bearer <SLACK_BOT_TOKEN>` and JSON `{channel: <the linked member id>, text: <the escaped reply part>, mrkdwn: false, unfurl_links: false, unfurl_media: false}`: to the linked member whose direct message made the turn, once per part of each reply to a Slack turn that `Conversation` accepted, only while both Slack variables are set and the install is not the online demo. No other Slack method is called. CI and every pipeline test reach only the mock (`http://mock:8080/api`, dummy token); nothing in the pipeline calls slack.com. A real post happens only on an install whose admin set the variables (the Planner's hands-on pass is the Planner's).
- (c) VETO items, with online-demo behaviour:
  - Secrets: `SLACK_BOT_TOKEN` now authorizes outbound posts; read at use, header only, stripped from every error text, never stored or logged. Demo: unset, Slack off.
  - Stored data: `Delivery` rows of channel `slack` (`<link Ref>:<ts>`, no text kept, no member/team/channel id), purged like every Delivery row (AD-27). Demo: none written.
  - Production item `SlackOut` (Enabled, PoolSize 1, one idle job). Demo: present, never routed, refuses.
  - `OCUTALON_SLACK_API_BASE` read by `SlackOut` (already in AD-19). Demo: unset.
  - Inbound turn text now decoded (gate d). Demo: Slack off, no turns.
  - No new role, grant, resource, setting key, table or dependency (the mock uses Node's standard library).
- (d) MODEL-FACING: one. A Slack turn's text reaches the model decoded (entities → `& < >`; mentions → `@label`/`@someone`; links → `label (url)`; channels → `#name`). Recommendation: no A/B, because the decoded text is what the person typed and what the same message carries from the web chat or Telegram, and it removes ids the model should not see. If the Planner requires an A/B, the merge waits on it as R7's did; `Markup.Plain` is called from one line (`Slack/In.cls` `Turn`), so the ruling can drop the decode without touching the reply path.
- (e) CONTENDED paths: `Production.cls` lane B region, one appended line after `SlackIn` (sequenced within lane B; R11 pattern). Spine: `OCT-epic28` (local) edits AD-10/17/21/23/24/33 and `origin/OCT-epic0-flakes` (Story 0.39) adds one AD-22 bullet near the mock rules; 27.2 edits AD-14, AD-19, AD-22 (match list and a new "mock as built" bullet), AD-32 and Deferred: textual overlap only possible in AD-22 (adjacent lines; whichever lands second rebases the line). `GUIDE.md` line 259 (stale `origin/OCT-epic36` +2 elsewhere). Not edited: `Core/Conversation.cls` (Story 0.38), `test-class-rules.sh` (Epic 28), `ci/compose.ci.yml`, `ci/units.sh`, Epic 28's paths, any Lane A file. `EXPERIENCE.md` is a planning artifact (the lead re-warms `epic-27-context.md`).
- (f) SPINE edits (each tagged `[AMENDED|ADDED <date>, Story 27.2, Contest Planner ruling]`):
  - AD-14 :532 (Notify): after "a reply goes to its turn's channel and the web chat" add "(a Slack reply goes to `SlackOut` only while Slack is on and the session has a `SlackLink` row, `Functions.SlackLinked`; Slack never gets a Notification)".
  - AD-14, new bullet after the Telegram outbound bullet: "`SlackOut` (Story 27.2) posts a reply to a Slack turn with `chat.postMessage`, built with `%Net.HttpRequest`, to the session's linked member (`SlackLink.MemberFor`), as Telegram's text with `&`, `<`, `>` escaped, `mrkdwn` and unfurls off, in parts of at most 4,000 characters cut at line breaks; it retries only a 429, after Slack's `Retry-After` (at most 30 s, 5 tries), never resends a sent part, records `Delivery` `<SlackLink Ref>:<ts>`, maps only `Msg.Outbound` and refuses while Slack is off; the token is read from the environment at each call, sent only in the `Authorization` header and never in a setting, status text or log. No Slack code uses socket mode or a WebSocket (`docker/tests/test-boundaries.sh`)."
  - AD-19 :715: after "`OCUTALON_SLACK_API_BASE` (read only by `SlackOut`, Story 27.2)" add "(default `https://slack.com/api`; CI sets `http://mock:8080/api` only in `live:slack-hook`'s own override and in-process in unit tests, R9)".
  - AD-22 :955 "the model API and the Telegram API" → "the model API, the Telegram API and the Slack Web API"; :964 match list adds `slack`; new bullet under "The mock as built": "**The mock's Slack side [ADDED <date>, Story 27.2]:** `POST /api/chat.postMessage` with a Bearer token (logged by length only) on the HTTP port, answering `{ok, channel, ts}` or a queued reply; any other method answers `unknown_method`; a scenario whose `match` is `slack` names `chat.postMessage` and uses `status`, `headers` (`Retry-After`), `delayMs` and `body`; control at `/_mock/slack/{calls,replies,reset}`; the log keeps parameter names only."
  - AD-32 :1320: renderer channels "`web`, `phone`, `mailbox`, `telegram` and `email`" → add "and, from Story 27.2, `slack` (Telegram's text)".
  - Deferred :1932: the Slack row moves out (built in Epic 27: route 27.1, linking 27.3, replies 27.2; no socket mode, pinned).
  - No AD contradicted; no Rule replaced.

## Verification

Run from the worktree root. Every `ci/iris.sh`/`ci/warm.sh` call sets `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=27 stage=implement'` and a tag beginning `e27s2` (fresh `e27s2i`, warm `e27s2iw`); one per foreground call, `timeout: 600000`. Change `ci/mock/**` before `ci/warm.sh up` (a later mock change needs `down`/`up`); `ci/warm.sh down` at the stage's end, also after a failure.

**Commands:**
- `bash docker/tests/test-mock.sh` (loop) -- every mock test passes, the Slack side's included.
- `node --test web/scripts/slack-setup-steps.test.mjs` (loop) -- passes with the ruled step 1.
- `bash docker/tests/test-boundaries.sh` (loop) -- `slack-no-socket-mode` passes; its bad sample is flagged.
- `bash docker/tests/test-readme.sh`, `bash docker/tests/test-ci-config.sh` (once each) -- pass.
- `ci/warm.sh up` (once), then `OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s2iw ci/iris.sh class <C>` (loop, one class per call) for `OcuTalon.Test.Channel.SlackOut`, `.ReplyText`, `.SlackMarkup`, `.SlackIn`, `OcuTalon.Test.Core.Routing`, `OcuTalon.Test.Msg.Catalog`, `OcuTalon.Test.Data.SlackLink`, `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Contract.Mock` -- each passes.
- `OCUTALON_RUN_TAG=e27s2i ci/iris.sh live slack-hook` (once, fresh, ≈ 7 min) -- every phase passes, the reply phases and the zero-call pin included; then `ci/iris.sh teardown` with the same tag.
- `uv run --no-cache .claude/skills/bmad-architecture/scripts/lint_spine.py --workspace _bmad-output/planning-artifacts/architecture/architecture-OcuTalon-2026-10-16` (once) -- `"ok": true`, no new placeholder.

**Shared surfaces:** Notify's `Outbound` targets (`Test.Core.Routing` `TestNotifyTargets`, `TestRuleTargetsAreProductionItems` expected list, `TestFunctions` name list); the production items (`Test.Core.ProductionItems`, `Test.Install.Production`, any live script that counts items: grep `docker/tests` for item counts); `Msg.Catalog` CHANNELS (`Test.Msg.Catalog` refused set and loops); the mock's routes, match types and constants (`ci/mock/test/*.test.mjs`); the Slack setup step 1 (`slack-setup-steps.test.mjs`, GUIDE, EXPERIENCE); `Delivery` rows (counts in `test-slack-hook.sh` phase 7 `sends()`); the mock's shared call log (every Slack test resets the side first). Every test added or changed passes on a fresh environment, in either order.

**Mutations (Rule 19; the implement stage records each as `mutation: <change> → <red test>`):** Notify's slack `when` removed; `SlackLinked` without the `On()` check; escaping dropped; `Retry-After` ignored (fixed 1 s); token appended to `ERRORREFUSED`; Delivery recorded after a partial failure; `slack` removed from `CHANNELS`; `Markup.Plain` keeps `<@U…>`; the socket-mode rule's scanner returns nothing; step 1 without `chat:write`.

## Auto Run Result

Status: ready-for-dev
Blocking condition: none

Planned 2026-11-17 (plan stage only; halt after planning). The build waits on the Contest Planner's ruling of `### Planner gate items` (a)-(f): the step-1 sentence and SlackOut's trace texts (a), the chat.postMessage send (b), the veto items (c), the inbound-markup decode as a model-facing change (d), the contended spine/Production lines (e) and the spine edits (f). For the lead: a Rule 5 apply-and-report amendment of AC 4 ("the README" → "`GUIDE.md`, linked from the README", Decided 11), and one routed ledger entry for the forced Rule 2 copy in `Channel/ReplyText.cls` (Decided 7). No split proposed (Decided 13).
