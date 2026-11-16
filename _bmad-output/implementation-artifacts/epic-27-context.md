# Epic 27 Context: Slack (step 7, Could)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make Slack a working OcuTalon channel without socket mode. Slack's Events API posts to a Slack route under the existing `/ocutalon/hook` application. A direct message from a linked Slack member becomes a normal user turn: it gets an attention decision, shows in the web chat and is traced end to end. The reply goes back as a Slack message through `chat.postMessage`. Socket mode is ruled out because the platform's WebSocket client fails right after opening. Step 7 had been moved to after the contest. The owner reversed that on 2026-11-16: Epics 27 and 28 start now, Epic 27 first, in Lane B's files. Each story's spec gate goes to the Contest Planner before it is built. Slack stays off on the online demo. Until the 1.0.12 merge-back, the stories build and run CI on their own branch.

## Stories

- Story 27.1: Receive Slack events by webhook
- Story 27.2: Reply as Slack messages, with no socket mode

## Requirements & Constraints

- **Inbound security:**
  - Verify Slack's request signature over the timestamp and the raw body, in constant time.
  - A missing or wrong signature, or a stale timestamp, gets 401. Rejections are recorded at a capped rate.
  - Answer Slack's URL-verification challenge.
  - Acknowledge each valid event within 3 seconds and decide afterwards.
  - A retried event is processed once, keyed by its event id.
- **What becomes a turn:** only a direct message to the bot from a Slack member that an admin linked to an OcuTalon user. It becomes a turn in that user's session with provenance `user` and channel `slack`, joined to the session's daily thread.
- **Everything else is trace-only.** Another member, a channel message or an unhandled event type is recorded in Visual Trace and goes no further: no decision, no reply, and nothing about any session.
- **Off switch:** with no Slack token set, or on the online demo, Slack is off, nothing Slack-related runs and every other feature still works. On the demo the proxy blocks the webhook path anyway.
- **Secrets:**
  - The signing secret and the bot token come only from environment variables, listed by name in `.env.example`.
  - Neither ever appears in IRIS, a setting, a log, a message, an agent step or an audit entry.
  - `SlackOut` never logs the token.
- **Outbound:**
  - A reply to a Slack turn goes to Slack and to the web chat. It is the same plain text Telegram gets, and it records a `Delivery` row.
  - Notifications and approval requests never go to Slack. They stay on the web chat, the simulated phone and the paired Telegram chat.
  - When Slack rate-limits a post, wait the time Slack gives before retrying.
  - Any failure is recorded in Visual Trace with a plain reason.
- **Texts:** Slack's channel state and member linking in Settings, and the setup steps, have no UX text yet.
  - Propose them to the author as additions to `EXPERIENCE.md` (Message Catalog and Later Steps).
  - Their keys go in `OcuTalon.Msg.Catalog.Core`.
  - No story ships a text the author hasn't accepted.
- **Tests:**
  - IRIS tests go in `OcuTalon.Test.Channel`, posting signed fixture requests. Valid, unsigned, stale, retried and unlinked events are all posted, and only the valid linked direct message becomes a turn, exactly once.
  - Slack API tests run against a Slack mock in CI's mock service, with scenarios under `ci/mock/scenarios/B/`, never against real Slack.
  - CI must show that no Slack code opens a WebSocket or uses socket mode.
- **README:** a plain-English developer section on four things: creating the Slack app, subscribing its events to the Slack route on a public HTTPS address, setting the environment variables and linking a member. It claims nothing the release doesn't ship.

## Technical Decisions

- **Spine update in 27.1's own change** (same-change rule; the spine is `ARCHITECTURE-SPINE.md`, large, so read it by section). Add:
  - `SlackIn` and `SlackOut` to the production-item table, owned by Lane B;
  - the Slack route under `/ocutalon/hook`;
  - the Slack setting keys;
  - the Slack API endpoint override for CI;
  - how an admin links a Slack member to an OcuTalon user.

  Today the spine only says Slack is "one more channel pair" under the channel rules, and the `Channel` enumeration already holds `slack`.
- **Channel pattern:**
  - The pair is an inbound service plus an outbound operation, named `<Channel>In` and `<Channel>Out`. Every inbound message becomes an `OcuTalon.Msg.Item`.
  - User-written text has provenance `user` and reaches the model as a user message. Anything else is `untrusted`.
  - Only business operations send outbound traffic.
  - Telegram (`OcuTalon.Channel.Telegram.In`, `.Out`, `.Api`) is the sibling to copy. It builds calls with `%Net.HttpRequest` in OcuTalon code, takes the token from the environment and keeps the API base URL as an override. It records state through `StatusMark` and keeps chat ids out of logs and audit.
  - Telegram's classes are Lane A's. Copy the pattern; don't edit them.
