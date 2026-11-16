# Epic 27 Context: Slack (step 7, Could)

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Make Slack a working OcuTalon channel without socket mode, because the platform's WebSocket client fails right after opening. Slack's Events API posts to a Slack route under the existing `/ocutalon/hook` application. A direct message from a linked Slack member becomes a normal user turn: it gets an attention decision, shows in the web chat and is traced end to end. The reply goes back through `chat.postMessage`. Epics 27 and 28 start now (owner, 2026-11-16), Epic 27 first, in Lane B's files. Each story's spec gate goes to the Contest Planner before it is built. Slack stays off on the online demo. Until the 1.0.12 merge-back, stories build and run CI on `OCT-epic27`. Story 27.1 is delivered: the route, `SlackIn` and the stored member link. Next is 27.3 (linking and the Settings texts), then 27.2 (replies).

## Stories

- Story 27.1: Receive Slack events by webhook (done)
- Story 27.3: Link Slack members in Settings
- Story 27.2: Reply as Slack messages, with no socket mode

## Requirements & Constraints

- **Binding Planner rulings from 27.1 that later stories must keep:**
  - R1: only a plain direct message to the bot from a linked member becomes a turn: `channel_type` `im`, no `subtype`, no `bot_id`. Bot messages, including our own replies once 27.2 lands, and edits each leave one content-free `Ignored` record.
  - R2: a link matches only when both `team_id` and the member id match.
  - R3: the signature is checked before `url_verification`.
  - R4: the route answers within 3 s and a retry is deduped by event id.
  - R5: a rejected request stores nothing from its body. R6: nothing typed in Slack can answer an approval request.
  - R7: a Slack turn's session-start notes read `(slack)`.
  - R8: member ids and team ids are personal identifiers. No trace, log, audit entry or message carries them, and links go with their session.
  - R9: dummy `SLACK_*` values exist only in a unit's own throwaway, through a `$tmp` compose override. `ci/compose.ci.yml` stays untouched, and a default throwaway answers 404.
  - R10: no new role, resource or grant.
  - R11 and R12: the approved veto items, AD amendments and public texts.
- **Off switch:** Slack is on only when both `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` are non-empty and the online-demo flag is off. `OcuTalon.Channel.Slack.In.On(demo = "")` is the single source of that answer, read at call time. When Slack is off, the route answers 404 like an unknown path. Settings must show Slack's state from `On()`, never from its own check.
- **Secrets:** environment only, read with `$SYSTEM.Util.GetEnviron` at use. They are never stored, put in a setting, logged, audited, traced or shown. `.env.example` already lists both names, empty. Slack has no `Data.Setting` key, and none may be added.
- **Linking (27.3):**
  - Only admins can link and unlink, through `SettingsOps` commands. Each writes an audit entry, behind an admin REST route.
  - Settings > Channels shows Slack's state and the linking, as a lazy chunk.
  - Ships the catalog keys and the "via Slack" marker.
  - Decides whether a Slack-linked session is kept by the purge's `Keeps`.
  - Carries the spine edit on how an admin links a member.
- **Outbound (27.2):**
  - A reply to a Slack turn goes to Slack and to the web chat, as the same plain text Telegram gets, and records a `Delivery` row.
  - Notifications and approval requests never go to Slack.
  - On a rate limit, wait the time Slack gives before retrying. Failures go to Visual Trace with a plain reason, and the token is never logged.
  - No WebSocket or socket mode, which CI proves. Tests run against a Slack mock under `ci/mock/scenarios/B/`.
  - 27.2 adds `chat:write` to setup step 1 in the same commit as the reply code, and raises `Msg/Catalog.cls` `CHANNELS` to include `slack` at its gate. Today the catalog refuses to render for a `slack` channel.
  - README: a plain-English developer section. It claims nothing the release doesn't ship.
- **Approved texts (R12), shipped by 27.3** with keys in `OcuTalon.Msg.Catalog.Core` and added to `EXPERIENCE.md` (Message Catalog, Later Steps). Copy them verbatim from 27.1's spec under "Planner gate items" (a):
  - Settings keys: `settings.slackHeading`, `slackNotSetUp`, `slackHowTo`, `slackOn`, `slackAddress` (`{address}`), `slackOffOnDemo`, `slackMembersHeading`, `slackMembersHelp`, `slackMemberId`, `slackMemberUser`, `slackLink`, `slackUnlink`, `slackNoMembers`, `slackBadMemberId`, `slackMemberTaken`, `slackUserTaken` (`{user}`), `slackLinked`, `slackUnlinked`.
  - Chat marker: `chat.viaSlack`.
  - Four setup steps, reordered by the Planner so the secrets (step 2) come before the request-URL check (step 3); step 4 is linking in Settings › Channels › Slack.
  - No story ships a text the author hasn't accepted.
- **Ledger items:**
  - DW-1442, routed by the Planner to 27.3 and now one of its acceptance criteria: 27.3's spine gate carries the wording fix. The Rule wording of AD-13 (the hook bullet names only `WebhookIn`), AD-14 (every inbound message becomes an Item), AD-17 (the rejection audit target is a webhook Ref) and AD-22 (eval-session Turn rows) contradicts 27.1's behaviour. Rewording an AD Rule is a Planner veto item.
  - DW-1441 ratified: the Slack route answers a form body 400 before the signature check. Keep it; revisit only if interactivity or slash commands are ever added.
  - DW-1440 moot: the R7 A/B is already running.
- **Residual from 27.1:** Slack's `&amp;`/`&lt;`/`&gt;` escapes and `<@U…>` mention markup reach the turn text unchanged. Story 27.2 or 27.3 may decide whether to decode them.

## Technical Decisions

