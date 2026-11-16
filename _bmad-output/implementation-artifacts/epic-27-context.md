# Epic 27 Context: Slack (step 7, Could)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make Slack a working OcuTalon channel without socket mode, because the platform's WebSocket client fails right after opening. Slack's Events API posts to a Slack route under `/ocutalon/hook`. A direct message from a linked Slack member becomes a normal user turn: it gets an attention decision, shows in the web chat "via Slack" and is traced end to end. The reply goes back to Slack through `chat.postMessage`. Epic 27 runs now (owner, 2026-11-16) in Lane B's files. Each story's spec gate goes to the Contest Planner before it is built. Slack stays off on the online demo. Until the 1.0.12 merge-back, stories build and run CI on `OCT-epic27`. Stories 27.1 (route, `SlackIn`, link table) and 27.3 (admin linking in Settings, the approved texts) are delivered. Story 27.2 (replies) is last.

## Stories

- Story 27.1: Receive Slack events by webhook (done)
- Story 27.3: Link Slack members in Settings (done)
- Story 27.2: Reply as Slack messages, with no socket mode

## Requirements & Constraints

- **Binding Planner rulings (R1–R12) that 27.2 must keep:**
  - Only a plain direct message (`im`, no `subtype`, no `bot_id`) from a member linked under both `team_id` and member id becomes a turn. Our own replies come back as bot messages and must stay `Ignored`.
  - Nothing typed in Slack can answer an approval request. A Slack turn's session-start notes read `(slack)`.
  - Member ids and team ids are personal identifiers (R8). No trace, log, audit entry, message, `CommandResult` or status text may hold them. A link goes with its session.
  - Dummy `SLACK_*` values exist only in a unit's own `$tmp` compose override. `ci/compose.ci.yml` stays untouched, and a default throwaway answers 404 (R9).
  - No new role, resource or grant (R10).
  - One workspace per install: `^OcuTalonP.SlackW` holds the one `team_id`, noted from signed events.
- **Off switch:** `OcuTalon.Channel.Slack.In.On(demo = "")` is the single answer. It is 1 only when `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` are both non-empty and the online demo is off, and it is read at call time. Reuse it and never re-derive it.
- **Secrets:** environment only, read with `$SYSTEM.Util.GetEnviron` at use. The token is never put in a property, setting, row, global, message, trace, log line or status text. `.env.example` already lists both names. Slack has no `Data.Setting` key.
- **27.2's acceptance:**
  - A reply to a Slack turn goes to Slack and to the web chat, as the same plain text Telegram gets, and records a `Delivery` row.
  - Notifications and approval requests never go to Slack.
  - On a rate limit, wait the time Slack gives before retrying. A failure goes to Visual Trace with a plain reason, and the token is never logged.
  - No Slack code opens a WebSocket or uses socket mode, and CI proves it.
  - Tests run against a Slack mock in CI's mock service, with scenarios under `ci/mock/scenarios/B/`. Nothing calls slack.com.
  - A plain-English developer section covers creating the app, subscribing events on a public HTTPS address, the environment variables and linking a member. It claims nothing the release doesn't ship.
- **27.2's own duties:**
  - Setup step 1 gains `chat:write` in the same commit as the reply code. Step 1 is approved public text (R12), so the new wording is a Planner gate item. It sits word for word in three places: `GUIDE.md` `## Slack`, `EXPERIENCE.md` Later Steps › Step 7 (a planning artifact, so editing it stales this context), and `web/scripts/slack-setup-steps.test.mjs`. That test's step text and its two "names no chat:write" cases must flip.
  - `Msg/Catalog.cls` `CHANNELS` (`web,phone,mailbox,telegram,email`) refuses `slack` today. Raise it at the gate. `Test.Msg.Catalog.TestEveryKeyOnEveryChannel` pins the refused set `webhook,slack,system,heartbeat` and the channel loop. `CHANNELNAMES` (for `channel` slots) has no `slack` either.
