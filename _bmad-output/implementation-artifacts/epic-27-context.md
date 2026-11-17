# Epic 27 Context: Slack (step 7, Could)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make Slack a working OcuTalon channel without socket mode (the platform's WebSocket client fails right after opening). Slack's Events API posts to a route under `/ocutalon/hook`. A direct message from a linked Slack member becomes a normal user turn: it gets an attention decision, shows in the web chat "via Slack" and is traced end to end. The reply goes back to Slack through `chat.postMessage`. It runs in Lane B's files, and each spec gate goes to the Contest Planner before building. Slack stays off on the online demo. Until the 1.0.12 merge-back, stories build and run CI on `OCT-epic27`. Stories 27.1 (route, `SlackIn`, link table) and 27.3 (admin linking in Settings, the approved texts, and a rework so that a Slack turn needs a user who may chat) are delivered. Story 27.2 (replies) is last, and the Planner has approved its gate (rulings 1–5).

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
- **Only accepted turns get a reply (27.3 rework, AD-14):** `Core.Conversation` (production job, channel `slack` only) takes a Slack Item only when `Conversation.MayChat(irisUser)` (`Bridge.Approval.RolesOf` + `Web.Public.Shell.MayChat(roles)`) is 1. A refused Item leaves one content-free `Channel.Slack.Ignored` (reason `not_user`), no Turn and no `Outbound`, so it gets no reply. `SlackOut` adds no role check. Linking offers only users who may chat.
- **Off switch:** `OcuTalon.Channel.Slack.In.On(demo = "")` is the single answer. It is 1 only when `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` are both non-empty and the online demo is off, and it is read at call time. Reuse it and never re-derive it.
- **Secrets:** environment only, read with `$SYSTEM.Util.GetEnviron` at use. The token is never put in a property, setting, row, global, message, trace, log line or status text. `.env.example` already lists both names. Slack has no `Data.Setting` key.
- **27.2's acceptance:**
  - A reply to a Slack turn goes to Slack and to the web chat, as the same plain text Telegram gets, and records a `Delivery` row.
  - Notifications and approval requests never go to Slack.
  - On a rate limit, wait the time Slack gives before retrying. A failure goes to Visual Trace with a plain reason, and the token is never logged.
  - No Slack code opens a WebSocket or uses socket mode, and CI proves it.
  - Tests run against a Slack mock in CI's mock service, with scenarios under `ci/mock/scenarios/B/`. Nothing calls slack.com.
  - `GUIDE.md` › Slack, linked from the README, gives a plain-English developer section: creating the app, subscribing events on a public HTTPS address, the environment variables and linking a member. It claims nothing the release doesn't ship.
- **27.2 gate rulings (Contest Planner, binding):**
  - (1) Step 1 (`im:history`, `chat:write`) and SlackOut's 8 Visual Trace texts are approved verbatim. Condition: each `{reason}`/`{status}`/`{code}` slot holds only a fixed reason word or Slack's error code, never an id, message text or token (pinned by the token-strip test).
  - (2) Only `chat.postMessage`, to the linked member of an accepted turn, once per part. `mrkdwn`/unfurls are off, `&<>` escaped, parts ≤ 4,000 characters, `Retry-After` ≤ 30 s, ≤ 5 tries, and no sent part resent. The token is header only and stripped from errors, and `Delivery` holds `Ref:ts` only. On the demo both `Notify` and `SlackOut` refuse (pinned). Also approved: the no-socket-mode rule, the mock's Slack side and scenarios, and zero posts for a refused turn, pinned in `live:slack-hook`.
  - (3) Decode inbound markup, with no A/B. Tests pin the decode table (entities, mentions, links, channel references).
  - (4) The developer section is `GUIDE.md` › Slack, and no README sentence is added.
  - (5) Approved spine edits: AD-14, AD-19, AD-22, AD-32, and the Deferred row moved out. If AD-22 overlaps Story 0.39, whichever lands second rebases.