- **Same-change spine rule.** `ARCHITECTURE-SPINE.md` is about 1,900 lines, so read it by line range. Tag each AD Rule amendment, run `memlog.py append` and `lint_spine.py`. Lint's 13 low `placeholder` findings were already there before 27.1; add none. 27.1 has already written:
  - the production-item row `SlackIn`, plus `SlackOut` for 27.2;
  - `SlackLink` in the Tables paragraph and the ER diagram (`Session ||--o| SlackLink`);
  - the REST row `POST /ocutalon/hook/slack/events`;
  - AD-19's Slack variables and `OCUTALON_SLACK_API_BASE`, read only by `SlackOut`;
  - the amendments to AD-1 (`DraftTransform`), AD-13 (the second route and its check order), AD-24 (`OcuTalonWebhook` serves `SlackIn` with no new grant) and AD-26 (`Ignored` gets a trace session of its own), plus AD-29 and Deferred (step 7 runs now).
- **`OcuTalon.Data.SlackLink`** (Lane B, `^OcuTalonP.SlackLink`):
  - Fields: `Ref`, `TeamId`, `MemberId` (each `EXACT`, at most 32 letters and digits), `SessionRef` and `CreatedAt`.
  - Indexes are unique on `(TeamId, MemberId)` and on `SessionRef`: one member per session and one session per member.
  - `ForeignKey SessionFK` cascades on `Data.Session(RefIndex)`. The purge's `%DeleteId`, `DropEval` and SQL deletes all remove the link, with no `Purge.cls` code. A link to a missing session cannot be saved.
  - `SessionFor(teamId, memberId)` returns "" unless both ids match and the session row exists.
  - `Link(teamId, memberId, sessionRef, .sc)` returns the link's Ref. `Unlink(sessionRef)` succeeds whether or not a link exists. Neither has a product caller yet: 27.3's `SettingsOps` command is the first.
  - `Link` returns one combined error for "member or session already linked". Its status text never holds an id.
- **Open points for 27.3's plan:**
  - `Link` targets a session, but the UI says "OcuTalon user". `Data.Session` has `IrisUser`, which is not unique. The plan must say which session a user's link goes to.
  - The UI asks only for a member ID, but `Link` needs a `team_id`. The plan must say where that comes from without an outward call.
  - Telling `slackMemberTaken` from `slackUserTaken` needs a check before `Link`, or a change to `Link`.
- **Commands (AD-1):**
  - 27.3's link and unlink follow the `CreateWebhook` precedent: verbs from origin `web_admin` only, routed to `SettingsOps` (`Core/SettingsOps.cls`), each with a Settings audit entry, and no tool verb. A Slack sender is never an origin for any governance command.
- **Admin reads and personal data (AD-24):**
  - The web process never reads product storage (CI rule `web-global-reads`). Listing links or users goes through a read verb to `SettingsOps`. A list that names IRIS users comes back through `SecretHandoff`, never in a traced message.
  - Routes sit under `/api/v1/settings/channels/`, forwarded from `Web/Api.cls`. `Web/HookSettings.cls` and the webhooks routes are the precedent.
- **Inbound path (shipped):** `SlackIn` (adapterless, PoolSize 0) either turns an event into a `slack`/`user` Item for `Conversation` or sends `Intake` an `Ignored` record (kind, reason and event id only), which `Intake` drops silently.
- **Outbound (27.2):**
  - `Conversation` sends the reply (`Msg.Outbound` with `OriginChannel`) to `Core.Rule.Notify`, which routes it to the turn's channel plus the web chat.
  - `SlackOut` builds calls with `%Net.HttpRequest`, uses `OCUTALON_SLACK_API_BASE` as its endpoint override, and records each send through `Data.Delivery.Record`.
  - Copy Telegram's classes (Lane A); never edit or extract from them (U-177).
  - The CI mock is modelled on Telegram's in `ci/compose.ci.yml` (Node standard library, token logged by length only).
- **Ownership (AD-29, AD-33):** Slack's items, tables and texts are Lane B's. New items or tables go into the ownership tables in the same change. Contended files take only approved appends.

## UX & Interaction Patterns

- **Settings > Channels** already groups Email and Webhooks (`web/src/app/settings/channels-section.ts`, `webhooks-section.ts`). Slack's group is admin-only and lazily loaded:
  - with Slack off, the not-set-up line and "How to set it up";
  - on the demo, the off-on-demo line;
  - with Slack on, the state line and the address to subscribe to;
  - the linked-members list with link and unlink.
- **Web chat:** turns from another channel carry a marker. "via Telegram" lives in `CHAT_TEXTS` in `web/src/app/chat/chat-view.ts`, checked by `web/scripts/ux-strings.test.mjs`. "via Slack" joins it (`web/src/app/chat/**` is contended).
- **Plain text only:** no Markdown.

## Cross-Story Dependencies

- **27.1 → 27.3 → 27.2:**
  - 27.3 calls `SlackLink.Link`/`Unlink` and reads `SlackIn.On()`.
  - 27.2's README linking section describes what 27.3 ships.
  - 27.2's `SlackOut` replies to `SlackIn`'s turns. R1's `bot_id` guard already ignores its echoes.
- **R7 A/B gate:** 27.1 is committed on `OCT-epic27`. Its merge into the feature branch is held for the verdict of the Planner's A/B (`eval/run.sh --release-candidate --notes telegram|slack`, N = 5), running from `d57a6d753`. Later stories build on the epic branch meanwhile.
- **Epic 28:** Story 28.1 (Lane A) writes the handler for 27.1's `DraftTransform` verb, which `IncidentManager` answers `failed` until then.
- **Shared Notify:** 27.2 edits `Core.Rule.Notify`, contended with Story 24.3's `page` routing. Do the two one after the other.
- **Demo host:** its proxy blocks the webhook path. The Contest Planner's demo-host checks cover that.