- **Residual from 27.1/27.3:** Slack's `&amp;`/`&lt;`/`&gt;` escapes and `<@U…>` mention markup reach the turn text unchanged. 27.3 left the decision to 27.2: decode them, or record why not.
- **Ledger:**
  - DW-1454: a second workspace's signed event overwrites the noted one. By design under the one-workspace ruling.
  - DW-1284 (owner 26-4): any user with a session row can be linked, a viewer included, and `SlackIn` checks no role at use time. 27.2 replies to such a member too.

## Technical Decisions

- **Same-change spine rule.** `ARCHITECTURE-SPINE.md` is about 1,935 lines, so read it by line range only. Tag each AD amendment, run `memlog.py append` and `lint_spine.py`. Lint's 13 low `placeholder` findings were already there; add none. Already written:
  - the production-item row `SlackIn`/`SlackOut` (Lane B);
  - the AD-19 endpoint override `OCUTALON_SLACK_API_BASE`, "read only by `SlackOut`";
  - AD-14's Slack bullets (with the DW-1442 fixes), AD-1's three admin verbs, the Tables paragraph and the REST rows.
  27.2 must add: the `Notify` routing for Slack replies in AD-14, `SlackOut`'s behaviour, and a "mock's Slack side" bullet under AD-22's "mock as built" (as the POP3, SMTP and OAuth2 sides have).
- **Routing today (`Core/Rule/Notify.cls`, Lane B):**
  - `Conversation.Tell` already sends `Msg.Outbound` with `OriginChannel` = the turn's channel. The `Outbound` rule sends Telegram replies to `WebChatOut,TelegramOut` and everything else to `WebChatOut`, so a Slack reply reaches only the web chat now.
  - 24.3a/b are merged. The `Notification` rule now also routes kind `page` (`PageWeb`, `PageChannel`, plus the `DigestEmail`/`PageEmail` rules), but the `Outbound` rule is untouched. 27.2 adds one `when` to `Outbound` only, e.g. `OriginChannel="slack"` plus a Slack-on condition → `WebChatOut,SlackOut`. The `Notification` rules stay free of Slack.
  - Conditions call functions of `Core/Rule/Functions.cls`, whose names must be unique across every `Ens.Rule.FunctionSet` and never throw. `Test.Core.Routing` (`TestNotifyTargets`) is where the routing is pinned. Update `Notify`'s class doc.