- **27.2's own duties:**
  - Setup step 1 gains `chat:write` in the same commit as the reply code, word for word in three places: `GUIDE.md` `## Slack`, `EXPERIENCE.md` Later Steps › Step 7 (a planning artifact, so editing it stales this context), and `web/scripts/slack-setup-steps.test.mjs`. That test's step text and its two "names no chat:write" cases flip.
  - `Msg/Catalog.cls` `CHANNELS` (`web,phone,mailbox,telegram,email`) gains `slack` (AD-32, ruling 5). `Test.Msg.Catalog.TestEveryKeyOnEveryChannel`'s refused set (`webhook,slack,system,heartbeat`) and channel loop change with it. `CHANNELNAMES` (for `channel` slots) has no `slack`.
- **Residual from 27.1/27.3:** `&amp;`/`&lt;`/`&gt;` and `<@U…>` markup still reach the turn text; decode them (ruling 3).
- **Ledger:**
  - DW-1454: a second workspace's signed event overwrites the noted one. By design under the one-workspace ruling.
  - DW-1284, DW-1465 (`MayChat` ignores a disabled or expired account) and DW-1466 (no Core-to-Web reference in the spine) went to lane D's Story 0.38. It extends `MayChat`, moves the predicate into Core and moves `not_user` to a channel-neutral `Channel.Refused`. Keep 27.2 out of `Conversation`'s gate and build nothing on that record.

## Technical Decisions

- **Same-change spine rule.** `ARCHITECTURE-SPINE.md` is about 1,935 lines, so read it by line range only. Tag each AD amendment, run `memlog.py append` and `lint_spine.py`. Lint's 13 low `placeholder` findings were already there; add none. Already written:
  - the production-item row `SlackIn`/`SlackOut` (Lane B);
  - the AD-19 endpoint override `OCUTALON_SLACK_API_BASE`, "read only by `SlackOut`";
  - AD-14's Slack bullets (with the DW-1442 fixes and the `not_user` sentence), AD-1's three admin verbs, the Tables paragraph and the REST rows.
  27.2 adds the ruling-5 edits, including a "mock's Slack side" bullet under AD-22's "mock as built".
- **Routing today (`Core/Rule/Notify.cls`, Lane B):**
  - `Conversation.Tell` already sends `Msg.Outbound` with `OriginChannel` = the turn's channel. The `Outbound` rule sends Telegram replies to `WebChatOut,TelegramOut` and everything else to `WebChatOut`, so a Slack reply reaches only the web chat now.
  - 24.3's `page` routing changed only the `Notification` rules, which stay free of Slack. 27.2 adds one `when` to `Outbound`, e.g. `OriginChannel="slack"` plus a Slack-on condition → `WebChatOut,SlackOut`.
  - Conditions call `Core/Rule/Functions.cls` functions (names unique across every `Ens.Rule.FunctionSet`, never throwing). `Test.Core.Routing` (`TestNotifyTargets`) pins routing. Update `Notify`'s class doc.
