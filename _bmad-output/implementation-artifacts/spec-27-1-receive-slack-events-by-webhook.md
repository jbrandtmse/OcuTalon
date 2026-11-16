---
title: 'Story 27.1: Receive Slack events by webhook'
type: 'feature'
created: '2026-11-16'
status: 'draft'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-27-context.md'
warnings: [oversized, multiple-goals]
deferred: []
---

<intent-contract>

## Intent

**Problem:** OcuTalon has no Slack channel. A Slack user cannot message it, and Slack's Events API has no OcuTalon address to post to. Socket mode is ruled out because the platform's WebSocket client fails right after opening.

**Approach (the narrowed scope this plan proposes; see "Proposed split" under Design Notes):** add a fixed Slack route, `POST /ocutalon/hook/slack/events`, to the existing hook application. It checks Slack's v0 signature over the raw body in constant time, rejects stale or unsigned requests with 401 (counted with the hook's capped audit), answers URL verification, and hands every valid event to a new adapterless service, `SlackIn`, before answering 200. `SlackIn` drops a retried event by its `event_id`. A linked member's direct message becomes a `user`-provenance turn on channel `slack` in the member's session. Every other event leaves one content-free `Ignored` record in Visual Trace and goes no further. Slack is off, and the route answers 404, unless both env vars are set and the install is not the online demo. The story also creates the `DraftTransform` command verb and its `CommandsIn` route to `IncidentManager`, from origin `tool` only and only for the session's own incidents. Story 28.1 writes the handler.

## Boundaries & Constraints