- **The channel Out pattern (copy Lane A's Telegram; never edit or extract from it, U-177):**
  - `Channel/Telegram/Out.cls` extends `OcuTalon.Channel.Operation`, which gives `IsSession` and the warnings `LOGNOTASESSION`/`LOGPUBLISH`.
  - `OnOutbound` builds the text from `Text`, else `Catalog.Render(CatalogKey, Slots, channel)`. It then appends the check sentence (`CheckSentence`/`WhatFailed`, private, about 80 lines) and `Memory.Learned.Lines(..., channel)`. Both render with the channel, so the `CHANNELS` raise is needed for "the same text".
  - `Send` splits with `Api.Split` (4,096 UTF-16 units, at line breaks). `Post` retries a 429 after `retry_after` seconds (at least 1), up to `TRIES` = 5, and never resends a part that was sent.
  - `Recorded` writes `Data.Delivery.Record(sessionRef, "telegram", "<ChatRef>:<message_id>", ...)`. A failed record is one warning and the status stays OK.
  - `Channel/Telegram/Api.cls` is the one place that builds a request (`%Net.HttpRequest`, a new object per call, `FollowRedirect` 0, https → `SSLConfig` `OcuTalonClient`) and reads the token at call time. Every error text goes through `Safe`, which strips the exact token and then runs `Bridge.Redact`. `Endpoint` parses `http(s)://host[:port][/path]`.
  - Telegram's base is a host setting written by `Install.Step.Telegram`. Slack has no install step; AD-19 says `SlackOut` reads `OCUTALON_SLACK_API_BASE` itself, defaulting to Slack's public API.
- **How Slack differs (the plan must settle each):**
  - **Recipient:** the Slack Item carries only text: no member, channel or team id. `SlackOut` must find the session's member through `Data.SlackLink` (`SessionRefIndex` is unique). No method answers that yet; add one in the own file.
  - **R8 and Delivery:** `Delivery.Record` already accepts `slack` (Msg.Enum `CHANNEL`). `ChannelMessageId` (MAXLEN 128) must hold no member id.
  - **Text:** Slack reads `&`, `<` and `>` as markup in `text` and applies its own formatting. Say how the reply is escaped so it reads as Telegram's plain text, and the part size.
  - **Errors and limits:** Slack answers errors as `{"ok":false,"error":...}` and rate limits as HTTP 429 with a `Retry-After` header.
  - **`Msg.Notification`:** `SlackOut` should map only `Msg.Outbound`, so a Notification cannot be sent even if misrouted.
- **Production:**
  - Add `SlackOut` (`OcuTalon.Channel.Slack.Out`) in the lane B region of `Production.cls`, beside `SlackIn` (PoolSize 0, Enabled true, with the `On()` gate as precedent).
  - Add its row to the oracle in `Test/Core/ProductionItems.cls`.
- **CI mock (`ci/mock/`, Lane B; the hosted `web` job runs `mock`):**
  - It serves Telegram's Bot API (`/bot<token>/<method>`, `/_mock/telegram/{updates,replies,calls,files,reset}`, the token logged by length only), and scenario match type `telegram` (`BOT_METHODS`, replies `{status, headers, delayMs, body}`).
  - Slack has no path, match type or scenario yet. Add a Slack Web API side (`chat.postMessage` with a bearer token logged by length only, a calls log, queued replies, reset), a `slack` match type in `scenarios.mjs`, `ci/mock/test/` cases and `B/` scenarios (ok, 429 with `Retry-After`, an error).
  - `OCUTALON_SLACK_API_BASE=http://mock:8080` goes in the unit's `$tmp` override with the dummy `SLACK_*` values (R9). `live:slack-hook` (`docker/tests/test-slack-hook.sh`, `shards-3`, about 373 s) is the live unit to extend.
- **No socket mode:** no existing check covers it. Add one to a hermetic check script, such as `test-class-rules.sh` or `test-boundaries.sh`.
- **Ownership (AD-29, AD-33):** `Notify`, `Functions`, `Delivery`, `SlackLink`, `Msg.Catalog`, `ci/` except `scenarios/A/`, `README.md` and `GUIDE.md` are Lane B's. Telegram's classes are Lane A's (read only). New items go into the ownership tables in the same change.

## UX & Interaction Patterns

- **Plain text only:** no Markdown, and the same words Telegram gets.
- **Web chat:** the web chat already shows the reply and the "via Slack" caption (27.3). No new web text is planned.
- **Setup steps:** a changed step 1 is public text and needs the author's acceptance, so ship no unruled sentence.
- **Developer docs:** the README is judge-facing and fully pinned by `docker/tests/test-readme.sh`:
  - an exact H2 list, a 2,300-word cap (now 2,230), and a ruled "More" paragraph that must link every `GUIDE.md` H2;
  - no class names outside the guide's "For admins and developers" and "Gmail and Microsoft 365" sections;
  - "How you talk to it" never names Slack.
  Install and admin material moved to `GUIDE.md` (Story 0.30), so where "a README developer section" lives is a gate question.
- **Known red:** `test-readme.sh` rule `guide` fails on the current HEAD (in `CHECK_SCRIPTS`). 27.3 added `## Slack` to `GUIDE.md`, but `GUIDE_H2` and the README's More paragraph don't name it.

## Cross-Story Dependencies

- **27.1 and 27.3 → 27.2:**
  - `SlackOut` replies to `SlackIn`'s turns. R1's `bot_id` guard already ignores the echoes.
  - The developer section's linking part describes 27.3's Settings › Channels › Slack group and `GUIDE.md` › Slack.
- **Notify:** 24.3's `page` routing is merged into this branch, so 27.2's edit is no longer contended with it. Keep the Notification rules exactly as they are.
- **Epic 28:** Story 28.1 (Lane A) waits for Epic 27 to merge, for the `DraftTransform` verb. 28.2 is integrated here.
- **Demo host:** its proxy blocks the webhook path, and Slack stays off there.