- **The channel Out pattern (copy Lane A's Telegram; never edit or extract from it, U-177):**
  - `Channel/Telegram/Out.cls` extends `OcuTalon.Channel.Operation`, which gives `IsSession` and the warnings `LOGNOTASESSION`/`LOGPUBLISH`.
  - `OnOutbound` builds the text from `Text`, else `Catalog.Render(CatalogKey, Slots, channel)`. It then appends the check sentence (`CheckSentence`/`WhatFailed`, private, about 80 lines) and `Memory.Learned.Lines(..., channel)`. Both render with the channel, so the `CHANNELS` raise is needed for "the same text".
  - `Send` splits with `Api.Split` (4,096 UTF-16 units, at line breaks). `Post` retries a 429 after `retry_after` seconds (at least 1), up to `TRIES` = 5, and never resends a part that was sent.
  - `Recorded` writes `Data.Delivery.Record(sessionRef, "telegram", "<ChatRef>:<message_id>", ...)`; a failed record is one warning, status OK.
  - `Channel/Telegram/Api.cls` alone builds requests (a new `%Net.HttpRequest` per call, `FollowRedirect` 0, https → `SSLConfig` `OcuTalonClient`) and reads the token at call time. `Safe` strips the exact token from every error text, then runs `Bridge.Redact`. `Endpoint` parses `http(s)://host[:port][/path]`.
  - Telegram's base is an install-step host setting. Slack has none: `SlackOut` reads `OCUTALON_SLACK_API_BASE` itself, defaulting to Slack's public API.
- **How Slack differs:**
  - **Recipient:** the Slack Item carries only text. `SlackOut` finds the session's member through `Data.SlackLink` (`SessionRefIndex` is unique). No method does that yet, so add one in the own file.
  - **R8 and Delivery:** `Delivery.Record` already accepts `slack`. `ChannelMessageId` (MAXLEN 128) holds no member id.
  - **Text and errors:** Slack reads `&`, `<`, `>` as markup, so escape them as ruled. Errors come back as `{"ok":false,"error":...}` and rate limits as 429 with `Retry-After`.
  - **`Msg.Notification`:** `SlackOut` maps only `Msg.Outbound`, so it can never send a Notification, even a misrouted one.
- **Production:**
  - Add `SlackOut` (`OcuTalon.Channel.Slack.Out`) in the lane B region of `Production.cls`, beside `SlackIn` (PoolSize 0, Enabled true, with the `On()` gate as precedent).
  - Add its row to the oracle in `Test/Core/ProductionItems.cls`.
- **CI mock (`ci/mock/`, Lane B; the hosted `web` job runs `mock`):**
  - It serves Telegram's Bot API (`/bot<token>/<method>`, `/_mock/telegram/{updates,replies,calls,files,reset}`, token logged by length only) and match type `telegram` (replies `{status, headers, delayMs, body}`). Slack has nothing yet. Add a Slack Web API side (`chat.postMessage` with a bearer token logged by length only, a calls log, queued replies, reset), a `slack` match type in `scenarios.mjs`, `ci/mock/test/` cases and `B/` scenarios (ok, 429 with `Retry-After`, an error).
  - `OCUTALON_SLACK_API_BASE=http://mock:8080` goes in the unit's `$tmp` override with the dummy `SLACK_*` values (R9). `live:slack-hook` (`docker/tests/test-slack-hook.sh`, `shards-3`, about 373 s) is the live unit to extend.
- **No socket mode:** no existing check covers it. Add the approved boundary rule to `test-boundaries.sh`, not `test-class-rules.sh`, which `OCT-epic28` edits.
- **Ownership (AD-29, AD-33):** `Notify`, `Functions`, `Delivery`, `SlackLink`, `Msg.Catalog`, `ci/` except `scenarios/A/`, `README.md` and `GUIDE.md` are Lane B's. Telegram's classes are Lane A's (read only). New items go into the ownership tables in the same change.

## UX & Interaction Patterns

- **Plain text only:** no Markdown, and the same words Telegram gets.
- **Web chat:** the web chat already shows the reply and the "via Slack" caption (27.3). No new web text is planned.
- **Setup steps:** step 1 with `chat:write` is approved (ruling 1). Ship no other unruled sentence.
- **Developer docs:** the README is judge-facing and fully pinned by `docker/tests/test-readme.sh`:
  - an exact H2 list, a 2,300-word cap (now 2,235), and a ruled "More" paragraph that must link every `GUIDE.md` H2;
  - no class names outside the guide's "For admins and developers" and "Gmail and Microsoft 365" sections;
  - "How you talk to it" never names Slack.
  So, by ruling 4, the README is not edited.
- **README checks are green:** `GUIDE_H2` has `Slack` and the More paragraph links `GUIDE.md#slack`.

## Cross-Story Dependencies

- **27.1 and 27.3 → 27.2:**
  - `SlackOut` replies only to `SlackIn`'s accepted turns. R1's `bot_id` guard already ignores the echoes.
  - Phase 7 of `live:slack-hook` and `Test.Core.ConversationNotUser` pin the refusal; extended, it must log no `chat.postMessage` for it.
  - The developer section's linking part describes 27.3's Settings › Channels › Slack group and `GUIDE.md` › Slack.
- **Notify:** 24.3's `page` routing is merged here, so 27.2's edit is uncontended. Keep the Notification rules as they are.
- **Epic 28:** Story 28.1 (Lane A) waits for Epic 27 to merge, for the `DraftTransform` verb. 28.2 is integrated here.
- **Integrated from feature:** 25.9 (`SettingsOps`) and DW-1421 round 3 (bridge `Decide`, `DecisionPayload`).
- **Demo host:** its proxy blocks the webhook path, Slack stays off there, and `Notify` and `SlackOut` both refuse.
