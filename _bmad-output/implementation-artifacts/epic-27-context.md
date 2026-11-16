# Epic 27 Context: Slack (step 7, Could)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make Slack a working OcuTalon channel without socket mode. Slack's Events API posts to a Slack route under the existing `/ocutalon/hook` application. A direct message from a Slack member that an admin linked to an OcuTalon user becomes a normal user turn: it gets an attention decision, shows in the web chat and is traced end to end. The reply goes back as a Slack message through `chat.postMessage`. Socket mode is ruled out: the platform's WebSocket client fails right after opening. Per the owner (2026-11-16), Epics 27 and 28 start now, Epic 27 first, in Lane B's files. Each story's spec gate goes to the Contest Planner before it is built. Slack stays off on the online demo. Until the 1.0.12 merge-back, the stories build and run CI on their own branch. Story 27.1 was split on 2026-11-16: 27.1 receives events and reads the stored member link, 27.3 writes the link and ships the Settings texts and UI, 27.2 is the reply path. Order: 27.1, 27.3, 27.2.

## Stories

- Story 27.1: Receive Slack events by webhook
- Story 27.3: Link Slack members in Settings
- Story 27.2: Reply as Slack messages, with no socket mode

## Requirements & Constraints

- **Inbound security (27.1):**
  - Verify Slack's signature over the timestamp and raw body in constant time; a missing or wrong signature or stale timestamp gets 401, recorded at a capped rate.
  - Answer the URL-verification challenge. Acknowledge each valid event within 3 seconds and decide afterwards. A retried event is processed once, keyed by its event id.