- **Hook application** (built by Story 35.3; dispatch class `OcuTalon.Web.Hook`):
  - It is unauthenticated, with no session and the minimal `OcuTalonWebhook` role.
  - Its one route today is `POST /<ref>`, and every other path answers 404.
  - It is not created on an online-demo install.
  - A valid webhook event goes through an adapterless service (`CreateBusinessService` and `ProcessInput` in the request's process), which sends asynchronously and returns before any decision. Slack's 3-second acknowledgement follows the same shape.
  - The Slack route must not collide with the `/<ref>` route.
  - `Data.Webhook.HashSecret`/`Matches` are named as available to the Slack route.
- **Commands (AD-1):**
  - 27.1 creates the command verb `OcuTalon.Msg.Command.DraftTransform`, carrying the incident's `IncidentRef`. It uses the name Lane A's Story 28.1 fixes.
  - `CommandsIn` routes it to Lane A's `IncidentManager`. It is accepted from origin `tool` only, and only for one of the session's own incidents, so AD-1's list of tool-origin verbs gains it.
  - The verb is submitted only through `Core.Commands.Submit`. The governance tests expect origin checks to hold.
  - A Slack sender is never an origin for governance commands.
- **Outbound routing (AD-14, AD-32):**
  - `Conversation` sends the reply (`OcuTalon.Msg.Outbound` with `OriginChannel`) to `OcuTalon.Core.Rule.Notify`, which routes on `Kind` and the session's channels.
  - A reply goes to its turn's channel and to the web chat.
  - Producers never render text.
  - `SlackOut` records delivery through `OcuTalon.Data.Delivery.Record(ownerRef, channel, channelMessageId, approvalRef)`.
- **Secrets and config (AD-19):**
  - Bot tokens come only from the environment (`@{env:VAR}` or `$SYSTEM.Util.GetEnviron`).
  - Endpoint overrides are fixed optional environment variables set only by CI and the demo deployment. Today the list is `OCUTALON_MODEL_BASE_URL`, `OCUTALON_EXTRA_CA_FILE` and `OCUTALON_TELEGRAM_API_BASE`, and Slack's override joins it.
- **Audit (AD-17):**
  - `OcuTalon.Bridge.Audit` is the only writer.
  - The webhook's capped-rejection precedent is one `Action` entry per 60 s per target. It holds no secret, header, body or caller address.
- **Visual Trace (AD-26):**
  - A turn joins the session's daily thread through `Core.Trace.Join`, which only channel services call, at the start of a turn.
  - The joining service sets `%SessionId` and `%SuperSession` in `OnProcessInput` before its first send.
  - An ignored event still needs its own trace record.
- **CI mock (AD-22):**
  - It runs on Node's standard library in `ci/compose.ci.yml`, reached through the endpoint override.
  - Telegram's side (`match: telegram`, queued replies per method, recorded calls, token logged by length only) is the model for a Slack API side.
  - The `OcuTalon.Test.Channel` area runs in the `lane-a` shard.
- **Ownership (AD-29, AD-33):**
  - Slack's items, tables and texts are Lane B's.
  - Any new item or table goes into the ownership tables in the same change.
  - A Lane B story that needs Telegram behaviour is paired with a Lane A story.

## UX & Interaction Patterns

- **Web chat:** every turn shows there, and turns from another channel carry a "via Telegram"-style marker. Slack's marker and Slack's Settings › Channels texts are not yet specified, so propose them.
- **Plain text only:** outbound messages are plain text with no Markdown, and Telegram and the simulated phone share each text exactly. Slack replies use the text Telegram gets.

## Cross-Story Dependencies

- **27.1 before 27.2:** 27.2 needs the channel, linking, settings keys and spine rows that 27.1 adds.
- **Epic 35 (Lane B):** provides the `/ocutalon/hook` application, `Web.Hook`, `Web.HookSettings`, `Data.Webhook` and `Core.SecretHandoff`. It is merged.
- **Epic 28:**
  - Story 28.1 (Lane A) fixes the `DraftTransform` name and waits on Epic 27 for its chat path.
  - 28.1's spine update and 27.1's creation of the verb must agree on name, payload, origin and routing.
- **Shared Notify:** 27.2 edits the shared routing rule `Core.Rule.Notify`. Sprint planning flagged it as contended with Story 24.3's `page` routing, which is held in another lane, so serialize the two.
- **Demo host:** the proxy blocks the webhook path. The Contest Planner's checks on the demo host cover that.