**Always:**
- `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` are read only with `$SYSTEM.Util.GetEnviron`, at use. Neither value is ever stored, put in a setting, message, log line, audit entry, trace, agent step or test output (NFR-11, AD-19).
- Slack is on only when both variables are non-empty and the online-demo flag is off. When Slack is off, the route answers exactly like an unknown path (404, no body), and `SlackIn` refuses input.
- Signature: `v0=` + lower-case hex of HMAC-SHA256(`v0:<X-Slack-Request-Timestamp>:<raw body bytes>`, secret), compared over its full length with no early exit. A timestamp more than 300 s from now, in either direction, is stale. The body is the bytes exactly as received, never decoded or re-encoded before hashing.
- Check order: off → 404; declared or actual size over `Data.Webhook` `BODYMAX` → 413; signature missing, wrong or stale → 401; body not a JSON object → 400; `url_verification` → 200 with the challenge as `text/plain`; otherwise the event goes to `SlackIn` → 200 with no body, or 503 when the production can't take it. The answer never waits for a decision.
- 401, 413 and 400 are rejections. They are counted in the existing `Data.Webhook.Reject` slot `slack` and audited through `RecordRejection` at most once per 60 s.
- Inbound Slack content is UNTRUSTED. Only a direct message (`event.type` `message`, `channel_type` `im`, no `subtype`, no `bot_id`, a sender, text that is not blank) from a member with a `Data.SlackLink` row whose session row exists becomes a turn: an `OcuTalon.Msg.Item` with Channel `slack`, Provenance `user`, `FromGuide` 0 and only the text, sent asynchronously to `Conversation`, after `Core.Trace.Join` (AD-14, AD-26).
- An event id is processed once: the first claim within 2 hours wins, and a repeat (Slack's retry, `X-Slack-Retry-Num`) does nothing and still answers 200.
- The trace, the audit, the console log and the `Ignored` record carry no message text, Slack member id, team id, channel id, name or email. They carry only fixed kinds, reasons and the event id.

**Contest Planner gate rulings, 2026-11-16 ~16:30Z (BINDING; full text `.worktrees/.coordination/prompts/story-271-rulings-20261116.md` outside the repo; every item is pinned by a test):**
- R1 Loop and noise guard: only a plain message becomes a user turn: `channel_type` `im`, NO `subtype`, NO `bot_id`, from a LINKED member. Bot messages (our own replies once 27.2 lands included), edits, deletes, joins and file-share subtypes each leave one content-free `Ignored` record. Pinned with a `bot_id` event and a `message_changed` event.
- R2 The link match includes the team: an event counts only when BOTH its `team_id` and its member id match a `Data.SlackLink` row; the same member id from another workspace is Ignored. Pinned.
- R3 The signature is checked BEFORE `url_verification`: an unsigned challenge gets 401. Pinned.
- R4 Answer fast: turn processing is asynchronous, so the 200 returns within Slack's 3-second window; Slack's retries (`X-Slack-Retry-Num`) are deduped by `event_id`. Pinned.
- R5 A 401 or stale request stores nothing from the body: only the count and the once-a-minute audit. Pinned.
- R6 Nothing typed in Slack can approve, reject or answer an approval request: a Slack turn has the same rights as a typed web-chat turn and no approval surface. Pinned: a typed "approve" over Slack approves nothing.
- R7 Model-facing check: confirm FROM CODE that no agent instruction text keys on the channel name, and record the evidence (file:line search) under Design Notes. If any instruction mentions channels (for example a telegram branch), HALT with `intent gap` naming it, BEFORE implementation: a new channel value would then be model-facing and needs the Planner's key-holder A/B.
- R8 Link retention: the AD-27 purge, or the removal of the session, deletes a removed user's link rows. Pinned. Member ids and team ids are personal identifiers: no trace, log or audit line carries them.
- R9 CI dummy SLACK_* values are NOT global: they are set ONLY for the `live:slack-hook` unit's throwaway, through a per-unit compose override or env. Every other throwaway keeps Slack OFF, as a default install does, and one assertion pins that a default throwaway answers 404 on `/ocutalon/hook/slack/events`.
- R10 Privileges: no new grant. If Task 0 shows the `OcuTalonWebhook` grants are not enough, STOP (HALT `intent gap`) for the Planner.
- R11 Approved: the route, `Data.SlackLink`, `^OcuTalonP.SlackE`, the `SlackIn` item, `Intake` dropping `Ignored`, env-only secrets, no new dependencies; the AD amendments AD-13 (second route, its check order, the 200), AD-24 (`OcuTalonWebhook` serves `SlackIn`, no new grant), AD-26 (`Ignored` in its own trace session), AD-1 (`DraftTransform` from origin tool, answers `failed` until 28.1). Contended appends approved: Production.cls lane B region (sequence within lane B), `Test/Data/Tables.cls` append only, `live:slack-hook` in `shards-3` (~28.7 min).
- R12 Public text: the catalog keys and `.env.example` lines are approved verbatim (27.1 ships only `.env.example`); the setup steps are REORDERED (secrets before the URL check) and step 1 is reworded; 27.2 adds `chat:write` to step 1 in the same commit as the reply code.

**Never:**
- No call to slack.com or any Slack API, no `SlackOut`, no reply in Slack, no WebSocket and no socket mode. The reply path is Story 27.2's.
- No Settings UI, no admin link/unlink command or REST route, and no shipped user-facing text. These move to the proposed sibling (Story 27.3). The texts are only proposed here.
- No edit to a Lane A class (Telegram's, `Watch/IncidentManager.cls`), and no new role, grant or `Data.Setting` key.
- No allowance call: Slack is off wherever the allowance flag is on (the online demo).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Linked DM | Signed `event_callback`, `message`/`im` from a linked member | 200, no body; one Item (slack, user, text) to `Conversation` in the member's session thread; a Turn row appears in that session, once | Hand-over error → 503, console line with no request data |
| Retry | Same `event_id` again, `X-Slack-Retry-Num: 1` | 200; nothing sent, nothing recorded | — |
| Unlinked member | Signed DM from a member with no link (or a link whose session row is gone) | 200; one `Ignored` (kind `message.im`, reason `unlinked`) in Visual Trace; no Item, no Turn | — |
| Channel message / bot / subtype / other type | Signed `message` in a channel, a bot's own message, `message_changed`, `app_mention`, `app_rate_limited` | 200; one `Ignored` with the matching reason; nothing else | — |
| URL verification | Signed `{"type":"url_verification","challenge":"c"}` | 200, `text/plain`, body `c`; nothing handed over | — |
| Unsigned / wrong / stale | Signature header missing or wrong, or timestamp off by more than 300 s | 401, no body; counted in slot `slack`; one audit entry per 60 s at most | Audit write failure is logged without request data |
| Too big / not JSON | Over 65,536 bytes; a form, text or JSON scalar | 413 / 400, no body; counted | — |
| Slack off | Either variable empty, or the online demo | 404 like any unknown path; nothing counted or handed over; `SlackIn` refuses input | — |

</intent-contract>

## Code Map

All classes are under `src/ocutalon/cls/OcuTalon/`.

- `Web/Hook.cls` -- the hook dispatch class (Lane B, Story 35.3). Its UrlMap has the one route `/:ref` at :48; the new route goes BEFORE it. Reuse its private seams: `Rejected` (capped count plus audit), `BodySize`, `IsForm`, `OnlineDemo`, `Log`, `ReportHttpStatusCode`, `Hand` (`CreateBusinessService` plus `ProcessInput`; a disabled or missing item is an error, Director.cls:1470), and the `SUPERSESSIONHEADER` delete. `BodyText` (:177) decodes UTF-8; Slack needs the undecoded bytes.
- `Data/Webhook.cls` -- `Reject(slot, now, .count)` :196 and `RecordRejection(slot, count)` :248 (Action `webhook_rejected`). A Ref is always 22 characters (`IsRef`), so the slot `slack` can never collide with a Ref, and neither can the two-segment path `/slack/events`. `BODYMAX` is 65536. `Matches` (:83) is the constant-time loop to copy the shape of, with no early exit.
- `Channel/Webhook/In.cls`, `Channel/Webhook/Event.cls` -- the adapterless-service and plain-event pattern for `SlackIn` and `Slack.Event`.
- `Channel/Telegram/In.cls` (Lane A, read-only) -- `Turn` :798-859 is the turn recipe: open the Session row, `Trace.Join`, set `%SessionId`/`%SuperSession`, build the Item, `SendRequestAsync` to `Conversation`, `Trace.Started` when Join returned "", and the cleanup in every path including after an exception. The send goes through a private `SendTurn` seam (:877).
- `Core/Trace.cls` -- `Join(sessionRef, .sc, now)` :39 and `Started(sessionRef, sessionId, now)` :84. "Only channel services call Join."
- `Core/Intake.cls` -- `OnRequest` :72 refuses a non-Item with a warning (`Refusal`). The `Ignored` record needs a silent early return.
- `Core/Conversation.cls` -- accepts only `user` provenance (:270) and copies `Item.Channel` to the Turn and to `chat.message` (:230). `Tell` (:816) sets `OriginChannel`, and Notify sends a `slack` origin to the web chat only until Story 27.2.
- `Data/Session.cls` -- one durable row per IRIS user on a local install. `RefIndexOpen`, `RefIndexExists`.
- `Data/Pairing.cls` -- the sibling identity table (Telegram) for the shape of `Data.SlackLink`: object access, an EXACT collation for the external id, and `SessionRef` as the only owner field.
- `Production.cls` -- the Lane B region ends at :106 (`<!-- lane B: end -->`), and `WebhookIn` is at :105. CONTENDED (Lane B's current batch): one line, gate item (e).
- `Test/Core/ProductionItems.cls` -- the Lane B oracle XData (WebhookIn row :42). `Test/Install/Production.cls` `TestDefinition` :136 asserts items, order and count against it.
- `src/short-names.tsv` -- registry of tables (Webhook row :37). `Test/Data/Tables.cls` (CONTENDED, Lane D) asserts every `OcuTalon.Data` table has exactly its contract (Webhook contract :512, registry copy :847). `docker/tests/test-storage.sh` checks the registry.
- `Test/Web/HookProbe.cls`, `Test/Web/Hook.cls`, `Test/Web/StubRequest.cls` -- the probe-subclass test pattern (`^OcuTalonTest("HookProbe", ...)` drives the seams; `Post`/`Dispatch` helpers :312-330). `TestOtherPaths` :184 must stay green.
- `Test/Channel/TelegramNoToken.cls` -- the "no token anywhere" scan to extend for the Slack dummy values.
- `ci/compose.ci.yml` -- CI-only env for throwaways (it already sets the dummy `TELEGRAM_BOT_TOKEN` and `OCUTALON_TELEGRAM_API_BASE`).
- `ci/units.sh` -- group `shards-3` :158 (`live:floor live:demo-switch live:install-script-live`, about 25.2 min planned: the most headroom). The Channel area runs as `shard:lane-a@Channel` in group `production` (in `NO_WEB_BUNDLE_UNITS`). `docker/tests/test-ci-config.sh` enforces the lists.
- `docker/tests/test-online-demo.sh` :474-510 -- the curl pattern against the hook app on a throwaway. `docker/tests/lib-live.sh` -- the stack helpers.
- `.env.example` -- 5 lines, `#` comments; lists `ANTHROPIC_API_KEY` and `TELEGRAM_BOT_TOKEN`.
- irislib `%CSP/Page.cls:73-79` -- `CONVERTINPUTSTREAM = 0`, so a JSON body arrives as a binary stream that has not been converted (the doc says so; measuring it is Task 0). A form body has no `Content` (measured in Story 35.3). `%SYSTEM.Encryption.HMACSHA(256, text, key)` is at irissys `%SYSTEM/Encryption.cls:965`.

## Tasks & Acceptance

**Execution:**
- Task 0 (measure first, on a lane-B throwaway, recorded in `## Verification` before any code relies on it):
  - (a) In the hook process, `%request.Content` for `application/json` and `application/json; charset=utf-8` bodies: its class, `IsCharacter()`, and whether the bytes are byte-exact. Check that a non-ASCII body's HMAC equals one computed with `openssl dgst -sha256 -hmac`.
  - (b) That `$SYSTEM.Util.GetEnviron` in the hook (CSP) process sees the container's `SLACK_*` variables.
  - (c) That `SlackIn` under the `OcuTalonWebhook` role's existing grants can read `Data.SlackLink` and `Data.Session`, write the event-claim global, and send. If a grant is missing, STOP: that is a privilege veto item.
- `Channel/Slack/Signature.cls` (new) -- pure class methods: `Check(secret, timestamp, signature, rawBody, nowEpoch) As %String` returns "" or a reason (`missing`, `stale`, `mismatch`), with `STALESECONDS` 300 and a constant-time compare. No state, no I/O. It is the testable core of the 401 path.
- `Channel/Slack/Event.cls`, `Channel/Slack/Ignored.cls` (new) -- `Event` is a plain `%RegisteredObject` (like `Webhook.Event`): EventId, EnvelopeType, EventType, ChannelType, Subtype, BotId, TeamId, MemberId, Text. It is never stored. `Ignored` is an `Ens.Request` with only `Kind`, `Reason` and `EventId`, from fixed sets.
- `Channel/Slack/In.cls` (new, `SlackIn`) -- the adapterless service.
  - `On()` and the variable-name parameters are the single source of "Slack on".
  - `OnProcessInput`: refuses when off or when the input is not an Event. Then it claims the event id (`Data.SlackLink.ClaimEvent`; a repeat returns OK and sends nothing). It classifies the event: a linked DM becomes a turn by Telegram's recipe; anything else sends one `Ignored` asynchronously to `Intake` with `%SessionId`/`%SuperSession` empty.
  - Private `Send` seam for tests. It logs nothing that holds content.
- `Data/SlackLink.cls` (new, Lane B) -- `Ref`, `TeamId` (EXACT, 32), `MemberId` (EXACT, 32), `SessionRef` (EXACT, 22), `CreatedAt`. Unique index on (TeamId, MemberId), unique on SessionRef. Object access only.
  - `SessionFor(teamId, memberId) As %String`: "" unless the link exists and its session row does.
  - `Link`/`Unlink`: the data writers that Story 27.3's SettingsOps command will call. No product caller in this story.
  - `ClaimEvent(eventId, now) As %Boolean`: an atomic `$Increment` claim in `EVENTGLOBAL` `^OcuTalonP.SlackE`, bucketed by UTC hour, killing buckets older than 2 hours on each claim.
  - `src/short-names.tsv`: one-row append (`SlackLink ^OcuTalonP.SlackLink OcuTalon.Data.SlackLink B`).
  - `Test/Data/Tables.cls` (CONTENDED): append its contract and registry entries, only as the gate rules.
- `Web/Hook.cls` -- add `<Route Url="/slack/events" Method="POST" Call="Slack"/>` before `/:ref`, and `ClassMethod Slack()` in the Always order. Add private seams `SlackOn()`, `SlackSecret()`, `SlackHeader(name)`, `RawBody()` (bytes, not decoded) and `SlackHand(event)` (`CreateBusinessService("SlackIn")`). Parse the JSON from the UTF-8-decoded bytes only after the signature passes. Update the class doc ("two routes").
- `Core/Intake.cls` -- `OnRequest` returns `$$$OK` at once for an `OcuTalon.Channel.Slack.Ignored`: no warning, no Join, no decision. Update the class doc.
- `Production.cls` (CONTENDED, gate) -- `<Item Name="SlackIn" ClassName="OcuTalon.Channel.Slack.In" PoolSize="0" Enabled="true"/>` after WebhookIn. Add the matching Lane B row in `Test/Core/ProductionItems.cls`.
- `.env.example` -- the proposed lines (gate a). `ci/compose.ci.yml` -- dummy `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` values marked CI-only.
- Tests: `Test/Channel/SlackSignature.cls`, `Test/Channel/SlackHook.cls` (+ `Test/Channel/SlackHookProbe.cls` extending `Test.Web.HookProbe` with the Slack seams), `Test/Channel/SlackIn.cls` (+ a probe overriding `Send`), and an extension of `Test/Web/Hook.cls` `TestOtherPaths` (POST `/slack/events` with Slack off is 404). Also `docker/tests/test-slack-hook.sh` (new live unit `live:slack-hook` in group `shards-3`, via `ci/units.sh`). It runs curl with openssl-signed requests on a throwaway: valid linked DM (exactly one Turn with channel `slack`, answered in under 3 s), retry, unsigned, stale, unlinked, url_verification. Afterwards it greps the console log, audit and message bodies for the dummy secret/token values and the fixture text.
- `Msg/Command/DraftTransform.cls` (new), `Core/CommandsIn.cls`, `Test/Bridge/CodeRules.cls`, `Test/Msg/Contracts.cls`, `Test/Core/CommandsRouting.cls`: the DraftTransform verb exactly as listed under Design Notes › Proposed split. This applies unless the lead moves it to a sibling 27.4.
- `ARCHITECTURE-SPINE.md` -- the spine edits in gate item (f), applied in the same change once the gate approves (Rule 20, by whoever the lead names).

**Acceptance Criteria:**
- Given the change, when it lands, then the spine carries every edit of gate item (f). AD amendments land only as the gate rules (AD-14, AD-19, AD-29, AD-33).
- Given the env vars, when the repo is read, then `.env.example` lists `SLACK_BOT_TOKEN` and `SLACK_SIGNING_SECRET` by name with empty values, and after the live run no console line, audit entry, message body or test output holds either dummy value or the fixture's message text (NFR-11).
- Given a request to `/ocutalon/hook/slack/events`, when it arrives, then each row of the I/O matrix holds, through the real hook application on a throwaway and through the probe (FR-46, AD-13, AD-17).
- Given a linked member's DM, when `SlackIn` handles it, then exactly one Turn with channel `slack` and provenance `user` exists in the member's session, joined to the session's daily thread (FR-46, AD-14, AD-26). Integration AC: `Conversation` (the consumer) reads the Item and records the Turn row that the web chat shows.
- Given any other event, when it arrives, then exactly one `Ignored` record reaches `Intake`, and no Item, Turn, decision or reply exists (NFR-14).
- Given `OcuTalon.Msg.Command.DraftTransform` with an `IncidentRef`, when it is submitted through `Core.Commands.Submit`: from a non-tool origin it is refused `not_allowed`; from origin `tool` for an incident the session can't see it is refused `not_found`; for the session's own incident it is sent to `IncidentManager` (pinned through the `Send` override). Integration AC: Story 28.1's handler consumes it (AD-1, AD-29).
- Given Slack off (either variable empty, or the online demo), when any request reaches the route, then it is 404 with nothing counted or handed over, `SlackIn` refuses input, and every other hook and test stays green (AD-25).

## Spec Change Log

- 2026-11-16 ~16:35Z, lead: Contest Planner gate rulings R1-R12 applied (Boundaries & Constraints, binding block; setup steps reordered under Planner gate items). Changes the plan must carry: R2 team_id in the link match; R3 signature before url_verification; R5 nothing stored from a rejected body; R6 approve-proof pin; R7 model-facing evidence (HALT if any agent instruction keys on the channel); R8 link rows deleted with the session/purge, pinned, in THIS story (prefer a mechanism inside the new `Data.SlackLink` class, e.g. an SQL foreign key with cascade or the session's own removal path; `Data/Purge.cls` is lane D's contended file: only a self-contained appended block, reported, if unavoidable); R9 dummy Slack env only for `live:slack-hook`'s throwaway + a default-throwaway 404 assertion (no global `ci/compose.ci.yml` env); R10 Task 0 hard gate on grants. Status stays `draft` for the re-plan (cycle_iteration 2).

- 2026-11-16, lead (epic-27 runner), unattended ruling on the plan's split proposal (doctrine U5: a split into a sibling planned next in this epic, 1 of 6, category decide): ACCEPTED as proposed. Story 27.1 is the narrowed scope in this spec and keeps `DraftTransform` (no 27.4: moving it would change Epic 28's dependency text, owner-only). New Story 27.3 "Link Slack members in Settings" takes, verbatim, "how an admin links a Slack member to an OcuTalon user" and the texts criterion; order 27.1, 27.3, 27.2. `epics.md` amended (27.1's first and fourth criteria, Story 27.3 inserted before Epic 28); tracker key `27-3-link-slack-members-in-settings` added. Status reset to `draft`: the re-plan runs after the Contest Planner rules this spec's gate items (public text, veto items, contended appends, spine edits and the AD-1/AD-13/AD-24/AD-26 amendments); the rulings will be recorded here and under Design Notes.

## Review Triage Log

## Design Notes

**Governing ADs:**
- AD-1 (commands and REST writes: the route writes only the existing counters).
- AD-3 (private globals).
- AD-4 (identity lives only in its own row; messages carry `SessionRef`).
- AD-13 (the hook application: AMENDED, gate f).
- AD-14 (channel pair, provenance).
- AD-17 (the only audit writer, capped rejections).
- AD-19 (env-only secrets, endpoint overrides).
- AD-24 (the `OcuTalonWebhook` role and its measured grants).
- AD-25 (online demo).
- AD-26 (trace join).
- AD-27 (retention).
- AD-29 and AD-33 (Lane B ownership; items and tables go into the spine tables in the same change).

**Already met on this branch (evidence):**
- `Msg.Enum` CHANNEL already holds `slack` (`Msg/Enum.cls:36`).
- The hook app is absent on the online demo (`Install/Step/Web.cls:306-317`, `RemoveHook`), so Slack is unreachable there regardless.
- `Data.Delivery`, `Web.History` and the usage view already accept `slack`.

**Decided in-stage:**
1. Route address `POST /ocutalon/hook/slack/events`. It has two segments, so it never matches `/:ref`, and `slack` fails `Data.Webhook.IsRef` (always 22 characters), so no webhook can take it. Webhook names are never in paths.
2. "On" needs both variables, which is stricter than the AC's "no token": without the signing secret no request can be verified.
3. No install step and no `Data.Setting` key. `SlackIn` is enabled with PoolSize 0, as WebhookIn is, so no job runs. The route's `On()` gate is the switch.
4. Reuse `Data.Webhook.Reject`/`RecordRejection` with slot `slack` (extend, Rule 2). The audit action stays `webhook_rejected`.
5. Dedupe in `SlackIn`, not in the REST code (AD-1). It uses a 2-hour, self-pruning global.
6. The trace-only record is an `Ignored` message to `Intake`, which drops it silently. No other existing item can take a record without acting on it. The alternative, a new sink item, would add a production item.
7. 200, not 202, for events (Slack's contract).
8. The URL-verification challenge is echoed as `text/plain`.
9. No allowance call (demo-only flag).
10. A retried event leaves no second record.
11. Turn recipe copied from Lane A's `Telegram.In.Turn`: a Lane B story may not edit or extract from a Lane A class (U-177). `Hook.Slack` extends `Web.Hook`'s seams, and `Signature`'s compare copies the shape of `Data.Webhook.Matches` (that one compares salted SHA-256, this one HMAC hex).
12. "via Slack" marker: needed for parity with "via Telegram" (EXPERIENCE :35, :290). It moves to 27.3 because `web/src/app/chat/**` is contended.

**Integration ACs / Consumed-by / Consumes:**
- Consumes: `Conversation` (turns), `Intake` (`Ignored`), `Core.Trace`, `Data.Session`, `Data.Webhook` counters.
- Consumed-by:
  - Story 27.2: `SlackOut` replies to the turns `SlackIn` makes; it reads `OCUTALON_SLACK_API_BASE`.
  - Story 27.3 (proposed): its SettingsOps link/unlink commands call `Data.SlackLink.Link`/`Unlink`, and the Settings UI reads `SlackIn.On()`.
- `Data.SlackLink`'s writers have no consumer in this story; the first is Story 27.3.

**Lead ruling on the split (2026-11-16, unattended, decide):** accepted as proposed below; 27.1 keeps DraftTransform; 27.3 is planned after 27.1 and before 27.2. See the Spec Change Log.

**Proposed split (the blocking item; criteria moved verbatim):** Story 27.1 as written spans four separable deliverables:
- the inbound route and `SlackIn`;
- admin member linking: a stored table, a SettingsOps command (Lane A's 25.9 holds `Core/SettingsOps.cls`), an admin REST route (`Web/Api.cls` is Lane D's), retention in `Data/Purge.cls` (Lane D's), and audit;
- the Settings UI for channel state and linking, whose texts the author has not accepted, so it cannot ship yet;
- the `DraftTransform` verb.

Planned whole, it is about 18 tasks across five contended paths. Recommended split:
- **27.1 (this spec, narrowed):** keeps every criterion except the two moved below.
  - The first criterion's spine bullet stays, minus "how an admin links …", which 27.3 records.
  - It keeps the DraftTransform bullet: moving it would change the story-level dependency text of Epic 28 (`epics.md:826` and Story 28.1, "the `DraftTransform` command verb that Story 27.1 creates"), which is owner-only.
  - The DraftTransform work it keeps:
    - `Msg/Command/DraftTransform.cls`: the `Dismiss` shape with `<Subscript>"DraftTransform"`.
    - `Core/CommandsIn.cls`: a Routes row `{"verb":"DraftTransform","owner":"IncidentManager","origins":"tool"}`, a `TOOLVERBS` append, and the own-incident check widened to `(verb = "ProposeFix") || (verb = "DraftTransform")`.
    - `Test/Bridge/CodeRules.cls`: its `TOOLVERBS` copy.
    - `Test/Msg/Contracts.cls`: its verbs list.
    - `Test/Core/CommandsRouting.cls`: `TestDraftTransformToolOnly`.
    - Until Story 28.1, `IncidentManager` answers `failed` (5001), as the spine allows (AD-29 :1231). No Lane A edit.
  - If the lead prefers DraftTransform as its own sibling 27.4, that is the alternative, and the lead routes the Epic 28 wording question.
- **27.3 "Link Slack members in Settings" (new, planned next, before 27.2, so that 27.2's README "linking a member" holds).** Moved verbatim:
  - from the first criterion: "and how an admin links a Slack member to an OcuTalon user (AD-14, AD-19, AD-29, AD-33)";
  - the shipping half of the texts criterion: "the step 7 texts the UX doesn't give (the Slack channel's state and member-linking in Settings, and its setup steps) are proposed to the author as additions to `EXPERIENCE.md` (Message Catalog, and Later Steps), with their catalog keys in `OcuTalon.Msg.Catalog.Core`, and no story of this epic ships a text the author hasn't accepted (UX-DR117)". 27.1 keeps the proposal, written below.
  - Scope: an admin-only link/unlink command through SettingsOps (audit `Pairing`, user names via `SecretHandoff` per AD-24), an admin REST class forwarded from `Web/Api.cls`, `Data/Purge.cls` `Keeps` for a linked session plus a purge of orphan links, Settings › Channels Slack state and linking UI (lazy), catalog keys, the "via Slack" marker, and the GUIDE setup section.
- 27.2 is unchanged. If the lead rules for no split, re-dispatch this spec as `draft`; the investigation above still applies.

### Planner gate items

- (a) PUBLIC TEXT, proposed verbatim for EXPERIENCE.md. They ship in 27.3, keys in `Msg.Catalog.Core`:
  - `settings.slackHeading` "Slack"
  - `settings.slackNotSetUp` "Slack not set up. Add SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET to .env and restart OcuTalon."
  - `settings.slackHowTo` "How to set it up"
  - `settings.slackOn` "Slack on"
  - `settings.slackAddress` "Subscribe your Slack app's events to {address}."
  - `settings.slackOffOnDemo` "Slack is off on the online demo, so it has no public Slack address. It works on your own install."
  - `settings.slackMembersHeading` "Linked Slack members"
  - `settings.slackMembersHelp` "Only direct messages to the bot from a linked member become chat turns. Everything else from Slack is recorded in Visual Trace and goes no further."
  - `settings.slackMemberId` "Slack member ID"
  - `settings.slackMemberUser` "OcuTalon user"
  - `settings.slackLink` "Link member"
  - `settings.slackUnlink` "Unlink"
  - `settings.slackNoMembers` "No Slack members are linked yet."
  - `settings.slackBadMemberId` "Enter a Slack member ID such as U012AB3CDE: a U or W followed by letters and digits. Nothing was changed."
  - `settings.slackMemberTaken` "That Slack member is already linked to another user. Nothing was changed."
  - `settings.slackUserTaken` "{user} already has a linked Slack member. Unlink it first. Nothing was changed."
  - `settings.slackLinked` "Linked. Their direct messages to the bot now reach OcuTalon. Recorded in the audit log."
  - `settings.slackUnlinked` "Unlinked. Their messages no longer reach OcuTalon. Recorded in the audit log."
  - `chat.viaSlack` "via Slack"
  - Setup steps (Later Steps and the GUIDE's Slack section), as APPROVED and REORDERED by the Planner (R12):
    1. "Create a Slack app for your workspace at api.slack.com/apps. In App Home, turn on the Messages Tab and allow users to send messages from it. Give its bot the im:history scope, and install it to the workspace."
    2. "Copy the bot token and the signing secret into .env as SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET, then restart OcuTalon."
    3. "Under Event Subscriptions, set the request URL to https://<your public address>/ocutalon/hook/slack/events and subscribe the bot to the message.im event. OcuTalon answers Slack's check at once."
    4. "As an admin, open Settings › Channels › Slack and link each person's Slack member ID to their OcuTalon user. Only linked members' direct messages to the bot reach OcuTalon."
  - `.env.example` lines (this story):
    - "# Slack (optional): set both to turn Slack on. Leave empty to keep it off."
    - "SLACK_BOT_TOKEN="
    - "SLACK_SIGNING_SECRET="
- (b) Outward actions: none. The only traffic is OcuTalon's answer to Slack's own HTTP request: status lines and the URL-verification challenge echo. Nothing is sent to slack.com or any other service. CI uses dummy values and curl to the throwaway only.
- (c) Veto items, each with its online-demo behaviour:
  - New route `POST /ocutalon/hook/slack/events`. Demo: the hook app does not exist and the dispatch answers 404.
  - New table `Data.SlackLink` (TeamId, MemberId, SessionRef, CreatedAt). Demo: the table exists, stays empty and is never read.
  - New global `^OcuTalonP.SlackE` (event-id claims, kept 2 h, self-pruning). Demo: never written.
  - Retention of links: until unlinked (27.3) or their session row is gone. In this story an orphan link reads as unlinked; 27.3 adds the purge and `Keeps`.
  - Secrets: `SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN`, env-only, read at use in the hook process, never stored. CI dummy values in `ci/compose.ci.yml`. Demo: unset, so Slack is off.
  - Privileges: no new role, resource or grant. `SlackIn` runs under the existing `OcuTalonWebhook` grants, and Task 0 (c) proves it or stops.
  - New production item `SlackIn` (adapterless, PoolSize 0). Demo: present, unreachable.
  - `Intake` accepts `Ignored` silently.
  - No new dependency.
- (d) Model-facing text changes: none. A Slack turn reaches the model as a `user` message exactly as a Telegram turn does. No prompt, tool description or model-read catalog text changes, and `DraftTransform` gets no tool in this story.
- (e) Contended paths:
  - `src/ocutalon/cls/OcuTalon/Production.cls`, Lane B's region: one line `<Item Name="SlackIn" ClassName="OcuTalon.Channel.Slack.In" PoolSize="0" Enabled="true"/>` inserted before `<!-- lane B: end -->`.
  - `src/ocutalon/cls/OcuTalon/Test/Data/Tables.cls` (Lane D): append the `OcuTalon.Data.SlackLink` contract entry and its registry entry in the XData.
  - One-name appends, reported: `src/short-names.tsv`, `ci/units.sh` (`live:slack-hook` in `shards-3`).
- (f) Spine edits:
  - Production-item table (:1540): `| `SlackIn` (step 7), `SlackOut` (step 7, Story 27.2) | `OcuTalon.Channel.Slack.In`, `.Out` | B |`.
  - Tables paragraph (:1571): Lane B owns `SlackLink`, with `^OcuTalonP.SlackE` claims written only by `SlackIn` and kept 2 h.
  - ER diagram: `Session ||--o| SlackLink : "has at most one"`.
  - REST surface (:1824): a `POST /ocutalon/hook/slack/events` row.
  - AD-19 (:701-702): Slack's variable names, and `OCUTALON_SLACK_API_BASE` joins the endpoint overrides (read by 27.2).
  - Setting keys: none. Slack is configured by environment only.
  - Member linking: the Slack identity lives only in the `SlackLink` row. An admin links it through SettingsOps (Story 27.3), and messages carry `SessionRef` only (AD-4, AD-14).
  - Deferred (:1904) and AD-29 (:1191): step 7 now runs (owner decision 2026-11-16).
  - AD amendments for the gate:
    - AD-13's Rule (:488-489): "One route, `POST /<ref>`" becomes two routes, adding `POST /slack/events` with its own order (404 off, 413, 401 by Slack signature, 400, 200 challenge, 200 or 503) and its answer of 200 rather than 202.
    - AD-24 (:1032): `OcuTalonWebhook` also serves `SlackIn`, with no new grant.
    - AD-26: an event with no session leaves an `Ignored` record in a trace session of its own.
    - AD-1 (:117): `DraftTransform` joins the tool-origin list (with the 27.1-keeps-it split).

## Verification

LANE below means `OCUTALON_LOCK_DIR="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.worktrees/.coordination/locks/lane-b" OCUTALON_TEST_WEB_PORT=52802 OCUTALON_LOCK_OWNER='epic=27 stage=implement'`. Every call runs in the foreground with `timeout: 600000` from the worktree root. Warm runs use tag `e27s1iw`, after `LANE OCUTALON_RUN_TAG=e27s1iw ci/warm.sh up`, and the stage ends with `ci/warm.sh down`.

**Commands:**
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Channel.SlackSignature` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Channel.SlackHook` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Channel.SlackIn` -- expected: CLASS passed
- (loop) `LANE OCUTALON_WARM=1 OCUTALON_RUN_TAG=e27s1iw ci/iris.sh class OcuTalon.Test.Web.Hook` -- expected: CLASS passed
- (loop) `LANE OCUTALON_RUN_TAG=e27s1l ci/iris.sh live slack-hook` -- expected: exit 0 (fresh stack, about 2 min)
- (once) `LANE OCUTALON_RUN_TAG=e27s1o ci/iris.sh class OcuTalon.Test.Core.ProductionItems`, then separately `OcuTalon.Test.Install.Production`, `OcuTalon.Test.Data.Tables` and `OcuTalon.Test.Core.Intake`, one per call -- expected: each passed
- (once) `bash docker/tests/test-ci-config.sh` and `bash ci/checks.sh`, one per call -- expected: pass
- CI: the `production` group runs the new Channel classes, and `shards-3` runs `live:slack-hook` (new_units: `live:slack-hook` → `shards-3`, about 25.2 + ~3.5 min planned, inference).

**Shared surfaces:**
- the production item list (`Test/Core/ProductionItems` oracle, the `Test/Install/Production` count);
- the table registry (`src/short-names.tsv`, `Test/Data/Tables`, `test-storage.sh`);
- the hook's path set (`Test/Web/Hook` `TestOtherPaths`);
- `Intake`'s refusal set (`Test/Core/Intake`);
- `ci/units.sh` groups (`test-ci-config.sh`);
- `ci/compose.ci.yml` env (every throwaway now has Slack on with dummy values).

Every test added or changed passes on a fresh environment, in either order.

**Mutations (one per AC, recorded by the implement stage):**
- `Signature.Check` always returns "" → `SlackHook` TestUnsigned red.
- `STALESECONDS` 999999999 → TestStale red.
- `ClaimEvent` always 1 → `SlackIn` TestRetryOnce red.
- Provenance `untrusted` → TestLinkedDm red.
- `On()` ignores the online-demo flag → TestOnlineDemo red.

## Auto Run Result

Status: blocked
Blocking condition: intent gap: Story 27.1 is oversized (about 18 tasks, five contended paths, and Settings texts the author has not accepted). Proposed split: 27.1 narrowed to the inbound route, SlackIn, the link table read side, dedupe, the off switch, secrets, spine and DraftTransform; new sibling 27.3 "Link Slack members in Settings" (admin link/unlink, REST, Purge, Settings UI, catalog texts, "via Slack"), planned before 27.2; the moved criteria are quoted under Design Notes › Proposed split. Lead to rule.