- **What becomes a turn (27.1):** only a direct message to the bot from a Slack member with a stored link to an OcuTalon user. It becomes a turn in that user's session with provenance `user` and channel `slack`, joined to the session's daily thread. 27.1 defines and reads the stored link; it adds no way to write one.
- **Everything else is trace-only.** Another member, a channel message or an unhandled event type is recorded in Visual Trace only: no decision, no reply, nothing about any session.
- **Off switch:** with no Slack token set, or on the online demo, Slack is off, nothing Slack-related runs and every other feature still works.
- **Secrets:** the signing secret and the bot token come only from environment variables, listed by name in `.env.example`. Neither ever appears in IRIS, a setting, a log, a message, an agent step or an audit entry, and `SlackOut` never logs the token.
- **Linking (27.3):** scope named at the split:
  - admin-only link and unlink through `SettingsOps`, each with an audit entry, behind an admin REST route;
  - links kept and purged with their session (AD-27's `Data.Purge`);
  - Settings > Channels shows Slack's state (on or off) and the linking, as a lazy chunk;
  - the catalog keys, and the "via Slack" marker on web-chat turns.
- **Outbound (27.2):**
  - A reply to a Slack turn goes to Slack and to the web chat. It is the same plain text Telegram gets, and it records a `Delivery` row.
  - Notifications and approval requests never go to Slack. They stay on the web chat, the simulated phone and the paired Telegram chat.
  - When Slack rate-limits a post, wait the time Slack gives before retrying. Any failure is recorded in Visual Trace with a plain reason.
- **Texts:** 27.1 ships no user-facing text; it proposes the step 7 texts (Slack's state and member linking in Settings, and the setup steps) at its spec gate. 27.3 proposes them to the author as additions to `EXPERIENCE.md` (Message Catalog and Later Steps), puts their keys in `OcuTalon.Msg.Catalog.Core` and ships them. No story ships a text the author hasn't accepted.
- **Tests:**
  - IRIS tests in `OcuTalon.Test.Channel` post signed fixtures (valid, unsigned, stale, retried, unlinked); only the valid linked direct message becomes a turn, exactly once.
  - Slack API tests run against a Slack mock in CI's mock service, with scenarios under `ci/mock/scenarios/B/`, never against real Slack. CI must show that no Slack code opens a WebSocket or uses socket mode.
- **README (27.2):** a plain-English developer section on creating the Slack app, subscribing its events to the Slack route on a public HTTPS address, setting the environment variables and linking a member. It claims nothing the release doesn't ship, which is why 27.3 comes first.

## Technical Decisions

- **Spine updates in each story's own change** (same-change rule; `ARCHITECTURE-SPINE.md` is large, so read it by section). Today the spine only calls Slack "one more channel pair"; the `Channel` enumeration already holds `slack`.
  - 27.1 adds `SlackIn` and `SlackOut` to the production-item table (Lane B), the Slack route under `/ocutalon/hook`, the Slack setting keys, the Slack API endpoint override for CI, and the stored member link that `SlackIn` reads.
  - 27.3 adds how an admin links a Slack member to an OcuTalon user.
- **Channel pattern:**
  - The pair is an inbound service plus an outbound operation, named `<Channel>In` and `<Channel>Out`. Every inbound message becomes an `OcuTalon.Msg.Item`. User-written text has provenance `user`; anything else is `untrusted`. Only business operations send outbound traffic.
  - Telegram (`OcuTalon.Channel.Telegram.In`, `.Out`, `.Api`, Lane A's) is the sibling to copy, not edit. It builds calls with `%Net.HttpRequest`, keeps the API base URL as an override, records state through `StatusMark` and keeps chat ids out of logs and audit.
- **Hook application** (Story 35.3; dispatch class `OcuTalon.Web.Hook`):
  - Unauthenticated, no session, minimal `OcuTalonWebhook` role; not created on an online-demo install. Its one route is `POST /<ref>` (else 404); the Slack route must not collide with it.
  - A valid event goes through an adapterless service (`CreateBusinessService` and `ProcessInput` in the request's process), which sends asynchronously and returns before any decision. Slack's 3-second acknowledgement follows the same shape.
  - `Data.Webhook.HashSecret`/`Matches` are named as available to the Slack route.
- **Commands (AD-1):**
  - 27.1 creates the verb `OcuTalon.Msg.Command.DraftTransform`, carrying the incident's `IncidentRef`, under the name Lane A's Story 28.1 fixes. `CommandsIn` routes it to Lane A's `IncidentManager`, from origin `tool` only and only for one of the session's own incidents, so AD-1's tool-origin list gains it. It is submitted only through `Core.Commands.Submit`.
  - 27.3's link and unlink follow the admin-settings precedent (`CreateWebhook`): verbs from origin `web_admin` only, routed to `SettingsOps`, no tool verb. A Slack sender is never an origin for governance commands.
- **Admin reads and personal data (AD-24):** the web process never reads product storage directly (CI rule `web-global-reads`). A read beyond the caller's own rows, such as the list of OcuTalon users to link, goes through a read verb to `SettingsOps`, and a list that names IRIS users comes back through `SecretHandoff`, never in a traced message. Admin routes sit under `/api/v1/settings/channels/`, forwarded from `Web.Api`; Settings sections ship as lazy chunks (Settings > Roles is the precedent).
- **Outbound routing (AD-14, AD-32):** `Conversation` sends the reply (`OcuTalon.Msg.Outbound` with `OriginChannel`) to `OcuTalon.Core.Rule.Notify`, which routes on `Kind` and the session's channels to the turn's channel plus the web chat. Producers never render text. `SlackOut` records delivery through `OcuTalon.Data.Delivery.Record(ownerRef, channel, channelMessageId, approvalRef)`.
- **Secrets and config (AD-19):** tokens come only from the environment (`@{env:VAR}` or `$SYSTEM.Util.GetEnviron`). Endpoint overrides are fixed optional environment variables set only by CI and the demo deployment (today `OCUTALON_MODEL_BASE_URL`, `OCUTALON_EXTRA_CA_FILE`, `OCUTALON_TELEGRAM_API_BASE`); Slack's joins them.
- **Audit (AD-17):** `OcuTalon.Bridge.Audit` is the only writer. Capped rejections: one `Action` entry per 60 s per target, with no secret, header, body or caller address.
- **Visual Trace (AD-26):** a turn joins the session's daily thread through `Core.Trace.Join`, called only by channel services at a turn's start; the service sets `%SessionId` and `%SuperSession` in `OnProcessInput` before its first send. An ignored event still needs its own trace record.
- **CI mock (AD-22):** Node standard library in `ci/compose.ci.yml`, reached through the endpoint override. Telegram's side (queued replies per method, recorded calls, token logged by length only) is the model for Slack's. `OcuTalon.Test.Channel` runs in the `lane-a` shard.
- **Ownership (AD-29, AD-33):** Slack's items, tables and texts are Lane B's; new items or tables go into the ownership tables in the same change.

## UX & Interaction Patterns

- **Web chat:** every turn shows there, and turns from another channel carry a marker ("via Telegram" today). 27.3 adds "via Slack".
- **Settings:** admins only; non-admins don't see the link. Settings > Channels already groups Email and Webhooks; Slack's group, state line and linking texts are not yet specified, so propose them.
- **Plain text only:** no Markdown; Slack replies use the text Telegram gets.

## Cross-Story Dependencies

- **27.1 → 27.3 → 27.2:** 27.3 needs 27.1's route, `SlackIn` and the stored link; 27.2 needs the channel, settings keys and spine rows from 27.1, and its README's linking section describes 27.3's shipped behaviour. 27.1 ships before any admin writer exists, so its tests must set up links themselves.
- **Epic 35 (Lane B, merged):** provides the `/ocutalon/hook` application, `Web.Hook`, `Web.HookSettings`, `Data.Webhook` and `Core.SecretHandoff`.
- **Epic 28:** Story 28.1 (Lane A) fixes the `DraftTransform` name and waits on Epic 27 for its chat path. 28.1's spine update and 27.1's verb must agree on name, payload, origin and routing.
- **Shared Notify:** 27.2 edits `Core.Rule.Notify`, contended with Story 24.3's `page` routing, which is held in another lane; serialize the two.
- **Demo host:** its proxy blocks the webhook path; the Contest Planner's demo-host checks cover that.
